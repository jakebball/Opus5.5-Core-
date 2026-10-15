-- MeshTris.luau: builds the triangle table /perfbudget's survey reads (perf.js `tris`, Edit only, through bridge.deferred).
-- perf.js prepends SKIP_JSON (mesh keys already counted on an earlier run). Every mesh referenced in the place is noted:
-- MeshPart.MeshId with its LodTris0/Triangles attribute, LodMesh1/LodMesh2 with LodTris1/LodTris2, FileMesh SpecialMeshes.
-- A mesh with no attribute and not in SKIP is loaded as an EditableMesh and its faces counted (needs Game Settings >
-- Security > Allow Mesh / Image APIs, and access to the asset). Returns JSON { tris, names, failed, counted }.
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local skip = HttpService:JSONDecode(SKIP_JSON)
local tris, names, failed = {}, {}, {}
local ROOTS = {
	workspace,
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterPack"),
	game:GetService("Lighting"),
}

local function assetKey(meshId)
	if type(meshId) ~= "string" then
		return nil
	end
	return string.match(meshId, "(%d+)%s*$")
end

local function note(meshId, count, name)
	local key = assetKey(meshId)
	if not key then
		return
	end
	if not names[key] then
		names[key] = name
	end
	if type(count) == "number" and not tris[key] then
		tris[key] = count
	end
	if tris[key] == nil then
		tris[key] = false
	end
end

for _, root in ROOTS do
	for _, item in root:GetDescendants() do
		if item:IsA("MeshPart") then
			local name = item:GetFullName()
			note(item.MeshId, item:GetAttribute("LodTris0") or item:GetAttribute("Triangles"), name)
			note(item:GetAttribute("LodMesh1"), item:GetAttribute("LodTris1"), name .. " [LOD1]")
			note(item:GetAttribute("LodMesh2"), item:GetAttribute("LodTris2"), name .. " [LOD2]")
		elseif item:IsA("SpecialMesh") and item.MeshType == Enum.MeshType.FileMesh then
			note(item.MeshId, nil, item:GetFullName())
		end
	end
end

local counted = 0
for key, count in tris do
	if count ~= false or skip[key] then
		continue
	end
	local loaded, mesh = pcall(AssetService.CreateEditableMeshAsync, AssetService, Content.fromUri("rbxassetid://" .. key))
	if loaded and mesh then
		tris[key] = #mesh:GetFaces()
		mesh:Destroy()
		counted += 1
	else
		failed[key] = tostring(mesh)
	end
end

local out = {}
for key, count in tris do
	if count then
		out[key] = count
	end
end
return HttpService:JSONEncode({ tris = out, names = names, failed = failed, counted = counted })
