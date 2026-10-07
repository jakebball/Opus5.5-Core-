local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local ChamberedRound = {}
ChamberedRound.__index = ChamberedRound
ChamberedRound.Tag = "ChamberedRound"

const DEFAULT_CLIP = "Shoot"
const DEFAULT_MARKER = "RocketAppears"

function ChamberedRound.Start()
	setmetatable(ChamberedRound, { __index = ChamberedRound.BaseClass })
end

function ChamberedRound.new(instance, weaponId)
	local self = setmetatable(ChamberedRound.BaseClass.new(instance), ChamberedRound)

	local itemConfig = ChamberedRound.getConfig().Weapons[weaponId]
	self.round = ChamberedRound.RoundVisibility.target(instance, itemConfig)
	if not self.round then return self end

	self.clipName = (itemConfig and itemConfig.ChamberedRoundClip) or DEFAULT_CLIP
	self.markerName = (itemConfig and itemConfig.ChamberedRoundMarker) or DEFAULT_MARKER

	self.trove:AddPromise(
		ChamberedRound.EntityStore.promiseGetComponent(localPlayer, "FPSViewmodel"):andThen(function(viewmodel)
			self.viewmodel = viewmodel
			return ChamberedRound.EntityStore.promiseGetComponent(localPlayer, "Gun")
		end):andThen(function(gun)
			self.trove:Add(gun.fired:Connect(function()
				self:setVisible(false)
				self:_armMarker()
			end), "Disconnect")
		end)
	)

	return self
end

function ChamberedRound:_armMarker()
	if self.armed or not self.viewmodel then return end

	local track = self.viewmodel:getTrack(self.clipName)
	if not track then return end
	self.armed = true

	self.trove:Add(track:GetMarkerReachedSignal(self.markerName):Connect(function()
		self:setVisible(true)
	end), "Disconnect")

	self.trove:Add(track.Stopped:Connect(function()
		self:setVisible(true)
	end), "Disconnect")
end

function ChamberedRound:setVisible(visible)
	if not self.round then return end
	ChamberedRound.RoundVisibility.set(self.round, visible)
end

return ChamberedRound
