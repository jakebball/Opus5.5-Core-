#!/usr/bin/env bash
# Installs the Roblox + Claude Code team setup on macOS / Linux (Windows: install.ps1).
#   ./install.sh [--projects DIR] [--persona jarvis] [--claude-home DIR] [--skip-meshtools] [--skip-smoke]
# Studio itself is Windows/macOS; the skills are tested on Windows. On macOS set BLENDER if Blender is not on PATH:
#   export BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
PROJECTS="$HOME/RobloxProjects"
PERSONA=""
CLAUDE_HOME="$HOME/.claude"
SKIP_MESHTOOLS=0
SKIP_SMOKE=0
MESHTOOLS_COMMIT="01b74d5c25f799b7622b9a74e57266a83398bcfb"
BEGIN="<!-- roblox-claude-setup:begin -->"
END="<!-- roblox-claude-setup:end -->"
STAMP="$(date +%Y%m%d-%H%M%S)"
PROBLEMS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --projects) PROJECTS="$2"; shift 2 ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --claude-home) CLAUDE_HOME="$2"; shift 2 ;;
    --skip-meshtools) SKIP_MESHTOOLS=1; shift ;;
    --skip-smoke) SKIP_SMOKE=1; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done

say() { echo "  $1"; }
step() { echo; echo "== $1"; }

step "Toolchain"
if command -v node >/dev/null; then
  NODE_VERSION="$(node --version | tr -d v)"
  [ "${NODE_VERSION%%.*}" -lt 18 ] && PROBLEMS+=("Node $NODE_VERSION is older than 18: install Node 18+")
  say "node $NODE_VERSION"
else PROBLEMS+=("Node is not installed: install Node 18+ from https://nodejs.org"); fi
command -v git >/dev/null && say "$(git --version)" || PROBLEMS+=("git is not installed")
command -v claude >/dev/null && say "claude found" || PROBLEMS+=("Claude Code CLI not on PATH: https://code.claude.com")
BLENDER_BIN="${BLENDER:-}"
if [ -z "$BLENDER_BIN" ]; then
  if command -v blender >/dev/null; then BLENDER_BIN="$(command -v blender)"
  elif [ -x /Applications/Blender.app/Contents/MacOS/Blender ]; then BLENDER_BIN=/Applications/Blender.app/Contents/MacOS/Blender; fi
fi
[ -n "$BLENDER_BIN" ] && say "blender $BLENDER_BIN" || PROBLEMS+=("Blender 4.1+ not found: install it, or export BLENDER=/path/to/blender")

step "Skills -> $CLAUDE_HOME/skills"
SKILLS="$CLAUDE_HOME/skills"
BACKUP="$CLAUDE_HOME/backups/roblox-claude-setup-$STAMP"
mkdir -p "$SKILLS"
for skill in "$REPO"/skills/*/; do
  name="$(basename "$skill")"
  if [ -e "$SKILLS/$name" ]; then mkdir -p "$BACKUP"; mv "$SKILLS/$name" "$BACKUP/$name"; fi
  cp -R "$skill" "$SKILLS/$name"
  say "/$name"
done
[ -d "$BACKUP/assetshot/cache" ] && mv "$BACKUP/assetshot/cache" "$SKILLS/assetshot/cache" && say "kept the existing /assetshot cache"
[ -d "$BACKUP" ] && say "previous versions backed up to $BACKUP"

step "robloxMeshTools (MrChickenRocket/robloxMeshTools @ ${MESHTOOLS_COMMIT:0:7})"
KIT="$SKILLS/importmeshtools/vendor/robloxMeshTools"
OLD_KIT="$BACKUP/importmeshtools/vendor/robloxMeshTools"
mkdir -p "$(dirname "$KIT")"
if [ "$SKIP_MESHTOOLS" = 1 ]; then
  if [ -d "$OLD_KIT" ]; then mv "$OLD_KIT" "$KIT"; say "skipped the download; kept your existing copy"; else say "skipped; /blenderassets push needs it at $KIT"; fi
else
  TMP="$(mktemp -d)"
  if curl -fsSL "https://github.com/MrChickenRocket/robloxMeshTools/archive/$MESHTOOLS_COMMIT.tar.gz" | tar -xz -C "$TMP"; then
    rm -rf "$KIT"; mv "$TMP"/robloxMeshTools-* "$KIT"
    printf '# Vendored copy\n\n- Upstream: https://github.com/MrChickenRocket/robloxMeshTools\n- Commit: %s\n- Fetched: %s by install.sh\n\nDo not edit these files; upstream updates replace this folder wholesale.\n' "$MESHTOOLS_COMMIT" "$STAMP" > "$KIT/VENDORED.md"
    say "fetched into $KIT"
  elif [ -d "$OLD_KIT" ]; then mv "$OLD_KIT" "$KIT"; say "download failed; restored your previous copy"
  else PROBLEMS+=("Could not download robloxMeshTools; re-run when online"); fi
  rm -rf "$TMP"
fi

step "CLAUDE.md"
mkdir -p "$PROJECTS"
BLOCK="$(sed "s#<projects>#$PROJECTS#g" "$REPO/claude/CLAUDE.md")"
if [ -n "$PERSONA" ]; then
  [ -f "$REPO/claude/personas/$PERSONA.md" ] || { echo "no persona named $PERSONA"; exit 2; }
  BLOCK="$(cat "$REPO/claude/personas/$PERSONA.md")"$'\n\n'"$BLOCK"
  say "persona: $PERSONA"
fi
CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
EXISTING=""; REGISTERED=""
if [ -f "$CLAUDE_MD" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak-$STAMP"
  EXISTING="$(awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$CLAUDE_MD")"
  REGISTERED="$(awk -v b="$BEGIN" -v e="$END" '$0==b{inb=1;next} $0==e{inb=0} inb&&list{print} inb&&/^Known project update logs:/{list=1}' "$CLAUDE_MD")"
fi
{
  if [ -n "$(printf '%s' "$EXISTING" | tr -d '[:space:]')" ]; then printf '%s\n\n' "$EXISTING"; fi
  echo "$BEGIN"
  printf '%s\n' "$BLOCK"
  [ -n "$REGISTERED" ] && printf '%s\n' "$REGISTERED"
  echo "$END"
} > "$CLAUDE_MD.tmp"
mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
say "team block written to $CLAUDE_MD (between the roblox-claude-setup markers; anything else you had is kept)"
say "projects folder: $PROJECTS"

if [ "$SKIP_SMOKE" = 0 ] && command -v node >/dev/null && [ -n "$BLENDER_BIN" ]; then
  step "Smoke build (headless Blender)"
  OUT="$(mktemp -d)"
  if RESULT="$(BLENDER="$BLENDER_BIN" node "$SKILLS/blenderassets/blend.js" build "$SKILLS/blenderassets/examples/pumpkin_crate.py" --out "$OUT" 2>&1)" \
    && grep -q "built PumpkinCrate" <<<"$RESULT" && ! grep -Eq '^\s*(warn|error)' <<<"$RESULT"; then say "built PumpkinCrate: Blender works"
  else PROBLEMS+=("Smoke build failed: $RESULT"); fi
fi

step "Next, by hand"
say "1. Studio MCP plugin: https://github.com/boshyxd/robloxstudio-mcp/releases (archived; maintained fork: https://github.com/Chrrxs/robloxstudio-mcp),"
say "   into Studio's Plugins folder; turn on Game Settings > Security > Allow HTTP Requests in each place."
say "2. claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest"
say "3. Optional: merge claude/settings.example.json into $CLAUDE_HOME/settings.json"
say "4. Optional: ROBLOX_OPEN_CLOUD_API_KEY=... in $CLAUDE_HOME/.env (/create-devproduct, /create-gamepass, /upload-images)"
say "5. Open baseplate/RunnerBaseplate.rbxl in Studio, publish it as a new experience, then: /setup <ProjectName>"

if [ ${#PROBLEMS[@]} -gt 0 ]; then
  step "Needs attention"
  for problem in "${PROBLEMS[@]}"; do echo "  - $problem"; done
  exit 1
fi
echo; echo "Installed."
