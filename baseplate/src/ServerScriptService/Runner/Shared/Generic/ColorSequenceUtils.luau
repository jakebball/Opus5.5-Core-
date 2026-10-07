local ColorSequenceUtils = {}

ColorSequenceUtils.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 150, 40)),
	ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 230, 60)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(90, 220, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 170, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(180, 90, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 120, 220)),
})

function ColorSequenceUtils.Sample(sequence, t)
	if not sequence then return Color3.new(1, 1, 1) end
	local keypoints = sequence.Keypoints
	if not keypoints or #keypoints == 0 then return Color3.new(1, 1, 1) end
	if t <= keypoints[1].Time then return keypoints[1].Value end
	if t >= keypoints[#keypoints].Time then return keypoints[#keypoints].Value end
	for index = 1, #keypoints - 1 do
		local a, b = keypoints[index], keypoints[index + 1]
		if t >= a.Time and t <= b.Time then
			local span = b.Time - a.Time
			local localT = span > 0 and (t - a.Time) / span or 0
			return a.Value:Lerp(b.Value, localT)
		end
	end
	return keypoints[#keypoints].Value
end

return ColorSequenceUtils