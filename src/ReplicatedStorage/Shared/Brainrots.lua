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

	--[[ From the 87-character pack. Dealt into tiers by largest remainder so
	     each tier keeps the share of the roster it already had -- DropTable
	     weights the TIER, but ByTier decides what landing on it can give you,
	     so changing the mix would silently reprice every tier. ]]
	{ id = "1x1x1x1",                      name = "1x1x1x1",                      tier = "Common",    mul = 1.11, color = Color3.fromRGB(99, 205, 159) },
	{ id = "agarrini_la_pallini",          name = "Agarrini La Pallini",          tier = "Common",    mul = 0.87, color = Color3.fromRGB(121, 92, 233) },
	{ id = "avocadini_guffo",              name = "Avocadini Guffo",              tier = "Common",    mul = 1.18, color = Color3.fromRGB(136, 177, 174) },
	{ id = "ballerino_lololo",             name = "Ballerino Lololo",             tier = "Common",    mul = 1.18, color = Color3.fromRGB(128, 134, 161) },
	{ id = "bambini_crostini",             name = "Bambini Crostini",             tier = "Common",    mul = 0.87, color = Color3.fromRGB(91, 151, 102) },
	{ id = "banana_dancana",               name = "Banana Dancana",               tier = "Common",    mul = 1.04, color = Color3.fromRGB(133, 89, 178) },
	{ id = "bananini_kittini",             name = "Bananini Kittini",             tier = "Common",    mul = 0.95, color = Color3.fromRGB(124, 79, 198) },
	{ id = "blueberrinni_octopusini",      name = "Blueberrinni Octopusini",      tier = "Common",    mul = 0.92, color = Color3.fromRGB(73, 101, 199) },
	{ id = "bobrito_bandito",              name = "Bobrito Bandito",              tier = "Common",    mul = 0.93, color = Color3.fromRGB(209, 177, 116) },
	{ id = "brri_brri_bicus_dicus",        name = "Brri Brri Bicus Dicus",        tier = "Common",    mul = 0.98, color = Color3.fromRGB(176, 94, 165) },
	{ id = "burbaloni_luliloli",           name = "Burbaloni Luliloli",           tier = "Common",    mul = 1.07, color = Color3.fromRGB(216, 222, 221) },
	{ id = "cachorrito_melonito",          name = "Cachorrito Melonito",          tier = "Common",    mul = 0.98, color = Color3.fromRGB(80, 155, 151) },
	{ id = "cacto_hipopotamo",             name = "Cacto Hipopotamo",             tier = "Common",    mul = 0.95, color = Color3.fromRGB(174, 131, 82) },
	{ id = "cavallo_virtuoso",             name = "Cavallo Virtuoso",             tier = "Uncommon",  mul = 0.87, color = Color3.fromRGB(112, 158, 85) },
	{ id = "chef_crabracadabra",           name = "Chef Crabracadabra",           tier = "Uncommon",  mul = 1.15, color = Color3.fromRGB(224, 104, 171) },
	{ id = "chicleteira_bicicleteira",     name = "Chicleteira Bicicleteira",     tier = "Uncommon",  mul = 0.92, color = Color3.fromRGB(139, 165, 225) },
	{ id = "chicleteirina_bicicleteirina", name = "Chicleteirina Bicicleteirina", tier = "Uncommon",  mul = 1.02, color = Color3.fromRGB(108, 226, 211) },
	{ id = "chillin_chili",                name = "Chillin Chili",                tier = "Uncommon",  mul = 1.20, color = Color3.fromRGB(180, 224, 75) },
	{ id = "cocofanto_elefanto",           name = "Cocofanto Elefanto",           tier = "Uncommon",  mul = 1.00, color = Color3.fromRGB(213, 191, 157) },
	{ id = "dragon_cannelloni",            name = "Dragon Cannelloni",            tier = "Uncommon",  mul = 1.00, color = Color3.fromRGB(132, 143, 109) },
	{ id = "esok_sekolah",                 name = "Esok Sekolah",                 tier = "Uncommon",  mul = 1.11, color = Color3.fromRGB(233, 89, 152) },
	{ id = "espresso_signora",             name = "Espresso Signora",             tier = "Uncommon",  mul = 0.87, color = Color3.fromRGB(91, 147, 89) },
	{ id = "fluri_flura",                  name = "Fluri Flura",                  tier = "Uncommon",  mul = 1.08, color = Color3.fromRGB(148, 201, 130) },
	{ id = "ganganzelli_trulala",          name = "Ganganzelli Trulala",          tier = "Uncommon",  mul = 1.00, color = Color3.fromRGB(181, 221, 161) },
	{ id = "gangster_footera",             name = "Gangster Footera",             tier = "Rare",      mul = 1.09, color = Color3.fromRGB(104, 228, 94) },
	{ id = "garamararam",                  name = "Garamararam",                  tier = "Rare",      mul = 1.08, color = Color3.fromRGB(229, 135, 194) },
	{ id = "girafa_celeste",               name = "Girafa Celeste",               tier = "Rare",      mul = 1.20, color = Color3.fromRGB(80, 141, 138) },
	{ id = "gorillo_watermelondrillo",     name = "Gorillo Watermelondrillo",     tier = "Rare",      mul = 1.01, color = Color3.fromRGB(128, 147, 103) },
	{ id = "illuminato_triangolo",         name = "Illuminato Triangolo",         tier = "Rare",      mul = 1.09, color = Color3.fromRGB(175, 155, 95) },
	{ id = "job_job_job_sahur",            name = "Job Job Job Sahur",            tier = "Rare",      mul = 0.97, color = Color3.fromRGB(71, 97, 85) },
	{ id = "karkerkar_kurkur",             name = "Karkerkar Kurkur",             tier = "Rare",      mul = 0.88, color = Color3.fromRGB(106, 203, 224) },
	{ id = "lerulerulerule",               name = "Lerulerulerule",               tier = "Rare",      mul = 1.10, color = Color3.fromRGB(214, 79, 86) },
	{ id = "lionel_cactuseli",             name = "Lionel Cactuseli",             tier = "Rare",      mul = 1.02, color = Color3.fromRGB(193, 84, 193) },
	{ id = "madudung",                     name = "Madudung",                     tier = "Rare",      mul = 1.09, color = Color3.fromRGB(194, 145, 98) },
	{ id = "matteo",                       name = "Matteo",                       tier = "Rare",      mul = 0.86, color = Color3.fromRGB(234, 158, 117) },
	{ id = "meowl",                        name = "Meowl",                        tier = "Epic",      mul = 1.17, color = Color3.fromRGB(192, 182, 202) },
	{ id = "noo_my_examen",                name = "Noo My Examen",                tier = "Epic",      mul = 0.91, color = Color3.fromRGB(220, 98, 141) },
	{ id = "nyannini_cattalini",           name = "Nyannini Cattalini",           tier = "Epic",      mul = 0.87, color = Color3.fromRGB(222, 172, 70) },
	{ id = "orcalero_orcala",              name = "Orcalero Orcala",              tier = "Epic",      mul = 1.01, color = Color3.fromRGB(185, 209, 96) },
	{ id = "pakrahmatmamat",               name = "Pakrahmatmamat",               tier = "Epic",      mul = 1.12, color = Color3.fromRGB(209, 183, 234) },
	{ id = "pakrahmatmatina",              name = "Pakrahmatmatina",              tier = "Epic",      mul = 1.08, color = Color3.fromRGB(226, 169, 90) },
	{ id = "pandaccini_bananini",          name = "Pandaccini Bananini",          tier = "Epic",      mul = 0.93, color = Color3.fromRGB(121, 169, 150) },
	{ id = "pipi_kiwi",                    name = "Pipi Kiwi",                    tier = "Epic",      mul = 0.92, color = Color3.fromRGB(118, 95, 114) },
	{ id = "pipi_potato",                  name = "Pipi Potato",                  tier = "Epic",      mul = 0.90, color = Color3.fromRGB(71, 93, 146) },
	{ id = "pot_hotspot",                  name = "Pot Hotspot",                  tier = "Legendary", mul = 1.03, color = Color3.fromRGB(80, 178, 175) },
	{ id = "quesadilla_crocodila",         name = "Quesadilla Crocodila",         tier = "Legendary", mul = 0.92, color = Color3.fromRGB(89, 229, 223) },
	{ id = "rhino_toasterino",             name = "Rhino Toasterino",             tier = "Legendary", mul = 1.10, color = Color3.fromRGB(220, 222, 205) },
	{ id = "six_seven",                    name = "Six Seven",                    tier = "Legendary", mul = 0.95, color = Color3.fromRGB(180, 201, 228) },
	{ id = "smurfo_gatto",                 name = "Smurfo Gatto",                 tier = "Legendary", mul = 1.09, color = Color3.fromRGB(214, 141, 222) },
	{ id = "strawberrelli_flamingelli",    name = "Strawberrelli Flamingelli",    tier = "Legendary", mul = 0.94, color = Color3.fromRGB(136, 119, 191) },
	{ id = "strawberry_elephant",          name = "Strawberry Elephant",          tier = "Legendary", mul = 1.13, color = Color3.fromRGB(110, 234, 210) },
	{ id = "swag_soda",                    name = "Swag Soda",                    tier = "Legendary", mul = 1.11, color = Color3.fromRGB(81, 130, 143) },
	{ id = "ta_ta_ta_ta_sahur",            name = "Ta Ta Ta Ta Sahur",            tier = "Legendary", mul = 0.90, color = Color3.fromRGB(182, 165, 196) },
	{ id = "talpa_di_fero",                name = "Talpa Di Fero",                tier = "Mythic",    mul = 0.87, color = Color3.fromRGB(104, 94, 198) },
	{ id = "tigroligre_frutonni",          name = "Tigroligre Frutonni",          tier = "Mythic",    mul = 0.88, color = Color3.fromRGB(106, 167, 180) },
	{ id = "tirilikalika_tirilikalako",    name = "Tirilikalika Tirilikalako",    tier = "Mythic",    mul = 0.98, color = Color3.fromRGB(120, 166, 86) },
	{ id = "torrtuginni_dragonfrutini",    name = "Torrtuginni Dragonfrutini",    tier = "Mythic",    mul = 0.93, color = Color3.fromRGB(71, 118, 170) },
	{ id = "tralaledon",                   name = "Tralaledon",                   tier = "Mythic",    mul = 0.87, color = Color3.fromRGB(197, 224, 167) },
	{ id = "tric_trac_barabum",            name = "Tric Trac Barabum",            tier = "Mythic",    mul = 0.97, color = Color3.fromRGB(205, 110, 117) },
	{ id = "triplito_tralaleritos",        name = "Triplito Tralaleritos",        tier = "Mythic",    mul = 1.04, color = Color3.fromRGB(103, 202, 176) },
	{ id = "trippi_troppi_troppa_trippa",  name = "Trippi Troppi Troppa Trippa",  tier = "Secret",    mul = 1.04, color = Color3.fromRGB(106, 103, 129) },
	{ id = "tung_sahur",                   name = "Tung Sahur",                   tier = "Secret",    mul = 1.13, color = Color3.fromRGB(173, 118, 158) },
	{ id = "w_or_l",                       name = "W Or L",                       tier = "Secret",    mul = 1.12, color = Color3.fromRGB(104, 102, 87) },
	{ id = "yess_my_examen",               name = "Yess My Examen",               tier = "Secret",    mul = 1.02, color = Color3.fromRGB(181, 131, 124) },
	{ id = "zibra_zubra_zibralini",        name = "Zibra Zubra Zibralini",        tier = "Secret",    mul = 1.15, color = Color3.fromRGB(182, 101, 108) },
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
