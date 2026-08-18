--[[
	RaceTrack
	The strip on island two, and the runners that go down it.

	SERVER-DRIVEN, so everyone standing at the rail watches the SAME race. The
	outcome is already decided before a runner moves -- this module only draws
	it -- so there is nothing here that can disagree with the payout, and a
	second player watching cannot see a different winner.

	THE ORDER IS GUARANTEED, THE JOURNEY IS NOT. Each runner is handed a finish
	time derived from its decided place, and a wobble that makes it trade
	positions with its neighbours on the way. The wobble DECAYS to nothing over
	the last quarter, so the field is watchable in the middle and unambiguous at
	the line -- which is the whole trick to a race whose result was settled
	before it started.

	Runners are ModelFactory copies with the brainrot tag stripped, for the same
	reason the mount is: the client bobs anything tagged, and that animation
	would fight this one for control of every runner on the track.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = script.Parent
local ModelFactory = require(Modules.ModelFactory)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Islands = require(Shared.Islands)
local Brainrots = require(Shared.Brainrots)

local RaceTrack = {}

local LENGTH = 150 -- start line to finish line
local LANE = 7 -- spacing between runners
--[[ The clearing's TOP surface, relative to the island centre. IslandService
     puts the clearing slab at +3.34 and it is 1.4 thick, so its surface is at
     +4.04 -- and 3.4 was the slab's CENTRE, which buried the whole track a
     quarter stud under the ground it is supposed to lie on. ]]
local DECK = 4.05

local busy = false

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color or Color3.fromRGB(120, 128, 160)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Name = props.name or "Part"
	p.Transparency = props.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[ Lanes run along X; the field spreads along Z. Returned rather than stored
     so callers cannot drift from the geometry that was actually built. ]]
function RaceTrack.laneStart(index, count)
	local island = Islands.get("racing")
	local z = (index - (count + 1) / 2) * LANE
	return island.center + Vector3.new(-LENGTH / 2, DECK, z)
end

function RaceTrack.laneFinish(index, count)
	return RaceTrack.laneStart(index, count) + Vector3.new(LENGTH, 0, 0)
end

function RaceTrack.build()
	local island = Islands.get("racing")
	if not island then
		return
	end

	local existing = Workspace:FindFirstChild("RaceTrack")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Model")
	root.Name = "RaceTrack"
	root.Parent = Workspace

	local c = island.center + Vector3.new(0, DECK, 0)
	local accent = island.accent

	-- the running surface
	part({
		name = "Strip", size = Vector3.new(LENGTH + 16, 0.4, LANE * 10 + 6),
		cframe = CFrame.new(c + Vector3.new(0, 0.2, 0)),
		color = Color3.fromRGB(94, 76, 62), material = Enum.Material.Sand,
	}, root)

	--[[ Lane lines rather than lane walls. A rail between every runner would
	     hide the field from anyone standing side-on, and side-on is where the
	     whole race is watched from. ]]
	for i = 0, 10 do
		local z = (i - 5) * LANE
		part({
			name = "LaneLine", size = Vector3.new(LENGTH + 16, 0.42, 0.3),
			cframe = CFrame.new(c + Vector3.new(0, 0.42, z)),
			color = Color3.fromRGB(150, 132, 110), material = Enum.Material.SmoothPlastic,
		}, root)
	end

	for _, side in ipairs({ -1, 1 }) do
		part({
			name = "StartPost", size = Vector3.new(1.2, 9, 1.2),
			cframe = CFrame.new(c + Vector3.new(-LENGTH / 2 - 2, 4.5, side * (LANE * 5 + 2))),
			color = accent, material = Enum.Material.Neon,
		}, root)
		part({
			name = "FinishPost", size = Vector3.new(1.2, 9, 1.2),
			cframe = CFrame.new(c + Vector3.new(LENGTH / 2 + 2, 4.5, side * (LANE * 5 + 2))),
			color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Neon,
		}, root)
	end

	-- start gate and finish line, so both ends read at a glance
	part({
		name = "StartLine", size = Vector3.new(0.8, 0.44, LANE * 10 + 4),
		cframe = CFrame.new(c + Vector3.new(-LENGTH / 2, 0.44, 0)),
		color = accent, material = Enum.Material.Neon,
	}, root)
	for i = 0, 13 do
		part({
			name = "Chequer", size = Vector3.new(3, 0.46, 3),
			cframe = CFrame.new(c + Vector3.new(LENGTH / 2, 0.46, (i - 6.5) * 5.4)),
			color = (i % 2 == 0) and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(28, 30, 40),
			material = Enum.Material.SmoothPlastic,
		}, root)
	end

	--[[ The stand, and the prompt. Set BEHIND the start line and off to one
	     side, because a player triggering a race should be looking down the
	     length of the track rather than across it. ]]
	local podium = part({
		name = "Stand", size = Vector3.new(10, 6, 10),
		cframe = CFrame.new(c + Vector3.new(-LENGTH / 2 - 14, 3, LANE * 5 + 12)),
		color = Color3.fromRGB(84, 92, 120), material = Enum.Material.Metal,
		collide = true,
	}, root)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(156, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.MaxDistance = 260
	gui.Parent = podium

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "THE TRACK"
	title.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 20
	cap.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = accent
	sub.TextStrokeTransparency = 0.45
	sub.Text = "pick your field"
	sub.Parent = gui
	local subCap = Instance.new("UITextSizeConstraint")
	subCap.MaxTextSize = 10
	subCap.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RacePrompt"
	prompt.ActionText = "Race"
	prompt.ObjectText = "The Track"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = podium

	RaceTrack.prompt = prompt
	RaceTrack.root = root
	return root
end

--[[ A runner: the player's own brainrot for their lane, a random one for each
     rival, so the field looks like a field rather than a row of clones. ]]
local function buildRunner(entry, rng)
	local charId, variantId = entry.charId, entry.variantId
	if not charId then
		local pool = Brainrots.List
		charId = pool[rng:NextInteger(1, #pool)].id
		variantId = "Normal"
	end
	local model = ModelFactory.build(charId, variantId)
	if not model then
		return nil
	end
	CollectionService:RemoveTag(model, Config.BrainrotTag)
	for _, name in ipairs({ "Aura", "LabelAnchor" }) do
		local extra = model:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	model.Name = entry.you and "You" or "Rival"
	return model
end

--[[
	Run the decided order down the track.

	`order` is finishing order, index 1 first. Returns immediately; the race
	plays out on Heartbeat and cleans itself up.
]]
function RaceTrack.run(order, seconds)
	if busy or not order or #order == 0 then
		return false
	end
	local root = Workspace:FindFirstChild("RaceTrack")
	if not root then
		return false
	end
	busy = true

	local rng = Random.new()
	local count = #order
	local runners = {}

	for place, entry in ipairs(order) do
		local model = buildRunner(entry, rng)
		if model then
			local lane = place -- lane assignment is arbitrary; the ORDER is not
			local from = RaceTrack.laneStart(lane, count)
			model.Parent = root
			model:PivotTo(CFrame.new(from) * CFrame.Angles(0, math.rad(-90), 0))
			table.insert(runners, {
				model = model,
				from = from,
				to = RaceTrack.laneFinish(lane, count),
				--[[ Later places finish later. A tenth of a second apart is
				     enough to be unambiguous at the line and far too little to
				     read as a procession. ]]
				finish = 1 - (place - 1) * 0.012,
				phase = rng:NextNumber(0, math.pi * 2),
				swing = rng:NextNumber(0.04, 0.10),
			})
		end
	end

	if #runners == 0 then
		busy = false
		return false
	end

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / seconds, 0, 1)

		for _, r in ipairs(runners) do
			--[[ Wobble decays to zero over the last quarter, so places can
			     change all the way through the middle and cannot change once
			     the line is in sight. ]]
			local decay = math.clamp((1 - t) / 0.25, 0, 1)
			local wobble = math.sin(t * math.pi * 3 + r.phase) * r.swing * decay
			local progress = math.clamp(t * r.finish + wobble, 0, 1)
			local at = r.from:Lerp(r.to, progress)
			-- a small bounce, so they read as running rather than sliding
			at += Vector3.new(0, math.abs(math.sin(elapsed * 9 + r.phase)) * 0.8, 0)
			r.model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.rad(-90), 0))
		end

		if t >= 1 then
			connection:Disconnect()
			task.delay(3.5, function()
				for _, r in ipairs(runners) do
					if r.model.Parent then
						r.model:Destroy()
					end
				end
				busy = false
			end)
		end
	end)

	return true
end

function RaceTrack.isBusy()
	return busy
end

return RaceTrack
