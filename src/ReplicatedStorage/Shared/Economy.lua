--[[
	Economy
	The one place that knows how a (character, variant) pair turns into money.
	Server and client both use this, so the number on the pad billboard and the
	number the server actually pays can never drift apart.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Variants = require(Shared.Variants)
local Brainrots = require(Shared.Brainrots)

local Economy = {}

--[[ Income per second for one owned brainrot. ]]
function Economy.incomeOf(charId, variantId)
	local char = Brainrots.get(charId)
	if not char then
		return 0
	end
	local tier = Rarity.get(char.tier)
	local variant = Variants.get(variantId)
	return tier.income * char.mul * variant.mult
end

--[[ "Rainbow Tralalero Tralala" ]]
function Economy.displayName(charId, variantId)
	local char = Brainrots.get(charId)
	if not char then
		return "???"
	end
	return Variants.get(variantId).prefix .. char.name
end

--[[
	A single number for sorting an inventory "best first". Income is already the
	honest measure of value, so we just use it -- ties broken by tier so a
	Legendary sorts above a Common that lucked into a big variant.
]]
function Economy.powerScore(charId, variantId)
	local char = Brainrots.get(charId)
	if not char then
		return 0
	end
	return Economy.incomeOf(charId, variantId) * 1000 + Rarity.get(char.tier).index
end

--[[ Cost to unlock the NEXT pad, given how many the player already has. ]]
function Economy.slotCost(currentSlots)
	if currentSlots >= Config.MaxSlots then
		return nil
	end
	local steps = currentSlots - Config.StartingSlots
	return math.floor(Config.SlotBaseCost * (Config.SlotCostGrowth ^ steps))
end

--[[ Total per-second income from a list of placed entries. ]]
function Economy.totalIncome(inventory)
	local total = 0
	for _, item in ipairs(inventory) do
		if item.pad then
			total += Economy.incomeOf(item.charId, item.variantId)
		end
	end
	return total
end

return Economy
