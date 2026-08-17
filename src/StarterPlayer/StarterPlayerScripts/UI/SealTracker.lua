--[[
	SealTracker
	How close you are to the key for the next chapter.

	FRAGMENTS WERE INVISIBLE BEFORE THIS. Plinko has awarded them since it was
	built, the profile has stored them, and the only place they were ever
	mentioned was a toast that scrolled away in four seconds. A currency you
	cannot check the balance of is indistinguishable from no currency, which is
	why the fifth fragment never felt like it was coming.

	PIPS, NOT A PERCENTAGE. There are five, they are countable at a glance, and
	the target is small enough that "two more" is a thought a player can hold.
	A 40%-full bar says the same thing and invites nobody to finish it.

	IT HIDES WHEN THERE IS NOTHING TO SAY, unlike the event card beside it. An
	idle countdown is information; an empty seal row before you have ever flown
	is a promise about content the player has no way to act on yet, sitting
	permanently in the corner.

	One row per island, built from Islands.List, so the second island appears
	here the moment it exists in that table.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)

local Theme = require(script.Parent.Theme)

local SealTracker = {}

local WIDTH = 232 -- matches the event card it sits under
local ROW = 24
local PIP = 13

--[[
	Sits directly under the event card -- and asks the event card where that is,
	rather than recomputing the offset from the topbar inset itself.

	BECAUSE THE INSET IS RACED. GetGuiInset returns 0 until the topbar has been
	measured, and which module reads before that varies run to run: caught once
	with this card 50 pixels INSIDE the event card, and again with the two 66
	apart when the race went the other way. Two independent derivations of the
	same number will disagree exactly when the number is unstable. Reading the
	card above makes the stack correct by construction, whatever the inset does.
]]
local FALLBACK_TOP = 44 + 54 + 8

local function topOffset(gui)
	local event = gui:FindFirstChild("EventCard")
	if event then
		return event.Position.Y.Offset + event.Size.Y.Offset + 8
	end
	return GuiService:GetGuiInset().Y + FALLBACK_TOP
end

function SealTracker.init(ctx)
	local ui = {}

	local card = Theme.frame({
		parent = ctx.gui,
		name = "SealCard",
		color = Theme.color.panel,
		size = UDim2.fromOffset(WIDTH, 40),
		position = UDim2.fromOffset(16, topOffset(ctx.gui)),
		radius = 12,
	})
	card.Visible = false
	Theme.stroke(card, Theme.color.line, 2)
	Theme.padding(card, 10)

	local header = Theme.label({
		parent = card,
		name = "Header",
		text = "SEALS",
		font = Theme.font.black,
		textSize = 11,
		color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 13),
	})
	header.TextXAlignment = Enum.TextXAlignment.Left

	--[[ A row per island, created once. Rendering only ever flips Visible and
	     recolours pips, so a state push never rebuilds instances -- the money
	     tick pushes state every second. ]]
	local rows = {}
	for order, island in ipairs(Islands.List) do
		local row = Theme.frame({
			parent = card,
			name = "Row_" .. island.id,
			transparency = 1,
			size = UDim2.new(1, 0, 0, ROW),
			position = UDim2.fromOffset(0, 15 + (order - 1) * ROW),
			radius = false,
		})

		local name = Theme.label({
			parent = row,
			name = "Name",
			text = island.name:upper(),
			font = Theme.font.black,
			textSize = 13,
			color = island.accent or Theme.color.gold,
			size = UDim2.new(1, -(PIP + 3) * Seals.required(island), 1, 0),
		})
		name.TextXAlignment = Enum.TextXAlignment.Left

		--[[ Right-aligned and laid out right-to-left, so the pip that fills next
		     is always in the same place regardless of how many the island
		     asks for. ]]
		local pipRow = Theme.frame({
			parent = row,
			name = "Pips",
			transparency = 1,
			size = UDim2.fromOffset((PIP + 3) * Seals.required(island), ROW),
			position = UDim2.new(1, 0, 0, 0),
			anchor = Vector2.new(1, 0),
			radius = false,
		})
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 3)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = pipRow

		local pips = {}
		for i = 1, Seals.required(island) do
			local pip = Theme.frame({
				parent = pipRow,
				name = "Pip" .. i,
				color = Theme.color.raised,
				size = UDim2.fromOffset(PIP, PIP),
				radius = 4,
			})
			pip.LayoutOrder = i
			pips[i] = pip
		end

		rows[island.id] = { root = row, pips = pips, island = island, name = name }
	end

	local function render()
		local state = ctx.state
		local shown = 0

		for _, entry in pairs(rows) do
			local island = entry.island
			local held, need, complete = Seals.progress(state, island)
			--[[ Nothing to say until the first fragment lands. Once a seal is
			     held the row STAYS -- it is the record that this chapter is
			     open, and the thing the next island's gate points back at. ]]
			local visible = complete or held > 0
			entry.root.Visible = visible
			if visible then
				shown += 1
				entry.root.Position = UDim2.fromOffset(0, 15 + (shown - 1) * ROW)
				for i, pip in ipairs(entry.pips) do
					pip.BackgroundColor3 = (i <= held)
						and (island.accent or Theme.color.gold)
						or Theme.color.raised
				end
				entry.name.Text = complete
					and (island.name:upper() .. "  ✓")
					or island.name:upper()
			end
		end

		card.Visible = shown > 0
		card.Size = UDim2.fromOffset(WIDTH, 20 + 15 + shown * ROW)
		card.Position = UDim2.fromOffset(16, topOffset(ctx.gui))
	end

	ctx.onState(render)
	render()

	function ui.isVisible()
		return card.Visible
	end

	ui.root = card
	return ui
end

return SealTracker
