--[[
	DuelUI
	Throwing a punch, answering an offer, putting a brainrot up, and backing
	someone else's fight.

	FOUR CARDS AND ONE INPUT, all in one module because they are one flow: the
	offer becomes the wager becomes the fight, and a player is only ever
	looking at one of them. Splitting them across modules would mean four
	places that all have to agree about which is currently on screen.

	THE PUNCH IS PREDICTED, THE HIT IS NOT. Clicking swings the arm here
	immediately, through UI/Punch -- input that waits for a round trip feels
	broken -- but this module never says whether it CONNECTED. The server
	decides that, and the only evidence the attacker gets is the other player's
	health going down, the same evidence everyone else gets. Nothing here is
	authoritative and nothing here can be worth lying to.

	THE WAGER PICKER SHOWS TIERS, NOT INCOME. It is the tier that has to match,
	so the tier is what the rows are sorted and labelled by. Showing income
	would invite the reasonable-but-wrong assumption that a wager is matched on
	how much a brainrot earns -- see Shared/Duel for why it is not.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Duel = require(Shared.Duel)
local Brainrots = require(Shared.Brainrots)
local Rarity = require(Shared.Rarity)
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)
local Config = require(Shared.Config)

local Theme = require(script.Parent.Theme)
local Punch = require(script.Parent.Punch)

local DuelUI = {}

local player = Players.LocalPlayer

function DuelUI.init(ctx)
	local root = Theme.frame({
		name = "Duel",
		parent = ctx.gui,
		size = UDim2.fromOffset(420, 300),
		position = UDim2.new(0.5, 0, 1, -120),
		anchor = Vector2.new(0.5, 1),
		color = Theme.color.bg,
		transparency = 1,
	})
	root.Visible = false
	root.ZIndex = 40

	local card = Theme.frame({
		name = "Card",
		parent = root,
		size = UDim2.fromScale(1, 1),
		color = Theme.color.panel,
	})
	Theme.stroke(card, Theme.color.line, 3)
	Theme.padding(card, 14)
	local layout = Theme.list(card, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local title = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 26), font = Theme.font.bold,
		textSize = 22, align = Enum.TextXAlignment.Center, order = 1,
	})
	local body = Theme.label({
		parent = card, size = UDim2.new(1, 0, 0, 40), color = Theme.color.dim,
		textSize = 15, align = Enum.TextXAlignment.Center, order = 2,
	})
	body.TextWrapped = true

	--[[ The stake list lives between the copy and the buttons and is the only
	     part that changes height, so it is the only thing with AutomaticSize
	     -- letting every row size itself would make the card jump on each
	     state push. ]]
	local list = Theme.scroller({
		parent = card, size = UDim2.new(1, 0, 0, 140), order = 3,
	})
	local listLayout = Theme.list(list, 4)

	local buttons = Theme.frame({
		parent = card, size = UDim2.new(1, 0, 0, 38), order = 4, transparency = 1,
	})
	local buttonRow = Theme.list(buttons, 8, Enum.FillDirection.Horizontal)
	buttonRow.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local state = {
		duelId = nil,
		phase = nil,
		picked = {}, -- [uid] = true
	}

	local function clear(container)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	--[[ Declared before the trade window exists, so it dispatches through a
	     field the window fills in later rather than closing over something that
	     is not built yet. ]]
	local closeWager
	local function hide()
		root.Visible = false
		state.phase = nil
		state.mine = {}
		if closeWager then
			closeWager()
		end
	end

	-- ── the punch ───────────────────────────────────────────────────────────

	--[[
		Left click swings, unless the click was consumed by the interface.

		`processed` is the whole guard. Without it every click on the shop, the
		Mines board or this very card would also throw a punch -- which in a
		duel would mean opening the wager picker was itself an attack.
	]]
	local attack = Net.get("Attack")
	local lastSwing = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		--[[ Rate limited to the SERVER's cooldown, not to something shorter.
		     The server's limit is the one that counts, and a client that
		     predicts faster than the server accepts would animate swings that
		     never happened -- which is a worse lie than a dropped input. ]]
		local now = os.clock()
		if now - lastSwing < Config.PunchCooldown then
			return
		end
		lastSwing = now
		--[[ Swing first, ask second. The server will publish this same swing
		     to everyone else a round trip later; UI/Punch ignores the
		     attribute for the local player so it is not thrown twice. ]]
		Punch.swing(player.Character)
		attack:FireServer()
	end)

	-- ── the offer ───────────────────────────────────────────────────────────

	local function showOffer(payload)
		state.duelId = payload.id
		state.phase = "offer"
		root.Visible = true
		title.Text = "DUEL?"
		body.Text = ("%s is fighting back. Make it count — both of you put a brainrot up, winner takes it.")
			:format(payload.opponent or "They")
		clear(list)
		clear(buttons)

		Theme.button({
			parent = buttons, size = UDim2.fromOffset(150, 34), text = "FIGHT",
			color = Theme.color.good, order = 1,
		}).MouseButton1Click:Connect(function()
			ctx.remotes.DuelRespond:InvokeServer(true)
		end)
		Theme.button({
			parent = buttons, size = UDim2.fromOffset(150, 34), text = "NO THANKS",
			color = Theme.color.raised, order = 2,
		}).MouseButton1Click:Connect(function()
			ctx.remotes.DuelRespond:InvokeServer(false)
			hide()
		end)
	end

	-- ── the wager: a trade window ───────────────────────────────────────────

	--[[
		TWO GRIDS, BOTH LIVE, AND TWO ACCEPTS.

		The shape everybody already knows from trading: your offer on one side,
		theirs on the other, both assembled in the open, and nothing happens
		until both sides press ACCEPT. It replaced a one-sided picker where you
		submitted a stake and the other player could only take it or refuse --
		which meant you could never see what you were being offered while you
		decided what to offer.

		THE GRID IS DRAWN FROM THE SERVER'S PAYLOAD, never from what this client
		thinks it put down. `state.mine` exists only to build the next "set"
		message; every slot you can see came back from the server, which
		re-resolves each uid against the real inventory on every push. A slot
		showing a brainrot you have already sold is a slot somebody could accept
		a trade on.

		ANY CHANGE CLEARS BOTH ACCEPTS -- enforced on the server, shown here by
		the status flipping back to DECIDING. It is the rule that stops the
		classic swap: accept, wait for them to accept, change your offer in the
		gap.
	]]

	local wager = Theme.frame({
		name = "TradeWindow",
		parent = ctx.gui,
		size = UDim2.fromOffset(660, 390),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.color.bg,
	})
	Theme.stroke(wager, Theme.color.line, 3)
	wager.Visible = false
	wager.ZIndex = 45

	local wagerTitle = Theme.label({
		parent = wager, size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 8), font = Theme.font.bold, textSize = 22,
		align = Enum.TextXAlignment.Center, text = "DECIDING...",
	})
	local wagerNeed = Theme.label({
		parent = wager, size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 36), color = Theme.color.dim, textSize = 13,
		align = Enum.TextXAlignment.Center,
	})

	--[[ One side of the window. Built twice, mirrored, and the only difference
	     is whether its slots do anything when clicked. ]]
	local function buildSide(xScale, anchorX, mine)
		local panel = Theme.frame({
			parent = wager,
			size = UDim2.new(0.46, 0, 0, 268),
			position = UDim2.new(xScale, 0, 0, 60),
			anchor = Vector2.new(anchorX, 0),
			color = Theme.color.panel,
		})
		Theme.stroke(panel, Theme.color.line, 2)
		Theme.padding(panel, 10)

		local name = Theme.label({
			parent = panel, size = UDim2.new(1, 0, 0, 20), font = Theme.font.bold,
			textSize = 16, align = Enum.TextXAlignment.Center,
		})
		local status = Theme.label({
			parent = panel, size = UDim2.new(1, 0, 0, 16),
			position = UDim2.fromOffset(0, 20), textSize = 13,
			align = Enum.TextXAlignment.Center, color = Theme.color.gold,
			text = "DECIDING",
		})

		local grid = Theme.frame({
			parent = panel, size = UDim2.new(1, 0, 0, 186),
			position = UDim2.fromOffset(0, 40), transparency = 1,
		})
		local layout = Instance.new("UIGridLayout")
		--[[ Sized off the panel rather than in pixels, so the three columns stay
		     square whatever the window is scaled to. ]]
		layout.CellSize = UDim2.new(0.31, 0, 0, 58)
		layout.CellPadding = UDim2.new(0.015, 0, 0, 6)
		layout.FillDirectionMaxCells = 3
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid

		local slots = {}
		for i = 1, Duel.MaxStakeItems do
			local slot = Theme.button({
				parent = grid, order = i, color = Theme.color.tile,
				text = "", size = UDim2.fromScale(1, 1),
			})
			local glyph = Theme.label({
				parent = slot, size = UDim2.fromScale(1, 1), textSize = 26,
				font = Theme.font.bold, align = Enum.TextXAlignment.Center,
				text = mine and "+" or "", color = Theme.color.faint,
			})
			local label = Theme.label({
				parent = slot, size = UDim2.new(1, -6, 0, 30),
				position = UDim2.fromOffset(3, 4), textSize = 11,
				align = Enum.TextXAlignment.Center, text = "",
			})
			label.TextWrapped = true
			label.Visible = false
			--[[ The income sits UNDER the name rather than beside it. With the
			     matching rule gone this is the number the trade is judged on,
			     so it gets its own line instead of competing for one. ]]
			local rate = Theme.label({
				parent = slot, size = UDim2.new(1, -6, 0, 14),
				position = UDim2.new(0, 3, 1, -17), textSize = 11,
				font = Theme.font.medium, align = Enum.TextXAlignment.Center,
				color = Theme.color.gold, text = "",
			})
			rate.Visible = false
			slots[i] = { button = slot, glyph = glyph, label = label, rate = rate }
		end

		local total = Theme.label({
			parent = panel, size = UDim2.new(1, 0, 0, 18),
			position = UDim2.new(0, 0, 1, -18), color = Theme.color.dim,
			textSize = 13, align = Enum.TextXAlignment.Left,
		})

		return { panel = panel, name = name, status = status, slots = slots, total = total }
	end

	local sideMine = buildSide(0.02, 0, true)
	local sideTheirs = buildSide(0.98, 1, false)

	local wagerButtons = Theme.frame({
		parent = wager, size = UDim2.new(1, 0, 0, 36),
		position = UDim2.new(0, 0, 1, -46), transparency = 1,
	})
	local wagerRow = Theme.list(wagerButtons, 10, Enum.FillDirection.Horizontal)
	wagerRow.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local acceptButton = Theme.button({
		parent = wagerButtons, size = UDim2.fromOffset(150, 34), text = "ACCEPT",
		color = Theme.color.good, order = 1,
	})
	local declineButton = Theme.button({
		parent = wagerButtons, size = UDim2.fromOffset(150, 34), text = "DECLINE",
		color = Theme.color.bad, order = 2,
	})

	-- ── the picker that fills a slot ────────────────────────────────────────

	local picker = Theme.frame({
		parent = wager, size = UDim2.new(0.7, 0, 0, 250),
		position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
		color = Theme.color.panel,
	})
	Theme.stroke(picker, Theme.color.line, 3)
	Theme.padding(picker, 10)
	picker.Visible = false
	picker.ZIndex = 50
	Theme.label({
		parent = picker, size = UDim2.new(1, 0, 0, 22), font = Theme.font.bold,
		textSize = 16, align = Enum.TextXAlignment.Center, text = "PUT ONE UP",
	})
	local pickerList = Theme.scroller({
		parent = picker, size = UDim2.new(1, 0, 1, -58),
		position = UDim2.fromOffset(0, 26),
	})
	Theme.list(pickerList, 4)
	local pickerClose = Theme.button({
		parent = picker, size = UDim2.new(1, 0, 0, 26), text = "CANCEL",
		position = UDim2.new(0, 0, 1, -26), color = Theme.color.raised,
	})

	--[[ The uids this client currently has in its grid. Rebuilt from the
	     server's payload on every push, so it can never drift from what the
	     server believes is staked. ]]
	state.mine = {}

	local function sendOffer()
		local reply = ctx.remotes.DuelWager:InvokeServer("set", state.mine)
		if reply and not reply.ok then
			ctx.notify(reply.err or "That offer was refused.", "info")
		end
	end

	local function openPicker()
		picker.Visible = true
		for _, child in ipairs(pickerList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local staked = {}
		for _, uid in ipairs(state.mine) do
			staked[uid] = true
		end

		local items = {}
		for _, item in ipairs(ctx.state.inventory or {}) do
			local char = Brainrots.get(item.charId)
			--[[ Already-staked uids are filtered out rather than shown greyed:
			     the list is what you can still add, and a row that refuses to
			     do anything is worse than a row that is not there. ]]
			if char and not staked[item.uid] then
				table.insert(items, { item = item, char = char, tier = Rarity.get(char.tier) })
			end
		end
		table.sort(items, function(x, y)
			if x.tier.index ~= y.tier.index then
				return x.tier.index > y.tier.index
			end
			return (x.item.uid or "") < (y.item.uid or "")
		end)

		for order, entry in ipairs(items) do
			local row = Theme.button({
				parent = pickerList, size = UDim2.new(1, -6, 0, 28), order = order,
				color = Theme.color.tile, text = "",
			})
			Theme.label({
				parent = row, size = UDim2.new(1, -14, 1, 0),
				position = UDim2.fromOffset(10, 0), textSize = 13,
				color = entry.tier.color,
				text = ("%s  ·  %s"):format(
					Economy.displayName(entry.item.charId, entry.item.variantId),
					entry.char.tier),
			})
			row.MouseButton1Click:Connect(function()
				if #state.mine >= Duel.MaxStakeItems then
					ctx.notify(("At most %d brainrots."):format(Duel.MaxStakeItems), "info")
					return
				end
				table.insert(state.mine, entry.item.uid)
				picker.Visible = false
				sendOffer()
			end)
		end
	end

	pickerClose.MouseButton1Click:Connect(function()
		picker.Visible = false
	end)

	for index, slot in ipairs(sideMine.slots) do
		slot.button.MouseButton1Click:Connect(function()
			--[[ A filled slot empties, an empty slot opens the picker. One
			     control, and which it is is obvious from what is in it. ]]
			if state.mine[index] then
				table.remove(state.mine, index)
				sendOffer()
			else
				openPicker()
			end
		end)
	end

	acceptButton.MouseButton1Click:Connect(function()
		local reply = ctx.remotes.DuelWager:InvokeServer("accept")
		if reply and not reply.ok then
			ctx.notify(reply.err or "Cannot accept yet.", "info")
		end
	end)
	declineButton.MouseButton1Click:Connect(function()
		local reply = ctx.remotes.DuelWager:InvokeServer("cancel")
		if reply and not reply.ok then
			ctx.notify(reply.err or "Too late.", "info")
		end
	end)

	local function paintSide(side, rows, income, accepted, who)
		side.name.Text = who or "?"
		side.status.Text = accepted and "ACCEPTED" or "DECIDING"
		side.status.TextColor3 = accepted and Theme.color.good or Theme.color.gold
		side.total.Text = ("%s  total"):format(Format.rate(income or 0))
		for i, slot in ipairs(side.slots) do
			local row = rows and rows[i]
			if row then
				slot.glyph.Visible = false
				slot.label.Visible = true
				slot.rate.Visible = true
				slot.label.Text = row.name or row.tier
				slot.label.TextColor3 = Rarity.get(row.tier).color
				slot.rate.Text = Format.rate(row.income or 0)
				slot.button.BackgroundColor3 = Theme.color.raised
			else
				slot.glyph.Visible = true
				slot.label.Visible = false
				slot.rate.Visible = false
				slot.button.BackgroundColor3 = Theme.color.tile
			end
			slot.button:SetAttribute("BaseColor", slot.button.BackgroundColor3)
		end
	end

	local function showWager(payload)
		state.phase = "wager"
		root.Visible = false -- the offer card and the window never share the screen
		wager.Visible = true

		--[[ Rebuilt from the server rather than trusted locally -- see the note
		     at the top of this section. ]]
		state.mine = {}
		for _, row in ipairs(payload.yourRows or {}) do
			table.insert(state.mine, row.uid)
		end

		paintSide(sideMine, payload.yourRows, payload.yourIncome,
			payload.youAccepted, payload.you)
		paintSide(sideTheirs, payload.theirRows, payload.theirIncome,
			payload.theyAccepted, payload.opponent)

		wagerTitle.Text = (payload.youAccepted and payload.theyAccepted)
			and "STARTING..." or "DECIDING..."

		--[[ No fairness line, because there is no fairness rule -- see
		     Shared/Duel. What is left to say is what the stakes are, and the
		     income under each brainrot is what tells you whether it is worth
		     it. ]]
		local ready = #(payload.yourRows or {}) > 0 and #(payload.theirRows or {}) > 0
		if ready then
			wagerNeed.Text = "both accept and the fight starts. winner takes the other's stake."
			wagerNeed.TextColor3 = Theme.color.good
		else
			wagerNeed.Text = "put a brainrot up. winner takes the other's stake."
			wagerNeed.TextColor3 = Theme.color.dim
		end
	end

	closeWager = function()
		wager.Visible = false
		picker.Visible = false
	end

	-- ── the arena's sky ─────────────────────────────────────────────────────

	--[[
		THE ARENA HAS ITS OWN SKY, and only the two fighters see it.

		Lighting is global. Swapping it on the server would put the arena's
		night over the whole game -- the street, the shop, the islands, every
		player who is not in the duel. Done here instead, on the client, which
		does not replicate: the same trick Braziers uses to light shared
		geometry for one player.

		THE ORIGINAL IS CAPTURED ON THE WAY IN, not written down as constants.
		Reading the properties back off the live Sky means the restore returns
		whatever the game actually had, so a future change to the daytime sky
		does not leave duellists permanently under yesterday's.

		EVERY Sky IN LIGHTING, NOT THE FIRST ONE FOUND. The supplied map ships
		with TWO -- rbxassetid://6444884337 and rbxassetid://13107325341 -- and
		Roblox renders one of them without saying which. This used
		FindFirstChildOfClass, which returned 6444884337 while the sky actually
		on screen was the other one, so the swap ran, reported success, and
		changed nothing anybody could see. Writing to all of them is correct
		whichever renders, and stays correct if the map ever ships three.
	]]
	local Lighting = game:GetService("Lighting")
	local skyBefore = nil

	local function skies()
		local found = {}
		for _, d in ipairs(Lighting:GetChildren()) do
			if d:IsA("Sky") then
				table.insert(found, d)
			end
		end
		return found
	end

	local function enterArenaSky()
		if skyBefore then
			return -- already swapped
		end
		local found = skies()
		if #found == 0 then
			return
		end
		--[[ Keyed by the Sky itself, so a restore puts each one back to its
		     own values rather than to whatever the last one happened to
		     have. ]]
		skyBefore = {}
		for _, sky in ipairs(found) do
			local saved = {}
			for prop, value in pairs(Config.ArenaSky) do
				local ok, current = pcall(function()
					return sky[prop]
				end)
				if ok then
					saved[prop] = current
					pcall(function()
						sky[prop] = value
					end)
				end
			end
			skyBefore[sky] = saved
		end
	end

	local function leaveArenaSky()
		if not skyBefore then
			return
		end
		local restore = skyBefore
		--[[ Cleared BEFORE the writes, so a failure partway through cannot
		     leave this thinking a swap is still owed and refuse the next one. ]]
		skyBefore = nil
		for sky, saved in pairs(restore) do
			if sky.Parent then
				for prop, value in pairs(saved) do
					pcall(function()
						sky[prop] = value
					end)
				end
			end
		end
	end

	-- ── lock on ─────────────────────────────────────────────────────────────

	--[[
		WHILE A DUEL IS RUNNING, YOU ALWAYS FACE YOUR OPPONENT.

		This is the whole of the aim assist, and it works because of where the
		server measures a hit from: CombatService resolves the punch cone
		against the character's own LookVector. Point the character at the
		other player and every swing is already aimed -- nothing about the
		server's hit test has to be loosened, so a punch still has to be in
		range and in front, it is simply no longer possible to be facing the
		wrong way by accident.

		AUTOROTATE GOES OFF, because the humanoid turns the character toward
		whatever direction it is walking and would fight this every frame. With
		it off the character strafes instead of turning, which is what lock-on
		feels like in anything else that has it.

		AN ALIGNORIENTATION, NOT A CFRAME WRITE. Writing the root's CFrame every
		frame fights the physics solver and reads as jitter -- Flight already
		learned this and drives its flying pose the same way. The constraint is
		handed a target and the solver gets there smoothly.

		YAW ONLY. The target is flattened to the character's own height before
		it is looked at, or standing on a platform beside a player who is
		mid-jump would tilt you at the sky.

		IT IS NOT A CAMERA LOCK. The camera stays yours -- you can look wherever
		you like while the character keeps its guard up. A camera that snaps to
		a target is a much bigger change in feel, and this is the half that
		makes punches land.
	]]
	local lock = nil

	local function stopLock()
		if not lock then
			return
		end
		local held = lock
		lock = nil
		if held.conn then
			held.conn:Disconnect()
		end
		--[[ AutoRotate is restored before the constraint goes, so there is no
		     frame where nothing is steering the character. ]]
		if held.humanoid and held.humanoid.Parent then
			held.humanoid.AutoRotate = true
		end
		for _, inst in ipairs({ held.orientation, held.attachment }) do
			if inst and inst.Parent then
				inst:Destroy()
			end
		end
	end

	local function startLock(opponentId)
		stopLock()
		local opponent = opponentId and Players:GetPlayerByUserId(opponentId)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not opponent or not humanoid or not root then
			return
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = "LockAttachment"
		attachment.Parent = root

		local orientation = Instance.new("AlignOrientation")
		orientation.Name = "LockOrientation"
		orientation.Attachment0 = attachment
		orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orientation.RigidityEnabled = false
		--[[
			INFINITE TORQUE, AND THE NUMBER MATTERS.

			This shipped at 60000, copied from Flight's 90000, and the
			character did not turn AT ALL -- measured over 1.2 seconds it stayed
			exactly 180 degrees off target. Flight gets away with less because
			its player is airborne; a grounded Humanoid holds its own
			orientation hard enough to win against any finite torque worth
			naming, so the torque is taken out of the equation entirely and the
			SPEED is set by Responsiveness alone.

			35 turns a full 180 in 0.35s. Measured across the range: 15 takes
			0.77s (sluggish -- an opponent can circle you), 60 takes 0.20s
			(snaps hard enough to read as a glitch when they dash past). 35 is
			quick enough to keep a dashing opponent in front and slow enough to
			look like the character did the turning.
		]]
		orientation.MaxTorque = math.huge
		orientation.Responsiveness = 35
		orientation.CFrame = root.CFrame.Rotation
		orientation.Parent = root

		humanoid.AutoRotate = false

		lock = { humanoid = humanoid, attachment = attachment, orientation = orientation }
		lock.conn = RunService.RenderStepped:Connect(function()
			if not lock or not root.Parent or not humanoid.Parent then
				stopLock()
				return
			end
			local theirChar = opponent.Character
			local theirRoot = theirChar and theirChar:FindFirstChild("HumanoidRootPart")
			if not theirRoot then
				return -- they died or are respawning; hold the last facing
			end
			--[[ Flattened to our own height -- see the header. ]]
			local at = Vector3.new(theirRoot.Position.X, root.Position.Y, theirRoot.Position.Z)
			if (at - root.Position).Magnitude < 0.5 then
				return -- standing inside each other; any facing is arbitrary
			end
			orientation.CFrame = CFrame.lookAt(root.Position, at).Rotation
		end)
	end

	-- ── the fight ───────────────────────────────────────────────────────────

	local fightCard = Theme.frame({
		name = "DuelClock",
		parent = ctx.gui,
		size = UDim2.fromOffset(230, 62),
		position = UDim2.new(0.5, 0, 0, 96),
		anchor = Vector2.new(0.5, 0),
		color = Theme.color.panel,
	})
	Theme.stroke(fightCard, Theme.color.line, 3)
	fightCard.Visible = false
	fightCard.ZIndex = 40
	local clockLabel = Theme.label({
		parent = fightCard, size = UDim2.new(1, 0, 0, 32),
		position = UDim2.fromOffset(0, 4), font = Theme.font.bold, textSize = 30,
		align = Enum.TextXAlignment.Center,
	})
	local clockSub = Theme.label({
		parent = fightCard, size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 36), color = Theme.color.dim, textSize = 13,
		align = Enum.TextXAlignment.Center, text = "most health wins",
	})

	local fightEndsAt = nil
	RunService.RenderStepped:Connect(function()
		if not fightEndsAt then
			return
		end
		local left = math.max(fightEndsAt - os.clock(), 0)
		clockLabel.Text = ("%.1f"):format(left)
		clockLabel.TextColor3 = left <= 5 and Theme.color.bad or Theme.color.text
		if left <= 0 then
			fightEndsAt = nil
			fightCard.Visible = false
		end
	end)

	-- ── backing someone else's fight ────────────────────────────────────────

	local betCard = Theme.frame({
		name = "DuelBook",
		parent = ctx.gui,
		size = UDim2.fromOffset(250, 150),
		position = UDim2.new(1, -18, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.color.panel,
	})
	Theme.stroke(betCard, Theme.color.line, 3)
	Theme.padding(betCard, 12)
	local betLayout = Theme.list(betCard, 6)
	betLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	betCard.Visible = false
	betCard.ZIndex = 40

	local function showBook(payload)
		clear(betCard)
		betCard.Visible = true

		Theme.label({
			parent = betCard, size = UDim2.new(1, 0, 0, 20), font = Theme.font.bold,
			textSize = 16, align = Enum.TextXAlignment.Center, order = 1,
			text = "DUEL — BACK ONE",
		})
		Theme.label({
			parent = betCard, size = UDim2.new(1, 0, 0, 16), color = Theme.color.dim,
			textSize = 12, align = Enum.TextXAlignment.Center, order = 2,
			text = ("closes with %ds left"):format(payload.closeAt or Duel.BetCloseAt),
		})

		--[[ The stake is fixed at the minimum rather than typed. A field would
		     need validating, a keyboard on mobile, and somewhere to show the
		     error -- for a side bet on a thirty second fight that is more
		     interface than the decision deserves. ]]
		for order, side in ipairs({ "a", "b" }) do
			local name = side == "a" and payload.a or payload.b
			Theme.button({
				parent = betCard, size = UDim2.new(1, 0, 0, 32), order = 2 + order,
				text = ("%s  ·  %s"):format(name or "?", Format.money(Duel.MinSpectatorBet)),
				color = Theme.color.tile, textSize = 13,
			}).MouseButton1Click:Connect(function()
				local reply = ctx.remotes.DuelBet:InvokeServer(
					payload.id, side, Duel.MinSpectatorBet)
				if reply and reply.ok then
					ctx.notify(("Backed %s."):format(name), "good")
					betCard.Visible = false
				elseif reply then
					ctx.notify(reply.err or "Bet refused.", "info")
				end
			end)
		end
	end

	-- ── wiring ──────────────────────────────────────────────────────────────

	--[[ A respawn replaces the character, and with it the attachment, the
	     constraint and the humanoid whose AutoRotate was turned off. The lock
	     is dropped rather than re-pointed: dying in a duel ends it anyway, so
	     there is nothing left to aim at. ]]
	player.CharacterRemoving:Connect(stopLock)

	Net.get("DuelOffer").OnClientEvent:Connect(showOffer)

	Net.get("DuelState").OnClientEvent:Connect(function(payload)
		if payload.phase == "closed" then
			hide()
			fightEndsAt = nil
			fightCard.Visible = false
			--[[ Unconditional. Every way a duel ends comes through here,
			     including the ones that never reached the arena, and putting
			     the sky back when it was never taken is a no-op. ]]
			leaveArenaSky()
			stopLock()
			return
		end
		state.duelId = payload.id
		if payload.phase == "offer" then
			--[[ Already answered: the card would otherwise sit there offering
			     buttons that do nothing while the other side decides. ]]
			if payload.youAccepted then
				title.Text = "WAITING"
				body.Text = ("Waiting for %s to accept."):format(payload.opponent)
				clear(buttons)
			end
		elseif payload.phase == "wager" then
			showWager(payload)
		elseif payload.phase == "fight" then
			hide()
			fightEndsAt = os.clock() + Duel.Seconds
			fightCard.Visible = true
			enterArenaSky()
			startLock(payload.opponentId)
		end
	end)

	Net.get("DuelBoard").OnClientEvent:Connect(function(payload)
		if payload.phase == "open" then
			--[[ Not shown to the two people in it -- they have a clock, and a
			     betting card would be an invitation to bet on themselves. ]]
			if payload.aId ~= player.UserId and payload.bId ~= player.UserId then
				showBook(payload)
			end
		elseif payload.phase == "closed_book" or payload.phase == "closed" then
			betCard.Visible = false
		elseif payload.phase == "result" then
			betCard.Visible = false
			if payload.draw then
				ctx.notify("Duel ended in a draw.", "info")
			elseif payload.winner then
				ctx.notify(("%s%s won the duel%s."):format(
					payload.knockout and "Knockout — " or "",
					payload.winner,
					payload.took and (" and took " .. payload.took) or ""), "info")
			end
		end
	end)

	return {
		hide = hide,
	}
end

return DuelUI
