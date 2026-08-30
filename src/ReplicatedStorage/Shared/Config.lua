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

--[[
	MINE COUNT NO LONGER LIFTS RARITY DIRECTLY, and this is 0 for that reason.

	It was 0.16 a mine, which forced a floor under the drop depth so a 12-mine
	board rolled as though it were already at 3.8x. That was added to make a
	dangerous board feel rarer, and it did -- but it also meant two things set
	your luck, and the first design pillar is that the MULTIPLIER is the luck
	stat. A board could be generous before you had risked anything.

	Mines still make you luckier; they do it the honest way. More mines means a
	steeper multiplier per pick, a deeper depth by the time you cash out, and a
	better roll. The luck comes from the risk you actually took.

	Kept as a knob rather than deleted so the behaviour can be dialled back in
	without re-threading it through DropTable. Re-run tools/balance.py after
	touching it.
]]
Config.DropQualityPerMine = 0

--[[
	THE BET IS THE OTHER HALF OF THE RISK, so it lifts drop QUALITY too.

	Mine count and multiplier were the only things that touched rarity, which
	meant a player shoving their whole balance onto one board got exactly the
	same brainrots as one betting the ten-dollar minimum. The bet is the purest
	statement of how much you are risking and it was worth nothing.

	A FLOOR, NOT A BONUS, and this is the distinction the mine version got
	wrong twice. Added to depth it COMPOUNDS with a deep run: modelled, a 100x
	cash-out at a ten-million bet took Secret from 1 in 665 to 1 in 187, which
	would have quietly undone the rarity pass. As a floor it lifts the shallow
	reveals -- where nearly every drop actually happens -- and does nothing once
	the multiplier has climbed past it, so the deep economy is untouched at
	every bet size. Modelled at 12 mines: a first-pick drop goes from 13.6% to
	31.4% rare-or-better, while 30x and 100x cash-outs come out identical.

	LOGARITHMIC AND CAPPED. Bets span the minimum of 10 to hundreds of millions,
	so anything linear is either nothing at the bottom or unbounded at the top.
	log2(bet / MinBet) * 0.20, capped at 3.5 -- so ten million buys a floor
	equivalent to an 11x multiplier, and a billion buys exactly the same. The
	cap is what stops this becoming a way to purchase the top of the table.
]]
Config.DropQualityPerBet = 0.20
Config.DropQualityBetCap = 3.5

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

--[[
	A flat multiplier on EVERY brainrot's rent, applied once inside
	Economy.incomeOf so the pad billboard, the HUD, the drop card and the actual
	payout all move together -- nothing reads a tier's income directly.

	Here rather than doubled into Rarity's per-tier numbers, because those are
	the shape of the tier curve and this is a decision about the whole economy's
	pace. Keeping them apart means the curve can be retuned without re-deriving
	what the global rate was, and this can be moved again without touching seven
	tiers.

	NOTHING ELSE MOVED WITH IT. Pads, upgrades, the Plinko ball, Plinko drops and
	rebirth all still cost what they did, so raising this shortens the time to
	every one of them in proportion.
]]
Config.IncomeMultiplier = 2

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
-- upgrade shop counter.
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

-- ── The Wheel ───────────────────────────────────────────────────────────────
--[[
	YOU CHOOSE WHAT TO STAKE, AND ONLY MONEY IS AT RISK.

	It used to be one bet: everything, cash and every brainrot you owned, for a
	flat 9.4% shot at a Secret. Two things were wrong with that. Losing a
	collection you had spent hours placing is a punishment nobody comes back
	from, and a flat chance at a 1.5M floor made the wheel the CHEAP route to a
	Secret -- about 16M expected, against the Mines' thousands of drops.

	Now the Secret chance rises linearly with the stake, from nothing to
	WheelSecretMaxChance at WheelSecretCapStake. Brainrots are never wagered.

	THE NUMBER THAT MATTERS: expected money spent per Secret is
	WheelSecretCapStake / WheelSecretMaxChance -- $1.2B, constant at every
	stake. The dial buys variance, not value. Two spins of 600M and eight
	hundred of 1.5M cost the same in expectation; what differs is how long you
	are willing to be uncertain.

	That constant is also what makes this a sink worthy of the rarest tier:
	$1.2B is about eight rebirths.
]]
Config.WheelMinStake = 1500000

--[[ The stake at which the Secret chance reaches its ceiling, and that
     ceiling. Half, rather than a certainty, so the biggest possible bet is
     still a bet. ]]
Config.WheelSecretCapStake = 600000000
Config.WheelSecretMaxChance = 0.50

--[[ The consolation, as a FRACTION OF THE STAKE rather than a flat 200K.
     Flat made sense when every spin cost the same; against a stake that ranges
     four hundredfold it would have paid a rounding error on a big bet and most
     of the stake back on a small one. ]]
Config.WheelCashReturn = 0.5

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

--[[
	WHAT EACH REBIRTH OPENS, and why depth alone was not enough.

	RebirthLuckPerLevel is a depth bonus, and depth lifts the whole curve at
	once -- which sounds right and plays wrong. +0.35 is worth about 1.26x on
	the top tiers, so three rebirths roughly DOUBLED a Mythic: 1 in 605 became
	1 in 279 on a typical 8x cash-out. Three rebirths is a quarter of a billion
	spent and the collection wiped twice over, and doubling a number that was
	already 1 in 605 is invisible from inside the game. The reward was real and
	unfeelable, which is the same as not being there.

	So each rebirth now OPENS A TIER outright, on top of the depth it already
	gave. The promise is legible before you pay for it -- one rebirth for
	Legendaries, two for Mythics, three for Secrets -- and it lands as a step
	rather than a slope you need a spreadsheet to notice:

		         Legendary     Mythic      Secret
		reb 0     1 in 74      1 in 605    1 in 8,202
		reb 1     1 in 13      1 in 495    1 in 6,657
		reb 2     1 in 11      1 in 56     1 in 5,247
		reb 3     1 in  9      1 in 45     1 in 413

	A WEIGHT MULTIPLIER, NOT MORE DEPTH, because depth is the multiplier's job
	and doubling up on it would make a deep run pay twice for the same risk.
	This rides the `tierMul` axis events already use, so a lucky player and a
	lucky server are one mechanism.

	THE BOOST DOES NOT GROW AFTER IT OPENS. It does not need to -- the depth
	bonus keeps compounding underneath it, which is what carries Mythic from
	1 in 56 at rebirth 2 to 1 in 24 by rebirth 6. Letting both grow put the
	expected income of a drop at 19x by rebirth 6 against the 5.8x the cost
	curve is built for, and a rebirth ladder that gets cheaper as you climb it
	is not a ladder.
]]
Config.RebirthTierBoost = {
	Legendary = { rebirth = 1, weight = 5 },
	Mythic = { rebirth = 2, weight = 7 },
	Secret = { rebirth = 3, weight = 10 },
}

-- ── The Sky ─────────────────────────────────────────────────────────────────
--[[
	The Plinko ball, which opens the first island above the map.

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
--[[ What the jetpack used to cost, and for the same reason: it is the first
     big purchase, the thing the early game is saving toward. Buying it is what
     opens the second half of the game. ]]
Config.PlinkoBallCost = 1000000

--[[
	THE TWO VANITY ITEMS, and they are priced like trophies rather than tools.

	Everything else in the shop buys capability -- a ball that moves you, a
	whistle that calls a ride. These buy nothing but how you look, so they sit
	ABOVE the first rebirth (150M) on purpose: the point is that somebody who
	has one has visibly been here a while. Pricing them like utilities would
	make them the first thing everyone buys and the last thing anyone notices.

	The stink is the default state, so the cologne is the one item in the shop
	that REMOVES something you were given rather than adding something you were
	not. That is why it is the cheaper of the two -- undoing a starting
	condition should cost less than rewriting your face.
]]
Config.CologneCost = 500000000
Config.PeptidesCost = 1000000000

--[[ Bought once and owned forever. It is a way to reach the game rather than a
     consumable, and metering it per flight would turn every trip upward into a
     small purchase decision -- exactly the friction that keeps people on the
     ground. One payment, then the sky is simply open. ]]

Config.FlightSpeed = 74 -- horizontal cruise, about 3x walking
Config.FlightRise = 46 -- climb rate on the boost key
--[[ Kept as a NUMBER even though nothing enforces it any more. Flight is gone,
     so there is no ceiling to hit -- but the islands were sited against this
     value and Islands.lua still explains itself in terms of it, and deleting
     it would leave those comments pointing at nothing. ]]
Config.FlightCeiling = 900
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
--[[ The MINIMUM stake now, not the only one -- the player picks anything from
     here upward. The name is kept because it is still what a drop costs if you
     never touch the dial, and renaming it would churn six call sites to say
     the same thing. ]]
Config.PlinkoDropCost = 450000

--[[
	And the ceiling, which exists because of the 1000x bin.

	A stake with no cap and a four-figure multiplier is not a game, it is a
	money printer waiting for one lucky drop: at ten million staked, a single
	edge bin returns ten billion, which is sixty-six rebirths from one ball.
	Twenty times the minimum puts the best possible drop at nine billion --
	still enormous, still worth chasing, and about one drop in thirty-three
	thousand rather than one in twenty-eight.

	Expressed as a multiple so it follows the minimum if that is ever retuned.
]]
Config.PlinkoMaxStakeMultiple = 20
Config.PlinkoRange = 26 -- how close you must stand to the machine

-- ── Racing ──────────────────────────────────────────────────────────────────

--[[ Fixed per race, like a Plinko drop, so the FIELD is the dial rather than
     the stake. Expected value is scale-invariant anyway -- letting players pick
     a number would add a second knob that changes nothing about the odds. ]]
Config.RaceStake = 250000

--[[ Long enough that a lead can change hands and be worth watching, short
     enough to run many times. The payout lands on the same beat as the finish;
     see RaceService. ]]
Config.RaceSeconds = 14

-- ── Fighting ────────────────────────────────────────────────────────────────

--[[
	There was no combat in this game at all before duels, so all of this is
	new ground and the numbers are set to make a THIRTY SECOND fight readable
	rather than to model anything.

	At 9 damage on a 0.55s swing, a clean hit rate empties 100 health in about
	seven seconds -- so a duel is roughly four exchanges long if both players
	are landing everything, and nobody is knocked out by two lucky hits. The
	clock, not the health bar, is what ends it.
]]
Config.PunchDamage = 9
Config.PunchCooldown = 0.55
--[[ Generous, because the server is checking a distance the client has already
     acted on and the two are a ping apart. Deliberately shorter than the
     ProximityPrompt ranges elsewhere: a punch that lands from further away
     than you can read a sign would feel like being shot. ]]
Config.PunchRange = 11
--[[ How far off straight-ahead a swing may still connect. cos(50 degrees),
     compared against the dot product, so it is a cone and not a sphere --
     otherwise you would hit people behind you. ]]
Config.PunchArc = 0.64

--[[
	THE DASH.

	Speed and time multiply out to roughly 13 studs of ground covered, which is
	a little over one dash of separation in the arena and about a second and a
	half of walking. Long enough to be worth pressing, short enough that four
	of them do not cross the street.

	The cooldown is what stops it being a movement speed upgrade: at 1.15s
	against a 0.22s dash, chaining them averages out slower than the walk you
	already have, so dashing is for closing a gap rather than for travelling.
]]
Config.DashSpeed = 58
Config.DashTime = 0.22
Config.DashCooldown = 1.15

--[[
	THE ARENA'S SKY, from asset 570559352.

	Shared rather than server-side because it is applied on the CLIENT: Lighting
	is global, so swapping it on the server would hang a night sky over the
	whole game -- the street, the islands, everyone. The two fighters get it on
	their own clients for the length of the duel and it is put back afterwards,
	the same way Braziers lights shared geometry for one player at a time.

	Stored as the raw ids rather than as a Sky instance, so nothing has to be
	replicated or parented anywhere to make it available.
]]
Config.ArenaSky = {
	SkyboxBk = "http://www.roblox.com/asset/?id=570557514",
	SkyboxDn = "http://www.roblox.com/asset/?id=570557775",
	SkyboxFt = "http://www.roblox.com/asset/?id=570557559",
	SkyboxLf = "http://www.roblox.com/asset/?id=570557620",
	SkyboxRt = "http://www.roblox.com/asset/?id=570557672",
	SkyboxUp = "http://www.roblox.com/asset/?id=570557727",
	StarCount = 3000,
	CelestialBodiesShown = false,
}

--[[
	CRITICAL HITS. One punch in ten lands for double.

	Rolled on the SERVER at the moment damage is applied, not at the swing:
	a crit is a property of a hit, and rolling it early would mean a whiff
	could "be" a crit. It is also the only reason the roll cannot live on the
	client -- a client that picks its own crits picks all of them.

	The chance is what was asked for. THE MULTIPLIER IS AN ASSUMPTION: 2x, so a
	crit takes 18 off a 100 health pool instead of 9, which is noticeable
	without making a duel a coin flip -- across a thirty second fight it is
	worth roughly one extra landed punch. Change the number here if it should
	hit harder or softer.
]]
Config.PunchCritChance = 0.10
Config.PunchCritMultiplier = 2

--[[ How long a gap resets the M1 combo back to its first hit. Shared, because
     the server picks the sound off this and the client picks the matching
     animation off it -- two copies of the number would eventually mean the
     fourth punch playing the first punch's sound. ]]
Config.PunchComboReset = 1.6

--[[ A street fight is remembered only long enough to notice a reply. Hit
     someone and wander off, and thirty seconds later there is nothing to
     answer -- which is what stops a punch thrown across the map at someone
     you have forgotten about from opening a wager prompt. ]]
Config.StreetFightMemory = 30

--[[ Nobody is dragged into this. Both of these exist so a player who never
     wants to fight can turn duels off and be left alone; the offer is simply
     never raised against them. ]]
Config.DuelsDefaultOn = true

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

	--[[ Everything needed to stand on the racing island: the seal that opens
	     it, something worth summoning, and money to stake once you are up
	     there. Earning this legitimately is about 69 Plinko drops, which is the
	     wrong price for looking at the island once. ]]
	SKYPASS = {
		seals = { "plinko" },
		secrets = true,
		money = 5000000,
		testOnly = true,
		blurb = "the Plinko saddle, a Secret to ride, and stake money",
	},
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

--[[
	One code per rebirth, and three of them rather than one big one, because a
	rebirth resets money to StartingMoney -- banking the total up front would
	be spent entirely on the first and leave nothing for the second.

	Each covers its own rebirth plus the eight pads that rebirth also demands,
	with a little slack. Derived from the same constants the cost curve uses, so
	retuning RebirthBaseCost or the growth rate carries these along instead of
	quietly leaving them short.

	DEFINED AT THE END OF THE FILE, after Config.Codes exists. Anchored above
	it first, where Config.Codes is still nil, and indexing that took the whole
	module down -- Bootstrap and ClientMain both failed to load and every
	remote call timed out, which looks nothing like a typo in a code table.
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

--[[ Hear the top of the range without grinding for it. Each forces the next
     few Mines drops to a tier, so the real drop path fires and the real sting
     with it -- granting the brainrot outright would hand you the item and none
     of the sound. ]]
Config.Codes.HEARLEGEND = { forceTier = "Legendary", forceDrops = 3, testOnly = true,
	blurb = "next 3 drops are Legendary" }
Config.Codes.HEARMYTHIC = { forceTier = "Mythic", forceDrops = 3, testOnly = true,
	blurb = "next 3 drops are Mythic" }
Config.Codes.HEARSECRET = { forceTier = "Secret", forceDrops = 3, testOnly = true,
	blurb = "next 3 drops are Secret" }

return Config
