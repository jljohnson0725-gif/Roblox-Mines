--[[
	Dash
	Q, in whichever direction you are already asking to go.

	DIRECTION COMES FROM THE CAMERA, NOT THE CHARACTER, and this is the one
	thing in here that is easy to get wrong. With the default camera the body
	turns to face wherever it is walking, so W and A and D all leave the
	character looking straight down its own LookVector -- measure against that
	and every dash is a forward dash. Measuring the movement input against the
	CAMERA's forward and right vectors is what makes S+Q a backstep instead.

	Q ON ITS OWN IS A FORWARD DASH, per the spec, which falls out of the same
	rule: no movement input means no direction to project, so it defaults to
	whichever way the camera is looking.

	THE CLIENT OWNS THIS, exactly as Flight does. The client already owns its
	own character's physics -- it is the network owner -- so a dash applied
	from the server would be overwritten by the client's own simulation on the
	next frame. The movement and the animation are both settled here, before
	anything is sent, and the cooldown below is a feel constraint rather than a
	security one: a dash wins nothing, so there is nothing to protect.

	THE ONE THING THAT LEAVES THIS MODULE IS THE SOUND. A Sound created on the
	dasher's own client is audible to the dasher alone, so the cue is announced
	to the server and played there instead -- see CombatService.dashed. The
	remote is told what happened; it is never asked for permission, and nothing
	here waits for a reply.

	A LINEARVELOCITY, NOT A VELOCITY WRITE. Setting AssemblyLinearVelocity each
	frame fights the humanoid's own controller and reads as stuttering; a
	constraint is what Flight uses and it hands the whole job to the solver.
	It is built per dash and destroyed after -- Flight's note about leftover
	constraints being the classic way to end up unable to walk applies just as
	much to something that fires every second.

	VECTOR MODE, NOT PLANE MODE, and this was measured rather than reasoned
	about. Plane mode looks like the right tool -- constrain the two horizontal
	axes, leave the vertical one to gravity -- and it does not work: three
	trials from the same standing start moved the character 0.1 studs with
	Plane (with the vertical axis blocked AND with every axis allowed force)
	against 15.0 studs with Vector. Flight already uses Vector and MaxForce for
	its own movement; there was no reason to invent a second shape.

	The cost is that the dash owns vertical velocity for its 0.22 seconds. It
	is seeded with whatever the character already had, so a dash off a ledge
	keeps falling at the speed it was falling -- it simply stops ACCELERATING
	downward until the dash ends. At this duration that is not visible.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Animations = require(Shared.Animations)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Dash = {}

local localPlayer = Players.LocalPlayer

--[[ Tracks are cached per humanoid and warmed on spawn, for the reason
     UI/Punch records: LoadAnimation fetches the asset, and building them on
     the first dash means the first dash plays a clip that has not arrived. ]]
local tracks = setmetatable({}, { __mode = "k" })

local function tracksFor(humanoid)
	local entry = tracks[humanoid]
	if entry ~= nil then
		return entry or nil
	end
	--[[
		NOTHING IS DECIDED UNTIL THE ANIMATOR EXISTS.

		The warm-up runs on CharacterAdded, and the Animator is not always
		there yet when it does. Every load then returns nil, the "these ids do
		not work" answer gets cached, and it is cached FOREVER -- so a race lost
		by a few frames at spawn permanently disabled the animation while
		leaving everything else working. Measured: zero Action tracks across a
		whole session, no errors, ids that load perfectly when asked directly.

		Returning nil WITHOUT caching is the fix: the next call simply asks
		again, by which time the Animator has arrived.
	]]
	if not humanoid:FindFirstChildOfClass("Animator") then
		return nil
	end
	local built, any = {}, false
	for name, id in pairs(Animations.Dash) do
		local track = Animations.load(humanoid, id)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			built[name] = track
			any = true
		end
	end
	if not any then
		--[[ Cached as false so a bad id is not re-fetched on every dash. The
		     dash still MOVES you -- only the animation is missing, which is
		     the right way round. ]]
		tracks[humanoid] = false
		return nil
	end
	tracks[humanoid] = built
	return built
end

--[[
	Which of the four this is.

	Returns a name and a WORLD direction, because the caller needs both and
	deriving one from the other twice would be two chances to disagree.

	The dominant axis wins outright rather than blending: there are four clips,
	so a diagonal has to resolve to one of them, and picking the larger
	component is what makes W+A read as forward rather than as an arbitrary
	choice between two equals.
]]
local function directionFor(humanoid)
	local camera = Workspace.CurrentCamera
	if not camera then
		return "forward", Vector3.zero
	end

	--[[ Flattened. A camera looking at the floor would otherwise send a
	     forward dash into the ground. ]]
	local forward = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	local right = camera.CFrame.RightVector * Vector3.new(1, 0, 1)
	forward = forward.Magnitude > 0 and forward.Unit or Vector3.new(0, 0, -1)
	right = right.Magnitude > 0 and right.Unit or Vector3.new(1, 0, 0)

	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return "forward", forward -- Q alone
	end

	local ahead = move:Dot(forward)
	local across = move:Dot(right)
	if math.abs(ahead) >= math.abs(across) then
		if ahead >= 0 then
			return "forward", forward
		end
		return "backward", -forward
	end
	if across >= 0 then
		return "right", right
	end
	return "left", -right
end

local nextDash = 0

function Dash.go()
	local now = os.clock()
	if now < nextDash then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	--[[ Not while sitting. Riding a mount is a Seat, so without this you could
	     dash out of the saddle a thousand studs up -- and the mount would carry
	     on to the island without you. ]]
	if humanoid.Sit then
		return
	end

	local name, direction = directionFor(humanoid)
	if direction.Magnitude < 0.1 then
		return
	end
	nextDash = now + Config.DashCooldown

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	--[[ Y is seeded from the character's CURRENT vertical speed rather than
	     zeroed. Zeroing it would stop a falling player dead in the air for the
	     length of the dash, which reads as catching on something. ]]
	velocity.VectorVelocity = Vector3.new(
		direction.X * Config.DashSpeed,
		root.AssemblyLinearVelocity.Y,
		direction.Z * Config.DashSpeed)
	velocity.Parent = root

	local set = tracksFor(humanoid)
	local track = set and set[name]
	if track then
		track:Stop(0.05)
		track:Play(0.05)
	end

	--[[ Fired after the dash is already underway, so a slow round trip delays
	     the noise and never the movement. ]]
	Net.get("Dashed"):FireServer()

	task.delay(Config.DashTime, function()
		if velocity.Parent then
			velocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
	--[[ A backstop on top of the timer. If this thread is ever lost -- an
	     error, a respawn landing between the two -- a surviving constraint
	     would leave the player skating. ]]
	Debris:AddItem(velocity, Config.DashTime + 2)
	Debris:AddItem(attachment, Config.DashTime + 2)
end

function Dash.init(ctx)
	local function warm(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			task.spawn(function()
				--[[ Waited for rather than assumed -- see tracksFor. ]]
				humanoid:WaitForChild("Animator", 10)
				tracksFor(humanoid)
			end)
		end
	end
	warm(localPlayer.Character)
	localPlayer.CharacterAdded:Connect(warm)

	UserInputService.InputBegan:Connect(function(input, processed)
		--[[ `processed` keeps Q out of the chat bar and out of any text field
		     a panel is showing. Without it, typing the letter q in a code box
		     would throw the player sideways. ]]
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			Dash.go()
		end
	end)

	return Dash
end

return Dash
