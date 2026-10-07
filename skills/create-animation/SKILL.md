---
name: create-animation
description: Upload a KeyframeSequence as a persistent Animation asset and return its rbxassetid. Supports two paths — Studio MCP (AssetService:CreateAssetAsync, no API key, uploads via the logged-in user's credentials) and Open Cloud HTTP (needs a group-scoped API key + a pre-saved .rbxmx file on disk). Portable across every Roblox project.
---

# create-animation

Turns a KeyframeSequence into a permanent `rbxassetid://...` that works at runtime in any published game.

Two upload paths:

- **Studio MCP path** (default) — `AssetService:CreateAssetAsync` via the Studio MCP plugin. Uses the logged-in Studio user's credentials. Can upload to a group if the logged-in user has that group's "Configure group place assets" role. No API key needed.
- **Open Cloud path** (opt-in via `--file` or when `--creator-type group` is passed and a group-scoped API key is available in the env) — `POST /assets/v1/assets` with an `asset:write` API key bound to the target creator. Requires a pre-saved `.rbxmx` file.

## Usage

```
/create-animation <keyframeSequencePath | --file <rbxmxPath>> [--name <string>] [--description <string>] [--creator-type user|group] [--creator-id <id>] [--key <name>] [--write-attribute <targetPath>] [--write-animation-id <animationInstancePath>]
```

Examples:

- `/create-animation "workspace.Snowboard anims.AnimSaves.Snowboard Backflip"` → Studio path, caches creator on first run.
- `/create-animation "workspace.MyRig.AnimSaves.Idle" --creator-type group --creator-id 34567890` → Studio path, uploads to the group using the logged-in user's group role.
- `/create-animation --file C:\tmp\trick.rbxmx --creator-type group --creator-id 34567890 --key GAME_GROUP` → Open Cloud path, uses `ROBLOX_OPEN_CLOUD_API_KEY_GAME_GROUP` from `~/.claude/.env`.

If the user invokes without args, ask for the KeyframeSequence path (and `--name` if relevant) before proceeding.

## Step 0 — Follow the project's animation style

Before uploading, check the current project for an animation style guide: `features/animation-style.md` (or
`systems/animation-style.md`), which the project's `tech-design.md` names in its **Every animation follows the
project animation style** rule. If it exists, read it and make sure the clip follows it before it becomes an asset;
an uploaded clip that breaks the user's style is rework. If it reads **Unset**, settle the style with the user first.
If the project has no guide, carry on, and mention that `/setup` can add one.

## Step 1 — Pick a path

- If `--file <path>` was passed **or** `--creator-type group` is passed **and** a matching group API key env var is present → **Open Cloud path** (Step 4b). The Open Cloud route is preferred when available because it's credential-scoped (the key names the creator; no "I'm logged into the wrong account" risk).
- Otherwise → **Studio MCP path** (Step 4a).

In both cases, Step 2 (resolve source) and Step 3 (creator) still run.

## Step 2 — Resolve the source

**Instance path** (Studio path): `mcp__robloxstudio__get_instance_properties` on the path. Verify `ClassName == "KeyframeSequence"`. If it's an `AnimSaves` folder, list children and ask which one to upload.

**File path** (Open Cloud path): check that the file exists and ends in `.rbxmx` or `.rbxm`. If not, stop.

If the MCP is needed but isn't reachable, stop with:
> Open Studio with the MCP plugin active, then re-run.

## Step 3 — Resolve creator

**The animation MUST be owned by the same creator that owns the place it will run in.** Roblox refuses to load an animation whose creator doesn't match the experience's owner, and it fails **silently** — no error, no warning, `AnimationTrack.Length` stays 0 and the track simply never plays. It is indistinguishable from a wiring bug and will send you debugging the wrong system. This is not a preference; getting it wrong produces a dead asset.

So the place is the authority, not the cache. When the Studio MCP is reachable, read it:

```lua
return string.format("%s|%d", tostring(game.CreatorType), game.CreatorId)
```

`game.CreatorType` is `Enum.CreatorType.Group` or `Enum.CreatorType.User`; `game.CreatorId` is the group or user id. (On a never-published place both read 0 — treat that as "unknown" and fall through.)

Resolution order — stop at the first hit:

1. `--creator-type` + `--creator-id` args (explicit user intent always wins; useful for one-offs).
2. **`game.CreatorType` / `game.CreatorId` from the open place**, when non-zero. Use it, and *say so* in the report so the user can see which creator was chosen and why.
3. Cached file (below) — a fallback for the Open Cloud path or an unpublished place, never an override of the live place.
4. Ask the user: *"Upload to which creator — your personal user (id N) or a group? If group, what's the group id?"*

If the cache disagrees with the live place, **the place wins**. Warn once, don't silently follow the cache:
> Cached creator is Group N, but this place is owned by Group M — uploading to M so the animation will actually load.

Cache at `~/.claude/.roblox-animation-creator.json`:

```json
{ "type": "Group", "id": 34567890 }
```

The cache is a single value shared by **every project on the machine**, so it is wrong the moment you work on a place with a different owner. Only write it when the creator came from step 1 or step 4 (an explicit human answer) — never overwrite it from step 2, or one project's owner leaks into the next. Prefer keying new entries by place: `{ "byPlace": { "<placeId>": { "type": "Group", "id": M } }, "type": "Group", "id": N }`, reading `byPlace[placeId]` ahead of the top-level default.

**Group upload via Studio path** — logged-in user needs the group role permission **"Configure group place assets"** (aka "Create assets"). 403 on `CreateAssetAsync` = missing role. Surface the error and link https://create.roblox.com/dashboard/groups/<groupId>/settings so the user can fix the role. Studio does **not** need to be logged into the group; it just needs a user who has that permission on it.

## Step 4a — Studio path: `AssetService:CreateAssetAsync`

Call via `mcp__robloxstudio__execute_luau`:

```lua
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local target = <resolved instance via :FindFirstChild chain>
if not target or not target:IsA("KeyframeSequence") then
    return HttpService:JSONEncode({ ok = false, err = "not a KeyframeSequence" })
end

-- The live signature is `(instance, assetType, params)` where `params` is a
-- FLAT dictionary; CreatorType/CreatorId live at the top level, NOT nested
-- under a `Creator` sub-table. The nested form errors with
--   "unexpected option 'Creator'"
-- The older positional `(instance, creatorType, creatorId, assetType, ...)`
-- form errors with
--   "Unable to cast double to Dictionary"
-- Return is a multi-value tuple: (CreateAssetResult, assetId, operationId?).
-- Capture all three from the pcall — assetId is in r2, not r1.
local ok, result, assetId, operationId = pcall(function()
    return AssetService:CreateAssetAsync(
        target,
        Enum.AssetType.Animation,
        {
            Name = "<name or target.Name>",
            Description = "<description or "">",
            CreatorType = Enum.AssetCreatorType.<User|Group>,
            CreatorId = <id>,
        }
    )
end)

if not ok then
    return HttpService:JSONEncode({ ok = false, err = tostring(result) })
end

if result ~= Enum.CreateAssetResult.Success then
    return HttpService:JSONEncode({ ok = false, err = "CreateAssetResult: " .. tostring(result) })
end

return HttpService:JSONEncode({ ok = true, assetId = assetId, operationId = operationId })
```

Common errors:

- **HTTP 403** — logged-in user lacks the group's asset-create role. See Step 3 note.
- **Moderated** — Roblox flagged the asset. Rename the KeyframeSequence and retry.
- **`AssetService:CreateAssetAsync is not a valid member`** — Studio version / beta flag issue. Toggle "File → Beta Features → Asset API" or fall back to Open Cloud (Step 4b).

## Step 4b — Open Cloud path: `POST /assets/v1/assets`

### API key resolution

Read `~/.claude/.env`. Resolution order — stop at the first hit:

1. `--key <name>` arg → look for `ROBLOX_OPEN_CLOUD_API_KEY_<name>` (so per-group keys live side-by-side; e.g. `ROBLOX_OPEN_CLOUD_API_KEY_GAME_GROUP`).
2. When uploading to a group and `--key` wasn't passed, try `ROBLOX_OPEN_CLOUD_API_KEY_GROUP_<groupId>` — this lets the user cache a dedicated key per group with a predictable name.
3. Fall back to `ROBLOX_OPEN_CLOUD_API_KEY` (the default used by `create-devproduct`).

**Never echo the key in chat or in error output.** Load into a shell variable only. Redact in any debug curl printout.

If no key is found, stop with:

> Create an Open Cloud API key at https://create.roblox.com/dashboard/credentials with the **`asset:write`** scope, bound to the group if uploading to a group. Append it to `~/.claude/.env` as `ROBLOX_OPEN_CLOUD_API_KEY_GROUP_<groupId>=<value>` (or `ROBLOX_OPEN_CLOUD_API_KEY_<NAME>` and pass `--key <NAME>`).

### Request

```bash
KEY="$ROBLOX_OPEN_CLOUD_API_KEY_..."   # selected above
CREATOR_JSON='{"creator":{"groupId":"34567890"}}'   # or {"creator":{"userId":"N"}}
CREATION_CONTEXT=$(cat <<EOF
{
  "assetType": "Animation",
  "displayName": "$NAME",
  "description": "$DESCRIPTION",
  "creationContext": $CREATOR_JSON
}
EOF
)

curl -s -X POST "https://apis.roblox.com/assets/v1/assets" \
  -H "x-api-key: $KEY" \
  -F "request=$CREATION_CONTEXT;type=application/json" \
  -F "fileContent=@$FILE_PATH;type=model/x-rbxm-xml"
```

PowerShell equivalent — build the multipart with `Invoke-RestMethod -Form` and pass the same two parts (`request` JSON + `fileContent` file).

Response is an **Operation** envelope: `{"path": "operations/<op-id>", "done": false}`. Poll:

```bash
curl -s -H "x-api-key: $KEY" "https://apis.roblox.com/assets/v1/operations/<op-id>"
```

until `done: true`, then read `response.assetId`. Time out after ~60 s with the last body printed for the user to debug.

### Error handling (Open Cloud specific)

- **401** — key is malformed or revoked. Check `~/.claude/.env` and https://create.roblox.com/dashboard/credentials.
- **403** — key lacks `asset:write` scope, or isn't bound to the target group/user. Fix the scope or key binding.
- **400** — `.rbxmx` is malformed or the creationContext JSON doesn't match the API schema. Dump the request body (key redacted) so the user can inspect.

## Step 4c — Verify the asset actually loads (Studio MCP available)

Do not report success on the upload call's return value alone. A wrong-creator asset uploads perfectly and then never plays, so **prove it loads** before handing the id over or writing it into a config:

```lua
local rig = <any R15/R6 rig>:Clone()
rig.Parent = workspace
local humanoid = rig:FindFirstChildOfClass("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

local animation = Instance.new("Animation")
animation.AnimationId = "rbxassetid://<id>"
local track = animator:LoadAnimation(animation)
local deadline = os.clock() + 8
while track.Length == 0 and os.clock() < deadline do task.wait(0.1) end
rig:Destroy()
return track.Length   -- > 0 means it resolved; 0 after the timeout means it did NOT
```

`Length > 0` is the pass condition. **Exception:** a single-keyframe hold (a static idle pose) is legitimately 0 s, so `Length` can't discriminate for it — verify that one with `game:GetObjects("rbxassetid://<id>")` instead and check you get a `KeyframeSequence` back.

If verification fails, the near-certain cause is a creator mismatch (Step 3). Re-upload to the place's own creator rather than debugging the consumer.

**Idempotence.** `execute_luau` calls are occasionally delivered twice, and a duplicated upload silently creates a second asset and rewrites whatever you recorded. Guard each upload by writing the result onto the source `KeyframeSequence` as an `UploadedAssetId_<creatorId>` attribute and skipping any sequence that already has one. Scope the attribute by creator so re-uploading to a different owner isn't mistaken for a duplicate. Afterwards, trust the attribute you read back — not the value the upload call returned.

## Step 5 — Report and optionally write back

Report:

- Asset id (plain number and `rbxassetid://<id>`)
- Store link: `https://create.roblox.com/store/asset/<id>`
- The instance or file path that was uploaded
- Which path was used (Studio / Open Cloud)
- **The creator it was uploaded to, and where that came from** (place / arg / cache) — this is the field that goes wrong silently, so make it visible
- **The verification result** from Step 4c (`Length` in seconds, or the `GetObjects` fetch for a hold clip). If verification was skipped because the MCP wasn't reachable, say so explicitly rather than implying the id is known-good.

**Optional write-back targets** (both skipped silently if not passed):

- `--write-attribute <targetPath>`: set `Attribute "AnimationId" = "rbxassetid://<id>"` on the target instance via `mcp__robloxstudio__execute_luau`. Useful for data-driven configs.
- `--write-animation-id <animationInstancePath>`: set the `AnimationId` property of an existing `Animation` instance to `rbxassetid://<id>`. Warn and skip if the instance doesn't exist or isn't an `Animation`.

## Step 6 — Log (project-agnostic, opt-in by convention)

Only after the user approves the change (global `CLAUDE.md` § Documentation Waits for Approval): search cwd: `find . -maxdepth 2 -name "updatelog.md"`. If exactly one exists, append under today's date heading:

```
- Animation uploaded: <name> (<id>) from <source>
```

Match the existing `## YYYY-MM-DD — <title>` convention if a heading for today already exists. Don't fabricate `updatelog.md` in projects that don't use one.

## Security

- The Studio path uses the logged-in Studio user's credentials; no secret in this skill.
- Open Cloud API keys (any of `ROBLOX_OPEN_CLOUD_API_KEY*` variants) live in `~/.claude/.env` only. Never print, never commit, never paste into chat. Treat the same as `create-devproduct`.
- Cached creator file (`~/.claude/.roblox-animation-creator.json`) stays in the user's home; never written into a project repo.

## References

- `AssetService:CreateAssetAsync` — https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateAssetAsync
- Open Cloud Assets API — https://create.roblox.com/docs/cloud/reference/assets
- Open Cloud credentials dashboard — https://create.roblox.com/dashboard/credentials
- Group roles / "Configure group place assets" permission — https://create.roblox.com/docs/production/groups#roles
- Why `KeyframeSequenceProvider:RegisterKeyframeSequence` doesn't solve runtime use — https://create.roblox.com/docs/reference/engine/classes/KeyframeSequenceProvider/RegisterKeyframeSequence

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
