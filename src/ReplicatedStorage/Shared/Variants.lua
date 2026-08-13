--[[
	Variants
	The second axis. Rolled INDEPENDENTLY of the character tier, so a Common
	character can show up Galaxy and a Secret can show up Normal.

	final income = tier.income * character.mul * variant.mult

	Variants scale with run depth too, but more gently than tiers do -- otherwise
	deep runs would double-dip and the top end would break.
]]

local Variants = {}

Variants.Order = { "Normal", "Gold", "Diamond", "Rainbow", "Frost", "Lava", "Galaxy" }

Variants.List = {
	Normal = {
		index = 1,
		mult = 1,
		weight = 1000,
		growth = 0.85,
		prefix = "",
		color = nil, -- keeps the character's own colour
		material = Enum.Material.SmoothPlastic,
		reflectance = 0,
	},
	Gold = {
		index = 2,
		mult = 2.5,
		weight = 250,
		growth = 1.00,
		prefix = "Gold ",
		color = Color3.fromRGB(255, 200, 62),
		material = Enum.Material.Metal,
		reflectance = 0.25,
	},
	Diamond = {
		index = 3,
		mult = 6,
		weight = 70,
		growth = 1.15,
		prefix = "Diamond ",
		color = Color3.fromRGB(150, 240, 255),
		material = Enum.Material.Glass,
		reflectance = 0.45,
	},
	Rainbow = {
		index = 4,
		mult = 15,
		weight = 15,
		growth = 1.35,
		prefix = "Rainbow ",
		color = Color3.fromRGB(255, 120, 200), -- cycled client-side
		material = Enum.Material.Neon,
		reflectance = 0,
		cycleHue = true,
	},
	--[[
		EVENT-EXCLUSIVE. Base weight 0 means it can never roll normally -- the
		Winter Freeze event surfaces it with `variantAdd`, which is why that
		modifier is additive rather than a multiplier. Copy this shape for any
		future event-locked variant.
	]]
	Frost = {
		index = 5,
		mult = 22,
		weight = 0,
		growth = 1.40,
		prefix = "Frost ",
		color = Color3.fromRGB(186, 240, 255),
		material = Enum.Material.Ice,
		reflectance = 0.3,
		eventOnly = true,
	},
	Lava = {
		index = 6,
		mult = 40,
		weight = 3,
		growth = 1.55,
		prefix = "Lava ",
		color = Color3.fromRGB(255, 92, 24),
		material = Enum.Material.Neon,
		reflectance = 0,
	},
	Galaxy = {
		index = 7,
		mult = 110,
		weight = 0.3,
		growth = 1.80,
		prefix = "Galaxy ",
		color = Color3.fromRGB(126, 80, 255),
		material = Enum.Material.Neon,
		reflectance = 0,
	},
}

function Variants.get(name)
	return Variants.List[name] or Variants.List.Normal
end

return Variants
