"""
Model altitude-tier pricing against the real economy.

The jetpack is meant to be the PROGRESSION gate -- deterministic and earned --
so the gambling islands can go back to paying rewards rather than standing
between a player and the next chapter. That only works if the tier prices pace
the islands out sensibly instead of all unlocking the same afternoon.

Everything here is read out of src/ so the model cannot drift from the game.

Run: python tools/altitude.py
"""

import math
import pathlib
import random
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "src" / "ReplicatedStorage" / "Shared"


# ── read the real numbers ───────────────────────────────────────────────────

def read(name):
    return (SHARED / name).read_text(encoding="utf-8")


def parse_tiers():
    """Rarity.Tiers -> {name: {income, weight, growth, wheelOnly}}."""
    src = read("Rarity.lua")
    order = re.search(r"Rarity\.Order = \{(.*?)\}", src, re.S)
    order = re.findall(r'"(\w+)"', order.group(1)) if order else []
    tiers = {}
    for name in order:
        block = re.search(r"\t%s = \{(.*?)\n\t\}," % name, src, re.S)
        if not block:
            continue
        b = block.group(1)
        def num(field):
            m = re.search(r"%s = ([\d.]+)" % field, b)
            return float(m.group(1)) if m else 0.0
        tiers[name] = {
            "income": num("income"),
            "weight": num("weight"),
            "growth": num("growth"),
            "wheelOnly": "wheelOnly = true" in b,
        }
    return order, tiers


def parse_variants():
    src = read("Variants.lua")
    order = re.search(r"Variants\.Order = \{(.*?)\}", src, re.S)
    order = re.findall(r'"(\w+)"', order.group(1)) if order else []
    out = {}
    for name in order:
        block = re.search(r"\t%s = \{(.*?)\n\t\}," % name, src, re.S)
        if not block:
            continue
        b = block.group(1)
        def num(field, default=0.0):
            m = re.search(r"%s = ([\d.]+)" % field, b)
            return float(m.group(1)) if m else default
        out[name] = {"mult": num("mult", 1), "weight": num("weight"),
                     "growth": num("growth", 1)}
    return order, out


def parse_muls():
    return [float(m) for m in re.findall(r"mul = ([\d.]+)", read("Brainrots.lua"))]


def parse_config():
    src = read("Config.lua")
    def num(field):
        m = re.search(r"Config\.%s = ([\d_]+)" % field, src)
        return int(m.group(1).replace("_", "")) if m else None
    return {
        "slot_base": num("SlotBaseCost"),
        "slot_growth": float(re.search(r"Config\.SlotCostGrowth = ([\d.]+)", src).group(1)),
        "start_slots": num("StartingSlots"),
        "max_slots": num("MaxSlots"),
        "wheel_min": num("WheelMinStake"),
    }


TIER_ORDER, TIERS = parse_tiers()
VAR_ORDER, VARIANTS = parse_variants()
MULS = parse_muls()
CFG = parse_config()

ROLLABLE = [t for t in TIER_ORDER if not TIERS[t]["wheelOnly"]]

# A typical Mines round: 3 mines, cash out around 4 picks -> multiplier ~1.68,
# so depth = log2(1.68). Deep runs are rarer than this and shallow ones commoner.
DEPTH = math.log2(1.68)

# rounds are roughly 20s of clicking, and 18% of safe tiles drop
DROPS_PER_HOUR = 85


def weighted(order, table, depth, rng):
    weights = []
    for name in order:
        d = table[name]
        weights.append(d["weight"] * (d["growth"] ** depth))
    total = sum(weights)
    if total <= 0:
        return order[0]
    roll = rng.random() * total
    for name, w in zip(order, weights):
        roll -= w
        if roll <= 0:
            return name
    return order[-1]


def roll_drop(rng):
    tier = weighted(ROLLABLE, TIERS, DEPTH, rng)
    variant = weighted(VAR_ORDER, VARIANTS, DEPTH, rng)
    mul = rng.choice(MULS)
    return TIERS[tier]["income"] * mul * VARIANTS[variant]["mult"]


def income_after(drops, rng, pads=8):
    """Best `pads` drops out of `drops`, summed -- what your base actually earns."""
    best = []
    for _ in range(drops):
        best.append(roll_drop(rng))
        if len(best) > pads:
            best.sort(reverse=True)
            best = best[:pads]
    return sum(best)


def money(v):
    for unit, size in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(v) >= size:
            return f"${v/size:,.2f}{unit}"
    return f"${v:,.0f}"


def hours(h):
    return f"{h*60:.0f} min" if h < 1.5 else f"{h:.1f} h"


# ── the curve ───────────────────────────────────────────────────────────────

def pads_owned(hours_played):
    """Pads come fast and cap at 8; roughly one per early half hour."""
    return min(CFG["max_slots"], CFG["start_slots"] + int(hours_played / 0.6))


def simulate(hours_played, rng):
    drops = int(hours_played * DROPS_PER_HOUR)
    return income_after(drops, rng, pads_owned(hours_played))


def main():
    print("read from src/: %d tiers, %d variants, %d characters\n"
          % (len(TIERS), len(VARIANTS), len(MULS)))
    print("Mines-only income (no Secret), median of 400 simulated players:\n")
    print("  %-10s %-8s %14s %16s" % ("played", "pads", "income/s", "earned so far"))

    rng = random.Random(4)
    marks = [0.5, 1, 2, 4, 8, 16, 30, 60]
    curve = []
    for h in marks:
        runs = sorted(simulate(h, rng) for _ in range(400))
        med = runs[len(runs) // 2]
        curve.append((h, med))
        # money accrues at roughly the average rate up to this point
        earned = 0.0
        prev_h, prev_rate = 0.0, 0.0
        for hh, rr in curve:
            earned += (rr + prev_rate) / 2 * (hh - prev_h) * 3600
            prev_h, prev_rate = hh, rr
        print("  %-10s %-8d %14s %16s"
              % (hours(h), pads_owned(h), money(med) + "/s", money(earned)))

    # cumulative earnings, so tier prices can be set against them
    earned_at = {}
    total, prev_h, prev_rate = 0.0, 0.0, 0.0
    for h, rate in curve:
        total += (rate + prev_rate) / 2 * (h - prev_h) * 3600
        earned_at[h] = total
        prev_h, prev_rate = h, rate

    print("\n" + "=" * 74)
    print("PROPOSED ALTITUDE TIERS")
    print("=" * 74)
    print("""
Priced so each island lands at a target hour on the curve above, and set at
roughly a third of everything earned by then -- the rest has to stay available
for pads, upgrades and the wheel, which are competing for the same wallet.
""")

    targets = [
        ("Tier 1", "first island", 2),
        ("Tier 2", "second island", 8),
        ("Tier 3", "third island", 16),
        ("Tier 4", "the key vault", 30),
    ]

    def nice(v):
        """Round to something a human would have chosen."""
        if v <= 0:
            return 0
        mag = 10 ** (math.floor(math.log10(v)) - 1)
        return int(round(v / mag) * mag)

    prices = []
    for name, label, at in targets:
        price = nice(earned_at[at] * 0.33)
        prices.append((name, label, at, price))
        print("  %-8s %-16s unlocks around %-7s  cost %s"
              % (name, label, hours(at), money(price)))

    print("\nsanity: what else wants that money at the same time")
    slot_total = sum(int(CFG["slot_base"] * CFG["slot_growth"] ** s)
                     for s in range(CFG["max_slots"] - CFG["start_slots"]))
    print("  all 8 pads        %12s" % money(slot_total))
    print("  one wheel spin    %12s" % money(CFG["wheel_min"]))
    print("  all four tiers    %12s" % money(sum(p for _, _, _, p in prices)))

    # ── the luck spread, which is what killed the 10% key gate ──────────────
    print("\n" + "=" * 74)
    print("DOES LUCK STILL DECIDE? (the thing that broke the 10% key gate)")
    print("=" * 74)
    rng = random.Random(99)
    for name, label, at, price in prices:
        times = []
        for _ in range(240):
            # walk the clock until this player has banked `price`
            t, banked, rate_prev = 0.0, 0.0, 0.0
            while banked < price and t < 400:
                t += 0.5
                rate = simulate(t, rng)
                banked += (rate + rate_prev) / 2 * 0.5 * 3600
                rate_prev = rate
            times.append(t)
        times.sort()
        med = times[len(times) // 2]
        slow = times[int(len(times) * 0.9)]
        print("  %-8s median %-8s  unluckiest 10%% %-8s  spread %.1fx"
              % (name, hours(med), hours(slow), slow / med if med else 0))

    print("""
A spread near 1.0 means the gate is a SAVINGS target, not a dice roll -- every
player gets there, the unlucky ones just take a little longer. Compare the 10%
key gate, where the unluckiest 1% needed 6.3x the median and some never arrived.
""")


if __name__ == "__main__":
    main()
