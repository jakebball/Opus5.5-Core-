#!/usr/bin/env node
// perf.js: measures what a Roblox place asks the GPU to draw, stop by stop along a fixed route, in a real Studio
// playtest, and keeps every run on disk so changes can be judged against the last one and against a budget.
//
//   node perf.js check                                   the bridge, the place, the route, the triangle table
//   node perf.js tris [--full]                           refresh perf-source/meshtris.json in Edit
//   node perf.js survey [--label NAME] [--only a,b] [--frames] [--load S] [--port N]
//                                                        one survey playtest -> perf-source/runs/<stamp>-<label>.json
//   node perf.js report [RUN] [--vs RUN] [--top N]       a run (default: the latest) against the budget and a previous run
//   node perf.js cleanup                                 remove a leftover __PerfSurvey script from the place
//
// The project keeps its route in perf-source/route.json (stops, chase camera, budget). A survey refreshes the triangle
// table in Edit, installs PerfSurvey.luau (with the route and the table baked in) as StarterPlayerScripts.__PerfSurvey and
// a server director ServerScriptService.__PerfSurveyServer, starts a playtest, collects the survey's [perf:<id>:*]
// lines from Studio's session log (the MCP's get_playtest_output never sees client prints), and removes both scripts
// whatever happened. The test ends itself: the director calls StudioTestService:EndTest when the survey reports done or
// its watchdog runs out; perf.js then waits for StopPlaySoloEnd in the log, falls back to stop_playtest, and fails
// loudly if the test is still alive (studio/playtest.js, shared with /demo).
// With --frames it also saves a frame of the Studio window at each stop's worst heading to runs/frames/ (local only),
// for checking the estimate against Studio's render stats overlay.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const bridge = require(path.join(__dirname, "..", "studio", "bridge.js"));
const playtest = require(path.join(__dirname, "..", "studio", "playtest.js"));
const { findFfmpeg, windowHelper } = require(path.join(__dirname, "..", "demo", "demo.js"));
const { sleep } = playtest;

const SURVEY = "__PerfSurvey";
const SURVEY_SERVER = "__PerfSurveyServer";
const POLL_MS = 250;

function parse(argv) {
  const options = { _: [] };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      options._.push(arg);
      continue;
    }
    const key = arg.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) options[key] = true;
    else options[key] = argv[++index];
  }
  return options;
}

function paths(root) {
  const dir = path.join(root, "perf-source");
  return {
    dir,
    route: path.join(dir, "route.json"),
    tris: path.join(dir, "meshtris.json"),
    runs: path.join(dir, "runs"),
    frames: path.join(dir, "runs", "frames"),
  };
}

function readJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function loadRoute(root) {
  const file = paths(root).route;
  const route = readJson(file, null);
  if (!route) throw new Error(`no route: write ${file} (see the skill's SKILL.md, The route)`);
  if (!Array.isArray(route.stops) || !route.stops.length) throw new Error(`${file}: "stops" is empty`);
  for (const stop of route.stops) {
    if (!stop.name || !Array.isArray(stop.position) || stop.position.length !== 3) {
      throw new Error(`${file}: every stop needs a name and a position [x, y|null, z]`);
    }
  }
  route.budget = route.budget || { tris: null, draws: null };
  return route;
}

async function place(options, writes) {
  const config = bridge.readConfig(bridge.findProjectRoot());
  return bridge.resolve({ port: options.port, placeId: options["place-id"] || config.placeId, writes });
}

// ---------- the triangle table ----------

async function refreshTris(port, root, full) {
  const file = paths(root).tris;
  const table = readJson(file, { tris: {}, names: {}, failed: {} });
  const skip = {};
  if (!full) for (const key of Object.keys(table.tris)) skip[key] = true;
  const body = fs.readFileSync(path.join(__dirname, "MeshTris.luau"), "utf8").replace(/\r\n/g, "\n");
  const code = `local SKIP_JSON = ${bridge.longString(JSON.stringify(skip))}\n${body}`;
  const reply = JSON.parse(await bridge.deferred(port, code));
  const merged = {
    updated: new Date().toISOString(),
    tris: full ? reply.tris : { ...table.tris, ...reply.tris },
    names: { ...table.names, ...reply.names },
    failed: reply.failed,
  };
  for (const key of Object.keys(merged.tris)) delete merged.failed[key];
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(merged, null, 1));
  const failed = Object.keys(merged.failed);
  console.log(`tris     ${Object.keys(merged.tris).length} meshes known, ${reply.counted} counted from EditableMesh this run, ${failed.length} unreadable`);
  if (failed.length) console.log(`         unreadable (surveys count them as 0): ${failed.slice(0, 8).join(", ")}${failed.length > 8 ? " ..." : ""}`);
  return merged;
}

// ---------- the survey ----------

function surveySource(route, table, only, id) {
  const stops = only ? route.stops.filter((stop) => only.includes(stop.name)) : route.stops;
  if (!stops.length) throw new Error(`--only matched no stop; stops: ${route.stops.map((stop) => stop.name).join(", ")}`);
  const config = { ...route, stops, budget: undefined };
  const body = fs.readFileSync(path.join(__dirname, "PerfSurvey.luau"), "utf8").replace(/\r\n/g, "\n");
  return {
    stops,
    source: `if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
	return
end
local RUN_ID = "${id}"
${playtest.CLIENT_SIGNAL_LUA}
local CONFIG_JSON = ${bridge.longString(JSON.stringify(config))}
local TRIS_JSON = ${bridge.longString(JSON.stringify(table.tris))}
${body}`,
  };
}

const CLEANUP_LUA = `local removed = 0
for _, entry in { { game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"), "${SURVEY}" }, { game:GetService("ServerScriptService"), "${SURVEY_SERVER}" } } do
	local leftover = entry[1] and entry[1]:FindFirstChild(entry[2])
	if leftover then
		leftover:Destroy()
		removed += 1
	end
end
return removed`;

async function install(port, source, serverSource) {
  const parts = [
    ['game:GetService("StarterPlayer").StarterPlayerScripts', "LocalScript", SURVEY, source],
    ['game:GetService("ServerScriptService")', "Script", SURVEY_SERVER, serverSource],
  ];
  for (const [, , name, code] of parts) {
    const check = await bridge.once(port, `local fn, err = loadstring(${bridge.longString(code)}, "${name}")\nreturn if fn then "" else tostring(err)`);
    if (check) throw new Error(`${name} does not compile: ${check}`);
  }
  for (const [parent, className, name, code] of parts) {
    await bridge.once(port, `local parent = ${parent}
local existing = parent:FindFirstChild("${name}")
if existing then existing:Destroy() end
local script = Instance.new("${className}")
script.Name = "${name}"
script.Source = ${bridge.longString(code)}
script.Parent = parent
return "ok"`);
  }
}

function grabFrame(ffmpeg, title, file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const result = spawnSync(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", "-f", "gdigrab", "-i", `title=${title}`, "-frames:v", "1", file], { encoding: "utf8" });
  return result.status === 0 ? null : (result.stderr || "").slice(-200);
}

// Reassembles "[perf:<id>:<kind>] <seq> <i>/<n> <chunk>" lines into payloads. Lines come from the log tail, so each
// arrives once; lines of other runs (another id) are ignored.
function collector(id) {
  const pending = new Map();
  const mine = `[perf:${id}`;
  return function take(entries, handlers) {
    for (const entry of entries) {
      const text = String(entry.message || "");
      if (!text.startsWith(mine)) continue;
      const rest = text.slice(mine.length);
      const frame = /^:frame\] (.+)$/.exec(rest);
      if (frame) {
        handlers.frame(frame[1].trim());
        continue;
      }
      const chunk = /^:(\w+)\] (\d+) (\d+)\/(\d+) ([\s\S]*)$/.exec(rest);
      if (chunk) {
        const [, kind, seq, index, count, part] = chunk;
        const slot = pending.get(seq) || { kind, parts: [], got: 0, count: Number(count) };
        if (slot.parts[Number(index) - 1] === undefined) slot.got++;
        slot.parts[Number(index) - 1] = part;
        pending.set(seq, slot);
        if (slot.got === slot.count) {
          pending.delete(seq);
          handlers.payload(kind, JSON.parse(slot.parts.join("")));
        }
        continue;
      }
      const line = /^\] (.*)$/s.exec(rest);
      if (line) handlers.line(line[1]);
    }
  };
}

async function survey(options) {
  const root = bridge.findProjectRoot();
  const files = paths(root);
  const route = loadRoute(root);
  const target = await place(options, true);
  const label = typeof options.label === "string" ? options.label.replace(/[^\w.-]+/g, "-") : "survey";
  const only = typeof options.only === "string" ? options.only.split(",").map((name) => name.trim()) : null;

  const logFile = await playtest.findLog(target.port);
  const id = playtest.nonce();
  console.log(`place    port ${target.port}: ${target.placeId} "${target.name}"`);
  console.log(`log      ${path.basename(logFile)}, run ${id}`);
  const table = await refreshTris(target.port, root, false);
  const { stops, source } = surveySource(route, table, only, id);

  const headings = route.headings || 8;
  const perStop = (route.settleSeconds || 6) + headings * ((route.headingSeconds || 1.2) + 0.4) + 8 + (options.frames ? 4 : 0);
  const maxSeconds = Number(options.max) || Math.ceil(stops.length * perStop + 60);
  const loadSeconds = Number(options.load) || 150;
  const serverSource = playtest.serverDirectorSource({ tag: "perf", id, loadSeconds, maxSeconds });

  let ffmpeg = null;
  let title = null;
  if (options.frames) {
    ffmpeg = findFfmpeg();
    const window = windowHelper(target.name, { focus: true });
    if (!window.found) throw new Error("--frames: no Roblox Studio window found");
    title = window.title;
    console.log(`frames   from "${title}" (turn on Studio's render stats overlay; keep the window uncovered)`);
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const run = { label, at: new Date().toISOString(), place: target.placeId, budget: route.budget, route: { headings, camera: route.camera, maxDistance: route.maxDistance, shadowRange: route.shadowRange }, meta: null, stops: [], frames: {}, errors: [] };
  const take = collector(id);
  let tail = null;
  let launched = false;
  let started = null;
  let done = false;
  // hard watchdog: whatever hangs, stop waiting and go through the stop path (the in-game director ends the test too)
  let tripped = null;
  const hardMs = (loadSeconds + maxSeconds + 90) * 1000;
  const watchdog = setTimeout(() => {
    tripped = `hard timeout of ${hardMs / 1000} s`;
    setTimeout(() => {
      console.error("watchdog: the stop path hung; exiting. CHECK STUDIO: a playtest may still be running.");
      process.exit(3);
    }, 90000).unref();
  }, hardMs);

  try {
    tail = playtest.prepare(logFile);
    await install(target.port, source, serverSource);
    launched = true;
    await playtest.launch(target.port, tail);
    const begin = Date.now();
    console.log(`playtest started; ${stops.length} stops x ${headings} headings (cap ${maxSeconds} s once the survey starts)`);
    while (!done) {
      await sleep(POLL_MS);
      if (tripped) throw new Error(`watchdog: ${tripped}`);
      const entries = tail.poll();
      for (const entry of entries) {
        if (entry.kind === "lifecycle") console.log(`studio   ${entry.phase}`);
        else if (entry.message.startsWith(`[perf:${id}] server `)) console.log(`server   ${entry.message.slice(`[perf:${id}] server `.length).split("\n")[0]}`);
      }
      take(entries, {
        payload(kind, payload) {
          if (kind === "meta") run.meta = payload;
          if (kind === "stop") {
            run.stops.push(payload);
            const worst = payload.worstTris;
            console.log(`  ${payload.name.padEnd(20)} worst ${fmt(worst.total)} tris @${worst.yaw}°, ${payload.worstDraws.total} draws @${payload.worstDraws.yaw}°`);
          }
        },
        frame(stopName) {
          if (!ffmpeg) return;
          const file = path.join(files.frames, `${stamp}-${label}-${stopName}.png`);
          const failure = grabFrame(ffmpeg, title, file);
          if (failure) console.log(`  frame ${stopName} failed: ${failure}`);
          else run.frames[stopName] = path.relative(files.dir, file);
        },
        line(text) {
          if (text.startsWith("server ")) return;
          if (text === "start") {
            started = Date.now();
            console.log(`survey started after ${((started - begin) / 1000).toFixed(1)} s`);
          } else if (text === "done") {
            done = true;
          } else if (text.startsWith("error:")) {
            run.errors.push(text);
            console.log(`survey ${text.split("\n")[0]}`);
          }
        },
      });
      if (done) break;
      if (tail.phases.stopping !== undefined) {
        run.errors.push("the playtest ended before the survey finished");
        console.log("the playtest ended before the survey finished (the director's load/max watchdog, or a manual stop)");
        break;
      }
      if (!started && Date.now() - begin > (loadSeconds + 20) * 1000) throw new Error(`the survey did not start within ${loadSeconds} s (did the character spawn?)`);
      if (started && Date.now() - started > (maxSeconds + 20) * 1000) {
        run.errors.push(`stopped at the ${maxSeconds} s cap`);
        console.log(`stopping at the ${maxSeconds} s cap`);
        break;
      }
    }
  } finally {
    clearTimeout(watchdog);
    let stopError = null;
    if (launched) {
      try {
        const how = await playtest.ensureStopped(target.port, tail);
        console.log(`stopped  (${how === "game" ? "the game ended itself" : how})`);
      } catch (error) {
        stopError = error;
      }
    }
    const removed = await bridge.once(target.port, CLEANUP_LUA).catch(() => "?");
    console.log(`cleanup  removed ${removed} survey script(s)`);
    if (stopError) throw stopError;
  }

  if (!run.stops.length) throw new Error("the survey reported no stops; nothing saved");
  fs.mkdirSync(files.runs, { recursive: true });
  const file = path.join(files.runs, `${stamp}-${label}.json`);
  fs.writeFileSync(file, JSON.stringify(run, null, 1));
  console.log(`saved    ${path.relative(root, file)}\n`);
  const previous = listRuns(files.runs).filter((other) => other !== file).pop();
  printReport(run, previous ? readJson(previous) : null, table.names, { top: 8 });
}

// ---------- reports ----------

function listRuns(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((name) => name.endsWith(".json")).sort().map((name) => path.join(dir, name));
}

function resolveRun(dir, given) {
  if (!given) return listRuns(dir).pop();
  if (fs.existsSync(given)) return given;
  const match = listRuns(dir).filter((file) => path.basename(file).includes(given)).pop();
  if (!match) throw new Error(`no run matches "${given}" in ${dir}`);
  return match;
}

function fmt(value) {
  if (value >= 1e6) return `${(value / 1e6).toFixed(2)}M`;
  if (value >= 1e4) return `${(value / 1e3).toFixed(0)}k`;
  return String(Math.round(value));
}

function delta(now, before) {
  if (before === undefined || before === null || before === 0) return "";
  const change = ((now - before) / before) * 100;
  return `${change >= 0 ? "+" : ""}${change.toFixed(1)}%`;
}

function totals(heading) {
  return { tris: heading.tris + heading.shadowTris, draws: heading.draws + heading.shadowDraws + heading.extras };
}

function stopSummary(stop) {
  let tris = null;
  let draws = null;
  for (const heading of stop.headings) {
    const sum = totals(heading);
    if (!tris || sum.tris > tris.value) tris = { value: sum.tris, yaw: heading.yaw, heading };
    if (!draws || sum.draws > draws.value) draws = { value: sum.draws, yaw: heading.yaw, heading };
  }
  return { name: stop.name, tris, draws };
}

function printReport(run, previous, names, { top = 8 } = {}) {
  const budget = run.budget || {};
  const before = new Map((previous ? previous.stops : []).map((stop) => [stop.name, stopSummary(stop)]));
  const meta = run.meta || {};
  console.log(`run "${run.label}" ${run.at}${previous ? `  vs "${previous.label}" ${previous.at}` : ""}`);
  console.log(`view ${meta.viewport ? meta.viewport.join("x") : "?"}, fov ${meta.fov}, quality ${meta.quality}, shadows ${meta.shadows}, streaming ${meta.streaming}`);
  console.log(`budget ${budget.tris ? fmt(budget.tris) : "unset"} tris, ${budget.draws || "unset"} draws (worst heading at any stop; tris include the shadow pass)\n`);
  console.log(`${"stop".padEnd(20)} ${"tris".padStart(8)} ${"(shadow)".padStart(9)} ${"@".padStart(5)} ${"draws".padStart(6)} ${"@".padStart(5)} ${"Δtris".padStart(8)} ${"Δdraws".padStart(8)}  verdict`);
  let worstTris = null;
  let worstDraws = null;
  for (const stop of run.stops) {
    const now = stopSummary(stop);
    const then = before.get(stop.name);
    const overTris = budget.tris && now.tris.value > budget.tris;
    const overDraws = budget.draws && now.draws.value > budget.draws;
    const verdict = !budget.tris && !budget.draws ? "" : overTris || overDraws ? `OVER${overTris ? " tris" : ""}${overDraws ? " draws" : ""}` : "ok";
    console.log(
      `${stop.name.padEnd(20)} ${fmt(now.tris.value).padStart(8)} ${fmt(now.tris.heading.shadowTris).padStart(9)} ${(now.tris.yaw + "°").padStart(5)} ${String(now.draws.value).padStart(6)} ${(now.draws.yaw + "°").padStart(5)} ${delta(now.tris.value, then && then.tris.value).padStart(8)} ${delta(now.draws.value, then && then.draws.value).padStart(8)}  ${verdict}`,
    );
    if (!worstTris || now.tris.value > worstTris.summary.tris.value) worstTris = { stop, summary: now };
    if (!worstDraws || now.draws.value > worstDraws.summary.draws.value) worstDraws = { stop, summary: now };
  }

  const unknown = new Set();
  for (const stop of run.stops) for (const heading of stop.headings) for (const key of heading.unknownMeshes || []) unknown.add(key);
  if (unknown.size) console.log(`\n${unknown.size}+ meshes on screen have no triangle count (counted as 0): ${[...unknown].slice(0, 6).join(", ")} — run \`tris\``);
  if (run.errors && run.errors.length) console.log(`\nerrors: ${run.errors.map((text) => text.split("\n")[0]).join(" | ")}`);

  const list = (title, rows, field, label) => {
    console.log(`  ${title}`);
    for (const row of rows.slice(0, top)) {
      const value = field === "tris" ? fmt(row.tris) : String(row.draws);
      console.log(`    ${value.padStart(8)}  ${label(row)}`);
    }
  };
  const meshName = (row) => `${(names && names[row.name]) || "?"}  [${row.name}] x${row.parts}`;
  if (worstTris) {
    const breakdown = worstTris.stop.worstTris.breakdown;
    console.log(`\nworst tris: ${worstTris.stop.name} @${worstTris.stop.worstTris.yaw}° — ${fmt(worstTris.summary.tris.value)}`);
    list("by group", breakdown.groupsByTris, "tris", (row) => `${row.name} (${row.parts} parts, ${row.draws} draws)`);
    list("by asset", breakdown.assetsByTris, "tris", (row) => `${row.name} x${row.parts}`);
    list("by mesh", breakdown.meshesByTris, "tris", meshName);
  }
  if (worstDraws) {
    const breakdown = worstDraws.stop.worstDraws.breakdown;
    console.log(`\nworst draws: ${worstDraws.stop.name} @${worstDraws.stop.worstDraws.yaw}° — ${worstDraws.summary.draws.value} (${worstDraws.summary.draws.heading.draws} main, ${worstDraws.summary.draws.heading.shadowDraws} shadow, ${worstDraws.summary.draws.heading.extras} extras)`);
    list("by group", breakdown.groupsByDraws, "draws", (row) => `${row.name} (${fmt(row.tris)} tris)`);
    list("by asset", breakdown.assetsByDraws, "draws", (row) => `${row.name} x${row.parts}`);
  }
  const frames = Object.keys(run.frames || {});
  if (frames.length) console.log(`\nframes: ${frames.map((name) => run.frames[name]).join(", ")}`);
}

function report(options) {
  const root = bridge.findProjectRoot();
  const files = paths(root);
  const file = resolveRun(files.runs, options._[1]);
  if (!file) throw new Error(`no runs in ${files.runs} yet: run \`survey\` first`);
  const run = readJson(file);
  const runs = listRuns(files.runs);
  const vsFile = options.vs ? resolveRun(files.runs, options.vs) : runs[runs.indexOf(file) - 1];
  const route = readJson(files.route, null);
  if (route && route.budget) run.budget = route.budget;
  const table = readJson(files.tris, { names: {} });
  printReport(run, vsFile ? readJson(vsFile) : null, table.names, { top: Number(options.top) || 10 });
}

// ---------- check ----------

async function check(options) {
  const root = bridge.findProjectRoot();
  const files = paths(root);
  try {
    const target = await place(options, false);
    console.log(`studio   port ${target.port}: ${target.placeId} "${target.name}"`);
    const state = require(path.join(__dirname, "..", "studio", "studioLog.js")).playState(await playtest.findLog(target.port));
    console.log(`play     ${state.running ? `RUNNING (${state.phase}): stop it before surveying` : "not running"} (from Studio's session log)`);
  } catch (error) {
    console.log(`studio   ${error.message}`);
  }
  try {
    const route = loadRoute(root);
    const budget = route.budget;
    console.log(`route    ${route.stops.length} stops (${route.stops.map((stop) => stop.name).join(", ")}), ${route.headings || 8} headings`);
    console.log(`budget   ${budget.tris ? fmt(budget.tris) : "unset"} tris, ${budget.draws || "unset"} draws`);
  } catch (error) {
    console.log(`route    ${error.message}`);
  }
  const table = readJson(files.tris, null);
  console.log(table ? `tris     ${Object.keys(table.tris).length} meshes, updated ${table.updated}` : "tris     none yet (the first survey builds it)");
  const runs = listRuns(files.runs);
  console.log(runs.length ? `runs     ${runs.length}, latest ${path.basename(runs[runs.length - 1])}` : "runs     none yet");
}

async function main() {
  const options = parse(process.argv.slice(2));
  const command = options._[0];
  if (command === "check") return check(options);
  if (command === "tris") {
    const target = await place(options, true);
    return refreshTris(target.port, bridge.findProjectRoot(), Boolean(options.full));
  }
  if (command === "survey") return survey(options);
  if (command === "report") return report(options);
  if (command === "cleanup") {
    const target = await place(options, true);
    console.log(`removed ${await bridge.once(target.port, CLEANUP_LUA)} survey script`);
    return;
  }
  console.log("usage: node perf.js check | tris [--full] | survey [--label NAME] [--only a,b] [--frames] | report [RUN] [--vs RUN] | cleanup");
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
