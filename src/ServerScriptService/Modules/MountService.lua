--[[
	MountService
	Summon a brainrot and ride it to the racing island.

	THIS IS THE ONLY WAY UP. The racing island sits at y=1150 and the jetpack
	stops at 900, so nothing here has to police access -- the geometry does it.
	What this module owns is the trip.

	IT IS NOT A CUTSCENE, and that is the whole design. A cutscene takes the
	camera and turns the player into an audience; here the player is a
	PASSENGER. They keep their camera, they can look around the whole way, they
	simply are not the one steering. Sitting them in a Seat gets that for free:
	the default camera keeps following their character, and the humanoid is
	movement-locked by the sit rather than by anything this module has to
	enforce.

	THE SUMMON IS A COPY. The brainrot on your pad never stops earning -- it is
	still standing there collecting rent while its double carries you. That
	removes any reason to weigh "do I want income or do I want to look good",
	which is the point: the mount is fashion, and fashion should never cost you
	money.

	TWO WAYS THIS STRANDS SOMEONE, both handled rather than hoped about:

	  1. StreamingEnabled means the island may not exist on the rider's client
	     when they arrive. RequestStreamAroundAsync is fired DURING the flight,
	     not on landing, so the ground is there before they are.
	  2. Any failure at all -- an error, a death, a disconnect, a tween that
	     never finishes -- must still end with the rider standing on the island.
	     At 1150 there is no ceiling to catch a fall and no jetpack that reaches,
	     so a stranded player is a lost player. `finish` is idempotent and every
	     path leads to it, including a hard timeout that does not care why.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = script.Parent
local ModelFactory = require(Modules.ModelFactory)
local DataService = require(Modules.DataService)
local PlayerState = require(Modules.PlayerState)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)
local Economy = require(Shared.Economy)

local MountService = {}

--[[ Beside the jetpack pad on purpose. That corner of the street is already
     where you go to leave the ground, so the two ways up sit together and a
     player who has found one has found the other. ]]
local PERCH = Vector3.new(-70, 0.3, -14)

local RIDE_SECONDS = 12
local MOUNT_SCALE = 1.8 -- big enough to sit on and read as a vehicle
local TIMEOUT = RIDE_SECONDS + 8 -- the failsafe fires well after a healthy trip

local riding = {} -- [player] = true, so one rider cannot start two flights

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color or Color3.fromRGB(120, 128, 160)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Name = props.name or "Part"
	if props.transparency then
		p.Transparency = props.transparency
	end
	p.Parent = parent
	return p
end

--[[ Which brainrot answers the call.

     The player's pick if they have made one and still own it, otherwise their
     best earner -- so the first summon shows off something they are proud of
     rather than whatever happens to be first in the list. ]]
function MountService.racerFor(profile)
	if not profile or not profile.inventory then
		return nil
	end
	local chosen, best = nil, -1
	for _, item in ipairs(profile.inventory) do
		if profile.racer and item.uid == profile.racer then
			return item
		end
		local score = Economy.powerScore(item.charId, item.variantId)
		if score > best then
			chosen, best = item, score
		end
	end
	return chosen
end

--[[ A ridable double of an owned brainrot.

     UNTAGGED, DELIBERATELY. ModelFactory tags what it builds so the client can
     bob it on its pad, and that animation writes part CFrames every frame --
     which would fight this module for control of the mount the entire way up.
     The aura and nameplate go for the same reason: they are pad furniture, and
     a shadow disc floating a thousand studs up looks like a bug. ]]
local function buildMount(item)
	local model = ModelFactory.build(item.charId, item.variantId)
	if not model then
		return nil
	end
	CollectionService:RemoveTag(model, Config.BrainrotTag)
	for _, name in ipairs({ "Aura", "LabelAnchor" }) do
		local extra = model:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	model:ScaleTo(MOUNT_SCALE)
	model.Name = "Mount"
	return model
end

--[[ A gentle S through the sky rather than a straight line, because a straight
     line to a point a thousand studs up is a lift, and this is supposed to read
     as a creature carrying you. Cubic Bezier: out over the street first, then
     up, then level into the island. ]]
local function flightPath(from, to)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local p1 = from + flat * 0.15 + Vector3.new(0, (to.Y - from.Y) * 0.35, 0)
	local p2 = to - flat * 0.30 - Vector3.new(0, (to.Y - from.Y) * 0.18, 0)
	return function(t)
		local u = 1 - t
		return from * (u * u * u)
			+ p1 * (3 * u * u * t)
			+ p2 * (3 * u * t * t)
			+ to * (t * t * t)
	end
end

function MountService.start()
	local island = Islands.get("racing")
	if not island then
		warn("[MountService] no racing island; perch not built")
		return
	end

	local existing = Workspace:FindFirstChild("RacePerch")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "RacePerch"
	root.Parent = Workspace

	part({
		name = "Pad", size = Vector3.new(16, 1, 16),
		cframe = CFrame.new(PERCH + Vector3.new(0, 0.5, 0)),
		color = island.accent, material = Enum.Material.SmoothPlastic,
	}, root)
	local post = part({
		name = "Roost", size = Vector3.new(2, 9, 2),
		cframe = CFrame.new(PERCH + Vector3.new(0, 5, 0)),
		color = Color3.fromRGB(96, 104, 132), material = Enum.Material.Metal,
	}, root)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(156, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	gui.MaxDistance = 220
	gui.Parent = post

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(240, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "RACE PERCH"
	title.Parent = gui
	local titleCap = Instance.new("UITextSizeConstraint")
	titleCap.MaxTextSize = 20
	titleCap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = island.accent
	sub.TextStrokeTransparency = 0.45
	sub.Text = "summon a ride"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 10
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SummonPrompt"
	prompt.ActionText = "Summon"
	prompt.ObjectText = "Race Perch"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = post

	prompt.Triggered:Connect(function(player)
		MountService.summon(player)
	end)

	MountService.prompt = prompt
	MountService.root = root
end

--[[
	Everything that ends a ride, in one place.

	Idempotent on purpose. It is called by the normal arrival, by the timeout,
	by death and by disconnect, and more than one of those can happen at once --
	a player who dies on the last frame of the flight runs two of them. Whatever
	the reason, the outcome is identical: the mount is gone and the rider is
	standing on the island rather than falling toward a map they cannot reach.
]]
local function finish(player, mount, landing, reason)
	if not riding[player] then
		return
	end
	riding[player] = nil

	if mount and mount.Parent then
		mount:Destroy()
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Sit then
		humanoid.Sit = false
	end
	if hrp then
		hrp.CFrame = CFrame.new(landing)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	if reason ~= "arrived" then
		warn(("[MountService] %s's ride ended early (%s); set down on the island")
			:format(player.Name, tostring(reason)))
	end
end

function MountService.summon(player)
	if riding[player] then
		return
	end

	local island = Islands.get("racing")
	local profile = DataService.get(player)
	if not profile or not island then
		return
	end

	local ok, missing = Seals.canEnter(profile, island)
	if not ok then
		PlayerState.notify(player, ("The %s seal opens this. Keep playing Plinko.")
			:format(missing or "?"))
		return
	end

	local item = MountService.racerFor(profile)
	if not item then
		PlayerState.notify(player, "You need a brainrot to summon.")
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return
	end

	local mount = buildMount(item)
	if not mount then
		return
	end

	riding[player] = true

	--[[ The landing spot is on the island's own ground, stepped in from the rim
	     so an arrival never puts anyone on the lip of a thousand-stud drop. ]]
	local landing = island.center + Vector3.new(0, 6, -island.radius * 0.45)

	local seat = Instance.new("Seat")
	seat.Name = "Saddle"
	seat.Size = Vector3.new(4, 1, 4)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CFrame = CFrame.new(PERCH + Vector3.new(0, 8, 0))
	seat.Parent = mount

	mount.PrimaryPart = seat
	mount:PivotTo(CFrame.new(PERCH + Vector3.new(0, 8, 0)))
	mount.Parent = Workspace

	PlayerState.notify(player, ("Summon %s?  —  going up.")
		:format(Economy.displayName(item.charId, item.variantId)))
	seat:Sit(humanoid)

	--[[ Fired now, not on arrival: the client needs the island streamed in
	     before it gets there, or the rider lands in an empty sky. Wrapped
	     because it yields and can throw, and a streaming failure must not be
	     what strands someone. ]]
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(island.center, RIDE_SECONDS)
		end)
	end)

	local curve = flightPath(seat.Position, landing)
	local elapsed = 0
	local connection

	--[[ The hard failsafe. It does not inspect anything or try to work out what
	     went wrong -- it just puts the rider on the ground. Anything subtler is
	     a thing that can itself fail. ]]
	task.delay(TIMEOUT, function()
		if connection then
			connection:Disconnect()
		end
		finish(player, mount, landing, "timeout")
	end)

	connection = RunService.Heartbeat:Connect(function(dt)
		if not riding[player] or not mount.Parent then
			connection:Disconnect()
			return
		end

		elapsed += dt
		local t = math.clamp(elapsed / RIDE_SECONDS, 0, 1)
		-- ease both ends, so it lifts off and settles rather than snapping
		local eased = t * t * (3 - 2 * t)

		local position = curve(eased)
		local ahead = curve(math.min(eased + 0.01, 1))
		local facing = (ahead - position)
		if facing.Magnitude < 0.01 then
			facing = Vector3.new(0, 0, -1)
		end

		mount:PivotTo(CFrame.lookAt(position, position + facing.Unit))

		if t >= 1 then
			connection:Disconnect()
			finish(player, mount, landing, "arrived")
		end
	end)

	--[[ Death and disconnect both have to land somewhere sane. Dying mid-flight
	     would otherwise respawn the character while the seat still holds a weld
	     to a corpse being flown into the sky. ]]
	local died
	died = humanoid.Died:Connect(function()
		died:Disconnect()
		if connection then
			connection:Disconnect()
		end
		finish(player, mount, landing, "died")
	end)
end

Players.PlayerRemoving:Connect(function(player)
	riding[player] = nil
end)

return MountService
