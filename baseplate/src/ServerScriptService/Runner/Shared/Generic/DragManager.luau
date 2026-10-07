local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Assets = require(script.Parent.Assets)

local DragManager = {}

local currentDrag = nil

function DragManager.isDragging()
	return currentDrag ~= nil
end

function DragManager.startDrag(sourceType, guid, itemData, originFrame, hotbarAssignment)
	if currentDrag then return end

	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local hotbarItemTemplate = Assets.Get("Gui/HotbarItem")
	if not hotbarItemTemplate then return end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "DragOverlay"
	overlay.DisplayOrder = 100
	overlay.IgnoreGuiInset = false
	overlay.Parent = playerGui

	local ghost = hotbarItemTemplate:Clone()
	ghost.Size = UDim2.new(0, originFrame.AbsoluteSize.X, 0, originFrame.AbsoluteSize.Y)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundTransparency = 0.4

	local origTitle = originFrame:FindFirstChild("Title")
	if origTitle then
		ghost.Title.Text = origTitle.Text
	end
	local origLevel = originFrame:FindFirstChild("Level")
	if origLevel then
		ghost.Level.Text = origLevel.Text
	end
	local origIcon = originFrame:FindFirstChild("Icon")
	if origIcon then
		ghost.Icon.Image = origIcon.Image
	end
	ghost.NumberIndex.Visible = false

	local ghostButton = ghost:FindFirstChild("Button")
	if ghostButton then
		ghostButton:Destroy()
	end

	ghost.Parent = overlay

	local originAbsPos = originFrame.AbsolutePosition + originFrame.AbsoluteSize / 2

	local connections = {}

	currentDrag = {
		sourceType = sourceType,
		guid = guid,
		itemData = itemData,
		ghost = ghost,
		overlay = overlay,
		originAbsPos = originAbsPos,
		hotbarAssignment = hotbarAssignment,
	}

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			ghost.Position = UDim2.new(0, input.Position.X, 0, input.Position.Y)
		end
	end))

	local mousePos = UserInputService:GetMouseLocation()
	ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		for _, conn in connections do
			conn:Disconnect()
		end

		local dropPos = Vector2.new(input.Position.X, input.Position.Y)
		local success = DragManager.handleDrop(sourceType, guid, dropPos, hotbarAssignment)

		if success then
			overlay:Destroy()
		else
			local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(ghost, tweenInfo, {
				Position = UDim2.new(0, originAbsPos.X, 0, originAbsPos.Y),
			})
			tween:Play()
			tween.Completed:Connect(function()
				overlay:Destroy()
			end)
		end

		currentDrag = nil
	end))
end

function DragManager.handleDrop(sourceType, guid, dropPos, hotbarAssignment)
	if not hotbarAssignment then return false end

	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return false end

	local hotbarFrame = playerGui:FindFirstChild("BottomHUD") and playerGui.BottomHUD:FindFirstChild("Hotbar")
	local backpackHolder
	local backpackGui = playerGui:FindFirstChild("Backpack")
	if backpackGui then
		local main = backpackGui:FindFirstChild("Main")
		if main then backpackHolder = main:FindFirstChild("Holder") end
	end

	local atDrop = playerGui:GetGuiObjectsAtPosition(dropPos.X, dropPos.Y)

	local hitHotbar = false
	local hitBackpack = false
	local hotbarSlotGuid = nil
	for _, gui in atDrop do
		if hotbarFrame and (gui == hotbarFrame or gui:IsDescendantOf(hotbarFrame)) then
			hitHotbar = true
			if not hotbarSlotGuid then
				local node = gui
				while node and node ~= hotbarFrame do
					local attr = node:GetAttribute("ItemGuid")
					if attr then
						hotbarSlotGuid = attr
						break
					end
					node = node.Parent
				end
			end
		end
		if backpackHolder and (gui == backpackHolder or gui:IsDescendantOf(backpackHolder)) then
			hitBackpack = true
		end
	end

	if sourceType == "hotbar" and hitBackpack then
		hotbarAssignment:requestMoveToBackpack(guid)
		return true
	elseif sourceType == "backpack" and hitHotbar then
		if hotbarSlotGuid and hotbarSlotGuid ~= guid then
			hotbarAssignment:requestSwapHotbarSlot(guid, hotbarSlotGuid)
		else
			hotbarAssignment:requestMoveToHotbar(guid)
		end
		return true
	end

	return false
end

return DragManager