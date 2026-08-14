--[[
	Bootstrap
	The only Script in the game. Requires the services in dependency order,
	wires player lifecycle, and runs the passive income tick.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net) -- requiring this on the server BUILDS the remotes
local Economy = require(Shared.Economy)

local Modules = ServerScriptService:WaitForChild("Modules")
local MapStyle = require(Modules.MapStyle)
local DataService = require(Modules.DataService)
local PlayerState = require(Modules.PlayerState)
local EventService = require(Modules.EventService)
local PlotService = require(Modules.PlotService)
local MinesLandmark = require(Modules.MinesLandmark)
local AuctionService = require(Modules.AuctionService)
local HubService = require(Modules.HubService)
local ShopService = require(Modules.ShopService)
local UpgradeService = require(Modules.UpgradeService)
local WheelService = require(Modules.WheelService)
local MinesService = require(Modules.MinesService)

-- ── Startup ─────────────────────────────────────────────────────────────────

-- Restyle first: PlotService caches each pad's colour when it attaches, so the
-- map has to be in its final look before that happens.
local styled, shrooms = MapStyle.apply()
print(("[MapStyle] daylight pass: %d parts restyled, %d mushrooms"):format(styled, shrooms))

--[[ Set on StarterPlayer as well as per-character. UpgradeService applies the
     upgraded speed a frame after the character spawns, and without this the
     player gets Roblox's default 16 for that frame -- a visible stutter on every
     respawn. ]]
game:GetService("StarterPlayer").CharacterWalkSpeed = Config.BaseWalkSpeed

DataService.start()
EventService.start()

-- Before PlotService: it attaches to the bases that exist when it starts, so
-- the one the wheel replaces has to be gone first.
WheelService.clearSite()

PlotService.start()
MinesService.start()

-- Built after the restyle so they sit on the final map, and after EventService
-- so the landmark's rings can pick up whatever event is already running.
HubService.start()
ShopService.start()
MinesLandmark.build()
MinesLandmark.startEventSync()
UpgradeService.start()

-- The auction's proximity gate is the hub's consign desk, which only exists
-- once HubService has built the room -- so the handoff happens here rather than
-- either module reaching into the other.
AuctionService.desk = HubService.desk
AuctionService.start()
HubService.startBlockDisplay()

-- The wheel is the only source of Secrets. Its site was cleared above.
WheelService.start()

Net.get("RequestState").OnServerInvoke = function(player)
	local snapshot = PlayerState.snapshot(player)
	if snapshot then
		-- Event state is global, not per-player, so it rides along on the pull
		-- rather than living in the profile snapshot.
		snapshot.event = EventService.snapshot()
	end
	return snapshot
end

-- ── Player lifecycle ────────────────────────────────────────────────────────

local function onCharacterAdded(player, character)
	-- One frame for the character to finish assembling before we move it.
	task.defer(function()
		PlotService.spawnAt(player, character)
	end)
end

local function onPlayerAdded(player)
	DataService.load(player)
	PlotService.assign(player)
	PlotService.refresh(player)
	PlayerState.push(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
		UpgradeService.applyToCharacter(player)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Studio "Play Solo" can add the player before this script runs.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Connected last, so the services above still see a live profile as they
-- clean up their own per-player state.
Players.PlayerRemoving:Connect(function(player)
	DataService.release(player)
end)

-- ── Passive income ──────────────────────────────────────────────────────────

task.spawn(function()
	while true do
		local elapsed = task.wait(Config.IncomeTickRate)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.get(player)
			if profile then
				local rate = Economy.totalIncome(profile.inventory)

				-- Income accrues to the collect strips, NOT straight to the
				-- wallet. Capped per slot, so leaving forever stops paying and
				-- coming back to collect stays worth doing.
				if rate > 0 then
					PlotService.accrue(player, elapsed)
				end

				-- Render and collect run even at zero income: cash can still be
				-- sitting on a strip whose brainrot has since been stored, and
				-- skipping these would strand it permanently.
				PlotService.renderPiles(player)
				PlotService.tickCollect(player)

				if rate > 0 then
					PlayerState.pushMoney(player)
				elseif profile.money < Config.MinBet and PlayerState.totalPending(profile) < Config.MinBet then
					-- Broke with nothing earning: hand them back into the loop
					-- rather than leaving them softlocked at the table.
					profile.money = Config.BrokeStipend
					PlayerState.push(player)
					PlayerState.notify(player, "Here's " .. Config.BrokeStipend .. " to get back in.", "info")
				end
			end
		end
	end
end)

print("[BrainrotMines] server up")
