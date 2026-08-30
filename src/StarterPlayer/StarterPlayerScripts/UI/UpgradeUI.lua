--[[
	UpgradeUI
	The shop panel. Opens at the street shop counter, never remotely,
	and the server enforces the same rule -- spending is the trip you make, now
	that Mines isn't.

	TWO TABS, ONE PANEL. Items are things you buy and use; upgrades are levels
	you buy and keep. They are different enough to want separate lists and
	similar enough that giving each its own window would mean two trips to the
	same counter.

	Every row states what you HAVE and what you'd GET, not just a level number.
	"x1.36 income -> x1.48" is a decision; "level 3 -> 4" is a chore. The item
	rows hold to the same rule: a boost that's running shows the time left, and
	the sweep shows the money it would actually bank right now.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)
local Items = require(Shared.Items)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local UpgradeUI = {}

local ROW_H = 74
local PAD = 16
local HEADER = 92
local PANEL_W = 470
--[[ Sized to the longer list so switching tabs doesn't resize the window under
     the cursor -- they happen to be equal today, which is not a guarantee. ]]
local ROWS = math.max(#Items.List, #Upgrades.List)
local PANEL_H = HEADER + PAD + ROWS * (ROW_H + 8) + PAD
local TICK = 0.25

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
		text = "SHOP",
		font = Theme.font.black,
		textSize = 20,
		size = UDim2.fromOffset(300, 30),
		position = UDim2.fromOffset(PAD, 14),
	})

	local subtitle = Theme.label({
		parent = root,
		text = "",
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

	-- ── row chrome ──────────────────────────────────────────────────────────

	--[[ Items and upgrades want the same four pieces of furniture in the same
	     four places; only the text differs. Built once here so the two lists
	     can't drift apart visually. ]]
	local function makeRow(parent, index, def)
		local row = Theme.frame({
			parent = parent,
			name = def.id,
			color = Theme.color.panel,
			size = UDim2.new(1, -PAD * 2, 0, ROW_H),
			position = UDim2.fromOffset(PAD, (index - 1) * (ROW_H + 8)),
			radius = 10,
		})
		Theme.stroke(row, def.color, 1, 0.72)
		Theme.padding(row, 10)

		Theme.label({
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

		local status = Theme.label({
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

		return { effect = effect, status = status, buy = buy }
	end

	--[[ One shape for "can you press this and what does it say", so the
	     affordable / unaffordable / unavailable states look identical whichever
	     list they're in.

	     White with a hard dark outline, never dark-on-colour: the price used to
	     be drawn in Theme.color.bg, which reads as black and sat on four
	     different button colours -- fine on the pale ones, muddy on the rest. ]]
	local function setBuy(row, def, label, enabled)
		row.buy.Text = label
		row.buy.Active = enabled
		Theme.recolor(row.buy, enabled and def.color or Theme.color.raised)
		row.buy.TextColor3 = enabled and Theme.color.text or Theme.color.faint
		row.buy.TextStrokeColor3 = Theme.color.line
		row.buy.TextStrokeTransparency = enabled and 0 or 0.6
	end

	local function wire(row, remote, id)
		row.buy.MouseButton1Click:Connect(function()
			if not row.buy.Active then
				return
			end
			local ok, result = pcall(remote.InvokeServer, remote, id)
			if not ok then
				warn("[UpgradeUI] purchase failed: " .. tostring(result))
				ctx.notify("Something went wrong — try again.", "bad")
				return
			end
			--[[ `silent` is the server saying it already told them itself --
				 pressing buy on something you own gets one message, not two. ]]
			if result and not result.ok and not result.silent then
				ctx.notify(result.err or "Couldn't buy that.", "bad")
			end
		end)
	end

	-- ── pages ───────────────────────────────────────────────────────────────

	local body = HEADER + PAD

	local itemPage = Theme.frame({
		parent = root,
		name = "Items",
		size = UDim2.new(1, 0, 0, ROWS * (ROW_H + 8)),
		position = UDim2.fromOffset(0, body),
		transparency = 1,
		radius = false,
	})

	local upgradePage = Theme.frame({
		parent = root,
		name = "Upgrades",
		size = UDim2.new(1, 0, 0, ROWS * (ROW_H + 8)),
		position = UDim2.fromOffset(0, body),
		transparency = 1,
		radius = false,
	})

	local itemRows, upgradeRows = {}, {}
	for index, def in ipairs(Items.List) do
		local row = makeRow(itemPage, index, def)
		wire(row, ctx.remotes.BuyItem, def.id)
		itemRows[def.id] = row
	end
	for index, def in ipairs(Upgrades.List) do
		local row = makeRow(upgradePage, index, def)
		wire(row, ctx.remotes.BuyUpgrade, def.id)
		upgradeRows[def.id] = row
	end

	-- ── tabs ────────────────────────────────────────────────────────────────

	local TAB_W = (PANEL_W - PAD * 2 - 8) / 2
	local tab = "items"
	local tabButtons = {}

	for index, entry in ipairs({
		{ key = "items", text = "ITEMS", sub = "spend it to get ahead" },
		{ key = "upgrades", text = "UPGRADES", sub = "permanent, and they stack" },
	}) do
		local button = Theme.button({
			parent = root,
			name = entry.key,
			text = entry.text,
			textSize = 13,
			color = Theme.color.raised,
			size = UDim2.fromOffset(TAB_W, 30),
			position = UDim2.fromOffset(PAD + (index - 1) * (TAB_W + 8), 54),
			radius = 8,
		})
		tabButtons[entry.key] = { button = button, sub = entry.sub }
		button.MouseButton1Click:Connect(function()
			ui.setTab(entry.key)
		end)
	end

	-- ── render ──────────────────────────────────────────────────────────────

	--[[ Seconds left on a boost, from the countdown the server sent and the
	     moment the client heard it. Never from the client's own clock. ]]
	local function remaining(id)
		local boosts = ctx.state.boosts
		local left = boosts and boosts[id]
		if not left then
			return 0
		end
		return math.max(left - (os.clock() - (ctx.state.boostsAt or os.clock())), 0)
	end

	local function renderItems()
		local money = ctx.state.money or 0

		for _, def in ipairs(Items.List) do
			local row = itemRows[def.id]
			--[[ Per def, not per panel: a `stock` is priced off how many you
			     are holding, so there is no single cost to compare against. ]]
			local cost = Items.costOf(def, def.field and ctx.state[def.field] or 0)
			local affordable = cost ~= nil and money >= cost

			if def.kind == "stock" then
				local held = ctx.state[def.field] or 0
				row.effect.Text = held > 0
					and ("%d in hand  ·  spent one per mine survived"):format(held)
					or def.effect
				row.status.Text = held > 0 and ("x%d"):format(held) or ""
				row.status.TextColor3 = held > 0 and def.color or Theme.color.dim
				--[[ FULL rather than a price, at the cap. A button quoting a
				     number the server will refuse is worse than a dead one. ]]
				setBuy(row, def, cost and Format.money(cost) or "FULL", affordable)
			elseif def.kind == "unlock" and ctx.state[def.flag] == true then
				row.effect.Text = def.effect
				row.status.Text = "OWNED"
				setBuy(row, def, "OWNED", false)
			elseif def.kind == "boost" then
				local left = remaining(def.id)
				row.effect.Text = left > 0
					and ("%s  ·  %s left"):format(def.effect, Format.duration(left))
					or def.effect
				row.status.Text = left > 0 and "ACTIVE" or ""
				row.status.TextColor3 = left > 0 and def.color or Theme.color.dim
				--[[ Still buyable while it's running: a second purchase extends
				     the clock rather than being refused. ]]
				setBuy(row, def, Format.money(cost), affordable)
			else
				--[[ The sweep quotes the money it would actually bank, which is
				     the only honest way to price a convenience against itself. ]]
				local waiting = ctx.state.pending or 0
				row.effect.Text = waiting >= 1
					and ("collects %s right now"):format(Format.money(waiting))
					or "nothing waiting to collect"
				row.status.Text = ""
				setBuy(row, def, Format.money(cost), affordable and waiting >= 1)
			end
		end
	end

	local function renderUpgrades()
		local owned = ctx.state.upgrades or {}
		local money = ctx.state.money or 0

		for _, def in ipairs(Upgrades.List) do
			local row = upgradeRows[def.id]
			local lvl = owned[def.id] or 0
			local cost = Upgrades.cost(def.id, lvl)

			row.status.Text = ("LV %d / %d"):format(lvl, def.maxLevel)

			if cost then
				-- show the delta, not just the current state: the next value is
				-- what you're actually deciding about
				row.effect.Text = ("%s  →  %s"):format(def.format(lvl), def.format(lvl + 1))
				setBuy(row, def, Format.money(cost), money >= cost)
			else
				row.effect.Text = def.format(lvl)
				setBuy(row, def, "MAXED", false)
			end
		end
	end

	local function render()
		if tab == "items" then
			renderItems()
		else
			renderUpgrades()
		end
	end

	function ui.setTab(key)
		tab = key
		itemPage.Visible = key == "items"
		upgradePage.Visible = key == "upgrades"
		for name, entry in pairs(tabButtons) do
			local on = name == key
			Theme.recolor(entry.button, on and Theme.color.panel or Theme.color.raised)
			entry.button.TextColor3 = on and Theme.color.text or Theme.color.faint
			if on then
				subtitle.Text = entry.sub
			end
		end
		render()
	end

	ctx.onState(function()
		if root.Visible then
			render()
		end
	end)

	--[[ The boost countdowns move on their own, without any state arriving to
	     drive them, so the items tab re-renders on a timer while it's open. ]]
	task.spawn(function()
		while true do
			task.wait(TICK)
			if root.Visible and tab == "items" then
				renderItems()
			end
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
	ui.setTab("items")
	fit()
	return ui
end

return UpgradeUI
