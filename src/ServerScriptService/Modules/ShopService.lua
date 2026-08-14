--[[
	ShopService
	The upgrade shop, back out in the street where it started.

	It lived in the hub for a while. That room is an auction house now, and
	sharing it would have made the auction floor a lobby with a shop counter in
	it -- the thing the move indoors was supposed to fix.

	Deliberately a KIOSK, not a monument. The two structures this replaces were
	bulky enough that the street felt crowded with only two of them on it; this
	one is a counter, a canopy and a sign, and it sits off the centre line so it
	never blocks the walk between the portals.

	Owns its own proximity check, because the module that enforces a rule should
	be the one that states it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local ShopService = {}

--[[ Open ground: 237 studs from the west portal, 351 from the east, and clear
     of the centre walk at z = -66. Verified against the map before building. ]]
local SITE = Vector3.new(-100, 0.3, -100)

local GOLD = Color3.fromRGB(255, 190, 60)
local STONE = Color3.fromRGB(64, 70, 96)
local STONE_LIT = Color3.fromRGB(96, 106, 138)

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.size
	p.CFrame = CFrame.new(SITE + props.offset)
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Transparency = props.transparency or 0
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

function ShopService.build()
	local existing = Workspace:FindFirstChild("UpgradeShop")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "UpgradeShop"
	root.Parent = Workspace

	part({
		name = "Deck",
		size = Vector3.new(22, 0.6, 12),
		offset = Vector3.new(0, 0.3, 0),
		color = STONE,
		material = Enum.Material.Slate,
	}, root)

	local counter = part({
		name = "Counter",
		size = Vector3.new(14, 3.2, 3),
		offset = Vector3.new(0, 2.2, -2),
		color = STONE_LIT,
		material = Enum.Material.Metal,
	}, root)

	part({
		name = "CounterGlow",
		size = Vector3.new(13.4, 0.28, 2.6),
		offset = Vector3.new(0, 3.9, -2),
		color = GOLD,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	-- two posts and a canopy: enough to read as a shopfront from across the
	-- street without becoming another landmark
	for _, side in ipairs({ -1, 1 }) do
		part({
			name = "Post",
			size = Vector3.new(0.8, 9, 0.8),
			offset = Vector3.new(side * 9.5, 5, 0),
			color = STONE_LIT,
			material = Enum.Material.Metal,
		}, root)
	end
	part({
		name = "Canopy",
		size = Vector3.new(21, 0.6, 12),
		offset = Vector3.new(0, 9.6, 0),
		color = STONE,
		material = Enum.Material.Metal,
	}, root)
	part({
		name = "CanopyTrim",
		size = Vector3.new(21.6, 0.3, 12.6),
		offset = Vector3.new(0, 9.1, 0),
		color = GOLD,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	local lamp = Instance.new("PointLight")
	lamp.Color = GOLD
	lamp.Range = 34
	lamp.Brightness = 1.8
	lamp.Parent = counter

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(220, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 220
	gui.Adornee = counter
	gui.Parent = root

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "UPGRADES"
	title.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 26
	cap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = GOLD
	sub.TextStrokeTransparency = 0.45
	sub.Text = "spend it to make it"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 14
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Upgrades"
	prompt.ObjectText = "Upgrade Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		Net.get("OpenUpgrades"):FireClient(player)
	end)

	ShopService.counter = counter
	return root
end

function ShopService.isNear(player)
	local counter = ShopService.counter
	if not counter then
		return true -- shop never built: don't lock anyone out of their money
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - counter.Position).Magnitude <= Config.ShopRange
end

function ShopService.start()
	ShopService.build()
end

return ShopService
