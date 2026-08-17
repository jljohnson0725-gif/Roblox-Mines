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

--[[
	HOW EACH TIER SOUNDS.

	Two rules, and they pull against each other on purpose. Pitch goes DOWN as
	rarity climbs -- lower reads as heavier, and a Secret announcing itself an
	octave above a Common would sound like a smaller event, not a bigger one.
	The ARPEGGIO on top climbs instead, and gets longer, so the big finds take
	real time to finish speaking. A Common is one note; a Secret is seven and
	you wait for them.

	Common and Uncommon used to be identical -- both level 0, both the same
	cue -- so the most frequent outcome in the game and the second most
	frequent were indistinguishable. Uncommon is the same cue a little brighter
	now, which is the smallest difference that still registers.

	`cue` is the seam for real audio. Swap the id in Sounds.Library and every
	tier inherits it, still pitched and stacked by these numbers.
]]
local STINGS = {
	Common = { cue = "tileDrop", speed = 1.00, volume = 0.85 },
	Uncommon = { cue = "tileDrop", speed = 1.18, volume = 1.00 },
	Rare = { cue = "stinger", speed = 0.95, volume = 1.00,
		arp = { count = 3, from = 0, gap = 0.07 } },
	Epic = { cue = "stinger", speed = 0.78, volume = 1.05,
		arp = { count = 4, from = 0, gap = 0.075 } },
	Legendary = { cue = "stinger", speed = 0.62, volume = 1.10,
		arp = { count = 5, from = -2, gap = 0.08 } },
	Mythic = { cue = "stinger", speed = 0.50, volume = 1.15,
		arp = { count = 6, from = -4, gap = 0.085 } },
	Secret = { cue = "stinger", speed = 0.42, volume = 1.20,
		arp = { count = 7, from = -5, gap = 0.09 } },
}

--[[
	Play the find. One place, so the three call sites that announce a drop
	cannot drift into announcing it three different ways -- which they already
	had begun to, with Fx branching on spec.level and picking cues itself.
]]
function Sounds.sting(tierName, scale)
	local sting = STINGS[tierName] or STINGS.Common
	--[[ `scale` is for someone ELSE'S find. A server-wide announcement of a
	     Mythic should read as distant good news, not as your own. ]]
	scale = scale or 1
	Sounds.play(sting.cue, sting.speed, sting.volume * scale)
	-- the flourish is skipped when it is not your find; the headline is enough
	if sting.arp and scale >= 1 then
		Sounds.arpeggio(sting.cue, sting.arp.count, sting.arp.from, sting.arp.gap)
	end
	return sting
end

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

	--[[ Routed to a mixing bus when the client has set one up. Absent -- on the
	     server, or before Audio.init -- this is a no-op and the cue behaves
	     exactly as it always did. ]]
	if Sounds.router then
		Sounds.router(sound, def.bus or "SFX")
	end

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
