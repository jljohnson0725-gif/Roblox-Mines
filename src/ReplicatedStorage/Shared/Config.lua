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

-- CollectionService tag on placed brainrot models. Lives here because the
-- server applies it and the client animates by it, and they must not drift.
Config.BrainrotTag = "BrainrotModel"

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
