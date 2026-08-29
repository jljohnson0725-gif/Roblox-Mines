--[[
	Wheel
	The segment layout, shared so the face you see and the result the server
	rolls are built from one table.

	THE WHEEL IS NOT THE RANDOMISER. The server picks an outcome and then tells
	the client which segment to land on; the spin is an animation of a decision
	already made. That ordering is what makes it honest, and it is also why this
	is a wheel rather than the plinko board -- a wheel can be tweened to a known
	angle convincingly, whereas steering a physics ball into a chosen slot means
	faking the physics anyway.

	Segments alternate rather than sitting in four solid blocks, so the pointer
	passing BUST-SECRET-BUST-SECRET reads as a real gamble instead of a pie
	chart. Odds are unchanged by the arrangement: each outcome's share of the
	face equals its probability.
]]

local Shared = script.Parent
local Config = require(Shared.Config)

local Wheel = {}

--[[
	100, so the face cannot misreport the odds.

	8 / 15 / 30 / 47 share no common factor, so 100 is the only wedge count that
	represents all four exactly. At 20 wedges the 8% Secret rounds up to two
	wedges and the wheel would show 10% -- a player who counts the face would be
	reading a different game to the one the server is running, which is not a
	thing to be casual about in a gambling machine.

	100 thin wedges also just looks like a carnival wheel, which helps.
]]
Wheel.SEGMENTS = 100

--[[
	Build the face: SEGMENTS wedges, each assigned an outcome, with each
	outcome's wedge count proportional to its chance.

	Largest-remainder allocation, so the counts always total SEGMENTS exactly --
	rounding each share independently would leave a gap or an overlap, and a
	wheel with a missing wedge is the kind of thing nobody notices until a
	player lands on it.
]]
--[[
	THE ODDS ARE A FUNCTION OF THE STAKE NOW, not a constant.

	Secret rises linearly with what you put in: nothing at nothing, and
	WheelSecretMaxChance at WheelSecretCapStake. Everything else keeps its
	share of what is left, in the same ratio Config.WheelOdds states -- so the
	retry/cash/bust balance is unchanged and only the Secret slice grows.

	LINEAR RATHER THAN A CURVE, and the reason is the one number a curve gets
	wrong. Under a linear ramp the expected money spent per Secret is constant
	at WheelSecretCapStake / WheelSecretMaxChance -- $1.2B whatever you stake.
	The dial buys VARIANCE, not value: two spins of 600M or eight hundred of
	1.5M, same expected cost. A square-root ramp instead makes the minimum
	stake twenty times cheaper per Secret than the maximum, which turns "bet
	more for a better chance" into a trap for anyone who does not do the
	arithmetic.
]]
function Wheel.oddsFor(stake)
	local p = math.clamp((stake or 0) / Config.WheelSecretCapStake, 0, 1)
		* Config.WheelSecretMaxChance

	--[[ The rest keep their relative proportions. Taken from the table rather
	     than hardcoded, so retuning the bust/cash balance there still works. ]]
	local rest = 0
	for _, outcome in ipairs(Config.WheelOdds) do
		if outcome.id ~= "secret" then
			rest += outcome.chance
		end
	end

	local out = {}
	for _, outcome in ipairs(Config.WheelOdds) do
		local chance = outcome.id == "secret" and p
			or (rest > 0 and outcome.chance / rest * (1 - p) or 0)
		table.insert(out, { id = outcome.id, chance = chance, label = outcome.label })
	end
	return out
end

local function buildFace(odds)
	local counts, order, used = {}, {}, 0
	for _, outcome in ipairs(odds) do
		local exact = outcome.chance * Wheel.SEGMENTS
		local whole = math.floor(exact)
		counts[outcome.id] = whole
		used += whole
		table.insert(order, { id = outcome.id, remainder = exact - whole })
	end

	table.sort(order, function(a, b)
		return a.remainder > b.remainder
	end)
	local i = 1
	while used < Wheel.SEGMENTS do
		local id = order[i].id
		counts[id] = counts[id] + 1
		used += 1
		i = i % #order + 1
	end

	--[[
		Deal the wedges out in RUNS, not one at a time, so the face reads as a
		handful of wide arcs rather than a hundred stripes.

		The chunk sizes are chosen to land on TWELVE arcs. One wedge at a time
		gave a smear of colour; 5/3/2/1 gave about thirty-six, which is more than
		a wheel can be lettered with -- the labels sat on top of each other.
		Twelve is what a real prize wheel has, and it divides the exact wedge
		counts cleanly: secret 8 -> 2x4, retry 15 -> 3x5, cash 30 -> 3x10,
		nothing 47 -> 12+12+12+11.

		The COUNTS are untouched throughout, so the odds the face states are
		still exact. Only the grouping changes.
	]]
	local RUN = { nothing = 12, cash = 10, retry = 5, secret = 4 }

	local pools = {}
	for _, outcome in ipairs(odds) do
		table.insert(pools, { id = outcome.id, left = counts[outcome.id] })
	end
	-- most common first, so a cycle opens on a wide dark band
	table.sort(pools, function(a, b)
		return a.left > b.left
	end)

	local face, cursor = {}, 1
	while #face < Wheel.SEGMENTS do
		local pool = pools[cursor]
		local take = math.min(RUN[pool.id] or 1, pool.left, Wheel.SEGMENTS - #face)
		for _ = 1, take do
			table.insert(face, pool.id)
		end
		pool.left -= take
		cursor = cursor % #pools + 1
	end
	return face
end

function Wheel.faceFor(stake)
	return buildFace(Wheel.oddsFor(stake))
end

--[[
	THE PHYSICAL FACE IS A PROP, and this is the one place the old rule had to
	give. It used to be that the face could not misreport the odds -- a player
	who counted wedges had to be reading the same game the server ran. Odds are
	per-stake now, so no single face can be right for everyone, and the wheel is
	a shared object: two people watching the same spin would need different
	faces.

	So the resolution is the other way round. The face is built from the base
	ratios in Config.WheelOdds -- a representative carnival wheel with all four
	outcomes on it -- and the honest number lives in the panel, where it is
	quoted exactly for the stake you dialled in.

	IT MUST BE BUILT FROM THE BASE RATIOS, not from oddsFor(minimum). At the
	minimum stake the Secret share is 0.125%, which is an eighth of one wedge
	out of a hundred and rounds to NONE -- and segmentsFor would then hand back
	an empty list for the outcome the server had just rolled, crashing the spin
	on the one result anybody cares about.
]]
Wheel.FACE = buildFace(Config.WheelOdds)

--[[ Every wedge index showing this outcome, so the server can pick one to land
     on and the spin looks different each time it repeats a result. ]]
function Wheel.segmentsFor(outcomeId, face)
	local list = {}
	for index, id in ipairs(face or Wheel.FACE) do
		if id == outcomeId then
			table.insert(list, index)
		end
	end
	return list
end

--[[
	The face as contiguous ARCS rather than individual wedges.

	buildFace deals in runs, so a stretch of five BUST wedges is one visible arc.
	This is what lets the wheel carry words: one label per arc, at its middle,
	instead of a hundred wedges nobody can read.
]]
function Wheel.runs(face)
	face = face or Wheel.FACE
	local runs, i = {}, 1
	while i <= #face do
		local id = face[i]
		local count = 0
		while face[i + count] == id do
			count += 1
		end
		local step = 360 / Wheel.SEGMENTS
		table.insert(runs, {
			id = id,
			first = i,
			count = count,
			sweep = count * step,
			-- middle of the arc, in the same clockwise-from-the-pointer frame
			-- angleOf uses
			mid = Wheel.angleOf(i) + (count - 1) * step / 2,
		})
		i += count
	end
	return runs
end

function Wheel.outcome(id)
	for _, outcome in ipairs(Config.WheelOdds) do
		if outcome.id == id then
			return outcome
		end
	end
	return nil
end

--[[ Centre angle of a wedge, in degrees clockwise from the pointer at 12
     o'clock. Wedge 1 is centred on the pointer. ]]
function Wheel.angleOf(segmentIndex)
	return (segmentIndex - 1) * (360 / Wheel.SEGMENTS)
end

--[[
	The odds a player actually experiences.

	A retry re-rolls rather than resolving, so it is not an outcome -- quoting
	the raw 8% would understate the real chance of a Secret. This is what the UI
	shows.
]]
function Wheel.effectiveOdds(stake)
	local odds = Wheel.oddsFor(stake or Config.WheelMinStake)
	local retry = 0
	for _, outcome in ipairs(odds) do
		if outcome.id == "retry" then
			retry = outcome.chance
		end
	end
	local live = 1 - retry
	local out = {}
	for _, outcome in ipairs(odds) do
		if outcome.id ~= "retry" then
			out[outcome.id] = live > 0 and outcome.chance / live or 0
		end
	end
	return out, retry
end

return Wheel
