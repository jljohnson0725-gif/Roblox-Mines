"""
Sanity model for auction house pricing.

The NPC floor is `income_per_sec * FLOOR_SECONDS` -- "the house pays you N
seconds of rent up front to take it off your hands". The question this script
answers is what N can be without wrecking the two sinks that already exist:
pads (~$1.02M all-in) and upgrades (~$417M all-in).

Run: python tools/auction.py
"""

TIERS = {
    "Common":    2,
    "Uncommon":  7,
    "Rare":      25,
    "Epic":      90,
    "Legendary": 320,
    "Mythic":    1200,
    "Secret":    5000,
}
VARIANTS = {
    "Normal": 1, "Gold": 2.5, "Diamond": 6, "Rainbow": 15,
    "Frost": 22, "Lava": 40, "Galaxy": 110,
}
MUL_MIN, MUL_TYP, MUL_MAX = 0.85, 1.0, 1.20

# existing sinks, for scale
SLOT_BASE, SLOT_GROWTH, START_SLOTS, MAX_SLOTS = 2500, 4.2, 3, 8
UPG_BASE, UPG_GROWTH, UPG_LEVELS = 4000, 1.55, 25
COLLECT_CAP_S = 4 * 3600


def money(v):
    for unit, size in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(v) >= size:
            return f"${v/size:,.2f}{unit}"
    return f"${v:,.0f}"


def slot_total():
    return sum(int(SLOT_BASE * SLOT_GROWTH ** s)
               for s in range(MAX_SLOTS - START_SLOTS))


def upgrade_total():
    return sum(int(UPG_BASE * UPG_GROWTH ** lv) for lv in range(UPG_LEVELS))


def income(tier, variant, mul=MUL_TYP):
    return TIERS[tier] * mul * VARIANTS[variant]


def main():
    pads, upgrades = slot_total(), upgrade_total()
    print(f"existing sinks:  pads {money(pads)}   upgrades {money(upgrades)}")
    print(f"collect cap:     {COLLECT_CAP_S/3600:.0f}h of rent per slot\n")

    print("=== NPC floor at candidate FLOOR_SECONDS ===")
    print(f"{'item':34}{'income/s':>12}", end="")
    cands = [300, 900, 1800, 3600]
    for c in cands:
        print(f"{str(c)+'s':>14}", end="")
    print()

    rows = [
        ("Common Normal (worst)",    "Common",    "Normal",  MUL_MIN),
        ("Common Normal (typical)",  "Common",    "Normal",  MUL_TYP),
        ("Uncommon Gold",            "Uncommon",  "Gold",    MUL_TYP),
        ("Rare Normal",              "Rare",      "Normal",  MUL_TYP),
        ("Rare Diamond",             "Rare",      "Diamond", MUL_TYP),
        ("Epic Gold",                "Epic",      "Gold",    MUL_TYP),
        ("Legendary Normal",         "Legendary", "Normal",  MUL_TYP),
        ("Legendary Rainbow",        "Legendary", "Rainbow", MUL_TYP),
        ("Mythic Diamond",           "Mythic",    "Diamond", MUL_TYP),
        ("Secret Normal",            "Secret",    "Normal",  MUL_TYP),
        ("Secret Galaxy (best)",     "Secret",    "Galaxy",  MUL_MAX),
    ]
    for label, tier, variant, mul in rows:
        inc = income(tier, variant, mul)
        print(f"{label:34}{inc:>12,.1f}", end="")
        for c in cands:
            print(f"{money(inc*c):>14}", end="")
        print()

    print("\n=== what one sale buys, at FLOOR_SECONDS = 900 ===")
    K = 900
    for label, tier, variant, mul in rows:
        price = income(tier, variant, mul) * K
        print(f"{label:34}{money(price):>12}   "
              f"{price/pads*100:8.2f}% of all pads   "
              f"{price/upgrades*100:8.4f}% of all upgrades")

    print("\n=== keep-vs-sell crossover (how long on a pad to beat the sale) ===")
    for K in cands:
        print(f"  FLOOR_SECONDS={K:5}  ->  keeping it wins after "
              f"{K/60:6.1f} min of collected rent"
              f"   (collect cap holds {COLLECT_CAP_S/60:.0f} min)")

    print("\n=== first sale vs. early costs (typical Common, mul 1.0) ===")
    base = income("Common", "Normal")
    for K in cands:
        p = base * K
        print(f"  FLOOR_SECONDS={K:5}  Common sells for {money(p):>9}"
              f"   start money $500   4th pad {money(SLOT_BASE)}"
              f"   -> {p/SLOT_BASE:5.2f} Commons per pad")


if __name__ == "__main__":
    main()
