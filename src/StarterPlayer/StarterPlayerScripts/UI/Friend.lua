--[[
	Friend
	The chud outside your front door, and his body pillow.

	HE IS CLIENT-SIDE, one per player, standing outside the player's OWN
	apartment. A single shared NPC would have to pick one base and would be
	loitering outside a stranger's apartment for everyone else. FriendService fetches
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
	did not ask for.

	AND HE OPENS AND CLOSES THE ARC. His first speech names the three things
	wrong with you -- hideous, broke, stinking -- and those are not chosen for
	the rhythm: they are the cologne, the loop, and the peptides, which is the
	whole shop in one insult. `stink` and `face` nag through the middle of it,
	and `adam` pays it off once both are bought, where he makes the point the
	whole bit has been building to: the glow-up was never about the girlfriend.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Theme = require(script.Parent.Theme)
local Cutscene = require(script.Parent.Cutscene)

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
		--[[ Gated on having HEARD it, not on being new. Keyed off rounds first,
		     which meant playing a single round before saying hello deleted the
		     introduction permanently -- and the introduction is the one speech
		     that has to land, because it plants the peptides ending. Now it
		     waits for you however long you take to walk over. ]]
		when = function(state, seen)
			return not seen.welcome
		end,
		lines = {
			"Hey, neighbour!",
			"Heard you got dumped. Sorry about that. Plenty of fish in the sea.",
			--[[ THE THESIS, and it is three items long on purpose. Hideous,
			     broke and stinking are not insults picked for the rhythm --
			     they are the three things the game sells a fix for, in the
			     order you can afford them. Everything he says afterwards is
			     him working down this list. ]]
			"Well — who can blame her? You're hideous, broke, and absolutely stink.",
			"I say that with love. Nobody else is going to.",
			"Me, I'm fine. I've got my Puro Pillow. She's perfect.",
			"But you could win her back. If you became a <b>true Adam</b>.",
			"Three problems, three fixes. Money you go and earn. The shop sells the other two.",
		},
	},
	{
		--[[
			THE ENDING, and the only other topic gated on having HEARD it.

			Once both vanity items are bought there is nothing left for him to
			nag about, and a neighbour who repeats his own finale forever stops
			being a character. So it lands once and then falls through to the
			ordinary topics below -- which is also the joke: after the big
			speech he goes straight back to explaining the desk.
		]]
		id = "adam",
		when = function(state, seen)
			return not seen.adam
				and state.cologne == true
				and state.peptides == true
		end,
		lines = {
			"Look at you. Rich, clean, and that jawline.",
			"You could walk right back over there tomorrow.",
			"Or — and I'm just saying this as your neighbour — you could stay here. With the guys. And me. And Puro.",
		},
	},
	{
		--[[ Cologne bought, face still to go. Above `stink` because the two are
		     mutually exclusive and this is the later half of the same arc.

		     AND BOTH SIT ABOVE THE EXPLAINERS, which is not where they started.
		     They were below `unsecured` and `mines` on the reasoning that a
		     player rich enough for a five hundred million purchase has long
		     since stopped needing either -- but those two are gated on HAVING
		     BUSTED and on twelve rounds, not on wealth. A careful player who
		     never hit a mine kept getting the unsecured warning forever and
		     never heard a word about the cologne they had just bought.

		     The rule these two follow: a topic about what you OWN outranks a
		     topic about what you have not done yet. ]]
		id = "face",
		when = function(state)
			return state.cologne == true and state.peptides ~= true
		end,
		lines = {
			"Better! Genuinely. I can stand closer to you now.",
			"That's one down. The face is the expensive one.",
			"Peptides. A billion. You'll look like a completely different man, which is the idea.",
		},
	},
	{
		--[[
			HALF THE PRICE, NOT ZERO. He only brings the smell up once doing
			something about it is in sight -- nagging a player about a five
			hundred million purchase while they are worth four thousand is not
			advice, it is just being told you smell for six hours.
		]]
		id = "stink",
		when = function(state)
			return state.cologne ~= true
				and (state.money or 0) >= Config.CologneCost * 0.5
		end,
		lines = {
			"Not to bring it up again, but you do still smell.",
			"There's a cologne in the shop. Half a billion. I know.",
			"Puro says money can't buy happiness. Puro is a pillow. Buy the cologne.",
		},
	},
	{
		--[[
			THE ONLY WARNING ABOUT DUELS ANYWHERE IN THE GAME.

			Coach does not mention fighting at all, and the offer card's one
			line -- "X is fighting back, both of you put a brainrot up" --
			arrives AFTER you have swung and they have swung back. So the rule
			that a punch can escalate into staking a brainrot permanently was
			learned by having it happen to you, which is exactly the shape of
			thing this NPC exists to head off.

			HE ALSO SAYS THE OPPOSITE HALF, and that half matters as much: a
			street fight stakes nothing. A player who assumes punching is
			dangerous simply never punches anyone, and the whole street-fight
			layer goes unused for want of one sentence.

			GATED ON HAVING SOMETHING TO LOSE, not on having been in a fight --
			there is no combat counter on the profile, and adding one to time a
			warning is the wrong way round. Three brainrots means the advice
			lands before somebody takes one rather than after.

			AND ONCE ONLY. Sitting above the explainers with an always-true
			condition would starve every topic below it, which is the bug the
			ordering note further up records. It is a warning, not a nag.
		]]
		id = "fight",
		when = function(state, seen)
			if seen.fight then
				return false
			end
			--[[ EITHER TRIGGER, whichever lands first. Three brainrots means
			     the warning arrives before somebody can take one; a single
			     street fight means it arrives the moment the subject becomes
			     real. Before the combat stats existed only the first was
			     available, and it left a player who punched someone on their
			     first day waiting to accumulate a collection before anyone
			     told them what a punch can turn into. ]]
			local stats = state.stats or {}
			return (stats.fights or 0) > 0
				or (state.inventory ~= nil and #state.inventory >= 3)
		end,
		lines = {
			"Word to the wise, since nobody else here will give it.",
			"Swing at someone in the street and nothing's on the line. No stakes, no prompt. That's all a street fight is.",
			"But hit one back within thirty seconds and the game asks you both whether you want it for real.",
			"Say yes and there's a brainrot on the table. Lose, and it's theirs. Permanently.",
			"Puro and I settle our differences by talking. Well. I talk.",
		},
	},
	{
		--[[
			HE READS YOUR RECORD BACK AT YOU, which needs the numbers and so is
			the one topic whose lines are a function rather than a table.

			THREE DUELS, NOT ONE. "You are 1 and 0" is not a record, it is an
			anecdote -- there is nothing for him to have an opinion about until
			there is a pattern.

			AND ONCE, like the warning. A standing readout sitting above the
			explainers would starve every topic below it the moment you fought
			your third duel, which is the bug the ordering note further up
			records. If this ever wants to be recurring it needs to fire on the
			record CHANGING rather than on it existing -- which means stamping
			the total when heard, not a `seen` boolean.
		]]
		id = "record",
		when = function(state, seen)
			if seen.record then
				return false
			end
			local s = state.stats or {}
			return ((s.duelWins or 0) + (s.duelLosses or 0) + (s.duelDraws or 0)) >= 3
		end,
		lines = function(state)
			local s = state.stats or {}
			local won, lost, drew = s.duelWins or 0, s.duelLosses or 0, s.duelDraws or 0
			local out = {
				("So you're %d and %d in duels now.%s"):format(won, lost,
					drew > 0 and (" %d went nowhere, which I'm counting separately because it's funnier."):format(drew) or ""),
			}
			--[[ Three readings, and he is fond of you in all of them. ]]
			if lost > won then
				out[#out + 1] = "I'm not going to tell you to stop. I'm going to stand here and think it very loudly."
			elseif won > lost then
				out[#out + 1] = "People are going to start crossing the street when they see you. That's a compliment. Mostly."
			else
				out[#out + 1] = "Dead level. Which means the next one decides which of those you are."
			end
			out[#out + 1] = "Puro's record is nothing and nothing. Never been in a fight. Never lost one either."
			return out
		end,
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
			"Cash out to keep them. I've watched someone lose a Secret to one extra click. I had to sit down for a bit.",
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
			"Your guys are earning. See the ring around your desk?",
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
			"It also redecorates the apartment. Mine's still the starter one. Puro likes the concrete.",
		},
	},
	{
		id = "sky",
		when = function(state)
			return (state.plinkoball == true)
		end,
		lines = {
			"You bought the ball. So you've seen there's stuff up there.",
			"Plinko first. It drops saddle pieces, and a saddle is what gets you to the next one.",
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
			"You're doing well, you know. The place is looking less like a crime scene.",
			"If you ever want to talk about her — don't. Buy another brainrot instead.",
		},
	},
}

--[[
	THE GUIDED TOUR.

	Offered once, the second time you talk to him -- after the ground loop has
	worked and before you have any idea the rest of the map exists. The old
	shape ended at "collect your money" and left the player to find the shop,
	the wheel and the sky on their own; this walks them round it.

	IT MOVES ON THE PLAYER'S PRESS, never on a timer. He is explaining things,
	and a camera that slides away mid-sentence is the reason people skip
	tutorials. Next advances the line; the last line of a stop flies to the next
	one.

	FOCUS IS A LOOKUP, not a position. Every one of these is built at runtime --
	the shop is cloned from a template, the wheel picks its own site, the island
	moved 330 studs up this week -- so a baked coordinate would be pointing at
	empty sky within a day. A stop whose thing is missing is skipped rather than
	flown to.
]]
local TOUR = {
	{
		id = "shop",
		focus = function()
			local shop = Workspace:FindFirstChild("UpgradeShop")
			local counter = shop and shop:FindFirstChild("Counter")
			return counter and counter.Position
		end,
		offset = Vector3.new(16, 13, -30),
		aim = Vector3.new(0, -1, 0),
		lines = {
			"Right — since you've got money now, let me show you where it goes.",
			"That's the shop. Upgrades on one tab, items on the other.",
			"Upgrades make you better. Items make you <b>you</b> — cologne, peptides, a ball that takes you to Plinko. All permanent.",
		},
	},
	{
		id = "wheel",
		focus = function()
			local wheel = Workspace:FindFirstChild("TheWheel")
			return wheel and wheel:GetPivot().Position
		end,
		offset = Vector3.new(0, 26, -46),
		aim = Vector3.new(0, 4, 0),
		lines = {
			"The wheel. You stake everything you're carrying, all at once.",
			"Best odds on a <b>Secret</b> anywhere — eight percent. The Mines can drop one, but you'll be waiting.",
			"I've never dared. You look like you might.",
		},
	},
	{
		id = "sky",
		focus = function()
			local island = Workspace:FindFirstChild("Island_plinko")
			return island and island:GetPivot().Position
		end,
		--[[ From well below and a long way out, looking up. This is the one stop
		     that is about ALTITUDE -- the point being made is "that is a long way
		     up and you cannot walk there" -- and a level shot of it says nothing. ]]
		offset = Vector3.new(120, -300, -520),
		aim = Vector3.new(0, 20, 0),
		lines = {
			"And that. Up there.",
			"Plinko. Drop a ball, watch it fall, hope. Buy the ball from the shop and go and see.",
			"Every good bin gives you a saddle piece. Five makes a saddle.",
			"Then you can ride to the racing island — the ball only ever goes to Plinko.",
		},
	},
}

local function topicFor(state, seen)
	for _, topic in ipairs(TOPICS) do
		local ok, want = pcall(topic.when, state, seen)
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
	--[[ Which topics have been heard all the way through. Separate from
	     `progress`, which is only a line index for cycling. ]]
	local seen = {}
	local npc, prompt

	-- ── the dialogue card ──────────────────────────────────────────────────
	local card = Theme.frame({
		parent = ctx.gui,
		name = "Friend",
		color = Theme.color.panel,
		--[[ 156 tall, not 132. Body ran y22..80 and the button sat at y70..100,
		     so the two overlapped by ten pixels and the button printed straight
		     over the last line of every message that wrapped past two lines. ]]
		size = UDim2.fromOffset(440, 156),
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
		size = UDim2.new(1, 0, 0, 66), position = UDim2.fromOffset(0, 22),
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
		--[[ Flush to the bottom edge. It was offset up by its own height as well
		     as being anchored there, which left thirty pixels of dead card
		     under the button. ]]
		size = UDim2.new(1, 0, 0, 30), position = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		radius = 10,
	})

	--[[
		A topic's `lines` may be a FUNCTION of the state rather than a table,
		for the ones that read a number back at you. Resolved ONCE when the
		topic is picked, not on every render: a live income tick firing between
		two clicks would otherwise rewrite the sentence the player is halfway
		through reading.

		A function that errors or returns nothing falls back to a single line
		rather than propagating -- he is a flavour NPC, and a bad format string
		must not take the dialogue box down with it.
	]]
	local function linesOf(topic, snapshot)
		if type(topic.lines) ~= "function" then
			return topic.lines
		end
		local ok, out = pcall(topic.lines, snapshot)
		if ok and type(out) == "table" and #out > 0 then
			return out
		end
		warn("[Friend] lines() failed for topic " .. tostring(topic.id))
		return { "Anyway. You know where I am." }
	end

	local current, index, shown = nil, 1, nil

	--[[ One place decides whether the card is up, and it publishes that on the
	     player. The tutorial's highlight watches it so the ring and the four
	     shades get out of the way while he is actually talking -- being told to
	     go and meet someone, over the top of meeting them, is just clutter. ]]
	local function setOpen(on)
		card.Visible = on
		game.Players.LocalPlayer:SetAttribute("TalkingToNeighbour", on)
	end

	local function show()
		body.Text = shown[index]
		advance.Text = (index >= #shown) and "Alright" or "Next"
		setOpen(true)
	end

	-- ── the tour ────────────────────────────────────────────────────────────

	--[[ nil when not touring; otherwise { stop, line }. ]]
	local tour

	--[[ Offered exactly once: after the ground loop has paid out, and only
	     while the server says it has not been sat through. `toured` is on the
	     profile rather than a client attribute for that reason -- a tour is
	     minutes long and being shown it again on every rejoin is a punishment. ]]
	local function wantsTour()
		local ob = state.onboarding
		return ob ~= nil and ob.collected == true and ob.toured ~= true
	end

	local function showTour()
		local stop = TOUR[tour.stop]
		body.Text = stop.lines[tour.line]
		local lastLine = tour.line >= #stop.lines
		advance.Text = (lastLine and tour.stop >= #TOUR) and "Got it" or "Next"
		--[[ card.Visible directly, NOT setOpen. setOpen also clears
		     TalkingToNeighbour, and Tutorial reads that every frame to decide
		     whether to stand down -- so hiding the card between stops through
		     setOpen would flash the tutorial overlay across the letterbox each
		     time the camera flew. The attribute is held for the whole tour and
		     released once, at the end. ]]
		card.Visible = true
	end

	local function endTour()
		if not tour then
			return
		end
		tour = nil
		card.Visible = false
		game.Players.LocalPlayer:SetAttribute("TalkingToNeighbour", false)
		if prompt then
			prompt.Enabled = true
		end
		Cutscene.close()
		--[[ Latched server-side so it survives the session. Fired even when the
		     player escaped early: they have seen the map, and re-offering it is
		     worse than letting them miss the last stop. ]]
		local remote = ctx.remotes and ctx.remotes.FinishTour
		if remote then
			remote:FireServer()
		end
	end

	--[[ Fly to a stop, then speak. Yields on the camera move, so it runs in its
	     own thread -- the button handler must return immediately or the click
	     that started the move is still being processed when it lands. ]]
	local function goToStop(n)
		while n <= #TOUR do
			local focus = TOUR[n].focus()
			if focus then
				tour.stop, tour.line = n, 1
				card.Visible = false
				Cutscene.moveTo({
					focus = focus,
					offset = TOUR[n].offset,
					aim = TOUR[n].aim,
				}, tour.first and 0 or 1.9)
				tour.first = false
				if not tour then -- escaped while the camera was moving
					return
				end
				showTour()
				return
			end
			--[[ Nothing to point at -- the wheel demolishes a base to place
			     itself and could be missing on a map that changed. Skip the stop
			     rather than flying to the world origin. ]]
			n += 1
		end
		endTour()
	end

	local function startTour()
		if not Cutscene.open(endTour) then
			return false
		end
		tour = { stop = 0, line = 1, first = true }
		game.Players.LocalPlayer:SetAttribute("TalkingToNeighbour", true)
		if prompt then
			prompt.Enabled = false
		end
		task.spawn(function()
			goToStop(1)
		end)
		return true
	end

	local function open()
		if wantsTour() and startTour() then
			return
		end
		current = topicFor(state, seen)
		shown = linesOf(current, state)
		--[[ Resume where this topic left off, wrapping. Talking to him again in
		     the same state should not replay line one forever, and should not
		     dead-end either. ]]
		index = ((progress[current.id] or 0) % #shown) + 1
		show()
	end

	advance.Activated:Connect(function()
		if tour then
			local stop = TOUR[tour.stop]
			if tour.line < #stop.lines then
				tour.line += 1
				showTour()
			elseif tour.stop < #TOUR then
				local next_ = tour.stop + 1
				task.spawn(function()
					goToStop(next_)
				end)
			else
				endTour()
			end
			return
		end

		if not current then
			setOpen(false)
			return
		end
		progress[current.id] = index
		if index >= #shown then
			seen[current.id] = true
			--[[ Recorded on the PLAYER so the tutorial can ask whether this
			     conversation happened without either module knowing about the
			     other. Set when the topic is FINISHED, not when it opens, so
			     walking up and walking away again does not count. ]]
			if current.id == "welcome" then
				game.Players.LocalPlayer:SetAttribute("MetNeighbour", true)
			end
			setOpen(false)
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
		--[[
			AIM THE RIG, NOT THE MODEL.

			The character sits rotated inside its wrapper Model, so pointing the
			model's PIVOT at someone leaves the body ninety degrees off -- which
			read as "not tracking" even though he was turning correctly the whole
			time, because the error was a constant offset rather than a failure.

			So the twist between the two is measured once, here, and cancelled
			every time he turns. Same family as pivot-is-not-centre, one step
			further in: a model's pivot tells you nothing about which way the
			thing inside it is looking.
		]]
		local rigPart = npc:FindFirstChild("HumanoidRootPart", true)
			or npc:FindFirstChildWhichIsA("BasePart", true)
		local rigTwist = npc:GetPivot().Rotation:Inverse() * rigPart.CFrame.Rotation

		local function stand(lookAt)
			local dir = Vector3.new(lookAt.X - at.X, 0, lookAt.Z - at.Z)
			if dir.Magnitude < 0.1 then
				dir = Vector3.new(0, 0, 1)
			end
			local face = CFrame.lookAt(Vector3.zero, dir.Unit).Rotation
			local aim = CFrame.new(at) * face * rigTwist:Inverse()

			npc:PivotTo(aim)
			local box, size = npc:GetBoundingBox()
			local drift = npc:GetPivot().Position - box.Position
			npc:PivotTo(aim + drift + Vector3.new(0, size.Y / 2, 0))
		end
		stand(at - out)
		npc.Parent = workspace
		--[[ Published so anything that needs to point at him -- the tutorial --
		     can find him without reaching into this module. ]]
		Friend.npc = npc

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

		--[[ Same part the twist was measured from: recursive, because the asset
		     wraps its rig in another Model and a shallow lookup returns nil --
		     which silently skipped the prompt and left an NPC nobody could talk
		     to. ]]
		local root = rigPart
		if root then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "TalkPrompt"
			prompt.ActionText = "Talk"
			prompt.ObjectText = "Your Neighbour"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = TALK_RANGE
			prompt.RequiresLineOfSight = false
			--[[ On the HEAD and nudged up, not on the torso. Anchored at the
			     root it rendered dead centre of his chest, straight over the
			     body pillow -- covering the one thing that explains him. ]]
			prompt.Parent = npc:FindFirstChild("Head", true) or root
			prompt.UIOffset = Vector2.new(0, -46)
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
		--[[ Through setOpen like every other hide, or this path leaves the
		     player flagged as mid-conversation forever and the tutorial overlay
		     never comes back. ]]
		close = function()
			current = nil
			setOpen(false)
		end,
	}
end

return Friend
