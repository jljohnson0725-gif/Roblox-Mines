--[[
	MinesUI
	The gambling panel.

	The one non-obvious choice here: the odds panel shows the tier odds for the
	NEXT tile, not the current one. That's the number the player is actually
	deciding on -- "if I click again, what am I playing for" -- and watching
	Legendary climb from 0.4% to 4% as you go deeper is the entire hook.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MinesMath = require(Shared.MinesMath)
local DropTable = require(Shared.DropTable)
local Rarity = require(Shared.Rarity)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Sounds = require(Shared.Sounds)
local Events = require(Shared.Events)

local Theme = require(script.Parent.Theme)

local MinesUI = {}

local GRID = Config.GridSize
local CELL = 84
local GAP = 9
local GRID_PX = GRID * CELL + (GRID - 1) * GAP -- 456

-- panel geometry, all derived so changing CELL doesn't break the layout
local PAD = 18
local HEADER = 58
local BOARD = GRID_PX + 16 -- grid frame, incl. its own padding
local SIDE_W = 280
local PANEL_W = PAD + BOARD + 10 + SIDE_W + PAD
local PANEL_H = HEADER + BOARD + PAD

function MinesUI.init(ctx)
	local ui = {}

	local round = nil -- mirrors the server's live round
	local busy = false
	local mineIndex = table.find(Config.MineOptions, Config.DefaultMines) or 2
	local bet = Config.MinBet

	-- ── shell ───────────────────────────────────────────────────────────────

	local root = Theme.frame({
		parent = ctx.gui,
		name = "MinesPanel",
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
		local want = math.min(viewport.X / (root.Size.X.Offset + 40), viewport.Y / (root.Size.Y.Offset + 40))
		scale.Scale = math.clamp(want, 0.5, 1)
	end
	ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToViewport)

	Theme.label({
		parent = root,
		text = "MINES",
		font = Theme.font.black,
		textSize = 20,
		color = Theme.color.text,
		size = UDim2.fromOffset(200, 32),
		position = UDim2.fromOffset(18, 14),
	})

	Theme.label({
		parent = root,
		text = "pick tiles, bank before you bust",
		font = Theme.font.regular,
		textSize = 12,
		color = Theme.color.faint,
		size = UDim2.fromOffset(320, 16),
		position = UDim2.fromOffset(80, 22),
	})

	local closeButton = Theme.button({
		parent = root,
		name = "Close",
		text = "✕",
		textSize = 16,
		color = Theme.color.raised,
		size = UDim2.fromOffset(30, 30),
		position = UDim2.new(1, -14, 0, 14),
		anchor = Vector2.new(1, 0),
	})

	-- ── grid ────────────────────────────────────────────────────────────────

	local gridFrame = Theme.frame({
		parent = root,
		name = "Grid",
		color = Theme.color.panel,
		size = UDim2.fromOffset(BOARD, BOARD),
		position = UDim2.fromOffset(PAD, HEADER),
		radius = 10,
	})
	Theme.padding(gridFrame, 8)

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CELL, CELL)
	gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridFrame

	-- Each tile lives inside a wrapper cell. UIGridLayout force-sets the size of
	-- its direct children, so a tile parented straight to the grid could never
	-- be scale-tweened -- the layout would stomp it every frame.
	local tiles = {}
	for i = 1, Config.TileCount do
		local cell = Theme.frame({
			parent = gridFrame,
			name = "Cell" .. i,
			transparency = 1,
			order = i,
			radius = false,
		})

		tiles[i] = Theme.button({
			parent = cell,
			name = "Tile" .. i,
			text = "",
			textSize = 30,
			color = Theme.color.tile,
			hover = Theme.color.tileHover,
			silent = true, -- reveal sound is pitched by depth instead
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			radius = 8,
		})
	end

	-- ── right column ────────────────────────────────────────────────────────

	local side = Theme.frame({
		parent = root,
		name = "Controls",
		color = Theme.color.bg,
		transparency = 1,
		size = UDim2.fromOffset(SIDE_W, BOARD),
		position = UDim2.fromOffset(PAD + BOARD + 10, HEADER),
		radius = false,
	})
	Theme.list(side, 8)

	local function sectionLabel(text, order)
		return Theme.label({
			parent = side,
			text = text,
			font = Theme.font.bold,
			textSize = 10,
			color = Theme.color.faint,
			size = UDim2.new(1, 0, 0, 12),
			order = order,
		})
	end

	-- bet row
	sectionLabel("BET", 1)

	local betRow = Theme.frame({
		parent = side,
		name = "BetRow",
		color = Theme.color.panel,
		size = UDim2.new(1, 0, 0, 38),
		order = 2,
	})
	Theme.padding(betRow, 6)

	local betBox = Instance.new("TextBox")
	betBox.Name = "BetBox"
	betBox.BackgroundTransparency = 1
	betBox.Size = UDim2.new(1, -132, 1, 0)
	betBox.Font = Theme.font.bold
	betBox.TextSize = 16
	betBox.TextColor3 = Theme.color.text
	betBox.TextXAlignment = Enum.TextXAlignment.Left
	betBox.Text = tostring(bet)
	betBox.ClearTextOnFocus = false
	betBox.Parent = betRow

	local function quickButton(text, offsetX, handler)
		local button = Theme.button({
			parent = betRow,
			name = text,
			text = text,
			textSize = 11,
			color = Theme.color.raised,
			size = UDim2.fromOffset(40, 26),
			position = UDim2.new(1, offsetX, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			radius = 6,
		})
		button.MouseButton1Click:Connect(handler)
		return button
	end

	-- ── mines selector ──────────────────────────────────────────────────────

	sectionLabel("MINES", 3)

	local mineRow = Theme.frame({
		parent = side,
		name = "MineRow",
		color = Theme.color.panel,
		size = UDim2.new(1, 0, 0, 38),
		order = 4,
	})

	local minesDown = Theme.button({
		parent = mineRow,
		name = "Down",
		text = "◀",
		textSize = 14,
		color = Theme.color.raised,
		size = UDim2.fromOffset(34, 26),
		position = UDim2.fromOffset(6, 6),
		radius = 6,
	})

	local minesUp = Theme.button({
		parent = mineRow,
		name = "Up",
		text = "▶",
		textSize = 14,
		color = Theme.color.raised,
		size = UDim2.fromOffset(34, 26),
		position = UDim2.new(1, -6, 0, 6),
		anchor = Vector2.new(1, 0),
		radius = 6,
	})

	local minesLabel = Theme.label({
		parent = mineRow,
		text = "3",
		font = Theme.font.bold,
		textSize = 16,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -92, 1, 0),
		position = UDim2.fromOffset(46, 0),
	})

	-- ── payout readout ──────────────────────────────────────────────────────

	local payoutBox = Theme.frame({
		parent = side,
		name = "Payout",
		color = Theme.color.panel,
		size = UDim2.new(1, 0, 0, 56),
		order = 5,
	})
	Theme.padding(payoutBox, 8)

	local multiplierLabel = Theme.label({
		parent = payoutBox,
		text = "1.00x",
		font = Theme.font.black,
		textSize = 26,
		color = Theme.color.gold,
		size = UDim2.new(0.5, 0, 1, 0),
	})

	local payoutLabel = Theme.label({
		parent = payoutBox,
		text = "$0",
		font = Theme.font.bold,
		textSize = 15,
		color = Theme.color.good,
		align = Enum.TextXAlignment.Right,
		size = UDim2.new(0.5, 0, 0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
	})

	local safeLabel = Theme.label({
		parent = payoutBox,
		text = "",
		font = Theme.font.medium,
		textSize = 11,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		size = UDim2.new(0.5, 0, 0.5, 0),
		position = UDim2.new(0.5, 0, 0.5, 0),
	})

	-- ── odds panel ──────────────────────────────────────────────────────────

	local oddsHeader = Theme.label({
		parent = side,
		text = "NEXT TILE ODDS",
		font = Theme.font.bold,
		textSize = 10,
		color = Theme.color.faint,
		size = UDim2.new(1, 0, 0, 12),
		order = 6,
	})

	-- 110 = 14 padding + 12 spacing + 7 rows x 12
	local oddsBox = Theme.frame({
		parent = side,
		name = "Odds",
		color = Theme.color.panel,
		size = UDim2.new(1, 0, 0, 110),
		order = 7,
	})
	Theme.padding(oddsBox, 7)
	Theme.list(oddsBox, 2)

	local oddsRows = {}
	for order, tierName in ipairs(Rarity.Order) do
		local tier = Rarity.get(tierName)

		local row = Theme.frame({
			parent = oddsBox,
			name = tierName,
			color = Theme.color.bg,
			transparency = 1,
			size = UDim2.new(1, 0, 0, 12),
			order = order,
			radius = false,
		})

		Theme.label({
			parent = row,
			text = tierName,
			font = Theme.font.medium,
			textSize = 11,
			color = tier.color,
			size = UDim2.fromOffset(66, 12),
		})

		local track = Theme.frame({
			parent = row,
			name = "Track",
			color = Theme.color.raised,
			size = UDim2.new(1, -66 - 46, 0, 5),
			position = UDim2.fromOffset(66, 4),
			radius = 3,
		})

		local fill = Theme.frame({
			parent = track,
			name = "Fill",
			color = tier.color,
			size = UDim2.fromScale(0, 1),
			radius = 3,
		})

		local value = Theme.label({
			parent = row,
			text = "0%",
			font = Theme.font.medium,
			textSize = 10,
			color = Theme.color.dim,
			align = Enum.TextXAlignment.Right,
			size = UDim2.fromOffset(44, 12),
			position = UDim2.new(1, 0, 0, 0),
			anchor = Vector2.new(1, 0),
		})

		oddsRows[tierName] = { fill = fill, value = value }
	end

	-- ── at-risk list ────────────────────────────────────────────────────────

	local riskHeader = Theme.label({
		parent = side,
		text = "AT RISK — 0",
		font = Theme.font.bold,
		textSize = 10,
		color = Theme.color.bad,
		size = UDim2.new(1, 0, 0, 12),
		order = 8,
	})

	local riskBox = Theme.frame({
		parent = side,
		name = "AtRisk",
		color = Theme.color.panel,
		size = UDim2.new(1, 0, 0, 62),
		order = 9,
	})

	local riskList = Theme.scroller({
		parent = riskBox,
		size = UDim2.new(1, -8, 1, -8),
		position = UDim2.fromOffset(4, 4),
	})
	Theme.list(riskList, 2)

	local riskEmpty = Theme.label({
		parent = riskBox,
		text = "nothing yet",
		font = Theme.font.regular,
		textSize = 11,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Center,
		size = UDim2.fromScale(1, 1),
	})

	-- ── action button ───────────────────────────────────────────────────────

	local actionButton = Theme.button({
		parent = side,
		name = "Action",
		text = "PLAY",
		textSize = 16,
		color = Theme.color.accent,
		size = UDim2.new(1, 0, 0, 44),
		order = 10,
		radius = 10,
	})

	-- ── rendering ───────────────────────────────────────────────────────────

	local function currentMines()
		return Config.MineOptions[mineIndex]
	end

	--[[
		Live event modifiers, so the odds panel tells the truth during an event
		rather than showing the base curve. Same shared DropTable the server
		rolls on, so the two can't disagree.
	]]
	local function eventMods()
		local snapshot = ctx.state.event
		return snapshot and Events.modsFor(snapshot.activeId) or nil
	end

	local function renderOdds(multiplier, mines)
		local mods = eventMods()
		local odds = DropTable.tierOdds(multiplier, mods)
		local peak = 0
		for _, p in pairs(odds) do
			peak = math.max(peak, p)
		end

		-- Surfacing drop chance here is what makes a Lucky Streak visible.
		local chance = DropTable.dropChance(mines, mods)
		local eventName = ctx.state.event and Events.get(ctx.state.event.activeId)
		if eventName then
			oddsHeader.Text = string.format("NEXT TILE ODDS · %s DROP · %s", Format.percent(chance), string.upper(eventName.name))
			oddsHeader.TextColor3 = eventName.color
		else
			oddsHeader.Text = string.format("NEXT TILE ODDS · %s DROP", Format.percent(chance))
			oddsHeader.TextColor3 = Theme.color.faint
		end

		for tierName, row in pairs(oddsRows) do
			local p = odds[tierName] or 0
			-- Compressed scale: a linear bar would make Secret invisible at
			-- every multiplier a player will realistically reach.
			local width = peak > 0 and (p / peak) ^ 0.35 or 0
			row.fill.Size = UDim2.fromScale(width, 1)
			row.value.Text = Format.percent(p)
		end
	end

	local function renderRisk()
		for _, child in ipairs(riskList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local unsecured = round and round.unsecured or {}
		riskEmpty.Visible = #unsecured == 0
		riskHeader.Text = string.format("AT RISK — %d", #unsecured)

		local total = 0
		for order, drop in ipairs(unsecured) do
			local tier = Rarity.get(drop.tier)
			total += drop.income or 0

			local row = Theme.frame({
				parent = riskList,
				name = "Drop" .. order,
				color = Theme.color.bg,
				transparency = 1,
				size = UDim2.new(1, -4, 0, 14),
				order = order,
				radius = false,
			})

			Theme.label({
				parent = row,
				text = Economy.displayName(drop.charId, drop.variantId),
				font = Theme.font.medium,
				textSize = 11,
				color = tier.color,
				size = UDim2.new(1, -60, 1, 0),
			})

			Theme.label({
				parent = row,
				text = Format.rate(drop.income or 0),
				font = Theme.font.medium,
				textSize = 10,
				color = Theme.color.good,
				align = Enum.TextXAlignment.Right,
				size = UDim2.fromOffset(58, 14),
				position = UDim2.new(1, 0, 0, 0),
				anchor = Vector2.new(1, 0),
			})
		end

		if #unsecured > 0 then
			riskHeader.Text = string.format("AT RISK — %d  (%s)", #unsecured, Format.rate(total))
		end
	end

	local function setTileIdle(tile)
		tile.Text = ""
		tile.Active = true
		tile.Size = UDim2.fromScale(1, 1)
		Theme.recolor(tile, Theme.color.tile)
		tile.BackgroundTransparency = 0
	end

	local function renderIdle()
		for _, tile in ipairs(tiles) do
			setTileIdle(tile)
		end

		local mines = currentMines()
		minesLabel.Text = tostring(mines)
		betBox.TextEditable = true
		minesDown.Active = true
		minesUp.Active = true

		multiplierLabel.Text = "1.00x"
		payoutLabel.Text = Format.money(bet)
		safeLabel.Text = string.format("%s safe next", Format.percent(MinesMath.nextTileSafeChance(mines, 0)))

		actionButton.Text = "PLAY  " .. Format.money(bet)
		Theme.recolor(actionButton, Theme.color.accent)
		actionButton.Active = true

		renderOdds(MinesMath.multiplier(mines, 1), mines)
		renderRisk()
	end

	local function renderActive()
		local mines = round.mines
		betBox.TextEditable = false
		minesDown.Active = false
		minesUp.Active = false

		multiplierLabel.Text = Format.multiplier(round.multiplier)
		payoutLabel.Text = Format.money(math.floor(round.bet * round.multiplier))
		safeLabel.Text = string.format("%s safe next", Format.percent(MinesMath.nextTileSafeChance(mines, round.picks)))

		if round.picks < 1 then
			actionButton.Text = "PICK A TILE"
			Theme.recolor(actionButton, Theme.color.raised)
			actionButton.Active = false
		else
			actionButton.Text = "CASH OUT  " .. Format.money(math.floor(round.bet * round.multiplier))
			Theme.recolor(actionButton, Theme.color.good)
			actionButton.Active = true
		end

		renderOdds(MinesMath.multiplier(mines, round.picks + 1), mines)
		renderRisk()
	end

	local function render()
		if round then
			renderActive()
		else
			renderIdle()
		end
	end

	-- ── tile reveal visuals ─────────────────────────────────────────────────

	local function markSafe(index, drop)
		local tile = tiles[index]
		tile.Active = false
		if drop then
			local tier = Rarity.get(drop.tier)
			Theme.recolor(tile, tier.color)
			tile.TextColor3 = Theme.color.bg
			tile.Text = "★"
		else
			Theme.recolor(tile, Theme.color.raised)
			tile.TextColor3 = Theme.color.good
			tile.Text = "◆"
		end

		tile.Size = UDim2.fromScale(0.72, 0.72)
		TweenService:Create(tile, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 1),
		}):Play()
	end

	local function markMine(index, isTrigger)
		local tile = tiles[index]
		tile.Active = false
		tile.Text = "✖"
		tile.TextColor3 = isTrigger and Color3.new(1, 1, 1) or Theme.color.bad
		Theme.recolor(tile, isTrigger and Theme.color.bad or Theme.color.panel)
		tile.BackgroundTransparency = isTrigger and 0 or 0.35
	end

	-- ── actions ─────────────────────────────────────────────────────────────

	--[[
		InvokeServer THROWS if the server handler errors or the player is
		disconnecting. Without this, `busy` would be stranded true and the panel
		would lock up permanently with no way back short of rejoining.
	]]
	local function invoke(remote, ...)
		busy = true
		local ok, result = pcall(remote.InvokeServer, remote, ...)
		busy = false
		if not ok then
			warn("[MinesUI] remote failed: " .. tostring(result))
			Sounds.play("uiDenied")
			ctx.notify("Something went wrong — try again.", "bad")
			return nil
		end
		return result
	end

	local function clampBet()
		local money = math.floor(ctx.state.money or 0)
		bet = math.clamp(math.floor(bet), Config.MinBet, math.max(Config.MinBet, money))
		betBox.Text = tostring(bet)
	end

	local function startRound()
		clampBet()
		local result = invoke(ctx.remotes.StartRound, bet, currentMines())
		if not result or not result.ok then
			-- a nil result means invoke() already reported the throw
			if result then
				Sounds.play("uiDenied")
				ctx.notify(result.err or "Couldn't start round.", "bad")
			end
			return
		end

		Sounds.play("betPlace")

		round = {
			bet = result.round.bet,
			mines = result.round.mines,
			picks = 0,
			multiplier = 1,
			unsecured = {},
		}
		for _, tile in ipairs(tiles) do
			setTileIdle(tile)
		end
		render()
	end

	local function finishRound(message, kind)
		round = nil
		if message then
			ctx.notify(message, kind)
		end
		-- Leave the board on screen for a beat so the result is readable.
		task.delay(1.6, function()
			if not round then
				render()
			end
		end)
		-- but update the controls immediately
		betBox.TextEditable = true
		minesDown.Active = true
		minesUp.Active = true
		actionButton.Text = "PLAY  " .. Format.money(bet)
		Theme.recolor(actionButton, Theme.color.accent)
		actionButton.Active = true
	end

	local function cashOut()
		if not round or busy then
			return
		end
		local result = invoke(ctx.remotes.CashOut)
		if not result or not result.ok then
			if result then
				ctx.notify(result.err or "Couldn't cash out.", "bad")
			end
			return
		end

		-- Rising flourish, longer the more you banked.
		Sounds.arpeggio("cashout", 3 + math.min(#result.secured, 3), 0, 0.075)

		local count = #result.secured
		local message
		if count > 0 then
			message = string.format("Banked %s and %d brainrot%s", Format.money(result.payout), count, count == 1 and "" or "s")
		else
			message = string.format("Banked %s", Format.money(result.payout))
		end
		finishRound(message, "good")
	end

	local function revealTile(index)
		if not round or busy then
			return
		end
		local result = invoke(ctx.remotes.RevealTile, index)
		if not result or not result.ok then
			return
		end

		if result.mine then
			Sounds.play("bust")
			-- Shake scales with what the run was actually worth, so a deep bust
			-- hits harder than losing a one-tile poke.
			ctx.fx.shakeBy(0.8 + math.min(#result.lostBrainrots, 6) * 0.25)
			ctx.fx.flashColor(Theme.color.bad, 0.42, 0.5)

			markMine(index, true)
			for i, isMine in ipairs(result.board) do
				if isMine and i ~= index then
					markMine(i, false)
				end
			end
			local lost = #result.lostBrainrots
			local message = lost > 0
				and string.format("Busted. Lost %s and %d brainrot%s.", Format.money(result.lostBet), lost, lost == 1 and "" or "s")
				or string.format("Busted. Lost %s.", Format.money(result.lostBet))
			finishRound(message, "bad")
			return
		end

		round.picks = result.picks
		round.multiplier = result.multiplier
		if result.drop then
			table.insert(round.unsecured, result.drop)
		end
		markSafe(index, result.drop)

		-- One semitone per safe tile. A run plays as a rising scale, so the
		-- tension builds out of the audio itself. Capped so deep runs on low
		-- mine counts don't end up inaudibly shrill.
		Sounds.play("tileReveal", Sounds.SEMITONE ^ math.min(result.picks, 18))

		if result.drop then
			ctx.flashDrop(result.drop, Rarity.get(result.drop.tier))
			ctx.fx.drop(result.drop)
		end

		if result.cleared and result.cashout and result.cashout.ok then
			render()
			finishRound(string.format("Cleared the board! Banked %s", Format.money(result.cashout.payout)), "good")
			return
		end

		render()
	end

	-- ── wiring ──────────────────────────────────────────────────────────────

	for i, tile in ipairs(tiles) do
		tile.MouseButton1Click:Connect(function()
			if tile.Active then
				revealTile(i)
			end
		end)
	end

	actionButton.MouseButton1Click:Connect(function()
		if not actionButton.Active or busy then
			return
		end
		if round then
			cashOut()
		else
			startRound()
		end
	end)

	minesDown.MouseButton1Click:Connect(function()
		if round then
			return
		end
		mineIndex = math.max(1, mineIndex - 1)
		render()
	end)

	minesUp.MouseButton1Click:Connect(function()
		if round then
			return
		end
		mineIndex = math.min(#Config.MineOptions, mineIndex + 1)
		render()
	end)

	betBox.FocusLost:Connect(function()
		bet = tonumber(betBox.Text) or bet
		clampBet()
		if not round then
			render()
		end
	end)

	quickButton("MAX", -4, function()
		if round then
			return
		end
		bet = math.floor(ctx.state.money or 0)
		clampBet()
		render()
	end)
	quickButton("2×", -48, function()
		if round then
			return
		end
		bet *= 2
		clampBet()
		render()
	end)
	quickButton("½", -92, function()
		if round then
			return
		end
		bet = math.floor(bet / 2)
		clampBet()
		render()
	end)

	closeButton.MouseButton1Click:Connect(function()
		ui.setVisible(false)
	end)

	local lastEventId = nil

	ctx.onState(function()
		-- Full re-render only when the EVENT changes. This fires on every
		-- income tick too, and renderRisk() rebuilds frames -- doing that once a
		-- second would be pure churn.
		local id = ctx.state.event and ctx.state.event.activeId
		if id ~= lastEventId then
			lastEventId = id
			if root.Visible then
				render()
			end
		end

		if not round then
			-- Keep the payout preview honest when passive income lands.
			payoutLabel.Text = Format.money(bet)
		end
	end)

	-- ── api ─────────────────────────────────────────────────────────────────

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			fitToViewport()
			render()
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	function ui.hasRound()
		return round ~= nil
	end

	ui.root = root
	render()
	fitToViewport()

	return ui
end

return MinesUI
