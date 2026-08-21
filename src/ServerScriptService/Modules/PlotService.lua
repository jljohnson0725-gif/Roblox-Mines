--[[
	PlotService
	Owns the physical world: assigns plots, and keeps each pad's visual state in
	sync with the owner's inventory.

	TWO MODES, chosen at startup:

	  attach   -- Workspace/Bases/BaseN exists (the imported map). Each base is
	              already a finished art asset with 8 slot pedestals, a Spawn
	              and an Owner marker. We bind to that geometry and build
	              nothing. (Its CollectZone is unused -- see tickCollect.)
	  generate -- no Bases folder. Falls back to building ground, plots and
	              tiered shelves in code, so the game still runs on a blank
	              baseplate with zero setup.

	Both modes produce the same `plot` shape, so everything below the mode split
	-- rendering, placement, unlocking -- is written once.

	Pad ORDER matters and must never change: pad indices are persisted in save
	data, so a brainrot on pad 3 has to come back on pad 3. The map names all
	eight slots "Slot1", so we sort by position instead of by name.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Variants = require(Shared.Variants)
local Rarity = require(Shared.Rarity)
local Brainrots = require(Shared.Brainrots)
local Upgrades = require(Shared.Upgrades)

local DataService = require(script.Parent.DataService)
local HomeService = require(script.Parent.HomeService)
local PlayerState = require(script.Parent.PlayerState)
local ModelFactory = require(script.Parent.ModelFactory)

local PlotService = {}

local GENERATED_PLOT_COUNT = 12

local plots = {}
local byUserId = {}
local mode = "generate"

local EMPTY_PAD = Color3.fromRGB(72, 76, 88)
local LOCKED_PAD = Color3.fromRGB(38, 40, 48)

-- How many cash slabs a full collect strip shows. Declared up here because
-- attachPlot builds the slabs long before the collect-pile section below --
-- a local declared later simply isn't in scope there.
local PILE_STEPS = 3

-- ════════════════════════════════════════════════════════════════════════════
-- ATTACH MODE
-- ════════════════════════════════════════════════════════════════════════════

local function findBases()
	local folder = Workspace:FindFirstChild("Bases")
	if not folder then
		return nil
	end

	local found = {}
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:FindFirstChild("Slots") then
			table.insert(found, model)
		end
	end
	if #found == 0 then
		return nil
	end

	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

--[[
	Read one slot model. Two DIFFERENT places matter, and conflating them was a
	bug worth naming:

	  `Part` / `Collect`  -- a narrow 8.7 x 5.1 strip. This is the COLLECT strip
	                         where cash piles up. It is not a display podium.
	  `Spawn`             -- a 1x1x1 marker sitting at the centre of the map's
	                         octagonal podium (four stacked Unions, 16x16 down
	                         to 10x10). This is where the brainrot belongs.

	The brainrot stands on the podium and faces the aisle, which is the
	direction from the podium back toward the collect strip.

	Podium height comes from a raycast rather than a guessed offset, because the
	podium is four stacked Unions of differing thickness and the marker sits
	inside them, not on top.
]]
local function readSlot(slot)
	local strip = slot:FindFirstChild("Part")
	if not strip or not strip:IsA("BasePart") then
		strip = slot:FindFirstChildWhichIsA("BasePart")
	end
	if not strip then
		return nil
	end

	local marker = slot:FindFirstChild("Spawn")
	if not marker or not marker:IsA("BasePart") then
		-- No podium marker: fall back to standing on the strip itself.
		return strip, Vector3.new(0, 0, 1), strip.Position + Vector3.new(0, strip.Size.Y / 2, 0)
	end

	--[[
		Facing, in order of trust.

		HomeService states it outright on converted bases, because the geometry
		it used to be inferred from no longer says anything: the strip now sits
		UNDER the marker, so strip-minus-marker is a zero vector. The inference
		was also wrong before that -- the map offsets every strip along -Z, so
		it aimed all eight brainrots the same way whichever wall they stood
		against. Unconverted bases keep the old reading, then +Z as the floor.
	]]
	local facing = slot:GetAttribute("Facing")
	if typeof(facing) ~= "Vector3" or facing.Magnitude < 0.1 then
		local delta = strip.Position - marker.Position
		facing = Vector3.new(delta.X, 0, delta.Z)
	end
	facing = facing.Magnitude > 0.1 and facing.Unit or Vector3.new(0, 0, 1)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { slot }

	local from = marker.Position + Vector3.new(0, 12, 0)
	local hit = Workspace:Raycast(from, Vector3.new(0, -24, 0), params)
	local stand = hit and hit.Position or marker.Position

	return strip, facing, stand
end

--[[
	Lay the reference's bright checker floor over a base.

	Finding the floor is the fiddly part. The base has several big flat slabs
	stacked up its height -- including a ROOF at y=27.5 that a downward raycast
	from above hits first -- so picking "largest flat part" gives you the ceiling.
	Instead we take the slot strips as ground truth: they sit ON the walkable
	floor, so the slab whose top is nearest their height is the one to tile.

	Tiles are thin, non-colliding and non-queryable, so they can't shadow a
	ProximityPrompt or trap a player on a lip. Any tile that would overlap a slot
	is skipped rather than drawn underneath -- 0.1 studs of clearance is not
	enough to stop z-fighting with the strips.

	TILE SIZE IS MEASURED, NOT CHOSEN. The slot rows sit 18 studs apart and the
	strips are 5.1 deep, so there are only ~12.9 studs of clear floor between
	them. A 9.5-stud tile needs 18.6 studs of row spacing once the exclusion
	margin is added, which is more than exists -- the first attempt rejected
	every candidate on all eight bases and produced empty folders. At 4 studs
	two tile rows fit in each lane.

	The slab underneath is recoloured as well. Tiles can only ever cover the
	lanes, so without that the base would read as bright stripes on a dark
	floor rather than a bright floor.
]]
local TILE = 4
local TILE_MARGIN = 0.3
local TILE_A = Color3.fromRGB(122, 188, 100)
local TILE_B = Color3.fromRGB(206, 104, 102)
local FLOOR_COLOR = Color3.fromRGB(142, 196, 120)

--[[
	The map ships each base full of Neon: glowing floor pads, strips and trim,
	about twenty-two parts apiece. MapStyle deliberately skips everything under
	Bases -- it restyles the world, not the plots -- so none of it was ever
	toned down, and the result was a floor that read as a lightbox.

]]
local function calmBase(base)
	local calmed = 0

	--[[ THE APARTMENT IS EXEMPT.

	     Everything below was written for the map's own base geometry -- its
	     neon plot tiling and its six surgical ceiling spotlights. HomeService's
	     interior is ours, is already tuned against the daylight pass, and now
	     gets built BEFORE this runs, so without the exemption this walks in
	     afterwards and undoes it: the collect pad loses its neon and every
	     rebirth tier's lighting collapses to the same clamped 0.65 warm white.
	     That is also what made the tier attribute lie -- the room said Studio
	     while wearing something else entirely. ]]
	local home = base:FindFirstChild("Home")

	for _, p in ipairs(base:GetDescendants()) do
		local exempt = home ~= nil and p:IsDescendantOf(home)

		if not exempt
			and p:IsA("BasePart")
			and p.Material == Enum.Material.Neon
		then
			p.Material = Enum.Material.SmoothPlastic
			-- pull the value down too: a colour picked to glow is usually far
			-- brighter than the same colour needs to be when it doesn't
			local h, sat, v = Color3.toHSV(p.Color)
			p.Color = Color3.fromHSV(h, sat * 0.9, math.min(v, 0.72))
			calmed += 1
		end

		--[[ And the ceiling lights. Six pure-white spotlights at brightness 1.6
		     were sized for the map's original darker interior; under the
		     daylight pass they wash the floor out to pastel and undo the point
		     of calming the colours. Dimmer, and warm rather than surgical. ]]
		if not exempt and (p:IsA("SpotLight") or p:IsA("PointLight")) then
			p.Brightness = math.min(p.Brightness, 0.65)
			p.Color = Color3.fromRGB(255, 248, 232)
		end
	end
	return calmed
end

local function tilePlot(base, slotParts)
	local existing = base:FindFirstChild("TileFloor")
	if existing then
		existing:Destroy()
	end
	if #slotParts == 0 then
		return 0
	end

	local slotY = 0
	for _, part in ipairs(slotParts) do
		slotY += part.Position.Y
	end
	slotY /= #slotParts

	local floor, bestGap
	for _, part in ipairs(base:GetChildren()) do
		if part:IsA("BasePart") and part.Size.Y < 6
			and part.Size.X > 40 and part.Size.Z > 40 then
			local top = part.Position.Y + part.Size.Y / 2
			local gap = math.abs(top - slotY)
			if not bestGap or gap < bestGap then
				floor, bestGap = part, gap
			end
		end
	end
	-- More than a couple of studs off the strips means we found a roof, not a
	-- floor. Better to leave the base alone than to tile its ceiling.
	if not floor or bestGap > 3 then
		return 0
	end

	local top = floor.Position.Y + floor.Size.Y / 2
	floor.Color = FLOOR_COLOR
	floor.Material = Enum.Material.Plastic

	local root = Instance.new("Folder")
	root.Name = "TileFloor"
	root.Parent = base

	local stepsX = math.floor((floor.Size.X / 2 - TILE) / TILE)
	local stepsZ = math.floor((floor.Size.Z / 2 - TILE) / TILE)
	local made = 0

	--[[
		NOT OUTSIDE THE APARTMENT.

		HomeService builds a room over one corner of the plot and publishes its
		footprint on the base. Tiling the whole plot regardless left a
		checkerboard running out past the walls -- the floor of the base the
		apartment replaced, still lying there in the street.

		Only skipped when the attributes exist, so a plot with no home on it --
		or a base built before this ran -- still tiles end to end as before.
	]]
	local roomX = base:GetAttribute("RoomX")
	local roomZ = base:GetAttribute("RoomZ")
	local halfX = base:GetAttribute("RoomHalfX")
	local halfZ = base:GetAttribute("RoomHalfZ")
	local bounded = roomX ~= nil and halfX ~= nil

	for ix = -stepsX, stepsX do
		for iz = -stepsZ, stepsZ do
			local centre = Vector3.new(
				floor.Position.X + ix * TILE, top + 0.08, floor.Position.Z + iz * TILE)

			local blocked = false
			if bounded and (math.abs(centre.X - roomX) > halfX
				or math.abs(centre.Z - roomZ) > halfZ) then
				blocked = true
			end
			for _, part in ipairs(slotParts) do
				local d = part.Position - centre
				if math.abs(d.X) < (part.Size.X + TILE) / 2 + TILE_MARGIN
					and math.abs(d.Z) < (part.Size.Z + TILE) / 2 + TILE_MARGIN then
					blocked = true
					break
				end
			end

			if not blocked then
				local tile = Instance.new("Part")
				tile.Name = "Tile"
				tile.Anchored = true
				tile.CanCollide = false
				tile.CanQuery = false
				tile.CanTouch = false
				tile.Size = Vector3.new(TILE - 0.2, 0.16, TILE - 0.2)
				tile.CFrame = CFrame.new(centre)
				tile.Color = ((ix + iz) % 2 == 0) and TILE_A or TILE_B
				tile.Material = Enum.Material.Plastic -- studs catch the light
				tile.TopSurface = Enum.SurfaceType.Smooth
				tile.BottomSurface = Enum.SurfaceType.Smooth
				tile.Parent = root
				made += 1
			end
		end
	end

	return made
end

local function attachPlot(base, index)
	local slotsFolder = base:FindFirstChild("Slots")
	local pads = {}

	local entries = {}
	for _, slot in ipairs(slotsFolder:GetChildren()) do
		local pedestal, facing, stand = readSlot(slot)
		if pedestal then
			table.insert(entries, { pedestal = pedestal, facing = facing, stand = stand })
		end
	end

	-- Deterministic, position-based ordering. Every slot in the map is named
	-- "Slot1", so name order is useless and GetChildren() order is not
	-- guaranteed stable across sessions -- but pad indices are saved.
	table.sort(entries, function(a, b)
		local pa, pb = a.pedestal.Position, b.pedestal.Position
		if math.abs(pa.X - pb.X) > 0.5 then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)

	-- Tiled before the pads are wired, so the strips end up sitting on the new
	-- floor rather than the tiles landing on top of a finished plot.
	do
		local slotParts = {}
		for _, entry in ipairs(entries) do
			table.insert(slotParts, entry.pedestal)
		end
		for _, slot in ipairs(slotsFolder:GetChildren()) do
			for _, part in ipairs(slot:GetChildren()) do
				if part:IsA("BasePart") then
					table.insert(slotParts, part)
				end
			end
		end
		tilePlot(base, slotParts)
		calmBase(base)
	end

	local container = Instance.new("Folder")
	container.Name = "PlacedBrainrots"
	container.Parent = base

	for i, entry in ipairs(entries) do
		local pedestal = entry.pedestal

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PadPrompt"
		prompt.ActionText = ""
		prompt.ObjectText = "Pad " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal

		-- Cash slabs stacked on the strip. Built once, hidden/shown by
		-- renderPile -- cheaper and steadier than spawning parts per tick.
		local pile = {}
		local top = pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2, 0)
		for step = 1, PILE_STEPS do
			local slab = Instance.new("Part")
			slab.Name = "Cash" .. step
			slab.Size = Vector3.new(pedestal.Size.X * 0.5, 0.35, pedestal.Size.Z * 0.55)
			slab.CFrame = CFrame.new(top + Vector3.new(0, 0.18 + (step - 1) * 0.38, 0))
			slab.Anchored = true
			slab.CanCollide = false
			slab.CanQuery = false
			slab.CanTouch = false
			slab.Color = Color3.fromRGB(96, 200, 118)
			slab.Material = Enum.Material.SmoothPlastic
			slab.Transparency = 1
			slab.Parent = container
			pile[step] = slab
		end

		local pileGui = Instance.new("BillboardGui")
		pileGui.Name = "PileLabel"
		pileGui.Size = UDim2.fromOffset(72, 16)
		pileGui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		pileGui.MaxDistance = 70
		pileGui.Adornee = pedestal
		-- On the PEDESTAL, not the container folder. A BillboardGui outlives its
		-- Adornee when streaming unloads the part, and one with a nil Adornee and
		-- a non-BasePart parent renders at the world origin -- out in the street.
		pileGui.Parent = pedestal

		local pileLabel = Instance.new("TextLabel")
		pileLabel.Size = UDim2.fromScale(1, 1)
		pileLabel.BackgroundTransparency = 1
		pileLabel.Font = Enum.Font.GothamBlack
		pileLabel.TextScaled = true
		pileLabel.TextColor3 = Color3.fromRGB(120, 235, 150)
		pileLabel.TextStrokeTransparency = 0.4
		pileLabel.Text = ""
		pileLabel.Parent = pileGui

		pads[i] = {
			part = pedestal, -- collect strip: carries the prompt and the tint
			prompt = prompt,
			model = nil,
			facing = entry.facing,
			stand = entry.stand, -- podium surface: where the model actually goes
			pile = pile,
			pileLabel = pileLabel,
			-- so an empty pad can be restored to the map's own look
			baseColor = pedestal.Color,
			baseMaterial = pedestal.Material,
		}
	end

	-- owner nameplate, hung on the map's own Owner marker
	local ownerPart = base:FindFirstChild("Owner")
	local ownerLabel, rateLabel
	if ownerPart and ownerPart:IsA("BasePart") then
		--[[
			Deliberately restrained. These were 300x74 at MaxDistance 250 with
			uncapped TextScaled, which was fine over a bright daytime map but
			became the loudest thing on screen once MapStyle took it to dusk --
			white text over a dark map, big enough to overlap between bases.
			Capping the text size is what actually fixes it; TextScaled alone
			just grows to fill whatever box you give it.
		]]
		local gui = Instance.new("BillboardGui")
		gui.Name = "OwnerLabel"
		gui.Size = UDim2.fromOffset(126, 31)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		gui.MaxDistance = 120
		gui.AlwaysOnTop = false
		gui.Parent = ownerPart

		ownerLabel = Instance.new("TextLabel")
		ownerLabel.Size = UDim2.new(1, 0, 0.58, 0)
		ownerLabel.BackgroundTransparency = 1
		ownerLabel.Font = Enum.Font.GothamBold
		ownerLabel.TextScaled = true
		ownerLabel.TextColor3 = Color3.fromRGB(226, 232, 248)
		ownerLabel.TextStrokeTransparency = 0.35
		ownerLabel.Text = "Empty Base"
		ownerLabel.Parent = gui

		local ownerCap = Instance.new("UITextSizeConstraint")
		ownerCap.MaxTextSize = 13
		ownerCap.Parent = ownerLabel

		rateLabel = Instance.new("TextLabel")
		rateLabel.Size = UDim2.new(1, 0, 0.42, 0)
		rateLabel.Position = UDim2.new(0, 0, 0.58, 0)
		rateLabel.BackgroundTransparency = 1
		rateLabel.Font = Enum.Font.GothamMedium
		rateLabel.TextScaled = true
		rateLabel.TextColor3 = Color3.fromRGB(120, 235, 150)
		rateLabel.TextStrokeTransparency = 0.45
		rateLabel.Text = ""
		rateLabel.Parent = gui

		local rateCap = Instance.new("UITextSizeConstraint")
		rateCap.MaxTextSize = 9
		rateCap.Parent = rateLabel
	end

	local spawnPart = base:FindFirstChild("Spawn")
	local spawnCFrame
	if spawnPart and spawnPart:IsA("BasePart") then
		spawnCFrame = spawnPart.CFrame + Vector3.new(0, 4, 0)
	end

	--[[
		NO LASER DOOR.

		The bars and the button that armed them are gone, not merely disarmed.
		They come from a game about stealing -- they exist to kill anyone who
		walks into your base -- and nothing here is stealable. The apartment has
		a door you walk through instead.

		Destroyed rather than hidden because an invisible collidable bar across
		your own doorway is a bug waiting to be reported, and a disarmed one
		still leaves a button on the wall promising a feature that is gone.
	]]
	local laserFolder = base:FindFirstChild("Lasers", true)
	if laserFolder then
		laserFolder:Destroy()
	end
	local lockPart = base:FindFirstChild("Lock")
	if lockPart then
		lockPart:Destroy()
	end

	return {
		index = index,
		model = base,
		pads = pads,
		modelFolder = container,
		ownerLabel = ownerLabel,
		rateLabel = rateLabel,
		spawnCFrame = spawnCFrame,
		userId = nil,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- GENERATE MODE  (fallback: no map present)
-- ════════════════════════════════════════════════════════════════════════════

local SHELF_COUNT = math.ceil(Config.MaxSlots / Config.PadColumns)
local SHELF_WIDTH = (Config.PadColumns - 1) * Config.PadSpacing + Config.PadSize.X + 4

local function shelfHeight(shelf)
	return Config.ShelfLift + shelf * Config.ShelfRise
end

local function shelfZ(shelf)
	return Config.ShelfFrontZ - shelf * Config.ShelfDepth
end

local function padOffset(index)
	local col = (index - 1) % Config.PadColumns
	local shelf = math.floor((index - 1) / Config.PadColumns)
	local x = (col - (Config.PadColumns - 1) / 2) * Config.PadSpacing
	return Vector3.new(x, shelfHeight(shelf), shelfZ(shelf))
end

local function buildGround()
	local stock = Workspace:FindFirstChild("Baseplate")
	if stock and stock:IsA("BasePart") then
		stock:Destroy()
	end

	local span = (GENERATED_PLOT_COUNT - 1) * Config.PlotSpacing

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(span + Config.PlotSize.X + 160, 4, Config.PlotSize.Z + 160)
	ground.Position = Vector3.new(span / 2, -2, 0)
	ground.Anchored = true
	ground.Color = Color3.fromRGB(32, 34, 42)
	ground.Material = Enum.Material.Slate
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace

	if not Workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Name = "Spawn"
		spawnPad.Size = Vector3.new(12, 1, 12)
		spawnPad.Position = Vector3.new(0, 0.5, Config.PlotSize.Z / 2 + 14)
		spawnPad.Anchored = true
		spawnPad.Neutral = true
		spawnPad.Duration = 0
		spawnPad.Color = Color3.fromRGB(120, 132, 255)
		spawnPad.Material = Enum.Material.Neon
		spawnPad.Parent = Workspace
	end
end

local function buildPlot(index, parent)
	local origin = Vector3.new((index - 1) * Config.PlotSpacing, 0, 0)
	local surfaceY = Config.PlotSize.Y

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder.Parent = parent

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Config.PlotSize
	base.Position = origin + Vector3.new(0, Config.PlotSize.Y / 2, 0)
	base.Anchored = true
	base.Color = Color3.fromRGB(46, 48, 58)
	base.Material = Enum.Material.Concrete
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = folder

	local signPost = Instance.new("Part")
	signPost.Name = "Sign"
	signPost.Size = Vector3.new(0.6, 6, 0.6)
	signPost.Position = origin + Vector3.new(0, surfaceY + 3, Config.PlotSize.Z / 2 - 2)
	signPost.Anchored = true
	signPost.Color = Color3.fromRGB(30, 32, 40)
	signPost.Material = Enum.Material.Metal
	signPost.Parent = folder

	local signGui = Instance.new("BillboardGui")
	signGui.Name = "OwnerLabel"
	signGui.Size = UDim2.fromOffset(168, 42)
	signGui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	signGui.MaxDistance = 220
	signGui.Parent = signPost

	local owner = Instance.new("TextLabel")
	owner.Size = UDim2.new(1, 0, 0.6, 0)
	owner.BackgroundTransparency = 1
	owner.Font = Enum.Font.GothamBold
	owner.TextScaled = true
	owner.TextColor3 = Color3.fromRGB(240, 242, 250)
	owner.TextStrokeTransparency = 0.4
	owner.Text = "Empty Plot"
	owner.Parent = signGui

	local rate = Instance.new("TextLabel")
	rate.Size = UDim2.new(1, 0, 0.4, 0)
	rate.Position = UDim2.new(0, 0, 0.6, 0)
	rate.BackgroundTransparency = 1
	rate.Font = Enum.Font.GothamMedium
	rate.TextScaled = true
	rate.TextColor3 = Color3.fromRGB(120, 235, 150)
	rate.TextStrokeTransparency = 0.5
	rate.Text = ""
	rate.Parent = signGui

	local shelfFolder = Instance.new("Folder")
	shelfFolder.Name = "Shelves"
	shelfFolder.Parent = folder

	for shelf = 0, SHELF_COUNT - 1 do
		local height = shelfHeight(shelf)

		local riser = Instance.new("Part")
		riser.Name = "Shelf" .. (shelf + 1)
		riser.Size = Vector3.new(SHELF_WIDTH, height, Config.ShelfDepth)
		riser.Position = origin + Vector3.new(0, surfaceY + height / 2, shelfZ(shelf))
		riser.Anchored = true
		riser.Color = Color3.fromRGB(54, 57, 70)
		riser.Material = Enum.Material.Concrete
		riser.TopSurface = Enum.SurfaceType.Smooth
		riser.Parent = shelfFolder

		local lip = Instance.new("Part")
		lip.Name = "Lip"
		lip.Size = Vector3.new(SHELF_WIDTH, 0.25, 0.5)
		lip.Position = origin
			+ Vector3.new(0, surfaceY + height - 0.12, shelfZ(shelf) + Config.ShelfDepth / 2 - 0.25)
		lip.Anchored = true
		lip.CanCollide = false
		lip.Color = Color3.fromRGB(120, 132, 255)
		lip.Material = Enum.Material.Neon
		lip.Parent = shelfFolder
	end

	local padFolder = Instance.new("Folder")
	padFolder.Name = "Pads"
	padFolder.Parent = folder

	local modelFolder = Instance.new("Folder")
	modelFolder.Name = "Models"
	modelFolder.Parent = folder

	local pads = {}
	for i = 1, Config.MaxSlots do
		local pad = Instance.new("Part")
		pad.Name = "Pad" .. i
		pad.Size = Config.PadSize
		pad.Position = origin + padOffset(i) + Vector3.new(0, surfaceY + Config.PadSize.Y / 2, 0)
		pad.Anchored = true
		pad.Color = LOCKED_PAD
		pad.Material = Enum.Material.SmoothPlastic
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = padFolder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PadPrompt"
		prompt.ActionText = ""
		prompt.ObjectText = "Pad " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad

		pads[i] = {
			part = pad,
			prompt = prompt,
			model = nil,
			facing = Vector3.new(0, 0, 1),
			baseColor = EMPTY_PAD,
			baseMaterial = Enum.Material.SmoothPlastic,
		}
	end

	return {
		index = index,
		folder = folder,
		pads = pads,
		modelFolder = modelFolder,
		ownerLabel = owner,
		rateLabel = rate,
		spawnCFrame = CFrame.new(origin + Vector3.new(0, surfaceY + 5, Config.PlotSize.Z / 2 - 6)),
		userId = nil,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- SHARED: pad rendering
-- ════════════════════════════════════════════════════════════════════════════

local function slotsAvailable(plot)
	return #plot.pads
end

local function padStateKey(profile, padIndex, plot)
	local unlocked = math.min(profile.slots, slotsAvailable(plot))
	if padIndex > unlocked then
		return padIndex == unlocked + 1 and "locked-next" or "locked"
	end
	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return "empty"
	end
	return table.concat({ "on", item.uid, item.charId, item.variantId }, "|")
end

local function renderPad(plot, padIndex, profile)
	local pad = plot.pads[padIndex]
	if not pad then
		return
	end

	local key = padStateKey(profile, padIndex, plot)
	if pad.part:GetAttribute("StateKey") == key then
		return
	end
	pad.part:SetAttribute("StateKey", key)

	if pad.model then
		pad.model:Destroy()
		pad.model = nil
	end

	if key == "locked" or key == "locked-next" then
		pad.part.Color = LOCKED_PAD
		pad.part.Material = Enum.Material.SmoothPlastic

		local cost = key == "locked-next" and Economy.slotCost(padIndex - 1) or nil
		if cost then
			pad.prompt.Enabled = true
			pad.prompt.ActionText = "Unlock  " .. Format.money(cost)
			pad.prompt.ObjectText = "Locked Pad"
		else
			pad.prompt.Enabled = false
		end
		return
	end

	if key == "empty" then
		-- restore whatever the pad looked like before we touched it
		pad.part.Color = pad.baseColor
		pad.part.Material = pad.baseMaterial
		pad.prompt.Enabled = true
		pad.prompt.ActionText = "Place Brainrot"
		pad.prompt.ObjectText = "Empty Pad"
		return
	end

	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return
	end

	local char = Brainrots.get(item.charId)
	local tier = Rarity.get(char.tier)
	pad.part.Color = tier.color
	-- tier colour, not a light source. Eight glowing strips per base turned the
	-- floor into a lightbox; the colour alone still says which pads are filled.
	pad.part.Material = Enum.Material.SmoothPlastic

	local model = ModelFactory.build(item.charId, item.variantId)
	if model then
		model.Name = item.uid
		-- `stand` is the podium surface, NOT pad.part -- pad.part is the collect
		-- strip in front of it, which is where these used to wrongly appear.
		local top = pad.stand or (pad.part.Position + Vector3.new(0, pad.part.Size.Y / 2, 0))
		-- Placeholder figures are built facing +Z, and CFrame.lookAt aims -Z at
		-- the target, so the extra half turn makes them look along `facing`.
		local aim = CFrame.lookAt(top, top + pad.facing) * CFrame.Angles(0, math.pi, 0)
		ModelFactory.place(model, aim)
		model.Parent = plot.modelFolder
		pad.model = model

	end

	pad.prompt.Enabled = true
	pad.prompt.ActionText = "Store"
	pad.prompt.ObjectText = Economy.displayName(item.charId, item.variantId)
end

-- ════════════════════════════════════════════════════════════════════════════
-- COLLECT PILES
-- ════════════════════════════════════════════════════════════════════════════

--[[
	Income accrues into `profile.pending` and shows up as cash on the strips in
	front of each brainrot. Walking over the base's CollectZone banks it.

	Pending is tracked as ONE number, not per slot. Each strip displays its
	share proportionally (that brainrot's income / total income), which looks
	identical to per-slot accounting but avoids keeping eight extra counters in
	sync with placement changes.
]]
local function renderPile(pad, amount, fraction)
	if not pad.pile then
		return
	end

	local shown = 0
	if amount > 0 then
		-- stepped, not continuous: parts only toggle when crossing a threshold,
		-- so the per-second tick isn't rewriting geometry every frame
		shown = math.clamp(math.ceil(fraction * PILE_STEPS), 1, PILE_STEPS)
	end

	for i, slab in ipairs(pad.pile) do
		slab.Transparency = i <= shown and 0 or 1
	end

	if pad.pileLabel then
		pad.pileLabel.Text = amount > 0 and Format.money(amount) or ""
	end
end

--[[
	Grow each strip's pile. Capped PER SLOT off that brainrot's own rate, so a
	fast earner fills its strip in the same wall-clock time a slow one does --
	the cap is about how long you can stay away, not about who earns more.
]]
function PlotService.accrue(player, elapsed)
	local profile = DataService.get(player)
	if not profile or not profile.pending then
		return
	end

	-- Upgrades multiply the rate and extend how long a strip keeps filling.
	-- Applied here rather than inside Economy so Economy stays a pure function
	-- of (character, variant) that the client can evaluate identically.
	local multiplier = Upgrades.incomeMultiplier(profile)
	local capSeconds = Upgrades.capSeconds(profile, Config.CollectCapSeconds)

	for _, item in ipairs(profile.inventory) do
		local slot = item.pad
		if slot and slot >= 1 and slot <= Config.MaxSlots then
			local rate = Economy.incomeOf(item.charId, item.variantId) * multiplier
			profile.pending[slot] = math.min(rate * capSeconds, (profile.pending[slot] or 0) + rate * elapsed)
		end
	end
end

--[[ Refresh every strip on a player's base. Called once a second. ]]
function PlotService.renderPiles(player)
	local plot = byUserId[player.UserId]
	local profile = DataService.get(player)
	if not plot or not profile or not profile.pending then
		return
	end

	for index, pad in ipairs(plot.pads) do
		local item = DataService.itemOnPad(profile, index)
		local amount = profile.pending[index] or 0
		if item then
			local rate = Economy.incomeOf(item.charId, item.variantId) * Upgrades.incomeMultiplier(profile)
			local cap = math.max(rate * Upgrades.capSeconds(profile, Config.CollectCapSeconds), 1)
			renderPile(pad, amount, math.clamp(amount / cap, 0, 1))
		else
			-- cash left behind by a brainrot that got stored stays collectable
			renderPile(pad, amount, amount > 0 and 1 or 0)
		end
	end

	--[[
		The desk monitor says what the piles say, in one place you can read from
		the doorway.

		Driven from here rather than its own loop because renderPiles already
		runs on the collect cadence and already has both numbers -- a second
		timer computing the same two figures is how the screen and the strips
		end up disagreeing by a tick.
	]]
	local home = plot.model and plot.model:FindFirstChild("Home")
	local interior = home and home:FindFirstChild("Interior")
	local desk = interior and interior:FindFirstChild("Desk")
	local readout = desk and desk:FindFirstChild("MonitorScreen")
	readout = readout and readout:FindFirstChild("Readout")
	if readout then
		local total = 0
		for i = 1, #plot.pads do
			total += profile.pending[i] or 0
		end
		local frame = readout:FindFirstChildWhichIsA("Frame")
		local rate = frame and frame:FindFirstChild("Rate")
		local ready = frame and frame:FindFirstChild("Ready")
		if rate then
			rate.Text = Format.rate(Economy.totalIncome(profile.inventory))
		end
		if ready then
			ready.Text = "READY  " .. Format.money(math.floor(total))
		end
	end
end

local function withinPad(root, part, pad)
	local delta = root.Position - part.Position
	local half = part.Size / 2
	return math.abs(delta.X) <= half.X + pad
		and math.abs(delta.Z) <= half.Z + pad
		and math.abs(delta.Y) <= 8
end

--[[
	Walk over the cash to pick it up.

	Collection happens ONLY at the per-slot strips -- the same pads the cash and
	the running total are displayed on. The map's own CollectZone is deliberately
	unused: it sits at z -151 while the laser door is at z -157, which puts it
	OUTSIDE your own security door, unreachable without opening up or dying.

	Standing near a strip banks that brainrot's share (its income / total), so
	you walk the row and pick cash up as you pass.

	Runs on the tick rather than Touched alone: Touched fires on entry but not
	while you stand still, so you'd watch the pile grow under your feet.
]]
function PlotService.tickCollect(player)
	local plot = byUserId[player.UserId]
	local profile = DataService.get(player)
	if not plot or not profile or not profile.pending then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	--[[
		ONE PAD BANKS EVERYTHING.

		Collection used to be per strip: stand near a pad, empty that pad. That
		is eight places to stand for an action nobody ever wants to do partially
		-- and it left every empty pad wearing a lit collect strip, which read as
		a bug rather than as furniture.

		HomeService puts a single CollectPad by the door. Standing on it claims
		the lot. The old per-strip path is kept as the fallback for any base that
		has not been converted, so this cannot strand a player's money.
	]]
	local home = plot.model and plot.model:FindFirstChild("Home")
	local interior = home and home:FindFirstChild("Interior")
	local zone = interior and interior:FindFirstChild("CollectZone")

	--[[
		A RADIUS, NOT A BOX.

		The trigger is a circle round the desk because the thing marking it is a
		ring, and a box behind a circle means the corners pay out and the edges
		do not -- a difference the player can feel and cannot see. HomeService
		writes the radius onto the zone so the two can never disagree; changing
		the ring's size in one place changes both.

		Compared in XZ only. A player jumping next to their desk is still next
		to their desk.
	]]
	local claimed = 0
	if zone then
		local radius = zone:GetAttribute("Radius") or 9
		local flat = Vector3.new(root.Position.X - zone.Position.X, 0,
			root.Position.Z - zone.Position.Z)
		if flat.Magnitude <= radius then
			for index = 1, #plot.pads do
				local amount = profile.pending[index] or 0
				if amount >= 1 then
					profile.pending[index] = 0
					claimed += amount
				end
			end
		end
	else
		for index, pad in ipairs(plot.pads) do
			local amount = profile.pending[index] or 0
			if amount >= 1 and withinPad(root, pad.part, 4) then
				-- the WHOLE strip, emptied in one go
				profile.pending[index] = 0
				claimed += amount
			end
		end
	end

	if claimed < 1 then
		return
	end

	profile.money += math.floor(claimed)

	--[[ The chime, played FROM the desk rather than into the player's head, so
	     it is positional and tells you the sound belongs to that object.
	     Server-side Play() replicates, and only fires on a claim that actually
	     moved money -- tickCollect runs constantly while you stand there, and a
	     sound on every tick would be a buzz, not a reward. ]]
	local zoneSound = zone and zone:FindFirstChildWhichIsA("Sound")
	if zoneSound then
		zoneSound:Play()
	end

	--[[ The one place that can honestly say a pile was collected. The coach's
	     last step reads this: inferring it client-side from `pending == 0` is
	     wrong, because pending is also zero in the seconds after you place a
	     brainrot and before it has earned anything. ]]
	if profile.onboarding then
		profile.onboarding.collected = true
	end

	PlotService.renderPiles(player)
	PlayerState.push(player)
	PlayerState.notify(player, "Collected " .. Format.money(math.floor(claimed)), "good")
end

function PlotService.refresh(player)
	local plot = byUserId[player.UserId]
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end

	for i = 1, #plot.pads do
		renderPad(plot, i, profile)
	end

	if plot.ownerLabel then
		plot.ownerLabel.Text = player.DisplayName .. "'s Base"
	end
	if plot.rateLabel then
		plot.rateLabel.Text = Format.rate(Economy.totalIncome(profile.inventory))
	end

	--[[ The room is redecorated to match the owner's rebirths. Here rather than
	     in RebirthService because refresh already runs on claim AND on rebirth,
	     so hanging it here makes "the room matches the profile" true wherever
	     the profile changed, instead of only where somebody remembered. ]]
	if plot.model then
		HomeService.applyTier(plot.model, profile.rebirths)
	end
end

--[[ How many pads this world actually offers. Attach mode is capped by the
     map's geometry, which is the real limit regardless of Config. ]]
function PlotService.padCapacity(player)
	local plot = byUserId[player.UserId]
	return plot and #plot.pads or Config.MaxSlots
end

-- ════════════════════════════════════════════════════════════════════════════
-- ACTIONS
-- ════════════════════════════════════════════════════════════════════════════

function PlotService.placeBrainrot(player, uid, padIndex)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if type(padIndex) ~= "number" or padIndex ~= padIndex then
		return { ok = false, err = "Invalid pad." }
	end
	padIndex = math.floor(padIndex)

	local capacity = PlotService.padCapacity(player)
	local unlocked = math.min(profile.slots, capacity)

	if padIndex ~= 0 and (padIndex < 1 or padIndex > unlocked) then
		return { ok = false, err = "That pad isn't unlocked." }
	end

	local item = DataService.findItem(profile, uid)
	if not item then
		return { ok = false, err = "You don't own that." }
	end

	if padIndex == 0 then
		item.pad = nil
		PlotService.refresh(player)
		PlayerState.push(player)
		return { ok = true, stored = true }
	end

	local occupant = DataService.itemOnPad(profile, padIndex)
	if occupant and occupant.uid ~= item.uid then
		occupant.pad = item.pad
	end
	item.pad = padIndex

	PlotService.refresh(player)
	PlayerState.push(player)
	return { ok = true }
end

function PlotService.storeBrainrot(player, padIndex)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return
	end
	item.pad = nil
	PlotService.refresh(player)
	PlayerState.push(player)
end

function PlotService.equipBest(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if #profile.inventory == 0 then
		return { ok = false, err = "You don't own any brainrots yet." }
	end

	local ranked = table.clone(profile.inventory)
	table.sort(ranked, function(a, b)
		return Economy.powerScore(a.charId, a.variantId) > Economy.powerScore(b.charId, b.variantId)
	end)

	local before = Economy.totalIncome(profile.inventory)
	for _, item in ipairs(profile.inventory) do
		item.pad = nil
	end

	local unlocked = math.min(profile.slots, PlotService.padCapacity(player))
	local placed = 0
	for i = 1, math.min(unlocked, #ranked) do
		ranked[i].pad = i
		placed += 1
	end

	local after = Economy.totalIncome(profile.inventory)
	PlotService.refresh(player)
	PlayerState.push(player)

	return { ok = true, placed = placed, income = after, gained = after - before }
end

function PlotService.buySlot(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end

	local capacity = PlotService.padCapacity(player)
	if profile.slots >= math.min(Config.MaxSlots, capacity) then
		return { ok = false, err = "All pads unlocked." }
	end

	local cost = Economy.slotCost(profile.slots)
	if not cost then
		return { ok = false, err = "All pads unlocked." }
	end
	if profile.money < cost then
		return { ok = false, err = "Need " .. Format.money(cost) .. " for the next pad." }
	end

	profile.money -= cost
	profile.slots += 1

	PlotService.refresh(player)
	PlayerState.push(player)
	PlayerState.notify(player, "Unlocked pad " .. profile.slots .. "!", "good")
	return { ok = true, slots = profile.slots }
end

-- ════════════════════════════════════════════════════════════════════════════
-- ASSIGNMENT
-- ════════════════════════════════════════════════════════════════════════════

local function assignPlot(player)
	for _, plot in ipairs(plots) do
		if plot.userId == nil then
			plot.userId = player.UserId
			byUserId[player.UserId] = plot
			--[[ Published as an attribute so the CLIENT can tell which of the
			     seven bases is its own. It could not before: assignment lives
			     entirely on the server, and the only outward sign was the owner
			     nameplate's text, which is a display string and a bad thing to
			     parse. UI/Friend needs this to stand outside the right door. ]]
			if plot.model then
				plot.model:SetAttribute("OwnerUserId", player.UserId)
			end
			return plot
		end
	end
	warn("[PlotService] no free plot for " .. player.Name)
	return nil
end

local function releasePlot(player)
	local plot = byUserId[player.UserId]
	if not plot then
		return
	end
	byUserId[player.UserId] = nil
	plot.userId = nil
	if plot.model then
		plot.model:SetAttribute("OwnerUserId", nil)
	end

	--[[ Back to the bare studio. A base keeps whatever it was last painted, so
	     without this the next player to claim it walks into the penthouse the
	     last one earned. ]]
	if plot.model then
		HomeService.applyTier(plot.model, 0)
	end

	for _, pad in ipairs(plot.pads) do
		if pad.model then
			pad.model:Destroy()
			pad.model = nil
		end
		pad.part:SetAttribute("StateKey", nil)
		pad.part.Color = pad.baseColor
		pad.part.Material = pad.baseMaterial
		pad.prompt.Enabled = false
	end

	if plot.ownerLabel then
		plot.ownerLabel.Text = mode == "attach" and "Empty Base" or "Empty Plot"
	end
	if plot.rateLabel then
		plot.rateLabel.Text = ""
	end

	-- Re-arm the door so the next occupant inherits a closed base rather than
	-- whatever the previous player happened to leave it as.
end

function PlotService.spawnAt(player, character)
	local plot = byUserId[player.UserId]
	if not plot or not plot.spawnCFrame then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5)
	if root then
		root.CFrame = plot.spawnCFrame
	end
end

PlotService.assign = assignPlot
PlotService.release = releasePlot

function PlotService.mode()
	return mode
end

-- ════════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════════════════

function PlotService.start()
	local bases = findBases()

	if bases then
		mode = "attach"
		for i, base in ipairs(bases) do
			plots[i] = attachPlot(base, i)
		end
		print(string.format(
			"[PlotService] attach mode: %d bases, %d pads each",
			#plots,
			#plots[1].pads
		))
	else
		mode = "generate"
		buildGround()

		local container = Instance.new("Folder")
		container.Name = "Plots"
		container.Parent = Workspace

		for i = 1, GENERATED_PLOT_COUNT do
			plots[i] = buildPlot(i, container)
		end
		print("[PlotService] generate mode: built " .. GENERATED_PLOT_COUNT .. " plots")
	end

	for _, plot in ipairs(plots) do
		for padIndex, pad in ipairs(plot.pads) do
			pad.prompt.Enabled = false
			pad.prompt.Triggered:Connect(function(player)
				if plot.userId ~= player.UserId then
					PlayerState.notify(player, "That's not your base.", "bad")
					return
				end
				local profile = DataService.get(player)
				if not profile then
					return
				end

				local unlocked = math.min(profile.slots, #plot.pads)
				if padIndex > unlocked then
					PlotService.buySlot(player)
				elseif DataService.itemOnPad(profile, padIndex) then
					PlotService.storeBrainrot(player, padIndex)
				else
					Net.get("OpenPicker"):FireClient(player, padIndex)
				end
			end)
		end
	end

	Net.get("PlaceBrainrot").OnServerInvoke = function(player, uid, padIndex)
		return PlotService.placeBrainrot(player, uid, padIndex)
	end

	Net.get("BuySlot").OnServerInvoke = function(player)
		return PlotService.buySlot(player)
	end

	Net.get("EquipBest").OnServerInvoke = function(player)
		return PlotService.equipBest(player)
	end

	Players.PlayerRemoving:Connect(releasePlot)
end

return PlotService
