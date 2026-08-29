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
--[[
	SEVENTEEN BINS, WHICH IS ROWS + 1, AND THAT IS NOT A STYLE CHOICE.

	It was nine, and nine is what forced the old payout table to top out at
	4.7x. Sixteen coin flips of half a bin each spread over seventeen bins; on
	a nine-wide board the tail is clipped and piles into the outer bins, which
	put 3.6% in each edge. An edge you hit one drop in twenty-eight cannot pay
	1000x -- at those odds the two edges alone would return 7200% of stake.

	Widening the board to seventeen lets the distribution finish. The edges
	become 0.0015% each, which is the real binomial, and a 1000x prize becomes
	something you see about once in thirty-three thousand drops. That is what
	makes the headline number payable at all.
]]
Plinko.BINS = 17

--[[
	Per bin, outward from the left edge.

	THE SHAPE IS THE STANDARD HIGH-RISK LADDER -- 1000, 130, 26, 9, 4, 2 and
	then a flat floor across the middle. Checked against the published table it
	comes from: with a 0.2x floor this geometry returns 98.98%, against their
	stated 99%, so the odds model below is sound.

	THE FLOOR IS 0.1x, NOT 0.2x, and that single number is the machine's whole
	edge. The outer six pay 83.2% of stake between them before the middle pays
	anything, so the floor is the only free parameter left:

		floor 0.20x  ->  98.98% back to player   (a 1% edge; barely a sink)
		floor 0.10x  ->  91.08% back to player   (an 8.9% edge)
		floor 0.05x  ->  87.13% back to player   (a 12.9% edge)

	0.1x keeps this a money sink rather than a break-even toy, while still
	being a visible improvement on the 84% it returned before.

	FRAGMENTS MOVED, AND THEY HAD TO. They used to come from the two edge bins,
	which on the old nine-wide board were 3.6% each -- 7.26% a drop, a seal in
	about 69. Those same bins are now 0.0015%, and leaving the award there
	would have put the Plinko seal 163,840 drops away and quietly walled off
	the racing island for good.

	So the rule is now "any bin paying 4x or better", which is 7.68% a drop and
	a seal in about 65. Near enough to the 69 it was that the progression is
	untouched, and a rule a player can actually state.
]]
local FLOOR = 0.1

Plinko.Bins = {
	{ pay = 1000, fragment = true },
	{ pay = 130, fragment = true },
	{ pay = 26, fragment = true },
	{ pay = 9, fragment = true },
	{ pay = 4, fragment = true },
	{ pay = 2, fragment = false },
	{ pay = FLOOR, fragment = false },
	{ pay = FLOOR, fragment = false },
	{ pay = FLOOR, fragment = false }, -- the middle, and the likeliest landing
	{ pay = FLOOR, fragment = false },
	{ pay = FLOOR, fragment = false },
	{ pay = 2, fragment = false },
	{ pay = 4, fragment = true },
	{ pay = 9, fragment = true },
	{ pay = 26, fragment = true },
	{ pay = 130, fragment = true },
	{ pay = 1000, fragment = true },
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
