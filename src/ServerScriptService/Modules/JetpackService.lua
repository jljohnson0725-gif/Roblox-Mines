--[[
	JetpackService
	Sells the jetpack, and decides who is allowed to be in the air.

	BOUGHT ONCE. The flag lives on the profile, so it survives rejoining and
	there is no second transaction ever. Charging per flight would price the
	sky by the trip and put a small purchase decision in front of every ascent,
	which is the surest way to keep people on the ground.

	The server does NOT fly anybody. Character physics are owned by the client
	that the character belongs to, so driving flight from here would mean
	fighting network ownership for the privilege of adding latency to it. What
	the server owns is the PERMISSION -- and the attribute, which is how every
	other client learns to draw the ascension pose on this player. See
	StarterPlayerScripts/UI/Flight.lua for the pose itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Format)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)

local JetpackService = {}

local ASCENDING = "Ascending"

--[[
	On the main walk between the wheel and the upgrade kiosk -- 73 studs from
	one, 58 from the other -- so it is somewhere you already pass rather than
	somewhere you have to be told about.

	MEASURED, NOT PICKED. The first attempt at (-210, -30) put it three studs
	from a map wall, which is the same mistake that once buried the auction
	portal inside an archway. This came out of a sweep of the whole street for
	ground at walk level with 18+ studs of clearance in all eight directions,
	clear sky overhead, and 55+ studs from every base and landmark. This site
	has 40 in every direction, which is the most the sweep measures.
]]
local SITE = Vector3.new(-70, 0.3, -50)

local SKY = Color3.fromRGB(96, 188, 255)
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

-- ── the pad ─────────────────────────────────────────────────────────────────

function JetpackService.build()
	local existing = Workspace:FindFirstChild("LaunchPad")
	if existing then
		existing:Destroy()
	end

	--[[ Drop the pad onto whatever the ground actually is here rather than
	     trusting y = 0.3, the same way the wheel sites itself. The old pad is
	     already destroyed above, so there is nothing to filter out. ]]
	local hit = Workspace:Raycast(Vector3.new(SITE.X, 200, SITE.Z), Vector3.new(0, -400, 0))
	if hit then
		SITE = Vector3.new(SITE.X, hit.Position.Y + 0.2, SITE.Z)
	end

	local root = Instance.new("Model")
	root.Name = "LaunchPad"
	root.Parent = Workspace

	local deck = part({
		name = "Deck",
		size = Vector3.new(16, 0.8, 16),
		offset = Vector3.new(0, 0.4, 0),
		color = STONE,
		material = Enum.Material.Slate,
	}, root)

	-- A ring rather than a full disc: it reads as a target to stand in the
	-- middle of, which is exactly what the pad is for.
	part({
		name = "Ring",
		size = Vector3.new(12, 0.24, 12),
		offset = Vector3.new(0, 0.9, 0),
		color = SKY,
		material = Enum.Material.SmoothPlastic,
		collide = false,
	}, root)
	part({
		name = "RingInner",
		size = Vector3.new(9, 0.3, 9),
		offset = Vector3.new(0, 0.92, 0),
		color = STONE,
		material = Enum.Material.Slate,
		collide = false,
	}, root)

	-- four corner markers, angled outward like landing lights
	for _, corner in ipairs({ Vector3.new(1, 0, 1), Vector3.new(1, 0, -1),
		Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) }) do
		part({
			name = "Light",
			size = Vector3.new(0.7, 3.4, 0.7),
			offset = Vector3.new(corner.X * 7, 2.2, corner.Z * 7),
			color = STONE_LIT,
			material = Enum.Material.Metal,
		}, root)
		part({
			name = "LightCap",
			size = Vector3.new(1, 0.5, 1),
			offset = Vector3.new(corner.X * 7, 4, corner.Z * 7),
			color = SKY,
			material = Enum.Material.SmoothPlastic,
			collide = false,
		}, root)
	end

	local console = part({
		name = "Console",
		size = Vector3.new(4.4, 3.4, 1.6),
		offset = Vector3.new(0, 2.5, 7.4),
		color = STONE_LIT,
		material = Enum.Material.Metal,
	}, root)

	local glow = Instance.new("PointLight")
	glow.Color = SKY
	glow.Range = 26
	glow.Brightness = 1.1
	glow.Parent = console

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(230, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 240
	gui.Adornee = console
	-- On the CONSOLE, not the model: a BillboardGui outliving its adornee under
	-- streaming renders at the world origin, in the middle of the street.
	gui.Parent = console

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "LAUNCH PAD"
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
	sub.TextColor3 = SKY
	sub.TextStrokeTransparency = 0.45
	sub.Text = Format.money(Config.JetpackCost) .. " — yours for good"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 14
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JetpackPrompt"
	prompt.ActionText = "Buy Jetpack"
	prompt.ObjectText = "Launch Pad"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	prompt.Triggered:Connect(function(player)
		JetpackService.buy(player)
	end)

	JetpackService.console = console
	JetpackService.deck = deck
	return root
end

function JetpackService.isNear(player)
	local console = JetpackService.console
	if not console then
		return true -- pad never built: don't lock anyone out of their money
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - console.Position).Magnitude <= Config.ShopRange
end

-- ── purchase ────────────────────────────────────────────────────────────────

function JetpackService.buy(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if profile.jetpack then
		--[[ Not an error. Someone pressing the prompt again almost always means
		     "how do I use this", so answer that instead of scolding them. ]]
		PlayerState.notify(player, "You already own it — press F to fly.", "info")
		return { ok = true, jetpack = true }
	end
	if not JetpackService.isNear(player) then
		return { ok = false, err = "Head to the launch pad." }
	end
	if profile.money < Config.JetpackCost then
		return {
			ok = false,
			err = "Need " .. Format.money(Config.JetpackCost) .. ".",
		}
	end

	profile.money -= Config.JetpackCost
	profile.jetpack = true

	PlayerState.push(player)
	PlayerState.notify(player, "Jetpack acquired. Press F to fly.", "good")
	return { ok = true, jetpack = true }
end

-- ── permission to be in the air ─────────────────────────────────────────────

--[[
	The client says it is flying; this decides whether that is allowed and, if
	so, tells everyone. The attribute is what every other client reads to draw
	the ascension pose, so this call is the only thing standing between "I own
	a jetpack" and "everyone can see me use it".
]]
function JetpackService.setFlying(player, wants)
	local character = player.Character
	if not character then
		return
	end

	local profile = DataService.get(player)
	local allowed = wants == true and profile ~= nil and profile.jetpack == true
	character:SetAttribute(ASCENDING, allowed)
end

function JetpackService.start()
	JetpackService.build()

	Net.get("BuyJetpack").OnServerInvoke = function(player)
		return JetpackService.buy(player)
	end

	Net.get("SetFlying").OnServerEvent:Connect(function(player, wants)
		JetpackService.setFlying(player, wants)
	end)

	--[[ A fresh character has no attribute and is therefore not flying, which
	     is correct -- but the flag has to be cleared on respawn anyway so a
	     player who dies mid-air doesn't land already posed. ]]
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			character:SetAttribute(ASCENDING, false)
		end)
	end

	-- Existing players too: in Studio the local player is usually in before
	-- Bootstrap finishes, and PlayerAdded alone would never see them.
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return JetpackService
