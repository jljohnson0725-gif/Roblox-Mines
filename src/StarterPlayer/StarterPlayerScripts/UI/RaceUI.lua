--[[
	RaceUI
	Pick your field, then go and watch.

	THE ODDS ARE ON THE BUTTON. Every field shows its win chance, what it pays,
	and how often it yields a fragment -- before you commit, not after. This is a
	betting game and the whole decision is the trade between those three
	numbers; hiding any of them turns a choice into a guess.

	HARDER IS NOT BETTER, AND THE PANEL SHOULD SAY SO. Every field returns the
	same 80% over time -- what changes is the swing. Without that line the top
	field reads as the "good" one and the selector becomes a difficulty setting
	nobody has a reason to move.

	The numbers come from the server, not from Shared/Racing directly, because
	they depend on the player's upgrade level and the server is the only thing
	that knows it. Same rule as the wheel pulling its stake fresh on open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local RaceUI = {}

local ACCENT = Color3.fromRGB(255, 88, 104)
local ROW = 62

function RaceUI.init(ctx)
	local ui = {}

	local root = Theme.frame({
		parent = ctx.gui,
		name = "RacePanel",
		color = Theme.color.panel,
		size = UDim2.fromOffset(470, 430),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 18,
	})
	root.Visible = false
	root.ZIndex = 20
	Theme.stroke(root, ACCENT, 3)
	Theme.padding(root, 18)

	Theme.label({
		parent = root, name = "Title", text = "THE TRACK",
		font = Theme.font.black, textSize = 22, color = ACCENT,
		size = UDim2.new(1, 0, 0, 26),
	})

	local blurb = Theme.label({
		parent = root, name = "Blurb", text = "",
		font = Theme.font.medium, textSize = 12, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 27),
	})
	blurb.TextWrapped = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top

	local holder = Instance.new("Frame")
	holder.Name = "Fields"
	holder.Size = UDim2.new(1, 0, 1, -110)
	holder.Position = UDim2.fromOffset(0, 60)
	holder.BackgroundTransparency = 1
	holder.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local status = Theme.label({
		parent = root, name = "Status", text = "",
		font = Theme.font.medium, textSize = 13, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 1, -46),
	})

	local close = Theme.button({
		parent = root, name = "Close", text = "Close",
		color = Theme.color.raised,
		size = UDim2.new(1, 0, 0, 34), position = UDim2.new(0, 0, 1, -24),
		radius = 10,
	})

	local rows = {}
	local locked = false

	local function render(data)
		for _, row in ipairs(rows) do
			row:Destroy()
		end
		rows = {}

		blurb.Text = ("%s a race  ·  speed %d/%d  ·  every field pays the same over time — harder just swings further.")
			:format(Format.money(data.stake), data.level, data.maxLevel)

		for index, field in ipairs(data.fields) do
			local row = Theme.frame({
				parent = holder, name = field.id,
				color = Theme.color.raised,
				size = UDim2.new(1, 0, 0, ROW),
				radius = 10,
			})
			row.LayoutOrder = index

			local name = Theme.label({
				parent = row, name = "Name",
				text = ("%s  ·  %d rivals"):format(field.name, field.rivals),
				font = Theme.font.black, textSize = 15,
				color = Color3.fromRGB(255, 255, 255),
				size = UDim2.new(1, -20, 0, 22), position = UDim2.fromOffset(12, 8),
			})
			name.TextXAlignment = Enum.TextXAlignment.Left

			local odds = Theme.label({
				parent = row, name = "Odds",
				text = ("win %.0f%%   pays %.2fx   fragment %.0f%% of wins")
					:format(field.win * 100, field.pay, field.frag * 100),
				font = Theme.font.regular, textSize = 12, color = Theme.color.dim,
				size = UDim2.new(1, -20, 0, 18), position = UDim2.fromOffset(12, 32),
			})
			odds.TextXAlignment = Enum.TextXAlignment.Left

			local hit = Instance.new("TextButton")
			hit.Size = UDim2.fromScale(1, 1)
			hit.BackgroundTransparency = 1
			hit.Text = ""
			hit.Parent = row
			hit.Activated:Connect(function()
				if locked then
					return
				end
				locked = true
				status.Text = "…"
				local result = ctx.remotes.EnterRace:InvokeServer(field.id)
				if result and result.ok then
					--[[ Closed the moment it starts. The race happens in the
					     WORLD, and leaving a panel over it would hide the one
					     thing the player paid to watch. ]]
					ui.setVisible(false)
					ctx.notify(("%s — you're in lane. Watch the track."):format(result.fieldName))
				else
					status.Text = (result and result.err) or "Could not enter."
				end
				locked = false
			end)

			table.insert(rows, row)
		end
	end

	close.Activated:Connect(function()
		ui.setVisible(false)
	end)

	function ui.setVisible(visible)
		root.Visible = visible
		status.Text = ""
		if visible then
			--[[ Pulled fresh rather than cached: the odds move with your upgrade
			     level, and a stale panel would quote numbers the server will not
			     honour. ]]
			local ok, data = pcall(function()
				return ctx.remotes.RaceOdds:InvokeServer()
			end)
			if ok and data then
				render(data)
			end
		end
	end

	function ui.isVisible()
		return root.Visible
	end

	ui.root = root
	return ui
end

return RaceUI
