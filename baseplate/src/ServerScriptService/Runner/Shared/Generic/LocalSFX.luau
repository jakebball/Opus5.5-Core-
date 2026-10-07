
local SoundService = game:GetService("SoundService")

local SoundWindow = require(script.Parent.SoundWindow)

const CLEANUP_FALLBACK = 15

local LocalSFX = {}

function LocalSFX.play(template)
	if not template or not template:IsA("Sound") then return nil end
	local sound = template:Clone()
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(CLEANUP_FALLBACK, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	sound:Play()
	SoundWindow.apply(sound, function()
		sound:Destroy()
	end)
	return sound
end

return LocalSFX
