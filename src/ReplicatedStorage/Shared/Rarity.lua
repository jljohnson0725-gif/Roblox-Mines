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
		income = 1200,
		weight = 0.8,
		growth = 1.90,
		color = Color3.fromRGB(255, 82, 110),
		modelColor = Color3.fromRGB(214, 58, 88),
	},
	Secret = {
		index = 7,
		income = 5000,
		weight = 0.05,
		growth = 2.20,
		-- Near-white so it reads on the dark UI; the model itself is void-black.
		color = Color3.fromRGB(238, 238, 250),
		modelColor = Color3.fromRGB(26, 26, 34),
	},
}

function Rarity.get(name)
	return Rarity.Tiers[name] or Rarity.Tiers.Common
end

return Rarity
