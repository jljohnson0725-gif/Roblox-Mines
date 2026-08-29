--[[
	ArenaService
	Where a duel is fought.

	BUILT IN CODE, like the islands, the race track and the Mines landmark. The
	alternative was a model file, and this codebase has already decided that
	question everywhere else: geometry that is generated is geometry that can
	be re-tuned by changing a number, and it cannot go missing from a place
	file or arrive with the wrong pivot.

	IT IS SEALED. A ring wall, high enough that nobody leaves. That is not
	decoration -- the duel is decided on health, so falling off the edge would
	be a way to hand someone the win, and worse, a way to lose a Mythic to your
	own bad footing rather than to the other player. Nobody falls out of a
	fight they staked a brainrot on.

	IT IS NOWHERE. Parked far off the map at altitude rather than sited on the
	street, because two players hitting each other for thirty seconds in the
	middle of the shopping district would drag every passer-by's camera into
	it, and because a fight nobody can wander into is a fight nobody can
	interfere with. Spectators watch through the betting card, not in person.

	ONE ARENA, NOT ONE PER DUEL. Two duels at once would share the floor and
	the fighters would tangle -- four people punching in one ring, with the
	health comparison at the end reading whoever happened to be hit least.
	`busy` is what stops that: DuelService checks it before it moves anyone,
	and a second pair is turned away and told to try again rather than queued.
	Queuing would mean holding two players in a menu for an unknown length of
	time on the promise of a floor.

	Building a fresh arena per duel was the other answer and a worse one: it
	puts an unbounded amount of geometry in the world at the mercy of a crash.
]]

local Workspace = game:GetService("Workspace")

local ArenaService = {}

--[[ Far out and high up. Nothing else in this game is near x=4000: the street
     sits around the origin, Plinko at y=550 and the racing island at y=1150,
     all of them within a few hundred studs of the middle. ]]
local CENTER = Vector3.new(4000, 400, 4000)
local RADIUS = 46
local WALL_HEIGHT = 34

local COL = {
	floor = Color3.fromRGB(38, 34, 52),
	ring = Color3.fromRGB(88, 76, 122),
	wall = Color3.fromRGB(28, 26, 40),
	post = Color3.fromRGB(150, 128, 210),
	glow = Color3.fromRGB(214, 92, 92),
}

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = false
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

ArenaService.center = CENTER
ArenaService.busy = false

--[[
	Where each fighter starts.

	Opposite each other across the floor and TURNED TO FACE the middle, because
	a duel that opens with both players looking at a wall wastes the first two
	seconds of a thirty second clock on finding the other one.

	`index` is 1 or 2. Anything else lands on the centre, which is harmless --
	this is called with a loop counter and a wrong number should not throw
	inside the one function that has to work for the arena to be usable.
]]
function ArenaService.spawnFor(index)
	local angle = index == 1 and 0 or math.pi
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (RADIUS * 0.55)
	local at = CENTER + offset + Vector3.new(0, 5, 0)
	return CFrame.lookAt(at, Vector3.new(CENTER.X, at.Y, CENTER.Z))
end

function ArenaService.build()
	local existing = Workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "Arena"
	root.Parent = Workspace

	--[[ A cylinder laid flat: Size.X is the LENGTH along the axis for a
	     Cylinder, so the thickness goes in X and the diameter in Y/Z, then the
	     whole thing is turned to stand on its face. The same trap the Plinko
	     pegs fell into. ]]
	local floor = part({
		name = "Floor",
		size = Vector3.new(3, RADIUS * 2, RADIUS * 2),
		cframe = CFrame.new(CENTER) * CFrame.Angles(0, 0, math.rad(90)),
		color = COL.floor,
		material = Enum.Material.Slate,
	}, root)
	floor.Shape = Enum.PartType.Cylinder

	--[[ A lit rim just inside the wall, so the floor reads as a ring rather
	     than as a dark disc, and so both fighters can see where the edge is
	     without walking into it. ]]
	local segments = 48
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local nextAngle = ((i + 1) / segments) * math.pi * 2
		local a = CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (RADIUS - 2)
		local b = CENTER + Vector3.new(math.cos(nextAngle), 0, math.sin(nextAngle)) * (RADIUS - 2)
		local mid = (a + b) / 2 + Vector3.new(0, 1.7, 0)
		part({
			name = "Rim",
			size = Vector3.new(0.8, 0.5, (b - a).Magnitude + 0.4),
			cframe = CFrame.lookAt(mid, mid + (b - a).Unit),
			color = COL.ring,
			material = Enum.Material.Neon,
			collide = false,
		}, root)

		--[[ The wall itself, in the same pass. Invisible-but-solid was the
		     other option and it is the wrong one: a fighter who cannot see the
		     cage backs into it, and being stopped by nothing reads as the
		     game sticking. ]]
		part({
			name = "Wall",
			size = Vector3.new(1.6, WALL_HEIGHT, (b - a).Magnitude + 0.6),
			cframe = CFrame.lookAt(
				(a + b) / 2 + Vector3.new(0, WALL_HEIGHT / 2 + 1.5, 0),
				(a + b) / 2 + Vector3.new(0, WALL_HEIGHT / 2 + 1.5, 0) + (b - a).Unit),
			color = COL.wall,
			material = Enum.Material.Metal,
			transparency = 0.55,
		}, root)
	end

	--[[ Corner posts on the diagonals, purely so the cage has a silhouette
	     from the outside and a scale from the inside. ]]
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + math.rad(45)
		local at = CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (RADIUS - 1)
		part({
			name = "Post",
			size = Vector3.new(2.4, WALL_HEIGHT + 6, 2.4),
			cframe = CFrame.new(at + Vector3.new(0, (WALL_HEIGHT + 6) / 2, 0)),
			color = COL.post,
			material = Enum.Material.Metal,
		}, root)
		part({
			name = "PostLamp",
			size = Vector3.new(2.8, 1.2, 2.8),
			cframe = CFrame.new(at + Vector3.new(0, WALL_HEIGHT + 6, 0)),
			color = COL.glow,
			material = Enum.Material.Neon,
			collide = false,
		}, root)
	end

	--[[ A centre mark, so the two spawn points read as opposite ends of
	     something rather than as two arbitrary spots on a disc. ]]
	local mark = part({
		name = "CentreMark",
		size = Vector3.new(0.4, 18, 18),
		cframe = CFrame.new(CENTER + Vector3.new(0, 1.55, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = COL.ring,
		material = Enum.Material.Neon,
		transparency = 0.72,
		collide = false,
	}, root)
	mark.Shape = Enum.PartType.Cylinder

	ArenaService.root = root
	return root
end

return ArenaService
