--[[
	Braziers
	The saddle count, rendered as five fires on the ground you stand on.

	WHY THIS EXISTS AT ALL. The reason to be on this island is to collect five
	saddle pieces, and that fact lived entirely in a 232-pixel card in the corner
	of the screen. Everything built to dress the island stood 59 studs out or
	further, behind the player, while the plaza -- the only place anyone stands
	-- was bare dirt by construction. "There is ONLY Plinko" was an accurate
	description of the view, not a complaint about part count.

	LIT PER PLAYER, ON SHARED GEOMETRY. IslandService builds all five braziers
	dark. This reveals flame N locally for each piece the LOCAL player holds.
	Transparency, Color and Light.Enabled set on a client are not replicated, so
	five people standing in the same plaza each see their own progress on the
	same five objects. That is the trick the wheel face could not use -- a wheel
	has to show one distribution to everyone watching one spin -- and it works
	here because a brazier only has to be true for the person reading it.

	NO NEW REMOTE. The fragment count already arrives in every state push, so
	this watches its own copy and reacts. A dedicated "you earned a piece" event
	would be a second source of truth for a number the client already has, and
	the two would eventually disagree about the count during a rejoin.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Islands = require(Shared.Islands)
local Seals = require(Shared.Seals)
local Sounds = require(Shared.Sounds)

local Braziers = {}

local ISLAND = "plinko"
local COUNT = 5

function Braziers.init(ctx)
	local island = Islands.get(ISLAND)
	if not island then
		return
	end
	local accent = island.accent

	--[[ Resolved lazily and never cached across a nil: the island is built by
	     the server after this module loads, and under streaming it can leave
	     and come back. A handle grabbed once is a handle that goes stale. ]]
	local function braziers()
		local root = Workspace:FindFirstChild("Island_" .. ISLAND)
		if not root then
			return nil
		end
		local found = {}
		for i = 1, COUNT do
			found[i] = root:FindFirstChild("Brazier" .. i)
			if not found[i] then
				return nil
			end
		end
		return found, root
	end

	local function setLit(brazier, lit)
		for _, d in ipairs(brazier:GetDescendants()) do
			if d.Name == "Flame" then
				--[[ Not fully opaque: a neon box at transparency 0 is a flat
				     block of colour, and a little translucency is what lets the
				     tiers read as separate flames rather than one lump. ]]
				d.Transparency = lit and 0.15 or 1
			elseif d.Name == "Glow" then
				d.Enabled = lit
				d.Brightness = lit and 2.2 or 0
			end
		end
	end

	--[[
		The shard: an amber mote thrown from the machine to the brazier that is
		about to light.

		The award is otherwise a line of text that scrolls away in 2.5 seconds.
		Making the piece a physical thing that travels from the machine to the
		monument is what welds the two together -- nobody has to be told the
		braziers are the count, they watch one get delivered.
	]]
	local function throwShard(from, to, onArrive)
		local shard = Instance.new("Part")
		shard.Name = "SaddleShard"
		shard.Size = Vector3.new(2.2, 2.2, 2.2)
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.Material = Enum.Material.Neon
		shard.Color = accent
		shard.CFrame = CFrame.new(from)
		shard.Parent = Workspace

		local flight = 1.1
		local start = os.clock()
		local peak = math.max(from.Y, to.Y) + 34

		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) / flight
			if t >= 1 then
				connection:Disconnect()
				shard:Destroy()
				onArrive()
				return
			end
			--[[ A real arc, not a straight lerp. Quadratic through a raised
			     midpoint, so it lobs over the plaza rather than sliding across
			     it -- the difference between a thrown object and a UI tween. ]]
			local flat = from:Lerp(to, t)
			local lift = (1 - (2 * t - 1) ^ 2) * (peak - math.max(from.Y, to.Y))
			shard.CFrame = CFrame.new(Vector3.new(flat.X, flat.Y + lift, flat.Z))
				* CFrame.Angles(t * 9, t * 7, 0)
		end)
	end

	-- ── state ───────────────────────────────────────────────────────────────

	--[[ nil rather than 0 until the first push, so a player who rejoins holding
	     three pieces sees three fires already burning instead of watching three
	     shards fly at them for progress they made yesterday. ]]
	local shown = nil

	local function render()
		local found, root = braziers()
		if not found then
			return
		end

		local held = Seals.held(ctx.state, ISLAND) and COUNT
			or math.min(Seals.count(ctx.state, ISLAND), COUNT)

		if shown == nil then
			for i = 1, COUNT do
				setLit(found[i], i <= held)
			end
			shown = held
			return
		end

		if held == shown then
			return
		end

		if held < shown then
			-- a rebirth or a correction: just settle, no ceremony
			for i = 1, COUNT do
				setLit(found[i], i <= held)
			end
			shown = held
			return
		end

		--[[ One shard per new piece, staggered. Two arriving together would
		     read as one event and undercount the thing being celebrated. ]]
		local machine = Workspace:FindFirstChild("Plinko")
		local from = machine and (machine:GetPivot().Position + Vector3.new(0, 40, 0))
			or (island.center + Vector3.new(0, 40, 0))

		for i = shown + 1, held do
			local brazier = found[i]
			local target = brazier:GetPivot().Position + Vector3.new(0, 12, 0)
			task.delay((i - shown - 1) * 0.5, function()
				throwShard(from, target, function()
					setLit(brazier, true)
					Sounds.play("unlock", 1 + i * 0.05)
					if ctx.fx then
						ctx.fx.flashColor(accent, 0.18, 0.35)
					end
				end)
			end)
		end
		shown = held
	end

	-- ── the saddle ──────────────────────────────────────────────────────────

	local sealed = nil

	local function checkSaddle()
		local has = Seals.held(ctx.state, ISLAND)
		if sealed == nil then
			sealed = has -- first push: never celebrate what you already had
			return
		end
		if has and not sealed then
			sealed = true
			--[[ The full drop spectacle, at Mythic weight. This is the single
			     biggest moment in the first chapter -- roughly sixty-five drops
			     of work, and the thing that opens the second island -- and until
			     now it was a toast the same size as "Collected $4.2K". ]]
			if ctx.fx then
				ctx.fx.celebrate({
					spec = Sounds.spectacleFor("Mythic"),
					color = accent,
					sound = "saddle",
					headline = "SADDLE COMPLETE!",
					name = island.name .. " saddle forged",
					sub = "Brainrot Racing is open",
				})
			end
		elseif not has then
			sealed = false
		end
	end

	ctx.onState(function()
		render()
		checkSaddle()
	end)

	--[[ Also on a timer, because the island is built by the SERVER after the
	     client starts: the first few state pushes arrive before there is any
	     geometry to light, and without this a returning player stands in a
	     plaza of dark braziers until their next push happens to land. ]]
	task.spawn(function()
		while shown == nil do
			task.wait(1)
			render()
		end
	end)

	return Braziers
end

return Braziers
