---
name: perfbudget
description: Optimise a Roblox place against a rendering budget in a loop. A survey playtest rides a fixed route of stops, holds a chase camera at eight headings at each, and estimates on-screen triangles (shadow pass included) and draw calls, with a breakdown by group, asset and mesh; runs are kept on disk and compared. The loop applies free rendering fixes (LOD distances, shadows, ranges) itself, keeping or reverting each by the next survey, and brings lossy art cuts to the user ranked with before/after shots. Use whenever the user invokes /perfbudget, asks to "optimise to a budget", "check tri counts / draw calls in a playtest", "run the perf survey", or "keep optimising until it hits budget". One of the two sanctioned ways (with /demo) for Claude to start a playtest, and only on the user's request.
---

# perfbudget: optimise to a budget, measured in Play

Optimising by feel stalls: each pass fixes what you happen to look at. `/perfbudget` measures the same route in the
same way every time, so every change is judged by a number against the last run, and the loop knows when it is done.
`<skill>` is this folder (`~/.claude/skills/perfbudget`); the project keeps `perf-source/` (route, mesh table, runs).

```
node <skill>/perf.js check                                   bridge, place, route, budget, triangle table, runs
node <skill>/perf.js survey --label baseline [--only a,b] [--frames]
node <skill>/perf.js report [RUN] [--vs RUN] [--top N]
node <skill>/perf.js tris [--full]                           refresh perf-source/meshtris.json (survey does it too)
node <skill>/perf.js cleanup                                 remove a leftover survey script after a crash
```

## When

- **Only when the user asks** (`/perfbudget`, or "run the survey / optimise to budget"). This is the second sanctioned
  exception to "never start or stop a playtest" (global `CLAUDE.md`; the first is `/demo`). Never start a playtest any
  other way.
- **Never while Studio is in use.** A playtest takes over the place for everyone. If the user is at the PC working in
  Studio, or another session may be editing the place, ask first. `perf.js` refuses if Studio's session log shows a
  playtest already running.
- **How the test is controlled** (shared with `/demo`, `studio/playtest.js`): the survey's lines are read from Studio's
  session log (the MCP's `get_playtest_output` never sees client prints), a server director `__PerfSurveyServer` ends
  the test through `StudioTestService:EndTest` when the survey is done or its load/max watchdog runs out, and `perf.js`
  waits for `StopPlaySoloEnd`, falls back to `stop_playtest`, and fails loudly (`THE PLAYTEST IS STILL RUNNING`) if
  the test is still alive. Tell the user at once if that happens.
- Code and map changes must be in the place (`/studio` `sync.js push`, the project's map rebuild) before a survey: it
  measures what is in Studio.

## What it measures, and what it does not

Roblox exposes neither draw calls nor rendered triangles to scripts, so the survey **estimates**, the same way every
run, which is what a loop needs:

| | How |
| --- | --- |
| Triangles | exact per mesh from `perf-source/meshtris.json`, read off the live `MeshId` (`ApplyMesh` rewrites it, so a LOD swap counts at the tier on screen); built from `LodTris0/1/2` / `Triangles` attributes, the rest counted once from an EditableMesh; unions use `TriangleCount`, primitives fixed counts |
| Draw calls | one per instancing group (same mesh, material and surface look), one per see-through part, one per shadow-casting mesh group inside `shadowRange`, plus decals, emitters, beams, trails, and highlights (2 each) on visible parts |
| Visible | inside the camera frustum and `maxDistance`, not fully transparent (`LocalTransparencyModifier` included), streamed in |
| Not modelled | occlusion culling, the client's quality-level distance culling, Terrain, UI, post effects, skinned-mesh cost |

So it is an **upper bound with a stable bias**: good for "did this change help, and where is the cost", not an exact
frame time. To check it against the real thing, run with `--frames` once with Studio's render stats overlay on: a
frame of the Studio window is saved at each stop's worst heading (`perf-source/runs/frames/`, never sent),
and you compare the overlay's numbers with the report. Say in the report if they disagree by more than ~25%.

## The route

`perf-source/route.json`: `stops` (name, `position` [x, y|null, z]; null y means the ground under it), the chase
`camera` (distance, height, lookAhead, lookHeight), `headings` (8), `settleSeconds` (time for LOD and streaming to
settle after a teleport), `headingSeconds`, `maxDistance`, `shadowRange`, `groupDepth` (how deep below Workspace the
"group" names go), and `budget` (`tris`, `draws`, both judged at the worst heading of every stop; tris include the
shadow pass). Pick stops where a player actually spends time, spread across every zone and compass sector, including
the views that see the most (overlooks, the hub). **Do not move stops between runs being compared**: add new ones.

## The loop

1. **Check:** `perf.js check`. Confirm with the user that Studio is free if there is any doubt.
2. **Baseline:** `perf.js survey --label baseline`. If `budget` is unset, stop here: show the user the stop table and
   the worst views' breakdowns, recommend numbers (worst stop, with headroom), and write the budget they choose into
   `route.json`. Never invent a budget silently.
3. **Pick the next fix** from the report: the largest contributor at the stops that are over budget. Weigh by how many
   over-budget stops it appears in, not one view alone.
4. **Classify it:**
   - **Free:** changes how things render, never what an asset looks like up close. LOD switch distances, render and
     fade ranges, `CastShadow` off on small or distant props, `RenderFidelity`, streaming settings, emitter rates and
     ranges, pooling and render caps for client-drawn things, highlights gated by distance. The loop applies these
     itself.
   - **Lossy:** anything that changes approved art or needs an upload: decimating or cutting a mesh, merging, new LOD
     tiers, a smaller texture, removing placed props, fewer things in a scene. These go to the user (step 7).
   - When unsure, it is lossy. A free fix that would be noticed inside ~100 studs is lossy.
5. **Apply one free fix (or one tight group of the same kind),** through the project's normal path (edit on disk,
   `sync.js push` or the map rebuild), and log it in `perf-source/ledger.md`: what changed, why, which stops it
   targets, and how to revert.
6. **Re-survey** with a label naming the fix, then `report --vs` the run before it. **Keep** it if the targeted metric
   fell by more than ~3% (wild knights move; smaller changes are noise) and no stop rose by more than that. **Revert**
   otherwise, and log the result either way. Repeat from 3 until every stop is within budget, free fixes run out, or
   six surveys have run this session (then report and ask before going on).
7. **Lossy proposals:** a ranked list (mesh or asset, instances on screen, estimated saving at the worst stops, what
   the cut would be), each with an `/assetshot` before/after at the distance it is actually seen. Nothing is cut,
   decimated or uploaded until the user approves that item; then build it through the project's asset pipeline and
   re-survey.
8. **Close:** the final stop table against the baseline, the ledger, what remains over budget and why. Offer `/demo`
   of the worst stop if the free fixes changed what a player sees at range.

## Rules

- One change per survey (or one tight group), or you cannot tell what helped.
- Never edit the place while the survey runs; it is the user's Studio.
- Runs are evidence: keep every `perf-source/runs/*.json` (small); never edit one by hand.
- If the report says meshes are unknown (counted as 0), run `tris` and say so; an unknown mesh hides cost.
- If a stop's focus lands on a roof or inside a wall (its `focus` y looks wrong), fix the stop's position before
  trusting it.

## Change Summary

A survey changes nothing in the place (the script is removed). Every kept fix is a change: close with the usual 2–3
sentence summary (`~/.claude/skills/setup/change-summary.md`), and the project docs wait for the user's
approval as always.
