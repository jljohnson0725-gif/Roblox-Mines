--[[
	UpgradeService
	Owns the upgrade shop: the structure in the street, and the purchase logic.

	The shop is a SECOND landmark rather than a panel on your base, for the same
	reason Mines moved out of the keybind -- spending should happen in the public
	space. Two points of interest out in the street give the map somewhere to
	walk between, and mean other players see you doing things.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Upgrades = require(Shared.Upgrades)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)

local UpgradeService = {}

-- Far enough from the Mines to be its own place, close enough to read as one
-- plaza. Sits on ground the earlier clearance survey found open.
local SITE = Vector3.new(48, 0.3, -60)

local STONE = Color3.fromRGB(74, 82, 112)
local STONE_LIT = Color3.fromRGB(104, 114, 146)
local ACCENT = Color3.fromRGB(255, 190, 60)

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

function UpgradeService.shopPosition()
	local root = Workspace:FindFirstChild("UpgradeShop")
	local counter = root and root:FindFirstChild("Counter")
	return counter and counter.Position or nil
end

function UpgradeService.isNear(player)
	local spot = UpgradeService.shopPosition()
	if not spot then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - spot).Magnitude <= Config.ShopRange
end

function UpgradeService.build()
	local existing = Workspace:FindFirstChild("UpgradeShop")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "UpgradeShop"
	root.Parent = Workspace

	part({
		name = "Base",
		size = Vector3.new(26, 1.4, 26),
		cframe = CFrame.new(SITE + Vector3.new(0, 0.7, 0)),
		color = STONE,
		material = Enum.Material.Slate,
	}, root).Shape = Enum.PartType.Cylinder
	local base = root:FindFirstChild("Base")
	base.CFrame = base.CFrame * CFrame.Angles(0, 0, math.rad(90))

	-- glowing lip, same language as the Mines podium
	for i = 1, 24 do
		local angle = (i / 24) * math.pi * 2
		local pos = SITE + Vector3.new(math.cos(angle) * 12.7, 1.3, math.sin(angle) * 12.7)
		part({
			name = "Lip",
			size = Vector3.new((2 * math.pi * 12.7 / 24) * 1.08, 0.28, 0.6),
			cframe = CFrame.lookAt(pos, Vector3.new(SITE.X, pos.Y, SITE.Z)),
			color = ACCENT,
			material = Enum.Material.Neon,
			collide = false,
		}, root)
	end

	local counter = part({
		name = "Counter",
		size = Vector3.new(11, 3.4, 4),
		cframe = CFrame.new(SITE + Vector3.new(0, 3.1, 0)),
		color = STONE_LIT,
		material = Enum.Material.Metal,
	}, root)

	part({
		name = "Glow",
		size = Vector3.new(10.4, 0.3, 3.4),
		cframe = CFrame.new(SITE + Vector3.new(0, 4.85, 0)),
		color = ACCENT,
		material = Enum.Material.Neon,
		collide = false,
	}, root)

	local pylon = part({
		name = "Pylon",
		size = Vector3.new(1.6, 16, 1.6),
		cframe = CFrame.new(SITE + Vector3.new(0, 11, -4)),
		color = ACCENT,
		material = Enum.Material.Neon,
		transparency = 0.3,
		collide = false,
	}, root)

	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = 44
	light.Brightness = 2
	light.Parent = pylon

	local anchor = part({
		name = "SignAnchor",
		size = Vector3.new(0.4, 0.4, 0.4),
		cframe = CFrame.new(SITE + Vector3.new(0, 20, -4)),
		color = STONE,
		transparency = 1,
		collide = false,
	}, root)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(230, 66)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	gui.MaxDistance = 260
	gui.Parent = anchor

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "UPGRADES"
	title.Parent = gui
	local titleCap = Instance.new("UITextSizeConstraint")
	titleCap.MaxTextSize = 28
	titleCap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = ACCENT
	sub.TextStrokeTransparency = 0.45
	sub.Text = "spend it to make it"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 15
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

	return root
end

-- ── purchasing ──────────────────────────────────────────────────────────────

function UpgradeService.buy(player, id)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if not UpgradeService.isNear(player) then
		return { ok = false, err = "Head to the upgrade shop." }
	end

	local def = Upgrades.get(id)
	if not def then
		return { ok = false, err = "Unknown upgrade." }
	end

	profile.upgrades = profile.upgrades or {}
	local level = profile.upgrades[id] or 0
	if level >= def.maxLevel then
		return { ok = false, err = def.name .. " is maxed." }
	end

	local cost = Upgrades.cost(id, level)
	if profile.money < cost then
		return { ok = false, err = "Need " .. Format.money(cost) .. "." }
	end

	profile.money -= cost
	profile.upgrades[id] = level + 1

	UpgradeService.applyToCharacter(player)
	PlayerState.push(player)
	PlayerState.notify(player, def.name .. " -> level " .. (level + 1), "good")

	return { ok = true, id = id, level = level + 1 }
end

--[[ Walk speed is the one upgrade that lives on the character, so it has to be
     re-applied every time one spawns as well as at purchase. ]]
function UpgradeService.applyToCharacter(player)
	local profile = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if profile and humanoid then
		humanoid.WalkSpeed = Upgrades.walkSpeed(profile)
	end
end

function UpgradeService.start()
	UpgradeService.build()

	Net.get("BuyUpgrade").OnServerInvoke = function(player, id)
		return UpgradeService.buy(player, id)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				UpgradeService.applyToCharacter(player)
			end)
		end)
	end)
end

return UpgradeService
