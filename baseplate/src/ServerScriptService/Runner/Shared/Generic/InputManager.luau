local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local InputManager = {}

local actions = {}
local keyToActions = {}
local inputTypeToActions = {}
local heldKeys = {}
local heldInputTypes = {}
local initialized = false

local preferenceSignal
local scrollSignal
local lastWasTouch = false

local function actionIsActive(action)
	return action.active or action.virtual
end

local function releaseActionIfUnheld(action)
	if not action or not action.active then return end
	if action.keys then
		for _, key in action.keys do
			if heldKeys[key] then return end
		end
	end
	if action.inputTypes then
		for _, inputType in action.inputTypes do
			if heldInputTypes[inputType] then return end
		end
	end
	action.active = false
	if not actionIsActive(action) then
		action.endedSignal:Fire()
	end
end

local function beginAction(action)
	if not action or action.active then return end
	local wasActive = actionIsActive(action)
	action.active = true
	if not wasActive then
		action.beganSignal:Fire()
	end
end

local function init()
	if initialized then return end
	if not RunService:IsClient() then return end
	initialized = true

	lastWasTouch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			heldKeys[input.KeyCode] = true
			local boundActions = keyToActions[input.KeyCode]
			if not boundActions then return end
			for _, actionName in boundActions do
				beginAction(actions[actionName])
			end
			return
		end

		local boundActions = inputTypeToActions[inputType]
		if not boundActions then return end
		heldInputTypes[inputType] = true
		for _, actionName in boundActions do
			beginAction(actions[actionName])
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			heldKeys[input.KeyCode] = nil
			local boundActions = keyToActions[input.KeyCode]
			if not boundActions then return end
			for _, actionName in boundActions do
				releaseActionIfUnheld(actions[actionName])
			end
			return
		end

		heldInputTypes[inputType] = nil
		local boundActions = inputTypeToActions[inputType]
		if not boundActions then return end
		for _, actionName in boundActions do
			releaseActionIfUnheld(actions[actionName])
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if scrollSignal then
			scrollSignal:Fire(input.Position.Z)
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local isTouch = inputType == Enum.UserInputType.Touch
		if isTouch ~= lastWasTouch then
			lastWasTouch = isTouch
			if preferenceSignal then
				preferenceSignal:Fire(isTouch)
			end
		end
	end)
end

function InputManager.setup(GoodSignal)
	InputManager._GoodSignal = GoodSignal
	preferenceSignal = preferenceSignal or GoodSignal.new()
	scrollSignal = scrollSignal or GoodSignal.new()
	init()
end

-- inputs is a list mixing Enum.KeyCode and Enum.UserInputType (e.g. MouseButton1 / Touch).
-- A pure-keycode list behaves exactly as before.
function InputManager.bindAction(name, inputs)
	if not InputManager._GoodSignal then
		warn("[InputManager] Must call setup(GoodSignal) before bindAction")
		return
	end

	local keys = {}
	local inputTypes = {}
	for _, input in inputs do
		if typeof(input) == "EnumItem" and input.EnumType == Enum.KeyCode then
			table.insert(keys, input)
		elseif typeof(input) == "EnumItem" and input.EnumType == Enum.UserInputType then
			table.insert(inputTypes, input)
		end
	end

	actions[name] = {
		keys = keys,
		inputTypes = inputTypes,
		active = false,
		virtual = false,
		beganSignal = InputManager._GoodSignal.new(),
		endedSignal = InputManager._GoodSignal.new(),
	}

	for _, keyCode in keys do
		if not keyToActions[keyCode] then
			keyToActions[keyCode] = {}
		end
		table.insert(keyToActions[keyCode], name)
	end
	for _, inputType in inputTypes do
		if not inputTypeToActions[inputType] then
			inputTypeToActions[inputType] = {}
		end
		table.insert(inputTypeToActions[inputType], name)
	end
end

function InputManager.isActive(name)
	local action = actions[name]
	return action and actionIsActive(action) or false
end

function InputManager.onActionBegan(name, callback)
	local action = actions[name]
	if not action then return nil end
	return action.beganSignal:Connect(callback)
end

function InputManager.onActionEnded(name, callback)
	local action = actions[name]
	if not action then return nil end
	return action.endedSignal:Connect(callback)
end

function InputManager.setVirtual(name, active)
	local action = actions[name]
	if not action then return end
	local newVirtual = active and true or false
	if newVirtual == action.virtual then return end
	local wasActive = actionIsActive(action)
	action.virtual = newVirtual
	local nowActive = actionIsActive(action)
	if not wasActive and nowActive then
		action.beganSignal:Fire()
	elseif wasActive and not nowActive then
		action.endedSignal:Fire()
	end
end

function InputManager.onScroll(callback)
	if not scrollSignal then return nil end
	return scrollSignal:Connect(callback)
end

function InputManager.isTouchPreferred()
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

function InputManager.onInputPreferenceChanged(callback)
	if not preferenceSignal then return nil end
	return preferenceSignal:Connect(callback)
end

return InputManager
