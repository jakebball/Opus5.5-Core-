local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("AdminPanel_Invoke")
local listItemTemplate = ReplicatedStorage:WaitForChild("AdminListItem")

local playerGui = player:WaitForChild("PlayerGui")
local adminPanel = playerGui:WaitForChild("AdminPanel")
local main = adminPanel:WaitForChild("Main")
local openPanelFrame = adminPanel:WaitForChild("OpenPanel")

local closeButton = main:WaitForChild("Close")
local titleLabel = main:WaitForChild("Title")
local descriptionLabel = main:WaitForChild("Description")
local runCommandButton = main:WaitForChild("RunCommand")
local numberInputTemplate = main:WaitForChild("NumberInput")
local categoryTabsFrame = main:WaitForChild("CategoryTabs", 10)

local listHolder = main:WaitForChild("ListHolder")
local commandListFrame = listHolder:WaitForChild("CommandList")
local parametersFrame = listHolder:WaitForChild("Parameters")
local parameterOptionsFrame = listHolder:WaitForChild("ParameterOptions")

local openButton = openPanelFrame:WaitForChild("Button")

local commandData = {}
local selectedCommand = nil
local paramInputs = {}

local categories = {}
local selectedCategory = nil
local categoryButtons = {}

local function setupGlobalMessageListener()
	local adminRemote = ReplicatedStorage:WaitForChild("ADMIN_REMOTE", 10)
	local globalMessageTemplate = ReplicatedStorage:WaitForChild("GlobalMessageItem", 10)
	local globalMessageGui = playerGui:WaitForChild("GlobalMessage", 10)
	if not adminRemote or not globalMessageTemplate or not globalMessageGui then return end

	local container = globalMessageGui:WaitForChild("Main")
	local activeMessages = {}
	local MAX_MESSAGES = 3
	local SIZE_WEIGHTS = { [1] = {1}, [2] = {0.6, 0.4}, [3] = {0.5, 0.33, 0.17} }
	local RESIZE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function repositionActiveMessages()
		local count = math.min(#activeMessages, MAX_MESSAGES)
		local weights = SIZE_WEIGHTS[count] or SIZE_WEIGHTS[MAX_MESSAGES]
		local yPosition = 0
		for index, entry in activeMessages do
			local weight = weights[index] or weights[#weights]
			TweenService:Create(entry.clone, RESIZE_TWEEN, {
				Size = UDim2.new(1, 0, weight, 0),
				Position = UDim2.new(0, 0, yPosition, 0),
			}):Play()
			yPosition = yPosition + weight
		end
	end

	local function removeMessage(entry)
		for index, active in activeMessages do
			if active == entry then
				table.remove(activeMessages, index)
				break
			end
		end
		local tweenOut = TweenService:Create(entry.clone, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) })
		tweenOut:Play()
		tweenOut.Completed:Wait()
		entry.clone:Destroy()
		repositionActiveMessages()
	end

	adminRemote.OnClientEvent:Connect(function(action, data)
		if action ~= "GlobalMessage" or not data then return end

		if #activeMessages >= MAX_MESSAGES then
			task.spawn(removeMessage, activeMessages[1])
			task.wait(0.15)
		end

		local clone = globalMessageTemplate:Clone()
		clone.Size = UDim2.new(1, 0, 0, 0)
		clone.Position = UDim2.new(0, 0, 1, 0)
		clone.ClipsDescendants = true
		clone.Parent = container

		local label = clone:FindFirstChild("Frame") and clone.Frame:FindFirstChild("Label")
		if label then
			label.Text = data.Message or ""
		end

		local icon = clone:FindFirstChild("Frame") and clone.Frame:FindFirstChild("PlayerIcon")
		if icon and data.UserId then
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(data.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and content then
				icon.Image = content
			end
		end

		local entry = { clone = clone }
		table.insert(activeMessages, entry)
		repositionActiveMessages()

		task.wait(data.Duration or 10)

		removeMessage(entry)
	end)
end

local commands = remote:InvokeServer("getCommands")

if not commands or #commands == 0 then
	openPanelFrame.Visible = false
	main.Visible = false
	setupGlobalMessageListener()
	return
end

commandData = commands

local function clearList(frame)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function createListItem(text, parent, layoutOrder)
	local item = listItemTemplate:Clone()
	item.Label.Text = text
	item.LayoutOrder = layoutOrder or 0
	item.Parent = parent
	return item
end

local function createTextInput(placeholder, parent, layoutOrder)
	local input = numberInputTemplate:Clone()
	input.Text = ""
	input.PlaceholderText = placeholder or ""
	input.Visible = true
	input.Size = UDim2.new(1, 0, 0, 40)
	input.LayoutOrder = layoutOrder or 0
	input.Parent = parent
	return input
end

local function buildCommandList()
	clearList(commandListFrame)

	for i, cmd in commandData do
		if not selectedCategory or cmd.Category == selectedCategory then
			local item = createListItem(cmd.Name, commandListFrame, cmd.LayoutOrder)
			item.Button.MouseButton1Click:Connect(function()
				for _, child in commandListFrame:GetChildren() do
					if child:IsA("Frame") then
						child.BackgroundColor3 = Color3.new(0, 0, 0)
					end
				end
				item.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
				selectCommand(cmd)
			end)
		end
	end

	local layout = commandListFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		commandListFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end
end

function selectCommand(cmd)
	selectedCommand = cmd
	paramInputs = {}

	titleLabel.Text = cmd.Name
	descriptionLabel.Text = cmd.Description
	descriptionLabel.TextColor3 = Color3.new(1, 1, 1)

	clearList(parametersFrame)
	clearList(parameterOptionsFrame)

	local paramOptions = {}
	local paramLabels = {}
	local activeParamName = nil
	local firstOptionsParam = nil

	local function showOptionsFor(paramName)
		clearList(parameterOptionsFrame)
		activeParamName = paramName

		for name, label in pairs(paramLabels) do
			if name == paramName then
				label.BackgroundColor3 = Color3.fromRGB(0, 60, 120)
			else
				label.BackgroundColor3 = Color3.new(0, 0, 0)
			end
		end

		local data = paramOptions[paramName]
		if not data then return end

		for j, entry in data.items do
			local item = createListItem(entry.text, parameterOptionsFrame, j)
			if data.selected and data.selected == entry.value then
				item.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
			end
			item.Button.MouseButton1Click:Connect(function()
				data.onSelect(entry.value)
				for _, child in parameterOptionsFrame:GetChildren() do
					if child:IsA("Frame") then
						child.BackgroundColor3 = Color3.new(0, 0, 0)
					end
				end
				item.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
			end)
		end

		local optLayout = parameterOptionsFrame:FindFirstChildOfClass("UIListLayout")
		if optLayout then
			parameterOptionsFrame.CanvasSize = UDim2.new(0, 0, 0, optLayout.AbsoluteContentSize.Y)
		end
	end

	for i, param in cmd.Parameters do
		if param.Type == "Number" then
			local label = createListItem(param.Name .. (param.Required and " *" or ""), parametersFrame, i * 2 - 1)
			local defaultText = param.Default and tostring(param.Default) or ""
			local input = createTextInput(param.Name .. " (number)", parametersFrame, i * 2)
			input.Text = defaultText

			paramInputs[param.Name] = {
				Type = "Number",
				getValue = function()
					local text = input.Text
					if text == "" then return param.Default end
					return tonumber(text)
				end,
			}

		elseif param.Type == "String" then
			local label = createListItem(param.Name .. (param.Required and " *" or ""), parametersFrame, i * 2 - 1)
			local input = createTextInput(param.Name, parametersFrame, i * 2)
			input.Text = param.Default or ""

			paramInputs[param.Name] = {
				Type = "String",
				getValue = function()
					local text = input.Text
					if text == "" then return param.Default end
					return text
				end,
			}

		elseif param.Type == "PlayerList" then
			local label = createListItem(param.Name .. (param.Required and " *" or ""), parametersFrame, i * 2 - 1)
			paramLabels[param.Name] = label

			local selectedUserId = nil

			local items = {}
			for _, p in Players:GetPlayers() do
				table.insert(items, { text = p.Name .. " (" .. p.UserId .. ")", value = p.UserId })
			end

			paramOptions[param.Name] = {
				items = items,
				selected = nil,
				onSelect = function(value)
					selectedUserId = value
					paramOptions[param.Name].selected = value
				end,
			}

			if not firstOptionsParam then
				firstOptionsParam = param.Name
			end

			label.Button.MouseButton1Click:Connect(function()
				showOptionsFor(param.Name)
			end)

			paramInputs[param.Name] = {
				Type = "PlayerList",
				getValue = function()
					return selectedUserId
				end,
			}

		elseif param.Type == "List" then
			local label = createListItem(param.Name .. (param.Required and " *" or ""), parametersFrame, i * 2 - 1)
			paramLabels[param.Name] = label

			local selectedValue = param.Default

			local items = {}
			if param.ListItems then
				for j, option in param.ListItems do
					table.insert(items, { text = option, value = option })
				end
			end

			paramOptions[param.Name] = {
				items = items,
				selected = param.Default,
				onSelect = function(value)
					selectedValue = value
					paramOptions[param.Name].selected = value
				end,
			}

			if not firstOptionsParam then
				firstOptionsParam = param.Name
			end

			label.Button.MouseButton1Click:Connect(function()
				showOptionsFor(param.Name)
			end)

			paramInputs[param.Name] = {
				Type = "List",
				getValue = function()
					return selectedValue
				end,
			}

		elseif param.Type == "CustomList" then
			local label = createListItem(param.Name .. (param.Required and " *" or ""), parametersFrame, i * 2 - 1)
			paramLabels[param.Name] = label

			local selectedValue = nil

			local items = {}
			local fetchedItems = remote:InvokeServer("getCustomList", cmd.Name, param.Name)
			if type(fetchedItems) == "table" then
				for j, entry in fetchedItems do
					table.insert(items, { text = entry.Text, value = entry.Value })
				end
			end

			paramOptions[param.Name] = {
				items = items,
				selected = nil,
				onSelect = function(value)
					selectedValue = value
					paramOptions[param.Name].selected = value
				end,
			}

			if not firstOptionsParam then
				firstOptionsParam = param.Name
			end

			label.Button.MouseButton1Click:Connect(function()
				showOptionsFor(param.Name)
			end)

			paramInputs[param.Name] = {
				Type = "CustomList",
				getValue = function()
					return selectedValue
				end,
			}
		end
	end

	local paramLayout = parametersFrame:FindFirstChildOfClass("UIListLayout")
	if paramLayout then
		parametersFrame.CanvasSize = UDim2.new(0, 0, 0, paramLayout.AbsoluteContentSize.Y)
	end

	if firstOptionsParam then
		showOptionsFor(firstOptionsParam)
	end
end

local function resetCommandSelection()
	selectedCommand = nil
	paramInputs = {}
	titleLabel.Text = "Admin Panel"
	descriptionLabel.Text = "[Command Description]"
	descriptionLabel.TextColor3 = Color3.new(1, 1, 1)
	clearList(parametersFrame)
	clearList(parameterOptionsFrame)
end

local function refreshCategoryHighlight()
	for name, frame in categoryButtons do
		if name == selectedCategory then
			frame.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
		else
			frame.BackgroundColor3 = Color3.new(0, 0, 0)
		end
	end
end

-- Global-mode warning: Global commands broadcast across every running server, so
-- when the Global category is selected we tint the whole panel red and surface a
-- loud banner underneath it. The tint is a non-Active overlay (Active = false) so
-- clicks still pass through to the controls/tabs beneath it.
local GLOBAL_CATEGORY = "Global"
local globalModeTint = nil
local globalModeWarning = nil

local function ensureGlobalModeWarning()
	if globalModeTint then return end

	globalModeTint = Instance.new("Frame")
	globalModeTint.Name = "GlobalModeTint"
	globalModeTint.Size = UDim2.new(1, 0, 1, 0)
	globalModeTint.Position = UDim2.new(0, 0, 0, 0)
	globalModeTint.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	globalModeTint.BackgroundTransparency = 0.55
	globalModeTint.BorderSizePixel = 0
	globalModeTint.ZIndex = 5000
	globalModeTint.Active = false
	globalModeTint.Visible = false
	local tintCorner = Instance.new("UICorner")
	tintCorner.Parent = globalModeTint
	globalModeTint.Parent = main

	globalModeWarning = Instance.new("TextLabel")
	globalModeWarning.Name = "GlobalModeWarning"
	globalModeWarning.AnchorPoint = Vector2.new(0.5, 0)
	globalModeWarning.Position = UDim2.new(0.5, 0, 1.02, 0)
	globalModeWarning.Size = UDim2.new(1, 0, 0.13, 0)
	globalModeWarning.BackgroundTransparency = 1
	globalModeWarning.Text = "YOU ARE IN GLOBAL MODE!"
	globalModeWarning.TextColor3 = Color3.fromRGB(255, 45, 45)
	globalModeWarning.TextScaled = true
	globalModeWarning.Font = Enum.Font.GothamBlack
	globalModeWarning.ZIndex = 5001
	globalModeWarning.Visible = false
	local warnStroke = Instance.new("UIStroke")
	warnStroke.Thickness = 3
	warnStroke.Color = Color3.new(0, 0, 0)
	warnStroke.Parent = globalModeWarning
	globalModeWarning.Parent = main
end

local function applyGlobalMode()
	ensureGlobalModeWarning()
	local isGlobal = selectedCategory ~= nil and string.lower(selectedCategory) == string.lower(GLOBAL_CATEGORY)
	globalModeTint.Visible = isGlobal
	globalModeWarning.Visible = isGlobal
end

local function buildCategoryTabs()
	clearList(categoryTabsFrame)
	categoryButtons = {}

	for index, name in categories do
		local tab = listItemTemplate:Clone()
		tab.Label.Text = name
		tab.Size = UDim2.new(0, 120, 1, 0)
		tab.LayoutOrder = index
		tab.Parent = categoryTabsFrame
		categoryButtons[name] = tab

		tab.Button.MouseButton1Click:Connect(function()
			if selectedCategory == name then return end
			selectedCategory = name
			refreshCategoryHighlight()
			applyGlobalMode()
			resetCommandSelection()
			buildCommandList()
		end)
	end

	refreshCategoryHighlight()
end

runCommandButton.MouseButton1Click:Connect(function()
	if not selectedCommand then
		descriptionLabel.Text = "Select a command first."
		descriptionLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		return
	end

	local params = {}
	for paramName, inputData in pairs(paramInputs) do
		params[paramName] = inputData.getValue()
	end

	descriptionLabel.Text = "Executing..."
	descriptionLabel.TextColor3 = Color3.new(1, 1, 1)

	local success, message = remote:InvokeServer("execute", selectedCommand.Name, params)

	if success then
		descriptionLabel.Text = message or "Success"
		descriptionLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
	else
		descriptionLabel.Text = message or "Failed"
		descriptionLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	end
end)

local panelOpen = false

local function togglePanel()
	panelOpen = not panelOpen
	main.Visible = panelOpen
end

openButton.MouseButton1Click:Connect(togglePanel)

closeButton.MouseButton1Click:Connect(function()
	panelOpen = false
	main.Visible = false
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Semicolon then
		togglePanel()
	end
end)

openPanelFrame.Visible = true
main.Visible = false
numberInputTemplate.Visible = false

if categoryTabsFrame then
	categories = remote:InvokeServer("getCategories")
	if type(categories) ~= "table" then
		categories = {}
	end

	if #categories > 0 then
		selectedCategory = categories[1]
		buildCategoryTabs()
		applyGlobalMode()
	else
		categoryTabsFrame.Visible = false
	end
end

buildCommandList()
setupGlobalMessageListener()