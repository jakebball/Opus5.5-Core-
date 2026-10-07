---
name: create-devproduct
description: Create a Roblox Developer Product via Open Cloud and optionally register its ID in the active project's Monetization config. Portable across every Roblox project — resolves universe and config paths from the current working directory at invocation time, never hardcoded.
---

# create-devproduct

Creates a Roblox Developer Product via the Open Cloud API and optionally patches the active project's Monetization config with the returned product ID.

## Usage

```
/create-devproduct <name> <priceInRobux> [--universe <id>] [--v2] [--register-as <configKey>] [--config-path <dot.notation>]
```

Examples:
- `/create-devproduct "Golden Cappuccino" 49`
- `/create-devproduct "Rainbow Tralalero" 149 --register-as RainbowTralalero`
- `/create-devproduct "Double Coins" 75 --universe 1234567890 --v2`

If the user invokes without args, ask them for product name and price first, then proceed.

## Step 1 — Resolve API key

Read `~/.claude/.env` (on Windows: `%USERPROFILE%\.claude\.env`) and grep for `ROBLOX_OPEN_CLOUD_API_KEY=`.

If absent, stop and tell the user:
> Create an Open Cloud API key at https://create.roblox.com/dashboard/credentials with the `developer-product:write` scope bound to the target universe, then append `ROBLOX_OPEN_CLOUD_API_KEY=<value>` to `~/.claude/.env`.

If a `--key <name>` arg was passed, look for `ROBLOX_OPEN_CLOUD_API_KEY_<name>` instead (allows per-universe keys).

**Never echo the key back into chat or the plan.** Load it into a shell variable only.

## Step 2 — Resolve universeId (project-agnostic, cwd-driven)

Resolution order — stop at the first hit:

1. `--universe <id>` argument.
2. `.roblox-universe` file in the current working directory. Read with `cat ./.roblox-universe`; contents are a single number.
3. If the Roblox Studio MCP is connected, call `mcp__robloxstudio__get_place_info` to retrieve the `placeId`, then:
   ```
   curl -s -H "x-api-key: $KEY" \
     "https://apis.roblox.com/universes/v1/places/{placeId}/universe"
   ```
   Parse the returned `universeId`. Cache it by writing the number (no newline noise, no quotes) into `./.roblox-universe` for future invocations in this same project.
4. If none of the above succeeded, prompt the user for their placeId and resume at step 3.

Never write `.roblox-universe` outside the current working directory. This keeps the skill project-scoped — running it from any other Roblox project directory will cache that project's universeId separately.

## Step 3 — Create the product

Correct endpoint (verified against the Roblox OpenAPI spec on `creator-docs/main`):

```
POST https://apis.roblox.com/developer-products/v2/universes/{universeId}/developer-products
```

**Important**: path uses `developer-products` (with a dash). There's a twin endpoint at `/developerproducts` (no dash) that serves LIST only and returns 404 on POST — don't use it.

Content-Type is `multipart/form-data`. Required field: `name`. Optional fields: `description`, `isForSale` (bool), `price` (int, Robux), `imageFile` (binary), `isRegionalPricingEnabled` (bool).

```bash
curl -s -X POST \
  -H "x-api-key: $KEY" \
  -F "name=$NAME" \
  -F "price=$PRICE" \
  -F "isForSale=true" \
  "https://apis.roblox.com/developer-products/v2/universes/$UNIVERSE_ID/developer-products"
```

PowerShell equivalent:

```powershell
$form = @{ name = $Name; price = $Price; isForSale = 'true' }
Invoke-RestMethod -Method Post `
  -Uri "https://apis.roblox.com/developer-products/v2/universes/$UniverseId/developer-products" `
  -Headers @{ 'x-api-key' = $Key } `
  -Form $form
```

Parse `id` out of the JSON response. Response schema is `DeveloperProductConfigV2` — see https://create.roblox.com/docs/cloud/features/developer-products if fields change.

## Step 4 — Report and optionally register (project-agnostic)

Report back to the user:
- `id` (this is what `MarketplaceService:PromptProductPurchase` needs)
- `name`
- `priceInRobux`
- A clickable reminder: https://create.roblox.com/dashboard/creations/experiences/{universeId}/monetization

If `--register-as <configKey>` was passed, find and patch the project's Monetization config. Resolution order:

1. `--config-path <dot.notation>` argument (e.g. `game.ServerScriptService.Runner.Shared.getConfig.Monetization`).
2. `mcp__robloxstudio__search_files` with `query="Monetization"` and `searchType="name"`. If exactly one `ModuleScript` hit, use that path. If multiple, ask the user to pick.
3. If none found, skip registration with a one-line note — some projects don't use a Monetization config and that's fine.

To patch:
- `mcp__robloxstudio__get_script_source` → read current source.
- Grep for `DeveloperProducts` and/or `Gamepasses` tables.
- Insert `[<configKey>] = { id = <newId>, name = "<name>", price = <price> }` into the `DeveloperProducts` table, preserving existing entries, formatting, and comments.
- If `DeveloperProducts` table doesn't exist, create it as a sibling of whatever is there.
- `mcp__robloxstudio__set_script_source` → write the updated source.

Skip registration silently if the Roblox Studio MCP is not connected in this session.

## Step 5 — Log (project-agnostic, opt-in by convention)

Only after the user approves the change (global `CLAUDE.md` § Documentation Waits for Approval): search the current working directory (and immediate subdirectories if none at root): `find . -maxdepth 2 -name "updatelog.md"`. If exactly one exists, append under today's date heading:

```
- DevProduct created: <name> (<id>) at <price> R$
```

Use the existing `## YYYY-MM-DD — <title>` convention if the file already has an entry for today; otherwise add a new heading. Do not fabricate an `updatelog.md` in projects that don't use one.

## Error handling

- **401 / 403**: API key is missing, expired, or lacks the `developer-product:write` scope on the target universe. Tell the user the exact scope name and link to https://create.roblox.com/dashboard/credentials.
- **409 Conflict**: product with that name already exists in this universe. Suggest appending a version tag (e.g. `Golden Cappuccino v2`).
- **400 Bad Request**: usually price format — Roblox requires an integer ≥ 1. Reject anything non-integer or ≤ 0 client-side before even sending.
- **Network / timeout**: retry once with 2s backoff; if it fails again, print the curl command with the key redacted so the user can debug manually.

## Security

- Never print the API key, even in error messages.
- Never commit `.env` or `.roblox-universe` to a public repo (the skill itself is safe to commit; the env file is where the secret lives).
- If the user asks you to paste the API key somewhere, refuse and explain that Open Cloud keys grant write access to their universe.

## References

- Live endpoint reference: https://create.roblox.com/docs/cloud/features/developer-products
- Open Cloud umbrella: https://create.roblox.com/docs/cloud/reference
- v2 announcement: https://devforum.roblox.com/t/new-open-cloud-apis-for-configuring-developer-products-and-game-passes/4114297
- v1 URL confirmation: https://devforum.roblox.com/t/what-is-the-roblox-api-to-create-developer-products/2432757

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
