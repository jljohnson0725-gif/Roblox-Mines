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
    (0.0,  "cold open", (-7.0, 9.0, -9.0), "him",     "High and behind. He is small, the rain is huge."),
    (3.4,  "the wait",  (-4.0, 4.5, -5.5), "him",     "Push in on silence. Nothing happens. That is the point."),
    (6.0,  "the turn",  ( 7.5, 2.4, -2.0), "between", "Camera swings round him -- the move that reveals her."),
    (7.4,  "reveal",    ( 5.2, 2.8, -4.2), "her",     "Over his shoulder. She stands at full height, he does not."),
    (9.2,  "settle",    ( 4.0, 2.4, -2.4), "her",     "The reveal shot keeps drifting in while she speaks."),
    (11.2, "back to him",( 3.0, 1.40,  6.8), "hisface", "Leaves her, drops in front of him. Her part is over."),
    (14.0, "the sit",    ( 2.4, 1.12,  6.2), "hisface", "He lifts his head. Held in silence before the fade."),
]
END = 14.0

HIM = (0.0, 0.0, 0.0)
HER = (0.0, 0.0, 7.0)

SUBTITLE_AT = 7.9
SUBTITLE_OUT = 10.6
FADE_IN, FADE_OUT = 0.4, 0.6

#[[ Where his head ends up once the pose is solved -- the closing shot aims here.
#   Kept in step with poseKneeling's neck target by hand; if that moves, this
#   moves. ]]
HIS_FACE = (0.0, 1.72, 2.96)


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def target(kind):
    if kind == "hisface":
        return HIS_FACE
    if kind == "him":
        return (HIM[0], HIM[1] + 1.2, HIM[2])
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
read_for = SUBTITLE_OUT - SUBTITLE_AT
print("subtitle lands at %.1fs, on screen %.1fs" % (SUBTITLE_AT, read_for))
if read_for < 1.5:
    print("  TOO LITTLE READING TIME"); bad += 1

#[[ The beat after the line. She speaks, the camera leaves her, and he is alone
#   with it -- that silence is the point of the shot, so it gets checked like
#   any other timing. ]]
alone = END - SHOTS[-2][0]
print("held on his face, silent: %.1fs" % alone)
if alone < 2.0:
    print("  NOT LONG ENOUGH TO LAND -- the line needs somewhere to settle"); bad += 1
if SUBTITLE_OUT > SHOTS[-2][0] + 0.4:
    print("  SUBTITLE STILL UP after the camera has left her"); bad += 1
print("silent stretch before the turn: %.1fs" % SHOTS[2][0])
print("shots: %d cuts, %d camera moves" % (0, len(SHOTS) - 1))
if SHOTS[2][0] < 2.5:
    print("  SILENCE TOO SHORT -- the reveal needs something to land against"); bad += 1

print()
print("all shots hold up" if bad == 0 else "%d problem(s)" % bad)
