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

--[[
	Palette.

	Every one of these was a muted dusk value and is now near-full saturation.
	The genre's look isn't subtle grading, it's moulded plastic under a bright
	sun -- so greens go vivid, rock goes light grey-blue rather than slate, and
	the four "neon" entries stop being light sources and become bright plastic,
	because at midday an emissive part just reads as a flat pale blob.
]]
local P = {
	grass = Color3.fromRGB(106, 208, 74),
	grassDeep = Color3.fromRGB(72, 172, 56),
	pine = Color3.fromRGB(42, 128, 62),
	rock = Color3.fromRGB(176, 186, 202),
	rockDeep = Color3.fromRGB(128, 140, 160),
	path = Color3.fromRGB(206, 200, 186),
	wood = Color3.fromRGB(160, 104, 62),
	roof = Color3.fromRGB(226, 62, 62),
	fruit = Color3.fromRGB(255, 150, 40),
	neonCyan = Color3.fromRGB(64, 196, 255),
	neonMag = Color3.fromRGB(255, 96, 176),
	neonViolet = Color3.fromRGB(150, 96, 255),
	neonAmber = Color3.fromRGB(255, 202, 40),
	stem = Color3.fromRGB(255, 252, 240),
}

MapStyle.Palette = P

-- ── lighting ────────────────────────────────────────────────────────────────

--[[
	Bright toy daylight.

	This was a dusk-neon scene for a while, and dusk is the wrong instinct for
	this genre: it makes every surface a muted version of itself and hides the
	one thing the art is doing, which is being loudly, primary-coloured plastic.
	The reference games all run high, near-white midday sun with the saturation
	pushed -- colour comes from the BUILD, and the lighting's only job is to not
	get in its way.

	So: sun overhead, shadows short, saturation up hard, fog pushed far enough
	back that the street reads end to end.
]]
local function applyLighting()
	--[[
		The dusk pass parked the map's static skyboxes in ServerStorage, because
		a Sky ignores ClockTime and kept the sky bright. Now that bright IS the
		look, put them back -- a hand-painted skybox beats the procedural one,
		and the reference's rainbow-streaked sky is exactly this kind of asset.
	]]
	local parked = ServerStorage:FindFirstChild("ParkedSkies")
	if parked then
		for _, child in ipairs(parked:GetChildren()) do
			child.Parent = Lighting
		end
	end

	Lighting.ClockTime = 13.6 -- just off noon, so shadows have a direction
	Lighting.GeographicLatitude = 12
	Lighting.Brightness = 2.6
	Lighting.ExposureCompensation = 0.05
	Lighting.Ambient = Color3.fromRGB(150, 158, 178)
	Lighting.OutdoorAmbient = Color3.fromRGB(178, 190, 214)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 230)
	Lighting.ColorShift_Bottom = Color3.fromRGB(150, 172, 200)
	Lighting.FogColor = Color3.fromRGB(186, 226, 255)
	--[[ Fog stays SHORT of the Auction House at x=4000: that room has no walls
	     of its own and relies on being past FogEnd to stay invisible from the
	     street. Costs nothing to keep -- the street's longest sightline is about
	     590 studs, so fog never actually touches it. ]]
	Lighting.FogStart = 900
	Lighting.FogEnd = 3000
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.32
		atmosphere.Haze = 1.1
		atmosphere.Glare = 0.15
		atmosphere.Color = Color3.fromRGB(210, 232, 255)
		atmosphere.Decay = Color3.fromRGB(140, 180, 226)
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 0.6 -- lower: in daylight this smears instead of glows
		bloom.Size = 24
		bloom.Threshold = 1.05
	end

	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		correction.Contrast = 0.10
		correction.Saturation = 0.30 -- the whole point; plastic wants to be loud
		correction.Brightness = 0.02
		correction.TintColor = Color3.fromRGB(255, 252, 246)
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

	--[[
		Ground gets Plastic, not SmoothPlastic. Plastic carries Roblox's faint
		stud-and-speckle shading, which is most of what makes the reference read
		as toy bricks rather than flat-shaded polygons -- and it only shows up
		under bright light, which is why this arrived with the daylight pass.
	]]
	if sat < 0.10 then -- greys: stone and concrete
		part.Color = isTerrain and P.rockDeep or P.rock
		part.Material = Enum.Material.Plastic
	elseif hue > 0.20 and hue < 0.46 then -- greens: ground and canopy
		part.Color = isTerrain and P.grassDeep or (widest > 8 and P.grass or P.pine)
		part.Material = Enum.Material.Plastic
	elseif hue < 0.12 or hue > 0.93 then -- oranges, reds, browns
		part.Color = isDetail and P.fruit or (isTerrain and P.path or P.wood)
		part.Material = Enum.Material.Plastic
	elseif hue >= 0.12 and hue <= 0.20 then -- the map's tiny pure-yellow bits
		part.Color = isDetail and P.neonAmber or P.wood
		part.Material = Enum.Material.Plastic
	elseif hue > 0.55 and hue < 0.80 then -- blues and purples: roofs, trim
		part.Color = isDetail and P.neonMag or P.roof
		part.Material = Enum.Material.Plastic
	else
		-- keep the hue, force it bright and saturated rather than darkening it
		part.Color = Color3.fromHSV(hue, math.max(sat, 0.65), math.max(value, 0.80))
		part.Material = Enum.Material.Plastic
	end

	--[[ Floor is now a MINIMUM brightness, not a rescue from darkness. The dusk
	     pass pushed everything down and had to catch what fell too far; daylight
	     pushes everything up, so the failure mode is a muddy mid-tone. ]]
	local h2, s2, v2 = Color3.toHSV(part.Color)
	if v2 < 0.45 then
		part.Color = Color3.fromHSV(h2, s2, 0.55)
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

--[[
	Bumped from "DuskStyled" when the scene went to daylight.

	The guard exists because the remap classifies parts BY HUE, so a second pass
	over already-restyled colours drifts them. That also means the attribute has
	to change whenever the palette does -- a place file saved under the old pass
	would otherwise be skipped and keep the old look forever.
]]
local STYLE_TAG = "StyledDay1"

function MapStyle.apply()
	if Workspace:GetAttribute(STYLE_TAG) then
		return 0, 0
	end
	Workspace:SetAttribute("DuskStyled", nil) -- retire the old marker

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
	Workspace:SetAttribute(STYLE_TAG, true)

	return styled, mushrooms
end

return MapStyle
