--[[
	WheelService
	The all-in wager. Everything you own, for a shot at a Secret.

	THE ONLY SOURCE OF SECRETS. Rarity marks that tier wheelOnly and DropTable
	skips it, so no tile reveal at any multiplier under any event can produce
	one. Nothing else in the game can mint a Secret.

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
--[[ Ten seconds and nine turns. The whole drama of a wheel is the stretch where
     it is barely moving and might still crawl one more segment, and that only
     works if there is enough of it. Nine turns keeps the opening fast enough
     that the long tail reads as deceleration rather than as a slow wheel. ]]
local SPIN_SECONDS = 10
local SPIN_TURNS = 9

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
	WheelService.playSpin(results[#results].segment, SPIN_TURNS, outcome)

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
--[[ 26, up from 15. It was asked to be bigger and it needed to be: a prize
     wheel is a landmark, and at 15 studs it read as a signpost. ]]
local RADIUS = 26
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
--[[
	Taken from the fortune-wheel model you supplied (Wheel spin.rbxmx).

	That model is a ScreenGui -- 335 instances and not one BasePart -- so it
	could not be "made bigger" as a world object. What it does have that is worth
	keeping is its arrow and its three sound effects, so those are reused here on
	a physical wheel. Its face image is a six-slot graphic and our odds are four
	outcomes at 8/15/30/47, which no six-segment picture can state honestly, so
	the face stays procedural.
]]
local ARROW_IMAGE = "rbxassetid://14339762504"
local SFX_TICK = "rbxassetid://421058925"
local SFX_WIN = "rbxassetid://4612386227"
local SFX_LOSE = "rbxassetid://70951308232500"

local LABEL = {
	secret = "SECRET",
	retry = "RETRY",
	cash = "$200K",
	nothing = "BUST",
}

local TINT = {
	secret = Color3.fromRGB(255, 206, 40),
	retry = Color3.fromRGB(66, 176, 255),
	cash = Color3.fromRGB(56, 200, 92),
	nothing = Color3.fromRGB(228, 54, 76),
}

--[[
	Each REPEAT of an outcome gets a slightly different shade.

	Four flat colours over twelve arcs meant the same red sat next to itself
	across a thin divider and the face read as a few enormous blobs rather than
	as a wheel of segments. Shifting hue a little per repeat keeps the outcome
	obvious -- all the reds are still clearly red -- while giving the eye the
	segment count the reference art has.
]]
local function shadeFor(outcomeId, repeatIndex)
	local base = TINT[outcomeId]
	local h, sat, v = Color3.toHSV(base)
	local drift = (repeatIndex % 3) -- 0, 1, 2
	return Color3.fromHSV(
		(h + drift * 0.035) % 1,
		math.clamp(sat - drift * 0.06, 0, 1),
		math.clamp(v + drift * 0.07, 0, 1)
	)
end

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
	--[[ This line was missing, and every `transparency = 1` in this file was
	     being silently dropped -- which turned the label plates into opaque
	     coloured rectangles sitting on top of the wedges. ]]
	p.Transparency = props.transparency or 0
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

	--[[
		THE PIVOT MUST BE AXIS-ALIGNED.

		This was the Hub, which is a Cylinder and therefore carries a 90-degree
		Y rotation to stand it up facing the player. A model pivots about its
		PrimaryPart's LOCAL axes, so rotating "about Z" was really rotating about
		world X -- the wheel tumbled end over end instead of spinning. An
		invisible identity-oriented part fixes it, and keeps the hub free to be
		oriented however it needs to look right.
	]]
	local pivot = part({
		name = "Pivot",
		size = Vector3.new(0.4, 0.4, 0.4),
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z)),
		color = Color3.fromRGB(255, 255, 255),
		transparency = 1,
		collide = false,
	}, face)
	face.PrimaryPart = pivot

	-- white outer ring, standing proud of the coloured disc all the way round
	part({
		name = "Ring",
		size = Vector3.new(1.0, (RADIUS + 3.5) * 2, (RADIUS + 3.5) * 2),
		-- +1.6: the layers face -Z, so a LARGER z offset is further from the
		-- viewer. Getting this backwards is what hid the wedges.
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z + 1.6))
			* CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(252, 252, 255),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
	}, face)

	-- dark backing just inside the ring, so no wedge gap ever shows white
	part({
		name = "Backing",
		size = Vector3.new(1.2, RADIUS * 2 + 1, RADIUS * 2 + 1),
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z + 1.2))
			* CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(26, 30, 52),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
	}, face)

	--[[ One radial bar per wedge. 100 of them, coloured by outcome, so the face
	     is a literal picture of the odds -- see Wheel.SEGMENTS for why the count
	     has to be 100 and not a rounder number. ]]
	-- Width is set from the arc at the RIM, not at mid-radius: sizing off the
	-- middle leaves visible gaps around the outside, which is where the eye is.
	--[[
		Each wedge is built as three radial BANDS, not one long bar.

		A single bar has to be as wide as the arc at the RIM, which makes it
		three and a half times too wide near the hub -- so every wedge overlapped
		three of its neighbours, all at identical depth. Coplanar overlapping
		faces give the depth buffer no winner, and the renderer flickers between
		them as the camera moves: the "vibrating middle".

		Sizing each band to the arc at ITS OWN mid-radius drops the worst overlap
		from 3.4x to about 1.5x, and the small z stagger below makes even that
		deterministic. Bands also start outside the hub, so the point where all
		one hundred wedges converge is simply not built.
	]]
	local BANDS = {
		{ inner = RADIUS * 0.30, outer = RADIUS * 0.54 },
		{ inner = RADIUS * 0.54, outer = RADIUS * 0.77 },
		{ inner = RADIUS * 0.77, outer = RADIUS },
	}

	-- which repeat of its outcome each wedge belongs to, so shadeFor can vary
	-- neighbouring arcs of the same result
	local shadeOf, seen = {}, {}
	for _, run in ipairs(Wheel.runs()) do
		seen[run.id] = (seen[run.id] or 0) + 1
		for w = run.first, run.first + run.count - 1 do
			shadeOf[w] = seen[run.id]
		end
	end

	for index, outcomeId in ipairs(Wheel.FACE) do
		local angle = math.rad(Wheel.angleOf(index))
		local colour = shadeFor(outcomeId, shadeOf[index] or 1)

		for bandIndex, band in ipairs(BANDS) do
			local span = band.outer - band.inner
			--[[ Sized from the band's OUTER edge, which is its widest point.

			     Sizing from the mid-radius left each band narrower than the arc
			     at its outer edge, so the dark backing showed through as thin
			     radial ticks -- a moire of hairlines across every segment. A
			     band must be at least as wide as its widest arc; the extra
			     overlap that creates further in is harmless now that the depths
			     are staggered. ]]
			local width = (2 * math.pi * band.outer / Wheel.SEGMENTS) * 1.02

			--[[ Stagger depth by wedge AND band. Any residual overlap then has a
			     strict front-to-back order instead of two faces at the same z,
			     which is what actually stops the shimmer. ]]
			local z = FACE_Z + ((index % 5) * 0.010) + (bandIndex * 0.003)

			local wedge = part({
				name = ("Wedge%d_%d"):format(index, bandIndex),
				size = Vector3.new(width, span, 0.6),
				cframe = CFrame.new(centre + Vector3.new(0, 0, z))
					* CFrame.Angles(0, 0, -angle)
					* CFrame.new(0, band.inner + span / 2, 0),
				color = colour,
				material = Enum.Material.SmoothPlastic,
				collide = false,
			}, face)
			wedge:SetAttribute("Outcome", outcomeId)
		end
	end

	--[[
		Big white centre, added AFTER the wedges so it sits over them.

		100 wedges all converging on one point produce a rainbow knot at the
		middle -- the "buggy" smear. A 7-stud hub on a 52-stud wheel was nowhere
		near enough to cover it; this is a third of the radius, like the white
		centre on a real prize wheel.
	]]
	local hub = part({
		name = "Hub",
		size = Vector3.new(math.abs(FACE_Z) + 2.4, RADIUS * 0.62, RADIUS * 0.62),
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z / 2 - 0.4))
			* CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(252, 252, 255),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
	}, face)
	part({
		name = "HubCap",
		size = Vector3.new(0.8, RADIUS * 0.34, RADIUS * 0.34),
		-- proud of the white hub, which reaches FACE_Z - 1.2
		cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z - 2.0))
			* CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(255, 198, 64),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		collide = false,
	}, face)

	--[[
		WORDS PRINTED ON THE WHEEL.

		SurfaceGui on a part inside the Face model, not a BillboardGui. A
		billboard always faces the camera, so the labels floated free of the disc
		and stayed upright while it turned -- which is why they read as bubbles
		hovering around the wheel rather than as writing on it. A SurfaceGui is
		painted onto the surface, so it rotates with its arc exactly like the
		numbers on a real prize wheel.
	]]
	for _, run in ipairs(Wheel.runs()) do
		local angle = math.rad(run.mid)
		local plate = part({
			name = "Label",
			-- sized to the arc it sits on, so a narrow SECRET wedge gets narrow
			-- text rather than text spilling over its neighbours
			size = Vector3.new(RADIUS * 0.46, math.rad(run.sweep) * RADIUS * 0.62, 0.18),
			cframe = CFrame.new(centre + Vector3.new(0, 0, FACE_Z - 0.42))
				* CFrame.Angles(0, 0, -angle)
				* CFrame.new(0, RADIUS * 0.66, 0)
				* CFrame.Angles(0, 0, math.rad(-90)),
			color = TINT[run.id],
			transparency = 1,
			collide = false,
		}, face)

		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 34
		surface.AlwaysOnTop = false
		surface.Adornee = plate
		surface.Parent = plate

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 255, 255)
		text.TextStrokeTransparency = 0
		text.TextStrokeColor3 = Color3.fromRGB(24, 20, 36)
		text.Text = LABEL[run.id]
		text.Parent = surface
	end

	--[[ Rim of bulbs, like a fairground wheel. Purely decorative, and the one
	     piece of decoration that most makes a disc read as a WHEEL. ]]
	for i = 1, 24 do
		local angle = (i / 24) * math.pi * 2
		part({
			name = "Bulb",
			size = Vector3.new(1.5, 1.5, 1.5),
			cframe = CFrame.new(centre + Vector3.new(
				math.sin(angle) * (RADIUS + 1.4),
				math.cos(angle) * (RADIUS + 1.4),
				FACE_Z + 0.2)),
			color = Color3.fromRGB(255, 244, 214),
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			collide = false,
		}, face)
	end

	-- pointer at 12 o'clock, fixed to the frame so the FACE turns under it
	local pointer = part({
		name = "Pointer",
		size = Vector3.new(5, 6.5, 0.6),
		cframe = CFrame.new(centre + Vector3.new(0, RADIUS + 1.2, FACE_Z - 1.2)),
		color = Color3.fromRGB(255, 72, 92),
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	do
		-- the arrow graphic from the supplied model, so the pointer reads as a
		-- pointer from any angle rather than as a red block
		local decal = Instance.new("Decal")
		decal.Texture = ARROW_IMAGE
		decal.Face = Enum.NormalId.Front
		decal.Parent = pointer
		local back = decal:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = pointer
		pointer.Transparency = 1
	end

	--[[ Sound, also from the supplied model. Parented to the hub so it carries
	     from the wheel itself and falls off with distance. ]]
	for name, id in pairs({ Tick = SFX_TICK, Win = SFX_WIN, Lose = SFX_LOSE }) do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.RollOffMaxDistance = 140
		sound.Volume = name == "Tick" and 0.35 or 0.8
		sound.Parent = hub
	end

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
function WheelService.playSpin(segment, turns, outcome)
	local face = WheelService.face
	if not face or not face.PrimaryPart then
		return
	end

	local hub = face.PrimaryPart
	local base = face:GetPivot()
	local target = -math.rad(Wheel.angleOf(segment))
	local total = math.rad(360 * (turns or SPIN_TURNS)) + target

	--[[ Which ARC each wedge belongs to. The tick fires on arc changes, not
	     wedge changes: a real wheel has one peg per segment, and ticking per
	     wedge meant 100 a turn -- peaking near 400 a second, which is a buzz
	     rather than a tick. Twelve a turn is a wheel. ]]
	local arcOf = {}
	for arcIndex, run in ipairs(Wheel.runs()) do
		for w = run.first, run.first + run.count - 1 do
			arcOf[w] = arcIndex
		end
	end

	task.spawn(function()
		local start = os.clock()
		local origin = base
		local lastArc = -1

		while true do
			local t = (os.clock() - start) / SPIN_SECONDS
			if t >= 1 then
				break
			end

			--[[ Power 2.6, not 4.

			     Quartic was fine over five seconds and useless over ten: it
			     leaves 0.4% of the rotation after seven and a half, so the wheel
			     appears to stop and then creeps through three seconds of dead
			     air. 2.6 still throws it off the line hard but keeps 16% of the
			     turn for the last half, which is where the tension lives. ]]
			local eased = 1 - (1 - t) ^ 2.6
			local turned = total * eased
			face:PivotTo(origin * CFrame.Angles(0, 0, turned))

			--[[ Driven off ANGLE, never a timer, so the ticks slow exactly as
			     the wheel does -- the sound IS the deceleration. ]]
			local wedge = math.floor(math.deg(turned) / (360 / Wheel.SEGMENTS))
				% Wheel.SEGMENTS + 1
			local arc = arcOf[wedge]
			if arc ~= lastArc then
				lastArc = arc
				local tick = hub:FindFirstChild("Tick")
				if tick then
					tick.PlaybackSpeed = 0.92 + math.random() * 0.16
					tick:Play()
				end
			end
			task.wait()
		end

		face:PivotTo(origin * CFrame.Angles(0, 0, total))

		local sound = hub:FindFirstChild(
			(outcome == "secret" or outcome == "cash") and "Win" or "Lose")
		if sound then
			sound:Play()
		end
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
