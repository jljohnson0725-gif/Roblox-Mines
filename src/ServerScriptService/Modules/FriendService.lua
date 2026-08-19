--[[
	FriendService
	Prepares the friend's rig for the clients that clone it.

	THE NPC ITSELF IS CLIENT-SIDE -- see UI/Friend. He stands outside YOUR front
	door in YOUR session, which only works if every player gets their own copy;
	one shared NPC in Workspace would have to pick a single base and would be
	loitering outside a stranger's flat for everyone else.

	HE ARRIVES AS A FILE, not a fetch, and both fetches were tried first:

	  - InsertService:LoadAsset refuses outright -- "User is not authorized to
	    access Asset" -- because the place is unpublished and the model belongs
	    to somebody else.
	  - game:GetObjects works, but only from a PLUGIN. From a Script it throws
	    "lacking capability Plugin". It looked like the answer for exactly as
	    long as it took to run it outside the command bar, which has that
	    capability and a normal script does not.

	So the rig lives in assets/friend.rbxmx and build_place.py injects it, the
	same shape as the apartment and the desk. The difference is the FORMAT: a
	.psv carries parts, and this is a character -- Humanoid, R6 joints,
	BodyColors, an Accessory, a ShirtGraphic, four Decals -- every one of which
	that format would drop. A rig has to stay a rig, so it stays a model file.

	FAILURE IS SILENT AND SURVIVABLE. He is flavour and a tutorial, not a
	system; a missing template must not take the server with it. UI/Friend does
	nothing when it cannot find one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FriendService = {}

function FriendService.start()
	local model = ReplicatedStorage:FindFirstChild("FriendTemplate")
	if not model then
		warn("[FriendService] no FriendTemplate -- run tools/build_place.py "
			.. "with assets/friend.rbxmx present. The neighbour will not appear.")
		return
	end

	--[[
		ANCHORED AND INERT at the template, so no clone can be forgotten.

		An unanchored R6 rig with a live Humanoid walks, falls, and can be
		shoved into the road by a player; this one is scenery that talks. The
		Humanoid stays -- it holds the joints together and leaves room to animate
		him later -- but its state machine is off so he does not try to stand up
		or ragdoll.

		CanQuery goes off too: he stands beside the doorway, and HomeService
		measures the room with raycasts. A body in the way would be read as a
		wall.
	]]
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			parts += 1
		end
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
	end

	print(("[FriendService] friend ready: %d parts, rig %s")
		:format(parts, humanoid and tostring(humanoid.RigType) or "none"))
end

return FriendService
