--[[
	Flight
	The jetpack: the ascension pose, and what it feels like to fly.

	THE POSE IS CODE, NOT AN ANIMATION. Arms spread, legs apart, rising -- that
	is six joint rotations, so there is no animation to author, nothing to
	upload, and no asset id that can rot. The numbers live in POSE below and can
	be retuned by editing them and pressing play.

	It is written to Motor6D.TRANSFORM, not C0, and rewritten every frame at a
	render priority just after Character. That ordering is the whole trick: the
	animator writes Transform during the Character step, so anything written
	after it wins unconditionally. We never have to stop the idle animation,
	disable the Animate script, or care what the humanoid thinks it is doing --
	whatever it plays is simply overwritten before the frame is drawn. Posing C0
	instead would COMPOSE with the running animation and the pose would drift as
	the idle breathed.

	EVERY CLIENT POSES EVERY FLYER. Joint transforms authored on one client do
	not replicate, so if you posed only your own character you would be the one
	person who couldn't see anyone else ascending. The server instead sets an
	attribute on the character -- attributes DO replicate -- and each client
	poses everyone wearing it, including remote players whose animations arrive
	over the network. One flag, and everybody sees the same thing.

	Flight itself is client-driven, because the client already owns its
	character's physics and routing that through the server would only add
	latency to something that isn't worth cheating at. The server still decides
	WHO may fly; it just doesn't fly them.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Flight = {}

--[[ Set by the server on any character that is currently flying. ]]
local ASCENDING = "Ascending"

--[[
	The pose, as a rotation per joint.

	MEASURED, NOT GUESSED. Every number here was solved against a real R15 rig
	rather than reasoned about, because two of the three assumptions turned out
	to be wrong:

	R15's arms DO NOT hang straight down at rest -- they already sit about 16
	degrees out from the body. So the shoulder angle is measured from that, not
	from vertical, and 66 here puts the arms at roughly 82 degrees, a touch
	below horizontal. The first attempt used 78 on the theory that it was 12
	short of a T-pose; it was actually 4 degrees PAST horizontal, arms angled up
	like a touchdown signal.

	The neck and waist signs were backwards. Positive X tips the head back, into
	the sky, which is what an ascension wants. Negative tucked the chin to the
	chest, which reads as unconscious -- an entirely different scene.

	Shoulders and hips turn about Z, the axis limbs swing out on; head and waist
	about X, the axis they lean back on. Signs mirror per side. Verified by
	solving hand and foot positions in root space: hands land level with the
	shoulders and a shade under, feet spread from 0.5 to 1.2 studs out.
]]
local ARM = math.rad(66)
local LEG = math.rad(20)

local POSE = {
	R15 = {
		RightShoulder = CFrame.Angles(0, 0, ARM),
		LeftShoulder = CFrame.Angles(0, 0, -ARM),
		RightHip = CFrame.Angles(0, 0, LEG),
		LeftHip = CFrame.Angles(0, 0, -LEG),
		Waist = CFrame.Angles(math.rad(6), 0, 0),
		Neck = CFrame.Angles(math.rad(10), 0, 0),
	},
	--[[
		R6 for completeness. Its shoulders are mounted with a quarter turn baked
		into C0, so the swing-out axis lands on X rather than Z, and the joint
		names carry spaces. Untested -- the place ships R15 -- so if R6 is ever
		switched on, expect to flip a sign here rather than to rewrite anything.
	]]
	R6 = {
		["Right Shoulder"] = CFrame.Angles(0, 0, ARM),
		["Left Shoulder"] = CFrame.Angles(0, 0, -ARM),
		["Right Hip"] = CFrame.Angles(0, 0, LEG),
		["Left Hip"] = CFrame.Angles(0, 0, -LEG),
		Neck = CFrame.Angles(math.rad(10), 0, 0),
	},
}

--[[
	Motor6Ds live scattered across the limbs, so finding them means walking the
	whole character. Cached per character rather than searched every frame,
	because this runs inside a render step for every flyer on the server.
]]
local joints = setmetatable({}, { __mode = "k" })

local function jointsFor(character)
	local found = joints[character]
	if found then
		return found
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local pose = humanoid.RigType == Enum.HumanoidRigType.R6 and POSE.R6 or POSE.R15

	found = {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("Motor6D") and pose[item.Name] then
			table.insert(found, { motor = item, cframe = pose[item.Name] })
		end
	end

	-- Don't cache a miss: limbs stream in a frame or two after the character
	-- does, and a cached empty list would leave that player permanently unposed.
	if #found == 0 then
		return nil
	end
	joints[character] = found
	return found
end

local function applyPose(character)
	local set = jointsFor(character)
	if not set then
		return
	end
	for _, entry in ipairs(set) do
		entry.motor.Transform = entry.cframe
	end
end

--[[ Runs for everyone, flying or not, so remote players are posed too. ]]
local function poseEveryone()
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character and character:GetAttribute(ASCENDING) then
			applyPose(character)
		end
	end
end

-- ── the flight rig ──────────────────────────────────────────────────────────

--[[
	A velocity and an orientation constraint, built on takeoff and destroyed on
	landing. Nothing persists between flights: leftover constraints on a
	character are the classic way to end up unable to walk.
]]
local function buildRig(root)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlightVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root

	-- Keeps you upright and facing where you're going. Without it the humanoid
	-- has no state machine to right itself and you fly on your side.
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "FlightOrientation"
	orientation.Attachment0 = attachment
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.RigidityEnabled = false
	orientation.MaxTorque = 90000
	orientation.Responsiveness = 22
	orientation.CFrame = root.CFrame.Rotation
	orientation.Parent = root

	return { attachment = attachment, velocity = velocity, orientation = orientation }
end

function Flight.init(ctx)
	local player = Players.LocalPlayer
	local flying = false
	local rig, takeoffAt

	--[[
		Character+1. The animator writes Transform during the Character step, so
		this is the first opportunity to overwrite it, and being late is the
		point rather than a compromise.
	]]
	RunService:BindToRenderStep("AscensionPose",
		Enum.RenderPriority.Character.Value + 1, poseEveryone)

	local function character()
		return player.Character
	end

	local function stop()
		if not flying then
			return
		end
		flying = false

		if rig then
			rig.velocity:Destroy()
			rig.orientation:Destroy()
			rig.attachment:Destroy()
			rig = nil
		end

		local model = character()
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		--[[
			Clear the pose locally the instant we land, rather than waiting for
			the server's attribute to come back. The round trip is only a few
			frames, but they are the frames where you are visibly falling in a
			star pose, which looks broken.
		]]
		if model then
			model:SetAttribute(ASCENDING, false)
		end
		ctx.remotes.SetFlying:FireServer(false)
	end

	local function start()
		if flying then
			return
		end
		if not ctx.state.jetpack then
			ctx.notify("You need a jetpack. Buy one at the launch pad.", "bad")
			return
		end

		local model = character()
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root) or humanoid.Health <= 0 then
			return
		end

		flying = true
		takeoffAt = os.clock()
		rig = buildRig(root)
		model:SetAttribute(ASCENDING, true) -- locally, so the pose is instant
		ctx.remotes.SetFlying:FireServer(true)
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	function Flight.toggle()
		if flying then
			stop()
		else
			start()
		end
	end

	Flight.isFlying = function()
		return flying
	end

	-- ── per-frame control ───────────────────────────────────────────────────

	RunService.RenderStepped:Connect(function()
		if not flying then
			return
		end

		local model = character()
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root) or humanoid.Health <= 0 then
			stop()
			return
		end

		-- The humanoid drifts out of Physics on its own (landing on geometry,
		-- for one), and once it does it starts walking you around mid-air.
		if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end

		local elapsed = os.clock() - takeoffAt
		local vertical, horizontal

		if elapsed < Config.TakeoffSeconds then
			--[[
				The opening climb is on rails and ignores input. It is the beat
				the pose exists for -- letting someone strafe out of it would
				turn an ascension into a jump.
			]]
			vertical = Config.TakeoffRise
			horizontal = Vector3.zero
		else
			--[[
				MoveDirection rather than reading keys: it is already camera
				-relative and already fed by the touch thumbstick and gamepads,
				so mobile flies without a line of its own.
			]]
			horizontal = humanoid.MoveDirection * Config.FlightSpeed

			local up = UserInputService:IsKeyDown(Enum.KeyCode.Space)
			local down = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			vertical = (up and Config.FlightRise or 0) - (down and Config.FlightRise or 0)
		end

		-- Stop climbing at the ceiling instead of blocking it, so you drift to a
		-- halt rather than hitting an invisible lid.
		if root.Position.Y >= Config.FlightCeiling and vertical > 0 then
			vertical = 0
		end

		rig.velocity.VectorVelocity = Vector3.new(horizontal.X, vertical, horizontal.Z)

		-- Face the direction of travel; hold the last heading when hovering.
		if horizontal.Magnitude > 1 then
			rig.orientation.CFrame = CFrame.lookAt(Vector3.zero,
				Vector3.new(horizontal.X, 0, horizontal.Z).Unit)
		end
	end)

	-- ── input ───────────────────────────────────────────────────────────────

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			Flight.toggle()
		end
	end)

	--[[ Dying mid-flight leaves the rig on a character that is about to be
	     replaced, and the next spawn inherits nothing. ]]
	player.CharacterRemoving:Connect(function()
		flying = false
		rig = nil
	end)

	return Flight
end

return Flight
