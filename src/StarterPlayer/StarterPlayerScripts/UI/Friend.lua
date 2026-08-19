--[[
	Friend
	The chud outside your front door, and his body pillow.

	HE IS CLIENT-SIDE, one per player, standing outside the player's OWN
	apartment. A single shared NPC would have to pick one base and would be
	loitering outside a stranger's flat for everyone else. FriendService fetches
	the rig into ReplicatedStorage; this clones it.

	WHAT HE IS FOR, and what he deliberately is not. Tutorial gates the two
	steps nobody guesses -- open Mines, cash out -- and Coach nudges through
	four. Repeating those here would be a third voice saying the same thing at
	the same moment. He explains the layer underneath instead: that the
	multiplier is also the luck stat, that a run's brainrots die with the run,
	that mine count moves drop chance, what rebirth actually keeps. Things the
	loop never says out loud.

	HIS LINES MOVE WITH YOUR PROGRESS rather than running a script. Each topic
	declares when it is worth hearing, and the first one that is picks itself --
	the same shape Coach uses, and for the same reason: there is no cursor to
	desync, nothing to replay, and a player who does things out of order still
	gets a line that makes sense. Talk to him twice in the same state and he
	cycles within that topic, so he is never a single stuck sentence.

	THE JOKE IS LOAD-BEARING. He is in a happy relationship with a body pillow
	and feels genuinely sorry for you, which is why he keeps giving advice you
	did not ask for. It also quietly sets up the ending: he is the proof that
	the glow-up is not actually about the girlfriend.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)

local Friend = {}

--[[ Where he stands relative to your front door: out on the step, off to one
     side so he is never in the doorway you are trying to walk through. ]]
local BESIDE_DOOR = 9
local IN_FRONT = 7
local TALK_RANGE = 14

--[[
	Topics, in priority order. `when(state)` decides whether a topic is worth
	hearing yet; the FIRST one that says yes is the one he talks about.

	Ordered from "you are new" to "you have seen everything", so the list reads
	top to bottom as the game opens up.
]]
local TOPICS = {
	{
		id = "welcome",
		when = function(state)
			return (state.stats and (state.stats.rounds or 0) or 0) < 1
		end,
		lines = {
			"Hey, neighbour!",
			"Heard you got dumped. Sorry, mate. Plenty of fish in the sea, though.",
			"Well — not for me. I've got my Puro Pillow. She's perfect.",
			"But you could win her back. If you became a <b>true Adam</b>.",
			"Takes money and looks, that does. Try betting — quickest way to get rich, if you're lucky.",
			"Get enough and you can buy peptides. Sort that mug of yours right out.",
		},
	},
	{
		id = "multiplier",
		when = function(state)
			return (state.inventory == nil or #state.inventory == 0)
		end,
		lines = {
			"Here's the bit nobody tells you: that multiplier climbing on screen isn't just money.",
			"It IS your luck. Higher multiplier, better brainrots drop. Same number does both jobs.",
			"So 'one more tile' is never just greed. It's greed AND a rarity roll. Beautiful, really.",
		},
	},
	{
		id = "unsecured",
		when = function(state)
			return (state.stats and (state.stats.busts or 0) or 0) < 1
		end,
		lines = {
			"Word of warning, friend to friend.",
			"Brainrots you find mid-run aren't yours yet. Hit a mine and they go with the cash.",
			"Cash out to keep them. I've watched people lose a Secret to one extra click. I made tea about it.",
		},
	},
	{
		id = "mines",
		when = function(state)
			return (state.stats and (state.stats.rounds or 0) or 0) < 12
		end,
		lines = {
			"You noticed the mine count changes the payout. It also changes the DROP chance.",
			"More mines, more likely something falls out. That's why one mine isn't just the safe option.",
			"Puro says I explain things too much. She doesn't say anything actually. But I can tell.",
		},
	},
	{
		id = "desk",
		when = function(state)
			return (state.pending or 0) > 0
		end,
		lines = {
			"Your lads are earning. See the ring round your desk?",
			"Walk into it. All of it banks at once — you don't collect them one at a time like some animal.",
			"I sit at mine a lot. Not for the money. It's just where the pillow is.",
		},
	},
	{
		id = "rebirth",
		when = function(state)
			return (state.slots or 0) >= 8 and (state.rebirths or 0) < 1
		end,
		lines = {
			"Eight pads. Look at you. Genuinely, I'm proud, and slightly threatened.",
			"Rebirth wipes the money and the collection but keeps your luck — permanently.",
			"It also redecorates the flat. Mine's still the starter one. Puro likes the concrete.",
		},
	},
	{
		id = "sky",
		when = function(state)
			return (state.jetpack == true)
		end,
		lines = {
			"You bought the jetpack. So you've seen there's stuff up there.",
			"Plinko first. It drops seal fragments, and seals are what open the next one up.",
			"I don't go up. Puro gets airsick. She's never said so. I just know.",
		},
	},
	{
		id = "idle",
		when = function()
			return true
		end,
		lines = {
			"Still here. Still winning, relationship-wise.",
			"You're doing well, you know. The flat's looking less like a crime scene.",
			"If you ever want to talk about her — don't. Buy another brainrot instead.",
		},
	},
}

local function topicFor(state)
	for _, topic in ipairs(TOPICS) do
		local ok, want = pcall(topic.when, state)
		if ok and want then
			return topic
		end
	end
	return TOPICS[#TOPICS]
end

function Friend.init(ctx)
	local player = Players.LocalPlayer
	local state = ctx.state

	--[[ Which line of the current topic he is on. Keyed by topic id, so moving
	     to a new topic starts it at the beginning while an old one remembers
	     where you left it. ]]
	local progress = {}
	local npc, prompt

	-- ── the dialogue card ──────────────────────────────────────────────────
	local card = Theme.frame({
		parent = ctx.gui,
		name = "Friend",
		color = Theme.color.panel,
		size = UDim2.fromOffset(440, 132),
		position = UDim2.new(0.5, 0, 1, -110),
		anchor = Vector2.new(0.5, 1),
		radius = 14,
	})
	card.Visible = false
	Theme.stroke(card, Theme.color.line, 2)
	Theme.padding(card, 16)

	local name = Theme.label({
		parent = card, name = "Name", text = "YOUR NEIGHBOUR",
		font = Theme.font.black, textSize = 11, color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 14),
	})
	name.TextXAlignment = Enum.TextXAlignment.Left

	local body = Theme.label({
		parent = card, name = "Body", text = "",
		font = Theme.font.medium, textSize = 14, color = Theme.color.text,
		size = UDim2.new(1, 0, 0, 58), position = UDim2.fromOffset(0, 22),
	})
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	--[[ So <b>true Adam</b> reads as emphasis rather than as literal tags. He
	     is not shouting it -- caps would be shouting -- he is leaning on it. ]]
	body.RichText = true

	local advance = Theme.button({
		parent = card, name = "Next", text = "Next",
		color = Theme.color.accent,
		size = UDim2.new(1, 0, 0, 30), position = UDim2.new(0, 0, 1, -30),
		anchor = Vector2.new(0, 1),
		radius = 10,
	})

	local current, index = nil, 1

	local function show()
		body.Text = current.lines[index]
		advance.Text = (index >= #current.lines) and "Alright" or "Next"
		card.Visible = true
	end

	local function open()
		current = topicFor(state)
		--[[ Resume where this topic left off, wrapping. Talking to him again in
		     the same state should not replay line one forever, and should not
		     dead-end either. ]]
		index = ((progress[current.id] or 0) % #current.lines) + 1
		show()
	end

	advance.Activated:Connect(function()
		if not current then
			card.Visible = false
			return
		end
		progress[current.id] = index
		if index >= #current.lines then
			card.Visible = false
			current = nil
		else
			index += 1
			show()
		end
	end)

	-- ── the NPC ────────────────────────────────────────────────────────────
	--[[
		Placed off the player's OWN apartment, found through the base whose
		Owner nameplate carries this player's name -- rather than by remembering
		which base was assigned, which the client is never told.
	]]
	local function ownBase()
		local bases = workspace:FindFirstChild("Bases")
		if not bases then
			return nil
		end
		for _, base in ipairs(bases:GetChildren()) do
			if base:GetAttribute("OwnerUserId") == player.UserId then
				return base
			end
		end
		return nil
	end

	local function place()
		local template = ReplicatedStorage:FindFirstChild("FriendTemplate")
		local base = ownBase()
		if not template or not base then
			return false
		end
		local home = base:FindFirstChild("Home")
		local shell = home and home:FindFirstChild("Interior")
		local lintel = shell and shell:FindFirstChild("Lintel")
		local floor = shell and shell:FindFirstChild("Floor")
		if not lintel or not floor then
			return false
		end

		if npc then
			npc:Destroy()
		end
		npc = template:Clone()

		--[[ Out through the doorway and a few studs to the side. `facing` is
		     recovered from the lintel: it sits in the front wall, so the way
		     from the room's centre to it IS the way out. ]]
		local deck = floor.Position.Y + floor.Size.Y / 2
		local out = (lintel.Position - floor.Position)
		out = Vector3.new(out.X, 0, out.Z).Unit
		local side = Vector3.new(-out.Z, 0, out.X)
		local at = Vector3.new(lintel.Position.X, deck, lintel.Position.Z)
			+ out * IN_FRONT + side * BESIDE_DOOR

		--[[ Stood ON the step, by his bounding box rather than his pivot -- a
		     rig's pivot is at its HumanoidRootPart, which is chest height, so
		     pivoting to floor level buries him to the shoulders. ]]
		local function stand(lookAt)
			local aim = CFrame.lookAt(at, Vector3.new(lookAt.X, at.Y, lookAt.Z))
			npc:PivotTo(aim)
			local box, size = npc:GetBoundingBox()
			local drift = npc:GetPivot().Position - box.Position
			npc:PivotTo(aim + drift + Vector3.new(0, size.Y / 2, 0))
		end
		stand(at - out)
		npc.Parent = workspace

		--[[
			HE TURNS TO LOOK AT YOU, rather than being aimed once at a guess.

			A fixed facing has no right answer here: he stands beside a doorway
			people arrive at from the street AND come out of, so any single
			direction shows his back half the time -- which is exactly how the
			first version looked.

			Levelled to the player's XZ so he never tilts to track someone on a
			roof, and only while you are close enough to care. Cheap: eight
			anchored parts, and only when somebody is actually there.
		]]
		task.spawn(function()
			while npc and npc.Parent do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - at).Magnitude < 40 then
					stand(hrp.Position)
				end
				task.wait(0.2)
			end
		end)

		--[[ RECURSIVE, both of them. The asset wraps its rig in another Model,
		     so a shallow lookup finds only that wrapper and returns nil -- which
		     silently skipped the prompt and left an NPC nobody could talk to. ]]
		local root = npc:FindFirstChild("HumanoidRootPart", true)
			or npc:FindFirstChildWhichIsA("BasePart", true)
		if root then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "TalkPrompt"
			prompt.ActionText = "Talk"
			prompt.ObjectText = "Your Neighbour"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = TALK_RANGE
			prompt.RequiresLineOfSight = false
			prompt.Parent = root
			prompt.Triggered:Connect(open)
		end
		return true
	end

	--[[ Retried rather than placed once. The base's owner attribute, the
	     apartment's Interior and the template all arrive on their own schedule,
	     and this is the fourth thing in this client to have needed exactly this
	     -- see the note on nameplate LOD. ]]
	task.spawn(function()
		for _ = 1, 60 do
			if place() then
				return
			end
			task.wait(1)
		end
	end)

	return {
		close = function()
			card.Visible = false
		end,
	}
end

return Friend
