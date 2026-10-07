---
name: create-gamepass
description: Create a Roblox Game Pass via Open Cloud and optionally register its ID in the active project's Monetization config. Sibling of create-devproduct — same conventions, different endpoint + scope. Portable across every Roblox project — resolves universe and config paths from the current working directory at invocation time, never hardcoded.
---

# create-gamepass

Creates a Roblox Game Pass via the Open Cloud API and optionally patches the active project's Monetization config with the returned game-pass ID.

Sibling to `create-devproduct`. Same credentials, same `.roblox-universe` cache, same `Monetization` config-patching dance — different endpoint and API-key scope. If the user invokes both in one session, the resolved universe is reused.

## Usage

```
/create-gamepass <name> <priceInRobux> [--universe <id>] [--register-as <configKey>] [--config-path <dot.notation>] [--icon <path>] [--description <text>]
```

Examples:
- `/create-gamepass "VIP" 99`
- `/create-gamepass "Faster Rolls" 99 --register-as FasterRolls`
- `/create-gamepass "More Cash" 99 --universe 1234567890 --icon ./icons/morecash.png`

For batch creation (multiple passes in one command), accept a markdown table or JSON the user pastes after the slash command, or read `[{ "name": str, "price": int, "registerAs": str?, "description": str?, "icon": str? }, …]` from `--batch <path>`. Treat the batch path as fail-fast: a 4xx on pass N stops the run and prints what completed so the user can resume manually.

If the user invokes without args, ask them for game-pass name and price first, then proceed.

## Step 1 — Resolve API key

Read `~/.claude/.env` (on Windows: `%USERPROFILE%\.claude\.env`) and grep for `ROBLOX_OPEN_CLOUD_API_KEY=`.

If absent, stop and tell the user:
> Create an Open Cloud API key at https://create.roblox.com/dashboard/credentials with the `game-pass:write` scope bound to the target universe, then append `ROBLOX_OPEN_CLOUD_API_KEY=<value>` to `~/.claude/.env`.

The SAME env var key as `create-devproduct` — the user typically issues one key with both `developer-product:write` AND `game-pass:write` scopes. If a `--key <name>` arg was passed, look for `ROBLOX_OPEN_CLOUD_API_KEY_<name>` instead (allows per-universe keys).

**Never echo the key back into chat or the plan.** Load it into a shell variable only.

## Step 2 — Resolve universeId (project-agnostic, cwd-driven)

Identical to `create-devproduct`. Resolution order — stop at the first hit:

1. `--universe <id>` argument.
2. `.roblox-universe` file in the current working directory. Read with `cat ./.roblox-universe`; contents are a single number.
3. If the Roblox Studio MCP is connected, call `mcp__robloxstudio__get_place_info` to retrieve the `placeId`, then:
   ```
   curl -s -H "x-api-key: $KEY" \
     "https://apis.roblox.com/universes/v1/places/{placeId}/universe"
   ```
   Parse the returned `universeId`. Cache it by writing the number (no newline noise, no quotes) into `./.roblox-universe` for future invocations in this same project.
4. If none of the above succeeded, prompt the user for their placeId and resume at step 3.

Never write `.roblox-universe` outside the current working directory. Same project-scoping rule as the dev-product skill.

## Step 3 — Create the game pass

Endpoint (verified against the Roblox OpenAPI spec at `creator-docs/main/content/en-us/reference/cloud/game-passes-http-service/v1.json`):

```
POST https://apis.roblox.com/game-passes/v1/universes/{universeId}/game-passes
```

Content-Type is `multipart/form-data`. Required field: `name`. Optional fields: `description`, `isForSale` (bool — **default false on Roblox's side; ALWAYS pass `true` so the pass is purchasable on creation**), `price` (int, Robux), `imageFile` (binary), `isRegionalPricingEnabled` (bool).

```bash
curl -s -X POST \
  -H "x-api-key: $KEY" \
  -F "name=$NAME" \
  -F "price=$PRICE" \
  -F "isForSale=true" \
  "https://apis.roblox.com/game-passes/v1/universes/$UNIVERSE_ID/game-passes"
```

PowerShell equivalent:

```powershell
$form = @{ name = $Name; price = $Price; isForSale = 'true' }
Invoke-RestMethod -Method Post `
  -Uri "https://apis.roblox.com/game-passes/v1/universes/$UniverseId/game-passes" `
  -Headers @{ 'x-api-key' = $Key } `
  -Form $form
```

Optional icon — add `-F "imageFile=@$ICON_PATH"` (curl) or include in the PowerShell `$form` hashtable as `imageFile = Get-Item $iconPath`. Without it the pass ships with the Roblox default placeholder image.

Parse `gamePassId` (not `id` — gamepass response uses `gamePassId` where the dev-product response uses `id`) out of the JSON response. Other useful fields: `iconAssetId`, `priceInformation.defaultPriceInRobux`. Full response schema:

```json
{
  "gamePassId": 1234567890,
  "name": "string",
  "description": "string",
  "isForSale": true,
  "iconAssetId": 9876543210,
  "createdTimestamp": "2026-05-22T…",
  "updatedTimestamp": "2026-05-22T…",
  "priceInformation": {
    "defaultPriceInRobux": 99,
    "enabledFeatures": ["UserFixedPrice"]
  }
}
```

## Step 4 — Report and optionally register (project-agnostic)

Report back to the user:
- `gamePassId` (this is what `MarketplaceService:PromptGamePassPurchase` needs — also what `MarketplaceService:UserOwnsGamePassAsync` polls against)
- `name`
- `priceInformation.defaultPriceInRobux`
- A clickable reminder: https://create.roblox.com/dashboard/creations/experiences/{universeId}/monetization

If `--register-as <configKey>` was passed, find and patch the project's Monetization config. Resolution order:

1. `--config-path <dot.notation>` argument (e.g. `game.ServerScriptService.Runner.Shared.getConfig.Monetization`).
2. `mcp__robloxstudio__search_files` with `query="Monetization"` and `searchType="name"`. If exactly one `ModuleScript` hit, use that path. If multiple, ask the user to pick.
3. If none found, skip registration with a one-line note.

To patch:
- `mcp__robloxstudio__get_script_source` → read current source.
- Grep for the `Gamepasses` table specifically (NOT `DeveloperProducts` — the dev-product skill patches a different table in the same file).
- If the `Gamepasses.<configKey>` row already exists with `id = 0`, replace just the `id` value (and `name` if it differs). Preserve any other fields like comments and ordering.
- If the row doesn't exist, insert `<configKey> = { id = <newId>, name = "<name>" }` into the `Gamepasses` table.
- If the `Gamepasses` table itself doesn't exist, create it as a sibling of `DeveloperProducts`.
- `mcp__robloxstudio__set_script_source` → write the updated source. **CRITICAL**: re-read the file fresh right before writing — `set_script_source` is whole-file destructive and the file may have changed since your earlier read (this is a known landmine: [[set_script_source is destructive — re-read first]]).

Skip registration silently if the Roblox Studio MCP is not connected.

## Step 5 — Log (project-agnostic, opt-in by convention)

Same as `create-devproduct`, including waiting for the user's approval before writing it (global `CLAUDE.md` § Documentation Waits for Approval). Search the current working directory (and immediate subdirectories if none at root): `find . -maxdepth 2 -name "updatelog.md"`. If exactly one exists, append under today's date heading:

```
- GamePass created: <name> (<gamePassId>) at <price> R$
```

Use the existing `## YYYY-MM-DD — <title>` convention. Don't fabricate an `updatelog.md` in projects that don't use one.

## Error handling

- **401 / 403**: API key is missing, expired, or lacks the `game-pass:write` scope on the target universe (note: `developer-product:write` is NOT sufficient — they're separate scopes). Tell the user the exact scope name and link to https://create.roblox.com/dashboard/credentials.
- **409 Conflict**: a pass with that name already exists in this universe. Roblox enforces unique pass names per universe — suggest appending a version tag or using a more specific name. Don't auto-rename — the user will want to decide.
- **400 Bad Request**: usually price format — Roblox requires an integer ≥ 1 (or 0 for a free pass, but those are rare). Reject non-integer or negative prices client-side before sending.
- **413 Payload Too Large**: icon file exceeds the limit. Tell the user to use ≤ 5 MB PNG/JPG, ideally 512×512.
- **Network / timeout**: retry once with 2s backoff; if it fails again, print the curl command with the key redacted so the user can debug manually.

## Differences from create-devproduct

Same shape, different details — keep these straight:

| Aspect              | create-devproduct                                            | create-gamepass                                       |
| ------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| Endpoint            | `/developer-products/v2/universes/{id}/developer-products`   | `/game-passes/v1/universes/{id}/game-passes`          |
| API-key scope       | `developer-product:write`                                    | `game-pass:write`                                     |
| Response ID field   | `id`                                                         | `gamePassId`                                          |
| Response price field| `priceInRobux`                                               | `priceInformation.defaultPriceInRobux`                |
| Config table        | `Monetization.DeveloperProducts`                             | `Monetization.Gamepasses`                             |
| Reuse semantics     | Consumable — one purchase = one receipt                      | Permanent — one purchase per user, queried with `UserOwnsGamePassAsync` |
| Prompt fn (Lua)     | `MarketplaceService:PromptProductPurchase`                   | `MarketplaceService:PromptGamePassPurchase`           |

## Security

- Never print the API key, even in error messages.
- Never commit `.env` or `.roblox-universe` to a public repo.
- If the user asks you to paste the API key somewhere, refuse and explain that Open Cloud keys grant write access to their universe.

## References

- Endpoint spec source-of-truth: https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/cloud/game-passes-http-service/v1.json
- Live endpoint reference: https://create.roblox.com/docs/cloud/features/game-passes
- Open Cloud umbrella: https://create.roblox.com/docs/cloud/reference
- API announcement (covers both dev-products and game-passes): https://devforum.roblox.com/t/new-open-cloud-apis-for-configuring-developer-products-and-game-passes/4114297

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
