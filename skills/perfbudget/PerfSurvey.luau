-- PerfSurvey.luau: the client half of /perfbudget. perf.js prepends CONFIG_JSON and TRIS_JSON and installs the result as
-- StarterPlayerScripts.__PerfSurvey for one playtest. It rides the route: at each stop it parks the character, holds a
-- chase camera at every heading, lets the place's own LOD and streaming settle, and estimates what the GPU is asked to
-- draw from there.
--
-- An estimate, not the render stats: Roblox exposes neither draw calls nor rendered triangles to scripts.
--   triangles   exact per mesh from the mesh table, read off the live MeshId, so a LOD swap (ApplyMesh rewrites MeshId)
--               counts at the tier on screen; unions use TriangleCount, primitives fixed counts
--   draw calls  one per instancing group (same mesh + material + surface look), one per see-through part (sorted, not
--               instanced), one per shadow-casting mesh group inside shadowRange, plus decals, emitters, beams, trails
--               and highlights (two each) on visible parts
--   visibility  frustum and maxDistance only: no occlusion, no quality-level distance culling, so it is an upper bound
-- perf.js also prepends RUN_ID (the run nonce) and __signalDirector (tells the server director "begin" / "done"; it
-- ends the test). Lines go out as prints, read back from Studio's session log: "[perf:<id>] start|done|error: ...",
-- "[perf:<id>:<kind>] <seq> <i>/<n> <json chunk>", "[perf:<id>:frame] <stop>". The log cuts a line at ~1020 bytes, so a
-- payload goes out in CHUNK-character pieces.
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local config = HttpService:JSONDecode(CONFIG_JSON)
local meshTris = HttpService:JSONDecode(TRIS_JSON)
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local chase = config.camera or {}

local CHUNK = 700
local TOP = config.top or 15
local CAMERA_BIND = "PerfSurveyCamera"
local PRIMITIVE_TRIS = { Block = 12, Wedge = 8, CornerWedge = 6, Cylinder = 128, Ball = 760 }
local EXTRA_COST = {
	Decal = 1,
	Texture = 1,
	ParticleEmitter = 1,
	Fire = 1,
	Smoke = 1,
	Sparkles = 1,
	Beam = 1,
	Trail = 1,
	Highlight = 2,
}

local sequence = 0

local function emit(kind, payload)
	sequence += 1
	local text = HttpService:JSONEncode(payload)
	local count = math.max(1, math.ceil(#text / CHUNK))
	for index = 1, count do
		print(string.format("[perf:%s:%s] %d %d/%d %s", RUN_ID, kind, sequence, index, count, string.sub(text, (index - 1) * CHUNK + 1, index * CHUNK)))
	end
end

local function log(text)
	print("[perf:" .. RUN_ID .. "] " .. text)
end

local function assetKey(meshId)
	if type(meshId) ~= "string" then
		return nil
	end
	return string.match(meshId, "(%d+)%s*$")
end

local function meshKeyOf(part)
	if part:IsA("MeshPart") then
		return assetKey(part.MeshId)
	end
	local special = part:FindFirstChildOfClass("SpecialMesh")
	if special and special.MeshType == Enum.MeshType.FileMesh then
		return assetKey(special.MeshId)
	end
	return nil
end

local function trianglesOf(part, meshKey)
	if meshKey then
		return meshTris[meshKey]
	end
	if part:IsA("PartOperation") then
		local read, count = pcall(function()
			return part.TriangleCount
		end)
		return if read then count else nil
	end
	if part:IsA("Part") then
		return PRIMITIVE_TRIS[part.Shape.Name] or 12
	end
	return 12
end

local function surfaceKey(part)
	local surface = part:FindFirstChildOfClass("SurfaceAppearance")
	if not surface then
		return if part:IsA("MeshPart") then part.TextureID else ""
	end
	local read, uri = pcall(function()
		return surface.ColorMapContent.Uri
	end)
	if read and uri then
		return uri
	end
	read, uri = pcall(function()
		return surface.ColorMap
	end)
	if read and uri then
		return uri
	end
	return "sa:" .. surface.Name
end

local function shapeKey(part)
	return if part:IsA("Part") then part.Shape.Name else part.ClassName
end

local function labelsOf(part)
	-- group: the path below workspace cut at groupDepth names (Map/Dressing/Meadow); asset: the nearest Model's name
	local names = {}
	local asset
	local node = part
	while node and node ~= workspace do
		table.insert(names, 1, node.Name)
		if not asset and node ~= part and node:IsA("Model") then
			asset = node.Name
		end
		node = node.Parent
	end
	local depth = math.min(config.groupDepth or 3, math.max(#names - 1, 1))
	return table.concat(names, "/", 1, depth), asset or part.Name
end

local function bump(map, name, triangles, drawKey)
	local entry = map[name]
	if not entry then
		entry = { tris = 0, parts = 0, draws = 0, keys = {} }
		map[name] = entry
	end
	entry.tris += triangles
	entry.parts += 1
	if not drawKey then
		entry.draws += 1
	elseif not entry.keys[drawKey] then
		entry.keys[drawKey] = true
		entry.draws += 1
	end
end

local function ranked(map, field)
	local list = {}
	for name, entry in map do
		table.insert(list, { name = name, tris = entry.tris, parts = entry.parts, draws = entry.draws })
	end
	table.sort(list, function(left, right)
		return left[field] > right[field]
	end)
	for index = #list, TOP + 1, -1 do
		list[index] = nil
	end
	return list
end

local function anchorOf(item)
	local anchor
	if item:IsA("Beam") or item:IsA("Trail") then
		anchor = item.Attachment0 and item.Attachment0.Parent
	elseif item:IsA("Highlight") then
		anchor = item.Adornee or item.Parent
	else
		anchor = item.Parent
	end
	if anchor and anchor:IsA("Attachment") then
		anchor = anchor.Parent
	end
	return anchor
end

local function anchorVisible(anchor, visible)
	if not anchor then
		return false
	end
	if visible[anchor] then
		return true
	end
	if anchor:IsA("Model") then
		for _, child in anchor:GetChildren() do
			if visible[child] then
				return true
			end
		end
	end
	return false
end

local function measure(view)
	local viewport = camera.ViewportSize
	local tanV = math.tan(math.rad(camera.FieldOfView) / 2)
	local tanH = tanV * viewport.X / math.max(viewport.Y, 1)
	local secV = math.sqrt(1 + tanV * tanV)
	local secH = math.sqrt(1 + tanH * tanH)
	local maxDistance = config.maxDistance or 3000
	local shadowRange = config.shadowRange or 400
	local shadows = Lighting.GlobalShadows
	local terrain = workspace.Terrain

	local result = { tris = 0, shadowTris = 0, draws = 0, shadowDraws = 0, extras = 0, parts = 0, unknownParts = 0 }
	local drawKeys, shadowKeys, visible, unknown = {}, {}, {}, {}
	local groups, assets, meshes = {}, {}, {}
	local extras = {}

	for _, item in workspace:GetDescendants() do
		if EXTRA_COST[item.ClassName] then
			table.insert(extras, item)
			continue
		end
		if not item:IsA("BasePart") or item == terrain then
			continue
		end
		local transparency = math.max(item.Transparency, item.LocalTransparencyModifier)
		if transparency >= 1 then
			continue
		end
		local relative = view:PointToObjectSpace(item.Position)
		local depth = -relative.Z
		local radius = item.Size.Magnitude / 2
		if depth + radius < 0 or depth - radius > maxDistance then
			continue
		end
		if math.abs(relative.Y) - depth * tanV > radius * secV or math.abs(relative.X) - depth * tanH > radius * secH then
			continue
		end

		visible[item] = true
		local meshKey = meshKeyOf(item)
		local triangles = trianglesOf(item, meshKey)
		if not triangles then
			result.unknownParts += 1
			if meshKey then
				unknown[meshKey] = true
			end
			triangles = 0
		end
		result.parts += 1
		result.tris += triangles

		local drawKey = nil
		if transparency > 0 then
			result.draws += 1
		else
			drawKey = (meshKey or shapeKey(item)) .. "|" .. item.Material.Name .. "|" .. surfaceKey(item)
			if not drawKeys[drawKey] then
				drawKeys[drawKey] = true
				result.draws += 1
			end
		end
		if shadows and item.CastShadow and depth <= shadowRange then
			result.shadowTris += triangles
			local shadowKey = meshKey or shapeKey(item)
			if not shadowKeys[shadowKey] then
				shadowKeys[shadowKey] = true
				result.shadowDraws += 1
			end
		end

		local group, asset = labelsOf(item)
		bump(groups, group, triangles, drawKey)
		bump(assets, asset, triangles, drawKey)
		if meshKey then
			bump(meshes, meshKey, triangles, drawKey)
		end
	end

	for _, item in extras do
		local enabled = true
		pcall(function()
			enabled = item.Enabled
		end)
		if enabled == false then
			continue
		end
		if (item:IsA("Decal") or item:IsA("Texture")) and item.Transparency >= 1 then
			continue
		end
		if anchorVisible(anchorOf(item), visible) then
			result.extras += EXTRA_COST[item.ClassName]
		end
	end

	local unknownList = {}
	for key in unknown do
		if #unknownList >= 10 then
			break
		end
		table.insert(unknownList, key)
	end
	result.unknownMeshes = unknownList

	local breakdown = {
		groupsByTris = ranked(groups, "tris"),
		groupsByDraws = ranked(groups, "draws"),
		assetsByTris = ranked(assets, "tris"),
		assetsByDraws = ranked(assets, "draws"),
		meshesByTris = ranked(meshes, "tris"),
	}
	return result, breakdown
end

local desired = nil

local function holdCamera(cframe)
	desired = cframe
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
end

local function viewFor(focus, yawDegrees)
	local yaw = math.rad(yawDegrees)
	local forward = Vector3.new(math.sin(yaw), 0, -math.cos(yaw))
	local eye = focus - forward * (chase.distance or 24) + Vector3.new(0, chase.height or 9, 0)
	local target = focus + forward * (chase.lookAhead or 20) + Vector3.new(0, chase.lookHeight or 3, 0)
	return CFrame.lookAt(eye, target)
end

local function groundAt(position, character)
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(Vector3.new(position.X, 2000, position.Z), Vector3.new(0, -4000, 0), parameters)
	return if hit then hit.Position else position
end

local function park(character, root, stop)
	local given = stop.position
	local target = Vector3.new(given[1], given[2] or 0, given[3])
	pcall(player.RequestStreamAroundAsync, player, target, 15)
	local ground = if given[2] then target else groundAt(target, character)
	root.Anchored = false
	character:PivotTo(CFrame.new(ground + Vector3.new(0, config.standHeight or 4, 0)))
	root.Anchored = true
	return root.Position
end

local function qualityLevel()
	local read, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name
	end)
	return if read then level else "unknown"
end

local root = nil

RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Last.Value, function()
	if desired then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = desired
	end
end)

local ran, failure = xpcall(function()
	local character = player.Character or player.CharacterAdded:Wait()
	root = character:WaitForChild("HumanoidRootPart", 30)
	if not root then
		error("the character has no HumanoidRootPart")
	end
	task.wait(config.loadSeconds or 10)
	log("start")
	__signalDirector("begin")
	emit("meta", {
		viewport = { camera.ViewportSize.X, camera.ViewportSize.Y },
		fov = camera.FieldOfView,
		shadows = Lighting.GlobalShadows,
		streaming = workspace.StreamingEnabled,
		quality = qualityLevel(),
	})

	local count = config.headings or 8
	for index, stop in config.stops do
		local focus = park(character, root, stop)
		holdCamera(viewFor(focus, 0))
		task.wait(config.settleSeconds or 6)

		local headings = {}
		local worstTris, worstDraws = nil, nil
		for heading = 0, count - 1 do
			local yaw = heading * 360 / count
			holdCamera(viewFor(focus, yaw))
			task.wait(config.headingSeconds or 1.2)
			local result, breakdown = measure(camera.CFrame)
			result.yaw = yaw
			table.insert(headings, result)
			local trisTotal = result.tris + result.shadowTris
			local drawsTotal = result.draws + result.shadowDraws + result.extras
			if not worstTris or trisTotal > worstTris.total then
				worstTris = { total = trisTotal, yaw = yaw, breakdown = breakdown }
			end
			if not worstDraws or drawsTotal > worstDraws.total then
				worstDraws = { total = drawsTotal, yaw = yaw, breakdown = breakdown }
			end
			task.wait()
		end

		emit("stop", {
			index = index,
			name = stop.name,
			focus = { focus.X, focus.Y, focus.Z },
			headings = headings,
			worstTris = worstTris,
			worstDraws = worstDraws,
		})
		log(string.format("stop %d/%d %s", index, #config.stops, stop.name))

		if config.frames then
			holdCamera(viewFor(focus, worstTris.yaw))
			task.wait(config.headingSeconds or 1.2)
			print("[perf:" .. RUN_ID .. ":frame] " .. stop.name)
			task.wait(config.frameHoldSeconds or 2.5)
		end
	end
end, debug.traceback)

desired = nil
RunService:UnbindFromRenderStep(CAMERA_BIND)
camera.CameraType = Enum.CameraType.Custom
if root then
	root.Anchored = false
end
if not ran then
	log("error: " .. tostring(failure))
end
log("done")
__signalDirector("done")
