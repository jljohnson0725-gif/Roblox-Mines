"""
Model a brand new player's first session.

The question: how often does someone finish their opening rounds with NOTHING
to show? That is the exact failure this game shares with the reference video,
where a real player quit seconds after the tutorial because the next step was
out of reach.

The hook is "you found a thing and it pays you rent forever". If a player never
banks a brainrot, the hook never fires and there is nothing to come back for.

Run: python tools/onboarding.py
"""

import random

# ── config mirror ───────────────────────────────────────────────────────────
TILES = 25
START_MONEY = 500
MIN_BET = 10
DROP_BASE, DROP_PER_MINE, DROP_CAP = 0.06, 0.04, 0.90
HOUSE_EDGE = 0.03
DEFAULT_MINES = 3

SLOT_BASE, SLOT_GROWTH, START_SLOTS = 2500, 4.2, 3
COMMON_INCOME = 2.0          # tier income x mul ~1.0 for a typical Common
INCOME_TICK = 1.0

TRIALS = 40000


def drop_chance(mines):
    return min(DROP_BASE + DROP_PER_MINE * mines, DROP_CAP)


def ncr(n, r):
    from math import comb
    return comb(n, r)


def multiplier(mines, picks):
    safe = TILES - mines
    if picks == 0:
        return 1.0
    return (1 - HOUSE_EDGE) * ncr(TILES, picks) / ncr(TILES - mines, picks)


def play_round(mines, cash_out_at, guaranteed_first_drop, rng):
    """One round. Returns (banked_drops, profit)."""
    board = [True] * mines + [False] * (TILES - mines)
    rng.shuffle(board)
    order = list(range(TILES))
    rng.shuffle(order)

    p = drop_chance(mines)
    unsecured = 0
    picks = 0
    for idx in order[:cash_out_at]:
        if board[idx]:
            return 0, -MIN_BET          # bust: bet and every unsecured drop lost
        picks += 1
        if guaranteed_first_drop and picks == 1:
            unsecured += 1
        elif rng.random() < p:
            unsecured += 1

    payout = int(MIN_BET * multiplier(mines, picks))
    return unsecured, payout - MIN_BET


def session(rounds, cash_out_at, guarantee_rounds, rng):
    """Play `rounds` opening rounds. Returns (first_round_with_a_drop, total)."""
    banked_total = 0
    first_bank = None
    remaining_guarantee = guarantee_rounds
    for r in range(1, rounds + 1):
        use = remaining_guarantee > 0
        got, _ = play_round(DEFAULT_MINES, cash_out_at, use, rng)
        if got > 0:
            banked_total += got
            if first_bank is None:
                first_bank = r
            # the guarantee is spent only when a drop is actually BANKED,
            # so busting never burns it
            if use:
                remaining_guarantee -= 1
    return first_bank, banked_total


def report(label, guarantee_rounds, cash_out_at=4, rounds=5):
    rng = random.Random(20260814)
    never = 0
    firsts = []
    totals = []
    for _ in range(TRIALS):
        first, total = session(rounds, cash_out_at, guarantee_rounds, rng)
        totals.append(total)
        if first is None:
            never += 1
        else:
            firsts.append(first)

    pct_never = never / TRIALS * 100
    avg_first = sum(firsts) / len(firsts) if firsts else float("nan")
    avg_total = sum(totals) / TRIALS
    print(f"  {label:<34} {pct_never:6.1f}%  {avg_first:8.2f}  {avg_total:9.2f}")


def main():
    print("A new player bets the $10 minimum at 3 mines and cashes out at 4 picks.")
    print(f"Drop chance is {drop_chance(DEFAULT_MINES):.0%} per safe tile.\n")

    print("  %-34s %6s  %8s  %9s" % ("", "NOTHING", "1st bank", "brainrots"))
    print("  %-34s %6s  %8s  %9s" % ("", "in 5rds", "on round", "in 5 rds"))
    report("no guarantee (today)", 0)
    report("guarantee 1st banked drop", 1)
    report("guarantee first 2 banked drops", 2)

    print("\n  A 'NOTHING' player has bet five times, lost money, and has an empty")
    print("  base. There is no reason for them to come back.\n")

    # ── how long to the first real goal, the 4th pad ────────────────────────
    print("Time to afford the 4th pad ($%s), from placed Commons alone:" % f"{SLOT_BASE:,}")
    for placed in (1, 2, 3):
        rate = placed * COMMON_INCOME
        secs = (SLOT_BASE - START_MONEY) / rate
        print(f"  {placed} placed Common(s)  ->  {rate:4.1f}/s  ->  "
              f"{secs/60:5.1f} min")

    print("\nWith the guarantee, a player has 1 earner within a round or two,")
    print("and 3 filled pads shortly after -- the 4th pad lands inside one session.")


if __name__ == "__main__":
    main()
