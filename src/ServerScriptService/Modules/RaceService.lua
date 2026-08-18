--[[
	RaceService
	Enter a field, stake, and watch your brainrot run.

	THE OUTCOME IS DECIDED BEFORE THE RACE STARTS, exactly like the wheel. The
	server rolls once against Shared/Racing's odds, then hands the client a
	finished script -- who won, and the finishing order -- for it to play out.
	Nothing about the visible race can change the result, which is what makes it
	honest: there is no simulation to desync, no physics to disagree about
	across clients, and no way for a laggy machine to lose a race it won.

	IT RUNS TO COMPLETION WITHOUT INPUT, and that is deliberate scaffolding.
	A manual mode would be an INPUT LAYER on top of this, not a second system --
	so if steering ever turns out to be unfun, the layer comes off and a working
	island remains.

	THE MONEY MOVES WHEN THE RACE ENDS, not when it starts. The stake is taken
	up front, but the win is paid on the same beat the player sees the finish.
	Paying early means the counter jumps before the race resolves and tells you
	the ending; paying late by more than a moment reads as a bug.
]]

local Players = game:GetService("Players")

local Modules = script.Parent
local DataService = require(Modules.DataService)
local PlayerState = require(Modules.PlayerState)
local RaceTrack = require(Modules.RaceTrack)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Racing = require(Shared.Racing)
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)

local RaceService = {}

local running = {} -- [player] = true while a race is in flight

--[[ Names for the field you run against. Flavour only -- the rivals have no
     stats, because the outcome is already decided and giving them numbers
     would invite someone to "balance" a thing that does not compute. ]]
local RIVALS = {
	"Zoomer", "Bolt", "Clatter", "Wisp", "Grubby", "Nitro",
	"Sputter", "Tangle", "Rocket", "Mudlark", "Scrappy", "Dart",
}

local function shuffled(rng, list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	One race, start to finish.

	Returns the payload the client animates. `order` is the finishing order with
	the player already in their decided place, so the client has nothing to
	decide -- it draws what it is told.
]]
function RaceService.enter(player, fieldId)
	if running[player] then
		return { ok = false, err = "Already racing." }
	end
	if RaceTrack.isBusy() then
		return { ok = false, err = "A race is running. Watch this one." }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end

	local island = Islands.get("racing")
	local allowed, missing = Seals.canEnter(profile, island)
	if not allowed then
		return { ok = false, err = ("The %s seal opens this."):format(missing or "?") }
	end

	local field = Racing.get(fieldId)
	if not field then
		return { ok = false, err = "Pick a field." }
	end

	local stake = Config.RaceStake
	if profile.money < stake then
		return { ok = false, err = "Need " .. Format.money(stake) .. "." }
	end

	local racer = nil
	for _, item in ipairs(profile.inventory) do
		if item.uid == profile.racer then
			racer = item
		end
	end
	if not racer then
		-- same rule the perch uses: your best earner turns up if you never chose
		local best = -1
		for _, item in ipairs(profile.inventory) do
			local score = Economy.powerScore(item.charId, item.variantId)
			if score > best then
				racer, best = item, score
			end
		end
	end
	if not racer then
		return { ok = false, err = "You need a brainrot to race." }
	end

	profile.money -= stake
	running[player] = true

	local odds = Racing.odds(profile, field)
	local rng = Random.new()
	local won = rng:NextNumber() < odds.win

	--[[ Where you finish when you lose. Not always last -- coming second in a
	     field of nine reads completely differently from trailing in, and the
	     result is the same money either way, so the only thing this costs is
	     nothing and the only thing it buys is the race being worth watching. ]]
	local place = won and 1 or rng:NextInteger(2, field.rivals + 1)

	local names = shuffled(rng, RIVALS)
	local order = {}
	local nameIndex = 0
	for slot = 1, field.rivals + 1 do
		if slot == place then
			table.insert(order, {
				name = Economy.displayName(racer.charId, racer.variantId),
				charId = racer.charId,
				variantId = racer.variantId,
				you = true,
			})
		else
			nameIndex += 1
			table.insert(order, { name = names[nameIndex] or ("Rival " .. slot), you = false })
		end
	end

	local payload = {
		ok = true,
		field = field.id,
		fieldName = field.name,
		seconds = Config.RaceSeconds,
		stake = stake,
		won = won,
		place = place,
		pay = odds.pay,
		order = order,
	}

	--[[ The track draws what was already decided. If it refuses -- a race is
	     mid-run -- the result still stands and still pays; the money must never
	     depend on the scenery. ]]
	RaceTrack.run(order, Config.RaceSeconds)

	--[[ Settled on a timer rather than by the client reporting home. The client
	     is drawing a result it was given; letting it tell the server when to pay
	     would hand it a lever it has no business holding. ]]
	task.delay(Config.RaceSeconds, function()
		running[player] = nil
		local live = DataService.get(player)
		if not live then
			return
		end

		local winnings = won and math.floor(stake * odds.pay) or 0
		live.money += winnings

		local sealed = false
		if won and rng:NextNumber() < field.frag then
			local _, _, justSealed = Seals.award(live, island)
			sealed = justSealed
		end

		local message
		if sealed then
			message = "THE RACING SEAL IS YOURS."
		elseif won then
			message = ("Won the %s — %s"):format(field.name, Format.money(winnings))
		else
			message = ("%s: finished %d of %d"):format(field.name, place, field.rivals + 1)
		end
		PlayerState.notify(player, message, sealed and "great" or (won and "good" or "info"))
		PlayerState.push(player)
	end)

	PlayerState.push(player)
	return payload
end

function RaceService.start()
	RaceTrack.build()

	if RaceTrack.prompt then
		RaceTrack.prompt.Triggered:Connect(function(player)
			local profile = DataService.get(player)
			if not profile then
				return
			end
			local allowed, missing = Seals.canEnter(profile, Islands.get("racing"))
			if not allowed then
				PlayerState.notify(player, ("The %s seal opens this."):format(missing or "?"))
				return
			end
			Net.get("OpenRace"):FireClient(player)
		end)
	end

	Net.get("EnterRace").OnServerInvoke = function(player, fieldId)
		local ok, result = pcall(RaceService.enter, player, fieldId)
		if not ok then
			--[[ A thrown error must not leave the flag set, or that player can
			     never race again for the life of the server. ]]
			running[player] = nil
			warn("[RaceService] " .. tostring(result))
			return { ok = false, err = "Something went wrong." }
		end
		return result
	end

	Net.get("RaceOdds").OnServerInvoke = function(player)
		local profile = DataService.get(player)
		return {
			fields = Racing.all(profile),
			stake = Config.RaceStake,
			level = Racing.level(profile),
			maxLevel = Racing.MaxLevel,
			upgradeCost = Racing.upgradeCost(Racing.level(profile)),
			money = profile and profile.money or 0,
		}
	end

	--[[ Bought here rather than at the street shop, because it is only useful on
	     this island and a player who has never been up cannot see it. Same
	     validate-then-charge order as every other purchase: read the price from
	     the server's own level, never from anything the client sent. ]]
	Net.get("BuyRaceSpeed").OnServerInvoke = function(player)
		local profile = DataService.get(player)
		if not profile then
			return { ok = false, err = "Still loading, one sec." }
		end
		local level = Racing.level(profile)
		local cost = Racing.upgradeCost(level)
		if not cost then
			return { ok = false, err = "Already at top speed." }
		end
		if profile.money < cost then
			return { ok = false, err = "Need " .. Format.money(cost) .. "." }
		end
		profile.money -= cost
		profile.raceLevel = level + 1
		PlayerState.push(player)
		PlayerState.notify(player,
			("Speed %d/%d — you win more often, and each win pays less.")
				:format(profile.raceLevel, Racing.MaxLevel), "good")
		return { ok = true, level = profile.raceLevel }
	end

	Players.PlayerRemoving:Connect(function(player)
		running[player] = nil
	end)
end

return RaceService
