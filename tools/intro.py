"""
intro.py -- the cold-open storyboard, and the arithmetic behind it.

The cutscene is the game's hook and it is exactly ten seconds, so the beats
cannot be eyeballed: every second spent on one shot is taken from another. This
lays the shots out, checks they add up, and checks the camera never does
anything a real one could not.

Run it after changing any timing in UI/Intro.lua and keep the two in step.
"""

# t, name, camera position (relative to the set origin), what it looks at, why
SHOTS = [
    (0.0,  "her alone", ( 3.2, 4.7,  3.4), "her",     "Only her. He is behind the lens; nobody knows who she is talking to."),
    (3.6,  "the drift", ( 4.6, 4.8,  1.4), "her",     "Barely moves. She is working up to it."),
    (6.0,  "pull back", ( 7.4, 4.6, -3.0), "between", "Past him, and the situation arrives: two people, one being left."),
    (8.4,  "two shot",  ( 5.6, 4.6, -4.6), "her",     "Over his shoulder for the line that sets up the whole economy."),
    (12.4, "settle",    ( 4.4, 4.4, -2.8), "her",     "Holds while she finishes."),
    (15.0, "to him",    ( 1.7, 4.55, 4.6), "hisface", "Leaves her on 'I'm sorry' -- the goodbye plays over his face."),
    (20.0, "the sit",   ( 1.3, 4.45, 3.4), "hisface", "Held in silence before the fade."),
]
END = 20.0

#[[ t, seconds on screen, text. Kept in step with LINES in UI/Intro by hand. ]]
DIALOGUE = [
    (1.2,  2.6, "It's not you. It's me."),
    (6.4,  1.3, "I just..."),
    (8.7,  4.4, "I just can't be with someone ugly and broke like you..."),
    (14.1, 2.6, "I'm sorry. Goodbye."),
]

HIM = (0.0, 0.0, 0.0)
HER = (0.0, 0.0, 7.0)

SUBTITLE_AT = 7.9
SUBTITLE_OUT = 10.6
FADE_IN, FADE_OUT = 0.4, 0.6

#[[ Where his head ends up once the pose is solved -- the closing shot aims here.
#   Kept in step with poseKneeling's neck target by hand; if that moves, this
#   moves. ]]
HIS_FACE = (0.0, 5.80, 0.0)


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def target(kind):
    if kind == "hisface":
        return HIS_FACE
    if kind == "him":
        return (HIM[0], HIM[1] + 3.4, HIM[2])
    if kind == "her":
        return (HER[0], HER[1] + 4.4, HER[2])
    return (0.0, 1.8, 3.5)


print("SHOT LIST\n")
bad = 0
for i, (t, name, pos, look, why) in enumerate(SHOTS):
    if i + 1 >= len(SHOTS):
        continue  # the last entry is the end pose of the shot before it, not a cut
    end = SHOTS[i + 1][0]
    span = end - t
    tgt = target(look)
    d = dist(pos, tgt)
    speed = dist(pos, SHOTS[i + 1][2]) / span

    notes = []
    if span < 0.8:
        notes.append("TOO SHORT to read")
        bad += 1
    # a camera crossing more than ~6 studs a second reads as a whip, not a move
    if speed > 6:
        notes.append("MOVE TOO FAST (%.1f studs/s)" % speed)
        bad += 1
    if d < 3:
        notes.append("TOO CLOSE, subject will clip the near plane")
        bad += 1

    print("  %4.1fs  %-10s  %5.1fs long   %4.1f studs from subject   %4.1f studs/s  %s"
          % (t, name, span, d, speed, "; ".join(notes) or "ok"))
    print("         %s" % why)

print()
#[[ Reading speed. Roughly fifteen characters a second is a comfortable
#   subtitle; below twelve it is a race. ]]
for t, hold, text in DIALOGUE:
    rate = len(text) / hold
    flag = "ok"
    if rate > 15:
        flag = "TOO FAST TO READ (%.0f chars/s)" % rate
        bad += 1
    print("  %4.1fs  %4.1fs  %-52s %s" % (t, hold, '"%s"' % text, flag))

#[[ She should not be talking for most of it. The silences are the performance. ]]
speaking = sum(h for _, h, _ in DIALOGUE)
print()
print("she speaks for %.1fs of %.1fs (%.0f%%)" % (speaking, END, 100 * speaking / END))
if speaking / END > 0.55:
    print("  TOO TALKY -- the pauses are doing the work here"); bad += 1

last_t, last_hold, _ = DIALOGUE[-1]
alone = END - (last_t + last_hold)
print("silent on his face after her last word: %.1fs" % alone)
if alone < 1.5:
    print("  NOT LONG ENOUGH -- the goodbye needs somewhere to land"); bad += 1

print("before she is seen with him: %.1fs" % SHOTS[2][0])
print("shots: %d cuts, %d camera moves" % (0, len(SHOTS) - 1))
if SHOTS[2][0] < 2.5:
    print("  TOO SOON -- she needs a moment alone first"); bad += 1

print()
print("all shots hold up" if bad == 0 else "%d problem(s)" % bad)
