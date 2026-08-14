--[[
	Auction
	How a brainrot turns into a price, and how a bid has to beat the last one.

	Server and client both require this for the same reason Economy exists: the
	number on the bid button and the number the server will actually accept can
	never drift apart. The client uses it to grey out a bid it knows will be
	rejected; the server uses it as the truth.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)

local Auction = {}

--[[
	The house's standing offer: a flat number of seconds of the brainrot's own
	rent. Linear in income, so the keep-vs-sell crossover lands in the same
	place for a Common and for a Secret -- see the Config note.
]]
function Auction.floorPrice(charId, variantId)
	local income = Economy.incomeOf(charId, variantId)
	return math.max(1, math.floor(income * Config.AuctionFloorSeconds))
end

--[[
	Smallest bid that beats `current`.

	The +1 matters: at low prices a 10% step can floor back onto the current
	bid, and a "minimum next bid" equal to the standing bid would let two
	players trade the lot back and forth forever without the price moving.
]]
function Auction.minNextBid(current)
	return math.floor(current * (1 + Config.AuctionBidStep)) + 1
end

--[[ Seconds left, clamped at zero so the UI never renders a negative clock. ]]
function Auction.timeLeft(endsAt, now)
	return math.max(0, endsAt - (now or os.clock()))
end

return Auction
