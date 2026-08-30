--[[
	Upgrades
	The money sink that exists after pads run out.

	Pads cap at 8 (~$1.02M to max), and past that money had nowhere to go but
	bets. These scale forever, so late-game income always has something to buy.

	DELIBERATELY NO LUCK UPGRADE. Buying better drop odds would attack the first
	design pillar -- the multiplier IS the luck stat. If luck is purchasable,
	the mine-count dial and the cash-out decision both matter less, and the thing
	that makes this more than a clicker gets diluted. Nothing here touches the
	drop table.

	EXTRA LIFE USED TO LIVE HERE and does not any more. It was the one upgrade
	that touched risk, and as a LEVEL it was permanent: buy the third and every
	round afterwards started with three mistakes in hand, free, forever. That
	made it the last time a bad pick ever cost anything. It is a consumable in
	Shared/Items now -- bought, held, and spent one per survived mine.

	Effects are pure functions of level so nothing has to be recomputed or
	cached -- the level is the only thing that persists.
]]

local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)

local Upgrades = {}

Upgrades.List = {
	{
		id = "income",
		name = "Rent Multiplier",
		blurb = "Every brainrot pays more",
		color = Color3.fromRGB(120, 235, 150),
		maxLevel = 25,
		baseCost = 4000,
		costGrowth = 1.55,
		-- +20% per level -> x6 at max, for ~$420M total. 40 levels at 1.9x growth
		-- put the last level at $371 TRILLION, which nobody would ever reach --
		-- a curve people abandon at level 8 isn't a money sink, it's a wall.
		effect = function(level)
			return 1 + level * 0.20
		end,
		format = function(level)
			return string.format("x%.2f income", 1 + level * 0.20)
		end,
	},
	{
		id = "capacity",
		name = "Vault Capacity",
		blurb = "Piles keep growing while you're away",
		color = Color3.fromRGB(255, 190, 60),
		maxLevel = 12,
		baseCost = 20000,
		costGrowth = 1.8,
		-- +45 min per level on top of the 4h base -> 13h fully upgraded, which
		-- covers an overnight session
		effect = function(level)
			return level * 45 * 60
		end,
		format = function(level)
			local hours = (4 * 3600 + level * 45 * 60) / 3600
			return string.format("%.1fh of storage", hours)
		end,
	},
	{
		id = "speed",
		name = "Fast Feet",
		blurb = "Get to the Mines and back quicker",
		color = Color3.fromRGB(120, 132, 255),
		maxLevel = 12,
		baseCost = 3000,
		costGrowth = 1.60,
		-- Starts at Config.BaseWalkSpeed (25, what level 6 used to give) and runs
		-- to 43. Deliberately cheap: it buys down travel time, so it should be
		-- reachable early.
		effect = function(level)
			return Config.BaseWalkSpeed + level * 1.5
		end,
		format = function(level)
			return string.format("%.0f walk speed", Config.BaseWalkSpeed + level * 1.5)
		end,
	},
}

Upgrades.ById = {}
for _, entry in ipairs(Upgrades.List) do
	Upgrades.ById[entry.id] = entry
end

function Upgrades.get(id)
	return Upgrades.ById[id]
end

--[[ Cost of the NEXT level, or nil when maxed.

     Two shapes, because two things are being priced. Most upgrades are a curve
     -- a base and a growth rate, running for a dozen levels or more. Extra Life
     is three prices: 1.5M, 10M, 30M, a 6.7x step followed by a 3x one, which no
     single growth rate produces. Forcing it into one would mean picking which
     of the three numbers to get wrong, so a def may simply list them. ]]
function Upgrades.cost(id, currentLevel)
	local def = Upgrades.get(id)
	if not def or currentLevel >= def.maxLevel then
		return nil
	end
	if def.costs then
		return def.costs[currentLevel + 1]
	end
	return math.floor(def.baseCost * (def.costGrowth ^ currentLevel))
end

function Upgrades.levelOf(profile, id)
	return (profile and profile.upgrades and profile.upgrades[id]) or 0
end

function Upgrades.valueOf(profile, id)
	local def = Upgrades.get(id)
	if not def then
		return 0
	end
	return def.effect(Upgrades.levelOf(profile, id))
end

--[[ Convenience readers, so callers don't repeat the effect lookups.

     TIMED BOOSTS FOLD IN HERE, not at the call sites. "What does this player's
     income get multiplied by" has one honest answer and three callers who each
     need it -- the HUD readout, the accrual tick and the per-pad rate -- and a
     boost that only some of them knew about would show one number and pay a
     different one. Same argument for walk speed and its one caller. ]]
function Upgrades.incomeMultiplier(profile)
	return Upgrades.valueOf(profile, "income") * Items.incomeMultiplier(profile)
end

function Upgrades.capSeconds(profile, baseSeconds)
	return baseSeconds + Upgrades.valueOf(profile, "capacity")
end

function Upgrades.walkSpeed(profile)
	return Upgrades.valueOf(profile, "speed") + Items.walkBonus(profile)
end

--[[ How many mines this player survives in one round. Read fresh at the start
     of each round; MinesService owns the spending. ]]

return Upgrades
