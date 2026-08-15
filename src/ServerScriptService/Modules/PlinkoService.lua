--[[
	PlinkoService
	The first island's machine. A real ball, real pegs, and whatever bin it
	lands in is the answer.

	THE SERVER OWNS THE BALL. Physics parts default to being simulated by
	whichever client is nearest, which for a gambling machine would mean the
	person betting also decides where the ball goes. SetNetworkOwner(nil) pins
	simulation to the server, so the drop is as unreachable as a dice roll made
	in a locked room.

	NO PREDETERMINED OUTCOME, unlike the wheel. The wheel picks a result and
	tweens toward it because a wheel can be steered convincingly and a bouncing
	ball cannot. Here there is nothing to steer: the ball falls, the bin it
	settles in is read, and that IS the result. It is the honest version, and
	it is only available because the physics happens to be watchable.

	WHICH MEANS THE ODDS ARE AN EMPIRICAL QUESTION. tools/plinko.py assumes a
	clean binomial -- a perfect 50/50 at every peg. Real collisions are not
	perfect, so the true distribution will be bell-shaped but not exactly
	binomial, and the payout table is only correct once it has been measured
	against a few thousand real drops. That measurement is still to do.
]]

local Players = game:GetService("Players")
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

-- ── board geometry ──────────────────────────────────────────────────────────

local W = 4 -- bin width, and the horizontal step between pegs
local SPACING = 5 -- vertical gap between peg rows
local BALL = 1.5 -- diameter; must clear W minus two peg radii
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
	local base = island.center + Vector3.new(0, 4, 0)
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

	--[[ A Galton board: row r carries r pegs, each row offset half a step from
	     the last. That stagger is the entire mechanism -- it is what turns each
	     row into one left-or-right coin flip. ]]
	local topPeg = total / 2 - ENTRY
	for r = 1, Plinko.ROWS do
		for i = 1, r do
			local peg = part({
				name = "Peg",
				size = Vector3.new(PEG, PEG, DEPTH - 0.4),
				cframe = at((i - (r + 1) / 2) * W, topPeg - (r - 1) * SPACING),
				color = COL.peg,
				material = Enum.Material.Neon,
			}, root)
			peg.Shape = Enum.PartType.Cylinder
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
		PlinkoService.bins[j] = x
	end

	local console = part({
		name = "Console",
		size = Vector3.new(6, 4, 3),
		cframe = at(0, -total / 2 - 2.6, DEPTH / 2 + 2.4),
		color = COL.frame,
		material = Enum.Material.Metal,
	}, root)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(250, 62)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 260
	gui.Adornee = console
	gui.Parent = console -- on the console, never the model: streaming + origin

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "PLINKO"
	title.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 28
	cap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 206, 64)
	sub.TextStrokeTransparency = 0.45
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
	PlinkoService.binY = binTop - BINS_H
	return root
end

-- ── dropping ────────────────────────────────────────────────────────────────

local dropping = {} -- [userId] = true while a ball of theirs is in the air

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

--[[ Which bin a resting ball is in, from its position along the board's own X
     axis. Read from geometry rather than from a Touched event, because a ball
     can brush two bin floors on the way to settling in one of them. ]]
local function binOf(position)
	local local_ = board:PointToObjectSpace(position)
	local index = math.floor(local_.X / W + (Plinko.BINS + 1) / 2 + 0.5)
	return math.clamp(index, 1, Plinko.BINS)
end

function PlinkoService.drop(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if dropping[player.UserId] then
		return { ok = false, err = "Your ball is still falling." }
	end
	if not PlinkoService.isNear(player) then
		return { ok = false, err = "Head to the Plinko machine." }
	end
	if profile.money < Config.PlinkoDropCost then
		return { ok = false, err = "Need " .. Format.money(Config.PlinkoDropCost) .. "." }
	end

	profile.money -= Config.PlinkoDropCost
	PlayerState.push(player)
	dropping[player.UserId] = true

	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL, BALL, BALL)
	ball.Color = COL.ball
	ball.Material = Enum.Material.Neon
	ball.CanCollide = true
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.55, 1, 1)
	--[[ A hair off centre. Dropped exactly onto the apex peg the ball balances
	     there, and a machine that occasionally freezes on the first peg is
	     worse than one that is a fraction less symmetric. ]]
	ball.CFrame = at(math.random(-40, 40) / 200, PlinkoService.topY)
	ball.Parent = Workspace:FindFirstChild("Plinko")
	ball:SetNetworkOwner(nil) -- the server rolls the dice, not the bettor

	task.spawn(function()
		local resolved, deadline = nil, os.clock() + 20
		while os.clock() < deadline do
			task.wait(0.15)
			if not ball.Parent then
				break
			end
			if ball.Position.Y <= PlinkoService.binY + 4
				and ball.AssemblyLinearVelocity.Magnitude < 3 then
				resolved = binOf(ball.Position)
				break
			end
		end
		-- A stuck ball still pays: read wherever it ended up rather than
		-- silently eating the stake.
		resolved = resolved or (ball.Parent and binOf(ball.Position)) or 5
		PlinkoService.settle(player, resolved)
		task.delay(0.6, function()
			if ball.Parent then
				ball:Destroy()
			end
		end)
	end)

	return { ok = true }
end

function PlinkoService.settle(player, index)
	dropping[player.UserId] = nil
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
		dropping[player.UserId] = nil
	end)
end

return PlinkoService
