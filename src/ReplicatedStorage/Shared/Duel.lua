--[[
	Duel
	The rules of a staked fight, with no state and no side effects, so the
	server and the client can both answer "is this wager legal?" and never
	disagree about it.

	TWO KINDS OF FIGHT, and the difference is consent.

	  street  -- you hit someone. Nothing is at stake, nothing is won, and the
	             other player owes you no answer. This exists so that throwing
	             a punch is not a contract.
	  duel    -- both players said yes, both put a brainrot up, and the arena
	             takes them. Only a duel can move anything between inventories.

	A STREET FIGHT BECOMES A DUEL ONLY BY BEING ANSWERED. The offer is raised
	when the person you hit hits you BACK -- not when you hit them. Swinging at
	someone who ignores you is a street fight forever, which is the point: you
	cannot drag an unwilling player into a wager by attacking them, and the
	prompt only appears once both people have chosen to be in a fight.

	THERE IS NO MATCHING RULE, and that is deliberate.

	This enforced a tier ladder for a while -- each tier worth three of the one
	below, so a Mythic had to be answered by a Mythic or three Legendary, and
	the window refused to close until the totals were equal. It is gone.

	Players price their own trades. Every trading game works this way and the
	people playing them are better at valuing a brainrot than a table of
	exponents is: the ladder could not see variants, rebirth multipliers, or
	the fact that somebody simply wants THAT one. A rule that says no to a
	trade both sides are happy with is a rule that is wrong.

	What replaces it is INFORMATION. Both grids are visible while they are
	assembled, every brainrot shows its income, and each side totals up -- so
	the judgement the ladder used to make is handed to the two people making
	the wager, with the numbers in front of them.

	The only things the server still refuses: an empty side, more than
	MaxStakeItems, and a brainrot the offerer does not actually own.
]]

local Rarity = require(script.Parent.Rarity)

local Duel = {}

--[[ Thirty seconds, and it is a hard stop rather than a fight to the death.
     A duel that ends when someone dies would be decided by who spawned with
     more health left over from whatever they were doing beforehand; a clock
     makes both players start from the same place and makes the spectator
     window a known length. ]]
Duel.Seconds = 30

--[[ How long the two of them have to agree, and then to settle on a wager,
     before the whole thing is dropped. Someone who walks away mid-negotiation
     must not leave the other player stuck in a menu. ]]
Duel.OfferSeconds = 20
Duel.WagerSeconds = 60

--[[ Spectator bets close BEFORE the fight ends, not when it ends. Betting on
     a fight you can see the last second of is not betting. ]]
Duel.BetCloseAt = 10 -- seconds remaining when the book shuts

Duel.MinSpectatorBet = 1000

--[[ Nine, because the trade window is a three by three grid and a cap that
     did not match it would leave slots that exist and cannot be used.

     There has to be a cap at all: without one a player could answer a Common
     with 243 Commons, which is legal by value and is really a way to make the
     other person read a list. ]]
Duel.MaxStakeItems = 9

--[[ A one-line description of a stake, for prompts and the result toast. ]]
function Duel.describe(tiers)
	local counts, order = {}, {}
	for _, tier in ipairs(tiers or {}) do
		if not counts[tier] then
			table.insert(order, tier)
		end
		counts[tier] = (counts[tier] or 0) + 1
	end
	table.sort(order, function(a, b)
		return Rarity.get(a).index > Rarity.get(b).index
	end)
	local parts = {}
	for _, tier in ipairs(order) do
		table.insert(parts, ("%dx %s"):format(counts[tier], tier))
	end
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

--[[
	WHO WON.

	More health takes it. Equal health is a DRAW and a draw moves nothing --
	both stakes go home and every spectator bet is refunded. Picking a winner
	off a tiebreak (who hit first, lower userId) would decide a wager on
	something neither player could see, and a duel whose result you cannot
	explain from the screen is worse than one with no result.

	Health is compared as a fraction of MaxHealth, not in absolute points, so
	a future upgrade that raises someone's health pool cannot also make them
	win ties.
]]
function Duel.winner(aHealth, aMax, bHealth, bMax)
	local a = (aMax or 0) > 0 and (aHealth / aMax) or 0
	local b = (bMax or 0) > 0 and (bHealth / bMax) or 0
	if math.abs(a - b) < 1e-4 then
		return nil -- draw
	end
	return a > b and "a" or "b"
end

--[[
	Spectator payouts, parimutuel: the losing side's money is split among the
	winning side in proportion to what each of them staked.

	NOT fixed odds. A house that offers 2x on a coin flip it cannot price is a
	house that loses money to anyone who can read the two players' upgrades;
	a pool pays out exactly what came in, so the game can never be drained by
	a bettor who is simply better informed than it is.

	Returns [userId] = payout, INCLUDING the bettor's own stake back. A winning
	bettor who staked S out of a winning pool W, against a losing pool L, gets
	S + S/W*L. If nobody backed the loser there is nothing to share and
	everyone gets their own money back, which is correct -- a market with one
	side is not a market.
]]
function Duel.settleBets(bets, winnerKey)
	local payouts = {}
	if not winnerKey then -- draw: everyone is refunded
		for userId, bet in pairs(bets) do
			payouts[userId] = bet.amount
		end
		return payouts
	end

	local winPool, losePool = 0, 0
	for _, bet in pairs(bets) do
		if bet.on == winnerKey then
			winPool += bet.amount
		else
			losePool += bet.amount
		end
	end

	for userId, bet in pairs(bets) do
		if bet.on == winnerKey then
			--[[ Integer maths on the share, so the pool can never pay out more
			     than it took in through rounding. The remainder stays unpaid
			     rather than being invented. ]]
			local share = winPool > 0 and math.floor(bet.amount / winPool * losePool) or 0
			payouts[userId] = bet.amount + share
		else
			payouts[userId] = 0
		end
	end
	return payouts
end

return Duel
