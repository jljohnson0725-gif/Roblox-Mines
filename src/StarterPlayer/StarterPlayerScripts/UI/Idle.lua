--[[
	Idle
	The brainrots breathe. A slow bob and a slight turn, so a pad reads as
	occupied rather than decorated.

	NOT A ROBLOX ANIMATION, AND NOT BY CHOICE AT FIRST. The pack these models
	came from ships a rigged skeleton and a per-character idle Animation, which
	is the better answer -- real secondary motion, ears and tails, authored per
	creature. It cannot be used yet for two stacked reasons, both measured:

	  1. The library MeshParts are synthesised from a MeshId in the place file
	     and carry NO Bone instances, so there is no skeleton to drive. Bones
	     only exist on an imported rig; they cannot be created from a script.
	  2. Animation assets refuse to load into an unpublished place. The failure
	     is explicit -- "assetId ...&serverplaceid=0" -- and the track sits at
	     Length 0 forever with its bones never moving.

	So this animates the only thing available: the whole model. It is what the
	reference game's pad displays read as anyway from more than a few studs
	away, and it costs one CFrame multiply per part per frame instead of a
	skinned mesh update.

	CLIENT-SIDE, DELIBERATELY. Nothing here replicates. Bobbing sixty models on
	the server would be sixty CFrame replications a frame for something that
	changes no game state and that every client could compute for itself.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)

local Idle = {}

local BOB = 0.30 -- studs above and below the resting height
local SWAY = math.rad(6) -- yaw, each way
local PERIOD = 2.6 -- seconds for one full cycle

--[[
	Parts that do NOT ride along.

	The aura is a shadow, and shadows do not float. The label anchor carries the
	nameplate, which is UI rather than anatomy -- bobbing it makes the text
	shimmer against the background for no gain, and three lines of small type
	moving half a stud is exactly the kind of motion the eye keeps catching.

	Both were found by printing the moving set rather than assuming it: the
	label anchor is not obvious from the model's shape.
]]
local GROUNDED = { Aura = true, LabelAnchor = true }

local tracked = {}

local function capture(model)
	local pivot = model:GetPivot()
	local entry = { pivot = pivot, parts = {}, offset = {}, applied = nil }

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not GROUNDED[d.Name] then
			table.insert(entry.parts, d)
			--[[ Stored relative to the model pivot rather than as an absolute
			     CFrame, so the whole thing turns about its own centre. Rotating
			     each part about ITS centre looks identical while a model is one
			     concentric mesh, and falls apart the moment one isn't. ]]
			entry.offset[d] = pivot:ToObjectSpace(d.CFrame)
		end
	end

	if #entry.parts == 0 then
		return nil
	end

	--[[ Phase from world position, so neighbouring pads are out of step. Eight
	     brainrots bobbing in perfect unison reads as one mechanism, which is
	     the opposite of alive. ]]
	local p = pivot.Position
	entry.phase = (p.X * 0.7 + p.Z * 1.3) % (math.pi * 2)

	tracked[model] = entry
	return entry
end

--[[ Returns false when the model is gone and should stop being tracked. Split
     out so the loop below has no early exits -- `continue` is Luau and the
     parse check runs a 5.3 grammar, and nothing else in this codebase uses
     it. ]]
local function stepModel(model, entry, clock)
	if not model.Parent then
		return false
	end

	local lead = entry.parts[1]
	if not lead or not lead.Parent then
		return false
	end

	--[[ RE-ANCHOR IF SOMETHING ELSE MOVED IT. The server re-pivots these on a
	     plot refresh and on rebirth. Without this the model would snap back to
	     wherever it was first seen, every frame, and fight the server for the
	     rest of the session. ]]
	if entry.applied and (lead.CFrame.Position - entry.applied.Position).Magnitude > 0.01 then
		entry = capture(model)
		if not entry then
			return false
		end
		lead = entry.parts[1]
	end

	local t = (clock / PERIOD + entry.phase) * math.pi * 2
	local pivot = entry.pivot
		* CFrame.new(0, math.sin(t) * BOB, 0)
		* CFrame.Angles(0, math.sin(t * 0.5) * SWAY, 0)

	for _, part in ipairs(entry.parts) do
		local offset = entry.offset[part]
		if offset then
			part.CFrame = pivot * offset
		end
	end
	entry.applied = lead.CFrame
	return true
end

local function step(clock)
	for model, entry in pairs(tracked) do
		if not stepModel(model, entry, clock) then
			tracked[model] = nil
		end
	end
end

function Idle.init(ctx)
	local tag = Config.BrainrotTag

	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		capture(model)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		--[[ A tagged model arrives before its parts do when it replicates, so
		     capturing on the same frame finds nothing. One step of delay is
		     enough and costs a frame of stillness nobody sees. ]]
		task.defer(capture, model)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
		tracked[model] = nil
	end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		step(clock)
	end)

	return Idle
end

return Idle
