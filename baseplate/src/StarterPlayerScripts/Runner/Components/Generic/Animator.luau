local Animator = {}
Animator.__index = Animator
Animator.Tag = "Animator"

function Animator.Start()
	setmetatable(Animator, { __index = Animator.BaseClass })
end
function Animator.new(instance)
	local self = setmetatable({}, Animator)
	self.trove = Animator.Trove.new()
	self.instance = instance
	self.tracks = {}
	self.animations = {}

	local humanoid = instance:FindFirstChildWhichIsA("Humanoid")
	local animController = instance:FindFirstChildWhichIsA("AnimationController")
	local container = humanoid or animController

	if not container then
		warn("[Animator] No Humanoid or AnimationController on: " .. instance.Name)
		return self
	end

	local animator = container:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = container
		self.trove:Add(animator)
	end
	self.animator = animator

	return self
end

function Animator:_loadTrack(name, animInstance)
	if not self.animator then return nil end
	local track = self.animator:LoadAnimation(animInstance)
	self.tracks[name] = track
	self.animations[name] = animInstance
	return track
end

function Animator:registerAnimation(name, animationId)
	if not self.animator then return nil end
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = animationId
	anim.Parent = self.instance
	self.trove:Add(anim)
	return self:_loadTrack(name, anim)
end

function Animator:unregisterAnimation(name, fadeTime)
	local track = self.tracks[name]
	if track then
		track:Stop(fadeTime or 0)
		track:Destroy()
		self.tracks[name] = nil
	end

	local animation = self.animations[name]
	if animation then
		self.trove:Remove(animation)
		self.animations[name] = nil
	end
end

function Animator:playAnimation(name, fadeTime, looped, priority)
	local track = self.tracks[name]
	if not track then
		warn("[Animator] No track: " .. name .. " on " .. self.instance.Name)
		return nil
	end
	if looped ~= nil then
		track.Looped = looped
	end
	if priority then
		track.Priority = priority
	end

	track:Play(fadeTime or 0.1)
	return track
end

function Animator:stopAnimation(name, fadeTime)
	local track = self.tracks[name]
	if track then
		track:Stop(fadeTime or 0.1)
	end
end

function Animator:stopAllAnimations(fadeTime)
	for _, track in self.tracks do
		track:Stop(fadeTime or 0.1)
	end
end

function Animator:getTrack(name)
	return self.tracks[name]
end

function Animator:isPlaying(name)
	local track = self.tracks[name]
	return track ~= nil and track.IsPlaying
end

function Animator:adjustSpeed(name, speed)
	local track = self.tracks[name]
	if track then
		track:AdjustSpeed(speed)
	end
end

function Animator:destroy()
	self.trove:Clean()
end

return Animator