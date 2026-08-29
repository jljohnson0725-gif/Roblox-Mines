--[[
	Cutscene
	Takes the camera, moves it where it is told, and gives it back.

	IT USED TO DRIVE ITSELF -- a list of shots, a hold time each, skippable with
	any key. That was right for a flyover nobody was talking over. The guided
	tour is not that: the neighbour explains each place and the camera moves
	when the PLAYER presses Next, so pacing belongs to whoever owns the
	dialogue. This is a rig now, not a player: open it, move it, close it.

	SHOTS ARE FOCUS PLUS OFFSET, never a baked CFrame. A shot stored as an
	absolute position is frozen to one spot in a world that is entirely
	generated at runtime -- move the island or restyle the street and the
	cutscene points at empty air with nothing to say why. Stored as "look at
	this thing from here", it follows whatever it was pointed at.

	GIVING THE CAMERA BACK IS THE HARD PART, and it is why the restore is
	guarded three ways: at the end, on skip, and on CharacterAdded. One death
	mid-cutscene would otherwise leave a player staring at a fixed point in
	space with no way out and no idea why -- the single worst failure this
	module can have, and the easiest one to ship.

	IT IS ALWAYS ESCAPABLE. A tutorial you cannot leave is the thing players
	complain about most, and it lands hardest on exactly the people who have
	seen it before -- so `onEscape` is armed while the rig is open and the
	caller decides what leaving means.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Cutscene = {}

local BAR = 0.13 -- letterbox height, as a fraction of the screen
local player = Players.LocalPlayer

local playing = false
local escapeConnection

--[[ So other UI can stand down while a cutscene owns the screen. ]]
function Cutscene.isPlaying()
	return playing
end

--[[ Where a shot actually puts the camera. `focus` may be a live part, so this
     is resolved at the moment the shot starts rather than when it is written. ]]
--[[ A focus may be a Vector3, a BasePart, or a MODEL, and the difference bit:
     Models have no `.Position`, so `focus.Position` threw the moment a stop
     pointed at one -- inside a spawned thread, which meant the tour simply
     stopped with no error on screen and the camera stuck on the previous shot.
     GetPivot covers models; parts keep using Position. ]]
local function focusPoint(focus)
	if typeof(focus) == "Vector3" then
		return focus
	end
	if typeof(focus) == "Instance" then
		if focus:IsA("BasePart") then
			return focus.Position
		end
		if focus:IsA("Model") then
			return focus:GetPivot().Position
		end
	end
	return nil
end

Cutscene.focusPoint = focusPoint

local function resolve(shot)
	local point = focusPoint(shot.focus)
	return CFrame.lookAt(point + shot.offset, point + (shot.aim or Vector3.zero))
end

function Cutscene.init(ctx)
	local gui = ctx.gui

	local root = Instance.new("Frame")
	root.Name = "Cutscene"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 60
	root.Visible = false
	root.Parent = gui

	local bars = {}
	for _, edge in ipairs({ "Top", "Bottom" }) do
		local bar = Instance.new("Frame")
		bar.Name = edge
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, 0)
		bar.Position = edge == "Top" and UDim2.fromScale(0, 0) or UDim2.fromScale(0, 1)
		bar.AnchorPoint = edge == "Top" and Vector2.zero or Vector2.new(0, 1)
		bar.ZIndex = 60
		bar.Active = true -- the bars also swallow clicks meant for the world
		bar.Parent = root
		bars[edge] = bar
	end

	--[[
		A BUTTON, NOT "PRESS ANY KEY".

		This was any unprocessed keypress, which is correct for a flyover nobody
		interacts with and actively hostile for a tour you advance by clicking:
		a click that lands a few pixels off Next -- or during the second the card
		is hidden while the camera flies -- counted as input and abandoned the
		whole thing. Measured exactly that way. Leaving is now a deliberate
		press on a deliberate target.
	]]
	local skip = Theme.button({
		parent = root, name = "Skip", text = "Skip",
		textSize = 13, color = Theme.color.raised, textColor = Theme.color.dim,
		size = UDim2.fromOffset(84, 26),
		position = UDim2.new(1, -20, 1, -18),
		anchor = Vector2.new(1, 1),
		radius = 8,
	})
	skip.ZIndex = 61

	local function bars_to(scale, time)
		for _, bar in pairs(bars) do
			TweenService:Create(bar, TweenInfo.new(time), {
				Size = UDim2.fromScale(1, scale),
			}):Play()
		end
	end

	--[[
		Restore, and mean it. Called at the end, on skip, and from
		CharacterAdded -- the last of which is the one that matters, because a
		death mid-cutscene destroys the humanoid this was freezing and there is
		nothing left to thaw.
	]]
	local function restore()
		playing = false
		root.Visible = false
		bars_to(0, 0.25)
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = ctx.walkSpeed or 25
			humanoid.JumpHeight = 7.2
		end
	end

	Cutscene.restore = restore
	player.CharacterAdded:Connect(function()
		if playing then
			restore()
		end
	end)

	--[[
		OPEN THE RIG. Letterbox in, camera to Scriptable, player frozen.

		`onEscape` fires on any unprocessed keypress. It is a callback rather
		than a built-in skip because only the caller knows what abandoning its
		sequence should do -- the tour has to tell the server it finished and
		put its own dialogue card away.
	]]
	function Cutscene.open(onEscape)
		if playing then
			return false
		end
		playing = true

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		root.Visible = true

		--[[ Hide the tutorial overlay directly rather than asking it to hide
		     itself. A cooperating flag only works if both halves agree about
		     when they run, and this one was still drawing over the letterbox. ]]
		local overlay = gui:FindFirstChild("Tutorial")
		if overlay then
			overlay.Visible = false
		end
		bars_to(BAR, 0.4)

		--[[ Frozen, or they wander out of frame while being shown something --
		     and on a touch device a resting thumb does it for them. ]]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
		end

		if escapeConnection then
			escapeConnection:Disconnect()
		end
		escapeConnection = skip.Activated:Connect(function()
			if playing and onEscape then
				onEscape()
			end
		end)
		return true
	end

	--[[
		Move to a shot and return when it has arrived.

		YIELDS, on purpose: the caller wants to show a line once the camera is
		looking at the thing the line is about. The stream request comes first
		and yields too -- StreamingEnabled means a camera sent somewhere the
		player is not would otherwise arrive at unloaded space.
	]]
	function Cutscene.moveTo(shot, seconds)
		if not playing then
			return
		end
		local camera = workspace.CurrentCamera
		local point = focusPoint(shot.focus)
		if not point then
			return -- nothing to look at; the caller skips this stop
		end
		pcall(function()
			player:RequestStreamAroundAsync(point, 4)
		end)

		local target = resolve(shot)
		if seconds and seconds > 0 then
			TweenService:Create(camera, TweenInfo.new(seconds,
				Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ CFrame = target }):Play()
			local until_ = os.clock() + seconds
			while os.clock() < until_ and playing do
				task.wait(0.05)
			end
		else
			camera.CFrame = target
		end
	end

	function Cutscene.close()
		if escapeConnection then
			escapeConnection:Disconnect()
			escapeConnection = nil
		end
		restore()
	end

	return Cutscene
end

return Cutscene
