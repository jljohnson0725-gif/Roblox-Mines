--[[
	JetpackService
	Decides who is allowed to be in the air. Nothing else.

	IT USED TO OWN A LAUNCH PAD TOO -- a deck and a console on the main walk,
	which is where you went to buy the jetpack. The shop sells it now, and the
	pad had no second job: flight is bound to F and works anywhere, so a
	structure whose only purpose was a purchase became a landmark that meant
	nothing. It is gone rather than left standing as decoration.

	BOUGHT ONCE. The flag lives on the profile, so it survives rejoining and
	there is no second transaction ever. Charging per flight would price the
	sky by the trip and put a small purchase decision in front of every ascent,
	which is the surest way to keep people on the ground.

	The server does NOT fly anybody. Character physics are owned by the client
	that the character belongs to, so driving flight from here would mean
	fighting network ownership for the privilege of adding latency to it. What
	the server owns is the PERMISSION -- and the attribute, which is how every
	other client learns to draw the ascension pose on this player. See
	StarterPlayerScripts/UI/Flight.lua for the pose itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local JetpackService = {}

local ASCENDING = "Ascending"

-- ── permission to be in the air ─────────────────────────────────────────────

--[[
	The client says it is flying; this decides whether that is allowed and, if
	so, tells everyone. The attribute is what every other client reads to draw
	the ascension pose, so this call is the only thing standing between "I own
	a jetpack" and "everyone can see me use it".
]]
function JetpackService.setFlying(player, wants)
	local character = player.Character
	if not character then
		return
	end

	local profile = DataService.get(player)
	local allowed = wants == true and profile ~= nil and profile.jetpack == true
	character:SetAttribute(ASCENDING, allowed)
end

function JetpackService.start()
	Net.get("SetFlying").OnServerEvent:Connect(function(player, wants)
		JetpackService.setFlying(player, wants)
	end)

	--[[ A fresh character has no attribute and is therefore not flying, which
	     is correct -- but the flag has to be cleared on respawn anyway so a
	     player who dies mid-air doesn't land already posed. ]]
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			character:SetAttribute(ASCENDING, false)
		end)
	end

	-- Existing players too: in Studio the local player is usually in before
	-- Bootstrap finishes, and PlayerAdded alone would never see them.
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return JetpackService
