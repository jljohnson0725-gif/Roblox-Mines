--[[
	Animations
	Every animation asset id the game plays, in one table.

	WHY THIS FILE IS MOSTLY EMPTY, and what to do about it.

	The RPG Animation Pack ships 140 R15 animations as KeyframeSequence
	objects -- raw curves -- and NOT as Animation objects. There is not a single
	asset id in the file. A KeyframeSequence cannot be handed to
	Animator:LoadAnimation; only an id can, so every clip has to be published
	once before anything here can play it.

	KeyframeSequenceProvider:RegisterKeyframeSequence looks like a way around
	that and is not one. It works -- it returns a hash that loads and plays --
	but the hash names content registered in ONE machine's local content cache.
	It was measured working in Studio, where the server and the client are the
	same process and share that cache; a live server would hand every remote
	player an id their machine has never heard of. Studio passing is not
	evidence here, so it is not used.

	SO: PUBLISH THE THREE, THEN FILL THEM IN.

	  1. Insert the pack. The KeyframeSequences arrive under a folder called
	     "RPG Animation Pack KeyframeSequences".
	  2. For each of the three named below: select it, open the Animation
	     Editor, Import -> From Roblox Studio, then Publish to Roblox.
	  3. Paste the id it gives you into the matching field.

	Seven, not a hundred and forty: three for the ride and four for the punch
	combo. The other 133 are combat-room, fishing and sword clips for mechanics
	this game does not have.

	NOTHING BREAKS WHILE THEY ARE BLANK. The ride falls back to the default sit
	pose and the punch falls back to UI/Punch's code-driven swing, so every one
	of these is an upgrade rather than a dependency.

	EMPTY IS A VALID STATE and every caller must treat it as one. An unfilled
	id means the mount ride simply looks the way it looks today -- the default
	sit pose -- rather than erroring on a player who is a thousand studs up
	with no way down. `Animations.load` returns nil and callers do nothing.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = {}

--[[ Riding a summoned brainrot. From the pack's DTalon set, which is the only
     group in it built for sitting on something that moves. Durations are the
     measured lengths of the source clips, kept here because the loop has to be
     told to loop and the other two must not be. ]]
Animations.Ride = {
	--[[ DTalon_XRideStart_KeyframeSequence -- 0.98s ]]
	start = "94533213285841",
	--[[ DTalon_XRideLoop_KeyframeSequence -- 1.33s, loops ]]
	loop = "112210005062693",
	--[[ DTalon_XRideJumpOff_KeyframeSequence -- 0.65s ]]
	jumpOff = "127365481694489",
}

--[[
	THE FOUR-HIT M1 COMBO, from the pack's Control set. Cycled one per swing so
	repeated punches read as a sequence rather than the same jab four times.

	These are the ids to publish if you want the pack's punch:

	  ControlM1_1_KeyframeSequence .. ControlM1_4_KeyframeSequence

	WHILE THIS LIST IS EMPTY, UI/Punch poses the arm in code instead. Fill in
	even one and it switches over -- a partly-filled list simply cycles through
	the entries that exist, which is what makes publishing them one at a time
	safe.
]]
Animations.Punch = {
	"139673613545631", -- ControlM1_1
	"89103537551227", -- ControlM1_2
	"81076576625620", -- ControlM1_3
	"108447879983564", -- ControlM1_4
}

--[[
	THE DASH, one clip per direction.

	Direction is worked out against the CAMERA, not the character: with the
	default camera the body turns to face wherever it is walking, so measuring
	against the character's own LookVector would report "forward" for all four
	of them.
]]
Animations.Dash = {
	forward = "106680454668560", -- DashForward
	backward = "79881645287312", -- DashBackward
	left = "90885896362209", -- DashLeft
	right = "123525811311871", -- DashRight
}

--[[
	THE STUDIO PREVIEW PATH.

	A way to see the pack's real animation before publishing anything, so the
	question "is this the clip I want?" can be answered in thirty seconds
	rather than after an upload.

	KeyframeSequenceProvider:RegisterKeyframeSequence takes a raw sequence and
	hands back a hash that Animation.AnimationId accepts. Measured working: the
	returned hash loaded and played, in Edit and in a running Studio server.

	IT IS GATED TO STUDIO AND IT MUST STAY THAT WAY. The hash names content in
	ONE MACHINE'S local content cache. In Studio the server and the client are
	the same process, which is exactly why the earlier test passed and exactly
	why that test proves nothing about a live server -- a remote player would
	be handed an id their machine has never registered. IsStudio is what stops
	this shipping by accident and quietly working for the developer alone.

	NOTE ON WHERE TO PUT THE PACK. The whole thing is 226,619 instances. Left
	in ReplicatedStorage in full it replicates to every joining client, which
	is a long download for four clips. Insert it, keep the sequences you
	actually want, delete the rest.

	THE SEARCH IS DELIBERATELY SHALLOW -- direct children of ReplicatedStorage
	and one level inside its folders. GetDescendants would walk all 226,619 of
	them, four times over, on the first punch of every round.
]]
Animations.PunchClips = { "ControlM1_1", "ControlM1_2", "ControlM1_3", "ControlM1_4" }

local previewCache = {}

local function findSequence(clip)
	local wanted = { [clip] = true, [clip .. "_KeyframeSequence"] = true }
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child:IsA("KeyframeSequence") and wanted[child.Name] then
			return child
		end
		if child:IsA("Folder") or child:IsA("Model") then
			for _, inner in ipairs(child:GetChildren()) do
				if inner:IsA("KeyframeSequence") and wanted[inner.Name] then
					return inner
				end
			end
		end
	end
	return nil
end

--[[ A playable id for one pack clip, or nil. Cached per clip INCLUDING the
     misses -- a `false` entry stops a failed lookup being repeated on every
     swing when the pack simply is not in the place. ]]
function Animations.previewId(clip)
	if not RunService:IsStudio() then
		return nil
	end
	local cached = previewCache[clip]
	if cached ~= nil then
		return cached or nil
	end
	local sequence = findSequence(clip)
	if not sequence then
		previewCache[clip] = false
		return nil
	end
	local ok, hash = pcall(function()
		return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(sequence)
	end)
	if not ok or type(hash) ~= "string" or hash == "" then
		warn("[Animations] could not register preview for", clip, hash)
		previewCache[clip] = false
		return nil
	end
	previewCache[clip] = hash
	return hash
end

function Animations.previewIds(clips)
	local out = {}
	for _, clip in ipairs(clips or {}) do
		local id = Animations.previewId(clip)
		if id then
			table.insert(out, id)
		end
	end
	return out
end

--[[ Is there at least one real id in a list? What UI/Punch asks to decide
     between the published clips and its own posing. ]]
function Animations.hasAny(list)
	for _, id in ipairs(list or {}) do
		if type(id) == "string" and id ~= "" then
			return true
		end
	end
	return false
end

--[[ The filled entries only, in order, so a half-published combo cycles
     through what exists instead of playing nothing every other swing. ]]
function Animations.filled(list)
	local out = {}
	for _, id in ipairs(list or {}) do
		if type(id) == "string" and id ~= "" then
			table.insert(out, id)
		end
	end
	return out
end

--[[
	Load a track onto a humanoid, or return nil.

	Returns nil rather than throwing for an unset id, a missing Animator or a
	character that has already gone -- all three are ordinary, and none of them
	is worth failing a ride over.

	Animator, not Humanoid:LoadAnimation. Loading through the humanoid is
	deprecated and, on the server, does not always replicate the track to
	spectators; the Animator is the object that actually owns playback.
]]
function Animations.load(humanoid, id)
	if type(id) ~= "string" or id == "" then
		return nil
	end
	if not humanoid or not humanoid.Parent then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	--[[
		ONLY A BARE NUMBER GETS THE PREFIX.

		A published id is digits and wants rbxassetid://. A registered preview
		id is a 32-character hash and must be passed THROUGH UNTOUCHED --
		measured: the bare hash loads and plays, while "hash://" and
		"rbxassetid://" in front of it both fail with "Invalid animation id".
		Prefixing everything would have broken the preview path on its first
		swing while looking like a pack problem.
	]]
	animation.AnimationId = id:match("^%d+$") and ("rbxassetid://" .. id) or id

	--[[ Wrapped because LoadAnimation yields on a fetch and throws on an id
	     that does not resolve -- a typo in the table above must not be able to
	     strand a rider. ]]
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		warn("[Animations] could not load", id, track)
		return nil
	end
	return track
end

return Animations
