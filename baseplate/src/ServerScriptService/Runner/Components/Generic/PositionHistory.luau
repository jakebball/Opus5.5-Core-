
local RunService = game:GetService("RunService")

local PositionHistory = {}
PositionHistory.__index = PositionHistory
PositionHistory.Tag = "PositionHistory"

PositionHistory.combatants = nil

const HISTORY_SECONDS = 1

function PositionHistory.Start()
	setmetatable(PositionHistory, { __index = PositionHistory.BaseClass })
	workspace:AddTag(PositionHistory.Tag)
end

function PositionHistory.new(instance)
	local self = setmetatable(PositionHistory.BaseClass.new(instance), PositionHistory)
	self.tracks = {}
	self.trove:Add(RunService.Heartbeat:Connect(function()
		self:_record()
	end))
	return self
end

function PositionHistory:_record()
	if not PositionHistory.combatants then return end

	local now = workspace:GetServerTimeNow()
	local cutoff = now - HISTORY_SECONDS
	local seen = {}
	for _, candidate in PositionHistory.combatants() do
		if candidate.Parent then
			local boxCFrame, boxSize = PositionHistory.HitscanMath.volumeOf(candidate)
			if boxCFrame then
				seen[candidate] = true
				local track = self.tracks[candidate]
				if not track then
					track = {}
					self.tracks[candidate] = track
				end
				table.insert(track, { time = now, cframe = boxCFrame, size = boxSize })
				while track[1] and track[1].time < cutoff do
					table.remove(track, 1)
				end
			end
		end
	end

	for candidate in self.tracks do
		if not seen[candidate] then
			self.tracks[candidate] = nil
		end
	end
end

-- The volume this candidate occupied at `timestamp`, linearly interpolated between the two
-- bracketing samples: fraction = (timestamp - older.time) / (newer.time - older.time). A stamp
-- newer than the last sample, or a candidate with no history yet, reads the live volume; one
-- older than the whole buffer pins to the oldest sample.
function PositionHistory:volumeAt(candidate, timestamp)
	local track = self.tracks[candidate]
	local count = track and #track or 0
	if count == 0 or timestamp >= track[count].time then
		return PositionHistory.HitscanMath.volumeOf(candidate)
	end
	if timestamp <= track[1].time then
		return track[1].cframe, track[1].size
	end

	for index = count - 1, 1, -1 do
		local older = track[index]
		if timestamp >= older.time then
			local newer = track[index + 1]
			local span = newer.time - older.time
			local fraction = if span > 0 then (timestamp - older.time) / span else 1
			return older.cframe:Lerp(newer.cframe, fraction), older.size:Lerp(newer.size, fraction)
		end
	end
	return track[1].cframe, track[1].size
end

return PositionHistory