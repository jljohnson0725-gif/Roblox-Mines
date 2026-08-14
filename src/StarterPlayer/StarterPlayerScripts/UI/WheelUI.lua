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
	cash = Format.money(Config.WheelCashPrize) .. " back",
	nothing = "you lose it all",
}

function WheelUI.init(ctx)
	local ui = {}
	local stake, busy = nil, false

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

	local effective, retryChance = Wheel.effectiveOdds()
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
		local shown = outcome.id == "retry" and retryChance or effective[outcome.id]
		Theme.label({
			parent = row,
			text = ("%.1f%%"):format(shown * 100),
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
		text = "YOU ARE WAGERING",
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
	local stakeRots = Theme.label({
		parent = stakeBox,
		name = "StakeRots",
		text = "",
		font = Theme.font.medium,
		textSize = 14,
		color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 52),
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

	local function render()
		if not stake then
			return
		end
		stakeMoney.Text = Format.money(stake.money)
		stakeRots.Text = ("and every brainrot you own — %d of them, %s")
			:format(stake.brainrots, Format.rate(stake.income))

		if not stake.eligible then
			stakeWarn.Text = ("You need %s to play. The wheel takes everything or nothing.")
				:format(Format.money(stake.minimum))
			stakeWarn.TextColor3 = Theme.color.bad
			commit.Active = false
			Theme.recolor(commit, Theme.color.raised)
			commit.Text = "NOT ENOUGH — " .. Format.money(stake.minimum) .. " NEEDED"
		else
			stakeWarn.Text = "Your pads, upgrades and Index all survive. The cash and the brainrots do not."
			stakeWarn.TextColor3 = Theme.color.faint
			commit.Active = not busy
			Theme.recolor(commit, busy and Theme.color.raised or Theme.color.bad)
			commit.Text = busy and "SPINNING…" or "HOLD TO WAGER EVERYTHING"
		end
	end

	function ui.setStake(next)
		stake = next
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
						return ctx.remotes.SpinWheel:InvokeServer()
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
