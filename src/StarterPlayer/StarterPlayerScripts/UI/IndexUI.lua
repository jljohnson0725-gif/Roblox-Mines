--[[
	IndexUI
	The collection. Every character in the roster crossed with every variant,
	with the ones you've secured filled in and the rest showing as silhouettes.

	Two things it is NOT:

	  - It is not your inventory. Losing a brainrot removes
	    it from your inventory forever, and a collection you can lose by selling
	    isn't a collection. The server keeps a separate `index` count that only
	    ever goes up.

	  - It is not a list of what you're holding. The count on a tile is how many
	    of that exact pair you have EVER banked, which is why it survives a sale.

	The variant tabs run down the right edge rather than across the top: there
	are seven of them and they read as a rarity ladder, which is a column.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Brainrots = require(Shared.Brainrots)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Rarity = require(Shared.Rarity)
local Variants = require(Shared.Variants)

local Theme = require(script.Parent.Theme)

local IndexUI = {}

local PANEL_W, PANEL_H = 690, 470
local PAD = 16
local TAB_W = 104
local COLS = 4
local CELL_H = 78

--[[ Every (character, variant) pair that can legitimately be owned. Frost is
     event-locked but still rollable during Winter Freeze, so it counts. ]]
local function totalPairs()
	return #Brainrots.List * #Variants.Order
end

function IndexUI.init(ctx)
	local ui = {}
	local activeVariant = "Normal"

	local root = Theme.frame({
		parent = ctx.gui,
		name = "IndexPanel",
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
		local viewport = ctx.gui.AbsoluteSize
		if viewport.X < 10 then
			return
		end
		scale.Scale = math.clamp(
			math.min(viewport.X / (PANEL_W + 40), viewport.Y / (PANEL_H + 40)), 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local heading = Theme.label({
		parent = root,
		name = "Heading",
		text = "INDEX",
		font = Theme.font.black,
		textSize = 22,
		size = UDim2.fromOffset(460, 30),
		position = UDim2.fromOffset(PAD, 12),
	})

	local closeButton = Theme.button({
		parent = root,
		name = "Close",
		text = "✕",
		textSize = 18,
		color = Theme.color.bad,
		size = UDim2.fromOffset(34, 34),
		position = UDim2.new(1, -PAD, 0, 12),
		anchor = Vector2.new(1, 0),
		radius = 10,
	})
	closeButton.MouseButton1Click:Connect(function()
		ui.setVisible(false)
	end)

	-- ── variant tabs, down the right edge ───────────────────────────────────
	local tabColumn = Theme.frame({
		parent = root,
		name = "Tabs",
		transparency = 1,
		size = UDim2.fromOffset(TAB_W, PANEL_H - 100),
		position = UDim2.fromOffset(PANEL_W - PAD - TAB_W, 56),
		radius = false,
	})
	Theme.list(tabColumn, 6)

	local tabButtons = {}
	local render -- forward declared: the tabs re-render on click

	for order, variantId in ipairs(Variants.Order) do
		local variant = Variants.get(variantId)
		local button = Theme.button({
			parent = tabColumn,
			name = variantId,
			text = string.upper(variantId),
			textSize = 12,
			color = variant.color or Theme.color.raised,
			size = UDim2.new(1, 0, 0, 34),
			order = order,
			radius = 10,
		})
		tabButtons[variantId] = button
		button.MouseButton1Click:Connect(function()
			activeVariant = variantId
			render()
		end)
	end

	-- ── the grid ────────────────────────────────────────────────────────────
	local grid = Theme.scroller({
		parent = root,
		name = "Grid",
		size = UDim2.fromOffset(PANEL_W - PAD * 3 - TAB_W, PANEL_H - 100),
		position = UDim2.fromOffset(PAD, 56),
	})

	--[[ Wrapper cells, not a UIGridLayout on the tiles themselves: a grid layout
	     overwrites its children's Size, which would fight the tile styling. ]]
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.CellSize = UDim2.fromOffset(
		(PANEL_W - PAD * 3 - TAB_W - 8 * (COLS - 1) - 10) / COLS, CELL_H)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local footer = Theme.label({
		parent = root,
		name = "Footer",
		text = "Secure a brainrot in the Mines and it's yours here forever — even if you sell it.",
		font = Theme.font.regular,
		textSize = 11,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -PAD * 2, 0, 20),
		position = UDim2.new(0, PAD, 1, -26),
	})

	local cells = {}

	function render()
		local owned = ctx.state.index or {}

		--[[ Tab highlighting. Label colour is chosen by the swatch's luminance
		     rather than fixed: Diamond and Frost are near-white, and white-on-
		     white was unreadable when those tabs were picked. ]]
		for variantId, button in pairs(tabButtons) do
			local on = variantId == activeVariant
			local swatch = Variants.get(variantId).color or Theme.color.raised
			local luma = 0.299 * swatch.R + 0.587 * swatch.G + 0.114 * swatch.B
			button.TextColor3 = luma > 0.6 and Theme.color.line or Theme.color.text
			button.BackgroundTransparency = on and 0 or 0.55
			button.TextSize = on and 13 or 12
			button.TextStrokeTransparency = luma > 0.6 and 1 or 0.4
		end

		local discovered = 0
		for _ in pairs(owned) do
			discovered += 1
		end
		heading.Text = ("INDEX   %d / %d"):format(discovered, totalPairs())

		for _, cell in ipairs(cells) do
			cell:Destroy()
		end
		table.clear(cells)

		local variant = Variants.get(activeVariant)

		for order, char in ipairs(Brainrots.List) do
			local count = owned[char.id .. ":" .. activeVariant] or 0
			local found = count > 0
			local tierColor = Rarity.get(char.tier).color

			local cell = Theme.frame({
				parent = grid,
				name = char.id,
				color = found and Theme.color.tile or Theme.color.panel,
				order = order,
				radius = 10,
			})
			table.insert(cells, cell)
			if found then
				Theme.stroke(cell, tierColor, 2)
			end

			-- rarity band along the top, so a full page reads as a ladder
			Theme.frame({
				parent = cell,
				name = "Band",
				color = found and tierColor or Theme.color.line,
				size = UDim2.new(1, -16, 0, 3),
				position = UDim2.fromOffset(8, 8),
				radius = 2,
			})

			Theme.label({
				parent = cell,
				text = found and char.name or "???",
				font = Theme.font.bold,
				textSize = 12,
				color = found and Theme.color.text or Theme.color.faint,
				size = UDim2.new(1, -16, 0, 15),
				position = UDim2.fromOffset(8, 15),
			})

			Theme.label({
				parent = cell,
				text = found
					and Format.rate(Economy.incomeOf(char.id, activeVariant))
					or "undiscovered",
				font = Theme.font.medium,
				textSize = 11,
				color = found and Theme.color.good or Theme.color.faint,
				size = UDim2.new(1, -16, 0, 14),
				position = UDim2.fromOffset(8, 32),
			})

			Theme.label({
				parent = cell,
				text = char.tier,
				font = Theme.font.regular,
				textSize = 10,
				color = found and tierColor or Theme.color.faint,
				size = UDim2.new(1, -16, 0, 13),
				position = UDim2.fromOffset(8, 48),
			})

			if found then
				Theme.label({
					parent = cell,
					name = "Count",
					text = count .. "x",
					font = Theme.font.black,
					textSize = 13,
					color = variant.color or Theme.color.text,
					align = Enum.TextXAlignment.Right,
					size = UDim2.fromOffset(46, 15),
					position = UDim2.new(1, -8, 0, 48),
					anchor = Vector2.new(1, 0),
				})
			end
		end

		local pageFound = 0
		for _, char in ipairs(Brainrots.List) do
			if (owned[char.id .. ":" .. activeVariant] or 0) > 0 then
				pageFound += 1
			end
		end
		footer.Text = ("%s  ·  %d / %d found  ·  x%g income")
			:format(activeVariant, pageFound, #Brainrots.List, variant.mult)
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

return IndexUI
