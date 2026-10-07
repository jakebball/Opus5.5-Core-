local Players = game:GetService("Players")

local FireCycleReload = {}
FireCycleReload.__index = FireCycleReload
FireCycleReload.Tag = "FireCycleReload"

function FireCycleReload.Start()
	setmetatable(FireCycleReload, { __index = FireCycleReload.BaseClass })
	FireCycleReload.Observers.observePlayer(function(player)
		player:AddTag(FireCycleReload.Tag)
	end)
end

function FireCycleReload.new(instance)
	local self = setmetatable(FireCycleReload.BaseClass.new(instance), FireCycleReload)

	self.trove:AddPromise(
		FireCycleReload.EntityStore.promiseGetComponent(instance, "Gun"):andThen(function(gun)
			self.gun = gun
			self.trove:Add(gun.fired:Connect(function()
				self:_onFired()
			end), "Disconnect")
		end)
	)

	return self
end

function FireCycleReload:_onFired()
	if not self.gun then return end

	local weaponId = self.gun:getWeapon()
	if not weaponId then return end

	local itemConfig = FireCycleReload.getConfig().Weapons[weaponId]
	if not (itemConfig and itemConfig.ReloadOnFire) then return end

	task.defer(function()
		if not self.gun then return end
		self.gun:reload()
	end)
end

return FireCycleReload
