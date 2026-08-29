--[[
	Punch
	The swing you can see.

	TWO WAYS TO THROW IT, and which one runs depends on whether anybody has
	published the pack's combo yet.

	  published  Shared/Animations.Punch has ids -> the real four-hit M1 combo
	             plays through the Animator, cycling one clip per swing.
	  otherwise  the arm is posed in code, here, exactly as Flight poses a
	             flying player and Intro poses the cold open's rig.

	The code-driven version is not a placeholder to be deleted. It is what makes
	the punch work on a fresh clone of this place with nothing published, and
	the switch is a list being non-empty rather than a flag anybody has to
	remember to set.

	THE TWO PATHS REPLICATE DIFFERENTLY, which is the whole reason they are not
	interchangeable:

	  A track played through an Animator on the character you OWN replicates by
	  itself -- Roblox sends it, and every other client sees it with no help
	  from us. So on the published path, only the swinger plays anything.

	  Joint Transforms do NOT replicate at all. So on the code path every client
	  has to pose every swinger itself, off the attribute the server publishes.

	Running both would double the work and, on the published path, would fight
	the animator for the same shoulder.

	IT IS WRITTEN TO `Transform`, NOT TO C0. Transform is what the animator
	itself writes, so a later write in the same frame wins without having to
	disable the Animate script or fight it for ownership of the joint. Writing
	C0 would permanently move the limb's mounting point and leave the arm
	crooked once the swing finished.

	THE PHASE DEPENDS ON THE JOINT CLASS, and getting it wrong fails silently.
	Motor6D is kinematic: the animator writes it at render time, so the last
	write before the frame is drawn wins. AnimationConstraint is force-driven,
	backed by a BallSocketConstraint -- Transform is a TARGET the solver moves
	toward during the physics step, and a render-time write is simply thrown
	away before it can matter.

	This shipped writing everything at render time and the arm did not move at
	all, on a rig that turned out to be fifteen AnimationConstraints. Flight's
	pose had already recorded the same measurement and the same fix.

	THE SWINGER'S OWN CLIENT NEVER WAITS FOR THE SERVER. It throws the punch the
	moment the button goes down, because a swing that starts a round trip later
	feels broken even when the round trip is fast. The server's attribute is
	ignored for the local player on both paths, so nothing is ever thrown
	twice.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Animations = require(Shared.Animations)
local Config = require(Shared.Config)

local Punch = {}

local localPlayer = Players.LocalPlayer

--[[ How long the whole swing takes. Shorter than the server's cooldown, so
     the arm is always home before the next one can start and two swings can
     never overlap into a blur. ]]
local DURATION = 0.34

--[[
	The joints, by rig.

	R15 shoulders swing FORWARD about X -- Z is the axis they lift out
	sideways on, which is what Flight uses for its ascension pose.

	THE SIGN WAS MEASURED, not reasoned about, because a root's LookVector is
	-Z and it is easy to talk yourself into the wrong one. Solving the right
	hand's position in root space at 105 degrees: sign -1 put it at z +2.75,
	which is BEHIND the character, and sign +1 puts it at z -2.20 and y +1.88 --
	forward and shoulder high. It shipped at -1 and threw a backhand.

	R6 is here for completeness on the same terms Flight's is: its shoulders
	carry a quarter turn in C0 so the forward axis lands elsewhere, and the
	joint names carry spaces. Untested -- the place ships R15 -- so expect to
	flip this sign rather than rewrite anything.
]]
local RIG = {
	R15 = { arm = "RightShoulder", torso = "Waist", sign = 1 },
	R6 = { arm = "Right Shoulder", torso = nil, sign = 1 },
}

--[[
	MOTOR6D **OR** ANIMATIONCONSTRAINT, and this is the third time this
	codebase has been caught by it -- Intro's rig walker and Flight's pose
	both carry the same note.

	Roblox ships avatars with either. A character built from a plain
	HumanoidDescription, which is what a player gets here, comes back with
	fifteen AnimationConstraints and NOT ONE Motor6D. Measured on the live
	local character: R15, AnimationConstraint x15, Motor6D x0.

	The failure is silent, which is what makes it expensive. Looking only for
	Motor6D finds nothing, throws nothing, and poses nothing -- the arm simply
	never moves and it reads as the click not registering.

	Both classes expose `.Transform` and both use the same joint names, so once
	the class check is widened everything downstream is identical.
]]
local function jointsFor(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local rig = RIG[humanoid.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"]
	local found = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			if d.Name == rig.arm then
				found.arm = d
			elseif rig.torso and d.Name == rig.torso then
				found.torso = d
			end
		end
	end
	if not found.arm then
		return nil
	end
	--[[ Recorded per lookup rather than per rig table, because a character can
	     in principle carry a mix and the phase has to follow the JOINT. ]]
	found.physical = found.arm:IsA("AnimationConstraint")
	--[[ Carried on the result rather than read back off RIG.R15 at apply time,
	     which is what the loop did at first -- an R6 player would have been
	     posed with R15's sign. ]]
	found.sign = rig.sign
	return found
end

--[[
	The shape of the throw, as a signed 0..1 over the swing.

	Three beats in one expression rather than three branches: a short pull
	back, a fast extension past the shoulder, and a slower settle. The negative
	lobe at the start is the windup -- without it the arm simply appears at
	full extension and reads as a shove.
]]
local function curve(t)
	if t < 0.22 then
		return -0.35 * (t / 0.22)
	elseif t < 0.45 then
		local k = (t - 0.22) / 0.23
		return -0.35 + 1.35 * k * k
	end
	local k = (t - 0.45) / 0.55
	return 1 * (1 - k) * (1 - k)
end

--[[ [character] = os.clock() the current swing started. Weak keys, the way
     Flight holds its pose weights: a character that leaves the world takes its
     entry with it rather than pinning a destroyed model in memory until the
     swing would have finished. ]]
local active = setmetatable({}, { __mode = "k" })

--[[
	THE PUBLISHED COMBO.

	Tracks are cached per humanoid rather than loaded per swing: LoadAnimation
	fetches the asset, and doing that on every punch would put a network round
	trip inside a 0.55 second cooldown. Weak keys, so a respawned character's
	tracks go with it.
]]
local combos = setmetatable({}, { __mode = "k" })

--[[ Shared with the server, which picks the hit sound off the same number.
     Two copies would drift and the fourth punch would land with the first
     punch's sound. ]]
local COMBO_RESET = Config.PunchComboReset

local function comboFor(humanoid)
	local entry = combos[humanoid]
	--[[ `~= nil`, not truthiness. `false` is the cached "these ids do not
	     load" answer, and testing it as truthy would fall straight through and
	     retry the failed fetch on every single punch. ]]
	if entry ~= nil then
		return entry or nil
	end
	--[[ Published first, then the Studio preview. The preview returns nothing
	     outside Studio and nothing when the pack is not in the place, so this
	     collapses to the code path on a shipped server without a flag. ]]
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

	local ids = Animations.filled(Animations.Punch)
	if #ids == 0 then
		ids = Animations.previewIds(Animations.PunchClips)
	end
	if #ids == 0 then
		return nil
	end
	local tracks = {}
	for _, id in ipairs(ids) do
		local track = Animations.load(humanoid, id)
		if track then
			--[[ Action, so it plays over the walk/idle the default animator is
			     already running rather than losing to it. ]]
			track.Priority = Enum.AnimationPriority.Action
			table.insert(tracks, track)
		end
	end
	if #tracks == 0 then
		--[[ Every id in the list failed to load -- a typo, or an asset that is
		     not owned by this place. Cached as `false` so the failure is not
		     retried on every punch, and the code path takes over. ]]
		combos[humanoid] = false
		return nil
	end
	entry = { tracks = tracks, index = 0, last = 0 }
	combos[humanoid] = entry
	return entry
end

--[[
	Throw a punch on this character.

	Returns nothing. The caller does not need to know which path ran, and
	deliberately cannot choose -- that decision belongs to whether the ids are
	published, in one place.
]]
--[[
	`forcedIndex` is the server's combo position, and it is passed for OTHER
	players' swings only.

	The local player's own swing is predicted, so there is no server index yet
	to use -- it counts its own. Everyone else's arrives with the authoritative
	number attached, which keeps the clip they are seen throwing in step with
	the sound the server already played.
]]
function Punch.swing(character, forcedIndex)
	if not character or not character.Parent then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local entry = comboFor(humanoid)
		if entry then
			local now = os.clock()
			if forcedIndex then
				--[[ Wrapped into range rather than trusted: the server cycles
				     1..4 against its own list, and a half-published combo
				     leaves this one shorter. ]]
				entry.index = ((forcedIndex - 1) % #entry.tracks) + 1
			else
				if now - entry.last > COMBO_RESET then
					entry.index = 0
				end
				entry.index = (entry.index % #entry.tracks) + 1
			end
			entry.last = now
			local track = entry.tracks[entry.index]
			--[[ Restarted rather than left to finish. Two swings inside one
			     clip's length would otherwise leave the second doing nothing,
			     which reads as a dropped input. ]]
			track:Stop(0.08)
			track:Play(0.08)
			return
		end
	end

	active[character] = os.clock()
end

--[[
	Does REPLICATION cover other players' swings?

	Only on the published path. A track played through the Animator on the
	character you own is sent by Roblox to everyone, so watching the attribute
	as well would play it twice.

	The preview path is deliberately NOT included. Its ids are hashes in each
	machine's own content cache, so nothing about them replicates -- every
	client has to play the clip on the swinger itself, exactly as the code path
	poses them. Treating preview as "replicated" would make the pack's
	animation visible only to the person throwing it.
]]
local function replicatesItself()
	return Animations.hasAny(Animations.Punch)
end

--[[
	Apply the swing to whichever joints are mid-throw.

	`physical` selects which half of the rigs get written this pass, because
	the two classes have to be written in different phases -- see the header.
]]
local function applyAll(physical)
	local now = os.clock()
	for character, startedAt in pairs(active) do
		local t = (now - startedAt) / DURATION
		if t >= 1 or not character.Parent then
			active[character] = nil
		else
			local joints = jointsFor(character)
			if joints and joints.physical == physical then
				local amount = curve(t) * math.rad(105) * joints.sign
				if physical then
					--[[ ABSOLUTE, not composed. The solver is already moving
					     the limb toward the last target between our writes, so
					     composing onto the joint's current value would blend
					     off something we pushed ourselves and the arm would
					     creep past the pose instead of returning from it. ]]
					joints.arm.Transform = CFrame.Angles(amount, 0, 0)
					if joints.torso then
						joints.torso.Transform =
							CFrame.Angles(0, curve(t) * math.rad(-16), 0)
					end
				else
					--[[ Kinematic joints have no solver, so composing onto
					     whatever the animator wrote this frame is what keeps
					     the legs walking while only the arm is overridden. ]]
					joints.arm.Transform = joints.arm.Transform
						* CFrame.Angles(amount, 0, 0)
					if joints.torso then
						joints.torso.Transform = joints.torso.Transform
							* CFrame.Angles(0, curve(t) * math.rad(-16), 0)
					end
				end
			end
		end
	end
end

--[[
	LOAD THE CLIPS BEFORE THE FIRST PUNCH NEEDS THEM.

	LoadAnimation fetches the asset, and the fetch is not instant. Building the
	combo lazily on the first swing meant that swing played a track that had
	not arrived yet -- measured across five clicks, the first reported
	Length = 0.00 while every later one reported 0.52. It plays nothing
	visible, so the very first punch of a round was a dud and every one after
	it was fine, which is the most annoying possible version of this bug.

	Warmed on spawn instead, and only for the local player: nobody else's
	character is ever animated from here on the published path, and on the
	preview path their first swing warms their own entry the same way.
]]
local function warm(character)
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		--[[ Spawned, because comboFor yields on the asset fetch and the
		     caller is a CharacterAdded handler. The Animator is WAITED for
		     rather than assumed -- see comboFor. ]]
		task.spawn(function()
			humanoid:WaitForChild("Animator", 10)
			comboFor(humanoid)
		end)
	end
end

function Punch.init(ctx)
	warm(localPlayer.Character)
	localPlayer.CharacterAdded:Connect(warm)

	--[[ Force-driven rigs, in the physics phase. Measured in Flight: at
	     PreSimulation an AnimationConstraint moves the limb; at render time and
	     at Heartbeat it does not move at all. ]]
	RunService.PreSimulation:Connect(function()
		applyAll(true)
	end)

	--[[ Kinematic rigs, just after the animator has written them. Character + 1
	     is the priority Flight uses for the same reason: one place later than
	     the animator, so ours is the write that survives. ]]
	RunService:BindToRenderStep("PunchPose",
		Enum.RenderPriority.Character.Value + 1, function()
			applyAll(false)
		end)

	--[[
		Everyone else's swings, off the attribute the server publishes.

		Watched per character rather than once per player, because the
		attribute lives on the character model and a respawn replaces it --
		a connection made to the old one would go quiet after the first death.
	]]
	local function watch(player)
		if player == localPlayer then
			return -- see the header: the local swing is predicted, not echoed
		end
		local function attach(character)
			character:GetAttributeChangedSignal("SwingAt"):Connect(function()
				if not character:GetAttribute("SwingAt") then
					return
				end
				--[[ On the published path their own client already played the
				     track and Roblox replicated it here. Posing on top of that
				     would fight the animator for the same shoulder. ]]
				if replicatesItself() then
					return
				end
				Punch.swing(character, character:GetAttribute("SwingIndex"))
			end)
		end
		if player.Character then
			attach(player.Character)
		end
		player.CharacterAdded:Connect(attach)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	return Punch
end

return Punch
