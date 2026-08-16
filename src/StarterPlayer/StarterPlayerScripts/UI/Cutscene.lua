--[[
	Cutscene
	Takes the camera, moves it through a list of shots, and gives it back.

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

	IT IS ALWAYS SKIPPABLE. A tutorial cutscene you cannot dismiss is the thing
	players complain about most, and it lands hardest on exactly the people who
	have seen it before.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Cutscene = {}

local BAR = 0.13 -- letterbox height, as a fraction of the screen
local player = Players.LocalPlayer

local playing = false

--[[ So other UI can stand down while a cutscene owns the screen. ]]
function Cutscene.isPlaying()
	return playing
end

--[[ Where a shot actually puts the camera. `focus` may be a live part, so this
     is resolved at the moment the shot starts rather than when it is written. ]]
local function resolve(shot)
	local focus = shot.focus
	local point = typeof(focus) == "Instance" and focus.Position or focus
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

	local skip = Theme.label({
		parent = root, name = "Skip", text = "",
		font = Theme.font.black, textSize = 13, color = Theme.color.dim,
		size = UDim2.new(0, 260, 0, 20),
		position = UDim2.new(1, -20, 1, -18),
		anchor = Vector2.new(1, 1),
		align = Enum.TextXAlignment.Right,
	})
	skip.ZIndex = 61
	skip.TextStrokeTransparency = 0.5

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

	--[[ shots: { focus = Vector3|BasePart, offset = Vector3, aim = Vector3?,
	              move = seconds, hold = seconds } ]]
	function Cutscene.play(shots, label)
		if playing then
			return false
		end
		playing = true

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		root.Visible = true
		skip.Text = (label or "Skip") .. "  —  press any key"
		bars_to(BAR, 0.4)

		--[[ Frozen, or they wander out of frame while being shown something --
		     and on a touch device a resting thumb does it for them. ]]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
		end

		local skipped = false
		local connection
		connection = UserInputService.InputBegan:Connect(function(_, processed)
			if not processed then
				skipped = true
			end
		end)

		for index, shot in ipairs(shots) do
			if skipped then
				break
			end

			--[[ StreamingEnabled is on, so a camera sent somewhere the player
			     is not will look at unloaded space. Ask for it first; this
			     yields, which is why it happens before the tween rather than
			     during it. ]]
			local point = typeof(shot.focus) == "Instance" and shot.focus.Position
				or shot.focus
			pcall(function()
				player:RequestStreamAroundAsync(point, 4)
			end)

			local target = resolve(shot)
			if index == 1 then
				camera.CFrame = target
			else
				local move = shot.move or 1.6
				TweenService:Create(camera, TweenInfo.new(move,
					Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ CFrame = target }):Play()
				local until_ = os.clock() + move
				while os.clock() < until_ and not skipped do
					task.wait(0.05)
				end
			end

			local hold = os.clock() + (shot.hold or 1.2)
			while os.clock() < hold and not skipped do
				task.wait(0.05)
			end
		end

		connection:Disconnect()
		restore()
		return true
	end

	return Cutscene
end

return Cutscene
