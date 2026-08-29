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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)

local FriendService = {}

--[[
	The tour is a client-side thing -- a camera and a dialogue card -- so all
	the server owns is the latch that stops it being offered a second time.

	NOTHING IS TRUSTED HERE BEYOND "IT HAPPENED". There is no reward and no
	gate behind this flag; the worst a forged call can do is skip a tour the
	player was going to be shown once. Latched rather than toggled, so it can
	only ever move one way.
]]
local function watchTour()
	Net.get("FinishTour").OnServerEvent:Connect(function(player)
		local profile = DataService.get(player)
		if not profile or not profile.onboarding then
			return
		end
		if profile.onboarding.toured then
			return
		end
		profile.onboarding.toured = true
		PlayerState.push(player)
	end)
end

function FriendService.start()
	watchTour()

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

	-- recursive: the asset nests its rig inside another Model
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)

	--[[
		THE SPARE PILLOW GOES.

		The asset ships TWO of them: one tucked under his arm, and a second
		lying seven studs away that the creator evidently left in the scene.
		Cloned as-is, every player gets a body pillow abandoned in the street
		outside their flat, which reads as a bug rather than as a joke.

		Told apart by DISTANCE, not by name or parent -- both are called "Puro
		Pillow", and neither is welded to anything, so there is no join to
		follow. The held one sits 2.1 studs from the root and the stray 7.0, so
		anything beyond four is not part of him.
	]]
	local root = model:FindFirstChild("HumanoidRootPart", true)
	local strays = 0
	if root then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root
				and (d.Position - root.Position).Magnitude > 4
			then
				d:Destroy()
				strays += 1
			end
		end
	end
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
	end

	print(("[FriendService] friend ready: %d parts, rig %s, %d stray part(s) dropped")
		:format(parts, humanoid and tostring(humanoid.RigType) or "none", strays))
end

return FriendService
