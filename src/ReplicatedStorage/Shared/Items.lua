--[[
	Items
	What the street shop sells that isn't an upgrade level.

	Three kinds, and the difference is only where the purchase lands:

	  boost   -- a stretch of time. Stored as an EXPIRY, never as a remaining
	             duration, so logging out doesn't bank the minutes you weren't
	             there for and a server restart can't quietly extend one.
	  unlock  -- a flag on the profile. Bought once, owned forever.
	  instant -- no state at all: the purchase IS the effect.

	NOTHING HERE SELLS LUCK, for exactly the reason Upgrades doesn't. The
	multiplier is the luck stat; a shop that sells drop odds turns the mine-count
	dial into a formality and the cash-out decision into arithmetic. Every item
	here moves money, time or distance, and none of them touch the drop table.

	BOOSTS STACK BY EXTENSION rather than refusing a second purchase. Refusing is
	the worse answer -- it punishes someone for wanting to spend, and makes them
	sit watching a timer before the shop will take their money again. There is a
	cap so it can't be pre-paid for a week.
]]

local Config = require(script.Parent.Config)

local Items = {}

--[[ Ten minutes is deliberately short enough that a boost is something you
     spend and then use, rather than something you buy and forget you have. ]]
local SHIFT = 10 * 60
Items.MaxStack = 4 * 3600

Items.List = {
	{
		id = "energy",
		kind = "boost",
		name = "Energy Drink",
		blurb = "Move like the rent is due",
		color = Color3.fromRGB(120, 235, 150),
		cost = 25000,
		duration = SHIFT,
		--[[ +12 on top of Fast Feet, which runs 25 to 43. Big enough to feel
		     from the first sip; temporary, so it never makes the upgrade
		     pointless to buy. ]]
		walkBonus = 12,
		effect = "+12 walk speed",
	},
	{
		id = "doublerent",
		kind = "boost",
		name = "Double Rent",
		blurb = "Every brainrot pays twice over",
		color = Color3.fromRGB(255, 190, 60),
		cost = 150000,
		duration = SHIFT,
		incomeMultiplier = 2,
		effect = "x2 income",
	},
	{
		id = "sweep",
		kind = "instant",
		name = "Vault Sweep",
		blurb = "Bank every pile without the walk",
		color = Color3.fromRGB(120, 132, 255),
		--[[ Flat priced, though what it collects isn't. That's the intended
		     shape: it buys back a walk home, so it's worth it in the mid game
		     and beneath notice later. It can never print money -- everything it
		     banks is money you would have collected on foot anyway. ]]
		cost = 60000,
		effect = "collects your whole base",
	},
	{
		id = "jetpack",
		kind = "unlock",
		flag = "jetpack",
		name = "Jetpack",
		blurb = "Press F and leave the ground",
		color = Color3.fromRGB(120, 200, 255),
		cost = Config.JetpackCost,
		effect = "yours for good",
	},
	{
		id = "whistle",
		kind = "unlock",
		flag = "whistle",
		name = "Brainrot Whistle",
		blurb = "Call a ride to the racing island",
		color = Color3.fromRGB(190, 150, 255),
		--[[ Dearer than the jetpack because it comes later: by the time the
		     Plinko seal is in reach, a million is not the decision it was. ]]
		cost = 2500000,
		--[[ Says what it does NOT buy, on the row itself. The seal still gates
		     the island -- this only removes the walk to a perch that used to
		     stand on the street -- and finding that out at the shop is far
		     better than finding it out after paying. ]]
		effect = "needs the Plinko saddle to ride",
	},
}

Items.ById = {}
for _, entry in ipairs(Items.List) do
	Items.ById[entry.id] = entry
end

function Items.get(id)
	return Items.ById[id]
end

--[[ Seconds left on a boost, 0 when it isn't running.

     `now` is a parameter rather than an os.time() call inside, because the
     client has no business trusting its own clock about this: it is handed
     remaining seconds by the server and counts down locally from there. ]]
function Items.remaining(profile, id, now)
	local expiry = profile and profile.boosts and profile.boosts[id]
	if type(expiry) ~= "number" then
		return 0
	end
	return math.max(expiry - (now or os.time()), 0)
end

function Items.isActive(profile, id, now)
	return Items.remaining(profile, id, now) > 0
end

function Items.owned(profile, def)
	return def.kind == "unlock" and profile ~= nil and profile[def.flag] == true
end

--[[ Multiplicative, so a second income boost would compound rather than
     overwrite the first. There is only one today; the shape is the point. ]]
function Items.incomeMultiplier(profile, now)
	local multiplier = 1
	for _, def in ipairs(Items.List) do
		if def.incomeMultiplier and Items.isActive(profile, def.id, now) then
			multiplier *= def.incomeMultiplier
		end
	end
	return multiplier
end

function Items.walkBonus(profile, now)
	local bonus = 0
	for _, def in ipairs(Items.List) do
		if def.walkBonus and Items.isActive(profile, def.id, now) then
			bonus += def.walkBonus
		end
	end
	return bonus
end

return Items
