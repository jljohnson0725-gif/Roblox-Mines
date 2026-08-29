--[[
	Fx
	The over-the-top part. Camera shake, screen flash, confetti, bloom, and the
	takeover banner -- all scaled by the drop's rarity via Sounds.Spectacle.

	Nothing here is on for Common/Uncommon. If every drop got a celebration, a
	Legendary wouldn't feel like anything, and Commons are ~64% of drops at low
	multipliers. The spectacle earns its impact by being rare.

	Lighting effects are created CLIENT-SIDE, which means they're local to this
	player and never replicate -- one person's Secret doesn't bloom everyone
	else's screen. The server-wide announcement is what other players see.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Sounds)
local Rarity = require(Shared.Rarity)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)

local Fx = {}

local SHAKE_DECAY = 3.2

function Fx.init(ctx)
	local fx = {}

	-- ── layers ──────────────────────────────────────────────────────────────
	-- Above every panel. ZIndexBehavior on the ScreenGui is Sibling, so these
	-- sit over the Mines UI without needing to be its child.

	local layer = Instance.new("Frame")
	layer.Name = "FxLayer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 100
	layer.Active = false
	layer.Parent = ctx.gui

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 101
	flash.Parent = layer

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 100
	vignette.Parent = layer

	local confettiHost = Instance.new("Frame")
	confettiHost.Name = "Confetti"
	confettiHost.Size = UDim2.fromScale(1, 1)
	confettiHost.BackgroundTransparency = 1
	confettiHost.ZIndex = 103
	confettiHost.Parent = layer

	-- ── camera shake ────────────────────────────────────────────────────────

	local shake = 0

	RunService:BindToRenderStep("BrainrotFxShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shake <= 0 then
			return
		end
		shake = math.max(0, shake - dt * SHAKE_DECAY)

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		-- Applied AFTER the camera scripts run, so it isn't overwritten.
		local a = shake * 0.02
		camera.CFrame = camera.CFrame
			* CFrame.Angles(
				(math.random() - 0.5) * a,
				(math.random() - 0.5) * a,
				(math.random() - 0.5) * a * 1.6
			)
	end)

	-- ── pieces ──────────────────────────────────────────────────────────────

	local function doFlash(color, strength, duration)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 1 - strength
		TweenService:Create(flash, TweenInfo.new(duration or 0.45, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		}):Play()
	end

	local function doVignette(duration)
		vignette.BackgroundTransparency = 0.45
		local tween = TweenService:Create(vignette, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		})
		tween:Play()
	end

	local function doConfetti(count, color)
		local palette = {
			color,
			color:Lerp(Color3.new(1, 1, 1), 0.5),
			Theme.color.gold,
			Color3.fromRGB(255, 255, 255),
		}

		for _ = 1, count do
			local piece = Instance.new("Frame")
			piece.Size = UDim2.fromOffset(math.random(5, 11), math.random(8, 16))
			piece.Position = UDim2.fromScale(0.5, 0.5)
			piece.AnchorPoint = Vector2.new(0.5, 0.5)
			piece.BackgroundColor3 = palette[math.random(1, #palette)]
			piece.BorderSizePixel = 0
			piece.Rotation = math.random(0, 360)
			piece.ZIndex = 103
			piece.Parent = confettiHost

			local angle = math.random() * math.pi * 2
			local distance = 0.18 + math.random() * 0.55
			local target = UDim2.fromScale(
				0.5 + math.cos(angle) * distance,
				0.5 + math.sin(angle) * distance * 0.75
			)
			local flightTime = 0.65 + math.random() * 0.75

			TweenService:Create(piece, TweenInfo.new(flightTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = target,
				Rotation = piece.Rotation + math.random(-360, 360),
				BackgroundTransparency = 1,
			}):Play()

			Debris:AddItem(piece, flightTime + 0.1)
		end
	end

	local function doLighting(spec, tierColor, duration)
		local effects = {}

		if spec.bloom then
			local bloom = Instance.new("BloomEffect")
			bloom.Intensity = 0
			bloom.Size = 40
			bloom.Threshold = 0.85
			bloom.Parent = Lighting
			table.insert(effects, { inst = bloom, prop = "Intensity", peak = 2.2 })
		end

		if spec.saturate then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Saturation = 0
			cc.Contrast = 0
			cc.TintColor = tierColor
			cc.Parent = Lighting
			table.insert(effects, { inst = cc, prop = "Saturation", peak = 0.65 })
		end

		for _, entry in ipairs(effects) do
			local up = TweenService:Create(entry.inst, TweenInfo.new(0.18), { [entry.prop] = entry.peak })
			up:Play()
			task.delay(duration * 0.45, function()
				if entry.inst.Parent then
					local down = TweenService:Create(
						entry.inst,
						TweenInfo.new(duration * 0.55),
						{ [entry.prop] = 0 }
					)
					down:Play()
					down.Completed:Once(function()
						entry.inst:Destroy()
					end)
				end
			end)
		end
	end

	local function doBanner(headline, name, income, tierColor, spec)
		local banner = Instance.new("Frame")
		banner.Name = "Banner"
		banner.Size = UDim2.fromOffset(560, 150)
		banner.Position = UDim2.fromScale(0.5, 0.36)
		banner.AnchorPoint = Vector2.new(0.5, 0.5)
		banner.BackgroundColor3 = Theme.color.panel
		banner.BackgroundTransparency = 0.08
		banner.BorderSizePixel = 0
		banner.ZIndex = 104
		banner.Parent = layer
		Theme.corner(banner, 16)
		Theme.stroke(banner, tierColor, 3, 0)

		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = banner

		local headlineLabel = Theme.label({
			parent = banner,
			text = headline,
			font = Theme.font.black,
			textSize = spec.level >= 4 and 40 or 32,
			color = tierColor,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 52),
			position = UDim2.fromOffset(0, 16),
		})
		headlineLabel.ZIndex = 105
		headlineLabel.TextStrokeTransparency = 0.5

		local nameLabel = Theme.label({
			parent = banner,
			text = name,
			font = Theme.font.bold,
			textSize = 22,
			color = Theme.color.text,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, -24, 0, 30),
			position = UDim2.fromOffset(12, 70),
		})
		nameLabel.ZIndex = 105
		nameLabel.TextScaled = false

		local incomeLabel = Theme.label({
			parent = banner,
			text = income,
			font = Theme.font.black,
			textSize = 20,
			color = Theme.color.good,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 26),
			position = UDim2.fromOffset(0, 104),
		})
		incomeLabel.ZIndex = 105

		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()

		task.delay(spec.hold or 1.5, function()
			if not banner.Parent then
				return
			end
			local out = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Scale = 0.85 })
			out:Play()
			for _, item in ipairs({ banner, headlineLabel, nameLabel, incomeLabel }) do
				if item:IsA("Frame") then
					TweenService:Create(item, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
				else
					TweenService:Create(item, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
				end
			end
			task.wait(0.3)
			banner:Destroy()
		end)
	end

	-- ── public ──────────────────────────────────────────────────────────────

	--[[ Celebrate a drop the local player just found. ]]
	function fx.drop(drop)
		local tierName = drop.tier
		local tier = Rarity.get(tierName)
		local spec = Sounds.spectacleFor(tierName)

		--[[ The sound is Sounds' business, not Fx's. This used to branch on
		     spec.level and pick a cue, which is how the same drop ended up
		     announced differently depending on which of three call sites got
		     there first. ]]
		Sounds.sting(tierName)

		if spec.level <= 0 then
			return
		end
		Sounds.play("tileDrop", 1 + spec.level * 0.08)

		shake = math.max(shake, spec.shake)
		doFlash(tier.color, spec.flash, 0.3 + spec.level * 0.08)
		doConfetti(spec.confetti, tier.color)
		doLighting(spec, tier.color, spec.hold)

		if spec.vignette then
			doVignette(spec.hold)
		end

		doBanner(
			string.upper(tierName) .. "!",
			Economy.displayName(drop.charId, drop.variantId),
			Format.rate(drop.income or Economy.incomeOf(drop.charId, drop.variantId)),
			tier.color,
			spec
		)
	end

	--[[
		THE SAME SPECTACLE, FOR SOMETHING THAT IS NOT A DROP.

		fx.drop above is the shake/flash/confetti/lighting/banner sequence, and
		it was welded to a brainrot: it takes a `drop`, looks up a Rarity tier
		and reads the tier's colour and name. The saddle is the biggest moment in
		the first chapter and is none of those things -- no charId, no tier, no
		income -- so it either got a toast that scrolls away in 2.5 seconds or
		this had to come apart.

		Extracted rather than copied. A second implementation of the same
		sequence is how the drop celebration ended up announced three different
		ways before, which the comment in fx.drop already records.
	]]
	function fx.celebrate(opts)
		local spec = opts.spec or Sounds.spectacleFor("Mythic")
		local color = opts.color or Theme.color.gold

		--[[ A NAMED CUE, not a raw id. Sounds.Library owns volume, speed and
		     which bus it lands on; a bare id here would be a sound nobody could
		     find in the mix and nobody could re-balance. ]]
		if opts.sound then
			Sounds.play(opts.sound)
		end

		shake = math.max(shake, spec.shake)
		doFlash(color, spec.flash, 0.3 + spec.level * 0.08)
		doConfetti(spec.confetti, color)
		doLighting(spec, color, spec.hold)
		if spec.vignette then
			doVignette(spec.hold)
		end
		doBanner(opts.headline or "", opts.name or "", opts.sub or "", color, spec)
	end

	--[[ Somebody ELSE hit a Mythic or Secret. Loud, but not screen-shaking. ]]
	function fx.announce(payload)
		local tier = Rarity.get(payload.tier)
		local spec = Sounds.spectacleFor(payload.tier)

		Sounds.sting(payload.tier, 0.55)
		doFlash(tier.color, spec.flash * 0.3, 0.5)

		local verb = payload.lost and "LOST" or "FOUND"
		ctx.notify(
			string.format(
				"%s %s a %s — %s",
				payload.playerName,
				verb,
				string.upper(payload.tier),
				Economy.displayName(payload.charId, payload.variantId)
			),
			payload.lost and "bad" or "good"
		)
	end

	function fx.shakeBy(amount)
		shake = math.max(shake, amount)
	end

	function fx.flashColor(color, strength, duration)
		doFlash(color, strength, duration)
	end

	return fx
end

return Fx
