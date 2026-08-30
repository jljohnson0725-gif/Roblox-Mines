--[[
	RaceLab
	The bench for the racing stat model. Press L on the racing island.

	A SANDBOX, NOT A FEATURE. There is no rail button and no prompt: this is
	here to make the model in Shared/RaceSim feelable before six tracks and five
	bosses get built on top of it, and it should be deleted or promoted once
	that decision is made rather than quietly becoming part of the game.

	IT QUOTES THE SAME CODE IT RUNS. The predicted time comes from
	RaceSim.predict, which steps the identical function the live race steps.
	A panel whose estimate came from a formula while the race came from a
	simulation would be the exact failure Shared/Racing was written to prevent,
	one layer up.

	THE OPPONENT'S SPLIT IS SHOWN AFTER THE RACE, NOT BEFORE. Reading what they
	brought and reallocating against it is the whole loop being tested here, and
	handing it over up front would skip the part that has to be fun.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RaceSim = require(Shared.RaceSim)
local Net = require(Shared.Net)
local Islands = require(Shared.Islands)

local Theme = require(script.Parent.Theme)

local RaceLab = {}

function RaceLab.init(ctx)
	local player = Players.LocalPlayer

	local track = RaceSim.Tracks[1].id
	local opponent = RaceSim.Opponents[1].id
	--[[
		POOL AND SPEED, with endurance derived. Two independent 0..40 counters
		meant moving one point took two presses -- Speed down, then Endurance up
		-- which is the opposite of the "one pool, one slider" the model is
		built around. There is one number to drag now and the other follows.
	]]
	--[[
		Seeded from the profile, but NOT AT INIT -- ClientMain builds every UI
		module before it pulls the first state, so ctx.state.runner is still nil
		here and reading it now would silently give everyone the default forever.
		The saved split is adopted below, the first time state actually arrives.
	]]
	local pool = 22
	local speed = 11
	local endurance = pool - speed
	local adopted = false
	local racing = false

	--[[ Debounced: the +/- buttons fire fast and the server does not need to
	     hear about every intermediate value, only where you stopped. ]]
	local saveAt = 0
	local function save()
		saveAt = os.clock()
		local at = saveAt
		task.delay(0.4, function()
			if saveAt == at then
				Net.get("SetRacer"):FireServer(pool, speed)
			end
		end)
	end

	local card = Theme.frame({
		parent = ctx.gui,
		name = "RaceLab",
		color = Theme.color.panel,
		size = UDim2.fromOffset(430, 430),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		radius = 14,
	})
	card.Visible = false
	Theme.stroke(card, Theme.color.line, 2)
	Theme.padding(card, 16)
	Theme.list(card, 8)

	local title = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 22), order = 1,
		text = "RACE LAB", textSize = 16, color = Theme.color.text,
	})
	local sub = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 16), order = 2,
		text = "the stat model, on its own strip", textSize = 12, color = Theme.color.faint,
	})

	local function row(order, height)
		local f = Theme.frame({
			parent = card, color = Theme.color.panel, size = UDim2.new(1, 0, 0, height),
			order = order, radius = 0,
		})
		f.BackgroundTransparency = 1
		Theme.list(f, 6, Enum.FillDirection.Horizontal)
		return f
	end

	--[[ track ]]
	Theme.label({ parent = card, size = UDim2.new(1, 0, 0, 14), order = 3,
		text = "TRACK", textSize = 11, color = Theme.color.dim })
	local trackRow = row(4, 30)
	local trackButtons = {}
	for i, t in ipairs(RaceSim.Tracks) do
		trackButtons[t.id] = Theme.button({
			parent = trackRow, size = UDim2.new(0, 94, 1, 0), order = i,
			text = t.name, textSize = 12,
		})
	end

	--[[ opponent ]]
	Theme.label({ parent = card, size = UDim2.new(1, 0, 0, 14), order = 5,
		text = "OPPONENT", textSize = 11, color = Theme.color.dim })
	local oppRow = row(6, 30)
	local oppButtons = {}
	for i, o in ipairs(RaceSim.Opponents) do
		oppButtons[o.id] = Theme.button({
			parent = oppRow, size = UDim2.new(0, 74, 1, 0), order = i,
			text = o.name, textSize = 11,
		})
	end
	local tell = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 16), order = 7,
		text = "", textSize = 11, color = Theme.color.faint,
	})

	--[[ the split ]]
	Theme.label({ parent = card, size = UDim2.new(1, 0, 0, 14), order = 8,
		text = "YOUR RUNNER", textSize = 11, color = Theme.color.dim })
	local statRow = row(9, 34)
	--[[ One control moves the split: a point out of Endurance is a point into
	     Speed, which is what the pool actually means. ]]
	local toEnd = Theme.button({ parent = statRow, size = UDim2.fromOffset(38, 34), order = 1, text = "<" })
	local splitLabel = Theme.label({ parent = statRow, size = UDim2.fromOffset(230, 34), order = 2,
		text = "", textSize = 13, color = Theme.color.text })
	local toSpeed = Theme.button({ parent = statRow, size = UDim2.fromOffset(38, 34), order = 3, text = ">" })
	local reset = Theme.button({ parent = statRow, size = UDim2.fromOffset(74, 34), order = 4,
		text = "RESET", textSize = 11 })

	local poolRow = row(10, 28)
	local poolDown = Theme.button({ parent = poolRow, size = UDim2.fromOffset(38, 28), order = 1, text = "-" })
	local poolLabel = Theme.label({ parent = poolRow, size = UDim2.fromOffset(230, 28), order = 2,
		text = "", textSize = 12, color = Theme.color.dim })
	local poolUp = Theme.button({ parent = poolRow, size = UDim2.fromOffset(38, 28), order = 3, text = "+" })

	local estimate = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 34), order = 11,
		text = "", textSize = 12, color = Theme.color.text,
	})
	local go = Theme.button({
		parent = card, size = UDim2.new(1, 0, 0, 36), order = 12,
		text = "RACE", textSize = 15, color = Theme.color.good,
	})
	local result = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 44), order = 13,
		text = "", textSize = 12, color = Theme.color.faint,
	})
	result.TextWrapped = true

	local function render()
		for id, b in pairs(trackButtons) do
			Theme.recolor(b, id == track and Theme.color.good or Theme.color.raised)
		end
		for id, b in pairs(oppButtons) do
			Theme.recolor(b, id == opponent and Theme.color.good or Theme.color.raised)
		end
		local o = RaceSim.OpponentById[opponent]
		tell.Text = o and ("pool %d  ·  %s"):format(o.pool, o.tell) or ""

		splitLabel.Text = ("SPEED %d      ENDURANCE %d"):format(speed, endurance)
		poolLabel.Text = ("POOL %d"):format(pool)

		local t = RaceSim.track(track)
		local mine = RaceSim.predict(speed, endurance, track)
		--[[ What the pool COULD do here, so a bad split is visible as a bad
		     split rather than as a slow runner. ]]
		local bs, be, bt = RaceSim.bestSplit(pool, track)
		estimate.Text = ("%s · %d studs%s\nyou: %.1fs      best possible at pool %d: %.1fs (%d/%d)")
			:format(t.name, t.length,
				t.drain > 1 and (" · uphill"):format() or "",
				mine, pool, bt, bs, be)
		go.Text = racing and "RUNNING..." or "RACE"
	end

	local function settle()
		--[[ Any deliberate change wins over a late-arriving profile: adopting
		     after the player has started dragging would yank it back. ]]
		adopted = true
		pool = math.clamp(pool, 1, RaceSim.MaxPool)
		speed = math.clamp(speed, 0, pool)
		endurance = pool - speed
		render()
		save()
	end

	toSpeed.Activated:Connect(function() speed += 1 settle() end)
	toEnd.Activated:Connect(function() speed -= 1 settle() end)
	poolUp.Activated:Connect(function() pool += 1 settle() end)
	poolDown.Activated:Connect(function()
		pool -= 1
		--[[ Shrinking the pool takes the point off Speed first, so the split
		     never silently inverts on the way down. ]]
		speed = math.min(speed, math.max(pool, 0))
		settle()
	end)
	reset.Activated:Connect(function() speed = math.floor(pool / 2) settle() end)

	for id, b in pairs(trackButtons) do
		b.Activated:Connect(function() track = id render() end)
	end
	for id, b in pairs(oppButtons) do
		b.Activated:Connect(function() opponent = id render() end)
	end

	go.Activated:Connect(function()
		if racing then
			return
		end
		racing = true
		result.Text = "..."
		render()
		task.spawn(function()
			local ok, res = pcall(function()
				return Net.get("RaceTest"):InvokeServer(speed, endurance, track, opponent)
			end)
			--[[ Returns as soon as the race STARTS. The finish arrives on
			     RaceResult, because The Haul runs for ninety seconds and a
			     RemoteFunction held open that long is a hang wearing a race's
			     clothes. ]]
			if not ok or type(res) ~= "table" or not res.ok then
				racing = false
				result.Text = (type(res) == "table" and res.err) or "Race failed."
				result.TextColor3 = Theme.color.bad
				render()
			else
				result.Text = "they are off -- watch the strip"
				result.TextColor3 = Theme.color.faint
			end
		end)
	end)

	--[[ Adopt the saved split the first time the server tells us what it is. ]]
	ctx.onState(function()
		if adopted then
			return
		end
		local saved = ctx.state.runner
		if type(saved) ~= "table" then
			return
		end
		adopted = true
		pool = math.clamp(math.floor(saved.pool or pool), 1, RaceSim.MaxPool)
		speed = math.clamp(math.floor(saved.speed or speed), 0, pool)
		endurance = pool - speed
		render()
	end)

	--[[ The finish, pushed by the server whenever it happens. ]]
	Net.get("RaceResult").OnClientEvent:Connect(function(res)
		racing = false
		if type(res) ~= "table" or not res.ok or not res.order then
			result.Text = (type(res) == "table" and res.err) or "Race failed."
			result.TextColor3 = Theme.color.bad
		else
			local first, second = res.order[1], res.order[2]
			local won = first and first.id == "you"
			result.Text = ("%s  —  %s %.1fs, %s %.1fs\nthey ran %d/%d")
				:format(won and "YOU WIN" or "you lose",
					first.name, first.time, second and second.name or "?",
					second and second.time or 0,
					res.opponent.speed, res.opponent.endurance)
			result.TextColor3 = won and Theme.color.good or Theme.color.bad
		end
		render()
	end)

	--[[ Only on the racing island, and only on a key: it is a bench, and a
	     bench that opens anywhere is a feature nobody asked for yet. ]]
	UserInputService.InputBegan:Connect(function(input, typing)
		if typing or input.KeyCode ~= Enum.KeyCode.L then
			return
		end
		local island = Islands.get("racing")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not island or not root then
			return
		end
		local flat = (root.Position - island.center) * Vector3.new(1, 0, 1)
		if flat.Magnitude > island.radius + 40 then
			return
		end
		card.Visible = not card.Visible
		if card.Visible then
			render()
		end
	end)

	render()
	return RaceLab
end

return RaceLab
