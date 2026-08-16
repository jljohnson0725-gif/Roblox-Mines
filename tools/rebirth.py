"""
Where the rebirth luck number can sit before it breaks the drop table.

Rebirth grants permanent bonus DEPTH, because depth is already the knob the
game climbs rarity with -- DropTable weights each tier by growth^depth, and
depth is log2 of the round multiplier. Adding to it means every round plays as
though you had revealed more tiles than you did, which is the honest way to
express luck in a game whose stated pillar is that the multiplier IS the luck
stat.

The risk is entirely at the top. Secrets cannot leak (wheelOnly), but Mythic
pays 4,500/s against Legendary's 320 -- a 14x step. Move Mythic from rare to
routine and the income curve does not bend, it snaps.

The tier mix here is EXACT, not sampled: at a given depth the weights are
deterministic, so the shares can be computed rather than counted. Only the
income figure needs simulation, because a base holds the best 8 of everything
you have ever found.

Run: python tools/rebirth.py
"""

import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import altitude as A  # parsers read straight out of src/, so this cannot drift


#[[ Typical round depth, from altitude.py: 3 mines, cashing out around four
#   picks, multiplier ~1.68. Rebirth adds to this. ]]
BASE_DEPTH = A.DEPTH


def mix(depth):
    """Exact share of drops per tier at a given depth."""
    weights = {}
    for name in A.ROLLABLE:
        t = A.TIERS[name]
        weights[name] = t["weight"] * (t["growth"] ** depth)
    total = sum(weights.values())
    return {k: v / total for k, v in weights.items()}


def simulate_income(depth, rng, drops, pads=8):
    """Best `pads` drops out of `drops`, at this depth."""
    best = []
    for _ in range(drops):
        tier = A.weighted(A.ROLLABLE, A.TIERS, depth, rng)
        variant = A.weighted(A.VAR_ORDER, A.VARIANTS, depth, rng)
        value = (A.TIERS[tier]["income"] * rng.choice(A.MULS)
                 * A.VARIANTS[variant]["mult"])
        best.append(value)
        if len(best) > pads:
            best.sort(reverse=True)
            best = best[:pads]
    return sum(best)


def main():
    print(f"base round depth {BASE_DEPTH:.3f}  "
          f"(a 1.68x round; rebirth adds to this)\n")

    print("=" * 74)
    print("TIER MIX AS LUCK CLIMBS  (exact, not sampled)")
    print("=" * 74)
    header = "  ".join(f"{n[:6]:>7}" for n in A.ROLLABLE)
    print(f"  {'bonus':<7}{header}")

    for bonus in (0.0, 0.35, 0.70, 1.05, 1.40, 1.75, 2.50):
        m = mix(BASE_DEPTH + bonus)
        row = "  ".join(f"{m[n]*100:6.2f}%" for n in A.ROLLABLE)
        print(f"  +{bonus:<6.2f}{row}")

    print("""
  Read the Mythic column. That is the one that decides this: it pays 4,500/s
  against Legendary's 320, so its share sets the ceiling of the whole economy.
""")

    # ── where does Mythic stop being rare ────────────────────────────────────
    print("=" * 74)
    print("WHERE THE NUMBER HAS TO SIT")
    print("=" * 74)

    def mythic_at(bonus):
        return mix(BASE_DEPTH + bonus).get("Mythic", 0)

    base_share = mythic_at(0)
    print(f"\n  Mythic share at rebirth 0: {base_share*100:.3f}% of drops")

    for target in (0.01, 0.02, 0.05, 0.10):
        lo, hi = 0.0, 8.0
        for _ in range(60):
            mid = (lo + hi) / 2
            if mythic_at(mid) < target:
                lo = mid
            else:
                hi = mid
        print(f"  Mythic reaches {target*100:>5.1f}% of drops at bonus depth {lo:.2f}")

    # ── what that does to a finished base ────────────────────────────────────
    print("\n" + "=" * 74)
    print("INCOME OF A FULL BASE, 8 HOURS IN  (median of 250 players)")
    print("=" * 74)
    print(f"\n  {'rebirths':<10}{'bonus':<8}{'income/s':>12}{'vs rebirth 0':>14}")

    rng = random.Random(11)
    drops = int(8 * A.DROPS_PER_HOUR)
    baseline = None
    for n, bonus in enumerate((0.0, 0.35, 0.70, 1.05, 1.40, 1.75)):
        runs = sorted(simulate_income(BASE_DEPTH + bonus, rng, drops)
                      for _ in range(250))
        med = runs[len(runs) // 2]
        baseline = baseline or med
        print(f"  {n:<10}+{bonus:<7.2f}{A.money(med) + '/s':>12}{med/baseline:>13.1f}x")

    print("""
  A rebirth is supposed to make the next run faster, not make the last one
  pointless. Anything past about 4x by the fifth rebirth means a returning
  player's old base was never worth building.
""")


if __name__ == "__main__":
    main()
