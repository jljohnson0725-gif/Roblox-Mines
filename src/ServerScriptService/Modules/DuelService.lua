--[[
	DuelService
	A street fight that both players agreed to make count.

	THE WHOLE MODULE EXISTS TO GATE ONE ACTION: moving a brainrot from one
	player's inventory to another's. Everything else here -- the offer, the
	wager, the arena, the clock, the book -- is consent-gathering in front of
	that single transfer.

	FOUR PHASES, AND YOU CANNOT SKIP ONE.

	  offer   both players say yes. Either says no and it is over.
	  wager   one side puts a stake up, the other covers it or denies it.
	          Denying clears BOTH stakes and asks again. Either may cancel.
	  fight   arena, thirty seconds, spectators may back a side.
	  done    health decides it, the stake moves, the book settles.

	CANCELLING STOPS AT THE ARENA DOOR. Up to the moment both fighters are
	moved, either can walk away and nothing has happened. After that, no --
	otherwise the player who is losing at second 29 simply leaves, and a wager
	you can withdraw from once you are behind is not a wager. Disconnecting
	mid-fight is a forfeit for the same reason.

	A DEATH ENDS IT THERE AND THEN. The clock is the LONGEST a duel can run,
	not the shortest: knock the other player out at second five and it is over
	at second five.

	That is not only about pacing. Roblox respawns a dead player automatically,
	at full health, a few seconds later -- so a duel that kept running to thirty
	would compare a freshly respawned 100 against the survivor's damaged bar
	and hand the win to the player who DIED. Ending on the death is what makes
	the health comparison mean anything at all.

	BOTH FIGHTERS ARE HEALED ON ENTRY. The result is "who has more health after
	thirty seconds", so starting from different health would decide the stake
	before the first punch -- and would make ambushing someone at 20 health the
	optimal way to play. Full health both sides, and the clock is the contest.

	OWNERSHIP IS CHECKED TWICE. Once when the stake is offered, and again at
	the instant of transfer, because a player can sell, store, place or lose a
	brainrot in the thirty seconds in between. A wager is a promise about an
	item, and the item is what has to be there at the end -- if it is not, the
	duel voids rather than transferring something that no longer exists.

	SPECTATOR MONEY IS TAKEN AT THE BET, NOT AT THE RESULT. A bet you have not
	paid for is free information; taking it up front also means the pool is
	real money that exists, so settling can never pay out of thin air.
]]

local Players = game:GetService("Players")

local Modules = script.Parent
local DataService = require(Modules.DataService)
local PlayerState = require(Modules.PlayerState)
local PlotService = require(Modules.PlotService)
local CombatService = require(Modules.CombatService)
local ArenaService = require(Modules.ArenaService)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Duel = require(Shared.Duel)
local Brainrots = require(Shared.Brainrots)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local DuelService = {}

local duels = {} -- [id] = duel
local byUserId = {} -- [userId] = duel, for both fighters AND nobody else
local nextId = 1

-- ── helpers ─────────────────────────────────────────────────────────────────

local function humanoidOf(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character
end

local function sideOf(duel, player)
	if duel.a == player then
		return "a"
	elseif duel.b == player then
		return "b"
	end
	return nil
end

local function otherOf(duel, player)
	return duel.a == player and duel.b or duel.a
end

--[[
	DataService.findItem RETURNS `item, index`, IN THAT ORDER.

	Worth stating because all three call sites in this module had it the other
	way round and two of them failed silently. `local _, item = findItem(...)`
	binds the INDEX to `item`, so the first thing to touch it dies with
	"attempt to index number with 'charId'" -- which is what a real two-player
	trade window produced the first time a brainrot was put in a slot.

	The third site was payStake, the one function that moves a brainrot between
	two players. It would have called table.remove with a table as the index
	and priced the stake off a number. It never got the chance to run, because
	the window crashed before any duel reached a transfer.
]]
local function tierOfItem(item)
	local char = item and Brainrots.get(item.charId)
	return char and char.tier or nil
end

--[[ The tiers of a list of uids, or nil if any of them is not currently owned
     by this player. Used at both ends of the wager -- see the header. ]]
local function tiersFor(profile, uids)
	local tiers, seen = {}, {}
	for _, uid in ipairs(uids) do
		if seen[uid] then
			return nil, "You cannot stake the same brainrot twice."
		end
		seen[uid] = true
		local item = DataService.findItem(profile, uid)
		if not item then
			return nil, "You do not have that brainrot any more."
		end
		local tier = tierOfItem(item)
		if not tier then
			return nil, "That brainrot cannot be staked."
		end
		table.insert(tiers, tier)
	end
	return tiers
end

-- ── talking to the two of them ──────────────────────────────────────────────

--[[
	One side's offer, as the GRID needs it: a row per staked brainrot rather
	than a sentence describing them.

	Re-resolved from uids on every push instead of being cached, for the same
	reason the transfer re-resolves them: a player can sell or place a
	brainrot while the window is open, and a slot showing something they no
	longer own is a slot they could accept a trade on.
]]
local function stakeRows(player, uids)
	local profile = DataService.get(player)
	if not profile or not uids then
		return {}, 0
	end
	local rows, income = {}, 0
	for _, uid in ipairs(uids) do
		local item = DataService.findItem(profile, uid)
		local tier = item and tierOfItem(item)
		if tier then
			--[[ Income travels with the row rather than being looked up on the
			     client. It is the number both players are judging the trade on
			     now that nothing else scores it, so it comes from the same
			     place the base pays out from and cannot disagree with it. ]]
			local rate = Economy.incomeOf(item.charId, item.variantId)
			table.insert(rows, {
				uid = uid,
				charId = item.charId,
				variantId = item.variantId,
				tier = tier,
				income = rate,
				name = Economy.displayName(item.charId, item.variantId),
			})
			income += rate
		end
	end
	return rows, income
end

local function pushState(duel)
	for _, player in ipairs({ duel.a, duel.b }) do
		local other = otherOf(duel, player)
		local yourRows, yourIncome = stakeRows(player, duel.stakes[player.UserId])
		local theirRows, theirIncome = stakeRows(other, duel.stakes[other.UserId])
		Net.get("DuelState"):FireClient(player, {
			id = duel.id,
			phase = duel.phase,
			you = player.DisplayName,
			opponent = other.DisplayName,
			opponentId = other.UserId,
			youAccepted = duel.accepted[player.UserId] or false,
			theyAccepted = duel.accepted[other.UserId] or false,
			--[[ Both grids and both income totals. The window shows the other
			     side's offer as it is built, so the payload has to carry it --
			     a trade you cannot watch being assembled is one you cannot
			     judge, and with no matching rule left the numbers ARE the
			     judgement. ]]
			yourRows = yourRows,
			theirRows = theirRows,
			yourIncome = yourIncome,
			theirIncome = theirIncome,
			maxItems = Duel.MaxStakeItems,
			endsAt = duel.deadline and (duel.deadline - os.clock()) or nil,
			side = sideOf(duel, player),
		})
	end
end

local function notifyBoth(duel, text, kind)
	PlayerState.notify(duel.a, text, kind)
	PlayerState.notify(duel.b, text, kind)
end

-- ── ending, from anywhere ───────────────────────────────────────────────────

--[[
	Refund every spectator, drop the duel, and put both fighters back.

	Idempotent and unconditional, exactly like MountService's `finish`, and for
	the same reason: every failure path in this module ends here, including
	ones that arrive twice, and a duel that half-closed would leave two players
	locked out of ever duelling again.
]]
--[[ One place that touches profile.stats, so a field added here cannot be
     incremented in one spot and forgotten in another. `or 0` because a save
     written before these existed reconciles on LOAD -- a profile already in
     memory when the server updated would not have them. ]]
local function bump(player, key)
	local profile = DataService.get(player)
	if not profile or type(profile.stats) ~= "table" then
		return
	end
	profile.stats[key] = (profile.stats[key] or 0) + 1
	PlayerState.push(player)
end

local function close(duel, reason, refundBets)
	if duel.closed then
		return
	end
	duel.closed = true

	--[[ Released before anything else can fail. The arena has to come free on
	     every path out of a duel, including the ones that throw -- a stuck
	     flag would lock every future duel out of the only floor there is. ]]
	if duel.heldArena then
		duel.heldArena = false
		ArenaService.busy = false
	end

	--[[ Dropped for the same reason: a Died handler that outlives its duel
	     would try to resolve a fight that has already paid out. ]]
	for _, conn in ipairs(duel.conns or {}) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	duel.conns = nil

	if refundBets then
		for userId, bet in pairs(duel.bets) do
			local better = Players:GetPlayerByUserId(userId)
			local profile = better and DataService.get(better)
			if profile then
				profile.money += bet.amount
				PlayerState.pushMoney(better)
				PlayerState.notify(better, ("Duel voided — %s refunded."):format(
					Format.money(bet.amount)), "info")
			end
		end
	end

	for _, player in ipairs({ duel.a, duel.b }) do
		byUserId[player.UserId] = nil
		local returnTo = duel.returnTo[player.UserId]
		if returnTo and player.Parent then
			local _, character = humanoidOf(player)
			if character then
				pcall(function()
					character:PivotTo(returnTo)
				end)
			end
		end
		if player.Parent then
			Net.get("DuelState"):FireClient(player, { id = duel.id, phase = "closed", reason = reason })
		end
	end

	CombatService.forget(duel.a, duel.b)
	duels[duel.id] = nil

	Net.get("DuelBoard"):FireAllClients({ id = duel.id, phase = "closed" })
end

-- ── phase 1: the offer ──────────────────────────────────────────────────────

--[[
	Raised by CombatService when the person you hit hits you back.

	`a` threw the first punch; `b` answered it. Which is which changes only the
	wording -- both must accept, and either may set the first wager.
]]
function DuelService.offer(a, b)
	if byUserId[a.UserId] or byUserId[b.UserId] then
		return -- one of them is already in something
	end
	local aProfile, bProfile = DataService.get(a), DataService.get(b)
	if not aProfile or not bProfile then
		return
	end
	--[[ Opting out is per-player and checked here rather than in combat: a
	     player with duels off can still be punched and can still punch back,
	     they simply never see the prompt. Punching is not the part anyone
	     needs protecting from. ]]
	if aProfile.duelsOff or bProfile.duelsOff then
		return
	end

	local duel = {
		id = nextId,
		a = a,
		b = b,
		phase = "offer",
		accepted = {},
		stakes = {},
		bets = {},
		returnTo = {},
		deadline = os.clock() + Duel.OfferSeconds,
	}
	nextId += 1
	duels[duel.id] = duel
	byUserId[a.UserId] = duel
	byUserId[b.UserId] = duel

	for _, player in ipairs({ a, b }) do
		Net.get("DuelOffer"):FireClient(player, {
			id = duel.id,
			opponent = otherOf(duel, player).DisplayName,
			seconds = Duel.OfferSeconds,
			--[[ Said plainly on the prompt, because "do you want to duel" is
			     not the question. The question is whether you want to put a
			     brainrot on it. ]]
			stakes = true,
		})
	end
	pushState(duel)
end

function DuelService.respond(player, yes)
	local duel = byUserId[player.UserId]
	if not duel or duel.phase ~= "offer" then
		return { ok = false, err = "Nothing to answer." }
	end
	if not yes then
		notifyBoth(duel, ("%s turned down the duel."):format(player.DisplayName), "info")
		close(duel, "declined", true)
		return { ok = true, declined = true }
	end

	duel.accepted[player.UserId] = true
	if duel.accepted[duel.a.UserId] and duel.accepted[duel.b.UserId] then
		duel.phase = "wager"
		duel.deadline = os.clock() + Duel.WagerSeconds
		notifyBoth(duel, "Duel on — put a brainrot up.", "good")
	end
	pushState(duel)
	return { ok = true }
end

-- ── phase 2: the wager ──────────────────────────────────────────────────────

local function bothStaked(duel)
	return duel.stakes[duel.a.UserId] ~= nil and duel.stakes[duel.b.UserId] ~= nil
end

--[[
	ANY CHANGE TO EITHER OFFER CLEARS BOTH ACCEPTS.

	This is the one rule that makes a trade window safe, and every trading
	game has it: without it, a player accepts, waits for the other to accept,
	and swaps their Mythic for a Common in the gap. Nobody can ever be holding
	an accept against an offer they did not see.
]]
local function unaccept(duel)
	duel.accepted = {}
end

function DuelService.wager(player, action, uids)
	local duel = byUserId[player.UserId]
	if not duel then
		return { ok = false, err = "You are not in a duel." }
	end

	if action == "cancel" then
		--[[ The one hard line in this module. Before the arena, walking away
		     costs nothing; after it, the wager is live and leaving is losing. ]]
		if duel.phase == "fight" then
			return { ok = false, err = "Too late — the duel has started." }
		end
		notifyBoth(duel, ("%s called it off."):format(player.DisplayName), "info")
		close(duel, "cancelled", true)
		return { ok = true, cancelled = true }
	end

	if duel.phase ~= "wager" then
		return { ok = false, err = "Not taking wagers right now." }
	end

	--[[ ── set: replace my whole offer ───────────────────────────────────────

		The client sends the FULL contents of its grid every time rather than
		"add this one" / "remove that one". One message shape, no way for the
		two sides to disagree about what is in a slot, and a dropped packet
		costs a redraw instead of leaving a phantom item in the window.
	]]
	if action == "set" then
		if type(uids) ~= "table" then
			return { ok = false, err = "Invalid offer." }
		end
		if #uids > Duel.MaxStakeItems then
			return { ok = false, err = ("At most %d brainrots."):format(Duel.MaxStakeItems) }
		end
		local profile = DataService.get(player)
		if not profile then
			return { ok = false, err = "Still loading, one sec." }
		end
		--[[ Ownership checked HERE as well as at transfer. It is not the last
		     line of defence -- payStake is -- but refusing at the window is
		     what stops someone building an offer out of brainrots they sold
		     and letting the other side accept it. ]]
		local tiers, err = tiersFor(profile, uids)
		if not tiers then
			return { ok = false, err = err }
		end

		duel.stakes[player.UserId] = #uids > 0 and uids or nil
		unaccept(duel)
		duel.deadline = os.clock() + Duel.WagerSeconds
		pushState(duel)
		return { ok = true }
	end

	-- ── accept: I am happy with both grids as they stand ────────────────────
	if action == "accept" then
		if not bothStaked(duel) then
			return { ok = false, err = "Both of you need something up first." }
		end

		--[[
			THE ONLY THING CHECKED HERE IS THAT BOTH OFFERS ARE STILL REAL.

			There is no fairness test. Whether a Mythic for two Commons is a
			good trade is the players' call and they can see both grids and both
			income totals while they make it -- see the note in Shared/Duel for
			why the tier ladder that used to live here was removed.
		]]
		local aRows = stakeRows(duel.a, duel.stakes[duel.a.UserId])
		local bRows = stakeRows(duel.b, duel.stakes[duel.b.UserId])
		if #aRows == 0 or #bRows == 0 then
			--[[ A stake evaporated between being offered and being accepted --
			     sold, stored, or lost to a mine while the window was open. ]]
			duel.stakes = {}
			unaccept(duel)
			notifyBoth(duel, "A stake stopped being real — offers cleared.", "info")
			pushState(duel)
			return { ok = false, err = "That stake is gone." }
		end

		duel.accepted[player.UserId] = true
		if duel.accepted[duel.a.UserId] and duel.accepted[duel.b.UserId] then
			DuelService.begin(duel)
		else
			duel.deadline = os.clock() + Duel.WagerSeconds
			pushState(duel)
		end
		return { ok = true }
	end

	return { ok = false, err = "Unknown action." }
end

-- ── phase 3: the fight ──────────────────────────────────────────────────────

function DuelService.begin(duel)
	local aChar, bChar
	local aHum, bHum
	aHum, aChar = humanoidOf(duel.a)
	bHum, bChar = humanoidOf(duel.b)
	--[[ Health checked as well as existence. Negotiating a wager takes up to a
	     minute, which is long enough to be killed by a fall on the way to
	     agreeing -- and setting Health on a humanoid that has already died
	     does not bring it back, so it would enter the arena as a corpse and
	     lose a Mythic without throwing a punch. ]]
	if not aHum or not bHum or not aChar or not bChar
		or aHum.Health <= 0 or bHum.Health <= 0 then
		notifyBoth(duel, "Duel voided — someone was not ready.", "info")
		close(duel, "notready", true)
		return
	end

	--[[ One floor, one fight. Checked here rather than at the offer, because
	     the arena can be taken during the minute the two of them spend
	     haggling over a stake. ]]
	if ArenaService.busy then
		notifyBoth(duel, "The arena is in use — try again in a moment.", "info")
		close(duel, "arenabusy", true)
		return
	end
	ArenaService.busy = true
	duel.heldArena = true

	duel.phase = "fight"
	duel.startedAt = os.clock()
	duel.deadline = os.clock() + Duel.Seconds

	for index, player in ipairs({ duel.a, duel.b }) do
		local humanoid, character = humanoidOf(player)
		duel.returnTo[player.UserId] = character and character:GetPivot() or nil
		if character then
			character:PivotTo(ArenaService.spawnFor(index))
		end
		if humanoid then
			--[[ Both to full. See the header -- the result is a health
			     comparison, so an unequal start decides it before it opens. ]]
			humanoid.Health = humanoid.MaxHealth
		end
	end

	--[[
		A DEATH ENDS THE DUEL IMMEDIATELY.

		Connected AFTER both are healed and moved, so the heal above cannot
		trip it, and stored on the duel so `close` can drop them -- a live
		Died handler on a character that outlives its duel would resolve a
		fight that is already over.

		`once` semantics come from resolve itself, which returns early if the
		duel is closed or already done. Both fighters dying in the same frame
		is therefore harmless: the second call finds phase == "done" and stops.
	]]
	duel.conns = {}
	for _, player in ipairs({ duel.a, duel.b }) do
		local humanoid = humanoidOf(player)
		if humanoid then
			table.insert(duel.conns, humanoid.Died:Connect(function()
				if duel.closed or duel.phase ~= "fight" then
					return
				end
				duel.forfeit = player.UserId
				duel.forfeitReason = "knockout"
				local ok, err = pcall(DuelService.resolve, duel)
				if not ok then
					warn("[DuelService] knockout resolve failed:", err)
				end
			end))
		end
	end

	notifyBoth(duel, ("Duel! %d seconds, or until someone drops."):format(Duel.Seconds), "great")
	pushState(duel)

	--[[ The book opens to everyone who is not in the fight. Names rather than
	     userIds in the payload because this is what the betting card shows. ]]
	Net.get("DuelBoard"):FireAllClients({
		id = duel.id,
		phase = "open",
		a = duel.a.DisplayName,
		b = duel.b.DisplayName,
		aId = duel.a.UserId,
		bId = duel.b.UserId,
		seconds = Duel.Seconds,
		closeAt = Duel.BetCloseAt,
	})

	task.spawn(function()
		--[[ A poll rather than a single wait, because the fight can end early
		     -- a disconnect forfeits -- and because the book has to shut
		     before the clock does. ]]
		local booked = false
		while not duel.closed and duel.phase == "fight" do
			local left = duel.deadline - os.clock()
			if not booked and left <= Duel.BetCloseAt then
				booked = true
				Net.get("DuelBoard"):FireAllClients({ id = duel.id, phase = "closed_book" })
			end
			if left <= 0 then
				break
			end
			task.wait(0.25)
		end
		if not duel.closed and duel.phase == "fight" then
			DuelService.resolve(duel)
		end
	end)
end

-- ── phase 4: paying up ──────────────────────────────────────────────────────

function DuelService.resolve(duel)
	if duel.closed or duel.phase == "done" then
		return
	end
	duel.phase = "done"

	local aHum = humanoidOf(duel.a)
	local bHum = humanoidOf(duel.b)
	local aHealth = aHum and aHum.Health or 0
	local aMax = aHum and aHum.MaxHealth or 100
	local bHealth = bHum and bHum.Health or 0
	local bMax = bHum and bHum.MaxHealth or 100

	--[[
		A forfeit is recorded as BELOW zero health rather than as a special
		case, so there is exactly one place that decides a winner.

		Below zero, not zero, and it matters here: a knocked-out player may
		already have respawned at full health by the time this runs, and even
		against a survivor on 0 the loser must still lose. -1 cannot tie.
	]]
	if duel.forfeit then
		if duel.forfeit == duel.a.UserId then
			aHealth = -1
		else
			bHealth = -1
		end
	end

	local winnerKey = Duel.winner(aHealth, aMax, bHealth, bMax)
	local winner = winnerKey == "a" and duel.a or (winnerKey == "b" and duel.b or nil)
	local loser = winner and otherOf(duel, winner) or nil

	--[[ RECORDED BEFORE THE STAKE MOVES, deliberately. The transfer below can
	     fail -- the loser may have sold the brainrot they put up -- and that
	     path returns early. The fight still happened and was still won, so a
	     record that only counted duels whose prize survived would be a record
	     of successful transfers rather than of duels. ]]
	if winner and loser then
		bump(winner, "duelWins")
		bump(loser, "duelLosses")
	else
		bump(duel.a, "duelDraws")
		bump(duel.b, "duelDraws")
	end

	local movedText = nil
	if winner and loser then
		local ok, tiers = DuelService.payStake(loser, winner, duel.stakes[loser.UserId] or {})
		if ok then
			movedText = Duel.describe(tiers)
		else
			--[[ The stake evaporated. Nobody is paid, and the spectators get
			     their money back -- settling a book on a fight whose prize did
			     not exist would be taking money for nothing. ]]
			notifyBoth(duel, "Duel voided — the stake was no longer there.", "info")
			close(duel, "stakegone", true)
			return
		end
	end

	-- the book
	local payouts = Duel.settleBets(duel.bets, winnerKey)
	for userId, amount in pairs(payouts) do
		local better = Players:GetPlayerByUserId(userId)
		local profile = better and DataService.get(better)
		if profile and amount > 0 then
			profile.money += amount
			PlayerState.pushMoney(better)
			local staked = duel.bets[userId].amount
			PlayerState.notify(better, amount > staked
				and ("Your bet came in — %s."):format(Format.money(amount))
				or ("Bet refunded — %s."):format(Format.money(amount)), "good")
		elseif better then
			PlayerState.notify(better, "Your bet went down with them.", "info")
		end
	end

	if winner and loser then
		--[[ Said differently for a knockout, because "you won on health" and
		     "you put them on the floor" are different events and the player
		     watching it happen already knows which one it was. ]]
		local how = duel.forfeitReason == "knockout" and "Knockout! " or ""
		PlayerState.notify(winner, ("%sYou won the duel — took %s."):format(
			how, movedText or "their stake"), "great")
		PlayerState.notify(loser, ("%sYou lost the duel — %s gone."):format(
			how, movedText or "your stake"), "info")
		PlayerState.push(winner)
		PlayerState.push(loser)
	else
		notifyBoth(duel, "Draw — both stakes stay put.", "info")
	end

	Net.get("DuelBoard"):FireAllClients({
		id = duel.id,
		phase = "result",
		winner = winner and winner.DisplayName or nil,
		draw = winner == nil,
		took = movedText,
		knockout = duel.forfeitReason == "knockout",
	})

	close(duel, "resolved", false)
end

--[[
	MOVE ONE PLAYER'S STAKED BRAINROTS TO THE OTHER.

	The only function in the codebase that moves a brainrot between two
	players, kept separate so it can be read on its own.

	Re-resolved from uids at this moment, not from anything captured earlier:
	between the wager and here the loser may have sold, stored or placed them.
	A uid that no longer resolves aborts the WHOLE transfer rather than moving
	a partial stake, because half a wager is not what either side agreed to --
	which is why nothing is removed until every uid has resolved.

	The winner receives NEW uids. Uids are allocated per profile, so carrying
	the loser's across would eventually collide with one of the winner's own.
]]
function DuelService.payStake(from, to, uids)
	local fromProfile, toProfile = DataService.get(from), DataService.get(to)
	if not fromProfile or not toProfile then
		return false
	end

	-- resolve every uid FIRST; move nothing until all of them are good
	local resolved, tiers = {}, {}
	for _, uid in ipairs(uids) do
		local item, index = DataService.findItem(fromProfile, uid)
		if not index or not item then
			return false
		end
		local tier = tierOfItem(item)
		if not tier then
			return false
		end
		table.insert(resolved, { index = index, item = item })
		table.insert(tiers, tier)
	end
	if #resolved == 0 then
		return false
	end

	--[[ Highest index first, so removing one does not shift the index of
	     another still to be removed. ]]
	table.sort(resolved, function(x, y)
		return x.index > y.index
	end)

	local clearedPad = false
	for _, entry in ipairs(resolved) do
		local item = entry.item
		if item.pad then
			clearedPad = true
		end
		table.remove(fromProfile.inventory, entry.index)
		table.insert(toProfile.inventory, {
			uid = DataService.nextUid(toProfile),
			charId = item.charId,
			variantId = item.variantId,
			--[[ Arrives unplaced. Dropping it straight onto a pad would either
			     evict whatever the winner already had there or silently pick a
			     slot for them; landing in the inventory lets them choose. ]]
		})
		DataService.recordIndex(toProfile, item.charId, item.variantId)
	end

	if clearedPad then
		--[[ It was standing on the loser's base earning rent. The pad has to be
		     re-rendered or the model stays there paying out for a brainrot its
		     owner no longer has. ]]
		PlotService.refresh(from)
	end
	return true, tiers
end

-- ── the book ────────────────────────────────────────────────────────────────

function DuelService.bet(player, duelId, side, amount)
	local duel = duels[duelId]
	if not duel or duel.phase ~= "fight" then
		return { ok = false, err = "No fight to bet on." }
	end
	if byUserId[player.UserId] == duel then
		return { ok = false, err = "You are in this one." }
	end
	if (duel.deadline - os.clock()) <= Duel.BetCloseAt then
		return { ok = false, err = "Betting is closed." }
	end
	if duel.bets[player.UserId] then
		return { ok = false, err = "You already have a bet on this." }
	end
	if side ~= "a" and side ~= "b" then
		return { ok = false, err = "Pick a fighter." }
	end

	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then
		return { ok = false, err = "Invalid amount." }
	end
	amount = math.floor(amount)
	if amount < Duel.MinSpectatorBet then
		return { ok = false, err = ("Minimum bet is %s."):format(Format.money(Duel.MinSpectatorBet)) }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if profile.money < amount then
		return { ok = false, err = "You cannot afford that." }
	end

	profile.money -= amount
	duel.bets[player.UserId] = { on = side, amount = amount }
	PlayerState.pushMoney(player)
	return { ok = true, on = side, amount = amount }
end

-- ── wiring ──────────────────────────────────────────────────────────────────

function DuelService.start()
	ArenaService.build()

	--[[ One direction only: combat calls into duels, never the reverse. See
	     CombatService's header for why that matters. ]]
	--[[ Street fights are counted here rather than in CombatService so that
	     file keeps knowing nothing about profiles. Both sides get the count:
	     it takes two to have a scrap, and the one who was swung at was in it
	     every bit as much as the one who swung. ]]
	CombatService.onStreetFight = function(a, b)
		bump(a, "fights")
		bump(b, "fights")
	end

	CombatService.onRetaliation = function(a, b)
		local ok, err = pcall(DuelService.offer, a, b)
		if not ok then
			warn("[DuelService] offer failed:", err)
		end
	end

	--[[
		Who may hit whom.

		While a duel is being fought its two fighters are sealed off: they may
		hit each other and nobody else, and nobody else may reach them. A
		spectator with a grudge must not get to decide a wager they have no
		stake in.

		Note the shape -- it answers about a PAIR. Asking "is this player
		busy?" about each of them in turn is what the first version did, and it
		refused the duellists' own punches along with everyone else's.
	]]
	CombatService.canFight = function(attacker, victim)
		local attackerDuel = byUserId[attacker.UserId]
		local victimDuel = byUserId[victim.UserId]
		local attackerFighting = attackerDuel and attackerDuel.phase == "fight"
		local victimFighting = victimDuel and victimDuel.phase == "fight"
		if not attackerFighting and not victimFighting then
			return true -- two people in the street
		end
		-- otherwise: only the same live duel counts
		return attackerFighting and victimFighting and attackerDuel == victimDuel
	end

	Net.get("DuelRespond").OnServerInvoke = function(player, yes)
		return DuelService.respond(player, yes == true)
	end
	Net.get("DuelWager").OnServerInvoke = function(player, action, uids)
		return DuelService.wager(player, action, uids)
	end
	Net.get("DuelBet").OnServerInvoke = function(player, duelId, side, amount)
		return DuelService.bet(player, duelId, side, amount)
	end

	--[[ Deadlines are swept in one place rather than with a timer per duel, so
	     a duel that is abandoned at any phase still expires. ]]
	task.spawn(function()
		while true do
			task.wait(1)
			for _, duel in pairs(duels) do
				if not duel.closed and duel.phase ~= "fight" and duel.deadline
					and os.clock() > duel.deadline then
					notifyBoth(duel, "Duel expired.", "info")
					close(duel, "expired", true)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local duel = byUserId[player.UserId]
		if not duel then
			return
		end
		if duel.phase == "fight" then
			--[[ Leaving a live duel is losing it. The alternative -- voiding --
			     would make disconnecting the correct play whenever you are
			     behind, which turns every close fight into a race to alt-F4. ]]
			duel.forfeit = player.UserId
			DuelService.resolve(duel)
		else
			close(duel, "left", true)
		end
	end)
end

return DuelService
