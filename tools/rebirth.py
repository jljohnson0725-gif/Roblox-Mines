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



# ── what a rebirth should cost ──────────────────────────────────────────────

#[[ Not everything earned goes toward the next rebirth: pads, the upgrade tree
#   and Plinko are all competing for the same wallet. ]]
TOWARD_REBIRTH = 0.40


def pads_at(hours, extra):
    """Pads owned this run. Rebirth hands you `extra` from the start."""
    return min(A.CFG["max_slots"], A.CFG["start_slots"] + extra + int(hours / 0.6))


def hours_to(cost, level, rng, cap=200.0):
    """Hours for a player at rebirth `level` to bank `cost`."""
    bonus = 0.35 * level
    banked, prev, t = 0.0, 0.0, 0.0
    while banked < cost and t < cap:
        t += 0.5
        rate = simulate_income(BASE_DEPTH + bonus, rng,
                               int(t * A.DROPS_PER_HOUR), pads_at(t, level))
        banked += (rate + prev) / 2 * 0.5 * 3600 * TOWARD_REBIRTH
        prev = rate
    return t


def cost_curve():
    print("\n" + "=" * 74)
    print("WHAT A REBIRTH SHOULD COST")
    print("=" * 74)
    print(f"""
Each rebirth should take about as long as the last, or a shade less. Cost
rising faster than income makes the loop stall; slower, and rebirths become
something you collect rather than earn. Income rose 4.4x over five rebirths,
which is {4.4 ** (1/5):.2f}x a step -- so the cost growth has to sit near that.

Assuming {TOWARD_REBIRTH*100:.0f}% of earnings go toward it, the rest to pads, upgrades and Plinko.
""")
    rng = random.Random(5)
    for base, growth in ((250e6, 2.20), (250e6, 1.55), (150e6, 1.35), (120e6, 1.30)):
        times = []
        for level in range(5):
            cost = base * (growth ** level)
            times.append(hours_to(cost, level, rng))
        drift = times[-1] / times[0]
        print(f"  base {A.money(base):>9}  x{growth:<5.2f} -> "
              + "  ".join(f"{t:4.1f}h" for t in times)
              + f"   drift {drift:.2f}x")

    print("""
  drift is the fifth rebirth against the first. Near 1.0 is a loop that holds;
  well above it stalls, well below it trivialises.
""")


if __name__ == "__main__":
    main()
    cost_curve()
