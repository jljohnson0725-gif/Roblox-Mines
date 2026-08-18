"""
Brainrot racing: field difficulty, odds, payout and how long a seal takes.

THE SHAPE IS THE MINE-COUNT SELECTOR'S. Picking a harder field must not be a
better deal, or the choice collapses to "always pick the hardest" and the dial
is decorative. So expected value is held roughly FLAT across fields while
variance climbs steeply -- the same trade Mines already makes, which is why it
should feel native rather than bolted on.

RACING IS A SINK, NOT AN INCOME SOURCE, exactly like Plinko (84% RTP). Pads are
where money comes from; the sky games are where it goes, and what they pay back
is PROGRESS -- fragments toward the next island's seal.

UPGRADES BUY CONSISTENCY, NOT PROFIT, and that is not a nicety -- the first
version of this model had upgrades raise win chance against FIXED payouts, and
since EV = p x pay, every level multiplied the house's loss. Legend reached
508% RTP at max: an infinite money printer that retires the idle economy.

So the payout is DERIVED, never authored: pay = TARGET_RTP / win. Buy a level
and you win more often while each win pays less, for identical expected value.
That still buys you two real things -- a far smoother ride, and faster seals,
because a fragment can only drop on a win. Progress speeds up; profit does
not.

Run: python tools/race.py
"""

# ── the fields you can enter ────────────────────────────────────────────────
# win = probability your brainrot wins at BASE upgrades
# pay = multiple of your stake returned on a win (0 on a loss)
# frag = chance a win also yields a seal fragment
TARGET_RTP = 0.80  # every field, every upgrade level, by construction

FIELDS = [
    # name,        rivals, win,  frag-on-win
    ("Novice",          3, 0.52, 0.05),
    ("Contender",       5, 0.34, 0.10),
    ("Champion",        7, 0.19, 0.20),
    ("Legend",          9, 0.09, 0.38),
]

# Upgrades are PLAYER stats -- the brainrot is fashion. Each level shifts your
# win chance toward the field's ceiling rather than adding a flat amount, so a
# level is worth more in a hard field than an easy one and the top field stays
# the interesting purchase.
UPGRADE_LEVELS = 8
#[[ Swept, not guessed. Too generous and every field converges on a coin flip:
#   at 0.55 a maxed Legend won 59% and paid 1.35x, so the swing spread across
#   fields fell to 1.6x and the difficulty dial stopped meaning anything -- the
#   same "decorative selector" failure this file exists to prevent, arriving by
#   a different road. 0.20 keeps the spread at 2.1x with Legend still a real
#   long shot (27% at 2.94x), while a seal still lands 3x faster than at
#   level 0. ]]
UPGRADE_REACH = 0.20

STAKE = 250_000  # comparable to a Plinko drop at 450k
SEAL_FRAGMENTS = 6  # island three's seal, one more than Plinko's


def win_chance(base, level):
    """Level 0 gives `base`; maxed closes UPGRADE_REACH of the gap to 1.0."""
    return base + (1.0 - base) * UPGRADE_REACH * (level / UPGRADE_LEVELS)


def line(name, rivals, p, pay, frag, stake):
    ev = p * pay
    # variance of the payout multiple, per unit staked
    var = p * (pay - ev) ** 2 + (1 - p) * (0 - ev) ** 2
    return dict(name=name, rivals=rivals, p=p, pay=pay, ev=ev, sd=var ** 0.5,
                rtp=ev, net=stake * (ev - 1), frag=p * frag)


print("STAKE %s per race, %d fragments to a seal\n" % (f"${STAKE:,}", SEAL_FRAGMENTS))

for level in (0, 4, UPGRADE_LEVELS):
    print(f"-- upgrade level {level}/{UPGRADE_LEVELS} " + "-" * 46)
    print(f"  {'field':<11}{'rivals':>7}{'win':>8}{'pay':>7}{'RTP':>8}"
          f"{'swing':>8}{'net/race':>12}{'frag/race':>11}{'races/seal':>11}")
    rows = []
    for name, rivals, base, frag in FIELDS:
        p = win_chance(base, level)
        pay = TARGET_RTP / p
        r = line(name, rivals, p, pay, frag, STAKE)
        rows.append(r)
        per_seal = SEAL_FRAGMENTS / r["frag"] if r["frag"] else float("inf")
        print(f"  {r['name']:<11}{rivals:>7}{r['p']:>7.1%}{r['pay']:>7.2f}"
              f"{r['rtp']:>8.1%}{r['sd']:>8.2f}{r['net']:>12,.0f}"
              f"{r['frag']:>10.1%}{per_seal:>11.0f}")
    rtps = [r["rtp"] for r in rows]
    print(f"  RTP spread across fields: {min(rtps):.1%} - {max(rtps):.1%} "
          f"({max(rtps) / min(rtps):.2f}x)   "
          f"swing spread: {min(r['sd'] for r in rows):.2f} - {max(r['sd'] for r in rows):.2f}"
          f" ({max(r['sd'] for r in rows) / min(r['sd'] for r in rows):.1f}x)\n")

# ── what a seal actually costs, on the fastest route ────────────────────────
print("cheapest route to island three's seal, per field, at max upgrades:")
best = None
for name, rivals, base, frag in FIELDS:
    p = win_chance(base, UPGRADE_LEVELS)
    r = line(name, rivals, p, TARGET_RTP / p, frag, STAKE)
    races = SEAL_FRAGMENTS / r["frag"]
    cost = races * STAKE * (1 - r["rtp"])
    print(f"  {name:<11}{races:>6.0f} races   staked {races * STAKE:>14,.0f}"
          f"   net cost {cost:>12,.0f}")
    if best is None or cost < best[1]:
        best = (name, cost, races)
print(f"\n  -> cheapest is {best[0]} at {best[1]:,.0f} net over {best[2]:.0f} races")
print("     (Plinko's seal: 69 drops, $31M staked, $4.97M net -- same order)")
