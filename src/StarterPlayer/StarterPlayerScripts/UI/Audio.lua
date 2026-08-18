--[[
	Audio
	The mixing buses, and the music that follows you up.

	FOUR BUSES UNDER A MASTER: Music, SFX, UI, Ambient. Everything that makes a
	noise routes through one of them, and that single fact is what makes the
	rest possible -- a mute the player expects and a mobile player needs, a
	balance pass that does not mean editing forty call sites, and the ability to
	duck the music under a win sting later without touching the win sting.

	Volume is set on the GROUP, never on the sounds. A cue that sets its own
	absolute volume is a cue that has to be found and re-edited every time the
	mix changes; a cue that sets a volume relative to its bus is one you tune
	once. Sounds.lua already scales per-cue volume, so those two multiply
	cleanly: the cue says how loud it is FOR ITS KIND, the bus says how loud
	that kind is.

	THE MUSIC CROSSFADES ON ALTITUDE, using the exact curve Sky already computes
	for the lighting. Climbing to an island changes the light from midday to
	blue hour over 120 studs; running the score off the same number means the
	sound arrives with the picture rather than near it, and there is only one
	definition of "how high am I" to keep honest.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared.Sounds)
local Islands = require(Shared.Islands)

local Sky = require(script.Parent.Sky)

local player = Players.LocalPlayer

local Audio = {}

--[[
	THE GROUND MUSIC ALTERNATES, it does not loop. Two tracks taking turns, so
	the street does not become one four-minute phrase you learn by heart in a
	session. The sky is a single track because you are not up there long enough
	for repetition to set in.
]]
--[[ `gain` is per TRACK, because two songs mastered separately are never the
     same loudness and a single volume on the player cannot fix one without
     moving the other. Tune the quiet one up or the loud one down here. ]]
local GROUND_PLAYLIST = {
	{ id = "rbxassetid://1841647093", gain = 0.28 },
	{ id = "rbxassetid://1848354536", gain = 1.00 },
}
local SKY_TRACK = "rbxassetid://139997523791273"

--[[ The racing island gets its own rotation rather than the sky loop. It sits
     at 1150, far above the altitude band, so without this it would inherit the
     one track meant for the trip up and never change -- and this is a place you
     stand and play in, not fly through. Three, alternating, for the same reason
     the street has two. ]]
local ISLAND_PLAYLIST = {
	{ id = "rbxassetid://1847683499", gain = 1.00 },
	{ id = "rbxassetid://85685374675332", gain = 1.00 },
	{ id = "rbxassetid://117496769617516", gain = 1.00 },
}
local ISLAND_ID = "racing"

local BUSES = { "Music", "SFX", "UI", "Ambient" }

--[[ Defaults per bus. Music sits under everything else because it plays
     constantly and the cues have to cut through it. ]]
local LEVELS = {
	Music = 0.35,
	SFX = 1,
	UI = 0.8,
	Ambient = 0.5,
}

Audio.groups = {}

local function buildGroups()
	local master = SoundService:FindFirstChild("Master")
	if not master then
		master = Instance.new("SoundGroup")
		master.Name = "Master"
		master.Volume = 1
		master.Parent = SoundService
	end
	Audio.groups.Master = master

	for _, name in ipairs(BUSES) do
		local group = master:FindFirstChild(name)
		if not group then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Parent = master
		end
		group.Volume = LEVELS[name] or 1
		Audio.groups[name] = group
	end
end

--[[ Send a sound to a bus. Safe before the groups exist, so callers never have
     to care about init order. ]]
function Audio.route(sound, bus)
	local group = Audio.groups[bus or "SFX"]
	if group and sound then
		sound.SoundGroup = group
	end
	return sound
end

--[[ One knob per bus, 0..1, for a settings panel to drive later. ]]
function Audio.setLevel(bus, level)
	local group = Audio.groups[bus]
	if group then
		group.Volume = math.clamp(level, 0, 1)
	end
end

function Audio.mute(on)
	if Audio.groups.Master then
		Audio.groups.Master.Volume = on and 0 or 1
	end
end

function Audio.init(ctx)
	buildGroups()

	--[[
		Handed straight to the module, not via ctx. The first version wrote
		`if ctx and ctx.sounds then` -- and ctx has no `sounds` field, so the
		assignment silently never ran and every cue played unrouted. Nothing
		errored and the buses existed, which is exactly the shape of bug that
		survives a look at the Explorer.
	]]
	Sounds.router = Audio.route

	--[[
		Both sides play continuously and only their VOLUMES move. Starting a
		track at the transition would restart it from bar one on every crossing,
		and a jetpack makes crossing 70 studs trivially repeatable.
	]]
	local function makeTrack(name)
		local sound = Instance.new("Sound")
		sound.Name = "music_" .. name
		sound.Volume = 0
		sound.SoundGroup = Audio.groups.Music
		sound.Parent = SoundService
		return sound
	end

	local ground = makeTrack("ground")
	local sky = makeTrack("sky")
	local island = makeTrack("island")

	sky.SoundId = SKY_TRACK
	sky.Looped = true
	sky:Play()

	--[[ Alternate rather than loop: when one finishes, the other starts. Looped
	     would have to be false for Ended to fire at all, which is why the
	     rotation lives here rather than in a property. ]]
	local nextIndex, groundGain = 0, 1
	local function advance()
		nextIndex = nextIndex % #GROUND_PLAYLIST + 1
		local track = GROUND_PLAYLIST[nextIndex]
		ground.SoundId = track.id
		groundGain = track.gain or 1
		ground:Play()
	end
	ground.Looped = false
	ground.Ended:Connect(advance)
	advance()

	local islandIndex, islandGain = 0, 1
	local function advanceIsland()
		islandIndex = islandIndex % #ISLAND_PLAYLIST + 1
		local track = ISLAND_PLAYLIST[islandIndex]
		island.SoundId = track.id
		islandGain = track.gain or 1
		island:Play()
	end
	island.Looped = false
	island.Ended:Connect(advanceIsland)
	advanceIsland()

	--[[
		Three beds, one fader.

		Standing on the racing island swaps the sky track out for the island
		rotation. Eased rather than switched, because the boundary is a place you
		can walk back and forth across -- a hard cut would slam the music every
		time you wandered near the rim.

		Everything keeps PLAYING throughout and only the volumes move, the same
		rule the ground and sky beds already follow: restarting a track at the
		boundary would begin it from bar one every time you crossed.
	]]
	local onIsland = 0
	RunService.Heartbeat:Connect(function(dt)
		local t = Sky.blend()

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local here = root and Islands.at(root.Position)
		local target = (here and here.id == ISLAND_ID) and 1 or 0
		onIsland += (target - onIsland) * math.min(dt * 1.6, 1)

		ground.Volume = (1 - t) * groundGain * (1 - onIsland)
		sky.Volume = t * (1 - onIsland)
		island.Volume = onIsland * islandGain
	end)

	return Audio
end

return Audio
