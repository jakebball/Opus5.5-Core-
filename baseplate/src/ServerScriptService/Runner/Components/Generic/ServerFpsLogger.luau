local DataStoreService = game:GetService("DataStoreService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local ServerFpsLogger = {}
ServerFpsLogger.Tag = "ServerFpsLogger"

local currentFps = 0

function ServerFpsLogger.getFps()
	return currentFps
end

const WINDOW_SECONDS = 1
const LOW_FPS_THRESHOLD = 30
const INCIDENT_DURATION = 120
const MAX_LOG_LINES = 4000
const MAX_LOG_BYTES = 2 * 1024 * 1024

const NEWLINE = string.char(10)

local dataStoresAvailable = game.PlaceId ~= 0
local incidentStore = nil

local function isDataStoreAccessError(err)
	local s = string.lower(tostring(err or ""))
	if string.find(s, "publish this place", 1, true) then return true end
	if string.find(s, "studio access", 1, true) then return true end
	if string.find(s, "api services", 1, true) then return true end
	return false
end

if not dataStoresAvailable then
	warn("[ServerFpsLogger] DataStores unavailable (place not published) — incident logging disabled")
end

local function getStore()
	if not dataStoresAvailable then return nil end
	if incidentStore then return incidentStore end

	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "ServerFpsIncidents")
	if ok then
		incidentStore = result
		return incidentStore
	end

	if isDataStoreAccessError(result) then
		dataStoresAvailable = false
		warn("[ServerFpsLogger] DataStores unavailable — disabling incident logging (" .. tostring(result) .. ")")
	else
		warn("[ServerFpsLogger] failed to acquire DataStore: " .. tostring(result))
	end
	return nil
end

local function getIncidentKey()
	if game.JobId and game.JobId ~= "" then
		return game.JobId
	end
	return "studio-" .. tostring(os.time())
end

function ServerFpsLogger.Start()
	local logBuffer = {}
	local logBytes = 0

	LogService.MessageOut:Connect(function(message, messageType)
		local typeName = (messageType and messageType.Name) or "Unknown"
		local line = "[" .. tostring(typeName) .. "] " .. tostring(message or "")
		table.insert(logBuffer, line)
		logBytes += #line + 1
		while #logBuffer > MAX_LOG_LINES or logBytes > MAX_LOG_BYTES do
			local removed = table.remove(logBuffer, 1)
			if not removed then break end
			logBytes -= #removed + 1
		end
	end)

	local frameCount = 0
	local elapsed = 0
	local lowFpsStart = nil
	local incidentKey = nil

	local function snapshotLogs()
		local parts = table.create(#logBuffer)
		for i = 1, #logBuffer do
			parts[i] = tostring(logBuffer[i] or "")
		end
		local ok, joined = pcall(table.concat, parts, NEWLINE)
		if ok then return joined end
		return tostring(joined)
	end

	local function postIncident(currentFps)
		local store = getStore()
		if not store then return end

		local key = getIncidentKey()
		local payload = {
			placeId = game.PlaceId,
			jobId = game.JobId,
			startedAt = os.time(),
			fpsAtTrigger = currentFps,
			thresholdFps = LOW_FPS_THRESHOLD,
			durationSeconds = INCIDENT_DURATION,
			logs = snapshotLogs(),
		}
		local ok, err = pcall(store.SetAsync, store, key, payload)
		if ok then
			incidentKey = key
			warn(("[ServerFpsLogger] low-FPS incident posted (%.1f fps, key=%s)"):format(currentFps, key))
		elseif isDataStoreAccessError(err) then
			dataStoresAvailable = false
			warn("[ServerFpsLogger] DataStores unavailable — disabling incident logging (" .. tostring(err) .. ")")
		else
			warn("[ServerFpsLogger] failed to write incident: " .. tostring(err))
		end
	end

	local function clearIncident()
		if not incidentKey then return end
		local store = getStore()
		if not store then
			incidentKey = nil
			return
		end

		local key = incidentKey
		incidentKey = nil
		local ok, err = pcall(store.RemoveAsync, store, key)
		if not ok then
			if isDataStoreAccessError(err) then
				dataStoresAvailable = false
				warn("[ServerFpsLogger] DataStores unavailable — disabling incident logging (" .. tostring(err) .. ")")
			else
				warn("[ServerFpsLogger] failed to clear incident: " .. tostring(err))
			end
		end
	end

	RunService.Heartbeat:Connect(function(deltaTime)
		frameCount += 1
		elapsed += deltaTime
		if elapsed < WINDOW_SECONDS then return end

		local fps = frameCount / elapsed
		currentFps = fps
		frameCount = 0
		elapsed = 0

		if fps < LOW_FPS_THRESHOLD then
			local now = os.clock()
			if not lowFpsStart then
				lowFpsStart = now
			elseif not incidentKey and now - lowFpsStart >= INCIDENT_DURATION then
				task.spawn(postIncident, fps)
			end
		else
			lowFpsStart = nil
			if incidentKey then
				task.spawn(clearIncident)
			end
		end
	end)
end

return ServerFpsLogger