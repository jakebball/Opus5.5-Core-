#!/usr/bin/env node
// Extracts the team baseplate from a live game place and turns it into Rojo source under baseplate/.
//
//   node maintainer/baseplate.js extract   # Studio -> baseplate/.extract/*.rbxm (--place-id ID of the source game, open in Studio)
//   node maintainer/baseplate.js source    # .extract/*.rbxm -> baseplate/src/** text files (rojo syncback)
//   node maintainer/baseplate.js build     # baseplate/src -> baseplate/RunnerBaseplate.rbxl (rojo build)
//   node maintainer/baseplate.js all --place-id ID   # all three
//
// baseplate/extract.json says which subtrees to copy and what to strip from each (remove / keepOnly / moveChildren).
// The copies are made and stripped in Studio on unparented clones, so the source place is never changed. After
// `source`, hand edits in baseplate/src (fixes, cleaned configs) are kept: `source` refuses to overwrite src unless
// --force, because the patches in maintainer/baseplate-patches.js are re-applied by `source` itself.
// Needs Node 18+, Rojo 7.5+ on PATH (or ROJO=path), and the Studio MCP bridge for `extract`.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const REPO = path.resolve(__dirname, "..");
const bridge = require(path.join(REPO, "skills", "studio", "bridge.js"));
const BASE = path.join(REPO, "baseplate");
const EXTRACT = path.join(BASE, ".extract");
const SPEC = JSON.parse(fs.readFileSync(path.join(BASE, "extract.json"), "utf8"));
const ROJO = process.env.ROJO || "rojo";
const CHUNK = 900000;

function luaPath(dotted) {
  const [service, ...rest] = dotted.split(".");
  return `game:GetService("${service}")` + rest.map((name) => `:FindFirstChild(${JSON.stringify(name)})`).join("");
}

function stripLua(take, index) {
  return `local HttpService = game:GetService("HttpService")
local spec = HttpService:JSONDecode(${bridge.longString(JSON.stringify(take))})
local source = ${luaPath(take.path)}
if not source then error("missing " .. spec.path) end
local copy = source:Clone()
local function find(root, dotted)
	local node = root
	if dotted == "" then return node end
	for name in string.gmatch(dotted, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end
local removed, missing = {}, {}
for _, dotted in spec.remove or {} do
	local node = find(copy, dotted)
	if node then node:Destroy() table.insert(removed, dotted) else table.insert(missing, dotted) end
end
for folderPath, names in spec.keepOnly or {} do
	local folder = find(copy, folderPath)
	if folder then
		local keep = {}
		for _, name in names do keep[name] = true end
		for _, child in folder:GetChildren() do
			if not keep[child.Name] then table.insert(removed, (folderPath == "" and "" or folderPath .. ".") .. child.Name) child:Destroy() end
		end
	end
end
for fromPath, toPath in spec.moveChildren or {} do
	local from, to = find(copy, fromPath), find(copy, toPath)
	if from and to then
		for _, child in from:GetChildren() do child.Parent = to end
		from:Destroy()
	end
end
local stripped = 0
if spec.stripTags then
	for _, descendant in copy:GetDescendants() do
		for _, tag in descendant:GetTags() do
			descendant:RemoveTag(tag)
			stripped += 1
		end
	end
end
for _, name in spec.ensureFolders or {} do
	if not copy:FindFirstChild(name) then
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = copy
	end
end
local serialized = game:GetService("SerializationService"):SerializeInstancesAsync({ copy })
local encoded = buffer.tostring(game:GetService("EncodingService"):Base64Encode(serialized))
copy:Destroy()
_G.BaseplateExtract = _G.BaseplateExtract or {}
_G.BaseplateExtract[${index}] = encoded
return HttpService:JSONEncode({ length = #encoded, removed = removed, missing = missing, strippedTags = stripped })`;
}

async function extract() {
  const flag = process.argv.indexOf("--place-id");
  const placeId = flag >= 0 ? process.argv[flag + 1] : SPEC.sourcePlaceId;
  if (!placeId || String(placeId) === "0") throw new Error("pass --place-id <id of the game place open in Studio> (or set sourcePlaceId in extract.json)");
  const place = await bridge.resolve({ placeId });
  fs.rmSync(EXTRACT, { recursive: true, force: true });
  fs.mkdirSync(EXTRACT, { recursive: true });
  for (const [index, take] of SPEC.take.entries()) {
    const report = JSON.parse(await bridge.deferred(place.port, stripLua(take, index + 1)));
    let encoded = "";
    for (let offset = 0; offset < report.length; offset += CHUNK) {
      encoded += await bridge.once(place.port, `return string.sub(_G.BaseplateExtract[${index + 1}], ${offset + 1}, ${offset + CHUNK})`);
    }
    await bridge.once(place.port, `_G.BaseplateExtract[${index + 1}] = nil return "ok"`);
    const bytes = Buffer.from(encoded, "base64");
    const file = path.join(EXTRACT, `${take.out}.rbxm`);
    fs.writeFileSync(file, bytes);
    console.log(`${take.out}: ${(bytes.length / 1024).toFixed(0)} KB, stripped ${report.removed.length}${report.strippedTags ? `, ${report.strippedTags} template tags removed` : ""}${report.missing.length ? `, not found: ${report.missing.join(", ")}` : ""}`);
  }
}

function rojo(args) {
  const result = spawnSync(ROJO, args, { cwd: BASE, encoding: "utf8", input: "y\n" });
  const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
  if (result.status !== 0) throw new Error(`rojo ${args.join(" ")} failed:\n${output}`);
  return output;
}

function rawProject() {
  const tree = { $className: "DataModel" };
  for (const take of SPEC.take) {
    const segments = take.out.split(".");
    const service = segments[0] === "StarterPlayerScripts" ? ["StarterPlayer", "StarterPlayerScripts"] : [segments[0]];
    let node = tree;
    for (const name of service) node = node[name] = node[name] || { $className: name };
    node[segments[segments.length - 1]] = { $path: `${take.out}.rbxm` };
  }
  return { name: "RunnerBaseplateRaw", tree };
}

function source(force) {
  const src = path.join(BASE, "src");
  if (fs.existsSync(src) && !force) throw new Error("baseplate/src exists; pass --force to regenerate it from .extract (patches are re-applied)");
  fs.rmSync(src, { recursive: true, force: true });
  for (const take of SPEC.take) {
    const segments = take.out.split(".");
    fs.mkdirSync(path.join(src, ...segments), { recursive: true });
    const seed = { Script: "init.server.luau", LocalScript: "init.client.luau", ModuleScript: "init.luau" }[take.class];
    if (seed) fs.writeFileSync(path.join(src, ...segments, seed), "");
  }
  fs.writeFileSync(path.join(BASE, ".extract", "raw.project.json"), JSON.stringify(rawProject(), null, 2));
  rojo(["build", path.join(".extract", "raw.project.json"), "-o", path.join(".extract", "raw.rbxl")]);
  const syncProject = JSON.parse(fs.readFileSync(path.join(BASE, "default.project.json"), "utf8"));
  const onlyExtracted = (node) => {
    for (const [key, child] of Object.entries(node)) {
      if (key.startsWith("$") || typeof child !== "object") continue;
      if (child.$path) child.$path = `../${child.$path}`;
      else if (!JSON.stringify(child).includes('"$path"')) delete node[key];
      else onlyExtracted(child);
    }
  };
  onlyExtracted(syncProject.tree);
  fs.writeFileSync(path.join(BASE, ".extract", "sync.project.json"), JSON.stringify(syncProject, null, 2));
  console.log(rojo(["syncback", path.join(".extract", "sync.project.json"), "--input", path.join(".extract", "raw.rbxl")]).split(/\r?\n/).slice(-3).join("\n"));
  const patches = require("./baseplate-patches.js");
  for (const patch of patches) {
    const file = path.join(src, patch.file);
    if (!fs.existsSync(file)) throw new Error(`patch target missing: ${patch.file}`);
    const before = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
    const after = patch.apply(before);
    if (after === before) throw new Error(`patch changed nothing: ${patch.name}`);
    fs.writeFileSync(file, after);
    console.log(`patched ${patch.file}: ${patch.name}`);
  }
}

function build() {
  console.log(rojo(["build", "default.project.json", "-o", "RunnerBaseplate.rbxl"]) || "built baseplate/RunnerBaseplate.rbxl");
}

async function main() {
  const [command] = process.argv.slice(2);
  const force = process.argv.includes("--force");
  if (command === "extract") await extract();
  else if (command === "source") source(force);
  else if (command === "build") build();
  else if (command === "all") {
    await extract();
    source(true);
    build();
  } else console.log("usage: node maintainer/baseplate.js extract | source [--force] | build | all");
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
