--[[
	Seals
	Fragments into seals, and seals into permission.

	THE RULES LIVE HERE SO THE TWO SIDES CANNOT DISAGREE. The server decides
	whether you earned a seal and the client draws how close you are; if those
	were two implementations, the day one changed the HUD would start lying
	about a gate the server still enforced. Both sides read the same functions
	over the same two fields, `fragments` and `seals`, which the profile and the
	client state deliberately name identically.

	A SEAL IS A KEY YOU KEEP, NOT ONE YOU SPEND. Islands.lua puts it plainly --
	what stops you walking into the third island is the seal it asks for, earned
	on the one below -- and a gate you can pay through once is a gate that has
	to remember who already paid. Holding it forever is simpler and it is what
	makes the sky read as chapters rather than tolls.

	WHICH IS WHY FRAGMENTS STOP ONCE THE SEAL IS HELD. Five fragments buy the
	only thing fragments buy, so a sixth would be a currency accruing against
	nothing -- the exact dead end this module exists to close. The bins that
	carried them still pay their 4.7x; only the bonus stops.
]]

local Seals = {}

--[[ How many fragments an island's seal takes. Reads from the island entry
     rather than a constant here, so the second island can be a table entry
     that asks for a different number. ]]
function Seals.required(island)
	return (island and island.sealFragments) or 0
end

function Seals.count(store, sealId)
	if not store or not sealId then
		return 0
	end
	local fragments = store.fragments
	return (fragments and fragments[sealId]) or 0
end

function Seals.held(store, sealId)
	if not store or not sealId then
		return false
	end
	local seals = store.seals
	return (seals and seals[sealId]) == true
end

--[[ Held count and the target, for a progress read. Reports the target once the
     seal is held rather than the raw count, so a tracker never shows 5/5 next
     to a seal you already own. ]]
function Seals.progress(store, island)
	local need = Seals.required(island)
	if Seals.held(store, island and island.seal) then
		return need, need, true
	end
	return math.min(Seals.count(store, island and island.seal), need), need, false
end

--[[
	Add one fragment, and forge the seal if that completes it.

	Returns held, need, justSealed. `justSealed` is what a caller announces --
	it is true on exactly the one call that crosses the threshold, so the moment
	is impossible to miss and impossible to repeat.
]]
function Seals.award(store, island)
	local sealId = island and island.seal
	local need = Seals.required(island)
	if not store or not sealId or need <= 0 then
		return 0, 0, false
	end
	if Seals.held(store, sealId) then
		return need, need, false
	end

	store.fragments = store.fragments or {}
	store.seals = store.seals or {}

	local held = (store.fragments[sealId] or 0) + 1
	if held >= need then
		--[[ Consumed, not kept. Leaving the five behind would show a full bar
		     next to an owned seal forever, and would make a later "spend
		     fragments" idea inherit five it never earned. ]]
		store.fragments[sealId] = nil
		store.seals[sealId] = true
		return need, need, true
	end

	store.fragments[sealId] = held
	return held, need, false
end

--[[
	Whether this island will let you in.

	`requires` is a seal id, absent on the first island because nothing gates
	the entrance to a chapter you start in. Returns ok, missingSealId so a
	caller can say WHICH seal without re-deriving it.
]]
function Seals.canEnter(store, island)
	local needs = island and island.requires
	if not needs then
		return true, nil
	end
	return Seals.held(store, needs), needs
end

return Seals
