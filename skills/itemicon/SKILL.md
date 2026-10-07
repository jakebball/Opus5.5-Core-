---
name: itemicon
description: Render any Roblox model (a weapon, armour set, mount, pet, tool, prop, knight) as a transparent, tightly framed, outlined item icon PNG for UI, and optionally upload it as an Image asset and stamp its rbxassetid on the model. Use whenever a UI needs a picture of an in-game item, such as shop cards, inventory slots, index or collection pages, reward popups or tooltips, or the user says "render the model for the UI", "item icon", "transparent render", "make a picture of the lance", or invokes /itemicon. Works offline in headless Blender through /assetshot's icon mode, so it never moves Studio's camera. Set up for every Roblox project by /setup.
---

# itemicon: a model's picture for the UI

Shops, inventories and indexes read best when an item card shows the item itself rather than a generic icon. This
renders each model on its own, transparent and square, framed to the model and outlined like the UI's black
`UIStroke`. It can upload the result and record where it went. Rendering reads the model out of Studio without
changing anything, the same way `/assetshot` does, so any number of sessions can run it, even during a playtest.

## Command

```
node ~/.claude/skills/itemicon/icon.js <instance path...> --out-dir <project>\ui-source\renders\<Group> [options]
```

| Option | Does |
| --- | --- |
| `--size N` | Finished icon size in px (default 512). The render is twice this and then scaled down, so edges stay clean |
| `--view V` | `front`, `back`, `left`, `right`, `top`, `persp`, `persp-right`, `persp-back`, `persp-back-right`, or a direction `dx,dy,dz` in the model's frame (default `persp`, three-quarter front) |
| `--roll DEG` | Turns the picture about the view axis. A long item reads best on the diagonal |
| `--forward AXIS` | The way the model faces: `-z` (Roblox's LookVector, the default), `+z`, `-x`, `+x` |
| `--margin F` | Empty share of the square around the item (default 0.06) |
| `--outline PX` / `--outline-colour HEX` | Outline width at the finished size (default 6; `0` for none) and colour (default `000000`) |
| `--upload` | Uploads each icon as an Image asset through Studio (`AssetService:CreateAssetAsync`, as the logged-in user or the place's group) and prints its `rbxassetid` |
| `--attribute NAME` | With `--upload`, sets the id as this attribute on the source model (default `IconImage`; `none` skips it). UI code then reads `model:GetAttribute("IconImage")` from the template it already has |
| `--manifest FILE` | Merges `{ name: { file, source, assetId } }` into a JSON file. Keep one per project, e.g. `ui-source/renders/renders.json` |
| `--force` | Renders and uploads again even when the manifest already has the icon. Without it, done icons are skipped, so a run cut off by the bridge resumes where it stopped |
| `--port N`, `--samples N` | The Studio MCP port (default 58741 or `STUDIO_PORT`) and Cycles samples (default 48) |

Every target renders on its own to `<out-dir>/<ModelName>.png`. **Read a few with the Read tool on a coloured
backdrop before uploading** (composite with PIL): the transparent PNG alone hides a bad crop or a missing part.

## Angles that worked

From JoustTycoon's shops, 2026-10-06:

| Item | Options | Why |
| --- | --- | --- |
| Lance, sword, spear, any long thin item | `--view right --roll -45` | Side on, tip to the top right, across the diagonal, so it fills the square |
| Armour, outfit, character | `--view persp` | Three-quarter front shows the chest piece and one shoulder |
| Horse, mount, pet | `--view persp-right` | Three-quarter side shows the silhouette, head and tack |

## In the UI

- **Show it in an `ImageLabel`** with `ScaleType = Fit` and `BackgroundTransparency = 1`, inside a card or slot frame.
  The outline lets it sit on any card colour.
- **Find it through the model**, not a hard-coded table: an item's template already knows its icon.
- **New uploads take a moment to appear.** In the first minute after an upload, Studio can report `IsLoaded = true`
  while drawing nothing. To check whether the asset itself is fine, read it back
  (`AssetService:CreateEditableImageAsync(Content.fromUri(id))`); the picture appears on its own once Roblox serves it.
- **Re-render after a model changes**, with `--force`, and update anything that copied the old id.

## How it works

1. `/assetshot`'s `shot.js` with `--icon SIZE` exports the model from Studio (read-only) and renders it in Blender:
   orthographic, square, fitted to the model's extent across the view, transparent film, no labels and no sheet.
2. `finish.py` (PIL) trims to the opaque pixels, pads to a square with the margin, lays the outline under the item
   (its silhouette, grown and filled) and scales to `--size`.
3. With `--upload`, `icon.js` writes the PNG into an `EditableImage` in Studio in base64 chunks, calls
   `CreateAssetAsync`, stamps the attribute and records the manifest. Every bridge call carries a token so a repeat
   delivery never uploads twice, and dropped connections are retried.

About 4 s a model to render and 10 s to upload on the RTX 3060.

## Failure modes

| Symptom | Fix |
| --- | --- |
| `render failed` with an assetshot message | See `/assetshot`'s failure modes: wrong path, Studio busy, or no Blender |
| `the render is empty` | The model was fully transparent, or the path points at a folder |
| `fetch failed` that retries do not clear | Studio's plugin is busy or disconnected; run again once it answers (finished icons are skipped) |
| `CreateAssetAsync: ...` other than Success | Upload limits or moderation; wait and run again |
| The icon is too small in its card | Lower `--margin`, or pick a view that shows the item's long side |
