"""
Model the jetpack price against the real economy.

The jetpack opens the sky. The question this file answers is how long a player
spends on the ground before it does, and -- once the price came down to a flat
million -- what has to gate the islands instead, since a purchase everyone can
afford within the hour cannot pace anything.

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

# Decided: one flat price, not a ladder. See THE JETPACK section below.
JETPACK = 1_000_000


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

    print("\n" + "=" * 74)
    print("THE JETPACK")
    print("=" * 74)
    print("""
ONE PRICE, NOT A LADDER. The first draft of this file proposed four altitude
tiers running $2M / $35M / $140M / $470M, gating each island behind a bigger
purchase. That was rejected, correctly: it put thirty hours between a new
player and the last island, and it made flying the most expensive thing in the
game -- the four tiers came to $647M against $417M for the whole upgrade tree.
""")

    rng = random.Random(21)
    times = []
    for _ in range(300):
        # walk the clock until this player has banked the price
        t, banked, prev = 0.0, 0.0, 0.0
        while banked < JETPACK and t < 40:
            t += 0.25
            rate = simulate(t, rng)
            banked += (rate + prev) / 2 * 0.25 * 3600
            prev = rate
        times.append(t)
    times.sort()
    med = times[len(times) // 2]
    fast = times[int(len(times) * 0.10)]
    slow = times[int(len(times) * 0.90)]

    print("  price  %s\n" % money(JETPACK))
    print("    luckiest 10%%    %2.0f min" % (fast * 60))
    print("    median          %2.0f min" % (med * 60))
    print("    unluckiest 10%%  %2.0f min     spread %.1fx" % (slow * 60, slow / med))

    slot_total = sum(int(CFG["slot_base"] * CFG["slot_growth"] ** s)
                     for s in range(CFG["max_slots"] - CFG["start_slots"]))
    print("\n  competing for the same wallet at that moment:")
    print("    all 8 pads      %12s" % money(slot_total))
    print("    one wheel spin  %12s" % money(CFG["wheel_min"]))
    print("""
  Those numbers matter more than the raw time. The pads cost about the same as
  the jetpack and pay for themselves, so nobody sensibly buys flight first --
  in practice it lands early in the second session rather than 45 minutes in,
  which is where an early goal belongs. Above is the floor, not the schedule.

  WHAT IT COSTS THE DESIGN. At this price every player is flying within an
  hour, so ALTITUDE CANNOT PACE THE ISLANDS. If height were the only
  requirement they would all open at once, and the four-island structure would
  collapse into one afternoon of hopping between minigames.

  The seals have to carry that instead: the first island is open to anyone who
  can fly, and each one above it wants the seal from the island below.
  Progression then comes from PLAYING the games rather than from saving up for
  the right to see them -- which suits a story game better anyway. Chapters
  should advance because you did something, not because a balance crossed a
  line. It also means a player who is bad at one game is stuck on that game,
  which is the risk to watch; the fragments are the release valve, since a
  fragment every few attempts still moves someone forward on a losing streak.

  Model that here once the fragment odds and per-drop costs are settled.
""")


if __name__ == "__main__":
    main()
