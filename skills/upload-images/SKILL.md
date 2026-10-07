---
name: upload-images
description: Bulk-upload PNG/JPG files from the user's local filesystem to Roblox as Decal assets via Open Cloud. Iterates a directory, rate-limits to stay under the 120-req/min POST cap, polls each upload's Operation until complete, and prints a `filename → assetId` Lua-table map the user can paste into a config. Portable across every Roblox project.
---

# upload-images

Takes a directory of PNG / JPEG / BMP / TGA image files (or a single file) and uploads each as a **Decal** asset on the target creator (user or group) via the Open Cloud Assets API. Emits a Lua table mapping `<filename-without-ext> → <assetId>` so the user can paste the ids into their game config (e.g. `getConfig.Brainrots[id].Icon`).

## Usage

```
/upload-images <path> [--creator-type user|group] [--creator-id <id>] [--key <name>] [--describe <text>] [--prefix <string>] [--dry-run]
```

Examples:

- `/upload-images ./brainrot-icons --creator-type group --creator-id 5837437`
- `/upload-images C:\path\to\Icons --key GAME_GROUP --prefix "Brainrot "`
- `/upload-images ./icons/CappuccinoAssassino.png` — single file.
- `/upload-images ./icons --dry-run` — lists files that would be uploaded; no API calls.

If the user invokes without args, ask for the directory (and `--creator-type group` + `--creator-id` if not cached) before proceeding.

## Known gotcha — Decal ID vs Image ID (CONFIRMED BREAK at runtime)

The Open Cloud Assets API returns a **Decal asset ID**, which is a wrapper around the underlying image asset. At runtime in Roblox:

- `Decal.Texture` and `MeshPart.TextureID` accept the wrapper id directly → works.
- `ImageLabel.Image` / `ImageButton.Image` — **does NOT reliably unwrap at runtime.** Studio *does* auto-unwrap the Decal→Image on paste (so testing in the property window is misleading), but live clients frequently render nothing. Confirmed on Slope 2026-04-21. See: https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046

**You MUST resolve Decal → Image IDs before recording them anywhere a consumer will feed them into `ImageLabel.Image`.** Studio tests will lie to you otherwise. Conversion procedure: see "Step 4.5".

## Step 1 — Resolve the source files

If `<path>` is a directory, glob for `*.png`, `*.jpg`, `*.jpeg`, `*.bmp`, `*.tga` (case-insensitive). If it's a single file, use just that. Skip hidden files (`.*`).

Stop if no files match.

Roblox caps are **20 MB per file** and **< 8000×8000 pixels**. Warn (don't abort) if any file is larger — the upload will reject it with a descriptive error.

Emit a list of detected files up-front so the user can spot typos before any API calls.

## Step 2 — Resolve API key

Read `~/.claude/.env`. Resolution order — stop at the first hit:

1. `--key <name>` arg → look for `ROBLOX_OPEN_CLOUD_API_KEY_<name>` (allows per-group keys; e.g. `ROBLOX_OPEN_CLOUD_API_KEY_GAME_GROUP`).
2. When uploading to a group and `--key` wasn't passed, try `ROBLOX_OPEN_CLOUD_API_KEY_GROUP_<groupId>`.
3. Fall back to `ROBLOX_OPEN_CLOUD_API_KEY` (the default used by `create-devproduct` / `create-animation`).

The key needs **both** `asset:write` (for the POST) **and** `asset:read` (for polling the Operation). Bind the key to the target group if uploading to a group.

**Never echo the key in chat or error output.** Load into a shell variable only. Redact in any debug curl printout.

If no key is found, stop with:

> Create an Open Cloud API key at https://create.roblox.com/dashboard/credentials with the **`asset:write`** and **`asset:read`** scopes, bound to the group if uploading to a group. Append it to `~/.claude/.env` as `ROBLOX_OPEN_CLOUD_API_KEY_GROUP_<groupId>=<value>` (or `ROBLOX_OPEN_CLOUD_API_KEY_<NAME>` and pass `--key <NAME>`).

## Step 3 — Resolve creator (cached)

Share the same cache file that `create-animation` uses: `~/.claude/.roblox-animation-creator.json`:

```json
{ "type": "Group", "id": 34567890 }
```

Resolution order — stop at the first hit:

1. `--creator-type` + `--creator-id` args (always override).
2. Cached file.
3. Ask the user: *"Upload to which creator — your personal user (id N) or a group? If group, what's the group id?"* Then write the cache so it's remembered across every project.

**Group upload note** — the API key must be group-bound (or the user who owns the key must have permission to upload assets to that group).

## Step 4 — Upload loop

For each image file, sequentially:

### Build the request

```bash
KEY="$ROBLOX_OPEN_CLOUD_API_KEY_..."         # selected above
CREATOR_JSON='{"creator":{"groupId":"5837437"}}'  # or {"creator":{"userId":"N"}}
NAME="$(basename "$FILE" | sed 's/\.[^.]*$//')"   # strip extension
DISPLAY_NAME="${PREFIX}${NAME}"              # optional --prefix
MIME="image/png"                             # derive from extension
CREATION_CONTEXT=$(cat <<EOF
{
  "assetType": "Decal",
  "displayName": "$DISPLAY_NAME",
  "description": "$DESCRIPTION",
  "creationContext": $CREATOR_JSON
}
EOF
)

RESPONSE=$(curl -s -X POST "https://apis.roblox.com/assets/v1/assets" \
  -H "x-api-key: $KEY" \
  -F "request=$CREATION_CONTEXT;type=application/json" \
  -F "fileContent=@$FILE;type=$MIME")
```

Parse `operations/<id>` from `$RESPONSE.path`. If the response doesn't include a path, log the full body (key redacted) and move on to the next file.

### Poll the Operation

```bash
OP_ID="${RESPONSE_PATH#operations/}"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  sleep $attempt   # exponential-ish backoff: 1, 2, 3, ..., up to 10 s per wait
  POLL=$(curl -s -H "x-api-key: $KEY" \
    "https://apis.roblox.com/assets/v1/operations/$OP_ID")
  DONE=$(echo "$POLL" | jq -r '.done // false')
  if [ "$DONE" = "true" ]; then break; fi
done
ASSET_ID=$(echo "$POLL" | jq -r '.response.assetId // empty')
MOD_STATE=$(echo "$POLL" | jq -r '.response.moderationResult.moderationState // "Unknown"')
```

If polling times out, log the last body and move on. Moderation state can legitimately be `"Reviewing"` when done — the asset id is usable but the image may not render until the state becomes `"Approved"`. Report this state alongside the id.

### Rate limit between POSTs

Sleep **~600 ms** between uploads. The API cap is 120 POSTs/minute, so 600 ms keeps you at ~100/min with headroom for occasional retries.

### Collect results

Append to an in-memory map:

```
results[NAME] = { id = ASSET_ID, moderation = MOD_STATE }
```

On a 429 or `UploadFailed` response, retry the upload once after a 3-second wait; if it fails again, record the error and continue.

## Step 4.5 — Resolve each Decal ID to its inner Image ID (REQUIRED if the consumer is `ImageLabel.Image` / `ImageButton.Image`)

Skip only if every consumer will set `Decal.Texture` or `MeshPart.TextureID` (those unwrap). For any UI-image use, do this step or live renders break despite Studio "working."

**Preferred — Roblox Studio MCP**:

```lua
-- via mcp__robloxstudio__execute_luau, batch ~40 ids per call to keep payloads small:
local InsertService = game:GetService("InsertService")
local ids = { <decalIds...> }
local out = {}
for _, id in ipairs(ids) do
    local ok, asset = pcall(function() return InsertService:LoadAsset(id) end)
    if ok and asset then
        local decal = asset:FindFirstChildWhichIsA("Decal", true)
        if decal then
            table.insert(out, tostring(id) .. "=" .. tostring(decal.Texture:match("%d+")))
        end
        asset:Destroy()
    end
end
return table.concat(out, ",")
```

Parse the returned `decal=image` pairs and overwrite the value in the results map with the Image ID. `LoadAsset` works for group-owned decals from the place's universe; no extra auth needed.

**Fallback — HTTP (no MCP available)**:

```bash
# `assetdelivery.roblox.com/v1/asset?id=<decalId>` returns XML containing the inner asset URL.
IMAGE_ID=$(curl -s "https://assetdelivery.roblox.com/v1/asset?id=$DECAL_ID" \
    | grep -oE 'id=[0-9]+' | head -1 | cut -d= -f2)
```

This endpoint is public for published assets, but rate-limits faster than Open Cloud. Throttle to ~10 req/sec.

**Always** rewrite the `results[NAME] = { id = ... }` entry with the Image ID — never the Decal ID — when UI consumers are involved. Keep the Decal ID only in a side log for audit.

## Step 5 — Report

Print a summary:

```
Uploaded: 68 / 70
Failed:   2 (see below)
Moderation pending: 5 (ids still usable; may not render until approved)
```

Then print a Lua table the user can paste into their config:

```lua
return {
    CappuccinoAssassino = 129208148741484,
    TralaleroTralala = 123456789012345,
    BrrBrrPatapim = 99887766554433,
    -- ... etc
}
```

List any failed files with the error message, so the user can re-run just those.

Also print a JSON-mapped block for non-Lua callers:

```json
{
  "CappuccinoAssassino": 129208148741484,
  ...
}
```

## Step 6 — Optional: write back to a config (advanced)

If `--write-config <path.lua>` and `--config-key <dot.notation>` are passed:

1. Resolve the target config file (absolute path, or search under the current working directory).
2. Read the file as text.
3. Locate the table at `--config-key` (e.g. `Brainrots`) and, for each entry whose key matches an uploaded filename, inject or update an `Icon = <assetId>` field.
4. Write the file back preserving existing formatting.

This is an advanced operation — default to **off** and let the user paste the map themselves unless they explicitly request the write-back. String-based Lua patching is fragile; consider this a convenience, not a primary flow.

## Error handling

- **400** — usually `assetType` / MIME mismatch or invalid image dimensions. Dump the request body (key redacted) and the response so the user can inspect.
- **401** — key malformed or revoked. Re-check `~/.claude/.env` and the credentials dashboard.
- **403** — key lacks `asset:write` / `asset:read`, or isn't bound to the target creator. Fix at the dashboard.
- **413** — file > 20 MB. Name the file and skip.
- **429** — rate-limited. Backoff: `Retry-After` header (seconds) or default 5 s, then retry once.
- **Moderation rejection** — `moderationResult.moderationState = "Rejected"`. Record and surface to the user — the asset id will exist but won't render.

## Security

- Open Cloud API keys live in `~/.claude/.env` only. Never print, never commit, never paste into chat. Treat the same as `create-devproduct` / `create-animation`.
- Cached creator file (`~/.claude/.roblox-animation-creator.json`) stays in the user's home; never written into a project repo.
- Files being uploaded **go to Roblox as-is** — the user is responsible for confirming the images comply with Roblox ToS (no copyrighted art, no inappropriate content).

## References

- Open Cloud Assets API — https://create.roblox.com/docs/cloud/reference/assets
- Usage guide (canonical request shape) — https://create.roblox.com/docs/cloud/guides/usage-assets
- Rate limits — https://create.roblox.com/docs/cloud/reference/rate-limits
- Open Cloud credentials dashboard — https://create.roblox.com/dashboard/credentials
- Decal-ID vs Image-ID caveat — https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046
- `create-animation` sibling skill — `~/.claude/skills/create-animation/SKILL.md` (mirror patterns for key resolution, creator cache, and logging)

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
