--[[
	HubService
	The Auction House, and the portal in the street that reaches it.

	Mines and Upgrades used to be two bulky monuments 34 and 79 studs from the
	map's archway, crowding the same stretch of road. Every future service --
	trading, an index, a rebirth altar -- would have made that worse, because
	the street is the only place to put things.

	So services move indoors. The map's own archway becomes a portal, and
	everything lives in a room on the other side. Adding a station is now a
	matter of filling one of the reserved bays rather than finding somewhere
	outdoors that isn't already taken.

	The hub sits at X = 4000, far outside Lighting.FogEnd (3000), so it is never
	visible from the map and needs no walls of its own to hide it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Format = require(Shared.Format)

local AuctionService = require(script.Parent.AuctionService)
local ModelFactory = require(script.Parent.ModelFactory)

local HubService = {}

--[[
	The map's OWN archways, one capping each end of the street: posts, a lintel,
	and a dark fill panel. A finished doorway, so the portal drops into it rather
	than standing in open ground.

	The catch is that the fill panel is SOLID -- it's the wall that closes the
	street off, and outside it the ground jumps to the baseplate at y=36. Putting
	the plane in the middle of the archway buried it inside that wall, where a
	player can never touch it.

	So `pos` is the panel's STREET-FACING surface, not the archway's centre, and
	the plane stands a stud proud of it. You touch the portal a step before you'd
	hit the wall, and the wall stays behind it as a backstop.

	Both archways are thin along X and open along Z, so the plane is thin on X.
	Two of them because the street runs 590 studs end to end; a single entrance
	would mean a long walk from half the bases.
]]
local GATES = {
	{ pos = Vector3.new(-334.4, 7.2, -66.5), width = 21.5, height = 13.2 }, -- west, street lies +X
	{ pos = Vector3.new(249.0, 8.9, -66.4), width = 26.5, height = 16.5 }, -- east, street lies -X
}
local PRIMARY = GATES[1]

local HUB = Vector3.new(4000, 200, 0)
local FLOOR_W, FLOOR_D = 104, 76

local STONE = Color3.fromRGB(64, 70, 96)
local STONE_LIT = Color3.fromRGB(96, 106, 138)
local TRIM = Color3.fromRGB(120, 132, 255)
local GOLD = Color3.fromRGB(255, 190, 60)

local recentTeleport = {} -- [userId] = os.clock(), stops the pad re-firing

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = false
	p.CanTouch = props.touch == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Transparency = props.transparency or 0
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

local function sign(parent, adornee, title, subtitle, color, maxTitle)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(230, 62)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 180
	gui.Adornee = adornee
	gui.Parent = parent

	local a = Instance.new("TextLabel")
	a.Size = UDim2.new(1, 0, 0.6, 0)
	a.BackgroundTransparency = 1
	a.Font = Enum.Font.GothamBlack
	a.TextScaled = true
	a.TextColor3 = Color3.fromRGB(236, 240, 255)
	a.TextStrokeTransparency = 0.3
	a.Text = title
	a.Parent = gui
	local ac = Instance.new("UITextSizeConstraint")
	ac.MaxTextSize = maxTitle or 26
	ac.Parent = a

	local b = Instance.new("TextLabel")
	b.Size = UDim2.new(1, 0, 0.4, 0)
	b.Position = UDim2.new(0, 0, 0.6, 0)
	b.BackgroundTransparency = 1
	b.Font = Enum.Font.GothamMedium
	b.TextScaled = true
	b.TextColor3 = color
	b.TextStrokeTransparency = 0.45
	b.Text = subtitle
	b.Parent = gui
	local bc = Instance.new("UITextSizeConstraint")
	bc.MaxTextSize = 14
	bc.Parent = b
	return a, b
end

-- ── the gate in the street ──────────────────────────────────────────────────

function HubService.buildGate()
	local existing = Workspace:FindFirstChild("HubGate")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "HubGate"
	root.Parent = Workspace

	for index, gate in ipairs(GATES) do
		-- Thin on X: these doorways face along the street's long axis, so the
		-- plane fills the Z opening. 1.2 thick rather than paper-thin so a
		-- character at max walk speed can't step past it between physics frames.
		local plane = part({
			name = "Portal" .. index,
			size = Vector3.new(1.2, gate.height, gate.width),
			cframe = CFrame.new(gate.pos),
			color = TRIM,
			material = Enum.Material.Neon,
			transparency = 0.45,
			collide = false,
			touch = true,
		}, root)

		-- gold edging inside the map's own frame
		for _, side in ipairs({ -1, 1 }) do
			part({
				name = "Jamb",
				size = Vector3.new(1, gate.height + 1, 0.9),
				cframe = CFrame.new(gate.pos + Vector3.new(0, 0, side * (gate.width / 2 + 0.4))),
				color = GOLD,
				material = Enum.Material.Neon,
				collide = false,
			}, root)
		end
		part({
			name = "Lintel",
			size = Vector3.new(1, 0.9, gate.width + 2),
			cframe = CFrame.new(gate.pos + Vector3.new(0, gate.height / 2 + 0.5, 0)),
			color = GOLD,
			material = Enum.Material.Neon,
			collide = false,
		}, root)

		local glow = Instance.new("PointLight")
		glow.Color = TRIM
		glow.Range = 42
		glow.Brightness = 2.4
		glow.Parent = plane

		sign(root, plane, "AUCTION HOUSE", "walk through", GOLD, 28)

		plane.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				HubService.sendToHub(player)
			end
		end)
	end

	return root
end

-- ── the hub interior ────────────────────────────────────────────────────────

--[[
	The room is one thing now, not a parade of service counters: an auction
	floor with the block in the middle.

	Mines went back to being playable anywhere and upgrades moved out to their
	own street shop, so the bay layout had nothing left to hold. What replaced
	it is a single focal point -- whatever is currently under the hammer stands
	lit on the block, and the desk beside it is where you consign and bid.
]]
local BLOCK = Vector3.new(0, 0, -6) -- offset from HUB, the centre of the room
local DESK = Vector3.new(0, 0, 16) -- consign desk, between the block and the exit

function HubService.build()
	local existing = Workspace:FindFirstChild("AuctionHouse")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "AuctionHouse"
	root.Parent = Workspace

	part({
		name = "Floor",
		size = Vector3.new(FLOOR_W, 2, FLOOR_D),
		cframe = CFrame.new(HUB),
		color = STONE,
		material = Enum.Material.Slate,
	}, root)

	-- inlaid glowing border, so the floor reads at the hub's low light
	for _, edge in ipairs({
		{ Vector3.new(0, 1.05, FLOOR_D / 2 - 1), Vector3.new(FLOOR_W - 4, 0.2, 0.6) },
		{ Vector3.new(0, 1.05, -FLOOR_D / 2 + 1), Vector3.new(FLOOR_W - 4, 0.2, 0.6) },
		{ Vector3.new(FLOOR_W / 2 - 1, 1.05, 0), Vector3.new(0.6, 0.2, FLOOR_D - 4) },
		{ Vector3.new(-FLOOR_W / 2 + 1, 1.05, 0), Vector3.new(0.6, 0.2, FLOOR_D - 4) },
	}) do
		part({
			name = "Inlay",
			size = edge[2],
			cframe = CFrame.new(HUB + edge[1]),
			color = TRIM,
			material = Enum.Material.Neon,
			collide = false,
		}, root)
	end

	-- colonnade
	for _, side in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			local base = HUB + Vector3.new(i * 22, 0, side * (FLOOR_D / 2 - 3))
			part({
				name = "Column",
				size = Vector3.new(3, 26, 3),
				cframe = CFrame.new(base + Vector3.new(0, 14, 0)),
				color = STONE_LIT,
				material = Enum.Material.Slate,
			}, root)
			part({
				name = "Capital",
				size = Vector3.new(4.4, 0.8, 4.4),
				cframe = CFrame.new(base + Vector3.new(0, 27.2, 0)),
				color = TRIM,
				material = Enum.Material.Neon,
				collide = false,
			}, root)
		end
	end

	-- ── the block ───────────────────────────────────────────────────────────
	--[[ A raised dais with a display stand on top. Whatever lot is closest to
	     closing stands here, so the room always shows what it's for. ]]
	local blockSpot = HUB + BLOCK

	part({
		name = "BlockDais",
		size = Vector3.new(26, 2, 26),
		cframe = CFrame.new(blockSpot + Vector3.new(0, 1.5, 0)),
		color = STONE_LIT,
		material = Enum.Material.Slate,
	}, root)
	part({
		name = "BlockRim",
		size = Vector3.new(27.4, 0.35, 27.4),
		cframe = CFrame.new(blockSpot + Vector3.new(0, 2.6, 0)),
		color = GOLD,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	local stand = part({
		name = "BlockStand",
		size = Vector3.new(9, 3.2, 9),
		cframe = CFrame.new(blockSpot + Vector3.new(0, 4.1, 0)),
		color = STONE,
		material = Enum.Material.Marble,
	}, root)

	-- The spot a lot's model is pivoted onto. An invisible marker rather than a
	-- computed offset so AuctionDisplay never has to know the dais geometry.
	local pedestal = part({
		name = "Pedestal",
		size = Vector3.new(1, 1, 1),
		cframe = CFrame.new(blockSpot + Vector3.new(0, 5.7, 0)),
		color = GOLD,
		transparency = 1,
		collide = false,
	}, root)

	-- spotlight down onto whatever is standing there
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = 44
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(255, 236, 198)
	spot.Parent = part({
		name = "BlockLamp",
		size = Vector3.new(4, 0.6, 4),
		cframe = CFrame.new(blockSpot + Vector3.new(0, 24, 0)),
		color = GOLD,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	local blockTitle, blockSub = sign(root, stand, "ON THE BLOCK", "nothing listed", GOLD, 26)
	HubService.blockTitle, HubService.blockSub = blockTitle, blockSub

	-- ── the consign desk ────────────────────────────────────────────────────
	local deskSpot = HUB + DESK

	part({
		name = "DeskFloor",
		size = Vector3.new(30, 0.4, 12),
		cframe = CFrame.new(deskSpot + Vector3.new(0, 1.2, 0)),
		color = STONE_LIT,
		material = Enum.Material.Slate,
	}, root)

	local desk = part({
		name = "ConsignDesk",
		size = Vector3.new(16, 3.4, 3.6),
		cframe = CFrame.new(deskSpot + Vector3.new(0, 3.1, 0)),
		color = STONE_LIT,
		material = Enum.Material.Metal,
	}, root)
	part({
		name = "DeskGlow",
		size = Vector3.new(15.4, 0.3, 3),
		cframe = CFrame.new(deskSpot + Vector3.new(0, 4.9, 0)),
		color = GOLD,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AuctionPrompt"
	prompt.ActionText = "Sell / Bid"
	prompt.ObjectText = "Auction House"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = desk
	prompt.Triggered:Connect(function(player)
		Net.get("OpenAuction"):FireClient(player)
	end)

	sign(root, desk, "CONSIGN & BID", "put a brainrot up", GOLD, 24)

	HubService.pedestal = pedestal
	HubService.desk = desk

	-- ── the way home ────────────────────────────────────────────────────────
	local exit = part({
		name = "Exit",
		size = Vector3.new(14, 16, 0.6),
		cframe = CFrame.new(HUB + Vector3.new(0, 9, -FLOOR_D / 2 + 4)),
		color = GOLD,
		material = Enum.Material.Neon,
		transparency = 0.45,
		collide = false,
		touch = true,
	}, root)
	local exitGlow = Instance.new("PointLight")
	exitGlow.Color = GOLD
	exitGlow.Range = 34
	exitGlow.Brightness = 2
	exitGlow.Parent = exit
	sign(root, exit, "BACK TO THE STREET", "walk through", GOLD, 22)

	exit.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			HubService.sendToStreet(player)
		end
	end)

	return root
end

--[[
	Keep the block showing the lot closest to the hammer.

	Polled, like the landmark's event sync and for the same reason: AuctionService
	has no listener hook, and a two-second lag on a two-minute auction is
	invisible. Rebuilds the model only when the LOT changes, so a bid every few
	seconds doesn't churn a model on the pedestal.
]]
function HubService.startBlockDisplay()
	task.spawn(function()
		local showingId = nil
		local shown = nil

		while true do
			local top = AuctionService.snapshot()[1]

			if (top and top.id) ~= showingId then
				showingId = top and top.id or nil
				if shown then
					shown:Destroy()
					shown = nil
				end
				if top then
					shown = ModelFactory.build(top.charId, top.variantId)
					if shown and HubService.pedestal then
						ModelFactory.place(shown, HubService.pedestal.CFrame)
						shown.Parent = Workspace:FindFirstChild("AuctionHouse")
					end
				end
			end

			if HubService.blockTitle then
				HubService.blockTitle.Text = top and string.upper(top.name) or "ON THE BLOCK"
				HubService.blockSub.Text = top
					and (Format.money(top.bid) .. "  ·  " ..
						math.ceil(top.timeLeft) .. "s  ·  " ..
						(top.bidderName or "the house"))
					or "nothing listed"
			end

			task.wait(2)
		end
	end)
end

-- ── travel ──────────────────────────────────────────────────────────────────

--[[ Arrival points are offset AWAY from the pad that sent you, or you'd land on
     the return pad and bounce straight back. ]]
local HUB_ARRIVAL = HUB + Vector3.new(0, 5, -FLOOR_D / 2 + 12)
local STREET_ARRIVAL = PRIMARY.pos + Vector3.new(16, -2, 0)

local function move(player, target)
	local now = os.clock()
	if now - (recentTeleport[player.UserId] or 0) < 2 then
		return
	end
	recentTeleport[player.UserId] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		character:PivotTo(CFrame.new(target))
	end
end

function HubService.sendToHub(player)
	move(player, HUB_ARRIVAL)
end

function HubService.sendToStreet(player)
	move(player, STREET_ARRIVAL)
end

--[[
	No proximity helpers live here any more.

	Mines is playable from anywhere, so nothing gates on it. Upgrades moved out
	to the street shop, which owns its own check. The one gate left in this room
	belongs to the auction, and AuctionService does it against HubService.desk --
	the module that enforces a rule should be the one that states it.
]]

function HubService.start()
	HubService.build()
	HubService.buildGate()

	Players.PlayerRemoving:Connect(function(player)
		recentTeleport[player.UserId] = nil
	end)
end

return HubService
