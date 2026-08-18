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
		--[[
			Everything you have EVER secured, as ["charId:variantId"] = count.

			Separate from inventory on purpose: storage takes brainrots
			out of your inventory permanently, and a collection you can lose by
			selling isn't a collection. String keys because a pair needs both
			halves, and because JSON round-trips string keys unchanged -- the
			same trap `pending` had to be a dense array to avoid.
		]]
		index = {},
		redeemed = {}, -- [CODE] = true; codes are one use each
		jetpack = false, -- bought once at the launch pad, then owned forever
		rebirths = 0, -- permanent luck; see Shared/Rebirth
		--[[ Racing is a PLAYER stat, not a per-brainrot one -- the summoned
		     brainrot is fashion, so speed lives here and applies whichever one
		     you ride. `racer` is the uid you picked to summon; nil means your
		     best earner turns up. ]]
		raceLevel = 0,
		racer = nil,
		--[[ [sealId] = fragments held. Fragments rather than whole seals so a
		     losing streak still advances you; see Shared/Islands. ]]
		fragments = {},
		seals = {}, -- [sealId] = true once its fragments were spent
		--[[ First-session state. `drops` is how many guaranteed finds are left,
		     `collected` records that a cash pile has actually been banked (the
		     coach's last step reads it), and `done` latches once the whole loop
		     has worked, so the coach never returns for an existing player. ]]
		onboarding = { drops = Config.OnboardingDrops, collected = false, done = false },
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
	if type(profile.index) ~= "table" then
		profile.index = {}
	end
	if type(profile.redeemed) ~= "table" then
		profile.redeemed = {}
	end
	profile.jetpack = profile.jetpack == true
	profile.rebirths = math.max(math.floor(tonumber(profile.rebirths) or 0), 0)
	if type(profile.fragments) ~= "table" then profile.fragments = {} end
	if type(profile.seals) ~= "table" then profile.seals = {} end
	if type(profile.onboarding) ~= "table" then
		profile.onboarding = { drops = Config.OnboardingDrops, collected = false, done = false }
	end
	profile.onboarding.drops = tonumber(profile.onboarding.drops) or 0
	profile.onboarding.collected = profile.onboarding.collected == true
	profile.onboarding.done = profile.onboarding.done == true

	--[[ Saves made before the index existed still hold proof of discovery in
	     the inventory, so seed from it rather than starting everyone at zero. ]]
	for _, item in ipairs(profile.inventory) do
		local key = item.charId .. ":" .. item.variantId
		if profile.index[key] == nil then
			profile.index[key] = 1
		end
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

--[[
	Record a (character, variant) pair as discovered.

	Called when a drop is SECURED, never when it's found: an unsecured brainrot
	lost to a mine was never yours, and having it show up in your collection
	would quietly undercut the one rule the whole game rests on.
]]
function DataService.recordIndex(profile, charId, variantId)
	profile.index = profile.index or {}
	local key = charId .. ":" .. variantId
	profile.index[key] = (profile.index[key] or 0) + 1
end

--[[
	Latch the first-session coach off once the whole loop has demonstrably
	worked: something banked, something standing on a pad, and a pile actually
	collected. All three, because the last step of the coach IS the collect and
	latching before it would hide the card mid-lesson.

	Derived rather than driven by a "tutorial finished" button, because those
	three facts ARE the tutorial. A returning player already satisfies all of
	them, so the coach never reappears, and nobody can get stuck on a step by
	dismissing something.
]]
function DataService.refreshOnboarding(profile)
	local ob = profile.onboarding
	if not ob or ob.done then
		return
	end
	if next(profile.index or {}) == nil or not ob.collected then
		return
	end
	for _, item in ipairs(profile.inventory) do
		if item.pad then
			ob.done = true
			return
		end
	end
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
