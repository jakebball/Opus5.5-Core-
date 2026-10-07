
local SoundWindow = require(script.Parent.SoundWindow)

local WorldSFX = {}

const CLEANUP_FALLBACK = 15
const HOST_NAME = "WorldSFX"

function WorldSFX.playAt(template, position)
	if not template or not template:IsA("Sound") then return nil end
	if typeof(position) ~= "Vector3" then return nil end

	local host = Instance.new("Attachment")
	host.Name = HOST_NAME
	host.Parent = workspace.Terrain
	host.WorldPosition = position

	local sound = template:Clone()
	sound.Parent = host
	sound.Ended:Once(function()
		host:Destroy()
	end)
	task.delay(CLEANUP_FALLBACK, function()
		if host.Parent then
			host:Destroy()
		end
	end)

	sound:Play()
	SoundWindow.apply(sound, function()
		host:Destroy()
	end)
	return sound
end

return WorldSFX
