#!/usr/bin/env node
// /itemicon: renders Roblox models as transparent item icons for UI, and optionally uploads them as Image assets.
// node icon.js <instance path...> --out-dir DIR [options]   (see USAGE)
// Rendering is /assetshot's icon mode (headless Blender, read-only from Studio); finishing is finish.py (PIL);
// uploading writes the PNG into an EditableImage in Studio and calls AssetService:CreateAssetAsync.
const fs = require("fs");
const os = require("os");
const path = require("path");
const studioBridge = (() => {
  try {
    return require(path.join(__dirname, "..", "studio", "bridge.js"));
  } catch {
    return null;
  }
})();
const zlib = require("zlib");
const { spawnSync } = require("child_process");

const ASSETSHOT = path.join(os.homedir(), ".claude", "skills", "assetshot", "shot.js");
const FINISH = path.join(__dirname, "finish.py");
const ROWS_PER_CALL = 128;

const USAGE = `usage: node icon.js <instance path...> --out-dir DIR [options]

Each target renders on its own to DIR/<Name>.png: transparent, square, tightly framed, outlined.

  --out-dir DIR        where the finished icons go (a project folder, e.g. ui-source/renders/<Group>)
  --size N             finished icon size in px (default 512); the render is twice that, then scaled down
  --view V             front, back, left, right, top, persp, persp-right, persp-back, persp-back-right or dx,dy,dz
                       in the model's frame (default persp)
  --roll DEG           turn the picture about the view axis (a lance: --view right --roll 45)
  --forward AXIS       the way the model faces: -z (default), +z, -x, +x
  --margin F           empty share of the square round the item (default 0.06)
  --outline PX         outline width at the finished size (default 6; 0 for none)
  --outline-colour HEX outline colour (default 000000)
  --upload             upload each icon as an Image asset and print its rbxassetid
  --attribute NAME     with --upload, also set the rbxassetid as this attribute on the source model (default
                       IconImage; "none" to skip), so code finds an item's icon on its own template
  --manifest FILE      merge { name: { assetId, file, source } } into this JSON file
  --port N             Studio MCP port (default: found by /studio's bridge, else 58741 or STUDIO_PORT)
  --place-id ID        only use a Studio with this place open (default: the project's studio.json)
  --samples N          Cycles samples (default 48)
  --force              render and upload again even when the manifest already has the icon (otherwise skipped,
                       so a run cut off by the bridge resumes where it stopped)`;

function parse(argv) {
  const options = { targets: [], size: 512, view: "persp", roll: 0, margin: 0.06, outline: 6, outlineColour: "000000", samples: 48 };
  for (let index = 0; index < argv.length; index++) {
    const item = argv[index];
    if (!item.startsWith("--")) {
      options.targets.push(item);
      continue;
    }
    const value = () => {
      index++;
      if (index >= argv.length) throw new Error(`${item} needs a value`);
      return argv[index];
    };
    switch (item) {
      case "--out-dir": options.outDir = path.resolve(value()); break;
      case "--size": options.size = Number(value()); break;
      case "--view": options.view = value(); break;
      case "--roll": options.roll = Number(value()); break;
      case "--forward": options.forward = value(); break;
      case "--margin": options.margin = Number(value()); break;
      case "--outline": options.outline = Number(value()); break;
      case "--outline-colour": options.outlineColour = value().replace("#", ""); break;
      case "--upload": options.upload = true; break;
      case "--manifest": options.manifest = path.resolve(value()); break;
      case "--port": options.port = Number(value()); break;
      case "--place-id": options.placeId = value(); break;
      case "--samples": options.samples = Number(value()); break;
      case "--force": options.force = true; break;
      case "--attribute": options.attribute = value(); break;
      case "--help": options.help = true; break;
      default: throw new Error(`unknown option ${item}\n\n${USAGE}`);
    }
  }
  return options;
}

function decodePng(file) {
  const data = fs.readFileSync(file);
  let offset = 8;
  let width, height, colourType;
  const chunks = [];
  while (offset < data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.toString("ascii", offset + 4, offset + 8);
    const body = data.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      colourType = body[9];
      if (body[8] !== 8 || body[12] !== 0) throw new Error("only 8-bit non-interlaced PNGs");
    } else if (type === "IDAT") chunks.push(body);
    offset += 12 + length;
  }
  const channels = colourType === 6 ? 4 : colourType === 2 ? 3 : 0;
  if (!channels) throw new Error(`unsupported PNG colour type ${colourType}`);
  const raw = zlib.inflateSync(Buffer.concat(chunks));
  const stride = width * channels;
  const pixels = Buffer.alloc(width * height * 4);
  let previous = Buffer.alloc(stride);
  for (let row = 0; row < height; row++) {
    const filter = raw[row * (stride + 1)];
    const line = Buffer.from(raw.subarray(row * (stride + 1) + 1, (row + 1) * (stride + 1)));
    for (let index = 0; index < stride; index++) {
      const left = index >= channels ? line[index - channels] : 0;
      const up = previous[index];
      const upLeft = index >= channels ? previous[index - channels] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = (left + up) >> 1;
      else if (filter === 4) {
        const estimate = left + up - upLeft;
        const toLeft = Math.abs(estimate - left);
        const toUp = Math.abs(estimate - up);
        const toUpLeft = Math.abs(estimate - upLeft);
        predictor = toLeft <= toUp && toLeft <= toUpLeft ? left : toUp <= toUpLeft ? up : upLeft;
      }
      line[index] = (line[index] + predictor) & 255;
    }
    for (let column = 0; column < width; column++) {
      const target = (row * width + column) * 4;
      line.copy(pixels, target, column * channels, column * channels + channels);
      if (channels === 3) pixels[target + 3] = 255;
    }
    previous = line;
  }
  return { width, height, pixels };
}

// The bridge hands a call that is still running to the plugin again every 0.5 s, so each call carries a token and a
// repeat waits for the first run's result instead of running again (an upload would otherwise happen twice).
let serial = 0;
function once(code) {
  const token = `${process.pid}-${Date.now()}-${++serial}`;
  return `_G.ItemIconCalls = _G.ItemIconCalls or {}
local state = _G.ItemIconCalls["${token}"]
if state then
	while not state.done do task.wait(0.05) end
	if state.failed then error(state.result, 0) end
	return state.result
end
state = { done = false }
_G.ItemIconCalls["${token}"] = state
local ok, result = pcall(function()
${code}
end)
state.done, state.failed, state.result = true, not ok, result
if not ok then error(result, 0) end
return result`;
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

// The bridge sometimes drops a connection mid-batch; a dropped call is sent again (the token keeps it from running twice).
async function call(port, code, attempt = 1) {
  try {
    return await callOnce(port, code);
  } catch (error) {
    if (attempt >= 5 || !/fetch failed|ECONNRESET|socket|without a result|timeout/i.test(error.message)) throw error;
    await sleep(2000 * attempt);
    return call(port, code, attempt + 1);
  }
}

async function callOnce(port, code) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name: "execute_luau", arguments: { code: once(code) } } }),
    signal: AbortSignal.timeout(300000),
  });
  const body = await response.text();
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (!message.result) throw new Error(`the bridge answered without a result: ${JSON.stringify(message.error || message).slice(0, 300)}`);
  const reply = JSON.parse(message.result.content[0].text);
  if (reply.success === false) throw new Error(reply.error || reply.message);
  return reply.returnValue;
}

const BASE64 = `local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP = table.create(256, 0)
for index = 1, 64 do LOOKUP[string.byte(ALPHABET, index)] = index - 1 end
local function decodeBase64(text)
	local parts = table.create(#text // 4 * 3)
	for index = 1, #text, 4 do
		local a, b, c, d = string.byte(text, index, index + 3)
		local value = LOOKUP[a] * 262144 + LOOKUP[b] * 4096 + LOOKUP[c or 61] * 64 + LOOKUP[d or 61]
		table.insert(parts, string.char(bit32.extract(value, 16, 8)))
		if c ~= 61 then table.insert(parts, string.char(bit32.extract(value, 8, 8))) end
		if d ~= 61 then table.insert(parts, string.char(bit32.extract(value, 0, 8))) end
	end
	return table.concat(parts)
end`;

async function upload(port, file, name) {
  const { width, height, pixels } = decodePng(file);
  const key = `ItemIcon_${name}`;
  for (let row = 0; row < height; row += ROWS_PER_CALL) {
    const rows = Math.min(ROWS_PER_CALL, height - row);
    const chunk = pixels.subarray(row * width * 4, (row + rows) * width * 4).toString("base64");
    await call(port, `${BASE64}
_G.ItemIconImages = _G.ItemIconImages or {}
if ${row} == 0 then
	_G.ItemIconImages["${key}"] = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(${width}, ${height}) })
end
_G.ItemIconImages["${key}"]:WritePixelsBuffer(Vector2.new(0, ${row}), Vector2.new(${width}, ${rows}), buffer.fromstring(decodeBase64("${chunk}")))
return "ok"`);
  }
  return call(port, `
local image = _G.ItemIconImages["${key}"]
local request = { Name = "${key}", Description = "Item icon rendered by /itemicon" }
if game.CreatorType == Enum.CreatorType.Group then
	request.CreatorId = game.CreatorId
	request.CreatorType = Enum.AssetCreatorType.Group
end
local result, id = game:GetService("AssetService"):CreateAssetAsync(image, Enum.AssetType.Image, request)
_G.ItemIconImages["${key}"] = nil
image:Destroy()
if result ~= Enum.CreateAssetResult.Success or not id then
	error("CreateAssetAsync: " .. tostring(result))
end
return id`);
}

async function stamp(port, target, attribute, value) {
  const steps = target.split(".").map((step) => JSON.stringify(step)).join(", ");
  return call(port, `local instance = game
for _, step in { ${steps} } do
	instance = instance:FindFirstChild(step) or (instance == game and game:GetService(step))
	if not instance then error("no instance at ${target}") end
end
instance:SetAttribute(${JSON.stringify(attribute)}, ${JSON.stringify(value)})
return "stamped"`);
}

async function main(argv) {
  const options = parse(argv);
  if (options.help || !options.targets.length || !options.outDir) {
    console.log(USAGE);
    return;
  }
  const fixedPort = options.port || (process.env.STUDIO_PORT ? Number(process.env.STUDIO_PORT) : undefined);
  const placeId = studioBridge ? options.placeId || studioBridge.readConfig(studioBridge.findProjectRoot()).placeId : options.placeId;
  const port = studioBridge ? (await studioBridge.resolve({ port: fixedPort, placeId, writes: Boolean(options.upload) })).port : fixedPort || 58741;
  fs.mkdirSync(options.outDir, { recursive: true });
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "itemicon-"));
  const manifest = options.manifest && fs.existsSync(options.manifest) ? JSON.parse(fs.readFileSync(options.manifest, "utf8")) : {};
  for (const target of options.targets) {
    const name = target.split(".").pop();
    const done = manifest[name];
    if (!options.force && done && done.source === target && (done.assetId || !options.upload) && fs.existsSync(path.join(options.outDir, `${name}.png`))) {
      console.log(`${name}: already in the manifest${done.assetId ? ` (${done.assetId})` : ""}, skipped`);
      continue;
    }
    const raw = path.join(scratch, `${name}.png`);
    const shotArgs = [ASSETSHOT, target, "--out", scratch, "--name", name, "--port", String(port), "--samples", String(options.samples),
      "--icon", String(options.size * 2), "--icon-view", options.view, "--icon-roll", String(options.roll), "--icon-padding", "1.02", "--icon-file", raw];
    if (options.forward) shotArgs.push("--forward", options.forward);
    const shot = spawnSync("node", shotArgs, { encoding: "utf8" });
    if (shot.status !== 0 || !fs.existsSync(raw)) throw new Error(`${target}: render failed\n${(shot.stdout + shot.stderr).trim().split(/\r?\n/).slice(-8).join("\n")}`);
    const finished = path.join(options.outDir, `${name}.png`);
    const finish = spawnSync("python", [FINISH, raw, finished, String(options.size), String(options.margin), String(options.outline), options.outlineColour], { encoding: "utf8" });
    if (finish.status !== 0) throw new Error(`${target}: finishing failed\n${finish.stderr}`);
    let assetId;
    if (options.upload) {
      assetId = await upload(port, finished, name);
      const attribute = options.attribute || "IconImage";
      if (attribute !== "none") await stamp(port, target, attribute, `rbxassetid://${assetId}`);
      console.log(`${name}: ${finished} -> rbxassetid://${assetId}${attribute !== "none" ? ` (${attribute} set)` : ""}`);
    } else console.log(`${name}: ${finished}`);
    if (options.manifest) {
      manifest[name] = { ...(manifest[name] || {}), file: path.relative(path.dirname(options.manifest), finished).replace(/\\/g, "/"), source: target };
      if (assetId) manifest[name].assetId = `rbxassetid://${assetId}`;
      fs.writeFileSync(options.manifest, JSON.stringify(manifest, null, 2) + "\n");
    }
  }
  fs.rmSync(scratch, { recursive: true, force: true });
}

main(process.argv.slice(2)).catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
