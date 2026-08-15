--[[
	CodesUI
	A box to type a code into, and the result.

	Deliberately does not list the valid codes. Half the point of a code is that
	it travels -- through a video, a Discord, a description -- and a panel that
	enumerates them turns that into a lookup table.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local CodesUI = {}

local PANEL_W, PANEL_H = 380, 232
local PAD = 18

function CodesUI.init(ctx)
	local ui = {}
	local busy = false

	local root = Theme.frame({
		parent = ctx.gui,
		name = "CodesPanel",
		color = Theme.color.bg,
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 16,
	})
	root.Visible = false
	Theme.stroke(root, Theme.color.line, 3)

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
		text = "CODES",
		font = Theme.font.black,
		textSize = 22,
		size = UDim2.fromOffset(220, 28),
		position = UDim2.fromOffset(PAD, 14),
	})
	Theme.label({
		parent = root,
		text = "one use each",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(220, 16),
		position = UDim2.fromOffset(PAD, 38),
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

	local field = Instance.new("TextBox")
	field.Name = "Field"
	field.Size = UDim2.new(1, -PAD * 2, 0, 46)
	field.Position = UDim2.fromOffset(PAD, 74)
	field.BackgroundColor3 = Theme.color.panel
	field.BorderSizePixel = 0
	field.Font = Theme.font.bold
	field.TextSize = 18
	field.TextColor3 = Theme.color.text
	field.PlaceholderText = "enter code"
	field.PlaceholderColor3 = Theme.color.faint
	field.Text = ""
	field.ClearTextOnFocus = false
	field.TextXAlignment = Enum.TextXAlignment.Center
	Theme.corner(field, 10)
	Theme.stroke(field, Theme.color.line, 2)
	field.Parent = root

	local status = Theme.label({
		parent = root,
		name = "Status",
		text = "",
		font = Theme.font.medium,
		textSize = 13,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -PAD * 2, 0, 20),
		position = UDim2.fromOffset(PAD, 128),
	})

	local redeem = Theme.button({
		parent = root,
		name = "Redeem",
		text = "REDEEM",
		textSize = 16,
		color = Theme.color.good,
		size = UDim2.new(1, -PAD * 2, 0, 46),
		position = UDim2.new(0, PAD, 1, -PAD - 46),
		radius = 12,
	})
	redeem.TextStrokeColor3 = Theme.color.line
	redeem.TextStrokeTransparency = 0

	local function submit()
		if busy then
			return
		end
		busy = true
		redeem.Text = "CHECKING…"

		local ok, result = pcall(function()
			return ctx.remotes.RedeemCode:InvokeServer(field.Text)
		end)
		busy = false
		redeem.Text = "REDEEM"

		if ok and result and result.ok then
			-- a code can pay money, brainrots, or both; "+$0" for a brainrot
			-- code would read as a failure
			local won
			if result.granted and #result.granted > 0 and (result.money or 0) > 0 then
				won = ("+%s and %d brainrots"):format(Format.money(result.money), #result.granted)
			elseif result.granted and #result.granted > 0 then
				won = table.concat(result.granted, ", ")
			else
				won = "+" .. Format.money(result.money or 0)
			end
			status.Text = ("%s — %s"):format(won, result.blurb or "redeemed")
			status.TextColor3 = Theme.color.good
			field.Text = ""
		else
			status.Text = (result and result.err) or "Couldn't redeem that."
			status.TextColor3 = Theme.color.bad
		end
	end

	redeem.MouseButton1Click:Connect(submit)
	field.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			fit()
			status.Text = ""
			field.Text = ""
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ui.root = root
	fit()
	return ui
end

return CodesUI
