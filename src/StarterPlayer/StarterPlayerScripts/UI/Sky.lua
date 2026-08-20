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

--[[ How far up the ground-to-sunset blend currently is, 0 to 1. Published so
     the music can cross-fade on the same number the lighting uses -- one
     definition of "how high am I" rather than two that can disagree. ]]
local blend = 0
function Sky.blend()
	return blend
end

local GROUND_Y = 70 -- below this, exactly what MapStyle set
local SKY_Y = 190 -- above this, full sunset; the island sits at 220

--[[
	BLUE HOUR, NOT GOLDEN HOUR. The reference's palette is cool -- blue-grey
	rock, dark green, neon accents -- and that is the light AFTER the sun has
	gone, not during it. An orange sun sitting on the horizon at 17.9 gilds
	every surface it touches and fights the whole palette; 18.45 puts it below
	and leaves the sky doing the work.

	THE GRADE COMES DOWN TOO. MapStyle runs a ColorCorrection at +0.30
	saturation and Bloom at 0.60, which is right for a bright cartoon town at
	midday and turns everything neon under a low sun. Twilight wants that
	mostly off.

	Ambient stays high. The failure mode when tuning this was reaching for
	brightness to make it darker, which does not produce dusk -- it produces
	black conifers.
]]
local SUNSET = {
	clock = 18.45,
	brightness = 1.1,
	ambient = Color3.fromRGB(128, 134, 158),
	outdoor = Color3.fromRGB(140, 148, 176),
	top = Color3.fromRGB(96, 104, 136),
	bottom = Color3.fromRGB(40, 46, 72),
	fog = Color3.fromRGB(150, 160, 196),
	exposure = -0.1,
	density = 0.2,
	haze = 0.6,
	atmColor = Color3.fromRGB(176, 186, 216),
	saturation = -0.02,
	contrast = 0.02,
	ccTint = Color3.fromRGB(240, 234, 244),
	bloom = 0.25,
}

local function atmosphere()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function grade()
	return Lighting:FindFirstChildWhichIsA("ColorCorrectionEffect"),
		Lighting:FindFirstChildWhichIsA("BloomEffect")
end

local function capture()
	local atm = atmosphere()
	local cc, bloom = grade()
	return {
		clock = Lighting.ClockTime,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		top = Lighting.ColorShift_Top,
		bottom = Lighting.ColorShift_Bottom,
		fog = Lighting.FogColor,
		exposure = Lighting.ExposureCompensation,
		density = atm and atm.Density or 0.32,
		haze = atm and atm.Haze or 1.1,
		atmColor = atm and atm.Color or Color3.fromRGB(199, 209, 255),
		saturation = cc and cc.Saturation or 0,
		contrast = cc and cc.Contrast or 0,
		ccTint = cc and cc.TintColor or Color3.new(1, 1, 1),
		bloom = bloom and bloom.Intensity or 0,
	}
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function apply(from, t)
	Lighting.ClockTime = lerp(from.clock, SUNSET.clock, t)
	Lighting.Brightness = lerp(from.brightness, SUNSET.brightness, t)
	Lighting.ExposureCompensation = lerp(from.exposure, SUNSET.exposure, t)
	Lighting.Ambient = from.ambient:Lerp(SUNSET.ambient, t)
	Lighting.OutdoorAmbient = from.outdoor:Lerp(SUNSET.outdoor, t)
	Lighting.ColorShift_Top = from.top:Lerp(SUNSET.top, t)
	Lighting.ColorShift_Bottom = from.bottom:Lerp(SUNSET.bottom, t)
	Lighting.FogColor = from.fog:Lerp(SUNSET.fog, t)

	local atm = atmosphere()
	if atm then
		atm.Density = lerp(from.density, SUNSET.density, t)
		atm.Haze = lerp(from.haze, SUNSET.haze, t)
		atm.Color = from.atmColor:Lerp(SUNSET.atmColor, t)
	end

	local cc, bloom = grade()
	if cc then
		cc.Saturation = lerp(from.saturation, SUNSET.saturation, t)
		cc.Contrast = lerp(from.contrast, SUNSET.contrast, t)
		cc.TintColor = from.ccTint:Lerp(SUNSET.ccTint, t)
	end
	if bloom then
		bloom.Intensity = lerp(from.bloom, SUNSET.bloom, t)
	end
end

function Sky.init(ctx)
	local player = Players.LocalPlayer
	local ground = nil

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

	--[[
		THE CUTSCENE OWNS LIGHTING WHILE IT RUNS.

		This pass and the intro were both writing Lighting, and this one wins
		because it runs every frame. Whenever the altitude blend was still
		converging -- which it is for a second or two after any spawn, and again
		any time the player's height changes -- apply() below would overwrite the
		intro's night with the map's daylight mid-shot: sky, fog, exposure,
		atmosphere, grade and bloom, several of which the intro does not even
		save. From the player's seat the whole scene simply vanished partway
		through, which is exactly how it was reported.

		Neither module knows about the other; they agree on one attribute.
	]]
	local suppressed = false

	RunService.Heartbeat:Connect(function(dt)
		if not ground then
			return
		end
		if player:GetAttribute("CutscenePlaying") then
			suppressed = true
			return
		end
		if suppressed then
			--[[ The intro has put Lighting back the way it found it; re-assert
			     the altitude blend once so the sky is not left at ground level
			     for a player who was up an island when it started. ]]
			suppressed = false
			apply(ground, blend)
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
		if math.abs(target - blend) > 0.0005 then
			blend += (target - blend) * math.min(dt * 2.2, 1)
			apply(ground, blend)
		end
	end)

	return Sky
end

return Sky
