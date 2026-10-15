// playtest.js: starting, following and ending a Studio playtest from Node, honestly. Shared by /demo and /perfbudget.
//
// Why it exists (2026-10-07): the MCP's start_playtest answered "A test is already running" as plain text that read as
// success, its stop_playtest (a warn relayed to a listener in the play server) left a test running for 9 minutes, and
// get_playtest_output never sees client prints. So:
//   - callTool() throws on any error answer, including {error} / {success:false} JSON in a text reply;
//   - the play state and every print come from Studio's own session log (studioLog.js);
//   - the test is ended from inside the game: serverDirectorSource() builds a server Script that calls
//     StudioTestService:EndTest() when the client says it is done, or when its own watchdog runs out;
//   - ensureStopped() waits for StopPlaySoloEnd in the log, falls back to stop_playtest, and throws loudly if the test
//     is still alive after that.
const path = require("path");
const studioLog = require(path.join(__dirname, "studioLog.js"));
const bridge = require(path.join(__dirname, "bridge.js"));

const REMOTE = "__PlaytestDirector";
const START_SEEN_MS = 10000;
const STOP_WAIT_MS = 15000;
const POLL_MS = 250;

function sleep(milliseconds) {
  return new Promise((done) => setTimeout(done, milliseconds));
}

function nonce() {
  return Math.random().toString(36).slice(2, 8) + Date.now().toString(36).slice(-4);
}

// An MCP tool call that fails loudly: JSON-RPC errors, isError results, and a text answer that is JSON carrying
// `error` or `success: false` all throw.
async function callTool(port, name, args = {}, timeoutMs = 60000) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name, arguments: args } }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`${name}: HTTP ${response.status}: ${body.slice(0, 300)}`);
  return toolText(name, body);
}

// The text of a tools/call reply, or an Error for any failure in it (split out so it can be tested offline).
function toolText(name, body) {
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (message.error) throw new Error(`${name}: ${JSON.stringify(message.error).slice(0, 300)}`);
  const text = ((message.result && message.result.content) || []).map((part) => part.text || "").join("\n");
  if (message.result && message.result.isError) throw new Error(`${name}: ${text.slice(0, 300)}`);
  let reply = null;
  try {
    reply = JSON.parse(text);
  } catch {}
  if (reply && typeof reply === "object") {
    if (reply.error) throw new Error(`${name}: ${typeof reply.error === "string" ? reply.error : JSON.stringify(reply.error)}`);
    if (reply.success === false) throw new Error(`${name}: ${reply.message || text.slice(0, 300)}`);
  }
  if (/^\s*(error|failed)\b/i.test(text)) throw new Error(`${name}: ${text.slice(0, 300)}`);
  return text;
}

// The session log of the Studio behind `port`.
function findLog(port) {
  return studioLog.findLog({ port, run: (code) => bridge.rawCall(port, code, 10000) });
}

// Refuses when the log shows a playtest; otherwise opens the tail that will hold every line of the coming test. Keep the
// tail even if launch() throws: ensureStopped(tail) is the cleanup either way.
function prepare(logFile) {
  const state = studioLog.playState(logFile);
  if (state.running) throw new Error(`Studio's log shows a playtest ${state.phase === "stopping" ? "still stopping" : "running"} (${state.phase} at ${new Date(state.at).toISOString()}); stop it first`);
  return studioLog.openTail(logFile);
}

// Starts the playtest and requires a fresh initiatePlaySolo in the log within 10 s.
// The plugin's start_playtest keeps its own testRunning flag, cleared only when its ExecutePlayModeAsync call returns; a
// test ended any other way (EndTest from the game, the Stop button) can leave it stuck on "A test is already running"
// (seen 2026-10-07). prepare() has already checked the log says nothing runs, so that answer is stale: start Play
// directly instead, spawned so execute_luau returns at once (a yielding call would be re-delivered by the bridge).
const DIRECT_LAUNCH = (mode) => `local StudioTestService = game:GetService("StudioTestService")
task.spawn(function()
	pcall(function()
		${mode === "run" ? "StudioTestService:ExecuteRunModeAsync({})" : "StudioTestService:ExecutePlayModeAsync({})"}
	end)
end)
return "launched"`;

async function launch(port, tail, { mode = "play" } = {}) {
  try {
    await callTool(port, "start_playtest", { mode });
  } catch (error) {
    if (!/already running/i.test(error.message)) throw error;
    console.log("studio   the plugin's start flag is stale (the log shows no playtest); starting Play directly");
    await bridge.once(port, DIRECT_LAUNCH(mode));
  }
  const deadline = Date.now() + START_SEEN_MS;
  while (tail.phases.start === undefined) {
    if (Date.now() > deadline) throw new Error(`start_playtest answered but Studio's log shows no initiatePlaySolo within ${START_SEEN_MS / 1000} s`);
    await sleep(POLL_MS);
    tail.poll();
  }
  return tail;
}

// Waits for StopPlaySoloEnd in the tail; true if it came within `ms`.
async function waitStopped(tail, ms) {
  const deadline = Date.now() + ms;
  for (;;) {
    tail.poll();
    if (tail.phases.stopped !== undefined) return true;
    if (Date.now() > deadline) return false;
    await sleep(POLL_MS);
  }
}

// After the game was told to end itself: wait for StopPlaySoloEnd; if it does not come, call stop_playtest and wait
// again; if the log still shows the test alive, throw. `log` prints progress.
async function ensureStopped(port, tail, { waitMs = STOP_WAIT_MS, log = console.log } = {}) {
  if (tail.phases.start === undefined) {
    // launch failed or is late: give a late start the chance to show, then make sure nothing is left running
    const deadline = Date.now() + waitMs;
    while (tail.phases.start === undefined && Date.now() < deadline) {
      await sleep(POLL_MS);
      tail.poll();
    }
    if (tail.phases.start === undefined) {
      await callTool(port, "stop_playtest", {}, 20000).catch(() => {});
      if (!studioLog.playState(tail.file).running) return "never started";
    }
  }
  if (await waitStopped(tail, waitMs)) return "game";
  log(`playtest still running ${waitMs / 1000} s after the end; calling stop_playtest`);
  await callTool(port, "stop_playtest", {}, 20000).catch((error) => log(`stop_playtest: ${error.message}`));
  if (await waitStopped(tail, STOP_WAIT_MS)) return "stop_playtest";
  const state = studioLog.playState(tail.file);
  if (!state.running) return "log";
  throw new Error(
    `THE PLAYTEST IS STILL RUNNING (last log marker: ${state.phase} at ${new Date(state.at).toISOString()}). ` +
      "Stop it in Studio (Stop button or Shift+F5) before anything else writes to the place.",
  );
}

// A server Script that ends the test from inside the game. The client fires ReplicatedStorage.__PlaytestDirector with
// "begin" when its timed part starts and "done" when it finishes; the director calls StudioTestService:EndTest
// (the call the MCP plugin's own stop listener uses) on "done", if "begin" never arrives within `loadSeconds`, or
// `maxSeconds` after "begin". `body` (optional Luau) runs alongside, for a demo's server half, with `context`
// ({ player, nonce, log }) in scope as in a live demo's server module. Prints go out as "[<tag>:<nonce>] server ...".
function serverDirectorSource({ tag, id, loadSeconds, maxSeconds, body = "" }) {
  return `if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local PREFIX = "[${tag}:${id}] server "
local LOAD_SECONDS = ${Number(loadSeconds)}
local MAX_SECONDS = ${Number(maxSeconds)}

local remote = Instance.new("RemoteEvent")
remote.Name = "${REMOTE}"
remote:SetAttribute("Id", "${id}")
remote.Parent = ReplicatedStorage

local ended = false
local function endTest(reason)
	if ended then
		return
	end
	ended = true
	print(PREFIX .. "ending the test: " .. reason)
	local ok, failure = pcall(function()
		StudioTestService:EndTest(reason)
	end)
	if not ok then
		warn(PREFIX .. "EndTest failed: " .. tostring(failure))
	end
end

local begun = false
remote.OnServerEvent:Connect(function(_, kind)
	if kind == "begin" and not begun then
		begun = true
		task.delay(MAX_SECONDS, endTest, "max")
	elseif kind == "done" then
		task.delay(0.5, endTest, "done")
	end
end)
task.delay(LOAD_SECONDS, function()
	if not begun then
		endTest("load timeout")
	end
end)
print(PREFIX .. "ready")

-- the same context a live demo's server body gets (demo.js live): context.player (the first player, waited for),
-- context.nonce, context.log(text). Bodies that use Players:GetPlayers()[1] themselves keep working.
local context = setmetatable({
	nonce = "${id}",
	log = function(text)
		print(PREFIX .. tostring(text))
	end,
}, {
	__index = function(_, key)
		if key == "player" then
			local Players = game:GetService("Players")
			return Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
		end
		return nil
	end,
})

task.spawn(function()
	local ok, failure = pcall(function(context)
${body}
	end, context)
	if not ok then
		warn(PREFIX .. "error: " .. tostring(failure))
	end
end)
`;
}

// Luau for the client: tell the server director "begin" or "done" (no-op if there is none).
const CLIENT_SIGNAL_LUA = `local function __signalDirector(kind)
	local remote = game:GetService("ReplicatedStorage"):WaitForChild("${REMOTE}", 15)
	if remote then
		remote:FireServer(kind)
	end
end`;

module.exports = { REMOTE, CLIENT_SIGNAL_LUA, sleep, nonce, callTool, toolText, findLog, prepare, launch, waitStopped, ensureStopped, serverDirectorSource };
