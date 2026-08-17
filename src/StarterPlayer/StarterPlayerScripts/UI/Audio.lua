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

local Sky = require(script.Parent.Sky)

local Audio = {}

--[[
	NOT FILLED IN. These are the seams for real audio, left empty on purpose --
	an invented asset id fails silently at runtime and looks like a bug in the
	mixer rather than a missing file. Paste ids from Studio's Toolbox > Audio,
	which is Roblox's own licensed library; anything uploaded from elsewhere is
	private to its uploader since the 2022 audio privacy change and will simply
	not play for anyone else.
]]
local TRACKS = {
	ground = "", -- the street: bright, busy
	sky = "", -- the islands: colder, sparser, fewer instruments
}

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

	--[[ Sounds.lua parents its cues to SoundService and has no idea buses
	     exist. Rather than edit forty call sites, hand it a router it can use
	     if one is present -- absent, it behaves exactly as before. ]]
	if ctx and ctx.sounds then
		ctx.sounds.router = Audio.route
	end

	local tracks = {}
	for key, id in pairs(TRACKS) do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "music_" .. key
			sound.SoundId = id
			sound.Looped = true
			sound.Volume = 0
			sound.SoundGroup = Audio.groups.Music
			sound.Parent = SoundService
			sound:Play()
			tracks[key] = sound
		end
	end

	--[[
		Both tracks run the whole time and only their volumes move. Starting a
		track at the moment of the transition would mean it begins from its
		first bar every time you cross 70 studs, which turns a crossfade into a
		restart -- and crossing that line repeatedly, which a jetpack makes
		trivially easy, would retrigger it endlessly.
	]]
	if not (tracks.ground or tracks.sky) then
		return Audio -- nothing to mix yet; the buses still work
	end

	RunService.Heartbeat:Connect(function()
		local t = Sky.blend()
		if tracks.ground then
			tracks.ground.Volume = 1 - t
		end
		if tracks.sky then
			tracks.sky.Volume = t
		end
	end)

	return Audio
end

return Audio
