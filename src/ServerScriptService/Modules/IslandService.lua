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

local function buildGround(island, rng, root)
	local c, r = island.center, island.radius

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
	for i = 1, 14 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0, r * 0.82)
		local size = rng:NextNumber(14, 30)
		part({
			name = "Facet",
			size = Vector3.new(size, 1.6, size * rng:NextNumber(0.7, 1.3)),
			cframe = CFrame.new(c + Vector3.new(
				math.cos(angle) * dist, 2.2, math.sin(angle) * dist))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			color = rng:NextNumber() < 0.5 and P.grassLit or P.grassDark,
			collide = true,
		}, root)
	end

	-- the clearing the game sits in
	cylinder({
		name = "Clearing",
		size = Vector3.new(1.4, 46, 46),
		cframe = CFrame.new(c + Vector3.new(0, 3.1, 0)),
		color = P.dirt,
		collide = true,
	}, root)
	cylinder({
		name = "ClearingRim",
		size = Vector3.new(1.2, 52, 52),
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
	for i = 1, 16 do
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
	for i = 1, 11 do
		local angle = (i / 11) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dist = r * rng:NextNumber(0.80, 0.98)
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

--[[ NARROW. A conifer is about four times taller than it is wide. The first
     pass was nearly square and read as a stack of crates from standing height,
     which is the only height that matters here. ]]
local function buildTrees(island, rng, root)
	local c, r = island.center, island.radius
	for i = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(30, r * 0.82)
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
	local c, r = island.center, island.radius
	for i = 1, 24 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(28, r * 0.86)
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
	local at = c + Vector3.new(-r * 0.52, 3, r * 0.34)
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
	local at = c + Vector3.new(0, 64, 0)
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
	for i = 1, 14 do
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
	buildOutcrops(island, rng, root)
	buildTrees(island, rng, root)
	buildMushrooms(island, rng, root)
	buildCottage(island, rng, root)
	buildBeacon(island, rng, root)
	buildDebris(island, rng, root)

	IslandService.built[island.id] = root
	return root
end

function IslandService.start()
	for _, island in ipairs(Islands.List) do
		IslandService.build(island)
	end
end

return IslandService
