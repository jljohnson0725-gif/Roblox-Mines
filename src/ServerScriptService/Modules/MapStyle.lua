--[[
	MapStyle
	Restyles the imported map to a dusk-neon look at server start.

	WHY AT RUNTIME rather than baked into assets/map.rbxlx: the map is an
	imported third-party asset that may get re-exported or replaced. Keeping the
	restyle as code means it survives that, lives in version control where the
	values are readable and tunable in one place, and can be removed by deleting
	one require. It matches how everything else in this project builds its world.

	Reference direction: low-poly dusk valley -- deep blue hour sky, cool
	desaturated terrain, and colour carried almost entirely by a small number of
	emissive accents. The discipline that makes it work is restraint: an early
	pass made 980 parts emissive and the tree canopies read as fairy lights.
	Roughly 150 deliberate glows beat 1000 scattered ones.

	Does NOT touch Workspace.Bases -- PlotService owns that geometry and caches
	each pad's original colour to restore when a pad empties.
]]

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapStyle = {}

-- ── palette ─────────────────────────────────────────────────────────────────
local P = {
	grass = Color3.fromRGB(92, 156, 98),
	grassDeep = Color3.fromRGB(66, 124, 80),
	pine = Color3.fromRGB(38, 76, 56),
	rock = Color3.fromRGB(104, 114, 146),
	rockDeep = Color3.fromRGB(74, 82, 112),
	path = Color3.fromRGB(92, 88, 104),
	wood = Color3.fromRGB(92, 74, 70),
	roof = Color3.fromRGB(58, 74, 124),
	fruit = Color3.fromRGB(214, 120, 76),
	neonCyan = Color3.fromRGB(90, 226, 255),
	neonMag = Color3.fromRGB(255, 92, 214),
	neonViolet = Color3.fromRGB(160, 120, 255),
	neonAmber = Color3.fromRGB(255, 176, 64),
	stem = Color3.fromRGB(226, 224, 240),
}

MapStyle.Palette = P

-- ── lighting ────────────────────────────────────────────────────────────────

--[[
	Blue hour: the sun sits just BELOW the horizon. That's deliberate --
	at 17.5 the sun disc hangs in frame and Atmosphere.Glare blows it into a
	white blob, and anything earlier just reads as daytime with dark roofs.
]]
local function applyLighting()
	-- Static skyboxes ignore ClockTime entirely, which is why the sky stayed
	-- bright daylight through several attempts. Park them so the procedural
	-- sky (which does respond) takes over.
	local parked = ServerStorage:FindFirstChild("ParkedSkies")
	if not parked then
		parked = Instance.new("Folder")
		parked.Name = "ParkedSkies"
		parked.Parent = ServerStorage
	end
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			child.Parent = parked
		end
	end

	Lighting.ClockTime = 18.45
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 1.9
	Lighting.ExposureCompensation = 0.42
	Lighting.Ambient = Color3.fromRGB(104, 114, 152)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 140, 182)
	Lighting.ColorShift_Top = Color3.fromRGB(150, 152, 208)
	Lighting.ColorShift_Bottom = Color3.fromRGB(62, 70, 108)
	Lighting.FogColor = Color3.fromRGB(88, 100, 148)
	Lighting.FogStart = 550
	Lighting.FogEnd = 3000
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.28
		atmosphere.Haze = 0.70
		atmosphere.Glare = 0.05 -- higher values re-create the white sun blob
		atmosphere.Color = Color3.fromRGB(146, 162, 214)
		atmosphere.Decay = Color3.fromRGB(74, 88, 142)
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 1.05
		bloom.Size = 30
		bloom.Threshold = 0.85 -- only the emissives bloom, not lit surfaces
	end

	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		correction.Contrast = 0.14
		correction.Saturation = 0.06 -- dusk drains colour; push some back
		correction.Brightness = 0.03
		correction.TintColor = Color3.fromRGB(226, 230, 255)
	end

	local blur = Lighting:FindFirstChildOfClass("BlurEffect")
	if blur then
		blur.Size = 0
	end

	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.FarIntensity = 0.12
		dof.NearIntensity = 0
	end
end

-- ── palette remap ───────────────────────────────────────────────────────────

--[[
	Classified by hue band and size rather than by name, because the map's parts
	are almost all called "Part" or "Union" -- there are no meaningful names to
	match on. Size is what separates terrain from detail.
]]
local function restylePart(part)
	local hue, sat, value = Color3.toHSV(part.Color)
	local widest = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	local isTerrain = widest > 40
	local isDetail = widest < 3.2

	if sat < 0.10 then -- greys: stone and concrete
		part.Color = isTerrain and P.rockDeep or P.rock
		part.Material = Enum.Material.Slate
	elseif hue > 0.20 and hue < 0.46 then -- greens: ground and canopy
		part.Color = isTerrain and P.grassDeep or (widest > 8 and P.grass or P.pine)
		part.Material = Enum.Material.SmoothPlastic
	elseif hue < 0.12 or hue > 0.93 then -- oranges, reds, browns
		part.Color = isDetail and P.fruit or (isTerrain and P.path or P.wood)
		part.Material = Enum.Material.SmoothPlastic
	elseif hue >= 0.12 and hue <= 0.20 then -- the map's tiny pure-yellow bits
		if isDetail then -- already accent-sized: the natural emissives
			part.Color = P.neonCyan
			part.Material = Enum.Material.Neon
		else
			part.Color = P.wood
			part.Material = Enum.Material.SmoothPlastic
		end
	elseif hue > 0.55 and hue < 0.80 then -- blues and purples: roofs, trim
		part.Color = isDetail and P.neonMag or P.roof
		part.Material = isDetail and Enum.Material.Neon or Enum.Material.SmoothPlastic
	else
		part.Color = Color3.fromHSV(hue, sat * 0.5, value * 0.55)
		part.Material = Enum.Material.SmoothPlastic
	end

	-- nothing crushed so dark it loses its silhouette
	local _, _, v2 = Color3.toHSV(part.Color)
	if v2 < 0.16 and part.Material ~= Enum.Material.Neon then
		part.Color = P.roof
	end
end

-- ── glowing mushrooms ───────────────────────────────────────────────────────

local CAPS = { P.neonMag, P.neonCyan, P.neonViolet, P.neonAmber }

--[[
	Scattered by raycast so they sit on whatever surface is actually there,
	rather than on a guessed ground plane -- the map is terraced and has no
	single floor height. Flat surfaces only, so none end up on roofs or cliffs.
]]
local function plantMushrooms(bases, budget)
	local existing = Workspace:FindFirstChild("DuskProps")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "DuskProps"
	folder.Parent = Workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, bases }

	local rng = Random.new(20260813) -- fixed seed: same map every server
	local made, attempts = 0, 0

	while made < budget and attempts < budget * 8 do
		attempts += 1
		local origin = Vector3.new(rng:NextNumber(-430, 360), 300, rng:NextNumber(-350, 250))
		local hit = Workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
		if hit and hit.Instance:IsA("BasePart") and hit.Normal.Y > 0.9 then
			local cap = CAPS[rng:NextInteger(1, #CAPS)]
			local scale = rng:NextNumber(0.7, 1.5)

			for i = 1, rng:NextInteger(1, 3) do -- little clusters, not lone pins
				local offset = i == 1 and Vector3.zero
					or Vector3.new(rng:NextNumber(-2.2, 2.2), 0, rng:NextNumber(-2.2, 2.2))
				local s = scale * (i == 1 and 1 or rng:NextNumber(0.5, 0.8))
				local root = hit.Position + offset

				local stem = Instance.new("Part")
				stem.Name = "Stem"
				stem.Size = Vector3.new(0.42 * s, 1.5 * s, 0.42 * s)
				stem.CFrame = CFrame.new(root + Vector3.new(0, 0.75 * s, 0))
				stem.Color = P.stem
				stem.Material = Enum.Material.SmoothPlastic
				stem.Anchored = true
				stem.CanCollide = false
				stem.CanQuery = false
				stem.Parent = folder

				local head = Instance.new("Part")
				head.Name = "Cap"
				head.Shape = Enum.PartType.Ball
				head.Size = Vector3.new(1.9 * s, 1.35 * s, 1.9 * s)
				head.CFrame = CFrame.new(root + Vector3.new(0, 1.6 * s, 0))
				head.Color = cap
				head.Material = Enum.Material.Neon
				head.Anchored = true
				head.CanCollide = false
				head.CanQuery = false
				head.Parent = folder

				local light = Instance.new("PointLight")
				light.Color = cap
				light.Range = 12 * s
				light.Brightness = 1.4
				light.Parent = head

				made += 1
			end
		end
	end

	return made
end

-- ── entry point ─────────────────────────────────────────────────────────────

MapStyle.MUSHROOM_BUDGET = 150

function MapStyle.apply()
	-- Guard against a double pass: the remap classifies by hue, so running it
	-- over already-restyled colours would drift them.
	if Workspace:GetAttribute("DuskStyled") then
		return 0, 0
	end

	applyLighting()

	local bases = Workspace:FindFirstChild("Bases")
	local styled = 0
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and not (bases and descendant:IsDescendantOf(bases)) then
			restylePart(descendant)
			styled += 1
		end
	end

	local mushrooms = plantMushrooms(bases, MapStyle.MUSHROOM_BUDGET)
	Workspace:SetAttribute("DuskStyled", true)

	return styled, mushrooms
end

return MapStyle
