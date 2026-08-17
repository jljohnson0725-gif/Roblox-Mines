--[[
	Rarity
	The seven character tiers. A tier sets a character's BASE income and its
	base weight in the drop table.

	`weight` and `growth` drive the drop roll:
		weight_at(L) = weight * growth ^ L      where L = log2(current multiplier)

	Tiers with growth < 1 shrink as the run gets deeper; tiers with growth > 1
	balloon. That single line is what makes deep Mines runs worth the risk.
]]

local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

Rarity.Tiers = {
	Common = {
		index = 1,
		income = 2,
		weight = 1000,
		growth = 0.72,
		color = Color3.fromRGB(168, 176, 190),
		modelColor = Color3.fromRGB(150, 158, 172),
	},
	Uncommon = {
		index = 2,
		income = 7,
		weight = 400,
		growth = 0.90,
		color = Color3.fromRGB(92, 204, 120),
		modelColor = Color3.fromRGB(80, 180, 106),
	},
	Rare = {
		index = 3,
		income = 25,
		weight = 120,
		growth = 1.10,
		color = Color3.fromRGB(74, 148, 255),
		modelColor = Color3.fromRGB(62, 126, 224),
	},
	Epic = {
		index = 4,
		income = 90,
		weight = 30,
		growth = 1.35,
		color = Color3.fromRGB(178, 96, 255),
		modelColor = Color3.fromRGB(150, 80, 220),
	},
	Legendary = {
		index = 5,
		income = 320,
		weight = 6,
		growth = 1.60,
		color = Color3.fromRGB(255, 176, 46),
		modelColor = Color3.fromRGB(226, 150, 30),
	},
	Mythic = {
		index = 6,
		-- 4500 x mul 0.90-1.20 -> 4.1K to 5.4K/s, i.e. "around 5K"
		income = 4500,
		weight = 0.8,
		growth = 1.90,
		color = Color3.fromRGB(255, 82, 110),
		modelColor = Color3.fromRGB(214, 58, 88),
	},
	Secret = {
		index = 7,
		--[[ 12000 x mul 1.00-1.20 -> 12K to 14.4K/s.

		     Raised from 5000 because Secrets stopped being a drop and became the
		     8% payout on wagering everything you own. A prize that rare has to
		     out-earn a Mythic by a wide margin or the wheel is a bad bet on its
		     own terms. ]]
		income = 12000,
		--[[
			WHEEL ONLY. Secrets cannot be rolled in the Mines at any multiplier,
			at any mine count, under any event. The only way to own one is to
			wager everything on the wheel and hit the 8%.

			`weight` and `growth` are kept so the tier still has a shape if it is
			ever made rollable again, but DropTable skips it entirely -- see
			Rarity.Rollable.
		]]
		--[[
			ROLLABLE NOW, and far below Mythic. This was wheelOnly, so the wheel
			was the only route to a Secret and that exclusivity was its whole
			reason to exist. Opening Mines to Secrets costs the wheel that, so
			the weight is set an order of magnitude under Mythic's 0.8 -- the
			wheel stays overwhelmingly the faster route, and a Secret out of
			Mines stays a story rather than a plan.

			0.18, not the 0.02 tried first. That put a Secret at one drop in
			36,800 -- about 433 hours of mining -- which is rollable on paper
			and never in practice. "Rarer than Mythic" has to still be
			reachable, so this sits about four times under it: roughly one in
			4,000 drops, or a couple of days of play. The wheel offers 9.4% a
			spin, so it remains the route anyone actually takes.
		]]
		weight = 0.18,
		growth = 2.20,
		-- Near-white so it reads on the dark UI; the model itself is void-black.
		color = Color3.fromRGB(238, 238, 250),
		modelColor = Color3.fromRGB(26, 26, 34),
	},
}

--[[
	The tiers the Mines is allowed to roll: Order minus anything wheelOnly.

	Separate from Order on purpose. Order is the full ladder and stays complete,
	because the Index has to list Secrets as undiscovered rather than pretend
	they don't exist -- seeing the locked row is what tells you the wheel is
	where they come from.
]]
Rarity.Rollable = {}
for _, name in ipairs(Rarity.Order) do
	if not Rarity.Tiers[name].wheelOnly then
		table.insert(Rarity.Rollable, name)
	end
end

function Rarity.get(name)
	return Rarity.Tiers[name] or Rarity.Tiers.Common
end

return Rarity
