#!/usr/bin/env node
// demo.js: records a short video of a feature running in a Studio playtest, cropped to the game view, ready for a phone.
//
//   node demo.js check                                      ffmpeg, the Studio bridge, and the Studio window
//   node demo.js record <demo.luau> [options]               the whole recording (below)
//   node demo.js process <raw.mp4> --out <clip.mp4>         markers -> trim, crop, encode (offline, no Studio)
//   node demo.js cleanup                                    remove any leftover demo scripts from the place
//
// record options: --server <file.luau> (a server-side half), --name NAME, --out DIR (default %TEMP%\demo),
//   --load SECONDS (wait for the game to start, default 90), --max SECONDS (demo length cap, default 120),
//   --fps N (default 30), --keep-raw, --no-focus, --port N, --place-id ID
//
// How a recording runs: the demo file (Luau statements using `Demo`, see DemoKit.luau) is wrapped with DemoKit into a
// LocalScript `__DemoDirector` in StarterPlayerScripts (and an optional Script `__DemoDirectorServer`), the Studio
// window is brought to the front, ffmpeg records the whole desktop, the playtest starts, `[demo:key]` lines from the
// game are forwarded as real key presses, and on `[demo] done` (or the cap) the playtest stops, ffmpeg stops, and the
// scripts are removed whatever happened. DemoKit flashes the game view magenta then green at the start and the end;
// `process` finds those flashes (only pixels that turn magenta and then green are the game view) to trim the clip and to crop it to exactly the game view, so nothing outside the game is ever
// in the output. No flash found means no output: the raw desktop recording is deleted rather than sent anywhere.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");
const bridge = require(path.join(__dirname, "..", "studio", "bridge.js"));

const DIRECTOR = "__DemoDirector";
const SERVER_DIRECTOR = "__DemoDirectorServer";
const SCAN_WIDTH = 320;
const SCAN_HEIGHT = 180;
const SCAN_FPS = 10;
const MAX_BYTES = 24 * 1024 * 1024;

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

const isMarker = (red, green, blue) => red > 230 && green < 40 && blue > 230;
const isSecondMarker = (red, green, blue) => red < 40 && green > 200 && blue < 40;
const MARKER_MIN_SHARE = 0.06;
const MARKER_PHASE_SECONDS = 0.5;
const MARKER_MAX_SECONDS = 1.5;

function markerBlocks(ffmpeg, file) {
  const raw = ffmpegSync(ffmpeg, ["-i", file, "-vf", `fps=${SCAN_FPS},scale=${SCAN_WIDTH}:${SCAN_HEIGHT}`, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], true);
  const frameBytes = SCAN_WIDTH * SCAN_HEIGHT * 3;
  const shares = [];
  for (let offset = 0; offset + frameBytes <= raw.length; offset += frameBytes) {
    let count = 0;
    for (let pixel = offset; pixel < offset + frameBytes; pixel += 3) if (isMarker(raw[pixel], raw[pixel + 1], raw[pixel + 2])) count++;
    shares.push(count / (SCAN_WIDTH * SCAN_HEIGHT));
  }
  const baseline = [...shares].sort((left, right) => left - right)[Math.floor(shares.length / 2)] || 0;
  const flags = shares.map((share) => share > baseline + MARKER_MIN_SHARE);
  const blocks = [];
  for (let index = 0; index < flags.length; index++) {
    if (!flags[index]) continue;
    const last = blocks[blocks.length - 1];
    if (last && last.endFrame === index - 1) last.endFrame = index;
    else blocks.push({ startFrame: index, endFrame: index });
  }
  return blocks
    .map((block) => ({ start: block.startFrame / SCAN_FPS, end: (block.endFrame + 1) / SCAN_FPS }))
    .filter((block) => block.end - block.start <= MARKER_MAX_SECONDS);
}

function grabFrame(ffmpeg, file, atSeconds) {
  return ffmpegSync(ffmpeg, ["-ss", Math.max(0, atSeconds).toFixed(3), "-i", file, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], true);
}

function markerBox(ffmpeg, file, magentaSeconds, greenSeconds, width, height) {
  const frame = grabFrame(ffmpeg, file, magentaSeconds);
  const after = grabFrame(ffmpeg, file, greenSeconds);
  const rows = new Array(height).fill(0);
  const columns = new Array(width).fill(0);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const pixel = (y * width + x) * 3;
      if (!isMarker(frame[pixel], frame[pixel + 1], frame[pixel + 2])) continue;
      if (!(after.length > pixel + 2 && isSecondMarker(after[pixel], after[pixel + 1], after[pixel + 2]))) continue;
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

function processVideo(ffmpeg, rawFile, outFile, log = console.log) {
  const info = probeVideo(ffmpeg, rawFile);
  const blocks = markerBlocks(ffmpeg, rawFile);
  if (!blocks.length) throw new Error("no start marker in the recording: the demo never ran (or the game view was hidden); nothing was produced");
  const first = blocks[0];
  const last = blocks.length > 1 ? blocks[blocks.length - 1] : null;
  const start = first.end + MARKER_PHASE_SECONDS + 0.15;
  const end = last ? Math.max(start + 0.5, last.start - 0.05) : info.seconds;
  const box = markerBox(ffmpeg, rawFile, (first.start + first.end) / 2, first.end + MARKER_PHASE_SECONDS / 2, info.width, info.height);
  if (!box || box.width < 64 || box.height < 64) throw new Error("could not find the game view in the marker frame; nothing was produced");
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
  log(`length   ${duration.toFixed(1)} s, ${(bytes / 1024 / 1024).toFixed(1)} MB, game view ${box.width}x${box.height} at ${box.x},${box.y} of ${info.width}x${info.height}`);
  return { clip: outFile, poster, seconds: duration, bytes, box };
}

async function callTool(port, name, args = {}) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name, arguments: args } }),
    signal: AbortSignal.timeout(60000),
  });
  const body = await response.text();
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (message.error) throw new Error(`${name}: ${JSON.stringify(message.error).slice(0, 300)}`);
  const text = (message.result && message.result.content || []).map((part) => part.text || "").join("\n");
  if (message.result && message.result.isError) throw new Error(`${name}: ${text.slice(0, 300)}`);
  return text;
}

function windowHelper(titleHint, focus) {
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
  $result.minimized = [DemoWindow]::IsIconic($pick.MainWindowHandle)
  if (${focus ? "$true" : "$false"}) {
    if ($result.minimized) { [void][DemoWindow]::ShowWindow($pick.MainWindowHandle, 9) }
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

function directorSource(demoFile) {
  const kit = fs.readFileSync(path.join(__dirname, "DemoKit.luau"), "utf8").replace(/\r\n/g, "\n");
  const body = fs.readFileSync(demoFile, "utf8").replace(/\r\n/g, "\n");
  return `if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
	return
end
local Demo = (function()
${kit}
end)()
Demo._run(function(Demo)
${body}
end)
`;
}

function serverSource(serverFile) {
  const body = fs.readFileSync(serverFile, "utf8").replace(/\r\n/g, "\n");
  return `if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
	return
end
${body}
`;
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

async function install(port, demoFile, serverFile) {
  const parts = [
    ["game:GetService(\"StarterPlayer\").StarterPlayerScripts", "LocalScript", DIRECTOR, directorSource(demoFile)],
  ];
  if (serverFile) parts.push(["game:GetService(\"ServerScriptService\")", "Script", SERVER_DIRECTOR, serverSource(serverFile)]);
  for (const [parent, className, name, source] of parts) {
    const check = await bridge.once(port, `local fn, err = loadstring(${bridge.longString(source)}, "${name}")\nreturn if fn then "" else tostring(err)`);
    if (check) throw new Error(`the demo does not compile: ${check}`);
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

async function record(options) {
  const demoFile = options._[1];
  if (!demoFile || !fs.existsSync(demoFile)) throw new Error("usage: node demo.js record <demo.luau> [--server file.luau] [--name NAME] [--out DIR]");
  const serverFile = typeof options.server === "string" ? options.server : null;
  const ffmpeg = findFfmpeg();
  const config = bridge.readConfig(bridge.findProjectRoot());
  const place = await bridge.resolve({ port: options.port, placeId: options["place-id"] || config.placeId, writes: true });
  const name = typeof options.name === "string" ? options.name : path.basename(demoFile).replace(/\.(client\.)?luau$/i, "");
  const outDir = typeof options.out === "string" ? path.resolve(options.out) : path.join(os.tmpdir(), "demo");
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const rawFile = path.join(outDir, `${name}-${stamp}.raw.mkv`);
  const outFile = path.join(outDir, `${name}-${stamp}.mp4`);
  const loadSeconds = Number(options.load) || 90;
  const maxSeconds = Number(options.max) || 120;
  fs.mkdirSync(outDir, { recursive: true });

  if (!options["no-focus"]) {
    const window = windowHelper(place.name, true);
    if (!window.found) throw new Error("no Roblox Studio window found");
    console.log(`window   "${window.title}"${window.focused === false ? " (could not bring it to the front; keep it visible)" : ""}`);
  }

  let recorder = null;
  let playing = false;
  try {
    await install(place.port, demoFile, serverFile);
    recorder = spawn(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", "-f", "gdigrab", "-framerate", String(Number(options.fps) || 30), "-draw_mouse", "0", "-i", "desktop", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", rawFile], { stdio: ["pipe", "ignore", "pipe"] });
    let recorderError = "";
    recorder.stderr.on("data", (chunk) => (recorderError += chunk));
    await sleep(800);
    if (recorder.exitCode !== null) throw new Error(`ffmpeg could not record the desktop: ${recorderError.slice(-300)}`);

    await callTool(place.port, "start_playtest", { mode: "play" });
    playing = true;
    console.log("playtest started; waiting for the demo");
    const startedAt = Date.now();
    let demoStartedAt = null;
    let keysSent = 0;
    for (;;) {
      await sleep(300);
      const output = await callTool(place.port, "get_playtest_output", {}).catch(() => "");
      if (!demoStartedAt && output.includes("[demo] start")) {
        demoStartedAt = Date.now();
        console.log(`demo started after ${((demoStartedAt - startedAt) / 1000).toFixed(1)} s`);
      }
      const keys = [...output.matchAll(/\[demo:key\] (?:Enum\.KeyCode\.)?(\w+) ([\d.]+)/g)];
      for (; keysSent < keys.length; keysSent++) {
        const [, keyCode, hold] = keys[keysSent];
        await callTool(place.port, "simulate_keyboard_input", { keyCode, action: "tap", duration: Number(hold), target: "client-1" }).catch(() =>
          callTool(place.port, "simulate_keyboard_input", { keyCode, action: "tap", duration: Number(hold) }),
        );
      }
      if (output.includes("[demo] done")) break;
      const errorLine = /\[demo\] error: ([^\n"\\]+)/.exec(output);
      if (errorLine) console.log(`demo error: ${errorLine[1]}`);
      if (!demoStartedAt && Date.now() - startedAt > loadSeconds * 1000) throw new Error(`the demo did not start within ${loadSeconds} s (did the game load? is the character spawning?)`);
      if (demoStartedAt && Date.now() - demoStartedAt > maxSeconds * 1000) {
        console.log(`stopping at the ${maxSeconds} s cap`);
        break;
      }
    }
    await sleep(500);
  } finally {
    if (playing) await callTool(place.port, "stop_playtest", {}).catch((error) => console.log(`could not stop the playtest: ${error.message}`));
    if (recorder && recorder.exitCode === null) {
      recorder.stdin.write("q");
      await new Promise((done) => recorder.on("exit", done));
    }
    await sleep(playing ? 1500 : 0);
    const removed = await bridge.once(place.port, CLEANUP_LUA).catch(() => "?");
    console.log(`cleanup  removed ${removed} demo script(s)`);
  }

  try {
    return processVideo(ffmpeg, rawFile, outFile);
  } finally {
    if (!options["keep-raw"]) fs.rmSync(rawFile, { force: true });
    else console.log(`raw      ${rawFile} (whole desktop; delete it when done)`);
  }
}

async function check() {
  try {
    console.log(`ffmpeg   ${findFfmpeg()}`);
  } catch (error) {
    console.log(`ffmpeg   MISSING: ${error.message}`);
  }
  const found = await bridge.probe();
  console.log(found.length ? found.map((entry) => `studio   port ${entry.port}: placeId ${entry.placeId} "${entry.name}"${entry.running ? " (playtest running)" : ""}`).join("\n") : "studio   no Studio MCP bridge answered");
  const window = windowHelper("", false);
  console.log(window.found ? `window   "${window.title}"${window.minimized ? " (minimized: recording will restore it)" : ""}` : "window   no Roblox Studio window");
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
  if (command === "cleanup") {
    const place = await bridge.resolve({ port: options.port, placeId: options["place-id"] || bridge.readConfig(bridge.findProjectRoot()).placeId, writes: true });
    console.log(`removed ${await bridge.once(place.port, CLEANUP_LUA)} demo script(s)`);
    return;
  }
  console.log("usage: node demo.js check | record <demo.luau> [options] | process <raw> --out <clip.mp4> | cleanup");
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
