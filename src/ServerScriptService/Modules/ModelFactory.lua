--[[
	ModelFactory
	Builds the thing that stands on a pad.

	Placeholder-first by design: with no art at all this produces a readable
	blocky figure tinted by character + variant, so the game is playable the
	moment you paste it in.

	To use real art: put your models in ReplicatedStorage/BrainrotModels, each
	named exactly the character's `id` from Brainrots.lua. This module picks them
	up automatically and applies the variant tint. No code change.

	The generated meshes get there via assets/meshes.json + build_place.py rather
	than being placed by hand, so a rebuild can't wipe them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Brainrots = require(Shared.Brainrots)
local Variants = require(Shared.Variants)
local Rarity = require(Shared.Rarity)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local ModelFactory = {}

ModelFactory.TAG = Config.BrainrotTag

--[[ How far the variant shell sits outside the textured mesh. Big enough to
     never z-fight, small enough that it doesn't read as a separate object. ]]
local SHELL_SCALE = 1.015

local function part(name, size, cf, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	Blocky stand-in figure, ~5.6 studs tall so it clears the shelf above.
	Origin (0,0,0) is between its feet, and it FACES +Z -- players approach a
	plot from the front, and a shelf of characters showing you their backs is
	worse than no shelf at all.
]]
local function buildPlaceholder(char)
	local model = Instance.new("Model")
	model.Name = char.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root

	local c = char.color
	local dark = c:Lerp(Color3.new(0, 0, 0), 0.25)

	part("LegL", Vector3.new(0.85, 1.5, 0.85), CFrame.new(-0.52, 0.75, 0), dark, model)
	part("LegR", Vector3.new(0.85, 1.5, 0.85), CFrame.new(0.52, 0.75, 0), dark, model)
	part("Torso", Vector3.new(2.25, 2.4, 1.5), CFrame.new(0, 2.7, 0), c, model)
	part("ArmL", Vector3.new(0.7, 1.95, 0.7), CFrame.new(-1.475, 2.925, 0), c, model)
	part("ArmR", Vector3.new(0.7, 1.95, 0.7), CFrame.new(1.475, 2.925, 0), c, model)
	part("Head", Vector3.new(1.8, 1.65, 1.65), CFrame.new(0, 4.725, 0), c:Lerp(Color3.new(1, 1, 1), 0.12), model)

	-- eyes on the +Z face, so it looks at whoever walks up
	local white = Color3.fromRGB(250, 250, 250)
	local eyeL = part("EyeL", Vector3.new(0.38, 0.38, 0.1), CFrame.new(-0.41, 4.95, 0.83), white, model)
	local eyeR = part("EyeR", Vector3.new(0.38, 0.38, 0.1), CFrame.new(0.41, 4.95, 0.83), white, model)
	eyeL.Material = Enum.Material.SmoothPlastic
	eyeR.Material = Enum.Material.SmoothPlastic
	for _, eye in ipairs({ eyeL, eyeR }) do
		eye:SetAttribute("NoTint", true)
		local pupil = part("Pupil", Vector3.new(0.17, 0.17, 0.08), eye.CFrame * CFrame.new(0, 0, 0.05), Color3.fromRGB(20, 20, 20), model)
		pupil:SetAttribute("NoTint", true)
	end

	return model
end

--[[
	Bounding box in the model's own frame, as (bottomY, topY, widest).
	Everything below anchors off this instead of assuming a build origin, so
	imported models of any size get their aura and nameplate in the right place.
]]
local function extents(model)
	local cf, size = model:GetBoundingBox()
	local centre = cf.Position
	return {
		bottom = centre.Y - size.Y / 2,
		top = centre.Y + size.Y / 2,
		widest = math.max(size.X, size.Z),
		centre = centre,
	}
end

--[[ Glowing disc under the figure, coloured by tier -- cheap rarity read. ]]
local function addAura(model, tier, ext)
	local centre = ext.centre
	local diameter = math.max(ext.widest * 1.2, 3)

	local aura = Instance.new("Part")
	aura.Name = "Aura"
	aura.Shape = Enum.PartType.Cylinder
	aura.Size = Vector3.new(0.15, diameter, diameter)
	aura.CFrame = CFrame.new(centre.X, ext.bottom + 0.1, centre.Z) * CFrame.Angles(0, 0, math.rad(90))
	aura.Color = tier.color
	aura.Material = Enum.Material.Neon
	aura.Transparency = 0.55
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura:SetAttribute("NoTint", true)
	aura.Parent = model
	return aura
end

local function addLabel(model, charId, variantId, ext)
	--[[ Kept, not discarded inline: the plate needs the character's own name and
	     tier as well as the tier's colour. ]]
	local char = Brainrots.get(charId)
	local tier = Rarity.get(char.tier)
	local income = Economy.incomeOf(charId, variantId)
	local centre = ext.centre

	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(centre.X, ext.top + 1, centre.Z)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor:SetAttribute("NoTint", true)
	anchor.Parent = model

	--[[
		THREE LINES: rarity, name, rent -- what it is, which one, what it pays,
		in the order the eye wants them. It was two before, with the variant
		folded into the name, which meant the thing players actually compare
		(the tier) was the hardest part to read.

		Full-opacity strokes, not the 0.4 and 0.5 these had. The outline is the
		entire reason bright text stays legible against a bright plot floor, and
		a half-transparent one on green grass is barely an outline at all.
	]]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(210, 76)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.9, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 110
	billboard.Parent = anchor

	local function line(order, text, color, font, cap)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1 / 3, 0)
		label.Position = UDim2.new(0, 0, (order - 1) / 3, 0)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = billboard
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = cap
		limit.Parent = label
	end

	--[[ Both of these are keyed BY name in their tables and carry no `name`
	     field, so tier.name and variant.name are nil. The id is the name. ]]
	local prefix = (variantId and variantId ~= "Normal") and (variantId .. " ") or ""
	local variant = Variants.get(variantId)
	line(1, prefix .. char.tier, (variant and variant.color) or tier.color,
		Enum.Font.GothamBlack, 16)
	line(2, char.name, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack, 19)
	line(3, Format.rate(income), Color3.fromRGB(96, 255, 128),
		Enum.Font.GothamBlack, 17)
end

--[[
	Build a display model for one owned brainrot.
	Returns a Model whose pivot sits at its feet -- PivotTo a pad surface.
]]
function ModelFactory.build(charId, variantId)
	local char = Brainrots.get(charId)
	if not char then
		return nil
	end
	local variant = Variants.get(variantId)
	local tier = Rarity.get(char.tier)

	--[[
		Two sources: a Model in ReplicatedStorage.BrainrotModels named after the
		character, or the block placeholder.

		That library is baked into the place by tools/build_place.py from
		assets/meshes.json, because MeshPart.MeshId is NOT writable from a
		runtime script -- a MeshPart has to already exist and be cloned. A
		half-filled library is fine; anything missing falls through to blocks.
	]]
	local model
	local library = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local source = library and library:FindFirstChild(charId)

	if source then
		model = source:Clone()

		--[[
			Generated models ship two copies of the same geometry: Body carries
			the generated paint job, BodyPlain is the same mesh with no texture.

			For a coloured variant, BodyPlain becomes a SHELL -- tinted, slightly
			enlarged and semi-transparent, sitting over the textured original.

			Painting the plain copy solid was the obvious approach and it's what
			made Gold and Diamond unreadable: a flat mesh has no face, no suit, no
			sunglasses, just a coloured silhouette. Tinting the textured mesh
			directly is not an option either -- MeshPart.Color does nothing once a
			TextureID is set, verified in Studio with four identically-rendered
			rats. The shell is what gives both: variant colour across the whole
			silhouette, original art still legible underneath.
		]]
		local body = model:FindFirstChild("Body")
		local plain = model:FindFirstChild("BodyPlain")
		if body and plain then
			body:SetAttribute("NoTint", true) -- the texture is the point; leave it alone
			if variant.color then
				plain.Name = "Shell"
				plain.Transparency = variant.shell or 0.45
				plain.Size = body.Size * SHELL_SCALE
				plain.CFrame = body.CFrame
				plain.CastShadow = false -- the body already casts one
			else
				plain:Destroy()
			end
		end

		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
	else
		model = buildPlaceholder(char)
	end

	--[[
		Variant skin.

		Textured meshes need the texture CLEARED for any variant that isn't
		Normal: a MeshPart keeps drawing its TextureID over whatever Color you
		set, so a Gold or Rainbow would have come out looking exactly like the
		Normal one. Dropping the texture and letting the material do the work is
		also the better look -- untextured Metal reads as gold, Glass as diamond.

		Normal is the one variant with no colour of its own, which is precisely
		when we want the generated paint job kept.
	]]
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant:GetAttribute("NoTint") and descendant.Name ~= "Root" then
			if variant.color then
				descendant.Color = variant.color
			end
			descendant.Material = variant.material
			descendant.Reflectance = variant.reflectance
		end
	end

	-- measured once, before the decorations change the bounding box
	local ext = extents(model)
	addAura(model, tier, ext)
	addLabel(model, charId, variantId, ext)

	model:SetAttribute("CharId", charId)
	model:SetAttribute("VariantId", variantId)
	model:SetAttribute("Tier", char.tier)
	model:SetAttribute("CycleHue", variant.cycleHue == true)
	CollectionService:AddTag(model, ModelFactory.TAG)

	return model
end

--[[
	Stand `model` on `cframe` -- i.e. put its LOWEST point at that position
	rather than its pivot, which is the only thing that behaves sanely across
	both the placeholders and whatever art you import later.
]]
function ModelFactory.place(model, cframe)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local lift = model:GetPivot().Position.Y - bottom
	model:PivotTo(cframe * CFrame.new(0, lift, 0))
end

return ModelFactory
