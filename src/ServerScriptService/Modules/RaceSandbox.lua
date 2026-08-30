--[[
	RaceSandbox
	A track you can stand next to and watch the stat model actually run.

	NOT THE BETTING RACE. RaceTrack still exists, still rolls a winner and still
	animates it; nothing here touches it. This is the new model on its own strip
	so the two can be compared side by side before either is thrown away.

	ONE LAP, AND THE LINE IS THE ANSWER. Whoever crosses first has won, and you
	can see it -- which is the whole reason this is not laps any more.

	It went through both wrong answers first. A straight strip SCALED to fit
	the island made The Haul crawl at 1.8 studs/s on screen while The Dash moved
	at 11.8, so the longest race looked six times slower than the shortest.
	Drawing 1:1 and running MULTIPLE LAPS fixed the speed and broke the reading:
	on a circuit the runner physically in front of you may be a lap down, so
	first-past-the-post becomes invisible.

	A circuit sized to the track fixes both. Every track is exactly one lap of
	its own oval, drawn 1:1, so apparent speed is the runner's real speed AND
	the leader is simply the one further round. Nobody is ever a lap down
	because there is only ever one lap.

	THE ISLAND HAD TO GROW FOR THIS. The Haul is 1400 studs, and a 1400-stud
	single lap needs about 305 studs of apron; the island was 110 with 90. It is
	400 now, which measured at 1322 parts against the old 467 -- the scatter
	exponents in IslandService are sub-linear, so tripling the radius cost less
	than a fifth of what the area suggests.

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
local LANE = 7 -- studs between the two runners, across the track
--[[ Well clear of the old RaceTrack, which is still standing on the same
     island and would otherwise be drawn through this one. Drop this back to
     ground level the day the betting track is retired. ]]
local DECK_Y = 26
local WIDTH = 20 -- how wide the running surface is

--[[
	THE CIRCUIT IS SIZED TO THE TRACK, so one lap is exactly its length.

	A stadium: two straights joined by two semicircles, with the straight fixed
	at twice the turn radius so every track is the same SHAPE and only the size
	changes -- a 220-stud dash and a 1400-stud haul read as the same kind of
	place, one small and one enormous.

		perimeter = 2S + 2*pi*R, and S = 2R
		          = 4R + 2*pi*R
		          = R * (4 + 2*pi)

	Solved for R, so the perimeter IS the track length rather than approximately
	it. Get this wrong and the finish line sits somewhere that is not the finish.
]]
local SHAPE = 4 + 2 * math.pi -- perimeter / radius, for straight = 2 * radius

local function circuitFor(track)
	local radius = track.length / SHAPE
	return {
		radius = radius,
		straight = radius * 2,
		turn = math.pi * radius,
		perimeter = track.length,
	}
end

--[[
	Distance along the centre line -> a point and a facing.

	NO WRAPPING. Distance runs 0 to the perimeter once and stops; a modulo here
	would silently start a second lap and put the leader behind the runner they
	just passed. Clamped instead, so a runner who has finished parks on the line
	rather than vanishing round it again.

	`offset` pushes a runner into its own lane WITHOUT changing how far it has
	run -- lanes are cosmetic, and a lane that added distance would quietly hand
	the inside runner a shorter race.
]]
local function pointAt(geo, distance, offset)
	local d = math.clamp(distance, 0, geo.perimeter)
	local S, R = geo.straight, geo.radius
	local r = R + (offset or 0)
	if d < S / 2 then
		--[[ the near straight runs from the LINE to the first turn, so distance
		     0 is the line and the lap closes back onto it ]]
		return Vector3.new(d, 0, -r), Vector3.new(1, 0, 0)
	end
	d -= S / 2
	if d < geo.turn then
		local a = d / R
		return Vector3.new(S / 2 + math.sin(a) * r, 0, -math.cos(a) * r),
			Vector3.new(math.cos(a), 0, math.sin(a))
	end
	d -= geo.turn
	if d < S then
		return Vector3.new(S / 2 - d, 0, r), Vector3.new(-1, 0, 0)
	end
	d -= S
	if d < geo.turn then
		local a = d / R
		return Vector3.new(-S / 2 - math.sin(a) * r, 0, math.cos(a) * r),
			Vector3.new(-math.cos(a), 0, -math.sin(a))
	end
	d -= geo.turn
	return Vector3.new(-S / 2 + d, 0, -r), Vector3.new(1, 0, 0)
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

	local geo = circuitFor(track)
	local root = Instance.new("Model")
	root.Name = ROOT_NAME
	local base = CFrame.new(island.center + Vector3.new(0, DECK_Y, 0))

	--[[ The surface, laid as short segments round the centre line. Cheaper to
	     reason about than a mesh and it makes the turns actually curve. ]]
	local SEGMENTS = 72
	for i = 0, SEGMENTS - 1 do
		local p0 = pointAt(geo, (i / SEGMENTS) * geo.perimeter, 0)
		local p1 = pointAt(geo, ((i + 1) / SEGMENTS) * geo.perimeter, 0)
		local mid = (p0 + p1) / 2
		local span = (p1 - p0).Magnitude
		local seg = part({
			name = "Track",
			size = Vector3.new(span + 0.6, 1, WIDTH),
			cframe = base * CFrame.lookAt(mid, mid + (p1 - p0).Unit),
			color = Color3.fromRGB(84, 96, 78),
			material = Enum.Material.Grass,
			collide = true,
		}, root)
		seg.CFrame = seg.CFrame * CFrame.Angles(0, math.rad(90), 0)
	end

	--[[ The line, and a marker every quarter lap so a fade has landmarks. ]]
	local startP = pointAt(geo, 0, 0)
	part({
		name = "StartLine",
		size = Vector3.new(1.4, 1.3, WIDTH),
		cframe = base * CFrame.new(startP + Vector3.new(0, 0.2, 0)),
		color = Color3.fromRGB(255, 196, 52),
		material = Enum.Material.Neon,
	}, root)
	for q = 1, 3 do
		local p, dir = pointAt(geo, geo.perimeter * q / 4, 0)
		part({
			name = "Quarter",
			size = Vector3.new(0.5, 1.1, WIDTH),
			cframe = base * CFrame.lookAt(p + Vector3.new(0, 0.1, 0), p + dir)
				* CFrame.Angles(0, math.rad(90), 0),
			color = Color3.fromRGB(150, 165, 145),
			transparency = 0.4,
		}, root)
	end

	local sign = part({
		name = "Sign",
		size = Vector3.new(0.4, 0.4, 0.4),
		cframe = base * CFrame.new(0, 16, 0),
		transparency = 1,
	}, root)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(460, 82)
	gui.AlwaysOnTop = true
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 240, 245)
	label.Text = ("%s  -  %d studs, one lap%s\nbest split %s")
		:format(track.name, track.length,
			track.drain > 1 and (("  -  uphill x%.1f drain"):format(track.drain)) or "",
			track.best)
	label.Parent = gui

	root.Parent = Workspace
	return root, base, geo
end

--[[ A runner: a coloured marker with its own live numbers over its head. ]]
local function buildRunner(root, base, geo, lane, entry, color)
	local model = Instance.new("Model")
	model.Name = "Runner_" .. entry.id
	local p = pointAt(geo, 0, lane * LANE)
	local body = part({
		name = "Body",
		size = Vector3.new(2.4, 3.2, 2.4),
		cframe = base * CFrame.new(p + Vector3.new(0, 2.5, 0)),
		color = color,
		material = Enum.Material.Neon,
	}, model)
	model.PrimaryPart = body

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(250, 66)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
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
		local root, base, geo = RaceSandbox.build(track)
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
			local model, body, label = buildRunner(root, base, geo, lane, runner, colors[i] or colors[1])
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
				--[[ 1:1 -- the distance the model says it has run is the distance
				     it has moved along the circuit. Nothing is scaled, which is
				     what makes apparent speed the same on every track. ]]
				local p, dir = pointAt(geo, runner.distance, view.lane * LANE)
				view.body.CFrame = base * CFrame.lookAt(p + Vector3.new(0, 2.5, 0),
					p + dir + Vector3.new(0, 2.5, 0))
				local pct = math.max(runner.stamina, 0) / runner.staminaMax * 100
				--[[ Place is read off DISTANCE, which on a ONE-LAP circuit is the
				     same thing the eye reads off the track. That equivalence is the
				     whole point of one lap: on a multi-lap oval the runner in front
				     of you may be a lap down, and the label would disagree with the
				     picture. ]]
				local place = 1
				for _, other in ipairs(state.runners) do
					if other ~= runner and other.distance > runner.distance then
						place += 1
					end
				end
				local togo = math.max(track.length - runner.distance, 0)
				view.label.Text = ("%s   %d/%d\n%s   %.0f studs/s   stamina %d%%   %.0f to go")
					:format(runner.name, runner.speed, runner.endurance,
						place == 1 and "LEADING" or ("P" .. place),
						runner.velocity * RaceSim.PACE, pct, togo)
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
