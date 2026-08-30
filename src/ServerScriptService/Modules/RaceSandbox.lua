--[[
	RaceSandbox
	A track you can stand next to and watch the stat model actually run.

	NOT THE BETTING RACE. RaceTrack still exists, still rolls a winner and still
	animates it; nothing here touches it. This is the new model on its own strip
	so the two can be compared side by side before either is thrown away.

	THE STRIP IS SCALED, THE CLOCK IS NOT. The racing island has a radius of 110
	and The Haul is 1400 studs, so a true-length track cannot be built here at
	all. Distance is mapped onto a strip that fits and the SECONDS are left
	alone -- which keeps the thing that actually needs feeling: The Dash is over
	in nine seconds and The Haul grinds for ninety, and a Sprinter dying at the
	three-quarter mark looks exactly like a Sprinter dying at the three-quarter
	mark whatever the strip measures. Build the real lengths when the island
	grows; this file is where that number changes.

	RUNNERS CARRY THEIR OWN NUMBERS. Each one has its speed and remaining
	stamina above its head, because the point of a sandbox is to see WHY the
	race went the way it did, not to be surprised by it. That readout is the
	feature, not debug output.

	BUILT ON DEMAND AND TORN DOWN AFTER, which is also how the real thing wants
	to work -- the six tracks are meant to load only once a boss is chosen, and
	this is that pattern at one-track scale.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RaceSim = require(Shared.RaceSim)
local Islands = require(Shared.Islands)

local RaceSandbox = {}

local ROOT_NAME = "RaceSandbox"
local LANE = 9 -- studs between the two runners
local DECK_Y = 5 -- height of the strip above the island floor
local WIDTH = 26

--[[ Shortest and longest strip the island can hold. The Haul gets the long end
     and The Dash the short one, so the tracks still LOOK different lengths
     even though none of them is its true length. ]]
local STRIP_MIN, STRIP_MAX = 95, 165

local busy = false

local function stripLength(track)
	local longest = 0
	for _, t in ipairs(RaceSim.Tracks) do
		longest = math.max(longest, t.length)
	end
	return STRIP_MIN + (track.length / longest) * (STRIP_MAX - STRIP_MIN)
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color or Color3.fromRGB(120, 120, 120)
	p.Transparency = props.transparency or 0
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

function RaceSandbox.clear()
	local existing = Workspace:FindFirstChild(ROOT_NAME)
	if existing then
		existing:Destroy()
	end
end

--[[ Lay the strip out along X, centred on the island, with the two lanes
     spread along Z. Returns the root plus the two lane start positions so the
     caller never re-derives geometry this function already decided. ]]
function RaceSandbox.build(track)
	RaceSandbox.clear()
	local island = Islands.get("racing")
	if not island then
		return nil
	end

	local length = stripLength(track)
	local root = Instance.new("Model")
	root.Name = ROOT_NAME

	local centre = island.center + Vector3.new(0, DECK_Y, 0)
	--[[ The Climb is drawn tilted. It changes nothing in the model -- drain is
	     a number on the track, not a slope the runner feels -- but a track that
	     drains you should not look flat. ]]
	local tilt = track.drain > 1.5 and math.rad(6) or 0

	local deck = part({
		name = "Deck",
		size = Vector3.new(length, 1, WIDTH),
		cframe = CFrame.new(centre) * CFrame.Angles(0, 0, tilt),
		color = Color3.fromRGB(78, 92, 70),
		material = Enum.Material.Grass,
		collide = true,
	}, root)

	part({
		name = "StartLine",
		size = Vector3.new(1.5, 1.2, WIDTH),
		cframe = deck.CFrame * CFrame.new(-length / 2 + 2, 0.2, 0),
		color = Color3.fromRGB(235, 235, 235),
	}, root)
	part({
		name = "FinishLine",
		size = Vector3.new(1.5, 1.2, WIDTH),
		cframe = deck.CFrame * CFrame.new(length / 2 - 2, 0.2, 0),
		color = Color3.fromRGB(255, 196, 52),
		material = Enum.Material.Neon,
	}, root)

	--[[ A marker every quarter, so "he died at the three-quarter mark" is a
	     thing you can see rather than a thing you have to time. ]]
	for q = 1, 3 do
		part({
			name = "Quarter",
			size = Vector3.new(0.5, 1.05, WIDTH),
			cframe = deck.CFrame * CFrame.new(-length / 2 + length * (q / 4), 0.1, 0),
			color = Color3.fromRGB(150, 165, 145),
			transparency = 0.35,
		}, root)
	end

	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.Size = Vector3.new(0.4, 0.4, 0.4)
	sign.Transparency = 1
	sign.CFrame = deck.CFrame * CFrame.new(0, 14, 0)
	sign.Parent = root

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 76)
	gui.AlwaysOnTop = true
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 240, 245)
	label.Text = ("%s  ·  %d studs%s\nbest split %s")
		:format(track.name, track.length,
			track.drain > 1 and (("  ·  uphill x%.1f drain"):format(track.drain)) or "",
			track.best)
	label.Parent = gui

	root.Parent = Workspace
	return root, deck, length
end

--[[ A runner: a coloured marker with its own live numbers over its head. ]]
local function buildRunner(root, deck, length, lane, entry, color)
	local model = Instance.new("Model")
	model.Name = "Runner_" .. entry.id

	local body = part({
		name = "Body",
		size = Vector3.new(2.6, 3.4, 2.6),
		cframe = deck.CFrame * CFrame.new(-length / 2 + 2, 2.6, lane * LANE),
		color = color,
		material = Enum.Material.Neon,
	}, model)
	model.PrimaryPart = body

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 68)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = body
	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = entry.name
	label.Parent = gui

	model.Parent = root
	return model, body, label
end

--[[
	Run one race and return the finishing order.

	The visual is driven straight off RaceSim.step -- there is no second copy of
	the movement here. If the marker is in front, it is because the simulation
	says it is in front.
]]
function RaceSandbox.run(entries, trackId, onFinish)
	if busy then
		return false, "A race is already running."
	end
	local track = RaceSim.track(trackId)
	if not track then
		return false, "Unknown track."
	end
	busy = true

	local function body()
		local root, deck, length = RaceSandbox.build(track)
		if not root then
			error("no racing island")
		end

		local state = RaceSim.start(entries, trackId)
		local views = {}
		local colors = {
			Color3.fromRGB(120, 220, 255),
			Color3.fromRGB(255, 140, 120),
		}
		for i, runner in ipairs(state.runners) do
			local lane = i - (#state.runners + 1) / 2
			local model, body, label = buildRunner(root, deck, length, lane, runner, colors[i] or colors[1])
			views[i] = { model = model, body = body, label = label, lane = lane }
		end

		local conn
		local finished = false
		conn = RunService.Heartbeat:Connect(function(dt)
			--[[ Clamped: a hitch that hands over a whole second would teleport
			     every runner and, worse, drain a whole second of stamina in one
			     step -- the Euler integration is only honest at small dt. ]]
			local step = math.min(dt, 0.1)
			finished = RaceSim.step(state, step)

			for i, runner in ipairs(state.runners) do
				local view = views[i]
				local along = (runner.distance / track.length) * (length - 4)
				view.body.CFrame = deck.CFrame
					* CFrame.new(-length / 2 + 2 + along, 2.6, view.lane * LANE)
				local pct = math.max(runner.stamina, 0) / runner.staminaMax * 100
				view.label.Text = ("%s   %d/%d\n%.1f studs/s   stamina %d%%")
					:format(runner.name, runner.speed, runner.endurance, runner.velocity, pct)
			end
			if finished then
				conn:Disconnect()
			end
		end)

		--[[
			DOES NOT BLOCK THE CALLER. The Haul takes ninety seconds of real
			time, and the first version returned the finishing order straight
			out of a RemoteFunction -- which meant the client sat inside a
			ninety-second InvokeServer, indistinguishable from a hang, and the
			MCP call testing it timed out before the race did. The result is
			pushed to `onFinish` instead and the remote answers immediately.
		]]
		local waited = 0
		while not finished and waited < 240 do
			task.wait(0.1)
			waited += 0.1
		end
		if conn.Connected then
			conn:Disconnect()
		end

		local order = {}
		for place, runner in ipairs(state.order) do
			order[place] = {
				id = runner.id,
				name = runner.name,
				speed = runner.speed,
				endurance = runner.endurance,
				time = runner.finishedAt,
			}
		end
		task.delay(6, function()
			--[[ Left standing for a beat so the finish can be read, then
			     cleared -- the next race rebuilds from scratch. ]]
			if not busy then
				RaceSandbox.clear()
			end
		end)
		return order
	end

	task.spawn(function()
		local ok, result = pcall(body)
		busy = false
		if not ok then
			RaceSandbox.clear()
			warn("[RaceSandbox] race failed:", result)
			if onFinish then
				onFinish(nil, tostring(result))
			end
			return
		end
		if onFinish then
			onFinish(result)
		end
	end)
	return true
end

function RaceSandbox.isBusy()
	return busy
end

--[[
	The remote. Validates the split rather than trusting it: the panel is the
	only thing that sends these today, but a sandbox that accepts Speed 9999
	teaches nothing about a model it is not actually running.
]]
function RaceSandbox.start()
	local Net = require(Shared.Net)
	local DataService = require(script.Parent.DataService)

	--[[
		Remember the split. Stored as pool + speed with endurance DERIVED, so
		the two can never be saved out of step with each other.

		Fire-and-forget, and deliberately not validated against anything but its
		own bounds: this is a bench, the pool is a dial the player is meant to
		drag around, and the race clamps what it is handed anyway.
	]]
	Net.get("SetRacer").OnServerEvent:Connect(function(player, pool, speed)
		local profile = DataService.get(player)
		if not profile then
			return
		end
		pool = math.clamp(math.floor(tonumber(pool) or 22), 1, RaceSim.MaxPool)
		speed = math.clamp(math.floor(tonumber(speed) or 0), 0, pool)
		profile.runner = { pool = pool, speed = speed }
	end)

	Net.get("RaceTest").OnServerInvoke = function(player, speed, endurance, trackId, opponentId)
		speed = math.clamp(math.floor(tonumber(speed) or 0), 0, RaceSim.MaxPool)
		endurance = math.clamp(math.floor(tonumber(endurance) or 0), 0, RaceSim.MaxPool)
		if speed + endurance > RaceSim.MaxPool then
			return { ok = false, err = "That is more than a runner can carry." }
		end
		local opponent = RaceSim.OpponentById[opponentId]
		if not opponent then
			return { ok = false, err = "Unknown opponent." }
		end
		local track = RaceSim.track(trackId)
		if not track then
			return { ok = false, err = "Unknown track." }
		end
		if RaceSandbox.isBusy() then
			return { ok = false, err = "A race is already running." }
		end

		local oSpeed, oEndurance = RaceSim.splitFor(opponent, trackId)
		local started, err = RaceSandbox.run({
			{ id = "you", name = player.DisplayName, speed = speed, endurance = endurance },
			{ id = opponent.id, name = opponent.name, speed = oSpeed, endurance = oEndurance },
		}, trackId, function(order, failed)
			--[[ The player may have left mid-race; firing at a gone player is
			     an error rather than a no-op. ]]
			if player.Parent then
				Net.get("RaceResult"):FireClient(player, {
					ok = order ~= nil,
					err = failed,
					order = order,
					opponent = { speed = oSpeed, endurance = oEndurance },
				})
			end
		end)
		if not started then
			return { ok = false, err = err or "Race failed." }
		end
		--[[ Answers the moment the race STARTS. The finish arrives on
		     RaceResult, however long it takes. ]]
		return { ok = true, started = true, track = trackId }
	end
end

return RaceSandbox
