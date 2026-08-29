--[[
	Beacon
	A marker in the world on whatever the Coach is currently asking for.

	THE CARD ALONE WAS IGNORABLE. It sits in the bottom-left corner and says
	what to do; a player looking at the middle of the screen never reads it and
	goes off to do their own thing. This is the other half: the objective gets a
	marker floating over it, and when it is off screen an arrow at the edge
	points the way. You can still ignore it -- but not without noticing it.

	IT NEVER DECIDES ANYTHING. The Coach owns "what now"; this asks
	ctx.coach.current() every frame and draws whatever that step's `where`
	returns. So the words on the card and the marker in the world cannot drift
	apart into two different instructions, which is the failure the tutorial
	already hit once when its spotlight and the card disagreed.

	WORLDTOVIEWPORTPOINT IS NOT A VISIBILITY TEST, and this module lives or dies
	on that. It reports a POSITIVE depth for anything merely outside the frame,
	so depth alone says "on screen" for a target behind your shoulder; and for
	anything actually behind the lens the projected point comes back MIRRORED
	through the centre, so an arrow drawn from it points confidently the wrong
	way. Both are handled in `project` below, and both were live bugs in
	UI/Tutorial before they were understood.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local Beacon = {}

--[[ How far in from the edge the off-screen arrow rides. Enough that the whole
     glyph and its label clear the corner rounding at any viewport size. ]]
local EDGE = 74
local LIFT = 7 -- studs above the target, so the marker never covers it
local BOB = 0.28 -- studs of float, so it reads as a marker and not as scenery

--[[
	Where a world point lands on screen, and whether it is really there.

	Returns point, onScreen. The mirroring correction is the whole reason this
	is a function rather than two inline lines: a point behind the camera
	projects to the opposite side of the centre from where it actually is, so
	the vector an edge arrow should point along is the one reflected back.
]]
local function project(camera, position)
	local viewport = camera.ViewportSize
	local centre = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local screen = camera:WorldToViewportPoint(position)
	local point = Vector2.new(screen.X, screen.Y)

	if screen.Z <= 0 then
		-- behind the lens: reflect through the centre to recover the true side
		return centre - (point - centre), false, centre, viewport
	end

	local inside = point.X >= 0 and point.X <= viewport.X
		and point.Y >= 0 and point.Y <= viewport.Y
	return point, inside, centre, viewport
end

function Beacon.init(ctx)
	local ui = {}

	local holder = Instance.new("Frame")
	holder.Name = "Beacon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(180, 64)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = 30
	holder.Visible = false
	holder.Parent = ctx.gui

	--[[ Two glyphs, not one rotated glyph. The on-screen marker points straight
	     down at the thing and should never tilt; the off-screen arrow does
	     nothing but tilt. Sharing one label meant every frame either spent
	     resetting a rotation or fighting one. ]]
	local pin = Theme.label({
		parent = holder,
		name = "Pin",
		text = "▼",
		font = Theme.font.black,
		textSize = 26,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 22),
	})
	pin.TextStrokeColor3 = Theme.color.line
	pin.TextStrokeTransparency = 0.25

	local arrow = Theme.label({
		parent = holder,
		name = "Arrow",
		text = "➤",
		font = Theme.font.black,
		textSize = 30,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 32),
		position = UDim2.fromOffset(0, 16),
	})
	arrow.TextStrokeColor3 = Theme.color.line
	arrow.TextStrokeTransparency = 0.25
	arrow.Visible = false

	local label = Theme.label({
		parent = holder,
		name = "Label",
		text = "",
		font = Theme.font.black,
		textSize = 12,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 4),
	})
	label.TextStrokeColor3 = Theme.color.line
	label.TextStrokeTransparency = 0.3

	local distance = Theme.label({
		parent = holder,
		name = "Distance",
		text = "",
		font = Theme.font.bold,
		textSize = 11,
		color = Theme.color.gold,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 12),
		position = UDim2.fromOffset(0, 50),
	})
	distance.TextStrokeColor3 = Theme.color.line
	distance.TextStrokeTransparency = 0.4

	--[[ Set by ClientMain from the same poll that hides the money counter, so a
	     marker cannot sit on top of an open panel. ]]
	local chromeHidden = false

	local function hide()
		if holder.Visible then
			holder.Visible = false
		end
	end

	local localPlayer = Players.LocalPlayer

	RunService.RenderStepped:Connect(function()
		--[[ Off entirely during the cold open and while the neighbour is
		     talking. This loop is connected before either of those runs, and a
		     gold arrow sliding around the edge of a break-up in the rain would
		     undo the whole opening. Same flags Sky and Tutorial stand down on. ]]
		if localPlayer:GetAttribute("CutscenePlaying")
			or localPlayer:GetAttribute("TalkingToNeighbour") then
			hide()
			return
		end

		if chromeHidden or not ctx.coach then
			hide()
			return
		end

		local step = ctx.coach.current()
		local target = step and step.where and step.where()
		if not target then
			hide()
			return
		end

		local camera = Workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera then
			hide()
			return
		end

		--[[ Bobbing applied in WORLD space, before projection, so the float
		     shrinks with distance the way the marker itself does. Bobbing the
		     screen position instead makes a marker a hundred studs away jitter
		     as hard as one at your feet. ]]
		local lifted = target + Vector3.new(0, LIFT + math.sin(os.clock() * 2.2) * BOB, 0)
		local point, onScreen, centre, viewport = project(camera, lifted)

		holder.Visible = true
		label.Text = step.title or ""

		if root then
			local studs = (Vector3.new(target.X, 0, target.Z)
				- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
			distance.Text = ("%dm"):format(math.floor(studs))
		else
			distance.Text = ""
		end

		if onScreen then
			pin.Visible = true
			arrow.Visible = false
			holder.Position = UDim2.fromOffset(point.X, point.Y)
			return
		end

		--[[ Off screen: ride the edge, pointing along the direction the target
		     actually lies in. The vector is taken from the CORRECTED point, so a
		     target behind the camera pulls the arrow backwards rather than
		     sending it to the opposite edge. ]]
		pin.Visible = false
		arrow.Visible = true

		local offset = point - centre
		if offset.Magnitude < 1 then
			offset = Vector2.new(0, -1)
		end
		local direction = offset.Unit

		--[[ Clamped to the rectangle, not to a circle: a circle leaves the arrow
		     floating in from the corners on a wide window, where the thing it is
		     pointing at is off the SIDE.

		     THE FLOOR OF 8 IS NOT PARANOIA. ViewportSize is (1, 1) for the first
		     frames before the camera is sized, and RenderStepped is connected
		     long before that settles. Half of one, minus a 74-pixel inset, is
		     -73.5; dividing that by a near-zero direction component gave a scale
		     of -735000 and threw the arrow a hundred thousand pixels off screen,
		     pointing backwards. Observed, not imagined. ]]
		local halfX = math.max(viewport.X / 2 - EDGE, 8)
		local halfY = math.max(viewport.Y / 2 - EDGE, 8)
		local scale = math.min(
			halfX / math.max(math.abs(direction.X), 1e-4),
			halfY / math.max(math.abs(direction.Y), 1e-4))
		local edgePoint = centre + direction * scale

		holder.Position = UDim2.fromOffset(edgePoint.X, edgePoint.Y)
		-- the glyph points right at rotation 0, so this is a straight bearing
		arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
	end)

	function ui.setChromeHidden(hidden)
		chromeHidden = hidden and true or false
	end

	ui.root = holder
	return ui
end

return Beacon
