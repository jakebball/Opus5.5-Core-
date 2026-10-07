local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Funnels = {}
Funnels.__index = Funnels
Funnels.Tag = "Funnels"

const VERSION_KEY = Enum.AnalyticsCustomFieldKeys.CustomField01.Name

local definitions = {}

function Funnels.Start()
	setmetatable(Funnels, { __index = Funnels.BaseClass })
	Funnels.Observers.observePlayer(function(player)
		player:AddTag(Funnels.Tag)
	end)
end

function Funnels.registerFunnel(funnelName, definition)
	if type(funnelName) ~= "string" or funnelName == "" then
		warn("[Funnels] registerFunnel called with non-string name: " .. tostring(funnelName))
		return
	end
	if type(definition) ~= "table" then
		warn(string.format("[Funnels] '%s' definition must be a table", funnelName))
		return
	end
	local version = definition.version
	if type(version) ~= "string" or version == "" then
		local analyticsConfig = Funnels.getConfig and Funnels.getConfig().Analytics
		version = analyticsConfig and analyticsConfig.FunnelVersion
	end
	if type(version) ~= "string" or version == "" then
		warn(string.format("[Funnels] '%s' has no version and getConfig.Analytics.FunnelVersion is unset", funnelName))
		return
	end
	if type(definition.steps) ~= "table" or #definition.steps == 0 then
		warn(string.format("[Funnels] '%s' missing non-empty `steps` array", funnelName))
		return
	end

	-- Pre-compute the stepName → ordinal map so logStep is O(1) per fire.
	local stepOrdinal = {}
	for ordinal, stepName in definition.steps do
		if type(stepName) ~= "string" or stepName == "" then
			warn(string.format("[Funnels] '%s' steps[%d] is not a string", funnelName, ordinal))
			return
		end
		if stepOrdinal[stepName] then
			warn(string.format("[Funnels] '%s' has duplicate step name '%s' — keeping ordinal %d, ignoring %d",
				funnelName, stepName, stepOrdinal[stepName], ordinal))
		else
			stepOrdinal[stepName] = ordinal
		end
	end

	definitions[funnelName] = {
		version = version,
		steps = definition.steps,
		stepOrdinal = stepOrdinal,
	}
end

function Funnels.getFunnel(funnelName)
	return definitions[funnelName]
end

function Funnels.new(instance)
	local self = setmetatable(Funnels.BaseClass.new(instance), Funnels)

	self.sessions = {}

	return self
end

function Funnels:newSession(funnelName)
	local sid = HttpService:GenerateGUID(false)
	self.sessions[funnelName] = sid
	return sid
end

function Funnels:_sessionFor(funnelName)
	local sid = self.sessions[funnelName]
	if not sid then
		sid = HttpService:GenerateGUID(false)
		self.sessions[funnelName] = sid
	end
	return sid
end

local function buildCustomFields(version, extraFields)
	local out = extraFields and table.clone(extraFields) or {}
	out[VERSION_KEY] = version
	return out
end

function Funnels:logStep(funnelName, stepName, extraFields)
	local def = definitions[funnelName]
	if not def then
		warn(string.format("[Funnels] %s: unknown funnel '%s' — register it via Funnels.registerFunnel before logging",
			self.instance.Name, tostring(funnelName)))
		return
	end
	local ordinal = def.stepOrdinal[stepName]
	if not ordinal then
		warn(string.format("[Funnels] %s: unknown step '%s' in funnel '%s'",
			self.instance.Name, tostring(stepName), funnelName))
		return
	end

	local sessionId = self:_sessionFor(funnelName)
	local customFields = buildCustomFields(def.version, extraFields)

	pcall(
		AnalyticsService.LogFunnelStepEvent,
		AnalyticsService,
		self.instance,
		funnelName,
		sessionId,
		ordinal,
		stepName,
		customFields
	)
end

function Funnels:logOnboardingStep(funnelName, stepName, extraFields)
	local def = definitions[funnelName]
	if not def then
		warn(string.format("[Funnels] %s: unknown funnel '%s' for onboarding step — register it first",
			self.instance.Name, tostring(funnelName)))
		return
	end
	local ordinal = def.stepOrdinal[stepName]
	if not ordinal then
		warn(string.format("[Funnels] %s: unknown onboarding step '%s' in funnel '%s'",
			self.instance.Name, tostring(stepName), funnelName))
		return
	end

	local customFields = buildCustomFields(def.version, extraFields)

	pcall(
		AnalyticsService.LogOnboardingFunnelStepEvent,
		AnalyticsService,
		self.instance,
		ordinal,
		stepName,
		customFields
	)
end

function Funnels:destroy()
	self.sessions = nil
	self.trove:Clean()
end

return Funnels