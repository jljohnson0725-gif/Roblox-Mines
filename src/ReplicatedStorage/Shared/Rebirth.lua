--[[
	Rebirth
	Give the run back, keep the luck.

	LUCK IS BONUS DEPTH, not a separate stat bolted on beside the drop table.
	DropTable already climbs rarity as growth^depth, where depth is log2 of the
	round multiplier -- so rebirth simply adds to that, and every round plays as
	though more tiles had been revealed than actually were. In a game whose
	pillar is that the multiplier IS the luck stat, expressing luck any other
	way would be saying one thing and doing another.

	THE NUMBERS ARE MODELLED, in tools/rebirth.py, and two of them contradict
	what I first proposed:

	  - Mythic was supposed to be the risk and is not, by a factor of three. At
	    +0.35 a rebirth it moves from 0.097% of drops to 0.40% over five, and
	    does not reach 1% until +2.97 -- about eight rebirths away.
	  - The risk is COMPOUNDING. Luck alone already yields 4.4x income by the
	    fifth rebirth, which is the ceiling past which a returning player's old
	    base was never worth building. A second, separate income multiplier was
	    planned alongside this and would have doubled that again to 8.8x. It was
	    cut. Luck already is the income multiplier.

	COST TRACKS INCOME, or the loop stalls. Income rises 1.34x a rebirth, so the
	cost growth is 1.35 -- the same number read back. At the 2.2 first proposed,
	the fifth rebirth took 49.5 hours against the first's 16.5, which is a wall
	rather than a loop. At 1.35 it holds flat: 13.0, 13.5, 14.0, 14.0, 11.0.

	Growth and base do different jobs, which is what to reach for when tuning:
	growth decides whether the loop holds at all, base only decides where it
	starts.
]]

local Shared = script.Parent
local Config = require(Shared.Config)

local Rebirth = {}

--[[ What the next one costs, given how many you already have. ]]
function Rebirth.cost(rebirths)
	return math.floor(Config.RebirthBaseCost
		* (Config.RebirthCostGrowth ^ (rebirths or 0)))
end

--[[ Bonus drop depth, permanently. Fed into DropTable alongside event mods. ]]
function Rebirth.luck(rebirths)
	return (rebirths or 0) * Config.RebirthLuckPerLevel
end

--[[
	Pads you start a run with. Capped short of the full eight on purpose: the
	perk is meant to reshape the opening hour, not hand you the finished base
	and delete the part of the game that is about building one.
]]
function Rebirth.startPads(rebirths)
	return math.min(
		Config.StartingSlots + (rebirths or 0) * Config.RebirthPadsPerLevel,
		Config.RebirthMaxStartPads)
end

--[[
	THE APARTMENT RENOVATES.

	Rebirth's rewards are all invisible -- luck is a number inside a drop roll,
	pads are a count. The one thing a player looks at for hours is the room they
	keep their collection in, so that is where the progress gets shown.

	This is the glow-up arc read as interior decoration: tier 0 is the cheap
	first place you get dumped into, tier 5 is the penthouse. Nothing here is
	mechanical -- no tier grants income or luck -- because rebirth already pays
	in both and a cosmetic that also buffs stops being read as a cosmetic.

	Thresholds are spaced 0,1,2,3,5,8 rather than one per rebirth. At one per
	rebirth the late tiers would need names for changes nobody could see, and
	the early ones -- where the arc has to sell itself -- would arrive slowest.
	This front-loads them: three renovations in your first three rebirths.

	Tier 0 is PLAIN, NOT BROKEN. It is what the whole first run is spent in, and
	a run spent somewhere that looks like a bug is not a story beat. Bare
	concrete under a cold bulb reads as cheap, which is the intent.

	BRIGHTNESS IS DERIVED, NOT CHOSEN -- see tools/hometiers.py. The first pass
	raised surface lightness and light brightness together, and Designer came
	out as white marble under four lights at 1.6: no floor, no corners, nothing
	readable. HomeService already carried a comment warning about that exact
	failure, which is the useful lesson -- "nicer" is not "brighter".

	So what the eye reads is modelled as light x albedo, and each tier's
	brightness is that target divided by its own wall. The target climbs gently
	(0.38 -> 0.60) across the whole arc, which is why the dark tiers carry the
	big brightness numbers and the pale ones do not. The model also enforces a
	floor/wall value gap, so the floor line never disappears.

	A tier's identity therefore comes from MATERIAL, HUE and ACCENT. Re-run
	tools/hometiers.py after touching any colour here.

	Two more traps the model now catches, both found by looking rather than by
	measuring -- the first version of it passed all six tiers and two of them
	were unusable on screen:

	  - GLASS WILL NOT HOLD A COLOUR. Empire's floor was authored as dark glass
	    and rendered near-white and reflective, because Roblox ignores the RGB.
	    Dark marble instead.
	  - A SATURATED BULB PAINTS THE WHOLE ROOM ITS OWN HUE. Empire's violet
	    light at brightness 2.15 turned every surface flat purple. The light is
	    near-neutral now and the magenta accent carries the identity, which is
	    the general rule: colour the ACCENT, not the air.
]]
Rebirth.tiers = {
	{
		at = 0,
		name = "Studio",
		floor = Color3.fromRGB(96, 93, 90),
		floorMaterial = Enum.Material.Concrete,
		wall = Color3.fromRGB(140, 135, 127),
		light = Color3.fromRGB(226, 232, 240),
		brightness = 0.72,
		range = 26,
		accent = Color3.fromRGB(120, 190, 140),
	},
	{
		at = 1,
		name = "Furnished",
		floor = Color3.fromRGB(96, 68, 44),
		floorMaterial = Enum.Material.WoodPlanks,
		wall = Color3.fromRGB(150, 141, 128),
		light = Color3.fromRGB(255, 240, 210),
		brightness = 0.79,
		range = 30,
		accent = Color3.fromRGB(96, 226, 130),
	},
	{
		at = 2,
		name = "Renovated",
		floor = Color3.fromRGB(122, 84, 52),
		floorMaterial = Enum.Material.Wood,
		wall = Color3.fromRGB(166, 154, 138),
		light = Color3.fromRGB(255, 244, 220),
		brightness = 0.79,
		range = 34,
		accent = Color3.fromRGB(104, 232, 176),
	},
	{
		at = 3,
		name = "Designer",
		floor = Color3.fromRGB(150, 146, 140),
		floorMaterial = Enum.Material.Marble,
		wall = Color3.fromRGB(176, 166, 152),
		light = Color3.fromRGB(255, 238, 206),
		brightness = 0.79,
		range = 38,
		accent = Color3.fromRGB(96, 214, 214),
	},
	{
		at = 5,
		name = "Penthouse",
		floor = Color3.fromRGB(48, 46, 54),
		floorMaterial = Enum.Material.Marble,
		wall = Color3.fromRGB(86, 80, 88),
		light = Color3.fromRGB(255, 214, 150),
		brightness = 1.74,
		range = 42,
		accent = Color3.fromRGB(240, 196, 92),
	},
	{
		at = 8,
		name = "Empire",
		floor = Color3.fromRGB(34, 32, 46),
		floorMaterial = Enum.Material.Marble,
		wall = Color3.fromRGB(74, 68, 96),
		light = Color3.fromRGB(236, 226, 255),
		brightness = 2.15,
		range = 46,
		accent = Color3.fromRGB(226, 120, 255),
	},
}

--[[ The tier a given rebirth count is living in. Walks up rather than indexing,
     because the thresholds are deliberately not one per level. ]]
function Rebirth.tier(rebirths)
	local level = rebirths or 0
	local found = Rebirth.tiers[1]
	for _, tier in ipairs(Rebirth.tiers) do
		if level >= tier.at then
			found = tier
		end
	end
	return found
end

--[[ The next renovation and how far off it is, or nil at the top. Used to tell
     a player what the next rebirth redecorates, so the reward is legible
     BEFORE it is paid for rather than being a surprise afterwards. ]]
function Rebirth.nextTier(rebirths)
	local level = rebirths or 0
	for _, tier in ipairs(Rebirth.tiers) do
		if tier.at > level then
			return tier, tier.at - level
		end
	end
	return nil, nil
end

--[[ Whether a profile may rebirth right now, and why not if it may not. ]]
function Rebirth.check(profile)
	if not profile then
		return false, "Still loading, one sec."
	end
	if (profile.slots or 0) < Config.MaxSlots then
		return false, "Own all " .. Config.MaxSlots .. " pads first."
	end
	local cost = Rebirth.cost(profile.rebirths)
	if (profile.money or 0) < cost then
		return false, nil, cost -- caller formats the money
	end
	return true, nil, cost
end

return Rebirth
