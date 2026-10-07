local ProjectileCodec = {}

const INT16_MIN = -32768
const INT16_MAX = 32767
-- Positions ride as a delta from the round's own spawn origin, so 1/64-stud steps cover
-- +/- 512 studs of flight whatever the map's world extents are.
const POSITION_SCALE = 64
-- Euler components live in [-pi, pi]; 32767/pi keeps the full int16 range.
const ROTATION_SCALE = 10430

ProjectileCodec.HeaderSize = 1
ProjectileCodec.EntrySize = 13
ProjectileCodec.MaxEntries = 60

local function quantize(value, scale)
	return math.clamp(math.round(value * scale), INT16_MIN, INT16_MAX)
end

function ProjectileCodec.create(count)
	return buffer.create(ProjectileCodec.HeaderSize + count * ProjectileCodec.EntrySize)
end

function ProjectileCodec.writeCount(stream, count)
	buffer.writeu8(stream, 0, count)
end

function ProjectileCodec.writeEntry(stream, index, slot, delta, rotation)
	local offset = ProjectileCodec.HeaderSize + index * ProjectileCodec.EntrySize
	buffer.writeu8(stream, offset, slot)
	buffer.writei16(stream, offset + 1, quantize(delta.X, POSITION_SCALE))
	buffer.writei16(stream, offset + 3, quantize(delta.Y, POSITION_SCALE))
	buffer.writei16(stream, offset + 5, quantize(delta.Z, POSITION_SCALE))

	local pitch, yaw, roll = rotation:ToEulerAnglesXYZ()
	buffer.writei16(stream, offset + 7, quantize(pitch, ROTATION_SCALE))
	buffer.writei16(stream, offset + 9, quantize(yaw, ROTATION_SCALE))
	buffer.writei16(stream, offset + 11, quantize(roll, ROTATION_SCALE))
end

function ProjectileCodec.readCount(stream)
	if typeof(stream) ~= "buffer" then
		return 0
	end
	local length = buffer.len(stream)
	if length < ProjectileCodec.HeaderSize then
		return 0
	end
	local capacity = (length - ProjectileCodec.HeaderSize) // ProjectileCodec.EntrySize
	return math.min(buffer.readu8(stream, 0), capacity)
end

function ProjectileCodec.readEntry(stream, index)
	local offset = ProjectileCodec.HeaderSize + index * ProjectileCodec.EntrySize
	local slot = buffer.readu8(stream, offset)
	local delta = Vector3.new(
		buffer.readi16(stream, offset + 1) / POSITION_SCALE,
		buffer.readi16(stream, offset + 3) / POSITION_SCALE,
		buffer.readi16(stream, offset + 5) / POSITION_SCALE
	)
	local rotation = CFrame.Angles(
		buffer.readi16(stream, offset + 7) / ROTATION_SCALE,
		buffer.readi16(stream, offset + 9) / ROTATION_SCALE,
		buffer.readi16(stream, offset + 11) / ROTATION_SCALE
	)
	return slot, delta, rotation
end

return ProjectileCodec
