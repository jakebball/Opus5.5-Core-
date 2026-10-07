local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MusicPlayer = {}
MusicPlayer.__index = MusicPlayer
MusicPlayer.Tag = "MusicPlayer"

local CONFIG

local muted = false
local musicSoundGroup

local suppressors = {}
local resumeBindable = Instance.new("BindableEvent")
local changeBindable = Instance.new("BindableEvent")

local playlists = {}
local baseVolumes = {}
local currentPlaylistName = nil
local currentTrack = nil

MusicPlayer.trackAnnounced = nil

function MusicPlayer.getTrackAnnounced()
	if not MusicPlayer.trackAnnounced then
		MusicPlayer.trackAnnounced = MusicPlayer.GoodSignal.new()
	end
	return MusicPlayer.trackAnnounced
end

local function isSuppressed()
	return next(suppressors) ~= nil
end

local function ensureMusicSoundGroup()
	if musicSoundGroup and musicSoundGroup.Parent then return musicSoundGroup end
	local existing = SoundService:FindFirstChild("Music")
	if existing and existing:IsA("SoundGroup") then
		musicSoundGroup = existing
		return musicSoundGroup
	end
	musicSoundGroup = Instance.new("SoundGroup")
	musicSoundGroup.Name = "Music"
	musicSoundGroup.Volume = 1
	musicSoundGroup.Parent = SoundService
	return musicSoundGroup
end

local function shuffle(list)
	for index = #list, 2, -1 do
		local swapIndex = math.random(1, index)
		list[index], list[swapIndex] = list[swapIndex], list[index]
	end
	return list
end

local function ensurePlaylist(name)
	local existing = playlists[name]
	if existing then return existing end

	local group = ensureMusicSoundGroup()
	local tracks = {}
	local seen = {}

	local folderPath = (name ~= nil and name ~= "") and (CONFIG.Folder .. "/" .. name) or CONFIG.Folder
	for _, template in MusicPlayer.Assets.Children(folderPath) do
		if template:IsA("Sound") and template.SoundId ~= "" then
			local key = template.Name .. "|" .. template.SoundId
			if not seen[key] then
				seen[key] = true
				local track = template:Clone()
				track.Looped = false
				track.Playing = false
				track.SoundGroup = group
				track.Parent = SoundService
				baseVolumes[track] = template.Volume
				table.insert(tracks, track)
			end
		end
	end

	if #tracks == 0 and name ~= nil and name ~= "" then
		warn("[MusicPlayer] no playable Sounds in " .. CONFIG.Folder .. "/" .. name .. " — that playlist is silent")
	end

	playlists[name] = tracks
	return tracks
end

local function fadeOutAndStop(track)
	if not track then return end

	local restore = baseVolumes[track] or track.Volume
	TweenService:Create(track, TweenInfo.new(CONFIG.FadeOut), { Volume = 0 }):Play()
	task.delay(CONFIG.FadeOut, function()
		track:Stop()
		track.Volume = restore
	end)
end

local function announceTrack(track)
	if not table.find(CONFIG.Announce, currentPlaylistName) then return end

	local info = MusicPlayer.MusicCatalog.getInfo(track.SoundId)
	local title = info and info.title or track.Name
	local artist = info and info.artist or nil

	local text = artist
		and string.format(CONFIG.ToastFormat, title, artist)
		or string.format(CONFIG.ToastFormatNoArtist, title)

	MusicPlayer.getTrackAnnounced():Fire(text, title, artist)
end

local function playTrack(track)
	currentTrack = track
	announceTrack(track)
	track.TimePosition = 0
	track.Volume = 0
	track:Play()
	TweenService:Create(track, TweenInfo.new(CONFIG.FadeIn), { Volume = baseVolumes[track] or track.Volume }):Play()

	local thread = coroutine.running()
	local resumed = false
	local connections = {}
	local function wake()
		if resumed then return end
		resumed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		task.spawn(thread)
	end

	table.insert(connections, track.Ended:Connect(wake))
	table.insert(connections, track.Stopped:Connect(wake))
	table.insert(connections, changeBindable.Event:Connect(wake))
	coroutine.yield()

	if currentTrack == track then
		currentTrack = nil
	end
end

local function runMusicLoop()
	while true do
		local playlistName = currentPlaylistName
		local tracks = playlistName and ensurePlaylist(playlistName) or nil

		if not tracks or #tracks == 0 then
			changeBindable.Event:Wait()
		else
			local queue = shuffle(table.clone(tracks))
			for _, track in queue do
				if currentPlaylistName ~= playlistName then break end
				while isSuppressed() do
					resumeBindable.Event:Wait()
				end
				if currentPlaylistName ~= playlistName then break end

				playTrack(track)
			end
		end
	end
end

function MusicPlayer.setPlaylist(name)
	if name == currentPlaylistName then return end
	currentPlaylistName = name

	local outgoing = currentTrack
	currentTrack = nil
	fadeOutAndStop(outgoing)

	changeBindable:Fire()
end

function MusicPlayer.getPlaylist()
	return currentPlaylistName
end

function MusicPlayer.setMuted(value)
	muted = value == true
	local group = ensureMusicSoundGroup()
	group.Volume = muted and 0 or 1
end

function MusicPlayer.toggleMuted()
	MusicPlayer.setMuted(not muted)
	return muted
end

function MusicPlayer.isMuted()
	return muted
end

function MusicPlayer.setSuppressed(key, value)
	if value then
		if suppressors[key] then return end
		suppressors[key] = true
		if currentTrack then
			currentTrack:Stop()
		end
	else
		if not suppressors[key] then return end
		suppressors[key] = nil
		if not isSuppressed() then
			resumeBindable:Fire()
		end
	end
end

function MusicPlayer.Start()
	setmetatable(MusicPlayer, { __index = MusicPlayer.BaseClass })
	CONFIG = MusicPlayer.getConfig().Music

	if currentPlaylistName == nil then
		currentPlaylistName = CONFIG.Default
	end
	ensureMusicSoundGroup()
	task.spawn(runMusicLoop)
end

function MusicPlayer.new(instance)
	local self = setmetatable(MusicPlayer.BaseClass.new(instance), MusicPlayer)
	return self
end

function MusicPlayer:destroy()
	self.trove:Clean()
end

return MusicPlayer
