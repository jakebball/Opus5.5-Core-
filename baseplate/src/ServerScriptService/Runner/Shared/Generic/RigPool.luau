local ServerStorage = game:GetService("ServerStorage")

local RigPool = {}
RigPool.__index = RigPool

function RigPool.new(folderName, options)
	return setmetatable({
		folderName = folderName,
		allowRepeats = options ~= nil and options.allowRepeats == true,
		used = {},
	}, RigPool)
end

function RigPool:source()
	return ServerStorage:FindFirstChild(self.folderName) or workspace:FindFirstChild(self.folderName)
end

function RigPool:take()
	local folder = self:source()
	if not folder then
		warn("[RigPool] no ServerStorage." .. self.folderName .. " - rigs are authored in Studio")
		return nil
	end

	local rigs = folder:GetChildren()
	if #rigs == 0 then
		warn("[RigPool] " .. self.folderName .. " is empty - author at least one rig in Studio")
		return nil
	end

	local candidates = {}
	for _, rig in rigs do
		if self.allowRepeats or not self.used[rig.Name] then
			table.insert(candidates, rig)
		end
	end

	if #candidates == 0 then
		warn("[RigPool] every rig in " .. self.folderName .. " is already in use")
		return nil
	end

	local chosen = candidates[math.random(#candidates)]
	if not self.allowRepeats then
		self.used[chosen.Name] = true
	end

	return chosen:Clone()
end

function RigPool:release(rigName)
	self.used[rigName] = nil
end

return RigPool
