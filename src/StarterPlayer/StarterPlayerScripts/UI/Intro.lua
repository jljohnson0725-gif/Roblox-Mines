--[[
	Intro
	The cold open: rain, him on his knees, and the line that starts the game.

	Ten seconds, ONE CONTINUOUS CAMERA MOVE, no cuts. The brief was "the camera
	turns around and she is revealed", and a cut would throw that away -- the
	turn IS the reveal, so it has to be one unbroken move or the moment belongs
	to the edit rather than to the world. Storyboarded and timed in
	tools/intro.py; keep the two in step.

		0.0  high and behind. He is small, the rain is huge.
		3.4  push in on silence. Nothing happens, which is the point.
		6.0  the camera swings round him -- the move that reveals her.
		7.4  low, looking up. She stands, he does not.
		7.9  "You're ugly and broke, we're done."
		9.2  the camera leaves her.
		11.2 round to his face. He lifts his head. Nobody says anything.
		14.0 out.

	BUILT ON ITS OWN SET, nine hundred studs under the map, entirely on the
	client. Staging it in the world would mean fighting the daylight pass, the
	map's own geometry and whatever another player happens to be standing in
	front of. Down here the only things in existence are the two figures, the
	rain, and the ground they are on, so every frame is composed rather than
	hoped for.

	IT MUST ALWAYS GIVE CONTROL BACK. A cutscene that fails halfway leaves a
	player frozen in a black box with no camera, which is worse than never
	playing it -- so the body runs inside a pcall, a hard timeout is armed
	BEFORE anything can go wrong, and the restore path is the same code whether
	it finished or threw.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Intro = {}

--[[ Far below anything the map or the sky islands use, so the set can never
     share a frame with the game. ]]
local ORIGIN = Vector3.new(0, -900, 0)
local HIM = ORIGIN
local HER = ORIGIN + Vector3.new(0, 0, 7)

local LINE = "You're ugly and broke, we're done."
local SUBTITLE_AT = 7.9
--[[ The line clears BEFORE the last beat, so the closing shot is silent. Her
     words are done; what is left is him. ]]
local SUBTITLE_OUT = 10.6
local RUNTIME = 14.0
local FADE_IN, FADE_OUT = 0.4, 0.6
local BAR = 0.11

--[[
	Position and aim, both interpolated. Aiming at a POINT rather than carrying
	a rotation is what keeps the subject centred through the swing;
	interpolating angles would let her drift out of frame mid-turn and snap
	back at the end.

	THE REVEAL SITS BEHIND HIM, over his shoulder. The first version put the
	camera BETWEEN the two of them, five studs from her face -- she filled the
	frame and was cut off top and bottom, and he was a shape at the very edge of
	the lens. Beyond him she reads at full height with him in the foreground,
	which is also the shot that says she is standing over him.
]]
local SHOTS = {
	{ t = 0.0,  pos = Vector3.new(-8.0, 10.0, -11.0), look = "him" },
	{ t = 3.4,  pos = Vector3.new(-5.0, 6.2, -7.5),  look = "him" },
	{ t = 6.0,  pos = Vector3.new(8.0, 4.2, -2.5),  look = "between" },
	{ t = 7.4,  pos = Vector3.new(5.6, 4.6, -4.6),  look = "her" },
	{ t = 9.2,  pos = Vector3.new(4.4, 4.4, -2.8),  look = "her" },
	--[[ AND THEN BACK TO HIM. Cutting to black on her last syllable made the
	     line the end of the scene; it is not, it is the start of his. The camera
	     leaves her, comes round in front and sits at his eyeline for nearly three
	     seconds with nothing said.

	     ABOVE HIS EYELINE, not below it. The first version sat a stud under his
	     face looking up, which frames the face beautifully and puts the horizon
	     below the bottom of the screen -- so the ground went, and she is behind
	     the lens anyway, and what was left was a dim figure against a lit sky.
	     Reported, accurately, as "everything disappears".

	     Nothing was disappearing: instrumenting the live run frame by frame,
	     the set is intact and his head sits dead centre of the viewport for the
	     whole beat. It was composition, not a bug. Looking slightly DOWN keeps
	     the wet ground under him and his whole body in shot. ]]
	--[[ RELATIVE TO HIS HEAD, not to the set origin. As fixed world offsets
	     these two worked for exactly one avatar: the pose is solved from
	     whatever proportions the player has, so his head lands anywhere from
	     about z 2.9 to z 3.9, and a camera pinned to z 6.8 was a comfortable
	     three studs in front of one body and standing inside HER on another.
	     That is what "the camera turns round and there is nothing there" was. ]]
	--[[ THE CLOSE-UP, off his head so it fits any avatar. He faces her, so the
	     lens sits BETWEEN them looking back at him -- which puts her behind the
	     camera and leaves him alone in the last shot. ]]
	{ t = 11.2, pos = Vector3.new(1.7, 0.15, 4.6), look = "hisface", rel = "hisface" },
	{ t = 14.0, pos = Vector3.new(1.3, 0.05, 3.4), look = "hisface", rel = "hisface" },
}

local AIM = {
	him = HIM + Vector3.new(0, 3.4, 0),
	her = HER + Vector3.new(0, 4.4, 0),
	between = ORIGIN + Vector3.new(0, 3.6, 3.5),
}

--[[ His head, MEASURED off the posed rig rather than guessed, because the pose
     is derived from whatever proportions the player's own avatar has and no
     fixed offset fits every body. buildSet overwrites this; the default only
     has to be sane for a caller that runs before any set exists. ]]
local himFaceAt = HIM + Vector3.new(0, 4.4, 0)

local function aimOf(name)
	if name == "hisface" then
		return himFaceAt
	end
	return AIM[name]
end

--[[ Where a shot's camera actually sits. Most are offsets from the set origin;
     the closing pair hang off his head so they fit whoever is in the scene.

     CLAMPED SHORT OF HER. Pushing the camera in front of his face moves it
     toward the only other person on the set, and an avatar whose head sits
     far enough forward would put her in front of the lens instead of behind
     it -- she would loom, blurred, over the last shot of the cutscene. ]]
local function shotPos(shot)
	if shot.rel ~= "hisface" then
		return ORIGIN + shot.pos
	end
	local at = himFaceAt + shot.pos
	return Vector3.new(at.X, at.Y, math.min(at.Z, HER.Z - 0.9))
end

--[[
	NIGHT, BUT LEGIBLE.

	Sealing the sky out took the only ambient source with it and the first pass
	came back almost entirely black -- a correct simulation of a closed dark box
	and useless as a shot. Ambient carries the scene now and the key light does
	the shaping; brightness stays low so it still reads as rain at night rather
	than as an overcast afternoon.
]]
local LOOK = {
	ClockTime = 21.2,
	Brightness = 1.0,
	Ambient = Color3.fromRGB(64, 68, 84),
	OutdoorAmbient = Color3.fromRGB(48, 52, 66),
	FogColor = Color3.fromRGB(20, 23, 32),
	FogStart = 26,
	FogEnd = 190,
}

--[[
	A LONGER LENS FOR THE WHOLE SEQUENCE.

	At the default 70 the reveal put her eleven studs out and about a hundred
	pixels tall, marooned in a frame that was three-quarters black -- the shot
	the entire cutscene builds to, and she was a detail in it. Moving the camera
	closer would have shouldered him out of frame and lost the over-the-shoulder
	read, so the fix is the lens rather than the blocking: at 42 she roughly
	doubles and his shoulder becomes the near edge of the frame.

	SAVED AND PUT BACK. Field of view is on the player's own camera, and leaving
	it at 42 would leave them zoomed in for the rest of the session.
]]
local FOV = 42

--[[ Where the rain column sits relative to the lens: a little ahead so it falls
     through the shot rather than on top of the camera, and high enough that
     streaks are already at speed by the time they cross the frame. ]]
local RAIN_OFFSET = Vector3.new(0, 9, 0)
local RAIN_AHEAD = 6

--[[
	THE REVEAL IS LIGHT, NOT GEOMETRY.

	The intent was that she is simply not in the opening shot -- but she stands
	seven studs behind him on the same flat ground, and a camera far enough back
	to frame a man on his knees frames the woman behind him too. Every position
	on a ring around him at eight and eleven studs, at three heights, was checked
	by projecting her bounding box to the viewport: she is visible in all of
	them. There is no angle that hides her, so hiding her was the wrong plan.

	What actually happens now is the better version of the same beat. She is
	THERE the whole time -- a dark shape in the rain, backlit only, too soft to
	read -- and what changes at the turn is that the light finds her and the
	focus racks onto her. The audience feels a presence for six seconds without
	being able to say who it is, which is worth more than an empty frame.

	FACE_BRIGHTNESS is her front light's full value; before REVEAL_FROM it is off
	entirely and she is lit by the backlight alone.
]]
local REVEAL_FROM, REVEAL_TO = 6.1, 7.3
local FACE_BRIGHTNESS = 2.0

--[[ His front light for the closing shot, brought up as the camera arrives.
     Off until then for the same reason hers is: lit early it puts a glow across
     the set and gives the reveal away. ]]
local HIS_BRIGHTNESS = 3.4
local LIFT_FROM, LIFT_TO = 11.0, 12.4

--[[ Filled in by buildSet: his head, and where it is, so the closing shot aims
     at the real thing whatever the player's proportions are. ]]
local himHead

local LIGHTING_KEYS = {
	"ClockTime", "Brightness", "Ambient", "OutdoorAmbient",
	"FogStart", "FogEnd", "FogColor",
	"ExposureCompensation", "ColorShift_Top", "ColorShift_Bottom",
}

--[[
	THE GRADE ON TOP OF THE LIGHTING, which is what actually made the set black.

	MapStyle dresses the town with an Atmosphere at density 0.32 and haze 1.10,
	plus a ColorCorrection, and both are tuned for a bright daytime street. In a
	sealed dark box that haze is a wall of grey over everything and the grade
	crushes what is left -- which is why raising Brightness and Ambient barely
	moved the picture. The numbers said one thing and the screen another because
	the numbers were not the whole pipeline.

	Neutralised for the ten seconds and put back exactly as found.

	NOT ZEROED, though -- the first pass stripped the haze to nothing and the
	scene went from crushed to blown out, because that haze had been doing most
	of the dimming. A little of it is right: rain wants air in it, and a touch of
	density is what puts distance between the two of them.

	The bloom threshold is here for a related reason. At 1.05 anything bright
	clipped into a halo and her head rendered as a glowing white blob; at 1.5
	only genuinely hot highlights bloom, which is the wet-street sparkle without
	the haze of an overexposed face.

	Depth of field is the one effect switched ON rather than tamed. It ships
	disabled, and a shallow focus is precisely what the reveal wants -- him soft
	in the foreground, her sharp at eleven studs.
]]
local SCENE_EFFECTS = {
	--[[ Keyed by CLASS, not by name. MapStyle names these things what it likes
	     ("DOF", "Grade", whatever a later pass calls them) and a lookup by name
	     silently finds nothing and reports success. The class is the one thing
	     about them that cannot drift. ]]
	Atmosphere = {
		Density = 0.12, Haze = 0.35, Glare = 0.2,
		--[[ A DARK atmosphere colour crushed the whole scene -- it tints the
		     scattering, so near-black haze subtracts light everywhere. This was
		     baked from a value never checked on screen and cost a full rebuild
		     to spot. ]]
		Color = Color3.fromRGB(105, 116, 142),
	},
	ColorCorrectionEffect = {
		Brightness = -0.01, Contrast = 0.14, Saturation = -0.04,
		TintColor = Color3.fromRGB(222, 232, 255),
	},
	BloomEffect = { Intensity = 0.35, Size = 20, Threshold = 1.5 },
	--[[ The night sky the scene is played under. Swapped in and put back with
	     everything else, so the map keeps its own daylight sky for the game. ]]
	Sky = {
		SkyboxBk = "rbxassetid://48020371",
		SkyboxDn = "rbxassetid://48020144",
		SkyboxFt = "rbxassetid://48020234",
		SkyboxLf = "rbxassetid://48020211",
		SkyboxRt = "rbxassetid://48020254",
		SkyboxUp = "rbxassetid://48020383",
		StarCount = 3000,
		CelestialBodiesShown = false,
	},
	BlurEffect = { Size = 0 },
	SunRaysEffect = { Enabled = false },
	DepthOfFieldEffect = {
		Enabled = true,
		FocusDistance = 11,
		InFocusRadius = 5,
		NearIntensity = 0.62,
		FarIntensity = 0.18,
	},
}

local function smooth(x)
	return x * x * (3 - 2 * x)
end

--[[ One block of a body. Everything here is a plain anchored Part: neither
     figure moves a limb, so a rig with joints would be machinery for a pose
     that is set once and held. ]]
local function block(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	HIM: hands and knees, head down.

	A pose, not an animation, because the whole shot is that he DOESN'T move.
	The camera moves; he is the still thing it moves around.
]]
local function buildHim(parent)
	local skin = Color3.fromRGB(222, 190, 160)
	local shirt = Color3.fromRGB(52, 56, 66)
	local trousers = Color3.fromRGB(34, 36, 44)

	local m = Instance.new("Model")
	m.Name = "Him"
	m.Parent = parent
	--[[ Facing her, matching the clone, so the closing shot frames a face
	     whichever figure ends up standing there. ]]
	local at = CFrame.lookAt(HIM, Vector3.new(HER.X, HIM.Y, HER.Z))

	block(m, "LeftLeg", Vector3.new(1, 3, 1), at * CFrame.new(-0.55, 1.5, 0), trousers)
	block(m, "RightLeg", Vector3.new(1, 3, 1), at * CFrame.new(0.55, 1.5, 0), trousers)
	block(m, "Torso", Vector3.new(2, 2, 1), at * CFrame.new(0, 4.0, 0), shirt)
	block(m, "LeftArm", Vector3.new(1, 2, 1), at * CFrame.new(-1.55, 4.0, 0), skin)
	block(m, "RightArm", Vector3.new(1, 2, 1), at * CFrame.new(1.55, 4.0, 0), skin)
	block(m, "Head", Vector3.new(1.4, 1.4, 1.4), at * CFrame.new(0, 5.7, 0), skin)
	return m
end

--[[
	HER: standing over him, arms folded, looking down.

	Read as a silhouette more than a face -- she is backlit and it is raining --
	so the shape does the work: the fold of the arms, the hair, and the fact
	that she is upright in a frame where he is not.
]]
--[[
	HER STANCE. Arms folded, hip out, chin down at the man on the floor.

	An avatar arrives in an A-pose, which is a pose for fitting clothes to and
	reads as a mannequin standing in the rain. She has one line and about two and
	a half seconds on screen, so the body has to say the thing before the
	subtitle does: folded arms and a cocked hip is closed, done, already left.

	Angles are in the JOINT's own space, so they suit whatever proportions the
	supplied avatar happens to have -- nothing here is a stud offset.
]]
local HER_POSE = {
	Waist         = CFrame.Angles(math.rad(-2), math.rad(10), math.rad(5)),
	Neck          = CFrame.Angles(math.rad(14), math.rad(-8), 0),
	LeftShoulder  = CFrame.Angles(math.rad(-22), 0, math.rad(13)),
	RightShoulder = CFrame.Angles(math.rad(-26), 0, math.rad(-13)),
	LeftElbow     = CFrame.Angles(math.rad(-88), 0, 0),
	RightElbow    = CFrame.Angles(math.rad(-95), 0, 0),
	LeftHip       = CFrame.Angles(math.rad(3), math.rad(7), math.rad(-4)),
	RightHip      = CFrame.Angles(math.rad(-6), math.rad(-5), math.rad(7)),
	RightKnee     = CFrame.Angles(math.rad(-16), 0, 0),
}

--[[
	THE RIG'S JOINTS, WHICHEVER KIND IT HAS.

	Roblox has two: the classic Motor6D, and the newer AnimationConstraint that
	pairs two Attachments. Avatars ship with either -- the supplied model uses
	Motor6D, a rig built from a plain HumanoidDescription came back with
	AnimationConstraints and no Motor6D at all, and a pose walker written for one
	silently moves nothing on the other. It does not error; every part simply
	stays where it started, which looks like a placement bug and is not one.

	Both reduce to the same pair of offsets, so both are read into one shape.
]]
local function rigJoints(model)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(out, { name = d.Name, p0 = d.Part0, p1 = d.Part1,
				c0 = d.C0, c1 = d.C1 })
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			table.insert(out, { name = d.Name,
				p0 = d.Attachment0.Parent, p1 = d.Attachment1.Parent,
				c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame })
		end
	end
	return out
end

--[[ Walked OUTWARD FROM THE ROOT, breadth first, so a parent is always placed
     before its children -- a limb positioned from a bone that has not moved yet
     lands relative to the old pose and the rig comes apart at the joints. ]]
local function poseRig(model, root, pose)
	local byParent = {}
	for _, j in ipairs(rigJoints(model)) do
		byParent[j.p0] = byParent[j.p0] or {}
		table.insert(byParent[j.p0], j)
	end

	local queue, seen, moved = { root }, { [root] = true }, 0
	while #queue > 0 do
		local part = table.remove(queue, 1)
		for _, j in ipairs(byParent[part] or {}) do
			if not seen[j.p1] then
				seen[j.p1] = true
				j.p1.CFrame = j.p0.CFrame * j.c0
					* (pose[j.name] or CFrame.new()) * j.c1:Inverse()
				moved += 1
				table.insert(queue, j.p1)
			end
		end
	end
	return moved
end

--[[
	ACCESSORIES DO NOT FOLLOW A POSE, and this is the part that looks like magic
	going wrong.

	Hats, hair and the rest hang off the body by weld -- but every part here is
	ANCHORED so it can be placed by CFrame, and an anchored part ignores its
	welds. Pose the body and her twintails stay hanging in the air where the
	default A-pose left them.

	So each handle is re-seated afterwards by the rule the engine itself uses:
	an accessory carries an Attachment whose NAME matches one on the body part it
	belongs to, and the handle sits wherever those two attachments coincide. That
	is proportion-independent and survives any pose.
]]
local function seatAccessories(model)
	local bodyAtt = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and d.Parent:IsA("BasePart")
			and not d.Parent.Parent:IsA("Accessory")
		then
			bodyAtt[d.Name] = bodyAtt[d.Name] or d
		end
	end

	local seated, orphans = 0, {}
	for _, acc in ipairs(model:GetDescendants()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local mine = handle and handle:FindFirstChildWhichIsA("Attachment")
			local theirs = mine and bodyAtt[mine.Name]
			if theirs then
				handle.CFrame = theirs.Parent.CFrame * theirs.CFrame * mine.CFrame:Inverse()
				seated += 1
			elseif handle then
				table.insert(orphans, acc.Name)
			end
		end
	end
	return seated, orphans
end

--[[
	HER, FROM A MODEL when one has been supplied.

	ReplicatedStorage.ExTemplate is whatever rig was dropped into assets/ex.rbxmx
	-- see the RIGS list in tools/build_place.py. The block version below is the
	fallback, and it is genuinely a fallback: standing a stack of cuboids next to
	the player's real avatar reads as a placeholder that nobody finished, because
	that is what it is.

	TWO THINGS ARE MEASURED RATHER THAN ASSUMED, both of which have already cost
	this project a day each:

	  - A MODEL'S PIVOT ROTATION IS NOT THE RIG'S FACING. The friend came out
	    eighty-three degrees off because his rig sits rotated inside a wrapper
	    Model, and the pivot describes the wrapper. So the turn is taken from the
	    HumanoidRootPart when there is one, and the rest of the model is carried
	    round with it.
	  - PIVOT IS NOT THE GEOMETRY CENTRE. Placing by pivot buried the desk five
	    studs into the floor. She is seated on the ground by BOUNDING BOX, so she
	    stands on it whatever the model's own origin happens to be.
]]
local function herFromTemplate(parent)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local template = ReplicatedStorage:FindFirstChild("ExTemplate")
	if not template then
		return nil
	end

	local m = template:Clone()
	m.Name = "Her"

	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			--[[ Whatever the model shipped with does not get to run inside the
			     cutscene; she is scenery that says one line. ]]
			d:Destroy()
		end
	end

	local hum = m:FindFirstChildWhichIsA("Humanoid", true)
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
	end

	--[[ Turn her to face him. Driven off the ROOT PART rather than the model
	     pivot: the friend came out eighty-three degrees wrong because his rig
	     sits rotated inside its wrapper Model and the pivot describes the
	     wrapper, not the body. ]]
	local root = m:FindFirstChild("HumanoidRootPart", true)
		or m:FindFirstChild("Torso", true)
		or m:FindFirstChild("UpperTorso", true)
	local want = CFrame.lookAt(HER, Vector3.new(HIM.X, HER.Y, HIM.Z))

	local posed, seated, orphans = 0, 0, {}
	if root then
		--[[ Placed roughly, then seated exactly further down. Height here only
		     has to be clear of the floor for the pose to be built at. ]]
		root.CFrame = CFrame.new(HER + Vector3.new(0, 3, 0)) * want.Rotation
		posed = poseRig(m, root, HER_POSE)
		seated, orphans = seatAccessories(m)
	else
		m:PivotTo(CFrame.new(m:GetPivot().Position) * want.Rotation)
	end

	--[[ Then slide the whole thing so her footprint centres on HER and her feet
	     land on the ground -- both read off the BOUNDING BOX, because a pivot is
	     not a geometry centre and placing by one buried the desk five studs into
	     the floor. Done last, after the pose, since posing changes the box. ]]
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(
		HER.X - cf.Position.X,
		ORIGIN.Y - (cf.Position.Y - size.Y / 2),
		HER.Z - cf.Position.Z))

	m:SetAttribute("Posed", posed)
	m:SetAttribute("AccessoriesSeated", seated)
	if #orphans > 0 then
		--[[ Said out loud rather than swallowed: an accessory with no matching
		     body attachment is one that will hang in the air beside her. ]]
		warn("[Intro] accessory with no matching attachment: "
			.. table.concat(orphans, ", "))
	end

	m.Parent = parent
	return m
end

local function buildHer(parent)
	local supplied = herFromTemplate(parent)
	if supplied then
		return supplied
	end

	--[[ Deliberately dark. At near-white skin over a hot dress she blew out to
	     a flat white-and-pink cutout under the key -- the same albedo-times-
	     brightness ceiling tools/hometiers.py enforces for the apartments. She
	     is backlit in the rain; she should read as a shape. ]]
	local skin = Color3.fromRGB(178, 152, 136)
	local dress = Color3.fromRGB(78, 18, 30)
	local hair = Color3.fromRGB(24, 19, 23)

	local m = Instance.new("Model")
	m.Name = "Her"
	m.Parent = parent
	--[[ Turned to face him, so the camera coming round his shoulder finds her
	     looking straight down the lens. ]]
	local at = CFrame.lookAt(HER, HIM)

	block(m, "LeftLeg", Vector3.new(1, 2, 1), at * CFrame.new(-0.55, 1, 0), skin)
	block(m, "RightLeg", Vector3.new(1, 2, 1), at * CFrame.new(0.55, 1, 0), skin)
	block(m, "Skirt", Vector3.new(2.5, 1.5, 1.5), at * CFrame.new(0, 2.35, 0), dress)
	block(m, "Torso", Vector3.new(2, 2, 1), at * CFrame.new(0, 3.4, 0), dress)

	-- folded across the chest, one crossed over the other
	block(m, "LeftArm", Vector3.new(1, 2, 1),
		at * CFrame.new(-0.75, 3.5, -0.45) * CFrame.Angles(0, 0, math.rad(-72)), skin)
	block(m, "RightArm", Vector3.new(1, 2, 1),
		at * CFrame.new(0.75, 3.25, -0.45) * CFrame.Angles(0, 0, math.rad(72)), skin)

	--[[ Tilted down. She is looking at someone on the floor, and the angle of
	     the head is most of what says so. ]]
	block(m, "Head", Vector3.new(2, 1, 1),
		at * CFrame.new(0, 4.9, 0) * CFrame.Angles(math.rad(-14), 0, 0), skin)
	block(m, "Hair", Vector3.new(2.25, 1.6, 1.35),
		at * CFrame.new(0, 5.0, 0.28) * CFrame.Angles(math.rad(-14), 0, 0), hair)
	block(m, "HairBack", Vector3.new(2.0, 2.4, 0.7),
		at * CFrame.new(0, 3.9, 0.62), hair)
	return m
end

--[[
	THE PLAYER'S OWN AVATAR, standing in the rain.

	It has to be them. A generic stand-in is a man; this is YOU, in your hat and
	your shirt -- and that is most of why the opening lands at all.

	Character.Archivable is FALSE, so :Clone() on a live character returns nil
	unless it is flipped first. The naive version produced nothing and fell
	silently through to the stand-in.

	EVERYTHING THAT USED TO LIVE HERE IS GONE: a limb-spanning helper, a two-bone
	IK solver, a kneeling pose built outward from the ground contacts, and an
	accessory re-seater to undo the damage that pose did to the welds. It was a
	lot of machinery for one silhouette, and it broke in a different place every
	time. A standing clone needs none of it.
]]

--[[
	EVERY PART OF AN R15 BODY, because a Head on its own is not an avatar.

	The old guard asked only whether the character had a Head, and 2.5 seconds
	after joining that is usually true while half the limbs are still streaming
	in. A clone taken then is missing pieces; if UpperTorso is one of them
	poseKneeling bails and the whole thing is thrown away for the blocky
	stand-in.

	Which is what "I can't see my character" was. Not invisible -- REPLACED, by a
	generic figure that looks exactly the same whichever avatar you are wearing,
	which is why changing characters never helped.
]]
local R15_PARTS = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local function avatarReady(char)
	if not char or not char:FindFirstChildWhichIsA("Humanoid") then
		return false
	end
	for _, name in ipairs(R15_PARTS) do
		if not char:FindFirstChild(name) then
			return false
		end
	end
	return true
end

--[[ Bounded, because the cutscene must start even if the avatar never finishes.
     The stand-in is a worse opening than the player's own body, but a cold open
     that never plays is worse than either. ]]
local function waitForAvatar(player, timeout)
	local deadline = os.clock() + (timeout or 8)
	while os.clock() < deadline do
		if avatarReady(player.Character) then
			--[[ A further beat for accessories and layered clothing, which
			     arrive after the limbs do and are what the pose re-seats. ]]
			task.wait(0.4)
			return true
		end
		task.wait(0.1)
	end
	return false
end

local function cloneAvatar(player, origin)
	local char = player.Character
	if not char or not char:FindFirstChild("Head") then
		return nil
	end

	local wasArchivable = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = wasArchivable
	if not ok or not clone then
		return nil
	end

	--[[
		HE STANDS. Nothing is posed, and that is the whole point.

		The previous version put him on his hands and knees, which meant stripping
		every joint, solving the arms to the floor with a two-bone IK, turning the
		head back the right way round because identity yaw faces the wrong axis,
		and then re-seating every accessory by attachment name because anchored
		parts ignore their welds. Each of those was a real mechanism and each one
		broke separately.

		A clone that is simply ANCHORED WHERE IT STANDS needs none of it. The pose
		is whatever the player's avatar was already in, the accessories are
		already welded exactly where they belong, and moving the model moves all
		of it rigidly. There is nothing left to get wrong.

		The Humanoid still goes -- a live one would animate him -- but the joints
		can stay: with every part anchored they are inert.
	]]
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("Animator") or d:IsA("Script")
			or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end

	--[[ Turned to face her, off the ROOT PART's own rotation rather than the
	     model pivot -- a rig can sit crooked inside its own model, and the pivot
	     describes the wrapper rather than the body. ]]
	local root = clone:FindFirstChild("HumanoidRootPart")
		or clone:FindFirstChild("UpperTorso")
		or clone:FindFirstChild("Torso")
	local want = CFrame.lookAt(origin, Vector3.new(HER.X, origin.Y, HER.Z))
	if root then
		clone:PivotTo(clone:GetPivot() * root.CFrame.Rotation:Inverse() * want.Rotation)
	end

	--[[ Then stood on the ground by BOUNDING BOX. A pivot is not a geometry
	     centre; placing by one buried the desk five studs into the floor once
	     already. ]]
	local cf, size = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + Vector3.new(
		origin.X - cf.Position.X,
		origin.Y - (cf.Position.Y - size.Y / 2),
		origin.Z - cf.Position.Z))

	clone.Name = "Him"
	return clone
end

--[[ The whole set, in one place, so `play` and `preview` cannot drift apart.
     A preview of a different scene is worse than no preview. ]]
local function buildSet(player)
	local set = Instance.new("Model")
	set.Name = "IntroSet"
	set.Parent = workspace

	--[[ Wet asphalt: dark, and reflective enough to catch the key light. A
	     matte ground in rain reads as a car park at noon.

	     WIDER THAN THE SHELL, deliberately. At 120 against the shell's 150 the
	     seam left a fifteen-stud gap on every side and the skybox blazed
	     through it as a bright horizon line straight across the shot. ]]
	local ground = block(set, "Ground", Vector3.new(156, 2, 156),
		CFrame.new(ORIGIN - Vector3.new(0, 1, 0)),
		Color3.fromRGB(26, 26, 30), Enum.Material.Concrete)
	ground.Reflectance = 0.18

	--[[
		NO SHELL AT ALL ANY MORE. The sky IS the background.

		This started as six slabs sealing the set into a black box, because the
		only sky available was the map's bright daylight one and fog does not
		hide a skybox -- fog dims what is IN the world, the sky is drawn behind
		all of it. The box was the right answer to that problem.

		Given a night sky of its own (SCENE_EFFECTS.Sky) the box became the
		problem: it put a lid and four walls between the camera and the thing it
		was supposed to be looking at, and the reveal played against black. Gone,
		the same shot has her in silhouette against cloud with the rain reading
		across it, which is the shot that was wanted all along.

		Fog carries the horizon now instead of geometry.
	]]

	--[[
		Puddles: LIGHTER than the ground, and barely reflective.

		Two wrong versions before this one, in opposite directions. At
		reflectance 0.5 on glass they came back as flat white sheets, bigger and
		brighter than either figure -- spilled paper, taking over every frame. So
		they went nearly black at 13,15,20 with a 0.22 sheen, and became something
		worse: perfect black rectangles that read as HOLES cut in the road.

		The mistake both times was reaching for reflectance. Roblox reflectance
		mirrors the SKYBOX, and this set is sealed inside a black shell, so a
		shinier puddle here reflects nothing and only gets darker. What makes
		standing water read is being a slightly lighter, smoother patch that
		catches the lights -- so that is what they are now, and the reflectance is
		almost off.
	]]
	for i = 1, 6 do
		local a = i * 2.39
		local puddle = block(set, "Puddle", Vector3.new(4 + i * 0.8, 0.05, 3 + i * 0.9),
			CFrame.new(ORIGIN + Vector3.new(math.cos(a) * (6 + i * 1.7), 0.03,
				math.sin(a) * (6 + i * 1.6))),
			Color3.fromRGB(22, 24, 30), Enum.Material.SmoothPlastic)
		puddle.Reflectance = 0.05
		--[[ Turned off axis. Six rectangles all square to the world read as floor
		     tiles no matter what colour they are; the angle is most of what makes
		     them puddles. ]]
		puddle.CFrame = CFrame.new(puddle.Position) * CFrame.Angles(0, i * 0.9, 0)
	end

	--[[ His own avatar if it can be had, the built figure if not. The fallback
	     is not decoration: an avatar still streaming in must not cost the
	     player the opening. ]]
	local avatar = player and cloneAvatar(player, HIM)
	if avatar then
		avatar.Parent = set
	else
		--[[ Said out loud. Silently swapping the player for a stand-in is the
		     kind of failure that gets reported as "it's broken" with nothing in
		     the log to point at. ]]
		warn("[Intro] could not clone the player's avatar -- using the stand-in")
		buildHim(set)
	end
	buildHer(set)

	--[[ The closing shot aims at his head, so take it from the rig that actually
	     got built. Whichever figure is standing in, and whatever proportions the
	     player's avatar has, the camera ends up on the real thing. ]]
	local himModel = avatar or set:FindFirstChild("Him")
	himHead = himModel and himModel:FindFirstChild("Head", true)
	if himHead then
		himFaceAt = himHead.Position
	end

	--[[
		Backlight behind her, so the reveal is a silhouette stepping out of the
		rain rather than a lit character standing there.

		NO SHADOWS on it. A shadow-casting light through a thousand rain
		particles wedged Studio hard enough that play mode would not start
		again; the scene has a ten-second budget and cannot spend it there.
	]]
	local key = Instance.new("Part")
	key.Name = "Key"
	key.Anchored = true
	key.CanCollide = false
	key.CanQuery = false
	key.Transparency = 1
	key.Size = Vector3.new(1, 1, 1)
	key.CFrame = CFrame.new(HER + Vector3.new(-2, 9, 5))
	key.Parent = set

	local light = Instance.new("PointLight")
	light.Brightness = 2.1
	light.Range = 55
	light.Color = Color3.fromRGB(196, 214, 255)
	light.Shadows = false
	light.Parent = key

	--[[
		A LIGHT ON HER FRONT.

		The key sits behind her by design -- she should read as a shape stepping
		out of the rain -- but behind her ALONE meant the camera saw an
		unlit back and she arrived as a black cut-out at the moment she is
		supposed to arrive. Backlight makes an outline; something has to make a
		face.
	]]
	local faceAt = Instance.new("Part")
	faceAt.Name = "FaceLight"
	faceAt.Anchored = true
	faceAt.CanCollide = false
	faceAt.CanQuery = false
	faceAt.Transparency = 1
	faceAt.Size = Vector3.new(1, 1, 1)
	faceAt.CFrame = CFrame.new(HER + Vector3.new(6, 7, -11))
	faceAt.Parent = set

	--[[ WARM, and the only warm light in the scene. The first version was the
	     same cold blue as the key and it turned her skin lavender -- she read as
	     another piece of the wet set rather than as a person in it. Everything
	     else here is night; she is the one thing lit like a face. ]]
	local face = Instance.new("PointLight")
	face.Brightness = 2.0
	face.Range = 42
	face.Color = Color3.fromRGB(255, 240, 224)
	face.Shadows = false
	face.Parent = faceAt

	--[[ A soft fill low and in front of HIM, so his hands and head are not lost
	     in his own shadow. ]]
	local fillAt = Instance.new("Part")
	fillAt.Name = "Fill"
	fillAt.Anchored = true
	fillAt.CanCollide = false
	fillAt.CanQuery = false
	fillAt.Transparency = 1
	fillAt.Size = Vector3.new(1, 1, 1)
	fillAt.CFrame = CFrame.new(HIM + Vector3.new(5, 5, -6))
	fillAt.Parent = set

	local fill = Instance.new("PointLight")
	fill.Brightness = 2.2
	fill.Range = 44
	fill.Color = Color3.fromRGB(150, 165, 200)
	fill.Shadows = false
	fill.Parent = fillAt

	--[[
		A WIDE, DIM SOURCE HIGH OVER THE WHOLE SET.

		Without it the asphalt had nothing reaching it: the two point lights are
		close-range shaping lights, and past their falloff the ground went to
		pure black, taking the puddles and the wet reflectance with it. The
		figures were lit and standing on a void.

		Low brightness over a very wide range, so it lifts the floor off black
		without flattening the shaping the other two are doing.
	]]
	local domeAt = Instance.new("Part")
	domeAt.Name = "Dome"
	domeAt.Anchored = true
	domeAt.CanCollide = false
	domeAt.CanQuery = false
	domeAt.Transparency = 1
	domeAt.Size = Vector3.new(1, 1, 1)
	domeAt.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 26, 3))
	domeAt.Parent = set

	local dome = Instance.new("PointLight")
	dome.Brightness = 1.15
	dome.Range = 90
	dome.Color = Color3.fromRGB(150, 168, 205)
	dome.Shadows = false
	dome.Parent = domeAt

	--[[
		A LIGHT FOR THE LAST SHOT, and nothing before it.

		The closing beat is his face, and every light in the scene is behind him
		for it -- the fill sits off his back shoulder, which is right for the six
		seconds it was placed for and leaves him a silhouette the moment the
		camera comes round in front of him.

		Ramped rather than switched, and off for the whole first act, for the same
		reason her front light is: lit early it would put a glow on her from
		across the set and give the reveal away before the camera gets there.
	]]
	local hisAt = Instance.new("Part")
	hisAt.Name = "HisLight"
	hisAt.Anchored = true
	hisAt.CanCollide = false
	hisAt.CanQuery = false
	hisAt.Transparency = 1
	hisAt.Size = Vector3.new(1, 1, 1)
	--[[ Placed off his head for the same reason the camera is. Pinned to the
	     origin it lit the spot one avatar's head happened to occupy and left
	     every other one in the dark. ]]
	hisAt.CFrame = CFrame.new(himFaceAt + Vector3.new(1.5, 1.0, 3.0))
	hisAt.Parent = set

	local his = Instance.new("PointLight")
	--[[ Zero until the lift ramps it. Range and distance matter more than
	     brightness here: at three studs it blew his face to white paper, and
	     backing off to six with a third of the intensity is the same amount of
	     light with a gradient across it. ]]
	his.Brightness = 0
	--[[ Close and hot, with a short range so it falls off before it reaches
	     anything else. It has to beat a lit SKY behind him now rather than the
	     black box this scene used to be played in -- at the old 1.7 he read as a
	     silhouette against cloud, which is a nice frame and not the one asked
	     for. ]]
	his.Range = 17
	his.Color = Color3.fromRGB(255, 244, 232)
	his.Shadows = false
	his.Parent = hisAt

	--[[
		RAIN, AND IT RIDES THE CAMERA. See RAIN_OFFSET / rainFollow below.

		The first version hung one wide emitter high over the set, which is the
		obvious way to make rain and produces almost none. Three separate things
		were wrong at once, and each of them looked like "particles are broken":

		  - SEVENTY STUDS WIDE. Nearly all of it fell where no lens was pointing.
		    Raising the rate just spent frames on rain nobody saw; the fix is a
		    narrow column near the camera, not a bigger storm.
		  - TWENTY-SIX STUDS UP. At that distance a 0.22-stud particle is under a
		    pixel. A test emitter six studs from the lens rendered huge and
		    obvious with a fifth of the rate, which is what proved the emitter
		    was fine and the placement was not.
		  - SQUASH ON THE WRONG AXIS. With VelocityParallel, squash stretches
		    ACROSS the direction of travel, so the streaks came out horizontal --
		    rain sliding sideways past the camera. FacingCamera stretches on
		    screen instead, which stays vertical however the camera swings.

		LightInfluence 0 so the streaks stay bright in a scene this dark, and no
		shadow-casting light anywhere near them -- that combination previously
		wedged Studio hard enough that play mode would not restart.
	]]
	local sky = Instance.new("Part")
	sky.Name = "RainSource"
	sky.Anchored = true
	sky.CanCollide = false
	sky.CanQuery = false
	sky.Transparency = 1
	sky.Size = Vector3.new(16, 1, 16)
	sky.CFrame = CFrame.new(ORIGIN + RAIN_OFFSET)
	sky.Parent = set

	local rain = Instance.new("ParticleEmitter")
	--[[ HELD DOWN DELIBERATELY. A shadow-casting light through ~1350 particles
	     already wedged Studio once in this project, and play mode stopped
	     starting again at 4200 even with shadows off. Bigger, more opaque
	     streaks at half the count read the same and cost far less. ]]
	rain.Rate = 2000
	rain.Lifetime = NumberRange.new(0.8, 1.1)
	rain.Speed = NumberRange.new(20, 26)
	rain.SpreadAngle = Vector2.new(3, 3)
	rain.Rotation = NumberRange.new(0, 0)
	rain.Size = NumberSequence.new(0.36)
	rain.Transparency = NumberSequence.new(0.16)
	rain.Color = ColorSequence.new(Color3.fromRGB(222, 234, 255))
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.LightEmission = 1
	rain.LightInfluence = 0
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Acceleration = Vector3.new(0, -28, 0)
	--[[ Both guarded: newer properties, and a missing one must not take the
	     cutscene down with it. ]]
	pcall(function()
		rain.Orientation = Enum.ParticleOrientation.FacingCamera
	end)
	pcall(function()
		rain.Squash = NumberSequence.new(4)
	end)
	rain.Parent = sky

	return set
end

--[[ Keeps the rain column sitting over the lens. Called every frame by the
     sequence and once by preview, so a moving camera never outruns its own
     weather -- which is the failure the fixed emitter had at every shot except
     the one it was placed for. ]]
local function rainFollow(set, cam)
	local src = set and set:FindFirstChild("RainSource")
	if src then
		src.CFrame = CFrame.new(cam.CFrame.Position
			+ cam.CFrame.LookVector * RAIN_AHEAD
			+ Vector3.new(0, RAIN_OFFSET.Y, 0))
	end
end

local function snapshotLighting()
	local s = { effects = {} }
	for _, k in ipairs(LIGHTING_KEYS) do
		s[k] = Lighting[k]
	end
	for class, fields in pairs(SCENE_EFFECTS) do
		local inst = Lighting:FindFirstChildWhichIsA(class)
		if inst then
			local kept = {}
			for field in pairs(fields) do
				pcall(function()
					kept[field] = inst[field]
				end)
			end
			s.effects[class] = kept
		end
	end
	return s
end

local function restoreLighting(s)
	for k, v in pairs(s) do
		if k ~= "effects" then
			pcall(function()
				Lighting[k] = v
			end)
		end
	end
	for class, fields in pairs(s.effects or {}) do
		local inst = Lighting:FindFirstChildWhichIsA(class)
		if inst then
			for field, value in pairs(fields) do
				pcall(function()
					inst[field] = value
				end)
			end
		end
	end
	--[[ Anything this scene had to CREATE goes away again, rather than being
	     left switched off on the player's Lighting for the rest of the run. ]]
	for _, made in ipairs(s.created or {}) do
		made:Destroy()
	end
end

local function applyLook(saved)
	for k, v in pairs(LOOK) do
		pcall(function()
			Lighting[k] = v
		end)
	end
	for class, fields in pairs(SCENE_EFFECTS) do
		local inst = Lighting:FindFirstChildWhichIsA(class)
		if not inst then
			--[[ Depth of field is the one that may genuinely be missing; the
			     shot is built around it, so make one rather than skip it. ]]
			local ok, made = pcall(Instance.new, class)
			if ok and made then
				made.Parent = Lighting
				inst = made
				if saved then
					saved.created = saved.created or {}
					table.insert(saved.created, made)
				end
			end
		end
		if inst then
			for field, value in pairs(fields) do
				pcall(function()
					inst[field] = value
				end)
			end
		end
	end
end

--[[ Where the camera is at time t. Shared by the live sequence and by preview,
     so what gets tuned is what ships. ]]
--[[ Position and aim for a moment in the sequence. Shared, so the camera and
     the focus puller can never disagree about where the shot is pointing. ]]
local function solve(t)
	local a, b = SHOTS[1], SHOTS[#SHOTS]
	for i = 1, #SHOTS - 1 do
		if t >= SHOTS[i].t and t <= SHOTS[i + 1].t then
			a, b = SHOTS[i], SHOTS[i + 1]
			break
		end
	end
	local span = math.max(b.t - a.t, 0.001)
	local k = smooth(math.clamp((t - a.t) / span, 0, 1))
	return shotPos(a):Lerp(shotPos(b), k), aimOf(a.look):Lerp(aimOf(b.look), k)
end

function Intro.cameraAt(t)
	local pos, aim = solve(t)
	return CFrame.lookAt(pos, aim)
end

--[[
	THE REVEAL, APPLIED. Her front light comes up as the camera comes round, and
	the focus follows whatever the shot is aiming at -- so he is sharp while the
	camera is on him and she is sharp once it is on her, with the rack between
	them landing on the line.

	Driven off t rather than tweened, so scrubbing to any moment in preview shows
	exactly what plays at that moment. A tween would only be correct if the
	sequence had run from the start.
]]
function Intro.applyReveal(set, t)
	if not set then
		return
	end
	local faceAt = set:FindFirstChild("FaceLight")
	local face = faceAt and faceAt:FindFirstChildWhichIsA("PointLight")
	if face then
		local k = smooth(math.clamp((t - REVEAL_FROM) / (REVEAL_TO - REVEAL_FROM), 0, 1))
		face.Brightness = FACE_BRIGHTNESS * k
	end

	--[[ His front light comes up as the camera arrives on him. ]]
	local hisAt = set:FindFirstChild("HisLight")
	local hisLight = hisAt and hisAt:FindFirstChildWhichIsA("PointLight")
	if hisLight then
		local k = smooth(math.clamp((t - LIFT_FROM) / (LIFT_TO - LIFT_FROM), 0, 1))
		hisLight.Brightness = HIS_BRIGHTNESS * k
	end
	if himHead and himHead.Parent then
		himFaceAt = himHead.Position
	end

	local dof = Lighting:FindFirstChildWhichIsA("DepthOfFieldEffect")
	if dof then
		local pos, aim = solve(t)
		dof.FocusDistance = (aim - pos).Magnitude
	end
end

function Intro.init(ctx)
	local player = Players.LocalPlayer
	local running = false

	local function play()
		if running then
			return
		end
		running = true

		--[[ BEFORE ANYTHING IS BUILT OR THE CAMERA IS TAKEN. The server fires
		     this a couple of seconds after joining, which is often before the
		     avatar has all of its limbs; cloning it then gets a partial body and
		     falls through to the stand-in. Waiting here costs a moment of the
		     player still holding their own camera, which is the harmless half of
		     the trade. ]]
		waitForAvatar(player, 8)

		--[[ Claims Lighting for the duration. UI/Sky's per-frame altitude blend
		     stands down on this, which is the difference between the night look
		     holding for ten seconds and being wiped mid-shot. ]]
		player:SetAttribute("CutscenePlaying", true)

		local cam = workspace.CurrentCamera
		local savedType = cam.CameraType
		local savedFov = cam.FieldOfView
		local savedLighting = snapshotLighting()
		local char = player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local savedWalk = hum and hum.WalkSpeed or 16
		local savedJump = hum and hum.JumpPower or 50

		local set, screen, conn

		local function restore()
			if conn then
				conn:Disconnect()
			end
			if set then
				set:Destroy()
			end
			if screen then
				screen:Destroy()
			end
			restoreLighting(savedLighting)
			cam.CameraType = savedType
			cam.FieldOfView = savedFov
			cam.CameraSubject = hum
			if hum then
				hum.WalkSpeed = savedWalk
				hum.JumpPower = savedJump
			end
			if hrp then
				hrp.Anchored = false
			end
			if ctx.gui then
				ctx.gui.Enabled = true
			end
			player:SetAttribute("CutscenePlaying", false)
			running = false
		end

		--[[ THE FAILSAFE, armed before anything else can go wrong. If the body
		     below throws, or a call hangs, control still comes back. ]]
		task.delay(RUNTIME + 4, function()
			if running then
				restore()
			end
		end)

		local ok, err = pcall(function()
			if hum then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
			end
			if hrp then
				hrp.Anchored = true
			end
			if ctx.gui then
				ctx.gui.Enabled = false
			end

			set = buildSet(player)
			applyLook(savedLighting)
			cam.FieldOfView = FOV

			-- ── letterbox, fade, subtitle ─────────────────────────────────
			screen = Instance.new("ScreenGui")
			screen.Name = "Intro"
			screen.IgnoreGuiInset = true
			screen.ResetOnSpawn = false
			screen.DisplayOrder = 500
			screen.Parent = player:WaitForChild("PlayerGui")

			local function bar(anchorY, posY)
				local f = Instance.new("Frame")
				f.BackgroundColor3 = Color3.new(0, 0, 0)
				f.BorderSizePixel = 0
				f.Size = UDim2.new(1, 0, 0, 0)
				f.Position = UDim2.new(0, 0, posY, 0)
				f.AnchorPoint = Vector2.new(0, anchorY)
				f.ZIndex = 8
				f.Parent = screen
				return f
			end
			local top, bottom = bar(0, 0), bar(1, 1)

			local fade = Instance.new("Frame")
			fade.BackgroundColor3 = Color3.new(0, 0, 0)
			fade.BorderSizePixel = 0
			fade.Size = UDim2.fromScale(1, 1)
			fade.BackgroundTransparency = 0
			fade.ZIndex = 10
			fade.Parent = screen

			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Size = UDim2.new(1, -160, 0, 46)
			sub.Position = UDim2.new(0.5, 0, 1, -104)
			sub.AnchorPoint = Vector2.new(0.5, 1)
			sub.Font = Enum.Font.GothamMedium
			sub.TextSize = 26
			sub.TextColor3 = Color3.fromRGB(244, 244, 248)
			sub.TextStrokeColor3 = Color3.new(0, 0, 0)
			sub.TextStrokeTransparency = 0.35
			sub.TextTransparency = 1
			sub.TextWrapped = true
			sub.Text = LINE
			sub.ZIndex = 9
			sub.Parent = screen

			-- ── roll ──────────────────────────────────────────────────────
			cam.CameraType = Enum.CameraType.Scriptable
			Intro.applyReveal(set, 0)
			cam.CFrame = Intro.cameraAt(0)
			rainFollow(set, cam)

			TweenService:Create(top, TweenInfo.new(0.5), { Size = UDim2.new(1, 0, BAR, 0) }):Play()
			TweenService:Create(bottom, TweenInfo.new(0.5), { Size = UDim2.new(1, 0, BAR, 0) }):Play()
			TweenService:Create(fade, TweenInfo.new(FADE_IN), { BackgroundTransparency = 1 }):Play()

			local started = os.clock()
			local subtitled, cleared, fading = false, false, false
			local lastGrade = -1

			conn = RunService.RenderStepped:Connect(function()
				local t = os.clock() - started

				--[[
					RE-ASSERTED EVERY FRAME, both of them.

					Three separate things in this game write Lighting or take the
					camera, on their own schedules: the sky's altitude blend, the
					map's daylight pass, and whatever hands the camera back on a
					respawn. Each one was found and dealt with individually and a
					fourth kept turning up -- the scene would play correctly four
					times and then lose its lighting a second and a half in, which
					from the player's seat is everything vanishing after the line.

					Setting it once at the start and hoping is what made this
					intermittent. The cutscene owns the camera and the look for
					fourteen seconds, so it says so on every frame and stops
					caring who else writes. Ten property assignments a frame is
					nothing next to the rain.
				]]
				if cam.CameraType ~= Enum.CameraType.Scriptable then
					cam.CameraType = Enum.CameraType.Scriptable
				end
				cam.FieldOfView = FOV
				for k, v in pairs(LOOK) do
					if Lighting[k] ~= v then
						Lighting[k] = v
					end
				end

				Intro.applyReveal(set, t)
				cam.CFrame = Intro.cameraAt(t)
				rainFollow(set, cam)

				--[[ The graded effects re-asserted a few times a second rather
				     than every frame: heavier to write, and nothing changes them
				     as aggressively as the per-frame lighting blend does. ]]
				if t - lastGrade > 0.25 then
					lastGrade = t
					applyLook(savedLighting)
				end

				if not subtitled and t >= SUBTITLE_AT then
					subtitled = true
					TweenService:Create(sub, TweenInfo.new(0.35),
						{ TextTransparency = 0 }):Play()
				end
				if subtitled and not cleared and t >= SUBTITLE_OUT then
					cleared = true
					TweenService:Create(sub, TweenInfo.new(0.5),
						{ TextTransparency = 1 }):Play()
				end
				if not fading and t >= RUNTIME - FADE_OUT then
					fading = true
					TweenService:Create(fade, TweenInfo.new(FADE_OUT),
						{ BackgroundTransparency = 0 }):Play()
					TweenService:Create(sub, TweenInfo.new(FADE_OUT * 0.6),
						{ TextTransparency = 1 }):Play()
				end
			end)

			task.wait(RUNTIME + 0.15)
		end)

		if not ok then
			warn("[Intro] cutscene failed, restoring control: " .. tostring(err))
		end
		restore()
	end

	--[[
		PREVIEW: build the set, park the camera at one moment, and hold there.

		A ten-second move cannot be judged from a screenshot taken over a network
		round trip -- every attempt to catch it live landed after the scene had
		already torn itself down. Holding one instant is the only way to look at
		a frame properly, and it runs the same camera solve the sequence does.
	]]
	local previewSet, previewLighting, previewFov

	local function preview(t)
		waitForAvatar(player, 8)
		player:SetAttribute("CutscenePlaying", true)
		local cam = workspace.CurrentCamera
		if previewSet then
			previewSet:Destroy()
		else
			previewLighting = snapshotLighting()
			previewFov = cam.FieldOfView
		end
		previewSet = buildSet(player)
		applyLook(previewLighting)
		cam.FieldOfView = FOV
		cam.CameraType = Enum.CameraType.Scriptable
		Intro.applyReveal(previewSet, t or 0)
		cam.CFrame = Intro.cameraAt(t or 0)
		rainFollow(previewSet, cam)
		if ctx.gui then
			ctx.gui.Enabled = false
		end
		return t or 0
	end

	local function previewStop()
		if previewSet then
			previewSet:Destroy()
			previewSet = nil
		end
		if previewLighting then
			restoreLighting(previewLighting)
			previewLighting = nil
		end
		player:SetAttribute("CutscenePlaying", false)
		local cam = workspace.CurrentCamera
		if previewFov then
			cam.FieldOfView = previewFov
			previewFov = nil
		end
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = player.Character
			and player.Character:FindFirstChildWhichIsA("Humanoid")
		if ctx.gui then
			ctx.gui.Enabled = true
		end
	end

	Intro.play = play
	return { play = play, preview = preview, previewStop = previewStop }
end

return Intro
