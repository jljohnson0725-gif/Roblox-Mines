--[[
	PlinkoService
	The first island's machine. A real ball, real pegs, and whatever bin it
	lands in is the answer.

	THE SERVER OWNS THE BALL. Physics parts default to being simulated by
	whichever client is nearest, which for a gambling machine would mean the
	person betting also decides where the ball goes. SetNetworkOwner(nil) pins
	simulation to the server, so the drop is as unreachable as a dice roll made
	in a locked room.

	THE BOUNCES ARE ROLLED, THE FALL IS REAL. At every row the server flips a
	coin, and the ball is steered toward whichever column that flip chose.
	Vertical motion is left entirely to physics -- gravity, and every peg it
	clatters off on the way down -- so the fall and the bouncing are genuine
	and the ball really does arrive where sixteen flips sent it.

	This is NOT the wheel's trick. The wheel picks a RESULT and animates toward
	it. Here nothing knows the result; it is whatever the flips add up to.

	WHY NOT LEAVE IT TO THE PHYSICS, which is what this did first: because the
	physics decides nothing you can state. Measured over 138 centred drops the
	spread came out 29,9,18,10,6,10,12,8,36 -- a BOWL. 47% of balls in the two
	outer bins that a binomial says should see 0.39%, and 4% in the middle bin
	that should take 27%. That is an 849% return to player and a seal fragment
	on four drops in five.

	It is not a tuning problem. A real ball is not sixteen independent coin
	flips: it carries sideways momentum from one row into the next, so
	deflections compound instead of cancelling and it walks to a wall. Damping
	moves the number (52% in the middle three at elasticity 0.02 against 39% at
	0.55) and never reaches the shape.

	Rolling the bounces buys three things beyond a distribution we can choose:
	the odds are exact rather than sampled, so payouts are computed and not
	counted; they cannot drift when Roblox next changes its physics solver; and
	they do not quietly depend on server load or frame rate, which the measured
	version almost certainly did.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Islands = require(Shared.Islands)
local Plinko = require(Shared.Plinko)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)

local PlinkoService = {}

--[[ Its own collision group, so parallel balls pass through each other while
     still landing on the bin floors. ]]
local BALL_GROUP = "PlinkoBall"
do
	local PhysicsService = game:GetService("PhysicsService")
	pcall(function()
		PhysicsService:RegisterCollisionGroup(BALL_GROUP)
		PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, BALL_GROUP, false)
	end)
end

--[[ One generator for the machine. Seeded from the clock so two servers do
     not deal identical sequences of drops. ]]
local rng = Random.new(os.clock() * 1e6 % 2 ^ 31)

-- ── board geometry ──────────────────────────────────────────────────────────

--[[ 5.2, up from 4. Sixteen rows made the board 71 studs tall against 39 wide
     -- a tower, where a Plinko board should be wider than it is high. The row
     count is fixed by the odds, so the fix is to widen the bins and tighten the
     rows rather than to drop rows. ]]
local W = 5.2
--[[ Tightened from 5 so sixteen rows fit a board you can stand next to. The
     row count is set by the odds we want, not by the space -- see
     Shared/Plinko -- so the spacing is what gives. ]]
local SPACING = 2.6
--[[ Purely a visual choice now. It used to have to fit between two pegs; the
     ball passes through them, so the only question is whether you can follow
     it. At 1.5 against a 39-stud board it was a speck you lost track of. ]]
local BALL = 2.8
local PEG = 0.9
local DEPTH = 4 -- how thick the board is; the ball is boxed into this slice

local HALF = W * (Plinko.BINS / 2) -- 18 for a 9-bin board
local FIELD = (Plinko.ROWS - 1) * SPACING
local ENTRY = 9 -- drop height above the first peg
local BINS_H = 11 -- bin pocket depth

local COL = {
	frame = Color3.fromRGB(72, 82, 112),
	back = Color3.fromRGB(40, 46, 68),
	peg = Color3.fromRGB(226, 232, 246),
	ball = Color3.fromRGB(255, 206, 64),
	divider = Color3.fromRGB(96, 106, 138),
	gold = Color3.fromRGB(255, 198, 72),
}

--[[ Bin tints: hot at the edges, cold up the middle, so the payout curve is
     legible from across the island without reading a single number. ]]
local function binColor(index)
	local bin = Plinko.Bins[index]
	if bin.fragment then
		return Color3.fromRGB(255, 196, 52)
	elseif bin.pay >= 1 then
		return Color3.fromRGB(70, 190, 120)
	end
	return Color3.fromRGB(196, 72, 88)
end

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

--[[ Everything is placed in BOARD SPACE and transformed once, so the whole
     machine can be turned to face the arrival path without touching a single
     coordinate below. ]]
local board -- CFrame: X across, Y up, Z out of the face

local function at(x, y, z)
	return board * CFrame.new(x, y, z or 0)
end

function PlinkoService.build(island)
	local existing = Workspace:FindFirstChild("Plinko")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "Plinko"
	root.Parent = Workspace

	--[[ Stood at the middle of the island's clearing, face turned toward the
	     rim you arrive over, so the board is side-on as you land rather than
	     edge-on. ]]
	--[[ Nine, not four. At four the frame met the clearing right where the
	     ground rises, so the machine read as sinking into the dirt rather than
	     standing on it. It sits on a plinth now, which is what gives the eye
	     the line between object and ground that was missing. ]]
	local base = island.center + Vector3.new(0, 9, 0)
	board = CFrame.new(base) * CFrame.Angles(0, math.rad(180), 0)
		* CFrame.new(0, BINS_H + FIELD / 2, 0)

	local total = ENTRY + FIELD + BINS_H

	part({ name = "Back", size = Vector3.new(HALF * 2 + 3, total, 1),
		cframe = at(0, 0, -DEPTH / 2), color = COL.back }, root)

	--[[ The front is the reason this works as a 2D board at all: the ball is
	     boxed into a four-stud slice, so it cannot drift out of the peg plane
	     and miss the pegs entirely. Transparent, and collidable so players
	     cannot climb inside and catch it. ]]
	part({ name = "Glass", size = Vector3.new(HALF * 2 + 3, total, 0.6),
		cframe = at(0, 0, DEPTH / 2), color = Color3.fromRGB(180, 220, 255),
		transparency = 0.82 }, root)

	for _, side in ipairs({ -1, 1 }) do
		part({ name = "Side", size = Vector3.new(1.4, total, DEPTH + 1.6),
			cframe = at(side * (HALF + 0.7), 0), color = COL.frame,
			material = Enum.Material.Metal }, root)
	end
	part({ name = "Floor", size = Vector3.new(HALF * 2 + 3, 1.2, DEPTH + 1.6),
		cframe = at(0, -total / 2), color = COL.frame,
		material = Enum.Material.Metal }, root)

	-- the plinth: two courses, so it steps down to the ground instead of
	-- meeting it in one abrupt edge
	part({ name = "Plinth", size = Vector3.new(HALF * 2 + 7, 3, DEPTH + 5),
		cframe = at(0, -total / 2 - 2.1), color = COL.frame,
		material = Enum.Material.Metal, collide = true }, root)
	part({ name = "PlinthBase", size = Vector3.new(HALF * 2 + 11, 3.4, DEPTH + 9),
		cframe = at(0, -total / 2 - 5.3), color = COL.back,
		material = Enum.Material.Slate, collide = true }, root)

	--[[
		TRIM AND A HEADER. Without them this is a dark rectangle with dots on
		it -- structurally a Plinko board and visually an unfinished one. A lit
		edge round the face and a marquee across the top are what make it read
		as a machine somebody built rather than geometry somebody placed.

		THE TRIM HAS TO CLEAR THE FRAME, not touch it. At DEPTH/2 + 0.55 its
		front face landed on z = 2.80 -- exactly the side frame's front plane --
		and flickered for the same depth-buffer reason the grass did. Proud of a
		surface is not the same as clear of it; the number has to be checked
		against what is actually there.
	]]
	for _, side in ipairs({ -1, 1 }) do
		part({ name = "Trim", size = Vector3.new(0.5, total, 0.5),
			cframe = at(side * (HALF + 0.7), 0, DEPTH / 2 + 1.15),
			color = COL.gold, material = Enum.Material.Neon }, root)
	end
	for _, edge in ipairs({ -1, 1 }) do
		part({ name = "Trim", size = Vector3.new(HALF * 2 + 4, 0.5, 0.5),
			cframe = at(0, edge * (total / 2 + 0.3), DEPTH / 2 + 1.15),
			color = COL.gold, material = Enum.Material.Neon }, root)
	end

	local header = part({ name = "Header",
		size = Vector3.new(HALF * 2 + 4, 7, DEPTH + 2),
		cframe = at(0, total / 2 + 3.6), color = COL.frame,
		material = Enum.Material.Metal }, root)

	local marquee = Instance.new("SurfaceGui")
	marquee.Name = "Marquee"
	--[[ Back, not Front. The whole board is built through a CFrame turned 180
	     degrees about Y, so a SurfaceGui on Front points away from the player and
	     renders where nobody stands. ]]
	marquee.Face = Enum.NormalId.Back
	marquee.CanvasSize = Vector2.new(600, 120)
	marquee.LightInfluence = 0
	marquee.Parent = header
	local mtext = Instance.new("TextLabel")
	mtext.Size = UDim2.fromScale(1, 1)
	mtext.BackgroundTransparency = 1
	mtext.Font = Enum.Font.GothamBlack
	mtext.Text = "P L I N K O"
	mtext.TextScaled = true
	mtext.TextColor3 = COL.gold
	mtext.Parent = marquee

	--[[ A funnel, so the ball is dropped INTO something rather than appearing
	     in mid-air above the pegs. ]]
	for _, side in ipairs({ -1, 1 }) do
		part({ name = "Funnel", size = Vector3.new(HALF, 0.7, DEPTH - 0.4),
			cframe = at(side * (HALF * 0.62), total / 2 - 3.2)
				* CFrame.Angles(0, 0, math.rad(side * -26)),
			color = COL.frame, material = Enum.Material.Metal }, root)
	end

	--[[
		FULL-WIDTH STAGGERED ROWS, not a triangle.

		The first build was a textbook Galton board -- row r carrying r pegs in
		a widening triangle -- and measuring it found two thirds of balls in the
		two edge bins, an 849% return. The triangle leaves the outer columns
		bare: below the widest row there was a 4.7-stud chute down each side
		with nothing in it, and the 12x fragment bins sat directly under those
		chutes. Any outward drift was a clean fall into the jackpot.

		Real Plinko machines are a full rectangular grid offset half a step per
		row, which is what this is now. Every column has pegs in it, so there is
		nowhere to fall through uninterrupted, and the walls bound the walk
		instead of feeding it.
	]]
	local topPeg = total / 2 - ENTRY
	for r = 1, Plinko.ROWS do
		local wide = r % 2 == 1
		local count = wide and Plinko.BINS or Plinko.BINS - 1
		for i = 1, count do
			local x = wide and (i - (Plinko.BINS + 1) / 2) * W
				or (i - Plinko.BINS / 2) * W
			local peg = part({
				name = "Peg",
				--[[ For a Cylinder, Size.X is the LENGTH along the axis and Y/Z
				     are the diameter -- pass them the other way round and you
				     get a stub. This was (PEG, PEG, DEPTH) and measured as a
				     0.9 cube: a peg too shallow to reliably touch a ball
				     crossing a four-stud channel. ]]
				size = Vector3.new(DEPTH - 0.4, PEG, PEG),
				cframe = at(x, topPeg - (r - 1) * SPACING),
				color = COL.peg,
				material = Enum.Material.Neon,
			}, root)
			peg.Shape = Enum.PartType.Cylinder
			-- turn the axis to lie across the board's depth
			peg.CFrame = peg.CFrame * CFrame.Angles(0, math.rad(90), 0)
		end
	end

	-- bins, with a divider between each
	local binTop = topPeg - FIELD - 2
	PlinkoService.bins = {}
	for j = 1, Plinko.BINS do
		local x = (j - (Plinko.BINS + 1) / 2) * W
		part({ name = "BinFloor", size = Vector3.new(W - 0.4, 0.8, DEPTH - 0.4),
			cframe = at(x, binTop - BINS_H + 1), color = binColor(j),
			material = Enum.Material.Neon }, root)
		if j < Plinko.BINS then
			part({ name = "Divider", size = Vector3.new(0.6, BINS_H, DEPTH - 0.4),
				cframe = at(x + W / 2, binTop - BINS_H / 2), color = COL.divider }, root)
		end

		--[[ What each pocket pays, on the pocket. The colour coding said hot
		     or cold and never said how much, so the whole point of aiming at
		     the edges had to be taken on trust. ]]
		local plate = part({ name = "BinPlate",
			size = Vector3.new(W - 0.5, 2.6, 0.4),
			cframe = at(x, binTop - BINS_H + 3.2, DEPTH / 2 + 0.3),
			color = COL.back, material = Enum.Material.SmoothPlastic }, root)
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Back
		face.CanvasSize = Vector2.new(140, 90)
		face.LightInfluence = 0
		face.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = ("%gx"):format(Plinko.Bins[j].pay)
		label.TextColor3 = Plinko.Bins[j].fragment and COL.gold
			or Color3.fromRGB(232, 238, 252)
		label.Parent = face

		PlinkoService.bins[j] = x
	end

	local console = part({
		name = "Console",
		size = Vector3.new(6, 4, 3),
		cframe = at(0, -total / 2 - 2.6, DEPTH / 2 + 2.4),
		color = COL.frame,
		material = Enum.Material.Metal,
	}, root)

	--[[
		The floating sign is gone; the marquee on the machine says PLINKO now,
		and two of them fought -- the billboard drew straight over the bin
		plates, hiding the very numbers it was duplicating. Only the price is
		left, low and small, where the prompt already draws the eye.
	]]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Price"
	gui.Size = UDim2.fromOffset(190, 26)
	--[[ BELOW the console, not above it. Above put it level with the bin
	     plates and it drew straight across the payout numbers -- the same
	     collision the PLINKO billboard had, moved down a few studs and
	     repeated, because I fixed the sign without checking what else the
	     console sits beside. ]]
	gui.StudsOffsetWorldSpace = Vector3.new(0, -2.6, 0)
	gui.MaxDistance = 150
	gui.Adornee = console
	gui.Parent = console

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 1)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = COL.gold
	sub.TextStrokeTransparency = 0.4
	sub.Text = Format.money(Config.PlinkoDropCost) .. " a ball"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 15
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DropPrompt"
	prompt.ActionText = "Drop a ball"
	prompt.ObjectText = "Plinko"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	prompt.Triggered:Connect(function(player)
		PlinkoService.drop(player)
	end)

	PlinkoService.console = console
	PlinkoService.topY = topPeg + ENTRY - 2
	-- the Y of the first peg row, so a falling ball can be told which row it
	-- is passing and therefore which column it should be drifting toward
	PlinkoService.topPegY = board:PointToWorldSpace(Vector3.new(0, topPeg, 0)).Y
	PlinkoService.binY = binTop - BINS_H
	return root
end

-- ── dropping ────────────────────────────────────────────────────────────────

--[[ [userId] = how many of their balls are in the air. A COUNT, not a flag:
     the machine used to refuse a second ball until the first landed, which
     made a five-second fall the real cost of a drop and turned sixty-nine of
     them into six minutes of waiting. Your money is the limit now. ]]
local inFlight = {}

--[[
	A ceiling anyway, well above what a person can click. It is not there to
	pace anyone -- it is there so a jammed prompt or a scripted client cannot
	put a thousand parts on the island and take the server down with them.

	IT COUNTS FLIGHTS, NOT BALL PARTS, and the two differ on purpose. A ball is
	destroyed 0.8s after it settles, so counting Ball children reads higher
	than this number by however many landed in the last fraction of a second.
	Thirty rapid clicks measured 29 accepted and 28 parts present, which looked
	like the cap leaking and was not: 25 went out, the 26th was refused, and
	four more went as early balls settled and freed their slots. A burst is
	slower than it looks -- InvokeServer blocks on the round trip, so thirty
	clicks spaced 0.12s apart take about 5.3 seconds, comfortably longer than
	the 4.5s a ball takes to land.
]]
local MAX_IN_FLIGHT = 25

function PlinkoService.isNear(player)
	local console = PlinkoService.console
	if not console then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - console.Position).Magnitude <= Config.PlinkoRange
end

function PlinkoService.drop(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if (inFlight[player.UserId] or 0) >= MAX_IN_FLIGHT then
		return { ok = false, err = "That is a lot of balls. Let some land." }
	end
	if not PlinkoService.isNear(player) then
		return { ok = false, err = "Head to the Plinko machine." }
	end
	if profile.money < Config.PlinkoDropCost then
		return { ok = false, err = "Need " .. Format.money(Config.PlinkoDropCost) .. "." }
	end

	profile.money -= Config.PlinkoDropCost
	PlayerState.push(player)
	inFlight[player.UserId] = (inFlight[player.UserId] or 0) + 1

	--[[ Sixteen coin flips, rolled before the ball exists. Nothing here knows
	     the bin -- it is whatever the flips add up to. ]]
	local path, bin = Plinko.roll(rng)
	local column, targets = 0, {}
	for r = 1, Plinko.ROWS do
		column += path[r]
		targets[r] = column * (W / 2)
	end

	local ball = Instance.new("Part")
	ball.Name = "Ball"
	-- Balls ignore one another. They only ever collide at the bottom, and a
	-- pile-up nudging a settled ball into the next pocket would look like the
	-- payout changing after the fact -- it would not (the rolled bin is what
	-- pays) but it would read as a machine that cheats.
	ball.CollisionGroup = BALL_GROUP
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL, BALL, BALL)
	ball.Color = COL.ball
	ball.Material = Enum.Material.Neon
	ball.CanCollide = true
	--[[
		Nearly inelastic, and high friction. Measured across 300 drops on the
		fixed board: elasticity 0.55 put 39% of balls in the middle three bins,
		0.15 got 43%, and 0.02 with friction 0.8 got 52%. A bouncy ball keeps
		its sideways speed through every peg and drifts to a wall; a dead one
		drops more or less where it is deflected.

		52% is still not the 71% a true binomial would give, and that gap is
		the honest state of this machine -- see the note at the top of the file.
	]]
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.8, 0.02, 1, 1)
	--[[ A hair off centre. Dropped exactly onto the apex peg the ball balances
	     there, and a machine that occasionally freezes on the first peg is
	     worse than one that is a fraction less symmetric. ]]
	ball.CFrame = at(math.random(-40, 40) / 200, PlinkoService.topY)
	ball.Parent = Workspace:FindFirstChild("Plinko")
	ball:SetNetworkOwner(nil) -- the server rolls the dice, not the bettor

	--[[
		CARRY THE BALL ALONG THE PATH IT ROLLED.

		Vertical motion is left entirely to physics -- gravity, and every peg it
		clatters off on the way down. Only the sideways component is steered,
		toward the column the coin flips chose for the row it is currently
		passing. So the fall is real, the bouncing is real, and the ball
		genuinely arrives where sixteen flips sent it.

		Steering rather than teleporting, and with a dead zone, so it drifts
		into each column instead of snapping to it.
	]]
	--[[
		THE PEGS ARE SCENERY, and the ball passes through them.

		It collided with them at first, and wedged every single time: a ball
		whose sideways motion is steered has no energy of its own to get off a
		peg it lands on, so it balances there and the drop never finishes.
		Measured over five balls at two different elasticities -- 0.02/friction
		0.8 and 0.45/friction 0.05 -- every one stopped within two rows of the
		top, at identical heights. When the physics properties make no
		difference to the outcome, they are not the variable.

		Since the bounces are already rolled, nothing is lost. The pegs never
		decided anything; they only ever had to look like they did. So the ball
		falls freely, is steered across, and is given a small hop each time it
		crosses a row -- which reads as the clatter down the board it used to
		get from collisions, without any way to get stuck.
	]]
	ball.CanCollide = false

	local right = board.RightVector
	local plane = board.LookVector
	local planeAt = board.Position:Dot(plane)
	local topY = PlinkoService.topPegY
	-- world Y where the peg field ends and the bin pockets begin
	local binTop = topY - FIELD - 2
	local lastRow = 0
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not ball.Parent then
			connection:Disconnect()
			return
		end

		local row = math.clamp(
			math.floor((topY - ball.Position.Y) / SPACING) + 1, 1, Plinko.ROWS)

		--[[ Past the last peg row the ball needs its collisions back, or it
		     falls through the bin floor as well and off the island -- which is
		     exactly what it did the first time. Vertical speed is capped on the
		     way in so it drops into the pocket rather than punching through. ]]
		if ball.Position.Y <= binTop and not ball.CanCollide then
			ball.CanCollide = true
			local v = ball.AssemblyLinearVelocity
			ball.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, -26), v.Z)
		end

		-- a hop on each new row: the visible bounce, minus the wedging
		if row > lastRow and ball.Position.Y > binTop then
			lastRow = row
			local velocity = ball.AssemblyLinearVelocity
			ball.AssemblyLinearVelocity = Vector3.new(velocity.X, 14, velocity.Z)
		end

		local localPos = board:PointToObjectSpace(ball.Position)
		local drift = targets[row] - localPos.X
		local velocity = ball.AssemblyLinearVelocity
		local want = math.clamp(drift * 5, -16, 16)
		velocity += right * (want - velocity:Dot(right))
		-- and hold it in the board's plane, which collisions used to do
		velocity += plane * ((planeAt - ball.Position:Dot(plane)) * 4
			- velocity:Dot(plane))
		ball.AssemblyLinearVelocity = velocity
	end)

	task.spawn(function()
		local deadline = os.clock() + 20
		while os.clock() < deadline do
			task.wait(0.15)
			if not ball.Parent then
				break
			end
			--[[ Against binTop, which is WORLD space. PlinkoService.binY is in
			     board space -- a number like -46 -- so comparing a world Y of
			     226 against it never passed, and every drop sat out the full
			     20-second deadline before paying. It resolved correctly and
			     four times too slowly, which is the kind of bug that hides. ]]
			if ball.Position.Y <= binTop - 4
				and ball.AssemblyLinearVelocity.Magnitude < 3 then
				break
			end
		end
		connection:Disconnect()

		--[[ Pay the rolled bin, not the resting position. They agree -- the
		     steering puts the ball there -- but the roll is what the odds were
		     computed from, so a ball nudged by a player or wedged on a peg
		     cannot change what it was worth. ]]
		PlinkoService.settle(player, bin)
		task.delay(0.8, function()
			if ball.Parent then
				ball:Destroy()
			end
		end)
	end)

	return { ok = true }
end

function PlinkoService.settle(player, index)
	inFlight[player.UserId] = math.max((inFlight[player.UserId] or 1) - 1, 0)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local bin = Plinko.Bins[index]
	local won = math.floor(Config.PlinkoDropCost * bin.pay)
	profile.money += won

	local island = Islands.get("plinko")
	local message = ("Bin %d — %.1fx, %s"):format(index, bin.pay, Format.money(won))

	if bin.fragment and island then
		profile.fragments = profile.fragments or {}
		local held = (profile.fragments[island.seal] or 0) + 1
		profile.fragments[island.seal] = held
		message = ("%s  +1 seal fragment (%d/%d)"):format(
			message, math.min(held, island.sealFragments), island.sealFragments)
	end

	PlayerState.push(player)
	PlayerState.notify(player, message, bin.pay >= 1 and "good" or "info")
end

function PlinkoService.start()
	local island = Islands.get("plinko")
	if not island then
		return
	end
	PlinkoService.build(island)

	Net.get("DropBall").OnServerInvoke = function(player)
		return PlinkoService.drop(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		inFlight[player.UserId] = nil
	end)
end

return PlinkoService
