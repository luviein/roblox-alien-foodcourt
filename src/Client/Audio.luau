--!strict
-- Sound effects and the background playlist.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundDefs = require(Shared.SoundDefs)

local Settings = require(script.Parent.Settings)

local Audio = {}

local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local musicPlayer: Sound
local trackIndex = 0
local lastVolumeBlip = 0

-- Volume is written onto each Sound directly rather than relying on the
-- SoundGroup to attenuate it. The group is still there for routing, but a
-- slider that visibly moves and changes nothing audible is worse than no
-- slider, and this removes any dependence on how group volume composes.
local function musicVolume(): number
	return Settings.values.musicVolume * SoundDefs.MusicGain
end

-- --------------------------------------------------------------- helpers ---

local function assetUrl(id: number): string
	return "rbxassetid://" .. tostring(id)
end

-- ------------------------------------------------------------------ music --

-- Walks the playlist until something actually loads.
--
-- Roblox gates long-form audio: clips over roughly six seconds can only be
-- played by the account that uploaded them, unless Roblox published the asset
-- itself. Short effects have no such restriction. So a soundtrack silently
-- refusing to play while every SFX works is the expected symptom of borrowed
-- music, not a bug -- and it deserves a warning that says so rather than
-- silence you have to guess at.
local function playNextTrack()
	local tracks = SoundDefs.Music
	if #tracks == 0 or not musicPlayer then
		return
	end

	for _ = 1, #tracks do
		trackIndex += 1
		if trackIndex > #tracks then
			trackIndex = 1
		end

		local id = tracks[trackIndex]
		musicPlayer.SoundId = assetUrl(id)

		pcall(function()
			ContentProvider:PreloadAsync({ musicPlayer })
		end)

		-- A track that failed to load reports no length.
		if musicPlayer.TimeLength > 0 then
			musicPlayer.Volume = musicVolume()
			musicPlayer:Play()
			return
		end

		warn(("[AlienFoodCourt] music track %d would not load. Audio longer than "
			.. "~6s can only be played by the account that uploaded it, unless "
			.. "Roblox published it."):format(id))
	end

	warn("[AlienFoodCourt] no usable music tracks -- running silent")
end

function Audio.startMusic()
	if not musicPlayer or #SoundDefs.Music == 0 then
		return
	end
	if musicPlayer.IsPlaying then
		return
	end
	trackIndex = math.random(0, #SoundDefs.Music - 1)  -- vary which track opens

	-- PreloadAsync yields, so keep it off whatever called us.
	task.spawn(playNextTrack)
end

function Audio.stopMusic()
	if musicPlayer then
		musicPlayer:Stop()
	end
end

-- -------------------------------------------------------------------- sfx --

-- Fire-and-forget. An id of 0 means "not sourced yet" and is skipped, so a
-- half-filled SoundDefs never errors.
function Audio.play(name: string)
	local def = SoundDefs.Sfx[name]
	if not def or def.id == 0 then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = assetUrl(def.id)
	sound.Volume = def.volume * Settings.values.sfxVolume
	sound.SoundGroup = sfxGroup

	if def.pitchJitter > 0 then
		sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * def.pitchJitter
	end

	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	-- Backstop: a sound that never loads never fires Ended.
	Debris:AddItem(sound, 10)
end

-- ------------------------------------------------------------------- init --

function Audio.init()
	local existing = SoundService:FindFirstChild("AFC_Sfx")
	if existing then
		existing:Destroy()
	end
	existing = SoundService:FindFirstChild("AFC_Music")
	if existing then
		existing:Destroy()
	end

	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "AFC_Sfx"
	sfxGroup.Volume = 1
	sfxGroup.Parent = SoundService

	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "AFC_Music"
	musicGroup.Volume = 1
	musicGroup.Parent = SoundService

	musicPlayer = Instance.new("Sound")
	musicPlayer.Name = "AFC_MusicPlayer"
	musicPlayer.Looped = false          -- advanced manually, to cycle the list
	musicPlayer.Volume = musicVolume()
	musicPlayer.SoundGroup = musicGroup
	musicPlayer.Parent = SoundService
	musicPlayer.Ended:Connect(function()
		task.spawn(playNextTrack)
	end)

	Settings.changed.Event:Connect(function(key: string, value: any)
		if key == "sfxVolume" then
			-- Live SFX are one-shots and already gone; the next one picks up
			-- the new value when it is created.
			-- Audible feedback while adjusting, throttled: dragging the slider
			-- fires this many times a second otherwise.
			if os.clock() - lastVolumeBlip > 0.12 then
				lastVolumeBlip = os.clock()
				Audio.play("click")
			end
		elseif key == "musicVolume" then
			musicPlayer.Volume = musicVolume()
		end
	end)
end

return Audio
