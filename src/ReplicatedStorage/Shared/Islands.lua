--[[
	Islands
	The sky islands, declared rather than built.

	One entry per island. IslandService turns an entry into geometry, so adding
	the second island is a table entry and a game module, not a modelling
	session -- which is the whole reason this is a spec and not just code inside
	the builder.

	THEY ARE NOT THE GROUND'S ART STYLE, deliberately. The street is a bright
	blocky suburb; up here is faceted low-poly at dusk, cold blue rock and dark
	conifers lit by neon. Climbing should feel like arriving somewhere else,
	and a floating island that matched the town below would just read as more
	town. The altitude lighting on the client is the other half of that.

	ALTITUDE IS NOT THE GATE. Every island sits under Config.FlightCeiling and
	anyone with a jetpack can reach any of them; what stops you walking into
	the third island on your first flight is the SEAL it asks for, earned on the
	one below. See the note on Config.JetpackCost.
]]

local Islands = {}

--[[
	Sited directly over the launch pad. The pad then reads as pointing at it --
	you stand on the ring, look up, and the destination is the thing overhead.
	That is worth more than spreading the islands prettily across the sky,
	because the first question a new jetpack owner has is "where do I go".
]]
Islands.List = {
	{
		id = "plinko",
		name = "Plinko",
		blurb = "Drop the ball. Watch it decide.",

		center = Vector3.new(-70, 220, -50),
		radius = 56, -- walkable ground; the mountain ring sits outside this
		game = "plinko",

		--[[ What playing here drops. Fragments rather than the whole seal, so a
		     losing streak still moves you forward -- the release valve for a
		     player who is simply bad at this particular game. ]]
		seal = "plinko",
		sealFragments = 5,

		--[[ Cold blue rock, dark green conifers, amber neon. Each island gets
		     one accent so they can be told apart from the ground at a glance,
		     which is the only way the sky reads as a set of destinations
		     rather than a pile of rocks. ]]
		accent = Color3.fromRGB(255, 206, 64),
	},
}

Islands.ById = {}
for _, island in ipairs(Islands.List) do
	Islands.ById[island.id] = island
end

function Islands.get(id)
	return id and Islands.ById[id] or nil
end

--[[ The island whose ground a position is standing on, or nil for the sky. ]]
function Islands.at(position)
	for _, island in ipairs(Islands.List) do
		local flat = (position - island.center) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= island.radius + 12
			and math.abs(position.Y - island.center.Y) < 40 then
			return island
		end
	end
	return nil
end

return Islands
