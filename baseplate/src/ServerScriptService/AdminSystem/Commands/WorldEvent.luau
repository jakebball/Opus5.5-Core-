local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

const STOP_VALUE = "__Stop"
const COMPONENT_NAME = "WorldEvents"

local function worldEvents()
	-- EntityStore opens with ReplicatedStorage:WaitForChild("Shared"), which only resolves once
	-- Runner has reparented it. Requiring it before that would yield inside a command Execute.
	if not ReplicatedStorage:FindFirstChild("Shared") then return nil end
	local runner = ServerScriptService:FindFirstChild("Runner")
	local entityStore = runner and runner:FindFirstChild("EntityStore")
	if not entityStore then return nil end

	local loaded, store = pcall(require, entityStore)
	if not loaded then return nil end

	return store.findComponent(workspace, COMPONENT_NAME)
end

local function definitions()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local getConfig = shared and shared:FindFirstChild("getConfig")
	if not getConfig then return {} end

	local loaded, config = pcall(function()
		return require(getConfig)()
	end)

	if not loaded or not config.WorldEvents then return {} end

	return config.WorldEvents.Definitions or {}
end

return {
	Name = "WorldEvent",
	Description = "Start a world event right now, ignoring the day's schedule and its concurrency cap. It runs ALONGSIDE whatever is already going and cancels the day's pending firings, so nothing further arrives on its own. An event that has nothing to act on -- a Line Fight with no two settled guests standing together in a lane -- refuses to start and tells you so rather than running as a silent no-op. Stopping is a teardown, not a resolution, so it pays no clear bonus.",
	MinPermissionLevel = 1,
	LayoutOrder = 210,

	Parameters = {
		{ Name = "Event", Type = "CustomList", Required = true },
		{ Name = "Seconds", Type = "Number", Required = false },
	},

	CustomLists = {
		Event = function()
			local available = definitions()
			local items = { { Text = "(stop everything running)", Value = STOP_VALUE } }
			local ids = {}

			for eventId in available do
				table.insert(ids, eventId)
			end

			table.sort(ids)

			for _, eventId in ids do
				local definition = available[eventId]
				local label = definition.displayName or eventId

				if definition.duration then
					label = label .. " - " .. definition.duration .. "s"
				end

				table.insert(items, { Text = label, Value = eventId })
			end

			return items
		end,
	},

	Execute = function(context, params)
		local component = worldEvents()

		if not component then
			return false, "WorldEvents is not running. Press Play first, then run this."
		end

		if params.Event == STOP_VALUE then
			local running = component:getActiveEventIds()
			component:endDay()

			if #running == 0 then
				return true, "Nothing was running. The day's pending firings are cancelled."
			end

			return true, ("Stopped %s. The day's pending firings are cancelled too."):format(table.concat(running, ", "))
		end

		local started, detail = component:forceEvent(params.Event, params.Seconds)

		if not started then
			return false, detail
		end

		if not detail then
			return true, ("Started %s. It runs until it is dealt with, or Doors closes."):format(params.Event)
		end

		return true, ("Started %s for %ds."):format(params.Event, math.floor(detail))
	end,
}
