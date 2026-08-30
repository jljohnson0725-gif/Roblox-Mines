--[[
	PlayerState
	The single way the server tells a client what it owns.

	Exists so MinesService and PlotService don't have to know about each other
	just to refresh a money counter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local Items = require(Shared.Items)

local DataService = require(script.Parent.DataService)

local PlayerState = {}

--[[ Total across every collect strip -- the HUD only needs the one number. ]]
local function totalPending(profile)
	local sum = 0
	for i = 1, Config.MaxSlots do
		sum += profile.pending and profile.pending[i] or 0
	end
	return sum
end

PlayerState.totalPending = totalPending

--[[ Expiries turned into countdowns, dropping anything already finished so the
     client never has to reason about a zero. ]]
local function boostsRemaining(profile)
	local now, out = os.time(), {}
	for id in pairs(profile.boosts or {}) do
		local left = Items.remaining(profile, id, now)
		if left > 0 then
			out[id] = left
		end
	end
	return out
end

--[[
	Sync payloads are MERGED by the client, not replaced, so a frequent update
	can carry just the field that moved. The per-second income tick would
	otherwise be replicating the whole inventory to every player every second.
]]
function PlayerState.snapshot(player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	-- Cheap, and this is the one place every structural change funnels through,
	-- so the coach can never miss the moment it should switch off.
	DataService.refreshOnboarding(profile)

	return {
		money = profile.money,
		pending = totalPending(profile),
		slots = profile.slots,
		inventory = profile.inventory,
		-- multiplied, so the HUD matches what the strips actually fill at
		income = Economy.totalIncome(profile.inventory) * Upgrades.incomeMultiplier(profile),
		-- so the summon panel opens on the ride you took last time
		racer = profile.racer,
		upgrades = profile.upgrades or {},
		index = profile.index or {}, -- ["charId:variantId"] = times secured
		onboarding = profile.onboarding, -- drives the first-session coach
		plinkoball = profile.plinkoball == true, -- whether the rail shows PLINKO
		--[[ The shop rows read these to show OWNED instead of a price. The
		     appearance itself is server-made, so the client never acts on
		     them beyond that. ]]
		--[[ The shop prices the next one off this, and the Mines HUD counts
		     down from it. ]]
		lives = profile.lives or 0,
		--[[ The Race Lab reads its opening split from this, so a rejoin picks
		     up the runner you left rather than the default. NOT `racer`, which
		     is already the uid of the brainrot you summon -- coercing that to a
		     table would have broken MountService, RaceService and SummonUI at
		     once. ]]
		runner = profile.runner,
		cologne = profile.cologne == true,
		peptides = profile.peptides == true,
		whistle = profile.whistle == true, -- whether the ride button is there
		plinkoStake = profile.plinkoStake, -- the dial, so the panel reopens on it
		wheelStake = profile.wheelStake,
		--[[ REMAINING SECONDS, not the expiry stored on the profile. The client
		     counts down from what it was handed instead of comparing against its
		     own os.time(), which is a clock the server has no reason to trust and
		     no way to correct. See Shared/Items. ]]
		boosts = boostsRemaining(profile),
		rebirths = profile.rebirths or 0,
		stats = profile.stats,
		--[[ Named exactly as the profile names them, because Shared/Seals reads
		     both through the same functions -- the client tracker and the
		     server's gate must never be able to disagree about a seal. ]]
		fragments = profile.fragments or {},
		seals = profile.seals or {},
	}
end

--[[ Push the player's full owned-state. Call on any structural change. ]]
function PlayerState.push(player)
	local snapshot = PlayerState.snapshot(player)
	if snapshot then
		Net.get("Sync"):FireClient(player, snapshot)
	end
end

--[[ Money + pending only -- for the per-second income tick. ]]
function PlayerState.pushMoney(player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	Net.get("Sync"):FireClient(player, {
		money = profile.money,
		pending = totalPending(profile),
	})
end

--[[ kind: "great" | "good" | "bad" | "info" -- "great" is reserved for
     once-a-chapter events, currently only a completed seal. ]]
function PlayerState.notify(player, text, kind)
	Net.get("Notify"):FireClient(player, text, kind or "info")
end

return PlayerState
