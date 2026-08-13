--[[
	MinesMath
	Standard Mines payout curve. Shared so the client can PREVIEW the next
	multiplier without asking the server, while the server stays the only thing
	that actually pays out.

		multiplier(m, k) = (1 - edge) * C(25, k) / C(25 - m, k)

	which is just "one over the probability you survived this far", shaved by
	the house edge.
]]

local Config = require(script.Parent.Config)

local MinesMath = {}

local function nCr(n, r)
	if r < 0 or r > n then
		return 0
	end
	local result = 1
	for i = 1, r do
		result = result * (n - r + i) / i
	end
	return result
end

MinesMath.nCr = nCr

--[[ Payout multiplier after `picks` successful reveals with `mines` on the board. ]]
function MinesMath.multiplier(mines, picks)
	if picks <= 0 then
		return 1
	end
	local safe = Config.TileCount - mines
	if picks > safe then
		return 0
	end
	return (1 - Config.HouseEdge) * nCr(Config.TileCount, picks) / nCr(safe, picks)
end

--[[ Odds the NEXT click is safe, given `picks` already revealed. ]]
function MinesMath.nextTileSafeChance(mines, picks)
	local remaining = Config.TileCount - picks
	if remaining <= 0 then
		return 0
	end
	return (remaining - mines) / remaining
end

--[[ How many safe tiles exist in total -- revealing them all is an auto cash-out. ]]
function MinesMath.safeTileCount(mines)
	return Config.TileCount - mines
end

--[[
	Build a shuffled board: an array of TileCount booleans where true == mine.
	Generated up-front at round start, never "decided" on click, so the server
	has no opportunity to rig a reveal after seeing what you picked.
]]
function MinesMath.generateBoard(mines, rng)
	local board = table.create(Config.TileCount, false)
	for i = 1, mines do
		board[i] = true
	end
	-- Fisher-Yates
	for i = Config.TileCount, 2, -1 do
		local j = rng:NextInteger(1, i)
		board[i], board[j] = board[j], board[i]
	end
	return board
end

return MinesMath
