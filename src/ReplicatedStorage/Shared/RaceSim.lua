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

--[[
	HOW FAST THE WHOLE THING PLAYS, and it is a pure presentation dial.

	Every runner's velocity is in model studs; at PACE 1 the field moves at
	15-24 studs/s, which is a jog and reads as one. This multiplies the clock,
	so every velocity, every gap and every finishing time scales together and
	the ORDER cannot change -- a race at PACE 2.2 is the same race, watched at
	2.2x. The balance below is therefore unaffected by it, which is why the
	optimal splits are quoted without reference to it.

	2.2 puts the field at 34-54 studs/s against a default Roblox walk of 16,
	and leaves the gaps readable: the sprinter still wins The Dash by about a
	second rather than by a frame.
]]
RaceSim.PACE = 2.2

--[[ The pool a runner allocates. Grows as the story progresses, which is what
     makes the last opponent unbeatable until it does not: below his pool there
     is no split that beats his time, so the wall is real rather than scripted. ]]
--[[
	14, not 10, and the number is load-bearing: the first opponent needs 13 to
	beat, so a smaller start is a player who cannot win their first race and has
	nowhere to earn the point. Measured, not chosen.
]]
RaceSim.StartingPool = 14
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
		id = "straight",
		name = "The Straight",
		blurb = "Long enough to punish a pure sprinter",
		length = 340,
		drain = 1.0,
		best = "13 / 9",
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
	--[[
		THE CLOCK COUNTS REAL SECONDS; THE PHYSICS RUNS PACE TIMES FASTER.

		Getting this backwards is subtle and was wrong first time: scaling dt
		before adding it to the clock advances the world faster AND counts the
		faster seconds, so finishedAt still reports 90 for a race that takes 41
		on a stopwatch -- and the panel quotes finishedAt. The clock has to be
		the wall clock, and only the step handed to the integration is scaled.
	]]
	state.clock += dt
	local step = dt * RaceSim.PACE

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
		runner.stamina -= cost * step
		runner.distance += runner.velocity * step

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
	THE FIELD YOU RACE AGAINST, five of them, each standing on their own track.

	THE POOL IS NOT THE DIFFICULTY. Measured, the lowest pool that beats each:

		Scuffed Larry  pool 12, optimal    -> you need 13
		Bolt           pool 18, speed      -> you need 16   BELOW his
		Grind          pool 22, endurance  -> you need 21   BELOW his
		The Ace        pool 28, optimal    -> you need 29
		???            pool 34, optimal    -> you need 35

	The two with a STYLE are beatable by a weaker runner, because they spend
	the same way whatever ground they are on and their own track does not
	quite want it -- Bolt brings 14/4 to a straight that wants 13/9. The two
	that solve their track can only be out-pooled. That is the lesson in the
	order it needs teaching: read the ground first, and only grind when the
	opponent has stopped making mistakes for you.

	`grants` IS THE CEILING THIS OPPONENT CAN RAISE YOU TO, not a reward. Every
	win gives one point while you are under it, so a boss you have outgrown pays
	nothing and the next one is the only way up. The chain was checked end to
	end and has no dead end -- each ceiling clears the next requirement:

		start 14  ->  Larry needs 13, raises you to 18
		          ->  Bolt  needs 16, raises you to 24
		          ->  Grind needs 21, raises you to 30
		          ->  Ace   needs 29, raises you to 36
		          ->  ???   needs 35

	NOBODY IS LOCKED. You may race the last one at 14 and lose, which is the
	story beat -- his tell is "not yet". The wall is real arithmetic, so it does
	not need a door.

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
	{ id = "rookie", name = "Scuffed Larry", pool = 12, style = "optimal", track = "dash",
		grants = 18, tell = "runs the track the way the track wants, badly" },
	{ id = "bolt", name = "Bolt", pool = 18, style = "speed", track = "straight",
		grants = 24, tell = "all legs, no lungs -- goes out hard whatever the ground" },
	{ id = "grind", name = "Grind", pool = 22, style = "endurance", track = "climb",
		grants = 30, tell = "never tires, never quick, never adapts" },
	{ id = "ace", name = "The Ace", pool = 28, style = "optimal", track = "mile",
		grants = 36, tell = "reads the track exactly as well as you do" },
	{ id = "boss", name = "???", pool = 34, style = "optimal", track = "haul",
		grants = 40, tell = "not yet" },
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
