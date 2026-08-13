--[[
	InventoryUI
	The collection, and the pad picker -- same panel, two modes.

	Opening it from a pad prompt puts it in picker mode: the header changes and
	clicking a card places that brainrot on the pad you walked up to. Opening it
	from the HUD drops the brainrot on the first free pad instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Variants = require(Shared.Variants)
local Brainrots = require(Shared.Brainrots)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local InventoryUI = {}

local CARD_W, CARD_H = 158, 96
local COLUMNS = 4
local PAD = 16
local HEADER = 56
local SUMMARY = 40 -- tall enough for the 26px Equip Best button plus padding
local PANEL_W = PAD * 2 + COLUMNS * CARD_W + (COLUMNS - 1) * 10 + 10
local PANEL_H = 508

function InventoryUI.init(ctx)
	local ui = {}
	local pickerPad = nil -- non-nil => picker mode for that pad

	local root = Theme.frame({
		parent = ctx.gui,
		name = "InventoryPanel",
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

	local function fitToViewport()
		local viewport = ctx.gui.AbsoluteSize
		if viewport.X < 10 then
			return
		end
		scale.Scale = math.clamp(math.min(viewport.X / (PANEL_W + 40), viewport.Y / (PANEL_H + 40)), 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToViewport)

	local title = Theme.label({
		parent = root,
		text = "COLLECTION",
		font = Theme.font.black,
		textSize = 20,
		size = UDim2.fromOffset(360, 30),
		position = UDim2.fromOffset(PAD, 14),
	})

	local subtitle = Theme.label({
		parent = root,
		text = "",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(420, 16),
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

	-- ── summary strip ───────────────────────────────────────────────────────

	local summary = Theme.frame({
		parent = root,
		name = "Summary",
		color = Theme.color.panel,
		size = UDim2.new(1, -PAD * 2, 0, SUMMARY),
		position = UDim2.fromOffset(PAD, HEADER),
	})
	Theme.padding(summary, 7)

	local incomeLabel = Theme.label({
		parent = summary,
		text = "",
		font = Theme.font.bold,
		textSize = 13,
		color = Theme.color.good,
		size = UDim2.new(0, 120, 1, 0),
	})

	local slotsLabel = Theme.label({
		parent = summary,
		text = "",
		font = Theme.font.medium,
		textSize = 12,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		size = UDim2.new(1, -290, 1, 0),
		position = UDim2.fromOffset(124, 0),
	})

	local equipBestButton = Theme.button({
		parent = summary,
		name = "EquipBest",
		text = "⚡  EQUIP BEST",
		textSize = 12,
		color = Theme.color.accent,
		size = UDim2.fromOffset(158, 26),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		radius = 8,
	})

	-- ── card grid ───────────────────────────────────────────────────────────

	local scroller = Theme.scroller({
		parent = root,
		size = UDim2.new(1, -PAD * 2, 1, -(HEADER + SUMMARY + PAD + 10)),
		position = UDim2.fromOffset(PAD, HEADER + SUMMARY + 10),
	})

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller

	local emptyLabel = Theme.label({
		parent = root,
		text = "No brainrots yet — go win some.",
		font = Theme.font.medium,
		textSize = 14,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromScale(0.5, 0.55),
		anchor = Vector2.new(0.5, 0.5),
	})

	-- ── behaviour ───────────────────────────────────────────────────────────

	local function firstFreePad()
		local used = {}
		for _, item in ipairs(ctx.state.inventory or {}) do
			if item.pad then
				used[item.pad] = true
			end
		end
		for i = 1, (ctx.state.slots or Config.StartingSlots) do
			if not used[i] then
				return i
			end
		end
		return nil
	end

	--[[
		One click, three meanings, decided by context:
		  picker mode      -> place on the pad the player walked up to
		  card is placed   -> take it back off the pad
		  card is stored   -> drop it on the first free pad
		Pad 0 is the server's "store this" sentinel.
	]]
	local function onCardClicked(item)
		local target
		if pickerPad then
			target = pickerPad
		elseif item.pad then
			target = 0
		else
			target = firstFreePad()
			if not target then
				ctx.notify("No free pads — store one first, or unlock more.", "bad")
				return
			end
		end

		-- InvokeServer throws if the handler errors, so never call it bare.
		local ok, result = pcall(ctx.remotes.PlaceBrainrot.InvokeServer, ctx.remotes.PlaceBrainrot, item.uid, target)
		if not ok then
			warn("[InventoryUI] PlaceBrainrot failed: " .. tostring(result))
			ctx.notify("Something went wrong — try again.", "bad")
			return
		end
		if not result or not result.ok then
			ctx.notify(result and result.err or "Couldn't move that.", "bad")
			return
		end

		if pickerPad then
			pickerPad = nil
			ui.setVisible(false)
		end
	end

	local function buildCard(item, order)
		local char = Brainrots.get(item.charId)
		if not char then
			return
		end
		local tier = Rarity.get(char.tier)
		local variant = Variants.get(item.variantId)

		local card = Theme.button({
			parent = scroller,
			name = item.uid,
			text = "",
			color = Theme.color.panel,
			order = order,
			radius = 10,
		})
		Theme.stroke(card, tier.color, item.pad and 2 or 1, item.pad and 0.2 or 0.75)
		Theme.padding(card, 8)

		Theme.label({
			parent = card,
			text = Economy.displayName(item.charId, item.variantId),
			font = Theme.font.bold,
			textSize = 12,
			color = tier.color,
			size = UDim2.new(1, 0, 0, 30),
			valign = Enum.TextYAlignment.Top,
		}).TextWrapped = true

		Theme.label({
			parent = card,
			text = Format.rate(Economy.incomeOf(item.charId, item.variantId)),
			font = Theme.font.black,
			textSize = 15,
			color = Theme.color.good,
			size = UDim2.new(1, 0, 0, 18),
			position = UDim2.fromOffset(0, 32),
		})

		Theme.label({
			parent = card,
			text = char.tier .. (variant.index > 1 and "  •  " .. item.variantId or ""),
			font = Theme.font.medium,
			textSize = 10,
			color = Theme.color.faint,
			size = UDim2.new(1, 0, 0, 12),
			position = UDim2.fromOffset(0, 52),
		})

		Theme.label({
			parent = card,
			text = item.pad and ("ON PAD " .. item.pad) or "STORED",
			font = Theme.font.bold,
			textSize = 10,
			color = item.pad and tier.color or Theme.color.faint,
			size = UDim2.new(0.5, 0, 0, 12),
			position = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
		})

		local actionText
		if pickerPad then
			actionText = "PLACE HERE ▸"
		elseif item.pad then
			actionText = "STORE ▸"
		else
			actionText = "PLACE ▸"
		end

		Theme.label({
			parent = card,
			text = actionText,
			font = Theme.font.bold,
			textSize = 10,
			color = Theme.color.accent,
			align = Enum.TextXAlignment.Right,
			size = UDim2.new(0.5, 0, 0, 12),
			position = UDim2.new(1, 0, 1, 0),
			anchor = Vector2.new(1, 1),
		})

		card.MouseButton1Click:Connect(function()
			onCardClicked(item)
		end)
	end

	local function render()
		for _, child in ipairs(scroller:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		local inventory = ctx.state.inventory or {}

		-- Best first. Placed brainrots float to the top of their own band so the
		-- ones actually earning are never buried under a long tail of commons.
		local sorted = table.clone(inventory)
		table.sort(sorted, function(a, b)
			local aPlaced, bPlaced = a.pad ~= nil, b.pad ~= nil
			if aPlaced ~= bPlaced then
				return aPlaced
			end
			return Economy.powerScore(a.charId, a.variantId) > Economy.powerScore(b.charId, b.variantId)
		end)

		for order, item in ipairs(sorted) do
			buildCard(item, order)
		end

		emptyLabel.Visible = #sorted == 0

		local income = Economy.totalIncome(inventory)
		local placed = 0
		for _, item in ipairs(inventory) do
			if item.pad then
				placed += 1
			end
		end

		incomeLabel.Text = Format.rate(income)
		slotsLabel.Text = string.format(
			"%d / %d pads used   •   %d owned",
			placed,
			ctx.state.slots or Config.StartingSlots,
			#inventory
		)

		-- Meaningless in picker mode: the player already told us which pad they
		-- want filled, and auto-arranging everything would ignore that.
		equipBestButton.Visible = pickerPad == nil

		if pickerPad then
			title.Text = "CHOOSE A BRAINROT"
			subtitle.Text = "for pad " .. pickerPad .. " — click any card"
		else
			title.Text = "COLLECTION"
			subtitle.Text = "click a stored brainrot to put it on a free pad"
		end
	end

	equipBestButton.MouseButton1Click:Connect(function()
		local ok, result = pcall(ctx.remotes.EquipBest.InvokeServer, ctx.remotes.EquipBest)
		if not ok then
			warn("[InventoryUI] EquipBest failed: " .. tostring(result))
			ctx.notify("Something went wrong — try again.", "bad")
			return
		end
		if not result or not result.ok then
			ctx.notify(result and result.err or "Couldn't equip.", "bad")
			return
		end

		-- Report the delta, not just the total: "nothing changed" is a useful
		-- answer and the player should be able to tell it apart from "worked".
		if result.gained > 0.01 then
			ctx.notify(
				string.format(
					"Equipped your %d best — %s (+%s)",
					result.placed,
					Format.rate(result.income),
					Format.rate(result.gained)
				),
				"good"
			)
		else
			ctx.notify("Already running your best " .. result.placed .. ".", "info")
		end
	end)

	closeButton.MouseButton1Click:Connect(function()
		pickerPad = nil
		ui.setVisible(false)
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
			fitToViewport()
			render()
		else
			pickerPad = nil
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	function ui.openForPad(padIndex)
		pickerPad = padIndex
		ui.setVisible(true)
	end

	ui.root = root
	fitToViewport()

	return ui
end

return InventoryUI
