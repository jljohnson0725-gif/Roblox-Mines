--[[
	Racing
	The rules of a race, shared so the odds on the panel and the odds the server
	rolls against can never be two different numbers.

	THE PAYOUT IS DERIVED, NEVER AUTHORED. `pay = TARGET_RTP / win`, always. The
	first version of the model authored payouts per field and let upgrades raise
	win chance, and since expected value is win x pay, every upgrade level
	multiplied the house's loss -- the top field reached 508% RTP at max, an
	infinite money printer that would have quietly retired the whole idle
	economy. Deriving it makes that class of mistake unrepresentable: RTP is
	80% for every field at every upgrade level because there is nowhere else for
	it to come from.

	SO WHAT DO UPGRADES BUY? Consistency and progress, not profit. A level moves
	your win chance toward the field's ceiling, so you win more often and each
	win pays proportionally less -- identical expected value, far smoother ride.
	And because a seal fragment can only drop on a WIN, winning more often is
	what makes the next island arrive sooner. Progress speeds up; profit does
	not.

	HARDER FIELDS ARE NOT A BETTER DEAL, they are a swingier one -- the same
	trade the mine-count selector makes, which is why this should feel native
	rather than bolted on. Equal EV, 2.1x the swing from Novice to Legend.

	tools/race.py is the model. Re-run it after touching any number here.
]]

local Racing = {}

Racing.TARGET_RTP = 0.80

--[[ `win` is the chance at upgrade level 0. `frag` is the chance a WIN also
     yields a fragment toward the racing seal -- conditioned on winning, which
     is the whole reason upgrades speed up progress. ]]
Racing.Fields = {
	{ id = "novice", name = "Novice", rivals = 3, win = 0.52, frag = 0.05 },
	{ id = "contender", name = "Contender", rivals = 5, win = 0.34, frag = 0.10 },
	{ id = "champion", name = "Champion", rivals = 7, win = 0.19, frag = 0.20 },
	{ id = "legend", name = "Legend", rivals = 9, win = 0.09, frag = 0.38 },
}

Racing.ById = {}
for index, field in ipairs(Racing.Fields) do
	field.index = index
	Racing.ById[field.id] = field
end

Racing.MaxLevel = 8

--[[
	How much of the gap to certainty a fully upgraded player closes.

	Swept, not guessed. At 0.55 a maxed Legend won 59% and paid 1.35x, which
	collapsed the swing spread across fields to 1.6x and made the field selector
	decorative -- the same failure this file exists to prevent, arriving from the
	other direction. 0.20 holds the spread at 2.1x with Legend still a genuine
	long shot (27% at 2.94x), while a seal still lands 3x faster than at level 0.
]]
Racing.UpgradeReach = 0.20

--[[
	What the next speed level costs.

	Geometric, and steep on purpose. A level buys CONSISTENCY, never profit --
	RTP is 80% at level 0 and 80% at level 8 -- so the thing being sold is a
	smoother ride and a seal that arrives about 3x sooner. Priced against the
	rebirth wall rather than against a race: all eight levels come to roughly
	90M, so maxing this is a real project sitting just under the 150M rebirth
	rather than something a good evening pays for.
]]
Racing.UpgradeBase = 1500000
Racing.UpgradeGrowth = 1.55

function Racing.upgradeCost(level)
	level = math.floor(level or 0)
	if level >= Racing.MaxLevel then
		return nil -- maxed; callers show this rather than a price
	end
	return math.floor(Racing.UpgradeBase * (Racing.UpgradeGrowth ^ level))
end

function Racing.get(id)
	return id and Racing.ById[id] or nil
end

function Racing.level(store)
	local level = store and tonumber(store.raceLevel) or 0
	return math.clamp(math.floor(level), 0, Racing.MaxLevel)
end

--[[ Win chance for this field at this upgrade level. Level 0 is the field's
     own number; maxed closes UpgradeReach of the remaining gap to certainty. ]]
function Racing.winChance(field, level)
	if not field then
		return 0
	end
	level = math.clamp(level or 0, 0, Racing.MaxLevel)
	return field.win + (1 - field.win) * Racing.UpgradeReach * (level / Racing.MaxLevel)
end

--[[ The multiple of your stake a win returns. Derived, so the house edge is
     identical everywhere and cannot be tuned apart by accident. ]]
function Racing.payout(win)
	if not win or win <= 0 then
		return 0
	end
	return Racing.TARGET_RTP / win
end

--[[ Everything the panel needs for one row, and everything the server needs to
     settle one race -- from a single place, so they agree by construction. ]]
function Racing.odds(store, field)
	local level = Racing.level(store)
	local win = Racing.winChance(field, level)
	return {
		id = field.id,
		name = field.name,
		rivals = field.rivals,
		level = level,
		win = win,
		pay = Racing.payout(win),
		frag = field.frag,
	}
end

function Racing.all(store)
	local rows = {}
	for _, field in ipairs(Racing.Fields) do
		table.insert(rows, Racing.odds(store, field))
	end
	return rows
end

return Racing
