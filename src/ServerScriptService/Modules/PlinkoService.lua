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
local Seals = require(Shared.Seals)

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

--[[
	W IS THE BIN PITCH AND THEREFORE THE PEG PITCH, and it was 5.2 to stop
	sixteen rows reading as a tower: 71 tall against 39 wide.

	4.2 solves that from the other end. Widening the bins fixed the ratio by
	growing the part that was already too big; narrowing them fixes it by
	shrinking it, which costs nothing -- a pocket only has to catch a 2.8 ball,
	and 4.2 less a 0.6 divider still leaves 3.6.

	It also lands the peg pitch on the reference machine's, which measures
	3.96 across 133 pegs. Ours is now 4.2 at the same board proportion (74 by
	68, against its 71 by 67), which is the whole reason for the number.
]]
local W = 4.2
--[[ Up from 2.6, and it is the narrower bins that pay for it: the board can
     afford to be taller now without going back to being a tower. The row count
     is set by the odds we want, not by the space -- see Shared/Plinko -- so
     the spacing is the only free variable in the ratio. ]]
local SPACING = 3.2
--[[
	THE BALL HAS TO BEAT THE PEGS, and that is a ratio, not a size.

	At 2.8 against a 0.9 pin the ball was unmistakably the moving thing. At 2.8
	against a 2.6 stud it was the same size as the scenery and merged with
	whatever peg it was passing, which is the one thing this part is not
	allowed to do.

	1.4 AGAINST A 4.2 PITCH -- a third of the pitch covered, two thirds air.
	The pegs went to 2.6 to copy the reference machine, which runs about three
	quarters covered, and at that density the field reads as a wall with holes
	rather than as a grid of pins: 55% of the pitch was peg. A third is still
	far chunkier than the 0.9 pin this started as (17%), and the ball is now
	well over twice a peg's width, so it stays the thing your eye follows.
]]
local BALL = 3.2
local PEG = 1.4
--[[ Seven, and the two occupants are why. A 3.2 ball and a 2.0 peg need 5.2
     studs of interior between the backboard's face and the glass, and DEPTH
     is what buys it -- at 6 they had 5.2 to share and touched exactly. ]]
local DEPTH = 7 -- how thick the board is; the ball is boxed into this slice

--[[
	THE BALL RIDES IN FRONT OF THE PEGS, not through them.

	Both sat on the board's centre plane, which was invisible while a peg was
	0.9 across and a thin bar crossing the ball now and then. At 2.6 it is not:
	a ball that vanishes inside a stud and comes out the far side reads as a
	rendering fault, and the pegs had to get fat for the board to look like the
	machine it is copying.

	So the pegs are mounted ON the backboard and stop short, and the ball is
	held one stud proud of their tips. Worth noting what this makes impossible
	rather than merely switched off: the wedging that forced CanCollide = false
	in the first place cannot happen when the two never share a depth. The
	interior runs -2.5 (back face) to 2.7 (glass), and the two occupants of it
	are laid out to touch neither each other nor the panels.
]]
local PEG_LEN = 2.0
local PEG_Z = -DEPTH / 2 + 0.5 + PEG_LEN / 2 -- flush to the backboard's face
local BALL_Z = 1.0 -- clear of the peg tips behind and the glass in front

local HALF = W * (Plinko.BINS / 2) -- 18 for a 9-bin board
local FIELD = (Plinko.ROWS - 1) * SPACING
local ENTRY = 9 -- drop height above the first peg
local BINS_H = 11 -- bin pocket depth

local COL = {
	frame = Color3.fromRGB(58, 72, 96),
	back = Color3.fromRGB(30, 42, 58),
	peg = Color3.fromRGB(244, 246, 250),
	ball = Color3.fromRGB(255, 206, 64),
	divider = Color3.fromRGB(78, 92, 120),
	gold = Color3.fromRGB(242, 188, 64),
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
--[[
	THE MACHINE CURRENTLY BEING BUILT.

	Every coordinate below is written in board space and transformed once
	through this, which is what lets a machine be dropped anywhere and turned
	to face anything without touching a single number in the geometry.

	It is module state rather than a parameter for one reason: `at` is called
	about thirty times through the build and threading a board through all of
	them would be noise. buildMachine sets it, builds, and captures it into the
	machine's record -- and the build is SYNCHRONOUS, so there is never a
	second machine part-built against a stale board. Nothing outside the build
	may read this; the runtime path takes its board off the machine record.
]]
local board -- CFrame: X across, Y up, Z out of the face

local function at(x, y, z)
	return board * CFrame.new(x, y, z or 0)
end

--[[
	One machine, at a given spot, facing a given way.

	Returns a record -- board, console, bins, and the three heights the falling
	ball is steered by. Those used to live on PlinkoService itself, which was
	fine while there was exactly one machine and became a bug the moment there
	were four: every ball would have been steered by whichever machine was
	built last.
]]
local function buildMachine(index, base, facing, parent)
	local root = Instance.new("Model")
	root.Name = "Machine" .. index
	root.Parent = parent

	--[[ Nine, not four. At four the frame met the clearing right where the
	     ground rises, so the machine read as sinking into the dirt rather than
	     standing on it. It sits on a plinth now, which is what gives the eye
	     the line between object and ground that was missing. ]]
	board = CFrame.new(base + Vector3.new(0, 9, 0)) * CFrame.Angles(0, facing, 0)
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
		A TRIANGLE, WHICH IT WAS NOT ALLOWED TO BE UNTIL NOW.

		This was a full-width rectangular grid, and the comment here used to
		argue hard for it: the original triangle measured two thirds of balls in
		the two edge bins and an 849% return, because the outer columns were
		bare and a drifting ball fell down a clean chute straight into the
		jackpot.

		THAT REASON DIED WITH THE PHYSICS-DECIDED ERA. Nothing about the layout
		can move the odds any more -- the bin comes from Plinko.roll, sixteen
		coin flips made before the ball exists, and the ball is steered toward
		the column those flips chose. Pegs are now clatter and guidance, not a
		decision, so the shape is free to be the shape everyone recognises.

		AND THE TRIANGLE ACTUALLY FITS THE ROLL. After r rows a ball is at most
		r half-steps from centre, which is r*W/2; a row of r+2 pegs spans
		(r+1)*W/2 either side. So the field is always exactly wide enough to
		hold every path the roll can produce -- it can never be steered into a
		gap that isn't there. Row 16 carries 18 pegs, which is the 17 bins plus
		the pair that bound them.
	]]
	local topPeg = total / 2 - ENTRY
	for r = 1, Plinko.ROWS do
		local count = r + 2
		for i = 1, count do
			local x = (i - (count + 1) / 2) * W
			local peg = part({
				name = "Peg",
				--[[ For a Cylinder, Size.X is the LENGTH along the axis and Y/Z
				     are the diameter -- pass them the other way round and you
				     get a stub. ]]
				size = Vector3.new(PEG_LEN, PEG, PEG),
				cframe = at(x, topPeg - (r - 1) * SPACING, PEG_Z),
				color = COL.peg,
				--[[ Plastic, not Neon. Neon was right for a 0.9 pin picked out
				     against a dark board; a hundred and sixty-eight 2.6 studs
				     of it is a wall of white light with no shape to it. The
				     reference machine is 288 plastic parts and reads as
				     moulded, which is what the size needs to stay legible. ]]
				material = Enum.Material.SmoothPlastic,
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
		--[[ Lifted a hair, and the hair matters. At `binTop - BINS_H + 1` the
		     bin floor's top face lands at -total/2 - 0.6, which is exactly where
		     the Plinth's top face is -- work it through and the two expressions
		     reduce to the same number. Two up-facing coplanar surfaces with
		     nothing to order them is z-fighting, and because these two differ
		     (neon bin colour against the metal frame) it is the visible kind:
		     the bins flickered. ]]
		part({ name = "BinFloor", size = Vector3.new(W - 0.4, 0.8, DEPTH - 0.4),
			cframe = at(x, binTop - BINS_H + 1.06), color = binColor(j),
			material = Enum.Material.Neon }, root)
		if j < Plinko.BINS then
			--[[ 0.45, not 0.6. The pocket has to swallow a 3.2 ball, and a
			     4.2 pitch less a 0.6 divider left 3.6 -- clearance measured in
			     millimetres, on the one part of the fall where the ball is
			     collidable and a landing on a divider top is a stuck ball. ]]
			part({ name = "Divider", size = Vector3.new(0.45, BINS_H, DEPTH - 0.4),
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
	gui.Size = UDim2.fromOffset(114, 16)
	--[[
		ADORNED TO ITS OWN ANCHOR, in front of the plinth.

		STILL BELOW THE MACHINE, never above it. Above puts it level with the
		bin plates and it draws straight across the payout numbers -- the same
		collision the old floating PLINKO sign had. Low is not the problem.

		It hung 2.6 studs under the console, which put it INSIDE the plinth:
		the two courses are sized off DEPTH (DEPTH + 9 for the base), so the
		label sat about two studs behind the front face and rendered as
		whichever letters cleared it -- "ball", out of "from $450K a ball".
		Widening the cabinet did not cause that, it only made it obvious.

		AlwaysOnTop was the first fix and the wrong one: it stopped the label
		drawing at all rather than drawing it over the plinth. So the label is
		moved instead of re-ordered, onto an invisible anchor placed in BOARD
		space -- which, unlike StudsOffsetWorldSpace, stays correct if the
		machine is ever turned to face somewhere else.
	]]
	--[[ DEPTH/2 + 6 clears the plinth base's front face, at DEPTH/2 + 4.5, by
	     a stud and a half. 4.6 cleared it by 0.1, which is not clearance -- it
	     is the same coincidence this label already fell foul of once. ]]
	local anchor = part({ name = "PriceAnchor", size = Vector3.new(0.2, 0.2, 0.2),
		cframe = at(0, -total / 2 - 5.4, DEPTH / 2 + 6), color = COL.frame,
		transparency = 1, collide = false }, root)

	gui.MaxDistance = 150
	gui.Adornee = anchor
	gui.Parent = anchor

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 1)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = COL.gold
	sub.TextStrokeTransparency = 0.4
	sub.Text = "from " .. Format.money(Config.PlinkoDropCost) .. " a ball"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 9
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DropPrompt"
	prompt.ActionText = "Play Plinko"
	prompt.ObjectText = "Plinko"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	--[[ The prompt OPENS THE PANEL now rather than dropping. It used to drop
	     straight away, which was right when a ball had one price; with a stake
	     to choose, a prompt that spends money the instant you press E is a way
	     to lose twenty times the minimum by accident. ]]
	prompt.Triggered:Connect(function(player)
		Net.get("OpenPlinko"):FireClient(player)
	end)

	return {
		root = root,
		board = board,
		console = console,
		bins = PlinkoService.bins,
		topY = topPeg + ENTRY - 2,
		-- the Y of the first peg row, so a falling ball can be told which row
		-- it is passing and therefore which column it should be drifting toward
		topPegY = board:PointToWorldSpace(Vector3.new(0, topPeg, 0)).Y,
		binY = binTop - BINS_H,
	}
end

--[[
	FOUR MACHINES, EVENLY SPACED, ALL FACING THE MIDDLE.

	On a ring rather than in a row: a row has a best seat and a worst one, and
	the island is a disc. Facing inward means the plaza between them is where
	you stand to watch, and every board is legible from it.

	The ring radius is set against the board's own width. Four machines at 90
	degrees sit RING * sqrt(2) apart, so at 105 that is 148 studs between
	neighbours against a 74-stud board -- a full board's width of air on either
	side, which is what stops them reading as one long wall.
]]
local COUNT = 4
local RING = 105

function PlinkoService.build(island)
	local existing = Workspace:FindFirstChild("Plinko")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "Plinko"
	root.Parent = Workspace

	PlinkoService.machines = {}
	for index = 1, COUNT do
		local angle = (index - 1) / COUNT * math.pi * 2
		local spot = island.center
			+ Vector3.new(math.cos(angle) * RING, 0, math.sin(angle) * RING)
		--[[
			TURNED TO FACE THE CENTRE, and the yaw is solved rather than
			guessed -- the first attempt was `angle + pi/2 + pi`, which pointed
			two of the four the wrong way and looked plausible from one camera
			angle.

			The face is the board's +Z, NOT its LookVector: the header calls it
			"Z out of the face" and LookVector is -Z. So the face normal of
			CFrame.Angles(0, t, 0) is (sin t, 0, cos t), and pointing it at the
			middle from an angle a means solving

			    sin t = -cos a,  cos t = -sin a   ->   t = -(pi/2 + a)

			Checks out at both ends: a = 0 gives a face normal of (-1, 0, 0)
			from (+R, 0, 0), and a = pi/2 gives (0, 0, -1) from (0, 0, +R).
		]]
		local machine = buildMachine(index, spot, -(math.pi / 2 + angle), root)
		machine.index = index
		table.insert(PlinkoService.machines, machine)
	end

	--[[ Kept for anything that still wants "the" machine -- the coach's
	     waypoint, and the tour. The first is as good as any and they are all
	     the same distance from the middle. ]]
	PlinkoService.console = PlinkoService.machines[1].console
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

--[[
	The machine this player is standing at, or nil.

	NEAREST, not first-in-range, because the four are only 148 studs apart and
	PlinkoRange is 26 -- close enough that a player between two of them would
	otherwise drop on whichever happened to be earlier in the list, and watch
	their ball fall down the machine they were not looking at.
]]
local function nearestMachine(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, Config.PlinkoRange
	for _, machine in ipairs(PlinkoService.machines or {}) do
		local distance = (root.Position - machine.console.Position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = machine, distance
		end
	end
	return best
end

function PlinkoService.isNear(player)
	return nearestMachine(player) ~= nil
end

--[[ What this player is allowed to stake, and what they asked for clamped
     into it. Shared with the client through the DropBall reply so the panel and
     the server can never disagree about the limits. ]]
function PlinkoService.stakeRange(profile)
	local low = Config.PlinkoDropCost
	local high = low * Config.PlinkoMaxStakeMultiple
	return low, high
end

function PlinkoService.drop(player, stake)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if (inFlight[player.UserId] or 0) >= MAX_IN_FLIGHT then
		return { ok = false, err = "That is a lot of balls. Let some land." }
	end
	--[[ Resolved ONCE, here, and carried through the whole drop. Asking again
	     later would let a player who walked between two machines mid-fall have
	     their ball steered by one board and paid out by another. ]]
	local machine = nearestMachine(player)
	if not machine then
		return { ok = false, err = "Head to a Plinko machine." }
	end
	--[[ The seal gate. Plinko declares no `requires`, being the chapter you
	     start in, so this always passes today -- it is here so the second
	     island's game is a table entry with a `requires` field and not a hunt
	     through every service for where permission should have been checked. ]]
	local allowed, needs = Seals.canEnter(profile, Islands.get("plinko"))
	if not allowed then
		local gate = Islands.get(needs)
		return { ok = false, err = ("Needs the %s saddle."):format(
			(gate and gate.name) or needs) }
	end
	--[[ THE STAKE IS AN INPUT, so it is floored, clamped and re-read rather
	     than trusted. A client asking to stake a negative amount would
	     otherwise be paid a negative multiple of it, which is a deposit. ]]
	local low, high = PlinkoService.stakeRange(profile)
	stake = math.floor(tonumber(stake) or low)
	stake = math.clamp(stake, low, high)

	if profile.money < stake then
		return { ok = false, err = "Need " .. Format.money(stake) .. "." }
	end

	profile.money -= stake
	--[[ Remembered so the next drop opens on the same number. Someone dropping
	     twenty balls should set their stake once. ]]
	profile.plinkoStake = stake
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
	ball.CFrame = machine.board
		* CFrame.new(math.random(-40, 40) / 200, machine.topY, BALL_Z)
	--[[ Parented to ITS OWN machine, not to the Plinko model. Four machines
	     dropping into one folder would make "how many balls are on this board"
	     unanswerable, and a machine that is ever rebuilt would take everyone
	     else's balls with it. ]]
	ball.Parent = machine.root
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
		THE PEGS ARE SCENERY, and the ball passes IN FRONT of them.

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

		The depth split (see PEG_Z / BALL_Z) came later, for the look, and it
		makes this structural rather than merely switched off: the two no longer
		share a plane, so there is nothing here to wedge on even if the flag
		were wrong. The flag stays anyway -- it is what keeps the ball off the
		side rails and the glass while the steering is throwing it about.
	]]
	ball.CanCollide = false

	local right = machine.board.RightVector
	local plane = machine.board.LookVector
	--[[ The ball's plane, not the board's centre. These were the same number
	     while the ball sat at z = 0; now that it rides in front of the pegs,
	     holding it to the board's middle would drag it straight back into
	     them. ]]
	local planeAt = machine.board:PointToWorldSpace(Vector3.new(0, 0, BALL_Z)):Dot(plane)
	local topY = machine.topPegY
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

		local localPos = machine.board:PointToObjectSpace(ball.Position)
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
		PlinkoService.settle(player, bin, stake)
		task.delay(0.8, function()
			if ball.Parent then
				ball:Destroy()
			end
		end)
	end)

	return { ok = true }
end

--[[ `stake` travels with the ball rather than being re-read from the profile.
     Up to MAX_IN_FLIGHT balls can be falling at once and the dial can be moved
     between drops, so the profile's current stake is not necessarily the one
     THIS ball was bought with. ]]
function PlinkoService.settle(player, index, stake)
	inFlight[player.UserId] = math.max((inFlight[player.UserId] or 1) - 1, 0)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local bin = Plinko.Bins[index]
	local won = math.floor((stake or Config.PlinkoDropCost) * bin.pay)
	profile.money += won

	local island = Islands.get("plinko")
	local message = ("Bin %d — %.1fx, %s"):format(index, bin.pay, Format.money(won))

	--[[ The award, the forging and the "already held" case all live in
	     Shared/Seals, so the second island's game is one call rather than a
	     copy of this arithmetic. ]]
	local sealed = false
	if bin.fragment and island then
		local held, need, justSealed = Seals.award(profile, island)
		sealed = justSealed
		if justSealed then
			message = ("%s  —  %s SEAL COMPLETE"):format(message, island.name:upper())
		elseif Seals.held(profile, island.seal) then
			message = ("%s  (saddle already forged)"):format(message)
		else
			message = ("%s  +1 saddle piece (%d/%d)"):format(message, held, need)
		end
	end

	PlayerState.push(player)
	--[[ A seal is the rarest thing this machine produces -- 69 drops of
	     expected play -- so it does not share the tone of a 0.3x bin. ]]
	PlayerState.notify(player, message, sealed and "great" or (bin.pay >= 1 and "good" or "info"))
end

function PlinkoService.start()
	local island = Islands.get("plinko")
	if not island then
		return
	end
	PlinkoService.build(island)

	Net.get("DropBall").OnServerInvoke = function(player, stake)
		return PlinkoService.drop(player, stake)
	end

	Players.PlayerRemoving:Connect(function(player)
		inFlight[player.UserId] = nil
	end)
end

return PlinkoService
