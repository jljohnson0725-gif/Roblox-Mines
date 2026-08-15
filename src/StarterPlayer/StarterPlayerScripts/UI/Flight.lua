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
	Drift, so the pose is held rather than frozen.

	A body pinned to six exact angles reads as a mannequin no matter how good
	the angles are -- the eye notices the absence of motion faster than it
	notices the pose. These are tiny: three degrees at the shoulders, under two
	at the hips, on slow periods that don't share a common multiple, so the
	limbs never visibly resynchronise into a pulse.

	Left amplitudes are NEGATIVE because the left joints are mirrored. Adding
	the same delta to both sides would raise one arm while lowering the other,
	which is a flap; negating it makes both rise together, which is a breath.
]]
local SWAY = {
	RightShoulder = { amp = math.rad(3.1), speed = 2.1 },
	LeftShoulder = { amp = math.rad(-3.1), speed = 2.1 },
	RightHip = { amp = math.rad(1.5), speed = 1.43, phase = 0.7 },
	LeftHip = { amp = math.rad(-1.5), speed = 1.43, phase = 0.7 },
}
SWAY["Right Shoulder"] = SWAY.RightShoulder
SWAY["Left Shoulder"] = SWAY.LeftShoulder
SWAY["Right Hip"] = SWAY.RightHip
SWAY["Left Hip"] = SWAY.LeftHip

--[[ How fast the pose takes over and lets go. Fast in, because takeoff is a
     burst; slower out, because landing should settle rather than snap. ]]
local BLEND_IN = 5.0 -- per second, so ~0.2s to full
local BLEND_OUT = 3.4

--[[
	TWO RIG GENERATIONS, and the joint class is the entire difference.

	The classic rig joins limbs with Motor6D, which is KINEMATIC: the animator
	writes Transform during the render step, so the last write before the frame
	is drawn wins. Roblox's newer physical rig joins them with
	AnimationConstraint backed by a BallSocketConstraint, which is FORCE-DRIVEN:
	Transform is a target the solver moves the limb toward during the physics
	step.

	So they need different phases, and choosing wrong fails silently rather than
	erroring. Writing an AnimationConstraint at render time does nothing
	whatsoever -- physics runs afterwards and overwrites it -- which is exactly
	how this first shipped: a live character with zero Motor6Ds on it and a pose
	being applied to nothing at all. Measured on a real character: at
	PreSimulation the hand moves from x +1.35 to +3.35, at render time and at
	Heartbeat it does not move.

	Both classes expose .Transform and both use the same joint NAMES, so the
	pose table above is shared. Only the phase and the blending differ, and
	supporting both is worth it while avatars exist on either rig.
]]
local joints = setmetatable({}, { __mode = "k" })

--[[ How much of the pose each character is currently wearing, 0 to 1. Weak
     keys: a character that leaves the world takes its entry with it. ]]
local weights = setmetatable({}, { __mode = "k" })

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
		local physical = item:IsA("AnimationConstraint")
		if (physical or item:IsA("Motor6D")) and pose[item.Name] then
			table.insert(found, {
				joint = item,
				physical = physical,
				cframe = pose[item.Name],
				sway = SWAY[item.Name],
			})
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

local function applyPose(character, weight, clock, physical)
	local set = jointsFor(character)
	if not set then
		return
	end
	for _, entry in ipairs(set) do
		if entry.physical == physical then
			local target = entry.cframe
			if entry.sway then
				local s = entry.sway
				target = target * CFrame.Angles(0, 0,
					s.amp * math.sin(clock * s.speed + (s.phase or 0)))
			end

			if physical then
				--[[
					ABSOLUTE, blended out from neutral. A relative lerp off the
					joint's own value would compound here, because the solver
					is also moving the limb toward the last target between our
					writes -- so each frame would blend off a value we already
					pushed and the pose would creep past itself. The physical
					joint gets its easing for free anyway: writing a target
					makes the solver travel to it over several frames, which is
					why the blend can be this blunt and still look soft.
				]]
				entry.joint.Transform = CFrame.identity:Lerp(target, weight)
			else
				--[[
					Kinematic joints have no solver to soften anything, so the
					blend is the animation. Lerping off the joint's CURRENT
					value blends over whatever the animator wrote this frame --
					the live frame of the idle or the fall -- so weight 0 is
					exactly the animation and weight 1 exactly the pose, and
					neither end of the transition pops.
				]]
				entry.joint.Transform = entry.joint.Transform:Lerp(target, weight)
			end
		end
	end
end

--[[
	Runs for everyone, flying or not, so remote players are posed too -- and
	keeps running through the blend-out, after the attribute is already off.

	Called from BOTH phases. PreSimulation owns the clock, because it fires once
	a frame and is the phase the physical joints are actually read in; the
	render pass only writes, using the weight already computed.
]]
local function drive(dt, physical)
	local clock = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character then
			local weight = weights[character] or 0

			if physical then
				local wants = character:GetAttribute(ASCENDING) and 1 or 0
				if weight ~= wants then
					local rate = wants == 1 and BLEND_IN or BLEND_OUT
					weight = wants == 1 and math.min(1, weight + rate * dt)
						or math.max(0, weight - rate * dt)
					weights[character] = weight
				end
			end

			if weight > 0.001 then
				applyPose(character, weight, clock, physical)
			end
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
	-- Facing, held between frames so a hover keeps the heading you arrived with
	-- rather than snapping back to whatever the humanoid last wanted.
	local heading

	--[[
		Both phases, because the two rig generations resolve in different ones.

		PreSimulation lands between the animator and the physics solve, which is
		the only window where a written AnimationConstraint target survives to
		be acted on. Character+1 is the first opportunity to overwrite a Motor6D
		after the animator has written it; being late is the point there rather
		than a compromise. Each pass touches only the joints it owns.
	]]
	RunService.PreSimulation:Connect(function(dt)
		drive(dt, true)
	end)
	RunService:BindToRenderStep("AscensionPose",
		Enum.RenderPriority.Character.Value + 1, function(dt)
			drive(dt, false)
		end)

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
		heading = root.CFrame.Rotation -- take off facing where you were standing
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

				It ACCELERATES rather than holding one speed: a third of the
				rise at the start, full by the end. A constant velocity from a
				standing start looks like being pulled up on a wire, because
				nothing in the world begins moving at its top speed. Easing in
				reads as lift building underneath you.
			]]
			local t = elapsed / Config.TakeoffSeconds
			vertical = Config.TakeoffRise * (0.34 + 0.66 * t * t)
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

		--[[
			Face the direction of travel and LEAN INTO IT, up to 20 degrees at
			full speed. This is the one piece of the animation that isn't in the
			joints, and it does more work than any of them: a spread-eagle body
			travelling perfectly upright looks like it is being slid across the
			sky, whereas the same body tipped forward looks like it is driving
			itself. Negative pitch, because the character's forward is -Z and a
			forward lean means the nose goes down.

			Eased rather than set, so changing direction banks over instead of
			flicking. Heading holds when you stop, so a hover keeps the facing
			you arrived with.
		]]
		local speed = Vector3.new(horizontal.X, 0, horizontal.Z).Magnitude
		local lean = math.rad(20) * math.min(speed / Config.FlightSpeed, 1)
		if speed > 1 then
			heading = CFrame.lookAt(Vector3.zero,
				Vector3.new(horizontal.X, 0, horizontal.Z).Unit)
		end
		if heading then
			rig.orientation.CFrame = rig.orientation.CFrame:Lerp(
				heading * CFrame.Angles(-lean, 0, 0), 0.18)
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
