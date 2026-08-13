--[[
	MinesLandmark
	Gives the gambling a place.

	Until now Mines existed only as a keypress -- press M, a panel appears. The
	world and the core loop were unrelated, and the map had no focal point. This
	builds a monument at the centre of the street: a tiered podium under two
	counter-rotating neon rings, visible from every base.

	The rings are faceted from straight segments rather than being a smooth
	torus. Roblox has no torus primitive, but more to the point a segmented ring
	is what the low-poly reference art actually looks like -- the facets are the
	style, not a compromise.

	The rings also tint to the running event, so the landmark reads as live
	state from across the map: you can see a Lava Surge is on without opening
	anything.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Events = require(Shared.Events)

local EventService = require(script.Parent.EventService)

local MinesLandmark = {}

-- Sited by raycast survey: dead centre of the street between the two rows of
-- bases, with clear sky above and nothing within 16 studs.
local SITE = Vector3.new(0, 0.3, -60)

local IDLE_OUTER = Color3.fromRGB(90, 226, 255)
local IDLE_INNER = Color3.fromRGB(255, 92, 214)
local STONE = Color3.fromRGB(74, 82, 112)
local STONE_LIT = Color3.fromRGB(104, 114, 146)

local rings = {}

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide ~= false
	p.CanQuery = false
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

--[[
	One ring, built from `segments` straight bars laid around a circle.

	Each bar is oriented with CFrame.lookAt pointed at the centre, which puts
	its X axis tangential -- so the bar's LENGTH runs along the circle rather
	than sticking out radially.
]]
local function buildRing(parent, radius, segments, thickness, height, color, name)
	local model = Instance.new("Model")
	model.Name = name

	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Size = Vector3.new(0.4, 0.4, 0.4)
	hub.CFrame = CFrame.new(SITE + Vector3.new(0, height, 0))
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.Parent = model
	model.PrimaryPart = hub

	local segLength = (2 * math.pi * radius / segments) * 1.06 -- slight overlap
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local pos = SITE
			+ Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		part({
			name = "Seg",
			size = Vector3.new(segLength, thickness, thickness),
			cframe = CFrame.lookAt(pos, Vector3.new(SITE.X, pos.Y, SITE.Z)),
			color = color,
			material = Enum.Material.Neon,
			collide = false,
		}, model)
	end

	model.Parent = parent
	CollectionService:AddTag(model, Config.RingTag)
	return model
end

function MinesLandmark.build()
	local existing = Workspace:FindFirstChild("MinesLandmark")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "MinesLandmark"
	root.Parent = Workspace

	-- ── tiered podium ───────────────────────────────────────────────────────
	local tiers = { { 23, 1.6 }, { 18, 1.5 }, { 13, 1.4 } }
	local y = SITE.Y
	for index, tier in ipairs(tiers) do
		local radius, thick = tier[1], tier[2]
		part({
			name = "Tier" .. index,
			size = Vector3.new(radius * 2, thick, radius * 2),
			cframe = CFrame.new(SITE + Vector3.new(0, y - SITE.Y + thick / 2, 0)),
			color = index == #tiers and STONE_LIT or STONE,
			material = Enum.Material.Slate,
		}, root).Shape = Enum.PartType.Cylinder
		y += thick
	end

	-- Cylinders point along X, so each needs rolling upright.
	for _, p in ipairs(root:GetChildren()) do
		if p:IsA("BasePart") and p.Name:match("^Tier") then
			p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	local deckY = y - SITE.Y

	-- glowing rim on the top tier, so the podium reads at night
	local rimSegments = 32
	for i = 1, rimSegments do
		local angle = (i / rimSegments) * math.pi * 2
		local pos = SITE + Vector3.new(math.cos(angle) * 12.6, deckY - 0.15, math.sin(angle) * 12.6)
		part({
			name = "Rim",
			size = Vector3.new((2 * math.pi * 12.6 / rimSegments) * 1.08, 0.3, 0.7),
			cframe = CFrame.lookAt(pos, Vector3.new(SITE.X, pos.Y, SITE.Z)),
			color = IDLE_OUTER,
			material = Enum.Material.Neon,
			collide = false,
		}, root)
	end

	-- ── central pillar and light shaft ──────────────────────────────────────
	part({
		name = "Pillar",
		size = Vector3.new(4.4, 26, 4.4),
		cframe = CFrame.new(SITE + Vector3.new(0, deckY + 13, 0)),
		color = STONE,
		material = Enum.Material.Slate,
	}, root)

	part({
		name = "Shaft",
		size = Vector3.new(1.5, 34, 1.5),
		cframe = CFrame.new(SITE + Vector3.new(0, deckY + 30, 0)),
		color = IDLE_OUTER,
		material = Enum.Material.Neon,
		transparency = 0.35,
		collide = false,
	}, root)

	local beacon = Instance.new("PointLight")
	beacon.Color = IDLE_OUTER
	beacon.Range = 60
	beacon.Brightness = 2.4
	beacon.Parent = root:FindFirstChild("Shaft")

	-- ── the rings ───────────────────────────────────────────────────────────
	rings = {
		outer = buildRing(root, 26, 28, 1.5, deckY + 30, IDLE_OUTER, "OuterRing"),
		inner = buildRing(root, 17, 20, 1.1, deckY + 42, IDLE_INNER, "InnerRing"),
	}
	rings.inner:SetAttribute("SpinDirection", -1) -- counter-rotates
	rings.outer:SetAttribute("SpinDirection", 1)
	rings.inner:SetAttribute("SpinSpeed", 0.42)
	rings.outer:SetAttribute("SpinSpeed", 0.26)

	-- ── sign and interaction ────────────────────────────────────────────────
	local anchor = part({
		name = "SignAnchor",
		size = Vector3.new(0.4, 0.4, 0.4),
		cframe = CFrame.new(SITE + Vector3.new(0, deckY + 28, 0)),
		color = STONE,
		transparency = 1,
		collide = false,
	}, root)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(260, 76)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	gui.MaxDistance = 320
	gui.Parent = anchor

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "MINES"
	title.Parent = gui
	local titleCap = Instance.new("UITextSizeConstraint")
	titleCap.MaxTextSize = 34
	titleCap.Parent = title

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0.42, 0)
	status.Position = UDim2.new(0, 0, 0.58, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextScaled = true
	status.TextColor3 = IDLE_OUTER
	status.TextStrokeTransparency = 0.45
	status.Text = "bet, reveal, bank"
	status.Parent = gui
	local statusCap = Instance.new("UITextSizeConstraint")
	statusCap.MaxTextSize = 17
	statusCap.Parent = status

	-- A pedestal you walk up to. M still works -- this is a destination, not a
	-- toll gate; forcing the walk every round would fight the core loop.
	local console = part({
		name = "Console",
		size = Vector3.new(6, 3.2, 3),
		cframe = CFrame.new(SITE + Vector3.new(0, deckY + 1.6, 8.5)),
		color = STONE_LIT,
		material = Enum.Material.Metal,
	}, root)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MinesPrompt"
	prompt.ActionText = "Play Mines"
	prompt.ObjectText = "The Mines"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	prompt.Triggered:Connect(function(player)
		Net.get("OpenMines"):FireClient(player)
	end)

	MinesLandmark.status = status
	return root
end

--[[
	Tint the whole monument to the live event, so the map itself advertises it.
	Polled rather than event-driven: EventService has no listener hook, and a
	two-second lag on a 90-second event is imperceptible.
]]
function MinesLandmark.startEventSync()
	task.spawn(function()
		local lastId = false
		while true do
			local snapshot = EventService.snapshot()
			if snapshot.activeId ~= lastId then
				lastId = snapshot.activeId
				local def = Events.get(snapshot.activeId)
				local outer = def and def.color or IDLE_OUTER
				local inner = def and def.color:Lerp(Color3.new(1, 1, 1), 0.45) or IDLE_INNER

				for _, seg in ipairs(rings.outer and rings.outer:GetDescendants() or {}) do
					if seg:IsA("BasePart") and seg.Name == "Seg" then
						seg.Color = outer
					end
				end
				for _, seg in ipairs(rings.inner and rings.inner:GetDescendants() or {}) do
					if seg:IsA("BasePart") and seg.Name == "Seg" then
						seg.Color = inner
					end
				end

				local root = Workspace:FindFirstChild("MinesLandmark")
				local shaft = root and root:FindFirstChild("Shaft")
				if shaft then
					shaft.Color = outer
					local light = shaft:FindFirstChildOfClass("PointLight")
					if light then
						light.Color = outer
					end
				end
				for _, rim in ipairs(root and root:GetChildren() or {}) do
					if rim:IsA("BasePart") and rim.Name == "Rim" then
						rim.Color = outer
					end
				end

				if MinesLandmark.status then
					MinesLandmark.status.Text = def and string.upper(def.name) or "bet, reveal, bank"
					MinesLandmark.status.TextColor3 = outer
				end
			end
			task.wait(2)
		end
	end)
end

return MinesLandmark
