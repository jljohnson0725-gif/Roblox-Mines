--[[
	Format
	Number shortening. Incomes in this game run from 2/s to ~550,000/s and
	balances go far past that, so raw digits stop being readable fast.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

--[[ 1234567 -> "1.23M" ]]
function Format.short(n)
	n = n or 0
	local sign = n < 0 and "-" or ""
	n = math.abs(n)

	if n < 1000 then
		if n < 10 and n % 1 ~= 0 then
			return sign .. string.format("%.1f", n)
		end
		return sign .. tostring(math.floor(n))
	end

	local tier = math.floor(math.log(n, 1000))
	tier = math.clamp(tier, 1, #SUFFIXES - 1)

	local scaled = n / (1000 ^ tier)
	local text
	if scaled < 10 then
		text = string.format("%.2f", scaled)
	elseif scaled < 100 then
		text = string.format("%.1f", scaled)
	else
		text = string.format("%.0f", scaled)
	end

	-- trim trailing zeros: "1.20" -> "1.2", "3.00" -> "3"
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end

	return sign .. text .. SUFFIXES[tier + 1]
end

--[[ "$1.23M" ]]
function Format.money(n)
	return "$" .. Format.short(n)
end

--[[ "$1.23M/s" ]]
function Format.rate(n)
	return "$" .. Format.short(n) .. "/s"
end

--[[ 12.3456 -> "12.35x" ]]
function Format.multiplier(n)
	return string.format("%.2fx", n or 1)
end

--[[ 0.0234 -> "2.34%" -- keeps small odds legible instead of rounding to 0% ]]
function Format.percent(p)
	p = (p or 0) * 100
	if p >= 10 then
		return string.format("%.0f%%", p)
	elseif p >= 1 then
		return string.format("%.1f%%", p)
	elseif p >= 0.01 then
		return string.format("%.2f%%", p)
	elseif p > 0 then
		return string.format("%.3f%%", p)
	end
	return "0%"
end

--[[ Adds thousands separators for places where the exact value matters. ]]
function Format.comma(n)
	local text = tostring(math.floor(math.abs(n or 0)))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return ((n or 0) < 0 and "-" or "") .. out
end

return Format
