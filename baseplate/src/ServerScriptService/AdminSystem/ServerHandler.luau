local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

const GLOBAL_COMMAND_TOPIC = "AdminGlobalCommand"

local ServerHandler = {}

local config
local commands = {}
local banDataStore
local rateLimits = {}

local categoryIndex = {}
local categoryOrder = {}
local defaultCategory = "Server"

-- Fires the existing GlobalMessage banner to THIS server's clients. The cross-server dispatch path
-- calls this on every server that runs a global command, so the announcement reaches every player
-- without relying on MessagingService delivering a publish back to its own origin server.
local function broadcastLocalAnnouncement(message, duration, originUserId)
	if not message or message == "" then
		return
	end
	local adminRemote = game.ReplicatedStorage:FindFirstChild("ADMIN_REMOTE")
	if not adminRemote then
		return
	end
	adminRemote:FireAllClients("GlobalMessage", {
		Message = message,
		Duration = duration or 10,
		UserId = originUserId,
	})
end

local function buildCategoryIndex(cfg)
	categoryIndex = {}
	categoryOrder = {}
	defaultCategory = nil

	for _, category in cfg.Categories or {} do
		table.insert(categoryOrder, category.Name)
		if category.Default then
			defaultCategory = category.Name
		end
		if category.Commands then
			for _, commandName in category.Commands do
				categoryIndex[commandName] = category.Name
			end
		end
	end

	if not defaultCategory then
		defaultCategory = categoryOrder[1] or "Server"
	end
	if #categoryOrder == 0 then
		categoryOrder = { defaultCategory }
	end
end

function ServerHandler.Init(cfg, commandsFolder)
	config = cfg
	banDataStore = DataStoreService:GetDataStore(config.BanDataStoreName)

	buildCategoryIndex(config)

	for _, module in commandsFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, cmd = pcall(require, module)
			if ok and cmd and cmd.Name then
				commands[cmd.Name] = cmd
			else
				warn("[AdminSystem] Failed to load command: " .. module.Name .. " — " .. tostring(cmd))
			end
		end
	end

	local remote = game.ReplicatedStorage:WaitForChild("AdminPanel_Invoke")
	remote.OnServerInvoke = function(player, action, commandName, params)
		return ServerHandler.HandleInvoke(player, action, commandName, params)
	end

	local adminRemote = game.ReplicatedStorage:WaitForChild("ADMIN_REMOTE")

	pcall(function()
		MessagingService:SubscribeAsync("AdminGlobalMessage", function(message)
			local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, message.Data)

			if ok2 and decoded then
				adminRemote:FireAllClients("GlobalMessage", decoded)
			end
		end)
	end)

	pcall(function()
		MessagingService:SubscribeAsync(GLOBAL_COMMAND_TOPIC, function(message)
			local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, message.Data)
			if not decodeOk or type(decoded) ~= "table" then
				return
			end
			-- The origin server already ran the command locally (DispatchGlobal); skip its own echo.
			if decoded.OriginJobId == game.JobId then
				return
			end
			if type(decoded.Command) ~= "string" then
				return
			end
			local commandParams = type(decoded.Params) == "table" and decoded.Params or {}
			local ranOk = ServerHandler.RunCommandLocally(decoded.Command, commandParams, decoded.OriginUserId)
			if ranOk or decoded.AlwaysAnnounce then
				broadcastLocalAnnouncement(decoded.Announce, decoded.AnnounceDuration, decoded.OriginUserId)
			end
		end)
	end)

	Players.PlayerAdded:Connect(function(player)
		ServerHandler.OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ServerHandler.OnPlayerRemoving(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(ServerHandler.OnPlayerAdded, player)
	end
end

function ServerHandler.GetPermissionLevel(player)
	if config.BlanketEnable and RunService:IsStudio() then
		return math.huge
	end
	local override = config.UserOverrides[player.UserId]
	if override then
		return override
	end

	if config.GroupId and config.GroupId > 0 then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(config.GroupId)
		end)

		if ok and rank then
			local roleData = config.Roles[rank]
			if roleData then
				return roleData.PermissionLevel
			end
		end
	end

	return 0
end

function ServerHandler.GetCategories()
	return categoryOrder
end

function ServerHandler.GetCategoryForCommand(commandName)
	return categoryIndex[commandName] or defaultCategory
end

function ServerHandler.GetBanDataStore()
	return banDataStore
end

function ServerHandler.GetCommand(commandName)
	return commands[commandName]
end

function ServerHandler.HandleInvoke(player, action, commandName, params)
	if action == "getCommands" then
		return ServerHandler.GetCommandsForPlayer(player)
	elseif action == "getCategories" then
		return ServerHandler.GetCategories()
	elseif action == "execute" then
		return ServerHandler.ExecuteCommand(player, commandName, params)
	elseif action == "getCustomList" then
		return ServerHandler.GetCustomList(player, commandName, params)
	end

	return false, "Unknown action."
end

function ServerHandler.GetCommandsForPlayer(player)
	local level = ServerHandler.GetPermissionLevel(player)
	local result = {}

	for _, cmd in commands do
		if level >= cmd.MinPermissionLevel then
			local paramsCopy = {}
			for i, p in cmd.Parameters do
				paramsCopy[i] = {
					Name = p.Name,
					Type = p.Type,
					Required = p.Required,
					Default = p.Default,
					ListItems = p.ListItems,
				}
			end

			table.insert(result, {
				Name = cmd.Name,
				Description = cmd.Description,
				LayoutOrder = cmd.LayoutOrder,
				Category = ServerHandler.GetCategoryForCommand(cmd.Name),
				Parameters = paramsCopy,
			})
		end
	end

	table.sort(result, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	return result
end

function ServerHandler.GetCustomList(player, commandName, paramName)
	if type(commandName) ~= "string" or type(paramName) ~= "string" then
		return false, "Invalid arguments."
	end

	local cmd = commands[commandName]
	if not cmd then
		return false, "Unknown command."
	end

	local level = ServerHandler.GetPermissionLevel(player)
	if level < cmd.MinPermissionLevel then
		return false, "Insufficient permissions."
	end

	if not cmd.CustomLists or not cmd.CustomLists[paramName] then
		return false, "No custom list for parameter: " .. paramName
	end

	local ok, items = pcall(cmd.CustomLists[paramName])
	if not ok then
		warn("[AdminSystem] CustomList error (" .. commandName .. "." .. paramName .. "): " .. tostring(items))
		return false, "Failed to generate list."
	end

	return items
end

local function runCommandCore(player, cmd, params)
	local validOk, validMsg = ServerHandler.ValidateParams(cmd, params)
	if not validOk then
		return false, validMsg
	end

	for _, paramDef in cmd.Parameters do
		if params[paramDef.Name] == nil and paramDef.Default ~= nil then
			params[paramDef.Name] = paramDef.Default
		end
	end

	local customListMetadata = {}
	for _, paramDef in cmd.Parameters do
		if paramDef.Type == "CustomList" and cmd.CustomLists and cmd.CustomLists[paramDef.Name] then
			local ok, items = pcall(cmd.CustomLists[paramDef.Name])
			if ok and items then
				local selectedValue = params[paramDef.Name]
				for _, item in items do
					if item.Value == selectedValue and item.Metadata then
						customListMetadata[paramDef.Name] = item.Metadata
						break
					end
				end
			end
		end
	end

	local context = {
		Player = player,
		Config = config,
		GetBanDataStore = ServerHandler.GetBanDataStore,
		CustomListMetadata = customListMetadata,
	}

	local ok, success, message = pcall(cmd.Execute, context, params)
	if not ok then
		warn("[AdminSystem] Command error (" .. cmd.Name .. "): " .. tostring(success))
		return false, "Command errored: " .. tostring(success)
	end

	return success, message
end

function ServerHandler.ExecuteCommand(player, commandName, params)
	local rateLimited, rateLimitMsg = ServerHandler.CheckRateLimit(player)
	if rateLimited then
		return false, rateLimitMsg
	end

	local cmd = commands[commandName]
	if not cmd then
		return false, "Unknown command: " .. tostring(commandName)
	end

	local level = ServerHandler.GetPermissionLevel(player)
	if level < cmd.MinPermissionLevel then
		return false, "Insufficient permissions."
	end

	return runCommandCore(player, cmd, params)
end

-- Runs an already-authorized command with NO permission / rate-limit gate. The cross-server
-- dispatch path uses this: the origin server enforces permissions once, then every server runs the
-- command body locally. Params are still validated + defaulted because they crossed the network.
-- originUserId resolves to a live Player only on whichever server hosts that admin (nil elsewhere),
-- so any command dispatched globally must key its target off params, not context.Player.
function ServerHandler.RunCommandLocally(commandName, params, originUserId)
	local cmd = commands[commandName]
	if not cmd then
		return false, "Unknown command: " .. tostring(commandName)
	end

	local originPlayer = originUserId and Players:GetPlayerByUserId(originUserId) or nil
	return runCommandCore(originPlayer, cmd, params or {})
end

-- Generic "run on every server" entry point. A global command's Execute just forwards to this with
-- the command to run per-server + its params + the announcement banner text. This server runs the
-- command immediately and announces it locally; every other server gets the same (command, params,
-- announce) over MessagingService and the subscriber replays it via RunCommandLocally. Each server
-- only announces if its own run succeeded, so the banner shows where the effect actually landed.
function ServerHandler.DispatchGlobal(context, commandName, params, announceMessage, announceDuration, alwaysAnnounce)
	if not commands[commandName] then
		return false, "Unknown command: " .. tostring(commandName)
	end

	local originUserId = context and context.Player and context.Player.UserId or nil
	local localOk, localMessage = ServerHandler.RunCommandLocally(commandName, params, originUserId)
	if localOk or alwaysAnnounce then
		broadcastLocalAnnouncement(announceMessage, announceDuration, originUserId)
	end

	local payload = HttpService:JSONEncode({
		Command = commandName,
		Params = params or {},
		OriginUserId = originUserId,
		OriginJobId = game.JobId,
		Announce = announceMessage,
		AnnounceDuration = announceDuration,
		AlwaysAnnounce = alwaysAnnounce,
	})

	local publishOk, publishErr = pcall(function()
		MessagingService:PublishAsync(GLOBAL_COMMAND_TOPIC, payload)
	end)

	local thisServer = localOk and ("this server: " .. (localMessage or "ok")) or ("this server FAILED: " .. tostring(localMessage))
	local otherServers = publishOk and ("all other servers: broadcast '" .. commandName .. "'.") or ("broadcast FAILED: " .. tostring(publishErr))

	return (localOk or publishOk), thisServer .. string.char(10) .. otherServers
end

function ServerHandler.ValidateParams(cmd, params)
	if type(params) ~= "table" then
		return false, "Invalid parameters."
	end

	for _, paramDef in cmd.Parameters do
		local value = params[paramDef.Name]

		if paramDef.Required and value == nil and paramDef.Default == nil then
			return false, "Missing required parameter: " .. paramDef.Name
		end

		if value ~= nil then
			if paramDef.Type == "Number" then
				if type(value) ~= "number" then
					return false, paramDef.Name .. " must be a number."
				end
			elseif paramDef.Type == "String" then
				if type(value) ~= "string" then
					return false, paramDef.Name .. " must be a string."
				end
			elseif paramDef.Type == "PlayerList" then
				if type(value) ~= "number" then
					return false, paramDef.Name .. " must be a UserId (number)."
				end
			elseif paramDef.Type == "List" then
				if type(value) ~= "string" then
					return false, paramDef.Name .. " must be a string."
				end
				if paramDef.ListItems then
					local found = false
					for _, item in paramDef.ListItems do
						if item == value then
							found = true
							break
						end
					end
					if not found then
						return false, paramDef.Name .. ": invalid option '" .. tostring(value) .. "'."
					end
				end
			elseif paramDef.Type == "CustomList" then
				if type(value) ~= "string" then
					return false, paramDef.Name .. " must be a string."
				end
				if cmd.CustomLists and cmd.CustomLists[paramDef.Name] then
					local ok, items = pcall(cmd.CustomLists[paramDef.Name])
					if ok and items then
						local found = false
						for _, item in items do
							if item.Value == value then
								found = true
								break
							end
						end
						if not found then
							return false, paramDef.Name .. ": invalid option '" .. tostring(value) .. "'."
						end
					end
				end
			end
		end
	end

	return true, nil
end

function ServerHandler.CheckRateLimit(player)
	local userId = player.UserId
	local now = os.time()
	local window = 60

	if not rateLimits[userId] then
		rateLimits[userId] = {}
	end

	local timestamps = rateLimits[userId]

	local fresh = {}
	for _, t in timestamps do
		if now - t < window then
			table.insert(fresh, t)
		end
	end
	rateLimits[userId] = fresh

	if #fresh >= config.RateLimitPerMinute then
		return true, "Rate limited. Try again in a moment."
	end

	table.insert(rateLimits[userId], now)
	return false, nil
end

function ServerHandler.OnPlayerAdded(player)
	local ok, banData = pcall(function()
		return banDataStore:GetAsync("ban_" .. tostring(player.UserId))
	end)

	if ok and banData then
		if banData.Duration == -1 then
			player:Kick("You are permanently banned. Reason: " .. (banData.Reason or "No reason provided"))
			return
		end

		local banEndTime = banData.BannedAt + (banData.Duration * 60)
		if os.time() < banEndTime then
			local remaining = math.ceil((banEndTime - os.time()) / 60)
			player:Kick("You are banned for " .. remaining .. " more minute(s). Reason: " .. (banData.Reason or "No reason provided"))
			return
		else
			pcall(function()
				banDataStore:RemoveAsync("ban_" .. tostring(player.UserId))
			end)
		end
	end
end

function ServerHandler.OnPlayerRemoving(player)
	rateLimits[player.UserId] = nil
end

return ServerHandler