---
name: demo
description: Record a short phone-friendly video of a Roblox feature running in a real Studio playtest and send it to the user — for when they are away from the PC (on mobile) and cannot playtest themselves. A scripted demo (DemoKit: walk, camera moves, captions, real key presses, component calls) runs in Play while ffmpeg records; the clip is trimmed and cropped to the game view automatically. Use whenever the user invokes /demo, asks to "show me", "send a video", "record it", "demo the feature", or accepts the offer of a demo after a gameplay change. The ONE sanctioned way for Claude to start a playtest, and only on the user's request.
---

# demo: a video of the feature, recorded in Studio

The user is often away from the PC, on a phone, and cannot playtest. `/demo` plays the feature for them: a short
script drives the game in a real Studio playtest, ffmpeg records the screen, and the trimmed, cropped MP4 is sent to
them. `<skill>` is this folder (`~/.claude/skills/demo`).

```
node <skill>/demo.js check
node <skill>/demo.js record <project>/demo-source/<Feature>.luau [--server <Feature>.server.luau] [--name <Feature>]
node <skill>/demo.js cleanup
```

## When

- **Only when the user asks** (`/demo`, "show me", "send a video", or yes to the offer). This is the single exception
  to "never start or stop a playtest": `demo.js` starts and stops one for the recording. Never start a playtest any
  other way, and never record unasked.
- **Offer it after every gameplay change** (global `CLAUDE.md`): when a change alters what a player sees or does in
  play, end the reply with one line asking whether they want a demo of it. Not for docs, tooling, art-only or
  refactor-only changes.
- **Never while Studio is in use.** A playtest takes over the place for every session and the user. If another session
  might be editing the place, or the user is at the PC working in Studio, ask before recording.

## Before recording

1. `node <skill>/demo.js check`: ffmpeg found, the Studio bridge answers with the right place, a Studio window exists.
2. The PC must be **unlocked** with the display on: Windows records black frames from a locked screen. The Studio
   window is restored and brought to the front automatically; nothing may cover it during the recording.
3. Code changes must already be pushed to the place (`/studio` `sync.js push`); the demo plays what is in Studio.

## Writing the demo

A demo is a Luau file in the project's `demo-source/` folder (create it; keep demos, they are reusable regression
clips). Its body runs inside a LocalScript after the character spawns, with `Demo` in scope. Aim for 15–40 seconds:
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
| `Demo.key(keyCode, hold?)` | a **real** key press, sent through the Studio MCP (`simulate_keyboard_input`); allow ~0.6 s latency |
| `Demo.component(instance, tag)` | the instance's client component (EntityStore), to call its API directly |
| `Demo.camera.follow(subject?, distance, height)` | chase camera (subject defaults to the character) |
| `Demo.camera.fixed(position, lookAt)` / `moveTo(position, lookAt, seconds)` | a set shot, or a smooth move to one |
| `Demo.camera.orbit(subjectOrPosition, radius, height, seconds)` | one turn around the subject |
| `Demo.camera.reset()` | back to the player's camera |
| `Demo.log(text)` | `[demo] text` in the output |

- **Server setup** (spawn an NPC, grant gold, set a state) goes in an optional `<Feature>.server.luau`, passed with
  `--server`; it runs as a Script in `ServerScriptService` for the playtest only. Use the game's own components and
  admin paths, never a shortcut the real game does not have.
- **Mouse clicks are not simulated yet.** Press GUI buttons by calling the component behind them through
  `Demo.component`, and say so in the caption if it matters.
- Read the feature's doc and code first so the demo shows what changed, from where a player would see it.

## Recording

`record` installs the demo as `StarterPlayerScripts.__DemoDirector` (and `ServerScriptService.__DemoDirectorServer`),
brings Studio to the front, records the whole desktop with ffmpeg, starts the playtest, forwards `Demo.key` presses,
waits for the demo to finish (`--load` 90 s to start, `--max` 120 s to run), stops the playtest and ffmpeg, and removes
both scripts whatever happened (`cleanup` removes leftovers from a crash; the scripts also delete themselves outside
Studio). DemoKit flashes the game view magenta then green at the start and the end; `process` finds the flashes to trim the
clip and crop it to exactly the game view (only pixels that turn magenta and then green count, so nothing in the game
or on the desktop can fake it), then encodes H.264 at 720p-ish under 24 MB with a poster frame.
**No flash found means no clip**: the raw desktop recording is deleted, never sent, so nothing else on the screen
leaves the PC.

Then:

1. Look at the poster (`<clip>_poster.jpg`) before sending: is the feature in frame?
2. Send the MP4 with `SendUserFile` (`status: "proactive"` when the user is away, so it reaches the phone), with a
   one-line caption of what to watch for.
3. If the demo errored (`[demo] error:` in the output, also shown in the clip's caption), fix the demo and record again;
   do not send a broken clip as if it showed the feature.

## Limits

- It is a playback check, not a playtest: scripted inputs show the feature working, they do not find what a human
  would. Say so when the user is deciding whether a feature is done.
- One local player (no multi-client demos yet), no mouse simulation, Windows only (gdigrab).
- Studio's own panels are cropped away, but anything drawn over the game view (a notification, another window) is
  recorded, which is why the window is brought to the front first.

## Change Summary

Recording a demo changes nothing in the project (the scripts are removed); adding a file under `demo-source/` is a
change, so close with the usual 2–3 sentence summary (`~/.claude/skills/setup/change-summary.md`).
