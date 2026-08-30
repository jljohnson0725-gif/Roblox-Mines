--[[
	IslandService
	Turns an entry in Shared/Islands into an island you can stand on.

	BUILT FRESH, NOT CLONED FROM THE MAP. The first instinct was to reuse the
	town's own trees and houses for consistency, and it was wrong twice over:
	nothing in the imported map is named -- it is 973 anonymous Unions and 260
	anonymous Models, so there is nothing to clone BY -- and the look we are
	going for up here is a different one on purpose. Faceted cold rock and dark
	conifers, not a bright blocky suburb.

	EVERYTHING ANGULAR IS A ROTATED BOX. Roblox has no cone and no low-poly
	rock, so the faceted look comes from stacking boxes that shrink and turn as
	they rise. Three of them make a conifer, four make a mountain, and the
	turn between tiers is what stops them reading as a stack of crates. It is
	the cheapest convincing way to get this silhouette out of primitives, and
	it holds up because the reference style is itself all flat facets.

	SEEDED PER ISLAND, so every server builds the identical island. A player
	describing where something is has to be describing the same place you see.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local IslandService = {}

IslandService.built = {}

-- ── palette ─────────────────────────────────────────────────────────────────

local P = {
	grass = Color3.fromRGB(104, 190, 78),
	grassLit = Color3.fromRGB(138, 212, 98),
	grassDark = Color3.fromRGB(74, 156, 66),
	-- Well down from a natural tan: a light colour facing straight up under a
	-- bright sky blew out to near-white and read as poured concrete.
	dirt = Color3.fromRGB(178, 142, 96),
	dirtDark = Color3.fromRGB(150, 118, 78),

	rock = Color3.fromRGB(112, 124, 152),
	rockDark = Color3.fromRGB(82, 92, 122),
	rockDeep = Color3.fromRGB(62, 70, 100),
	snow = Color3.fromRGB(186, 200, 228),

	conifer = Color3.fromRGB(48, 104, 72),
	coniferDark = Color3.fromRGB(34, 80, 56),
	trunk = Color3.fromRGB(92, 66, 48),

	stone = Color3.fromRGB(92, 100, 126),
	roof = Color3.fromRGB(54, 118, 210),
	window = Color3.fromRGB(255, 208, 122),

	capRed = Color3.fromRGB(214, 62, 62),
	capSpot = Color3.fromRGB(244, 238, 228),
	stem = Color3.fromRGB(236, 226, 208),
}

-- ── primitives ──────────────────────────────────────────────────────────────

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanQuery = props.collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color
	p.Transparency = props.transparency or 0
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

local function cylinder(props, parent)
	local p = part(props, parent)
	p.Shape = Enum.PartType.Cylinder
	-- Cylinder parts lie along X, so standing one up is a quarter turn about Z
	p.CFrame = props.cframe * CFrame.Angles(0, 0, math.rad(90))
	return p
end

--[[
	A tapering stack: each tier smaller than the last and turned a little, so
	the silhouette breaks up instead of reading as a tower of boxes. This one
	helper is the mountains AND the trees; only the proportions differ.
]]
local function stack(opts, parent)
	local rng = opts.rng

	--[[
		Tier HEIGHT tapers along with width, which is what makes this a pyramid
		instead of a tower. Uniform tier heights put a full-height slab on top of
		a needle-thin apex, and the mountains came out as white-tipped spires --
		skyscrapers, not peaks.
	]]
	local fracs, total = {}, 0
	for tier = 1, opts.tiers do
		local t = (tier - 1) / math.max(opts.tiers - 1, 1)
		local f = 1 - t * opts.taper
		fracs[tier] = f
		total += f
	end

	local y = 0
	for tier = 1, opts.tiers do
		local t = (tier - 1) / math.max(opts.tiers - 1, 1)
		local width = opts.width * fracs[tier]
		local height = opts.height * (fracs[tier] / total) * rng:NextNumber(0.9, 1.1)

		part({
			name = opts.name or "Tier",
			size = Vector3.new(width, height, width),
			cframe = CFrame.new(opts.at + Vector3.new(0, y + height / 2, 0))
				* CFrame.Angles(
					math.rad(rng:NextNumber(-opts.lean, opts.lean)),
					math.rad(rng:NextNumber(0, 360)),
					math.rad(rng:NextNumber(-opts.lean, opts.lean))),
			color = t > (opts.capAt or 2) and opts.capColor or opts.color,
			collide = opts.collide,
		}, parent)

		-- tiers overlap slightly so no gap opens when one leans
		y += height * 0.80
	end
end

-- ── the island itself ───────────────────────────────────────────────────────

--[[ Fractions of the island radius, going down. The stepped inverted cone is
     the silhouette people actually see, because they arrive from below. ]]
local UNDERSIDE = {
	{ r = 0.97, h = 7, y = -5 },
	{ r = 0.84, h = 9, y = -12 },
	{ r = 0.66, h = 11, y = -21 },
	{ r = 0.45, h = 13, y = -32 },
	{ r = 0.21, h = 16, y = -45 },
}

--[[
	How far out anything scattered has to start.

	The apron radius plus a margin. Module-level rather than a local inside the
	ground builder, because the trees and mushrooms are scattered by their OWN
	functions -- the first version computed it in buildGround and every other
	builder saw nil, which took both islands down at boot rather than just
	misplacing a tree.
]]
local function apronRadius(island)
	local frac = island.clearing or 0.52
	return island.radius * frac * 1.12
end

--[[
	THE ISLAND HAS A FRONT NOW, and everything below is placed against it.

	It did not before, and that was the deepest fault in the place. Terraces,
	outcrops, conifers, mushrooms and debris were each `angle = i/count * 2pi`
	-- five independent rings of even scatter around a radially symmetric disc.
	Even density reads as TEXTURE: the eye files it as "the ground has rocks on
	it" in about half a second and stops looking, which is why 30 mesas, 59
	outcrops and 51 conifers still read as a bare platform. Adding more evenly
	scattered rock would have read as exactly the same thing.

	The bearing is not arbitrary. PlinkoService yaws the board 180 degrees, so
	its face looks along +Z; that is the side you are meant to arrive on and see
	the bins from. So +Z is the front: the arch goes there, the ground stays low
	and open there, and the terraces pile up BEHIND the machine instead, which
	turns a board parked in a field into a board standing on a stage.

	In this module's polar convention a point is
	`(cos(angle) * dist, y, sin(angle) * dist)`, so +Z is angle pi/2.
]]
local FRONT = math.pi / 2
local BACK = FRONT + math.pi

--[[ Shortest signed distance between two angles, in radians. Used to ask "how
     far round from the back is this?", which has to wrap correctly or the arc
     either side of -pi reads as the far side of the island. ]]
local function angleGap(a, b)
	local d = (a - b + math.pi) % (math.pi * 2) - math.pi
	return math.abs(d)
end

--[[
	An angle biased toward the BACK of the island.

	`weight` is the share that lands in the back arc; the rest is spread over
	everything else, so the front never becomes a hard empty wedge -- it just
	gets the thin end of the distribution. Returns the angle and how "back" it
	is (0 at the front, 1 at the back), which the caller uses to decide height.
]]
local function biasedAngle(rng, weight, arc)
	local angle
	if rng:NextNumber() < weight then
		angle = BACK + rng:NextNumber(-arc / 2, arc / 2)
	else
		angle = rng:NextNumber(0, math.pi * 2)
	end
	return angle, 1 - angleGap(angle, BACK) / math.pi
end

--[[
	SCATTER COUNTS, SCALED TO THE GROUND THEY HAVE TO COVER.

	Every count below -- thirteen trees, fourteen facets, eleven outcrops -- was
	tuned by eye on Plinko when it was 56 studs across. They are AREAL: they
	scatter over the ring between the clearing and the rim. Left fixed while the
	island doubles, the density falls by four and the place goes bald, which is
	the opposite failure to the one being fixed.

	SCALED OFF THE ANNULUS, NOT THE DISC, and the difference is the racing
	island. Racing is 110 studs of almost pure clearing -- 0.82 of it is
	racetrack, so its scatter ring is about nine studs wide. Scaling that by
	disc area would cram five times the conifers into a hoop. By annulus it
	comes out at 0.9x what it builds today, which is correct: nothing about
	that island changed.

	The exponent is how hard a given thing should follow the area. Ground skin
	takes it in full; sculpture takes a fraction, because twenty-seven conifers
	spread over a wide rim reads as woodland and seventy reads as the thicket
	this island is being rescued from.
]]
local BASE_RADIUS, BASE_CLEARING = 56, 0.52

local function annulusArea(radius, clearing)
	local inner = radius * clearing * 1.12
	return math.max(math.pi * (radius * radius - inner * inner), 1)
end

local BASE_AREA = annulusArea(BASE_RADIUS, BASE_CLEARING)

local function scatter(island, base, exponent)
	local area = annulusArea(island.radius, island.clearing or BASE_CLEARING)
	return math.max(1, math.floor(base * (area / BASE_AREA) ^ (exponent or 1) + 0.5))
end

local function buildGround(island, rng, root)
	local c, r = island.center, island.radius

	--[[ Everything scattered on this island has to keep off the apron, so the
	     apron's size is computed once here rather than where it is drawn. The
	     scatter used to start at a hardcoded 28-36 studs, which cleared a
	     58-stud clearing comfortably and put conifers in the middle of a
	     180-stud one the moment an island asked for a bigger pad. ]]
	local clearSize = r * 2 * (island.clearing or 0.52)
	local keepOut = apronRadius(island)

	-- the slab you stand on
	cylinder({
		name = "Ground",
		size = Vector3.new(5, r * 2, r * 2),
		cframe = CFrame.new(c),
		color = P.grass,
		collide = true,
	}, root)

	--[[ Facets: flat slabs at slightly different heights and angles in two
	     greens. Cheaper than real low-poly terrain and, from standing height,
	     indistinguishable from it. ]]
	--[[
		HEIGHTS ARE STAGGERED, and that is not cosmetic. Every facet used to sit
		at exactly 2.2 with the same 1.6 thickness, so all fourteen top faces
		were coplanar -- and two coplanar faces flicker against each other as
		the camera moves, because the depth buffer cannot decide which is in
		front. Same fault the wheel had at its hub. A hundredth of a stud
		between them is invisible and settles it.

		THE STAGGER RUNS 1..14, NOT i % 7. It was the modulo, over fourteen
		facets, which handed every height out exactly TWICE -- so the fix that
		was supposed to separate them left seven coplanar pairs instead of
		fourteen coplanar faces, and the two that happened to be drawn in
		different greens carried on flickering. A stagger that wraps is not a
		stagger. Fourteen steps of 0.014 spans a fifth of a stud, still far
		below anything the eye picks up on a walking surface.
	]]
	for i = 1, (island.smooth and 0 or scatter(island, 14)) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(keepOut, math.max(keepOut + 1, r * 0.82))
		local size = rng:NextNumber(14, 30)
		part({
			name = "Facet",
			size = Vector3.new(size, 1.6, size * rng:NextNumber(0.7, 1.3)),
			cframe = CFrame.new(c + Vector3.new(
				math.cos(angle) * dist, 2.2 + i * 0.014,
				math.sin(angle) * dist))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			color = rng:NextNumber() < 0.5 and P.grassLit or P.grassDark,
			collide = true,
		}, root)
	end

	--[[
		The flat apron the island's game sits on.

		SCALED OFF THE RADIUS, not fixed. It was hardcoded at 58 studs, which
		happened to be right for Plinko and stayed 58 when the racing island
		arrived at twice the radius -- leaving a machine-sized pad on an island
		built to hold a racetrack.

		0.52 reproduces Plinko's 58 exactly at its radius of 56, so the island
		that was tuned by eye is untouched. An island whose game needs more room
		asks for it with `clearing`, rather than every island paying for the
		greediest one.
	]]
	cylinder({
		name = "Clearing",
		size = Vector3.new(1.4, clearSize, clearSize),
		cframe = CFrame.new(c + Vector3.new(0, 3.34, 0)),
		color = P.dirt,
		collide = true,
	}, root)
	cylinder({
		name = "ClearingRim",
		-- the same 1.10 proportion the hand-tuned pair had
		size = Vector3.new(1.2, clearSize * 1.103, clearSize * 1.103),
		cframe = CFrame.new(c + Vector3.new(0, 2.9, 0)),
		color = P.dirtDark,
		collide = true,
	}, root)

	-- the stepped cone underneath
	for _, step in ipairs(UNDERSIDE) do
		cylinder({
			name = "Underside",
			size = Vector3.new(step.h, r * 2 * step.r, r * 2 * step.r),
			cframe = CFrame.new(c + Vector3.new(0, step.y, 0)),
			color = step.r > 0.6 and P.rockDark or P.rockDeep,
		}, root)
	end

	--[[ Shards hanging off the cone. Without these the underside is a neat
	     wedding cake; rock is not neat, and this is the face of the island
	     that everyone flies up through. ]]
	for i = 1, scatter(island, 16, 0.7) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local depth = rng:NextNumber(6, 40)
		local dist = r * (1 - depth / 60) * rng:NextNumber(0.5, 0.95)
		part({
			name = "Shard",
			size = Vector3.new(rng:NextNumber(5, 13), rng:NextNumber(8, 22),
				rng:NextNumber(5, 13)),
			cframe = CFrame.new(c + Vector3.new(
				math.cos(angle) * dist, -depth, math.sin(angle) * dist))
				* CFrame.Angles(math.rad(rng:NextNumber(-35, 35)),
					math.rad(rng:NextNumber(0, 360)),
					math.rad(rng:NextNumber(-35, 35))),
			color = rng:NextNumber() < 0.4 and P.rock or P.rockDeep,
		}, root)
	end
end

--[[
	OUTCROPS, NOT A MOUNTAIN RANGE. The mountains in the reference are the far
	horizon behind a village -- scenery at a distance. On a 56-stud disc there is
	no distance, so peaks at that scale become a wall you stand inside: the first
	attempt walled the clearing off entirely, the second became a blue skyline
	taller than the island is wide. Rock at head-to-three-storey height gives the
	same faceted language without swallowing the place.
]]
local function buildOutcrops(island, rng, root)
	local c, r = island.center, island.radius
	--[[
		CLUSTERED, NOT SPACED. This was `angle = i/count * 2pi`, which put sixty
		near-identical rocks every twenty studs around a 1,380-stud rim -- an
		even border, which the eye reads as a frame and edits out entirely. The
		gaps are what make the clumps visible: the same sixty rocks in a dozen
		groups is a landscape, and evenly spread they are a picket fence.
	]]
	local count = scatter(island, 11, 0.55)
	local clusters = math.max(3, math.floor(count / 5))
	local seeds = {}
	for i = 1, clusters do
		seeds[i] = rng:NextNumber(0, math.pi * 2)
	end
	for i = 1, count do
		local seed = seeds[(i - 1) % clusters + 1]
		local angle = seed + rng:NextNumber(-0.22, 0.22)
		local dist = math.max(r * rng:NextNumber(0.80, 0.98), apronRadius(island) + 6)
		stack({
			name = "Outcrop",
			rng = rng,
			at = c + Vector3.new(math.cos(angle) * dist, 1, math.sin(angle) * dist),
			tiers = 3,
			width = rng:NextNumber(7, 15),
			height = rng:NextNumber(9, 26),
			taper = 0.72,
			lean = 10,
			color = rng:NextNumber() < 0.4 and P.rock or P.rockDark,
			capColor = P.rockDeep,
			capAt = 2, -- no snow at this size; a capped 20-stud rock reads as litter
			collide = true,
		}, root)
	end
end

--[[
	TERRACES -- the thing that stops this reading as a disc.

	This is the one piece borrowed straight from the reference island. That
	island is not a plane with scenery on it: it is a dozen big terrain chunks
	at different heights with flat tops you can stand on, and that vertical
	variation is most of why it reads as a place rather than a platform. A flat
	slab with trees around the edge reads as a platform no matter how wide you
	make it, which is why growing the radius alone would not have fixed the
	complaint.

	ADDITIVE, because it has to be. Roblox cannot cut a plaza out of a slab
	without CSG, so the relief is built UP around the clearing rather than sunk
	into it -- and they step TALLER the further out they sit, which turns the
	middle of the island into a shallow bowl with the machine at the bottom.
	Arriving means flying up past a raised rim and dropping in, which is a
	better entrance than landing on a pancake.

	Two parts each: a rock body and a grass cap, so the top you stand on matches
	the ground rather than looking like somebody left a boulder there.
]]
local function buildTerraces(island, rng, root)
	local c, r = island.center, island.radius
	local keep = apronRadius(island)
	local span = r - keep

	--[[ An island whose clearing eats it has nowhere to put these. Racing is
	     0.82 clearing -- a nine-stud rim -- and a forty-stud mesa dropped into
	     that would sit half on the racetrack and half off the edge. Better to
	     build none than to build one in the way. ]]
	if span < 30 then
		return
	end

	local count = scatter(island, 3, 0.75)
	for i = 1, count do
		--[[ 70% land in a 140-degree arc behind the machine. The other 30% keep
		     the rim from having an obviously bald side -- a hard empty wedge
		     reads as unfinished, a thin one reads as a clearing. ]]
		local angle, backness = biasedAngle(rng, 0.7, math.rad(140))

		--[[ SIZE FIRST, THEN DISTANCE, and that order is the fix for a mesa that
		     hung sixteen studs off the edge of the island on the first build.
		     A turned box reaches its half-DIAGONAL, not its half-width -- a
		     40-wide chunk centred 100 studs out has a corner at 134 -- so the
		     distance has to be chosen against a reach that is already known. ]]
		--[[ VARIETY IS THE WHOLE POINT OF THESE NUMBERS. The first pass drew
		     every mesa from one recipe -- 22 to 42 wide, always two steps at a
		     fixed 62/50 split -- so ten of them read as one asset repeated
		     rather than as terrain. The reference island runs from chunks you
		     step over to chunks you walk around, and that range is most of why
		     it reads as landscape.

		     So the footprint now spans 14 to 52 (3.7x rather than 1.9x), the
		     depth ratio is wider, and the STEP COUNT follows the height: a low
		     one is a single shelf, a tall one is a three-tier hillside. ]]
		local w = math.min(rng:NextNumber(14, 52), span * 0.8)
		local d = w * rng:NextNumber(0.6, 1.5)
		local reach = math.sqrt((w / 2) ^ 2 + (d / 2) ^ 2)

		local near = keep + span * 0.2
		local dist = rng:NextNumber(near, math.max(near, r - reach))

		--[[ Height from how far out it sits AND how far round the back it is.

		     The distance term makes the bowl a bowl. The `backness` term is the
		     amphitheatre: a terrace behind the board can reach ~55 studs and
		     tower over the 73-stud machine, while one on the arrival side stays
		     at 3-10 and is something you step over. That difference is what
		     gives a radially symmetric disc a front and a back, and it costs
		     nothing -- the same thirty terraces, dealt unevenly.

		     The random term stays wide, because a rim of near-identical heights
		     is the other half of looking stamped out. ]]
		local lift = 3 + ((dist - keep) / span) * 15
			+ backness * backness * 34
			+ rng:NextNumber(-2.5, 6)
		local turn = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local at = c + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))

		--[[ STEPS, NOT A BLOCK. A single box tall enough to matter reads from
		     standing height as a flat-faced wall dropped on the grass -- which
		     is exactly what the very first build looked like. Each tier is a
		     rock body with a grass cap, so the surface you walk on matches the
		     ground rather than looking like somebody left a boulder there.

		     Every tier is nudged OUTWARD rather than centred. Concentric reads
		     as a wedding cake; offset reads as a hillside with shelves cut into
		     the near face, and it is the near face you stand under. ]]
		local steps = lift < 9 and 1 or (lift < 17 and 2 or 3)
		local CAP = 1.4

		local y = 2.5
		local tierW, tierD = w, d
		local tierAt = at
		for tier = 1, steps do
			--[[ Each tier takes a random share of what height is left, so two
			     three-step mesas do not have their shelves at the same
			     fractions. The last one takes everything remaining. ]]
			local remaining = lift - (y - 2.5)
			local h = tier == steps and remaining
				or remaining * rng:NextNumber(0.4, 0.62)
			if h < 1.2 then
				break
			end

			part({
				name = "Terrace",
				size = Vector3.new(tierW, h, tierD),
				cframe = CFrame.new(tierAt + Vector3.new(0, y + h / 2, 0)) * turn,
				color = rng:NextNumber() < 0.45 and P.rock or P.rockDark,
				collide = true,
			}, root)
			part({
				name = "TerraceTop",
				size = Vector3.new(tierW * 0.96, CAP, tierD * 0.96),
				cframe = CFrame.new(tierAt + Vector3.new(0, y + h + CAP / 2, 0)) * turn,
				color = rng:NextNumber() < 0.5 and P.grassLit or P.grassDark,
				collide = true,
			}, root)

			local shrink = rng:NextNumber(0.55, 0.76)
			tierAt = tierAt + outward * (tierW * rng:NextNumber(0.08, 0.2))
			tierW, tierD = tierW * shrink, tierD * shrink
			y += h + CAP
		end
	end
end

--[[
	THE KEYHOLE -- a lit arch on the arrival bearing, straddling the rim.

	Arriving used to be "clear the edge somewhere on 1,380 studs of
	circumference and land wherever". Nothing said which way to fly up, where to
	come down, or which way to face when you got there, and a good share of
	arrivals met the BACK of the board. One lit opening on the front bearing
	turns that into a door: it is the only lit thing that is not the beacon, you
	can see it during the climb, you fly through it, and you land in a known
	place already facing the machine.

	NEON ONLY, NO POINTLIGHT. The beacon's own note records what happened when
	something up here was given a big Range: it floodlit the island amber and
	made the ground immune to every global lighting change. Neon emits without
	lighting anything, which is exactly what a distant marker wants.

	The footings deliberately overhang the rim, because an arch standing safely
	inland reads as a monument and one hanging over the drop reads as a gate.
]]
local function buildKeyhole(island, rng, root)
	local c, r = island.center, island.radius
	local at = c + Vector3.new(math.cos(FRONT) * r * 0.99, 0,
		math.sin(FRONT) * r * 0.99)
	local across = Vector3.new(math.cos(FRONT + math.pi / 2), 0,
		math.sin(FRONT + math.pi / 2))

	local span = 34 -- half the clear opening; wide enough to fly without aiming
	local legH = 52

	for _, side in ipairs({ -1, 1 }) do
		local foot = at + across * (span * side)
		--[[ Canted toward each other so the pair reads as an arch rather than
		     as two towers that happen to be near one another. ]]
		stack({
			name = "KeyholeLeg",
			rng = rng,
			at = foot + Vector3.new(0, 2, 0),
			tiers = 4,
			width = 15,
			height = legH,
			taper = 0.42,
			lean = 4,
			color = P.rockDark,
			capColor = P.rock,
			capAt = 3,
			collide = true,
		}, root)
	end

	--[[ Three slabs rather than one beam: a single box spanning 68 studs reads
	     as a girder, and nothing else on this island has a straight edge that
	     long. Broken into three turned pieces it reads as cut stone. ]]
	for i = -1, 1 do
		part({
			name = "KeyholeStone",
			size = Vector3.new(30, 9, 15),
			cframe = CFrame.new(at + across * (i * 24) + Vector3.new(0, legH + 2, 0))
				* CFrame.Angles(0, 0, math.rad(i * 7)),
			color = i == 0 and P.rock or P.rockDark,
			collide = true,
		}, root)
	end

	-- the inlay: what makes it findable from 500 studs below at dusk
	for i = -2, 2 do
		part({
			name = "KeyholeInlay",
			size = Vector3.new(9, 1.6, 2.2),
			cframe = CFrame.new(at + across * (i * 13)
				+ Vector3.new(0, legH - 2.6, 0)),
			color = island.accent,
			material = Enum.Material.Neon,
		}, root)
	end
end

--[[
	FIVE BRAZIERS, ONE PER SADDLE PIECE, standing where the player actually is.

	Everything built to dress this island sat 59 studs out or further, behind
	the player, while the space they occupy -- the plaza and the face of the
	machine -- was bare dirt by construction. These go INSIDE that band, on the
	plaza rim, in the walked space.

	THEY ARE LIT PER PLAYER, and that is the whole trick. The island is one
	shared object and a saddle count is per-profile, so a server-lit brazier
	would show your neighbour's progress. Instead the server builds all five
	dark and UI/Braziers reveals flame N locally for each piece the local player
	holds -- Transparency and Color set on a client are not replicated, so every
	player sees their own count on the same geometry. That is a thing the wheel
	face could not do, because a wheel has to be the same object for everyone
	watching one spin; a brazier only has to be right for the person reading it.

	Sited on the FRONT half so the walk in from the arch passes them in order.
]]
local function buildBraziers(island, rng, root)
	local c = island.center
	local ring = apronRadius(island) * 0.94

	for i = 1, 5 do
		--[[ Spread across the front 200 degrees rather than the full circle, so
		     they frame the approach instead of surrounding the machine. ]]
		local angle = FRONT + math.rad(-100 + (i - 1) * 50)
		local at = c + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		local turn = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)

		local brazier = Instance.new("Model")
		brazier.Name = "Brazier" .. i
		brazier.Parent = root

		-- plinth: three boxes tapering upward, each turned off the last
		for tier = 0, 2 do
			part({
				name = "Plinth",
				size = Vector3.new(7 - tier * 1.4, 3, 7 - tier * 1.4),
				cframe = CFrame.new(at + Vector3.new(0, 2.5 + tier * 3, 0))
					* turn * CFrame.Angles(0, math.rad(tier * 22), 0),
				color = tier == 2 and P.rock or P.rockDark,
				collide = true,
			}, brazier)
		end

		-- the bowl: four slabs leaning outward make a faceted cup
		for side = 0, 3 do
			part({
				name = "Bowl",
				size = Vector3.new(6, 3.4, 1.2),
				cframe = CFrame.new(at + Vector3.new(0, 12, 0))
					* turn
					* CFrame.Angles(0, math.rad(side * 90), 0)
					* CFrame.new(0, 0, 2.6)
					* CFrame.Angles(math.rad(-24), 0, 0),
				color = P.rockDark,
				collide = true,
			}, brazier)
		end

		part({
			name = "Ash",
			size = Vector3.new(4.6, 0.8, 4.6),
			cframe = CFrame.new(at + Vector3.new(0, 11.6, 0)) * turn,
			color = P.rockDeep,
		}, brazier)

		--[[ Flame as three shrinking neon boxes, each turned off the one below
		     -- the same rotated-box language as everything else here, and it
		     survives dusk in a way a particle sheet would not. Built hidden;
		     UI/Braziers is what reveals it, per player. ]]
		for tier = 1, 3 do
			local flame = part({
				name = "Flame",
				size = Vector3.new(4.2 - tier * 0.9, 3.6 - tier * 0.7, 4.2 - tier * 0.9),
				cframe = CFrame.new(at + Vector3.new(0, 12.6 + tier * 1.9, 0))
					* turn * CFrame.Angles(0, math.rad(tier * 34), 0),
				color = island.accent,
				material = Enum.Material.Neon,
				transparency = 1,
			}, brazier)
			flame:SetAttribute("Tier", tier)
		end

		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = island.accent
		--[[ Range 34, not the beacon's mistake. Short enough to be a pool you
		     stand in rather than a floodlight that repaints the island. ]]
		light.Range = 34
		light.Brightness = 0
		light.Enabled = false
		light.Parent = brazier:FindFirstChild("Ash")
	end
end

--[[ NARROW. A conifer is about four times taller than it is wide. The first
     pass was nearly square and read as a stack of crates from standing height,
     which is the only height that matters here. ]]
local function buildTrees(island, rng, root)
	local keep = apronRadius(island)
	local c, r = island.center, island.radius
	--[[ Thirteen, not thirty. Thirty closed the island into a thicket you
	     could not see the machine or the sky through, which is the opposite of
	     what a clearing on a floating island is for.

	     Scaled at 0.45 rather than in full, and that exponent is the whole
	     answer to "cluttered with trees". A bigger island needs more of them or
	     it looks bald, but following the area exactly would have taken thirteen
	     to sixty-five and rebuilt the thicket at four times the size. At 0.45 it
	     lands near twenty-seven, spread over a rim three times as wide -- so the
	     island gains woodland and loses the wall.

	     AND THEY START FURTHER OUT. The old inner bound was the apron itself, so
	     the first trunk stood exactly where the clearing stopped. A band of open
	     grass between the plaza and the treeline is what makes the plaza read as
	     a clearing IN something rather than as the whole island. ]]
	local treeline = keep + r * 0.12
	for i = 1, scatter(island, 13, 0.45) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(math.max(36, treeline), math.max(treeline + 1, r * 0.9))
		local at = c + Vector3.new(math.cos(angle) * dist, 2, math.sin(angle) * dist)
		local scale = rng:NextNumber(0.8, 1.35)

		part({
			name = "Trunk",
			size = Vector3.new(1.3 * scale, 5 * scale, 1.3 * scale),
			cframe = CFrame.new(at + Vector3.new(0, 2.5 * scale, 0)),
			color = P.trunk,
		}, root)

		stack({
			name = "Canopy",
			rng = rng,
			at = at + Vector3.new(0, 4 * scale, 0),
			tiers = 5,
			width = 5.6 * scale,
			height = 24 * scale,
			taper = 0.9,
			lean = 0, -- upright; a leaning conifer just looks broken
			color = rng:NextNumber() < 0.5 and P.conifer or P.coniferDark,
			capColor = P.coniferDark,
			capAt = 2,
		}, root)
	end
end

local function buildMushrooms(island, rng, root)
	local keep = apronRadius(island)
	local c, r = island.center, island.radius
	--[[
		0.25, and this is the single biggest budget decision on the island.

		At 0.5 this built 245 mushrooms. Measured on the live island that was
		980 parts -- 490 Spot, 245 Cap, 245 Stem -- which is FORTY-SIX PERCENT
		of the island's entire 2137-part budget spent on ankle-height litter, in
		a band starting 59 studs out that the player crosses once and never
		looks down at. Sixty percent of the island was below knee height and the
		silhouette got the remainder.

		At 0.25 it is about 50 mushrooms, ~200 parts, and the ~780 parts freed
		pay for the braziers, the keyhole and the terrace bias below with room
		left over. Nothing about the island reads as emptier: the litter was
		never legible as litter, only as budget.
	]]
	for i = 1, scatter(island, 24, 0.25) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(math.max(28, keep), math.max(keep + 1, r * 0.86))
		local base = c + Vector3.new(math.cos(angle) * dist, 3, math.sin(angle) * dist)

		for j = 1, rng:NextInteger(1, 3) do -- clusters, not lone pins
			local offset = j == 1 and Vector3.zero
				or Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			-- ankle height; at the old scale the caps came up to a player's waist
			local s = rng:NextNumber(0.45, 1.0) * (j == 1 and 1 or 0.7)
			local at = base + offset

			part({
				name = "Stem",
				size = Vector3.new(0.45 * s, 1.5 * s, 0.45 * s),
				cframe = CFrame.new(at + Vector3.new(0, 0.75 * s, 0)),
				color = P.stem,
			}, root)
			local cap = part({
				name = "Cap",
				size = Vector3.new(2.2 * s, 1.0 * s, 2.2 * s),
				cframe = CFrame.new(at + Vector3.new(0, 1.85 * s, 0)),
				color = P.capRed,
			}, root)
			-- the white spots are the whole reason these read as mushrooms
			for _ = 1, 2 do
				part({
					name = "Spot",
					size = Vector3.new(0.5 * s, 0.26 * s, 0.5 * s),
					cframe = cap.CFrame * CFrame.new(
						rng:NextNumber(-0.65, 0.65) * s, 0.5 * s,
						rng:NextNumber(-0.65, 0.65) * s),
					color = P.capSpot,
				}, root)
			end
		end
	end
end

local function buildCottage(island, rng, root)
	local c, r = island.center, island.radius
	--[[ Sited by ANGLE at a distance that clears the apron, rather than at a
	     fixed fraction of the radius. At -0.52r/+0.34r it stood 65 studs out,
	     which is a corner of the island on Plinko and the middle of the
	     racetrack on an island with a wide pad. ]]
	local out = math.max(r * 0.62, apronRadius(island) + 14)
	local at = c + Vector3.new(-out * 0.84, 3, out * 0.55)
	local face = CFrame.new(at) * CFrame.Angles(0, math.rad(38), 0)

	part({ name = "Walls", size = Vector3.new(16, 11, 13),
		cframe = face * CFrame.new(0, 5.5, 0), color = P.stone, collide = true }, root)

	-- roof as two leaning slabs: a real gable out of two boxes
	for _, side in ipairs({ -1, 1 }) do
		part({ name = "Roof", size = Vector3.new(11, 1.4, 15),
			cframe = face * CFrame.new(side * 4.4, 13.4, 0)
				* CFrame.Angles(0, 0, math.rad(side * 42)),
			color = P.roof }, root)
	end

	part({ name = "Door", size = Vector3.new(3.4, 5.4, 0.6),
		cframe = face * CFrame.new(0, 2.7, 6.6), color = P.trunk }, root)

	for _, spot in ipairs({ Vector3.new(-5, 6.4, 6.6), Vector3.new(5, 6.4, 6.6) }) do
		local w = part({ name = "Window", size = Vector3.new(2.6, 2.6, 0.5),
			cframe = face * CFrame.new(spot.X, spot.Y, spot.Z),
			color = P.window, material = Enum.Material.Neon }, root)
		local glow = Instance.new("PointLight")
		glow.Color = P.window
		glow.Brightness = 1.4
		glow.Range = 18
		glow.Parent = w
	end
end

--[[
	The landmark. A faceted neon ring hanging over the island, big enough to be
	the thing you notice from the street -- which is the entire job, because a
	destination nobody can see from the ground is not a destination.
]]
local function buildBeacon(island, rng, root)
	local c = island.center
	--[[ 104, not 64. The Plinko machines top out at y+79 -- straight through a
	     ring placed for a much shorter board. The 9-stud neon core ended up
	     hanging in front of the peg field, which from the front reads as a
	     giant yellow blob sitting on the board. Anything sited over the
	     clearing has to clear whatever is standing in it.

	     Measured, not derived: the row count has changed twice and the height
	     did not move the way either change predicted (dropping to 14 rows made
	     the board shorter and the machine no taller, because the plinth and
	     console set the top, not the peg field). 104 leaves 25 studs. ]]
	local at = c + Vector3.new(0, 104, 0)
	-- high and wide enough to clear the outcrops and read from the street
	local segments, ringRadius = 16, 32

	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local nextAngle = ((i + 1) / segments) * math.pi * 2
		local a = at + Vector3.new(math.cos(angle) * ringRadius, 0,
			math.sin(angle) * ringRadius)
		local b = at + Vector3.new(math.cos(nextAngle) * ringRadius, 0,
			math.sin(nextAngle) * ringRadius)
		-- one straight segment per side: a polygon, not a circle, to match the
		-- faceted language of everything else up here
		part({
			name = "RingSegment",
			size = Vector3.new(2.4, 2.4, (b - a).Magnitude + 0.8),
			cframe = CFrame.lookAt((a + b) / 2, b),
			color = island.accent,
			material = Enum.Material.Neon,
		}, root)
	end

	local core = part({
		name = "BeaconCore",
		size = Vector3.new(9, 9, 9),
		cframe = CFrame.new(at) * CFrame.Angles(math.rad(35), math.rad(35), 0),
		color = island.accent,
		material = Enum.Material.Neon,
	}, root)
	--[[
		SHORT RANGE, and this matters more than it looks. At range 120 this one
		light reached the whole island and floodlit it amber -- which made the
		ground immune to every global lighting change, because it was not being
		lit by the sun at all. Hours can disappear into retuning Lighting while
		a single PointLight quietly overrides the lot.

		The ring is Neon, so it glows on its own and needs no help to read from
		the street. The light is only local spill, and at 64 studs up a range of
		30 never touches the ground.
	]]
	local light = Instance.new("PointLight")
	light.Color = island.accent
	light.Brightness = 2
	light.Range = 30
	light.Parent = core

	-- rocks caught in its pull, which is what makes the ring read as doing
	-- something rather than just hanging there
	for i = 1, 10 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(ringRadius * 0.6, ringRadius * 1.7)
		part({
			name = "OrbitRock",
			size = Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(3, 7),
				rng:NextNumber(3, 8)),
			cframe = CFrame.new(at + Vector3.new(math.cos(angle) * dist,
				rng:NextNumber(-16, 14), math.sin(angle) * dist))
				* CFrame.Angles(math.rad(rng:NextNumber(0, 360)),
					math.rad(rng:NextNumber(0, 360)), 0),
			color = P.rockDeep,
		}, root)
	end
end

--[[ Loose rock drifting around the island, so it sits in a field of debris
     rather than alone in clean air. ]]
local function buildDebris(island, rng, root)
	local c, r = island.center, island.radius
	for i = 1, scatter(island, 14, 0.5) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = r * rng:NextNumber(1.15, 1.9)
		part({
			name = "Debris",
			size = Vector3.new(rng:NextNumber(4, 14), rng:NextNumber(3, 11),
				rng:NextNumber(4, 14)),
			cframe = CFrame.new(c + Vector3.new(math.cos(angle) * dist,
				rng:NextNumber(-40, 26), math.sin(angle) * dist))
				* CFrame.Angles(math.rad(rng:NextNumber(0, 360)),
					math.rad(rng:NextNumber(0, 360)),
					math.rad(rng:NextNumber(0, 360))),
			color = rng:NextNumber() < 0.5 and P.rockDark or P.rockDeep,
		}, root)
	end
end

function IslandService.build(island)
	local existing = Workspace:FindFirstChild("Island_" .. island.id)
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "Island_" .. island.id
	root.Parent = Workspace

	-- Seeded from the id, so the island is identical on every server.
	local seed = 0
	for i = 1, #island.id do
		seed = seed * 31 + string.byte(island.id, i)
	end
	local rng = Random.new(seed)

	buildGround(island, rng, root)
	--[[ A smooth island is a floor, not a landscape -- see Islands.lua. The
	     ground and the plaza are still built; everything that stands up out of
	     them is not. ]]
	if not island.smooth then
		buildTerraces(island, rng, root)
		buildOutcrops(island, rng, root)
	end
	--[[ Only where a game's progress is actually tracked. Racing has no saddle
	     to collect, so five dark braziers there would be furniture that never
	     lights -- and an arch on an island of pure racetrack has nothing to
	     straddle. Keyed off the island declaring a seal, so island three gets
	     both the day it declares one. ]]
	if island.seal then
		buildKeyhole(island, rng, root)
		buildBraziers(island, rng, root)
	end
	if not island.smooth then
		buildTrees(island, rng, root)
		buildMushrooms(island, rng, root)
		buildCottage(island, rng, root)
		buildDebris(island, rng, root)
	end
	--[[ The beacon stays either way. It is not decoration -- it is how you find
	     the island from the street, and a smooth island needs it more, not
	     less, for having nothing else tall on it. ]]
	buildBeacon(island, rng, root)

	IslandService.built[island.id] = root
	return root
end

--[[
	THROWING THE BALL.

	The jetpack used to be the way up and it was a traversal mechanic: you
	bought flight, and every island's access was really a height check. The
	ball is a DESTINATION instead -- it goes to Plinko and nowhere else -- so
	the check is ownership rather than altitude.

	IT LANDS YOU IN FROM THE RIM, not on the centre. The plaza has four
	machines standing on it now, and arriving inside one of them would be a
	teleport that looks like a bug. The same offset the mount uses to land on
	Racing, for the same reason.

	NO SEAL CHECK. Plinko is the chapter you start in -- Seals.canEnter passes
	for it today -- so owning the ball is the whole gate. The call is still
	made rather than skipped, so the day an island wants gating the answer
	comes from one place.
]]
function IslandService.travelToPlinko(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if profile.plinkoball ~= true then
		return { ok = false, err = "You need a Plinko Ball. The shop sells one." }
	end

	local island = Islands.get("plinko")
	if not island then
		return { ok = false, err = "Plinko island is not up yet." }
	end
	local allowed, needs = Seals.canEnter(profile, island)
	if not allowed then
		local gate = Islands.get(needs)
		return { ok = false, err = ("Needs the %s saddle."):format(
			(gate and gate.name) or tostring(needs)) }
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, err = "One moment." }
	end
	--[[ Already there. Throwing it again would be a no-op that reads as the
	     button being broken, so it says so instead. ]]
	local flat = (root.Position - island.center) * Vector3.new(1, 0, 1)
	if flat.Magnitude <= island.radius and math.abs(root.Position.Y - island.center.Y) < 60 then
		return { ok = false, err = "You are already on Plinko island." }
	end

	character:PivotTo(CFrame.new(
		island.center + Vector3.new(0, 6, -island.radius * 0.45)))
	return { ok = true }
end

function IslandService.start()
	Net.get("UsePlinkoBall").OnServerInvoke = function(player)
		local ok, result = pcall(IslandService.travelToPlinko, player)
		if not ok then
			warn("[IslandService] plinko ball failed:", result)
			return { ok = false, err = "Something went wrong." }
		end
		return result
	end

	--[[ Each island built independently. A scoping mistake in the scatter code
	     once threw partway through and took EVERY island down with it, leaving
	     a sky with nothing in it and a stack trace that pointed at a tree. One
	     broken island should cost you that island. ]]
	for _, island in ipairs(Islands.List) do
		local ok, err = pcall(IslandService.build, island)
		if not ok then
			warn(("[IslandService] %s failed to build: %s"):format(island.id, tostring(err)))
		end
	end
end

return IslandService
