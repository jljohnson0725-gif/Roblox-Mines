--[[
	Plinko
	The board, and the coin that decides each bounce.

	THE BOUNCES ARE ROLLED, THE FALL IS REAL. At every peg row the server flips
	a fair coin and the ball is carried that way; fourteen flips later it is
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

	THE WALLS NO LONGER MATTER, AND THAT IS THE POINT. The board used to be
	narrower than its own distribution, so the tail was clipped and piled into
	the outer bins -- which is what once put 3.8% in each edge instead of a
	binomial's rounding error. BINS is now ROWS + 1, so the spread finishes on
	its own and `odds` below is the exact binomial. The clamp in there is dead
	code kept honest: it costs nothing and it means the table cannot lie if the
	board is ever narrowed again.
]]

local Plinko = {}

--[[
	FOURTEEN ROWS, DOWN FROM SIXTEEN, AND THE ROW COUNT IS THE REAL DIAL.

	How often a drop loses is not a free parameter -- it is quantised by the
	board, because the losing bins have to be the middle ones (payouts must
	rise outward or the board reads as broken). The centre three bins take:

		12 rows -> 61.2% of drops      16 rows -> 54.6%
		14 rows -> 57.6%               18 rows -> 51.9%

	The target was "lose on 60%", which no board hits exactly. 12 and 14 rows
	are the two either side of it. 14 won on the seal: fragments come from the
	outer four bins, which is 5.7% of drops here, against 3.9% at 12 rows. The
	Plinko seal gates the racing island, and halving its drop rate would wall
	that island off -- the same failure this file already records once.

	AND IT MUST BE EVEN. Each row moves the ball one half-bin, so after an odd
	number of rows the ball's final column is odd -- and PlinkoService steers
	to `column * W/2` while the pocket centre is `round(column/2) * W`. Those
	two agree exactly when the column is even and sit a full half-pocket apart
	when it is odd, so an odd ROWS parks every single ball on a divider. The
	payout would still be right (it comes from the roll, not the landing) and
	the machine would look broken on every drop, which is worse.
]]
Plinko.ROWS = 14
--[[ ROWS + 1, so the distribution finishes inside the board rather than
     piling against the side walls. Every other number in this file assumes
     it; change one and change both. ]]
Plinko.BINS = 15

--[[
	Per bin, outward from the left edge.

	THE MACHINE IS NOW BUILT AROUND HOW OFTEN YOU LOSE, not around a headline
	number. The centre three bins are the losing band -- 57.6% of drops -- and
	everything else follows from what is left over.

	AND WHAT IS LEFT OVER IS CONSERVED. That is the whole trade, and it is
	worth stating because it is not obvious:

		lose 79.0% of drops  ->  the average win pays 3.96x   (the old board)
		lose 57.6% of drops  ->  the average win pays 2.09x   (this one)

	Winning twice as often means winning half as much. There is no ladder that
	escapes it -- at 100% back to player, frequency and size are the same
	budget spent two ways. Every "make Plinko more generous" request is really
	a request to move along this line, and the only question is where.

	WHICH IS WHY THE 1000x IS GONE. On a 14-row board the edge bin comes up
	once in 16,384 drops rather than once in 65,536, so a 1000x prize there
	would cost 12 of the 100 points of return on its own and force every other
	bin down toward 1x. 400x costs 5. The prize got smaller and four times
	more reachable at the same time, which is the better end of that trade for
	a machine nobody was ever going to hit the old one on.

	FRAGMENTS ARE PINNED TO THE OUTER FOUR, not to a payout threshold. The
	rule used to be "any bin paying 4x or better", which quietly depended on
	there being a 4x rung -- and this ladder has 3x there instead, which would
	have dropped the seal rate to 1.3% and walled off the racing island. It is
	positional now, so re-pricing a bin can never move it: 5.74% of drops, a
	seal about every 87. That is slower than the 65 it was, and it is the
	closest the board can get -- the next rung inward is 18%, a seal every 28.
]]
local FLOOR = 0.1

Plinko.Bins = {
	{ pay = 400, fragment = true },
	{ pay = 60, fragment = true },
	{ pay = 8, fragment = true },
	{ pay = 3, fragment = true },
	{ pay = 1.8, fragment = false },
	--[[ 1.2x, AND IT HAS TO BE ABOVE 1. This pair takes 12.2% of drops each
	     way -- a quarter of the board -- so it is the single most expensive
	     rung to price. At exactly 1.0 it balanced beautifully and paid your
	     stake back, which is a push, not a win: it would have made the honest
	     headline "you lose on 57.6% and break even on 24.4%", and left only
	     18% of drops actually winning anything. 1.2 costs 5 points of return
	     and buys the sentence "you win money on 42.4% of drops". ]]
	{ pay = 1.2, fragment = false },
	--[[
		NEAR-MISS, not another floor. These two used to pay FLOOR like the
		centre, so the middle of the board was one flat dead zone.

		0.25 IS LOAD-BEARING. This pair takes 36.7% of drops, so every 0.1
		added to it moves the machine's return by about seven points -- at the
		0.5 they were once set to, Plinko paid 114.8% and every drop was
		profitable. Lower this first if the machine ever needs to be a sink.
	]]
	{ pay = 0.25, fragment = false },
	{ pay = FLOOR, fragment = false }, -- the middle, and the likeliest landing
	{ pay = 0.25, fragment = false },
	{ pay = 1.2, fragment = false },
	{ pay = 1.8, fragment = false },
	{ pay = 3, fragment = true },
	{ pay = 8, fragment = true },
	{ pay = 60, fragment = true },
	{ pay = 400, fragment = true },
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
