--[[
	ClientMain
	Owns client state, wires the three UI modules together, and animates the
	brainrots standing on pads.

	State is MERGE-updated from the server's Sync payloads: a payload carrying
	only `money` leaves inventory alone. That's what lets the per-second income
	tick be cheap.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Sounds = require(Shared.Sounds)

local UI = script.Parent:WaitForChild("UI")
local HUD = require(UI.HUD)
local Fx = require(UI.Fx)
local MinesUI = require(UI.MinesUI)
local InventoryUI = require(UI.InventoryUI)
local UpgradeUI = require(UI.UpgradeUI)
local IndexUI = require(UI.IndexUI)
local WheelUI = require(UI.WheelUI)
local CodesUI = require(UI.CodesUI)
local Coach = require(UI.Coach)
local Flight = require(UI.Flight)
local Tutorial = require(UI.Tutorial)
local RebirthUI = require(UI.RebirthUI)
local Sky = require(UI.Sky)
local Audio = require(UI.Audio)
local SealTracker = require(UI.SealTracker)
local SummonUI = require(UI.SummonUI)
local RaceUI = require(UI.RaceUI)

-- ── gui root ────────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotMines"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ── state ───────────────────────────────────────────────────────────────────

local state = {
	money = 0,
	slots = Config.StartingSlots,
	inventory = {},
	index = {}, -- ["charId:variantId"] = times secured; drives the Index panel
	onboarding = { drops = 0, done = false }, -- first-session coach progress
	pending = 0,
	income = 0,
	stats = {},
	upgrades = {},
	jetpack = false, -- owned once, then forever; gates the F key
	event = nil, -- global event clock, filled by RequestState / EventState
	-- Named as the profile names them, so Shared/Seals reads either one.
	fragments = {}, -- [sealId] = how many toward that island's seal
	seals = {}, -- [sealId] = true once forged; the key to the next chapter
}

local listeners = {}

local function fireState()
	for _, listener in ipairs(listeners) do
		local ok, err = pcall(listener)
		if not ok then
			warn("[ClientMain] state listener error: " .. tostring(err))
		end
	end
end

local ctx = {
	gui = gui,
	state = state,
	remotes = {
		StartRound = Net.get("StartRound"),
		RevealTile = Net.get("RevealTile"),
		CashOut = Net.get("CashOut"),
		PlaceBrainrot = Net.get("PlaceBrainrot"),
		BuySlot = Net.get("BuySlot"),
		EquipBest = Net.get("EquipBest"),
		BuyUpgrade = Net.get("BuyUpgrade"),
		SpinWheel = Net.get("SpinWheel"),
		WheelStake = Net.get("WheelStake"),
		RedeemCode = Net.get("RedeemCode"),
		BuyJetpack = Net.get("BuyJetpack"),
		DoRebirth = Net.get("DoRebirth"),
		SetFlying = Net.get("SetFlying"),
		SummonMount = Net.get("SummonMount"),
		EnterRace = Net.get("EnterRace"),
		RaceOdds = Net.get("RaceOdds"),
		RequestState = Net.get("RequestState"),
	},
	onState = function(fn)
		table.insert(listeners, fn)
	end,
	notify = function() end, -- replaced by HUD below
	flashDrop = function() end,
	fx = nil, -- replaced by Fx below
}

-- ── ui ──────────────────────────────────────────────────────────────────────
-- Order matters: HUD supplies notify (which Fx needs), Fx supplies ctx.fx
-- (which MinesUI needs), so both must exist before the panels are built.

local hud = HUD.init(ctx)
ctx.notify = hud.notify
ctx.flashDrop = hud.flashDrop

ctx.fx = Fx.init(ctx)

local minesUI = MinesUI.init(ctx)
local inventoryUI = InventoryUI.init(ctx)
local upgradeUI = UpgradeUI.init(ctx)
local indexUI = IndexUI.init(ctx)
local wheelUI = WheelUI.init(ctx)
local codesUI = CodesUI.init(ctx)
local rebirthUI = RebirthUI.init(ctx)
local summonUI = SummonUI.init(ctx)
local raceUI = RaceUI.init(ctx)
Coach.init(ctx)
-- Gates the first two steps; Coach carries the rest as a suggestion.
Tutorial.init(ctx)
-- Not a panel: it poses characters and drives flight, so it never enters the
-- chrome-hiding set below.
Flight.init(ctx)
-- Lights this client from its own altitude: bright street, sunset islands.
Sky.init(ctx)
-- Buses first, so anything that makes a noise after this can be routed.
Audio.init(ctx)
-- Fragment progress, under the event card. Hides itself until you hold one.
SealTracker.init(ctx)

--[[
	The bottom-centre money counter steps aside while any full panel is open.

	WATCHED, NOT PUSHED. This started as a syncChrome() call at every place a
	panel opened or closed, and it was wrong within a day: each panel also has
	its own close button, which calls its own setVisible directly and never
	reaches this file. Eight such paths existed. Closing Mines with the X left
	the money counter hidden until something else happened to open and close a
	panel -- which is exactly the "disappears randomly, comes back later"
	behaviour that got reported.

	Polling four booleans is far cheaper than the bug, and no future panel can
	forget to opt in.
]]
local function chromeHidden()
	return minesUI.isVisible() or inventoryUI.isVisible() or upgradeUI.isVisible()
		or indexUI.isVisible() or wheelUI.isVisible()
		or codesUI.isVisible() or rebirthUI.isVisible() or summonUI.isVisible()
		or raceUI.isVisible()
end

task.spawn(function()
	local last = nil
	while true do
		local hidden = chromeHidden()
		if hidden ~= last then
			last = hidden
			hud.setMoneyVisible(not hidden)
		end
		task.wait(0.1)
	end
end)

-- kept so opening a panel hides the counter on the same frame rather than up to
-- a tenth of a second later; the watcher above is what guarantees correctness
local function syncChrome()
	hud.setMoneyVisible(not chromeHidden())
end


local function showMines(visible)
	if visible then
		inventoryUI.setVisible(false)
		upgradeUI.setVisible(false)
		indexUI.setVisible(false)
		wheelUI.setVisible(false)
	end
	if visible ~= minesUI.isVisible() then
		Sounds.play(visible and "uiOpen" or "uiClose")
	end
	minesUI.setVisible(visible)
	syncChrome()
end

local function showInventory(visible)
	if visible then
		minesUI.setVisible(false)
		upgradeUI.setVisible(false)
		indexUI.setVisible(false)
		wheelUI.setVisible(false)
	end
	if visible ~= inventoryUI.isVisible() then
		Sounds.play(visible and "uiOpen" or "uiClose")
	end
	inventoryUI.setVisible(visible)
	syncChrome()
end

hud.onMines = function()
	showMines(not minesUI.isVisible())
end

hud.onCollection = function()
	showInventory(not inventoryUI.isVisible())
end

hud.onRebirth = function()
	rebirthUI.setVisible(not rebirthUI.isVisible())
end

hud.onCodes = function()
	local opening = not codesUI.isVisible()
	if opening then
		minesUI.setVisible(false)
		inventoryUI.setVisible(false)
		upgradeUI.setVisible(false)
		indexUI.setVisible(false)
		wheelUI.setVisible(false)
	end
	Sounds.play(opening and "uiOpen" or "uiClose")
	codesUI.setVisible(opening)
	syncChrome()
end

hud.onIndex = function()
	local opening = not indexUI.isVisible()
	if opening then
		minesUI.setVisible(false)
		inventoryUI.setVisible(false)
		upgradeUI.setVisible(false)
		wheelUI.setVisible(false)
	end
	Sounds.play(opening and "uiOpen" or "uiClose")
	indexUI.setVisible(opening)
	syncChrome()
end

-- ── server events ───────────────────────────────────────────────────────────

Net.get("Sync").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	for key, value in pairs(payload) do
		state[key] = value
	end
	fireState()
end)

Net.get("Notify").OnClientEvent:Connect(function(text, kind)
	hud.notify(text, kind)
end)

Net.get("OpenPicker").OnClientEvent:Connect(function(padIndex)
	minesUI.setVisible(false)
	Sounds.play("uiOpen")
	inventoryUI.openForPad(padIndex)
end)

Net.get("EventState").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	--[[ Only when one BEGINS. EventState also fires as an event ends and on
	     every reconnect, and a fanfare on either of those is a fanfare for
	     nothing -- so it turns on the id changing to something real. ]]
	local previous = state.event and state.event.id
	state.event = snapshot
	if snapshot.id and snapshot.id ~= previous then
		Sounds.play("eventStart")
	end
	fireState()
end)

Net.get("OpenUpgrades").OnClientEvent:Connect(function()
	minesUI.setVisible(false)
	inventoryUI.setVisible(false)
	indexUI.setVisible(false)
	Sounds.play("uiOpen")
	upgradeUI.setVisible(true)
	syncChrome()
end)

Net.get("OpenRace").OnClientEvent:Connect(function()
	minesUI.setVisible(false)
	inventoryUI.setVisible(false)
	upgradeUI.setVisible(false)
	indexUI.setVisible(false)
	wheelUI.setVisible(false)
	summonUI.setVisible(false)
	Sounds.play("uiOpen")
	raceUI.setVisible(true)
	syncChrome()
end)

Net.get("OpenSummon").OnClientEvent:Connect(function()
	minesUI.setVisible(false)
	inventoryUI.setVisible(false)
	upgradeUI.setVisible(false)
	indexUI.setVisible(false)
	wheelUI.setVisible(false)
	Sounds.play("uiOpen")
	summonUI.setVisible(true)
	syncChrome()
end)

--[[ The wheel pulls its stake fresh on open rather than reading cached state:
     it is about to take everything, so the number on screen has to be the
     server's, not one the client happens to be holding. ]]
Net.get("OpenWheel").OnClientEvent:Connect(function()
	minesUI.setVisible(false)
	inventoryUI.setVisible(false)
	upgradeUI.setVisible(false)
	indexUI.setVisible(false)
	Sounds.play("uiOpen")
	local ok, stake = pcall(function()
		return ctx.remotes.WheelStake:InvokeServer()
	end)
	if ok and stake then
		wheelUI.setStake(stake)
	end
	wheelUI.setVisible(true)
	syncChrome()
end)

Net.get("OpenMines").OnClientEvent:Connect(function()
	Sounds.play("uiOpen")
	showMines(true)
end)

Net.get("Announce").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	-- Skip our own finds -- we already got the full screen-shaking version.
	if payload.userId == player.UserId then
		return
	end
	ctx.fx.announce(payload)
end)

--[[
	Plot audio, driven off state changes rather than off the UI that caused
	them. Placement can originate from the collection panel OR from a pad's
	proximity prompt (which resolves entirely server-side), so watching the
	resulting state is the only place that catches both.
]]
do
	local lastSlots, lastPlaced

	ctx.onState(function()
		local placed = 0
		for _, item in ipairs(state.inventory or {}) do
			if item.pad then
				placed += 1
			end
		end
		local slots = state.slots or 0

		if lastSlots and slots > lastSlots then
			Sounds.play("unlock")
		end
		if lastPlaced and placed ~= lastPlaced then
			Sounds.play(placed > lastPlaced and "place" or "store")
		end

		lastSlots, lastPlaced = slots, placed
	end)
end

-- Pull once on startup so we can't miss the server's first push.
task.spawn(function()
	local ok, snapshot = pcall(ctx.remotes.RequestState.InvokeServer, ctx.remotes.RequestState)
	if not ok then
		warn("[ClientMain] initial state pull failed: " .. tostring(snapshot))
		return
	end
	if type(snapshot) == "table" then
		for key, value in pairs(snapshot) do
			state[key] = value
		end
		fireState()
	end
end)

-- ── keybinds ────────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		showMines(not minesUI.isVisible())
	elseif input.KeyCode == Enum.KeyCode.C then
		showInventory(not inventoryUI.isVisible())
	elseif input.KeyCode == Enum.KeyCode.Escape then
		minesUI.setVisible(false)
		inventoryUI.setVisible(false)
		upgradeUI.setVisible(false)
		indexUI.setVisible(false)
		syncChrome()
	end
end)

-- ── pad model animation ─────────────────────────────────────────────────────
--
-- Server-placed models are anchored and never moved by the server, so the
-- client is free to animate them locally. Rebuilding the tagged list every
-- frame would allocate constantly, so we track adds/removes instead, and skip
-- anything too far away to see.

local ANIMATE_RADIUS = 130
local tracked = {}

--[[
	The parts this model animates, and where each sits relative to the pivot.

	CALLED AGAIN LATER IF IT COMES BACK EMPTY, which it does. A tagged model
	replicates before its parts do, so GetDescendants on the frame the tag
	arrives can legitimately find nothing -- and a list captured empty then
	stays empty, leaving that brainrot frozen for the rest of the session. It
	survived one test because three models replicate faster than eight.

	The old PivotTo had no such failure mode: it addressed the model rather
	than a remembered list. Holding the Aura and LabelAnchor still is what
	requires naming parts individually, so this is the cost of that, paid with
	a re-check instead of a race.
]]
local function collectParts(model, data)
	local pivot = data.pivot
	table.clear(data.moving)
	table.clear(data.offset)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name ~= "Aura"
			and descendant.Name ~= "LabelAnchor"
		then
			table.insert(data.moving, descendant)
			data.offset[descendant] = pivot:ToObjectSpace(descendant.CFrame)
		end
	end

	--[[
		THE AURA IS THE ONLY HONEST ANCHOR. We never move it, so wherever it is,
		the model is genuinely resting -- unlike the pivot, which we displace
		every frame and which is a bounding box over parts we are shifting.

		This is what makes the capture race survivable. A tagged model can reach
		the client before the server has placed it, at the origin, and a pivot
		cached there is 250 studs from the camera: outside ANIMATE_RADIUS, never
		animated, frozen for the session. Two of eight hit exactly that. Since
		the offsets are all pivot-RELATIVE, recomputing the pivot from the aura
		each frame fixes the placement without touching them, and needs no
		distance threshold to guess with.
	]]
	data.aura = model:FindFirstChild("Aura")
	data.auraRel = data.aura and pivot:ToObjectSpace(data.aura.CFrame) or nil

	return #data.moving > 0
end

local function track(model)
	task.defer(function()
		if not model:IsDescendantOf(Workspace) then
			return
		end

		local tintable = {}
		if model:GetAttribute("CycleHue") then
			for _, descendant in ipairs(model:GetDescendants()) do
				if
					descendant:IsA("BasePart")
					and not descendant:GetAttribute("NoTint")
					and descendant.Name ~= "Root"
				then
					table.insert(tintable, descendant)
				end
			end
		end

		--[[
			MOVED PART BY PART, NOT BY PivotTo, so two things can stay behind.

			The Aura is a shadow, and a shadow that lifts off the floor with the
			thing casting it reads as broken depth. The LabelAnchor carries the
			nameplate, which is UI rather than anatomy -- three lines of small
			type bobbing half a stud is motion the eye keeps catching, and it
			shimmers against whatever is behind it.

			PivotTo moves every part in the model, so keeping those two still
			means addressing the rest individually. Offsets are stored relative
			to the pivot so the model still turns about its own centre.
		]]
		local data = {
			pivot = model:GetPivot(),
			tintable = tintable,
			moving = {},
			offset = {},
			phase = math.random() * math.pi * 2,
		}
		collectParts(model, data)
		tracked[model] = data
	end)
end

for _, model in ipairs(CollectionService:GetTagged(Config.BrainrotTag)) do
	track(model)
end
CollectionService:GetInstanceAddedSignal(Config.BrainrotTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.BrainrotTag):Connect(function(model)
	tracked[model] = nil
end)

--[[
	The landmark's rings. Separate from the brainrot animation because they want
	pure yaw at their own speeds and directions, no bob, and they're always
	worth spinning regardless of distance -- they're the map's landmark, so they
	read from across it.
]]
local ringPivots = {}

--[[
	Polls rather than checking once.

	PrimaryPart is a REFERENCE property, and references can replicate after the
	instance that owns them. The landmark is built at server start -- before any
	player joins -- so the whole thing lands in one burst as the client streams
	in, which is exactly when that lag shows up. A single deferred check loses
	the race and the ring then never spins, silently, for the life of the
	session. Waiting for the pivot to be trustworthy is what makes it reliable:
	capturing it early would snapshot the bounding box of a half-replicated ring
	and rotate it about the wrong centre.
]]
local function trackRing(model)
	task.spawn(function()
		local deadline = os.clock() + 15
		while os.clock() < deadline do
			if model:IsDescendantOf(Workspace) and model.PrimaryPart then
				ringPivots[model] = model:GetPivot()
				return
			end
			task.wait(0.25)
		end
		warn("[ClientMain] ring never became trackable: " .. model:GetFullName())
	end)
end
for _, m in ipairs(CollectionService:GetTagged(Config.RingTag)) do trackRing(m) end
CollectionService:GetInstanceAddedSignal(Config.RingTag):Connect(trackRing)
CollectionService:GetInstanceRemovedSignal(Config.RingTag):Connect(function(m)
	ringPivots[m] = nil
end)

-- Own accumulator on purpose: sharing the brainrot loop's `clock` would mean
-- deleting that loop silently freezes the rings.
local ringClock = 0
RunService.Heartbeat:Connect(function(dt)
	ringClock += dt
	for model, pivot in pairs(ringPivots) do
		if model.Parent then
			local dir = model:GetAttribute("SpinDirection") or 1
			local speed = model:GetAttribute("SpinSpeed") or 0.3
			model:PivotTo(pivot * CFrame.Angles(0, ringClock * speed * dir, 0))
		else
			ringPivots[model] = nil
		end
	end
end)

local clock = 0

RunService.Heartbeat:Connect(function(dt)
	clock += dt

	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position

	for model, data in pairs(tracked) do
		if not model.Parent then
			tracked[model] = nil
		else
			--[[
				NO ANCHOR YET MEANS RE-READ EVERYTHING. The Aura replicates
				separately from the Body, so the first look can find one and not
				the other -- and an anchor missed once was missed for the
				session, leaving that model with a pivot cached wherever it
				happened to be and failing the radius test forever. One of eight
				landed there even after the pivot fix.

				Safe to re-collect precisely because we have not animated this
				model: with no anchor it never passed the radius test, so its
				parts are still exactly where the server put them and GetPivot
				is its true rest pose.
			]]
			if not data.aura then
				data.pivot = model:GetPivot()
				collectParts(model, data)
			end

			-- re-derive the resting pivot from the part we never move, so a
			-- model placed after we cached it still lands in the right spot
			if data.aura and data.auraRel then
				data.pivot = data.aura.CFrame * data.auraRel:Inverse()
			end
			if not eye or (data.pivot.Position - eye).Magnitude < ANIMATE_RADIUS then
				-- late replication: try again rather than stay frozen forever
				local ready = #data.moving > 0 or collectParts(model, data)
				if ready then
					--[[ The spin carries `phase` too. Without it the yaw is raw
					     clock, so every brainrot on the map points the same way
					     at the same moment and eight pads read as one
					     mechanism -- the bob was already offset per model, the
					     turn was not. ]]
					local bob = math.sin(clock * 1.7 + data.phase) * 0.22
					local cf = data.pivot
						* CFrame.new(0, bob, 0)
						* CFrame.Angles(0, clock * 0.7 + data.phase, 0)
					for _, part in ipairs(data.moving) do
						local rest = data.offset[part]
						if rest then
							part.CFrame = cf * rest
						end
					end
				end

				if #data.tintable > 0 then
					local hue = (clock * 0.16 + data.phase * 0.08) % 1
					local color = Color3.fromHSV(hue, 0.85, 1)
					for _, part in ipairs(data.tintable) do
						part.Color = color
					end
				end
			end
		end
	end
end)

--[[
	Close the shop panel when you walk away from its counter.

	Not Mines -- that's playable from anywhere again, so there's nowhere to walk
	away FROM, and the server agrees. A UI rule the server doesn't share is
	theatre; this one matches a real server-side gate.

	A MISSING part closes the panel as well. StreamingEnabled is on, so walking
	far enough unloads the counter -- and waiting on a part that will never
	stream back would leave the panel stuck open. You can only open this
	standing at the counter, so "not there" is the only thing nil can mean.

	It was written for two counters, the second being the one through the hub
	portal. That one went with the auction; the loop is unchanged because it was
	never counting them.
]]
task.spawn(function()
	local function walkedAway(modelName, partName)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local model = Workspace:FindFirstChild(modelName)
		local counter = model and model:FindFirstChild(partName)
		return not counter or not root
			or (root.Position - counter.Position).Magnitude > 34
	end

	while true do
		task.wait(0.5)
		if upgradeUI.isVisible() and walkedAway("UpgradeShop", "Counter") then
			upgradeUI.setVisible(false)
			syncChrome()
		end
	end
end)

-- ── first-run nudge ─────────────────────────────────────────────────────────

--[[
	The first-run nudge used to live here: one toast, two seconds after spawn,
	gone before most people had finished loading in. UI/Coach replaces it with a
	persistent card that tracks real progress, so this is deliberately empty.
]]
