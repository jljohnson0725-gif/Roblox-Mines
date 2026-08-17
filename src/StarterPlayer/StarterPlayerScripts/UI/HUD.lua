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

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)

--[[
	Vertical start of the HUD stack.

	The ScreenGui sets IgnoreGuiInset, so our coordinates begin at the very top
	of the screen -- straight underneath Roblox's own topbar. GetGuiInset covers
	the bar itself, but the menu and chat buttons hang BELOW it on the left, so
	an inset-only offset still collides. The extra clearance clears the buttons.
]]
--[[
	Clearance below the Roblox topbar. The ScreenGui sets IgnoreGuiInset, so
	nothing is pushed down for us and every top-anchored element has to add
	this itself.

	IT IS RACED AT STARTUP. GetGuiInset returns 0 until the topbar has been
	measured, and which modules read before that point varies run to run --
	caught with the event card at y=44, tucked under the topbar, while a card
	built moments later correctly used 58. A one-off read at build time is
	therefore not safe, so `topAnchored` re-applies the offset once the value
	settles.
]]
local function hudTop()
	return GuiService:GetGuiInset().Y + 44
end

--[[ Remember a top-anchored element and its X, and keep its Y correct. ]]
local topAnchored = {}
local function anchorTop(frame, x)
	table.insert(topAnchored, { frame = frame, x = x })
	frame.Position = UDim2.new(x.Scale, x.Offset, 0, hudTop())
end

task.spawn(function()
	--[[ Cheap and short: the inset settles within the first frames, and a
	     resize or a topbar change is the only other thing that moves it, both
	     of which the ViewportSize signal below covers. ]]
	for _ = 1, 12 do
		task.wait(0.1)
		for _, entry in ipairs(topAnchored) do
			entry.frame.Position = UDim2.new(entry.x.Scale, entry.x.Offset, 0, hudTop())
		end
	end
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for _, entry in ipairs(topAnchored) do
			entry.frame.Position = UDim2.new(entry.x.Scale, entry.x.Offset, 0, hudTop())
		end
	end)
end

local HUD = {}

function HUD.init(ctx)
	local hud = {}

	-- ── money card ──────────────────────────────────────────────────────────

	--[[
		Bottom CENTRE, and big.

		It used to be a small card in the top-left corner. In this genre the
		money number is the score -- it's what you watch tick while you decide
		whether to bet again -- and the corner is where you put things you check
		occasionally. Centre-bottom sits directly under where your eyes already
		are, and it's the one HUD element the reference makes unmissable.

		No panel behind it: a heavy text stroke reads cleanly over a bright map,
		whereas a dark card would punch a hole in it.
	]]
	local card = Theme.frame({
		parent = ctx.gui,
		name = "MoneyCard",
		transparency = 1,
		size = UDim2.fromOffset(460, 74),
		position = UDim2.new(0.5, 0, 1, -14),
		anchor = Vector2.new(0.5, 1),
		radius = false,
	})

	local moneyLabel = Theme.label({
		parent = card,
		text = "$0",
		font = Theme.font.black,
		textSize = 42,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 46),
	})
	moneyLabel.TextStrokeColor3 = Theme.color.line
	moneyLabel.TextStrokeTransparency = 0

	local incomeLabel = Theme.label({
		parent = card,
		text = "$0/s",
		font = Theme.font.medium,
		textSize = 15,
		color = Theme.color.good,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 48),
	})
	incomeLabel.TextStrokeColor3 = Theme.color.line
	incomeLabel.TextStrokeTransparency = 0.25

	-- ── event card ──────────────────────────────────────────────────────────
	-- Top-left now that the money moved to the bottom, and it inherits the
	-- corner the money used to hold. Always visible: an idle countdown is as
	-- much information as a live event, and a card that appears and vanishes is
	-- easier to miss than one that just changes colour.

	local eventCard = Theme.frame({
		parent = ctx.gui,
		name = "EventCard",
		color = Theme.color.panel,
		size = UDim2.fromOffset(232, 54),
		position = UDim2.fromOffset(16, hudTop()),
		radius = 12,
	})
	anchorTop(eventCard, UDim.new(0, 16))

	local eventStroke = Theme.stroke(eventCard, Theme.color.line, 2)
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

	-- ── left rail ───────────────────────────────────────────────────────────
	--[[
		A vertical stack of square icon buttons down the left edge, each a solid
		primary colour with the label under the glyph.

		It replaces a two-button dock along the bottom. The rail scales: this
		genre accumulates entry points (index, shop, rebirth, rewards, invite)
		and a horizontal dock runs out of room at about four, whereas a column
		just gets longer. It also clears the bottom-centre, which is where the
		money counter wants to be.
	]]
	--[[
		A 2x2 GRID IN THE CORNER, not a vertical strip up the side.

		The strip was centred on the viewport edge, which put its top button
		near the Roblox topbar on short windows -- the same trap the coach card
		fell into. A corner block cannot drift into it, reads as one object
		rather than four, and leaves the middle of the screen to the game.
	]]
	local rail = Theme.frame({
		parent = ctx.gui,
		name = "Rail",
		transparency = 1,
		size = UDim2.fromOffset(152, 232),
		position = UDim2.new(0, 14, 1, -104),
		anchor = Vector2.new(0, 1),
		radius = false,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(72, 72)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = rail

	--[[ The rail carries only what can be opened from anywhere. Anything gated
	     to a place -- the upgrade shop at its counter, the wheel at the wheel --
	     opens from that place's prompt instead, because a rail button leading to
	     a panel where every control is refused is worse than no button. ]]
	local RAIL = {
		{ id = "mines", glyph = "💣", label = "MINES", color = Theme.color.accent },
		{ id = "index", glyph = "📘", label = "INDEX", color = Color3.fromRGB(120, 100, 255) },
		{ id = "collection", glyph = "🎒", label = "BASE", color = Color3.fromRGB(255, 120, 190) },
		{ id = "codes", glyph = "🎁", label = "CODES", color = Color3.fromRGB(64, 200, 120) },
		{ id = "rebirth", glyph = "🔁", label = "REBIRTH", color = Color3.fromRGB(255, 176, 48) },
	}

	for order, entry in ipairs(RAIL) do
		local button = Theme.button({
			parent = rail,
			name = entry.id .. "Button",
			text = "",
			color = entry.color,
			-- sized by the grid; UIGridLayout ignores this but Theme wants it
			size = UDim2.fromOffset(72, 72),
			order = order,
			radius = 14,
		})

		Theme.label({
			parent = button,
			text = entry.glyph,
			textSize = 24,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 30),
			position = UDim2.fromOffset(0, 6),
		})
		local caption = Theme.label({
			parent = button,
			text = entry.label,
			font = Theme.font.black,
			textSize = 11,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 14),
			position = UDim2.fromOffset(0, 38),
		})
		caption.TextStrokeColor3 = Theme.color.line
		caption.TextStrokeTransparency = 0.4

		button.MouseButton1Click:Connect(function()
			local handler = hud["on" .. entry.id:sub(1, 1):upper() .. entry.id:sub(2)]
			if handler then
				handler()
			end
		end)
	end

	-- ── toasts ──────────────────────────────────────────────────────────────

	local toastStack = Theme.frame({
		parent = ctx.gui,
		name = "Toasts",
		transparency = 1,
		size = UDim2.fromOffset(420, 200),
		position = UDim2.new(0.5, 0, 0, hudTop()), -- same topbar clearance
		anchor = Vector2.new(0.5, 0),
		radius = false,
	})
	anchorTop(toastStack, UDim.new(0.5, 0))

	local toastLayout = Theme.list(toastStack, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local TOAST_COLOR = {
		good = Theme.color.good,
		bad = Theme.color.bad,
		info = Theme.color.dim,
		--[[ Above `good`, for the handful of things that happen once a chapter
		     rather than once a minute -- a completed seal is 69 drops of
		     expected play. Gold because that is already the game's colour for
		     the rarest outcome, on the wheel and on the fragment bins. ]]
		great = Theme.color.gold,
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

		-- Pending is the nudge to walk home, so it takes over the income line
		-- entirely when there's something waiting.
		local pending = ctx.state.pending or 0
		if pending >= 1 then
			incomeLabel.Text = string.format("%s  •  %s ready",
				Format.rate(ctx.state.income or 0), Format.money(pending))
			incomeLabel.TextColor3 = Theme.color.gold
		else
			incomeLabel.Text = Format.rate(ctx.state.income or 0)
			incomeLabel.TextColor3 = Theme.color.good
		end
	end

	--[[
		Hide the bottom-centre money while a full panel is open.

		The panels are nearly viewport-height, so the counter sat behind them.
		Raising its ZIndex instead would park a big gold number on top of the
		Mines cash-out button, which is worse. The counter is for when you're
		walking around; an open panel already shows the number that matters.
	]]
	function hud.setMoneyVisible(visible)
		card.Visible = visible
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
