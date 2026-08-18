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

--[[ Ground-floor interior of the apartment, measured off the shell mesh: it is
     50 x 70 outside with walls about a stud and a half thick. Slots go along
     the two long sides. ]]
local SLOT_X = 19
local SLOT_Z = { -25, -9, 9, 25 }

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

	--[[ Slots re-laid inside, along the two long walls. Their ORDER is kept --
	     PlotService pairs slot N with pad N and with the pending array, so
	     shuffling them would silently move everyone's brainrots between pads. ]]
	local slots = base:FindFirstChild("Slots")
	local moved = 0
	if slots then
		local list = slots:GetChildren()
		table.sort(list, function(a, b)
			return a:GetPivot().Position.Z < b:GetPivot().Position.Z
		end)
		for index, slot in ipairs(list) do
			local side = (index <= 4) and -1 or 1
			local z = SLOT_Z[((index - 1) % 4) + 1]
			local target = Vector3.new(
				cf.Position.X + side * SLOT_X,
				deck,
				cf.Position.Z + z
			)
			local scf, ssize = slot:GetBoundingBox()
			local lift = deck - (scf.Position.Y - ssize.Y / 2)
			slot:PivotTo(CFrame.new(target + Vector3.new(0, lift, 0))
				* CFrame.Angles(0, side > 0 and math.rad(180) or 0, 0))
			moved += 1
		end
	end

	converted[base] = true
	print(("[HomeService] %s: %d hidden, %d slots re-laid, %d meshes hollowed, deck y=%.1f")
		:format(base.Name, hidden, moved, hollowed, deck))
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
