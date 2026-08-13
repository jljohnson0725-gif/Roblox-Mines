# Brainrot Mines — Design

Source of truth for direction. `README.md` is setup and workflow only.

A Mines-style gambling game where the payout is **brainrots**, not just cash.
You bet, you reveal tiles, and every safe tile might hand you a character. Bank
them and they stand on your plot paying rent forever. Hit a mine and you lose
everything the run gave you.

---

## The loop

```
brainrots on your plot  ──pay passive income──▶  cash
        ▲                                         │
        │                                         │
    cash out                                   place a bet
        │                                         │
        └──────  reveal tiles, find brainrots  ◀──┘
                    (deeper = better drops)
```

The gamble is the **acquisition** loop. The plot is the **progression** loop.
Neither works alone: without the plot, winning a Legendary means nothing; without
the gamble, the plot is an idle game with no decisions in it.

---

## Four pillars — don't simplify these away

### 1. Your multiplier IS your luck stat

The Mines payout multiplier and the drop-rarity odds are driven by the same
number. `DropTable` takes `L = log2(multiplier)` and scales every tier's weight
by `growth ^ L`.

| multiplier | Common | Rare  | Legendary | Mythic | Secret |
|-----------:|-------:|------:|----------:|-------:|-------:|
| 1×         | 64.2%  |  7.7% |     0.39% |  0.05% | 0.003% |
| 16×        | 31.3%  | 20.5% |     4.59% |  1.22% |  0.14% |
| 256×       |  5.8%  | 20.5% |    20.56% | 10.84% |  2.19% |

This is why "cash out or click one more" is a real decision instead of an
arithmetic problem. If drops were a flat table, the deep end of a run would
carry risk with no matching pull, and everyone would bank at two tiles forever.

### 2. Brainrots are unsecured until you cash out

Anything you find mid-run sits in `round.unsecured`. It enters your inventory
**only** on a successful cash-out. A mine drops the bet *and* every brainrot the
run produced.

The MinesUI "AT RISK" panel exists to keep this in the player's face, and the
drop banner deliberately says **FOUND**, never "won". The moment brainrots
become safe on reveal, the deep end of the board stops being frightening and the
whole game deflates.

### 3. Drop chance scales with mine count

`dropChance = 0.06 + 0.04 × mines`, capped at 0.90.

This one is counterintuitive and load-bearing. Because brainrots are lost on a
bust, *survival* is what drives value — so with a flat drop chance, 1 mine is
about **10× better value per round** than 24 and the mine selector is purely
decorative. Scaling frequency with danger flattens expected value to a **1.3×
spread** across the whole range:

| mines | drop% | best depth | P(reach) | rel. value |
|------:|------:|-----------:|---------:|-----------:|
|     1 |   10% |         15 |   40.0%  |      0.88  |
|     5 |   26% |          7 |   16.1%  |      0.77  |
|    12 |   54% |          6 |    0.97% |      0.89  |
|    20 |   86% |          3 |    0.44% |      1.00  |

EV is flat; **variance is not**. One mine drips small drops constantly. Twenty
mines pays enormously in 0.4% of rounds. That is what a risk dial is supposed to
do — offer a different shape, not a better deal.

Re-run `python tools/balance.py` after touching any tuning number. It prints the
spread and flags anything above 1.6×.

### 4. Two axes: character tier × variant

A drop rolls a **tier** (which picks a character) and a **variant**,
independently. Income is `tier.income × character.mul × variant.mult`.

That means a Common can show up Galaxy and a Secret can show up Normal, and the
collection has 29 characters × 7 variants of depth from a small roster. Variants
roll on a flatter curve than tiers so deep runs don't double-dip.

One of those seven, `Frost`, has base weight 0 and exists only during the Winter
Freeze event — see the Events section below.

Range: Common Normal at **$2/s** to Galaxy Secret at **$660K/s**.

---

## Economy shape

- **Cash is deliberately -EV.** 3% house edge on the payout curve. Cash is the
  entry fee; brainrots are the real reward. The money faucet is the *plot*, not
  the table.
- **Pad slots are the money sink.** Start with 3, max 8, cost `2500 × 4.2^n` —
  $2.5K, $10.5K, $44K, $185K, $778K, about **$1.02M** to max out. Sized to the
  imported map, which gives each base exactly 8 pedestals. Fewer pads than the
  original 20 makes each unlock a real moment, and makes "which eight do I
  display" an actual decision instead of "display everything".
- **Anti-softlock floor.** Broke with nothing placed → topped up to $50. It's a
  floor, not a faucet: you must lose below $10 to trigger it, so it can't be
  farmed.

Chase timings at casual play (3 mines, bank at 4 tiles, ~20s/round):

| tier | rounds each | playtime |
|------|------------:|---------:|
| Rare        |     27 |  0.2h |
| Epic        |     99 |  0.5h |
| Legendary   |    456 |  2.5h |
| Mythic      |  3,151 | 17.5h |
| Secret      | 46,947 |   11d |

---

## Architecture notes

- **The server is the only authority.** The board is generated in full at round
  start, not decided per click, so the server can't rig a reveal after seeing
  your pick. The client never learns mine positions until the round ends.
- **`Economy.lua` is the single source of income truth.** Server and client both
  use it, so a pad billboard can never disagree with what the server pays.
- **Sync payloads merge, they don't replace.** That's what lets the per-second
  income tick send `{money = n}` instead of the whole inventory.
- **Placeholder-first art.** `ModelFactory` builds blocky stand-ins so the game
  is playable with zero assets. Drop real models into
  `ReplicatedStorage/BrainrotModels` named by character `id` and it picks them
  up with no code change.

- **`PlotService` has two modes.** If `Workspace/Bases/BaseN` exists (the
  imported map), it **attaches** to that geometry: each base already ships 8
  slot pedestals, a `Spawn`, an `Owner` marker and a `CollectZone`, so we bind
  to them and build nothing. With no `Bases` folder it **generates** ground,
  plots and tiered shelves in code, so the game still runs on a blank baseplate.
  Both modes produce the same `plot` shape, so rendering, placement and
  unlocking are written once.

  **Pad order is load-bearing.** Pad indices are persisted, so a brainrot on
  pad 3 must come back on pad 3. The map names all eight slots `Slot1`, and
  `GetChildren()` order isn't guaranteed stable — so pads are sorted by world
  position (X then Z), which is deterministic across sessions.

  The map caps pads at 8 regardless of `Config.MaxSlots`; `padCapacity()` is
  the real limit and everything clamps to it.

---

## Build order

**Done (v1)** — Mines rounds, two-axis drop system, plots with tiered shelf
display, passive income, pad unlocks, persistence, full code-built UI, audio
and the rarity-scaled drop spectacle, server-wide timed events, Equip Best.

### Events

Server-wide, one event at a time, starting every **6.0 minutes** on average and
running **24%** of the time. Type is weighted-random: `Lucky Streak` is 36% of
events, `Cosmic Alignment` is 1.1% (roughly one every nine hours). Rarer event,
bigger swing — Cosmic pushes Galaxy variants from 3% to 82% at a 256× multiplier.

**The next event is pre-rolled.** "Chance-based" and "show me a countdown" pull
against each other: if you roll when the timer expires, the timer is really
"next dice roll" and might yield nothing. So both the gap length and the event
type are decided the instant the previous event *ends*. The countdown is then a
real deadline and the chance is fully intact — it just resolved earlier than it
was displayed.

**The upcoming type is deliberately hidden.** Showing "Cosmic in 3:40" would
teach players to stop playing and wait, which is the exact trap flagged below.
You see the clock, not the prize.

Events bend knobs that already exist — `dropChanceMul`, `depthMul`,
`variantMul`, `variantAdd` — and add no parallel systems. `depthMul` scales
*L* rather than the growth exponents, which amplifies each tier's existing
direction (Common shrinks faster *and* Secret grows faster). Adding to the
exponents instead would drag Common's 0.72 toward 1.0 and make commons more
likely, which is backwards.

**`Frost` is the event-exclusive proof of concept.** Base weight `0`, surfaced
only by Winter Freeze's `variantAdd`. That's why the modifier is additive rather
than multiplicative — zero times anything is still zero. It's unobtainable at
every depth outside the event and 4–38% inside it, and because its base weight
is 0 it perturbs the base economy by exactly nothing (verified in `balance.py`).
Copy that shape for any future event-locked variant.

### A note on the spectacle

`Sounds.Spectacle` scales five things by tier — shake, flash, confetti, stinger
pitch, and hold duration — and Common/Uncommon get **level 0: nothing**. That's
deliberate. Commons are ~64% of drops at low multipliers; celebrating them would
train players to ignore celebrations, and a Legendary needs to land differently
from the thing you see every third tile.

Mythic and Secret broadcast to the whole server, and the loss broadcasts too.
Announcing a find without ever announcing the bust would make the risk invisible
to everyone except the person taking it — the server watching someone sit on an
unsecured Secret is the best drama the game has.

The reveal sound is pitched up one semitone per safe tile, so a run plays as a
rising scale. That's the cheapest tension in the build and it survives any
sample you swap in.

**Next, roughly in order of value:**

1. **Collect piles.** Income accrues into a visible pile on the plot you walk
   over to bank. Currently it auto-credits, which is safe but has no texture.

2. **Collection index.** A "seen / owned" grid over all 29 × 7 combos, now that
   events add exclusive variants worth chasing. Cheap to build, and it converts
   the two-axis system into a visible goal.

   **The trap to keep watching:** if events become strictly better, players
   learn to idle between them and the base game dies for three of every four
   minutes. Current events change the *shape* of the drop table (this variant
   is pouring right now) more than its raw magnitude, which is what keeps base
   play worth doing. Preserve that when adding new ones.

3. **More event types.** The pattern is one table entry in `Events.lua`.
   Obvious gaps: a tier-focused event (Epic Hour), and a genuinely rare one
   that stacks both axes at once.

4. **Group reward.** `Player:IsInGroup(groupId)` — needs a group ID. Keep it
   small and mostly cosmetic (one free pad, or a group-exclusive variant).
   A large group-gated income boost is pay-to-win by proxy and makes the
   ungrouped experience feel broken.

5. **Robux starter packs.** Developer Products / Game Passes. Two design
   constraints worth deciding before building:

   - **Sell pads, not cash.** Pads are permanent utility. Cash is gambling
     stake — selling it converts Robux directly into Mines bets, which is the
     part that draws scrutiny and also the part that unbalances the economy,
     since cash is deliberately -EV at the table.
   - **Fixed contents, not randomised.** Roblox requires disclosed odds on paid
     random items, and a casino-style core loop plus paid loot boxes is a
     policy-sensitive combination. A pack of "X pads + a named Legendary +
     starting cash" sidesteps the randomised-paid-item rules completely and is
     far easier to price.

6. **Rebirth.** The slot curve tops out at 20 pads; something has to come after.

7. **Real models + animations.** The hook-up point already exists.

8. **Trading, then stealing.** The plot is already public and per-player, which
   is the hard prerequisite. Stealing turns the flex into a risk — but do not
   ship it before collect-piles, or there's nothing to steal *from*.

**Known limitations to fix before any real launch:**

- `DataService` is **not session-locked**. Swap it for ProfileService before
  players can hop servers — the API shape (`load` / `get` / `save` / `release`)
  is deliberately drop-in compatible.
- No rate limiting on remotes. `RevealTile` is guarded against double-fire by a
  per-round `busy` flag, but a determined client can still spam invocations.
- Plot count is fixed at 12. Fine for a 12-player server, wrong above that.
- The brainrot names are community memes. Check moderation and IP exposure
  before publishing anything with real money attached.
