--[[
	Items
	What the street shop sells that isn't an upgrade level.

	Three kinds, and the difference is only where the purchase lands. EVERY ITEM
	IS CURRENTLY AN UNLOCK -- the boost and instant machinery is kept because it
	is generic and costs nothing idle (every helper below walks Items.List, so
	with no boost in the list they return 0 and 1), not because anything uses
	it. Energy Drink, Double Rent and Vault Sweep were the three that did.

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
     spend and then use, rather than something you buy and forget you have.
     Unreferenced while the shop sells no boosts; kept with the machinery. ]]
Items.MaxStack = 4 * 3600

Items.List = {
	{
		--[[
			THE STINK IS THE DEFAULT, so this is the only row in the shop that
			sells a SUBTRACTION. You spawn with the aura on; five hundred
			million takes it off. Nothing else about the character changes.

			Which makes it the one purchase whose effect other players see
			before you do -- the aura is server-made and replicated, so it has
			always been on for everyone but you. See AppearanceService.
		]]
		id = "cologne",
		kind = "unlock",
		flag = "cologne",
		name = "Cologne",
		blurb = "1st step to winning her back",
		color = Color3.fromRGB(150, 205, 90),
		cost = Config.CologneCost,
		effect = "yours for good -- clears the stink",
	},
	{
		--[[
			Replaces the head outright: the real one goes invisible and the chad
			head is welded on in its place. Hair and hats go with it, because a
			ponytail through the jaw is not the joke.
		]]
		id = "peptides",
		kind = "unlock",
		flag = "peptides",
		name = "Peptides",
		blurb = "Fix your face",
		color = Color3.fromRGB(236, 232, 224),
		cost = Config.PeptidesCost,
		effect = "yours for good -- new head",
	},
	{
		--[[
			THE BALL REPLACED THE JETPACK, and it is a different kind of thing.

			The jetpack was a traversal mechanic: you bought flight and then
			flew wherever you liked, which meant every island's access was
			really a height check. The ball is a DESTINATION -- one press and
			you are on Plinko island. Nothing about it lets you go anywhere
			else, so the islands are now reached by the thing that goes to
			them: the ball to Plinko, the whistle to Racing.
		]]
		id = "plinkoball",
		kind = "unlock",
		flag = "plinkoball",
		name = "Plinko Ball",
		blurb = "Keep it. Throw it. Be there.",
		color = Color3.fromRGB(120, 200, 255),
		cost = Config.PlinkoBallCost,
		effect = "yours for good -- takes you to Plinko",
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
