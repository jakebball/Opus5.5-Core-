--!strict

export type AttributeValue =
	| string
| boolean
| number
| UDim
| UDim2
| BrickColor
| Color3
| Vector2
| Vector3
| CFrame
| NumberSequence
| ColorSequence
| NumberRange
| Rect
| Font

type Callback = (value: AttributeValue) -> (() -> ())?

local function defaultGuard(_value: AttributeValue)
	return true
end

local function observeAttribute(
	instance: Instance,
	name: string,
	callback: Callback,
	guard: ((value: AttributeValue) -> boolean)?
): () -> ()
	local cleanFn: (() -> ())? = nil

	local onAttrChangedConn: RBXScriptConnection
	local changedId = 0

	local valueGuard: (value: AttributeValue) -> boolean = if guard ~= nil then guard else defaultGuard

	local function OnAttributeChanged()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end

		changedId += 1
		local id = changedId

		local value = instance:GetAttribute(name) :: AttributeValue?

		if value ~= nil and valueGuard(value) then
			task.spawn(function()
				local clean = (callback :: any)(value)
				if typeof(clean) == "function" then
					if id == changedId and onAttrChangedConn.Connected then
						cleanFn = clean
					else
						task.spawn(clean)
					end
				end
			end)
		end
	end

	onAttrChangedConn = instance:GetAttributeChangedSignal(name):Connect(OnAttributeChanged)

	task.defer(function()
		if not onAttrChangedConn.Connected then
			return
		end

		OnAttributeChanged()
	end)

	return function()
		onAttrChangedConn:Disconnect()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end
	end
end

return observeAttribute