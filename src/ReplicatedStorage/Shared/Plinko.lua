--[[
	Plinko
	The board, shared so the machine you watch and the payout you get are built
	from one table.

	THE ODDS ARE NOT A DESIGN CHOICE. A ball falling through eight rows of pegs
	is a binomial walk, so the bin chances fall out of the row count and cannot
	be argued with: 0.39% at each edge, 27.3% up the middle. What IS chosen is
	the payout on each bin and which bins carry a seal fragment.

	UNLIKE THE WHEEL, THIS ONE IS HONEST. The wheel decides the outcome on the
	server and animates a spin toward it, because steering a tweened wheel to a
	known angle is convincing and steering a physics ball is not. Plinko does
	not need the lie -- a ball dropped through pegs lands where it lands, the
	server reads the bin, and that IS the result. The server simulates it and
	owns the ball, so nothing on a client can lean on it.

	The payout curve is symmetric and steep at the edges. That shape is what
	makes people aim for the outside and what makes a centre landing feel like
	a near miss rather than simply a small win.
]]

local Plinko = {}

Plinko.ROWS = 8
Plinko.BINS = Plinko.ROWS + 1

--[[
	Per bin, outward from the left edge. Modelled in tools/plinko.py before any
	of it was built:

		return to player   85.2%   (house edge 14.8%)
		fragment chance    7.03% per drop
		a seal (5 fragments) takes about 71 drops

	That last number is the one to watch when retuning. 71 drops is roughly ten
	minutes of dropping balls, which is a chapter; half that would make the
	island a formality and double would make it a chore.
]]
Plinko.Bins = {
	{ pay = 12.0, fragment = true },
	{ pay = 3.2, fragment = true },
	{ pay = 1.3, fragment = false },
	{ pay = 0.5, fragment = false },
	{ pay = 0.2, fragment = false }, -- the middle, and the most likely landing
	{ pay = 0.5, fragment = false },
	{ pay = 1.3, fragment = false },
	{ pay = 3.2, fragment = true },
	{ pay = 12.0, fragment = true },
}

local function comb(n, k)
	local r = 1
	for i = 1, k do
		r = r * (n - i + 1) / i
	end
	return r
end

--[[ Chance of landing in each bin, straight from the binomial. Computed rather
     than written down, so it can never disagree with the row count. ]]
function Plinko.odds()
	local total = 2 ^ Plinko.ROWS
	local out = {}
	for i = 0, Plinko.ROWS do
		out[i + 1] = comb(Plinko.ROWS, i) / total
	end
	return out
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
