--[[
	Coach
	The single next thing to do, from the first minute to the last island.

	One card in the bottom-left corner. It replaces a lone toast that fired once
	at spawn and was gone before anyone read it.

	IT USED TO STOP AFTER THE GROUND LOOP -- four steps, about five minutes, and
	then silence forever. That silence was the whole problem: the sky islands,
	the fragments and the seal that opens the second one were never mentioned
	anywhere a player would look. The step list now runs the length of the game,
	which costs nothing structurally because the card was never counting steps;
	it shows the first one that isn't done and hides when none are left.

	EVERY STEP IS DERIVED FROM REAL STATE, never from a script position. The
	player is on "place it on a pad" because they own something unplaced, not
	because they pressed Next twice. That means it cannot desync and it survives
	a rejoin mid-way.

	It shows the FIRST incomplete step, which is not the same as skipping ahead.
	Someone who wins a brainrot and places it without ever opening
	Mines still gets "Play a round of Mines" -- correctly, because they haven't.
	The pips are what tell them the later steps are already behind them, so they
	light by whether each step is DONE rather than by position in the list.

	It switches off once every step reads done -- which now means the player has
	the whistle and the racing island is open to them, not merely that the
	tutorial is behind them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)
local Items = require(Shared.Items)

local Theme = require(script.Parent.Theme)

local Coach = {}

local W = 268

--[[ Read from the definitions rather than written out, so a price change in
     Shared/Items or a fragment count in Shared/Islands cannot leave this card
     confidently telling the player a number that stopped being true. ]]
local function costOf(id)
	local def = Items.get(id)
	return def and Format.money(def.cost) or "a fortune"
end

local PLINKO = Islands.get("plinko")
local PLINKO_NEED = PLINKO and Seals.required(PLINKO) or 5

--[[ ── WHERE EACH OBJECTIVE PHYSICALLY IS ──────────────────────────────────

     UI/Beacon draws a marker on whatever these return, so a player who is not
     reading the card still gets shown where to go. nil is a normal answer: some
     steps are answered inside a panel and have nowhere to point.

     RESOLVED EVERY FRAME, never cached. The shop is built after the client
     starts, the player's base is not theirs until they claim one, and under
     streaming any of it can leave and come back. A handle grabbed once is a
     handle that goes stale the first time somebody rejoins.
]]
local function landmark()
	local model = Workspace:FindFirstChild("MinesLandmark")
	return model and model:GetPivot().Position or nil
end

local function shopCounter()
	local shop = Workspace:FindFirstChild("UpgradeShop")
	local counter = shop and shop:FindFirstChild("Counter")
	return counter and counter.Position or nil
end

--[[ The player's OWN base, found by the owner attribute PlotService stamps on
     it. Pointing at whichever base happens to be first would send half the
     server to somebody else's front door. ]]
local function myBase()
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then
		return nil
	end
	local me = Players.LocalPlayer.UserId
	for _, base in ipairs(bases:GetChildren()) do
		if base:GetAttribute("OwnerUserId") == me then
			return base
		end
	end
	return nil
end

local function myPads()
	local base = myBase()
	return base and base:GetPivot().Position or nil
end

local function myCollectZone()
	local base = myBase()
	local home = base and base:FindFirstChild("Home")
	local interior = home and home:FindFirstChild("Interior")
	local zone = interior and interior:FindFirstChild("CollectZone")
	--[[ Falls back to the base itself: not every base has been converted to a
	     room, and "go home" is still the right instruction when it hasn't. ]]
	return zone and zone.Position or myPads()
end

local function plinkoIsland()
	return PLINKO and PLINKO.center or nil
end

--[[
	Ordered. The first step whose `done` is false is the one shown, so the
	sequence self-heals: complete a later step early and it is simply skipped.
]]
local STEPS = {
	{
		key = "play",
		where = landmark,
		chapter = "GETTING STARTED",
		title = "Play a round of Mines",
		body = "Press M, set a bet, then reveal tiles. Green is safe.",
		done = function(s)
			return (s.stats and s.stats.rounds or 0) > 0
		end,
	},
	{
		key = "bank",
		chapter = "GETTING STARTED",
		title = "Cash out to keep it",
		body = "A brainrot is only yours once you bank. Hit a mine and you lose it.",
		done = function(s)
			return next(s.index or {}) ~= nil
		end,
	},
	{
		key = "place",
		where = myPads,
		chapter = "GETTING STARTED",
		title = "Put it on a pad",
		body = "Press C, pick your brainrot, choose a pad. It pays rent forever.",
		done = function(s)
			for _, item in ipairs(s.inventory or {}) do
				if item.pad then
					return true
				end
			end
			return false
		end,
	},
	{
		key = "collect",
		where = myCollectZone,
		chapter = "GETTING STARTED",
		title = "Collect what it earned",
		body = "Cash piles up on the strip by each pad. Walk over it to bank it.",
		--[[
			Reads a server flag rather than inferring from `pending == 0`.

			Pending is also zero in the moment right after placing, before any
			rent has accrued, so testing it directly completed this step
			instantly, hid the card, and then un-hid it seconds later when the
			first cash appeared. Tracking "I have seen a pile" on the client
			fixed that but broke returning players, whose client starts each
			session having seen nothing and got told to go and collect.

			PlotService sets `collected` the first time it actually banks a
			pile, so the fact survives a rejoin and means exactly one thing.
		]]
		done = function(s)
			return (s.onboarding and s.onboarding.collected) == true
		end,
	},

	{
		key = "tour",
		chapter = "GETTING STARTED",
		--[[ The hinge of the whole opening. The ground loop ends here and the
		     rest of the map begins, and before this step the player was simply
		     turned loose at that point to find the shop, the wheel and the sky
		     unaided. He shows them instead. ]]
		title = "Talk to your neighbour again",
		body = "Now you've been paid, he wants to show you around.",
		--[[ Required lazily, inside the call. Coach is built before Friend, so a
		     require at the top of the file would resolve the module before it
		     had published `npc` -- and Tutorial reaches for it the same way for
		     the same reason. ]]
		where = function()
			local ok, friend = pcall(function()
				return require(script.Parent.Friend).npc
			end)
			local npc = ok and friend or nil
			return npc and npc:GetPivot().Position or nil
		end,
		done = function(s)
			return (s.onboarding and s.onboarding.toured) == true
		end,
	},

	--[[ ── THE CHAPTERS ──────────────────────────────────────────────────────

		Everything above is the ground loop and takes about five minutes.
		Everything below is the rest of the game, and it lives here because
		NOTHING ELSE IN THE UI EVER MENTIONS IT.

		SealTracker looked like it covered this and does not: it hides itself
		until you already hold a fragment, so it can tell you how close the seal
		is but never that there is a seal to go and start. And the launch pad
		that used to stand in the street -- sited off to one side of the Plinko
		island precisely so that it pointed at it -- is gone now that the shop
		sells the ball. Between them, a player who finished the tutorial was
		told nothing whatsoever about the sky.

		Same rule as the four above: every step is a question asked of real
		state, so these survive a rejoin and cannot desync. They just answer it
		over hours instead of minutes.
	]]
	{
		key = "plinkoball",
		where = shopCounter,
		chapter = "LEAVING THE GROUND",
		title = "Buy a Plinko Ball",
		body = "The shop sells one for " .. costOf("plinkoball")
			.. ". Throw it and you are on the island.",
		done = function(s)
			return s.plinkoball == true
		end,
	},
	{
		key = "sky",
		where = plinkoIsland,
		chapter = "LEAVING THE GROUND",
		title = "Fly up to the Plinko island",
		body = "Press F and climb. It is the island hanging over the west of the map.",
		--[[ "Has a fragment" rather than "has been there": arriving is not the
		     point, playing is, and the first fragment is proof of both. ]]
		done = function(s)
			return Seals.count(s, "plinko") > 0 or Seals.held(s, "plinko")
		end,
	},
	{
		key = "seal",
		where = plinkoIsland,
		chapter = "THE PLINKO SEAL",
		title = "Earn the Plinko saddle",
		body = ("Every drop can award a saddle piece. %d of them make the saddle.")
			:format(PLINKO_NEED),
		done = function(s)
			return Seals.held(s, "plinko")
		end,
	},
	{
		key = "whistle",
		where = shopCounter,
		chapter = "THE PLINKO SEAL",
		title = "Buy the Brainrot Whistle",
		body = "It calls a ride to Brainrot Racing — " .. costOf("whistle")
			.. ". The saddle you just made is what lets you ride it.",
		--[[ Ends on the purchase, not on the ride, because owning the whistle is
		     the moment the RIDE button appears on the rail. The card goes away
		     and the button takes over: one handoff, no overlap. ]]
		done = function(s)
			return s.whistle == true
		end,
	},
}

function Coach.init(ctx)
	local ui = {}

	--[[
		BOTTOM left, not top.

		It was anchored at half the viewport height minus 212 pixels, which put
		it around 150px down on a short window -- straight under Roblox's own
		topbar, behind the logo and the menu button. Any position derived from
		the viewport centre can land there on some window size.

		The bottom-left corner cannot: the topbar is a fixed offset from the TOP,
		so anchoring to the bottom is the one placement that clears it at every
		height. It sits below the rail and left of the money counter.
	]]
	local card = Theme.frame({
		parent = ctx.gui,
		name = "Coach",
		color = Theme.color.panel,
		size = UDim2.fromOffset(W, 96),
		position = UDim2.new(0, 12, 1, -16),
		anchor = Vector2.new(0, 1),
		radius = 14,
	})
	card.Visible = false
	Theme.stroke(card, Theme.color.line, 2)
	Theme.padding(card, 13)

    local eyebrow = Theme.label({
		parent = card,
		name = "Eyebrow",
		text = "GETTING STARTED",
		font = Theme.font.black,
		textSize = 10,
		color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 12),
	})
	eyebrow.TextStrokeColor3 = Theme.color.line
	eyebrow.TextStrokeTransparency = 0.5

	local title = Theme.label({
		parent = card,
		name = "Title",
		text = "",
		font = Theme.font.black,
		textSize = 15,
		size = UDim2.new(1, 0, 0, 19),
		position = UDim2.fromOffset(0, 15),
	})

	local body = Theme.label({
		parent = card,
		name = "Body",
		text = "",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 34),
		position = UDim2.fromOffset(0, 36),
	})
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top

	-- progress pips: four steps, so a dotted row reads faster than "2 of 4"
	local pips = Theme.frame({
		parent = card,
		name = "Pips",
		transparency = 1,
		size = UDim2.new(1, 0, 0, 6),
		position = UDim2.new(0, 0, 1, -6),
		anchor = Vector2.new(0, 1),
		radius = false,
	})
	Theme.list(pips, 5, Enum.FillDirection.Horizontal)

	local dots = {}
	for i = 1, #STEPS do
		dots[i] = Theme.frame({
			parent = pips,
			name = "Pip" .. i,
			color = Theme.color.raised,
			--[[ Scaled, not a fixed 26px. Four steps fitted at that width and
			     eight do not -- they overran the card by a pixel. A share of the
			     row means the strip fits whatever the list grows to. ]]
			size = UDim2.new(1 / #STEPS, -5, 0, 5),
			order = i,
			radius = 3,
		})
	end

	local shownKey
	--[[ Held down while the tutorial is gating a step. Two prompts for one
	     action is worse than either alone -- the card said "Play a round of
	     Mines" beside a spotlight saying "Open Mines", and a new player has to
	     work out whether those are one instruction or two. ]]
	local suppressed = false

	local function render()
		local state = ctx.state

		if suppressed then
			card.Visible = false
			return
		end

		local current, index
		for i, step in ipairs(STEPS) do
			if not step.done(state) then
				current, index = step, i
				break
			end
		end

		if not current then
			card.Visible = false
			return
		end

		card.Visible = true
		-- Lit by completion, not position: a step finished out of order still
		-- reads as done rather than pretending it's ahead of the player.
		for i, dot in ipairs(dots) do
			dot.BackgroundColor3 = i == index and Theme.color.gold
				or (STEPS[i].done(state) and Theme.color.good or Theme.color.raised)
		end

		if current.key ~= shownKey then
			shownKey = current.key
			--[[ The eyebrow used to be the literal "GETTING STARTED", set once at
			     build time. That was true while the card only covered the first
			     five minutes and became a lie the moment it started saying
			     "Earn the Plinko seal" underneath it. ]]
			eyebrow.Text = current.chapter or "NEXT UP"
			title.Text = current.title
			body.Text = current.body

			-- a small nudge on change, so an advancing step is noticed
			card.Size = UDim2.fromOffset(W, 96)
			TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Back,
				Enum.EasingDirection.Out), { Size = UDim2.fromOffset(W + 8, 100) }):Play()
			task.delay(0.24, function()
				TweenService:Create(card, TweenInfo.new(0.16), {
					Size = UDim2.fromOffset(W, 96),
				}):Play()
			end)
		end

		-- the collect step is the only one with a live number worth showing
		if current.key == "collect" and (ctx.state.pending or 0) >= 1 then
			body.Text = ("%s is waiting on your pads. Walk over the strip to bank it.")
				:format(Format.money(ctx.state.pending))
		end
	end

	ctx.onState(render)
	render()

	--[[ Published on ctx rather than returned, because Coach is initialised
	     before Tutorial and the caller does not thread handles between them. ]]
	ctx.coach = {
		suppress = function(on)
			local want = on and true or false
			if want ~= suppressed then
				suppressed = want
				render()
			end
		end,

		--[[ The step the card is showing, or nil when it is showing nothing --
		     suppressed, or every step done. UI/Beacon reads this to decide what
		     to point at, so the marker in the world and the words on the card
		     can never be about two different objectives: there is one answer to
		     "what now", and this is it. ]]
		current = function()
			if suppressed then
				return nil
			end
			for _, step in ipairs(STEPS) do
				if not step.done(ctx.state) then
					return step
				end
			end
			return nil
		end,
	}

	ui.root = card
	return ui
end

return Coach
