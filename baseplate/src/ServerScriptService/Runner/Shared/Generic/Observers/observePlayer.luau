--!strict

type Callback = (player: Player) -> (() -> ())?

local Players = game:GetService("Players")

local function observePlayer(callback: Callback): () -> ()
	local playerAddedConn: RBXScriptConnection
	local playerRemovingConn: RBXScriptConnection

	local cleanupsPerPlayer: { [Player]: (exitReason: Enum.PlayerExitReason) -> () } = {}
	local inflight: { [Player]: Enum.PlayerExitReason } = {}

	local function OnPlayerAdded(player: Player)
		if not playerAddedConn.Connected then
			return
		end

		task.spawn(function()
			inflight[player] = Enum.PlayerExitReason.Unknown
			local cleanup = (callback :: any)(player)
			if typeof(cleanup) == "function" then
				if playerAddedConn.Connected and player.Parent then
					cleanupsPerPlayer[player] = cleanup
				else
					task.spawn(cleanup, inflight[player])
				end
			end
			inflight[player] = nil
		end)
	end

	local function OnPlayerRemoving(player: Player, exitReason: Enum.PlayerExitReason)
		if inflight[player] then
			inflight[player] = exitReason
		end

		local cleanup = cleanupsPerPlayer[player]
		cleanupsPerPlayer[player] = nil
		if typeof(cleanup) == "function" then
			task.spawn(cleanup, exitReason)
		end
	end

	playerAddedConn = Players.PlayerAdded:Connect(OnPlayerAdded)
	playerRemovingConn = Players.PlayerRemoving:Connect(OnPlayerRemoving)

	task.defer(function()
		if not playerAddedConn.Connected then
			return
		end

		for _, player in Players:GetPlayers() do
			task.spawn(OnPlayerAdded, player)
		end
	end)

	return function()
		playerAddedConn:Disconnect()
		playerRemovingConn:Disconnect()

		local player = next(cleanupsPerPlayer)
		while player do
			OnPlayerRemoving(player, inflight[player])
			player = next(cleanupsPerPlayer)
		end
	end
end

return observePlayer