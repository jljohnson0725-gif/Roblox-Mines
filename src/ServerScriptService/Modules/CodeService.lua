--[[
	CodeService
	Redeemable codes, one use per player.

	Server-authoritative for the obvious reason: the reward is money, and the
	client is only ever telling us what someone typed.

	The gate that matters is `testOnly`. WHEELTEST hands out $10.5M, which is
	fine on a test server and ruinous on a public one -- so a testOnly code is
	refused unless the game is running in Studio or the redeemer is listed in
	Config.CodeAdmins. Leaving one in the table is therefore safe by default
	rather than safe if you remember.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Format)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)

local CodeService = {}

local admins = {}
for _, userId in ipairs(Config.CodeAdmins or {}) do
	admins[userId] = true
end

--[[ Players paste codes out of videos, so match generously: trim, strip inner
     spaces, and ignore case. The stored key is the canonical form. ]]
local function normalise(input)
	if type(input) ~= "string" then
		return nil
	end
	local cleaned = input:gsub("%s", ""):upper()
	if #cleaned == 0 or #cleaned > 32 then
		return nil
	end
	return cleaned
end

function CodeService.redeem(player, input)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end

	local code = normalise(input)
	if not code then
		return { ok = false, err = "Type a code first." }
	end

	local reward = Config.Codes[code]
	if not reward then
		return { ok = false, err = "That code isn't a thing." }
	end

	if reward.testOnly and not (RunService:IsStudio() or admins[player.UserId]) then
		-- deliberately the same message as an unknown code: telling people a
		-- secret code exists but isn't for them just invites guessing
		return { ok = false, err = "That code isn't a thing." }
	end

	profile.redeemed = profile.redeemed or {}
	if profile.redeemed[code] then
		return { ok = false, err = "You've already used that one." }
	end

	profile.redeemed[code] = true
	profile.money += reward.money or 0

	PlayerState.push(player)
	PlayerState.notify(player,
		("%s — %s"):format(Format.money(reward.money or 0), reward.blurb or "redeemed"), "good")

	return {
		ok = true,
		code = code,
		money = reward.money or 0,
		blurb = reward.blurb,
	}
end

function CodeService.start()
	Net.get("RedeemCode").OnServerInvoke = function(player, input)
		return CodeService.redeem(player, input)
	end
end

return CodeService
