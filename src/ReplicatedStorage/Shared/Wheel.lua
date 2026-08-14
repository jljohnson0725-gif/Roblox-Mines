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
local function buildFace()
	local counts, order, used = {}, {}, 0
	for _, outcome in ipairs(Config.WheelOdds) do
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

	--[[ Deal the wedges out round-robin from the rarest outcome to the most
	     common, which naturally scatters the good ones instead of clustering
	     them on one side of the face. ]]
	local pools = {}
	for _, outcome in ipairs(Config.WheelOdds) do
		table.insert(pools, { id = outcome.id, left = counts[outcome.id] })
	end
	table.sort(pools, function(a, b)
		return a.left < b.left
	end)

	local face, cursor = {}, 1
	while #face < Wheel.SEGMENTS do
		local pool = pools[cursor]
		if pool.left > 0 then
			table.insert(face, pool.id)
			pool.left -= 1
		end
		cursor = cursor % #pools + 1
	end
	return face
end

Wheel.FACE = buildFace()

--[[ Every wedge index showing this outcome, so the server can pick one to land
     on and the spin looks different each time it repeats a result. ]]
function Wheel.segmentsFor(outcomeId)
	local list = {}
	for index, id in ipairs(Wheel.FACE) do
		if id == outcomeId then
			table.insert(list, index)
		end
	end
	return list
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
function Wheel.effectiveOdds()
	local retry = 0
	for _, outcome in ipairs(Config.WheelOdds) do
		if outcome.id == "retry" then
			retry = outcome.chance
		end
	end
	local live = 1 - retry
	local out = {}
	for _, outcome in ipairs(Config.WheelOdds) do
		if outcome.id ~= "retry" then
			out[outcome.id] = live > 0 and outcome.chance / live or 0
		end
	end
	return out, retry
end

return Wheel
