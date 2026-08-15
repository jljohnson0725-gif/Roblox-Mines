"""
Sanity model for the all-in wheel.

You wager EVERYTHING -- all cash and every brainrot -- with a $1.5M floor.

  8%  a Secret brainrot
  15% a free retry
  30% $200,000 back
  47% nothing

Run: python tools/wheel.py
"""

P_SECRET, P_RETRY, P_CASH, P_NOTHING = 0.08, 0.15, 0.30, 0.47
CASH_PRIZE = 200_000
MIN_STAKE = 1_500_000

# Secret tier income, x character mul, x variant mult
SECRET_BASE = 12000
MULS = {"low": 1.00, "high": 1.20}
VARIANTS = {"Normal": 1, "Gold": 2.5, "Diamond": 6, "Rainbow": 15,
            "Frost": 22, "Lava": 40, "Galaxy": 110}

SLOT_TOTAL = 1_020_000       # all 8 pads
UPGRADE_TOTAL = 416_850_000  # every upgrade level


def money(v):
    for unit, size in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(v) >= size:
            return f"${v/size:,.2f}{unit}"
    return f"${v:,.0f}"


def main():
    assert abs(P_SECRET + P_RETRY + P_CASH + P_NOTHING - 1) < 1e-9, "odds must sum to 1"

    print("=== the odds as written ===")
    for label, p in (("Secret", P_SECRET), ("retry", P_RETRY),
                     ("cash", P_CASH), ("nothing", P_NOTHING)):
        print(f"  {label:<9}{p:5.0%}")

    # A retry is a re-roll, so the real chances are the non-retry odds
    # renormalised. This is the number a player actually experiences.
    live = 1 - P_RETRY
    print("\n=== what a COMMITMENT actually resolves to ===")
    print("  (a retry re-rolls, so it is not an outcome -- renormalise without it)")
    print(f"  Secret   {P_SECRET/live:6.1%}")
    print(f"  cash     {P_CASH/live:6.1%}")
    print(f"  nothing  {P_NOTHING/live:6.1%}")
    print(f"\n  expected spins per commitment: {1/live:.2f}")

    print("\n=== expected cash return on the minimum stake ===")
    ev_cash = (P_CASH / live) * CASH_PRIZE
    print(f"  stake {money(MIN_STAKE)}  ->  expected cash back {money(ev_cash)}"
          f"  ({ev_cash/MIN_STAKE:.1%})")
    print(f"  so as a CASH game it destroys {1 - ev_cash/MIN_STAKE:.0%} of what you put in.")
    print("  the Secret is the entire reason to play; the cash prize is a consolation.")

    print("\n=== what a Secret earns, per second ===")
    print(f"  {'variant':<9}{'low mul':>14}{'high mul':>14}{'per hour (high)':>20}")
    for v, mult in VARIANTS.items():
        lo = SECRET_BASE * MULS["low"] * mult
        hi = SECRET_BASE * MULS["high"] * mult
        print(f"  {v:<9}{money(lo):>14}{money(hi):>14}{money(hi*3600):>20}")

    print("\n=== how fast a Secret pays back the stake ===")
    for v in ("Normal", "Gold", "Galaxy"):
        rate = SECRET_BASE * MULS["high"] * VARIANTS[v]
        print(f"  {v:<8} {money(rate):>12}/s -> re-earns the {money(MIN_STAKE)} floor "
              f"in {MIN_STAKE/rate/60:6.1f} min")

    print("\n=== against the existing sinks ===")
    worst = SECRET_BASE * MULS["low"] * VARIANTS["Normal"]
    print(f"  the WEAKEST possible Secret is {money(worst)}/s")
    print(f"    all 8 pads     {money(SLOT_TOTAL):>12}  -> {SLOT_TOTAL/worst/60:6.1f} min")
    print(f"    all upgrades   {money(UPGRADE_TOTAL):>12}  -> {UPGRADE_TOTAL/worst/3600:6.1f} hours")

    print("\n=== the loop this creates ===")
    rate = SECRET_BASE * MULS["low"] * VARIANTS["Normal"]
    print(f"  win one Secret, place it, and you re-reach the {money(MIN_STAKE)} entry")
    print(f"  in {MIN_STAKE/rate/60:.1f} minutes -- so the wheel becomes repeatable")
    print("  almost immediately after the first win. That is the endgame loop,")
    print("  but it does mean the 1.5M floor only ever gates the FIRST spin.")


if __name__ == "__main__":
    main()
