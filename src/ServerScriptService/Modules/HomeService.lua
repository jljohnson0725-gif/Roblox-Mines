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

local Rebirth = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rebirth"))

local HomeService = {}

--[[ Anything reaching higher than this above the floor is shell and gets
     hidden. The floor slab itself tops out at +0, the fence starts around +8. ]]
local SHELL_ABOVE = 4

--[[ How far a pad is inset from the wall it stands against, and how much of
     the room's depth the four of them span. Fractions, not studs, because the
     interior is MEASURED rather than assumed -- see interiorOf. ]]
local SLOT_INSET = 7
local SLOT_SPREAD = 0.74

--[[ How much floor one standing brainrot needs. Models are scaled toward
     `defaultTarget` (9.0) in meshes.json, so this is that plus nothing: it is
     the width the layout must keep between neighbours and off the walls. ]]
local BRAINROT_WIDTH = 9

--[[ The doorway cut into the front face: how wide, and how tall. Anything of
     the building's own geometry inside that box stops blocking you. ]]
local DOOR_WIDTH = 14
local DOOR_HEIGHT = 13

--[[
	How far a floor-laid part sits above the floor, and why it is not zero.

	Two faces pointing the same way at the same height are the definition of
	z-fighting: the renderer has no way to order them, so it picks per pixel per
	frame and the surface boils. It only bites when the faces point the SAME way
	-- a rug's underside resting exactly on the floor is fine, because the floor
	is behind it and gets culled -- which is why the collect pad flickered and
	the carpet, sitting on the same plane, never did.

	Anything laid on the floor is lifted clear by this instead.
]]
local FLOOR_LIFT = 0.06

--[[
	THE COLLECT RING: how far from the desk banking happens, and where the ring
	sits relative to the desk.

	Deliberately generous. The thing this replaced was a 14x14 slab you had to
	stand ON, and the reason it was that big is that it was the trigger and the
	sign for the trigger at once. Splitting those means the ring can read as
	furniture-scale while the radius stays forgiving -- you should never be
	stood next to your own desk wondering why nothing happened.

	The ring is offset toward the door rather than centred on the desk, because
	a circle centred on a 13-stud desk is half underneath it.
]]
local COLLECT_RADIUS = 9
local RING_STANDOFF = 5
local RING_COLOR = Color3.fromRGB(178, 240, 200)

--[[
	A cash register. Verified as audio before wiring: AssetTypeId 3,
	"cash-register-sound-fx", 1.045 seconds.

	Worth the check. The first id given for this was 524440363, which is the
	DESK MODEL -- AssetTypeId 10 -- given twice by mistake, and a Sound pointed
	at a model does not error, it just never plays. The placeholder that stood
	in meanwhile was the unlock sting, which is why collecting sounded exactly
	like buying a pad.
]]
local COLLECT_SOUND = 120891770644830

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
				--[[
					A DECAL DOES NOT CARE THAT ITS PART IS INVISIBLE.

					Transparency = 1 on a BasePart hides the part and nothing
					stuck to it: Decals and Textures keep drawing at their own
					transparency, floating exactly where the surface used to be.

					That is what "the floating windows" were the whole time. The
					base's window walls are six Unions, thin and ten studs tall,
					each carrying six Decals at 0.5 -- so hiding the Unions left
					six sheets of glass standing in the open. It survived every
					hunt because every probe I wrote read the PART's transparency,
					saw 1.00, and moved on. The part was invisible. The glass on
					it was not.
				]]
				if d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = 1
				end
				if d:IsA("BasePart") then
					d.Transparency = 1
					for _, skin in ipairs(d:GetChildren()) do
						if skin:IsA("Decal") or skin:IsA("Texture") then
							skin.Transparency = 1
						end
					end
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

	--[[
		THE GROUND-FLOOR SHELL COMES OFF ENTIRELY.

		Our doorway is a gap in OUR wall, but the template's ground floor is one
		mesh that runs straight across it -- and that mesh is single-sided. From
		inside it is invisible and the doorway looked open; from outside it is
		opaque and the doorway looked like a wall. Same surface, two answers,
		which is the tell for single-sided geometry every time.

		A hole cannot be cut in a mesh, and its collision is a Box no matter what
		fidelity is asked for, so there is nothing to subtract. The mesh goes.
		What replaces it is our own wall, which is WIDER than the mesh in both
		directions (66x49 against 50x70's frontage) -- so the building keeps an
		exterior, it is just ours, with our windows and our cased door in it.

		Only the ground floor. Everything above still hangs there, which is the
		whole point of the building being tall.
	]]
	--[[ No "is this ours?" guard, deliberately: this runs BEFORE the Interior
	     model is built, so everything under `home` is template geometry by
	     definition. The guard was there in the first draft and it matched
	     nothing at all -- IsDescendantOf against a folder that does not exist
	     yet is false for every part, so the loop hid zero meshes and the
	     doorway stayed walled. ]]
	local unshelled = 0
	for _, d in ipairs(home:GetDescendants()) do
		if d:IsA("MeshPart")
			and d.Size.X > 45 and d.Size.Y < 16
			and d.Position.Y - d.Size.Y / 2 < deck + 2
		then
			d.Transparency = 1
			unshelled += 1
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

--[[ Skirting, window sills and the door casing. Build colour only -- applyTier
     repaints all of it, so this is just what an unclaimed room wears. ]]
local TRIM = Color3.fromRGB(88, 84, 78)

	--[[ Eighteen studs, not thirteen. The third-person camera sits about twelve
	     studs back and up, so a low ceiling jams it into the floor and points it
	     at your feet -- which is what made the first look inside unreadable. ]]
	local HEIGHT = 18
	local midY = deck + HEIGHT / 2

	local floorSlab = slab("Floor", Vector3.new(hx * 2, 0.6, hz * 2),
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
	local windows = 0
	for _, dir in ipairs(SIDES) do
		local onX = math.abs(dir.X) > 0.5
		local out = onX and hx or hz -- how far to the wall
		local run = onX and hz or hx -- how long the wall is
		local origin = Vector3.new(cx, midY, cz) + dir * out
		local along = onX and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)

		--[[ `span` is the length of a piece measured ALONG the wall; thickness
		     and height are the same whichever wall it is. Everything below is
		     built through this so a piece can never be laid out sideways. ]]
		local function piece(name, span, height, shift, y, thick, color, material)
			local t = thick or WALL
			local size = onX and Vector3.new(t, height, span)
				or Vector3.new(span, height, t)
			local at = origin + along * shift
			return slab(name, size,
				Vector3.new(at.X, y or midY, at.Z), color or PLASTER, material)
		end

		--[[ A skirting board, which is the cheapest thing on this list and does
		     the most work. A box of flat planes reads as a box; the same box
		     with a dark line where wall meets floor reads as a room. ]]
		local function skirting(span, shift)
			local p = piece("Skirting", span, 2.2, shift, deck + 1.1,
				WALL * 0.45, TRIM, Enum.Material.Wood)
			p.CFrame = p.CFrame - dir * (WALL * 0.4)
			p.CanCollide = false
		end

		--[[
			A WINDOWED RUN OF WALL: a sill band, a header band, and piers between
			the openings, with glass filling each gap.

			Openings are SIZED FROM THE RUN, not picked -- the count drops until
			the piers are at least three studs, so one function gives the 47-stud
			side walls three windows, the 66-stud back wall four, and the two
			26-stud segments beside the front door one each. It can never produce
			a run that is more hole than wall, and a run too short for a window
			just comes back solid.

			The glass is COLLIDABLE. The gap in the front wall is a doorway
			precisely because nothing fills it; these must not become eight more.
		]]
		local function windowed(name, length, shift)
			local openW = 10
			local count = math.floor(length / 16)
			local pier = count > 0 and (length - count * openW) / (count + 1) or 0
			while count > 1 and pier < 3 do
				count -= 1
				pier = (length - count * openW) / (count + 1)
			end

			if count < 1 then
				piece(name, length, HEIGHT, shift)
				skirting(length, shift)
				return
			end

			local sillTop = deck + 5
			local headBot = deck + 12
			local headH = deck + HEIGHT - headBot

			piece(name, length, 5, shift, deck + 2.5)
			piece(name, length, headH, shift, headBot + headH / 2)
			skirting(length, shift)

			local left = shift - length / 2
			for i = 0, count do
				piece(name, pier, headBot - sillTop,
					left + pier / 2 + i * (pier + openW), (sillTop + headBot) / 2)
			end

			for j = 0, count - 1 do
				local at = left + pier + openW / 2 + j * (pier + openW)
				local pane = piece("WindowPane", openW, headBot - sillTop, at,
					(sillTop + headBot) / 2, WALL * 0.35,
					Color3.fromRGB(226, 240, 248), Enum.Material.Glass)
				pane.Transparency = 0.62
				pane.Reflectance = 0.08

				--[[ A ledge, proud of the wall on the inside. It catches the
				     light coming through and gives the opening a bottom edge,
				     which is what stops a window reading as a painted rectangle. ]]
				--[[ Hung a touch low on purpose: level with the opening its
				     underside shared a plane with the pane's and the wall's,
				     three down-facing faces in one spot. ]]
				local ledge = piece("WindowSill", openW + 2, 0.5, at,
					sillTop + 0.17, WALL * 2.2, TRIM, Enum.Material.Wood)
				ledge.CFrame = ledge.CFrame - dir * (WALL * 0.5)
				ledge.CanCollide = false
				windows += 1
			end
		end

		if dir:Dot(facing) > 0.5 then
			local segment = (run * 2 - DOOR_WIDTH) / 2
			for _, sign in ipairs({ -1, 1 }) do
				windowed("WallFront", segment, sign * (DOOR_WIDTH + segment) / 2)
				doored += 1
			end
			-- a lintel over the gap, so it reads as a door and not a missing wall
			piece("Lintel", DOOR_WIDTH, HEIGHT - DOOR_HEIGHT, 0,
				deck + DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2)

			--[[ A CASED OPENING, not just a hole. Two jambs and a head in the
			     trim colour, standing slightly proud of the wall. Without them
			     the entrance was a rectangle of missing wall -- which is what it
			     is, but a doorway is the one place a room should not look like
			     it was built by subtraction. ]]
			--[[ The casing sits INSIDE the opening, not above it. The head used
			     to hang at DOOR_HEIGHT + 0.7, which put its underside on exactly
			     the same plane as the lintel's -- two down-facing faces over a
			     14-stud strip, both visible from below, boiling against each
			     other. Now the head occupies the top of the opening and the
			     lintel's underside is behind it, occluded rather than tied. ]]
			local headBottom = deck + DOOR_HEIGHT - 1.4
			for _, sign in ipairs({ -1, 1 }) do
				local jamb = piece("DoorJamb", 1.4, DOOR_HEIGHT - 1.4,
					sign * (DOOR_WIDTH + 1.4) / 2, deck + (DOOR_HEIGHT - 1.4) / 2,
					WALL * 1.5, TRIM, Enum.Material.Wood)
				jamb.CanCollide = false
			end
			local head = piece("DoorHead", DOOR_WIDTH + 2.8, 1.4, 0,
				headBottom + 0.7, WALL * 1.5, TRIM, Enum.Material.Wood)
			head.CanCollide = false
		else
			windowed("Wall", run * 2, 0)
		end
	end

	--[[
		THE GROUND FLOOR'S OWN SHOPFRONT GOES.

		The template's ground floor is a glazed storefront: 8x10 glass panels
		hung on a metal mullion grid, sitting about a third of a stud in front of
		where our wall now stands. Our wall has its own windows cut into it and
		they do not line up, so looking out through one of ours you saw a sheet
		of glass and a grid of frames hanging in mid-air with daylight behind
		them. That is the "floating windows outside".

		BOTH MATERIALS, because removing only the glass left the frames -- and an
		empty frame floating in front of a wall reads worse than a glazed one.
		The frame is one 42x10x42 metal mesh, which is also why probing this by
		raycast kept coming back as the concrete wall behind it: a sparse fan of
		rays slips between mullions and reports whatever is behind them. It took
		a dense sweep to catch it.

		Only the GROUND FLOOR goes. The upper storeys are glazed the same way and
		none of it is redundant up there, because there is no room of ours behind
		it -- so the cut-off is the height of our ceiling, and the 47x11x64 slabs
		that start above it are left exactly as they are.

		The colonnade stays. Columns and the cornice above them give the entrance
		a porch, and none of them read as floating -- they meet the ground.
	]]
	local deglazed = 0
	for _, part in ipairs(home:GetDescendants()) do
		local skin = part:IsA("BasePart")
			and (part.Material == Enum.Material.Glass
				or part.Material == Enum.Material.Metal)
		if skin and not part:IsDescendantOf(shell)
			and part.Position.Y - part.Size.Y / 2 < deck + HEIGHT - 3
			and part.Position.Y + part.Size.Y / 2 > deck
		then
			part.Transparency = 1
			part.CanCollide = false
			deglazed += 1
		end
	end

	--[[
		CLEAR THE DOORWAY.

		Leaving a gap in OUR wall does not make a hole in the building: the
		template has its own front door standing in that spot -- two panels, a
		column, and a couple of trim bands -- and since every facade part was
		made non-collidable you walk straight through them. The result reads as
		walking through a solid wall, which is worse than a wall you cannot pass.

		So anything of the template standing in the opening is hidden outright.
		The filter is by SIZE, because the same box also contains the building's
		floor slab and its ground-floor mass, and hiding those would take a
		chunk out of the building. A part goes only if it is door-sized (no
		horizontal dimension much wider than the doorway) or a thin panel --
		which is what a door leaf, a column and a trim band are, and what a
		50x15x70 structural block is not.
	]]
	local doorOut = (math.abs(facing.X) > 0.5) and hx or hz
	local doorAt = Vector3.new(cx, deck + DOOR_HEIGHT / 2, cz) + facing * doorOut
	local doorBox = (math.abs(facing.X) > 0.5)
		and Vector3.new(WALL * 4, DOOR_HEIGHT, DOOR_WIDTH)
		or Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, WALL * 4)

	local doorParams = OverlapParams.new()
	doorParams.FilterType = Enum.RaycastFilterType.Include
	doorParams.FilterDescendantsInstances = { home }
	doorParams.MaxParts = 120

	local cleared = 0
	for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(doorAt), doorBox, doorParams)) do
		if not part:IsDescendantOf(shell) then
			local widest = math.max(part.Size.X, part.Size.Z)
			local thinnest = math.min(part.Size.X, part.Size.Y, part.Size.Z)
			if widest <= DOOR_WIDTH * 1.2 or thinnest <= 0.5 then
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
				cleared += 1
			end
		end
	end

	--[[
		GIVE THE OUTSIDE ITS COLLISION BACK.

		Hollowing the whole facade is what made the stoop and its steps walk-
		through: they are part of the template, so they lost collision along with
		the walls. But the reason for hollowing was MESHES -- a MeshPart's
		CollisionFidelity is stuck at Box (asking for anything else is accepted
		and ignored, and emitting it into the place file does not apply either),
		so a hollow shell mesh collides as a filled brick. Plain Parts have no
		such problem; a Part is exactly the box it looks like.

		So: plain Parts get their collision back, meshes stay off. Two guards on
		top of that, both of which would otherwise produce something worse than
		the bug being fixed --

		  - OUTSIDE THE ROOM ONLY. Template parts standing inside our walls would
		    become furniture nobody can walk past, in a room whose whole job is
		    holding brainrots.
		  - VISIBLE ONLY. Everything hidden above -- the doorway blockers, the
		    shopfront -- is still there at Transparency 1. Re-solidifying those
		    would put an invisible wall exactly where the door is.
	]]
	local resolid = 0
	local roomX = floorSlab.Size.X / 2 + 2
	local roomZ = floorSlab.Size.Z / 2 + 2
	for _, d in ipairs(home:GetDescendants()) do
		if d:IsA("Part") and not d:IsDescendantOf(shell) and d.Transparency < 0.9 then
			local dx = math.abs(d.Position.X - floorSlab.Position.X)
			local dz = math.abs(d.Position.Z - floorSlab.Position.Z)
			if dx > roomX or dz > roomZ then
				d.CanCollide = true
				resolid += 1
			end
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

		--[[
			STEP 1 -- put each slot back together.

			A map slot is three parts: `Spawn`, an invisible 1x1 marker where the
			brainrot stands, and `Part`/`Collect`, the visible strip -- sitting
			TWELVE STUDS AWAY from it. Nothing marks where the brainrot actually
			stands, so a brainrot appeared to float on bare floor while a grey
			slab lay a body-length behind it.

			That gap also poisoned the layout. The model's bounding box spanned
			marker AND strip, so its centre was six studs from either, and every
			"place the box at X" put the brainrot six studs off X. It is the same
			pivot-is-not-centre trap as before wearing a different hat: this time
			the box was honest and the box was not the thing being positioned.

			So the strip moves under the marker and becomes what it was always
			being read as -- the plinth the brainrot stands on. After this the
			box IS the plinth, and placing it means what it says.
		]]
		for _, slot in ipairs(list) do
			local marker = slot:FindFirstChild("Spawn")
			if marker and marker:IsA("BasePart") then
				for _, piece in ipairs(slot:GetChildren()) do
					if piece:IsA("BasePart") and piece ~= marker then
						piece.Position = Vector3.new(
							marker.Position.X, piece.Position.Y, marker.Position.Z)
					end
				end
			end
		end

		--[[
			STEP 2 -- lay them out in two facing rows.

			Sorted the way PlotService sorts (column, then depth) so that the
			names written below match the pad indices it hands out; pad N is
			saved in the profile, so any disagreement moves everyone's brainrots.

			The spread is derived from the BRAINROT's width, not the plinth's.
			The plinth is under nine studs across but the models are scaled to
			about nine, so four slots packed to the plinth spacing overlapped --
			three brainrots stood inside each other. What must not collide is the
			thing you can see.
		]]
		table.sort(list, function(a, b)
			local pa, pb = a:GetPivot().Position, b:GetPivot().Position
			if math.abs(pa.X - pb.X) > 0.5 then
				return pa.X < pb.X
			end
			return pa.Z < pb.Z
		end)

		local innerX = hx - WALL / 2
		local innerZ = hz - WALL / 2
		local acrossX = math.max(0, innerX - BRAINROT_WIDTH / 2 - 1.5)
		local spanZ = math.max(0, innerZ - BRAINROT_WIDTH / 2 - 1.5)

		local perRow = math.ceil(#list / 2)
		for index, slot in ipairs(list) do
			local side = (index <= perRow) and -1 or 1
			local rank = ((index - 1) % perRow) + 1
			local z = (perRow > 1) and (-spanZ + (rank - 1) * (spanZ * 2 / (perRow - 1))) or 0
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

			--[[ Facing stated outright rather than inferred. PlotService used to
			     read it from strip-minus-marker, which now points nowhere since
			     they share a spot -- and which was wrong anyway: it aimed every
			     brainrot down -Z whichever wall it stood against. The two rows
			     turn to look at each other across the aisle, so walking in from
			     the door you see faces, not backs. ]]
			slot:SetAttribute("Facing", Vector3.new(-side, 0, 0))
			slot.Name = "Slot" .. index
			moved += 1
		end
	end

	--[[
		THE OLD GROUND-FLOOR BASE, OUTSIDE THE ROOM.

		The apartment is built over one corner of the plot the map ships, and
		everything the plot had outside that corner is still standing: the
		checkerboard tiling running out past the walls, and the pad platforms the
		slots used to sit on before they were moved indoors. From the street it
		reads as the base this replaced, half demolished.

		Measured rather than assumed. Of the eight 16x16 platforms, four sit
		inside the room with a slot on them and four are orphans -- nearest slot
		eleven studs away -- and 65 of the 194 floor tiles fall outside the walls.
		Only the orphans go.

		HIDDEN, NOT DELETED, like everything else here: collision stays so a
		player wandering the plot still has ground under them, and a base can be
		re-dressed by putting the transparency back.
	]]
	--[[
		THE ROOM'S FOOTPRINT, PUBLISHED.

		PlotService tiles the plot AFTER this runs, and it destroys and rebuilds
		the whole TileFloor when it does -- so hiding stray tiles from here is
		undone a moment later by a module that has never heard of the apartment.
		Tried exactly that first: the pads stripped and stayed stripped, the 65
		tiles came straight back.

		So the bounds go on the base as attributes and PlotService skips
		anything outside them. Attributes rather than a require, because the
		dependency only runs one way and should stay that way.
	]]
	base:SetAttribute("RoomX", floorSlab.Position.X)
	base:SetAttribute("RoomZ", floorSlab.Position.Z)
	base:SetAttribute("RoomHalfX", floorSlab.Size.X / 2 + 2)
	base:SetAttribute("RoomHalfZ", floorSlab.Size.Z / 2 + 2)

	local strippedPads = 0
	local outX = floorSlab.Size.X / 2 + 2
	local outZ = floorSlab.Size.Z / 2 + 2
	local function outsideRoom(pos)
		return math.abs(pos.X - floorSlab.Position.X) > outX
			or math.abs(pos.Z - floorSlab.Position.Z) > outZ
	end

	--[[
		AND THE MAP'S OWN COLLECT PAD, which is the big green square out front.

		PlotService documents it as deliberately unused: it sits at z -151 while
		the old laser door was at z -157, which put it outside your own security
		door. Collection happens at the per-slot strips, and the ring at the desk
		has its own invisible CollectZone inside the room. So the green slab in
		the street is signage for a mechanic that does not exist.

		Only the map's own -- matched as a DIRECT CHILD of the base and only when
		it falls outside the room, so the interior one built above is never in
		scope no matter that they share a name.
	]]
	local mapZone = base:FindFirstChild("CollectZone")
	if mapZone and mapZone:IsA("BasePart") and outsideRoom(mapZone.Position) then
		local at = mapZone.Position
		mapZone.Transparency = 1
		strippedPads += 1
		--[[ The plinth under it goes too, or the pad leaves a grey rectangle
		     exactly its own size behind. ]]
		for _, d in ipairs(base:GetChildren()) do
			if d:IsA("BasePart") and d ~= mapZone and d.Transparency < 0.99
				and math.abs(d.Position.Y - at.Y) < 3
				and math.abs(d.Position.X - at.X) < 8
				and math.abs(d.Position.Z - at.Z) < 8
			then
				d.Transparency = 1
				strippedPads += 1
			end
		end
	end

	--[[ A pad platform is a ~16x16 slab of the plot's own dressing. One with a
	     slot standing on it is in use; one without is what the slot left behind
	     when it moved inside. ]]
	for _, child in ipairs(base:GetChildren()) do
		if child:IsA("Model") and child ~= home and child.Name ~= "PlacedBrainrots" then
			local cf, size = child:GetBoundingBox()
			if math.abs(size.X - 16) < 3 and math.abs(size.Z - 16) < 3
				and outsideRoom(cf.Position) then
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") and d.Transparency < 0.99 then
						d.Transparency = 1
						strippedPads += 1
					end
				end
			end
		end
	end

	--[[
		A RUNNER DOWN THE AISLE.

		Laid between the two slot rows and stopped SHORT OF THE COLLECT PAD rather
		than run the length of the room: both sit just above the floor, so
		overlapping them would put the rug over the one tile the player is meant to
		stand on.

		Aimed off `facing` rather than off X or Z, because three of the seven bases
		are entered from the opposite end and a rug hardcoded to one axis lies
		sideways in those.
	]]
	local rug = Instance.new("Part")
	rug.Name = "Carpet"
	rug.Anchored = true
	rug.CanCollide = false
	rug.Size = (math.abs(facing.X) > 0.5)
		and Vector3.new(26, 0.12, math.min(24, hz * 0.9))
		or Vector3.new(math.min(24, hx * 0.6), 0.12, 26)
	rug.CFrame = CFrame.new(
		Vector3.new(cx, deck + 0.6 + FLOOR_LIFT + 0.06, cz) - facing * 6)
	rug.Color = TRIM
	rug.Material = Enum.Material.Fabric
	rug.TopSurface = Enum.SurfaceType.Smooth
	rug.BottomSurface = Enum.SurfaceType.Smooth
	rug.Parent = shell

	--[[
		THE DESK, AT THE FAR END OF THE AISLE.

		This replaces a 14x14 slab of neon lying in the walkway. The slab was
		honest -- stand here, get paid -- and it looked like a debug volume,
		because it WAS the trigger as well as the sign for it. Separating those
		is what lets the collector be furniture: the desk is the thing you see,
		a ring on the floor is the thing you read, and the trigger is a radius
		neither of them has to match.

		Put at the BACK, not by the door, so the walk to it runs the length of
		your own collection. The room stops being a corridor with a pad in it
		and becomes somewhere you walk past your brainrots to reach the machine
		that pays you. It is also the machine the endgame runs on -- the
		peptides get ordered from this desk -- so it earns being the thing at
		the end of the room.
	]]
	local deskTemplate = ReplicatedStorage:FindFirstChild("DeskTemplate")
	local backReach = (math.abs(facing.X) > 0.5) and hx or hz
	if deskTemplate then
		local desk = deskTemplate:Clone()
		desk.Name = "Desk"

		--[[ The rig is approached from its -X side (chair at x=-2.5, desk top
		     at x=+1.5), so local +X has to point AWAY from the door. Built with
		     fromMatrix rather than a yaw angle because "which way does +X go"
		     is the thing being stated; an angle would need rediscovering. ]]
		local deskAt = Vector3.new(cx, deck + 0.6, cz) - facing * (backReach - 7)
		local aim = CFrame.fromMatrix(deskAt, -facing, Vector3.new(0, 1, 0))

		--[[ PLACED BY ITS BOX, NOT ITS PIVOT, and standing on the floor rather
		     than centred on it. A model's pivot is wherever the asset's author
		     left it -- for this rig it is the bounding-box centre, so pivoting
		     to floor level buried the desk 5.6 studs under it. Aim, measure the
		     drift, aim again: the offset can only be known once the model is
		     somewhere. Fifth time this project has paid for pivot-is-not-centre,
		     after the race runners, the building, the pads and the saddle. ]]
		desk:PivotTo(aim)
		local box, boxSize = desk:GetBoundingBox()
		local drift = desk:GetPivot().Position - box.Position
		desk:PivotTo(aim + drift + Vector3.new(0, boxSize.Y / 2, 0))
		desk.Parent = shell

		for _, part in ipairs(desk:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = true
			end
		end

		--[[
			THE MONITOR, BUILT RATHER THAN IMPORTED.

			The asset's own computer was 72 cubes and it read as a white blob --
			see the note in assets/desk.psv. This is four parts: a foot, a stem,
			a bezel and a screen, in the dark greys a monitor actually is.

			Positioned off DESKTOP'S OWN CFRAME, not the room's. The desk has
			already been rotated to face the door and nudged to sit on the floor,
			so anything placed in world coordinates here would need both of those
			re-derived. Asking the desk top where it is means the monitor cannot
			drift away from the desk no matter what moves it.

			In that frame X is across the desk's 5-stud width and Z is along its
			13-stud length, so a screen facing the chair is THIN IN X and wide in
			Z -- which is why the sizes look transposed.
		]]
		local deskTop = desk:FindFirstChild("DeskTop", true)
		if deskTop then
			local function fitting(name, size, offset, color)
				local part = Instance.new("Part")
				part.Name = name
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
				part.Size = size
				part.CFrame = deskTop.CFrame * CFrame.new(offset)
				part.Color = color
				part.Material = Enum.Material.SmoothPlastic
				part.TopSurface = Enum.SurfaceType.Smooth
				part.BottomSurface = Enum.SurfaceType.Smooth
				part.Parent = desk
				return part
			end

			local surface = 0.2 -- the desk top's upper face, in its own frame
			fitting("MonitorFoot", Vector3.new(1.4, 0.25, 3.0),
				Vector3.new(1.2, surface + 0.125, 0), Color3.fromRGB(28, 28, 32))
			fitting("MonitorStem", Vector3.new(0.4, 1.8, 0.5),
				Vector3.new(1.2, surface + 1.15, 0), Color3.fromRGB(28, 28, 32))
			fitting("MonitorBezel", Vector3.new(0.32, 4.2, 6.8),
				Vector3.new(1.2, surface + 4.1, 0), Color3.fromRGB(20, 20, 24))

			--[[ Proud of the bezel on the CHAIR side (-X), which is also the
			     side you walk in from, so the readout faces the door. ]]
			local screen = fitting("MonitorScreen", Vector3.new(0.12, 3.5, 6.1),
				Vector3.new(1.02, surface + 4.1, 0), Color3.fromRGB(14, 18, 26))
			screen.Material = Enum.Material.Neon

			local face = Instance.new("SurfaceGui")
			face.Name = "Readout"
			face.Face = Enum.NormalId.Left -- -X, the chair side
			face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			face.PixelsPerStud = 48
			face.LightInfluence = 0
			face.Parent = screen

			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
			bg.BorderSizePixel = 0
			bg.Parent = face

			local rate = Instance.new("TextLabel")
			rate.Name = "Rate"
			rate.BackgroundTransparency = 1
			rate.Size = UDim2.fromScale(1, 0.34)
			rate.Position = UDim2.fromScale(0, 0.12)
			rate.Font = Enum.Font.GothamBlack
			rate.TextScaled = true
			rate.TextColor3 = Color3.fromRGB(150, 240, 180)
			rate.Text = "--/s"
			rate.Parent = bg

			local ready = Instance.new("TextLabel")
			ready.Name = "Ready"
			ready.BackgroundTransparency = 1
			ready.Size = UDim2.fromScale(1, 0.26)
			ready.Position = UDim2.fromScale(0, 0.52)
			ready.Font = Enum.Font.GothamBold
			ready.TextScaled = true
			ready.TextColor3 = Color3.fromRGB(120, 150, 190)
			ready.Text = "READY  $0"
			ready.Parent = bg
		end

		--[[
			THE RING. A circle you step into, drawn as an OUTLINE rather than a
			disc -- a filled 18-stud circle is the neon slab again, just round.

			Segments, because Roblox has no torus and no annulus. The count is
			derived from the radius so the polygon stays smooth if the radius
			changes; at a fixed count a bigger ring visibly becomes a polygon.
			Lifted off the floor by FLOOR_LIFT, or it z-fights exactly the way
			the pad did.
		]]
		local ring = Instance.new("Model")
		ring.Name = "CollectRing"
		ring.Parent = shell

		local ringAt = deskAt + facing * RING_STANDOFF
		local segments = math.clamp(math.floor(COLLECT_RADIUS * 4), 24, 72)
		local step = math.pi * 2 / segments
		-- chord length, so neighbours meet instead of leaving gaps
		local segLen = 2 * COLLECT_RADIUS * math.sin(step / 2) + 0.15
		for i = 0, segments - 1 do
			local a = i * step
			local seg = Instance.new("Part")
			seg.Name = "RingSegment"
			seg.Anchored = true
			seg.CanCollide = false
			seg.CastShadow = false
			seg.Size = Vector3.new(segLen, 0.08, 0.55)
			seg.CFrame = CFrame.new(
				ringAt + Vector3.new(math.cos(a), 0, math.sin(a)) * COLLECT_RADIUS
					+ Vector3.new(0, 0.6 + FLOOR_LIFT + 0.04, 0))
				--[[ Minus a quarter turn, and it matters: CFrame.Angles(0, -a, 0)
				     sends local +X along the RADIUS, so the segments came out as
				     a sunburst of spokes rather than a ring. The length was
				     right the whole time, which is why it looked like a gap
				     problem. +X has to land on the tangent. ]]
				* CFrame.Angles(0, -a - math.pi / 2, 0)
			seg.Color = RING_COLOR
			seg.Material = Enum.Material.Neon
			seg.Transparency = 0.35
			seg.Parent = ring
		end

		--[[ The trigger itself: invisible, and NOT the ring. PlotService checks
		     a radius against this part, so the ring can be restyled or removed
		     without touching what actually collects. ]]
		local zone = Instance.new("Part")
		zone.Name = "CollectZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.Transparency = 1
		zone.Size = Vector3.new(1, 1, 1)
		zone.CFrame = CFrame.new(ringAt + Vector3.new(0, 3, 0))
		zone:SetAttribute("Radius", COLLECT_RADIUS)
		zone.Parent = shell

		--[[ Parented in the world so the chime plays FROM the desk rather than
		     inside your head. Played server-side, which replicates. ]]
		local chime = Instance.new("Sound")
		chime.Name = "CollectSound"
		chime.SoundId = "rbxassetid://" .. COLLECT_SOUND
		chime.Volume = 0.55
		chime.RollOffMaxDistance = 90
		chime.Parent = zone
	end



	--[[ The per-slot strips stop pretending to be collect zones. They stay as
	     the pad surface -- you still need to see where a brainrot goes -- but in
	     a quiet stone rather than a lit green that says "stand here". ]]
	local quieted = 0
	if slots then
		for _, slot in ipairs(slots:GetChildren()) do
			local strip = slot:FindFirstChild("Collect")
			if strip and strip:IsA("BasePart") then
				strip.Color = Color3.fromRGB(122, 116, 104)
				strip.Material = Enum.Material.Concrete
				quieted += 1
			end
		end
	end

	--[[ Dressed as tier 0 before anyone owns it. The build colours above are
	     tier 1's, so without this an unclaimed base would advertise a
	     renovation its occupant has not paid for yet. ]]
	HomeService.applyTier(base, 0)

	converted[base] = true
	print(("[HomeService] %s: room %.0f x %.0f x %d at (%.0f, %.0f) | %d map parts hidden, %d facade parts hollowed, %d front segments, %d lights, %d windows, %d cleared from the doorway, %d shopfront parts removed, %d shell, %d re-solidified, %d slots, %d stray pad parts stripped, facing %s")
		:format(base.Name, room.halfX * 2, room.halfZ * 2, 18, room.centre.X, room.centre.Z,
			hidden, hollowed, doored, lit, windows, cleared, deglazed, unshelled, resolid, moved,
			strippedPads,
			(facing.X ~= 0) and (facing.X > 0 and "+X" or "-X") or (facing.Z > 0 and "+Z" or "-Z")))
	return true
end

--[[
	RENOVATE A ROOM TO MATCH ITS OWNER'S REBIRTHS.

	Everything a tier touches was already being built with a hardcoded colour,
	so this repaints rather than rebuilds -- no part is created or destroyed and
	nothing under Slots is touched, which means it is safe to call on a room a
	player is standing in and safe to call repeatedly.

	Driven from PlotService.refresh, which already runs on claim and on rebirth.
	Hanging it off those rather than adding a third trigger keeps "the room
	matches the profile" true by construction instead of by remembering.

	Parts are matched BY NAME, and the names are the ones `convert` gives them.
	A slab this misses keeps its build colour and the room ends up half
	renovated, so the wall list covers all four names the wall builder emits --
	including Lintel, which is a wall that does not have Wall in its name.
]]
local WALL_PARTS = { Wall = true, WallFront = true, Lintel = true, Ceiling = true }
local TRIM_PARTS = { Skirting = true, WindowSill = true, DoorJamb = true, DoorHead = true }

function HomeService.applyTier(base, rebirths)
	local home = base and base:FindFirstChild("Home")
	local shell = home and home:FindFirstChild("Interior")
	if not shell then
		return false, nil
	end

	--[[ Returns (changed, tier). The tier comes back on BOTH paths -- a caller
	     asking "what is this room wearing" should not have to know whether it
	     happened to be the call that changed it. ]]
	local tier = Rebirth.tier(rebirths)
	if shell:GetAttribute("Tier") == tier.name then
		return false, tier -- already wearing it; repainting would be pointless
	end
	shell:SetAttribute("Tier", tier.name)

	for _, part in ipairs(shell:GetChildren()) do
		if part:IsA("BasePart") then
			if part.Name == "Floor" then
				part.Color = tier.floor
				part.Material = tier.floorMaterial
			elseif WALL_PARTS[part.Name] then
				part.Color = tier.wall
			elseif part.Name == "Bulb" then
				part.Color = tier.light
				local light = part:FindFirstChildWhichIsA("PointLight")
				if light then
					light.Brightness = tier.brightness
					light.Range = tier.range
					light.Color = tier.light
				end
			elseif TRIM_PARTS[part.Name] then
				part.Color = tier.trim
			elseif part.Name == "Carpet" then
				part.Color = tier.carpet
			end
		end
	end

	--[[ The ring lives in its own model, so it is walked separately. It takes
	     the tier accent lightened toward white -- a floor marking wants to read
	     as a marking, not as a second light source competing with the bulbs. ]]
	local ring = shell:FindFirstChild("CollectRing")
	if ring then
		local marked = tier.accent:Lerp(Color3.new(1, 1, 1), 0.45)
		for _, seg in ipairs(ring:GetChildren()) do
			if seg:IsA("BasePart") then
				seg.Color = marked
			end
		end
	end

	return true, tier
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
