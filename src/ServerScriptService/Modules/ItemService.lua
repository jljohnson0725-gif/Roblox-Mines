--[[
	ItemService
	Purchase logic for the items sold at the street shop, alongside the upgrades.

	Split from UpgradeService rather than bolted onto it because the two answer
	different questions. An upgrade asks "what level am I", once, forever. An
	item asks "is it running, and for how much longer" -- which needs a clock,
	an expiry sweep and a re-apply when it lapses. Sharing a module would have
	meant one file where half the code was about time and half wasn't.

	THE EXPIRY LOOP IS NOT OPTIONAL, and it is easy to think it is: Shared/Items
	already reports a lapsed boost as inactive, so income corrects itself with no
	help. Walk speed does not. That one is written onto the Humanoid at purchase
	and stays there until something writes it again -- so without this loop, one
	Energy Drink would be permanent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Items = require(Shared.Items)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local PlayerState = require(script.Parent.PlayerState)
local PlotService = require(script.Parent.PlotService)
local UpgradeService = require(script.Parent.UpgradeService)

local ItemService = {}

local SWEEP_INTERVAL = 5

-- ── purchasing ──────────────────────────────────────────────────────────────

--[[ Each kind resolves to a function that either does the thing and returns a
     result, or refuses BEFORE any money moves. Charging happens in buy(), once,
     after the handler has agreed -- so a refusal can never leave a player short
     of the cost of something they didn't get. ]]
local resolve = {}

function resolve.boost(player, profile, def)
	local now = os.time()
	local standing = math.max((profile.boosts[def.id] or now) - now, 0)
	if standing + def.duration > Items.MaxStack then
		return { ok = false, err = def.name .. " is stacked as high as it goes." }
	end
	return {
		ok = true,
		commit = function()
			profile.boosts[def.id] = now + standing + def.duration
			--[[ Walk speed lives on the Humanoid, so a speed boost has to be
			     written out at purchase; income is read from the profile every
			     time it's needed and looks after itself. ]]
			UpgradeService.applyToCharacter(player)
		end,
		message = standing > 0
			and (def.name .. " extended — " .. Format.duration(standing + def.duration) .. " left")
			or (def.name .. " active for " .. Format.duration(def.duration)),
	}
end

function resolve.unlock(player, profile, def)
	if profile[def.flag] == true then
		--[[ Not an error. Pressing buy on something you own almost always means
		     "how do I use this", so answer that instead of scolding. ]]
		PlayerState.notify(player, "You already own the " .. def.name .. ".", "info")
		return { ok = false, silent = true }
	end
	return {
		ok = true,
		commit = function()
			profile[def.flag] = true
		end,
		message = def.name .. " acquired.",
	}
end

function resolve.instant(player, profile, def)
	if def.id ~= "sweep" then
		return { ok = false, err = "Unknown item." }
	end
	--[[ Counted before charging, so nobody pays to sweep an empty base. This is
	     the reason resolve() runs before the money moves at all. ]]
	local waiting = PlayerState.totalPending(profile)
	if waiting < 1 then
		return { ok = false, err = "Nothing waiting to collect." }
	end
	return {
		ok = true,
		commit = function()
			local claimed = PlotService.sweep(player)
			PlayerState.notify(player, "Swept " .. Format.money(claimed), "good")
		end,
	}
end

function ItemService.buy(player, id)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if not ShopService.isNear(player) then
		return { ok = false, err = "Head to the shop." }
	end

	local def = Items.get(id)
	if not def then
		return { ok = false, err = "Unknown item." }
	end

	local handler = resolve[def.kind]
	if not handler then
		return { ok = false, err = "Unknown item." }
	end

	profile.boosts = profile.boosts or {}
	local verdict = handler(player, profile, def)
	if not verdict.ok then
		return { ok = false, err = verdict.err, silent = verdict.silent }
	end

	if profile.money < def.cost then
		return { ok = false, err = "Need " .. Format.money(def.cost) .. "." }
	end

	profile.money -= def.cost
	verdict.commit()

	PlayerState.push(player)
	if verdict.message then
		PlayerState.notify(player, verdict.message, "good")
	end
	return { ok = true, id = id }
end

-- ── expiry ──────────────────────────────────────────────────────────────────

--[[ Drop everything that has run out and report whether anything did. Kept
     separate from the loop so the reason to push is a return value rather than
     a flag set three lines away from where it's read. ]]
local function reap(profile, now)
	local lapsed = nil
	for id, expiry in pairs(profile.boosts or {}) do
		if expiry <= now then
			profile.boosts[id] = nil
			lapsed = lapsed or {}
			table.insert(lapsed, id)
		end
	end
	return lapsed
end

function ItemService.start()
	Net.get("BuyItem").OnServerInvoke = function(player, id)
		return ItemService.buy(player, id)
	end

	task.spawn(function()
		while true do
			task.wait(SWEEP_INTERVAL)
			local now = os.time()
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = DataService.get(player)
				local lapsed = profile and reap(profile, now)
				if lapsed then
					--[[ Re-apply before pushing, so the state the client is
					     handed already matches the character it describes. ]]
					UpgradeService.applyToCharacter(player)
					PlayerState.push(player)
					for _, id in ipairs(lapsed) do
						local def = Items.get(id)
						if def then
							PlayerState.notify(player, def.name .. " wore off.", "info")
						end
					end
				end
			end
		end
	end)
end

return ItemService
