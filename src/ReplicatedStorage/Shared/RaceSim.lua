--[[
	RaceSim
	How a runner gets down a track, and why two builds finish in a different
	order depending on which track it is.

	THE SIMULATION IS THE RACE. Every tick moves a runner by the speed it
	actually has at that moment, and the finish order is whatever falls out.
	Nothing here decides a winner and then draws it -- which is the difference
	between this and RaceTrack, where the outcome was rolled first and the
	animation was a replay. Shared/Plinko makes the same argument about its
	bounces and is worth reading alongside this.

	TWO STATS, ONE SLIDER.

	  Speed      sets your top speed while you are fresh.
	  Endurance  sets how long you stay near it.

	Both come out of one pool, so every point of Speed is a point of Endurance
	you did not take. That is the whole game: there is no build that is good
	everywhere, only a build that suits the track in front of you.

	THE EXHAUSTED JOG IS THE SAME FOR EVERYONE, and that single number is what
	makes Endurance worth anything. The first version of this model decayed a
	runner to a FRACTION of its own top speed, so a spent Sprinter (floor 12.3)
	still outran a spent Stayer (floor 8.7) and Endurance bought nothing at any
	length. An absolute floor means running out is the same disaster whoever you
	are, and avoiding it is what Endurance is for.

	DRAIN IS QUADRATIC in current speed. Going fast is disproportionately
	expensive, which is why a Sprinter cannot simply out-run a long track: it is
	not that it lacks stamina, it is that its own top speed eats the stamina it
	has. Halving the exponent makes Speed strictly better than Endurance;
	raising it makes Speed unplayable. It is the most sensitive number here.

	MEASURED, NOT GUESSED. At a 22-point pool the optimal split is:

		The Dash    220 flat        15 / 7
		The Mile    650 flat        10 / 12
		The Climb   480 uphill       7 / 15
		The Haul   1400 flat         5 / 17

	Four tracks, four different answers, which is the property the whole design
	rests on. A medium UPHILL was cut for exactly this reason: 650 at drain 2.2
	wants 5/17, the same as the long flat, so it was a second copy of a puzzle
	that already existed wearing different scenery. The climb is 480 instead.
]]

local RaceSim = {}

--[[ Tuning. Re-run tools/race.py after touching any of these -- the four
     tracks above only have four different answers because of where these sit,
     and there is no warning when that stops being true. ]]
RaceSim.V_BASE = 16.0 -- top speed at Speed 0
RaceSim.V_PER = 0.85 -- top speed per point of Speed
RaceSim.ST_BASE = 30.0 -- stamina at Endurance 0
RaceSim.ST_PER = 11.0 -- stamina per point of Endurance
RaceSim.DRAIN = 5.0 -- stamina per second at V_REF
RaceSim.V_REF = 24.0 -- the speed DRAIN is quoted at
RaceSim.V_FLOOR = 11.0 -- the exhausted jog; the same for everyone

--[[ The pool a runner allocates. Grows as the story progresses, which is what
     makes the last opponent unbeatable until it does not: below his pool there
     is no split that beats his time, so the wall is real rather than scripted. ]]
RaceSim.StartingPool = 10
RaceSim.MaxPool = 40

--[[
	`drain` multiplies stamina cost, which is what "uphill" means here. It is
	deliberately not a speed penalty: slowing everyone down equally would change
	no finishing order, whereas draining everyone faster punishes the build that
	was relying on stamina it no longer has.
]]
RaceSim.Tracks = {
	{
		id = "dash",
		name = "The Dash",
		blurb = "Over before it starts",
		length = 220,
		drain = 1.0,
		best = "15 / 7",
	},
	{
		id = "mile",
		name = "The Mile",
		blurb = "Rewards a runner with no weaknesses",
		length = 650,
		drain = 1.0,
		best = "10 / 12",
	},
	{
		id = "climb",
		name = "The Climb",
		blurb = "Short, and it takes your legs",
		length = 480,
		drain = 2.2,
		best = "7 / 15",
	},
	{
		id = "haul",
		name = "The Haul",
		blurb = "Whoever is left standing",
		length = 1400,
		drain = 1.0,
		best = "5 / 17",
	},
}

RaceSim.ById = {}
for index, track in ipairs(RaceSim.Tracks) do
	track.index = index
	RaceSim.ById[track.id] = track
end

function RaceSim.track(id)
	return RaceSim.ById[id]
end

function RaceSim.topSpeed(speed)
	return RaceSim.V_BASE + (speed or 0) * RaceSim.V_PER
end

function RaceSim.stamina(endurance)
	return RaceSim.ST_BASE + (endurance or 0) * RaceSim.ST_PER
end

--[[
	One runner's state at the start line. `speed` and `endurance` are the split;
	nothing else about a brainrot enters the model, so two runners with the same
	split are the same runner however they look.
]]
local function newRunner(entry)
	return {
		id = entry.id,
		name = entry.name,
		speed = entry.speed or 0,
		endurance = entry.endurance or 0,
		vmax = RaceSim.topSpeed(entry.speed),
		staminaMax = RaceSim.stamina(entry.endurance),
		stamina = RaceSim.stamina(entry.endurance),
		distance = 0,
		velocity = 0,
		finishedAt = nil,
	}
end

function RaceSim.start(entries, trackId)
	local track = RaceSim.track(trackId) or RaceSim.Tracks[1]
	local state = { track = track, clock = 0, runners = {}, order = {} }
	for _, entry in ipairs(entries) do
		table.insert(state.runners, newRunner(entry))
	end
	return state
end

--[[
	Advance the race by `dt` seconds. Returns true once everyone is home.

	CALLED WITH A REAL FRAME DELTA, not a fixed tick, so the race runs at the
	speed of the world it is being watched in. The model is a plain Euler step
	and does drift slightly with frame time -- irrelevant at the scale of a
	race, and the alternative (accumulating a fixed timestep) would decouple
	what is simulated from what is drawn, which is the thing this module exists
	to avoid.
]]
function RaceSim.step(state, dt)
	local track = state.track
	state.clock += dt

	local done = true
	for _, runner in ipairs(state.runners) do
		if runner.finishedAt then
			continue
		end
		done = false

		--[[ Fresh runs at vmax; spent runs at V_FLOOR; in between it slides.
		     This is the "dropoff" -- Endurance does not make you faster, it
		     moves this curve to the right. ]]
		local left = math.max(runner.stamina, 0) / runner.staminaMax
		runner.velocity = RaceSim.V_FLOOR + (runner.vmax - RaceSim.V_FLOOR) * left

		local cost = (runner.velocity / RaceSim.V_REF) ^ 2 * RaceSim.DRAIN * track.drain
		runner.stamina -= cost * dt
		runner.distance += runner.velocity * dt

		if runner.distance >= track.length then
			runner.distance = track.length
			runner.finishedAt = state.clock
			table.insert(state.order, runner)
		end
	end
	return done
end

--[[
	Run a whole race with no world attached and hand back the finishing times.
	The panel uses this to quote what a split WOULD do before it is committed --
	the same code the live race steps through, so the estimate cannot disagree
	with the result.
]]
function RaceSim.predict(speed, endurance, trackId)
	local state = RaceSim.start({ { id = "x", speed = speed, endurance = endurance } }, trackId)
	local guard = 0
	while not RaceSim.step(state, 0.05) do
		guard += 1
		if guard > 20000 then
			break -- a runner that cannot finish is a tuning bug, not a hang
		end
	end
	return state.runners[1].finishedAt or math.huge
end

--[[
	The split that finishes this track fastest, for a given pool.

	Brute force over the whole pool, which is 41 simulations at most and runs in
	well under a frame. Worth having in the shared module rather than in a
	tool: it is how the AI opponents are built, and an opponent whose split came
	from a different formula than the one the player is solving against would be
	solving a different puzzle.
]]
function RaceSim.bestSplit(pool, trackId)
	local bestSpeed, bestTime = 0, math.huge
	for speed = 0, pool do
		local time = RaceSim.predict(speed, pool - speed, trackId)
		if time < bestTime then
			bestSpeed, bestTime = speed, time
		end
	end
	return bestSpeed, pool - bestSpeed, bestTime
end

--[[
	THE FIELD YOU RACE AGAINST.

	`style` is how an opponent spends its pool, and it is the thing the player
	is meant to READ. Only "optimal" solves the track it is standing on; the
	other two spend the same way whatever the track, which is what makes them
	beatable on the right ground and brutal on the wrong one -- Bolt wins The
	Dash comfortably and is still running when you have showered after The Haul.

	Pool is the difficulty dial and it is honest: below an opponent's pool there
	is no split that beats their time, so an early player loses to the last one
	no matter how cleverly they allocate. See RaceSim.bestSplit.
]]
RaceSim.Opponents = {
	{ id = "rookie", name = "Scuffed Larry", pool = 12, style = "optimal",
		tell = "runs the track the way the track wants" },
	{ id = "bolt", name = "Bolt", pool = 20, style = "speed",
		tell = "all legs, no lungs -- goes out hard every time" },
	{ id = "grind", name = "Grind", pool = 20, style = "endurance",
		tell = "never tires, never quick" },
	{ id = "ace", name = "The Ace", pool = 26, style = "optimal",
		tell = "reads the track as well as you do" },
	{ id = "boss", name = "???", pool = 34, style = "optimal",
		tell = "not yet" },
}
RaceSim.OpponentById = {}
for index, o in ipairs(RaceSim.Opponents) do
	o.index = index
	RaceSim.OpponentById[o.id] = o
end

--[[ What this opponent brings to this particular track. A style that ignores
     the track still has to spend its whole pool, so the lopsided ones are not
     weaker -- they are wrong in a way you can exploit. ]]
function RaceSim.splitFor(opponent, trackId)
	local pool = opponent.pool
	if opponent.style == "speed" then
		local speed = math.floor(pool * 0.8 + 0.5)
		return speed, pool - speed
	elseif opponent.style == "endurance" then
		local endurance = math.floor(pool * 0.8 + 0.5)
		return pool - endurance, endurance
	end
	local speed, endurance = RaceSim.bestSplit(pool, trackId)
	return speed, endurance
end

return RaceSim
