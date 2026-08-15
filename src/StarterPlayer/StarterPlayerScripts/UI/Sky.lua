--[[
	Sky
	The ground stays bright. Climbing takes you into sunset.

	LIGHTING IS PER-CLIENT, which is the whole trick. Properties written to
	Lighting on a client are local to that client and never replicate, so one
	player standing on an island can be at 17.9 while everyone in the street
	below is still at 13.6 midday. There is no server involvement and nothing
	to synchronise -- each client simply lights its own view from its own
	altitude.

	THE GROUND PRESET IS CAPTURED, NOT WRITTEN DOWN. MapStyle owns the daylight
	look and has opinions about eleven properties; copying its numbers here
	would mean two places to edit and one of them silently going stale. Instead
	this reads whatever Lighting actually is on the first sync -- after
	Bootstrap has run MapStyle -- and treats that as t = 0. Retune the daylight
	and the blend follows for free.

	The band is deliberately wide. Sunset arriving over a hundred and twenty
	studs of climb reads as travelling somewhere; the same change over ten would
	read as a light switch, and you would see it flicker every time you bobbed
	across the boundary.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Sky = {}

local GROUND_Y = 70 -- below this, exactly what MapStyle set
local SKY_Y = 190 -- above this, full sunset; the island sits at 220

--[[ Where the climb ends up. Tuned on screen against the reference: a warm low
     sun with enough ambient fill that the conifers stay green instead of going
     to silhouette. Dropping brightness alone just turns everything black. ]]
local SUNSET = {
	clock = 17.9,
	brightness = 1.8,
	ambient = Color3.fromRGB(126, 122, 126),
	outdoor = Color3.fromRGB(140, 137, 142),
	top = Color3.fromRGB(78, 58, 32),
	bottom = Color3.fromRGB(34, 38, 58),
	fog = Color3.fromRGB(196, 172, 168),
	density = 0.30,
	haze = 1.5,
	atmColor = Color3.fromRGB(198, 194, 212),
}

local function atmosphere()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function capture()
	local atm = atmosphere()
	return {
		clock = Lighting.ClockTime,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		top = Lighting.ColorShift_Top,
		bottom = Lighting.ColorShift_Bottom,
		fog = Lighting.FogColor,
		density = atm and atm.Density or 0.32,
		haze = atm and atm.Haze or 1.1,
		atmColor = atm and atm.Color or Color3.fromRGB(199, 209, 255),
	}
end

local function apply(from, t)
	Lighting.ClockTime = from.clock + (SUNSET.clock - from.clock) * t
	Lighting.Brightness = from.brightness + (SUNSET.brightness - from.brightness) * t
	Lighting.Ambient = from.ambient:Lerp(SUNSET.ambient, t)
	Lighting.OutdoorAmbient = from.outdoor:Lerp(SUNSET.outdoor, t)
	Lighting.ColorShift_Top = from.top:Lerp(SUNSET.top, t)
	Lighting.ColorShift_Bottom = from.bottom:Lerp(SUNSET.bottom, t)
	Lighting.FogColor = from.fog:Lerp(SUNSET.fog, t)

	local atm = atmosphere()
	if atm then
		atm.Density = from.density + (SUNSET.density - from.density) * t
		atm.Haze = from.haze + (SUNSET.haze - from.haze) * t
		atm.Color = from.atmColor:Lerp(SUNSET.atmColor, t)
	end
end

function Sky.init(ctx)
	local player = Players.LocalPlayer
	local ground, current = nil, 0

	--[[ Captured on the first sync rather than at require time. Bootstrap runs
	     MapStyle before it opens the remotes, so a state payload arriving is
	     proof the daylight pass has already happened and Lighting is the thing
	     we want to treat as ground level. ]]
	local captured = false
	ctx.onState(function()
		if not captured then
			captured = true
			ground = capture()
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not ground then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local y = root.Position.Y
		local target = math.clamp((y - GROUND_Y) / (SKY_Y - GROUND_Y), 0, 1)
		-- smoothstep, so the transition eases in and out of both ends rather
		-- than starting and stopping abruptly at the band edges
		target = target * target * (3 - 2 * target)

		--[[ Eased over time as well as over height. Without this a fast climb
		     changes the sky as quickly as it changes altitude, which reads as
		     the sun being yanked rather than the player rising through
		     evening. ]]
		if math.abs(target - current) > 0.0005 then
			current += (target - current) * math.min(dt * 2.2, 1)
			apply(ground, current)
		end
	end)

	return Sky
end

return Sky
