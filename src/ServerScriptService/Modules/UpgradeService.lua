--[[
	UpgradeService
	Purchase logic for the upgrades sold in the Auction House.

	ShopService builds and owns the street kiosk. This module keeps only the
	purchase logic, which is the part that has to be server-authoritative.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Upgrades = require(Shared.Upgrades)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local PlayerState = require(script.Parent.PlayerState)

local UpgradeService = {}

-- ── purchasing ──────────────────────────────────────────────────────────────

function UpgradeService.buy(player, id)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if not ShopService.isNear(player) then
		return { ok = false, err = "Head to the upgrade shop." }
	end

	local def = Upgrades.get(id)
	if not def then
		return { ok = false, err = "Unknown upgrade." }
	end

	profile.upgrades = profile.upgrades or {}
	local level = profile.upgrades[id] or 0
	if level >= def.maxLevel then
		return { ok = false, err = def.name .. " is maxed." }
	end

	local cost = Upgrades.cost(id, level)
	if profile.money < cost then
		return { ok = false, err = "Need " .. Format.money(cost) .. "." }
	end

	profile.money -= cost
	profile.upgrades[id] = level + 1

	UpgradeService.applyToCharacter(player)
	PlayerState.push(player)
	PlayerState.notify(player, def.name .. " -> level " .. (level + 1), "good")

	return { ok = true, id = id, level = level + 1 }
end

--[[ Walk speed is the one upgrade that lives on the character, so it has to be
     re-applied every time one spawns as well as at purchase. ]]
function UpgradeService.applyToCharacter(player)
	local profile = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if profile and humanoid then
		humanoid.WalkSpeed = Upgrades.walkSpeed(profile)
	end
end

function UpgradeService.start()
	Net.get("BuyUpgrade").OnServerInvoke = function(player, id)
		return UpgradeService.buy(player, id)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				UpgradeService.applyToCharacter(player)
			end)
		end)
	end)
end

return UpgradeService
