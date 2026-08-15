--[[
	Plinko
	The board, and the coin that decides each bounce.

	THE BOUNCES ARE ROLLED, THE FALL IS REAL. At every peg row the server flips
	a fair coin and the ball is carried that way; sixteen flips later it is
	wherever they sent it. Nothing knows the outcome in advance -- it emerges
	from the flips, which is exactly what a Galton board is supposed to do and
	only approximately does.

	This is NOT the wheel's trick. The wheel picks a result and animates toward
	it, because a tweened wheel is convincing and a steered ball is not. Here
	there is no result to pick.

	WHY NOT LET THE PHYSICS DECIDE. Because it doesn't decide anything you can
	state. The physics board was measured at 19% in the middle three bins and
	47% in the two outer ones -- an inverted bowl paying 849%, because a real
	ball carries sideways momentum from one row into the next and walks to a
	wall. Rolling the bounces gives exact odds instead of measured ones, and
	those odds cannot drift when Roblox next changes its solver.

	SIXTEEN ROWS, NINE BINS, AND THE WALLS MATTER. Sixteen coin flips of half a
	bin each would spread over seventeen bins; the board is nine wide, so the
	tail is clipped by the side walls and piles into the outer bins. That is
	not a flaw to correct -- it is what puts 3.8% in each edge bin instead of a
	binomial's 0.0015%, which is what makes the edges a prize worth aiming at
	rather than a rounding error.
]]

local Plinko = {}

Plinko.ROWS = 16
Plinko.BINS = 9

--[[
	Per bin, outward from the left edge. Chosen against the exact odds below,
	not measured off a sample:

		bin odds     3.6  6.7  12.4  17.5  19.6  17.5  12.4  6.7  3.6  (%)
		middle three 54.6%     each edge 3.6%
		return to player   84.0%
		fragment chance    7.26% per drop (the two edge bins)
		a seal (5 fragments) takes about 69 drops -- $31M staked, $4.97M net

	69 drops is roughly ten minutes of dropping balls. Half that would make the
	island a formality; double would make it a chore. And the staked figure is
	the one to ignore: winnings are re-staked, so the machine only keeps its
	edge, and $4.97M is what actually gates the island.
]]
Plinko.Bins = {
	{ pay = 4.7, fragment = true },
	{ pay = 1.5, fragment = false },
	{ pay = 0.7, fragment = false },
	{ pay = 0.3, fragment = false },
	{ pay = 0.1, fragment = false }, -- the middle, and the likeliest landing
	{ pay = 0.3, fragment = false },
	{ pay = 0.7, fragment = false },
	{ pay = 1.5, fragment = false },
	{ pay = 4.7, fragment = true },
}

--[[
	Exact bin odds, by walking the distribution forward one row at a time and
	letting the walls absorb whatever runs past the edge.

	Computed rather than written down, so it can never disagree with ROWS, and
	so the payout table can be checked against the real numbers at any time.
]]
function Plinko.odds()
	local span = Plinko.BINS - 1 -- half-steps either side of centre
	local pos = { [0] = 1 }
	for _ = 1, Plinko.ROWS do
		local nxt = {}
		for p, w in pairs(pos) do
			for _, step in ipairs({ -1, 1 }) do
				-- the wall: a ball that would leave the board stays in the
				-- outer bin rather than vanishing
				local to = math.clamp(p + step, -span, span)
				nxt[to] = (nxt[to] or 0) + w * 0.5
			end
		end
		pos = nxt
	end

	local out = {}
	for i = 1, Plinko.BINS do
		out[i] = 0
	end
	for p, w in pairs(pos) do
		local index = math.clamp(math.floor(p / 2 + 0.5) + (Plinko.BINS + 1) / 2,
			1, Plinko.BINS)
		out[index] += w
	end
	return out
end

--[[
	One drop. Returns the sequence of bounces and the bin they arrive at, so
	the ball can be carried along the path it actually rolled.

	Half-steps in board units: each flip moves the ball half a bin, and the
	clamp is the side wall.
]]
function Plinko.roll(rng)
	local span = Plinko.BINS - 1
	local path, at = {}, 0
	for i = 1, Plinko.ROWS do
		local step = rng:NextInteger(0, 1) == 1 and 1 or -1
		local to = math.clamp(at + step, -span, span)
		path[i] = to - at -- 0 when the wall refused the step
		at = to
	end
	local bin = math.clamp(math.floor(at / 2 + 0.5) + (Plinko.BINS + 1) / 2,
		1, Plinko.BINS)
	return path, bin, at
end

--[[ The two numbers the UI has to be able to state honestly. ]]
function Plinko.summary()
	local odds = Plinko.odds()
	local rtp, fragment = 0, 0
	for i, bin in ipairs(Plinko.Bins) do
		rtp += odds[i] * bin.pay
		if bin.fragment then
			fragment += odds[i]
		end
	end
	return rtp, fragment
end

return Plinko
