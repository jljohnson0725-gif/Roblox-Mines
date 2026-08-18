--[[
	HomeService
	Turns a map base into the apartment you live in.

	THE BASE IS NOT DELETED, IT IS UNDRESSED. Its walls and roof are hidden and
	its laser door is removed, but the floor slab, the slots, the spawn, the
	collect zone and PlacedBrainrots all stay exactly where they were -- because
	PlotService reads all of them, and a base that loses its floor drops every
	player on it through the world.

	WHAT DECIDES WHAT GOES: shape, not name. Anything whose top sits more than a
	few studs above the floor is shell -- wall, fence, roof -- and anything at or
	below it is ground. Classifying by name would have meant hardcoding the
	map author's choices, and there are 42 objects per base called Part, Union
	and Model in no useful order.

	THE SLOTS MOVE, and that is the point. The map lays them in a 2x4 grid
	spanning 55x56 studs, which is a car park; the apartment's ground floor is
	about 47x66 inside its walls. So they are re-laid along the two long walls,
	which fits, leaves the middle open to walk through, and turns a lot full of
	livestock into a gallery you show people.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HomeService = {}

--[[ Anything reaching higher than this above the floor is shell and gets
     hidden. The floor slab itself tops out at +0, the fence starts around +8. ]]
local SHELL_ABOVE = 4

--[[ How far a pad is inset from the wall it stands against, and how much of
     the room's depth the four of them span. Fractions, not studs, because the
     interior is MEASURED rather than assumed -- see interiorOf. ]]
local SLOT_INSET = 7
local SLOT_SPREAD = 0.74

--[[ The doorway cut into the front face: how wide, and how tall. Anything of
     the building's own geometry inside that box stops blocking you. ]]
local DOOR_WIDTH = 14
local DOOR_HEIGHT = 13

local converted = {}

--[[
	The floor is whatever the slots are already standing on -- found by CASTING
	A RAY DOWN FROM ONE, not by guessing at shapes.

	The first version looked for "flat and wide and low", which describes this
	base's roof exactly as well as its floor -- 72x1x83 at y+27 against 63x4x73
	at y-1 -- and since it took the highest match it picked the roof, put the
	deck at 27.5, and then found nothing above it to hide. The base came out
	completely untouched with the apartment on its roof.

	A ray cannot make that mistake: whatever holds a slot up IS the floor.
]]
local function floorTop(base)
	local slots = base:FindFirstChild("Slots")
	local slot = slots and slots:GetChildren()[1]
	if not slot then
		return nil
	end
	local from = slot:GetPivot().Position + Vector3.new(0, 6, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { slots, base:FindFirstChild("PlacedBrainrots") }
	local hit = Workspace:Raycast(from, Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y or nil
end

--[[
	The room's real inside, found by casting from its middle until something
	COLLIDABLE stops the ray.

	Not taken from the bounding box, which was the bug behind pads standing
	outside: the building's mass is not centred on its own box -- the back wall
	sits 28 studs one way while the glass frontage is 21 the other -- so a band
	of pads centred on the box pokes straight through the shopfront.

	Collidable only, because the shell meshes are decoration with their
	collision switched off, and a ray that stops on one reports a wall where a
	player would walk through.
]]
local function interiorOf(home, centre, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { home }

	--[[
		A FAN OF RAYS, NOT ONE.

		A single ray down the middle of the glass frontage slipped between two
		window panes and reported no wall at all -- which inflated the room by
		twelve studs on that side and put the doorway search outside the
		building. Sampling across the face and keeping the NEAREST collidable
		hit finds the wall even when the middle of it happens to be a gap.

		Non-collidable hits are walked through rather than counted: the shell
		meshes are scenery with their collision off, and stopping on one reports
		a wall where a player walks straight past.
	]]
	local function reach(dir)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local nearest = nil
		for _, offset in ipairs({ -18, -9, 0, 9, 18 }) do
			local start = Vector3.new(centre.X, y, centre.Z) + side * offset
			local from = start
			for _ = 1, 12 do
				local hit = Workspace:Raycast(from, dir * 150, params)
				if not hit then
					break
				end
				if hit.Instance.CanCollide then
					local d = (hit.Position - start).Magnitude
					if not nearest or d < nearest then
						nearest = d
					end
					break
				end
				from = hit.Position + dir * 0.4
			end
		end
		return nearest or 30
	end

	local xPlus = reach(Vector3.new(1, 0, 0))
	local xMinus = reach(Vector3.new(-1, 0, 0))
	local zPlus = reach(Vector3.new(0, 0, 1))
	local zMinus = reach(Vector3.new(0, 0, -1))

	return {
		centre = Vector3.new(centre.X + (xPlus - xMinus) / 2, y, centre.Z + (zPlus - zMinus) / 2),
		halfX = (xPlus + xMinus) / 2,
		halfZ = (zPlus + zMinus) / 2,
		frontX = centre.X + xPlus,
	}
end

function HomeService.convert(base)
	if not base or converted[base] then
		return false
	end
	local template = ReplicatedStorage:FindFirstChild("ApartmentTemplate")
	if not template then
		warn("[HomeService] no ApartmentTemplate; base left alone")
		return false
	end

	local cf, size = base:GetBoundingBox()
	local ground = cf.Position.Y - size.Y / 2
	local deck = floorTop(base) or (ground + 4)

	--[[ Hidden, not destroyed. The map is the source of these and a future
	     change of mind should not need a re-export -- and destroying map
	     geometry is the one thing here that cannot be undone at runtime. ]]
	local hidden = 0
	for _, c in ipairs(base:GetChildren()) do
		local isShell = false
		if c:IsA("BasePart") then
			isShell = (c.Position.Y + c.Size.Y / 2) > deck + SHELL_ABOVE
		elseif c:IsA("Model") then
			local mcf, msize = c:GetBoundingBox()
			isShell = (mcf.Position.Y + msize.Y / 2) > deck + SHELL_ABOVE
		end
		if isShell then
			for _, d in ipairs(c:IsA("BasePart") and { c } or c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = 1
					--[[
						COLLISION COMES OFF TALL THINGS ONLY.

						A wall blocks you and has to go; a slab never does, so
						it can keep its collision and stay a floor. Two earlier
						rules both got this wrong -- the first decollided
						everything it hid, the second used height above the
						deck, and both punched holes in the floor because the
						base's ground is made of several flat pieces at
						different heights.

						This was invisible to every check I ran, because
						RAYCASTS HIT NON-COLLIDABLE PARTS: "floor below:
						Bases.Base1.Part" kept coming back true while the player
						fell through it. Any future check here has to read
						CanCollide, not just whether a ray landed.
					]]
					if d.Size.Y > 6 then
						d.CanCollide = false
					end
					hidden += 1
				end
			end
		end
	end

	--[[ The laser door goes entirely. It exists to kill people who try to walk
	     in, which is a rule from a game about stealing -- and nobody steals
	     here. The apartment has a door instead. ]]
	local lock = base:FindFirstChild("Lock")
	if lock then
		lock.Transparency = 1
		lock.CanCollide = false
		lock.CanTouch = false
	end

	local home = template:Clone()
	home.Name = "Home"
	home.Parent = base

	--[[ Placed by its BOTTOM, measured. The template's pivot is its bounding box
	     centre, so pivoting straight to the deck would bury half the building --
	     the same mistake that sank the race runners. ]]
	home:PivotTo(CFrame.new(cf.Position.X, deck, cf.Position.Z))
	local hcf, hsize = home:GetBoundingBox()
	home:PivotTo(CFrame.new(
		cf.Position.X,
		deck + (hcf.Position.Y - (hcf.Position.Y - hsize.Y / 2)),
		cf.Position.Z
	))

	--[[
		THE SHELL MESHES ARE SCENERY, NOT WALLS.

		They ship with CollisionFidelity = Box, which collides a hollow building
		as a filled brick -- the ground floor was solid and there was no way to
		stand in it. That property cannot be changed: assigning it at runtime is
		accepted and silently ignored, and emitting it into the place file did
		not apply either.

		So collision comes off the meshes and stays on the thin Parts, which are
		the actual walls and are boxes anyway. The room ends up bounded by the
		same surfaces you can see, and nothing depends on a property Roblox will
		not let us set.
	]]
	local hollowed = 0
	for _, d in ipairs(home:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d:IsA("MeshPart") then
				d.CanCollide = false
				hollowed += 1
			end
		end
	end

	local room = interiorOf(home, cf.Position, deck + 6)

	--[[
		THE BUILDING IS A FACADE. THE ROOM IS OURS.

		This was the wrong way round for a while and it showed: the shell's walls
		are SINGLE-SIDED geometry, built to be looked at from outside, so from
		within a player sees straight through them to the sky and the sun glares
		in. Cutting a doorway through someone else's facade was solving the wrong
		problem -- that model's ground floor was never meant to be entered.

		So the shell keeps its looks and loses all its collision, and every
		surface a player actually touches -- four walls, a ceiling, a floor, and a
		gap to walk through -- is built here, opaque and double-sided because a
		Part always is. It also means the doorway is a gap we LEAVE rather than a
		hole we cut, which is why it cannot silently seal itself again.
	]]
	local hollowed = 0
	for _, d in ipairs(home:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			hollowed += 1
		end
	end

	local shell = Instance.new("Model")
	shell.Name = "Interior"
	shell.Parent = home

	local function slab(name, size, position, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = true
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.Color = color
		p.Material = material or Enum.Material.Plaster
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = shell
		return p
	end

	--[[ Pulled a stud inside the measured walls so our surfaces sit just behind
	     the facade rather than fighting it for the same plane. ]]
	local hx = room.halfX - 1
	local hz = room.halfZ - 1
	local cx, cz = room.centre.X, room.centre.Z
	local WALL = 1.5
	--[[ Warm grey, not white. The first pass used near-white plaster with four
     bright lights and the room came out blown out -- every surface at once,
     no shading, no corners. A darker wall gives the light something to fall
     off. ]]
local PLASTER = Color3.fromRGB(150, 141, 128)

	--[[ Eighteen studs, not thirteen. The third-person camera sits about twelve
	     studs back and up, so a low ceiling jams it into the floor and points it
	     at your feet -- which is what made the first look inside unreadable. ]]
	local HEIGHT = 18
	local midY = deck + HEIGHT / 2

	slab("Floor", Vector3.new(hx * 2, 0.6, hz * 2),
		Vector3.new(cx, deck + 0.3, cz),
		Color3.fromRGB(96, 68, 44), Enum.Material.WoodPlanks)

	slab("Ceiling", Vector3.new(hx * 2, 0.8, hz * 2),
		Vector3.new(cx, deck + HEIGHT, cz), PLASTER)

	-- back and the two sides, whole
	slab("WallBack", Vector3.new(WALL, HEIGHT, hz * 2),
		Vector3.new(cx - hx, midY, cz), PLASTER)
	slab("WallLeft", Vector3.new(hx * 2, HEIGHT, WALL),
		Vector3.new(cx, midY, cz - hz), PLASTER)
	slab("WallRight", Vector3.new(hx * 2, HEIGHT, WALL),
		Vector3.new(cx, midY, cz + hz), PLASTER)

	--[[ The front, in two pieces with a gap between them. A gap cannot be
	     accidentally re-sealed by a part we failed to notice, which is what
	     happened twice while this was a hole cut through the facade. ]]
	local sideZ = (hz * 2 - DOOR_WIDTH) / 2
	local doored = 0
	for _, sign in ipairs({ -1, 1 }) do
		slab("WallFront", Vector3.new(WALL, HEIGHT, sideZ),
			Vector3.new(cx + hx, midY, cz + sign * (DOOR_WIDTH + sideZ) / 2), PLASTER)
		doored += 1
	end
	-- a lintel over the opening, so the gap reads as a door and not a missing wall
	slab("Lintel", Vector3.new(WALL, HEIGHT - DOOR_HEIGHT, DOOR_WIDTH),
		Vector3.new(cx + hx, deck + DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2, cz), PLASTER)

	--[[ Lights, because an enclosed room under a solid ceiling is pitch black.
	     Four on a grid rather than one bright one: a single source pools in the
	     middle and leaves the pads, which stand against the walls, in the dark. ]]
	local lit = 0
	for _, sx in ipairs({ -0.45, 0.45 }) do
		for _, sz in ipairs({ -0.45, 0.45 }) do
			local bulb = Instance.new("Part")
			bulb.Name = "Bulb"
			bulb.Anchored = true
			bulb.CanCollide = false
			bulb.Size = Vector3.new(4, 0.3, 4)
			bulb.CFrame = CFrame.new(cx + hx * sx, deck + HEIGHT - 1.2, cz + hz * sz)
			bulb.Color = Color3.fromRGB(255, 238, 205)
			bulb.Material = Enum.Material.Neon
			bulb.Parent = shell

			local light = Instance.new("PointLight")
			--[[ Tuned down hard from 3 / 52. Four sources at that strength in a
			     49x68 room overlapped into a single flat wash that washed the
			     walls white and lost every corner. These four together should
			     LIGHT the room, not erase it. ]]
			light.Brightness = 1.1
			light.Range = 32
			light.Color = Color3.fromRGB(255, 240, 210)
			light.Shadows = false -- four shadow casters indoors is a frame-rate bill
			light.Parent = bulb
			lit += 1
		end
	end

	--[[ Slots re-laid against the two long walls, off the MEASURED room rather
	     than the base's centre. Their ORDER is kept -- PlotService pairs slot N
	     with pad N and with the pending array, so shuffling them would silently
	     move everyone's brainrots between pads. ]]
	local slots = base:FindFirstChild("Slots")
	local moved = 0
	if slots then
		local list = slots:GetChildren()
		table.sort(list, function(a, b)
			return a:GetPivot().Position.Z < b:GetPivot().Position.Z
		end)
		local span = room.halfZ * SLOT_SPREAD
		for index, slot in ipairs(list) do
			local side = (index <= 4) and -1 or 1
			local rank = ((index - 1) % 4) + 1
			local z = -span + (rank - 1) * (span * 2 / 3)
			local target = Vector3.new(
				room.centre.X + side * (room.halfX - 1 - SLOT_INSET),
				deck,
				room.centre.Z + z
			)
			local scf, ssize = slot:GetBoundingBox()
			local lift = deck - (scf.Position.Y - ssize.Y / 2)
			slot:PivotTo(CFrame.new(target + Vector3.new(0, lift, 0))
				* CFrame.Angles(0, side > 0 and math.rad(180) or 0, 0))
			moved += 1
		end
	end

	converted[base] = true
	print(("[HomeService] %s: room %.0f x %.0f x %d at (%.0f, %.0f) | %d map parts hidden, %d facade parts hollowed, %d front segments, %d lights, %d slots")
		:format(base.Name, room.halfX * 2, room.halfZ * 2, 18, room.centre.X, room.centre.Z,
			hidden, hollowed, doored, lit, moved))
	return true
end

function HomeService.start(only)
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then
		return
	end
	for _, base in ipairs(bases:GetChildren()) do
		if not only or base.Name == only then
			local ok, err = pcall(HomeService.convert, base)
			if not ok then
				warn(("[HomeService] %s failed: %s"):format(base.Name, tostring(err)))
			end
		end
	end
end

return HomeService
