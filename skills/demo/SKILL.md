---
name: demo
description: Record a short phone-friendly video of a Roblox feature running in a real Studio playtest and send it to the user — for when they are away from the PC (on mobile) and cannot playtest themselves. A scripted demo (DemoKit: walk, camera moves, captions, in-game key presses, component calls) runs in Play while ffmpeg records the Studio window; the clip is trimmed and cropped to the game view automatically. Use whenever the user invokes /demo, asks to "show me", "send a video", "record it", "demo the feature", or accepts the offer of a demo after a gameplay change. One of the two sanctioned ways (with /perfbudget) for Claude to start a playtest, and only on the user's request.
---

# demo: a video of the feature, recorded in Studio

The user is often away from the PC, on a phone, and cannot playtest. `/demo` plays the feature for them: a short
script drives the game in a real Studio playtest, ffmpeg records the Studio window, and the trimmed, cropped MP4 is
sent to them. `<skill>` is this folder (`~/.claude/skills/demo`).

```
node <skill>/demo.js check
node <skill>/demo.js record <project>/demo-source/<Feature>.luau [--server <Feature>.server.luau] [--name <Feature>]
node <skill>/demo.js cleanup
```

## When

- **Only when the user asks** (`/demo`, "show me", "send a video", or yes to the offer). This is one of the two exceptions
  to "never start or stop a playtest" (the other is `/perfbudget`): `demo.js` starts one, and the game ends it.
  Never start a playtest any other way, and never record unasked.
- **Offer it after every gameplay change** (global `CLAUDE.md`): when a change alters what a player sees or does in
  play, end the reply with one line asking whether they want a demo of it. Not for docs, tooling, art-only or
  refactor-only changes.
- **Never while Studio is in use.** A playtest takes over the place for every session and the user, and breaks other
  agents' Edit-mode previews. If another session might be using Studio, or the user is at the PC working in it, ask
  before recording.

## Before recording

1. `node <skill>/demo.js check`: ffmpeg (with `gfxcapture`), the Studio bridge with the right place, Studio's session
   log and its play state (must be "not running"), and the Studio window.
2. The PC must be **unlocked** with the display on, and the Studio window **not minimised** (window capture gets no
   frames from a minimised window; `record` restores it). Other windows may cover Studio: window capture records the
   Studio window only, never the rest of the desktop.
3. Code changes must already be pushed to the place (`/studio` `sync.js push`); the demo plays what is in Studio.

## Writing the demo

A demo is a Luau file in the project's `demo-source/` folder (create it; keep demos, they are reusable regression
clips). Its body runs inside a LocalScript with `Demo` in scope, after `Demo.ready()`. Aim for 15–40 seconds:
a title, the feature from a good angle, a caption naming what the viewer should notice.

```lua
Demo.title("Road boost", 1.5)
Demo.teleport(CFrame.new(0, 5, -180))
Demo.camera.follow(nil, 20, 8)
Demo.caption("Riding onto the road: the boost chevron eases in")
Demo.walkTo(Vector3.new(0, 5, 40), 20)
Demo.key("F", 0.2)
Demo.wait(2)
Demo.camera.orbit(Demo.root(), 24, 10, 6)
```

| Call | Does |
| --- | --- |
| `Demo.title(text, seconds)` | centred title card |
| `Demo.caption(text, seconds?)` / `Demo.clearCaption()` | caption bar along the bottom |
| `Demo.wait(seconds)` | pause |
| `Demo.character()`, `Demo.humanoid()`, `Demo.root()` | the local character (waits for it) |
| `Demo.teleport(cframeOrPosition)` | place the character |
| `Demo.walkTo(position, timeout?)` | walk there with `Humanoid:MoveTo`; returns whether it arrived |
| `Demo.face(position)` | turn the character toward a point |
| `Demo.key(keyCode, hold?)` | an in-game key press through the project's `InputManager.simulateKey` (same action path as the keyboard, no latency); retried for 5 s while the key is not bound yet, then an error. No InputManager: an error (use `Demo.component`). **Never an OS key press.** |
| `Demo.component(instance, tag, timeout?)` | the instance's client component (EntityStore), to call its API directly |
| `Demo.camera.follow(subject?, distance, height)` | chase camera (subject defaults to the character) |
| `Demo.camera.fixed(position, lookAt)` / `moveTo(position, lookAt, seconds)` | a set shot, or a smooth move to one |
| `Demo.camera.orbit(subjectOrPosition, radius, height, seconds)` | one turn around the subject |
| `Demo.camera.reset()` | back to the player's camera |
| `Demo.ready()` | waits for the game to be worth recording (below); runs by default, call it only to wait early |
| `Demo.begin()` | the start flash. Call it yourself after setup that should not be in the clip (waiting for NPCs, teleports); if the demo never calls it, it runs before the first line |
| `Demo.log(text)` | `[demo:<run>] text` in the output |

- **Readiness.** `Demo.ready()` waits for `game:IsLoaded()`, the character with its root part and Humanoid, a viewport
  size that holds still for 1 s, and the project's own check, then holds `--preroll` (1.5 s). The project's check is
  `demo-source/ready.luau`: a function body with `Demo` in scope that returns `true` when the game view is worth
  recording (JoustTycoon's: the `LoadingGui` gone from PlayerGui and the rider mounted). Write one for each project
  whose loading screen or spawn runs past the character's arrival; `--ready FILE` / `--no-ready` override it.
- **Server setup** (spawn an NPC, grant gold, set a state) goes in an optional `<Feature>.server.luau`, passed with
  `--server`; it runs inside the server director for the playtest only. Use the game's own components and admin paths,
  never a shortcut the real game does not have.
- **Mouse clicks are not simulated.** Press GUI buttons by calling the component behind them through `Demo.component`,
  and say so in the caption if it matters.
- **No `\n` escapes typed through the Bash tool** into Luau or JS: the Bash tool turns them into real line breaks. Write
  files with the Write/Edit tools.
- Read the feature's doc and code first so the demo shows what changed, from where a player would see it.

## Recording

`record` does all of this, and removes both scripts whatever happened (`cleanup` removes leftovers from a crash; the
scripts also delete themselves outside Studio):

1. Refuses if Studio's session log (`studio/studioLog.js`) shows a playtest running, finds that log (the one of the
   Studio behind the bridge port), and picks a run id (nonce). Every DemoKit line is `[demo:<run>] ...`; lines of other
   runs and other sessions are ignored.
2. Installs the demo as `StarterPlayerScripts.__DemoDirector`, and **always** a server director
   `ServerScriptService.__DemoDirectorServer` (with the `--server` body inside). The director ends the test from inside
   the game with `StudioTestService:EndTest` when the client reports done, when `Demo.begin` never comes within
   `--load` (90 s), or `--max` (120 s) after it.
3. Records the Studio window with ffmpeg `gfxcapture` (`--capture desktop` falls back to gdigrab of the whole desktop,
   which needs Studio in front and uncovered), then calls `start_playtest`, whose answer must be a real success and must
   be followed by a fresh `initiatePlaySolo` in the log within 10 s.
4. Follows the log every 250 ms and prints the game's lines and Studio's lifecycle (`start`, `success`, `playable`,
   `stopping`, `stopped`).
5. Waits for `StopPlaySoloEnd`. If it does not come within 15 s, calls `stop_playtest` and waits 15 s more; if the
   log still shows the test alive it fails with **THE PLAYTEST IS STILL RUNNING**: tell the user at once, nothing else
   may write to the place until it is stopped. A hard watchdog (`--load` + `--max` + 90 s) kills ffmpeg and runs the
   same stop path whatever hangs; Ctrl+C does too.
6. Checks the start against Studio: a start flash logged before `PlaySoloPlayableTotalTime` + 1 s was drawn before the
   game view was on screen, so the run is rejected (raise `--preroll` or tighten `ready.luau`).
7. Processes the raw recording. DemoKit flashes the game view **magenta then green** at the start and **magenta then
   blue** at the end. `process` prints every flash block it finds (`start@12.3-12.8s(58%)`), takes the first start
   block and the first end block after it (an end flash is never taken as a start), trims to them, crops to exactly the
   pixels that flashed, and encodes H.264 at 720p-ish under 24 MB with a poster frame. With no end flash it ends at the
   log's stop time and says so. **No start flash means no clip**: the raw recording is deleted, never sent.

Then:

1. Look at the poster (`<clip>_poster.jpg`) before sending: is the feature in frame?
2. Send the MP4 with `SendUserFile` (`status: "proactive"` when the user is away, so it reaches the phone), with a
   one-line caption of what to watch for.
3. If the demo errored (`DEMO ERROR` in the output, `[demo:<run>] error:` in the game lines, also shown in the clip's
   caption), fix the demo and record again; do not send a broken clip as if it showed the feature.

## Limits

- It is a playback check, not a playtest: scripted inputs show the feature working, they do not find what a human
  would. Say so when the user is deciding whether a feature is done.
- One local player (no multi-client demos), no mouse simulation, Windows only (gfxcapture / gdigrab), ffmpeg 8+ for
  window capture.
- Studio's own log cuts a line at ~1020 bytes: keep `Demo.log` lines short.
- The MCP server (Claude Code's `robloxstudio-mcp`) and the Studio plugin should be the same version; with a mismatch,
  `target`-routed calls time out. Nothing here depends on them (no `get_playtest_output`, no client targets, no
  simulated keyboard).

## Live mode (experimental, untested live)

Built 2026-10-07 (plan: `<project>/plans/live-demo-plan.md`); tested offline and in Studio Edit only, **no live run
yet**. It records the same `demo-source/` demo in the real Roblox Player instead of a Studio playtest, so it never
touches Studio and never starts a playtest. Only JoustTycoon has the game side so far. `live.js` and `playerLog.js`
hold it; the Studio path above is unchanged.

```
node <skill>/demo.js live check [--open]                 Player, logs, live config, bundle, ffmpeg, no session, unlocked
node <skill>/demo.js live bundle [demo.luau[=server.luau] ...]   regenerate the game-side bundle, then push + publish
node <skill>/demo.js live record <project>/demo-source/<Demo>.luau [--direct] [--join 120] [--load 90] [--max 120]
                                 [--keep-client] [--keep-raw] [--stats] [--capture window|desktop] [--out DIR]
node <skill>/demo.js live kill                           end the RobloxPlayerBeta the last record drove
```

- **Config** is the game's own `game-source/ServerStorage/LiveDemo/Config.luau` (`Enabled`, `TestPlaceId`,
  `UniverseId`, `OwnerUserIds`, `LoadSeconds`, `MaxSeconds`, `PrerollSeconds`): the server reads it as the security
  boundary and `live.js` parses the same file, so there is no second copy (the project has no `studio.json`).
- **Game side:** `LiveDemo` server and client components (`Components/Generic`). The hook is inert unless the player's
  UserId is in `OwnerUserIds`, `game.PlaceId == TestPlaceId` and `Enabled`; launch data (`{"d","n","b"[,"x"]}`, at most
  200 bytes, letters/digits/_ only) must name a demo in `ServerStorage.LiveDemo.Client.Demos`. No `loadstring`, no
  HttpService. The lobby reserves a server, stores the request in MemoryStore (`LiveDemoRequests`, 10 min) and
  teleports; the reserved server re-checks everything and refuses a bundle stamp that is not its own (`stale build`).
- **Bundle:** `live bundle` writes `ServerStorage/LiveDemo/{BuildStamp, Client/DemoKit, Client/Ready, Client/Demos/*,
  Server/*}` comment-stripped, with `demo-source/.live-bundle.json` as its manifest, compile-checks them and prints the
  `sync.js push` list. Then **publish the place from Studio**; reserved servers run the published version. A server
  half ships only when named (`JoustRework.luau=Jousting.server.luau`); it runs privileged on the live server with
  `context.player`, and things like `setTier` change the owner's real save, so review it like an admin command.
- **`record`** refuses a stale or unpushed bundle, a locked PC and a running Roblox session, opens
  `roblox://experiences/start?placeId=..&launchData=..` (never `roblox-player:`, cookies or tickets), finds the session
  log by its "Joining game" line (tray hand-off), records the Player window by hwnd from the reserved join, follows the
  `[demo:<nonce>]` lines (server status is relayed by the client), and ends 1.5 s after `done`: ffmpeg stops, the
  client is killed, `<clip>.stats.json` holds fps/ping/memory/server heartbeat, and the clip is processed as in Studio.
  An errored demo ends on a **magenta->red** flash and the clip is renamed `-ERROR`: never send it as the feature
  working. Watchdogs: no join in `--join`, no reserved join 60 s after the lobby, no start in `--load`, past `--max`,
  client gone, PC locked, hard cap, Ctrl+C.
- **Before the first live run** (plan § 9, T0): push the bundle and the components, publish, run `live check --open`
  once by hand (protocol prompt, sign-in, windowed mode, fixed graphics quality), and close Roblox on the phone
  (error 273). Then `live record demo-source/LiveSmoke.luau` (10 s), and the negatives: an unknown name
  (`--name Nope --allow-unknown-name`: the server must answer `refused`), a stale stamp (bundle and push a change
  without publishing: `stale build`), and `--direct`.

## Change Summary

Recording a demo changes nothing in the project (the scripts are removed); adding a file under `demo-source/` is a
change, so close with the usual 2–3 sentence summary (`~/.claude/skills/setup/change-summary.md`).
