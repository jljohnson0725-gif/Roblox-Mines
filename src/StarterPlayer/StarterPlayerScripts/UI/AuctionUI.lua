--[[
	AuctionUI
	The auction floor panel: what's under the hammer on the left, what you could
	consign on the right.

	Both columns in one view on purpose. The interesting moment is seeing a
	Legendary sitting at the house floor while you're holding two spares you
	can't place -- putting "sell" and "buy" on separate screens would hide
	exactly the comparison the room exists for.

	The countdown ticks locally between server broadcasts. The server only sends
	`timeLeft` (never an absolute clock -- see AuctionService), so this decrements
	its own copy and lets each broadcast correct the drift.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Auction = require(Shared.Auction)
local Brainrots = require(Shared.Brainrots)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Rarity = require(Shared.Rarity)

local Theme = require(script.Parent.Theme)

local AuctionUI = {}

local PANEL_W, PANEL_H = 660, 452
local PAD = 16
local COL_W = (PANEL_W - PAD * 3) / 2
local HEAD_H = 92
local ROW_H = 58

local function tierColor(charId)
	local char = Brainrots.get(charId)
	return Rarity.get(char and char.tier or "Common").color
end

function AuctionUI.init(ctx)
	local ui = {}
	local lots = {}

	local root = Theme.frame({
		parent = ctx.gui,
		name = "AuctionPanel",
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
		scale.Scale = math.clamp(
			math.min(viewport.X / (PANEL_W + 40), viewport.Y / (PANEL_H + 40)), 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	Theme.label({
		parent = root,
		text = "AUCTION HOUSE",
		font = Theme.font.black,
		textSize = 20,
		size = UDim2.fromOffset(360, 30),
		position = UDim2.fromOffset(PAD, 14),
	})
	Theme.label({
		parent = root,
		text = "the house always bids; players can beat it",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(360, 16),
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

	local status = Theme.label({
		parent = root,
		name = "Status",
		text = "",
		font = Theme.font.medium,
		textSize = 12,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromOffset(260, 16),
		position = UDim2.new(1, -PAD - 40, 0, 36),
		anchor = Vector2.new(1, 0),
	})

	local function say(text, good)
		status.Text = text
		status.TextColor3 = good and Theme.color.good or Theme.color.bad
		task.delay(3.5, function()
			if status.Text == text then
				status.Text = ""
			end
		end)
	end

	-- ── column headers ──────────────────────────────────────────────────────
	local function column(title, subtitle, x)
		Theme.label({
			parent = root,
			text = title,
			font = Theme.font.bold,
			textSize = 13,
			size = UDim2.fromOffset(COL_W, 18),
			position = UDim2.fromOffset(x, HEAD_H - 34),
		})
		Theme.label({
			parent = root,
			text = subtitle,
			font = Theme.font.regular,
			textSize = 11,
			color = Theme.color.faint,
			size = UDim2.fromOffset(COL_W, 14),
			position = UDim2.fromOffset(x, HEAD_H - 18),
		})
		local scroller = Theme.scroller({
			parent = root,
			name = title,
			size = UDim2.fromOffset(COL_W, PANEL_H - HEAD_H - PAD),
			position = UDim2.fromOffset(x, HEAD_H),
		})
		Theme.list(scroller, 6)
		return scroller
	end

	local lotList = column("ON THE BLOCK", "bid to take it", PAD)
	local ownList = column("YOUR BRAINROTS", "listing pulls it off its pad", PAD * 2 + COL_W)

	-- ── live lots ───────────────────────────────────────────────────────────
	local lotRows = {} -- [lotId] = { frame, timer }

	local function buildLotRow(lot)
		local frame = Theme.frame({
			parent = lotList,
			name = "Lot" .. lot.id,
			color = Theme.color.tile,
			size = UDim2.new(1, -6, 0, ROW_H),
		})

		Theme.frame({
			parent = frame,
			name = "Pip",
			color = tierColor(lot.charId),
			size = UDim2.fromOffset(3, ROW_H - 16),
			position = UDim2.fromOffset(8, 8),
			radius = 2,
		})

		Theme.label({
			parent = frame,
			text = lot.name,
			font = Theme.font.bold,
			textSize = 13,
			color = tierColor(lot.charId),
			size = UDim2.fromOffset(COL_W - 110, 16),
			position = UDim2.fromOffset(18, 7),
		})
		Theme.label({
			parent = frame,
			text = Format.rate(lot.income) .. "  ·  " .. lot.sellerName,
			font = Theme.font.regular,
			textSize = 10,
			color = Theme.color.faint,
			size = UDim2.fromOffset(COL_W - 110, 13),
			position = UDim2.fromOffset(18, 23),
		})
		local bidLabel = Theme.label({
			parent = frame,
			name = "Bid",
			text = "",
			font = Theme.font.medium,
			textSize = 11,
			color = Theme.color.text,
			size = UDim2.fromOffset(COL_W - 110, 14),
			position = UDim2.fromOffset(18, 37),
		})

		local timer = Theme.label({
			parent = frame,
			name = "Timer",
			text = "",
			font = Theme.font.bold,
			textSize = 11,
			color = Theme.color.dim,
			align = Enum.TextXAlignment.Right,
			size = UDim2.fromOffset(70, 14),
			position = UDim2.new(1, -10, 0, 7),
			anchor = Vector2.new(1, 0),
		})

		local bidButton = Theme.button({
			parent = frame,
			name = "BidButton",
			text = "BID",
			textSize = 11,
			color = Theme.color.gold,
			size = UDim2.fromOffset(80, 24),
			position = UDim2.new(1, -10, 1, -8),
			anchor = Vector2.new(1, 1),
			radius = 8,
		})
		bidButton.MouseButton1Click:Connect(function()
			if not bidButton.Active then
				return
			end
			local current = lots[lot.id]
			if not current then
				return
			end
			local result = ctx.remotes.PlaceBid:InvokeServer(lot.id, current.minNextBid)
			if result and result.ok then
				say("Top bid is yours.", true)
			else
				say(result and result.err or "Bid failed.", false)
			end
		end)

		return { frame = frame, timer = timer, bid = bidLabel, button = bidButton }
	end

	local function renderLots()
		local seen = {}
		local order = 0

		for _, lot in ipairs(lots.ordered or {}) do
			seen[lot.id] = true
			order += 1
			local row = lotRows[lot.id]
			if not row then
				row = buildLotRow(lot)
				lotRows[lot.id] = row
			end
			row.frame.LayoutOrder = order

			local holder = lot.bidderName or "the house"
			row.bid.Text = Format.money(lot.bid) .. "   " .. holder
			row.bid.TextColor3 = lot.bidderId and Theme.color.good or Theme.color.dim

			local mine = lot.sellerId == ctx.userId
			local topBid = lot.bidderId == ctx.userId
			local affordable = (ctx.state.money or 0) >= lot.minNextBid

			row.button.Text = mine and "YOURS"
				or topBid and "WINNING"
				or Format.money(lot.minNextBid)
			row.button.Active = not mine and not topBid and affordable
			Theme.recolor(row.button, row.button.Active and Theme.color.gold or Theme.color.raised)
			row.button.TextColor3 = row.button.Active and Theme.color.bg or Theme.color.faint
		end

		for id, row in pairs(lotRows) do
			if not seen[id] then
				row.frame:Destroy()
				lotRows[id] = nil
			end
		end

		if order == 0 then
			status.Text = ""
		end
	end

	-- ── your brainrots ──────────────────────────────────────────────────────
	local ownRows = {}

	local function renderOwn()
		for _, row in ipairs(ownRows) do
			row:Destroy()
		end
		table.clear(ownRows)

		local items = table.clone(ctx.state.inventory or {})
		table.sort(items, function(a, b)
			return Economy.powerScore(a.charId, a.variantId)
				> Economy.powerScore(b.charId, b.variantId)
		end)

		for index, item in ipairs(items) do
			local frame = Theme.frame({
				parent = ownList,
				name = "Own" .. index,
				color = Theme.color.tile,
				size = UDim2.new(1, -6, 0, ROW_H),
				order = index,
			})
			table.insert(ownRows, frame)

			Theme.frame({
				parent = frame,
				name = "Pip",
				color = tierColor(item.charId),
				size = UDim2.fromOffset(3, ROW_H - 16),
				position = UDim2.fromOffset(8, 8),
				radius = 2,
			})
			Theme.label({
				parent = frame,
				text = Economy.displayName(item.charId, item.variantId),
				font = Theme.font.bold,
				textSize = 13,
				color = tierColor(item.charId),
				size = UDim2.fromOffset(COL_W - 110, 16),
				position = UDim2.fromOffset(18, 7),
			})
			Theme.label({
				parent = frame,
				text = Format.rate(Economy.incomeOf(item.charId, item.variantId))
					.. (item.pad and "  ·  on pad " .. item.pad or "  ·  stored"),
				font = Theme.font.regular,
				textSize = 10,
				color = item.pad and Theme.color.gold or Theme.color.faint,
				size = UDim2.fromOffset(COL_W - 110, 13),
				position = UDim2.fromOffset(18, 23),
			})
			Theme.label({
				parent = frame,
				text = "house pays " .. Format.money(Auction.floorPrice(item.charId, item.variantId)),
				font = Theme.font.medium,
				textSize = 11,
				color = Theme.color.dim,
				size = UDim2.fromOffset(COL_W - 110, 14),
				position = UDim2.fromOffset(18, 37),
			})

			local listButton = Theme.button({
				parent = frame,
				name = "ListButton",
				text = "LIST",
				textSize = 11,
				color = Theme.color.accent,
				size = UDim2.fromOffset(80, 24),
				position = UDim2.new(1, -10, 1, -8),
				anchor = Vector2.new(1, 1),
				radius = 8,
			})
			local uid = item.uid
			listButton.MouseButton1Click:Connect(function()
				local result = ctx.remotes.ListBrainrot:InvokeServer(uid)
				if result and result.ok then
					say("On the block.", true)
				else
					say(result and result.err or "Listing failed.", false)
				end
			end)
		end

		if #items == 0 then
			Theme.label({
				parent = ownList,
				text = "Nothing to sell yet — win some in the Mines.",
				font = Theme.font.regular,
				textSize = 12,
				color = Theme.color.faint,
				size = UDim2.new(1, -6, 0, 40),
			})
		end
	end

	-- ── wiring ──────────────────────────────────────────────────────────────

	function ui.setLots(list)
		lots = { ordered = list }
		for _, lot in ipairs(list) do
			lots[lot.id] = lot
		end
		if root.Visible then
			renderLots()
		end
	end

	ctx.onState(function()
		if root.Visible then
			renderOwn()
			renderLots()
		end
	end)

	--[[ Local countdown between broadcasts. Only touches the timer labels, so a
	     lot's row never rebuilds underneath a click. ]]
	task.spawn(function()
		while true do
			task.wait(0.25)
			if root.Visible then
				for _, lot in ipairs(lots.ordered or {}) do
					lot.timeLeft = math.max(0, (lot.timeLeft or 0) - 0.25)
					local row = lotRows[lot.id]
					if row then
						row.timer.Text = ("%ds"):format(math.ceil(lot.timeLeft))
						row.timer.TextColor3 = lot.timeLeft <= 15
							and Theme.color.bad or Theme.color.dim
					end
				end
			end
		end
	end)

	-- ── api ─────────────────────────────────────────────────────────────────

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			fit()
			renderOwn()
			renderLots()
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ui.root = root
	fit()
	return ui
end

return AuctionUI
