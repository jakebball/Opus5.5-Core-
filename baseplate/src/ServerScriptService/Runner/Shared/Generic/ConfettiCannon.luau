local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Generic.Trove)

local ConfettiCannon = {}

local localPlayer = Players.LocalPlayer

const CONFETTI_SFX_FOLDER = "Tiles"
const CONFETTI_SFX_NAME = "Confetti"

local function playConfettiSfx()
	local folder = SoundService:FindFirstChild(CONFETTI_SFX_FOLDER)
	local source = folder and folder:FindFirstChild(CONFETTI_SFX_NAME)
	if not (source and source:IsA("Sound")) then return end

	local clone = source:Clone()
	clone.Name = "ConfettiCannonSfx"
	clone.Parent = SoundService
	clone:Play()
	local tail = (source.TimeLength > 0 and source.TimeLength or 2) + 0.5
	Debris:AddItem(clone, tail)
end

const DEFAULTS = {
	Count = 35,
	Duration = 1.6,
	Gravity = 4.2,
	SizeMin = 0.07,
	SizeMax = 0.11,
	InitialVyMin = -2.7,
	InitialVyMax = -1.95,
	InitialVxRange = 1.1,
	SpawnY = 1.05,
	SpawnXMin = 0.1,
	SpawnXMax = 0.9,
	SpinDegPerSec = 240,
	SpinVariance = 180,
	ZIndex = 4,
	DisplayOrder = 11,
	OverlayName = "ConfettiOverlay",
	PieceName = "ConfettiPiece",
}

local function pickValue(opts, key)
	local v = opts[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

local function resolveIconAsset(opts)
	if type(opts.IconAssetId) == "string" and opts.IconAssetId ~= "" then
		return opts.IconAssetId
	end
	local template = opts.IconTemplate
	if template and template:IsA("ImageLabel") then
		local img = template.Image
		if type(img) == "string" and img ~= "" then
			return img
		end
	end
	return nil
end

local function resolvePieceColor(opts, palette, numColors)
	if palette and numColors > 0 then
		return palette[math.random(1, numColors)]
	end
	if typeof(opts.PieceColor) == "Color3" then
		return opts.PieceColor
	end
	return nil
end

local function buildPiece(iconAssetId, pieceColor, sizeMin, sizeMax,spawnXMin, spawnXMax, spawnY, zIndex, pieceName)
	local piece
	if iconAssetId then
		piece = Instance.new("ImageLabel")
		piece.BackgroundTransparency = 1
		piece.Image = iconAssetId
		if pieceColor then
			piece.ImageColor3 = pieceColor
		end
	else
		piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		if pieceColor then
			piece.BackgroundColor3 = pieceColor
		end
	end
	piece.Name = pieceName
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.ZIndex = zIndex

	local sz = sizeMin + math.random() * math.max(0, sizeMax - sizeMin)
	piece.Size = UDim2.fromScale(sz, sz)

	local x = spawnXMin + math.random() * math.max(0, spawnXMax - spawnXMin)
	piece.Position = UDim2.fromScale(x, spawnY)
	piece.Rotation = math.random(0, 359)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = piece

	return piece, x
end

function ConfettiCannon.fire(opts, parentTrove)
	opts = opts or {}

	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local iconAssetId = resolveIconAsset(opts)
	local palette = opts.Colors
	local numColors = (typeof(palette) == "table") and #palette or 0

	if not iconAssetId and numColors == 0 and typeof(opts.PieceColor) ~= "Color3" then
		return nil
	end

	if opts.PlayConfettiSfx ~= false then
		playConfettiSfx()
	end

	local count = math.max(1, math.floor(pickValue(opts, "Count")))
	local duration = pickValue(opts, "Duration")
	local gravity = pickValue(opts, "Gravity")
	local sizeMin = pickValue(opts, "SizeMin")
	local sizeMax = pickValue(opts, "SizeMax")
	local initialVyMin = pickValue(opts, "InitialVyMin")
	local initialVyMax = pickValue(opts, "InitialVyMax")
	local initialVxRange = pickValue(opts, "InitialVxRange")
	local spawnY = pickValue(opts, "SpawnY")
	local spawnXMin = pickValue(opts, "SpawnXMin")
	local spawnXMax = pickValue(opts, "SpawnXMax")
	local spinDegPerSec = pickValue(opts, "SpinDegPerSec")
	local spinVariance = pickValue(opts, "SpinVariance")
	local zIndex = pickValue(opts, "ZIndex")
	local displayOrder = pickValue(opts, "DisplayOrder")
	local overlayName = pickValue(opts, "OverlayName")
	local pieceName = pickValue(opts, "PieceName")

	local fxTrove
	if parentTrove then
		local ok, extended = pcall(parentTrove.Extend, parentTrove)
		if ok then
			fxTrove = extended
		end
	end
	fxTrove = fxTrove or Trove.new()

	local overlay = Instance.new("ScreenGui")
	overlay.Name = overlayName
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = displayOrder
	overlay.Parent = playerGui
	fxTrove:Add(overlay)

	local pieces = table.create(count)
	for i = 1, count do
		local pieceColor = resolvePieceColor(opts, palette, numColors)
		if iconAssetId and not pieceColor then
			pieceColor = Color3.new(1, 1, 1)
		end

		local piece, x = buildPiece(iconAssetId, pieceColor,
			sizeMin, sizeMax, spawnXMin, spawnXMax, spawnY, zIndex, pieceName)
		piece.Parent = overlay

		local vx = (math.random() * 2 - 1) * initialVxRange
		local vy = initialVyMin + math.random() * math.max(0, initialVyMax - initialVyMin)
		local spin = spinDegPerSec + (math.random() * 2 - 1) * spinVariance

		pieces[i] = { piece = piece, x = x, y = spawnY, vx = vx, vy = vy, spin = spin }
	end

	local startedAt = os.clock()
	local lastTick = startedAt
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local deltaTime = now - lastTick
		lastTick = now
		local elapsed = now - startedAt
		if elapsed >= duration then
			conn:Disconnect()
			fxTrove:Destroy()
			return
		end
		for _, p in pieces do
			local piece = p.piece
			if piece.Parent then
				p.vy = p.vy + gravity * deltaTime
				p.x = p.x + p.vx * deltaTime
				p.y = p.y + p.vy * deltaTime
				piece.Position = UDim2.fromScale(p.x, p.y)
				piece.Rotation = piece.Rotation + p.spin * deltaTime
			end
		end
	end)
	fxTrove:Add(conn, "Disconnect")

	return fxTrove
end

return ConfettiCannon
