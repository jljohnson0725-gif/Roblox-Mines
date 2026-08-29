--[[
	PlinkoUI
	The stake dial, and the button that drops the ball.

	THE MACHINE USED TO HAVE NO PANEL AT ALL. A ball had one price, so pressing
	E at the console was the whole interface and that was the right answer. A
	stake you choose needs somewhere to choose it, and a prompt that spends
	money the moment you press it is a way to lose twenty times the minimum by
	accident.

	IT DOES NOT HIDE THE REST OF THE SCREEN, unlike every other panel here. The
	point of this machine is watching the ball fall, and a modal window over the
	board would mean choosing between setting a stake and seeing what it bought.
	So it sits low and to the side, it is not in the chrome-hiding set, and it
	stays open across drops -- you set the dial once and press DROP twenty
	times.

	THE SERVER STILL DECIDES. Everything here is clamped again on the way in;
	this panel is a convenience, not a gate. See PlinkoService.drop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Plinko = require(Shared.Plinko)

local Theme = require(script.Parent.Theme)

local PlinkoUI = {}

--[[ 196 tall, not 168. At 168 the inner height after padding was 140 and the
     content needed 158, so the "top bin pays" line rendered underneath the DROP
     button -- clipped and half-covered. Measured off the stack below: 22 title
     + 14 odds + 40 dial + 14 best + 38 button + the gaps between them. ]]
local W, H = 296, 196
local PAD = 14

--[[ The dial moves in multiples of the minimum rather than by a percentage,
     so every stop is a round number of balls and the readout never shows
     $618,750. Doubling would reach the cap in five presses and skip most of
     the range; stepping by one minimum makes all twenty stops reachable. ]]
local function stops()
	local low = Config.PlinkoDropCost
	local list = {}
	for i = 1, Config.PlinkoMaxStakeMultiple do
		list[i] = low * i
	end
	return list
end

function PlinkoUI.init(ctx)
	local ui = {}
	local STOPS = stops()
	local index = 1

	local root = Theme.frame({
		parent = ctx.gui,
		name = "PlinkoPanel",
		color = Theme.color.bg,
		size = UDim2.fromOffset(W, H),
		--[[ Bottom RIGHT. Bottom-left is the Coach card's corner and the two
		     would have sat on top of each other; the money counter owns the
		     centre. This is the one free corner. ]]
		position = UDim2.new(1, -12, 1, -16),
		anchor = Vector2.new(1, 1),
		radius = 14,
	})
	root.Visible = false
	Theme.stroke(root, Theme.color.line, 1)
	Theme.padding(root, PAD)

	Theme.label({
		parent = root,
		text = "PLINKO",
		font = Theme.font.black,
		textSize = 18,
		size = UDim2.new(1, 0, 0, 22),
	})

	local odds = Theme.label({
		parent = root,
		name = "Odds",
		text = "",
		font = Theme.font.regular,
		textSize = 11,
		color = Theme.color.faint,
		size = UDim2.new(1, -30, 0, 14),
		position = UDim2.fromOffset(0, 21),
	})

	local closeButton = Theme.button({
		parent = root,
		name = "Close",
		text = "✕",
		textSize = 14,
		color = Theme.color.raised,
		size = UDim2.fromOffset(24, 24),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
	})
	closeButton.MouseButton1Click:Connect(function()
		ui.setVisible(false)
	end)

	-- ── the dial ────────────────────────────────────────────────────────────

	local down = Theme.button({
		parent = root,
		name = "Down",
		text = "−",
		textSize = 22,
		color = Theme.color.raised,
		size = UDim2.fromOffset(44, 40),
		position = UDim2.fromOffset(0, 44),
		radius = 10,
	})

	local up = Theme.button({
		parent = root,
		name = "Up",
		text = "+",
		textSize = 22,
		color = Theme.color.raised,
		size = UDim2.fromOffset(44, 40),
		position = UDim2.new(1, 0, 0, 44),
		anchor = Vector2.new(1, 0),
		radius = 10,
	})

	local stakeLabel = Theme.label({
		parent = root,
		name = "Stake",
		text = "",
		font = Theme.font.black,
		textSize = 20,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -100, 0, 24),
		position = UDim2.fromOffset(50, 46),
	})

	local perBall = Theme.label({
		parent = root,
		name = "PerBall",
		text = "",
		font = Theme.font.regular,
		textSize = 10,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -100, 0, 12),
		position = UDim2.fromOffset(50, 70),
	})

	local best = Theme.label({
		parent = root,
		name = "Best",
		text = "",
		font = Theme.font.medium,
		textSize = 11,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 92),
	})

	local drop = Theme.button({
		parent = root,
		name = "Drop",
		text = "DROP",
		textSize = 15,
		color = Theme.color.good,
		size = UDim2.new(1, 0, 0, 38),
		position = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		radius = 10,
	})

	-- ── render ──────────────────────────────────────────────────────────────

	local function stake()
		return STOPS[index]
	end

	local function render()
		local value = stake()
		local money = ctx.state.money or 0

		stakeLabel.Text = Format.money(value)
		perBall.Text = index == 1 and "minimum" or ("%dx the minimum"):format(index)

		--[[ The top prize for THIS stake, which is the number the dial is
		     actually for. Read off the table rather than typed, so retuning the
		     bins can never leave this promising something they were changed
		     out of. ]]
		local top = 0
		for _, bin in ipairs(Plinko.Bins) do
			top = math.max(top, bin.pay)
		end
		best.Text = ("top bin pays %s"):format(Format.money(math.floor(value * top)))

		down.Active = index > 1
		up.Active = index < #STOPS
		Theme.recolor(down, index > 1 and Theme.color.raised or Theme.color.panel)
		Theme.recolor(up, index < #STOPS and Theme.color.raised or Theme.color.panel)

		local affordable = money >= value
		drop.Active = affordable
		drop.Text = affordable and "DROP" or ("NEED " .. Format.money(value))
		Theme.recolor(drop, affordable and Theme.color.good or Theme.color.raised)
		drop.TextColor3 = affordable and Theme.color.text or Theme.color.faint
	end

	local function step(by)
		index = math.clamp(index + by, 1, #STOPS)
		render()
	end

	down.MouseButton1Click:Connect(function()
		if down.Active then
			step(-1)
		end
	end)
	up.MouseButton1Click:Connect(function()
		if up.Active then
			step(1)
		end
	end)

	drop.MouseButton1Click:Connect(function()
		if not drop.Active then
			return
		end
		--[[ THE INDEXING GOES INSIDE THE PCALL, and that is not style.
		     `pcall(ctx.remotes.DropBall.InvokeServer, ...)` reads the field to
		     build the argument list BEFORE pcall is entered, so a missing remote
		     throws outside the protection: the handler dies, no toast appears,
		     and the button silently does nothing. That was this button's first
		     bug -- DropBall was never added to ctx.remotes -- and it presented
		     as "I press DROP and nothing happens". ]]
		local remote = ctx.remotes.DropBall
		local ok, result = pcall(function()
			return remote:InvokeServer(stake())
		end)
		if not ok then
			warn("[PlinkoUI] DropBall failed: " .. tostring(result))
			ctx.notify("Something went wrong — try again.", "bad")
			return
		end
		if result and not result.ok then
			ctx.notify(result.err or "Couldn't drop that.", "bad")
		end
	end)

	ctx.onState(function()
		if root.Visible then
			render()
		end
	end)

	-- ── api ─────────────────────────────────────────────────────────────────

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			--[[ Reopen on the stake they last used. The server remembers it on
			     the profile, so this survives a rejoin rather than resetting to
			     the minimum every session. ]]
			local saved = ctx.state.plinkoStake
			if saved then
				for i, value in ipairs(STOPS) do
					if value == saved then
						index = i
						break
					end
				end
			end
			local back, fragment = Plinko.summary()
			odds.Text = ("%s back · %s of drops carry a fragment")
				:format(Format.percent(back), Format.percent(fragment))
			render()
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ui.root = root
	return ui
end

return PlinkoUI
