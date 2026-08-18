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

--[[
	Which way this home faces: across the street, toward the other row of bases.

	TWO EARLIER RULES WERE WRONG, both instructively.

	Hardcoding +X -- the template's native frontage -- worked for Base1 by
	accident and would put three of the seven front doors against a side wall.

	Aiming at the base's own Spawn looked principled and was not. The spawn sits
	about six studs off centre on a base seventy-two deep, so it barely indicates
	a direction; and because it was measured AFTER the building was parented in,
	the bounding box had already grown by 106 studs of apartment, so neighbours
	in the same row came out facing different ways.

	The bases sit in two rows straddling a road -- a 588x178 slab at z=-67 -- so
	the street is what a front door should face. Taken from the rows themselves
	rather than the road's coordinates, so it survives the map being moved.
]]
local function facingOf(base, centre)
	local mean, n = 0, 0
	for _, other in ipairs(base.Parent:GetChildren()) do
		mean += other:GetBoundingBox().Position.Z
		n += 1
	end
	mean = n > 0 and mean / n or centre.Z

	--[[ CFrame.Angles(0, y, 0) sends +X to (cos y, 0, -sin y), so -Z is a
	     quarter turn and +Z is three quarters. Written down rather than
	     rediscovered by trying all four. ]]
	if mean >= centre.Z then
		return Vector3.new(0, 0, 1), -math.pi / 2
	end
	return Vector3.new(0, 0, -1), math.pi / 2
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

	--[[ Worked out BEFORE the building goes in, and off the centre captured at
	     the top. Measured afterwards, the base's bounding box already includes
	     106 studs of apartment and the answer changes -- which is exactly how
	     neighbours in one row ended up facing different directions. ]]
	local facing, yaw = facingOf(base, cf.Position)
	local turn = CFrame.Angles(0, yaw, 0)

	local home = template:Clone()
	home.Name = "Home"
	home.Parent = base

	--[[ Placed by its BOTTOM, measured. The template's pivot is its bounding box
	     centre, so pivoting straight to the deck would bury half the building --
	     the same mistake that sank the race runners. ]]

	home:PivotTo(CFrame.new(cf.Position.X, deck, cf.Position.Z) * turn)
	local hcf, hsize = home:GetBoundingBox()
	home:PivotTo(CFrame.new(
		cf.Position.X,
		deck + hsize.Y / 2,
		cf.Position.Z
	) * turn)

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

	--[[
		FOUR WALLS, AND THE FRONT ONE IS SPLIT.

		Built by side rather than by name so the door can be on any of them --
		three of the seven bases are entered from the opposite end to Base1, and
		a hardcoded front wall put their entrance round the back.

		The gap is left, never cut. Two earlier attempts cut a hole through the
		facade and both re-sealed themselves: first because the test compared
		part positions instead of volumes, then because a 44-stud kerb ran across
		the opening from ten studs away. A gap has nothing to re-seal it with.
	]]
	local SIDES = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}
	local doored = 0
	for _, dir in ipairs(SIDES) do
		local onX = math.abs(dir.X) > 0.5
		local out = onX and hx or hz -- how far to the wall
		local run = onX and hz or hx -- how long the wall is
		local origin = Vector3.new(cx, midY, cz) + dir * out
		local function wall(name, length, shift)
			local size = onX and Vector3.new(WALL, HEIGHT, length)
				or Vector3.new(length, HEIGHT, WALL)
			local along = onX and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
			slab(name, size, origin + along * shift, PLASTER)
		end

		if dir:Dot(facing) > 0.5 then
			local segment = (run * 2 - DOOR_WIDTH) / 2
			for _, sign in ipairs({ -1, 1 }) do
				wall("WallFront", segment, sign * (DOOR_WIDTH + segment) / 2)
				doored += 1
			end
			-- a lintel over the gap, so it reads as a door and not a missing wall
			local lintelSize = onX
				and Vector3.new(WALL, HEIGHT - DOOR_HEIGHT, DOOR_WIDTH)
				or Vector3.new(DOOR_WIDTH, HEIGHT - DOOR_HEIGHT, WALL)
			slab("Lintel", lintelSize,
				Vector3.new(origin.X, deck + DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2, origin.Z),
				PLASTER)
		else
			wall("Wall", run * 2, 0)
		end
	end

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

	--[[
		Slots re-laid against the two long walls.

		PLACED BY THEIR GEOMETRY, NOT THEIR PIVOT. A slot's bounding box sits up
		to twelve studs off its own origin, so setting the pivot to a tidy
		position puts the visible pad somewhere else entirely -- which is how
		brainrots ended up standing through the walls while every check of the
		pivots came back clean. That is the third thing on this project to be
		bitten by pivot-is-not-centre, after the race runners and the building.

		The spread is DERIVED from the pad's own size and the room's inner faces
		rather than being a fraction picked by eye, so a pad can never be laid
		half inside a wall no matter what the room measures.

		Their ORDER is kept: PlotService pairs slot N with pad N and with the
		pending array, so shuffling them would silently move everyone's
		brainrots between pads.
	]]
	local slots = base:FindFirstChild("Slots")
	local moved = 0
	if slots then
		local list = slots:GetChildren()
		table.sort(list, function(a, b)
			return a:GetPivot().Position.Z < b:GetPivot().Position.Z
		end)

		local _, padSize = list[1]:GetBoundingBox()
		local innerX = hx - WALL / 2
		local innerZ = hz - WALL / 2
		local acrossX = innerX - padSize.X / 2 - 2
		local spanZ = math.max(0, innerZ - padSize.Z / 2 - 2)

		for index, slot in ipairs(list) do
			local side = (index <= 4) and -1 or 1
			local rank = ((index - 1) % 4) + 1
			local z = (#list > 4) and (-spanZ + (rank - 1) * (spanZ * 2 / 3)) or 0
			local target = Vector3.new(cx + side * acrossX, deck, cz + z)

			--[[ Aim the BOX at the target, then let the pivot fall where it
			     must. Two steps because the offset can only be measured after
			     the model has been put somewhere. ]]
			slot:PivotTo(CFrame.new(target))
			local box, boxSize = slot:GetBoundingBox()
			local drift = slot:GetPivot().Position - box.Position
			slot:PivotTo(CFrame.new(
				target + Vector3.new(drift.X, drift.Y + boxSize.Y / 2, drift.Z)
			))
			moved += 1
		end
	end

	converted[base] = true
	print(("[HomeService] %s: room %.0f x %.0f x %d at (%.0f, %.0f) | %d map parts hidden, %d facade parts hollowed, %d front segments, %d lights, %d slots, facing %s")
		:format(base.Name, room.halfX * 2, room.halfZ * 2, 18, room.centre.X, room.centre.Z,
			hidden, hollowed, doored, lit, moved,
			(facing.X ~= 0) and (facing.X > 0 and "+X" or "-X") or (facing.Z > 0 and "+Z" or "-Z")))
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
