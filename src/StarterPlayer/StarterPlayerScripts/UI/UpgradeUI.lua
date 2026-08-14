--[[
	UpgradeUI
	The shop panel. Opens from the counter out in the street, never remotely --
	same rule as Mines, for the same reason.

	Every row states what you HAVE and what you'd GET, not just a level number.
	"x1.36 income -> x1.48" is a decision; "level 3 -> 4" is a chore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local UpgradeUI = {}

local ROW_H = 74
local PAD = 16
local HEADER = 56
local PANEL_W = 470
local PANEL_H = HEADER + PAD + #Upgrades.List * (ROW_H + 8) + PAD

function UpgradeUI.init(ctx)
	local ui = {}

	local root = Theme.frame({
		parent = ctx.gui,
		name = "UpgradePanel",
		color = Theme.color.bg,
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 14,
	})
	root.Visible = false
	Theme.stroke(root, Theme.color.line, 1)

	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local viewport = ctx.gui.AbsoluteSize
		if viewport.X < 10 then
			return
		end
		scale.Scale = math.clamp(math.min(viewport.X / (PANEL_W + 40), viewport.Y / (PANEL_H + 40)), 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	Theme.label({
		parent = root,
		text = "UPGRADES",
		font = Theme.font.black,
		textSize = 20,
		size = UDim2.fromOffset(300, 30),
		position = UDim2.fromOffset(PAD, 14),
	})

	Theme.label({
		parent = root,
		text = "permanent, and they stack",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(300, 16),
		position = UDim2.fromOffset(PAD, 34),
	})

	local closeButton = Theme.button({
		parent = root,
		name = "Close",
		text = "✕",
		textSize = 16,
		color = Theme.color.raised,
		size = UDim2.fromOffset(30, 30),
		position = UDim2.new(1, -PAD, 0, 14),
		anchor = Vector2.new(1, 0),
	})
	Theme.iconify(closeButton, "close", 8)
	closeButton.MouseButton1Click:Connect(function()
		ui.setVisible(false)
	end)

	-- ── rows ────────────────────────────────────────────────────────────────

	local rows = {}
	for index, def in ipairs(Upgrades.List) do
		local row = Theme.frame({
			parent = root,
			name = def.id,
			color = Theme.color.panel,
			size = UDim2.new(1, -PAD * 2, 0, ROW_H),
			position = UDim2.fromOffset(PAD, HEADER + PAD + (index - 1) * (ROW_H + 8)),
			radius = 10,
		})
		Theme.stroke(row, def.color, 1, 0.72)
		Theme.padding(row, 10)

		local name = Theme.label({
			parent = row,
			text = def.name,
			font = Theme.font.bold,
			textSize = 15,
			color = def.color,
			size = UDim2.new(1, -150, 0, 18),
		})

		Theme.label({
			parent = row,
			text = def.blurb,
			font = Theme.font.regular,
			textSize = 11,
			color = Theme.color.faint,
			size = UDim2.new(1, -150, 0, 14),
			position = UDim2.fromOffset(0, 19),
		})

		local effect = Theme.label({
			parent = row,
			text = "",
			font = Theme.font.medium,
			textSize = 12,
			color = Theme.color.text,
			size = UDim2.new(1, -150, 0, 16),
			position = UDim2.fromOffset(0, 36),
		})

		local level = Theme.label({
			parent = row,
			text = "",
			font = Theme.font.bold,
			textSize = 11,
			color = Theme.color.dim,
			align = Enum.TextXAlignment.Right,
			size = UDim2.fromOffset(130, 14),
			position = UDim2.new(1, 0, 0, 0),
			anchor = Vector2.new(1, 0),
		})

		local buy = Theme.button({
			parent = row,
			name = "Buy",
			text = "",
			textSize = 13,
			color = def.color,
			textColor = Theme.color.bg,
			size = UDim2.fromOffset(130, 30),
			position = UDim2.new(1, 0, 1, 0),
			anchor = Vector2.new(1, 1),
			radius = 8,
		})

		buy.MouseButton1Click:Connect(function()
			if not buy.Active then
				return
			end
			local ok, result = pcall(ctx.remotes.BuyUpgrade.InvokeServer, ctx.remotes.BuyUpgrade, def.id)
			if not ok then
				warn("[UpgradeUI] BuyUpgrade failed: " .. tostring(result))
				ctx.notify("Something went wrong — try again.", "bad")
				return
			end
			if not result or not result.ok then
				ctx.notify(result and result.err or "Couldn't buy that.", "bad")
			end
		end)

		rows[def.id] = { effect = effect, level = level, buy = buy, name = name }
	end

	-- ── render ──────────────────────────────────────────────────────────────

	local function render()
		local owned = ctx.state.upgrades or {}
		local money = ctx.state.money or 0

		for _, def in ipairs(Upgrades.List) do
			local row = rows[def.id]
			local lvl = owned[def.id] or 0
			local cost = Upgrades.cost(def.id, lvl)

			row.level.Text = ("LV %d / %d"):format(lvl, def.maxLevel)

			if cost then
				-- show the delta, not just the current state: the next value is
				-- what you're actually deciding about
				row.effect.Text = ("%s  →  %s"):format(def.format(lvl), def.format(lvl + 1))
				row.buy.Text = Format.money(cost)
				local affordable = money >= cost
				row.buy.Active = affordable
				Theme.recolor(row.buy, affordable and def.color or Theme.color.raised)
				row.buy.TextColor3 = affordable and Theme.color.bg or Theme.color.faint
			else
				row.effect.Text = def.format(lvl)
				row.buy.Text = "MAXED"
				row.buy.Active = false
				Theme.recolor(row.buy, Theme.color.raised)
				row.buy.TextColor3 = Theme.color.faint
			end
		end
	end

	ctx.onState(function()
		if root.Visible then
			render()
		end
	end)

	-- ── api ─────────────────────────────────────────────────────────────────

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			fit()
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

return UpgradeUI
