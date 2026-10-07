local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Letterbox = {}
Letterbox.__index = Letterbox

local function newHandle(topBar, bottomBar, ownedGui)
	return setmetatable({
		_top = topBar,
		_bottom = bottomBar,
		gui = ownedGui,
		_topTween = nil,
		_bottomTween = nil,
	}, Letterbox)
end

function Letterbox.wrap(topBar, bottomBar)
	return newHandle(topBar, bottomBar, nil)
end

function Letterbox.create(opts)
	opts = opts or {}
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local gui = Instance.new("ScreenGui")
	gui.Name = opts.Name or "Letterbox"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = opts.DisplayOrder or 100
	gui.ResetOnSpawn = false

	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.Size = UDim2.new(1, 0, 0, 0)
	top.Parent = gui

	local bottom = Instance.new("Frame")
	bottom.Name = "BottomBar"
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BorderSizePixel = 0
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, 0, 1, 0)
	bottom.Size = UDim2.new(1, 0, 0, 0)
	bottom.Parent = gui

	gui.Parent = playerGui
	return newHandle(top, bottom, gui)
end

function Letterbox:_cancel()
	if self._topTween then
		self._topTween:Cancel()
		self._topTween = nil
	end
	if self._bottomTween then
		self._bottomTween:Cancel()
		self._bottomTween = nil
	end
end

function Letterbox:tween(targetScale, duration)
	self:_cancel()
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local size = UDim2.new(1, 0, targetScale, 0)
	if self._top and self._top.Parent then
		self._topTween = TweenService:Create(self._top, info, { Size = size })
		self._topTween:Play()
	end
	if self._bottom and self._bottom.Parent then
		self._bottomTween = TweenService:Create(self._bottom, info, { Size = size })
		self._bottomTween:Play()
	end
end

function Letterbox:snap(targetScale)
	self:_cancel()
	local size = UDim2.new(1, 0, targetScale, 0)
	if self._top then self._top.Size = size end
	if self._bottom then self._bottom.Size = size end
end

function Letterbox:destroy()
	self:_cancel()
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
		self._top = nil
		self._bottom = nil
	elseif self._top or self._bottom then
		self:snap(0)
	end
end

return Letterbox