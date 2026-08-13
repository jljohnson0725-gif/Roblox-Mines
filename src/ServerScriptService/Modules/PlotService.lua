--[[
	PlotService
	Owns the physical world: assigns plots, and keeps each pad's visual state in
	sync with the owner's inventory.

	TWO MODES, chosen at startup:

	  attach   -- Workspace/Bases/BaseN exists (the imported map). Each base is
	              already a finished art asset with 8 slot pedestals, a Spawn,
	              an Owner marker and a CollectZone. We bind to that geometry and
	              build nothing.
	  generate -- no Bases folder. Falls back to building ground, plots and
	              tiered shelves in code, so the game still runs on a blank
	              baseplate with zero setup.

	Both modes produce the same `plot` shape, so everything below the mode split
	-- rendering, placement, unlocking -- is written once.

	Pad ORDER matters and must never change: pad indices are persisted in save
	data, so a brainrot on pad 3 has to come back on pad 3. The map names all
	eight slots "Slot1", so we sort by position instead of by name.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Rarity = require(Shared.Rarity)
local Brainrots = require(Shared.Brainrots)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local ModelFactory = require(script.Parent.ModelFactory)

local PlotService = {}

local GENERATED_PLOT_COUNT = 12

local plots = {}
local byUserId = {}
local mode = "generate"

local EMPTY_PAD = Color3.fromRGB(72, 76, 88)
local LOCKED_PAD = Color3.fromRGB(38, 40, 48)

-- ════════════════════════════════════════════════════════════════════════════
-- ATTACH MODE
-- ════════════════════════════════════════════════════════════════════════════

local function findBases()
	local folder = Workspace:FindFirstChild("Bases")
	if not folder then
		return nil
	end

	local found = {}
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:FindFirstChild("Slots") then
			table.insert(found, model)
		end
	end
	if #found == 0 then
		return nil
	end

	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

--[[
	The pedestal inside one slot model. The map gives each slot a wide flat
	`Part` (the visible platform), a `Collect` trigger of the same footprint,
	and a small `Spawn` marker set off to one side -- that offset is the only
	thing telling us which way the slot faces, so we keep it.
]]
local function readSlot(slot)
	local pedestal = slot:FindFirstChild("Part")
	if not pedestal or not pedestal:IsA("BasePart") then
		pedestal = slot:FindFirstChildWhichIsA("BasePart")
	end
	if not pedestal then
		return nil
	end

	local marker = slot:FindFirstChild("Spawn")
	local facing
	if marker and marker:IsA("BasePart") then
		local delta = marker.Position - pedestal.Position
		facing = Vector3.new(delta.X, 0, delta.Z)
		if facing.Magnitude < 0.1 then
			facing = nil
		else
			facing = facing.Unit
		end
	end

	return pedestal, facing or Vector3.new(0, 0, 1)
end

local function attachPlot(base, index)
	local slotsFolder = base:FindFirstChild("Slots")
	local pads = {}

	local entries = {}
	for _, slot in ipairs(slotsFolder:GetChildren()) do
		local pedestal, facing = readSlot(slot)
		if pedestal then
			table.insert(entries, { pedestal = pedestal, facing = facing })
		end
	end

	-- Deterministic, position-based ordering. Every slot in the map is named
	-- "Slot1", so name order is useless and GetChildren() order is not
	-- guaranteed stable across sessions -- but pad indices are saved.
	table.sort(entries, function(a, b)
		local pa, pb = a.pedestal.Position, b.pedestal.Position
		if math.abs(pa.X - pb.X) > 0.5 then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)

	local container = Instance.new("Folder")
	container.Name = "PlacedBrainrots"
	container.Parent = base

	for i, entry in ipairs(entries) do
		local pedestal = entry.pedestal

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PadPrompt"
		prompt.ActionText = ""
		prompt.ObjectText = "Pad " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal

		pads[i] = {
			part = pedestal,
			prompt = prompt,
			model = nil,
			facing = entry.facing,
			-- so an empty pad can be restored to the map's own look
			baseColor = pedestal.Color,
			baseMaterial = pedestal.Material,
		}
	end

	-- owner nameplate, hung on the map's own Owner marker
	local ownerPart = base:FindFirstChild("Owner")
	local ownerLabel, rateLabel
	if ownerPart and ownerPart:IsA("BasePart") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "OwnerLabel"
		gui.Size = UDim2.fromOffset(300, 74)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		gui.MaxDistance = 250
		gui.AlwaysOnTop = false
		gui.Parent = ownerPart

		ownerLabel = Instance.new("TextLabel")
		ownerLabel.Size = UDim2.new(1, 0, 0.6, 0)
		ownerLabel.BackgroundTransparency = 1
		ownerLabel.Font = Enum.Font.GothamBold
		ownerLabel.TextScaled = true
		ownerLabel.TextColor3 = Color3.fromRGB(240, 242, 250)
		ownerLabel.TextStrokeTransparency = 0.4
		ownerLabel.Text = "Empty Base"
		ownerLabel.Parent = gui

		rateLabel = Instance.new("TextLabel")
		rateLabel.Size = UDim2.new(1, 0, 0.4, 0)
		rateLabel.Position = UDim2.new(0, 0, 0.6, 0)
		rateLabel.BackgroundTransparency = 1
		rateLabel.Font = Enum.Font.GothamMedium
		rateLabel.TextScaled = true
		rateLabel.TextColor3 = Color3.fromRGB(120, 235, 150)
		rateLabel.TextStrokeTransparency = 0.5
		rateLabel.Text = ""
		rateLabel.Parent = gui
	end

	local spawnPart = base:FindFirstChild("Spawn")
	local spawnCFrame
	if spawnPart and spawnPart:IsA("BasePart") then
		spawnCFrame = spawnPart.CFrame + Vector3.new(0, 4, 0)
	end

	return {
		index = index,
		model = base,
		pads = pads,
		modelFolder = container,
		ownerLabel = ownerLabel,
		rateLabel = rateLabel,
		spawnCFrame = spawnCFrame,
		userId = nil,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- GENERATE MODE  (fallback: no map present)
-- ════════════════════════════════════════════════════════════════════════════

local SHELF_COUNT = math.ceil(Config.MaxSlots / Config.PadColumns)
local SHELF_WIDTH = (Config.PadColumns - 1) * Config.PadSpacing + Config.PadSize.X + 4

local function shelfHeight(shelf)
	return Config.ShelfLift + shelf * Config.ShelfRise
end

local function shelfZ(shelf)
	return Config.ShelfFrontZ - shelf * Config.ShelfDepth
end

local function padOffset(index)
	local col = (index - 1) % Config.PadColumns
	local shelf = math.floor((index - 1) / Config.PadColumns)
	local x = (col - (Config.PadColumns - 1) / 2) * Config.PadSpacing
	return Vector3.new(x, shelfHeight(shelf), shelfZ(shelf))
end

local function buildGround()
	local stock = Workspace:FindFirstChild("Baseplate")
	if stock and stock:IsA("BasePart") then
		stock:Destroy()
	end

	local span = (GENERATED_PLOT_COUNT - 1) * Config.PlotSpacing

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(span + Config.PlotSize.X + 160, 4, Config.PlotSize.Z + 160)
	ground.Position = Vector3.new(span / 2, -2, 0)
	ground.Anchored = true
	ground.Color = Color3.fromRGB(32, 34, 42)
	ground.Material = Enum.Material.Slate
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace

	if not Workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Name = "Spawn"
		spawnPad.Size = Vector3.new(12, 1, 12)
		spawnPad.Position = Vector3.new(0, 0.5, Config.PlotSize.Z / 2 + 14)
		spawnPad.Anchored = true
		spawnPad.Neutral = true
		spawnPad.Duration = 0
		spawnPad.Color = Color3.fromRGB(120, 132, 255)
		spawnPad.Material = Enum.Material.Neon
		spawnPad.Parent = Workspace
	end
end

local function buildPlot(index, parent)
	local origin = Vector3.new((index - 1) * Config.PlotSpacing, 0, 0)
	local surfaceY = Config.PlotSize.Y

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder.Parent = parent

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Config.PlotSize
	base.Position = origin + Vector3.new(0, Config.PlotSize.Y / 2, 0)
	base.Anchored = true
	base.Color = Color3.fromRGB(46, 48, 58)
	base.Material = Enum.Material.Concrete
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = folder

	local signPost = Instance.new("Part")
	signPost.Name = "Sign"
	signPost.Size = Vector3.new(0.6, 6, 0.6)
	signPost.Position = origin + Vector3.new(0, surfaceY + 3, Config.PlotSize.Z / 2 - 2)
	signPost.Anchored = true
	signPost.Color = Color3.fromRGB(30, 32, 40)
	signPost.Material = Enum.Material.Metal
	signPost.Parent = folder

	local signGui = Instance.new("BillboardGui")
	signGui.Name = "OwnerLabel"
	signGui.Size = UDim2.fromOffset(280, 70)
	signGui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	signGui.MaxDistance = 220
	signGui.Parent = signPost

	local owner = Instance.new("TextLabel")
	owner.Size = UDim2.new(1, 0, 0.6, 0)
	owner.BackgroundTransparency = 1
	owner.Font = Enum.Font.GothamBold
	owner.TextScaled = true
	owner.TextColor3 = Color3.fromRGB(240, 242, 250)
	owner.TextStrokeTransparency = 0.4
	owner.Text = "Empty Plot"
	owner.Parent = signGui

	local rate = Instance.new("TextLabel")
	rate.Size = UDim2.new(1, 0, 0.4, 0)
	rate.Position = UDim2.new(0, 0, 0.6, 0)
	rate.BackgroundTransparency = 1
	rate.Font = Enum.Font.GothamMedium
	rate.TextScaled = true
	rate.TextColor3 = Color3.fromRGB(120, 235, 150)
	rate.TextStrokeTransparency = 0.5
	rate.Text = ""
	rate.Parent = signGui

	local shelfFolder = Instance.new("Folder")
	shelfFolder.Name = "Shelves"
	shelfFolder.Parent = folder

	for shelf = 0, SHELF_COUNT - 1 do
		local height = shelfHeight(shelf)

		local riser = Instance.new("Part")
		riser.Name = "Shelf" .. (shelf + 1)
		riser.Size = Vector3.new(SHELF_WIDTH, height, Config.ShelfDepth)
		riser.Position = origin + Vector3.new(0, surfaceY + height / 2, shelfZ(shelf))
		riser.Anchored = true
		riser.Color = Color3.fromRGB(54, 57, 70)
		riser.Material = Enum.Material.Concrete
		riser.TopSurface = Enum.SurfaceType.Smooth
		riser.Parent = shelfFolder

		local lip = Instance.new("Part")
		lip.Name = "Lip"
		lip.Size = Vector3.new(SHELF_WIDTH, 0.25, 0.5)
		lip.Position = origin
			+ Vector3.new(0, surfaceY + height - 0.12, shelfZ(shelf) + Config.ShelfDepth / 2 - 0.25)
		lip.Anchored = true
		lip.CanCollide = false
		lip.Color = Color3.fromRGB(120, 132, 255)
		lip.Material = Enum.Material.Neon
		lip.Parent = shelfFolder
	end

	local padFolder = Instance.new("Folder")
	padFolder.Name = "Pads"
	padFolder.Parent = folder

	local modelFolder = Instance.new("Folder")
	modelFolder.Name = "Models"
	modelFolder.Parent = folder

	local pads = {}
	for i = 1, Config.MaxSlots do
		local pad = Instance.new("Part")
		pad.Name = "Pad" .. i
		pad.Size = Config.PadSize
		pad.Position = origin + padOffset(i) + Vector3.new(0, surfaceY + Config.PadSize.Y / 2, 0)
		pad.Anchored = true
		pad.Color = LOCKED_PAD
		pad.Material = Enum.Material.SmoothPlastic
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = padFolder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PadPrompt"
		prompt.ActionText = ""
		prompt.ObjectText = "Pad " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad

		pads[i] = {
			part = pad,
			prompt = prompt,
			model = nil,
			facing = Vector3.new(0, 0, 1),
			baseColor = EMPTY_PAD,
			baseMaterial = Enum.Material.SmoothPlastic,
		}
	end

	return {
		index = index,
		folder = folder,
		pads = pads,
		modelFolder = modelFolder,
		ownerLabel = owner,
		rateLabel = rate,
		spawnCFrame = CFrame.new(origin + Vector3.new(0, surfaceY + 5, Config.PlotSize.Z / 2 - 6)),
		userId = nil,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- SHARED: pad rendering
-- ════════════════════════════════════════════════════════════════════════════

local function slotsAvailable(plot)
	return #plot.pads
end

local function padStateKey(profile, padIndex, plot)
	local unlocked = math.min(profile.slots, slotsAvailable(plot))
	if padIndex > unlocked then
		return padIndex == unlocked + 1 and "locked-next" or "locked"
	end
	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return "empty"
	end
	return table.concat({ "on", item.uid, item.charId, item.variantId }, "|")
end

local function renderPad(plot, padIndex, profile)
	local pad = plot.pads[padIndex]
	if not pad then
		return
	end

	local key = padStateKey(profile, padIndex, plot)
	if pad.part:GetAttribute("StateKey") == key then
		return
	end
	pad.part:SetAttribute("StateKey", key)

	if pad.model then
		pad.model:Destroy()
		pad.model = nil
	end

	if key == "locked" or key == "locked-next" then
		pad.part.Color = LOCKED_PAD
		pad.part.Material = Enum.Material.SmoothPlastic

		local cost = key == "locked-next" and Economy.slotCost(padIndex - 1) or nil
		if cost then
			pad.prompt.Enabled = true
			pad.prompt.ActionText = "Unlock  " .. Format.money(cost)
			pad.prompt.ObjectText = "Locked Pad"
		else
			pad.prompt.Enabled = false
		end
		return
	end

	if key == "empty" then
		-- restore whatever the pad looked like before we touched it
		pad.part.Color = pad.baseColor
		pad.part.Material = pad.baseMaterial
		pad.prompt.Enabled = true
		pad.prompt.ActionText = "Place Brainrot"
		pad.prompt.ObjectText = "Empty Pad"
		return
	end

	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return
	end

	local char = Brainrots.get(item.charId)
	local tier = Rarity.get(char.tier)
	pad.part.Color = tier.color
	pad.part.Material = Enum.Material.Neon

	local model = ModelFactory.build(item.charId, item.variantId)
	if model then
		model.Name = item.uid
		local top = pad.part.Position + Vector3.new(0, pad.part.Size.Y / 2, 0)
		-- Placeholder figures are built facing +Z, and CFrame.lookAt aims -Z at
		-- the target, so the extra half turn makes them look outward.
		local aim = CFrame.lookAt(top, top + pad.facing) * CFrame.Angles(0, math.pi, 0)
		ModelFactory.place(model, aim)
		model.Parent = plot.modelFolder
		pad.model = model
	end

	pad.prompt.Enabled = true
	pad.prompt.ActionText = "Store"
	pad.prompt.ObjectText = Economy.displayName(item.charId, item.variantId)
end

function PlotService.refresh(player)
	local plot = byUserId[player.UserId]
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end

	for i = 1, #plot.pads do
		renderPad(plot, i, profile)
	end

	if plot.ownerLabel then
		plot.ownerLabel.Text = player.DisplayName .. "'s Base"
	end
	if plot.rateLabel then
		plot.rateLabel.Text = Format.rate(Economy.totalIncome(profile.inventory))
	end
end

--[[ How many pads this world actually offers. Attach mode is capped by the
     map's geometry, which is the real limit regardless of Config. ]]
function PlotService.padCapacity(player)
	local plot = byUserId[player.UserId]
	return plot and #plot.pads or Config.MaxSlots
end

-- ════════════════════════════════════════════════════════════════════════════
-- ACTIONS
-- ════════════════════════════════════════════════════════════════════════════

function PlotService.placeBrainrot(player, uid, padIndex)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if type(padIndex) ~= "number" or padIndex ~= padIndex then
		return { ok = false, err = "Invalid pad." }
	end
	padIndex = math.floor(padIndex)

	local capacity = PlotService.padCapacity(player)
	local unlocked = math.min(profile.slots, capacity)

	if padIndex ~= 0 and (padIndex < 1 or padIndex > unlocked) then
		return { ok = false, err = "That pad isn't unlocked." }
	end

	local item = DataService.findItem(profile, uid)
	if not item then
		return { ok = false, err = "You don't own that." }
	end

	if padIndex == 0 then
		item.pad = nil
		PlotService.refresh(player)
		PlayerState.push(player)
		return { ok = true, stored = true }
	end

	local occupant = DataService.itemOnPad(profile, padIndex)
	if occupant and occupant.uid ~= item.uid then
		occupant.pad = item.pad
	end
	item.pad = padIndex

	PlotService.refresh(player)
	PlayerState.push(player)
	return { ok = true }
end

function PlotService.storeBrainrot(player, padIndex)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local item = DataService.itemOnPad(profile, padIndex)
	if not item then
		return
	end
	item.pad = nil
	PlotService.refresh(player)
	PlayerState.push(player)
end

function PlotService.equipBest(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if #profile.inventory == 0 then
		return { ok = false, err = "You don't own any brainrots yet." }
	end

	local ranked = table.clone(profile.inventory)
	table.sort(ranked, function(a, b)
		return Economy.powerScore(a.charId, a.variantId) > Economy.powerScore(b.charId, b.variantId)
	end)

	local before = Economy.totalIncome(profile.inventory)
	for _, item in ipairs(profile.inventory) do
		item.pad = nil
	end

	local unlocked = math.min(profile.slots, PlotService.padCapacity(player))
	local placed = 0
	for i = 1, math.min(unlocked, #ranked) do
		ranked[i].pad = i
		placed += 1
	end

	local after = Economy.totalIncome(profile.inventory)
	PlotService.refresh(player)
	PlayerState.push(player)

	return { ok = true, placed = placed, income = after, gained = after - before }
end

function PlotService.buySlot(player)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end

	local capacity = PlotService.padCapacity(player)
	if profile.slots >= math.min(Config.MaxSlots, capacity) then
		return { ok = false, err = "All pads unlocked." }
	end

	local cost = Economy.slotCost(profile.slots)
	if not cost then
		return { ok = false, err = "All pads unlocked." }
	end
	if profile.money < cost then
		return { ok = false, err = "Need " .. Format.money(cost) .. " for the next pad." }
	end

	profile.money -= cost
	profile.slots += 1

	PlotService.refresh(player)
	PlayerState.push(player)
	PlayerState.notify(player, "Unlocked pad " .. profile.slots .. "!", "good")
	return { ok = true, slots = profile.slots }
end

-- ════════════════════════════════════════════════════════════════════════════
-- ASSIGNMENT
-- ════════════════════════════════════════════════════════════════════════════

local function assignPlot(player)
	for _, plot in ipairs(plots) do
		if plot.userId == nil then
			plot.userId = player.UserId
			byUserId[player.UserId] = plot
			return plot
		end
	end
	warn("[PlotService] no free plot for " .. player.Name)
	return nil
end

local function releasePlot(player)
	local plot = byUserId[player.UserId]
	if not plot then
		return
	end
	byUserId[player.UserId] = nil
	plot.userId = nil

	for _, pad in ipairs(plot.pads) do
		if pad.model then
			pad.model:Destroy()
			pad.model = nil
		end
		pad.part:SetAttribute("StateKey", nil)
		pad.part.Color = pad.baseColor
		pad.part.Material = pad.baseMaterial
		pad.prompt.Enabled = false
	end

	if plot.ownerLabel then
		plot.ownerLabel.Text = mode == "attach" and "Empty Base" or "Empty Plot"
	end
	if plot.rateLabel then
		plot.rateLabel.Text = ""
	end
end

function PlotService.spawnAt(player, character)
	local plot = byUserId[player.UserId]
	if not plot or not plot.spawnCFrame then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5)
	if root then
		root.CFrame = plot.spawnCFrame
	end
end

PlotService.assign = assignPlot
PlotService.release = releasePlot

function PlotService.mode()
	return mode
end

-- ════════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════════════════

function PlotService.start()
	local bases = findBases()

	if bases then
		mode = "attach"
		for i, base in ipairs(bases) do
			plots[i] = attachPlot(base, i)
		end
		print(string.format(
			"[PlotService] attach mode: %d bases, %d pads each",
			#plots,
			#plots[1].pads
		))
	else
		mode = "generate"
		buildGround()

		local container = Instance.new("Folder")
		container.Name = "Plots"
		container.Parent = Workspace

		for i = 1, GENERATED_PLOT_COUNT do
			plots[i] = buildPlot(i, container)
		end
		print("[PlotService] generate mode: built " .. GENERATED_PLOT_COUNT .. " plots")
	end

	for _, plot in ipairs(plots) do
		for padIndex, pad in ipairs(plot.pads) do
			pad.prompt.Enabled = false
			pad.prompt.Triggered:Connect(function(player)
				if plot.userId ~= player.UserId then
					PlayerState.notify(player, "That's not your base.", "bad")
					return
				end
				local profile = DataService.get(player)
				if not profile then
					return
				end

				local unlocked = math.min(profile.slots, #plot.pads)
				if padIndex > unlocked then
					PlotService.buySlot(player)
				elseif DataService.itemOnPad(profile, padIndex) then
					PlotService.storeBrainrot(player, padIndex)
				else
					Net.get("OpenPicker"):FireClient(player, padIndex)
				end
			end)
		end
	end

	Net.get("PlaceBrainrot").OnServerInvoke = function(player, uid, padIndex)
		return PlotService.placeBrainrot(player, uid, padIndex)
	end

	Net.get("BuySlot").OnServerInvoke = function(player)
		return PlotService.buySlot(player)
	end

	Net.get("EquipBest").OnServerInvoke = function(player)
		return PlotService.equipBest(player)
	end

	Players.PlayerRemoving:Connect(releasePlot)
end

return PlotService
