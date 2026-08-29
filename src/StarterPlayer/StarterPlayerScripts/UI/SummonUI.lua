--[[
	SummonUI
	"Summon Gold Tralalero Tralala?"

	THE CHOICE IS THE POINT. Racing speed is a player stat and the brainrot is
	fashion, so which one you ride changes nothing about whether you win -- and
	that is exactly why it has to be yours to pick. Choosing your best earner
	for you removes the only decision the ride contains and turns a wardrobe
	into a lookup.

	SO THE PANEL SAYS WHAT IT COSTS, WHICH IS NOTHING. The single most common
	misread of a screen like this is "if I send it away, does it stop earning?"
	-- and the answer is no, because what flies is a copy. That sentence is on
	the panel rather than in a tooltip, because a player deciding is looking
	here.

	Reads the inventory straight off ctx.state, which the server already pushes
	on every change, so there is no second copy of your collection to go stale
	and no request to wait on when the chooser opens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Brainrots = require(Shared.Brainrots)
local Rarity = require(Shared.Rarity)
local Variants = require(Shared.Variants)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local SummonUI = {}

local ROW_HEIGHT = 34

function SummonUI.init(ctx)
	local ui = {}

	local root = Theme.frame({
		parent = ctx.gui,
		name = "SummonPanel",
		color = Theme.color.panel,
		size = UDim2.fromOffset(440, 430),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 18,
	})
	root.Visible = false
	root.ZIndex = 20
	Theme.stroke(root, Color3.fromRGB(255, 88, 104), 3)
	Theme.padding(root, 18)

	Theme.label({
		parent = root, name = "Title", text = "SUMMON A RIDE",
		font = Theme.font.black, textSize = 22, color = Color3.fromRGB(255, 88, 104),
		size = UDim2.new(1, 0, 0, 26),
	})

	local blurb = Theme.label({
		parent = root, name = "Blurb",
		text = "A copy flies you up. The one on your pad keeps earning.",
		font = Theme.font.medium, textSize = 13, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 28),
	})
	blurb.TextWrapped = true

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 1, -160)
	list.Position = UDim2.fromOffset(0, 52)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new()
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local confirm = Theme.button({
		parent = root, name = "Confirm", text = "Pick one",
		color = Theme.color.raised,
		size = UDim2.new(1, 0, 0, 46), position = UDim2.new(0, 0, 1, -104),
		radius = 12,
	})

	local close = Theme.button({
		parent = root, name = "Close", text = "Not now",
		color = Theme.color.raised,
		size = UDim2.new(1, 0, 0, 34), position = UDim2.new(0, 0, 1, -34),
		radius = 10,
	})

	local chosen = nil -- uid
	local rows = {}

	local function render()
		local inventory = ctx.state.inventory or {}

		--[[ Best first, so the one most people want is under the thumb. Sorted
		     by income even though income is irrelevant to racing -- it is the
		     order players already know from the collection panel, and inventing
		     a second ordering for the same list would be worse than a slightly
		     arbitrary one. ]]
		local sorted = table.clone(inventory)
		table.sort(sorted, function(a, b)
			return Economy.powerScore(a.charId, a.variantId)
				> Economy.powerScore(b.charId, b.variantId)
		end)

		for _, row in ipairs(rows) do
			row:Destroy()
		end
		rows = {}

		for index, item in ipairs(sorted) do
			local char = Brainrots.get(item.charId)
			if char then
				local tier = Rarity.get(char.tier)
				local variant = Variants.get(item.variantId)
				local picked = chosen == item.uid

				local row = Theme.frame({
					parent = list, name = "Row" .. index,
					color = picked and Theme.color.accent or Theme.color.raised,
					size = UDim2.new(1, -6, 0, ROW_HEIGHT),
					radius = 8,
				})
				row.LayoutOrder = index
				if picked then
					Theme.stroke(row, Color3.fromRGB(255, 255, 255), 2)
				end

				local name = Theme.label({
					parent = row, name = "Name",
					text = Economy.displayName(item.charId, item.variantId),
					font = Theme.font.medium, textSize = 14,
					color = Color3.fromRGB(255, 255, 255),
					size = UDim2.new(1, -96, 1, 0), position = UDim2.fromOffset(10, 0),
				})
				name.TextXAlignment = Enum.TextXAlignment.Left

				local tag = Theme.label({
					parent = row, name = "Tier", text = char.tier,
					font = Theme.font.black, textSize = 11,
					color = (variant and variant.color) or tier.color,
					size = UDim2.new(0, 86, 1, 0), position = UDim2.new(1, -92, 0, 0),
				})
				tag.TextXAlignment = Enum.TextXAlignment.Right

				local hit = Instance.new("TextButton")
				hit.Size = UDim2.fromScale(1, 1)
				hit.BackgroundTransparency = 1
				hit.Text = ""
				hit.Parent = row
				hit.Activated:Connect(function()
					chosen = item.uid
					render()
				end)

				table.insert(rows, row)
			end
		end

		list.CanvasSize = UDim2.fromOffset(0, #rows * (ROW_HEIGHT + 4))

		--[[ The button IS the question. "Summon Gold Tralalero Tralala?" says
		     what is about to happen more clearly than a confirm dialog ever
		     would, and it is the line the whole feature was described by. ]]
		if chosen then
			local pick
			for _, item in ipairs(inventory) do
				if item.uid == chosen then
					pick = item
				end
			end
			if pick then
				confirm.Text = ("Summon %s?"):format(Economy.displayName(pick.charId, pick.variantId))
				confirm.BackgroundColor3 = Color3.fromRGB(255, 88, 104)
			end
		elseif #rows == 0 then
			confirm.Text = "You have nothing to ride"
			confirm.BackgroundColor3 = Theme.color.raised
		else
			confirm.Text = "Pick one"
			confirm.BackgroundColor3 = Theme.color.raised
		end
	end

	confirm.Activated:Connect(function()
		if not chosen then
			return
		end
		ui.setVisible(false)
		ctx.remotes.SummonMount:InvokeServer(chosen)
	end)

	close.Activated:Connect(function()
		ui.setVisible(false)
	end)

	function ui.setVisible(visible)
		root.Visible = visible
		if visible then
			--[[ Opens on the ride you took last time, so a player with a
			     favourite confirms rather than re-picks. ]]
			chosen = chosen or ctx.state.racer
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

return SummonUI
