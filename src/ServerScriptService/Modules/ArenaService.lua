--[[
	ArenaService
	Where a duel is fought.

	THIS IS THE SUPPLIED ARENA, rebuilt from the two assets rather than
	inserted from them. What was handed over was a place containing one part
	and a Sky:

	    79264147822932  a 2048 x 16 x 2048 plate, grey, Reflectance 0.25,
	                    with a grid Texture on its top face
	    570559352       a Sky -- and the Sky is where the purple comes from,
	                    not the plate, which is very nearly neutral grey

	Rebuilt rather than loaded because a plate is six properties and a texture,
	and InsertService at runtime would mean the arena could fail to exist
	because an asset fetch timed out. The numbers below are read straight off
	the asset; changing them changes the arena.

	THE GROUND IS TERRAIN WATER, and the fighters stand on a platform sitting
	on it. That is what the reference shows: a slab floating on a mirror that
	runs to the horizon.

	Water rather than a very shiny part, because the two do not look the same.
	A part with Reflectance 1 mirrors the skybox and stops there; terrain water
	also ripples, refracts and carries its own colour, and it is the movement
	that reads as water rather than as polished floor. Roblox's default water
	is already Reflectance 1.0 -- the sky does the rest.

	THE GLOBAL WATER PROPERTIES ARE TUNED, WITH A CAVEAT. WaterColor and the
	rest live on Terrain itself rather than on a region, so setting them here
	retints every body of water in the game. That is safe TODAY and only today:
	the arena's is the only water there is -- the islands and the street are
	built from parts, and sampling them turned up none. The day this game grows
	an ocean, these four lines become its ocean's settings too, and the arena
	will need its own way to look different.

	Left at the Roblox default the water reads teal-blue in the near field,
	because the default colour is a sea colour: 0.05, 0.33, 0.36. The reference
	is almost pure reflection, so the colour goes neutral-violet and the
	transparency up -- what you see is then mostly the sky in the mirror rather
	than the water's own body.

	THE EDGE IS WALLED, INVISIBLY. Nobody goes in the water. The original ring
	was a visible cage and this is the same idea with the geometry taken away:
	the platform reads as open, the reflection runs out to the horizon, and you
	simply cannot leave. Falling in would decide a wager on footing, and worse,
	a swimming player is one the punch cone cannot reach.

	INVISIBLE RATHER THAN SHORT. A knee-high lip would be visible and would
	still let a dash carry someone over it -- a dash is 58 studs a second and
	does not care about a step. The wall is tall enough that nothing in the
	game clears it.

	THE SKY IS SWAPPED PER CLIENT, not here. Lighting is global -- changing it
	on the server would put a night sky over the whole game for everybody,
	including the people standing in the street. The two fighters get it on
	their own clients instead, exactly the way Braziers lights shared geometry
	for one player. See UI/DuelUI, and Config.ArenaSky for the ids.

	IT IS STILL NOWHERE. Parked far off the map at altitude for the same reason
	as before: a fight nobody can wander into is a fight nobody can interfere
	with. Spectators watch through the betting card, not in person.

	ONE ARENA, NOT ONE PER DUEL. Two duels at once would share the floor and
	the fighters would tangle. `busy` is what stops that: DuelService checks it
	before it moves anyone, and a second pair is turned away rather than queued.
]]

local Workspace = game:GetService("Workspace")

local ArenaService = {}

--[[ Far out and high up. Nothing else in this game is near x=4000: the street
     sits around the origin, Plinko at y=550 and the racing island at y=1150,
     all of them within a few hundred studs of the middle. ]]
local CENTER = Vector3.new(4000, 400, 4000)

--[[ The platform. Colour and reflectance are read off asset 79264147822932 --
     it is very nearly neutral grey, and the purple everybody sees is that
     0.25 reflectance picking up the skybox. Its footprint is this codebase's
     own: the asset's own 2048 was a whole world, not a stage. ]]
local PLATE = Vector3.new(180, 4, 180)
local PLATE_COLOR = Color3.fromRGB(94, 93, 95)
local PLATE_REFLECTANCE = 0.25

--[[ The water. Wide enough that its edge is past anything you can pick out
     from the platform -- 1024 studs to the nearest one -- and deliberately
     SHALLOW, because the fill cost is per voxel and depth buys nothing you can
     see. 2048 x 12 x 2048 at four studs a voxel is about 786,000 of them,
     which fills in well under a second; going to 32 deep would nearly triple
     that for a floor nobody swims to. ]]
--[[ 4096, not 2048. At 2048 the far edge of the region was visible from the
     platform as a seam against the skybox -- 1024 studs is inside the draw
     distance. Doubling it puts the edge past where anything is resolved. The
     fill is still cheap: 786k voxels took 0.06s, and this is about four times
     that. ]]
local WATER = Vector3.new(4096, 12, 4096)

--[[ Read to match the reference: a mirror rather than a sea. Applied to
     Terrain globally -- see the header for why that is currently safe. ]]
local WATER_COLOR = Color3.fromRGB(126, 118, 168)
local WATER_TRANSPARENCY = 0.62
local WATER_REFLECTANCE = 1
local WATER_WAVE_SIZE = 0.08
local WATER_WAVE_SPEED = 6

--[[ The grid. Black at 0.8 transparency over a grey plate is a faint darkening
     rather than a drawn line, which is what stops 2048 studs of flat floor
     reading as a single untextured slab. ]]
local GRID_TEXTURE = "rbxassetid://16848415109"
local GRID_TILE = 8

--[[ How far apart the two fighters start, total. Sixty against a punch range
     of eleven means the first few seconds are spent closing, which is what the
     dash is for. ]]
local SEPARATION = 60

--[[ Tall enough that nothing in the game gets over it: a jump is about seven
     studs and the dash is purely horizontal, so forty is far more than needed
     and costs nothing to be sure about. ]]
local WALL_HEIGHT = 40
local WALL_THICKNESS = 4

ArenaService.center = CENTER
ArenaService.busy = false

--[[
	Where each fighter starts.

	Opposite each other and TURNED TO FACE the middle, because a duel that
	opens with both players looking at empty floor wastes the first seconds of
	a thirty second clock on finding the other one. On a featureless plate that
	matters more than it did in the ring -- there is no wall to orient by.

	`index` is 1 or 2. Anything else lands on the centre, which is harmless --
	this is called with a loop counter and a wrong number should not throw
	inside the one function that has to work for the arena to be usable.
]]
function ArenaService.spawnFor(index)
	local side = index == 1 and 1 or -1
	--[[ CENTER is the WATER LINE. The platform's top sits PLATE.Y above it,
	     and the character is dropped a few studs higher again so it settles
	     rather than spawning inside the slab. ]]
	local at = CENTER + Vector3.new(side * (SEPARATION / 2), PLATE.Y + 4, 0)
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

	--[[
		THE WATER FIRST, so the platform is placed against a surface that
		already exists.

		Cleared to Air before filling. Rebuilding without the clear would leave
		whatever a previous build put here, and a half-overlapping second fill
		is how you end up with a seam you cannot find.
	]]
	local top = CENTER.Y
	local waterCF = CFrame.new(CENTER.X, top - WATER.Y / 2, CENTER.Z)
	local terrain = Workspace.Terrain
	terrain:FillBlock(waterCF, WATER, Enum.Material.Air)
	terrain:FillBlock(waterCF, WATER, Enum.Material.Water)

	terrain.WaterColor = WATER_COLOR
	terrain.WaterTransparency = WATER_TRANSPARENCY
	terrain.WaterReflectance = WATER_REFLECTANCE
	terrain.WaterWaveSize = WATER_WAVE_SIZE
	terrain.WaterWaveSpeed = WATER_WAVE_SPEED

	local plate = Instance.new("Part")
	plate.Name = "Floor"
	plate.Anchored = true
	plate.CanCollide = true
	--[[ Query and touch off: nothing raycasts against the arena floor and
	     nothing needs a Touched event from it. ]]
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Size = PLATE
	--[[ Sat ON the water rather than in it -- the underside meets the water
	     line exactly, so the slab reads as floating rather than as a block
	     someone sank. ]]
	plate.CFrame = CFrame.new(CENTER.X, top + PLATE.Y / 2, CENTER.Z)
	plate.Color = PLATE_COLOR
	plate.Material = Enum.Material.Plastic
	plate.Reflectance = PLATE_REFLECTANCE
	plate.TopSurface = Enum.SurfaceType.Smooth
	plate.BottomSurface = Enum.SurfaceType.Smooth
	plate.Parent = root

	local grid = Instance.new("Texture")
	grid.Name = "Grid"
	grid.Texture = GRID_TEXTURE
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = GRID_TILE
	grid.StudsPerTileV = GRID_TILE
	grid.Color3 = Color3.new(0, 0, 0)
	grid.Transparency = 0.8
	grid.Parent = plate

	--[[
		FOUR INVISIBLE WALLS, flush with the platform's edge.

		Sized to overlap at the corners -- the two on X run the full width plus
		both thicknesses -- because four walls that merely meet leave four
		hairline gaps at the corners, and a dash arriving at 58 studs a second
		is exactly the thing that finds them.

		CanCollide on, CanQuery and CanTouch off: they exist for the physics
		solver and for nothing else. A raycast that stops on an invisible wall
		would be a bug nobody could see.
	]]
	local half = PLATE.X / 2
	local wallY = top + WALL_HEIGHT / 2
	for _, side in ipairs({
		{ Vector3.new(PLATE.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
			Vector3.new(0, 0, half + WALL_THICKNESS / 2) },
		{ Vector3.new(PLATE.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
			Vector3.new(0, 0, -half - WALL_THICKNESS / 2) },
		{ Vector3.new(WALL_THICKNESS, WALL_HEIGHT, PLATE.Z + WALL_THICKNESS * 2),
			Vector3.new(half + WALL_THICKNESS / 2, 0, 0) },
		{ Vector3.new(WALL_THICKNESS, WALL_HEIGHT, PLATE.Z + WALL_THICKNESS * 2),
			Vector3.new(-half - WALL_THICKNESS / 2, 0, 0) },
	}) do
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Transparency = 1
		wall.Size = side[1]
		wall.CFrame = CFrame.new(
			CENTER.X + side[2].X, wallY, CENTER.Z + side[2].Z)
		wall.Parent = root
	end

	ArenaService.root = root
	return root
end

return ArenaService
