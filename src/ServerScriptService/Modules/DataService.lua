--[[
	DataService
	Profile load / save / autosave.

	NOT session-locked. If you ship this and players start hopping servers, swap
	this module for ProfileService -- the API below (load/get/save/release) is
	deliberately the same shape so it's a drop-in. See DESIGN.md.

	In Studio without API access enabled, every DataStore call fails. That's
	handled: the player just gets a fresh in-memory profile so you can still
	playtest. Look for the "running without persistence" warning.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = {}

local store
local persistenceOk = true

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		persistenceOk = false
		warn("[DataService] running without persistence: " .. tostring(result))
	end
end

local profiles = {} -- [userId] = profile

local function newProfile()
	return {
		money = Config.StartingMoney,
		slots = Config.StartingSlots,
		nextUid = 1,
		lasersOn = true, -- base door armed; toggled by the red button inside
		-- Per-slot, not one total: "collect this brainrot" can't be expressed
		-- without it. Stored as a dense 1..MaxSlots array on purpose -- a sparse
		-- table would JSON-encode to an object and come back with STRING keys,
		-- silently breaking every numeric lookup after a reload.
		pending = table.create(Config.MaxSlots, 0),
		upgrades = {}, -- [upgradeId] = level; absent means 0
		inventory = {}, -- array of { uid, charId, variantId, pad = number? }
		stats = {
			rounds = 0,
			busts = 0,
			bestMultiplier = 1,
			bestDrop = nil,
		},
	}
end

--[[ Fills in anything a newer version added, so old saves keep loading. ]]
local function reconcile(profile)
	local template = newProfile()
	for key, value in pairs(template) do
		if profile[key] == nil then
			profile[key] = value
		end
	end
	for key, value in pairs(template.stats) do
		if profile.stats[key] == nil then
			profile.stats[key] = value
		end
	end

	if type(profile.upgrades) ~= "table" then
		profile.upgrades = {}
	end

	-- Old saves stored pending as a single number; and any save could carry an
	-- array sized for a different MaxSlots.
	if type(profile.pending) ~= "table" then
		profile.pending = table.create(Config.MaxSlots, 0)
	end
	for i = 1, Config.MaxSlots do
		profile.pending[i] = tonumber(profile.pending[i]) or 0
	end
	for i = Config.MaxSlots + 1, #profile.pending do
		profile.pending[i] = nil
	end

	-- Drop anything referring to a character that no longer exists in the roster,
	-- and clamp pads that fell outside an (unlikely) shrunk slot count.
	local Brainrots = require(Shared.Brainrots)
	local cleaned = {}
	local seenPads = {}
	for _, item in ipairs(profile.inventory) do
		if Brainrots.get(item.charId) then
			if item.pad and (item.pad > profile.slots or seenPads[item.pad]) then
				item.pad = nil
			end
			if item.pad then
				seenPads[item.pad] = true
			end
			table.insert(cleaned, item)
		end
	end
	profile.inventory = cleaned

	return profile
end

local function keyFor(userId)
	return "player_" .. userId
end

function DataService.load(player)
	local userId = player.UserId
	local profile

	if persistenceOk then
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(userId))
		end)
		if ok and type(result) == "table" then
			profile = reconcile(result)
		elseif not ok then
			-- Do NOT hand out a fresh profile on a read error -- that would wipe a
			-- real save on the next write. Mark it unsaveable instead.
			warn(string.format("[DataService] load failed for %s: %s", player.Name, tostring(result)))
			profile = newProfile()
			profile.__readFailed = true
		end
	end

	profile = profile or newProfile()
	profiles[userId] = profile
	return profile
end

function DataService.get(player)
	return profiles[player.UserId]
end

function DataService.save(player)
	local profile = profiles[player.UserId]
	if not profile or not persistenceOk then
		return false
	end
	if profile.__readFailed then
		return false -- never overwrite a save we couldn't read
	end

	local snapshot = HttpService:JSONDecode(HttpService:JSONEncode(profile))
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player.UserId), snapshot)
	end)
	if not ok then
		warn(string.format("[DataService] save failed for %s: %s", player.Name, tostring(err)))
	end
	return ok
end

function DataService.release(player)
	DataService.save(player)
	profiles[player.UserId] = nil
end

--[[ Mints a stable per-profile id for one owned brainrot. ]]
function DataService.nextUid(profile)
	local uid = profile.nextUid or 1
	profile.nextUid = uid + 1
	return "b" .. uid
end

function DataService.findItem(profile, uid)
	for index, item in ipairs(profile.inventory) do
		if item.uid == uid then
			return item, index
		end
	end
	return nil
end

function DataService.itemOnPad(profile, pad)
	for _, item in ipairs(profile.inventory) do
		if item.pad == pad then
			return item
		end
	end
	return nil
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Config.AutoSaveInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				if profiles[player.UserId] then
					DataService.save(player)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.save(player)
		end
		if not RunService:IsStudio() then
			task.wait(2) -- let the writes land
		end
	end)
end

return DataService
