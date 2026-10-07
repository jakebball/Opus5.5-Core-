local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

const KIT_COMPONENT = "GateKit"
const EQUIP_COMPONENT = "WeaponEquip"

local function entityStore()
	-- EntityStore opens with ReplicatedStorage:WaitForChild("Shared"), which only resolves once
	-- Runner has reparented it. Requiring it before that would yield inside a command Execute.
	if not ReplicatedStorage:FindFirstChild("Shared") then return nil end
	local runner = ServerScriptService:FindFirstChild("Runner")
	local module = runner and runner:FindFirstChild("EntityStore")
	if not module then return nil end

	local loaded, store = pcall(require, module)
	if not loaded then return nil end

	return store
end

local function definitions()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local getConfig = shared and shared:FindFirstChild("getConfig")
	if not getConfig then return {} end

	local loaded, config = pcall(function()
		return require(getConfig)()
	end)

	if not loaded or not config.Items then return {} end

	return config.Items.Definitions or {}
end

return {
	Name = "GiveWeapon",
	Description = "Grant a player any weapon and put it straight in their hands. Weapons are not in the starting kit -- they are meant to be bought -- so this is the only way to get one today. A player owns exactly ONE weapon at a time: granting a new one retires the old one and takes its hotbar slot. The rest of the kit -- Scanner, Cuffs, Water Bucket -- is untouched. Granting a weapon they already own just re-equips it.",
	MinPermissionLevel = 1,
	LayoutOrder = 220,

	Parameters = {
		{ Name = "Player", Type = "PlayerList", Required = true },
		{ Name = "Weapon", Type = "CustomList", Required = true },
	},

	CustomLists = {
		-- Built from config at call time, so a new weapon in getConfig/Items appears in the panel
		-- with no change to this command. Sorted by price, since that is the order a shop would
		-- show them in.
		Weapon = function()
			local available = definitions()
			local ids = {}

			for itemId, definition in available do
				if definition.weaponId then
					table.insert(ids, itemId)
				end
			end

			table.sort(ids, function(left, right)
				local leftCost = available[left].cost or 0
				local rightCost = available[right].cost or 0
				if leftCost ~= rightCost then return leftCost < rightCost end
				return left < right
			end)

			local items = {}
			for _, itemId in ids do
				local definition = available[itemId]
				local label = definition.name or itemId
				if definition.cost then
					label = label .. " - $" .. definition.cost
				else
					label = label .. " - starting kit"
				end
				table.insert(items, { Text = label, Value = itemId })
			end

			return items
		end,
	},

	Execute = function(context, params)
		local targetPlayer = params.Player and Players:GetPlayerByUserId(params.Player)
		if not targetPlayer then
			return false, "Player not found in server."
		end

		local definition = definitions()[params.Weapon]
		if not definition or not definition.weaponId then
			return false, "'" .. tostring(params.Weapon) .. "' is not a weapon."
		end

		local store = entityStore()
		if not store then
			return false, "The Runner is not up. Press Play first, then run this."
		end

		local kit = store.findComponent(targetPlayer, KIT_COMPONENT)
		if not kit then
			return false, targetPlayer.Name .. " has no " .. KIT_COMPONENT .. " yet — their inventory has not loaded."
		end

		local alreadyOwned = kit:getIssuedGuid(params.Weapon) ~= nil
		local guid, retired = kit:grant(params.Weapon)

		if not guid then
			return false, targetPlayer.Name .. "'s hotbar is full (8 slots). Nothing was granted."
		end

		local replaced = ""
		if retired and #retired > 0 then
			local names = {}
			for _, retiredId in retired do
				local retiredDefinition = definitions()[retiredId]
				table.insert(names, (retiredDefinition and retiredDefinition.name) or retiredId)
			end
			replaced = " Replaced their " .. table.concat(names, " and ") .. "."
		end

		local equip = store.findComponent(targetPlayer, EQUIP_COMPONENT)
		if not equip then
			return true, ("Gave %s the %s, but they have no %s so it could not be equipped.")
				:format(targetPlayer.Name, definition.name or params.Weapon, EQUIP_COMPONENT)
		end

		equip:forceEquip(params.Weapon)

		local verb = if alreadyOwned then "Re-equipped" else "Gave"
		return true, ("%s %s the %s. It is in their hands now.%s"):format(
			verb, targetPlayer.Name, definition.name or params.Weapon, replaced)
	end,
}
