#!/usr/bin/env node
// scaffold.js: creates a project from the team template in about a second, so /setup never retypes standard docs.
//
//   node scaffold.js new <Name> [--dir DIR] [--kind roblox|generic] [--pitch "TEXT"] [--place-id ID]
//        copy template/<kind>/ to DIR/<Name> (DIR defaults to the current folder), fill {{NAME}}, {{DATE}}, {{PITCH}},
//        the place line, and for Roblox the seeded Hard Rules and the Change Summaries pointer (read from
//        project-setup.md at copy time, so the template never drifts from the standard), then git init.
//        With --place-id the place is linked at once (below).
//   node scaffold.js link --place-id ID          run inside a project: write studio.json, pull every script into
//                                                game-source/ through /studio, and record the place in index.md
//   node scaffold.js places                      the places open in Studio right now (pick the id from here)
//   node scaffold.js rules                       how many Hard Rules are seeded, and their names
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const TEMPLATE = path.join(__dirname, "template");
const STUDIO = path.join(__dirname, "..", "studio");

function parse(argv) {
  const options = { _: [] };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      options._.push(arg);
      continue;
    }
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) options[arg.slice(2)] = true;
    else options[arg.slice(2)] = argv[++index];
  }
  return options;
}

function standardFile() {
  const candidates = [
    path.join(__dirname, "project-setup.md"),
    process.env.SETUP_STANDARDS && path.join(process.env.SETUP_STANDARDS, "project-setup.md"),
    path.join(os.homedir(), "Desktop", "ClaudeProjets", "project-setup.md"),
  ].filter(Boolean);
  const found = candidates.find((candidate) => fs.existsSync(candidate));
  if (!found) throw new Error(`project-setup.md not found (looked in ${candidates.join(", ")})`);
  return found;
}

function readStandard() {
  const text = fs.readFileSync(standardFile(), "utf8").replace(/\r\n/g, "\n");
  const start = text.indexOf("## Seeded Hard Rules");
  if (start < 0) throw new Error("project-setup.md has no ## Seeded Hard Rules section");
  const section = text.slice(start, text.indexOf("\n## ", start + 5));
  const firstRule = section.indexOf("\n- **");
  const syncNote = section.indexOf("**Keep this seed in sync");
  const rules = section.slice(firstRule + 1, syncNote < 0 ? undefined : syncNote).trim();
  const pointer = /Every project's `tech-design\.md` ends with this pointer block, pasted verbatim:\s*```markdown\n([\s\S]*?)```/.exec(text);
  if (!pointer) throw new Error("project-setup.md has no Change Summaries pointer block");
  const names = [...rules.matchAll(/^- \*\*(.+?)\*\*/gm)].map((match) => match[1]);
  return { rules, names, pointer: pointer[1].trim() };
}

function copyTemplate(source, target, fill) {
  for (const name of fs.readdirSync(source)) {
    const from = path.join(source, name);
    const to = path.join(target, name);
    if (fs.statSync(from).isDirectory()) {
      fs.mkdirSync(to, { recursive: true });
      copyTemplate(from, to, fill);
    } else if (/\.(md|py|json|luau|txt)$|^\.git(ignore|attributes)$/.test(name)) {
      fs.writeFileSync(to, fill(fs.readFileSync(from, "utf8")));
    } else {
      fs.copyFileSync(from, to);
    }
  }
}

function runStudio(script, args, cwd) {
  return spawnSync(process.execPath, [path.join(STUDIO, script), ...args], { cwd, encoding: "utf8" });
}

function link(projectDir, placeId) {
  if (!placeId || placeId === true) throw new Error("link needs --place-id ID (see `node scaffold.js places`)");
  if (!fs.existsSync(path.join(STUDIO, "sync.js"))) throw new Error("the /studio skill is not installed");
  const configFile = path.join(projectDir, "studio.json");
  const config = fs.existsSync(configFile) ? JSON.parse(fs.readFileSync(configFile, "utf8")) : {};
  config.placeId = Number(placeId);
  config.gameSource = config.gameSource || "game-source";
  fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
  fs.mkdirSync(path.join(projectDir, config.gameSource), { recursive: true });
  const pull = runStudio("sync.js", ["pull"], projectDir);
  const output = `${pull.stdout}${pull.stderr}`.trim();
  if (pull.status !== 0) return { linked: false, message: `studio.json written; pull failed (open the place in Studio and run \`node sync.js pull\`): ${output}` };
  const indexFile = path.join(projectDir, "index.md");
  if (fs.existsSync(indexFile)) {
    const index = fs.readFileSync(indexFile, "utf8").replace(/^- \*\*Place:\*\* .*$/m, `- **Place:** \`${placeId}\`, scripts mirrored in \`game-source/\` (\`studio.json\`)`);
    fs.writeFileSync(indexFile, index);
  }
  return { linked: true, message: output };
}

function create(options) {
  const name = options._[1];
  if (!name || !/^[A-Za-z0-9][A-Za-z0-9 _-]*$/.test(name)) throw new Error('usage: node scaffold.js new <Name> [--dir DIR] [--kind roblox|generic] [--pitch "TEXT"] [--place-id ID]');
  const kind = typeof options.kind === "string" ? options.kind : "roblox";
  const template = path.join(TEMPLATE, kind);
  if (!fs.existsSync(template)) throw new Error(`no template "${kind}"; use roblox or generic`);
  const target = path.resolve(typeof options.dir === "string" ? options.dir : process.cwd(), name);
  if (fs.existsSync(target) && fs.readdirSync(target).length) throw new Error(`${target} already exists and is not empty; audit it with /setup instead`);
  fs.mkdirSync(target, { recursive: true });

  const standard = readStandard();
  const pitch = typeof options.pitch === "string" ? options.pitch.trim() : "";
  const values = {
    NAME: name,
    NAME_ID: name.replace(/[^A-Za-z0-9]/g, ""),
    DATE: new Date().toISOString().slice(0, 10),
    PITCH: pitch || "**Unset.** One or two sentences on what the game is, in the user's words.",
    PLACE_LINE: "**Not linked yet.** Open the place in Studio, then `node ~/.claude/skills/setup/scaffold.js link --place-id <id>` here.",
    RULES: standard.rules,
    RULE_COUNT: String(standard.names.length),
    CHANGE_SUMMARY: standard.pointer,
  };
  copyTemplate(template, target, (text) => text.replace(/\{\{([A-Z_]+)\}\}/g, (whole, key) => (key in values ? values[key] : whole)));

  const git = spawnSync("git", ["init", "-q"], { cwd: target, encoding: "utf8" });
  const report = [`created  ${target} (${kind} template${kind === "roblox" ? `, ${standard.names.length} seeded Hard Rules` : ""})`, git.status === 0 ? "git      initialised" : "git      not available; run git init yourself"];
  if (options["place-id"] && kind === "roblox") {
    const result = link(target, options["place-id"]);
    report.push(`place    ${result.linked ? "linked: " : ""}${result.message.split("\n").pop()}`);
  } else if (kind === "roblox") {
    report.push("place    not linked yet (scaffold.js link --place-id <id> once the place exists)");
  }
  const unset = [];
  if (!pitch) unset.push("pitch");
  if (kind === "roblox") unset.push("core loop", "art style", "animation style");
  report.push(`unset    ${unset.join(", ")}`);
  console.log(report.join("\n"));
}

async function places() {
  const bridge = require(path.join(STUDIO, "bridge.js"));
  const found = await bridge.probe();
  if (!found.length) return console.log("no Studio MCP bridge answered: open the place in Studio with the MCP plugin connected");
  const unique = new Map(found.map((entry) => [String(entry.placeId), entry]));
  for (const entry of unique.values()) console.log(`placeId ${entry.placeId}  "${entry.name}"${entry.placeId === 0 ? "  (unpublished: publish it first so it has an id)" : ""}${entry.running ? "  (playtest running)" : ""}`);
}

async function main() {
  const options = parse(process.argv.slice(2));
  const command = options._[0];
  if (command === "new") return create(options);
  if (command === "link") {
    const result = link(process.cwd(), options["place-id"]);
    return console.log(result.message);
  }
  if (command === "places") return places();
  if (command === "rules") {
    const standard = readStandard();
    console.log(`${standard.names.length} seeded Hard Rules (from ${standardFile()}):`);
    for (const name of standard.names) console.log(`  - ${name}`);
    return;
  }
  console.log('usage: node scaffold.js new <Name> [--dir DIR] [--kind roblox|generic] [--pitch "TEXT"] [--place-id ID] | link --place-id ID | places | rules');
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
