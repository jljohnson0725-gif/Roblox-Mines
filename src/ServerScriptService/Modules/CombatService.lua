--[[
	CombatService
	Punching, and the bookkeeping that turns a punch into an offer.

	THE SERVER DECIDES WHAT CONNECTED. The client sends one thing -- "I swung"
	-- and nothing else. It does not say who it hit, how hard, or from where,
	because every one of those is a number a modified client would be delighted
	to choose. Range, arc, cooldown and damage are all resolved here against
	positions the server already has.

	WHY A SWING IS AN EVENT AND NOT A FUNCTION. A punch has no answer worth
	waiting for. Making it a RemoteFunction would put a round trip in front of
	every click and, worse, would let a client hold the invocation open. The
	attacker's own animation plays locally the instant they click; whether it
	landed is something they find out from the other player's health bar, the
	same as everyone watching.

	STREET FIGHTS ARE A MEMORY, NOT A STATE. There is no object representing
	"A and B are fighting". There is only a note that A hit B, and when it was.
	That note is what makes retaliation detectable -- B hitting A back inside
	the memory window is the trigger for the duel offer -- and it expires on
	its own, so a punch thrown at someone you then forget about cannot open a
	wager prompt half an hour later.

	NOTHING HERE MOVES AN ITEM. This module can take health off a player and
	that is the whole of its authority; every transfer of anything valuable
	lives in DuelService, behind two explicit consents. Keeping the two apart
	is what makes it safe for punching to be unrestricted.

	IT ALSO OWNS THE DASH'S SOUND, and only its sound. The dash itself is
	entirely client-side -- see UI/Dash for why -- but a Sound created on the
	dasher's own client is audible to the dasher alone, and a fight where you
	can hear your opponent punch but not close the distance is worse than one
	with no audio at all. So the client announces the dash, and the one thing
	that happens here is a positional cue everyone in earshot gets.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Sounds = require(Shared.Sounds)

--[[ One generator for the crit roll. Seeded from the clock so two servers do
     not deal identical sequences of crits. ]]
local rng = Random.new(os.clock() * 1e6 % 2 ^ 31)

local CombatService = {}

--[[ [attackerUserId] = { [victimUserId] = os.clock() of the last landed hit }.
     Landed, not thrown: swinging at the air is not a fight. ]]
local struck = {}

--[[ [userId] = os.clock() when their next swing is allowed. Server-side, so
     the cooldown is real rather than a courtesy the client extends. ]]
local nextSwing = {}

--[[ [userId] = { index, last } -- where they are in the four-hit combo.

     THE SERVER OWNS THIS, not the client, because the server is what decides
     which swings are real. A client counting its own hits would drift from the
     accepted ones the first time a swing was refused on cooldown, and the
     fourth punch would land with the third punch's sound. ]]
local combo = {}

--[[
	Set by DuelService at startup. Two hooks rather than a require, so the
	dependency runs one way: combat knows nothing about wagers, arenas or
	inventories, and cannot be made to move an item by any code path in here.

	  onRetaliation(a, b)      -- b just hit a back inside the memory window
	  onStreetFight(a, b)      -- these two just started a fresh scrap
	  canFight(attacker, dst)  -- may this pair exchange blows right now?

	canFight takes BOTH players and not one. The first version asked "is this
	player busy?" about each of them separately and refused the swing if either
	said yes -- which sealed the two duellists away from everyone including
	each other, so no damage could ever be dealt inside a duel and every fight
	ended 100-100. The question is never whether someone is in a fight; it is
	whether these two are in the SAME one.
]]
CombatService.onRetaliation = nil
--[[ A HOOK RATHER THAN A require(DataService), for the reason the note above
     gives: this file knows nothing about profiles and is worth keeping that
     way. The counter lives with the other combat bookkeeping in DuelService. ]]
CombatService.onStreetFight = nil
CombatService.canFight = nil

local function humanoidOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

--[[ Has `attacker` hit `victim` recently enough for a reply to count? ]]
local function struckRecently(attacker, victim)
	local book = struck[attacker.UserId]
	local at = book and book[victim.UserId]
	return at ~= nil and (os.clock() - at) <= Config.StreetFightMemory
end

local function remember(attacker, victim)
	local book = struck[attacker.UserId]
	if not book then
		book = {}
		struck[attacker.UserId] = book
	end
	book[victim.UserId] = os.clock()
end

--[[
	Who this swing hits: the nearest living player inside the range AND inside
	the cone.

	The cone matters more than it looks. Range alone is a sphere, and a sphere
	means a swing lands on someone standing behind you -- which reads as the
	game hitting people at random, and in a duel would mean turning your back
	costs nothing. Comparing the dot product against Config.PunchArc is the
	whole of it.

	One target per swing. A punch that hits everyone in the arc would make a
	crowd the best place to farm retaliation offers.
]]
local function targetFor(attacker)
	local _, root = humanoidOf(attacker)
	if not root then
		return nil
	end
	local from = root.Position
	local facing = root.CFrame.LookVector

	local best, bestDistance = nil, math.huge
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= attacker then
			local _, otherRoot = humanoidOf(other)
			if otherRoot then
				local offset = otherRoot.Position - from
				local distance = offset.Magnitude
				if distance <= Config.PunchRange and distance > 0.01 then
					if facing:Dot(offset.Unit) >= Config.PunchArc and distance < bestDistance then
						best, bestDistance = other, distance
					end
				end
			end
		end
	end
	return best
end

--[[
	A swing.

	Returns nothing -- see the header. Everything a client could lie about is
	recomputed here, and a swing that fails any check is simply dropped rather
	than answered, because the honest client never trips them.
]]
function CombatService.swing(attacker)
	local now = os.clock()
	if (nextSwing[attacker.UserId] or 0) > now then
		return -- still on cooldown; a spammed click is not an error
	end
	nextSwing[attacker.UserId] = now + Config.PunchCooldown

	local humanoid = humanoidOf(attacker)
	if not humanoid then
		return -- dead people do not punch
	end

	--[[
		THE ANIMATION IS PUBLISHED BEFORE THE TARGET IS RESOLVED, so a miss
		still swings. A punch that is only visible when it connects would make
		whiffing look like the button not working.

		THE SOUND IS NOT. It is chosen further down, once the outcome is known,
		because connecting and swinging through air are different events -- see
		Sounds.punchWhiff / punchLight / punchHeavy.

		An attribute rather than a remote: joint poses are not replicated, so
		every client has to animate the swinger itself, and an attribute on the
		character is state they are already watching. See UI/Punch.
	]]
	local entry = combo[attacker.UserId]
	if not entry or (now - entry.last) > Config.PunchComboReset then
		entry = { index = 0, last = now }
		combo[attacker.UserId] = entry
	end
	entry.last = now
	entry.index = (entry.index % 4) + 1

	local character = attacker.Character
	local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if character then
		--[[ Index first, then the timestamp. A client watching SwingAt reads
		     SwingIndex in the same handler, and setting the timestamp first
		     would occasionally hand it the PREVIOUS index. ]]
		character:SetAttribute("SwingIndex", entry.index)
		character:SetAttribute("SwingAt", now)
	end

	--[[
		Everything below decides ONE thing: did this connect?

		A BLOCKED HIT COUNTS AS A MISS. If a duel's seal refuses the pair, the
		attacker swung and reached nothing that counts -- and playing the
		connecting cue for a punch that dealt no damage would be a lie about
		what happened.
	]]
	local victim = targetFor(attacker)
	local victimHumanoid = victim and humanoidOf(victim)
	local landed = victimHumanoid ~= nil
		and (not CombatService.canFight or CombatService.canFight(attacker, victim))

	if not landed then
		--[[ Air. Played on the ATTACKER, because that is where the swing
		     happened -- there is no impact to put it at. ]]
		if attackerRoot then
			Sounds.playAt("punchWhiff", attackerRoot)
		end
		return
	end

	--[[ Rolled here, where the hit is known to have landed. See the note in
	     Config: rolling at swing time would let a punch that hit nothing still
	     be a crit, and the sound would announce a hit that never happened. ]]
	local crit = rng:NextNumber() < Config.PunchCritChance
	victimHumanoid:TakeDamage(Config.PunchDamage
		* (crit and Config.PunchCritMultiplier or 1))

	--[[ ON THE VICTIM, not the attacker. This is an impact, so it belongs where
	     the impact was -- which also means a bystander hears the hit from the
	     person taking it rather than from across the fight. The fourth of the
	     combo is the heavy one. ]]
	local victimRoot = victim.Character
		and victim.Character:FindFirstChild("HumanoidRootPart")
	if victimRoot then
		Sounds.playAt(entry.index == 4 and "punchHeavy" or "punchLight", victimRoot)
		if crit then
			Sounds.playAt("punchCrit", victimRoot)
		end
	end

	--[[
		THE ORDER HERE IS THE WHOLE MECHANIC.

		Ask whether the VICTIM had already hit the ATTACKER before recording
		this hit. If they had, this swing is a reply, and a reply is what
		raises the offer. Recording first would make every first punch look
		like a retaliation against itself.
	]]
	local isReply = struckRecently(victim, attacker)
	--[[ A FRESH SCRAP is neither of them having struck the other inside the
	     window -- so it counts the encounter, not the punch, and a thirty-blow
	     brawl is one fight rather than thirty. Asked BEFORE remember() for the
	     same reason isReply is: recording first makes every opening punch look
	     like a continuation of itself. ]]
	local fresh = not isReply and not struckRecently(attacker, victim)
	remember(attacker, victim)

	if fresh and CombatService.onStreetFight then
		CombatService.onStreetFight(attacker, victim)
	end

	if isReply and CombatService.onRetaliation then
		--[[ The one who was hit FIRST is `a`. It decides nothing about the
		     wager -- both sides accept or it does not happen -- but it keeps
		     the prompt's wording honest about who started it. ]]
		CombatService.onRetaliation(victim, attacker)
	end
end

--[[ Wipe the memory of a fight. DuelService calls this when a duel resolves,
     so the loser throwing one more punch afterwards starts a fresh street
     fight rather than instantly re-opening the offer they just settled. ]]
function CombatService.forget(a, b)
	if struck[a.UserId] then
		struck[a.UserId][b.UserId] = nil
	end
	if struck[b.UserId] then
		struck[b.UserId][a.UserId] = nil
	end
end

--[[ [userId] = when their next dash cue is allowed. The dash is not gated by
     the server -- it has already happened by the time this arrives -- but the
     SOUND is, so a client firing the remote in a loop cannot machine-gun a
     noise at everybody around it. ]]
local nextDashCue = {}

function CombatService.dashed(player)
	local now = os.clock()
	if (nextDashCue[player.UserId] or 0) > now then
		return
	end
	--[[ The client's own cooldown, reused. A cue rejected here is one the
	     honest client would never have sent. ]]
	nextDashCue[player.UserId] = now + Config.DashCooldown * 0.9

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Sounds.playAt("dash", root)
	end
end

function CombatService.start()
	Net.get("Dashed").OnServerEvent:Connect(function(player)
		local ok, err = pcall(CombatService.dashed, player)
		if not ok then
			warn("[CombatService] dash cue failed:", err)
		end
	end)

	Net.get("Attack").OnServerEvent:Connect(function(player)
		--[[ Wrapped: a swing resolves against other players' characters, which
		     can be destroyed by a respawn between the range check and the
		     damage. One player's unlucky timing must not take the handler
		     down for everyone. ]]
		local ok, err = pcall(CombatService.swing, player)
		if not ok then
			warn("[CombatService] swing failed:", err)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		struck[player.UserId] = nil
		nextSwing[player.UserId] = nil
		combo[player.UserId] = nil
		nextDashCue[player.UserId] = nil
		for _, book in pairs(struck) do
			book[player.UserId] = nil
		end
	end)
end

return CombatService
