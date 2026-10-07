
local SoundWindow = {}

const FROM_ATTRIBUTE = "PlayFrom"
const LENGTH_ATTRIBUTE = "PlayLength"

function SoundWindow.apply(sound, finish)
	local from = sound:GetAttribute(FROM_ATTRIBUTE)
	if typeof(from) == "number" and from > 0 then
		sound.TimePosition = from
	end

	local length = sound:GetAttribute(LENGTH_ATTRIBUTE)
	if typeof(length) ~= "number" or length <= 0 then return end

	task.delay(length, function()
		if not sound.Parent then return end
		sound:Stop()
		if finish then finish() end
	end)
end

return SoundWindow
