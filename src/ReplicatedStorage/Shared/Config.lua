--[[
	Config
	Every tunable number in the game. Balance passes happen here, not in the
	services -- if you find yourself hardcoding a number elsewhere, move it here.
]]

local Config = {}

-- ── Mines board ─────────────────────────────────────────────────────────────
Config.GridSize = 5
Config.TileCount = 25

-- House edge on the CASH side of the game. The cash payout is deliberately
-- slightly -EV: brainrot drops are the real reward, cash is the entry fee.
Config.HouseEdge = 0.03

Config.MineOptions = { 1, 3, 5, 8, 12, 16, 20, 24 }
Config.DefaultMines = 3

-- ── Money ───────────────────────────────────────────────────────────────────
Config.StartingMoney = 500
Config.MinBet = 10

-- Anti-softlock. A player who busts their last dollar with nothing placed has
-- zero income and can't afford the minimum bet -- the game would be over with
-- no way back. Top them up instead of stranding them.
Config.BrokeStipend = 50

-- ── Drops ───────────────────────────────────────────────────────────────────
-- Chance that a safe reveal ALSO contains a brainrot (on top of the cash tick).
--
-- This SCALES WITH MINE COUNT, and that is load-bearing. Brainrots are lost on
-- a mine hit, so survival is what matters -- with a flat drop chance, 1 mine is
-- ~10x better value per round than 24 and the mine selector is decorative.
-- Scaling the chance by mine count flattens expected value to a ~1.3x spread
-- across the whole range while leaving variance completely different:
-- 1 mine drips small drops constantly, 20 mines pays enormously in 0.4% of
-- rounds. Same EV, different shape -- which is what a risk dial is for.
--
-- Re-run tools/balance.py after touching any of these three.
Config.DropChanceBase = 0.06
Config.DropChancePerMine = 0.04
Config.DropChanceCap = 0.90

-- ── Plot ────────────────────────────────────────────────────────────────────
-- Slot economy, sized to the imported map: each base there has exactly 8 slot
-- pedestals, and PlotService clamps to the real geometry regardless of MaxSlots.
--
-- Fewer pads than the old 20 makes each unlock a bigger moment, and makes
-- "which eight do I display" an actual decision rather than "display everything".
-- The curve is steeper to compensate for there being only 5 purchases:
--   3 -> 4      $2.5K
--   4 -> 5      $10.5K
--   5 -> 6      $44K
--   6 -> 7      $185K
--   7 -> 8      $778K      (~$1.02M to max out)
Config.StartingSlots = 3
Config.MaxSlots = 8
Config.SlotBaseCost = 2500
Config.SlotCostGrowth = 4.2

Config.PlotSize = Vector3.new(52, 1, 52)
Config.PlotSpacing = 72

-- Pads are arranged as a SHELVING UNIT, not a flat grid on the floor:
-- PadColumns per shelf, stacked upward. 20 slots = 4 shelves of 5. A wall of
-- brainrots reads as a trophy case; a grid on the ground reads as a car park.
Config.PadColumns = 5
Config.PadSize = Vector3.new(7, 0.4, 7)
Config.PadSpacing = 8.8

-- The shelves STEP BACK as they rise, like stadium seating, rather than
-- stacking into a flat wall. Two reasons, both load-bearing:
--   1. ProximityPrompt targets the NEAREST pad. On a vertical wall the bottom
--      row always wins and the top row is permanently unreachable. Stepping
--      back means standing on a tier makes that tier's pads nearest.
--   2. Each rise is jumpable, so you climb your own collection to manage it.
Config.ShelfLift = 1 -- top face of the front tier, above the plot floor
Config.ShelfRise = 4 -- vertical step per tier (jumpable, not walkable)
Config.ShelfDepth = 8 -- front-to-back per tier; also the step-back distance
Config.ShelfFrontZ = 8 -- centre Z of the front tier

-- Placeholder figures are ~5.6 studs tall. With a 4-stud rise the back tiers
-- are partly occluded by the front ones, exactly like stadium seating -- that's
-- intended. Raise ShelfRise if you import noticeably taller art.

-- ── Income ──────────────────────────────────────────────────────────────────
Config.IncomeTickRate = 1 -- seconds between passive income payouts

-- Income doesn't auto-credit: it piles up on the collect strips and you walk to
-- a brainrot to bank it.
--
-- FOUR HOURS, not the five minutes this started as. Leaving the game running to
-- stack money is a genuine pleasure of the genre and a short cap fights it --
-- you'd come back from dinner to a pile that stopped growing twenty minutes in.
-- A cap still has to exist, or a week away mints unbounded money, and the
-- Capacity upgrade extends this further.
--
-- Note this is AFK income: the tick only runs for connected players. Earning
-- while fully disconnected would be a separate feature.
Config.CollectCapSeconds = 4 * 60 * 60

-- CollectionService tag on placed brainrot models. Lives here because the
-- server applies it and the client animates by it, and they must not drift.
Config.BrainrotTag = "BrainrotModel"

-- Tag on the Mines landmark's rings. Server builds them, client spins them.
Config.RingTag = "MinesRing"

-- ── Upgrades ────────────────────────────────────────────────────────────────
-- How close you must stand to a counter to use it. Shared by the street
-- upgrade shop and the auction consign desk.
Config.ShopRange = 30

--[[
	Walk speed before any upgrade.

	Roblox's default is 16, and the old Fast Feet curve started there and reached
	25 at level 6. That first stretch was buying back speed the game should have
	had all along: the street runs 590 studs and at 16 the walk between your base
	and a portal is dead time, not friction worth paying to remove.

	So the whole curve moves up. You START where level 6 used to put you, and the
	twelve levels of Fast Feet now take you well past the old ceiling instead of
	climbing back to it.
]]
Config.BaseWalkSpeed = 25

-- ── First session ───────────────────────────────────────────────────────────
--[[
	Your first N BANKED drops are guaranteed: the first safe tile of a round
	always yields something until you have secured this many.

	Without it, 15% of new players bet five times, lose money and end up with an
	empty base -- the whole hook is "you found a thing and it pays you rent
	forever", and for one in seven people it never fires at all. The guarantee
	takes that to 1.4% and pulls the first bank forward from round 2.3 to 1.7.
	See tools/onboarding.py.

	Two rather than one because the retention gain is nearly all in the first
	(15% -> 1.4%, then 1.3%); the second is there to fill the base faster, which
	is what puts the 4th pad inside the first session.

	It guarantees THAT you find something, never WHAT -- the tier and variant
	still roll honestly. The multiplier is still the luck stat.

	Spent only when a drop is actually banked, so busting never burns one.
]]
Config.OnboardingDrops = 2

-- ── Auction house ───────────────────────────────────────────────────────────
--[[
	The house's standing offer on any listed brainrot is FLAT RENT: it pays
	`AuctionFloorSeconds` worth of that brainrot's income, whatever the tier.
	Linear in income on purpose -- it gives one rule that reads the same at
	every tier: KEEPING IT BEATS SELLING IT AFTER 15 MINUTES OF COLLECTED RENT.

	900 rather than something bigger because pads cap at 8 and drops far
	outrun them, so the auction's real job is liquidating brainrots you have
	nowhere to put -- where the alternative is zero -- not out-earning a pad.

	The eye-watering numbers this produces at the top (a Secret Galaxy floors
	around $594M) are not the auction's doing: that brainrot makes the same
	money in 15 minutes on a pad. Rent is what's unbounded up there. See
	tools/auction.py before changing this.
]]
Config.AuctionFloorSeconds = 900

Config.AuctionDuration = 120 -- seconds a lot stays open
Config.AuctionMaxListings = 3 -- concurrent lots per seller, stops board spam
Config.AuctionBidStep = 0.10 -- each bid must beat the last by 10%

-- A bid inside the last `AuctionSnipeWindow` seconds pushes the end out by that
-- much again, so a lot can't be stolen on the final tick. Uncapped on purpose:
-- a contested lot SHOULD run long, that's the drama.
Config.AuctionSnipeWindow = 15

-- ── The Wheel ───────────────────────────────────────────────────────────────
--[[
	One machine, one bet: EVERYTHING. All your cash and every brainrot you own,
	placed or stored, for a shot at a Secret.

	Secrets exist nowhere else. The Mines cannot roll one (Rarity marks the tier
	wheelOnly) and the auction can only ever resell one that came from here, so
	the only source in the game is this wager.

	NUMBERS WORTH KNOWING, from tools/wheel.py:

	  - The real chance of a Secret is 9.4%, not 8%. A retry re-rolls rather than
	    resolving, so the true odds are the non-retry ones renormalised.
	  - As a cash game it is atrocious: ~4.7% of the minimum stake comes back on
	    average. That is the point -- it is a sink, and the Secret is the reason.
	  - The floor only ever gates the FIRST spin. The weakest possible Secret
	    earns back 1.5M in about four minutes.

	That last one is self-correcting rather than a hole: spinning again wagers
	the Secret too, so once you hold a good one the bet is terrible and you stop.
	The wheel is attractive exactly while you have little to lose.
]]
Config.WheelMinStake = 1500000
Config.WheelCashPrize = 200000
Config.WheelRange = 34 -- how close you must stand

--[[ The wheel takes over a player base's footprint. That base is demolished at
     startup, so the map supports seven plots instead of eight. ]]
Config.WheelReplacesBase = "Base7"


-- Must sum to 1. Order is the display order on the wheel face.
Config.WheelOdds = {
	{ id = "secret", chance = 0.08, label = "SECRET" },
	{ id = "retry", chance = 0.15, label = "RETRY" },
	{ id = "cash", chance = 0.30, label = "$200K" },
	{ id = "nothing", chance = 0.47, label = "BUST" },
}

-- ── Rebirth ─────────────────────────────────────────────────────────────────
--[[
	Modelled in tools/rebirth.py before any of it was built. See Shared/Rebirth
	for what the numbers mean and which of them overturned a guess.

	Cost growth is the income growth read back: income rises 1.34x a rebirth, so
	anything above ~1.35 outruns the player and the loop stalls. Base only sets
	where the ladder starts -- lower it if 13 hours to the first reads long.
]]
Config.RebirthBaseCost = 150000000
Config.RebirthCostGrowth = 1.35
Config.RebirthLuckPerLevel = 0.35 -- bonus drop depth, permanently
Config.RebirthPadsPerLevel = 1
Config.RebirthMaxStartPads = 6 -- short of MaxSlots: still a base to build

-- ── The Sky ─────────────────────────────────────────────────────────────────
--[[
	The jetpack, which opens the islands above the map.

	ONE FLAT PRICE. An earlier plan tiered it -- $2M for the first island up to
	$470M for the last -- so that altitude itself paced the climb. That put
	thirty hours between a new player and the top of the map and made flying
	cost more than the entire upgrade tree, which is the wrong shape for a thing
	whose job is to open the game up rather than to be the game.

	A million lands about 45 minutes in if every dollar goes to it, and realistically
	early in the second session, since all eight pads cost about the same and pay
	rent back. Early enough to be a goal you can see from the ground; far enough
	that it isn't handed to you.

	The consequence, worth stating where the number lives: altitude no longer
	gates anything. Everyone is flying within the hour, so the ISLANDS have to be
	paced by their seals -- each one asking for the seal earned on the island
	below -- rather than by the right to reach them. See tools/altitude.py.
]]
Config.JetpackCost = 1000000

--[[ Bought once and owned forever. It is a way to reach the game rather than a
     consumable, and metering it per flight would turn every trip upward into a
     small purchase decision -- exactly the friction that keeps people on the
     ground. One payment, then the sky is simply open. ]]

Config.FlightSpeed = 74 -- horizontal cruise, about 3x walking
Config.FlightRise = 46 -- climb rate on the boost key
Config.FlightCeiling = 900 -- islands live under this; above it you stop climbing
Config.TakeoffSeconds = 1.4 -- the scripted rise before you get the controls
Config.TakeoffRise = 62 -- and how fast that opening climb goes

-- ── Plinko ──────────────────────────────────────────────────────────────────
--[[
	The first island's machine. Expensive on purpose: this is not an income
	source, it is the toll on a chapter, and a cheap drop would make the seal a
	formality rather than a decision.

	See Shared/Plinko for the board and tools/plinko.py for the modelling. The
	headline the UI has to be able to state: 85.2% back, 7% of drops carry a
	fragment, five fragments to a seal.
]]
Config.PlinkoDropCost = 450000
Config.PlinkoRange = 26 -- how close you must stand to the machine

-- ── Codes ───────────────────────────────────────────────────────────────────
--[[
	Redeemable codes. Each one is once per player, recorded in the profile.

	`testOnly` is the important field. A code that hands out eight figures is
	fine while you're testing the wheel and catastrophic the day the game goes
	public with it still in the table -- so those only work in Studio, or for a
	UserId listed in CodeAdmins. Ordinary codes have no such gate.

	Matching is case-insensitive and trims whitespace, because players paste
	codes out of videos with a trailing space more often than not.
]]
--[[
	One code per rebirth, and three of them rather than one big one, because a
	rebirth resets money to StartingMoney -- banking the total up front would
	be spent entirely on the first and leave nothing for the second.

	Each covers its own rebirth plus the eight pads that rebirth also demands,
	with a little slack. Derived from the same constants the cost curve uses, so
	retuning RebirthBaseCost or the growth rate carries these along instead of
	quietly leaving them short.
]]
for level = 0, 2 do
	local cost = Config.RebirthBaseCost * (Config.RebirthCostGrowth ^ level)
	local pads = 0
	for step = 0, Config.MaxSlots - Config.StartingSlots - 1 do
		pads += Config.SlotBaseCost * (Config.SlotCostGrowth ^ step)
	end
	Config.Codes["REBIRTH" .. (level + 1)] = {
		money = math.floor((cost + pads) * 1.05),
		testOnly = true,
		blurb = "enough for rebirth " .. (level + 1),
	}
end

Config.CodeAdmins = { 873380891 } -- UserIds that may redeem testOnly codes live

Config.Codes = {
	RELEASE = { money = 2500, blurb = "thanks for playing" },
	BRAINROT = { money = 1000, blurb = "a little starter cash" },

	--[[
		Every Secret in the roster, one each, Normal variant.

		`secrets = true` rather than a hardcoded pair of ids, so adding a third
		Secret to Brainrots.lua extends this code automatically instead of
		leaving it silently short.

		testOnly, obviously. Handing these out free on a live server would empty
		the wheel of its only reason to exist.
	]]
	SECRETS = { secrets = true, testOnly = true, blurb = "every Secret, one each" },
}

--[[
	SPIN1 .. SPIN10 -- ten test codes, each worth exactly one wager.

	One code per spin rather than one big grant, because that is what actually
	exercises the wheel: redeem, commit everything, lose it, redeem the next.
	A single lump sum would leave change sitting in the wallet after a bust and
	the next spin would no longer be a clean all-in.

	Pinned to WheelMinStake, so retuning the entry price retunes the codes with
	it and they can never drift into being worth less than a spin.
]]
for i = 1, 10 do
	Config.Codes["SPIN" .. i] = {
		money = Config.WheelMinStake,
		testOnly = true,
		blurb = "one spin of the wheel",
	}
end

-- ── Events ──────────────────────────────────────────────────────────────────
-- Gap between events, randomised in this range. The gap AND the event type are
-- both rolled the moment the previous event ends, so the countdown shown to
-- players is a real deadline rather than a guess.
--
-- These are the GAP, not the cycle. Average event duration is ~88s, so a 270s
-- average gap puts an event start every 6.0 minutes with ~25% uptime. Raising
-- these without re-running tools/balance.py will quietly drift that number.
Config.EventGapMin = 180
Config.EventGapMax = 360

-- ── Data ────────────────────────────────────────────────────────────────────
Config.DataStoreName = "BrainrotMines_Profiles_v1"
Config.AutoSaveInterval = 120

return Config
