--[[
	DropTable
	Turns the current Mines multiplier into rarity odds.

	This is the hinge of the whole design: your multiplier IS your luck stat.
	The same number that decides your cash payout decides how good the drops
	are, so "cash out or click one more" is a single decision instead of two
	unrelated ones.

		L = log2(multiplier)                    0 at 1x, 4 at 16x, 8 at 256x
		weight_i(L) = base_i * growth_i ^ L

	Roughly what that produces:

		multiplier    Common   Rare    Legendary   Mythic    Secret
		  1.00x        64.2%   7.7%      0.39%      0.05%     0.003%
		 16.0x         31.3%  20.5%      4.59%      1.22%     0.14%
		256.0x          5.8%  20.5%     20.6%      10.8%      2.2%

	Variants roll independently on the same curve but flatter, so deep runs
	don't double-dip into an absurd top end.

	The second axis is drop CHANCE, which scales with mine count -- see the note
	in Config. Quality comes from depth, frequency comes from danger.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Variants = require(Shared.Variants)
local Brainrots = require(Shared.Brainrots)

local DropTable = {}

--[[
	Chance a safe reveal also carries a brainrot, for a board with `mines`.
	`mods` is an event modifier bag (see Events.lua) or nil.
]]
function DropTable.dropChance(mines, mods)
	local chance = Config.DropChanceBase + Config.DropChancePerMine * mines
	if mods and mods.dropChanceMul then
		chance *= mods.dropChanceMul
	end
	return math.min(Config.DropChanceCap, chance)
end

local function depthOf(multiplier)
	return math.log(math.max(multiplier, 1), 2)
end

--[[
	Weighted pick over a set of names, using each entry's `weight` and `growth`.
	`source` is Rarity.Tiers or Variants.List.

	`opts` carries the event modifiers for this axis:
		add      -- flat weight added BEFORE the growth curve (event-exclusives)
		mul      -- weight multiplier applied after
		depthMul -- scales L, amplifying the rarity climb in both directions
]]
local function weightedPick(order, source, depth, rng, opts)
	local total = 0
	local weights = table.create(#order)
	local effectiveDepth = depth * ((opts and opts.depthMul) or 1)

	for i, name in ipairs(order) do
		local def = source[name]
		local base = def.weight + ((opts and opts.add and opts.add[name]) or 0)
		local w = base * (def.growth ^ effectiveDepth) * ((opts and opts.mul and opts.mul[name]) or 1)
		weights[i] = w
		total += w
	end

	if total <= 0 then
		return order[1]
	end

	local roll = rng:NextNumber() * total
	for i, name in ipairs(order) do
		roll -= weights[i]
		if roll <= 0 then
			return name
		end
	end
	return order[1]
end

--[[ Split an event modifier bag into the two per-axis option tables. ]]
local function axisOpts(mods)
	if not mods then
		return nil, nil
	end
	return {
		mul = mods.tierMul,
		depthMul = mods.depthMul,
	}, {
		mul = mods.variantMul,
		add = mods.variantAdd,
		depthMul = mods.variantDepthMul,
	}
end

--[[
	Roll one brainrot for a tile reveal at the given multiplier.
	Returns { charId = string, variantId = string }.
]]
function DropTable.roll(multiplier, rng, mods)
	local depth = depthOf(multiplier)
	local tierOpts, variantOpts = axisOpts(mods)

	-- Rollable, not Order: the Secret tier is wheel-only and must never appear
	-- from a tile reveal, at any multiplier or under any event.
	local tierName = weightedPick(Rarity.Rollable, Rarity.Tiers, depth, rng, tierOpts)
	local variantId = weightedPick(Variants.Order, Variants.List, depth, rng, variantOpts)

	-- A tier listed in Rarity with no characters assigned to it would otherwise
	-- hard-error here. Easy to hit while editing the roster, so fall back to
	-- the nearest tier that does have entries rather than killing the round.
	local pool = Brainrots.ByTier[tierName]
	if not pool or #pool == 0 then
		warn(string.format("[DropTable] tier %q has no characters -- falling back", tostring(tierName)))
		for i = Rarity.get(tierName).index - 1, 1, -1 do
			local candidate = Brainrots.ByTier[Rarity.Order[i]]
			if candidate and #candidate > 0 then
				pool = candidate
				break
			end
		end
		if not pool or #pool == 0 then
			return nil
		end
	end

	local char = pool[rng:NextInteger(1, #pool)]
	return { charId = char.id, variantId = variantId }
end

--[[
	Odds table for a given multiplier, as { [tierName] = probability }.
	Used by the UI so players can see the curve moving as they go deeper --
	the tension only works if the improving odds are visible.
]]
function DropTable.tierOdds(multiplier, mods)
	local depth = depthOf(multiplier)
	local tierOpts = axisOpts(mods)
	local effectiveDepth = depth * ((tierOpts and tierOpts.depthMul) or 1)
	local total = 0
	local raw = {}

	-- Rollable so the odds panel shows what can actually drop; listing Secret
	-- at 0% would read as a bug rather than as a rule.
	for _, name in ipairs(Rarity.Rollable) do
		local def = Rarity.Tiers[name]
		local w = def.weight
			* (def.growth ^ effectiveDepth)
			* ((tierOpts and tierOpts.mul and tierOpts.mul[name]) or 1)
		raw[name] = w
		total += w
	end

	if total <= 0 then
		return {}
	end

	local odds = {}
	for name, w in pairs(raw) do
		odds[name] = w / total
	end
	return odds
end

return DropTable
