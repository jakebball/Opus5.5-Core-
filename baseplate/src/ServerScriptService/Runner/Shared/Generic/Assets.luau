local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

local root = nil

local function getRoot()
	if root and root.Parent then
		return root
	end
	root = ReplicatedStorage:FindFirstChild("Assets")
	if not root then
		warn("[Assets] ReplicatedStorage.Assets folder is missing")
	end
	return root
end

function Assets.Get(path)
	if type(path) ~= "string" or path == "" then
		warn("[Assets] Get() expects a non-empty string path")
		return nil
	end

	local node = getRoot()
	if not node then return nil end

	for segment in path:gmatch("[^./]+") do
		local child = node:FindFirstChild(segment)
		if not child then
			warn(("[Assets] missing: '%s' (no child '%s' under %s) — called from:%s"):format(
				path, segment, node:GetFullName(), debug.traceback("", 2)
			))
			return nil
		end
		node = child
	end

	return node
end

function Assets.Clone(path)
	local instance = Assets.Get(path)
	if not instance then return nil end
	return instance:Clone()
end

function Assets.Children(path)
	local instance = Assets.Get(path)
	if not instance then return {} end
	return instance:GetChildren()
end

function Assets.Expect(path)
	local instance = Assets.Get(path)
	if not instance then
		error("[Assets] required asset missing: " .. tostring(path), 2)
	end
	return instance
end

return Assets