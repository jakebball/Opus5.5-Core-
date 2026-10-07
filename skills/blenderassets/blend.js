#!/usr/bin/env node
// blend.js: the blenderassets skill's runner.
//
//   node blend.js build    <asset.py> [--out DIR] [--blender PATH]
//        run an asset script in headless Blender: <Name>_sheet.png (four views) and <Name>.json (the Roblox payload)
//   node blend.js brushes  [--style NAME] [--role ROLE] [--blender PATH]
//        render the painter library's swatches (python/brushes/swatches/) and rewrite its CATALOG.md / catalog.json
//   node blend.js probe
//        Studio MCP ports 58741-58750 that answer, and the place each has open
//   node blend.js selftest <asset.json> --port N
//        build every part as a preview into an UNPARENTED model, check it, destroy it: proves the import, changes nothing
//   node blend.js push     <asset.json> --port N --place-id ID [--parent Workspace.BlenderImports] [--at x,y,z]
//                          [--upload] [--prefix NAME] [--tint HEX]
//        build the asset in the place, one execute_luau call per part, as previews unless --upload. A painted
//        (blendlib-textured/1) payload sends its textures first; --upload then makes Image and Mesh assets.
//        --tint sets SurfaceAppearance.Color on tinted parts (default FFFFFF: the game sets the team colour)
//
// Node 18+ (global fetch), no npm packages. Blender 4.1+. The Roblox side is robloxMeshTools' MeshKit, read from the
// importmeshtools skill's vendored copy and sent with each call, so nothing is installed into the place.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const RUNNER = path.join(__dirname, "python", "run.py");
const MESHKIT = path.join(__dirname, "..", "importmeshtools", "vendor", "robloxMeshTools", "kit", "MeshKit.luau");
const PORTS = Array.from({ length: 10 }, (_, index) => 58741 + index);
const studioBridge = (() => {
  try {
    return require(path.join(__dirname, "..", "studio", "bridge.js"));
  } catch {
    return null;
  }
})();
const MIN_BLENDER = [4, 1];

function parseArgs(argv) {
  const out = { _: [] };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = argv[index + 1];
      if (next === undefined || next.startsWith("--")) out[key] = true;
      else out[key] = argv[++index];
    } else out._.push(arg);
  }
  return out;
}

function findBlender(explicit) {
  if (typeof explicit === "string") return explicit;
  if (process.env.BLENDER) return process.env.BLENDER;
  const found = [];
  for (const base of [process.env.ProgramFiles, process.env["ProgramFiles(x86)"]].filter(Boolean)) {
    const root = path.join(base, "Blender Foundation");
    if (!fs.existsSync(root)) continue;
    for (const entry of fs.readdirSync(root)) {
      const match = entry.match(/^Blender (\d+)\.(\d+)/);
      const exe = path.join(root, entry, "blender.exe");
      if (match && fs.existsSync(exe)) found.push({ exe, version: [Number(match[1]), Number(match[2])] });
    }
  }
  found.sort((a, b) => b.version[0] - a.version[0] || b.version[1] - a.version[1]);
  if (found.length) {
    const [major, minor] = found[0].version;
    if (major < MIN_BLENDER[0] || (major === MIN_BLENDER[0] && minor < MIN_BLENDER[1])) {
      throw new Error(`the newest Blender installed is ${major}.${minor}; blendlib needs ${MIN_BLENDER.join(".")}+`);
    }
    return found[0].exe;
  }
  const steam = path.join(process.env["ProgramFiles(x86)"] || "", "Steam", "steamapps", "common", "Blender", "blender.exe");
  if (fs.existsSync(steam)) return steam;
  const mac = "/Applications/Blender.app/Contents/MacOS/Blender";
  if (fs.existsSync(mac)) return mac;
  return "blender";
}

function build(args) {
  if (!args._[1]) throw new Error("usage: build <asset.py> [--out DIR] [--blender PATH]");
  const script = path.resolve(args._[1]);
  if (!fs.existsSync(script)) throw new Error(`no such script: ${script}`);
  const out = path.resolve(typeof args.out === "string" ? args.out : path.join(os.tmpdir(), "blenderassets", path.basename(script, ".py")));
  fs.mkdirSync(out, { recursive: true });
  const blender = findBlender(args.blender);
  const started = Date.now();
  const result = spawnSync(blender, ["-b", "--factory-startup", "--python-exit-code", "1", "-P", RUNNER, "--", script, out], {
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw new Error(`could not start Blender (${blender}): ${result.error.message}`);
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const lines = `${result.stdout || ""}\n${result.stderr || ""}`.split(/\r?\n/);
  const reportLine = [...lines].reverse().find((line) => line.startsWith("BLENDLIB "));
  const report = reportLine ? JSON.parse(reportLine.slice("BLENDLIB ".length)) : null;
  if (report) {
    const size = report.size.map((value) => Number(value.toFixed(2))).join(" x ");
    console.log(`${report.errors.length ? "FAILED" : "built"} ${report.name} in ${seconds} s (Blender ${report.blender})`);
    if (report.sheet) console.log(`  sheet    ${report.sheet}`);
    if (report.payload) console.log(`  payload  ${report.payload} (${Math.round(fs.statSync(report.payload).size / 1024)} KB)`);
    console.log(`  size     ${size} studs (W x H x D, Roblox axes)`);
    console.log(`  parts    ${Object.entries(report.parts).map(([name, count]) => `${name} ${count}`).join(", ")} (${report.triangles} triangles)`);
    for (const texture of report.textures || []) console.log(`  texture  ${texture.name} ${texture.size}x${texture.size}, ${texture.cached ? "bake cached" : "baked"}, ${texture.seconds} s`);
    if (report.sockets) console.log(`  sockets  ${report.sockets}`);
    for (const warning of report.warnings) console.log(`  warn     ${warning}`);
    for (const error of report.errors) console.log(`  error    ${error}`);
  }
  if (result.status !== 0) {
    const start = lines.findIndex((line) => line.startsWith("Traceback"));
    if (start >= 0) console.log(lines.slice(start, start + 40).join("\n"));
    else if (!report) console.log(lines.filter((line) => /error/i.test(line)).slice(-20).join("\n") || "(Blender printed no error)");
    process.exitCode = 1;
    if (!report) console.log(`FAILED in ${seconds} s (exit ${result.status}, ${blender})`);
  }
}

function renderBrushes(args) {
  const script = path.join(__dirname, "python", "brushes", "swatch.py");
  const out = path.join(os.tmpdir(), "blenderassets-brushes");
  fs.mkdirSync(out, { recursive: true });
  const blender = findBlender(args.blender);
  const env = { ...process.env, BRUSH_STYLE: typeof args.style === "string" ? args.style : "", BRUSH_ROLE: typeof args.role === "string" ? args.role : "" };
  const started = Date.now();
  const result = spawnSync(blender, ["-b", "--factory-startup", "--python-exit-code", "1", "-P", RUNNER, "--", script, out], { encoding: "utf8", maxBuffer: 256 * 1024 * 1024, env });
  if (result.error) throw new Error(`could not start Blender (${blender}): ${result.error.message}`);
  const lines = `${result.stdout || ""}\n${result.stderr || ""}`.split(/\r?\n/);
  for (const line of lines) if (/^SWATCH|^BRUSHES/.test(line)) console.log(line);
  if (result.status !== 0) {
    const start = lines.findIndex((line) => line.startsWith("Traceback"));
    console.log(start >= 0 ? lines.slice(start, start + 30).join("\n") : lines.filter((line) => /error/i.test(line)).slice(-15).join("\n"));
    process.exitCode = 1;
  }
  console.log(`brushes in ${((Date.now() - started) / 1000).toFixed(1)} s: ${path.join(__dirname, "python", "brushes", "CATALOG.md")}`);
}

// The Studio MCP bridge (robloxstudio-mcp 1.4.0) hands a call that is still running to the plugin again on every
// 0.5 s poll, so a call that yields runs once per half second it lasts: a 3 s CreateAssetAsync ran six times and
// uploaded six assets. Every call therefore carries a token; a repeat delivery waits for the first run and returns
// its result instead of running the code again.
let callSerial = 0;

function onceLua(code) {
  const token = `${process.pid}-${Date.now()}-${++callSerial}`;
  return `local __token = "${token}"
_G.BlendCalls = _G.BlendCalls or {}
local __state = _G.BlendCalls[__token]
if __state then
	__state.repeats += 1
	while not __state.done do
		task.wait(0.05)
	end
	if __state.failed then
		error(__state.result, 0)
	end
	return __state.result
end
__state = { done = false, repeats = 0 }
_G.BlendCalls[__token] = __state
local __ok, __result = pcall(function()
${code}
end)
__state.done, __state.failed, __state.result = true, not __ok, __result
task.delay(120, function()
	_G.BlendCalls[__token] = nil
end)
if not __ok then
	error(__result, 0)
end
return __result
`;
}

async function call(port, code, timeoutMs = 300000) {
  const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name: "execute_luau", arguments: { code: onceLua(code) } } }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${body.slice(0, 200)}`);
  let message;
  for (const line of body.split(/\r?\n/)) if (line.startsWith("data: ")) message = JSON.parse(line.slice(6));
  if (!message) message = JSON.parse(body);
  if (message.error) throw new Error(`JSON-RPC error: ${JSON.stringify(message.error)}`);
  const inner = message.result && message.result.content && message.result.content[0] && message.result.content[0].text;
  let reply;
  try {
    reply = JSON.parse(inner);
  } catch {
    throw new Error(`unexpected tool reply: ${inner}`);
  }
  if (reply.success === false) throw new Error(`execute_luau failed: ${reply.error || reply.message || inner}`);
  return reply;
}

async function callJson(port, code) {
  const reply = await call(port, code);
  return JSON.parse(reply.returnValue);
}

const PROBE = `
return game:GetService("HttpService"):JSONEncode({
	placeId = game.PlaceId,
	name = game.Name,
	creatorType = tostring(game.CreatorType),
	running = game:GetService("RunService"):IsRunning(),
})
`;

function bracket(text) {
  for (let level = 1; level < 40; level++) {
    const equals = "=".repeat(level);
    if (!text.includes("]" + equals + "]")) return ["[" + equals + "[\n", "]" + equals + "]"];
  }
  throw new Error("no free long-bracket level");
}

function embed(value) {
  const json = JSON.stringify(value);
  const [open, close] = bracket(json);
  return `HttpService:JSONDecode(${open}${json}${close})`;
}

function luaString(text) {
  if (/["\\\n\r]/.test(text)) throw new Error(`unsafe Lua string literal: ${text}`);
  return `"${text}"`;
}

function kitSource() {
  if (!fs.existsSync(MESHKIT)) throw new Error(`MeshKit not found at ${MESHKIT}; blenderassets borrows it from the importmeshtools skill`);
  return fs.readFileSync(MESHKIT, "utf8").replace(/\r\n/g, "\n");
}

const SERVICES = `local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")

local function resolve(path, create)
	local segments = string.split(path, ".")
	local serviceName = if string.lower(segments[1]) == "workspace" then "Workspace" else segments[1]
	local current = game:GetService(serviceName)
	for index = 2, #segments do
		local child = current:FindFirstChild(segments[index])
		if not child then
			if not create then
				return nil
			end
			child = Instance.new("Folder")
			child.Name = segments[index]
			child.Parent = current
		end
		current = child
	end
	return current
end
`;

function builderLua() {
  return `${SERVICES}
local Kit = (function()
${kitSource()}
end)()

local function enumItem(enum, name, label, meshName)
	local ok, item = pcall(function()
		return enum[name]
	end)
	if not ok or item == nil then
		error("unknown " .. label .. " " .. tostring(name) .. " on part " .. meshName)
	end
	return item
end

local function buildMesh(mesh, quantum, options)
	local material = enumItem(Enum.Material, mesh.material, "Roblox material", mesh.name)
	local collision = enumItem(Enum.CollisionFidelity, mesh.collision, "CollisionFidelity", mesh.name)
	local positions = mesh.v
	local vertices = table.create(#positions // 3)
	local minPoint = Vector3.one * math.huge
	local maxPoint = -Vector3.one * math.huge
	for index = 1, #positions, 3 do
		local point = Vector3.new(positions[index], positions[index + 1], positions[index + 2]) / quantum
		table.insert(vertices, point)
		minPoint = minPoint:Min(point)
		maxPoint = maxPoint:Max(point)
	end
	local normals = table.create(#mesh.n // 3)
	for index = 1, #mesh.n, 3 do
		table.insert(normals, Vector3.new(mesh.n[index], mesh.n[index + 1], mesh.n[index + 2]).Unit)
	end

	local kit = Kit.new(mesh.name)
	function kit:bounds()
		return minPoint, maxPoint
	end
	function kit:triCount()
		return #mesh.t // 9
	end
	function kit:build(centre)
		local editable = AssetService:CreateEditableMesh()
		if not editable then
			error("CreateEditableMesh returned nil (memory budget)")
		end
		local vertexIds = table.create(#vertices)
		for index, point in vertices do
			vertexIds[index] = editable:AddVertex(point - centre)
		end
		local normalIds = table.create(#normals)
		for index, normal in normals do
			normalIds[index] = editable:AddNormal(normal)
		end
		local colourIds = table.create(#mesh.c)
		for index, hex in mesh.c do
			colourIds[index] = editable:AddColor(Color3.fromHex(hex), 1)
		end
		local uvIds = {}
		local function uvId(point, faceNormal)
			local absX, absY, absZ = math.abs(faceNormal.X), math.abs(faceNormal.Y), math.abs(faceNormal.Z)
			local across, along
			if absY >= absX and absY >= absZ then
				across, along = point.X, point.Z
			elseif absX >= absZ then
				across, along = point.Z, point.Y
			else
				across, along = point.X, point.Y
			end
			local key = string.format("%.3f,%.3f", across, along)
			local id = uvIds[key]
			if not id then
				id = editable:AddUV(Vector2.new(across / Kit.UV_SCALE, along / Kit.UV_SCALE))
				uvIds[key] = id
			end
			return id
		end
		local triangles = mesh.t
		for index = 1, #triangles, 9 do
			local first, second, third = triangles[index], triangles[index + 1], triangles[index + 2]
			local face = editable:AddTriangle(vertexIds[first], vertexIds[second], vertexIds[third])
			editable:SetFaceNormals(face, { normalIds[triangles[index + 3]], normalIds[triangles[index + 4]], normalIds[triangles[index + 5]] })
			editable:SetFaceColors(face, { colourIds[triangles[index + 6]], colourIds[triangles[index + 7]], colourIds[triangles[index + 8]] })
			local faceNormal = (vertices[second] - vertices[first]):Cross(vertices[third] - vertices[first])
			editable:SetFaceUVs(face, { uvId(vertices[first], faceNormal), uvId(vertices[second], faceNormal), uvId(vertices[third], faceNormal) })
		end
		self.faceCount = #editable:GetFaces()
		return editable
	end

	local existing = options.parent and options.parent:FindFirstChild(mesh.name)
	if existing then
		existing:Destroy()
	end
	local part = kit:finish(mesh.name, {
		preview = options.preview,
		parent = options.parent,
		origin = options.origin,
		prefix = options.prefix,
		material = material,
		color = Color3.new(1, 1, 1),
		collision = collision,
		collide = mesh.collide,
		shadow = mesh.shadow,
	})
	part:SetAttribute("Triangles", kit.faceCount)
	return part
end
`;
}

function selftestLua(payload) {
  return `${builderLua()}
local payload = ${embed(payload)}
local started = os.clock()
local model = Instance.new("Model")
local report = { ok = true, parts = {} }
local minPoint = Vector3.one * math.huge
local maxPoint = -Vector3.one * math.huge
for _, mesh in payload.meshes do
	local entry = { name = mesh.name, want = mesh.triangles }
	local ok, result = pcall(buildMesh, mesh, payload.quantum, { preview = true, parent = model, origin = CFrame.identity })
	if ok then
		entry.triangles = result:GetAttribute("Triangles")
		entry.size = { result.Size.X, result.Size.Y, result.Size.Z }
		entry.material = result.Material.Name
		minPoint = minPoint:Min(result.Position - result.Size / 2)
		maxPoint = maxPoint:Max(result.Position + result.Size / 2)
		if entry.triangles ~= mesh.triangles then
			entry.problem = "triangle count"
		end
	else
		entry.problem = tostring(result)
	end
	if entry.problem then
		report.ok = false
	end
	table.insert(report.parts, entry)
end
local extent = maxPoint - minPoint
report.size = { extent.X, extent.Y, extent.Z }
report.wantSize = payload.size
if payload.size then
	for axis, value in report.size do
		if math.abs(value - payload.size[axis]) > 0.01 then
			report.ok = false
			report.sizeProblem = true
		end
	end
end
report.seconds = os.clock() - started
model:Destroy()
return HttpService:JSONEncode(report)
`;
}

function prepareLua(parentPath, incoming, at) {
  return `${SERVICES}
local parent = resolve(${luaString(parentPath)}, true)
local stale = parent:FindFirstChild(${luaString(incoming)})
if stale then
	stale:Destroy()
end
local model = Instance.new("Model")
model.Name = ${luaString(incoming)}
model.WorldPivot = CFrame.new(${at.join(", ")})
model.Parent = parent
return model:GetFullName()
`;
}

function meshLua(parentPath, incoming, at, mesh, quantum, upload, prefix) {
  return `${builderLua()}
local mesh = ${embed(mesh)}
local parent = resolve(${luaString(parentPath)}, true)
local model = parent:FindFirstChild(${luaString(incoming)})
local recreated = false
if not model then
	model = Instance.new("Model")
	model.Name = ${luaString(incoming)}
	model.WorldPivot = CFrame.new(${at.join(", ")})
	model.Parent = parent
	recreated = true
end
local part = buildMesh(mesh, ${quantum}, { preview = ${upload ? "false" : "true"}, parent = model, origin = CFrame.new(${at.join(", ")}), prefix = ${luaString(prefix)} })
return HttpService:JSONEncode({ name = part.Name, triangles = part:GetAttribute("Triangles"), assetId = part:GetAttribute("MeshAssetId"), recreated = recreated })
`;
}

function verifyLua(parentPath, incoming, name, at, expected, upload, source, total, socketCount = 0) {
  return `${SERVICES}
local expected = ${embed(expected)}
local parent = resolve(${luaString(parentPath)}, false)
local incoming = parent and parent:FindFirstChild(${luaString(incoming)})
local report = { ok = true, problems = {}, parts = {} }
if not incoming then
	report.ok = false
	table.insert(report.problems, ${luaString(incoming)} .. " is missing (Studio may have rolled it back); run push again")
else
	for _, want in expected do
		local part = incoming:FindFirstChild(want.name)
		local entry = { name = want.name, want = want.triangles }
		if not part or not part:IsA("MeshPart") then
			entry.problem = "missing"
		else
			entry.triangles = part:GetAttribute("Triangles")
			entry.assetId = part:GetAttribute("MeshAssetId")
			if entry.triangles ~= want.triangles then
				entry.problem = "triangle count"
			elseif ${upload ? "true" : "false"} and not entry.assetId then
				entry.problem = "still a preview"
			end
		end
		if entry.problem then
			report.ok = false
		end
		table.insert(report.parts, entry)
	end
${socketCheckLua(socketCount)}	if report.ok then
		local old = parent:FindFirstChild(${luaString(name)})
		if old then
			old:Destroy()
		end
		incoming.Name = ${luaString(name)}
		incoming.WorldPivot = CFrame.new(${at.join(", ")})
		incoming:SetAttribute("BlenderSource", ${luaString(source)})
		incoming:SetAttribute("Triangles", ${total})
		report.path = incoming:GetFullName()
	end
end
return HttpService:JSONEncode(report)
`;
}

// Painted (textured) payloads: textures travel as RGBA rows into EditableImages, alpha intact, because on a tinted
// part alpha is the SurfaceAppearance TintMask amount (gold trim painted at alpha 0 stays gold). Previews keep the
// EditableImages; --upload turns each texture into an Image asset and each mesh into a Mesh asset, so the model
// works in Play and after a restart.
const TEXTURE_ROWS_PER_CALL = 192;

const BASE64 = `
local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_LOOKUP = table.create(256, 0)
for index = 1, 64 do
	BASE64_LOOKUP[string.byte(BASE64, index)] = index - 1
end
local function decodeBase64(text, byteCount)
	local out = buffer.create(byteCount)
	local offset = 0
	for index = 1, #text, 4 do
		local first, second, third, fourth = string.byte(text, index, index + 3)
		local value = BASE64_LOOKUP[first] * 262144 + BASE64_LOOKUP[second] * 4096 + BASE64_LOOKUP[third or 61] * 64 + BASE64_LOOKUP[fourth or 61]
		for shift = 16, 0, -8 do
			if offset < byteCount then
				buffer.writeu8(out, offset, bit32.extract(value, shift, 8))
				offset += 1
			end
		end
	end
	return out
end

local function uploadRequest(name, description)
	local request = { Name = name, Description = description }
	if game.CreatorType == Enum.CreatorType.Group then
		request.CreatorId = game.CreatorId
		request.CreatorType = Enum.AssetCreatorType.Group
	end
	return request
end
`;

function textureChunkLua(parentPath, incoming, at, key, width, height, row, rows, data, upload, prefix) {
  const last = row + rows >= height;
  return `${SERVICES}${BASE64}
local parent = resolve(${luaString(parentPath)}, true)
local model = parent:FindFirstChild(${luaString(incoming)})
if not model then
	model = Instance.new("Model")
	model.Name = ${luaString(incoming)}
	model.WorldPivot = CFrame.new(${at.join(", ")})
	model.Parent = parent
end
local folder = model:FindFirstChild("__Textures")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "__Textures"
	folder.Parent = model
end
local holder = folder:FindFirstChild(${luaString(key)})
local image
if not holder or ${row} == 0 then
	if holder then
		holder:Destroy()
	end
	holder = Instance.new("SurfaceAppearance")
	holder.Name = ${luaString(key)}
	image = AssetService:CreateEditableImage({ Size = Vector2.new(${width}, ${height}) })
	if not image then
		error("CreateEditableImage returned nil (memory budget)")
	end
	holder.ColorMapContent = Content.fromObject(image)
	holder.Parent = folder
else
	image = holder.ColorMapContent.Object
end
image:WritePixelsBuffer(Vector2.new(0, ${row}), Vector2.new(${width}, ${rows}), decodeBase64(${embedText(data)}, ${width * rows * 4}))
local assetId = nil
if ${last && upload ? "true" : "false"} then
	local result, id = AssetService:CreateAssetAsync(image, Enum.AssetType.Image, uploadRequest(${luaString(`${prefix}_${key}`)}, ${luaString(`${prefix}, generated painted texture`)}))
	if result ~= Enum.CreateAssetResult.Success or not id then
		error("CreateAssetAsync image ${key}: " .. tostring(result))
	end
	holder:SetAttribute("ImageAssetId", id)
	assetId = id
end
return HttpService:JSONEncode({ rows = ${rows}, assetId = assetId })
`;
}

function embedText(text) {
  const [open, close] = bracket(text);
  return `${open}${text}${close}`;
}

function texturedMeshLua(parentPath, incoming, at, mesh, quantum, uvQuantum, upload, prefix, tint) {
  return `${SERVICES}${BASE64}
local mesh = ${embed(mesh)}
local parent = resolve(${luaString(parentPath)}, true)
local model = parent:FindFirstChild(${luaString(incoming)})
if not model then
	error(${luaString(incoming)} .. " is missing (Studio may have rolled it back); run push again")
end
local holder = nil
if mesh.texture then
	local folder = model:FindFirstChild("__Textures")
	holder = folder and folder:FindFirstChild(mesh.texture)
	if not holder then
		error("texture " .. tostring(mesh.texture) .. " missing for " .. mesh.name)
	end
end
local function enumItem(enum, name, label)
	local ok, item = pcall(function()
		return enum[name]
	end)
	if not ok or item == nil then
		error("unknown " .. label .. " " .. tostring(name) .. " on part " .. mesh.name)
	end
	return item
end
local material = enumItem(Enum.Material, mesh.material, "Roblox material")
local fidelity = enumItem(Enum.CollisionFidelity, mesh.collision, "CollisionFidelity")
local vertices = table.create(#mesh.v // 3)
local low = Vector3.one * math.huge
local high = -Vector3.one * math.huge
for index = 1, #mesh.v, 3 do
	local point = Vector3.new(mesh.v[index], mesh.v[index + 1], mesh.v[index + 2]) / ${quantum}
	table.insert(vertices, point)
	low = low:Min(point)
	high = high:Max(point)
end
local centre = (low + high) / 2
local editable = AssetService:CreateEditableMesh()
if not editable then
	error("CreateEditableMesh returned nil (memory budget)")
end
local vertexIds = table.create(#vertices)
for index, point in vertices do
	vertexIds[index] = editable:AddVertex(point - centre)
end
local normalIds = table.create(#mesh.n // 3)
for index = 1, #mesh.n, 3 do
	table.insert(normalIds, editable:AddNormal(Vector3.new(mesh.n[index], mesh.n[index + 1], mesh.n[index + 2]).Unit))
end
local uvIds = table.create(#mesh.u // 2)
for index = 1, #mesh.u, 2 do
	table.insert(uvIds, editable:AddUV(Vector2.new(mesh.u[index] / ${uvQuantum}, mesh.u[index + 1] / ${uvQuantum})))
end
local corners = mesh.t
for index = 1, #corners, 9 do
	local face = editable:AddTriangle(vertexIds[corners[index]], vertexIds[corners[index + 1]], vertexIds[corners[index + 2]])
	editable:SetFaceNormals(face, { normalIds[corners[index + 3]], normalIds[corners[index + 4]], normalIds[corners[index + 5]] })
	editable:SetFaceUVs(face, { uvIds[corners[index + 6]], uvIds[corners[index + 7]], uvIds[corners[index + 8]] })
end
local faceCount = #editable:GetFaces()
local existing = model:FindFirstChild(mesh.name)
if existing then
	existing:Destroy()
end
local part
if ${upload ? "true" : "false"} then
	local result, assetId = AssetService:CreateAssetAsync(editable, Enum.AssetType.Mesh, uploadRequest(${luaString(prefix)} .. "_" .. mesh.name, ${luaString(`${prefix}, generated painted mesh`)}))
	editable:Destroy()
	if result ~= Enum.CreateAssetResult.Success or not assetId then
		error("CreateAssetAsync mesh " .. mesh.name .. ": " .. tostring(result))
	end
	part = AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId), { CollisionFidelity = fidelity })
	part:SetAttribute("MeshAssetId", assetId)
else
	part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), { CollisionFidelity = fidelity })
end
part.Name = mesh.name
part.Anchored = true
part.CanCollide = mesh.collide
part.CanTouch = mesh.collide
part.CanQuery = mesh.collide
part.Material = material
part.Color = if mesh.colour then Color3.fromHex(mesh.colour) else Color3.new(1, 1, 1)
part.CastShadow = mesh.shadow ~= false
part.CFrame = CFrame.new(${at.join(", ")}) * CFrame.new(centre)
part:SetAttribute("KitRel", CFrame.new(centre))
part:SetAttribute("Triangles", faceCount)
if holder then
	local appearance = Instance.new("SurfaceAppearance")
	local imageId = holder:GetAttribute("ImageAssetId")
	if ${upload ? "true" : "false"} then
		if not imageId then
			error("texture " .. mesh.texture .. " was not uploaded")
		end
		appearance.ColorMapContent = Content.fromAssetId(imageId)
		appearance:SetAttribute("ImageAssetId", imageId)
	else
		appearance.ColorMapContent = Content.fromObject(holder.ColorMapContent.Object)
	end
	if mesh.tint then
		appearance.AlphaMode = Enum.AlphaMode.TintMask
		appearance.Color = Color3.fromHex(${luaString(tint)})
	else
		appearance.AlphaMode = Enum.AlphaMode.Opaque
	end
	appearance.Parent = part
end
part.Parent = model
return HttpService:JSONEncode({ name = part.Name, triangles = faceCount, assetId = part:GetAttribute("MeshAssetId") })
`;
}

function texturedVerifyLua(parentPath, incoming, name, at, expected, upload, source, total, socketCount = 0) {
  return `${SERVICES}
local expected = ${embed(expected)}
local parent = resolve(${luaString(parentPath)}, false)
local incoming = parent and parent:FindFirstChild(${luaString(incoming)})
local report = { ok = true, problems = {}, parts = {} }
if not incoming then
	report.ok = false
	table.insert(report.problems, ${luaString(incoming)} .. " is missing (Studio may have rolled it back); run push again")
else
	for _, want in expected do
		local part = incoming:FindFirstChild(want.name)
		local entry = { name = want.name, want = want.triangles }
		if not part or not part:IsA("MeshPart") then
			entry.problem = "missing"
		else
			entry.triangles = part:GetAttribute("Triangles")
			local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
			if entry.triangles ~= want.triangles then
				entry.problem = "triangle count"
			elseif want.textured and not appearance then
				entry.problem = "no SurfaceAppearance"
			elseif want.textured and ${upload ? "true" : "false"} and not appearance:GetAttribute("ImageAssetId") then
				entry.problem = "texture still a preview"
			elseif want.textured and not ${upload ? "true" : "false"} and not appearance.ColorMapContent.Object then
				entry.problem = "texture missing"
			elseif ${upload ? "true" : "false"} and not part:GetAttribute("MeshAssetId") then
				entry.problem = "mesh still a preview"
			end
		end
		if entry.problem then
			report.ok = false
		end
		table.insert(report.parts, entry)
	end
${socketCheckLua(socketCount)}	if report.ok then
		if ${upload ? "true" : "false"} then
			local folder = incoming:FindFirstChild("__Textures")
			if folder then
				folder:Destroy()
			end
		end
		local old = parent:FindFirstChild(${luaString(name)})
		if old then
			old:Destroy()
		end
		incoming.Name = ${luaString(name)}
		incoming.WorldPivot = CFrame.new(${at.join(", ")})
		incoming:SetAttribute("BlenderSource", ${luaString(source)})
		incoming:SetAttribute("Triangles", ${total})
		report.path = incoming:GetFullName()
	end
end
return HttpService:JSONEncode(report)
`;
}

// Part attributes and sockets travel in the payload, because a push replaces the whole model: anything added in
// Studio afterwards would be lost on the next push. One call, after the parts exist and before verification.
function socketsLua(parentPath, incoming, at, meshes, sockets) {
  const attributes = {};
  for (const mesh of meshes) if (mesh.attributes && Object.keys(mesh.attributes).length) attributes[mesh.name] = mesh.attributes;
  return `${SERVICES}
local attributes = ${embed(attributes)}
local sockets = ${embed(sockets)}
local parent = resolve(${luaString(parentPath)}, false)
local model = parent and parent:FindFirstChild(${luaString(incoming)})
if not model then
	error(${luaString(incoming)} .. " is missing (Studio may have rolled it back); run push again")
end
local origin = Vector3.new(${at.join(", ")})
local function vector(values)
	return Vector3.new(values[1], values[2], values[3])
end
local tagged = 0
for partName, values in attributes do
	local part = model:FindFirstChild(partName)
	if not part then
		error("attributes for missing part " .. partName)
	end
	for key, value in values do
		part:SetAttribute(key, value)
	end
	tagged += 1
end
for _, socket in sockets do
	local part = model:FindFirstChild(socket.part)
	if not part then
		error("socket " .. socket.name .. " wants missing part " .. socket.part)
	end
	local up = vector(socket.up).Unit
	local back = -vector(socket.front)
	back = (back - up * back:Dot(up))
	if back.Magnitude < 1e-4 then
		back = if math.abs(up.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis
		back = back - up * back:Dot(up)
	end
	back = back.Unit
	local attachment = part:FindFirstChild(socket.name)
	if attachment then
		attachment:Destroy()
	end
	attachment = Instance.new("Attachment")
	attachment.Name = socket.name
	attachment.Parent = part
	attachment.WorldCFrame = CFrame.fromMatrix(origin + vector(socket.p), up:Cross(back), up, back)
	attachment:SetAttribute("BlenderSocket", true)
	for key, value in socket.attributes or {} do
		attachment:SetAttribute(key, value)
	end
end
return HttpService:JSONEncode({ sockets = #sockets, tagged = tagged })
`;
}

function socketCheckLua(count) {
  return `
	local found = 0
	for _, descendant in incoming:GetDescendants() do
		if descendant:IsA("Attachment") and descendant:GetAttribute("BlenderSocket") then
			found += 1
		end
	end
	if found ~= ${count} then
		report.ok = false
		table.insert(report.problems, "sockets: " .. found .. " of ${count}")
	end
`;
}

async function pushExtras(payload, port, parentPath, incoming, at) {
  const sockets = payload.sockets || [];
  const hasAttributes = payload.meshes.some((mesh) => mesh.attributes && Object.keys(mesh.attributes).length);
  if (!sockets.length && !hasAttributes) return 0;
  for (const socket of sockets) if (!/^[A-Za-z0-9_]+$/.test(socket.name)) throw new Error(`unsafe socket name ${socket.name}`);
  const result = await callJson(port, socketsLua(parentPath, incoming, at, payload.meshes, sockets));
  console.log(`  sockets ${result.sockets}, attributes on ${result.tagged} part${result.tagged === 1 ? "" : "s"}`);
  return sockets.length;
}

async function pushTextured(payload, port, parentPath, at, upload, prefix, tint) {
  const incoming = `${payload.name}__incoming`;
  const keys = Object.keys(payload.textures);
  console.log(`push ${payload.name} (painted, ${keys.length} texture${keys.length === 1 ? "" : "s"}) -> ${parentPath}.${payload.name} at (${at.join(", ")}), ${upload ? "UPLOAD" : "preview"}`);
  await call(port, prepareLua(parentPath, incoming, at));
  for (const key of keys) {
    if (!/^[A-Za-z0-9_]+$/.test(key)) throw new Error(`unsafe texture name ${key}`);
    const texture = payload.textures[key];
    const raw = fs.readFileSync(texture.file);
    const { width, height } = texture;
    if (raw.length !== width * height * 4) throw new Error(`${texture.file} is ${raw.length} bytes, expected ${width * height * 4} (RGBA rows, top first)`);
    let assetId = null;
    for (let row = 0; row < height; row += TEXTURE_ROWS_PER_CALL) {
      const rows = Math.min(TEXTURE_ROWS_PER_CALL, height - row);
      const chunk = raw.subarray(row * width * 4, (row + rows) * width * 4).toString("base64");
      const result = await callJson(port, textureChunkLua(parentPath, incoming, at, key, width, height, row, rows, chunk, upload, prefix));
      assetId = result.assetId || assetId;
    }
    console.log(`  texture ${key}: ${width}x${height}${assetId ? ", image asset " + assetId : ""}`);
  }
  for (const mesh of payload.meshes) {
    const result = await callJson(port, texturedMeshLua(parentPath, incoming, at, mesh, payload.quantum, payload.uvQuantum, upload, prefix, tint));
    console.log(`  ${result.name}: ${result.triangles} triangles${mesh.texture ? ", " + mesh.texture : ", solid " + mesh.colour}${mesh.tint ? " (tinted)" : ""}${result.assetId ? ", mesh asset " + result.assetId : ""}`);
  }
  const socketCount = await pushExtras(payload, port, parentPath, incoming, at);
  const expected = payload.meshes.map((mesh) => ({ name: mesh.name, triangles: mesh.triangles, textured: Boolean(mesh.texture) }));
  const report = await callJson(port, texturedVerifyLua(parentPath, incoming, payload.name, at, expected, upload, payload.source || "", payload.triangles, socketCount));
  for (const problem of report.problems) console.log(`  x ${problem}`);
  for (const part of report.parts) if (part.problem) console.log(`  x ${part.name}: ${part.problem}`);
  if (report.ok) {
    console.log(`verify (separate call): OK, ${report.path}, ${report.parts.length} parts`);
    if (!upload) console.log("  previews: meshes and textures are live EditableMesh/EditableImage objects that do not exist in Play or after a restart; push --upload once the asset is approved");
  } else {
    console.log(`verify (separate call): FAILED; ${parentPath}.${incoming} is left for inspection and the old model is untouched`);
    process.exitCode = 1;
  }
}

function readPayload(file) {
  if (!file) throw new Error("a payload .json (from build) is required");
  const payload = JSON.parse(fs.readFileSync(file, "utf8"));
  if (payload.format !== "blendlib/1" && payload.format !== "blendlib-textured/1") throw new Error(`${file} is not a blendlib/1 or blendlib-textured/1 payload`);
  for (const mesh of payload.meshes) if (!/^[A-Za-z0-9_]+$/.test(mesh.name)) throw new Error(`unsafe part name ${mesh.name}`);
  return payload;
}

async function needPort(args) {
  const port = Number(args.port);
  if (port) return port;
  if (!studioBridge) throw new Error("--port N is required (run `probe` first)");
  const placeId = args["place-id"] !== undefined && args["place-id"] !== true ? args["place-id"] : studioBridge.readConfig(studioBridge.findProjectRoot()).placeId;
  return (await studioBridge.resolve({ placeId })).port;
}

function parseAt(value) {
  if (value === undefined || value === true) return [0, 0, 0];
  const parts = String(value).split(",").map(Number);
  if (parts.length !== 3 || parts.some((part) => !Number.isFinite(part))) throw new Error(`--at wants x,y,z, got ${value}`);
  return parts;
}

async function probe() {
  let any = false;
  for (const port of PORTS) {
    try {
      const reply = await call(port, PROBE, 8000);
      const place = JSON.parse(reply.returnValue);
      any = true;
      console.log(`port ${port}: placeId=${place.placeId} name="${place.name}" ${place.creatorType} running=${place.running}`);
    } catch (error) {
      if (!/ECONNREFUSED|fetch failed/.test(String(error.cause || error.message))) console.log(`port ${port}: ${error.message}`);
    }
  }
  if (!any) console.log("no Studio MCP server answered on 58741-58750");
}

async function selftest(args) {
  const payload = readPayload(args._[1]);
  const port = await needPort(args);
  if (payload.format === "blendlib-textured/1") throw new Error("selftest checks vertex-colour payloads; push a painted payload as a preview instead (it verifies every part and texture)");
  const report = await callJson(port, selftestLua(payload));
  console.log(`selftest (unparented, nothing kept): ${report.ok ? "OK" : "FAILED"} in ${report.seconds.toFixed(2)} s`);
  for (const part of report.parts) {
    const size = part.size ? part.size.map((value) => value.toFixed(2)).join(" x ") : "-";
    console.log(`  ${part.problem ? "x " : "ok"} ${part.name}: ${part.triangles ?? "-"}/${part.want} triangles, ${size}, ${part.material ?? "-"}${part.problem ? "  " + part.problem : ""}`);
  }
  console.log(`  size ${report.size.map((value) => value.toFixed(3)).join(" x ")} vs Blender ${(report.wantSize || []).join(" x ")}${report.sizeProblem ? "  MISMATCH" : ""}`);
  process.exitCode = report.ok ? 0 : 1;
}

async function push(args) {
  const payload = readPayload(args._[1]);
  const port = await needPort(args);
  if (args["place-id"] === undefined || args["place-id"] === true) throw new Error("--place-id ID is required, so an asset never lands in another open place");
  const place = JSON.parse((await call(port, PROBE, 8000)).returnValue);
  if (String(place.placeId) !== String(args["place-id"])) throw new Error(`port ${port} has placeId ${place.placeId} ("${place.name}") open, not ${args["place-id"]}; refusing`);
  if (place.running) throw new Error("a playtest is running; push builds into the Edit datamodel, so stop the playtest first");
  const parentPath = typeof args.parent === "string" ? args.parent : "Workspace.BlenderImports";
  if (!/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(parentPath)) throw new Error(`--parent wants a dotted path like Workspace.BlenderImports, got ${parentPath}`);
  const at = parseAt(args.at);
  const upload = args.upload === true;
  const prefix = typeof args.prefix === "string" ? args.prefix : payload.name;
  if (!/^[A-Za-z0-9_]+$/.test(prefix)) throw new Error(`--prefix wants letters, digits and underscores, got ${prefix}`);
  if (payload.format === "blendlib-textured/1") {
    const tint = typeof args.tint === "string" ? args.tint.replace(/^#/, "") : "FFFFFF";
    if (!/^[0-9A-Fa-f]{6}$/.test(tint)) throw new Error(`--tint wants a hex colour like 1E5BD8, got ${args.tint}`);
    return pushTextured(payload, port, parentPath, at, upload, prefix, tint);
  }
  const incoming = `${payload.name}__incoming`;

  console.log(`push ${payload.name} -> ${parentPath}.${payload.name} at (${at.join(", ")}), ${upload ? "UPLOAD" : "preview"}`);
  await call(port, prepareLua(parentPath, incoming, at));
  for (const mesh of payload.meshes) {
    const result = await callJson(port, meshLua(parentPath, incoming, at, mesh, payload.quantum, upload, prefix));
    console.log(`  ${result.name}: ${result.triangles} triangles${result.assetId ? ", asset " + result.assetId : ""}${result.recreated ? "  (model was missing, recreated)" : ""}`);
  }
  const socketCount = await pushExtras(payload, port, parentPath, incoming, at);
  const expected = payload.meshes.map((mesh) => ({ name: mesh.name, triangles: mesh.triangles }));
  const report = await callJson(port, verifyLua(parentPath, incoming, payload.name, at, expected, upload, payload.source || "", payload.triangles, socketCount));
  for (const problem of report.problems) console.log(`  x ${problem}`);
  for (const part of report.parts) if (part.problem) console.log(`  x ${part.name}: ${part.problem}`);
  if (report.ok) {
    console.log(`verify (separate call): OK, ${report.path}, ${report.parts.length} parts`);
    if (!upload) console.log("  previews: they look real in Edit but do not exist in Play; push --upload once the asset is approved");
  } else {
    console.log(`verify (separate call): FAILED; ${parentPath}.${incoming} is left for inspection and the old model is untouched`);
    process.exitCode = 1;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = args._[0];
  if (command === "build") return build(args);
  if (command === "brushes") return renderBrushes(args);
  if (command === "probe") return probe();
  if (command === "selftest") return selftest(args);
  if (command === "push") return push(args);
  console.log(fs.readFileSync(__filename, "utf8").split("\n").slice(1, 15).join("\n"));
  process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = { call, callJson };
