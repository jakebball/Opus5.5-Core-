// bridge.js: the one way Node tools talk to Roblox Studio, over the Studio MCP plugin's HTTP bridge
// (boshyxd/robloxstudio-mcp, JSON-RPC `tools/call` -> `execute_luau` on http://127.0.0.1:<port>/mcp).
//
// What every caller gets for free:
//   - port discovery: the bridge answers on one of 58741-58750 and the port moves between Studio restarts; with several
//     Studios open each has its own. resolve() probes them and picks the one whose open place matches the project's
//     placeId (studio.json), so a write never lands in the wrong place.
//   - once(): the bridge hands a still-running call to the plugin again on every 0.5 s poll, so a call that yields runs
//     once per half second it lasts (a 3 s CreateAssetAsync ran six times). Every call carries a token; a repeat
//     delivery waits for the first run and returns its result instead of running the code again.
//   - deferred(): for runs longer than the bridge's ~30 s call timeout. The code starts inside task.defer under a token
//     and is polled until it finishes, so long builds complete and report and never start twice.
//   - a playtest guard: writers refuse while a playtest runs.
const fs = require("fs");
const path = require("path");

const PORTS = Array.from({ length: 10 }, (_, index) => 58741 + index);
let serial = 0;

function longString(text) {
  let level = 1;
  while (text.includes("]" + "=".repeat(level) + "]")) level++;
  const fence = "=".repeat(level);
  return `[${fence}[\n${text}]${fence}]`;
}

function token() {
  return `${process.pid}-${Date.now()}-${++serial}-${Math.random().toString(36).slice(2, 8)}`;
}

function onceLua(code) {
  return `local __token = "${token()}"
_G.StudioBridgeCalls = _G.StudioBridgeCalls or {}
local __state = _G.StudioBridgeCalls[__token]
if __state then
	while not __state.done do
		task.wait(0.05)
	end
	if __state.failed then
		error(__state.result, 0)
	end
	return __state.result
end
__state = { done = false }
_G.StudioBridgeCalls[__token] = __state
local __ok, __result = pcall(function()
${code}
end)
__state.done, __state.failed, __state.result = true, not __ok, __result
task.delay(120, function()
	_G.StudioBridgeCalls[__token] = nil
end)
if not __ok then
	error(__result, 0)
end
return __result`;
}

async function rawCall(port, code, timeoutMs = 300000) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name: "execute_luau", arguments: { code } } }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${body.slice(0, 200)}`);
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (!message.result) throw new Error(`the bridge answered without a result: ${JSON.stringify(message.error || message).slice(0, 400)}`);
  const inner = message.result.content && message.result.content[0] && message.result.content[0].text;
  let reply;
  try {
    reply = JSON.parse(inner);
  } catch {
    throw new Error(`unexpected tool reply: ${String(inner).slice(0, 400)}`);
  }
  if (reply.success === false) throw new Error(reply.error || reply.message || inner);
  return reply.returnValue;
}

function once(port, code, timeoutMs) {
  return rawCall(port, onceLua(code), timeoutMs);
}

const PROBE = `return game:GetService("HttpService"):JSONEncode({
	placeId = game.PlaceId,
	name = game.Name,
	running = game:GetService("RunService"):IsRunning(),
})`;

async function probe() {
  const found = [];
  await Promise.all(
    PORTS.map(async (port) => {
      try {
        found.push({ port, ...JSON.parse(await rawCall(port, PROBE, 6000)) });
      } catch {}
    }),
  );
  return found.sort((left, right) => left.port - right.port);
}

function findProjectRoot(start = process.cwd()) {
  let directory = path.resolve(start);
  for (;;) {
    if (fs.existsSync(path.join(directory, "studio.json"))) return directory;
    const parent = path.dirname(directory);
    if (parent === directory) return path.resolve(start);
    directory = parent;
  }
}

function readConfig(root) {
  const file = path.join(root, "studio.json");
  if (!fs.existsSync(file)) return {};
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

// Picks the bridge port: --port wins; otherwise the one Studio whose open place is the project's placeId; otherwise the
// only Studio that answers. Refuses ambiguity instead of guessing, and refuses a playtest when the caller writes.
async function resolve({ port, placeId, writes = false } = {}) {
  let place;
  if (port) {
    place = { port: Number(port), ...JSON.parse(await rawCall(Number(port), PROBE, 8000)) };
  } else {
    const found = await probe();
    if (!found.length) throw new Error("no Studio MCP bridge answered on 58741-58750: open the place in Studio and connect the MCP plugin");
    const matching = placeId ? found.filter((entry) => String(entry.placeId) === String(placeId)) : found;
    if (!matching.length) throw new Error(`no open Studio has placeId ${placeId}; open: ${found.map((entry) => `${entry.port}=${entry.placeId} "${entry.name}"`).join(", ")}`);
    const places = new Set(matching.map((entry) => String(entry.placeId)));
    if (places.size > 1) throw new Error(`several Studios answer (${matching.map((entry) => `${entry.port}=${entry.placeId}`).join(", ")}); pass --port or set placeId in studio.json`);
    place = matching[0];
  }
  if (placeId && String(place.placeId) !== String(placeId)) throw new Error(`port ${place.port} has placeId ${place.placeId} ("${place.name}") open, not ${placeId}; refusing`);
  if (writes && place.running) throw new Error("a playtest is running; stop it first (writes go to the Edit datamodel)");
  return place;
}

function sleep(milliseconds) {
  return new Promise((done) => setTimeout(done, milliseconds));
}

async function patiently(port, code, limitMs) {
  const deadline = Date.now() + limitMs;
  for (;;) {
    try {
      return await rawCall(port, code, 60000);
    } catch (error) {
      if (!/timeout|without a result|aborted/i.test(error.message) || Date.now() > deadline) throw error;
      await sleep(1500);
    }
  }
}

async function deferred(port, code) {
  const id = token();
  const start = `local __results = _G.StudioBridgeRuns or {}
_G.StudioBridgeRuns = __results
if __results["${id}"] == nil then
	__results["${id}"] = { done = false }
	task.defer(function()
		local ok, value = pcall(function()
${code}
		end)
		__results["${id}"] = { done = true, ok = ok, value = tostring(value) }
	end)
end
return "started"`;
  const poll = `local entry = (_G.StudioBridgeRuns or {})["${id}"]
if not entry then return "missing" end
if not entry.done then return "running" end
_G.StudioBridgeRuns["${id}"] = nil
return game:GetService("HttpService"):JSONEncode(entry)`;
  await patiently(port, start, 120000);
  for (;;) {
    await sleep(1500);
    const reply = await patiently(port, poll, 900000);
    if (reply === "running") continue;
    if (reply === "missing") throw new Error("the deferred run vanished from _G (did Studio restart or a playtest start?)");
    const entry = JSON.parse(reply);
    if (!entry.ok) throw new Error(entry.value);
    return entry.value;
  }
}

function takeFlag(argv, name, hasValue = true) {
  const index = argv.indexOf(`--${name}`);
  if (index < 0) return undefined;
  const value = hasValue ? argv[index + 1] : true;
  argv.splice(index, hasValue ? 2 : 1);
  return value;
}

module.exports = { PORTS, longString, rawCall, once, probe, resolve, deferred, findProjectRoot, readConfig, takeFlag };
