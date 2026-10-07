#!/usr/bin/env node
// meshtools.js: installs the vendored robloxMeshTools kit into the Studio place the Studio MCP plugin is attached
// to, by calling the MCP server's execute_luau directly over HTTP (POST /mcp, a bare JSON-RPC tools/call).
// That keeps a ~50 KB payload out of the chat. The HTTP path passes backslashes through intact (tested), but the
// `emit` fallback is pasted through the execute_luau tool, which unescapes them, so every backslash in the kit
// travels as a sentinel the installer restores in-engine and neither path can corrupt a literal.
//
//   node meshtools.js probe                                  ports that answer, and the place each has open
//   node meshtools.js install  --port N --place-id ID [--with techniques,examples|none] [--root ModelKit] [--force]
//   node meshtools.js selftest --port N [--with ...]         full install + verify + preview smoke build into an
//                                                            UNPARENTED folder: proves the payload, changes nothing
//   node meshtools.js verify   --port N [--with ...] [--root ModelKit]
//   node meshtools.js emit     [--with ...] [--root ModelKit] [--verify-only] --out file.luau   (paste fallback)
//   node meshtools.js run      --port N --file piece.luau    run any Luau file through execute_luau
//
// No npm packages; Node 18+ (global fetch).
const fs = require("fs");
const path = require("path");

const VENDOR = path.join(__dirname, "vendor", "robloxMeshTools");
const COMMIT = (fs.readFileSync(path.join(VENDOR, "VENDORED.md"), "utf8").match(/Commit: ([0-9a-f]{7,40})/) || [])[1];
const SHORT = COMMIT ? COMMIT.slice(0, 7) : "unknown";
const PORTS = Array.from({ length: 10 }, (_, i) => 58741 + i);
const BS = "@@MT_BACKSLASH@@";

// [group, folder under the kit root ("" = top), vendored source file]
const FILES = [
  ["core", "", "kit/MeshKit.luau"],
  ["core", "", "kit/BuildLib.luau"],
  ["core", "", "kit/Shapes.luau"],
  ["core", "", "kit/Remesh.luau"],
  ["core", "", "kit/CheckUploads.luau"],
  ["techniques", "", "techniques/GeodesicDome.luau"],
  ["techniques", "", "techniques/PaneTexture.luau"],
  ["examples", "", "examples/Demo.luau"],
  ["examples", "TemplateSrc", "examples/templates/Tank.luau"],
  ["examples", "TemplateSrc", "examples/templates/Console.luau"],
  ["examples", "TemplateSrc", "examples/templates/Crate.luau"],
  ["examples", "Pieces", "examples/pieces/Platform.luau"],
  ["examples", "Pieces", "examples/pieces/ToothedDoor.luau"],
];

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) out[key] = true;
      else out[key] = argv[++i];
    } else out._.push(a);
  }
  return out;
}

function groupsFrom(args) {
  const extra = typeof args.with === "string" ? args.with.split(",").map((s) => s.trim()).filter(Boolean) : ["techniques"];
  const groups = new Set(["core"]);
  for (const g of extra) {
    if (g === "none") continue;
    if (!["techniques", "examples"].includes(g)) throw new Error(`unknown --with group "${g}" (techniques, examples, none)`);
    groups.add(g);
  }
  return groups;
}

function selected(groups) {
  return FILES.filter(([g]) => groups.has(g)).map(([, folder, rel]) => {
    const text = fs.readFileSync(path.join(VENDOR, rel), "utf8").replace(/\r\n/g, "\n");
    if (text.includes(BS)) throw new Error(`${rel} contains the backslash sentinel; pick another`);
    return { folder, name: path.basename(rel, ".luau"), text, bytes: Buffer.byteLength(text, "utf8") };
  });
}

// a long-bracket level that does not occur in the text, so the source embeds verbatim
function bracket(text) {
  for (let n = 1; n < 40; n++) {
    const eq = "=".repeat(n);
    if (!text.includes("]" + eq + "]")) return ["[" + eq + "[\n", "]" + eq + "]"];
  }
  throw new Error("no free long-bracket level");
}

function luaString(s) {
  if (/["\\\n]/.test(s)) throw new Error(`unsafe Lua string literal: ${s}`);
  return `"${s}"`;
}

// Lua that checks every expected StringValue exists, has the vendored byte length and compiles, then builds one
// preview mesh into an unparented part. Reads MK; returns a JSON report.
function verifyLua(files) {
  const rows = files.map((f) => `\t{ ${luaString(f.folder)}, ${luaString(f.name)}, ${f.bytes} },`).join("\n");
  return `
local HS = game:GetService("HttpService")
local expected = {
${rows}
}
local report = { root = MK:GetFullName(), commit = MK:GetAttribute("KitCommit"), ok = true, modules = {} }
for _, e in ipairs(expected) do
	local parent = e[1] == "" and MK or MK:FindFirstChild(e[1])
	local v = parent and parent:FindFirstChild(e[2])
	local entry = { name = (e[1] == "" and "" or e[1] .. "/") .. e[2], want = e[3] }
	if not v then
		entry.err = "missing"
	else
		entry.len = #v.Value
		local fn, err = loadstring(v.Value)
		if not fn then
			entry.err = "compile: " .. tostring(err)
		elseif entry.len ~= e[3] then
			entry.err = "length"
		end
	end
	if entry.err then
		report.ok = false
	end
	table.insert(report.modules, entry)
end
if MK:FindFirstChild("MeshKit") then
	local okSmoke, smoke = pcall(function()
		local Kit = loadstring(MK.MeshKit.Value)()
		local k = Kit.new("MeshToolsSmoke")
		k:box(CFrame.identity, Vector3.new(4, 1, 2), 0.1)
		local part = k:finish("MeshToolsSmoke", { preview = true })
		local s = part.Size
		local tris = k:triCount()
		part:Destroy()
		return string.format("preview mesh ok: %d tris, size %.2f x %.2f x %.2f (want 44, 4 x 1 x 2)", tris, s.X, s.Y, s.Z)
	end)
	report.smoke = tostring(smoke)
	if not okSmoke then
		report.ok = false
	end
end
return HS:JSONEncode(report)
`;
}

function installerLua(files, { root, sandbox }) {
  let out = `--robloxMeshTools installer, generated by the importmeshtools skill (meshtools.js) from commit ${SHORT}.
--Creates ${sandbox ? "a throwaway UNPARENTED folder" : "ServerStorage." + root} with one StringValue per kit source; execute_luau cannot
--require ModuleScripts, so everything is loaded with loadstring(value.Value). Re-running replaces the sources and keeps
--Templates / PreviewTemplates. Every backslash in the sources travels as ${BS} and is restored here.
local BS = string.char(92)
local SS = ${sandbox ? 'Instance.new("Folder")' : 'game:GetService("ServerStorage")'}
local MK = SS:FindFirstChild(${luaString(root)}) or Instance.new("Folder")
MK.Name = ${luaString(root)}
MK.Parent = SS
local function folder(parent, name)
	local f = parent:FindFirstChild(name) or Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
for _, n in ipairs({ "TemplateSrc", "Pieces", "Templates", "PreviewTemplates" }) do
	folder(MK, n)
end
local function put(parentName, name, src)
	local parent = parentName == "" and MK or MK[parentName]
	local s = parent:FindFirstChild(name) or Instance.new("StringValue")
	s.Name = name
	s.Value = (string.gsub(src, ${luaString(BS)}, function()
		return BS
	end))
	s.Parent = parent
end
`;
  for (const f of files) {
    const text = f.text.split("\\").join(BS);
    const [open, close] = bracket(text);
    out += `put(${luaString(f.folder)}, ${luaString(f.name)}, ${open}${text}${close})\n`;
  }
  out += `MK:SetAttribute("KitCommit", ${luaString(SHORT)})
MK:SetAttribute("KitSource", "github.com/MrChickenRocket/robloxMeshTools")
MK:SetAttribute("KitModules", ${luaString(files.map((f) => f.name).join(","))})
`;
  // the sandbox has no later call to verify from, so it verifies in the same one; a real install verifies in a
  // separate call, because Studio has been seen to roll back plugin-created instances between calls
  if (sandbox) out += verifyLua(files);
  else out += `return "installed ${files.length} sources into " .. MK:GetFullName()\n`;
  if (out.includes("\\")) throw new Error("generated installer contains a backslash; refusing to send it");
  return out;
}

function verifyScript(files, root) {
  return `local MK = game:GetService("ServerStorage"):FindFirstChild(${luaString(root)})
if not MK then
	return game:GetService("HttpService"):JSONEncode({ ok = false, error = "ServerStorage.${root} does not exist" })
end
${verifyLua(files)}`;
}

const PROBE = `
local RS = game:GetService("RunService")
local SS = game:GetService("ServerStorage")
local MK = SS:FindFirstChild("ModelKit")
return game:GetService("HttpService"):JSONEncode({
	placeId = game.PlaceId,
	gameId = game.GameId,
	name = game.Name,
	creatorType = tostring(game.CreatorType),
	running = RS:IsRunning(),
	kit = MK and (MK:GetAttribute("KitCommit") or "present, no KitCommit (pre-skill install)") or false,
})
`;

const studioBridge = (() => {
  try {
    return require(path.join(__dirname, "..", "studio", "bridge.js"));
  } catch {
    return null;
  }
})();

async function call(port, code, timeoutMs = 120000) {
  if (studioBridge) code = studioBridge.onceLua(code);
  const res = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name: "execute_luau", arguments: { code } } }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await res.text();
  let msg;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) msg = JSON.parse(line.slice(6));
  if (!msg) msg = JSON.parse(body);
  if (msg.error) throw new Error(`JSON-RPC error: ${JSON.stringify(msg.error)}`);
  const inner = msg.result && msg.result.content && msg.result.content[0] && msg.result.content[0].text;
  let r;
  try {
    r = JSON.parse(inner);
  } catch {
    throw new Error(`unexpected tool reply: ${inner}`);
  }
  if (r.success === false) throw new Error(`execute_luau failed: ${r.message || inner}`);
  return r;
}

async function probePort(port) {
  const r = await call(port, PROBE, 8000);
  return JSON.parse(r.returnValue);
}

async function needPort(args) {
  const port = Number(args.port);
  if (port) return port;
  if (!studioBridge) throw new Error("--port N is required (run `probe` first)");
  const placeId = args["place-id"] || studioBridge.readConfig(studioBridge.findProjectRoot()).placeId;
  return (await studioBridge.resolve({ placeId })).port;
}

function printReport(label, json) {
  const r = JSON.parse(json);
  console.log(`${label}: ${r.ok ? "OK" : "FAILED"}${r.root ? " (" + r.root + ", commit " + (r.commit || "none") + ")" : ""}`);
  if (r.error) console.log(`  ${r.error}`);
  for (const m of r.modules || []) console.log(`  ${m.err ? "x" : "ok"} ${m.name} ${m.len ?? "-"}/${m.want}${m.err ? "  " + m.err : ""}`);
  if (r.smoke) console.log(`  smoke: ${r.smoke}`);
  return r.ok;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0];
  const root = typeof args.root === "string" ? args.root : "ModelKit";
  if (!["probe", "emit", "run", "selftest", "verify", "install"].includes(cmd)) {
    console.log(fs.readFileSync(__filename, "utf8").split("\n").slice(1, 14).join("\n"));
    process.exitCode = 1;
    return;
  }

  if (cmd === "probe") {
    let any = false;
    for (const port of PORTS) {
      try {
        const p = await probePort(port);
        any = true;
        console.log(`port ${port}: placeId=${p.placeId} gameId=${p.gameId} name="${p.name}" ${p.creatorType} running=${p.running} kit=${p.kit}`);
      } catch (e) {
        if (!/ECONNREFUSED|fetch failed/.test(String(e.cause || e.message))) console.log(`port ${port}: ${e.message}`);
      }
    }
    if (!any) console.log("no Studio MCP server answered on 58741-58750; fall back to `emit` and paste through execute_luau");
    return;
  }

  if (cmd === "emit") {
    if (typeof args.out !== "string") throw new Error("--out file.luau is required");
    const files = selected(groupsFrom(args));
    const text = args["verify-only"] ? verifyScript(files, root) : installerLua(files, { root, sandbox: false });
    fs.writeFileSync(args.out, text);
    console.log(`wrote ${args.out}: ${text.length} chars, ${files.length} sources, no backslashes`);
    return;
  }

  if (cmd === "run") {
    const port = await needPort(args);
    if (typeof args.file !== "string") throw new Error("--file piece.luau is required");
    const code = fs.readFileSync(args.file, "utf8");
    const r = await call(port, code, Number(args.timeout) || 300000);
    for (const line of r.output || []) console.log(typeof line === "string" ? line : JSON.stringify(line));
    console.log(r.returnValue === undefined ? "(no return value)" : typeof r.returnValue === "string" ? r.returnValue : JSON.stringify(r.returnValue));
    return;
  }

  const files = selected(groupsFrom(args));
  const port = await needPort(args);

  if (cmd === "selftest") {
    const r = await call(port, installerLua(files, { root, sandbox: true }));
    process.exitCode = printReport("selftest (sandbox, nothing parented)", r.returnValue) ? 0 : 1;
    return;
  }

  if (cmd === "verify") {
    const r = await call(port, verifyScript(files, root));
    process.exitCode = printReport("verify", r.returnValue) ? 0 : 1;
    return;
  }

  if (cmd === "install") {
    if (args["place-id"] === undefined || args["place-id"] === true) throw new Error("--place-id ID is required: the PlaceId the project expects, so the kit never lands in another open place");
    const p = await probePort(port);
    if (String(p.placeId) !== String(args["place-id"])) throw new Error(`port ${port} has placeId ${p.placeId} ("${p.name}") open, not ${args["place-id"]}; refusing`);
    if (typeof args["place-name"] === "string" && p.name !== args["place-name"]) throw new Error(`port ${port} has "${p.name}" open, not "${args["place-name"]}"; refusing`);
    if (p.running) throw new Error("a playtest is running; the kit installs into the Edit datamodel, so stop the playtest first");
    if (!args.force && p.kit === SHORT) {
      const v = await call(port, verifyScript(files, root));
      if (printReport(`already at ${SHORT}; verify`, v.returnValue)) return;
      console.log("verify failed; reinstalling");
    }
    const r = await call(port, installerLua(files, { root, sandbox: false }));
    console.log(r.returnValue);
    // separate call on purpose: a verify inside the install call cannot see a rollback between calls
    const v = await call(port, verifyScript(files, root));
    process.exitCode = printReport("verify (separate call)", v.returnValue) ? 0 : 1;
    if (Number(p.placeId) === 0) console.log("  note: placeId 0 = unpublished place; previews work, uploads need a published place");
  }
}

main().catch((e) => {
  console.error(`error: ${e.message}`);
  process.exitCode = 1;
});
