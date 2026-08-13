--[[
	Theme
	Palette plus the small constructors that keep the UI modules readable.
	Everything in this game's interface is built in code -- there is no GUI to
	hand-assemble in Studio, which is the whole point of the paste-in workflow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Sounds)

local Theme = {}

Theme.color = {
	bg = Color3.fromRGB(18, 19, 26),
	panel = Color3.fromRGB(26, 28, 38),
	raised = Color3.fromRGB(35, 38, 50),
	tile = Color3.fromRGB(48, 52, 68),
	tileHover = Color3.fromRGB(62, 68, 88),
	line = Color3.fromRGB(52, 56, 72),

	text = Color3.fromRGB(238, 240, 248),
	dim = Color3.fromRGB(146, 152, 170),
	faint = Color3.fromRGB(96, 102, 120),

	good = Color3.fromRGB(88, 214, 132),
	bad = Color3.fromRGB(240, 84, 96),
	gold = Color3.fromRGB(255, 190, 60),
	accent = Color3.fromRGB(120, 132, 255),
}

Theme.font = {
	bold = Enum.Font.GothamBold,
	medium = Enum.Font.GothamMedium,
	regular = Enum.Font.Gotham,
	black = Enum.Font.GothamBlack,
}

-- ── constructors ────────────────────────────────────────────────────────────

function Theme.corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.color.line
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

function Theme.padding(parent, all, extra)
	local pad = Instance.new("UIPadding")
	local value = UDim.new(0, all or 8)
	pad.PaddingTop = value
	pad.PaddingBottom = value
	pad.PaddingLeft = value
	pad.PaddingRight = value
	if extra then
		for key, offset in pairs(extra) do
			pad[key] = UDim.new(0, offset)
		end
	end
	pad.Parent = parent
	return pad
end

function Theme.list(parent, spacing, direction)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing or 6)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function Theme.frame(props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = props.color or Theme.color.panel
	frame.BackgroundTransparency = props.transparency or 0
	frame.BorderSizePixel = 0
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.Position = props.position or UDim2.fromOffset(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.new(0, 0)
	frame.LayoutOrder = props.order or 0
	frame.Name = props.name or "Frame"
	if props.radius ~= false then
		Theme.corner(frame, props.radius or 8)
	end
	frame.Parent = props.parent
	return frame
end

function Theme.label(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.size or UDim2.fromScale(1, 1)
	label.Position = props.position or UDim2.fromOffset(0, 0)
	label.AnchorPoint = props.anchor or Vector2.new(0, 0)
	label.Font = props.font or Theme.font.medium
	label.TextSize = props.textSize or 14
	label.TextColor3 = props.color or Theme.color.text
	label.Text = props.text or ""
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextYAlignment = props.valign or Enum.TextYAlignment.Center
	label.TextScaled = props.scaled or false
	label.RichText = props.rich or false
	label.LayoutOrder = props.order or 0
	label.Name = props.name or "Label"
	label.Parent = props.parent
	return label
end

function Theme.button(props)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = props.color or Theme.color.raised
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Size = props.size or UDim2.fromScale(1, 1)
	button.Position = props.position or UDim2.fromOffset(0, 0)
	button.AnchorPoint = props.anchor or Vector2.new(0, 0)
	button.Font = props.font or Theme.font.bold
	button.TextSize = props.textSize or 14
	button.TextColor3 = props.textColor or Theme.color.text
	button.Text = props.text or ""
	button.LayoutOrder = props.order or 0
	button.Name = props.name or "Button"
	button.AutoLocalize = false
	Theme.corner(button, props.radius or 8)
	button.Parent = props.parent

	-- hover feedback without AutoButtonColor's washed-out tint
	local base = button.BackgroundColor3
	local hover = props.hover or base:Lerp(Color3.new(1, 1, 1), 0.12)
	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = hover
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = button:GetAttribute("BaseColor") or base
	end)
	button:SetAttribute("BaseColor", base)

	-- Every button clicks, unless it has its own voice. Mines tiles pass
	-- silent = true because they play a pitched reveal instead.
	if not props.silent then
		button.MouseButton1Click:Connect(function()
			if button.Active then
				Sounds.play("uiClick")
			end
		end)
	end

	return button
end

--[[ Recolour a button built above, keeping hover in sync. ]]
function Theme.recolor(button, color)
	button.BackgroundColor3 = color
	button:SetAttribute("BaseColor", color)
end

function Theme.scroller(props)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = props.transparency or 1
	scroll.BackgroundColor3 = props.color or Theme.color.bg
	scroll.BorderSizePixel = 0
	scroll.Size = props.size or UDim2.fromScale(1, 1)
	scroll.Position = props.position or UDim2.fromOffset(0, 0)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.color.faint
	scroll.LayoutOrder = props.order or 0
	scroll.Name = props.name or "Scroller"
	scroll.Parent = props.parent
	return scroll
end

return Theme
