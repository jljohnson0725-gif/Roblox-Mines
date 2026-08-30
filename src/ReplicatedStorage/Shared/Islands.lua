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

	ALTITUDE IS NOT THE GATE, and never really was. Each island is reached by
	the thing that goes to it -- the Plinko ball to Plinko, the whistle to
	Racing -- and what stops you walking into the third island on your first
	visit is the SEAL it asks for, earned on the one below.

	This used to be a jetpack and a height limit, which only ever LOOKED like a
	gate: anyone who could fly could reach anything, and the seal was doing the
	work even then.
]]

local Islands = {}

--[[
	OFF TO ONE SIDE OF THE LAUNCH PAD, NOT OVER IT.

	Directly overhead was the first instinct -- the pad then reads as pointing
	at the island, and the first question a new ball owner has is "where do
	I go". It also meant that flying straight up from the pad drove you into
	the island's underside at 218 studs and stopped you dead, which reads as a
	height limit rather than as a solid object, because the
	thing blocking you is above your head where you cannot see it.

	Ninety-five studs of offset against a 56-stud radius leaves the climb clear
	while keeping the island filling the sky at about 66 degrees up from the
	pad -- still unmistakably the thing you are being pointed at. It also makes
	for a better arrival: you rise past the cliff edge and land on the rim,
	instead of punching up through the floor.
]]
Islands.List = {
	{
		id = "plinko",
		name = "Plinko",
		blurb = "Drop the ball. Watch it decide.",

		--[[ 550, up from 220. High enough that the climb is a journey rather than
		     a hop off the roof, and still well under Config.FlightCeiling (900) so
		     the ball is the way there -- Racing at 1150 is the one above the
		     ceiling, and that separation is what makes the mount the only way there. ]]
		center = Vector3.new(-165, 550, -50),
		--[[ Was 56, which made this read as a ledge with a machine on it rather
		     than a destination -- and put the treeline right at the edge of the
		     clearing, so the whole island was rim. At 110 it matches Racing's
		     footprint: the two chapters are the same KIND of place, and the first
		     one being a third the size said the opposite. ]]
		radius = 220, -- walkable ground; the mountain ring sits outside this
		--[[ THE CLEARING DOES NOT SCALE WITH THE ISLAND, and that is the whole
		     trick of this number. The board is 99 studs wide whatever the island
		     does, so the plaza wants to stay the size that fits a board -- about
		     106, the same few studs of margin the nine-bin machine had.
		
		     0.24 of 220 IS 105.6: the identical plaza it had at radius 110 and
		     clearing 0.48. Everything the island gained went into the rim, which
		     goes from 51 studs to 161. That is what makes the machine stop looking
		     oversized -- not shrinking it, but giving it somewhere to stand.
		
		     Racing wants 0.82 because a racetrack IS its island. Plinko is one
		     machine standing in a clearing, and now there is a great deal of
		     island around the clearing. ]]
		--[[ 0.66, up from 0.24. There are four machines now, on a ring 105
		     studs out, and the plaza has to hold all of them: a board is 74
		     wide, so its outer corner reaches 105 + 37 = 142. At 0.62 the plaza
		     was 136 and every machine hung six studs off the dirt onto the
		     grass. 0.66 of 220 is 145, which clears it. ]]
		clearing = 0.66,

		--[[
			SMOOTH. No terraces, no outcrops, no trees, no mushrooms, no
			scattered debris, and no surface facets -- just the disc and the
			plaza.

			The relief was built for an island with one machine standing in a
			clearing, where the rim was scenery you looked past. With four
			machines on a ring the whole top surface is the venue, and rock and
			trees in the middle of it are things to walk around rather than
			things to look at.

			A flag rather than a check on the id, so the next island that wants
			to be a floor says so itself.
		]]
		smooth = true,
		game = "plinko",

		--[[ What playing here drops. Fragments rather than the whole seal, so a
		     losing streak still moves you forward -- the release valve for a
		     player who is simply bad at this particular game.

		     Seal ids match island ids on purpose: the seal earned here is named
		     for the chapter that issues it, which is what lets a gate look up
		     the island it should name in its refusal.

		     The other half of the pair is `requires`, a seal id this island
		     demands before its game will run -- absent here, because nothing
		     gates the chapter you start in. Shared/Seals owns both rules. ]]
		seal = "plinko",
		sealFragments = 5,

		--[[ Cold blue rock, dark green conifers, amber neon. Each island gets
		     one accent so they can be told apart from the ground at a glance,
		     which is the only way the sky reads as a set of destinations
		     rather than a pile of rocks. ]]
		accent = Color3.fromRGB(255, 206, 64),
	},

	{
		id = "racing",
		name = "Brainrot Racing",
		blurb = "Summon one. Back it. Watch it run.",

		--[[
			ABOVE Config.FlightCeiling, and it is the first island that is.

			The note at the top of this file says altitude is not the gate, and
			for Plinko it isn't -- the seal is. This one breaks that on purpose,
			because its arrival IS the feature: you get here by summoning a
			brainrot and riding it, and a second route that quietly worked would
			make the mount a decoration. At 1150 nothing else reaches it --
			short, so the ride is the only way and nothing has to police it.

			Placed across the map from Plinko rather than above it, so the two
			read as separate destinations from the ground rather than a stack.
		]]
		center = Vector3.new(210, 1150, 120),

		--[[ Twice Plinko's radius: a race needs a straight worth watching, and
		     56 studs is a courtyard. 110 gives roughly 200 studs of track
		     inside the walkable ring. ]]
		radius = 110,

		--[[ A far bigger flat apron than the 0.52 default, because the thing
		     standing here is a track rather than a machine: 0.82 of the radius
		     gives about 180 studs of level ground to lay a straight on, inside
		     a 220-stud island. ]]
		clearing = 0.82,
		game = "racing",

		--[[ The seal Plinko issues is the key to this door -- the first time
		     the fragment loop actually gates anything. ]]
		requires = "plinko",

		--[[ Six rather than Plinko's five: a later chapter should cost more,
		     and the model puts a seal at about 58 races on the fastest field
		     against Plinko's 69 drops, so the two land in the same order. ]]
		seal = "racing",
		sealFragments = 6,

		--[[ Racing crimson against Plinko's amber -- the two islands have to be
		     tellable apart from the street at a glance, and they are the only
		     two things in the sky. ]]
		accent = Color3.fromRGB(255, 88, 104),
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
