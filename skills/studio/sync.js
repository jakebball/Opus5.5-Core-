#!/usr/bin/env node
// sync.js: mirrors a place's scripts to disk and pushes disk edits back, one file at a time, over the Studio MCP bridge.
// Run it from anywhere inside a project; it finds the project by its studio.json (made by `init`).
//
//   node sync.js init                      studio.json (placeId of the one open Studio), <gameSource>/, .gitattributes, .gitignore
//   node sync.js probe                     which Studios answer on 58741-58750, and the place each has open
//   node sync.js pull [prefix]             Studio -> disk for every script under the roots, or under prefix
//                                          (e.g. StarterPlayerScripts/Runner/Components/MyGame). A disk file with unpushed
//                                          edits is never overwritten; it is reported instead.
//   node sync.js push <file...> [--force]  disk -> Studio for exactly these files, after a compile check. Refuses a file whose
//                                          Studio copy changed since this disk copy was last synced: pull, merge, push again.
//   node sync.js check <file...>           compile-check disk files in Studio (loadstring) without changing anything
//   node sync.js status [prefix]           files edited on disk, changed in Studio, or both (CONFLICT)
//   node sync.js delete <file...>          removes the scripts in Studio and on disk
//   --port N                               skip discovery and use this bridge port
//
// Layout: <gameSource>/<Root>/<path>/<Name><ext>. Root is a service folder (ServerScriptService, StarterPlayerScripts, ...).
// ext: .luau ModuleScript, .server.luau Script, .client.luau LocalScript. A script with children is a file plus a folder of
// the same name. Folders that hold no script are not mirrored; a missing parent is created as a Folder on push.
// Workspace is not mirrored by default (a big map makes every pull walk it); list it in studio.json "roots" to opt in.
// Sync bases (the hash last seen in both places) live in <gameSource>/.sync/, one file per script, so parallel pushes of
// different files never race on shared state.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const bridge = require("./bridge");

const ROOTS = {
  ServerScriptService: "game.ServerScriptService",
  StarterPlayerScripts: "game.StarterPlayer.StarterPlayerScripts",
  StarterCharacterScripts: "game.StarterPlayer.StarterCharacterScripts",
  ReplicatedFirst: "game.ReplicatedFirst",
  ReplicatedStorage: "game.ReplicatedStorage",
  ServerStorage: "game.ServerStorage",
  StarterGui: "game.StarterGui",
  Workspace: "game.Workspace",
};
const EXTENSIONS = [
  [".server.luau", "Script"],
  [".client.luau", "LocalScript"],
  [".luau", "ModuleScript"],
];

const PROJECT = bridge.findProjectRoot();
const CONFIG = bridge.readConfig(PROJECT);
const HERE = path.join(PROJECT, CONFIG.gameSource || "game-source");
const BASE_DIR = path.join(HERE, ".sync");
const DEFAULT_ROOTS = Object.keys(ROOTS).filter((root) => root !== "Workspace");
const ACTIVE_ROOTS = Object.fromEntries((CONFIG.roots || DEFAULT_ROOTS).map((root) => [root, ROOTS[root]]));
let port;

const call = (code) => bridge.once(port, code);
const normalise = (text) => text.replace(/\r\n/g, "\n");
const hash = (text) => crypto.createHash("sha1").update(normalise(text)).digest("hex");

function relOf(file) {
  const absolute = path.resolve(file);
  const rel = path.relative(HERE, absolute).split(path.sep).join("/");
  if (rel.startsWith("..")) throw new Error(`${file} is outside ${path.relative(PROJECT, HERE)}/`);
  return rel;
}

function describe(rel) {
  const parts = rel.split("/");
  const root = parts.shift();
  if (!ACTIVE_ROOTS[root]) throw new Error(`${rel}: unknown root ${root}; use ${Object.keys(ACTIVE_ROOTS).join(", ")}`);
  const fileName = parts.pop();
  const match = EXTENSIONS.find(([ext]) => fileName.endsWith(ext));
  if (!match) throw new Error(`${rel}: not a .luau file`);
  return { root, segments: [...parts, fileName.slice(0, -match[0].length)], className: match[1] };
}

const basePath = (rel) => path.join(BASE_DIR, rel + ".sha1");
function readBase(rel) {
  try {
    return fs.readFileSync(basePath(rel), "utf8").trim();
  } catch {
    return null;
  }
}
function writeBase(rel, text) {
  fs.mkdirSync(path.dirname(basePath(rel)), { recursive: true });
  fs.writeFileSync(basePath(rel), hash(text));
}

const LUAU_LIST = `
local HttpService = game:GetService("HttpService")
local function listUnder(root, rootKey, prefixSegments)
	local start = root
	for _, segment in prefixSegments do
		start = start and start:FindFirstChild(segment)
	end
	if not start then return {} end
	local results = {}
	local function walk(instance, segments)
		for _, child in instance:GetChildren() do
			local childSegments = table.clone(segments)
			table.insert(childSegments, child.Name)
			if child:IsA("LuaSourceContainer") then
				table.insert(results, { root = rootKey, segments = childSegments, className = child.ClassName, source = child.Source })
			end
			walk(child, childSegments)
		end
	end
	if start:IsA("LuaSourceContainer") and start ~= root then
		table.insert(results, { root = rootKey, segments = table.clone(prefixSegments), className = start.ClassName, source = start.Source })
	end
	walk(start, prefixSegments)
	return results
end
`;

async function listStudio(prefix) {
  const out = [];
  const prefixParts = prefix ? prefix.split("/").filter(Boolean) : [];
  const roots = prefixParts.length ? [prefixParts.shift()] : Object.keys(ACTIVE_ROOTS);
  for (const root of roots) {
    if (!ACTIVE_ROOTS[root]) throw new Error(`unknown root ${root}`);
    const json = await call(`${LUAU_LIST}
return HttpService:JSONEncode(listUnder(${ACTIVE_ROOTS[root]}, "${root}", HttpService:JSONDecode(${bridge.longString(JSON.stringify(prefixParts))})))`);
    for (const entry of JSON.parse(json)) out.push(entry);
  }
  return out;
}

function relFor(entry) {
  const ext = EXTENSIONS.find(([, className]) => className === entry.className)[0];
  return [entry.root, ...entry.segments].join("/") + ext;
}

async function pull(prefix) {
  const entries = await listStudio(prefix);
  const seen = new Set();
  let written = 0;
  let unchanged = 0;
  const skipped = [];
  for (const entry of entries) {
    if (entry.segments.some((segment) => /[<>:"\\|?*/]/.test(segment))) {
      skipped.push(`${entry.segments.join("/")} (name is not a valid file name)`);
      continue;
    }
    const rel = relFor(entry);
    if (seen.has(rel.toLowerCase())) {
      skipped.push(`${rel} (duplicate sibling name)`);
      continue;
    }
    seen.add(rel.toLowerCase());
    const file = path.join(HERE, rel);
    const studio = normalise(entry.source);
    const base = readBase(rel);
    if (fs.existsSync(file)) {
      const disk = normalise(fs.readFileSync(file, "utf8"));
      if (disk === studio) {
        if (base !== hash(studio)) writeBase(rel, studio);
        unchanged++;
        continue;
      }
      if (base !== null && hash(disk) !== base) {
        skipped.push(`${rel} (edited on disk and not pushed; Studio ${hash(studio) === base ? "unchanged" : "ALSO changed: conflict"})`);
        continue;
      }
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, studio);
    writeBase(rel, studio);
    written++;
  }
  console.log(`pulled ${entries.length} scripts: ${written} written, ${unchanged} unchanged, ${skipped.length} skipped`);
  for (const line of skipped) console.log(`  skipped ${line}`);
}

function instanceLookup(description) {
  return `local HttpService = game:GetService("HttpService")
local node = ${ACTIVE_ROOTS[description.root]}
for _, segment in HttpService:JSONDecode(${bridge.longString(JSON.stringify(description.segments))}) do
	node = node and node:FindFirstChild(segment)
end`;
}

const COMPILE_BATCH_BYTES = 120000;

async function compileCheck(entries) {
  const batches = [[]];
  let size = 0;
  for (const entry of entries) {
    if (size + entry.source.length > COMPILE_BATCH_BYTES && batches[batches.length - 1].length) {
      batches.push([]);
      size = 0;
    }
    batches[batches.length - 1].push(entry);
    size += entry.source.length;
  }
  const failures = [];
  for (const batch of batches) {
    const payload = batch.map(({ rel, source }) => `{ ${JSON.stringify(rel)}, ${bridge.longString(source)} }`).join(",\n");
    const result = await call(`local failures = {}
for _, pair in { ${payload} } do
	local ok, fn, err = pcall(loadstring, pair[2], pair[1])
	if not ok then table.insert(failures, pair[1] .. ": " .. tostring(fn))
	elseif fn == nil then table.insert(failures, tostring(err)) end
end
return table.concat(failures, "\\n")`);
    if (result) failures.push(...result.split("\n").filter(Boolean));
  }
  return failures;
}

async function studioSource(description) {
  return JSON.parse(
    await call(`${instanceLookup(description)}
if not node then return HttpService:JSONEncode({ missing = true }) end
return HttpService:JSONEncode({ className = node.ClassName, source = node:IsA("LuaSourceContainer") and node.Source or "" })`),
  );
}

function readEntries(files) {
  return files.map((file) => {
    const rel = relOf(file);
    return { rel, description: describe(rel), source: normalise(fs.readFileSync(path.join(HERE, rel), "utf8")) };
  });
}

async function push(files, force) {
  const entries = readEntries(files);
  const failures = await compileCheck(entries);
  if (failures.length) {
    console.log("compile check failed; nothing pushed:");
    for (const line of failures) console.log(`  ${line}`);
    process.exitCode = 1;
    return;
  }
  for (const entry of entries) {
    const current = await studioSource(entry.description);
    const base = readBase(entry.rel);
    if (!current.missing) {
      if (current.className !== entry.description.className) {
        console.log(`${entry.rel}: REFUSED, Studio has a ${current.className} there`);
        process.exitCode = 1;
        continue;
      }
      const studio = normalise(current.source);
      if (studio === entry.source) {
        writeBase(entry.rel, studio);
        console.log(`${entry.rel}: unchanged`);
        continue;
      }
      if (!force && hash(studio) !== base) {
        console.log(`${entry.rel}: REFUSED, changed in Studio since your last sync (pull, merge, push again)`);
        process.exitCode = 1;
        continue;
      }
    } else if (!force && base !== null) {
      console.log(`${entry.rel}: REFUSED, deleted in Studio since your last sync (--force recreates it)`);
      process.exitCode = 1;
      continue;
    }
    await call(`local HttpService = game:GetService("HttpService")
local segments = HttpService:JSONDecode(${bridge.longString(JSON.stringify(entry.description.segments))})
local node = ${ACTIVE_ROOTS[entry.description.root]}
for index = 1, #segments - 1 do
	local child = node:FindFirstChild(segments[index])
	if not child then
		child = Instance.new("Folder")
		child.Name = segments[index]
		child.Parent = node
	end
	node = child
end
local script = node:FindFirstChild(segments[#segments])
if not script then
	script = Instance.new("${entry.description.className}")
	script.Name = segments[#segments]
	script.Parent = node
end
script.Source = ${bridge.longString(entry.source)}
return "ok"`);
    const after = await studioSource(entry.description);
    if (after.missing || normalise(after.source) !== entry.source) {
      console.log(`${entry.rel}: WRITE DID NOT STICK (an open script editor tab in Studio overwrites .Source; close it and push again)`);
      process.exitCode = 1;
      continue;
    }
    writeBase(entry.rel, entry.source);
    console.log(`${entry.rel}: ${current.missing ? "created" : "pushed"}`);
  }
}

async function check(files) {
  const entries = readEntries(files);
  const failures = await compileCheck(entries);
  if (failures.length) {
    for (const line of failures) console.log(line);
    process.exitCode = 1;
  } else console.log(`${entries.length} file(s) compile`);
}

async function status(prefix) {
  const entries = await listStudio(prefix);
  const studioByRel = new Map(entries.map((entry) => [relFor(entry), normalise(entry.source)]));
  const lines = [];
  const walk = (directory) => {
    if (!fs.existsSync(directory)) return;
    for (const name of fs.readdirSync(directory)) {
      const full = path.join(directory, name);
      if (name === ".sync") continue;
      if (fs.statSync(full).isDirectory()) walk(full);
      else if (name.endsWith(".luau")) {
        const rel = relOf(full);
        if (prefix && !rel.startsWith(prefix + "/") && !EXTENSIONS.some(([ext]) => rel === prefix + ext)) continue;
        const disk = normalise(fs.readFileSync(full, "utf8"));
        const studio = studioByRel.get(rel);
        const base = readBase(rel);
        studioByRel.delete(rel);
        if (studio === undefined) lines.push(`new on disk   ${rel}`);
        else if (disk === studio) continue;
        else if (hash(studio) === base) lines.push(`edited disk   ${rel}`);
        else if (hash(disk) === base) lines.push(`edited Studio ${rel}`);
        else lines.push(`CONFLICT      ${rel}`);
      }
    }
  };
  walk(prefix ? path.dirname(path.join(HERE, prefix)) : HERE);
  for (const rel of studioByRel.keys()) lines.push(`only Studio   ${rel}`);
  console.log(lines.length ? lines.join("\n") : "in sync");
}

async function remove(files) {
  for (const file of files) {
    const rel = relOf(file);
    await call(`${instanceLookup(describe(rel))}
if node then node:Destroy() end
return "ok"`);
    fs.rmSync(path.join(HERE, rel), { force: true });
    fs.rmSync(basePath(rel), { force: true });
    console.log(`${rel}: deleted`);
  }
}

async function init(portFlag) {
  const configFile = path.join(PROJECT, "studio.json");
  if (!fs.existsSync(configFile)) {
    const place = await bridge.resolve({ port: portFlag });
    const config = { placeId: place.placeId, gameSource: "game-source" };
    fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
    console.log(`studio.json: placeId ${place.placeId} ("${place.name}")`);
  } else console.log("studio.json: exists, left alone");
  const config = bridge.readConfig(PROJECT);
  const source = path.join(PROJECT, config.gameSource || "game-source");
  fs.mkdirSync(source, { recursive: true });
  const attributes = path.join(PROJECT, ".gitattributes");
  if (!fs.existsSync(attributes)) fs.writeFileSync(attributes, "*.luau text eol=lf\n");
  const ignore = path.join(PROJECT, ".gitignore");
  const ignoreLine = `${config.gameSource || "game-source"}/.sync/`;
  const ignoreText = fs.existsSync(ignore) ? fs.readFileSync(ignore, "utf8") : "";
  if (!ignoreText.split(/\r?\n/).includes(ignoreLine)) fs.writeFileSync(ignore, ignoreText + (ignoreText && !ignoreText.endsWith("\n") ? "\n" : "") + ignoreLine + "\n");
  console.log(`ready: ${path.relative(process.cwd(), source) || "."}; next: node sync.js pull`);
}

async function main() {
  const argv = process.argv.slice(2);
  const portFlag = bridge.takeFlag(argv, "port");
  const force = bridge.takeFlag(argv, "force", false) === true;
  const [command, ...rest] = argv;
  if (command === "probe") {
    const found = await bridge.probe();
    for (const place of found) console.log(`port ${place.port}: placeId=${place.placeId} "${place.name}" running=${place.running}`);
    if (!found.length) console.log("no Studio MCP bridge answered on 58741-58750");
    return;
  }
  if (command === "init") return init(portFlag);
  const usage = "usage: node sync.js init | probe | pull [prefix] | push <file...> [--force] | check <file...> | status [prefix] | delete <file...> [--port N]";
  if (!["pull", "push", "check", "status", "delete"].includes(command)) return console.log(usage);
  const writes = command === "push" || command === "delete";
  port = (await bridge.resolve({ port: portFlag, placeId: CONFIG.placeId, writes })).port;
  if (command === "pull") await pull(rest[0]);
  else if (command === "push") await push(rest, force);
  else if (command === "check") await check(rest);
  else if (command === "status") await status(rest[0]);
  else if (command === "delete") await remove(rest);
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
