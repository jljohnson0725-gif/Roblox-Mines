--[[
	Tutorial
	The first two steps, insisted on rather than suggested.

	IT DOES NOT KNOW ITS OWN PROGRESS. Every step asks the same question Coach
	asks -- is this true of the player yet? -- so there is no cursor to desync,
	nothing to replay, and a rejoin halfway through resumes exactly where it
	was. A scripted sequence would have to remember which line it was on and
	would be wrong the moment anything happened out of order.

	THE SPOTLIGHT IS FOUR RECTANGLES, NOT A MASK. Roblox has no cheap way to cut
	a hole in an overlay, and it does not need one: four dim frames arranged
	around the target leave it lit while covering everything else. Those four
	are also the gate -- Active swallows every click that lands on them -- so
	the thing you can see and the thing you can press are the same object, and
	they cannot disagree.

	ONLY TWO STEPS ARE GATED. Opening Mines and cashing out are the two nobody
	guesses; by the time a brainrot is banked the loop has explained itself, and
	blocking someone from wandering off after that is where a guided tutorial
	turns into paperwork. Coach picks up the rest as a card that suggests and
	never blocks.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Cutscene = require(script.Parent.Cutscene)

local Tutorial = {}

local DIM = 0.55 -- how far down everything outside the hole goes
local PAD = 10 -- breathing room around the highlighted control

--[[
	Ordered. Each step names what to light up and what has to become true.

	`target` is resolved every frame rather than once: the Mines panel does not
	exist until it is opened, and a rail button can be rebuilt.
]]
local STEPS = {
	{
		key = "meet",
		--[[ The only step that points at something in the WORLD rather than at a
		     button. He is the first thing the game asks for now: the cold open
		     ends on a man alone, and the first instruction being "go and talk to
		     someone" is worth more than "press M". ]]
		world = function()
			local ok, friend = pcall(function()
				return require(script.Parent.Friend).npc
			end)
			return ok and friend or nil
		end,
		find = function() return nil end,
		title = "Talk to your neighbour",
		body = "He is outside your front door. Walk over and press E.",
		done = function()
			return Players.LocalPlayer:GetAttribute("MetNeighbour") == true
		end,
	},
	{
		key = "open",
		find = function(gui)
			return gui:FindFirstChild("minesButton", true)
		end,
		title = "Open Mines",
		body = "Press M, or click here.",
		done = function(gui, state)
			local panel = gui:FindFirstChild("MinesPanel", true)
			return (panel and panel.Visible) or next(state.index or {}) ~= nil
		end,
	},
	{
		key = "bank",
		find = function(gui)
			return gui:FindFirstChild("MinesPanel", true)
		end,
		title = "Cash out to keep it",
		body = "Reveal tiles for a bigger payout, then CASH OUT. Hit a mine and you lose everything.",
		--[[ The index only records a brainrot once it is SECURED, so this is
		     true exactly when the player has banked one -- which is the thing
		     the step is actually teaching. ]]
		done = function(_, state)
			return next(state.index or {}) ~= nil
		end,
	},
}

--[[
	The opening shots, against anchors the world builds itself around rather
	than coordinates typed in by hand: the Mines console at the west end of the
	street, and the player. Move the landmark and the cutscene follows it.
]]
local function opening(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	--[[ The model's pivot, not a named part inside it. The first version looked
	     for a "Console" child, which MinesLandmark does not build -- it makes
	     Seg, Shaft and SignAnchor -- so the lookup returned nil and quietly
	     dropped the only shot the cutscene exists for. A pivot cannot be
	     misspelled. ]]
	--[[ The BASE of the landmark, not its pivot. The pivot is the centre of a
	     34-stud-tall structure and sits 46 studs up, so aiming above it looked
	     clean over the top of the thing it was supposed to show -- and framed
	     the building standing behind it instead. GetBoundingBox gives the
	     height to subtract; a pivot on its own never tells you how tall
	     something is. ]]
	local mines = workspace:FindFirstChild("MinesLandmark")
	local landmark
	if mines then
		local centre, size = mines:GetBoundingBox()
		landmark = centre.Position - Vector3.new(0, size.Y / 2, 0)
	end
	local here = root and root.Position or Vector3.new(0, 6, 0)

	local shots = {
		{ focus = here, offset = Vector3.new(-30, 46, 52), aim = Vector3.new(0, 6, 0),
			hold = 1.4 },
	}
	if landmark then
		table.insert(shots, { focus = landmark, offset = Vector3.new(26, 14, 40),
			aim = Vector3.new(0, 14, 0), move = 2.8, hold = 1.7 })
	end
	table.insert(shots, { focus = here, offset = Vector3.new(0, 7, 15),
		aim = Vector3.new(0, 4, 0), move = 1.8, hold = 0.6 })
	return shots
end

function Tutorial.init(ctx)
	local player = Players.LocalPlayer
	local gui = ctx.gui
	Cutscene.init(ctx)

	--[[ Once per session, and only for someone who has not finished the loop.
	     A module-local flag rather than a state field: replaying it because a
	     Sync arrived is worse than never showing it. ]]
	local opened = false
	task.spawn(function()
		repeat task.wait(0.3) until ctx.state.onboarding
		if ctx.state.onboarding.done or opened then
			return
		end
		opened = true
		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart")

		--[[
			AFTER THE COLD OPEN, not on top of it.

			This used to fire 1.2 seconds after the character loaded, which is
			the same moment the intro starts. Two cutscenes then fought over one
			camera -- and because this one sets Scriptable, the intro captured
			THAT as the state to restore, handed it back at the end, and left the
			player looking at empty sky unable to move.

			Bounded, so a cold open that never finishes cannot cost the player
			this as well.
		]]
		local deadline = os.clock() + 45
		while os.clock() < deadline do
			local busy = player:GetAttribute("CutscenePlaying")
				or player.PlayerGui:FindFirstChild("IntroEpilogue")
				or player.PlayerGui:FindFirstChild("ColdOpenCover")
			if not busy then
				break
			end
			task.wait(0.25)
		end
		task.wait(1.2)
		Cutscene.play(opening(character), "Skip intro")
	end)

	local root = Instance.new("Frame")
	root.Name = "Tutorial"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 40
	root.Visible = false
	root.Parent = gui

	--[[ The four shades. Active is what makes them a gate as well as a dim --
	     a click landing on any of them stops there instead of reaching the
	     control underneath. ]]
	local shades = {}
	for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
		local shade = Instance.new("Frame")
		shade.Name = side
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 1 - DIM
		shade.BorderSizePixel = 0
		shade.Active = true
		shade.ZIndex = 40
		shade.Parent = root
		shades[side] = shade
	end

	-- a ring round the hole, so the eye lands on it rather than on the dark
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.ZIndex = 41
	ring.Parent = root
	Theme.stroke(ring, Theme.color.gold, 3)
	Instance.new("UICorner").Parent = ring

	local card = Theme.frame({
		parent = root,
		name = "Card",
		color = Theme.color.panel,
		size = UDim2.fromOffset(300, 92),
		radius = 14,
	})
	card.ZIndex = 42
	Theme.stroke(card, Theme.color.gold, 2)
	Theme.padding(card, 13)

	local eyebrow = Theme.label({
		parent = card, name = "Eyebrow", text = "STEP 1 OF 2",
		font = Theme.font.black, textSize = 10, color = Theme.color.gold,
		size = UDim2.new(1, 0, 0, 12),
	})
	eyebrow.ZIndex = 43
	local title = Theme.label({
		parent = card, name = "Title", text = "",
		font = Theme.font.black, textSize = 16,
		size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 15),
	})
	title.ZIndex = 43
	local body = Theme.label({
		parent = card, name = "Body", text = "",
		font = Theme.font.regular, textSize = 12, color = Theme.color.dim,
		size = UDim2.new(1, 0, 0, 42), position = UDim2.fromOffset(0, 37),
	})
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 43

	local shown
	--[[ Only on change. Calling every frame would re-render Coach sixty times a
	     second to tell it the same thing. ]]
	local gating = false
	local function setGating(on)
		if on ~= gating then
			gating = on
			if ctx.coach then
				ctx.coach.suppress(on)
			end
		end
	end

	--[[
		Lay the four shades around a rect.

		ABSOLUTEPOSITION IS NOT THIS GUI'S SPACE. It is measured from the true
		top-left of the viewport, while these frames are children of a ScreenGui
		with IgnoreGuiInset set, whose own origin sits at (0, -58) -- above the
		screen. Feeding one straight into the other put every shade and ring 58
		pixels high, which is precisely how far off the first build looked.
		Subtracting the gui's own origin converts one to the other.
	]]
	--[[
		The dim and the ring, together, because they only make sense together.

		A world target that is off screen has NO rect worth surrounding, and
		laying the four shades around one anyway dims the entire screen -- which
		is what happens while the player is walking over to the neighbour, since
		WorldToViewportPoint reports a positive depth for anything merely outside
		the frame rather than behind the camera. So off screen keeps the card and
		drops the highlight entirely.
	]]
	local function highlight(on)
		ring.Visible = on
		for _, shade in pairs(shades) do
			shade.BackgroundTransparency = on and (1 - DIM) or 1
			shade.Active = on
		end
	end

	local function frame(rect)
		local view = gui.AbsoluteSize
		local origin = gui.AbsolutePosition
		local x = rect.Position.X - origin.X - PAD
		local y = rect.Position.Y - origin.Y - PAD
		local w, h = rect.Size.X + PAD * 2, rect.Size.Y + PAD * 2

		shades.Top.Position = UDim2.fromOffset(0, 0)
		shades.Top.Size = UDim2.fromOffset(view.X, math.max(y, 0))
		shades.Bottom.Position = UDim2.fromOffset(0, y + h)
		shades.Bottom.Size = UDim2.fromOffset(view.X, math.max(view.Y - (y + h), 0))
		shades.Left.Position = UDim2.fromOffset(0, y)
		shades.Left.Size = UDim2.fromOffset(math.max(x, 0), h)
		shades.Right.Position = UDim2.fromOffset(x + w, y)
		shades.Right.Size = UDim2.fromOffset(math.max(view.X - (x + w), 0), h)

		ring.Position = UDim2.fromOffset(x, y)
		ring.Size = UDim2.fromOffset(w, h)

		-- card goes under the hole, or above it when there is no room below
		local below = y + h + 14
		local cardY = (below + 92 < view.Y) and below or math.max(y - 106, 8)
		card.Position = UDim2.fromOffset(
			math.clamp(x + w / 2 - 150, 8, math.max(view.X - 308, 8)), cardY)
	end

	RunService.RenderStepped:Connect(function()
		local state = ctx.state

		--[[
			Stand down while a cutscene is running. Two overlays owning the
			screen at once is bad on its own -- the spotlight drew over the
			letterbox and told the player to press a button they could not see
			-- but the real damage was the gate: the shades swallow input, and
			the cutscene treats input as a skip, so the intro was being
			dismissed by its own tutorial before the second shot arrived.
		]]
		if Cutscene.isPlaying() then
			root.Visible = false
			setGating(false)
			return
		end

		--[[ Never for a returning player. `done` latches server-side once the
		     whole loop has worked once, so this cannot reappear. ]]
		if state.onboarding and state.onboarding.done then
			root.Visible = false
			setGating(false)
			return
		end

		--[[ Out of the way entirely while he is talking. Hiding the root takes
		     the ring, all four shades and the tutorial card with it, which is
		     the whole overlay -- the dialogue should have the screen to itself
		     for as long as it is up. ]]
		if Players.LocalPlayer:GetAttribute("TalkingToNeighbour") then
			root.Visible = false
			setGating(false)
			return
		end

		local step
		for index, candidate in ipairs(STEPS) do
			if not candidate.done(gui, state) then
				step = candidate
				step.index = index
				break
			end
		end

		if not step then
			root.Visible = false
			setGating(false)
			return
		end

		--[[
			A step points at a BUTTON or at something in the world.

			World steps project the model to the viewport and frame that, so the
			highlight lands on the neighbour himself. Behind the camera or off
			screen he reports a negative depth, which would otherwise draw a box
			in the wrong place with total confidence.
		]]
		local rect
		if step.world then
			local model = step.world()
			if model and model.Parent then
				local cam = workspace.CurrentCamera
				local sp = cam:WorldToViewportPoint(model:GetPivot().Position)
				local view = cam.ViewportSize
				--[[ IN FRONT is not the same as IN FRAME. Depth alone still
				     reports a point twenty thousand pixels off to the right as
				     visible, so the bounds are checked too. ]]
				if sp.Z > 0 and sp.X > 0 and sp.X < view.X
					and sp.Y > 0 and sp.Y < view.Y then
					local half = 62
					rect = {
						Position = Vector2.new(sp.X - half, sp.Y - half * 1.6),
						Size = Vector2.new(half * 2, half * 3.2),
					}
				end
			end
			if not rect then
				--[[ Not on screen: keep the card, drop the highlight. The
				     instruction is "go and find him", so hiding the card would
				     leave the player with nothing to go on -- but dimming the
				     screen around a hole they cannot see is worse than no dim. ]]
				root.Visible = true
				setGating(false)
				highlight(false)
				if shown ~= step.key then
					shown = step.key
					eyebrow.Text = ("STEP %d OF %d"):format(step.index, #STEPS)
					title.Text = step.title
					body.Text = step.body
				end
				return
			end
		else
			local target = step.find(gui)
			--[[ No target means the thing to point at is not on screen yet --
			     the panel between opening and rendering, say. Hide rather than
			     frame a rect at the origin, which is where a missing GuiObject
			     reports. ]]
			if not target or target.AbsoluteSize.X < 1 then
				root.Visible = false
				setGating(false)
				return
			end
			rect = { Position = target.AbsolutePosition, Size = target.AbsoluteSize }
		end

		root.Visible = true
		setGating(not step.world)
		highlight(true)
		frame(rect)

		if shown ~= step.key then
			shown = step.key
			eyebrow.Text = ("STEP %d OF %d"):format(step.index, #STEPS)
			title.Text = step.title
			body.Text = step.body
			card.Size = UDim2.fromOffset(300, 92)
			TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Back,
				Enum.EasingDirection.Out), { Size = UDim2.fromOffset(308, 96) }):Play()
			task.delay(0.22, function()
				TweenService:Create(card, TweenInfo.new(0.15),
					{ Size = UDim2.fromOffset(300, 92) }):Play()
			end)
		end
	end)

	return Tutorial
end

return Tutorial
