--[[
	EventService
	Runs the server-wide event cycle.

	── Why the next event is PRE-ROLLED ────────────────────────────────────────
	Events are chance-based, but the UI has to show an honest countdown to the
	next one. Those two requirements fight: if you roll at the moment the timer
	expires, the timer is really "next dice roll" and might produce nothing.

	So the roll happens the instant the previous event ENDS -- both the gap
	length (random inside a range) and which event it'll be. The countdown is
	then a real deadline, and the chance is still entirely intact; it just got
	resolved earlier than it was displayed.

	The chosen event is deliberately NOT revealed during the countdown. Knowing
	"Cosmic in 3:40" would teach players to stop playing and wait for it, which
	is exactly the trap called out in DESIGN.md.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Events = require(Shared.Events)

local EventService = {}

local rng = Random.new()

local state = {
	activeId = nil,
	endsAt = 0,
	nextAt = 0,
}
local pending = nil -- the pre-rolled event, hidden until it starts

--[[
	Server clock, synced to clients. os.time() would drift against the client;
	GetServerTimeNow is the primitive built for exactly this.
]]
local function now()
	return Workspace:GetServerTimeNow()
end

function EventService.snapshot()
	return {
		activeId = state.activeId,
		endsAt = state.endsAt,
		nextAt = state.nextAt,
	}
end

--[[ Modifier bag for the running event, or nil. Read live on every roll, so an
     event starting mid-round applies from that tile onward. ]]
function EventService.currentMods()
	return Events.modsFor(state.activeId)
end

local function broadcast()
	Net.get("EventState"):FireAllClients(EventService.snapshot())
end

local function scheduleNext()
	state.activeId = nil
	state.endsAt = 0
	state.nextAt = now() + rng:NextNumber(Config.EventGapMin, Config.EventGapMax)
	pending = Events.pick(rng)
	broadcast()
end

local function startEvent()
	local def = pending or Events.pick(rng)
	pending = nil

	state.activeId = def.id
	state.endsAt = now() + def.duration
	state.nextAt = 0
	broadcast()

	print(string.format("[Events] %s started for %ds", def.name, def.duration))
end

function EventService.start()
	scheduleNext()

	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			if state.activeId then
				if t >= state.endsAt then
					scheduleNext()
				end
			elseif t >= state.nextAt then
				startEvent()
			end
		end
	end)

	-- A joining player needs the clock immediately; their RequestState pull
	-- covers it, but this closes the gap if they join mid-transition.
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			Net.get("EventState"):FireClient(player, EventService.snapshot())
		end)
	end)
end

return EventService
