
local Players = game:GetService("Players")

local ServerIndicator = {}
ServerIndicator.__index = ServerIndicator
ServerIndicator.Tag = "ServerIndicator"

local localPlayer = Players.LocalPlayer

function ServerIndicator.Start()
	setmetatable(ServerIndicator, { __index = ServerIndicator.BaseClass })
end

function ServerIndicator.new(instance)
	local self = setmetatable(ServerIndicator.BaseClass.new(instance), ServerIndicator)

	instance.CanCollide = false
	instance.Transparency = 1

	return self
end

function ServerIndicator:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	
	if self.trove then
		self.trove:Clean()
	end
end

return ServerIndicator
