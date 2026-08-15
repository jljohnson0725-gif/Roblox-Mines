"""
Model the Plinko board: bin odds, house edge, and what a seal actually costs.

A ball falling through N rows of pegs is a binomial walk, so the bin odds are
not a design choice -- they fall out of the row count and cannot be argued
with. What IS a choice is the payout on each bin and which bins carry a seal
fragment, and those two together decide both how the machine feels and how long
the island gates the player.

The trap this exists to avoid: staking is not the same as spending. A player
re-stakes winnings, so the real cost of a seal is the expected NET loss over
however many drops it takes, not the headline sum of the drops.

Run: python tools/plinko.py
"""

import math
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "src" / "ReplicatedStorage" / "Shared"


def money(v):
    for unit, size in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(v) >= size:
            return f"${v/size:,.2f}{unit}"
    return f"${v:,.0f}"


# ── the board ───────────────────────────────────────────────────────────────

ROWS = 8  # peg rows; bins = ROWS + 1


def bin_odds(rows):
    """Binomial. Bin i is reached by i right-bounces out of `rows`."""
    total = 2 ** rows
    return [math.comb(rows, i) / total for i in range(rows + 1)]


#[[ Payout multiple per bin, and whether that bin yields a seal fragment.
#   Symmetric, high at the edges: that shape is what makes people aim for the
#   outside and what makes a centre landing feel like a near miss. ]]
PAYOUT = [12.0, 3.2, 1.3, 0.5, 0.2, 0.5, 1.3, 3.2, 12.0]
FRAGMENT = [True, True, False, False, False, False, False, True, True]

DROP_COST = 450_000
FRAGMENTS_PER_SEAL = 5


def main():
    odds = bin_odds(ROWS)
    print(f"{ROWS} peg rows -> {len(odds)} bins\n")
    print(f"  {'bin':<5}{'chance':>9}{'pays':>8}{'fragment':>11}{'EV share':>11}")

    ev = 0.0
    frag_chance = 0.0
    for i, p in enumerate(odds):
        share = p * PAYOUT[i]
        ev += share
        if FRAGMENT[i]:
            frag_chance += p
        print(f"  {i:<5}{p*100:>8.2f}%{PAYOUT[i]:>7.1f}x"
              f"{('yes' if FRAGMENT[i] else '-'):>11}{share:>11.3f}")

    edge = 1 - ev
    print(f"\n  return to player {ev*100:.1f}%   house edge {edge*100:.1f}%")
    print(f"  fragment chance  {frag_chance*100:.2f}% per drop")

    # ── what a seal costs ───────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("WHAT A SEAL COSTS")
    print("=" * 70)

    drops = FRAGMENTS_PER_SEAL / frag_chance
    staked = drops * DROP_COST
    net = staked * edge

    print(f"""
  {FRAGMENTS_PER_SEAL} fragments at {frag_chance*100:.2f}% a drop -> {drops:.0f} drops on average
  staked   {money(staked)}   (cycled through the machine, not spent)
  NET COST {money(net)}   (what the house actually keeps)
""")

    print("  Staked is the number that looks frightening and the wrong one to")
    print("  design against -- winnings are re-staked, so the machine only ever")
    print("  takes the edge. Net cost is what gates the island.\n")

    # against the income curve from altitude.py
    for label, hours, rate in (("2h player", 2, 1.70e3), ("8h player", 8, 7.78e3),
                               ("16h player", 16, 13.76e3)):
        print(f"  {label:<12} earns {money(rate)}/s -> "
              f"{net / rate / 60:.0f} min of income for one seal")

    # ── variance: the thing that killed the old 10% key gate ────────────────
    print("\n" + "=" * 70)
    print("DOES LUCK DECIDE? (the 10% key gate needed 6.3x for the unluckiest)")
    print("=" * 70)

    # negative binomial: drops needed for FRAGMENTS_PER_SEAL successes
    import random
    rng = random.Random(7)
    runs = []
    for _ in range(20000):
        got, n = 0, 0
        while got < FRAGMENTS_PER_SEAL:
            n += 1
            if rng.random() < frag_chance:
                got += 1
        runs.append(n)
    runs.sort()
    med = runs[len(runs) // 2]
    p90 = runs[int(len(runs) * 0.90)]
    p99 = runs[int(len(runs) * 0.99)]
    print(f"""
  median          {med:>4} drops
  unluckiest 10%  {p90:>4} drops   {p90/med:.1f}x the median
  unluckiest 1%   {p99:>4} drops   {p99/med:.1f}x the median

  Needing FIVE of something is what flattens this. A single 10% roll has no
  memory and no floor -- the unluckiest 1% waited 6.3x. Asking for five
  averages the luck out, and the tail comes in with it.
""")


if __name__ == "__main__":
    main()
