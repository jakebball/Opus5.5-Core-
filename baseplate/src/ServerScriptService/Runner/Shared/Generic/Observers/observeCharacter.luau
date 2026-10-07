--!strict

local observePlayer = require(script.Parent.observePlayer)

type Callback = (player: Player, character: Model) -> (() -> ())?

local function observeCharacter(callback: Callback, allowedPlayers: { Player }?): () -> ()
	return observePlayer(function(player)
		if allowedPlayers ~= nil and not table.find(allowedPlayers, player) then
			return nil
		end

		local cleanupFn: (() -> ())? = nil

		local characterAddedConn: RBXScriptConnection

		local function OnCharacterAdded(character: Model)
			local currentCharCleanup: (() -> ())? = nil

			task.defer(function()
				local cleanup = (callback :: any)(player, character)
				if typeof(cleanup) == "function" then
					if characterAddedConn.Connected and character.Parent then
						currentCharCleanup = cleanup
						cleanupFn = cleanup
					else
						task.spawn(cleanup)
					end
				end
			end)

			local ancestryChangedConn: RBXScriptConnection
			ancestryChangedConn = character.AncestryChanged:Connect(function(_, newParent)
				if newParent == nil and ancestryChangedConn.Connected then
					ancestryChangedConn:Disconnect()
					if currentCharCleanup ~= nil then
						task.spawn(currentCharCleanup)
						if cleanupFn == currentCharCleanup then
							cleanupFn = nil
						end
						currentCharCleanup = nil
					end
				end
			end)
		end

		characterAddedConn = player.CharacterAdded:Connect(OnCharacterAdded)

		task.defer(function()
			if player.Character and characterAddedConn.Connected then
				task.spawn(OnCharacterAdded, player.Character)
			end
		end)

		return function()
			characterAddedConn:Disconnect()
			if cleanupFn ~= nil then
				task.spawn(cleanupFn)
				cleanupFn = nil
			end
		end
	end)
end

return observeCharacter