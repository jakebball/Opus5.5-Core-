// playerLog.js: the Roblox Player's own logs as the back-channel for live demos (demo.js live), plus the Windows helpers
// that find, restore and end the Player process a live run drove.
//
// The Player writes %LOCALAPPDATA%\Roblox\logs\<version>_<startUTC>_Player_<id>_last.log with the same
// [FLog::CreatorOutput|CreatorWarning|CreatorError] lines as Studio's log (studioLog.parseLine reads them unchanged),
// plus its own session markers, all with UTC timestamps:
//   ! Joining game '<jobId>' place <placeId> at <ip>         -> phase "join" (jobId, placeId)
//   [FLog::SessionTransitionFSM] Entered play session.       -> phase "play"
//   [FLog::UgcExperienceController] ...doTeleport: url ...   -> phase "teleport" (the line's text is dropped: it carries
//                                                              a join ticket, which must never be printed or kept)
//   [FLog::SessionTransitionFSM] Teleported.                 -> phase "teleported"
//   [FLog::SessionTransitionFSM] Tearing down.               -> phase "teardown"
//   Disconnected from server for reason: Player: 285 (...)   -> phase "disconnect" (reason, code). A teleport also logs
//                                                              one (285) between "teleport" and "teleported".
//
// The tray trap (seen 2026-10-07): with Roblox's tray mode on, an idle RobloxPlayerBeta waits in the tray with its own
// log open. A launch starts a second process that writes a ~1 KB log ("WebPlay NoReload with Tray only!"), hands the
// join to the tray process and exits, so the session lands in the tray process's older log. When that session ends the
// process spawns a fresh tray process (a new log) and dies. So the session log is the one that gains a "Joining game"
// line for the test place after the launch, never simply the newest file; watchJoin() finds it.
//
// A log's process: the file name's start time is within a few seconds of the process's StartTime (2.4 s measured), so
// the session's pid is the RobloxPlayerBeta whose StartTime is nearest that time.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const studioLog = require(path.join(__dirname, "..", "studio", "studioLog.js"));

const LOG_DIR = path.join(process.env.LOCALAPPDATA || "", "Roblox", "logs");
const LINE = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z),[\d.]+,[0-9a-f]+,\d+(?:,(\w+))? \[(\w+)::(\w+)\] ?(.*)$/;
const PLAYER_LOG = /_(\d{8}T\d{6}Z)_Player_[0-9A-Fa-f]+_last\.log$/;
const JOIN = /^! Joining game '([0-9A-Fa-f-]+)' place (\d+) at /;
const DISCONNECT = /Disconnected from server for reason: (.*)$/;
const PID_MATCH_MS = 15000;

// What a disconnect code means for a live run (the ones seen or documented; anything else is reported raw).
const DISCONNECT_CODES = {
  267: "kicked by the server (Player:Kick; the demo's own end kick says \"Demo finished\")",
  273: "the same account joined from another device: close Roblox on the phone during live demos",
  277: "lost connection to the server",
  278: "idle kick",
  279: "failed to connect to the server",
  285: "the client left (closed, killed, or mid-teleport)",
};

const withoutCr = (line) => (line.charCodeAt(line.length - 1) === 13 ? line.slice(0, -1) : line);

function disconnectCode(reason) {
  const match = /\b(\d{3})\b/.exec(reason || "");
  return match ? Number(match[1]) : null;
}

function describeDisconnect(code) {
  return DISCONNECT_CODES[code] || "unknown code";
}

// One Player log line -> an entry, or null. Creator output parses exactly as Studio's does.
function parseLine(line) {
  const text = withoutCr(line);
  const match = LINE.exec(text);
  if (!match) return null;
  const [, iso, , , category, message] = match;
  const at = Date.parse(iso);
  const creator = studioLog.parseLine(text);
  if (creator && creator.kind !== "lifecycle") return creator;
  const join = JOIN.exec(message);
  if (join) return { at, kind: "lifecycle", phase: "join", jobId: join[1].toLowerCase(), placeId: join[2], message: `joining ${join[1]} place ${join[2]}` };
  if (category === "SessionTransitionFSM") {
    if (/^Entered play session\b/.test(message)) return { at, kind: "lifecycle", phase: "play", message: "entered play session" };
    if (/^Teleported\b/.test(message)) return { at, kind: "lifecycle", phase: "teleported", message: "teleported" };
    if (/^Tearing down\b/.test(message)) return { at, kind: "lifecycle", phase: "teardown", message: "tearing down" };
    return null;
  }
  if (category === "UgcExperienceController" && /doTeleport: url\b/.test(message)) return { at, kind: "lifecycle", phase: "teleport", message: "doTeleport" };
  const disconnect = DISCONNECT.exec(message);
  if (disconnect) {
    const reason = disconnect[1].slice(0, 200);
    return { at, kind: "lifecycle", phase: "disconnect", reason, code: disconnectCode(reason), message: `disconnected: ${reason}` };
  }
  return null;
}

// Whole lines -> entries; a line with no timestamp continues the previous creator entry (as studioLog.parseLines).
function parseLines(lines, into = [], previous = null) {
  let last = previous;
  for (const raw of lines) {
    const line = withoutCr(raw);
    if (!line) continue;
    if (!LINE.test(line)) {
      if (/^\d{4}-\d\d-\d\dT\d\d:\d\d/.test(line)) last = null;
      else if (last && last.kind !== "lifecycle") last.message += "\n" + line;
      continue;
    }
    const entry = parseLine(line);
    last = entry;
    if (entry) into.push(entry);
  }
  into.lastContext = last;
  return into;
}

function parseText(text) {
  return parseLines(text.split("\n"));
}

// ---------- which log ----------

// The start time a Player log's name carries (ms, UTC), or null.
function logStartTime(file) {
  const match = PLAYER_LOG.exec(path.basename(file));
  if (!match) return null;
  const stamp = match[1];
  return Date.parse(`${stamp.slice(0, 4)}-${stamp.slice(4, 6)}-${stamp.slice(6, 8)}T${stamp.slice(9, 11)}:${stamp.slice(11, 13)}:${stamp.slice(13, 15)}Z`);
}

// Player session logs (CrashHandler logs excluded), newest first: [{ file, size, mtime, startedAt }].
function listLogs(dir = LOG_DIR) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((name) => PLAYER_LOG.test(name))
    .map((name) => {
      const file = path.join(dir, name);
      const stat = fs.statSync(file);
      return { file, size: stat.size, mtime: stat.mtimeMs, startedAt: logStartTime(file) };
    })
    .sort((left, right) => right.mtime - left.mtime);
}

// Sizes of every Player log now, so a watch reads only what is written after the launch.
function snapshot(dir = LOG_DIR) {
  return new Map(listLogs(dir).map((entry) => [entry.file, entry.size]));
}

// Watches every Player log (those in `before` from their snapshot size, new ones from 0) for the first "Joining game"
// line for `placeId`. poll() returns { file, offset, join } once found (offset: where the watch began reading that
// file, so a tail opened there replays the join), otherwise null. Logs that only hand the join to the tray process
// never gain the line, so they are never picked.
function watchJoin(before, placeId, dir = LOG_DIR) {
  const state = new Map();
  return {
    poll() {
      for (const entry of listLogs(dir)) {
        let watch = state.get(entry.file);
        if (!watch) {
          const from = before.has(entry.file) ? before.get(entry.file) : 0;
          watch = { from, offset: from, pending: Buffer.alloc(0) };
          state.set(entry.file, watch);
        }
        if (entry.size < watch.offset) {
          watch.offset = 0;
          watch.from = 0;
          watch.pending = Buffer.alloc(0);
        }
        if (entry.size === watch.offset) continue;
        const bytes = Buffer.concat([watch.pending, studioLog.readRange(entry.file, watch.offset, entry.size - watch.offset)]);
        watch.offset = entry.size;
        const cut = bytes.lastIndexOf(10);
        if (cut < 0) {
          watch.pending = bytes;
          continue;
        }
        watch.pending = bytes.subarray(cut + 1);
        for (const line of bytes.subarray(0, cut).toString("utf8").split("\n")) {
          if (!line.includes("Joining game")) continue;
          const parsed = parseLine(line);
          if (parsed && parsed.phase === "join" && String(parsed.placeId) === String(placeId)) return { file: entry.file, offset: watch.from, join: parsed };
        }
      }
      return null;
    },
  };
}

// Where a log's sessions stand, from its join / play / teardown markers: { active, jobId, placeId, at, joins }.
// active: a session was entered and has not torn down (the process may still have died; check it).
function sessionState(file) {
  const entries = parseText(fs.readFileSync(file, "utf8"));
  let active = false;
  let jobId = null;
  let placeId = null;
  let at = null;
  let joins = 0;
  for (const entry of entries) {
    if (entry.kind !== "lifecycle") continue;
    if (entry.phase === "join") {
      active = true;
      jobId = entry.jobId;
      placeId = entry.placeId;
      at = entry.at;
      joins++;
    } else if (entry.phase === "teardown") {
      active = false;
      at = entry.at;
    }
  }
  return { active, jobId, placeId, at, joins };
}

// Follows one log from `offset`. poll() returns the entries completed since the last poll; tail.joins lists every join
// in order (the lobby, then the reserved server), tail.phases the first time each phase was seen.
function openTail(file, offset = fs.statSync(file).size) {
  let pending = Buffer.alloc(0);
  const tail = {
    file,
    entries: [],
    joins: [],
    phases: {},
    last: null,
    poll() {
      const size = fs.statSync(file).size;
      if (size < offset) throw new Error(`${path.basename(file)} shrank mid-run`);
      if (size === offset) return [];
      const bytes = Buffer.concat([pending, studioLog.readRange(file, offset, size - offset)]);
      offset = size;
      const cut = bytes.lastIndexOf(10);
      if (cut < 0) {
        pending = bytes;
        return [];
      }
      pending = bytes.subarray(cut + 1);
      const fresh = parseLines(bytes.subarray(0, cut).toString("utf8").split("\n"), [], tail.last);
      tail.last = fresh.lastContext;
      for (const entry of fresh) {
        tail.entries.push(entry);
        if (entry.kind !== "lifecycle") continue;
        if (tail.phases[entry.phase] === undefined) tail.phases[entry.phase] = entry.at;
        if (entry.phase === "join") tail.joins.push(entry);
      }
      return fresh;
    },
  };
  return tail;
}

// ---------- launch data ----------

const LAUNCH_DATA_LIMIT = 200;
const NAME_PATTERN = /^[A-Za-z0-9_]+$/;
const NONCE_PATTERN = /^[A-Za-z0-9]{6,16}$/;
const STAMP_PATTERN = /^[A-Za-z0-9]{1,32}$/;

// The launchData a live run passes: compact JSON {"d":name,"n":nonce,"b":stamp[,"x":"1"]}, every value matching the
// character classes the game's LiveDemo.parseLaunchData accepts, at most 200 bytes. Throws rather than send anything
// the game would refuse.
function encodeLaunchData({ demo, nonce, stamp, direct = false }) {
  if (!NAME_PATTERN.test(demo || "") || demo.length > 64) throw new Error(`demo name "${demo}" must be letters, digits and _ (at most 64)`);
  if (!NONCE_PATTERN.test(nonce || "")) throw new Error(`nonce "${nonce}" must be 6-16 letters or digits`);
  if (!STAMP_PATTERN.test(stamp || "")) throw new Error(`build stamp "${stamp}" must be 1-32 letters or digits`);
  const data = { d: demo, n: nonce, b: stamp };
  if (direct) data.x = "1";
  const text = JSON.stringify(data);
  if (Buffer.byteLength(text, "utf8") > LAUNCH_DATA_LIMIT) throw new Error(`launchData is ${Buffer.byteLength(text, "utf8")} bytes; Roblox allows ${LAUNCH_DATA_LIMIT}`);
  return text;
}

// The deep link (Roblox's documented experiences/start form). Never roblox-player:, never a ticket or cookie.
function deepLink(placeId, launchData = null) {
  if (!/^\d+$/.test(String(placeId))) throw new Error(`placeId ${placeId} is not a number`);
  const base = `roblox://experiences/start?placeId=${placeId}`;
  return launchData === null ? base : `${base}&launchData=${encodeURIComponent(launchData)}`;
}

// ---------- Windows ----------

function powershell(script) {
  const file = path.join(os.tmpdir(), `demo-live-${process.pid}-${Date.now().toString(36)}.ps1`);
  fs.writeFileSync(file, script);
  try {
    const result = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", file], { encoding: "utf8", timeout: 30000 });
    return { stdout: String(result.stdout || ""), stderr: String(result.stderr || ""), status: result.status };
  } finally {
    fs.rmSync(file, { force: true });
  }
}

function lastJson(text, fallback) {
  try {
    return JSON.parse(text.trim().split(/\r?\n/).pop());
  } catch {
    return fallback;
  }
}

const WINDOW_TYPE = `
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LiveDemoWindow {
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int command);
}
"@
`;

// Every RobloxPlayerBeta now: [{ pid, startedAt (ms UTC), hwnd, title, minimized }].
function playerProcesses() {
  const result = powershell(`${WINDOW_TYPE}
$list = @(Get-Process -Name RobloxPlayerBeta -ErrorAction SilentlyContinue | ForEach-Object {
  @{ pid = $_.Id; startedAt = [int64](($_.StartTime.ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds); hwnd = [int64]$_.MainWindowHandle; title = $_.MainWindowTitle; minimized = ($_.MainWindowHandle -ne 0 -and [LiveDemoWindow]::IsIconic($_.MainWindowHandle)) }
})
ConvertTo-Json -Compress -InputObject $list`);
  const list = lastJson(result.stdout, []);
  return Array.isArray(list) ? list : [list];
}

// The process that writes `file`: the RobloxPlayerBeta whose StartTime is nearest the log name's start, within 15 s.
function pidForLog(file, processes = playerProcesses()) {
  const startedAt = logStartTime(file);
  if (startedAt === null) return null;
  let best = null;
  for (const entry of processes) {
    const gap = Math.abs(entry.startedAt - startedAt);
    if (gap <= PID_MATCH_MS && (!best || gap < best.gap)) best = { ...entry, gap };
  }
  return best;
}

// Restores a minimised window (window capture gets no frames from one); returns whether it was minimised.
function restoreWindow(hwnd) {
  const result = powershell(`${WINDOW_TYPE}
$handle = [IntPtr]${Number(hwnd)}
$minimized = [LiveDemoWindow]::IsIconic($handle)
if ($minimized) { [void][LiveDemoWindow]::ShowWindow($handle, 9) }
@{ minimized = $minimized } | ConvertTo-Json -Compress`);
  return Boolean(lastJson(result.stdout, {}).minimized);
}

// The PC is locked (or at the sign-in screen) while LogonUI.exe runs.
function isLocked() {
  if (process.platform !== "win32") return false;
  const result = spawnSync("tasklist", ["/FI", "IMAGENAME eq LogonUI.exe", "/FO", "CSV", "/NH"], { encoding: "utf8" });
  return /"LogonUI\.exe"/i.test(String(result.stdout || ""));
}

function isAlive(pid) {
  if (!pid) return false;
  const result = spawnSync("tasklist", ["/FI", `PID eq ${Number(pid)}`, "/FO", "CSV", "/NH"], { encoding: "utf8" });
  return new RegExp(`"RobloxPlayerBeta\\.exe","${Number(pid)}"`, "i").test(String(result.stdout || ""));
}

// Ends one RobloxPlayerBeta by pid, and only that: refuses any other image name.
function killPlayer(pid) {
  if (!isAlive(pid)) return false;
  const result = spawnSync("taskkill", ["/PID", String(Number(pid)), "/F"], { encoding: "utf8" });
  return result.status === 0;
}

// The installed Player: { exe, handler } (the roblox: protocol's open command), or nulls.
function playerInstall() {
  const versions = path.join(process.env.LOCALAPPDATA || "", "Roblox", "Versions");
  const result = powershell(`(Get-ItemProperty "Registry::HKEY_CURRENT_USER\\Software\\Classes\\roblox\\shell\\open\\command" -ErrorAction SilentlyContinue).'(default)'`);
  const handler = result.stdout.trim() || null;
  const fromHandler = handler && /"([^"]+RobloxPlayerBeta\.exe)"/i.exec(handler);
  let exe = fromHandler && fs.existsSync(fromHandler[1]) ? fromHandler[1] : null;
  if (!exe && fs.existsSync(versions)) {
    for (const folder of fs.readdirSync(versions)) {
      const candidate = path.join(versions, folder, "RobloxPlayerBeta.exe");
      if (fs.existsSync(candidate)) exe = candidate;
    }
  }
  return { exe, handler };
}

// Only links of the shape deepLink() builds: the experiences/start form, a numeric place, URL-encoded launch data.
function isOwnLink(url) {
  return /^roblox:\/\/experiences\/start\?placeId=\d+(&launchData=[A-Za-z0-9%._~-]*)?$/.test(url);
}

// Opens a deep link through the shell's roblox: handler, as a click on a link would. Returns at once.
function openLink(url) {
  if (!isOwnLink(url)) throw new Error(`refusing to open ${url}: not a roblox://experiences/start link this tool builds`);
  const result = powershell(`Start-Process '${url}'`);
  if (result.status !== 0) throw new Error(`Start-Process failed: ${result.stderr.slice(0, 300)}`);
}

module.exports = {
  LOG_DIR,
  DISCONNECT_CODES,
  LAUNCH_DATA_LIMIT,
  parseLine,
  parseLines,
  parseText,
  disconnectCode,
  describeDisconnect,
  logStartTime,
  listLogs,
  snapshot,
  watchJoin,
  sessionState,
  openTail,
  encodeLaunchData,
  deepLink,
  playerProcesses,
  pidForLog,
  restoreWindow,
  isLocked,
  isAlive,
  killPlayer,
  playerInstall,
  isOwnLink,
  openLink,
};
