// live.js: `demo.js live ...`, a scripted demo recorded in the live Roblox client instead of a Studio playtest.
// EXPERIMENTAL: built 2026-10-07 and tested offline and in Studio Edit only; no live run has happened yet (plan:
// <project>/plans/live-demo-plan.md, T0 and T6). It never touches Studio, never starts a playtest, never publishes.
//
//   node demo.js live check  [--open]                 the Player, its logs, the live config, the bundle, ffmpeg, no
//                                                     Roblox session running, the PC unlocked. --open launches a bare
//                                                     deep link once (first run: protocol prompt, sign-in, window mode)
//   node demo.js live bundle [demo.luau[=server.luau] ...] [--no-check]
//                                                     regenerates game-source/ServerStorage/LiveDemo/{BuildStamp,Client,
//                                                     Server} from demo-source/ (default: every demo there); then push
//                                                     with sync.js and publish the place from Studio
//   node demo.js live record <demo.luau> [--name N] [--place-id ID] [--direct] [--join 120] [--load 90] [--max 120]
//                            [--fps 30] [--capture window|desktop] [--keep-client] [--keep-raw] [--stats] [--out DIR]
//                            [--allow-unknown-name] (negative test: send a name the bundle lacks; the server refuses)
//   node demo.js live kill                            ends the RobloxPlayerBeta the last record drove (pid file)
//
// How a live run works:
//   1. The game ships a gated hook: the LiveDemo server component (Components/Generic) runs only for a UserId in
//      ServerStorage.LiveDemo.Config.OwnerUserIds, only when game.PlaceId is Config.TestPlaceId and Config.Enabled, and
//      only for launch data naming a demo in the bundle's fixed folder. No loadstring, no HttpService.
//   2. record opens roblox://experiences/start?placeId=<id>&launchData={"d":<demo>,"n":<nonce>,"b":<stamp>}.
//      The lobby server reserves a fresh server, stores the request in MemoryStore under its PrivateServerId and
//      teleports the owner (3 tries); the reserved server (always the newest published version) reads the request back,
//      refuses a build stamp that is not its own ("stale build": publish), clones DemoKit, the ready check and the demo
//      into the owner's PlayerGui and starts it. --direct runs on the joined server instead (it still checks the stamp).
//   3. The Player's log is the back-channel (playerLog.js): the log that gains "Joining game ... place <id>" after the
//      launch is the session's (the tray hand-off trap), every "[demo:<nonce>]" line is this run's, server status comes
//      relayed through the client as "[demo:<nonce>] server ...", and "stats" lines every 2 s carry fps, ping, memory
//      and the server's heartbeat.
//   4. ffmpeg records the Player window by hwnd (gfxcapture) from the run server's join; DemoKit flashes magenta->green
//      at the start, magenta->blue at the end, or magenta->red when the demo errored. `processVideo` trims and crops as
//      for Studio, and an errored clip is named -ERROR and never to be sent as a clean one.
//   5. The end: the server kicks the owner a second after done (or on its load/max watchdog); record kills the client it
//      found (unless --keep-client) and writes <clip>.stats.json. Hard watchdog: join + 60 + load + max + 90 s, Ctrl+C.
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { spawn, spawnSync } = require("child_process");
const demo = require(path.join(__dirname, "demo.js"));
const playerLog = require(path.join(__dirname, "playerLog.js"));
const playtest = require(path.join(__dirname, "..", "studio", "playtest.js"));

const LIVE_ROOT = "ServerStorage/LiveDemo";
const CONFIG_REL = `${LIVE_ROOT}/Config.luau`;
const STAMP_REL = `${LIVE_ROOT}/BuildStamp.luau`;
const MANIFEST = ".live-bundle.json";
const POLL_MS = 250;
const TELEPORT_SECONDS = 60;
const DONE_GRACE_MS = 1500;
const WINDOW_WAIT_MS = 20000;
const HOUSEKEEPING_MS = 1000;
const ACTIVE_LOG_HOURS = 12;
const STATE_DIR = path.join(os.tmpdir(), "demo");
const PID_FILE = path.join(STATE_DIR, "live-client.json");

// ---------- the project and its live config ----------

function findProject(start = process.cwd()) {
  let directory = path.resolve(start);
  for (;;) {
    if (fs.existsSync(path.join(directory, "game-source", ...CONFIG_REL.split("/"))) || (fs.existsSync(path.join(directory, "demo-source")) && fs.existsSync(path.join(directory, "game-source")))) return directory;
    const parent = path.dirname(directory);
    if (parent === directory) throw new Error(`no project (demo-source/ and game-source/) at or above ${start}`);
    directory = parent;
  }
}

const gameSource = (project, rel) => path.join(project, "game-source", ...rel.split("/"));

// The live config is the game's own ServerStorage.LiveDemo.Config (game-source/ServerStorage/LiveDemo/Config.luau), the
// security boundary the server reads; this reads the same file so the two can never disagree.
function parseLiveConfig(text) {
  const number = (key) => {
    const match = new RegExp(`\\b${key}\\s*=\\s*([\\d.]+)`).exec(text);
    return match ? Number(match[1]) : null;
  };
  const enabled = /\bEnabled\s*=\s*(true|false)\b/.exec(text);
  const owners = /\bOwnerUserIds\s*=\s*\{([^}]*)\}/.exec(text);
  return {
    enabled: Boolean(enabled && enabled[1] === "true"),
    placeId: (/\bTestPlaceId\s*=\s*(\d+)/.exec(text) || [])[1] || null,
    universeId: (/\bUniverseId\s*=\s*(\d+)/.exec(text) || [])[1] || null,
    ownerUserIds: owners ? owners[1].split(",").map((part) => part.trim()).filter(Boolean) : [],
    loadSeconds: number("LoadSeconds"),
    maxSeconds: number("MaxSeconds"),
  };
}

function readLiveConfig(project) {
  const file = gameSource(project, CONFIG_REL);
  if (!fs.existsSync(file)) throw new Error(`no live config: ${file} is missing`);
  const config = parseLiveConfig(fs.readFileSync(file, "utf8"));
  if (!config.placeId) throw new Error(`${file}: no TestPlaceId`);
  if (!config.ownerUserIds.length || config.ownerUserIds.some((id) => !/^\d+$/.test(id))) throw new Error(`${file}: OwnerUserIds must list numeric UserIds`);
  return { ...config, file };
}

// ---------- the bundle ----------

// Luau without its comments (Hard Rule: generated game code carries none). Strings, long strings and interpolated
// strings are copied untouched; line count is kept, comment-only lines are dropped afterwards, runs of blank lines
// collapse to one.
function stripComments(source) {
  const text = source.replace(/\r\n/g, "\n");
  let out = "";
  let index = 0;
  const longBracket = (at) => {
    const match = /^\[(=*)\[/.exec(text.slice(at, at + 64));
    return match ? match[1].length : -1;
  };
  const skipLong = (at, level) => {
    const close = "]" + "=".repeat(level) + "]";
    const end = text.indexOf(close, at);
    return end < 0 ? text.length : end + close.length;
  };
  while (index < text.length) {
    const char = text[index];
    if (char === "-" && text[index + 1] === "-") {
      const level = longBracket(index + 2);
      if (level >= 0) {
        const end = skipLong(index + 2 + level + 2, level);
        out += text.slice(index, end).replace(/[^\n]/g, "");
        index = end;
      } else {
        const end = text.indexOf("\n", index);
        index = end < 0 ? text.length : end;
      }
      continue;
    }
    if (char === '"' || char === "'" || char === "`") {
      let end = index + 1;
      while (end < text.length && text[end] !== char && text[end] !== "\n") end += text[end] === "\\" ? 2 : 1;
      out += text.slice(index, end + 1);
      index = end + 1;
      continue;
    }
    if (char === "[") {
      const level = longBracket(index);
      if (level >= 0) {
        const end = skipLong(index + level + 2, level);
        out += text.slice(index, end);
        index = end;
        continue;
      }
    }
    out += char;
    index++;
  }
  const original = text.split("\n");
  const lines = out.split("\n").map((line) => line.replace(/\s+$/, ""));
  const kept = lines.filter((line, at) => line !== "" || (original[at] || "").trim() === "");
  const collapsed = [];
  for (const line of kept) if (!(line === "" && (collapsed.length === 0 || collapsed[collapsed.length - 1] === ""))) collapsed.push(line);
  while (collapsed.length && collapsed[collapsed.length - 1] === "") collapsed.pop();
  return collapsed.join("\n");
}

const NAME = /^[A-Za-z0-9_]+$/;

// Which demos to bundle: every demo-source/*.luau except ready.luau and *.server.luau, or the given list. A server half
// ships only when named explicitly ("A.luau=B.server.luau"): it runs privileged on the live server (setTier and the
// like change the owner's real save), so it is never picked up by file name alone.
function bundleInputs(project, list = []) {
  const folder = path.join(project, "demo-source");
  const pair = (clientFile, serverFile) => {
    const name = path.basename(clientFile).replace(/\.luau$/i, "");
    if (!NAME.test(name)) throw new Error(`${clientFile}: a bundled demo's name must be letters, digits and _`);
    const server = serverFile || null;
    for (const file of [clientFile, server]) if (file && !fs.existsSync(file)) throw new Error(`${file}: no such file`);
    return { name, client: path.resolve(clientFile), server: server ? path.resolve(server) : null };
  };
  if (list.length) {
    return list.map((item) => {
      const [clientFile, serverFile] = item.split("=");
      return pair(path.resolve(clientFile), serverFile ? path.resolve(serverFile) : null);
    });
  }
  return fs
    .readdirSync(folder)
    .filter((file) => file.endsWith(".luau") && !file.endsWith(".server.luau") && file !== "ready.luau")
    .sort()
    .map((file) => pair(path.join(folder, file)));
}

// Every generated file, keyed by its path under game-source/, plus the stamp (a hash of all of them but BuildStamp).
function generateBundle(project, inputs) {
  const read = (file) => fs.readFileSync(file, "utf8");
  const files = {};
  files[`${LIVE_ROOT}/Client/DemoKit.luau`] = stripComments(read(path.join(__dirname, "DemoKit.luau"))) + "\n";
  const readyFile = path.join(project, "demo-source", "ready.luau");
  if (fs.existsSync(readyFile)) files[`${LIVE_ROOT}/Client/Ready.luau`] = `return function(Demo)\n${stripComments(read(readyFile))}\nend\n`;
  const seen = new Set();
  for (const input of inputs) {
    if (seen.has(input.name)) throw new Error(`two demos are named ${input.name}`);
    seen.add(input.name);
    const body = stripComments(read(input.client));
    files[`${LIVE_ROOT}/Client/Demos/${input.name}.luau`] = `return {\n\tdeferBegin = ${/Demo\.begin\(/.test(body)},\n\trun = function(Demo)\n${body}\nend,\n}\n`;
    if (input.server) files[`${LIVE_ROOT}/Server/${input.name}.luau`] = `return function(context)\n${stripComments(read(input.server))}\nend\n`;
  }
  const hash = crypto.createHash("sha1");
  for (const rel of Object.keys(files).sort()) hash.update(`${rel}\n${files[rel]}\n`);
  const stamp = hash.digest("hex").slice(0, 12);
  files[STAMP_REL] = `return "${stamp}"\n`;
  return { stamp, files, names: inputs.map((input) => input.name) };
}

const sha1 = (text) => crypto.createHash("sha1").update(text.replace(/\r\n/g, "\n")).digest("hex");

function syncBase(project, rel) {
  const file = path.join(project, "game-source", ".sync", ...`${rel}.sha1`.split("/"));
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim() : null;
}

function relativeInputs(project, inputs) {
  return inputs.map((input) => ({ name: input.name, client: path.relative(project, input.client).split(path.sep).join("/"), server: input.server ? path.relative(project, input.server).split(path.sep).join("/") : null }));
}

// The bundle on disk against a fresh generation from its manifest: { exists, stamp, names, upToDate, pushed, problems,
// unpushed }. upToDate: disk matches what the sources generate now; pushed: every file's sync base is its disk hash.
function bundleState(project) {
  const manifestFile = path.join(project, "demo-source", MANIFEST);
  if (!fs.existsSync(manifestFile) || !fs.existsSync(gameSource(project, STAMP_REL))) return { exists: false, problems: ["no bundle yet: run demo.js live bundle"], names: [], unpushed: [] };
  const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
  const problems = [];
  let fresh = null;
  try {
    fresh = generateBundle(project, manifest.entries.map((entry) => ({ name: entry.name, client: path.join(project, entry.client), server: entry.server ? path.join(project, entry.server) : null })));
  } catch (error) {
    problems.push(`cannot regenerate the bundle: ${error.message}`);
  }
  const unpushed = [];
  if (fresh) {
    for (const [rel, content] of Object.entries(fresh.files)) {
      const file = gameSource(project, rel);
      const disk = fs.existsSync(file) ? fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n") : null;
      if (disk !== content) problems.push(`${rel} is out of date with demo-source (run live bundle)`);
      else if (syncBase(project, rel) !== sha1(disk)) unpushed.push(rel);
    }
    if (fresh.stamp !== manifest.stamp) problems.push(`the sources changed since the last bundle (${manifest.stamp} -> ${fresh.stamp}): run live bundle`);
  }
  return { exists: true, stamp: manifest.stamp, names: manifest.entries.map((entry) => entry.name), upToDate: problems.length === 0, pushed: unpushed.length === 0, problems, unpushed };
}

function compileCheck(project, rels) {
  const result = spawnSync(process.execPath, [path.join(project, "game-source", "sync.js"), "check", ...rels.map((rel) => gameSource(project, rel))], { encoding: "utf8", cwd: project, timeout: 180000 });
  return { ok: result.status === 0, output: `${result.stdout || ""}${result.stderr || ""}`.trim() };
}

function bundle(options) {
  const project = findProject();
  const inputs = bundleInputs(project, options._.slice(2));
  const generated = generateBundle(project, inputs);
  const written = [];
  for (const [rel, content] of Object.entries(generated.files)) {
    const file = gameSource(project, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const before = fs.existsSync(file) ? fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n") : null;
    if (before !== content) fs.writeFileSync(file, content);
    written.push(rel);
  }
  const stale = [];
  for (const sub of ["Client/Demos", "Server"]) {
    const folder = gameSource(project, `${LIVE_ROOT}/${sub}`);
    if (!fs.existsSync(folder)) continue;
    for (const file of fs.readdirSync(folder)) if (!generated.files[`${LIVE_ROOT}/${sub}/${file}`]) stale.push(`${LIVE_ROOT}/${sub}/${file}`);
  }
  fs.writeFileSync(path.join(project, "demo-source", MANIFEST), JSON.stringify({ stamp: generated.stamp, generatedAt: new Date().toISOString(), entries: relativeInputs(project, inputs) }, null, 2) + "\n");
  console.log(`bundle   stamp ${generated.stamp}: ${generated.names.join(", ")}`);
  for (const input of inputs) if (input.server) console.log(`server   ${input.name} <- ${path.basename(input.server)} (privileged: runs on the live server for the owner; review it like an admin command)`);
  for (const rel of stale) console.log(`stale    ${rel} is not in this bundle: remove it with node game-source/sync.js delete game-source/${rel}`);
  if (!options["no-check"]) {
    const checked = compileCheck(project, [CONFIG_REL, ...written]);
    console.log(checked.ok ? `compile  ${checked.output.split("\n").pop()}` : `COMPILE FAILED\n${checked.output}`);
    if (!checked.ok) process.exitCode = 1;
  }
  const state = bundleState(project);
  const push = [...state.unpushed];
  if (syncBase(project, CONFIG_REL) !== sha1(fs.readFileSync(gameSource(project, CONFIG_REL), "utf8"))) push.unshift(CONFIG_REL);
  console.log(push.length ? `push     node game-source/sync.js push ${push.map((rel) => `game-source/${rel}`).join(" ")}` : "push     nothing to push (every bundle file matches its sync base)");
  console.log("then     publish the place from Studio (File > Publish to Roblox): reserved servers run the published version");
  return generated;
}

// ---------- following a run ----------

function newRunState({ nonce, direct = false }) {
  return { nonce, direct, lobbyJoin: null, runJoin: null, teleportAt: null, ready: null, start: null, done: null, errors: [], statuses: [], stats: [], failure: null, serverEnded: null, disconnect: null, teardown: null };
}

function parseStats(text, at) {
  const fields = {};
  for (const match of text.matchAll(/(\w+)=([\d.?]+)/g)) fields[match[1]] = match[2] === "?" ? null : Number(match[2]);
  return { at, fps: fields.fps ?? null, ping: fields.ping ?? null, mem: fields.mem ?? null, srv: fields.srv ?? null };
}

// One Player-log entry applied to a run; returns what to print. Pure, so the lifecycle is tested on real logs.
// A disconnect between a doTeleport and the next join is the teleport's own (285), not the end of the run.
function liveStep(state, entry) {
  const lines = [];
  if (entry.kind === "lifecycle") {
    if (entry.phase === "join") {
      if (!state.lobbyJoin) {
        state.lobbyJoin = entry;
        if (state.direct) state.runJoin = entry;
        lines.push(`roblox   joined ${state.direct ? "the run server" : "the lobby"} ${entry.jobId} (place ${entry.placeId})`);
      } else if (!state.runJoin && entry.jobId !== state.lobbyJoin.jobId) {
        state.runJoin = entry;
        lines.push(`roblox   joined the reserved server ${entry.jobId}`);
      } else lines.push(`roblox   joined another server ${entry.jobId} (ignored)`);
    } else if (entry.phase === "teleport") {
      state.teleportAt = entry.at;
      lines.push("roblox   teleporting");
    } else if (entry.phase === "disconnect") {
      const teleporting = state.teleportAt !== null && (!state.runJoin || state.teleportAt > state.runJoin.at);
      if (teleporting) lines.push(`roblox   ${entry.message} (the teleport's own)`);
      else {
        if (!state.disconnect) state.disconnect = entry;
        lines.push(`roblox   ${entry.message}: ${playerLog.describeDisconnect(entry.code)}`);
      }
    } else if (entry.phase === "teardown") {
      if (!state.teardown) state.teardown = entry;
      lines.push("roblox   session torn down");
    }
    return lines;
  }
  const mine = `[demo:${state.nonce}] `;
  if (!entry.message.startsWith(mine)) return lines;
  const text = entry.message.slice(mine.length).split("\n")[0];
  if (text.startsWith("stats ")) {
    state.stats.push(parseStats(text, entry.at));
    return [{ stats: true, text: `stats    ${text.slice(6)}` }];
  }
  lines.push(`game     ${text}`);
  if (text.startsWith("server ")) {
    const status = text.slice(7);
    state.statuses.push(status);
    if (status.startsWith("stale build")) state.failure = state.failure || `${status} (publish the place from Studio)`;
    else if (status.startsWith("teleport failed x3")) state.failure = state.failure || `${status}; --direct runs on the lobby server instead (only when its build stamp matches)`;
    else if (status.startsWith("refused")) state.failure = state.failure || status;
    else if (status.startsWith("error:")) state.errors.push(status);
    else if (status.startsWith("ending: ")) state.serverEnded = status.slice(8);
  } else if (text.startsWith("ready after")) state.ready = state.ready ?? entry.at;
  else if (text === "start") state.start = state.start ?? entry.at;
  else if (text === "done") state.done = state.done ?? entry.at;
  else if (text.startsWith("error:")) state.errors.push(text);
  return lines;
}

// Why a live start cannot be trusted, or null: it must come after the run server's join and after DemoKit's ready.
function liveStartProblem(state) {
  if (state.start === null) return "the demo never logged start";
  if (!state.runJoin) return "no join of the run server was seen before the start";
  if (state.start < state.runJoin.at) return "the start flash was logged before the run server's join";
  if (state.ready === null || state.ready > state.start) return "the start came without DemoKit's ready";
  return null;
}

function median(values) {
  const list = values.filter((value) => typeof value === "number").sort((left, right) => left - right);
  return list.length ? list[Math.floor(list.length / 2)] : null;
}

function statsSummary(state) {
  const during = state.stats.filter((sample) => state.start !== null && sample.at >= state.start && (state.done === null || sample.at <= state.done));
  const samples = during.length ? during : state.stats;
  const values = (key) => samples.map((sample) => sample[key]).filter((value) => typeof value === "number");
  return {
    samples: samples.length,
    fpsMedian: median(values("fps")),
    fpsMin: values("fps").length ? Math.min(...values("fps")) : null,
    pingMedian: median(values("ping")),
    memMax: values("mem").length ? Math.max(...values("mem")) : null,
    serverHeartbeatMedian: median(values("srv")),
  };
}

// ---------- preflight ----------

// Sessions running now: logs touched in the last 12 h whose last session never tore down and whose process lives.
function activeSessions(processes = playerLog.playerProcesses()) {
  const since = Date.now() - ACTIVE_LOG_HOURS * 3600 * 1000;
  const active = [];
  for (const entry of playerLog.listLogs()) {
    if (entry.mtime < since) continue;
    const state = playerLog.sessionState(entry.file);
    if (!state.active) continue;
    const owner = playerLog.pidForLog(entry.file, processes);
    if (owner) active.push({ file: entry.file, pid: owner.pid, placeId: state.placeId, jobId: state.jobId });
  }
  return active;
}

function preflight() {
  if (playerLog.isLocked()) throw new Error("the PC is locked (LogonUI.exe runs): window capture would record nothing; unlock it first");
  const active = activeSessions();
  if (active.length) throw new Error(`a Roblox session is running (pid ${active.map((session) => `${session.pid} in place ${session.placeId}`).join(", ")}): close it first; a second session on this account would kick one with error 273`);
}

// ---------- record ----------

function writePidFile(record) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(PID_FILE, JSON.stringify(record, null, 2));
}

function killRecorded({ quiet = false } = {}) {
  if (!fs.existsSync(PID_FILE)) {
    if (!quiet) console.log("kill     no pid file: nothing this tool launched is recorded");
    return false;
  }
  const record = JSON.parse(fs.readFileSync(PID_FILE, "utf8"));
  const match = playerLog.playerProcesses().find((entry) => entry.pid === record.pid && Math.abs(entry.startedAt - record.processStartedAt) < 2000);
  if (!match) {
    if (!quiet) console.log(`kill     pid ${record.pid} is gone (or is another process now): nothing killed`);
    fs.rmSync(PID_FILE, { force: true });
    return false;
  }
  const killed = playerLog.killPlayer(record.pid);
  if (!quiet) console.log(killed ? `kill     ended RobloxPlayerBeta pid ${record.pid}` : `kill     could not end pid ${record.pid}`);
  if (killed) fs.rmSync(PID_FILE, { force: true });
  return killed;
}

async function findWindow(pid) {
  const deadline = Date.now() + WINDOW_WAIT_MS;
  for (;;) {
    const entry = playerLog.playerProcesses().find((process) => process.pid === pid);
    if (entry && entry.hwnd) return entry;
    if (Date.now() > deadline) return null;
    await demo.sleep(500);
  }
}

async function record(options) {
  const demoFile = options._[2];
  if (!demoFile || !fs.existsSync(demoFile)) throw new Error("usage: node demo.js live record <project>/demo-source/<Demo>.luau [options]");
  const project = findProject(path.dirname(path.resolve(demoFile)));
  const config = readLiveConfig(project);
  if (!config.enabled) throw new Error(`${config.file}: Enabled is false (the kill switch is off)`);
  const placeId = String(options["place-id"] || config.placeId);
  const name = typeof options.name === "string" ? options.name : path.basename(demoFile).replace(/\.luau$/i, "");
  const state = bundleState(project);
  if (!state.exists || !state.upToDate) throw new Error(`the bundle is not ready: ${state.problems.join("; ")}`);
  if (!state.pushed) throw new Error(`the bundle is not pushed: ${state.unpushed.join(", ")} (push with sync.js, then publish)`);
  if (!state.names.includes(name) && !options["allow-unknown-name"]) throw new Error(`${name} is not in the bundle (${state.names.join(", ")}): add it with live bundle, push and publish`);
  const joinSeconds = Number(options.join) || 120;
  const loadSeconds = Number(options.load) || config.loadSeconds || 90;
  const maxSeconds = Number(options.max) || config.maxSeconds || 120;
  const capture = options.capture === "desktop" ? "desktop" : "window";
  const fps = Number(options.fps) || 30;
  const direct = Boolean(options.direct);
  const ffmpeg = demo.findFfmpeg();
  if (capture === "window" && !demo.hasGfxcapture(ffmpeg)) throw new Error(`${ffmpeg} has no gfxcapture filter (needs ffmpeg 8+); update it or pass --capture desktop`);
  preflight();

  const nonce = playtest.nonce();
  const launchData = playerLog.encodeLaunchData({ demo: name, nonce, stamp: state.stamp, direct });
  const url = playerLog.deepLink(placeId, launchData);
  const outDir = typeof options.out === "string" ? path.resolve(options.out) : STATE_DIR;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const rawFile = path.join(outDir, `${name}-live-${stamp}.raw.mkv`);
  let outFile = path.join(outDir, `${name}-live-${stamp}.mp4`);
  fs.mkdirSync(outDir, { recursive: true });
  console.log(`live     place ${placeId}, demo ${name}, run ${nonce}, bundle ${state.stamp}${direct ? ", direct (no teleport)" : ""}`);
  console.log(`launch   ${Buffer.byteLength(launchData)} B of launchData`);

  const hardMs = (joinSeconds + TELEPORT_SECONDS + loadSeconds + maxSeconds + 90) * 1000;
  const run = newRunState({ nonce, direct });
  let tripped = null;
  let recorder = null;
  let recorderStartedAt = null;
  let recorderError = "";
  let client = null;
  let failure = null;
  const trip = (reason) => {
    if (tripped) return;
    tripped = reason;
    console.log(`WATCHDOG ${reason}: killing ffmpeg and the client`);
    if (recorder && recorder.exitCode === null) recorder.kill();
    setTimeout(() => {
      console.error("watchdog: the stop path hung; exiting");
      process.exit(3);
    }, 30000).unref();
  };
  const watchdog = setTimeout(() => trip(`hard timeout of ${hardMs / 1000} s`), hardMs);
  const onInterrupt = () => (tripped ? process.exit(130) : trip("interrupted (Ctrl+C again to exit at once)"));
  process.on("SIGINT", onInterrupt);

  const before = playerLog.snapshot();
  try {
    playerLog.openLink(url);
    const launchedAt = Date.now();
    const watch = playerLog.watchJoin(before, placeId);
    let found = null;
    while (!found) {
      await demo.sleep(POLL_MS);
      if (tripped) throw new Error(`watchdog: ${tripped}`);
      found = watch.poll();
      if (!found && Date.now() - launchedAt > joinSeconds * 1000) throw new Error(`no Player log shows "Joining game ... place ${placeId}" within ${joinSeconds} s: Roblox may be updating or waiting on a first-run prompt; launch once by hand (live check --open)`);
    }
    console.log(`log      ${path.basename(found.file)}`);
    const tail = playerLog.openTail(found.file, found.offset);
    client = playerLog.pidForLog(found.file);
    if (client) {
      writePidFile({ pid: client.pid, processStartedAt: client.startedAt, log: found.file, nonce, launchedAt: new Date(launchedAt).toISOString() });
      console.log(`client   RobloxPlayerBeta pid ${client.pid}`);
    } else console.log("warning  could not tell which RobloxPlayerBeta writes this log: the client will not be killed by this tool");

    const seen = { lobby: null, runJoin: null, start: null, done: null };
    let lastHousekeeping = 0;
    const print = (line) => {
      if (typeof line === "string") console.log(line);
      else if (options.stats) console.log(line.text);
    };
    for (;;) {
      await demo.sleep(POLL_MS);
      if (tripped) throw new Error(`watchdog: ${tripped}`);
      for (const entry of tail.poll()) for (const line of liveStep(run, entry)) print(line);
      const now = Date.now();
      if (run.lobbyJoin && !seen.lobby) seen.lobby = now;
      if (run.runJoin && !seen.runJoin) seen.runJoin = now;
      if (run.start !== null && !seen.start) seen.start = now;
      if (run.failure) throw new Error(run.failure);
      if (run.runJoin && !recorder && client) {
        const window = await findWindow(client.pid);
        if (!window) throw new Error("the Player has no window to record");
        if (window.minimized) playerLog.restoreWindow(window.hwnd);
        recorder = spawn(ffmpeg, demo.recorderArgs(capture, { hwnd: window.hwnd, fps, rawFile, exe: "RobloxPlayerBeta.exe" }), { stdio: ["pipe", "ignore", "pipe"] });
        recorderStartedAt = Date.now();
        recorder.stderr.on("data", (chunk) => (recorderError += chunk));
        console.log(`record   window "${window.title}" (hwnd ${window.hwnd})${window.minimized ? ", restored from minimised" : ""}`);
      } else if (run.runJoin && !recorder && !client) throw new Error("the run server joined but the client process is unknown, so its window cannot be recorded");
      if (recorder && recorder.exitCode !== null) throw new Error(`ffmpeg stopped mid-recording: ${recorderError.slice(-400) || `exit ${recorder.exitCode}`}`);
      if (run.done !== null) {
        if (!seen.done) seen.done = now;
        if (now - seen.done >= DONE_GRACE_MS) break;
        continue;
      }
      if (run.disconnect || run.teardown) {
        const ending = run.disconnect ? `${run.disconnect.reason} (${playerLog.describeDisconnect(run.disconnect.code)})` : "the session tore down";
        throw new Error(`the client left before the demo finished: ${ending}${run.serverEnded ? `; server: ${run.serverEnded}` : ""}`);
      }
      if (!run.runJoin && seen.lobby && now - seen.lobby > TELEPORT_SECONDS * 1000) throw new Error(`no second join (the reserved server) within ${TELEPORT_SECONDS} s of the lobby join: the teleport failed`);
      if (run.runJoin && run.start === null && now - seen.runJoin > (loadSeconds + 10) * 1000) throw new Error(`the demo did not begin within ${loadSeconds} s of the join (the game never got ready?)`);
      if (run.start !== null && now - seen.start > (maxSeconds + 15) * 1000) throw new Error(`the demo ran past the ${maxSeconds} s cap`);
      if (now - lastHousekeeping >= HOUSEKEEPING_MS) {
        lastHousekeeping = now;
        if (client && !playerLog.isAlive(client.pid)) throw new Error(`the client (pid ${client.pid}) is gone: it crashed or was closed`);
        if (playerLog.isLocked()) throw new Error("the PC was locked mid-run");
        if (recorder && client) {
          const window = playerLog.playerProcesses().find((entry) => entry.pid === client.pid);
          if (window && window.minimized) {
            playerLog.restoreWindow(window.hwnd);
            console.log("window   was minimised: restored");
          }
        }
      }
    }
  } catch (error) {
    failure = error;
  } finally {
    clearTimeout(watchdog);
    if (recorder && recorder.exitCode === null) {
      recorder.stdin.write("q");
      const exited = await Promise.race([new Promise((done) => recorder.on("exit", () => done(true))), demo.sleep(10000).then(() => false)]);
      if (!exited) recorder.kill();
    }
    if (client && !options["keep-client"]) {
      const killed = killRecorded({ quiet: true });
      console.log(killed ? `client   ended pid ${client.pid}` : `client   pid ${client.pid} had already gone`);
    }
    process.removeListener("SIGINT", onInterrupt);
  }

  const statsFile = outFile.replace(/\.mp4$/i, "") + ".stats.json";
  const summary = statsSummary(run);
  fs.writeFileSync(statsFile, JSON.stringify({ demo: name, nonce, placeId, bundle: state.stamp, direct, lobbyJoin: run.lobbyJoin && run.lobbyJoin.jobId, runJoin: run.runJoin && run.runJoin.jobId, ready: run.ready, start: run.start, done: run.done, errors: run.errors, statuses: run.statuses, disconnect: run.disconnect && run.disconnect.reason, failure: failure && failure.message, summary, samples: run.stats }, null, 2));
  console.log(`stats    ${statsFile}${summary.samples ? ` (fps median ${summary.fpsMedian}, min ${summary.fpsMin}; ping ${summary.pingMedian} ms; memory up to ${summary.memMax} MB; server ${summary.serverHeartbeatMedian} Hz)` : ""}`);
  try {
    if (failure) throw failure;
    if (run.errors.length) console.log(`DEMO ERROR ${run.errors.join(" | ")}`);
    const problem = liveStartProblem(run);
    if (problem) throw new Error(`${problem}. Nothing was produced`);
    if (!recorderStartedAt || !fs.existsSync(rawFile)) throw new Error("nothing was recorded");
    const endAt = run.disconnect ? run.disconnect.at : null;
    const fallbackEnd = endAt !== null ? (endAt - recorderStartedAt) / 1000 - 0.5 : null;
    const processed = demo.processVideo(ffmpeg, rawFile, outFile, { fallbackEnd });
    if (processed.errored || run.errors.length) {
      const flagged = outFile.replace(/\.mp4$/i, "-ERROR.mp4");
      fs.renameSync(outFile, flagged);
      fs.renameSync(processed.poster, flagged.replace(/\.mp4$/i, "_poster.jpg"));
      outFile = flagged;
      console.log(`ERRORED  ${flagged}: the demo failed; fix it and record again, never send this as the feature working`);
      processed.clip = flagged;
      processed.poster = flagged.replace(/\.mp4$/i, "_poster.jpg");
    }
    return processed;
  } finally {
    if (!options["keep-raw"]) fs.rmSync(rawFile, { force: true });
    else if (fs.existsSync(rawFile)) console.log(`raw      ${rawFile} (the Player window; delete it when done)`);
  }
}

// ---------- check / kill ----------

async function check(options) {
  const project = (() => {
    try {
      return findProject();
    } catch {
      return null;
    }
  })();
  const install = playerLog.playerInstall();
  console.log(install.exe ? `player   ${install.exe}` : "player   NOT FOUND: install Roblox");
  console.log(install.handler ? `link     roblox: opens ${install.handler}` : "link     NO roblox: protocol handler registered");
  const logs = playerLog.listLogs();
  console.log(`logs     ${logs.length} Player logs in ${playerLog.LOG_DIR}${logs.length ? `, newest ${path.basename(logs[0].file)}` : ""}`);
  let config = null;
  if (project) {
    try {
      config = readLiveConfig(project);
      console.log(`config   ${path.relative(project, config.file)}: place ${config.placeId}, universe ${config.universeId}, owners ${config.ownerUserIds.join(", ")}, ${config.enabled ? "Enabled" : "DISABLED (kill switch off)"}`);
    } catch (error) {
      console.log(`config   ${error.message}`);
    }
    const state = bundleState(project);
    if (!state.exists) console.log(`bundle   ${state.problems[0]}`);
    else console.log(`bundle   stamp ${state.stamp}: ${state.names.join(", ")}; ${state.upToDate ? "up to date" : `OUT OF DATE: ${state.problems.join("; ")}`}; ${state.pushed ? "pushed" : `NOT PUSHED: ${state.unpushed.join(", ")}`} (publishing cannot be checked from here: a stale place says "stale build")`);
  } else console.log("project  none found here (run from the project root)");
  try {
    const ffmpeg = demo.findFfmpeg();
    console.log(`ffmpeg   ${ffmpeg}${demo.hasGfxcapture(ffmpeg) ? " (gfxcapture: window capture available)" : " (NO gfxcapture: use --capture desktop or update ffmpeg)"}`);
  } catch (error) {
    console.log(`ffmpeg   MISSING: ${error.message}`);
  }
  const processes = playerLog.playerProcesses();
  const active = activeSessions(processes);
  console.log(active.length ? `session  RUNNING: ${active.map((session) => `pid ${session.pid} in place ${session.placeId}`).join(", ")}; close it before a live run` : `session  none running${processes.length ? ` (${processes.length} idle RobloxPlayerBeta, e.g. the tray)` : ""}`);
  console.log(playerLog.isLocked() ? "screen   LOCKED: unlock the PC before a live run" : "screen   unlocked");
  if (options.open) {
    if (!config) throw new Error("--open needs the live config for the place id");
    const url = playerLog.deepLink(config.placeId);
    playerLog.openLink(url);
    console.log(`opened   ${url}: clear the protocol prompt, sign in if asked, set windowed mode and a fixed graphics quality, then close Roblox`);
  }
}

async function main(options) {
  const command = options._[1];
  if (command === "check") return check(options);
  if (command === "bundle") return bundle(options);
  if (command === "record") return record(options);
  if (command === "kill") return killRecorded();
  console.log("usage: node demo.js live check [--open] | bundle [demo.luau[=server.luau] ...] | record <demo.luau> [options] | kill");
}

module.exports = { main, findProject, parseLiveConfig, readLiveConfig, stripComments, bundleInputs, generateBundle, bundleState, newRunState, liveStep, liveStartProblem, statsSummary, parseStats, activeSessions };
