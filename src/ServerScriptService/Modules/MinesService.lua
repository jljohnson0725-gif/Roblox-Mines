--[[
	MinesService
	Server-authoritative Mines rounds.

	Two rules the whole thing rests on:

	  1. The board is generated in full at round start. Nothing is "decided" when
	     you click, so the server cannot rig a reveal after seeing your pick.
	  2. The client is never told where the mines are until the round is over.

	Brainrots found mid-round are UNSECURED. They only enter the inventory on a
	successful cash-out -- hitting a mine drops the bet and every unsecured
	brainrot with it. That's the tension the whole game is built on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MinesMath = require(Shared.MinesMath)
local DropTable = require(Shared.DropTable)
local Economy = require(Shared.Economy)
local Brainrots = require(Shared.Brainrots)
local Sounds = require(Shared.Sounds)

local DataService = require(script.Parent.DataService)
local Rebirth = require(Shared.Rebirth)
local Upgrades = require(Shared.Upgrades)
local PlayerState = require(script.Parent.PlayerState)
local EventService = require(script.Parent.EventService)

local MinesService = {}

local rounds = {} -- [userId] = round
local rng = Random.new()

local function isValidMineCount(mines)
	for _, option in ipairs(Config.MineOptions) do
		if option == mines then
			return true
		end
	end
	return false
end

--[[ What the client is allowed to know about a live round. ]]
local function publicRound(round)
	return {
		bet = round.bet,
		mines = round.mines,
		picks = round.picks,
		multiplier = round.multiplier,
		payout = math.floor(round.bet * round.multiplier),
		revealed = round.revealed,
		unsecured = round.unsecured,
		lives = round.lives,
		dropChance = DropTable.dropChance(round.mines, EventService.currentMods()),
	}
end

local function endRound(userId)
	rounds[userId] = nil
end

--[[
	Broadcast the top-tier drops to everyone.

	Announcing on FIND rather than on cash-out is deliberate: the whole server
	watching someone sit on an unsecured Secret is better drama than a tidy
	confirmation after the fact. The matching `lost = true` broadcast on a bust
	is the payoff -- announcing the find without ever announcing the loss would
	make the risk invisible to everyone except the player taking it.
]]
local function announce(player, drop, lost)
	local spec = Sounds.spectacleFor(drop.tier)
	if not spec.announce then
		return
	end

	Net.get("Announce"):FireAllClients({
		-- userId, not name: display names aren't unique, and the finder needs to
		-- be identified exactly so they don't get the spectator version on top
		-- of their own full-screen one.
		userId = player.UserId,
		playerName = player.DisplayName,
		charId = drop.charId,
		variantId = drop.variantId,
		tier = drop.tier,
		lost = lost or false,
	})
end

-- ── Start ───────────────────────────────────────────────────────────────────

function MinesService.startRound(player, bet, mines)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if rounds[player.UserId] then
		return { ok = false, err = "You already have a round going." }
	end

	if type(bet) ~= "number" or bet ~= bet or bet == math.huge then
		return { ok = false, err = "Invalid bet." }
	end
	bet = math.floor(bet)
	if bet < Config.MinBet then
		return { ok = false, err = "Minimum bet is $" .. Config.MinBet .. "." }
	end
	if bet > profile.money then
		return { ok = false, err = "You can't afford that bet." }
	end

	if type(mines) ~= "number" or not isValidMineCount(mines) then
		return { ok = false, err = "Invalid mine count." }
	end

	profile.money -= bet

	local round = {
		bet = bet,
		mines = mines,
		board = MinesMath.generateBoard(mines, rng),
		revealed = {}, -- [tileIndex] = true
		picks = 0,
		multiplier = 1,
		unsecured = {},
		busy = false,
		--[[ Read once, at the start, and spent down as the round goes. Reading
		     it per hit instead would let someone buy a life mid-round from the
		     shop and retroactively survive a tile they already lost on.

		     A SNAPSHOT OF THE STOCK, not a refill. It was an upgrade level and
		     every round began with all of them back; now it is what you are
		     carrying, and spending one below spends it off the profile too. A
		     life bought mid-round therefore does not join THIS round -- the
		     snapshot has already been taken -- but it is still there for the
		     next one, which is the honest reading of both rules at once. ]]
		lives = profile.lives or 0,
	}
	rounds[player.UserId] = round

	profile.stats.rounds += 1
	PlayerState.push(player)

	return { ok = true, round = publicRound(round) }
end

-- ── Reveal ──────────────────────────────────────────────────────────────────

function MinesService.revealTile(player, index)
	local round = rounds[player.UserId]
	if not round then
		return { ok = false, err = "No round in progress." }
	end
	-- RemoteFunction invocations from one client aren't guaranteed to be
	-- serialised, so guard against a double-click racing itself.
	if round.busy then
		return { ok = false, err = "Too fast." }
	end

	if type(index) ~= "number" then
		return { ok = false, err = "Invalid tile." }
	end
	index = math.floor(index)
	if index < 1 or index > Config.TileCount then
		return { ok = false, err = "Invalid tile." }
	end
	if round.revealed[index] then
		return { ok = false, err = "Already revealed." }
	end

	round.busy = true
	round.revealed[index] = true

	--[[ ── survived ───────────────────────────────────────────────────────────

		A hit tile with a life left to spend. The round continues, and what it
		deliberately does NOT do is as important as what it does:

		  no multiplier   -- `picks` counts SAFE tiles, and paying out for
		                     stepping on a mine would make buying lives a way to
		                     farm multiplier rather than a way to survive.
		  no drop roll    -- same reason. A mine is not a find.
		  no bust stat    -- it wasn't a bust; the run is still going.

		The tile stays in `revealed`, so it cannot be picked again, and it stays
		true on the board, so a client that recounts still sees where the mines
		are. What is spent is the life.
	]]
	if round.board[index] and (round.lives or 0) > 0 then
		round.lives -= 1
		--[[ AND OFF THE PROFILE, which is the whole change: the life is gone,
		     not refunded at the next round. Clamped rather than trusted equal
		     to the snapshot -- the two can legitimately differ when a life is
		     bought mid-round, and a stock that could go negative would hand out
		     a free one at the next round start. ]]
		local spender = DataService.get(player)
		if spender then
			spender.lives = math.max((spender.lives or 0) - 1, 0)
			PlayerState.push(player)
		end
		round.busy = false
		return {
			ok = true,
			mine = true,
			survived = true,
			lives = round.lives,
			index = index,
			multiplier = round.multiplier,
			payout = math.floor(round.bet * round.multiplier),
		}
	end

	-- ── boom ────────────────────────────────────────────────────────────────
	if round.board[index] then
		local profile = DataService.get(player)
		local lost = round.unsecured
		if profile then
			profile.stats.busts += 1
		end

		-- Pay off any find we announced: the server watched them get it, the
		-- server should watch them lose it.
		for _, drop in ipairs(lost) do
			announce(player, drop, true)
		end

		endRound(player.UserId)
		PlayerState.push(player)

		return {
			ok = true,
			mine = true,
			index = index,
			board = round.board, -- safe to reveal now
			lostBet = round.bet,
			lostBrainrots = lost,
		}
	end

	-- ── safe ────────────────────────────────────────────────────────────────
	round.picks += 1
	round.multiplier = MinesMath.multiplier(round.mines, round.picks)

	local profile = DataService.get(player)
	if profile and round.multiplier > (profile.stats.bestMultiplier or 1) then
		profile.stats.bestMultiplier = round.multiplier
	end

	-- Read live rather than snapshotting at round start, so an event that begins
	-- mid-round applies from the very next tile.
	local mods = EventService.currentMods()

	--[[
		First-session guarantee: while the player still has guaranteed finds
		left, their FIRST safe tile of a round always yields something.

		Only the roll to drop is forced -- DropTable.roll still decides tier and
		variant honestly, so this changes whether you find something, never what.
		The multiplier remains the luck stat.

		The flag is set here but only spent at cash-out, so busting with an
		unsecured guaranteed drop doesn't cost the player their guarantee.
	]]
	local guaranteed = round.picks == 1
		and profile ~= nil
		and (profile.onboarding and profile.onboarding.drops or 0) > 0

	local drop
	if guaranteed or rng:NextNumber() < DropTable.dropChance(round.mines, mods) then
		-- roll() returns nil only if the roster is misconfigured; treat that as
		-- "no drop this tile" rather than failing the reveal.
		--[[ Rebirth luck rides in on the same mods table the events use. One
		     path into DropTable, so a lucky player and a lucky server are the
		     same mechanism rather than two that can disagree.

		     Two axes now: a depth BONUS, which lifts the whole curve, and a
		     per-tier WEIGHT for the tiers this many rebirths has opened. See
		     Config.RebirthTierBoost.

		     COMBINED WITH THE EVENT'S VALUES, NOT WRITTEN OVER THEM. This block
		     used to seed `{ depthBonus = luck }` and then copy the event mods
		     on top, so any event carrying its own depthBonus silently deleted
		     the player's rebirth luck for the duration -- and with tierMul now
		     on the same table there would be a second way to lose it. ]]
		mods = Rebirth.applyTo(mods, profile and profile.rebirths)
		--[[ A forced tier, from a test code, spends one charge per drop. Checked
		     before the honest roll so it stays exact: the roll would produce
		     the asked-for tier only by chance, and a test that is merely likely
		     to work is not a test. ]]
		local forced = profile and (profile.forceDrops or 0) > 0
			and DropTable.forceRoll(profile.forceTier, rng)
		if forced then
			profile.forceDrops -= 1
			drop = forced
		else
			drop = DropTable.roll(round.multiplier, rng, mods, round.mines, round.bet)
		end
		if drop then
			drop.income = Economy.incomeOf(drop.charId, drop.variantId)
			drop.tier = Brainrots.get(drop.charId).tier
			table.insert(round.unsecured, drop)
			if guaranteed then
				round.usedGuarantee = true
			end
			announce(player, drop, false)
		end
	end

	local cleared = round.picks >= MinesMath.safeTileCount(round.mines)
	local result = {
		ok = true,
		mine = false,
		index = index,
		picks = round.picks,
		multiplier = round.multiplier,
		payout = math.floor(round.bet * round.multiplier),
		nextMultiplier = MinesMath.multiplier(round.mines, round.picks + 1),
		safeChance = MinesMath.nextTileSafeChance(round.mines, round.picks),
		-- deliberately NOT sending the odds table: the client derives it from
		-- the same shared DropTable module, so shipping it every reveal would
		-- be seven keys of pure duplication
		drop = drop,
		cleared = cleared,
	}

	round.busy = false

	-- Board fully cleared -- nothing left to risk, so pay out automatically.
	if cleared then
		result.cashout = MinesService.cashOut(player)
	end

	return result
end

-- ── Cash out ────────────────────────────────────────────────────────────────

function MinesService.cashOut(player)
	local round = rounds[player.UserId]
	if not round then
		return { ok = false, err = "No round in progress." }
	end
	if round.picks < 1 then
		return { ok = false, err = "Reveal at least one tile first." }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end

	local payout = math.floor(round.bet * round.multiplier)
	profile.money += payout

	local secured = {}
	local best = nil
	for _, drop in ipairs(round.unsecured) do
		local item = {
			uid = DataService.nextUid(profile),
			charId = drop.charId,
			variantId = drop.variantId,
		}
		table.insert(profile.inventory, item)
		table.insert(secured, drop)

		-- Banked, so it counts for the Index. Recorded here rather than at the
		-- moment of the find, because a drop lost to a mine was never yours.
		DataService.recordIndex(profile, drop.charId, drop.variantId)

		local score = Economy.powerScore(drop.charId, drop.variantId)
		if not best or score > best.score then
			best = { score = score, charId = drop.charId, variantId = drop.variantId }
		end
	end

	if best then
		local previous = profile.stats.bestDrop
		if not previous or best.score > (previous.score or 0) then
			profile.stats.bestDrop = best
		end
	end

	-- Spend the guarantee only now that the drop is actually banked.
	if round.usedGuarantee and #secured > 0 and profile.onboarding then
		profile.onboarding.drops = math.max(0, profile.onboarding.drops - 1)
	end

	local multiplier = round.multiplier
	endRound(player.UserId)
	PlayerState.push(player)

	return {
		ok = true,
		payout = payout,
		profit = payout - round.bet,
		multiplier = multiplier,
		secured = secured,
	}
end

-- ── Wiring ──────────────────────────────────────────────────────────────────

function MinesService.start()
	Net.get("StartRound").OnServerInvoke = function(player, bet, mines)
		return MinesService.startRound(player, bet, mines)
	end

	Net.get("RevealTile").OnServerInvoke = function(player, index)
		return MinesService.revealTile(player, index)
	end

	Net.get("CashOut").OnServerInvoke = function(player)
		return MinesService.cashOut(player)
	end

	-- Leaving mid-round forfeits it. The bet was already taken at start, so
	-- there's nothing to gain by disconnecting -- this just cleans up.
	Players.PlayerRemoving:Connect(function(player)
		endRound(player.UserId)
	end)
end

return MinesService
