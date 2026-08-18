"""
Apartment tier palette: keep the room READABLE at every rebirth.

The first pass raised surface lightness AND light brightness together, so the
Designer tier hit white marble + cream walls + four lights at 1.6 and the room
blew out -- no floor, no corners, no shading. HomeService already carried a
comment warning about exactly that; this is the model that stops it recurring.

Rough model: what the eye reads is light x surface albedo. So brightness is
DERIVED from the wall it has to bounce off, against a target that climbs gently
across the arc. A tier gets its identity from material, hue and accent -- not
from being brighter than the last one.
"""

# name, wall rgb, floor rgb, floor material, accent rgb, light rgb
TIERS = [
    ("Studio",    (140,135,127), ( 96, 93, 90), "Concrete",   (120,190,140), (226,232,240)),
    ("Furnished", (150,141,128), ( 96, 68, 44), "WoodPlanks", ( 96,226,130), (255,240,210)),
    ("Renovated", (166,154,138), (122, 84, 52), "Wood",       (104,232,176), (255,244,220)),
    ("Designer",  (176,166,152), (150,146,140), "Marble",     ( 96,214,214), (255,238,206)),
    ("Penthouse", ( 86, 80, 88), ( 48, 46, 54), "Marble",     (240,196, 92), (255,214,150)),
    ("Empire",    ( 74, 68, 96), ( 34, 32, 46), "Marble",     (226,120,255), (236,226,255)),
]

# where the eye should land, climbing gently: a nicer flat is a touch brighter,
# not four times brighter.
TARGET = [0.38, 0.44, 0.48, 0.52, 0.56, 0.60]

def albedo(rgb):
    r, g, b = (c / 255 for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b  # relative luminance


def saturation(rgb):
    hi, lo = max(rgb), min(rgb)
    return 0 if hi == 0 else (hi - lo) / hi


# Materials that refuse to hold a colour. Glass renders pale and reflective
# whatever RGB it is given, so a "dark glass floor" comes out near-white -- the
# Empire tier was authored as one and rendered as a flat wash.
WONT_HOLD_COLOUR = {"Glass", "ForceField", "Neon"}

# Light saturation x brightness: how hard the bulb's own hue is painted onto
# every surface. CALIBRATED FROM SCREENSHOTS, not derived -- Penthouse sits at
# 0.72 with a warm gold and reads as expensive, while Empire at 0.89 with a
# violet read as a broken purple wash. Warm tints get read as lighting and cool
# ones as a coloured gel, so the bound sits just above Penthouse on purpose.
WASH_MAX = 0.75

print(f"{'tier':<11}{'wallAlb':>8}{'floorAlb':>9}{'target':>8}{'bright':>8}{'wash':>6}{'range':>7}   verdict")
prev = None
bad = 0
for (name, wall, floor, mat, accent, light), t in zip(TIERS, TARGET):
    wa, fa = albedo(wall), albedo(floor)
    b = round(t / wa, 2)
    rng = 26 + 4 * TIERS.index((name, wall, floor, mat, accent, light))

    notes = []
    if mat in WONT_HOLD_COLOUR:
        notes.append(f"{mat} will not hold its colour")
        bad += 1
    wash = saturation(light) * b
    if wash > WASH_MAX:
        notes.append(f"HUE WASH: {wash:.2f} > {WASH_MAX}")
        bad += 1
    # a light source strong enough to bloom near the bulb
    if b > 2.8:
        notes.append("BLOWOUT RISK: brightness > 2.8")
        bad += 1
    # floor and wall too close in value = no visible floor line
    if abs(wa - fa) < 0.06:
        notes.append(f"FLAT: wall/floor differ by only {abs(wa-fa):.3f}")
        bad += 1
    # perceived floor brightness -- a floor washing past ~0.62 loses its grain
    pf = b * fa
    if pf > 0.62:
        notes.append(f"FLOOR WASHED: {pf:.2f}")
        bad += 1
    if prev is not None and t <= prev:
        notes.append("not climbing")
        bad += 1
    prev = t

    print(f"{name:<11}{wa:>8.3f}{fa:>9.3f}{t:>8.2f}{b:>8.2f}{wash:>6.2f}{rng:>7}   "
          + ("ok" if not notes else "; ".join(notes)))

print()
print("all tiers readable" if bad == 0 else f"{bad} problem(s)")
