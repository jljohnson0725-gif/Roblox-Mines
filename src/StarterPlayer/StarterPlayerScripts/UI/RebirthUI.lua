--[[
	RebirthUI
	The one screen in this game that asks you to destroy something.

	SO IT SAYS WHAT IT TAKES, IN FULL, BEFORE ASKING. Every other panel here
	sells a purchase; this one has to be honest about a loss, and the loss is
	the point rather than a footnote. Two columns, kept and lost side by side,
	because a player deciding this is comparing them and should not have to
	hold one of them in their head.

	AND IT CONFIRMS TWICE. The button arms first and commits second, with the
	armed state saying exactly what is about to happen. A single click that
	deletes a base is the kind of thing people do by accident once and never
	forgive -- and unlike everything else in the game, there is no undo and no
	way for support to give it back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Rebirth = require(Shared.Rebirth)

local Theme = require(script.Parent.Theme)

local RebirthUI = {}

local KEPT = {
	"Your Index — every brainrot ever secured",
	"The Plinko ball, and any island saddles",
	"Redeemed codes and lifetime stats",
}

local LOST = {
	"All money, back to " .. Format.money(Config.StartingMoney),
	"Every upgrade level",
	"Every brainrot on a pad, and in storage",
}

function RebirthUI.init(ctx)
	local ui = {}

	local root = Theme.frame({
		parent = ctx.gui,
		name = "RebirthPanel",
		color = Theme.color.panel,
		-- 412, not 400: the apartment line below NEXT added twelve studs of
		-- content and the Close button fell off the bottom edge.
		size = UDim2.fromOffset(520, 412),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 18,
	})
	root.Visible = false
	root.ZIndex = 20
	Theme.stroke(root, Theme.color.gold, 3)
	Theme.padding(root, 20)

	Theme.label({
		parent = root, name = "Title", text = "REBIRTH",
		font = Theme.font.black, textSize = 26, color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 30),
	})

	local summary = Theme.label({
		parent = root, name = "Summary", text = "",
		font = Theme.font.medium, textSize = 14, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 44), position = UDim2.fromOffset(0, 34),
	})
	summary.TextWrapped = true
	summary.TextYAlignment = Enum.TextYAlignment.Top

	--[[ Kept on the left, lost on the right. Losses on the right because that
	     is the side the eye lands on last, and it should be the side you are
	     still looking at when you decide. ]]
	local function column(x, heading, lines, color)
		local head = Theme.label({
			parent = root, name = heading, text = heading,
			font = Theme.font.black, textSize = 12, color = color,
			size = UDim2.new(0.5, -10, 0, 16),
			position = UDim2.new(0, x, 0, 88),
		})
		head.TextXAlignment = Enum.TextXAlignment.Left
		for i, text in ipairs(lines) do
			local item = Theme.label({
				parent = root, name = heading .. i, text = "•  " .. text,
				font = Theme.font.regular, textSize = 12, color = Theme.color.dim,
				size = UDim2.new(0.5, -10, 0, 30),
				position = UDim2.new(0, x, 0, 108 + (i - 1) * 32),
			})
			item.TextXAlignment = Enum.TextXAlignment.Left
			item.TextWrapped = true
			item.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	column(0, "YOU KEEP", KEPT, Color3.fromRGB(96, 226, 130))
	column(266, "YOU LOSE", LOST, Color3.fromRGB(236, 96, 110))

	local gain = Theme.label({
		parent = root, name = "Gain", text = "",
		font = Theme.font.black, textSize = 15, color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 218),
	})

	--[[ What the apartment becomes. The other two rewards are numbers a player
	     has to take on trust; this one they can walk into, so it is worth a line
	     of its own -- and stating it BEFORE the purchase is the difference
	     between a reward and a surprise. ]]
	local tierLine = Theme.label({
		parent = root, name = "Tier", text = "",
		font = Theme.font.medium, textSize = 13, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 240),
	})

	local confirm = Theme.button({
		parent = root, name = "Confirm", text = "",
		color = Theme.color.accent,
		size = UDim2.new(1, 0, 0, 52), position = UDim2.fromOffset(0, 264),
		radius = 12,
	})

	local status = Theme.label({
		parent = root, name = "Status", text = "",
		font = Theme.font.medium, textSize = 13, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 324),
	})

	local close = Theme.button({
		parent = root, name = "Close", text = "Close",
		color = Theme.color.raised,
		size = UDim2.new(1, 0, 0, 34), position = UDim2.fromOffset(0, 348),
		radius = 10,
	})

	--[[ Armed is cleared on every open, every refresh and every close, so a
	     panel can never be sitting armed from a decision made minutes ago. ]]
	local armed = false

	local function render()
		local state = ctx.state
		local level = state.rebirths or 0
		local cost = Rebirth.cost(level)
		local canAfford = (state.money or 0) >= cost
		local hasPads = (state.slots or 0) >= Config.MaxSlots

		--[[ Name the tiers this rebirth has already opened. "+1.05 drop depth"
		     is the honest number and it means nothing to anyone; the tiers are
		     what the player is actually buying, and until now the only place
		     either could be seen was the Mines odds panel. ]]
		local opened = Rebirth.opened(level)
		summary.Text = (#opened > 0)
			and ("Rebirth %d. %s drop for you now, and you start with %d pads.")
				:format(level, table.concat(opened, ", "), Rebirth.startPads(level))
			or ("Rebirth %d. Your luck is +%.2f drop depth, and you start with %d pads.")
				:format(level, Rebirth.luck(level), Rebirth.startPads(level))

		--[[ The headline of the next one, when it opens a tier. A step is worth
		     naming; the slope underneath it is not. ]]
		local opening = Rebirth.opensAt(level)
		gain.Text = opening
			and ("NEXT:  %s START DROPPING  ·  %d starting pads")
				:format(Rebirth.plural(opening):upper(), Rebirth.startPads(level + 1))
			or ("NEXT:  luck +%.2f  ·  %d starting pads")
				:format(Rebirth.luck(level + 1), Rebirth.startPads(level + 1))

		local here = Rebirth.tier(level)
		local nextTier, away = Rebirth.nextTier(level)
		if not nextTier then
			tierLine.Text = ("Apartment: %s — the top floor."):format(here.name)
		elseif away <= 1 then
			tierLine.Text = ("Apartment: %s  →  %s"):format(here.name, nextTier.name)
		else
			tierLine.Text = ("Apartment: %s  →  %s in %d more")
				:format(here.name, nextTier.name, away)
		end

		if not hasPads then
			confirm.Text = "Own all " .. Config.MaxSlots .. " pads first"
			confirm.BackgroundColor3 = Theme.color.raised
		elseif not canAfford then
			confirm.Text = "Need " .. Format.money(cost)
			confirm.BackgroundColor3 = Theme.color.raised
		elseif armed then
			confirm.Text = "TAP AGAIN TO GIVE UP THIS RUN"
			confirm.BackgroundColor3 = Color3.fromRGB(214, 62, 76)
		else
			confirm.Text = "REBIRTH  ·  " .. Format.money(cost)
			confirm.BackgroundColor3 = Theme.color.accent
		end
	end

	confirm.Activated:Connect(function()
		local state = ctx.state
		local cost = Rebirth.cost(state.rebirths or 0)
		if (state.slots or 0) < Config.MaxSlots or (state.money or 0) < cost then
			return
		end
		if not armed then
			armed = true
			status.Text = "This cannot be undone."
			render()
			return
		end

		armed = false
		confirm.Text = "…"
		local result = ctx.remotes.DoRebirth:InvokeServer()
		if result and result.ok then
			status.Text = ""
			ui.setVisible(false)
		else
			status.Text = (result and result.err) or "Could not rebirth."
			render()
		end
	end)

	close.Activated:Connect(function()
		ui.setVisible(false)
	end)

	function ui.setVisible(visible)
		armed = false
		status.Text = ""
		root.Visible = visible
		if visible then
			render()
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ctx.onState(function()
		if root.Visible then
			render()
		end
	end)

	ui.root = root
	return ui
end

return RebirthUI
