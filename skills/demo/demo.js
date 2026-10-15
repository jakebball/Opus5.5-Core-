#!/usr/bin/env node
// demo.js: records a short video of a feature running in a Studio playtest, cropped to the game view, ready for a phone.
//
//   node demo.js check                                      ffmpeg, the bridge, Studio's log and play state, the window
//   node demo.js record <demo.luau> [options]               the whole recording (below)
//   node demo.js process <raw.mkv> --out <clip.mp4>         flashes -> trim, crop, encode (offline, no Studio)
//   node demo.js cleanup                                    remove any leftover demo scripts from the place
//
// record options: --server <file.luau> (a server-side half), --name NAME, --out DIR (default %TEMP%\demo),
//   --load SECONDS (game start to Demo.begin, default 90), --max SECONDS (Demo.begin to done, default 120),
//   --ready <file.luau> (project ready check, default <project>/demo-source/ready.luau), --no-ready,
//   --preroll SECONDS (hold after ready, default 1.5), --capture window|desktop (default window), --fps N (default 30),
//   --keep-raw, --port N, --place-id ID
//
// How a recording runs (Tier 1, 2026-10-07):
//   1. The demo (Luau using `Demo`, see DemoKit.luau) is wrapped with DemoKit, a run nonce and the project's ready check
//      into a LocalScript `__DemoDirector`; a server Script `__DemoDirectorServer` (always installed, the optional
//      --server body inside it) ends the test itself through StudioTestService:EndTest when the client reports done,
//      or when its own watchdog runs out (load / max).
//   2. Studio's session log (studio/studioLog.js) is the back-channel: it must not show a playtest already running, it
//      must show a fresh initiatePlaySolo within 10 s of start_playtest, and every "[demo:<nonce>]" line is read from it.
//   3. ffmpeg records only the Studio window (gfxcapture; it records while covered, not while minimised); --capture
//      desktop is the old gdigrab whole-desktop path.
//   4. DemoKit waits for Demo.ready() (loaded, character, stable viewport, ready check, pre-roll), then flashes the game
//      view magenta->green (start); at the end magenta->blue. A start logged before Studio's PlaySoloPlayableTotalTime
//      + 1 s is rejected (the view was not on screen yet).
//   5. demo.js waits for StopPlaySoloEnd; failing that it calls stop_playtest and fails loudly if the test is still
//      alive 15 s later. A hard watchdog kills ffmpeg and runs the same stop path whatever happens.
//   6. `process` finds the start block, then the first end block after it, trims to them and crops to exactly the
//      pixels that flashed. No start flash means no output: the raw recording is deleted rather than sent anywhere.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");
const bridge = require(path.join(__dirname, "..", "studio", "bridge.js"));
const playtest = require(path.join(__dirname, "..", "studio", "playtest.js"));
const studioLog = require(path.join(__dirname, "..", "studio", "studioLog.js"));

const DIRECTOR = "__DemoDirector";
const SERVER_DIRECTOR = "__DemoDirectorServer";
const SCAN_WIDTH = 320;
const SCAN_HEIGHT = 180;
const SCAN_FPS = 10;
const MAX_BYTES = 24 * 1024 * 1024;
const PLAYABLE_MARGIN_MS = 1000;
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

function findFfmpeg() {
  if (process.env.FFMPEG && fs.existsSync(process.env.FFMPEG)) return process.env.FFMPEG;
  const onPath = spawnSync(process.platform === "win32" ? "where" : "which", ["ffmpeg"], { encoding: "utf8" });
  if (onPath.status === 0) return onPath.stdout.split(/\r?\n/)[0].trim();
  const local = process.env.LOCALAPPDATA || "";
  const link = path.join(local, "Microsoft", "WinGet", "Links", "ffmpeg.exe");
  if (fs.existsSync(link)) return link;
  const packages = path.join(local, "Microsoft", "WinGet", "Packages");
  if (fs.existsSync(packages)) {
    for (const folder of fs.readdirSync(packages).filter((name) => name.startsWith("Gyan.FFmpeg"))) {
      const root = path.join(packages, folder);
      for (const build of fs.readdirSync(root)) {
        const candidate = path.join(root, build, "bin", "ffmpeg.exe");
        if (fs.existsSync(candidate)) return candidate;
      }
    }
  }
  throw new Error("ffmpeg not found: install it (winget install Gyan.FFmpeg) or set FFMPEG to ffmpeg.exe");
}

function hasGfxcapture(ffmpeg) {
  const result = spawnSync(ffmpeg, ["-hide_banner", "-h", "filter=gfxcapture"], { encoding: "utf8" });
  return /window_exe/.test(result.stdout || "");
}

function ffmpegSync(ffmpeg, args, binary = false) {
  const result = spawnSync(ffmpeg, ["-hide_banner", "-loglevel", "error", ...args], { encoding: binary ? "buffer" : "utf8", maxBuffer: 1024 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`ffmpeg ${args.join(" ").slice(0, 160)} failed: ${String(result.stderr).slice(-600)}`);
  return result.stdout;
}

function probeVideo(ffmpeg, file) {
  const result = spawnSync(ffmpeg, ["-hide_banner", "-i", file], { encoding: "utf8" });
  const text = result.stderr || "";
  const size = /Video:.*?(\d{2,5})x(\d{2,5})/.exec(text);
  const duration = /Duration: (\d+):(\d+):([\d.]+)/.exec(text);
  if (!size) throw new Error(`${file}: no video stream found`);
  return {
    width: Number(size[1]),
    height: Number(size[2]),
    seconds: duration ? Number(duration[1]) * 3600 + Number(duration[2]) * 60 + Number(duration[3]) : 0,
  };
}

// ---------- flashes ----------

const isMagenta = (red, green, blue) => red > 230 && green < 40 && blue > 230;
const isGreen = (red, green, blue) => red < 40 && green > 200 && blue < 40;
const isBlue = (red, green, blue) => red < 40 && green < 40 && blue > 200;
const isRed = (red, green, blue) => red > 200 && green < 40 && blue < 40;
const MARKER_MIN_SHARE = 0.06;
const MARKER_PHASE_SECONDS = 0.5;
const MARKER_MAX_SECONDS = 1.5;
// the second colour must cover this share of the pixels that were magenta
const SECOND_MIN_SHARE = 0.5;

// Every magenta block in the recording, classified by the colour the same pixels turn next: green = start, blue = end,
// red = error (an errored live demo's end flash; Studio demos never draw it), anything else = unknown (not a DemoKit
// flash, or a flash cut short). [{ start, end, type, share }] in seconds.
function markerBlocks(ffmpeg, file) {
  const raw = ffmpegSync(ffmpeg, ["-i", file, "-vf", `fps=${SCAN_FPS},scale=${SCAN_WIDTH}:${SCAN_HEIGHT}`, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], true);
  const pixels = SCAN_WIDTH * SCAN_HEIGHT;
  const frameBytes = pixels * 3;
  const frames = Math.floor(raw.length / frameBytes);
  const shares = [];
  for (let frame = 0; frame < frames; frame++) {
    let count = 0;
    for (let pixel = frame * frameBytes; pixel < (frame + 1) * frameBytes; pixel += 3) if (isMagenta(raw[pixel], raw[pixel + 1], raw[pixel + 2])) count++;
    shares.push(count / pixels);
  }
  const baseline = [...shares].sort((left, right) => left - right)[Math.floor(shares.length / 2)] || 0;
  const runs = [];
  for (let frame = 0; frame < frames; frame++) {
    if (!(shares[frame] > baseline + MARKER_MIN_SHARE)) continue;
    const last = runs[runs.length - 1];
    if (last && last.endFrame === frame - 1) last.endFrame = frame;
    else runs.push({ startFrame: frame, endFrame: frame });
  }
  const blocks = [];
  for (const run of runs) {
    const start = run.startFrame / SCAN_FPS;
    const end = (run.endFrame + 1) / SCAN_FPS;
    if (end - start > MARKER_MAX_SECONDS) continue;
    let peak = run.startFrame;
    for (let frame = run.startFrame; frame <= run.endFrame; frame++) if (shares[frame] > shares[peak]) peak = frame;
    const mask = [];
    for (let index = 0; index < pixels; index++) {
      const at = peak * frameBytes + index * 3;
      if (isMagenta(raw[at], raw[at + 1], raw[at + 2])) mask.push(index);
    }
    let green = 0;
    let blue = 0;
    let red = 0;
    const lastFrame = Math.min(frames - 1, run.endFrame + Math.ceil((MARKER_PHASE_SECONDS + 0.3) * SCAN_FPS));
    for (let frame = run.endFrame + 1; frame <= lastFrame; frame++) {
      let greenHere = 0;
      let blueHere = 0;
      let redHere = 0;
      for (const index of mask) {
        const at = frame * frameBytes + index * 3;
        if (isGreen(raw[at], raw[at + 1], raw[at + 2])) greenHere++;
        else if (isBlue(raw[at], raw[at + 1], raw[at + 2])) blueHere++;
        else if (isRed(raw[at], raw[at + 1], raw[at + 2])) redHere++;
      }
      green = Math.max(green, greenHere);
      blue = Math.max(blue, blueHere);
      red = Math.max(red, redHere);
    }
    const type = classifySecond(mask.length, { green, blue, red });
    blocks.push({ start, end, type, share: Number(shares[peak].toFixed(3)) });
  }
  return blocks;
}

// What a magenta block turned into, from the most pixels of its mask seen in each second colour: the colour must cover
// SECOND_MIN_SHARE of the mask and beat the others. Start and end are judged exactly as before red existed.
function classifySecond(maskSize, { green = 0, blue = 0, red = 0 }) {
  const need = maskSize * SECOND_MIN_SHARE;
  if (green >= need && green > blue) return "start";
  if (blue >= need && blue > green) return "end";
  if (red >= need && red > green && red > blue) return "error";
  return "unknown";
}

// The clip between the flashes: the first start block, then the first end (or error) block after it. An end block is
// never taken as the start. Without an end block, `fallbackEnd` (seconds into the video) closes the clip, or it is
// refused. `errored` is true when the clip closes on the red error flash.
function pickClip(blocks, { fallbackEnd = null } = {}) {
  const first = blocks.find((block) => block.type === "start");
  if (!first) throw new Error("no start flash (magenta->green) in the recording: the demo never began on screen; nothing was produced");
  const last = blocks.find((block) => (block.type === "end" || block.type === "error") && block.start > first.end);
  const start = first.end + MARKER_PHASE_SECONDS + 0.15;
  let end;
  if (last) end = last.start - 0.05;
  else if (fallbackEnd !== null && fallbackEnd > start + 0.5) end = fallbackEnd;
  else throw new Error("no end flash (magenta->blue) after the start flash, and no log time to end on; nothing was produced");
  if (end <= start + 0.5) throw new Error(`the clip between the flashes is ${(end - start).toFixed(2)} s long; nothing was produced`);
  return { first, last: last || null, start, end, errored: Boolean(last && last.type === "error") };
}

function grabFrame(ffmpeg, file, atSeconds) {
  return ffmpegSync(ffmpeg, ["-ss", Math.max(0, atSeconds).toFixed(3), "-i", file, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], true);
}

// The game view: the bounding box of the pixels that are magenta in the flash and turn green right after.
function markerBox(ffmpeg, file, magentaSeconds, secondSeconds, width, height) {
  const frame = grabFrame(ffmpeg, file, magentaSeconds);
  const after = grabFrame(ffmpeg, file, secondSeconds);
  const rows = new Array(height).fill(0);
  const columns = new Array(width).fill(0);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const pixel = (y * width + x) * 3;
      if (!isMagenta(frame[pixel], frame[pixel + 1], frame[pixel + 2])) continue;
      if (!(after.length > pixel + 2 && isGreen(after[pixel], after[pixel + 1], after[pixel + 2]))) continue;
      rows[y]++;
      columns[x]++;
    }
  }
  const solid = (counts) => {
    const peak = Math.max(...counts);
    const first = counts.findIndex((count) => count >= peak * 0.5);
    let last = -1;
    for (let index = counts.length - 1; index >= 0; index--) if (counts[index] >= peak * 0.5) { last = index; break; }
    return peak > 0 ? [first, last] : [-1, -1];
  };
  const [top, bottom] = solid(rows);
  const [left, right] = solid(columns);
  if (right < 0) return null;
  const inset = 2;
  const even = (value) => value - (value % 2);
  const x = left + inset;
  const y = top + inset;
  return { x, y, width: even(right - left + 1 - inset * 2), height: even(bottom - top + 1 - inset * 2) };
}

function processVideo(ffmpeg, rawFile, outFile, { log = console.log, fallbackEnd = null } = {}) {
  const info = probeVideo(ffmpeg, rawFile);
  const blocks = markerBlocks(ffmpeg, rawFile);
  log(`flashes  ${blocks.length ? blocks.map((block) => `${block.type}@${block.start.toFixed(1)}-${block.end.toFixed(1)}s(${(block.share * 100).toFixed(0)}%)`).join(", ") : "none"}`);
  const clip = pickClip(blocks, { fallbackEnd: fallbackEnd === null ? null : Math.min(fallbackEnd, info.seconds) });
  if (!clip.last) log(`warning  no end flash: the clip ends at the log's stop time (${clip.end.toFixed(1)} s)`);
  if (clip.errored) log("ERRORED  the clip ends on the red error flash: the demo failed. Never send it as a clean clip");
  const { first, start, end } = clip;
  const box = markerBox(ffmpeg, rawFile, (first.start + first.end) / 2, first.end + MARKER_PHASE_SECONDS / 2, info.width, info.height);
  if (!box || box.width < 64 || box.height < 64) throw new Error("could not find the game view in the start flash; nothing was produced");
  const duration = end - start;
  const kilobits = Math.max(800, Math.min(5000, Math.floor((MAX_BYTES * 8) / 1000 / Math.max(duration, 1) * 0.9)));
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  ffmpegSync(ffmpeg, [
    "-y", "-ss", start.toFixed(3), "-to", end.toFixed(3), "-i", rawFile,
    "-vf", `crop=${box.width}:${box.height}:${box.x}:${box.y},scale='min(1280,iw)':-2`,
    "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-maxrate", `${kilobits}k`, "-bufsize", `${kilobits * 2}k`,
    "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", outFile,
  ]);
  const poster = outFile.replace(/\.mp4$/i, "") + "_poster.jpg";
  ffmpegSync(ffmpeg, ["-y", "-ss", (duration / 2).toFixed(3), "-i", outFile, "-frames:v", "1", "-q:v", "3", poster]);
  const bytes = fs.statSync(outFile).size;
  log(`clip     ${outFile}`);
  log(`poster   ${poster}`);
  log(`length   ${duration.toFixed(1)} s (${start.toFixed(1)}-${end.toFixed(1)} s of the raw), ${(bytes / 1024 / 1024).toFixed(1)} MB, game view ${box.width}x${box.height} at ${box.x},${box.y} of ${info.width}x${info.height}`);
  return { clip: outFile, poster, seconds: duration, bytes, box, blocks, errored: clip.errored };
}

// ---------- the Studio window ----------

function windowHelper(titleHint, { restore = false, focus = false } = {}) {
  const script = `
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DemoWindow {
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
}
"@
$windows = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
$hint = ${JSON.stringify(titleHint || "")}
$pick = $windows | Where-Object { $hint -and $_.MainWindowTitle -like "*$hint*" } | Select-Object -First 1
if (-not $pick) { $pick = $windows | Select-Object -First 1 }
$result = @{ found = [bool]$pick; count = @($windows).Count }
if ($pick) {
  $result.title = $pick.MainWindowTitle
  $result.pid = $pick.Id
  $result.hwnd = [int64]$pick.MainWindowHandle
  $result.minimized = [DemoWindow]::IsIconic($pick.MainWindowHandle)
  if (${restore || focus ? "$true" : "$false"} -and $result.minimized) { [void][DemoWindow]::ShowWindow($pick.MainWindowHandle, 9); $result.restored = $true }
  if (${focus ? "$true" : "$false"}) {
    [void][DemoWindow]::ShowWindow($pick.MainWindowHandle, 3)
    $result.focused = [DemoWindow]::SetForegroundWindow($pick.MainWindowHandle)
  }
}
$result | ConvertTo-Json -Compress
`;
  const file = path.join(os.tmpdir(), `demo-window-${process.pid}.ps1`);
  fs.writeFileSync(file, script);
  const result = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", file], { encoding: "utf8" });
  fs.rmSync(file, { force: true });
  try {
    return JSON.parse(result.stdout.trim().split(/\r?\n/).pop());
  } catch {
    return { found: false, error: (result.stderr || result.stdout).slice(0, 300) };
  }
}

// ffmpeg arguments for the raw recording. window: gfxcapture of the one Studio window (Windows Graphics Capture: it
// keeps recording while other windows cover Studio, but a minimised window gives no frames, and nothing else on the
// desktop is ever captured). desktop: gdigrab of the whole desktop (Studio must be in front and uncovered).
function recorderArgs(mode, { hwnd, fps, rawFile, exe = "RobloxStudioBeta.exe" }) {
  const encode = ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", rawFile];
  if (mode === "desktop") return ["-hide_banner", "-loglevel", "error", "-y", "-f", "gdigrab", "-framerate", String(fps), "-draw_mouse", "0", "-i", "desktop", ...encode];
  const target = hwnd ? `hwnd=${hwnd}` : `window_exe=${exe}`;
  const source = `gfxcapture=${target}:max_framerate=${fps}:capture_cursor=0:width=-2:height=-2,hwdownload,format=bgra`;
  return ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", source, ...encode];
}

// ---------- the scripts ----------

function readLuau(file) {
  return fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
}

function directorSource(demoFile, { id, readyFile = null, readyTimeout = 90, preroll = 1.5 }) {
  const kit = readLuau(path.join(__dirname, "DemoKit.luau"));
  const body = readLuau(demoFile);
  const ready = readyFile ? `Demo._readyCheck = function(Demo)\n${readLuau(readyFile)}\nend\n` : "";
  return `if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
	return
end
local Demo = (function()
${kit}
end)()
Demo._nonce = "${id}"
Demo._config = { readyTimeout = ${Number(readyTimeout)}, preroll = ${Number(preroll)} }
${ready}${playtest.CLIENT_SIGNAL_LUA}
Demo._signal = __signalDirector
Demo._run(function(Demo)
${body}
end, ${/Demo\.begin\(/.test(body)})
`;
}

function serverSource(serverFile, { id, loadSeconds, maxSeconds }) {
  return playtest.serverDirectorSource({ tag: "demo", id, loadSeconds, maxSeconds, body: serverFile ? readLuau(serverFile) : "" });
}

const CLEANUP_LUA = `local removed = 0
for _, holder in { game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"), game:GetService("ServerScriptService") } do
	if holder then
		for _, name in { "${DIRECTOR}", "${SERVER_DIRECTOR}" } do
			local leftover = holder:FindFirstChild(name)
			if leftover then
				leftover:Destroy()
				removed += 1
			end
		end
	end
end
return removed`;

async function compileCheck(port, name, source) {
  const check = await bridge.once(port, `local fn, err = loadstring(${bridge.longString(source)}, "${name}")\nreturn if fn then "" else tostring(err)`);
  if (check) throw new Error(`${name} does not compile: ${check}`);
}

async function install(port, parts) {
  for (const [, , name, source] of parts) await compileCheck(port, name, source);
  for (const [parent, className, name, source] of parts) {
    await bridge.once(port, `local parent = ${parent}
local existing = parent:FindFirstChild("${name}")
if existing then existing:Destroy() end
local script = Instance.new("${className}")
script.Name = "${name}"
script.Source = ${bridge.longString(source)}
script.Parent = parent
return "ok"`);
  }
}

function sleep(milliseconds) {
  return new Promise((done) => setTimeout(done, milliseconds));
}

// Why a start flash cannot be trusted, or null. Studio swaps the edit view for the game view around
// PlaySoloPlayableTotalTime; a flash logged before that + 1 s was drawn into a view nobody saw (2026-10-07: the start
// flash came 7 s early, so the end flash was taken as the start).
function startFlashProblem(demoStartAt, playableAt) {
  if (demoStartAt === null || demoStartAt === undefined) return null;
  if (playableAt === undefined || playableAt === null) return null;
  if (demoStartAt >= playableAt + PLAYABLE_MARGIN_MS) return null;
  return `the start flash (${new Date(demoStartAt).toISOString()}) came before Studio reported the game playable (${new Date(playableAt).toISOString()}) + 1 s, so the game view was not on screen yet; raise --preroll or tighten demo-source/ready.luau`;
}

function defaultReadyFile(demoFile) {
  const candidate = path.join(path.dirname(path.resolve(demoFile)), "ready.luau");
  return fs.existsSync(candidate) ? candidate : null;
}

// ---------- record ----------

async function record(options) {
  const demoFile = options._[1];
  if (!demoFile || !fs.existsSync(demoFile)) throw new Error("usage: node demo.js record <demo.luau> [--server file.luau] [--name NAME] [--out DIR]");
  const serverFile = typeof options.server === "string" ? options.server : null;
  if (serverFile && !fs.existsSync(serverFile)) throw new Error(`--server ${serverFile}: no such file`);
  const readyFile = options["no-ready"] ? null : typeof options.ready === "string" ? options.ready : defaultReadyFile(demoFile);
  if (readyFile && !fs.existsSync(readyFile)) throw new Error(`--ready ${readyFile}: no such file`);
  const capture = options.capture === "desktop" ? "desktop" : "window";
  const fps = Number(options.fps) || 30;
  const ffmpeg = findFfmpeg();
  if (capture === "window" && !hasGfxcapture(ffmpeg)) throw new Error(`${ffmpeg} has no gfxcapture filter (needs ffmpeg 8+); update it or pass --capture desktop`);
  const config = bridge.readConfig(bridge.findProjectRoot());
  const place = await bridge.resolve({ port: options.port, placeId: options["place-id"] || config.placeId, writes: true });
  const logFile = await playtest.findLog(place.port);
  const name = typeof options.name === "string" ? options.name : path.basename(demoFile).replace(/\.(client\.)?luau$/i, "");
  const outDir = typeof options.out === "string" ? path.resolve(options.out) : path.join(os.tmpdir(), "demo");
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const rawFile = path.join(outDir, `${name}-${stamp}.raw.mkv`);
  const outFile = path.join(outDir, `${name}-${stamp}.mp4`);
  const loadSeconds = Number(options.load) || 90;
  const maxSeconds = Number(options.max) || 120;
  const preroll = options.preroll !== undefined ? Number(options.preroll) : 1.5;
  const id = playtest.nonce();
  fs.mkdirSync(outDir, { recursive: true });
  console.log(`place    port ${place.port}: ${place.placeId} "${place.name}"`);
  console.log(`log      ${path.basename(logFile)}`);
  console.log(`run      ${id}${readyFile ? `, ready check ${path.basename(readyFile)}` : ", no project ready check"}, capture ${capture}`);

  const window = windowHelper(place.name, { restore: true, focus: capture === "desktop" });
  if (!window.found) throw new Error("no Roblox Studio window found");
  console.log(`window   "${window.title}"${window.restored ? " (was minimised: restored)" : ""}`);

  // client ready timeout sits inside the server's load watchdog so the client reports its own failure first
  const parts = [
    ['game:GetService("StarterPlayer").StarterPlayerScripts', "LocalScript", DIRECTOR, directorSource(demoFile, { id, readyFile, readyTimeout: Math.max(10, loadSeconds - 10), preroll })],
    ['game:GetService("ServerScriptService")', "Script", SERVER_DIRECTOR, serverSource(serverFile, { id, loadSeconds, maxSeconds })],
  ];

  const hardMs = (loadSeconds + maxSeconds + 90) * 1000;
  let tripped = null;
  let recorder = null;
  let recorderStartedAt = null;
  let tail = null;
  let launched = false;
  const trip = (reason) => {
    if (tripped) return;
    tripped = reason;
    console.log(`WATCHDOG ${reason}: killing ffmpeg and stopping the playtest`);
    if (recorder && recorder.exitCode === null) recorder.kill();
    // last resort if the stop path itself hangs
    setTimeout(() => {
      console.error("watchdog: the stop path hung; exiting. CHECK STUDIO: a playtest may still be running.");
      process.exit(3);
    }, 90000).unref();
  };
  const watchdog = setTimeout(() => trip(`hard timeout of ${hardMs / 1000} s`), hardMs);
  const onInterrupt = () => (tripped ? process.exit(130) : trip("interrupted (Ctrl+C again to exit at once)"));
  process.on("SIGINT", onInterrupt);

  const run = { demoStart: null, done: false, errors: [], serverEnded: null };
  let processed = null;
  try {
    tail = playtest.prepare(logFile);
    await install(place.port, parts);
    recorder = spawn(ffmpeg, recorderArgs(capture, { hwnd: window.hwnd, fps, rawFile }), { stdio: ["pipe", "ignore", "pipe"] });
    recorderStartedAt = Date.now();
    let recorderError = "";
    recorder.stderr.on("data", (chunk) => (recorderError += chunk));
    await sleep(1200);
    if (recorder.exitCode !== null) throw new Error(`ffmpeg could not record (${capture}): ${recorderError.slice(-400) || `exit ${recorder.exitCode}`}`);

    launched = true;
    await playtest.launch(place.port, tail);
    const startedAt = Date.now();
    console.log("playtest started (initiatePlaySolo seen in the log)");
    const seconds = (at) => ((at - tail.phases.start) / 1000).toFixed(1);
    const mine = `[demo:${id}] `;
    while (!run.done) {
      await sleep(POLL_MS);
      if (tripped) throw new Error(`watchdog: ${tripped}`);
      for (const entry of tail.poll()) {
        if (entry.kind === "lifecycle") {
          console.log(`studio   +${seconds(entry.at)} s ${entry.phase}`);
          continue;
        }
        if (!entry.message.startsWith(mine)) continue;
        const text = entry.message.slice(mine.length);
        console.log(`game     +${seconds(entry.at)} s ${text.split("\n")[0]}`);
        if (text === "start") run.demoStart = entry.at;
        else if (text === "done") run.done = true;
        else if (text.startsWith("error:") || text.startsWith("server error:")) run.errors.push(text);
        else if (text.startsWith("server ending the test: ")) run.serverEnded = text.slice("server ending the test: ".length);
      }
      if (recorder.exitCode !== null) throw new Error(`ffmpeg stopped mid-recording: ${recorderError.slice(-400) || `exit ${recorder.exitCode}`}`);
      if (tail.phases.stopping !== undefined && !run.done) {
        console.log(`the playtest ended before the demo finished${run.serverEnded ? ` (server: ${run.serverEnded})` : ""}`);
        break;
      }
      if (!run.demoStart && Date.now() - startedAt > (loadSeconds + 20) * 1000) throw new Error(`the demo did not begin within ${loadSeconds} s (the game never got ready?)`);
      if (run.demoStart && Date.now() - startedAt > (loadSeconds + maxSeconds + 30) * 1000) throw new Error(`the demo ran past the ${maxSeconds} s cap`);
    }
  } finally {
    clearTimeout(watchdog);
    let stopError = null;
    if (launched) {
      try {
        const how = await playtest.ensureStopped(place.port, tail);
        console.log(`stopped  (${how === "game" ? "the game ended itself" : how})`);
      } catch (error) {
        stopError = error;
      }
    }
    if (recorder && recorder.exitCode === null) {
      recorder.stdin.write("q");
      const exited = await Promise.race([new Promise((done) => recorder.on("exit", () => done(true))), sleep(10000).then(() => false)]);
      if (!exited) recorder.kill();
    }
    const removed = await bridge.once(place.port, CLEANUP_LUA).catch(() => "?");
    console.log(`cleanup  removed ${removed} demo script(s)`);
    process.removeListener("SIGINT", onInterrupt);
    if (stopError) {
      if (!options["keep-raw"]) fs.rmSync(rawFile, { force: true });
      throw stopError;
    }
  }

  try {
    if (run.errors.length) console.log(`DEMO ERROR ${run.errors.join(" | ")}`);
    const playable = tail.phases.playable;
    if (playable === undefined) console.log("warning  Studio never logged PlaySoloPlayableTotalTime: the start could not be checked against it");
    const problem = startFlashProblem(run.demoStart, playable);
    if (problem) throw new Error(`${problem}. Nothing was produced`);
    const fallbackEnd = tail.phases.stopping !== undefined && recorderStartedAt ? (tail.phases.stopping - recorderStartedAt) / 1000 - 0.5 : null;
    processed = processVideo(ffmpeg, rawFile, outFile, { fallbackEnd });
    if (run.errors.length) console.log("the demo errored: fix it and record again before sending this clip");
    return processed;
  } finally {
    if (!options["keep-raw"]) fs.rmSync(rawFile, { force: true });
    else console.log(`raw      ${rawFile} (the Studio window; delete it when done)`);
  }
}

// ---------- check / cleanup ----------

async function check() {
  let ffmpeg = null;
  try {
    ffmpeg = findFfmpeg();
    console.log(`ffmpeg   ${ffmpeg}${hasGfxcapture(ffmpeg) ? " (gfxcapture: window capture available)" : " (NO gfxcapture: use --capture desktop or update ffmpeg)"}`);
  } catch (error) {
    console.log(`ffmpeg   MISSING: ${error.message}`);
  }
  const found = await bridge.probe();
  console.log(found.length ? found.map((entry) => `studio   port ${entry.port}: placeId ${entry.placeId} "${entry.name}"`).join("\n") : "studio   no Studio MCP bridge answered");
  if (found.length) {
    try {
      const file = await playtest.findLog(found[0].port);
      const state = studioLog.playState(file);
      console.log(`log      ${path.basename(file)}`);
      console.log(`play     ${state.running ? `RUNNING (${state.phase} at ${new Date(state.at).toISOString()}): stop it before recording` : state.phase ? `not running (last: ${state.phase} at ${new Date(state.at).toISOString()}${state.stale ? ", stale" : ""})` : "no playtest in this session yet"}`);
    } catch (error) {
      console.log(`log      ${error.message}`);
    }
  }
  const window = windowHelper("");
  console.log(window.found ? `window   "${window.title}"${window.minimized ? " (MINIMISED: recording restores it; window capture gets no frames from a minimised window)" : ""}` : "window   no Roblox Studio window");
}

async function main() {
  const options = parse(process.argv.slice(2));
  const command = options._[0];
  if (command === "check") return check();
  if (command === "record") return record(options);
  if (command === "process") {
    if (typeof options.out !== "string") throw new Error("usage: node demo.js process <raw> --out <clip.mp4>");
    return processVideo(findFfmpeg(), options._[1], path.resolve(options.out));
  }
  if (command === "live") return require(path.join(__dirname, "live.js")).main(options);
  if (command === "cleanup") {
    const place = await bridge.resolve({ port: options.port, placeId: options["place-id"] || bridge.readConfig(bridge.findProjectRoot()).placeId, writes: true });
    console.log(`removed ${await bridge.once(place.port, CLEANUP_LUA)} demo script(s)`);
    return;
  }
  console.log("usage: node demo.js check | record <demo.luau> [options] | process <raw> --out <clip.mp4> | cleanup | live check|bundle|record|kill");
}

const { callTool } = playtest;
module.exports = { parse, findFfmpeg, hasGfxcapture, windowHelper, recorderArgs, callTool, sleep, markerBlocks, classifySecond, pickClip, processVideo, directorSource, serverSource, startFlashProblem, readLuau, MARKER_PHASE_SECONDS };

if (require.main === module) {
  main().catch((error) => {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  });
}
