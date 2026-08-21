#!/usr/bin/env python3
"""
balance.py -- the model behind the numbers in ReplicatedStorage/Shared.

Run this after ANY change to Rarity/Variants/Config tuning values. It answers
the two questions that actually matter:

  1. Is any mine count strictly dominant? (If yes, the risk selector is dead.)
  2. How long until a player sees each tier?

Keep the constants below in sync with the Lua by hand -- this is a design tool,
not a build step.

    python tools/balance.py
"""

import math

# ── keep in sync with Shared/Rarity.lua ─────────────────────────────────────
#   name, base weight, growth, income/sec
TIERS = [
    ("Common",    1000,  0.72,    2),
    ("Uncommon",   400,  0.90,    7),
    ("Rare",       120,  1.10,   25),
    ("Epic",        30,  1.35,   90),
    ("Legendary",    6,  1.60,  320),
    ("Mythic",     0.8,  1.90, 1200),
    ("Secret",    0.05,  2.20, 5000),
]

# ── keep in sync with Shared/Variants.lua ───────────────────────────────────
#   Frost has weight 0: event-exclusive, surfaced only by Winter's variantAdd.
VARIANTS = [
    ("Normal",  1000, 0.85,   1),
    ("Gold",     250, 1.00, 2.5),
    ("Diamond",   70, 1.15,   6),
    ("Rainbow",   15, 1.35,  15),
    ("Frost",      0, 1.40,  22),
    ("Lava",       3, 1.55,  40),
    ("Galaxy",   0.3, 1.80, 110),
]

# ── keep in sync with Shared/Events.lua + Config.lua ────────────────────────
#   id, weight, duration, mods
EVENTS = [
    ("lucky",   100, 90, {"dropChanceMul": 1.7}),
    ("golden",   78, 90, {"variantMul": {"Gold": 7}}),
    ("rainbow",  44, 80, {"variantMul": {"Rainbow": 14, "Diamond": 3}}),
    ("winter",   26, 100, {"variantAdd": {"Frost": 70}, "variantMul": {"Diamond": 4}}),
    ("lava",     15, 75, {"variantMul": {"Lava": 28}}),
    ("deep",      8, 70, {"depthMul": 1.35, "dropChanceMul": 1.2}),
    ("cosmic",    3, 60, {"variantMul": {"Galaxy": 45}, "depthMul": 1.5, "variantDepthMul": 1.3}),
]
EVENT_GAP_MIN, EVENT_GAP_MAX = 180, 360

# ── keep in sync with Shared/Config.lua ─────────────────────────────────────
HOUSE_EDGE = 0.03
TILES = 25
MINE_OPTIONS = [1, 3, 5, 8, 12, 16, 20, 24]
DROP_BASE, DROP_PER_MINE, DROP_CAP = 0.06, 0.04, 0.90
#[[ Mine count floors the depth used for the TIER roll -- quality, not just
#   frequency. Modelled here because the dominance check below is the whole
#   reason this file exists, and a floor that lifts high mine counts moves it. ]]
DROP_QUALITY_PER_MINE = 0.16


def drop_chance(mines):
    return min(DROP_CAP, DROP_BASE + DROP_PER_MINE * mines)


def multiplier(mines, picks):
    if picks <= 0:
        return 1.0
    safe = TILES - mines
    if picks > safe:
        return None
    return (1 - HOUSE_EDGE) * math.comb(TILES, picks) / math.comb(safe, picks)


def p_survive(mines, picks):
    p = 1.0
    for i in range(picks):
        p *= (TILES - mines - i) / (TILES - i)
    return p


def weights(table, L):
    return [(name, base * (growth ** L), val) for name, base, growth, val in table]


def probabilities(table, L):
    w = weights(table, L)
    total = sum(x for _, x, _ in w)
    return [(name, x / total, val) for name, x, val in w]


def expected_value(table, L):
    return sum(p * val for _, p, val in probabilities(table, L))


def depth(mult):
    return math.log2(max(mult, 1))


def section(title):
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")


def tier_odds_table():
    section("TIER ODDS BY MULTIPLIER  (depth only -- mines floor this, see dominance)")
    print(f"{'mult':>9} {'L':>5} " + " ".join(f"{n[:9]:>9}" for n, _, _, _ in TIERS))
    for m in [1, 2, 4, 8, 16, 64, 256, 1024]:
        L = depth(m)
        probs = dict((n, p) for n, p, _ in probabilities(TIERS, L))
        print(f"{m:>8}x {L:>5.1f} " + " ".join(f"{probs[n] * 100:>8.3f}%" for n, _, _, _ in TIERS))


def variant_odds_table():
    section("VARIANT ODDS BY MULTIPLIER  (flatter curve, so no double-dip)")
    print(f"{'mult':>9} " + " ".join(f"{n:>9}" for n, _, _, _ in VARIANTS))
    for m in [1, 16, 256, 1024]:
        L = depth(m)
        probs = dict((n, p) for n, p, _ in probabilities(VARIANTS, L))
        print(f"{m:>8}x " + " ".join(f"{probs[n] * 100:>8.3f}%" for n, _, _, _ in VARIANTS))


def payout_table():
    section("MINES PAYOUT CURVE  (cash side, 3% edge)")
    ks = [1, 2, 3, 5, 8, 12]
    print("           " + "".join(f"{'k=' + str(k):>11}" for k in ks))
    for mines in MINE_OPTIONS:
        cells = []
        for k in ks:
            v = multiplier(mines, k)
            cells.append(f"{v:>11.2f}" if v else f"{'-':>11}")
        print(f"{mines:>2} mines: " + "".join(cells))


def dominance_table():
    """The important one: no mine count may be strictly best."""
    section("MINE-COUNT DOMINANCE  (E[income/sec secured] at best-play depth)")
    print(f"{'mines':>5} {'drop%':>7} {'bestk':>6} {'P(reach)':>9} {'E[val]':>10} {'E[drops]':>9}  rel")

    rows = []
    for mines in MINE_OPTIONS:
        safe = TILES - mines
        chance = drop_chance(mines)
        best = None
        for k in range(1, safe + 1):
            val = nd = 0.0
            for j in range(1, k + 1):
                L = depth(multiplier(mines, j))
                #[[ the floor applies to tiers only, as in DropTable ]]
                tier_L = max(L, DROP_QUALITY_PER_MINE * mines)
                val += chance * expected_value(TIERS, tier_L) * expected_value(VARIANTS, L)
                nd += chance
            pk = p_survive(mines, k)
            if best is None or val * pk > best[1]:
                best = (k, val * pk, nd * pk, pk)
        rows.append((mines, chance) + best)

    peak = max(r[3] for r in rows)
    for mines, chance, k, val, nd, pk in rows:
        print(f"{mines:>5} {chance:>7.0%} {k:>6} {pk:>9.5f} {val:>10.2f} {nd:>9.3f}  {val / peak:>5.2f}")

    spread = peak / min(r[3] for r in rows)
    verdict = "OK" if spread < 1.6 else "TOO WIDE -- retune DropChancePerMine/DropQualityPerMine"
    print(f"\n  spread (best/worst) = {spread:.2f}x   [{verdict}]")
    print("  Note: EV is flat by design but VARIANCE is not -- low mine counts")
    print("  drip small drops, high mine counts pay rarely and enormously.")


def chase_table():
    """How long until a player sees the good stuff, at a realistic cadence."""
    section("TIME TO CHASE  (3 mines, cash out at k=4, ~20s per round)")
    mines, k = 3, 4
    chance = drop_chance(mines)
    per_round = {name: 0.0 for name, _, _, _ in TIERS}
    for j in range(1, k + 1):
        L = depth(multiplier(mines, j))
        for name, p, _ in probabilities(TIERS, L):
            per_round[name] += chance * p
    pk = p_survive(mines, k)

    print(f"  P(surviving to k={k}) = {pk:.1%},  drop chance/tile = {chance:.0%}")
    print(f"\n{'tier':>10} {'per round':>11} {'rounds each':>13} {'playtime':>12}")
    for name, _, _, _ in TIERS:
        rate = per_round[name] * pk
        if rate <= 0:
            continue
        rounds = 1 / rate
        hours = rounds * 20 / 3600
        when = f"{hours:.1f}h" if hours < 48 else f"{hours / 24:.0f}d"
        print(f"{name:>10} {rate:>11.5f} {rounds:>13,.0f} {when:>12}")


def modded(table, L, mods, axis):
    """Apply an event modifier bag to one axis and return {name: probability}."""
    mods = mods or {}
    mul = mods.get("variantMul" if axis == "variant" else "tierMul", {})
    add = mods.get("variantAdd", {}) if axis == "variant" else {}
    dmul = mods.get("variantDepthMul" if axis == "variant" else "depthMul", 1)
    eff = L * dmul
    w = [(n, (b + add.get(n, 0)) * (g ** eff) * mul.get(n, 1)) for n, b, g, _ in table]
    total = sum(x for _, x in w)
    return {n: (x / total if total else 0) for n, x in w}


def events_table():
    section("EVENT CADENCE")
    total_w = sum(w for _, w, _, _ in EVENTS)
    avg_dur = sum(w * d for _, w, d, _ in EVENTS) / total_w
    gap = (EVENT_GAP_MIN + EVENT_GAP_MAX) / 2
    cycle = gap + avg_dur

    print(f"  gap {EVENT_GAP_MIN}-{EVENT_GAP_MAX}s (avg {gap:.0f}s), avg duration {avg_dur:.0f}s")
    print(f"  -> an event starts every {cycle / 60:.1f} min, running {avg_dur / cycle:.0%} of the time")
    print(f"\n{'event':>9} {'pick':>7} {'one every':>12}")
    for name, w, _, _ in EVENTS:
        p = w / total_w
        print(f"{name:>9} {p:>6.1%} {cycle / p / 60:>9.0f} min")

    section("EVENT EFFECTS  (rarer event => bigger swing)")
    print(f"{'event':>9} {'what moves':>34} {'at 1x':>10} {'at 16x':>10} {'at 256x':>10}")
    for name, _, _, mods in EVENTS:
        if name == "winter":
            label, axis, table, key = "Frost variant", "variant", VARIANTS, "Frost"
        elif name == "cosmic":
            label, axis, table, key = "Galaxy variant", "variant", VARIANTS, "Galaxy"
        elif name == "deep":
            label, axis, table, key = "Secret tier", "tier", TIERS, "Secret"
        elif name == "lava":
            label, axis, table, key = "Lava variant", "variant", VARIANTS, "Lava"
        elif name == "rainbow":
            label, axis, table, key = "Rainbow variant", "variant", VARIANTS, "Rainbow"
        elif name == "golden":
            label, axis, table, key = "Gold variant", "variant", VARIANTS, "Gold"
        else:
            chance = min(DROP_CAP, (DROP_BASE + DROP_PER_MINE * 3) * mods.get("dropChanceMul", 1))
            base = drop_chance(3)
            print(f"{name:>9} {'drop chance @3 mines':>34} {base:>9.0%} -> {chance:>7.0%}")
            continue
        cells = [modded(table, L, mods, axis)[key] for L in (0, 4, 8)]
        print(f"{name:>9} {label:>34} " + " ".join(f"{c:>9.2%}" for c in cells))

    print("\n  Frost outside Winter, at every depth: "
          + ", ".join(f"{modded(VARIANTS, L, None, 'variant')['Frost']:.4%}" for L in (0, 4, 8)))
    print("  (weight 0 -> literally unobtainable, which is the point)")


def top_end():
    section("TOP END")
    best_tier = max(TIERS, key=lambda t: t[3])
    best_var = max(VARIANTS, key=lambda v: v[3])
    print(f"  floor: Common Normal        = {TIERS[0][3] * VARIANTS[0][3] * 0.85:>12,.0f}/s")
    print(f"  ceil : {best_var[0]} {best_tier[0]:<15}= "
          f"{best_tier[3] * best_var[3] * 1.20:>12,.0f}/s")
    print(f"  ratio: {(best_tier[3] * best_var[3] * 1.2) / (TIERS[0][3] * VARIANTS[0][3] * 0.85):>12,.0f}x")


if __name__ == "__main__":
    tier_odds_table()
    variant_odds_table()
    payout_table()
    dominance_table()
    chase_table()
    events_table()
    top_end()
    print()
