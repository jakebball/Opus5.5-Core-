#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const { spawnSync } = require("child_process");

const SKILL_DIR = __dirname;
const CACHE_DIR = path.join(SKILL_DIR, "cache");
const MESH_CACHE = path.join(CACHE_DIR, "meshes");
// Textures are read at up to this many pixels a side (--image-limit) and averaged down in Studio above it. The image
// cache folder is named after the limit, so a copy read at another size is never reused.
const IMAGE_LIMIT = 1024;
const imageCacheDir = (limit) => path.join(CACHE_DIR, `images-${limit}`);
const DEFAULT_PORT = Number(process.env.STUDIO_PORT || 58741);
const studioBridge = (() => {
  try {
    return require(path.join(__dirname, "..", "studio", "bridge.js"));
  } catch {
    return null;
  }
})();

async function pickPort(options) {
  const fixed = options.port || (process.env.STUDIO_PORT ? Number(process.env.STUDIO_PORT) : undefined);
  if (!studioBridge) return fixed || DEFAULT_PORT;
  const placeId = options.placeId || studioBridge.readConfig(studioBridge.findProjectRoot()).placeId;
  return (await studioBridge.resolve({ port: fixed, placeId })).port;
}

const VIEWS = ["persp", "persp-back", "persp-right", "persp-back-right", "front", "back", "left", "right", "top", "bottom"];
const CLIP_VIEWS = ["side", "left", "chase", "chase-right", "front", "front-right", "back", "top"];
const CLIP_LAYOUTS = ["stack", "row", "separate"];
const CLIP_ENGINES = ["eevee", "cycles"];
const CLIP_DEFAULT_VIEWS = ["side", "chase"];
const CLIP_SECONDS = 6;
const CLIP_HOLD_SECONDS = 0.4;
const FORWARDS = ["-z", "+z", "-x", "+x"];
const DEFAULT_POSE = `local options = { label = ARGS.label, views = ARGS.views, focus = ARGS.focus, forward = ARGS.forward }
if ARGS.frame then
	options.frame = shot.pivot(shot.find(ARGS.frame))
end
if ARGS.studio then
	options.camera, options.fov, options.aspect = shot.studioCamera()
elseif ARGS.camera then
	options.camera = shot.pivot(shot.find(ARGS.camera))
	options.fov = ARGS.fov
end
shot.snap(options)`;
// Clip mode without --pose: clone each target 4,000 studs up, play every --clip on its copy, record the clip.
const DEFAULT_CLIP_POSE = `local LIFT = Vector3.new(0, 4000, 0)
local function counterpart(instance, original, copy)
	if instance == original then
		return copy
	end
	local names = {}
	local current = instance
	while current and current ~= original do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	if current ~= original then
		return nil
	end
	local found = copy
	for _, name in names do
		found = found and found:FindFirstChild(name)
	end
	return found
end
local originals = table.clone(shot.targets)
for _, clip in ARGS.clips do
	local owner = shot.find(clip.owner)
	local inside = false
	for _, original in originals do
		if owner == original or owner:IsDescendantOf(original) then
			inside = true
			break
		end
	end
	if not inside then
		table.insert(originals, if owner:IsA("Model") or owner:IsA("BasePart") then owner else owner:FindFirstAncestorWhichIsA("Model") or owner)
	end
end
local copies = {}
for index, original in originals do
	local copy = original:Clone()
	if not copy then
		error(original:GetFullName() .. " cannot be cloned (Archivable is off)", 0)
	end
	shot.temporary(copy)
	copy.Parent = workspace
	if copy:IsA("Model") then
		copy:PivotTo(original:GetPivot() + LIFT)
	elseif copy:IsA("BasePart") then
		copy.CFrame = original.CFrame + LIFT
	end
	copies[index] = copy
end
local function copyOf(instance)
	for index, original in originals do
		local found = counterpart(instance, original, copies[index])
		if found then
			return found
		end
	end
	error("clip: no copy of " .. instance:GetFullName(), 0)
end
local tracks = {}
for _, clip in ARGS.clips do
	local owner = copyOf(shot.find(clip.owner))
	for _, animation in clip.animations do
		table.insert(tracks, { animator = owner, animation = animation })
	end
end
shot.clip({ label = ARGS.label, targets = copies, tracks = tracks, root = if ARGS.root then copyOf(shot.find(ARGS.root)) else nil })`;

const USAGE = `usage: node shot.js <instance path...> [options]

Renders Studio instances offline in headless Blender. Studio's camera is never touched.

  --out DIR            where the sheet and tiles go (default: a fresh folder under the OS temp dir)
  --views a,b,c        ${VIEWS.join(", ")}
  --forward AXIS       the way the asset faces: ${FORWARDS.join(", ")} (default -z, Roblox's LookVector)
  --camera PATH        also render from this instance's CFrame (a Camera, part, attachment or bone)
  --view studio        render from Studio's current camera, read without moving it
  --fov N              vertical field of view for --camera (default 70)
  --focus x,y,z[,r[,dx,dy,dz]]   close-up of a point in the asset's frame; repeatable
  --frame PATH         the frame views and focus points are measured in (default: the first target's pivot)
  --pose FILE          Luau run in Studio before the snapshot; it poses things and calls shot.snap{...}
  --arg key=value      passed to the pose script as shot.args.key; repeatable
  --label TEXT         tile label for the default snapshot
  --samples N          Cycles samples per tile (default 24)
  --icon SIZE          icon mode: one square, transparent, orthographic SIZE x SIZE PNG per target, fitted tight,
                       with no labels and no sheet (the /itemicon skill drives this)
  --icon-view V        the icon's view: front, back, left, right, top, persp, persp-right, persp-back,
                       persp-back-right, or a direction dx,dy,dz in the asset's frame (default persp)
  --icon-roll DEG      turn the picture about the view axis, e.g. 45 to lay a lance across the diagonal
  --icon-padding F     frame size over the asset's extent (default 1.04)
  --icon-file PATH     write the icon here (one target only; default <out>/<label>.png)
  --image-limit N      largest texture side read from Studio (default ${IMAGE_LIMIT}); bigger textures are averaged down
  --name NAME          folder and sheet name
  --port N             Studio MCP port (default: found by /studio's bridge, else ${DEFAULT_PORT} or STUDIO_PORT)
  --place-id ID        only use a Studio with this place open (default: the project's studio.json)
  --blender PATH       Blender 4.1+ (default: newest under Program Files\\Blender Foundation, or BLENDER)
  --keep               keep scene.json and the preview textures beside the sheet (clip mode: and the frames)

Clip mode (an MP4 of an animation, sampled on a private copy in Edit, rendered frame by frame):
  --clip RIG=ANIM[,ANIM]  play ANIM (a KeyframeSequence or Animation path, or rbxassetid://N) on the Animator in RIG;
                       repeat for each rig. RIG may sit inside a target: pass the model that holds joined rigs
                       (a rider welded to a horse) as the target so they are copied together. A --pose script may
                       call shot.clip{...} itself instead
  --views a,b          clip cameras: ${CLIP_VIEWS.join(", ")} (default ${CLIP_DEFAULT_VIEWS.join(",")})
  --fps N              frames per second sampled and encoded (default 30)
  --loops N            how many times the clip plays in the video (default: about ${CLIP_SECONDS} s worth)
  --size WxH           each view's size (default 1280x720)
  --layout L           ${CLIP_LAYOUTS.join(", ")}: views stacked in one video (default), side by side, or one video each
  --travel T           auto (move forward at the clip's GroundSpeed attribute, default), off (in place) or studs/s
  --track on|off       cameras follow the travel (default on); off holds them still while the rig crosses
  --ground G           grid (checker, default), plain or off; --grid N sets the checker size (default 2 studs)
  --engine E           ${CLIP_ENGINES.join(", ")} (default eevee); --samples N per frame (eevee 16, cycles 8)
  --fov N              clip cameras' vertical field of view (default 30)
  --root PATH          the part travel and cameras follow (default: the first target's PrimaryPart)
  --no-label           no clip, view and time stamp on the frames`;

function parse(argv) {
  const options = { targets: [], args: {}, focus: [], clips: [] };
  for (let index = 0; index < argv.length; index++) {
    const item = argv[index];
    if (!item.startsWith("--")) {
      options.targets.push(item);
      continue;
    }
    const equals = item.indexOf("=");
    const flag = equals > 0 ? item.slice(2, equals) : item.slice(2);
    const inline = equals > 0 ? item.slice(equals + 1) : undefined;
    const value = () => {
      if (inline !== undefined) return inline;
      index += 1;
      if (index >= argv.length) throw new Error(`--${flag} needs a value`);
      return argv[index];
    };
    switch (flag) {
      case "out": options.out = value(); break;
      case "views": options.views = value().split(",").map((entry) => entry.trim()).filter(Boolean); break;
      case "forward": options.forward = value(); break;
      case "camera": options.camera = value(); break;
      case "view": options.view = value(); break;
      case "fov": options.fov = Number(value()); break;
      case "focus": options.focus.push(value().split(",").map(Number)); break;
      case "frame": options.frame = value(); break;
      case "pose": options.pose = value(); break;
      case "arg": {
        const pair = value();
        const split = pair.indexOf("=");
        if (split < 1) throw new Error(`--arg wants key=value, got ${pair}`);
        options.args[pair.slice(0, split)] = pair.slice(split + 1);
        break;
      }
      case "label": options.label = value(); break;
      case "samples": options.samples = Number(value()); break;
      case "icon": options.icon = { ...(options.icon || {}), size: Number(value()) }; break;
      case "icon-view": {
        const view = value();
        options.icon = { ...(options.icon || {}), view: view.includes(",") ? view.split(",").map(Number) : view };
        break;
      }
      case "icon-roll": options.icon = { ...(options.icon || {}), roll: Number(value()) }; break;
      case "icon-padding": options.icon = { ...(options.icon || {}), padding: Number(value()) }; break;
      case "icon-file": options.icon = { ...(options.icon || {}), file: path.resolve(value()) }; break;
      case "image-limit": options.imageLimit = Number(value()); break;
      case "name": options.name = value(); break;
      case "port": options.port = Number(value()); break;
      case "place-id": options.placeId = value(); break;
      case "blender": options.blender = value(); break;
      case "keep": options.keep = true; break;
      case "help": options.help = true; break;
      case "clip": {
        const spec = value();
        const split = spec.indexOf("=");
        const animations = split > 0 ? spec.slice(split + 1).split(",").map((entry) => entry.trim()).filter(Boolean) : [];
        if (split < 1 || !animations.length) throw new Error(`--clip wants <rig path>=<animation>[,<animation>], got ${spec}`);
        options.clips.push({ owner: spec.slice(0, split), animations });
        break;
      }
      case "fps": options.fps = Number(value()); break;
      case "loops": options.loops = Number(value()); break;
      case "size": {
        const match = /^(\d+)x(\d+)$/i.exec(value());
        if (!match) throw new Error("--size wants WIDTHxHEIGHT, e.g. 1280x720");
        options.size = [Number(match[1]), Number(match[2])];
        break;
      }
      case "layout": options.layout = value(); break;
      case "travel": options.travel = value(); break;
      case "track": options.track = value(); break;
      case "ground": options.ground = value(); break;
      case "grid": options.grid = Number(value()); break;
      case "engine": options.engine = value(); break;
      case "root": options.root = value(); break;
      case "no-label": options.noLabel = true; break;
      default: throw new Error(`unknown option --${flag}\n\n${USAGE}`);
    }
  }
  // a pose script may record clips with its own camera names, so only its names' spelling is checked here
  for (const view of options.views || []) {
    if (options.pose) {
      if (!/^[A-Za-z0-9_-]+$/.test(view)) throw new Error(`unknown view ${view}`);
    } else if (options.clips.length) {
      if (!CLIP_VIEWS.includes(view)) throw new Error(`unknown clip view ${view}; use ${CLIP_VIEWS.join(", ")}`);
    } else if (!VIEWS.includes(view)) {
      throw new Error(`unknown view ${view}; use ${VIEWS.join(", ")}`);
    }
  }
  if (options.fps !== undefined && !(options.fps >= 1 && options.fps <= 120)) throw new Error("--fps wants a number from 1 to 120");
  if (options.loops !== undefined && !(Number.isInteger(options.loops) && options.loops >= 1 && options.loops <= 200)) throw new Error("--loops wants a whole number from 1 to 200");
  if (options.size && !(options.size[0] >= 64 && options.size[1] >= 64 && options.size[0] <= 3840 && options.size[1] <= 2160)) throw new Error("--size wants 64x64 to 3840x2160");
  if (options.layout && !CLIP_LAYOUTS.includes(options.layout)) throw new Error(`--layout wants one of ${CLIP_LAYOUTS.join(", ")}`);
  if (options.travel !== undefined && !["auto", "off"].includes(options.travel) && !(Number(options.travel) >= 0)) throw new Error("--travel wants auto, off or a speed in studs/s");
  if (options.track !== undefined && !["on", "off"].includes(options.track)) throw new Error("--track wants on or off");
  if (options.ground !== undefined && !["grid", "plain", "off"].includes(options.ground)) throw new Error("--ground wants grid, plain or off");
  if (options.grid !== undefined && !(options.grid > 0.05)) throw new Error("--grid wants a checker size in studs");
  if (options.engine !== undefined && !CLIP_ENGINES.includes(options.engine)) throw new Error(`--engine wants one of ${CLIP_ENGINES.join(", ")}`);
  if (options.forward && !FORWARDS.includes(options.forward)) throw new Error(`--forward wants one of ${FORWARDS.join(", ")}`);
  for (const point of options.focus) if (point.length < 3 || point.some((value) => !Number.isFinite(value))) throw new Error("--focus wants x,y,z[,radius[,dx,dy,dz]]");
  if (options.view && options.view !== "studio") throw new Error("--view only takes studio");
  if (options.imageLimit !== undefined && !(Number.isInteger(options.imageLimit) && options.imageLimit >= 16 && options.imageLimit <= 4096)) throw new Error("--image-limit wants a whole number from 16 to 4096");
  return options;
}

async function call(port, code, timeoutMs) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name: "execute_luau", arguments: { code } } }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.text();
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (message.error) throw new Error(`JSON-RPC error: ${JSON.stringify(message.error)}`);
  const inner = message.result && message.result.content && message.result.content[0] && message.result.content[0].text;
  let result;
  try {
    result = JSON.parse(inner);
  } catch {
    throw new Error(`unexpected tool reply: ${String(inner).slice(0, 400)}`);
  }
  if (result.success === false) throw new Error(`execute_luau failed: ${result.error || result.message}`);
  return result.returnValue;
}

function bracket(text) {
  for (let level = 1; level < 40; level++) {
    const equals = "=".repeat(level);
    if (!text.includes("]" + equals + "]")) return ["[" + equals + "[\n", "]" + equals + "]"];
  }
  throw new Error("no free long-bracket level");
}

function luaString(text) {
  return JSON.stringify(text);
}

function buildCode(runId, args, pose) {
  const template = fs.readFileSync(path.join(SKILL_DIR, "export.luau"), "utf8").replace(/\r\n/g, "\n");
  const json = JSON.stringify(args);
  const [open, close] = bracket(json);
  return template
    .replace("__RUN_ID__", () => runId)
    .replace("__ARGS__", () => open + json + close)
    .replace("__POSE__", () => pose);
}

const pollCode = (runId) => `local job = _G.AssetShot and _G.AssetShot[${luaString(runId)}]
if not job then return "MISSING" end
if job.state == "done" then return "DONE " .. #job.chunks .. " " .. job.bytes end
if job.state == "error" then return "ERROR " .. tostring(job.error) end
return "PENDING " .. tostring(job.progress)`;
const fetchCode = (runId, index) => `return _G.AssetShot[${luaString(runId)}].chunks[${index}]`;
const releaseCode = (runId) => `if _G.AssetShot then _G.AssetShot[${luaString(runId)}] = nil end return "released"`;

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function writeAtomic(file, data) {
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temporary, data);
  try {
    fs.renameSync(temporary, file);
  } catch (error) {
    fs.rmSync(temporary, { force: true });
    throw error;
  }
}

function knownCache(imageCache) {
  const known = {};
  if (fs.existsSync(MESH_CACHE)) {
    for (const file of fs.readdirSync(MESH_CACHE)) {
      const match = file.match(/^(.*?)(\.uv)?\.json$/);
      if (!match) continue;
      const key = decodeURIComponent(match[1]);
      if (match[2] || !known[key]) known[key] = match[2] ? "uv" : "nouv";
    }
  }
  if (fs.existsSync(imageCache)) {
    for (const file of fs.readdirSync(imageCache)) {
      const match = file.match(/^(.*)\.png$/);
      if (match) known[decodeURIComponent(match[1])] = "png";
    }
  }
  return known;
}

function meshFile(key, hasUV) {
  return path.join(MESH_CACHE, `${encodeURIComponent(key)}${hasUV ? ".uv" : ""}.json`);
}

function saveMesh(key, data) {
  try {
    fs.mkdirSync(MESH_CACHE, { recursive: true });
    writeAtomic(meshFile(key, data.hasUV), JSON.stringify(data));
    if (data.hasUV && fs.existsSync(meshFile(key, false))) fs.rmSync(meshFile(key, false), { force: true });
  } catch {
    return;
  }
}

function loadMesh(key) {
  for (const file of [meshFile(key, true), meshFile(key, false)]) {
    if (fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, "utf8"));
  }
  return null;
}

let crcTable;
function crc32(buffer) {
  if (!crcTable) {
    crcTable = new Uint32Array(256);
    for (let index = 0; index < 256; index++) {
      let value = index;
      for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
      crcTable[index] = value >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (const byte of buffer) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, checksum]);
}

function writePng(file, width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let row = 0; row < height; row++) rgba.copy(raw, row * (stride + 1) + 1, row * stride, (row + 1) * stride);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  writeAtomic(file, Buffer.concat([signature, pngChunk("IHDR", header), pngChunk("IDAT", zlib.deflateSync(raw)), pngChunk("IEND", Buffer.alloc(0))]));
}

function robloxContentRoots() {
  const versions = path.join(process.env.LOCALAPPDATA || "", "Roblox", "Versions");
  if (!fs.existsSync(versions)) return [];
  return fs
    .readdirSync(versions)
    .map((entry) => path.join(versions, entry, "content"))
    .filter((folder) => fs.existsSync(folder))
    .sort((first, second) => fs.statSync(second).mtimeMs - fs.statSync(first).mtimeMs);
}

function localContent(relative) {
  for (const root of robloxContentRoots()) {
    const file = path.join(root, relative);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

function findBlender(explicit) {
  if (explicit) return explicit;
  if (process.env.BLENDER) return process.env.BLENDER;
  const found = [];
  for (const base of [process.env.ProgramFiles, process.env["ProgramFiles(x86)"]].filter(Boolean)) {
    const root = path.join(base, "Blender Foundation");
    if (!fs.existsSync(root)) continue;
    for (const entry of fs.readdirSync(root)) {
      const exe = path.join(root, entry, "blender.exe");
      const version = entry.match(/(\d+)\.(\d+)/);
      if (version && fs.existsSync(exe)) found.push({ exe, major: Number(version[1]), minor: Number(version[2]) });
    }
  }
  found.sort((first, second) => second.major - first.major || second.minor - first.minor);
  const pick = found.find((item) => item.major > 4 || (item.major === 4 && item.minor >= 1));
  if (!pick) throw new Error("Blender 4.1+ not found; install it or pass --blender PATH");
  return pick.exe;
}

function slug(text) {
  return String(text).replace(/[^A-Za-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "shot";
}

async function exportScene(port, args, pose, log) {
  const runId = `shot${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
  let startProblem = null;
  try {
    const reply = String(await call(port, buildCode(runId, args, pose), 60000));
    if (!reply.startsWith("started")) throw new Error(`unexpected reply from Studio: ${reply}`);
  } catch (error) {
    if (!/timeout|timed out|aborted/i.test(error.message)) throw error;
    startProblem = error;
    log("  studio   busy; waiting for the export to start");
  }
  const missingGrace = Date.now() + (startProblem ? 180000 : 0);
  const deadline = Date.now() + 10 * 60 * 1000;
  let chunkCount = 0;
  let lastProgress = "";
  for (;;) {
    if (Date.now() > deadline) throw new Error("timed out waiting for Studio");
    await sleep(500);
    let state;
    try {
      state = String(await call(port, pollCode(runId), 20000));
    } catch (error) {
      continue;
    }
    if (state.startsWith("DONE ")) {
      chunkCount = Number(state.split(" ")[1]);
      break;
    }
    if (state.startsWith("ERROR ")) throw new Error(`Studio: ${state.slice(6)}`);
    if (state === "MISSING") {
      if (Date.now() < missingGrace) continue;
      throw new Error(startProblem ? `Studio never started the export (${startProblem.message}); run again when it is free` : "the export is gone from Studio (did the plugin restart?); run again");
    }
    const progress = state.slice(8);
    if (progress !== lastProgress) {
      lastProgress = progress;
      log(`  studio   ${progress}`);
    }
  }
  const pieces = [];
  for (let index = 1; index <= chunkCount; index++) pieces.push(String(await call(port, fetchCode(runId, index), 60000)));
  await call(port, releaseCode(runId), 20000).catch(() => {});
  return JSON.parse(pieces.join(""));
}

function mergeCaches(payload, imageCache, scratchDir) {
  const meshes = payload.meshes || {};
  for (const [key, data] of Object.entries(meshes)) if (!key.startsWith("object:")) saveMesh(key, data);
  const failedMeshes = Array.isArray(payload.failedMeshes) ? {} : payload.failedMeshes || {};
  for (const key of payload.meshKeys || []) {
    if (meshes[key] || failedMeshes[key]) continue;
    const cached = loadMesh(key);
    if (cached) meshes[key] = cached;
    else failedMeshes[key] = "not in the cache and not exported";
  }
  const images = {};
  const scratch = [];
  const failedImages = Array.isArray(payload.failedImages) ? {} : payload.failedImages || {};
  for (const [key, entry] of Object.entries(payload.images || {})) {
    if (key.startsWith("local:")) {
      const file = localContent(key.slice(6));
      if (file) images[key] = file;
      else failedImages[key] = "not found in the local Roblox content folder";
    } else if (key.startsWith("asset:")) {
      // a live EditableImage gets a fresh key every run, so its texture goes beside the scene file and is removed
      // with it; an uploaded image is cached by its asset id
      const preview = key.startsWith("asset:object-");
      const file = path.join(preview ? scratchDir : imageCache, `${encodeURIComponent(key)}.png`);
      const rgba = entry.base64 ? Buffer.from(entry.base64, "base64") : entry.rgba ? Buffer.from(entry.rgba, "hex") : null;
      if (rgba && rgba.length !== entry.width * entry.height * 4) {
        failedImages[key] = `texture arrived as ${rgba.length} bytes, expected ${entry.width}x${entry.height} RGBA`;
      } else if (rgba) {
        try {
          fs.mkdirSync(path.dirname(file), { recursive: true });
          writePng(file, entry.width, entry.height, rgba);
          if (preview) scratch.push(file);
        } catch (error) {
          failedImages[key] = `could not cache: ${error.message}`;
        }
      }
      if (fs.existsSync(file)) images[key] = file;
      else if (!failedImages[key]) failedImages[key] = "not loaded";
    } else if (!failedImages[key]) {
      failedImages[key] = "unsupported content address";
    }
  }
  return { meshes, images, failedMeshes, failedImages, scratch };
}

function render(blender, scenePath, outDir) {
  const result = spawnSync(blender, ["-b", "--factory-startup", "--python-exit-code", "1", "-P", path.join(SKILL_DIR, "render.py"), "--", scenePath, outDir], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const lines = `${result.stdout || ""}\n${result.stderr || ""}`.split(/\r?\n/);
  const reportLine = [...lines].reverse().find((line) => line.startsWith("ASSETSHOT "));
  if (!reportLine) {
    const errors = lines.filter((line) => /error|Traceback|File "/i.test(line)).slice(-25).join("\n");
    throw new Error(`Blender failed (exit ${result.status}, ${blender})\n${errors || lines.slice(-25).join("\n")}`);
  }
  return JSON.parse(reportLine.slice("ASSETSHOT ".length));
}

function summarise(map, limit) {
  return Object.entries(map)
    .slice(0, limit)
    .map(([key, value]) => `${key}: ${String(value).slice(0, 140)}`);
}

function findFfmpeg() {
  if (process.env.FFMPEG && fs.existsSync(process.env.FFMPEG)) return process.env.FFMPEG;
  const onPath = spawnSync(process.platform === "win32" ? "where" : "which", ["ffmpeg"], { encoding: "utf8" });
  const first = onPath.status === 0 ? onPath.stdout.split(/\r?\n/)[0].trim() : "";
  if (first) return first;
  const local = process.env.LOCALAPPDATA || "";
  const link = path.join(local, "Microsoft", "WinGet", "Links", "ffmpeg.exe");
  if (fs.existsSync(link)) return link;
  const packages = path.join(local, "Microsoft", "WinGet", "Packages");
  if (fs.existsSync(packages)) {
    for (const folder of fs.readdirSync(packages).filter((name) => name.startsWith("Gyan.FFmpeg"))) {
      for (const build of fs.readdirSync(path.join(packages, folder))) {
        const candidate = path.join(packages, folder, build, "bin", "ffmpeg.exe");
        if (fs.existsSync(candidate)) return candidate;
      }
    }
  }
  throw new Error("ffmpeg not found: install it (winget install Gyan.FFmpeg) or set FFMPEG to ffmpeg.exe");
}

function ffmpegRun(ffmpeg, args) {
  const result = spawnSync(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", ...args], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`ffmpeg failed: ${String(result.stderr || result.error).slice(-800)}`);
}

function frameFile(dir, index) {
  return path.join(dir, `${String(index).padStart(4, "0")}.jpg`);
}

// One clip's frames -> phone-ready H.264 (yuv420p, faststart), views stacked or side by side. One play is encoded and
// then repeated `plays` times by stream copy, so the loops cost nothing to encode; a one-shot clip holds its last frame
// a moment before it starts again.
function encodeClip(ffmpeg, clip, layout, outDir) {
  const fps = clip.fps;
  const frames = clip.rendered;
  const plays = clip.loopsRendered > 1 ? 1 : clip.loops;
  const hold = !clip.loop && plays > 1 ? Math.round(CLIP_HOLD_SECONDS * fps) : 0;
  for (const view of clip.views) for (let index = 0; index < hold; index++) fs.copyFileSync(frameFile(view.dir, frames - 1), frameFile(view.dir, frames + index));
  const input = (view) => ["-framerate", String(fps), "-start_number", "0", "-i", path.join(view.dir, "%04d.jpg")];
  const base = slug(clip.label);
  const joined = layout !== "separate" && clip.views.length > 1;
  const width = joined && layout === "row" ? clip.size[0] * clip.views.length : clip.size[0];
  const height = joined && layout === "stack" ? clip.size[1] * clip.views.length : clip.size[1];
  // the lowest H.264 level the frame size allows (macroblocks a frame), so older phones still play it
  const macroblocks = Math.ceil(width / 16) * Math.ceil(height / 16);
  const level = macroblocks <= 8192 ? ["-level:v", "4.1"] : macroblocks <= 22080 ? ["-level:v", "5.1"] : [];
  const encode = ["-c:v", "libx264", "-preset", "medium", "-crf", "22", "-profile:v", "high", ...level, "-pix_fmt", "yuv420p", "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-maxrate", "6M", "-bufsize", "12M", "-movflags", "+faststart", "-r", String(fps), "-an"];
  const limited = "scale=out_range=tv:out_color_matrix=bt709,format=yuv420p";
  const jobs = joined
    ? [{ file: `${base}.mp4`, args: [...clip.views.flatMap(input), "-filter_complex", `${clip.views.map((_, index) => `[${index}:v]`).join("")}${layout === "row" ? "hstack" : "vstack"}=inputs=${clip.views.length},${limited}[video]`, "-map", "[video]"] }]
    : clip.views.map((view) => ({ file: clip.views.length === 1 ? `${base}.mp4` : `${base}_${slug(view.name)}.mp4`, args: [...input(view), "-vf", limited] }));
  const picks = [...new Set(Array.from({ length: 8 }, (_, index) => Math.round((index * (frames - 1)) / 7)))];
  const strip = path.join(outDir, `${base}_strip.png`);
  const outputs = [];
  for (const job of jobs) {
    const file = path.join(outDir, job.file);
    const once = plays > 1 ? file.replace(/\.mp4$/i, ".once.mp4") : file;
    ffmpegRun(ffmpeg, [...job.args, ...encode, once]);
    if (!outputs.length) ffmpegRun(ffmpeg, ["-i", once, "-vf", `select='${picks.map((frame) => `eq(n\\,${frame})`).join("+")}',scale=480:-2,tile=4x${Math.ceil(picks.length / 4)}`, "-frames:v", "1", "-fps_mode", "vfr", strip]);
    if (plays > 1) {
      const list = file.replace(/\.mp4$/i, ".concat.txt");
      fs.writeFileSync(list, Array.from({ length: plays }, () => `file '${path.basename(once)}'`).join("\n"));
      ffmpegRun(ffmpeg, ["-f", "concat", "-safe", "0", "-i", list, "-c", "copy", "-movflags", "+faststart", file]);
      fs.rmSync(list, { force: true });
      fs.rmSync(once, { force: true });
    }
    outputs.push(file);
  }
  return { outputs, strip, plays, hold, seconds: (plays * (frames + hold)) / fps, width, height, picks };
}

async function main(argv, log = console.log) {
  const options = parse(argv);
  if (options.help) {
    log(USAGE);
    return null;
  }
  if (!options.targets.length && !options.pose && !options.clips.length) throw new Error(`give at least one instance path, --clip or --pose\n\n${USAGE}`);
  const started = Date.now();
  const port = await pickPort(options);
  const firstName = options.targets[0] || (options.clips[0] && options.clips[0].owner);
  const name = slug(options.name || (firstName ? firstName.split(".").pop() : path.basename(options.pose, path.extname(options.pose))));
  const outDir = path.resolve(options.out || path.join(os.tmpdir(), "assetshot", `${name}-${Date.now().toString(36)}`));
  fs.mkdirSync(outDir, { recursive: true });
  const imageLimit = options.imageLimit || IMAGE_LIMIT;
  const imageCache = imageCacheDir(imageLimit);
  const args = {
    targets: options.targets,
    args: options.args,
    views: options.views,
    focus: options.focus.length ? options.focus : undefined,
    forward: options.forward,
    camera: options.camera,
    fov: options.fov,
    frame: options.frame,
    studio: options.view === "studio",
    label: options.label,
    imageLimit,
    known: knownCache(imageCache),
    clips: options.clips.length ? options.clips : undefined,
    fps: options.fps,
    root: options.root,
  };
  const pose = options.pose ? fs.readFileSync(path.resolve(options.pose), "utf8").replace(/\r\n/g, "\n") : options.clips.length ? DEFAULT_CLIP_POSE : DEFAULT_POSE;
  const exportStarted = Date.now();
  const payload = await exportScene(port, args, pose, log);
  const exportSeconds = (Date.now() - exportStarted) / 1000;
  const merged = mergeCaches(payload, imageCache, outDir);
  const clips = payload.clips || [];
  for (const clip of clips) clip.loops = options.loops || (clip.loop ? Math.max(2, Math.ceil(CLIP_SECONDS / Math.max(clip.duration, 0.05))) : 2);
  const clipSettings = {
    views: options.views && options.views.length ? options.views : CLIP_DEFAULT_VIEWS,
    size: options.size || [1280, 720],
    travel: options.travel === undefined || options.travel === "auto" || options.travel === "off" ? options.travel || "auto" : Number(options.travel),
    track: options.track !== "off",
    ground: options.ground || "grid",
    grid: options.grid || 2,
    engine: options.engine || "eevee",
    samples: options.samples,
    fov: options.fov || 30,
    labels: !options.noLabel,
  };
  const scene = {
    version: 1,
    name,
    lighting: payload.lighting,
    parts: payload.parts,
    frames: payload.frames,
    clips: clips.length ? clips : undefined,
    meshes: merged.meshes,
    images: merged.images,
    failedMeshes: merged.failedMeshes,
    options: { samples: options.samples || 24, forward: options.forward || "-z", icon: options.icon, clip: clips.length ? clipSettings : undefined },
  };
  const scenePath = path.join(outDir, "scene.json");
  fs.writeFileSync(scenePath, JSON.stringify(scene));
  const blender = findBlender(options.blender);
  const renderStarted = Date.now();
  const report = render(blender, scenePath, outDir);
  const renderSeconds = (Date.now() - renderStarted) / 1000;
  if (!options.keep) {
    fs.rmSync(scenePath, { force: true });
    for (const file of merged.scratch) fs.rmSync(file, { force: true });
  }
  if (report.sheet) {
    log(`sheet    ${report.sheet}`);
    log(`tiles    ${report.tiles.length} in ${path.dirname(report.tiles[0] || report.sheet)}`);
    for (const tile of report.tiles) log(`  ${path.basename(tile)}`);
    log(`frames   ${payload.frames.length}, ${report.objects} parts drawn, ${report.triangles} triangles`);
  }
  let encodeSeconds = 0;
  if (report.clips) {
    const ffmpeg = findFfmpeg();
    const encodeStarted = Date.now();
    report.videos = [];
    for (const clip of report.clips) {
      const video = encodeClip(ffmpeg, clip, options.layout || "stack", outDir);
      report.videos.push({ label: clip.label, ...video });
      if (!options.keep) fs.rmSync(path.dirname(clip.views[0].dir), { recursive: true, force: true });
      const sizes = video.outputs.map((file) => (fs.statSync(file).size / 1024 / 1024).toFixed(1) + " MB").join(", ");
      for (const file of video.outputs) log(`video    ${file}`);
      log(`         ${clip.label}: ${video.width}x${video.height}, ${video.seconds.toFixed(1)} s, ${video.plays} x ${clip.rendered} frames at ${clip.fps} fps (${clip.views.map((view) => view.name).join(" + ")}), ${sizes}`);
      log(`         ${clip.speed > 0 ? `travels ${clip.speed} studs/s${clip.track ? ", cameras follow" : ", cameras still"}` : "in place"}; ground at ${clip.ground.toFixed(2)}, checker ${clip.grid.toFixed(2)} studs; clip ${clip.duration.toFixed(3)} s ${clip.loop ? "looping" : "one-shot"}; tracks ${clip.tracks.map((track) => `${track.name} ${Number(track.length).toFixed(3)} s`).join(", ")}`);
      log(`strip    ${video.strip} (frames ${video.picks.join(", ")} of the first play)`);
    }
    encodeSeconds = (Date.now() - encodeStarted) / 1000;
    if (options.keep) fs.writeFileSync(path.join(outDir, `${name}_clips.json`), JSON.stringify(report.clips, null, 1));
    log(`engine   ${report.clipEngine}; ${report.objects} parts drawn`);
  }
  log(`time     export ${exportSeconds.toFixed(1)} s, render ${renderSeconds.toFixed(1)} s${report.clips ? `, encode ${encodeSeconds.toFixed(1)} s, total ${((Date.now() - started) / 1000).toFixed(1)} s` : ""} on ${report.device}`);
  const failedMeshes = summarise(merged.failedMeshes, 8);
  if (failedMeshes.length) log(`boxes    ${Object.keys(merged.failedMeshes).length} meshes could not be read and are drawn as their part's box:\n  ${failedMeshes.join("\n  ")}`);
  const failedImages = summarise(merged.failedImages, 8);
  if (failedImages.length) log(`untextured ${Object.keys(merged.failedImages).length} images could not be read:\n  ${failedImages.join("\n  ")}`);
  const unsupported = Array.isArray(payload.unsupported) ? {} : payload.unsupported || {};
  if (Object.keys(unsupported).length) log(`not drawn ${Object.entries(unsupported).map(([kind, count]) => `${count} ${kind}`).join(", ")}`);
  for (const warning of [...(payload.warnings || []), ...(report.warnings || [])]) log(`warn     ${warning}`);
  return report;
}

module.exports = { main, call, parse, USAGE, encodeClip, findFfmpeg };

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
