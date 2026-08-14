--[[
	probe_onboarding.luau
	Paste into Studio's command bar (Edit mode) to test the first-session
	guarantee without running the game.

	WHY THIS EXISTS. Studio's play-mode MCP bridge is unreliable -- for a whole
	session it answered in Edit and returned "Target is not reachable" for Client
	and Server. This drives MinesService directly instead, so the server logic can
	be checked from Edit mode alone.

	HOW IT WORKS. MinesService only needs `player.UserId` plus a profile, so a
	plain table stands in for a Player. The two calls that need a real Player
	instance (PlayerState.push / notify) are stubbed first -- replacing fields on
	the required table works because MinesService looks them up at call time, and
	requires return the same cached table.

	CAUTION: the Edit DataModel caches ModuleScript results. If you edit a script
	and re-run this, RELOAD THE PLACE first or you will be testing the old code.

	Expected output:
	  drops=2 -> 100%, drops=0 -> ~18%
	  banking spends one, busting never does, index ignores unsecured drops
]]

local SSS = game:GetService("ServerScriptService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PlayerState = require(SSS.Modules.PlayerState)
PlayerState.push = function() end
PlayerState.pushMoney = function() end
PlayerState.notify = function() end

local DataService = require(SSS.Modules.DataService)
local MinesService = require(SSS.Modules.MinesService)

local fake = { UserId = 424242, Name = "Probe", DisplayName = "Probe" }

local function freshProfile(drops)
	local p = DataService.load(fake)
	p.money = 1000000
	p.index = {}
	p.onboarding = { drops = drops, collected = false, done = false }
	return p
end

--[[ Play until a round survives its first tile, then report whether that first
     safe tile produced a drop. ]]
local function dropOnFirstSafeTile()
	for _ = 1, 80 do
		local r = MinesService.startRound(fake, 10, 3)
		if r.ok then
			local rev = MinesService.revealTile(fake, math.random(1, 25))
			if rev.ok and not rev.mine then
				local drop = rev.drop ~= nil
				MinesService.cashOut(fake)
				return drop
			end
		end
	end
	return nil
end

print("── drop on the FIRST safe tile ──────────────────────────────")
for _, guarantee in ipairs({ Config.OnboardingDrops, 0 }) do
	local hits, trials = 0, 200
	for _ = 1, trials do
		freshProfile(guarantee)
		if dropOnFirstSafeTile() then
			hits += 1
		end
	end
	print(("  drops=%d  ->  %3d/%d  (%.0f%%)"):format(guarantee, hits, trials, hits / trials * 100))
end
print("  base chance at 3 mines is 18%")

print("── a bust must not burn a guarantee ─────────────────────────")
local p = freshProfile(2)
local busts, lost = 0, 0
for _ = 1, 60 do
	local r = MinesService.startRound(fake, 10, 12)
	if r.ok then
		local saw = false
		for _ = 1, 25 do
			local rev = MinesService.revealTile(fake, math.random(1, 25))
			if not rev.ok then
				break
			end
			saw = saw or rev.drop ~= nil
			if rev.mine then
				busts += 1
				lost = lost + (saw and 1 or 0)
				break
			end
		end
	end
end
print(("  %d busts, %d of them lost a drop -> guarantees still %d (want 2)")
	:format(busts, lost, p.onboarding.drops))

local n = 0
for _ in pairs(p.index) do
	n += 1
end
print(("  index entries after busting: %d (want 0 -- unsecured is not yours)"):format(n))
