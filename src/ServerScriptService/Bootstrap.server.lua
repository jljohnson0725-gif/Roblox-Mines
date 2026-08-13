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
local DataService = require(Modules.DataService)
local PlayerState = require(Modules.PlayerState)
local EventService = require(Modules.EventService)
local PlotService = require(Modules.PlotService)
local MinesService = require(Modules.MinesService)

-- ── Startup ─────────────────────────────────────────────────────────────────

DataService.start()
EventService.start()
PlotService.start()
MinesService.start()

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

				if rate > 0 then
					profile.money += rate * elapsed
					PlayerState.pushMoney(player)
				elseif profile.money < Config.MinBet then
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
