local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

const RUN_ID = "__RUN_ID__"
const CHUNK_SIZE = 4000000
const STALE_SECONDS = 1800
const POSITION_SCALE = 10000
const NORMAL_SCALE = 1000
const UV_SCALE = 10000

local store = _G.AssetShot
if not store then
	store = {}
	_G.AssetShot = store
end
if store[RUN_ID] then
	return "started (duplicate delivery)"
end
local now = os.clock()
for runId, staleJob in store do
	if now - staleJob.started > STALE_SECONDS then
		store[runId] = nil
	end
end
local job = { state = "running", started = now, progress = "posing" }
store[RUN_ID] = job

local ARGS = HttpService:JSONDecode(__ARGS__)
local KNOWN = ARGS.known or {}
-- the largest texture side sent to the renderer; shot.js passes it (--image-limit) and names its image cache after it
local IMAGE_LIMIT = math.clamp(math.floor(tonumber(ARGS.imageLimit) or 1024), 16, 4096)

local meshes = {}
local meshOrder = {}
local objectKeys = {}
local objectCount = 0
local images = {}
local unsupported = {}
local notedInstances = {}
local failedMeshes = {}
local failedImages = {}
local partInfos = {}
local partIndexOf = {}
local frames = {}
local temporaries = {}
local warnings = {}

local function encode(value)
	return HttpService:JSONEncode(value)
end

local function vectorJson(vector)
	return string.format("[%.7g,%.7g,%.7g]", vector.X, vector.Y, vector.Z)
end

local function colorJson(color)
	return string.format("[%.4g,%.4g,%.4g]", color.R, color.G, color.B)
end

local function cframeList(cframe)
	local components = { cframe:GetComponents() }
	for index, value in components do
		components[index] = string.format(if index <= 3 then "%.9g" else "%.7g", value)
	end
	return table.concat(components, ",")
end

local function note(instance, kind)
	if notedInstances[instance] then
		return
	end
	notedInstances[instance] = true
	unsupported[kind] = (unsupported[kind] or 0) + 1
end

local function resolve(path)
	if typeof(path) == "Instance" then
		return path
	end
	local segments = string.split(path, ".")
	local first = 1
	if segments[1] == "game" then
		first = 2
	end
	local current
	local serviceName = segments[first]
	if serviceName == "workspace" or serviceName == "Workspace" then
		current = workspace
	else
		local found, service = pcall(game.GetService, game, serviceName)
		current = if found and service then service else game:FindFirstChild(serviceName)
	end
	if not current then
		error(path .. ": no service named " .. tostring(serviceName), 0)
	end
	for position = first + 1, #segments do
		local child = current:FindFirstChild(segments[position])
		if not child then
			error(path .. ": no " .. segments[position] .. " under " .. current:GetFullName(), 0)
		end
		current = child
	end
	return current
end

local function worldCFrame(instance)
	if instance:IsA("Camera") or instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Bone") then
		return instance.TransformedWorldCFrame
	elseif instance:IsA("Attachment") then
		return instance.WorldCFrame
	elseif instance:IsA("PVInstance") then
		return instance:GetPivot()
	end
	return CFrame.identity
end

local function contentKey(uri)
	if type(uri) ~= "string" or uri == "" then
		return nil, nil
	end
	local assetId = string.match(uri, "^rbxassetid://(%d+)") or string.match(uri, "[?&][iI][dD]=(%d+)") or string.match(uri, "^(%d+)$")
	if assetId then
		return "asset:" .. assetId, "rbxassetid://" .. assetId
	end
	local localPath = string.match(uri, "^rbxasset://(.+)$")
	if localPath then
		return "local:" .. localPath, uri
	end
	return "uri:" .. uri, uri
end

local function readMesh(mesh, wantUV)
	local vertexIds = mesh:GetVertices()
	local vertexIndex = {}
	local positions = table.create(#vertexIds * 3)
	for index, vertexId in vertexIds do
		vertexIndex[vertexId] = index - 1
		local position = mesh:GetPosition(vertexId)
		positions[index * 3 - 2] = math.round(position.X * POSITION_SCALE)
		positions[index * 3 - 1] = math.round(position.Y * POSITION_SCALE)
		positions[index * 3] = math.round(position.Z * POSITION_SCALE)
	end
	local faceIds = mesh:GetFaces()
	local faces = table.create(#faceIds * 3)
	local withColors = #faceIds > 0 and (pcall(mesh.GetFaceColors, mesh, faceIds[1]))
	local withNormals = #faceIds > 0 and (pcall(mesh.GetFaceNormals, mesh, faceIds[1]))
	local withUVs = wantUV and #faceIds > 0 and (pcall(mesh.GetFaceUVs, mesh, faceIds[1]))
	local colorSlots, colorList, faceColors = {}, {}, table.create(#faceIds * 3)
	local normalSlots, normalList, faceNormals = {}, {}, table.create(#faceIds * 3)
	local uvSlots, uvList, faceUVs = {}, {}, table.create(#faceIds * 3)
	for faceNumber, faceId in faceIds do
		local base = faceNumber * 3 - 3
		local corners = mesh:GetFaceVertices(faceId)
		for corner = 1, 3 do
			faces[base + corner] = vertexIndex[corners[corner]] or 0
		end
		if withColors then
			local colorIds = mesh:GetFaceColors(faceId)
			for corner = 1, 3 do
				local colorId = colorIds and colorIds[corner]
				local slot = -1
				if colorId then
					slot = colorSlots[colorId]
					if not slot then
						slot = -1
						local found, color = pcall(mesh.GetColor, mesh, colorId)
						if found and color then
							local alphaFound, alpha = pcall(mesh.GetColorAlpha, mesh, colorId)
							slot = #colorList // 4
							table.insert(colorList, math.round(color.R * 255))
							table.insert(colorList, math.round(color.G * 255))
							table.insert(colorList, math.round(color.B * 255))
							table.insert(colorList, math.round((if alphaFound and alpha then alpha else 1) * 255))
						end
						colorSlots[colorId] = slot
					end
				end
				faceColors[base + corner] = slot
			end
		end
		if withNormals then
			local normalIds = mesh:GetFaceNormals(faceId)
			for corner = 1, 3 do
				local normalId = normalIds and normalIds[corner]
				local slot = -1
				if normalId then
					slot = normalSlots[normalId]
					if not slot then
						slot = -1
						local found, normal = pcall(mesh.GetNormal, mesh, normalId)
						if found and normal then
							slot = #normalList // 3
							table.insert(normalList, math.round(normal.X * NORMAL_SCALE))
							table.insert(normalList, math.round(normal.Y * NORMAL_SCALE))
							table.insert(normalList, math.round(normal.Z * NORMAL_SCALE))
						end
						normalSlots[normalId] = slot
					end
				end
				faceNormals[base + corner] = slot
			end
		end
		if withUVs then
			local uvIds = mesh:GetFaceUVs(faceId)
			for corner = 1, 3 do
				local uvId = uvIds and uvIds[corner]
				local slot = -1
				if uvId then
					slot = uvSlots[uvId]
					if not slot then
						slot = -1
						local found, uv = pcall(mesh.GetUV, mesh, uvId)
						if found and uv then
							slot = #uvList // 2
							table.insert(uvList, math.round(uv.X * UV_SCALE))
							table.insert(uvList, math.round(uv.Y * UV_SCALE))
						end
						uvSlots[uvId] = slot
					end
				end
				faceUVs[base + corner] = slot
			end
		end
	end
	local pieces = { '{"positions":[', table.concat(positions, ","), '],"faces":[', table.concat(faces, ","), "]" }
	if withColors and #colorList > 0 then
		table.insert(pieces, ',"colors":[' .. table.concat(colorList, ",") .. '],"faceColors":[' .. table.concat(faceColors, ",") .. "]")
	end
	if withNormals and #normalList > 0 then
		table.insert(pieces, ',"normals":[' .. table.concat(normalList, ",") .. '],"faceNormals":[' .. table.concat(faceNormals, ",") .. "]")
	end
	local hasUV = withUVs and #uvList > 0
	if hasUV then
		table.insert(pieces, ',"uvs":[' .. table.concat(uvList, ",") .. '],"faceUVs":[' .. table.concat(faceUVs, ",") .. "]")
	end
	table.insert(pieces, ',"hasUV":' .. tostring(hasUV and true or false) .. "}")
	return table.concat(pieces)
end

-- Textures travel as base64 of their RGBA rows. EncodingService encodes a 1024 x 1024 texture in about 0.01 s; the
-- Luau fallback gives the same bytes in about 0.4 s.
local encodingService = nil
pcall(function()
	encodingService = game:GetService("EncodingService")
end)
local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64Pairs = nil

local function base64(data)
	if encodingService then
		local encoded, result = pcall(encodingService.Base64Encode, encodingService, data)
		if encoded then
			return buffer.tostring(result)
		end
	end
	if not base64Pairs then
		base64Pairs = buffer.create(8192)
		for value = 0, 4095 do
			buffer.writeu8(base64Pairs, value * 2, string.byte(BASE64, value // 64 + 1))
			buffer.writeu8(base64Pairs, value * 2 + 1, string.byte(BASE64, value % 64 + 1))
		end
	end
	local length = buffer.len(data)
	local groups = length // 3
	local out = buffer.create((length + 2) // 3 * 4)
	local target = 0
	for source = 0, groups * 3 - 1, 3 do
		local value = buffer.readu8(data, source) * 65536 + buffer.readu8(data, source + 1) * 256 + buffer.readu8(data, source + 2)
		buffer.writeu16(out, target, buffer.readu16(base64Pairs, value // 4096 * 2))
		buffer.writeu16(out, target + 2, buffer.readu16(base64Pairs, value % 4096 * 2))
		target += 4
	end
	local left = length - groups * 3
	if left > 0 then
		local source = groups * 3
		local value = buffer.readu8(data, source) * 65536 + (if left == 2 then buffer.readu8(data, source + 1) * 256 else 0)
		buffer.writeu16(out, target, buffer.readu16(base64Pairs, value // 4096 * 2))
		buffer.writeu8(out, target + 2, if left == 2 then string.byte(BASE64, value % 4096 // 64 + 1) else 61)
		buffer.writeu8(out, target + 3, 61)
	end
	return buffer.tostring(out)
end

-- A texture over the limit is averaged down in whole blocks, so its fine detail survives as tone instead of
-- aliasing the way point sampling did.
local function shrink(pixels, width, height)
	local stepX = math.max(1, math.ceil(width / IMAGE_LIMIT))
	local stepY = math.max(1, math.ceil(height / IMAGE_LIMIT))
	if stepX == 1 and stepY == 1 then
		return pixels, width, height
	end
	local outWidth = width // stepX
	local outHeight = height // stepY
	local area = stepX * stepY
	local half = area // 2
	local out = buffer.create(outWidth * outHeight * 4)
	for row = 0, outHeight - 1 do
		for column = 0, outWidth - 1 do
			local red, green, blue, alpha = 0, 0, 0, 0
			for dy = 0, stepY - 1 do
				local offset = ((row * stepY + dy) * width + column * stepX) * 4
				for _ = 1, stepX do
					red += buffer.readu8(pixels, offset)
					green += buffer.readu8(pixels, offset + 1)
					blue += buffer.readu8(pixels, offset + 2)
					alpha += buffer.readu8(pixels, offset + 3)
					offset += 4
				end
			end
			local target = (row * outWidth + column) * 4
			buffer.writeu8(out, target, (red + half) // area)
			buffer.writeu8(out, target + 1, (green + half) // area)
			buffer.writeu8(out, target + 2, (blue + half) // area)
			buffer.writeu8(out, target + 3, (alpha + half) // area)
		end
	end
	return out, outWidth, outHeight
end

local function imageJson(image)
	local size = image.Size
	local width, height = math.floor(size.X), math.floor(size.Y)
	local pixels, outWidth, outHeight = shrink(image:ReadPixelsBuffer(Vector2.zero, size), width, height)
	return string.format('{"width":%d,"height":%d,"base64":"%s"}', outWidth, outHeight, base64(pixels))
end

local function readImage(uri)
	local image = AssetService:CreateEditableImageAsync(Content.fromUri(uri))
	local read, result = pcall(imageJson, image)
	image:Destroy()
	if not read then
		error(result, 0)
	end
	return result
end

local function registerMesh(key, uri, wantUV)
	local entry = meshes[key]
	if not entry then
		entry = { uri = uri, wantUV = wantUV }
		meshes[key] = entry
		table.insert(meshOrder, key)
	elseif wantUV then
		entry.wantUV = true
	end
	return entry
end

local function objectMeshKey(object)
	local key = objectKeys[object]
	if not key then
		objectCount += 1
		key = "object:" .. objectCount
		objectKeys[object] = key
		local entry = registerMesh(key, nil, false)
		local found, data = pcall(readMesh, object, true)
		if found then
			entry.data = data
		else
			failedMeshes[key] = tostring(data)
		end
	end
	return key
end

local objectImageCount = 0
local objectImageKeys = {}
local function registerObjectImage(image)
	-- a live EditableImage (an unuploaded painted texture), read straight out of memory and left alive; parts that
	-- share one image (a horse's 18 parts share 2) share one copy in the payload
	local key = objectImageKeys[image]
	if key then
		return key
	end
	objectImageCount += 1
	key = "asset:object-" .. RUN_ID .. "-" .. objectImageCount
	images[key] = { uri = "object", data = imageJson(image) }
	objectImageKeys[image] = key
	return key
end

local function registerImage(uri)
	local key, normalized = contentKey(uri)
	if not key then
		return nil
	end
	if not images[key] then
		images[key] = { uri = normalized }
	end
	return key
end

local function variantFor(name)
	local variant = MaterialService:FindFirstChild(name, true)
	if variant and variant:IsA("MaterialVariant") then
		return variant
	end
	return nil
end

local function describe(part)
	local fields = {
		'"name":' .. encode(part.Name),
		'"class":"' .. part.ClassName .. '"',
		'"material":"' .. part.Material.Name .. '"',
		'"castShadow":' .. tostring(part.CastShadow),
	}
	local function add(name, value)
		table.insert(fields, '"' .. name .. '":' .. value)
	end
	if part.MaterialVariant ~= "" then
		add("variant", encode(part.MaterialVariant))
		local variant = variantFor(part.MaterialVariant)
		if variant then
			add("tile", string.format("%.6g", variant.StudsPerTile))
		end
	end
	local textureUri
	local objectTexture
	local special = part:FindFirstChildWhichIsA("DataModelMesh")
	if part:IsA("MeshPart") then
		local content = part.MeshContent
		local key
		local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
		if appearance then
			local colorContent = appearance.ColorMapContent
			if colorContent.SourceType == Enum.ContentSourceType.Object and colorContent.Object then
				objectTexture = registerObjectImage(colorContent.Object)
			else
				local found, colorMap = pcall(function()
					return appearance.ColorMap
				end)
				if found and colorMap ~= "" then
					textureUri = colorMap
				elseif colorContent.SourceType == Enum.ContentSourceType.Uri then
					textureUri = colorContent.Uri
				else
					note(appearance, "SurfaceAppearance (drawn untextured)")
				end
			end
			add("alphaMode", '"' .. appearance.AlphaMode.Name .. '"')
			add("tint", colorJson(appearance.Color))
		end
		if part.TextureID ~= "" then
			textureUri = part.TextureID
		end
		if content.SourceType == Enum.ContentSourceType.Object and content.Object then
			key = objectMeshKey(content.Object)
		elseif content.SourceType == Enum.ContentSourceType.Uri then
			local uri
			key, uri = contentKey(content.Uri)
			if key then
				registerMesh(key, uri, textureUri ~= nil)
			end
		end
		if key then
			add("kind", '"mesh"')
			add("mesh", encode(key))
			add("fit", '"size"')
		else
			add("kind", '"shape"')
			add("shape", '"Block"')
			note(part, "MeshPart with no mesh (drawn as its box)")
		end
	elseif special and special:IsA("SpecialMesh") then
		if special.MeshType == Enum.MeshType.FileMesh then
			local key, uri = contentKey(special.MeshId)
			textureUri = if special.TextureId ~= "" then special.TextureId else nil
			if key then
				registerMesh(key, uri, textureUri ~= nil)
				add("kind", '"mesh"')
				add("mesh", encode(key))
				add("fit", '"native"')
			else
				add("kind", '"shape"')
				add("shape", '"Block"')
			end
			add("tint", vectorJson(special.VertexColor))
		else
			add("kind", '"shape"')
			add("shape", encode("Mesh" .. special.MeshType.Name))
		end
		add("meshScale", vectorJson(special.Scale))
		add("meshOffset", vectorJson(special.Offset))
	elseif special then
		add("kind", '"shape"')
		add("shape", if special:IsA("CylinderMesh") then '"LegacyCylinder"' else '"Block"')
		add("meshScale", vectorJson(special.Scale))
		add("meshOffset", vectorJson(special.Offset))
	else
		local shape = "Block"
		if part:IsA("Part") then
			shape = part.Shape.Name
		elseif part:IsA("WedgePart") then
			shape = "Wedge"
		elseif part:IsA("CornerWedgePart") then
			shape = "CornerWedge"
		elseif not part:IsA("TrussPart") then
			note(part, part.ClassName .. " (drawn as its box)")
		end
		add("kind", '"shape"')
		add("shape", '"' .. shape .. '"')
	end
	if objectTexture then
		add("texture", encode(objectTexture))
	elseif textureUri then
		local imageKey = registerImage(textureUri)
		if imageKey then
			add("texture", encode(imageKey))
		end
	end
	local decals = {}
	for _, child in part:GetChildren() do
		if child:IsA("Texture") then
			note(child, "Texture (tiled, not drawn)")
		elseif child:IsA("Decal") then
			local imageKey = registerImage(child.Texture)
			if imageKey then
				table.insert(decals, string.format('{"face":"%s","image":%s,"color":%s,"transparency":%.4g}', child.Face.Name, encode(imageKey), colorJson(child.Color3), child.Transparency))
			end
		end
	end
	if #decals > 0 then
		add("decals", "[" .. table.concat(decals, ",") .. "]")
	end
	return "{" .. table.concat(fields, ",") .. "}"
end

local function record(part, index)
	local size = part.Size
	local color = part.Color
	return string.format("[%d,%s,%.7g,%.7g,%.7g,%.4g,%.4g,%.4g,%.4g]", index, cframeList(part.CFrame), size.X, size.Y, size.Z, color.R, color.G, color.B, part.Transparency)
end

local function collect(target, into, seen)
	local function consider(instance)
		if instance:IsA("BasePart") then
			if instance:IsA("Terrain") then
				note(instance, "Terrain")
			elseif not seen[instance] then
				seen[instance] = true
				table.insert(into, instance)
			end
		elseif instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("Light") or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") or instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("Highlight") then
			note(instance, instance.ClassName)
		end
	end
	consider(target)
	for _, descendant in target:GetDescendants() do
		consider(descendant)
	end
end

local shot = {}
shot.args = ARGS.args or {}
shot.views = ARGS.views
shot.focus = ARGS.focus
shot.forward = ARGS.forward
shot.find = resolve
shot.pivot = worldCFrame
shot.targets = {}
for _, path in ARGS.targets or {} do
	table.insert(shot.targets, resolve(path))
end

function shot.warn(message)
	table.insert(warnings, tostring(message))
end

function shot.temporary(instance)
	table.insert(temporaries, instance)
	return instance
end

function shot.studioCamera()
	local camera = workspace.CurrentCamera
	return camera.CFrame, camera.FieldOfView, camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
end

function shot.snap(options)
	options = options or {}
	local targets = options.targets or shot.targets
	if #targets == 0 then
		error("snap has no targets", 2)
	end
	local parts, seen = {}, {}
	for _, target in targets do
		collect(resolve(target), parts, seen)
	end
	local records = table.create(#parts)
	for _, part in parts do
		local index = partIndexOf[part]
		if not index then
			table.insert(partInfos, describe(part))
			index = #partInfos - 1
			partIndexOf[part] = index
		end
		table.insert(records, record(part, index))
	end
	local first = resolve(targets[1])
	local frame = options.frame or worldCFrame(first)
	local fields = {
		'"label":' .. encode(options.label or first.Name),
		'"frame":[' .. cframeList(frame) .. "]",
		'"parts":[' .. table.concat(records, ",") .. "]",
	}
	if options.camera then
		table.insert(fields, '"camera":[' .. cframeList(options.camera) .. "]")
		table.insert(fields, string.format('"fov":%.6g', options.fov or 70))
	end
	if options.aspect then
		table.insert(fields, string.format('"aspect":%.6g', options.aspect))
	end
	if options.views then
		table.insert(fields, '"views":' .. encode(options.views))
	end
	if options.focus then
		table.insert(fields, '"focus":' .. encode(options.focus))
	end
	local forward = options.forward or shot.forward
	if forward then
		table.insert(fields, '"forward":' .. encode(forward))
	end
	table.insert(frames, "{" .. table.concat(fields, ",") .. "}")
	job.progress = "snapped " .. #frames
	return #frames
end

local function loadMeshes()
	local pending = {}
	for _, key in meshOrder do
		local entry = meshes[key]
		if not entry.data and entry.uri and not failedMeshes[key] then
			local known = KNOWN[key]
			if not known or (entry.wantUV and known ~= "uv") then
				table.insert(pending, key)
			end
		end
	end
	for index, key in pending do
		job.progress = string.format("mesh %d/%d", index, #pending)
		local entry = meshes[key]
		local found, result = pcall(function()
			local mesh = AssetService:CreateEditableMeshAsync(Content.fromUri(entry.uri))
			local data = readMesh(mesh, entry.wantUV)
			mesh:Destroy()
			return data
		end)
		if found then
			entry.data = result
		else
			failedMeshes[key] = tostring(result)
		end
	end
end

local function loadImages()
	for key, entry in images do
		if string.sub(key, 1, 6) == "asset:" and not KNOWN[key] and not entry.data then
			job.progress = "image " .. key
			local found, result = pcall(readImage, entry.uri)
			if found then
				entry.data = result
			else
				failedImages[key] = tostring(result)
			end
		end
	end
end

local function payload()
	local sun = Lighting:GetSunDirection()
	local lighting = string.format(
		'{"sun":[%.5f,%.5f,%.5f],"ambient":%s,"outdoorAmbient":%s,"brightness":%.4g,"exposure":%.4g,"diffuse":%.4g,"specular":%.4g,"clockTime":%.4g}',
		sun.X,
		sun.Y,
		sun.Z,
		colorJson(Lighting.Ambient),
		colorJson(Lighting.OutdoorAmbient),
		Lighting.Brightness,
		Lighting.ExposureCompensation,
		Lighting.EnvironmentDiffuseScale,
		Lighting.EnvironmentSpecularScale,
		Lighting.ClockTime
	)
	local meshFields = {}
	for _, key in meshOrder do
		local entry = meshes[key]
		if entry.data then
			table.insert(meshFields, encode(key) .. ":" .. entry.data)
		end
	end
	local imageFields = {}
	for key, entry in images do
		table.insert(imageFields, encode(key) .. ":" .. (entry.data or ('{"uri":' .. encode(entry.uri) .. "}")))
	end
	return table.concat({
		'{"version":1,"lighting":',
		lighting,
		',"parts":[',
		table.concat(partInfos, ","),
		'],"frames":[',
		table.concat(frames, ","),
		'],"meshes":{',
		table.concat(meshFields, ","),
		'},"meshKeys":',
		encode(meshOrder),
		',"images":{',
		table.concat(imageFields, ","),
		'},"failedMeshes":',
		encode(failedMeshes),
		',"failedImages":',
		encode(failedImages),
		',"unsupported":',
		encode(unsupported),
		',"warnings":',
		encode(warnings),
		"}",
	})
end

local function POSE(shot)
__POSE__
end

task.defer(function()
	local finished, problem = pcall(function()
		local posed, poseProblem = pcall(POSE, shot)
		for index = #temporaries, 1, -1 do
			local instance = temporaries[index]
			pcall(instance.Destroy, instance)
		end
		if not posed then
			error("pose: " .. tostring(poseProblem), 0)
		end
		if #frames == 0 then
			error("the pose took no snapshots", 0)
		end
		loadMeshes()
		loadImages()
		job.progress = "encoding"
		local text = payload()
		local chunks = {}
		for start = 1, #text, CHUNK_SIZE do
			table.insert(chunks, string.sub(text, start, start + CHUNK_SIZE - 1))
		end
		job.chunks = chunks
		job.bytes = #text
		job.state = "done"
	end)
	if not finished then
		job.state = "error"
		job.error = tostring(problem)
	end
end)
return "started"
