#!/usr/bin/env node
// run.js: runs Luau files in Studio over the MCP bridge, so a script on disk can be the source of truth for anything built
// in the place (a map, a GUI, a preview, a data migration). Run it from anywhere inside a project (found by studio.json).
//
//   node run.js <file.luau | step>... [--set KEY=VALUE]... [--port N]
//
//   <file.luau>        runs the file. Paths are relative to the current directory.
//   <step>             a named list of files from studio.json "steps", run in order (e.g. "rebuild": ["map/Greybox.luau",
//                      "map/Terrain.luau"]). Steps and files can be mixed: node run.js greybox map/Dressing.luau
//   --set KEY=VALUE    (repeatable) exposes ARGS.KEY to the Luau; numbers and true/false are converted
//
// Before each file, in order: `local ARGS = {...}`; every module named on a `-- uses: <path from the project root>` line,
// wrapped as `local <Name> = (function() ... end)()`; and any studio.json "preludes" whose folder holds the file
// (e.g. { "folder": "ui-source", "file": "ui-source/Kit.luau" } gives every UI builder its kit).
// Before the first file, studio.json "shared" modules are installed from disk into "sharedFolder"
// (e.g. game.ServerScriptService.Runner.Shared.MyGame), so the disk copy is the only definition. A changed module is
// installed as a NEW ModuleScript, because Studio's require cache keeps serving the old one to anything that requires it in Edit.
// Every run is deferred inside Studio under a token and polled, so a build longer than the bridge's ~30 s call timeout
// still completes and reports, and a repeat delivery from the bridge never starts it twice. Long builds should still
// yield now and then (task.wait()) so Studio stays responsive.
const fs = require("fs");
const path = require("path");
const bridge = require("./bridge");

const PROJECT = bridge.findProjectRoot();
const CONFIG = bridge.readConfig(PROJECT);

function parse(argv) {
  const options = { port: bridge.takeFlag(argv, "port"), targets: [], args: {} };
  for (let index = 0; index < argv.length; index++) {
    if (argv[index] === "--set") {
      const [key, ...rest] = argv[++index].split("=");
      const raw = rest.join("=");
      options.args[key] = raw === "true" ? true : raw === "false" ? false : raw !== "" && !isNaN(Number(raw)) ? Number(raw) : raw;
    } else options.targets.push(argv[index]);
  }
  return options;
}

function luauValue(value) {
  return typeof value === "string" ? JSON.stringify(value) : String(value);
}

function argsPrelude(args) {
  return `local ARGS = { ${Object.entries(args)
    .map(([key, value]) => `${key} = ${luauValue(value)}`)
    .join(", ")} }\n`;
}

function usesModules(file, seen = new Set()) {
  return [...fs.readFileSync(file, "utf8").matchAll(/^-- uses: (\S+\.luau)\s*$/gm)]
    .map(([, module]) => {
      const modulePath = path.join(PROJECT, module);
      if (seen.has(modulePath)) return "";
      seen.add(modulePath);
      const name = path.basename(module, ".luau");
      return `local ${name} = (function()\n${fs.readFileSync(modulePath, "utf8")}\nend)()\n`;
    })
    .join("");
}

function configuredPreludes(file) {
  const absolute = path.resolve(file);
  return (CONFIG.preludes || [])
    .filter((prelude) => {
      const folder = path.join(PROJECT, prelude.folder) + path.sep;
      return absolute.startsWith(folder) && absolute !== path.join(PROJECT, prelude.file);
    })
    .map((prelude) => fs.readFileSync(path.join(PROJECT, prelude.file), "utf8") + "\n")
    .join("");
}

function codeFor(file, args) {
  return argsPrelude(args) + usesModules(file) + configuredPreludes(file) + fs.readFileSync(file, "utf8");
}

async function installShared(port) {
  if (!CONFIG.shared || !CONFIG.shared.length) return;
  if (!CONFIG.sharedFolder) throw new Error('studio.json lists "shared" modules but no "sharedFolder"');
  for (const shared of CONFIG.shared) {
    const file = path.join(PROJECT, shared.file);
    const name = shared.name || path.basename(file, ".luau");
    const code = `local folder = ${CONFIG.sharedFolder}
local module = folder:FindFirstChild("${name}")
if module and not module:IsA("ModuleScript") then error("${name} exists as a " .. module.ClassName) end
local source = ${bridge.longString(fs.readFileSync(file, "utf8"))}
if module and module.Source == source then return "unchanged" end
local replacement = Instance.new("ModuleScript")
replacement.Name = "${name}"
replacement.Source = source
if module then
	module:Destroy()
end
replacement.Parent = folder
return "installed"`;
    const result = await bridge.once(port, code);
    if (result !== "unchanged") console.log(`${name}: ${result} from ${shared.file}`);
  }
}

function expand(target) {
  const steps = CONFIG.steps || {};
  if (steps[target]) return steps[target].map((file) => ({ label: `${target} ${path.basename(file, ".luau")}`, file: path.join(PROJECT, file) }));
  if (target.endsWith(".luau")) return [{ label: target, file: path.resolve(target) }];
  const names = Object.keys(steps);
  throw new Error(`unknown step ${target}; use a .luau path${names.length ? " or one of: " + names.join(", ") : ""}`);
}

async function main() {
  const options = parse(process.argv.slice(2));
  if (!options.targets.length) {
    console.log("usage: node run.js <file.luau | step>... [--set KEY=VALUE]... [--port N]");
    const names = Object.keys(CONFIG.steps || {});
    if (names.length) console.log(`steps in studio.json: ${names.join(", ")}`);
    return;
  }
  const runs = options.targets.flatMap(expand);
  for (const run of runs) if (!fs.existsSync(run.file)) throw new Error(`${run.file} does not exist`);
  const { port } = await bridge.resolve({ port: options.port, placeId: CONFIG.placeId, writes: true });
  await installShared(port);
  for (const run of runs) {
    const started = Date.now();
    const result = await bridge.deferred(port, codeFor(run.file, options.args));
    console.log(`${run.label} (${((Date.now() - started) / 1000).toFixed(1)} s): ${result}`);
  }
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
