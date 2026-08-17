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
	-- the gray find doubles as the safe-tile reveal, which is deliberate: an
	-- ordinary uncover and an ordinary find are the same size of event.
	tileReveal = { id = "rbxassetid://140231021022259", volume = 0.40, speed = 1.00 },
	tileClick = { id = "rbxassetid://122835655736085", volume = 0.45, speed = 1.00 },
	tileDrop = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.75, speed = 0.70 },
	--[[ Speed back to 1.00. The old 0.55 existed to drag a generic bass hit
	     down into something that felt like a loss; a real file is already in
	     the key it was written in and pitching it is only damage. ]]
	bust = { id = "rbxassetid://132442290182354", volume = 1.00, speed = 1.00 },
	cashout = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.55, speed = 1.30 },
	betPlace = { id = "rbxasset://sounds/switch.wav", volume = 0.50, speed = 1.00 },

	-- the big-drop stinger, pitched down as rarity climbs (see Spectacle)
	stinger = { id = "rbxasset://sounds/bass.wav", volume = 1.00, speed = 1.00 },

	-- ui
	uiClick = { id = "rbxassetid://102702078778790", volume = 0.40, speed = 1.00, bus = "UI" },
	uiOpen = { id = "rbxassetid://102702078778790", volume = 0.38, speed = 1.10, bus = "UI" },
	uiClose = { id = "rbxassetid://102702078778790", volume = 0.32, speed = 0.90, bus = "UI" },
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
	ONE SOUND PER TIER, not one sound pitched seven ways.

	The first version shifted a single stinger down and stacked an arpeggio on
	it, which was the right shape when the only audio available was a built-in
	blip. With real assets per rarity that machinery is worse than useless --
	it would be pitching a finished sound away from the key it was written in.
	Colour names map to the tiers they are named for: gray Common through to
	Secret.

	MYTHIC IS TWO PARTS, a wind-up and a finish, so `after` chains a second cue
	once the first has actually ended rather than after a guessed delay. A fixed
	wait would drift the moment either file is re-cut, and the seam between a
	wind-up and its payoff is exactly where drift is audible.
]]
local STINGS = {
	Common = { id = "rbxassetid://140231021022259", volume = 0.85 },
	Uncommon = { id = "rbxassetid://117243786893013", volume = 0.95 },
	Rare = { id = "rbxassetid://138190748214493", volume = 1.00 },
	Epic = { id = "rbxassetid://117861167307650", volume = 1.05 },
	Legendary = { id = "rbxassetid://75127344844404", volume = 1.10 },
	Mythic = {
		id = "rbxassetid://130326607016455",
		after = "rbxassetid://93989620006639",
		volume = 0.70,
	},
	Secret = { id = "rbxassetid://139682612041479", volume = 1.20 },
}

local function playRaw(id, volume, bus)
	if not RunService:IsClient() then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "sting"
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	if Sounds.router then
		Sounds.router(sound, bus or "SFX")
	end
	sound:Play()
	return sound
end

--[[
	Play the find. One place, so the three call sites that announce a drop
	cannot drift into announcing it three different ways.

	`scale` is for somebody ELSE'S find: a server-wide Mythic should read as
	distant good news rather than as your own, so it plays quieter and skips
	the second half of a two-part cue.
]]
function Sounds.sting(tierName, scale)
	local sting = STINGS[tierName] or STINGS.Common
	scale = scale or 1
	local first = playRaw(sting.id, sting.volume * scale)
	if not first then
		return sting
	end

	if sting.after and scale >= 1 then
		--[[ Chained on Ended, not on a timer. The wind-up decides when the
		     finish lands, so re-cutting either file keeps them in step. ]]
		first.Ended:Once(function()
			playRaw(sting.after, sting.volume * scale)
		end)
	end

	first.Ended:Once(function()
		first:Destroy()
	end)
	task.delay(12, function()
		if first.Parent then
			first:Destroy()
		end
	end)
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
