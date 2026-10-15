// studioLog.js: Roblox Studio's own session log as the back-channel for playtests.
//
// Studio writes every print/warn/error from the Edit, server and client DataModels to
// %LOCALAPPDATA%\Roblox\logs\<version>_<startUTC>_Studio_<id>_last.log as [FLog::CreatorOutput|CreatorWarning|
// CreatorError] lines, plus playtest lifecycle markers, all with UTC timestamps. The MCP plugin's get_playtest_output
// only sees the Edit DataModel's LogService (never client prints), so tools that need to follow a playtest read this
// instead:
//
//   const studioLog = require(".../studio/studioLog.js");
//   const file = await studioLog.findLog({ port, run: (code) => bridge.rawCall(port, code, 10000) });
//   studioLog.playState(file)              -> { running, phase, at } from the last lifecycle marker
//   const tail = studioLog.openTail(file)  // remembers EOF now; tail.poll() returns entries written since
//
// Entries: { at (ms since epoch, UTC), kind: "output"|"warning"|"error"|"lifecycle", message, phase? }.
// Lifecycle phases, in order: start (initiatePlaySolo), success (PlaySoloSuccess), playable (PlaySoloPlayableTotalTime),
// stopping (stopPlaySoloImpl), stopped (StopPlaySoloEnd).
// Limits seen 2026-10-07: a logged line is cut at ~1020 bytes (a print longer than ~940 characters loses its tail), and
// a multi-line print continues on lines without a timestamp, which are joined back onto their entry here.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const LOG_DIR = path.join(process.env.LOCALAPPDATA || "", "Roblox", "logs");
const LINE = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z),[\d.]+,[0-9a-f]+,\d+(?:,(\w+))? \[(\w+)::(\w+)\] ?(.*)$/;
const CREATOR = { CreatorOutput: "output", CreatorWarning: "warning", CreatorError: "error" };
const STRIP = { warning: "Warning: ", error: "Error: " };
const LIFECYCLE = [
  [/^initiatePlaySolo\b/, "start"],
  [/reset in PlaySoloSuccess\b/, "success"],
  [/^PlaySoloPlayableTotalTime\b/, "playable"],
  [/^stopPlaySoloImpl\b/, "stopping"],
  [/^StopPlaySoloEnd\b/, "stopped"],
];
// a start or stop that never finished is only trusted for this long (a failed start must not block writes forever)
const STALE_TRANSITION_MS = 3 * 60 * 1000;

const withoutCr = (line) => (line.charCodeAt(line.length - 1) === 13 ? line.slice(0, -1) : line);

// One log line -> an entry, or null for lines that are neither creator output nor a lifecycle marker.
function parseLine(line) {
  const match = LINE.exec(withoutCr(line));
  if (!match) return null;
  const [, iso, , , category, message] = match;
  const at = Date.parse(iso);
  const kind = CREATOR[category];
  if (kind) {
    const strip = STRIP[kind];
    return { at, kind, message: strip && message.startsWith(strip) ? message.slice(strip.length) : message };
  }
  for (const [pattern, phase] of LIFECYCLE) if (pattern.test(message)) return { at, kind: "lifecycle", phase, message };
  return null;
}

// Whole lines -> entries; a line with no timestamp continues the previous creator entry (multi-line prints).
// `previous` is the entry a leading continuation line belongs to (the last one of an earlier read); the returned array
// carries `lastContext` to pass as `previous` next time.
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

function runningStudioPids() {
  if (process.platform !== "win32") return [];
  const result = spawnSync("tasklist", ["/FI", "IMAGENAME eq RobloxStudioBeta.exe", "/FO", "CSV", "/NH"], { encoding: "utf8" });
  return [...String(result.stdout || "").matchAll(/"RobloxStudioBeta\.exe","(\d+)"/g)].map((match) => Number(match[1]));
}

function readRange(file, start, length) {
  const handle = fs.openSync(file, "r");
  try {
    const buffer = Buffer.alloc(length);
    const read = fs.readSync(handle, buffer, 0, length, start);
    return buffer.subarray(0, read);
  } finally {
    fs.closeSync(handle);
  }
}

// The Studio process that writes a log names itself near the top ("... for process '25348' ...").
function logPid(file) {
  const head = readRange(file, 0, 256 * 1024).toString("utf8");
  const match = /for process '(\d+)'/.exec(head);
  return match ? Number(match[1]) : null;
}

// Logs of Studios running now, newest first: [{ file, pid, mtime }].
function candidates(dir = LOG_DIR) {
  if (!fs.existsSync(dir)) return [];
  const pids = new Set(runningStudioPids());
  return fs
    .readdirSync(dir)
    .filter((name) => /_Studio_[0-9A-Za-z]+_last\.log$/.test(name))
    .map((name) => {
      const file = path.join(dir, name);
      return { file, mtime: fs.statSync(file).mtimeMs };
    })
    .sort((left, right) => right.mtime - left.mtime)
    .slice(0, 12)
    .map((entry) => ({ ...entry, pid: logPid(entry.file) }))
    .filter((entry) => entry.pid !== null && pids.has(entry.pid));
}

const located = new Map();

// The log of the Studio behind a bridge port. One running Studio: its log. Several: print a token through the bridge
// (Edit DataModel, harmless) and take the log it lands in. `run(code)` executes Luau through that port.
async function findLog({ port, run, dir = LOG_DIR, timeoutMs = 6000 } = {}) {
  if (port && located.has(port) && fs.existsSync(located.get(port))) return located.get(port);
  const found = candidates(dir);
  if (!found.length) throw new Error(`no Studio session log for a running Studio in ${dir}`);
  if (found.length === 1 || !run) {
    if (found.length > 1) throw new Error(`${found.length} Studios are running and no bridge was given to tell their logs apart`);
    if (port) located.set(port, found[0].file);
    return found[0].file;
  }
  const token = `[studiolog:${process.pid}-${Date.now().toString(36)}]`;
  const sizes = new Map(found.map((entry) => [entry.file, fs.statSync(entry.file).size]));
  await run(`print("${token}")\nreturn "ok"`);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (const entry of found) {
      const size = fs.statSync(entry.file).size;
      const from = sizes.get(entry.file);
      if (size > from && readRange(entry.file, from, size - from).includes(token)) {
        if (port) located.set(port, entry.file);
        return entry.file;
      }
    }
    await new Promise((done) => setTimeout(done, 250));
  }
  throw new Error(`the bridge's print never reached any of ${found.length} Studio logs`);
}

// ---------- play state ----------

// The last lifecycle marker in the log, scanning back from the end in chunks. running is true from initiatePlaySolo
// until StopPlaySoloEnd; an unfinished start or stop older than STALE_TRANSITION_MS is reported as stale, not running.
function playState(file, now = Date.now()) {
  const size = fs.statSync(file).size;
  const CHUNK = 4 * 1024 * 1024;
  let end = size;
  while (end > 0) {
    const start = Math.max(0, end - CHUNK);
    // overlap so a line split across chunks is seen whole in the next (earlier) read
    const text = readRange(file, start, Math.min(size, end + 2048) - start).toString("utf8");
    const lines = text.split("\n");
    if (start > 0) lines.shift();
    for (let index = lines.length - 1; index >= 0; index--) {
      if (!lines[index].includes("PlaySolo")) continue;
      const entry = parseLine(lines[index]);
      if (!entry || entry.kind !== "lifecycle") continue;
      const settled = entry.phase === "success" || entry.phase === "playable";
      const transition = entry.phase === "start" || entry.phase === "stopping";
      const stale = transition && now - entry.at > STALE_TRANSITION_MS;
      return { running: settled || (transition && !stale), phase: entry.phase, at: entry.at, stale };
    }
    end = start;
  }
  return { running: false, phase: null, at: null, stale: false };
}

// ---------- tail ----------

// Follows the log from its end at the time of the call. poll() returns the entries completed since the last poll
// (a half-written last line waits for the next poll); tail.entries keeps them all, tail.phases the first time each
// lifecycle phase was seen.
function openTail(file) {
  let offset = fs.statSync(file).size;
  let pending = Buffer.alloc(0);
  const tail = {
    file,
    startedAt: Date.now(),
    entries: [],
    phases: {},
    last: null,
    poll() {
      const size = fs.statSync(file).size;
      if (size < offset) throw new Error(`${path.basename(file)} shrank: Studio restarted mid-run`);
      if (size === offset) return [];
      const bytes = Buffer.concat([pending, readRange(file, offset, size - offset)]);
      offset = size;
      const cut = bytes.lastIndexOf(10);
      if (cut < 0) {
        pending = bytes;
        return [];
      }
      pending = bytes.subarray(cut + 1);
      // a continuation line at the very start of this read belongs to the previous poll's last entry
      const fresh = parseLines(bytes.subarray(0, cut).toString("utf8").split("\n"), [], tail.last);
      tail.last = fresh.lastContext;
      for (const entry of fresh) {
        tail.entries.push(entry);
        if (entry.kind === "lifecycle" && tail.phases[entry.phase] === undefined) tail.phases[entry.phase] = entry.at;
      }
      return fresh;
    },
  };
  return tail;
}

module.exports = { LOG_DIR, parseLine, parseLines, parseText, runningStudioPids, logPid, candidates, findLog, playState, openTail, readRange };
