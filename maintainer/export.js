#!/usr/bin/env node
// Regenerates this repo's skills/ from a maintainer's live install, so the repo never drifts from the setup actually in use.
//
//   node maintainer/export.js [--skills DIR] [--standards DIR] [--dry]
//
// --skills     the live skills folder        (default ~/.claude/skills)
// --standards  the folder holding project-setup.md and change-summary.md (default: SETUP_STANDARDS env, else
//              ~/Desktop/ClaudeProjets)
//
// What it does: copies every shipped skill into skills/, copies project-setup.md and change-summary.md into
// skills/setup/, copies the worked animation-style example into skills/setup/examples/, rewrites every machine-specific
// path to a portable one (~/.claude/skills/..., <projects>/...), and drops caches and third-party code (the installer
// fetches robloxMeshTools from upstream). It fails, listing them, if any personal path survives the rewrite.
const fs = require("fs");
const os = require("os");
const path = require("path");

const REPO = path.resolve(__dirname, "..");
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const index = argv.indexOf(`--${name}`);
  return index >= 0 ? argv[index + 1] : fallback;
};
const SKILLS = path.resolve(flag("skills", path.join(os.homedir(), ".claude", "skills")));
const STANDARDS = path.resolve(flag("standards", process.env.SETUP_STANDARDS || path.join(os.homedir(), "Desktop", "ClaudeProjets")));
const DRY = argv.includes("--dry");
const HOME = os.homedir();
const USER = path.basename(HOME);

const SHIPPED = ["setup", "studio", "blenderassets", "assetshot", "itemicon", "importmeshtools", "create-animation", "create-devproduct", "create-gamepass", "upload-images", "makegui", "makereactcomponent", "makeweapon", "deslopify"];
const EXCLUDE = [/[\\/]__pycache__([\\/]|$)/, /^assetshot[\\/]cache([\\/]|$)/, /^importmeshtools[\\/]vendor[\\/]robloxMeshTools([\\/]|$)/, /\.pyc$/, /(^|[\\/])\.env$/, /(^|[\\/])node_modules([\\/]|$)/];
const TEXT = /\.(md|js|py|luau|lua|json|txt|html|css|sh|ps1)$/i;
const EXTRA = [
  { from: path.join(STANDARDS, "project-setup.md"), to: "skills/setup/project-setup.md" },
  { from: path.join(STANDARDS, "change-summary.md"), to: "skills/setup/change-summary.md" },
  { from: path.join(STANDARDS, "FPSTowerDefense", "features", "animation-style.md"), to: "skills/setup/examples/animation-style.md" },
];

const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const WIN_HOME = `C:\\Users\\${USER}`;
const standardsWin = STANDARDS.replace(/\//g, "\\");

function rewrite(text) {
  const swaps = [
    [`${standardsWin}\\project-setup.md`, "~/.claude/skills/setup/project-setup.md"],
    [`${standardsWin}\\change-summary.md`, "~/.claude/skills/setup/change-summary.md"],
    [`${standardsWin}\\FPSTowerDefense\\features\\animation-style.md`, "~/.claude/skills/setup/examples/animation-style.md"],
    [`${WIN_HOME}\\.claude\\.env`, "~/.claude/.env"],
    [`${WIN_HOME}\\.claude\\CLAUDE.md`, "~/.claude/CLAUDE.md"],
  ];
  for (const [from, to] of swaps) text = text.split(from).join(to);
  text = text.replace(new RegExp(`${escape(WIN_HOME)}\\\\\\.claude\\\\skills((?:\\\\[^\\s\`'"()<>\\\\]+)*)(\\\\?)`, "g"), (match, rest, slash) => `~/.claude/skills${rest.replace(/\\/g, "/")}${slash ? "/" : ""}`);
  text = text.replace(new RegExp(`${escape(standardsWin)}\\\\?`, "g"), "<projects>/");
  text = text.replace(new RegExp(`${escape(WIN_HOME)}\\\\projects\\\\?`, "g"), "<projects>/");
  text = text.replace(new RegExp(`${escape(WIN_HOME)}\\\\Icons`, "g"), "C:\\path\\to\\Icons");
  text = text.replace(/\(on Windows: `~\/\.claude\/\.env`\)/g, "(on Windows: `%USERPROFILE%\\.claude\\.env`)");
  return text;
}

const written = [];
const leftovers = [];

function copyFile(source, target) {
  const rel = path.relative(REPO, target);
  let data = fs.readFileSync(source);
  if (TEXT.test(source)) {
    const text = rewrite(data.toString("utf8"));
    for (const [index, line] of text.split(/\r?\n/).entries()) if (line.includes(USER) || line.includes(HOME)) leftovers.push(`${rel}:${index + 1}: ${line.trim().slice(0, 160)}`);
    data = Buffer.from(text, "utf8");
  }
  written.push(rel);
  if (DRY) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, data);
}

function copyTree(sourceRoot, targetRoot, relBase = "") {
  for (const name of fs.readdirSync(path.join(sourceRoot, relBase))) {
    const rel = path.join(relBase, name);
    if (EXCLUDE.some((pattern) => pattern.test(rel))) continue;
    const full = path.join(sourceRoot, rel);
    if (fs.statSync(full).isDirectory()) copyTree(sourceRoot, targetRoot, rel);
    else copyFile(full, path.join(targetRoot, rel));
  }
}

const outSkills = path.join(REPO, "skills");
if (!DRY) fs.rmSync(outSkills, { recursive: true, force: true });
for (const skill of SHIPPED) {
  const source = path.join(SKILLS, skill);
  if (!fs.existsSync(source)) throw new Error(`missing skill ${skill} in ${SKILLS}`);
  copyTree(SKILLS, outSkills, skill);
}
for (const extra of EXTRA) {
  if (!fs.existsSync(extra.from)) throw new Error(`missing ${extra.from}`);
  copyFile(extra.from, path.join(REPO, extra.to));
}

const setupDoc = path.join(outSkills, "setup", "project-setup.md");
if (!DRY) {
  const text = fs.readFileSync(setupDoc, "utf8");
  const note = "> **Paths in this document:** `~/.claude/skills` is your Claude Code skills folder (`%USERPROFILE%\\.claude\\skills` on Windows) and `<projects>` is the folder you keep projects in, recorded in your `~/.claude/CLAUDE.md` by the installer.\n\n";
  fs.writeFileSync(setupDoc, text.replace(/^(# [^\r\n]*\r?\n\r?\n)/, `$1${note}`));
}

const bytes = written.reduce((sum, rel) => sum + (DRY ? 0 : fs.statSync(path.join(REPO, rel)).size), 0);
console.log(`${DRY ? "would write" : "wrote"} ${written.length} files${DRY ? "" : `, ${(bytes / 1e6).toFixed(1)} MB`} into ${path.relative(process.cwd(), outSkills) || "skills"}/`);
if (leftovers.length) {
  console.log(`PERSONAL PATHS LEFT (${leftovers.length}); add a rewrite or edit the source:`);
  for (const line of leftovers) console.log(`  ${line}`);
  process.exitCode = 1;
}
