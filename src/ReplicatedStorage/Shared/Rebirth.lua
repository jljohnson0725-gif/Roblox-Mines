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
