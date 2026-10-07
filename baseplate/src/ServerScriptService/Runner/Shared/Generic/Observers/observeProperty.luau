--!strict

type Callback<T> = (value: T) -> (() -> ())?

local function observeProperty(instance: Instance, property: string, callback: Callback<unknown>): () -> ()
	local cleanFn: (() -> ())? = nil

	local propChangedConn: RBXScriptConnection
	local changedId = 0

	local function OnPropertyChanged()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end

		changedId += 1
		local id = changedId

		local value = (instance :: any)[property]

		task.spawn(function()
			local clean = (callback :: any)(value)
			if typeof(clean) == "function" then
				if id == changedId and propChangedConn.Connected then
					cleanFn = clean
				else
					task.spawn(clean)
				end
			end
		end)
	end

	propChangedConn = instance:GetPropertyChangedSignal(property):Connect(OnPropertyChanged)

	task.defer(function()
		if not propChangedConn.Connected then
			return
		end
		OnPropertyChanged()
	end)

	return function()
		propChangedConn:Disconnect()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end
	end
end

return observeProperty