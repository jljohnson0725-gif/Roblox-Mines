--[[
	AppearanceService
	What the two vanity items do to your character.

	SERVER-MADE, AND THAT IS THE WHOLE REASON THIS IS A SERVICE. Both effects
	are things OTHER PLAYERS see -- a stink cloud nobody else can smell is not a
	joke, and a chad head only you can see is not a flex. Particles and welds
	built on the server replicate to everyone; built on the client they would be
	local to the one person who least needs to see them.

	THE STINK IS THE DEFAULT STATE. A fresh profile has `cologne = false`, so
	the aura goes on at every spawn until the day it is bought. That inverts the
	usual shape of a shop item: this one is a subtraction, and the "before" is
	what everybody starts in.

	APPLIED ON EVERY SPAWN, not once at purchase. Roblox rebuilds the character
	from scratch on death, so anything welded or parented to it is gone -- which
	is exactly why `apply` is idempotent and safe to call at any time. It is
	called from Bootstrap on CharacterAdded and again from ItemService the
	moment either item is bought, so the change lands without waiting for a
	death.
]]

local Players = game:GetService("Players")

local ServerModules = script.Parent
local DataService = require(ServerModules.DataService)

local AppearanceService = {}

--[[
	THE CHAD HEAD, BUILT FROM IDS RATHER THAN LOADED AS AN ASSET.

	The bundle it comes from (10436554519) is two accessories in a Model, and
	only one of them carries the HatAttachment that tells Roblox where a head
	accessory sits. Rather than depend on InsertService at runtime -- a network
	round trip per spawn, which can fail -- the one piece that matters is
	rebuilt here from its mesh, texture, decals and attachment offset. Those
	were read off the asset itself; see the note on OFFSET below.
]]
local CHAD = {
	mesh = "rbxassetid://6390167392",
	texture = "rbxassetid://6390167062",
	--[[ The face. Two decals, both on the front, layered in this order. ]]
	decals = { "rbxassetid://8075905890", "rbxassetid://8075921377" },
	scale = 1.04,
	--[[ Straight off the asset's own HatAttachment. Roblox pairs this with the
	     head's HatAttachment to place the accessory, so it must match or the
	     head floats. Do not round it -- the 0.0994 forward offset is what sits
	     the jaw over the face rather than inside it. ]]
	offset = CFrame.new(-0.000363349915, 0.605928063, 0.0993585587),
}

--[[
	THE AURA. Two emitters, because one cannot be both the haze and the flies.

	EMISSIVE, NOT LIT. LightInfluence is 0 on both: the apartment every player
	starts in is a bright room with white walls, and at any LightInfluence above
	about 0.3 the green washed out completely there while looking fine outdoors.
	A starting condition has to read in the starting room.

	AND TRANSLUCENT ON PURPOSE. The first pass ran the haze at 0.55 transparency
	across 2.6-stud puffs, which stopped being an aura and became a green slab
	standing behind the player. You have to be able to read the character
	through it -- it is a smell, not a wall.
]]
local AURA = {
	color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(168, 224, 76)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(122, 190, 52)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 40)),
	}),
}

local AURA_FOLDER = "StinkAura"
local AURA_POINT = "StinkPoint"
local CHAD_NAME = "ChadHead"

local function torsoOf(character)
	return character:FindFirstChild("UpperTorso") -- R15
		or character:FindFirstChild("Torso") -- R6
end

--[[ Clear whatever a previous apply put on, so this can run at any time. ]]
local function stripAura(character)
	local folder = character:FindFirstChild(AURA_FOLDER)
	if folder then
		folder:Destroy()
	end
	local torso = torsoOf(character)
	local point = torso and torso:FindFirstChild(AURA_POINT)
	if point then
		point:Destroy()
	end
end

local function buildAura(character)
	local torso = torsoOf(character)
	if not torso then
		return
	end

	--[[ A marker child, so `stripAura` and any future read can find the aura
	     without knowing which limb it was hung on. ]]
	local folder = Instance.new("Folder")
	folder.Name = AURA_FOLDER
	folder.Parent = character

	local point = Instance.new("Attachment")
	point.Name = AURA_POINT
	point.Position = Vector3.new(0, 0.2, 0)
	point.Parent = torso

	local waft = Instance.new("ParticleEmitter")
	waft.Name = "Waft"
	waft.Texture = "rbxasset://textures/particles/smoke_main.dds"
	waft.Color = AURA.color
	waft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	waft.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.95),
		NumberSequenceKeypoint.new(1, 1.45),
	})
	waft.Lifetime = NumberRange.new(1.3, 2.0)
	waft.Rate = 16
	waft.Speed = NumberRange.new(0.8, 1.4)
	waft.SpreadAngle = Vector2.new(35, 35)
	waft.Acceleration = Vector3.new(0, 1.3, 0)
	waft.Rotation = NumberRange.new(0, 360)
	waft.RotSpeed = NumberRange.new(-30, 30)
	waft.LightInfluence = 0
	waft.LightEmission = 0.25
	waft.ZOffset = 0.2
	--[[ A volume rather than a point, so the haze wraps the body instead of
	     rising out of one spot like a chimney. ]]
	waft.Shape = Enum.ParticleEmitterShape.Box
	waft.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	waft.EmissionDirection = Enum.NormalId.Top
	waft.Parent = point

	--[[ The flies read the joke faster than the haze does -- high drag so they
	     hang around the body rather than flying off it. ]]
	local flies = Instance.new("ParticleEmitter")
	flies.Name = "Flies"
	flies.Color = ColorSequence.new(Color3.fromRGB(24, 22, 18))
	flies.Transparency = NumberSequence.new(0.1)
	flies.Size = NumberSequence.new(0.18)
	flies.Lifetime = NumberRange.new(0.8, 1.4)
	flies.Rate = 12
	flies.Speed = NumberRange.new(1.4, 2.6)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Acceleration = Vector3.new(0, 0.5, 0)
	flies.Drag = 6
	flies.LightInfluence = 0
	flies.ZOffset = 0.8
	flies.Parent = point
end

--[[
	Hide the real head and everything hanging off it, then weld the chad head
	where the head was.

	HIDDEN, NOT DESTROYED. Transparency on the player's own hats and hair rather
	than removing them: the character is rebuilt on every respawn anyway, so
	destroying buys nothing, and a reversible change is the one that cannot
	corrupt somebody's avatar if this ever runs when it should not.
]]
local function buildChadHead(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if not humanoid or not head then
		return
	end
	if character:FindFirstChild(CHAD_NAME) then
		return -- already wearing it
	end

	head.Transparency = 1
	for _, child in ipairs(head:GetChildren()) do
		if child:IsA("Decal") then
			child.Transparency = 1
		end
	end
	--[[ Their own hair and hats, which would otherwise clip straight through
	     the jaw. Only head-mounted ones -- a back accessory is left alone. ]]
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") and accessory.Name ~= CHAD_NAME then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:FindFirstChild("HatAttachment") then
				--[[ The handle's own transparency hides its mesh; decals sit on
				     top of it and need telling separately. ]]
				handle.Transparency = 1
				for _, child in ipairs(handle:GetChildren()) do
					if child:IsA("Decal") then
						child.Transparency = 1
					end
				end
			end
		end
	end

	local accessory = Instance.new("Accessory")
	accessory.Name = CHAD_NAME

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = CHAD.mesh
	mesh.TextureId = CHAD.texture
	mesh.Scale = Vector3.new(CHAD.scale, CHAD.scale, CHAD.scale)
	mesh.Parent = handle

	for _, id in ipairs(CHAD.decals) do
		local decal = Instance.new("Decal")
		decal.Texture = id
		decal.Face = Enum.NormalId.Front
		decal.Parent = handle
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.CFrame = CHAD.offset
	attachment.Parent = handle

	handle.Parent = accessory
	--[[ AddAccessory rather than a hand-built weld: it matches HatAttachment to
	     the head's own, which is what makes this land correctly on a scaled
	     avatar instead of only on a default-sized one. ]]
	humanoid:AddAccessory(accessory)
end

--[[
	Put this profile's appearance on this character. Safe to call repeatedly and
	safe to call on a character that already has it.
]]
function AppearanceService.apply(player, character)
	character = character or player.Character
	if not character or not character.Parent then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	--[[ The stink first, because it is the one that can be taken away: a player
	     who has just bought the cologne needs the aura GONE on this call, not
	     merely not re-added. ]]
	stripAura(character)
	if profile.cologne ~= true then
		buildAura(character)
	end

	if profile.peptides == true then
		buildChadHead(character)
	end
end

--[[ Everyone currently in the world. Used after a purchase, and cheap enough
     to not need a narrower path. ]]
function AppearanceService.refresh(player)
	local ok, err = pcall(AppearanceService.apply, player, player.Character)
	if not ok then
		warn("[AppearanceService] refresh failed:", err)
	end
end

return AppearanceService
