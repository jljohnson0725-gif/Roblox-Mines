--[[
	Sounds
	Every audio cue in the game, plus the rarity-scaled spectacle table.

	── About these IDs ─────────────────────────────────────────────────────────
	These are Roblox's BUILT-IN client sounds (`rbxasset://`, not `rbxassetid://`).
	They ship with the player, need no upload, and can't be moderated out from
	under you -- so the game has audio the moment you press Play. They are also a
	small and fairly plain palette.

	Replace them with real SFX from the Creator Store when you have them: change
	the `id` on a line below and nothing else in the codebase needs to know.
	The cues most worth replacing first are `bust`, `cashout`, and `stinger` --
	those carry the emotional beats.

	── The pitch trick ─────────────────────────────────────────────────────────
	`tileReveal` is pitched UP one semitone per safe tile, so a run plays as a
	rising scale and the tension climbs on its own. That's most of the audio
	design right there, and it works with whatever sample you swap in.
]]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sounds = {}

-- one semitone in playback-speed terms
Sounds.SEMITONE = 2 ^ (1 / 12)

Sounds.Library = {
	-- mines
	tileReveal = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.40, speed = 1.00 },
	tileDrop = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.75, speed = 0.70 },
	bust = { id = "rbxasset://sounds/bass.wav", volume = 1.00, speed = 0.55 },
	cashout = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.55, speed = 1.30 },
	betPlace = { id = "rbxasset://sounds/switch.wav", volume = 0.50, speed = 1.00 },

	-- the big-drop stinger, pitched down as rarity climbs (see Spectacle)
	stinger = { id = "rbxasset://sounds/bass.wav", volume = 1.00, speed = 1.00 },

	-- ui
	uiClick = { id = "rbxasset://sounds/switch3.wav", volume = 0.30, speed = 1.00 },
	uiOpen = { id = "rbxasset://sounds/switch.wav", volume = 0.35, speed = 1.25 },
	uiClose = { id = "rbxasset://sounds/switch.wav", volume = 0.35, speed = 0.85 },
	uiDenied = { id = "rbxasset://sounds/switch.wav", volume = 0.40, speed = 0.50 },

	-- plot
	place = { id = "rbxasset://sounds/switch3.wav", volume = 0.60, speed = 0.80 },
	store = { id = "rbxasset://sounds/switch3.wav", volume = 0.45, speed = 1.15 },
	unlock = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.80, speed = 0.60 },
}

--[[
	How loud a drop gets to be, by tier.

	`level` 0 means "no spectacle" -- Commons happen constantly and celebrating
	them would make the celebration meaningless. Everything scales from Rare up,
	and Mythic/Secret announce to the whole server, because the flex in front of
	other people IS the reward at that rarity.
]]
Sounds.Spectacle = {
	Common = { level = 0 },
	Uncommon = { level = 0 },
	Rare = {
		level = 1,
		shake = 0.20,
		flash = 0.10,
		confetti = 14,
		stingerSpeed = 0.95,
		hold = 0.9,
	},
	Epic = {
		level = 2,
		shake = 0.55,
		flash = 0.20,
		confetti = 32,
		stingerSpeed = 0.78,
		hold = 1.4,
	},
	Legendary = {
		level = 3,
		shake = 1.05,
		flash = 0.32,
		confetti = 58,
		stingerSpeed = 0.62,
		hold = 2.0,
		bloom = true,
	},
	Mythic = {
		level = 4,
		shake = 1.70,
		flash = 0.48,
		confetti = 95,
		stingerSpeed = 0.48,
		hold = 2.8,
		bloom = true,
		saturate = true,
		announce = true,
	},
	Secret = {
		level = 5,
		shake = 2.50,
		flash = 0.70,
		confetti = 150,
		stingerSpeed = 0.36,
		hold = 3.6,
		bloom = true,
		saturate = true,
		announce = true,
		vignette = true,
	},
}

function Sounds.spectacleFor(tierName)
	return Sounds.Spectacle[tierName] or Sounds.Spectacle.Common
end

--[[
	Fire and forget, 2D (parented to SoundService so it isn't positional).
	Server calls are a no-op rather than an error -- shared module, and it's
	easier to let callers not care which side they're on.
]]
function Sounds.play(name, speedMultiplier, volumeMultiplier)
	if not RunService:IsClient() then
		return nil
	end

	local def = Sounds.Library[name]
	if not def then
		warn(string.format("[Sounds] unknown cue %q", tostring(name)))
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "sfx_" .. name
	sound.SoundId = def.id
	sound.Volume = def.volume * (volumeMultiplier or 1)
	sound.PlaybackSpeed = def.speed * (speedMultiplier or 1)
	sound.Parent = SoundService

	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Backstop: a sound that never loads never fires Ended.
	Debris:AddItem(sound, 10)

	return sound
end

--[[ Ascending run of notes -- used for the cash-out flourish. ]]
function Sounds.arpeggio(name, count, startSemitone, gap)
	if not RunService:IsClient() then
		return
	end
	task.spawn(function()
		for i = 0, (count or 3) - 1 do
			Sounds.play(name, Sounds.SEMITONE ^ ((startSemitone or 0) + i * 4))
			task.wait(gap or 0.07)
		end
	end)
end

return Sounds
