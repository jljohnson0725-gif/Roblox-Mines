--[[
	WheelUI
	The confirmation screen for the all-in wager.

	This is the only control in the game that can destroy everything a player
	owns, so it is built to be hard to press by accident and impossible to press
	by surprise:

	  - it states the stake in full BEFORE the button does anything -- the exact
	    cash, the exact number of brainrots, the income per second you are about
	    to stop earning;
	  - the commit is a HOLD, not a click;
	  - it quotes the odds a player actually experiences (9.4% for a Secret),
	    not the raw 8%. A retry re-rolls rather than resolving, so the raw number
	    understates the real chance and would read as a lie the first time
	    somebody worked it out.

	It does not try to talk anyone out of it. The bet is the point.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Wheel = require(Shared.Wheel)

local Theme = require(script.Parent.Theme)

local WheelUI = {}

--[[
	The stake dial's stops.

	GEOMETRIC, NOT LINEAR. The range spans four hundredfold -- 1.5M to 600M --
	and even steps would need hundreds of presses to cross it. Twelve stops
	rising by about 1.66x each cover it in eleven, and every stop is rounded to
	two significant figures so the readout is never $17,320,508.

	Built from the Config values rather than typed out, so retuning the minimum
	or the cap moves the whole ladder with them.
]]
local function ladder()
	local lo, hi = Config.WheelMinStake, Config.WheelSecretCapStake
	local stops, n = {}, 12
	for i = 1, n do
		local v = lo * (hi / lo) ^ ((i - 1) / (n - 1))
		local mag = 10 ^ math.floor(math.log10(v) - 1)
		stops[i] = math.clamp(math.floor(v / mag + 0.5) * mag, lo, hi)
	end
	stops[1], stops[n] = lo, hi
	return stops
end

local PANEL_W, PANEL_H = 460, 486
local PAD = 18
local HOLD = 1.2 -- seconds

local TONE = {
	secret = Theme.color.gold,
	retry = Theme.color.accent,
	cash = Theme.color.good,
	nothing = Theme.color.bad,
}
local BLURB = {
	secret = "a Secret brainrot",
	retry = "spin again, free",
	cash = "half your stake back",
	nothing = "you lose the stake",
}

function WheelUI.init(ctx)
	local ui = {}
	local stake, busy = nil, false
	--[[ The dial: an index into the ladder, clamped every render to what the
	     player can actually afford. ]]
	local STOPS = ladder()
	local index = 1

	local root = Theme.frame({
		parent = ctx.gui,
		name = "WheelPanel",
		color = Theme.color.bg,
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 16,
	})
	root.Visible = false
	Theme.stroke(root, Theme.color.bad, 3)

	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local v = ctx.gui.AbsoluteSize
		if v.X < 10 then
			return
		end
		scale.Scale = math.clamp(math.min(v.X / (PANEL_W + 40), v.Y / (PANEL_H + 40)), 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	Theme.label({
		parent = root,
		text = "THE WHEEL",
		font = Theme.font.black,
		textSize = 24,
		color = Theme.color.gold,
		size = UDim2.fromOffset(300, 30),
		position = UDim2.fromOffset(PAD, 14),
	})
	Theme.label({
		parent = root,
		text = "the only place Secrets exist",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(300, 16),
		position = UDim2.fromOffset(PAD, 40),
	})

	local closeButton = Theme.button({
		parent = root,
		name = "Close",
		text = "✕",
		textSize = 16,
		color = Theme.color.raised,
		size = UDim2.fromOffset(32, 32),
		position = UDim2.new(1, -PAD, 0, 14),
		anchor = Vector2.new(1, 0),
	})
	closeButton.MouseButton1Click:Connect(function()
		ui.setVisible(false)
	end)

	-- ── the odds ────────────────────────────────────────────────────────────
	local oddsBox = Theme.frame({
		parent = root,
		name = "Odds",
		color = Theme.color.panel,
		size = UDim2.new(1, -PAD * 2, 0, 132),
		position = UDim2.fromOffset(PAD, 68),
		radius = 12,
	})
	Theme.padding(oddsBox, 12)
	Theme.list(oddsBox, 6)

	--[[ The percentages move with the dial now, so each row's number is kept and
	     refreshed in render() rather than baked at build time. Config.WheelOdds
	     is still the row ORDER and the labels -- only the numbers are live. ]]
	local oddsRows = {}
	for _, outcome in ipairs(Config.WheelOdds) do
		local row = Theme.frame({
			parent = oddsBox,
			transparency = 1,
			size = UDim2.new(1, 0, 0, 22),
			radius = false,
		})
		Theme.label({
			parent = row,
			text = outcome.label,
			font = Theme.font.black,
			textSize = 14,
			color = TONE[outcome.id],
			size = UDim2.fromOffset(96, 22),
		})
		Theme.label({
			parent = row,
			text = BLURB[outcome.id],
			font = Theme.font.regular,
			textSize = 12,
			color = Theme.color.dim,
			size = UDim2.new(1, -190, 0, 22),
			position = UDim2.fromOffset(100, 0),
		})
		--[[ Retry shows its raw share because it IS a re-roll; everything else
		     shows the renormalised chance, which is what actually happens. ]]
		oddsRows[outcome.id] = Theme.label({
			parent = row,
			text = "",
			font = Theme.font.bold,
			textSize = 14,
			color = TONE[outcome.id],
			align = Enum.TextXAlignment.Right,
			size = UDim2.fromOffset(76, 22),
			position = UDim2.new(1, 0, 0, 0),
			anchor = Vector2.new(1, 0),
		})
	end

	-- ── what you are putting up ─────────────────────────────────────────────
	local stakeBox = Theme.frame({
		parent = root,
		name = "Stake",
		color = Theme.color.panel,
		size = UDim2.new(1, -PAD * 2, 0, 122),
		position = UDim2.fromOffset(PAD, 210),
		radius = 12,
	})
	Theme.stroke(stakeBox, Theme.color.bad, 2)
	Theme.padding(stakeBox, 12)

	Theme.label({
		parent = stakeBox,
		text = "YOUR STAKE",
		font = Theme.font.black,
		textSize = 12,
		color = Theme.color.bad,
		size = UDim2.new(1, 0, 0, 16),
	})
	local stakeMoney = Theme.label({
		parent = stakeBox,
		name = "StakeMoney",
		text = "",
		font = Theme.font.black,
		textSize = 26,
		color = Theme.color.text,
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 20),
	})
	--[[ The number the dial exists for. Bigger than the odds strip above it
	     because this is the one that changes as you turn it. ]]
	local chanceLabel = Theme.label({
		parent = stakeBox,
		name = "Chance",
		text = "",
		font = Theme.font.bold,
		textSize = 14,
		color = Theme.color.gold,
		size = UDim2.new(1, -104, 0, 20),
		position = UDim2.fromOffset(0, 52),
	})

	local down = Theme.button({
		parent = stakeBox, name = "Down", text = "−",
		textSize = 20, color = Theme.color.raised,
		size = UDim2.fromOffset(44, 34),
		position = UDim2.new(1, -50, 0, 18),
		radius = 8,
	})
	local up = Theme.button({
		parent = stakeBox, name = "Up", text = "+",
		textSize = 20, color = Theme.color.raised,
		size = UDim2.fromOffset(44, 34),
		position = UDim2.new(1, 0, 0, 18),
		anchor = Vector2.new(1, 0),
		radius = 8,
	})
	local stakeWarn = Theme.label({
		parent = stakeBox,
		name = "StakeWarn",
		text = "",
		font = Theme.font.regular,
		textSize = 11.5,
		color = Theme.color.faint,
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 74),
	})
	stakeWarn.TextWrapped = true
	stakeWarn.TextYAlignment = Enum.TextYAlignment.Top

	-- ── commit ──────────────────────────────────────────────────────────────
	local commit = Theme.button({
		parent = root,
		name = "Commit",
		text = "HOLD TO WAGER EVERYTHING",
		textSize = 15,
		color = Theme.color.bad,
		size = UDim2.new(1, -PAD * 2, 0, 52),
		position = UDim2.new(0, PAD, 1, -PAD - 62),
		radius = 12,
	})
	local fill = Theme.frame({
		parent = commit,
		name = "Fill",
		color = Theme.color.gold,
		size = UDim2.new(0, 0, 1, 0),
		radius = 12,
	})
	fill.ZIndex = commit.ZIndex - 1

	local result = Theme.label({
		parent = root,
		name = "Result",
		text = "",
		font = Theme.font.black,
		textSize = 15,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -PAD * 2, 0, 20),
		position = UDim2.new(0, PAD, 1, -PAD - 74),
	})

	--[[ The highest stop this player can afford. The dial is clamped to it so
	     the button never offers a spin the server would refuse. ]]
	local function affordableTop()
		local top = 1
		for i, value in ipairs(STOPS) do
			if stake and value <= stake.money then
				top = i
			end
		end
		return top
	end

	local function current()
		return STOPS[math.clamp(index, 1, #STOPS)]
	end

	local function render()
		if not stake then
			return
		end
		local top = affordableTop()
		index = math.clamp(index, 1, top)
		local value = current()

		stakeMoney.Text = Format.money(value)

		--[[ Quoted from the shared model rather than recomputed here, so the
		     panel cannot promise odds the server does not roll. ]]
		local odds, retryChance = Wheel.effectiveOdds(value)
		chanceLabel.Text = ("%s chance of a Secret"):format(Format.percent(odds.secret or 0))

		for id, label in pairs(oddsRows) do
			--[[ Retry shows its RAW share because it is a re-roll rather than a
			     result; the others show the renormalised chance, which is what
			     actually happens to you. ]]
			local shown = id == "retry" and retryChance or (odds[id] or 0)
			label.Text = Format.percent(shown)
		end

		down.Active = index > 1
		up.Active = index < top
		Theme.recolor(down, index > 1 and Theme.color.raised or Theme.color.panel)
		Theme.recolor(up, index < top and Theme.color.raised or Theme.color.panel)

		if not stake.eligible then
			stakeWarn.Text = ("You need %s to play."):format(Format.money(stake.minimum))
			stakeWarn.TextColor3 = Theme.color.bad
			commit.Active = false
			Theme.recolor(commit, Theme.color.raised)
			commit.Text = "NOT ENOUGH — " .. Format.money(stake.minimum) .. " NEEDED"
		else
			--[[ Said plainly, because it USED to take them and a returning
			     player will assume it still does. ]]
			stakeWarn.Text = ("Money only. Your %d brainrot%s, pads, upgrades and Index are all safe.")
				:format(stake.brainrots, stake.brainrots == 1 and "" or "s")
			stakeWarn.TextColor3 = Theme.color.faint
			commit.Active = not busy
			Theme.recolor(commit, busy and Theme.color.raised or Theme.color.bad)
			commit.Text = busy and "SPINNING…" or ("HOLD TO STAKE " .. Format.money(value))
		end
	end

	local function step(by)
		index = math.clamp(index + by, 1, affordableTop())
		render()
	end
	down.MouseButton1Click:Connect(function()
		if down.Active then step(-1) end
	end)
	up.MouseButton1Click:Connect(function()
		if up.Active then step(1) end
	end)

	function ui.setStake(next)
		stake = next
		--[[ Reopen on the stake they last used. The server remembers it on the
		     profile, so this survives a rejoin. ]]
		local saved = ctx.state.wheelStake
		if saved then
			for i, value in ipairs(STOPS) do
				if value == saved then
					index = i
					break
				end
			end
		end
		render()
	end

	-- hold-to-confirm
	local holding, holdStart = false, 0
	local function cancelHold()
		holding = false
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.new(0, 0, 1, 0) }):Play()
	end

	commit.MouseButton1Down:Connect(function()
		if not commit.Active or busy then
			return
		end
		holding, holdStart = true, os.clock()
		TweenService:Create(fill, TweenInfo.new(HOLD, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, 1, 0),
		}):Play()

		task.spawn(function()
			while holding do
				if os.clock() - holdStart >= HOLD then
					holding = false
					busy = true
					render()
					result.Text = ""

					local ok, payload = pcall(function()
						return ctx.remotes.SpinWheel:InvokeServer(current())
					end)
					busy = false
					cancelHold()

					if not ok or not payload or not payload.ok then
						result.Text = (payload and payload.err) or "The wheel jammed."
						result.TextColor3 = Theme.color.bad
					elseif payload.outcome == "secret" then
						result.Text = "SECRET! " .. payload.secret.name
						result.TextColor3 = Theme.color.gold
					elseif payload.outcome == "cash" then
						result.Text = "Consolation: " .. Format.money(payload.cash)
						result.TextColor3 = Theme.color.good
					else
						result.Text = "Gone. All of it."
						result.TextColor3 = Theme.color.bad
					end

					if #(payload and payload.spins or {}) > 1 then
						result.Text = result.Text
							.. (" (after %d retries)"):format(#payload.spins - 1)
					end
					render()
					return
				end
				task.wait()
			end
		end)
	end)
	commit.MouseButton1Up:Connect(cancelHold)
	commit.MouseLeave:Connect(cancelHold)

	ctx.onState(function()
		if root.Visible then
			render()
		end
	end)

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			fit()
			result.Text = ""
			cancelHold()
			render()
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ui.root = root
	fit()
	return ui
end

return WheelUI
