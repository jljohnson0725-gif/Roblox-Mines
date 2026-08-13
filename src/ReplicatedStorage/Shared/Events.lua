--[[
	Events
	Server-wide timed modifiers. Everyone is in the same event at the same time,
	because "everybody piles in at once" is most of what makes an event an event.

	Per the design pillar, an event does NOT add a parallel system. It's a bag of
	multipliers over knobs that already exist:

		dropChanceMul   -- how OFTEN drops happen
		depthMul        -- amplifies the rarity climb (see below)
		variantDepthMul -- same, for variants
		tierMul         -- direct weight multiplier on named tiers
		variantMul      -- direct weight multiplier on named variants
		variantAdd      -- weight ADDED to a variant; the only way to surface an
		                   event-exclusive variant, since its base weight is 0
		                   and 0 x anything is still 0

	`depthMul` scales L (= log2 multiplier) rather than the growth exponents.
	That amplifies each tier's existing direction -- Common shrinks faster AND
	Secret grows faster -- which is what "rarities climb faster" should mean.
	Adding to the exponents instead would drag Common's 0.72 toward 1.0 and make
	commons MORE likely, which is backwards.

	Rarer event => better rewards, so `weight` runs inversely to strength.
]]

local Events = {}

Events.List = {
	{
		id = "lucky",
		name = "Lucky Streak",
		blurb = "Drops coming thick and fast",
		color = Color3.fromRGB(120, 235, 150),
		weight = 100,
		duration = 90,
		mods = { dropChanceMul = 1.7 },
	},
	{
		id = "golden",
		name = "Golden Hour",
		blurb = "Gold variants everywhere",
		color = Color3.fromRGB(255, 200, 62),
		weight = 78,
		duration = 90,
		mods = { variantMul = { Gold = 7 } },
	},
	{
		id = "rainbow",
		name = "Rainbow Rush",
		blurb = "Rainbow variants surging",
		color = Color3.fromRGB(255, 120, 200),
		weight = 44,
		duration = 80,
		mods = { variantMul = { Rainbow = 14, Diamond = 3 } },
	},
	{
		id = "winter",
		name = "Winter Freeze",
		blurb = "FROST variants — this event only",
		color = Color3.fromRGB(150, 240, 255),
		weight = 26,
		duration = 100,
		mods = {
			variantAdd = { Frost = 70 },
			variantMul = { Diamond = 4 },
		},
	},
	{
		id = "lava",
		name = "Lava Surge",
		blurb = "Lava variants pouring out",
		color = Color3.fromRGB(255, 92, 24),
		weight = 15,
		duration = 75,
		mods = { variantMul = { Lava = 28 } },
	},
	{
		id = "deep",
		name = "Deep Descent",
		blurb = "Rarity climbs far faster with depth",
		color = Color3.fromRGB(178, 96, 255),
		weight = 8,
		duration = 70,
		mods = { depthMul = 1.35, dropChanceMul = 1.2 },
	},
	{
		id = "cosmic",
		name = "Cosmic Alignment",
		blurb = "Galaxy variants — and Secrets within reach",
		color = Color3.fromRGB(126, 80, 255),
		weight = 3,
		duration = 60,
		mods = {
			variantMul = { Galaxy = 45 },
			depthMul = 1.5,
			variantDepthMul = 1.3,
		},
	},
}

Events.ById = {}
for _, event in ipairs(Events.List) do
	Events.ById[event.id] = event
end

function Events.get(id)
	return id and Events.ById[id] or nil
end

--[[ Modifier bag for an event id, or nil when nothing is running. ]]
function Events.modsFor(id)
	local event = Events.get(id)
	return event and event.mods or nil
end

--[[ Weighted pick. Rarer events are stronger, so this is the whole "chance". ]]
function Events.pick(rng)
	local total = 0
	for _, event in ipairs(Events.List) do
		total += event.weight
	end

	local roll = rng:NextNumber() * total
	for _, event in ipairs(Events.List) do
		roll -= event.weight
		if roll <= 0 then
			return event
		end
	end
	return Events.List[1]
end

return Events
