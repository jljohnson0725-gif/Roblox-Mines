--[[
	Variants
	The second axis. Rolled INDEPENDENTLY of the character tier, so a Common
	character can show up Galaxy and a Secret can show up Normal.

	final income = tier.income * character.mul * variant.mult * Config.IncomeMultiplier

	Variants scale with run depth too, but more gently than tiers do -- otherwise
	deep runs would double-dip and the top end would break.
]]

local Variants = {}

Variants.Order = { "Normal", "Gold", "Diamond", "Rainbow", "Frost", "Lava", "Galaxy" }

--[[
	`shell` is how see-through the coloured overlay is.

	A variant CANNOT be done by tinting the mesh: MeshPart.Color has no effect
	once a TextureID is set -- a gold tint over a textured rat renders as the
	plain rat, verified in Studio. Painting the mesh flat instead loses the face,
	the suit and the sunglasses, which is what made our Gold and Diamond
	unreadable blobs.

	So ModelFactory keeps the textured mesh and puts a slightly larger
	semi-transparent copy over it. The colour reads across the whole silhouette
	and the art still shows through, which is what the reference art does by
	recolouring only some parts of a many-part model.

	NOTHING IS NEON ANY MORE. A neon shell is fully self-lit, so it flattens the
	very shading that makes the shape legible. Rarity is already carried by the
	aura disc under the model and by the nameplate colour.
]]
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
		color = Color3.fromRGB(255, 196, 64),
		material = Enum.Material.Metal,
		reflectance = 0.3,
		shell = 0.42,
	},
	Diamond = {
		index = 3,
		mult = 6,
		weight = 70,
		growth = 1.15,
		prefix = "Diamond ",
		color = Color3.fromRGB(150, 235, 255),
		material = Enum.Material.Glass,
		reflectance = 0.35,
		shell = 0.50,
	},
	Rainbow = {
		index = 4,
		mult = 15,
		weight = 15,
		growth = 1.35,
		prefix = "Rainbow ",
		color = Color3.fromRGB(255, 120, 200), -- cycled client-side
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.1,
		shell = 0.45,
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
		color = Color3.fromRGB(196, 240, 255),
		material = Enum.Material.Ice,
		reflectance = 0.25,
		shell = 0.48,
		eventOnly = true,
	},
	Lava = {
		index = 6,
		mult = 40,
		weight = 3,
		growth = 1.55,
		prefix = "Lava ",
		color = Color3.fromRGB(255, 100, 32),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0,
		shell = 0.40,
	},
	Galaxy = {
		index = 7,
		mult = 110,
		weight = 0.3,
		growth = 1.80,
		prefix = "Galaxy ",
		color = Color3.fromRGB(140, 95, 255),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.15,
		shell = 0.40,
	},
}

function Variants.get(name)
	return Variants.List[name] or Variants.List.Normal
end

return Variants
