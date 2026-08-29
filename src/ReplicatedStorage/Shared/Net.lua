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
	"BuyUpgrade", -- purchase one level of an upgrade
	"BuyItem", -- purchase a boost, an unlock or a one-shot from the same shop
	"SpinWheel", -- wager everything on the wheel
	"WheelStake", -- what that wager currently consists of
	"RedeemCode", -- one-use reward codes
	"DropBall", -- one Plinko ball; resolves when it lands in a bin
	"DoRebirth", -- spend the run for permanent luck
	"SummonMount", -- ride the brainrot you picked
	"AskSummon", -- may I open the ride chooser? whistle + seal + a brainrot
	"EnterRace", -- stake a race on one of the fields
	"RaceOdds", -- the field list with this player's odds
	"BuyRaceSpeed", -- one level of racing consistency
	--[[ The duel handshake. All three are RemoteFunctions rather than events
	     because every one of them is an ANSWER -- yes, no, this is my wager --
	     and the caller needs to know it landed. A dropped "I accept" that the
	     client believes went through is the difference between standing in an
	     arena and standing in the street. ]]
	"DuelRespond", -- yes / no to an offer to make this fight a duel
	"DuelWager", -- put a stake up, deny theirs, or walk away
	"DuelBet", -- a spectator backs one of the two
	"RequestState", -- client pulls on startup, so it can't miss the first push
	"ReplayIntro", -- run the cold open again on demand; does not clear the seen flag
}

--[[
	Fire and forget. Server -> client unless marked otherwise: the two
	directions share a class, and the only client -> server event here is
	SetFlying, which is announcing something rather than asking for it.
]]
local EVENTS = {
	--[[ client -> server. The client owns its own character's physics, so it
	     flies itself and merely reports it; the server decides whether that is
	     allowed and publishes the pose attribute. ]]
	"SetFlying",
	--[[ client -> server. The tour runs entirely on the client -- it is a
	     camera and a dialogue card -- so the server only needs telling that it
	     finished, to latch the flag that stops it being offered again. ]]
	"FinishTour",
	"Sync", -- full player state (money / slots / inventory)
	"Notify", -- toast message
	"OpenPicker", -- a pad prompt was triggered; open the inventory picker for it
	"Announce", -- broadcast: somebody found (or lost) a Mythic/Secret
	"EventState", -- broadcast: an event started or ended
	"OpenMines", -- the landmark's console was used
	"OpenUpgrades", -- the shop counter was used
	"OpenSummon", -- server says go ahead: let them pick a ride
	"OpenRace", -- the podium was used; show the fields
	"OpenWheel", -- the wheel console was used
	"OpenPlinko", -- the machine was used; let them set a stake and drop
	"PlayIntro", -- roll the cold open on this client
	--[[ client -> server. The client reports a swing; the server decides
	     whether it connected. Deliberately an event and not a function: a
	     punch has no answer the attacker needs to wait for, and making it a
	     function would put a round trip in front of every click. ]]
	"Attack",
	--[[ client -> server. Announcing, not asking: the dash has already
	     happened locally by the time this is sent. It exists purely so the
	     sound can be played somewhere everyone can hear it -- a Sound created
	     on the dasher's own client is audible to the dasher alone. ]]
	"Dashed",
	"DuelOffer", -- the other player hit back: do you both want this to count?
	"DuelState", -- negotiation and fight state, to the two in it
	"DuelBoard", -- broadcast: a duel opened, closed its book, or resolved
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
