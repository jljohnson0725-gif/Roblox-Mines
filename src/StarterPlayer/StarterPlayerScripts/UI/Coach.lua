--[[
	Coach
	The first five minutes.

	One card in the bottom-left corner, showing the single next thing to do. It
	replaces a lone toast that fired once at spawn and was gone before anyone
	read it.

	EVERY STEP IS DERIVED FROM REAL STATE, never from a script position. The
	player is on "place it on a pad" because they own something unplaced, not
	because they pressed Next twice. That means it cannot desync and it survives
	a rejoin mid-way.

	It shows the FIRST incomplete step, which is not the same as skipping ahead.
	Someone who buys a brainrot at the auction and places it without ever opening
	Mines still gets "Play a round of Mines" -- correctly, because they haven't.
	The pips are what tell them the later steps are already behind them, so they
	light by whether each step is DONE rather than by position in the list.

	It switches off once all four steps read done, which is also exactly when the
	server latches `onboarding.done`: banked, placed, and a pile collected. Those
	three facts ARE the tutorial, so there is nothing else to remember and a
	returning player never sees the card.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local Coach = {}

local W = 268

--[[
	Ordered. The first step whose `done` is false is the one shown, so the
	sequence self-heals: complete a later step early and it is simply skipped.
]]
local STEPS = {
	{
		key = "play",
		title = "Play a round of Mines",
		body = "Press M, set a bet, then reveal tiles. Green is safe.",
		done = function(s)
			return (s.stats and s.stats.rounds or 0) > 0
		end,
	},
	{
		key = "bank",
		title = "Cash out to keep it",
		body = "A brainrot is only yours once you bank. Hit a mine and you lose it.",
		done = function(s)
			return next(s.index or {}) ~= nil
		end,
	},
	{
		key = "place",
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
			size = UDim2.fromOffset(26, 5),
			order = i,
			radius = 3,
		})
	end

	local shownKey

	local function render()
		local state = ctx.state

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

	ui.root = card
	return ui
end

return Coach
