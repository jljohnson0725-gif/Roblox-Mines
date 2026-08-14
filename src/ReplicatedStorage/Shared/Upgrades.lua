--[[
	Upgrades
	The money sink that exists after pads run out.

	Pads cap at 8 (~$1.02M to max), and past that money had nowhere to go but
	bets. These scale forever, so late-game income always has something to buy.

	DELIBERATELY NO LUCK UPGRADE. Buying better drop odds would attack the first
	design pillar -- the multiplier IS the luck stat. If luck is purchasable,
	the mine-count dial and the cash-out decision both matter less, and the thing
	that makes this more than a clicker gets diluted. Every upgrade here moves
	money, time or distance; none of them touch the drop table.

	Effects are pure functions of level so nothing has to be recomputed or
	cached -- the level is the only thing that persists.
]]

local Config = require(script.Parent.Config)

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
	{
		id = "radius",
		name = "Long Arms",
		blurb = "Collect from further away",
		color = Color3.fromRGB(90, 226, 255),
		maxLevel = 10,
		baseCost = 8000,
		costGrowth = 1.70,
		-- base reach is 4 studs around a strip; at max you sweep most of a row
		effect = function(level)
			return 4 + level * 3.5
		end,
		format = function(level)
			return string.format("%.0f stud reach", 4 + level * 3.5)
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

--[[ Cost of the NEXT level, or nil when maxed. ]]
function Upgrades.cost(id, currentLevel)
	local def = Upgrades.get(id)
	if not def or currentLevel >= def.maxLevel then
		return nil
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

--[[ Convenience readers, so callers don't repeat the effect lookups. ]]
function Upgrades.incomeMultiplier(profile)
	return Upgrades.valueOf(profile, "income")
end

function Upgrades.capSeconds(profile, baseSeconds)
	return baseSeconds + Upgrades.valueOf(profile, "capacity")
end

function Upgrades.walkSpeed(profile)
	return Upgrades.valueOf(profile, "speed")
end

function Upgrades.collectReach(profile)
	return Upgrades.valueOf(profile, "radius")
end

return Upgrades
