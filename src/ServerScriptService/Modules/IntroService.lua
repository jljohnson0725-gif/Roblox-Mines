--[[
	IntroService
	Decides who has never seen the cold open, and marks it seen.

	THE SCENE ITSELF IS CLIENT-SIDE -- see UI/Intro. It is one player's ten
	seconds, on a set nobody else can walk into; the server's only job is
	remembering whether they have had it.

	MARKED SEEN ON SEND, NOT ON FINISH. If it were confirmed by the client the
	obvious failure is the worst one: quit halfway through, rejoin, watch it
	again, quit halfway through. A player who misses the opening once has lost
	a cutscene; a player caught in that loop has lost the game. Wrong in the
	recoverable direction on purpose.

	FIRED AFTER A BEAT rather than the instant they join. The client is still
	building its UI and streaming the world in on the first frames, and a
	camera sequence starting into that judders through the opening shot -- the
	one shot that has to look composed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local IntroService = {}

--[[ Long enough for the client's UI and the map around the spawn to settle.
     Tuned against a cold join, which is the only join that ever sees this. ]]
local SETTLE = 2.5

function IntroService.consider(player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if type(profile.onboarding) ~= "table" then
		return
	end
	if profile.onboarding.introSeen then
		return
	end

	profile.onboarding.introSeen = true

	task.delay(SETTLE, function()
		if player.Parent then
			Net.get("PlayIntro"):FireClient(player)
		end
	end)
end

function IntroService.start()
	--[[ Also offered as a remote so it can be replayed deliberately -- for
	     testing, and because "watch the intro again" is a reasonable thing to
	     want from a menu later. It does not touch the seen flag. ]]
	Net.get("ReplayIntro").OnServerInvoke = function(player)
		Net.get("PlayIntro"):FireClient(player)
		return { ok = true }
	end
end

return IntroService
