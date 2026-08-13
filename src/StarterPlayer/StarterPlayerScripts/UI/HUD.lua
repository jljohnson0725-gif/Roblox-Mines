--[[
	HUD
	Always-on furniture: the money readout, the two panel buttons, toasts, and
	the drop banner.

	The drop banner is deliberately loud and deliberately NOT a "you won this"
	message -- until you cash out, what it announces is still at risk. It says
	FOUND, and the at-risk list in MinesUI is what tells you it isn't yours yet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Events = require(Shared.Events)
local Sounds = require(Shared.Sounds)

local Theme = require(script.Parent.Theme)

local HUD = {}

function HUD.init(ctx)
	local hud = {}

	-- ── money card ──────────────────────────────────────────────────────────

	local card = Theme.frame({
		parent = ctx.gui,
		name = "MoneyCard",
		color = Theme.color.panel,
		size = UDim2.fromOffset(196, 62),
		position = UDim2.fromOffset(16, 16),
		radius = 12,
	})
	Theme.stroke(card, Theme.color.line, 1)
	Theme.padding(card, 10)

	local moneyLabel = Theme.label({
		parent = card,
		text = "$0",
		font = Theme.font.black,
		textSize = 24,
		color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 26),
	})

	-- Pack icon if one is assigned, otherwise the label just keeps the whole row.
	local moneyIcon = Theme.image({
		parent = card,
		slot = "money",
		name = "MoneyIcon",
		size = UDim2.fromOffset(26, 26),
	})
	if moneyIcon then
		moneyLabel.Position = UDim2.fromOffset(32, 0)
		moneyLabel.Size = UDim2.new(1, -32, 0, 26)
	end

	local incomeLabel = Theme.label({
		parent = card,
		text = "$0/s",
		font = Theme.font.medium,
		textSize = 12,
		color = Theme.color.good,
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 28),
	})

	-- ── event card ──────────────────────────────────────────────────────────
	-- Sits under the money card. Always visible: an idle countdown is as much
	-- information as a live event, and a card that appears and vanishes is
	-- easier to miss than one that just changes colour.

	local eventCard = Theme.frame({
		parent = ctx.gui,
		name = "EventCard",
		color = Theme.color.panel,
		size = UDim2.fromOffset(232, 54),
		position = UDim2.fromOffset(16, 86),
		radius = 12,
	})
	local eventStroke = Theme.stroke(eventCard, Theme.color.line, 1)
	Theme.padding(eventCard, 10)

	local eventTitle = Theme.label({
		parent = eventCard,
		text = "NO EVENT",
		font = Theme.font.black,
		textSize = 13,
		color = Theme.color.dim,
		size = UDim2.new(1, -52, 0, 16),
	})

	local eventTimer = Theme.label({
		parent = eventCard,
		text = "--:--",
		font = Theme.font.black,
		textSize = 15,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromOffset(52, 16),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
	})

	local eventBlurb = Theme.label({
		parent = eventCard,
		text = "next event soon",
		font = Theme.font.regular,
		textSize = 11,
		color = Theme.color.faint,
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 19),
	})

	local function clockText(seconds)
		seconds = math.max(0, math.floor(seconds))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end

	local lastActiveId = false -- false = "not yet known", distinct from nil

	local function renderEvent()
		local snapshot = ctx.state.event
		if not snapshot then
			return
		end

		local remaining
		if snapshot.activeId then
			local def = Events.get(snapshot.activeId)
			remaining = snapshot.endsAt - Workspace:GetServerTimeNow()

			eventTitle.Text = string.upper(def and def.name or "EVENT")
			eventTitle.TextColor3 = def and def.color or Theme.color.gold
			eventBlurb.Text = def and def.blurb or ""
			eventBlurb.TextColor3 = Theme.color.dim
			eventTimer.TextColor3 = def and def.color or Theme.color.text
			eventStroke.Color = def and def.color or Theme.color.line
			eventStroke.Thickness = 2
		else
			remaining = snapshot.nextAt - Workspace:GetServerTimeNow()

			eventTitle.Text = "NO EVENT"
			eventTitle.TextColor3 = Theme.color.dim
			-- The upcoming type is intentionally not revealed -- see EventService.
			eventBlurb.Text = "next event in"
			eventBlurb.TextColor3 = Theme.color.faint
			eventTimer.TextColor3 = Theme.color.dim
			eventStroke.Color = Theme.color.line
			eventStroke.Thickness = 1
		end

		eventTimer.Text = clockText(remaining)

		-- announce transitions, but never on the first render after joining
		if lastActiveId ~= false and lastActiveId ~= snapshot.activeId then
			if snapshot.activeId then
				local def = Events.get(snapshot.activeId)
				Sounds.play("unlock")
				hud.notify(string.format("%s has begun — %s", def and def.name or "Event", def and def.blurb or ""), "good")
			else
				hud.notify("Event over.", "info")
			end
		end
		lastActiveId = snapshot.activeId
	end

	-- ── bottom buttons ──────────────────────────────────────────────────────

	local dock = Theme.frame({
		parent = ctx.gui,
		name = "Dock",
		transparency = 1,
		size = UDim2.fromOffset(300, 46),
		position = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 1),
		radius = false,
	})
	Theme.list(dock, 10, Enum.FillDirection.Horizontal)

	local minesButton = Theme.button({
		parent = dock,
		name = "MinesButton",
		text = "MINES  [M]",
		textSize = 14,
		color = Theme.color.accent,
		size = UDim2.fromOffset(145, 46),
		order = 1,
		radius = 12,
	})

	local collectionButton = Theme.button({
		parent = dock,
		name = "CollectionButton",
		text = "COLLECTION  [C]",
		textSize = 13,
		color = Theme.color.raised,
		size = UDim2.fromOffset(145, 46),
		order = 2,
		radius = 12,
	})

	minesButton.MouseButton1Click:Connect(function()
		if hud.onMines then
			hud.onMines()
		end
	end)
	collectionButton.MouseButton1Click:Connect(function()
		if hud.onCollection then
			hud.onCollection()
		end
	end)

	-- ── toasts ──────────────────────────────────────────────────────────────

	local toastStack = Theme.frame({
		parent = ctx.gui,
		name = "Toasts",
		transparency = 1,
		size = UDim2.fromOffset(420, 200),
		position = UDim2.new(0.5, 0, 0, 16),
		anchor = Vector2.new(0.5, 0),
		radius = false,
	})
	local toastLayout = Theme.list(toastStack, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local TOAST_COLOR = {
		good = Theme.color.good,
		bad = Theme.color.bad,
		info = Theme.color.dim,
	}

	function hud.notify(text, kind)
		local accent = TOAST_COLOR[kind or "info"] or Theme.color.dim

		local toast = Theme.frame({
			parent = toastStack,
			name = "Toast",
			color = Theme.color.panel,
			size = UDim2.fromOffset(400, 34),
			radius = 10,
		})
		Theme.stroke(toast, accent, 1, 0.4)

		Theme.label({
			parent = toast,
			text = text,
			font = Theme.font.medium,
			textSize = 13,
			color = Theme.color.text,
			align = Enum.TextXAlignment.Center,
			size = UDim2.fromScale(1, 1),
		})

		toast.BackgroundTransparency = 1
		TweenService:Create(toast, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()

		task.delay(3, function()
			if toast.Parent then
				local fade = TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
				fade:Play()
				fade.Completed:Wait()
				toast:Destroy()
			end
		end)
	end

	-- ── drop banner ─────────────────────────────────────────────────────────

	local dropStack = Theme.frame({
		parent = ctx.gui,
		name = "Drops",
		transparency = 1,
		size = UDim2.fromOffset(340, 240),
		position = UDim2.new(1, -16, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		radius = false,
	})
	local dropLayout = Theme.list(dropStack, 6)
	dropLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dropLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	function hud.flashDrop(drop, tier)
		local displayName = Economy.displayName(drop.charId, drop.variantId)
		local incomeText = Format.rate(drop.income or Economy.incomeOf(drop.charId, drop.variantId))

		local banner = Theme.frame({
			parent = dropStack,
			name = "Drop",
			color = Theme.color.panel,
			size = UDim2.fromOffset(320, 52),
			radius = 12,
		})
		Theme.stroke(banner, tier.color, 2, 0.15)
		Theme.padding(banner, 10)

		Theme.label({
			parent = banner,
			text = "★  FOUND",
			font = Theme.font.black,
			textSize = 10,
			color = tier.color,
			size = UDim2.new(1, 0, 0, 12),
		})

		Theme.label({
			parent = banner,
			text = displayName,
			font = Theme.font.bold,
			textSize = 14,
			color = Theme.color.text,
			size = UDim2.new(1, -70, 0, 18),
			position = UDim2.fromOffset(0, 14),
		})

		Theme.label({
			parent = banner,
			text = incomeText,
			font = Theme.font.black,
			textSize = 14,
			color = Theme.color.good,
			align = Enum.TextXAlignment.Right,
			size = UDim2.fromOffset(70, 18),
			position = UDim2.new(1, 0, 0, 14),
			anchor = Vector2.new(1, 0),
		})

		Theme.label({
			parent = banner,
			text = "at risk until you cash out",
			font = Theme.font.regular,
			textSize = 10,
			color = Theme.color.faint,
			size = UDim2.new(1, 0, 0, 10),
			position = UDim2.fromOffset(0, 32),
		})

		banner.Position = UDim2.fromOffset(60, 0)
		TweenService:Create(banner, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		}):Play()

		task.delay(3.5, function()
			if banner.Parent then
				local fade = TweenService:Create(banner, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
				fade:Play()
				fade.Completed:Wait()
				banner:Destroy()
			end
		end)
	end

	-- ── state ───────────────────────────────────────────────────────────────

	function hud.render()
		moneyLabel.Text = Format.money(math.floor(ctx.state.money or 0))
		incomeLabel.Text = Format.rate(ctx.state.income or 0)
	end

	ctx.onState(hud.render)
	ctx.onState(renderEvent)
	hud.render()

	-- The countdown has to tick on its own -- the server only pushes on
	-- transitions, not once a second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			renderEvent()
		end
	end)

	return hud
end

return HUD
