--[[
	RebirthService
	Spend the run, keep the luck.

	THIS IS THE ONLY OPERATION IN THE GAME THAT DESTROYS PLAYER PROPERTY, so it
	is written as a list of what SURVIVES rather than a list of what to clear.
	Wiping by omission is how a future field gets silently deleted the first
	time somebody adds one: anything new defaults to being kept, which is the
	safe direction to be wrong in.

	THE INDEX SURVIVES, and that is not a courtesy. DataService already keeps
	the index separate from inventory because "a collection you can lose by
	selling isn't a collection" -- rebirth is the same argument with more force.
	Wipe it and every player loses proof of every Secret they ever found, which
	is the one thing in this game that cannot be re-earned on demand.

	The jetpack survives because it was sold as "yours for good", and seals and
	fragments survive because they are chapter progress rather than economy --
	a player who has opened an island should not have to open it again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Rebirth = require(Shared.Rebirth)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local PlotService = require(script.Parent.PlotService)

local RebirthService = {}

--[[
	Fields carried across untouched. Everything not named here is reset.

	Listed rather than deleted-by-name on purpose -- see the note above. If you
	add a profile field and it belongs to the player rather than to the run, it
	goes in this table.
]]
local KEEP = {
	index = true, -- every pair ever secured; the collection
	redeemed = true, -- codes are one use per account, not per run
	jetpack = true, -- sold as "yours for good"
	fragments = true, -- chapter progress, not economy
	seals = true,
	rebirths = true, -- obviously
	nextUid = true, -- ids must stay unique across runs
	stats = true, -- lifetime, not per-run
	onboarding = true, -- never make someone sit the tutorial twice
}

function RebirthService.perform(player)
	local profile = DataService.get(player)
	local ok, err, cost = Rebirth.check(profile)
	if not ok then
		return {
			ok = false,
			err = err or ("Need " .. Format.money(cost) .. " to rebirth."),
		}
	end

	local level = (profile.rebirths or 0) + 1
	local fresh = {}

	--[[ Build the new run beside the old one rather than editing in place, so a
	     mistake here cannot half-destroy a profile. ]]
	for key, value in pairs(profile) do
		if KEEP[key] then
			fresh[key] = value
		end
	end

	fresh.rebirths = level
	fresh.money = Config.StartingMoney
	fresh.slots = Rebirth.startPads(level)
	fresh.upgrades = {}
	fresh.inventory = {}
	fresh.pending = table.create(Config.MaxSlots, 0)

	for key in pairs(profile) do
		profile[key] = nil
	end
	for key, value in pairs(fresh) do
		profile[key] = value
	end

	--[[ The pads still hold models for brainrots that no longer exist. Rebuild
	     before pushing, or the base shows a collection the profile has lost. ]]
	PlotService.refresh(player)
	PlayerState.push(player)
	PlayerState.notify(player, ("Rebirth %d — luck +%.2f, %d pads to start")
		:format(level, Rebirth.luck(level), fresh.slots), "good")

	--[[ Loud on purpose. Rebirth is the rarest thing anyone does here, and a
	     server that never mentions it makes it look like it did nothing. ]]
	Net.get("Announce"):FireAllClients({
		kind = "rebirth",
		who = player.DisplayName,
		level = level,
	})

	return { ok = true, rebirths = level, luck = Rebirth.luck(level) }
end

function RebirthService.start()
	Net.get("DoRebirth").OnServerInvoke = function(player)
		return RebirthService.perform(player)
	end
end

return RebirthService
