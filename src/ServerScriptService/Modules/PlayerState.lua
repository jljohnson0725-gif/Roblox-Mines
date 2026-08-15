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
		upgrades = profile.upgrades or {},
		index = profile.index or {}, -- ["charId:variantId"] = times secured
		onboarding = profile.onboarding, -- drives the first-session coach
		jetpack = profile.jetpack == true, -- whether F does anything
		stats = profile.stats,
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

--[[ kind: "good" | "bad" | "info" ]]
function PlayerState.notify(player, text, kind)
	Net.get("Notify"):FireClient(player, text, kind or "info")
end

return PlayerState
