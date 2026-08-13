--[[
	Brainrots
	The character roster. Each character belongs to a rarity tier, and carries a
	`mul` so characters inside the same tier aren't income-identical (0.85-1.20).

	`color` only drives the PLACEHOLDER model. Once you have real meshes, drop
	them into ReplicatedStorage/BrainrotModels named by `id` and ModelFactory
	will use them instead -- no code change needed.

	Adding a character is a one-line edit here. Nothing else needs to know.
]]

local Brainrots = {}

Brainrots.List = {
	-- ── Common ──────────────────────────────────────────────────────────────
	{ id = "trippi_troppi",        name = "Trippi Troppi",          tier = "Common",    mul = 0.85, color = Color3.fromRGB(196, 148, 108) },
	{ id = "boneca_ambalabu",      name = "Boneca Ambalabu",        tier = "Common",    mul = 0.95, color = Color3.fromRGB(88, 132, 96) },
	{ id = "brr_brr_patapim",      name = "Brr Brr Patapim",        tier = "Common",    mul = 1.00, color = Color3.fromRGB(140, 112, 78) },
	{ id = "tim_cheese",           name = "Tim Cheese",             tier = "Common",    mul = 1.05, color = Color3.fromRGB(246, 210, 92) },
	{ id = "bananita_dolphinita",  name = "Bananita Dolphinita",    tier = "Common",    mul = 1.10, color = Color3.fromRGB(244, 226, 110) },
	{ id = "svinina_bombardino",   name = "Svinina Bombardino",     tier = "Common",    mul = 1.20, color = Color3.fromRGB(232, 156, 168) },

	-- ── Uncommon ────────────────────────────────────────────────────────────
	{ id = "tung_tung_sahur",      name = "Tung Tung Tung Sahur",   tier = "Uncommon",  mul = 1.00, color = Color3.fromRGB(122, 88, 58) },
	{ id = "lirili_larila",        name = "Lirili Larila",          tier = "Uncommon",  mul = 0.88, color = Color3.fromRGB(198, 186, 160) },
	{ id = "chimpanzini_bananini", name = "Chimpanzini Bananini",   tier = "Uncommon",  mul = 0.96, color = Color3.fromRGB(236, 208, 88) },
	{ id = "bombombini_gusini",    name = "Bombombini Gusini",      tier = "Uncommon",  mul = 1.08, color = Color3.fromRGB(160, 170, 182) },
	{ id = "frigo_camelo",         name = "Frigo Camelo",           tier = "Uncommon",  mul = 1.18, color = Color3.fromRGB(214, 222, 230) },

	-- ── Rare ────────────────────────────────────────────────────────────────
	{ id = "tralalero_tralala",    name = "Tralalero Tralala",      tier = "Rare",      mul = 1.00, color = Color3.fromRGB(64, 110, 190) },
	{ id = "bombardiro_crocodilo", name = "Bombardiro Crocodilo",   tier = "Rare",      mul = 1.12, color = Color3.fromRGB(96, 138, 88) },
	{ id = "cappuccino_assassino", name = "Cappuccino Assassino",   tier = "Rare",      mul = 0.90, color = Color3.fromRGB(112, 78, 56) },
	{ id = "ballerina_cappuccina", name = "Ballerina Cappuccina",   tier = "Rare",      mul = 0.96, color = Color3.fromRGB(226, 176, 200) },
	{ id = "glorbo_fruttodrillo",  name = "Glorbo Fruttodrillo",    tier = "Rare",      mul = 1.20, color = Color3.fromRGB(126, 196, 96) },

	-- ── Epic ────────────────────────────────────────────────────────────────
	{ id = "vacca_saturnita",      name = "La Vacca Saturno Saturnita", tier = "Epic",  mul = 1.15, color = Color3.fromRGB(238, 240, 246) },
	{ id = "girafa_celestre",      name = "Girafa Celestre",        tier = "Epic",      mul = 1.00, color = Color3.fromRGB(240, 196, 96) },
	{ id = "orangutini_ananassini",name = "Orangutini Ananassini",  tier = "Epic",      mul = 0.88, color = Color3.fromRGB(224, 140, 60) },
	{ id = "trulimero_trulicina",  name = "Trulimero Trulicina",    tier = "Epic",      mul = 1.05, color = Color3.fromRGB(92, 168, 196) },

	-- ── Legendary ───────────────────────────────────────────────────────────
	{ id = "los_tralaleritos",     name = "Los Tralaleritos",       tier = "Legendary", mul = 1.20, color = Color3.fromRGB(58, 128, 206) },
	{ id = "odin_din_din_dun",     name = "Odin Din Din Dun",       tier = "Legendary", mul = 1.10, color = Color3.fromRGB(178, 186, 204) },
	{ id = "statutino_libertino",  name = "Statutino Libertino",    tier = "Legendary", mul = 0.92, color = Color3.fromRGB(120, 206, 190) },
	{ id = "tralalita_tralala",    name = "Tralalita Tralala",      tier = "Legendary", mul = 1.00, color = Color3.fromRGB(226, 150, 190) },

	-- ── Mythic ──────────────────────────────────────────────────────────────
	{ id = "garama_madundung",     name = "Garama and Madundung",   tier = "Mythic",    mul = 1.20, color = Color3.fromRGB(206, 78, 62) },
	{ id = "nuclearo_dinossauro",  name = "Nuclearo Dinossauro",    tier = "Mythic",    mul = 1.05, color = Color3.fromRGB(146, 226, 84) },
	{ id = "graipuss_medussi",     name = "Graipuss Medussi",       tier = "Mythic",    mul = 0.90, color = Color3.fromRGB(150, 96, 216) },

	-- ── Secret ──────────────────────────────────────────────────────────────
	{ id = "grande_combinasion",   name = "La Grande Combinasion",  tier = "Secret",    mul = 1.20, color = Color3.fromRGB(40, 40, 52) },
	{ id = "chimpanzini_spiderini",name = "Chimpanzini Spiderini",  tier = "Secret",    mul = 1.00, color = Color3.fromRGB(52, 40, 60) },
}

-- id -> entry, and tier -> { entries }
Brainrots.ById = {}
Brainrots.ByTier = {}

for _, entry in ipairs(Brainrots.List) do
	Brainrots.ById[entry.id] = entry
	local bucket = Brainrots.ByTier[entry.tier]
	if not bucket then
		bucket = {}
		Brainrots.ByTier[entry.tier] = bucket
	end
	table.insert(bucket, entry)
end

function Brainrots.get(id)
	return Brainrots.ById[id]
end

return Brainrots
