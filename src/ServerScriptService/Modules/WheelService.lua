--[[
	WheelService
	The all-in wager. Everything you own, for a shot at a Secret.

	THE ONLY SOURCE OF SECRETS. Rarity marks that tier wheelOnly and DropTable
	skips it, so no tile reveal at any multiplier under any event can produce
	one. The auction can resell a Secret, but it can never mint one.

	WHAT "EVERYTHING" MEANS. All cash, and every brainrot -- placed on pads,
	stored, no exceptions. It is taken BEFORE the roll, so a disconnect
	mid-spin can never leave a player holding both the stake and the prize.

	WHAT SURVIVES A LOSS, DELIBERATELY:
	  - the Index. It records what you have ever banked and only goes up, so a
	    bust costs you the brainrots but never the collection.
	  - your pads and upgrades. You keep the machine, you lose the contents.
	  - Config.BrokeStipend still catches you at zero, so a bust cannot softlock
	    anyone out of the Mines.

	The roll is server-side and happens first; the wheel animation is told which
	wedge to stop on. The spin never decides anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Wheel = require(Shared.Wheel)
local Brainrots = require(Shared.Brainrots)
local Variants = require(Shared.Variants)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local PlotService = require(script.Parent.PlotService)

local WheelService = {}

local rng = Random.new()
local spinning = {} -- [userId] = true while a spin resolves

-- Set by WheelBuild once the machine exists.
WheelService.anchor = nil

-- ── eligibility ─────────────────────────────────────────────────────────────

local function nearWheel(player)
	local anchor = WheelService.anchor
	if not anchor then
		return true -- machine missing: don't lock anyone out
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - anchor.Position).Magnitude <= Config.WheelRange
end

--[[ What the wager is worth, for the confirmation screen. Brainrot value is
     income per second, because that is the thing you actually lose. ]]
function WheelService.stakeOf(profile)
	local income = 0
	for _, item in ipairs(profile.inventory) do
		income += Economy.incomeOf(item.charId, item.variantId)
	end
	return {
		money = math.floor(profile.money),
		brainrots = #profile.inventory,
		income = income,
		eligible = profile.money >= Config.WheelMinStake,
		minimum = Config.WheelMinStake,
	}
end

-- ── the roll ────────────────────────────────────────────────────────────────

local function rollOutcome()
	local roll = rng:NextNumber()
	local sum = 0
	for _, outcome in ipairs(Config.WheelOdds) do
		sum += outcome.chance
		if roll < sum then
			return outcome.id
		end
	end
	-- floating point can leave a sliver at the top end; treat it as the last
	-- entry rather than returning nil
	return Config.WheelOdds[#Config.WheelOdds].id
end

--[[ A Secret, rolled honestly across the characters in that tier and the
     ordinary variant table -- so which Secret, and how good, is still luck. ]]
local function mintSecret(profile)
	local pool = Brainrots.ByTier.Secret
	if not pool or #pool == 0 then
		warn("[Wheel] no Secret characters in the roster")
		return nil
	end
	local char = pool[rng:NextInteger(1, #pool)]

	local total = 0
	for _, name in ipairs(Variants.Order) do
		total += Variants.get(name).weight
	end
	local pick, variantId = rng:NextNumber() * total, Variants.Order[1]
	for _, name in ipairs(Variants.Order) do
		pick -= Variants.get(name).weight
		if pick <= 0 then
			variantId = name
			break
		end
	end

	local item = {
		uid = DataService.nextUid(profile),
		charId = char.id,
		variantId = variantId,
	}
	table.insert(profile.inventory, item)
	DataService.recordIndex(profile, char.id, variantId)
	return item
end

-- ── the wager ───────────────────────────────────────────────────────────────

function WheelService.spin(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if spinning[player.UserId] then
		return { ok = false, err = "The wheel is already going." }
	end
	if not nearWheel(player) then
		return { ok = false, err = "Get to the wheel first." }
	end
	if profile.money < Config.WheelMinStake then
		return {
			ok = false,
			err = "You need " .. Format.money(Config.WheelMinStake) .. " to play.",
		}
	end

	spinning[player.UserId] = true

	-- Take the stake BEFORE rolling. Losing the connection mid-spin then costs
	-- the stake, which is the honest failure -- the alternative is a player who
	-- keeps everything and gets the prize.
	local staked = {
		money = math.floor(profile.money),
		brainrots = #profile.inventory,
	}
	profile.money = 0
	profile.inventory = {}
	PlotService.refresh(player)

	local results = {}
	local outcome, secret
	local guard = 0

	--[[ A retry re-rolls without a new stake. Bounded: the odds make an endless
	     chain impossible in practice, but an unbounded loop on a server thread
	     is not something to leave to probability. ]]
	repeat
		outcome = rollOutcome()
		guard += 1

		local wedges = Wheel.segmentsFor(outcome)
		table.insert(results, {
			outcome = outcome,
			segment = wedges[rng:NextInteger(1, #wedges)],
		})
	until outcome ~= "retry" or guard >= 12

	if outcome == "secret" then
		secret = mintSecret(profile)
	elseif outcome == "cash" then
		profile.money += Config.WheelCashPrize
	end

	profile.stats.wheelSpins = (profile.stats.wheelSpins or 0) + 1
	PlayerState.push(player)
	spinning[player.UserId] = nil

	-- turn the physical wheel to the wedge that was rolled, so anyone standing
	-- there watches the same result the player gets
	WheelService.playSpin(results[#results].segment, 5)

	local payload = {
		ok = true,
		spins = results, -- one entry per roll; more than one means retries
		outcome = outcome,
		staked = staked,
		cash = outcome == "cash" and Config.WheelCashPrize or 0,
		secret = secret and {
			charId = secret.charId,
			variantId = secret.variantId,
			name = Economy.displayName(secret.charId, secret.variantId),
			income = Economy.incomeOf(secret.charId, secret.variantId),
		} or nil,
	}

	if outcome == "secret" then
		Net.get("Announce"):FireAllClients({
			userId = player.UserId,
			playerName = player.DisplayName,
			charId = secret.charId,
			variantId = secret.variantId,
			tier = "Secret",
			lost = false,
			fromWheel = true,
		})
		PlayerState.notify(player, "THE WHEEL PAYS OUT: " .. payload.secret.name, "good")
	elseif outcome == "cash" then
		PlayerState.notify(player, "Consolation: " .. Format.money(Config.WheelCashPrize), "info")
	else
		PlayerState.notify(player, "The wheel took everything.", "bad")
	end

	return payload
end

-- ── the machine ─────────────────────────────────────────────────────────────

--[[
	The wheel stands where a player base used to.

	Config.WheelReplacesBase names it. That base is demolished at startup and
	PlotService then finds one fewer plot, so the server supports seven players
	instead of eight -- the trade the wheel is worth.

	Filled in by clearSite() from the demolished base's own footprint, so moving
	the wheel is a matter of naming a different base rather than hunting for
	coordinates.
]]
local SITE = Vector3.new(0, 0.3, -30)
local RADIUS = 15
--[[ NEGATIVE: the disc faces -Z, toward the street players walk in from.
     Built facing +Z first, which pointed it at the map edge -- from the
     approach you saw the blank backing plate and none of the wedges. ]]
local FACE_Z = -6

--[[
	Deliberately NOT neon, except the Secret slivers.

	The first pass made every wedge Neon and the whole disc rendered as a white
	starburst -- fully self-lit geometry under the daylight pass plus bloom, with
	no shading left to separate one wedge from the next. These are flat plastic
	with enough value contrast to read from across the street, and only the eight
	Secret wedges glow, which is exactly where the eye should go.
]]
local TINT = {
	secret = Color3.fromRGB(255, 214, 64),
	retry = Color3.fromRGB(64, 132, 220),
	cash = Color3.fromRGB(46, 168, 82),
	-- deep crimson, not near-black: at (30,36,62) the 47 BUST wedges were the
	-- same value as the backing plate and the whole face read as one dark disc
	nothing = Color3.fromRGB(152, 42, 60),
}

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = props.query == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Shape = props.shape or Enum.PartType.Block
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

--[[
	Demolish the base the wheel replaces, and take its ground position.

	MUST run before PlotService.start(). PlotService attaches to whatever bases
	exist when it starts, so deleting one afterwards would leave it holding a
	plot made of destroyed parts.
]]
function WheelService.clearSite()
	local bases = workspace:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild(Config.WheelReplacesBase)
	if not base then
		warn(("[Wheel] %s not found; leaving the wheel at its fallback site")
			:format(tostring(Config.WheelReplacesBase)))
		return SITE
	end

	local cf = base:GetBoundingBox()
	base:Destroy()

	--[[ Find the ground AFTER demolishing, by raycast.

	     The base's bounding box is not the answer: its foundation hangs about
	     three studs below the walkable floor, so taking the box's underside put
	     the wheel underground. With the base gone the ray lands on the map's
	     own terrain, which is what the wheel should stand on. ]]
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("TheWheel") }
	local hit = workspace:Raycast(Vector3.new(cf.X, cf.Y + 60, cf.Z),
		Vector3.new(0, -160, 0), params)

	SITE = Vector3.new(cf.X, hit and (hit.Position.Y + 0.2) or 0.3, cf.Z)
	print(("[Wheel] demolished %s; wheel site is %.0f, %.0f, %.0f")
		:format(Config.WheelReplacesBase, SITE.X, SITE.Y, SITE.Z))
	return SITE
end

function WheelService.build()
	local existing = workspace:FindFirstChild("TheWheel")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "TheWheel"
	root.Parent = workspace

	local centre = SITE + Vector3.new(0, RADIUS + 6, 0)

	-- frame: two legs and an axle, so the disc reads as mounted rather than
	-- floating
	for _, side in ipairs({ -1, 1 }) do
		part({
			name = "Leg",
			size = Vector3.new(2.2, RADIUS + 6, 2.2),
			cframe = CFrame.new(SITE + Vector3.new(side * (RADIUS + 3), (RADIUS + 6) / 2, 0)),
			color = Color3.fromRGB(96, 106, 138),
			material = Enum.Material.Metal,
		}, root)
	end
	part({
		name = "Axle",
		size = Vector3.new(2 * (RADIUS + 3), 1.6, 1.6),
		cframe = CFrame.new(SITE + Vector3.new(0, RADIUS + 6, 0)),
		color = Color3.fromRGB(96, 106, 138),
		material = Enum.Material.Metal,
	}, root)

	--[[ The face is its own Model so the whole disc can be pivoted as one unit
	     without dragging the frame around with it. ]]
	local face = Instance.new("Model")
	face.Name = "Face"
	face.Parent = root

	local hub = part({
		name = "Hub",
		-- wide enough to cap the middle: 100 wedges all converging on one point
		-- leaves a ragged knot there, and the hub is what hides it
		size = Vector3.new(7, 7, math.abs(FACE_Z) + 1.6),
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z / 2)) * CFrame.Angles(0, 0, 0),
		color = Color3.fromRGB(255, 190, 60),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
	}, face)
	hub.CFrame = CFrame.new(centre + Vector3.new(0, 0, FACE_Z / 2))
		* CFrame.Angles(0, math.rad(90), 0)
	face.PrimaryPart = hub

	-- backing disc, so the wedge bars never show a gap at the rim
	part({
		name = "Backing",
		size = Vector3.new(1.2, RADIUS * 2 + 2, RADIUS * 2 + 2),
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z + 0.6))
			* CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(28, 34, 60),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
	}, face)

	--[[ One radial bar per wedge. 100 of them, coloured by outcome, so the face
	     is a literal picture of the odds -- see Wheel.SEGMENTS for why the count
	     has to be 100 and not a rounder number. ]]
	-- Width is set from the arc at the RIM, not at mid-radius: sizing off the
	-- middle leaves visible gaps around the outside, which is where the eye is.
	local width = (2 * math.pi * RADIUS / Wheel.SEGMENTS) * 1.06
	for index, outcomeId in ipairs(Wheel.FACE) do
		local angle = math.rad(Wheel.angleOf(index))
		local wedge = part({
			name = "Wedge" .. index,
			size = Vector3.new(width, RADIUS, 0.6),
			cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z))
				* CFrame.Angles(0, 0, -angle)
				* CFrame.new(0, RADIUS / 2, 0),
			color = TINT[outcomeId],
			material = outcomeId == "secret" and Enum.Material.Neon
				or Enum.Material.SmoothPlastic,
			collide = false,
		}, face)
		wedge:SetAttribute("Outcome", outcomeId)
	end

	-- pointer at 12 o'clock, fixed to the frame so the FACE turns under it
	part({
		name = "Pointer",
		size = Vector3.new(2.4, 4, 1.4),
		cframe = CFrame.new(centre + Vector3.new(0, RADIUS + 1.5, FACE_Z - 0.8)),
		color = Color3.fromRGB(255, 72, 92),
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	-- the console you actually use, at ground level in front
	local console = part({
		name = "Console",
		size = Vector3.new(10, 3.4, 3.4),
		cframe = CFrame.new(SITE + Vector3.new(0, 1.7, FACE_Z - 6)),
		color = Color3.fromRGB(96, 106, 138),
		material = Enum.Material.Metal,
		query = true,
	}, root)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WheelPrompt"
	prompt.ActionText = "Wager everything"
	prompt.ObjectText = "The Wheel"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	prompt.Triggered:Connect(function(player)
		Net.get("OpenWheel"):FireClient(player)
	end)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(280, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 260
	gui.Adornee = console
	gui.Parent = console -- on the part, never the model: see the billboard fix

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 236, 120)
	title.TextStrokeTransparency = 0.25
	title.Text = "THE WHEEL"
	title.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 32
	cap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(236, 240, 255)
	sub.TextStrokeTransparency = 0.4
	sub.Text = "everything you own, for a Secret"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 15
	subCap.Parent = sub

	WheelService.anchor = console
	WheelService.face = face
	return root
end

--[[
	Turn the face so `segment` finishes under the pointer.

	Server-side so every player at the machine watches the same spin. It is pure
	theatre -- the outcome was decided before this is called, and the angle is
	derived from it, never the other way round.
]]
function WheelService.playSpin(segment, turns)
	local face = WheelService.face
	if not face or not face.PrimaryPart then
		return
	end

	local base = face:GetPivot()
	local target = -math.rad(Wheel.angleOf(segment))
	local total = math.rad(360 * (turns or 5)) + target

	task.spawn(function()
		local duration = 3.4
		local start = os.clock()
		local origin = base
		while true do
			local t = (os.clock() - start) / duration
			if t >= 1 then
				break
			end
			-- ease-out cubic: fast off the line, drifts into the result
			local eased = 1 - (1 - t) ^ 3
			face:PivotTo(origin * CFrame.Angles(0, 0, total * eased))
			task.wait()
		end
		face:PivotTo(origin * CFrame.Angles(0, 0, total))
	end)
end

function WheelService.start()
	WheelService.build()

	Net.get("SpinWheel").OnServerInvoke = function(player)
		return WheelService.spin(player)
	end

	Net.get("WheelStake").OnServerInvoke = function(player)
		local profile = DataService.get(player)
		return profile and WheelService.stakeOf(profile) or nil
	end

	Players.PlayerRemoving:Connect(function(player)
		spinning[player.UserId] = nil
	end)
end

return WheelService
