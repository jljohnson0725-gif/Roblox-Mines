--[[
	Net
	Creates (server) or waits for (client) every remote in one place, so neither
	side can typo a remote name into a silent failure.

	Requiring this on the server has the side effect of building the folder --
	Bootstrap does that first, before anything else touches it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- client -> server, expects a reply
local FUNCTIONS = {
	"StartRound",
	"RevealTile",
	"CashOut",
	"PlaceBrainrot",
	"BuySlot",
	"EquipBest", -- auto-place the highest-earning brainrots
	"RequestState", -- client pulls on startup, so it can't miss the first push
}

-- server -> client, fire and forget
local EVENTS = {
	"Sync", -- full player state (money / slots / inventory)
	"Notify", -- toast message
	"OpenPicker", -- a pad prompt was triggered; open the inventory picker for it
	"Announce", -- broadcast: somebody found (or lost) a Mythic/Secret
	"EventState", -- broadcast: an event started or ended
	"OpenMines", -- the landmark's console was used
}

local folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end

	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes", 30)
	assert(folder, "[Net] Remotes folder never replicated -- is the server Bootstrap running?")
end

function Net.get(name)
	local remote = folder:WaitForChild(name, 15)
	assert(remote, string.format("[Net] unknown remote %q", tostring(name)))
	return remote
end

return Net
