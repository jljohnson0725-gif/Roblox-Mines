--[[
	ShopService
	The street shop -- items and upgrades over one counter.

	It lived in the hub for a while. The hub is gone now, and it was already
	clear before that a shared room made the shop a counter in the corner of
	it -- the thing the move indoors was supposed to fix.

	The shopfront is a market stall model, cloned from a template that
	build_place.py injects into ReplicatedStorage. The hand-built kiosk that
	stood here before it is gone -- not kept as a fallback, because two
	shopfronts meant two things to keep in step and the one nobody looked at
	would have been the one that drifted.

	WHAT THE REST OF THE GAME NEEDS FROM THIS: a part named Counter, as a DIRECT
	child of the UpgradeShop model. ClientMain closes the upgrade window when you
	walk away from it and looks it up with a non-recursive FindFirstChild, so a
	Counter buried inside the stall art would read as "no counter" -- which that
	check treats as "never close". So the Counter is built first and separately,
	before the art it stands in front of, and exists even when the art doesn't.

	Owns its own proximity check, because the module that enforces a rule should
	be the one that states it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local ShopService = {}

--[[ Placed by hand in Studio and read back out, rather than derived from
     portal distances the way the old kiosk's site was. The stall is scenery
     with a footprint and a facing, and where it looks right on the street is a
     judgement the map makes better than arithmetic does.

     This is the model's PIVOT, which for this template is its bounding-box
     centre -- so the y is mid-height, not ground level. It sits about an eighth
     of a stud into the ground on purpose; exactly flush shows a hairline of
     daylight wherever the union under it disagrees with the baseplate. ]]
local STALL_PIVOT = CFrame.new(-130.67, 9.93, -35.33)

local GOLD = Color3.fromRGB(255, 190, 60)

--[[ The stall, plus the Counter proxy the rest of the game addresses it by.

     Nothing in the art is shaped like a service counter, and naming one of the
     crates Counter would break the moment the model changed. So the proxy is an
     invisible part at the stall's mouth: it is what the sign hangs off, what the
     prompt lives on, and what both distance checks measure to. It gets built
     whether or not the art does, because without it there is no way to open the
     shop at all. ]]
local function buildShop(root)
	local counter = Instance.new("Part")
	counter.Name = "Counter"
	counter.Anchored = true
	counter.CanCollide = false
	counter.CanQuery = false
	counter.CanTouch = false
	counter.Transparency = 1
	counter.Size = Vector3.new(2, 2, 2)
	counter.Parent = root

	local template = ReplicatedStorage:FindFirstChild("UpgradeShopTemplate")
	if not template then
		--[[ No art, but still a shop. An invisible counter in the right place
		     beats a street where nobody can spend their money. ]]
		warn("[ShopService] no UpgradeShopTemplate -- run tools/build_place.py "
			.. "with assets/upgradeshop.rbxmx present")
		counter.CFrame = STALL_PIVOT
		return counter
	end

	local stall = template:Clone()
	stall.Name = "Stall"
	stall.Parent = root
	stall:PivotTo(STALL_PIVOT)

	--[[ The stall model is built facing -Z: its signboard and its keeper both
	     look that way. Read the facing off the pivot rather than assuming it, so
	     turning the stall in Studio moves the prompt around with it. ]]
	local _, size = stall:GetBoundingBox()
	local front = STALL_PIVOT.LookVector
	counter.CFrame = CFrame.new(STALL_PIVOT.Position
		+ front * (size.Z / 2 - 1.5)
		+ Vector3.new(0, 3 - size.Y / 2, 0))

	--[[ Sign clears the roof, worked out from the stall the build actually
	     placed rather than a number I measured once. ]]
	local roof = STALL_PIVOT.Position.Y + size.Y / 2
	counter:SetAttribute("SignLift", (roof + 2.2) - counter.Position.Y)
	return counter
end

--[[ The light, the billboard and the prompt that actually opens the shop. ]]
local function dress(counter)
	local lamp = Instance.new("PointLight")
	lamp.Color = GOLD
	lamp.Range = 34
	lamp.Brightness = 1.8
	lamp.Parent = counter

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(132, 35)
	gui.StudsOffsetWorldSpace = Vector3.new(0, counter:GetAttribute("SignLift") or 3.4, 0)
	gui.MaxDistance = 220
	gui.Adornee = counter
	-- On the COUNTER, not the model. A BillboardGui parented to a Model survives
	-- its Adornee being streamed out, and then renders at the world origin.
	gui.Parent = counter

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 240, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "SHOP"
	title.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 16
	cap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = GOLD
	sub.TextStrokeTransparency = 0.45
	sub.Text = "items & upgrades"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 8
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Shop"
	prompt.ObjectText = "Street Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		Net.get("OpenUpgrades"):FireClient(player)
	end)
end

function ShopService.build()
	local existing = Workspace:FindFirstChild("UpgradeShop")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "UpgradeShop"
	root.Parent = Workspace

	local counter = buildShop(root)
	dress(counter)

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
