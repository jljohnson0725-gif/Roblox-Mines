#!/usr/bin/env python3
"""
extract_apartment.py -- turn a Studio model back into assets/apartment.psv

The other half of the apartment pipeline. build_place.py reads the .psv and
emits ReplicatedStorage.ApartmentTemplate; this reads a model and writes the
.psv, so the building can be arranged VISUALLY in Studio instead of by editing
numbers in a text file:

    1. open BrainrotMines.rbxlx, find ReplicatedStorage.ApartmentTemplate
       (or insert any building you like from the Creator Store)
    2. move / recolour / add / delete parts
    3. right-click the model -> Save to File As... -> somewhere.rbxmx
    4. python tools/extract_apartment.py somewhere.rbxmx
    5. python tools/build_place.py

Also accepts a whole .rbxlx place, in which case pass --model to say which
model to lift out (default: ApartmentTemplate).

    python tools/extract_apartment.py BrainrotMines.rbxlx --model ApartmentTemplate

WHY THE PLACE FILE IS NOT THE SOURCE. Editing the building directly in
BrainrotMines.rbxlx and saving does nothing -- every build overwrites that file
from assets/ + src/. This script is what makes a Studio edit durable: it moves
the change back into assets/, which IS source.

ORIGIN CONVENTION, and it is not the obvious one. Parts come out positioned
relative to the centre of the FOOTPRINT at GROUND LEVEL: X and Z centred on the
building, Y zero at its lowest point. That is what lets HomeService place one
with "put it where the base is" and no offset arithmetic.

Getting that centre right requires honouring ROTATION. Nine parts in this
building are tilted, and a part rotated ninety degrees contributes its LENGTH
to the axis its width nominally lies on. Measuring the naive way -- position
plus half the size on each axis -- reports this building as 125.7 studs wide
when it is 61.3, and puts the centre in the wrong place by enough to shift
every apartment off its base. The extent of an oriented box along world axis i
is sum_j |R[i][j]| * halfsize[j], which is what `aabb` below computes.

NATIVE SIZE IS NOT OPTIONAL. A MeshPart draws its mesh at Size/InitialSize, so
a mesh emitted without its true intrinsic size is inflated by that ratio -- the
bug that once made every character 475x too large. InitialSize is copied
through verbatim; if a MeshPart in the input is missing it, this refuses rather
than guessing, because guessing looks fine in every numeric check and wrong on
screen.
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "apartment.psv"

# Mirror of build_place.MATERIALS. Kept as its own table rather than imported so
# this script stays runnable on its own, and so an unknown token is reported by
# name instead of silently becoming Plastic.
MATERIALS = {
    256: "Plastic", 272: "SmoothPlastic", 816: "Concrete", 848: "Brick",
    1088: "Metal", 1568: "Glass", 1296: "Sand", 512: "Wood", 288: "Neon",
}

# Roblox omits properties sitting at their default, so every read needs one.
DEFAULT_COLOR = (163, 162, 165)  # medium stone grey
DEFAULT_MATERIAL = 256  # Plastic

# Anything with a size and a CFrame is emitted, because build_place.py rebuilds
# a part from its class string and those two properties -- so wedges, trusses
# and whatever else Roblox adds all survive without this script knowing about
# them. A whitelist here silently DELETED five parts on the first run.
#
# UnionOperation is the exception worth naming: it is kept, because the source
# file already carries two and dropping them would put holes in the building,
# but its geometry lives in a binary ChildData blob rather than in properties.
# There is nothing to write down, so a union comes back as its bounding box.
LOSSY = {"UnionOperation", "NegateOperation", "IntersectOperation"}

HEADER = """\
# The apartment block. Regenerate with:
#
#     python tools/extract_apartment.py <model.rbxmx>
#
# Pipe-separated so it stays diffable and hand-editable; build_place.py turns it
# into ReplicatedStorage.ApartmentTemplate and HomeService clones one per base.
# Extracted rather than referenced because a Studio-inserted model only survives
# a rebuild if it lives in assets/map.rbxlx, and hand-placing seven of these --
# then re-exporting the whole 18MB map every time one moves -- is not a pipeline.
#
# Coordinates are RELATIVE to the centre of the footprint at ground level, so
# placing one is "put it where the base is" with no offset arithmetic.
#
# class|name|size|pos|rot(9)|color|material|transparency|meshId|textureId|nativeSize
#
# nativeSize matters: a MeshPart draws its mesh at Size/InitialSize, so emitting
# a mesh without its TRUE intrinsic size inflates it by that ratio.
"""


def props(item):
    p = item.find("Properties")
    return p if p is not None else ET.Element("Properties")


def name_of(item):
    n = props(item).find("string[@name='Name']")
    return n.text if n is not None and n.text else ""


def vector3(item, prop):
    v = props(item).find("Vector3[@name='%s']" % prop)
    if v is None:
        return None
    out = []
    for axis in ("X", "Y", "Z"):
        e = v.find(axis)
        out.append(float(e.text) if e is not None and e.text else 0.0)
    return out


def cframe(item):
    c = props(item).find("CoordinateFrame[@name='CFrame']")
    if c is None:
        return None, None
    def g(tag, fallback=0.0):
        e = c.find(tag)
        return float(e.text) if e is not None and e.text else fallback
    pos = [g("X"), g("Y"), g("Z")]
    rot = [g("R00", 1.0), g("R01"), g("R02"),
           g("R10"), g("R11", 1.0), g("R12"),
           g("R20"), g("R21"), g("R22", 1.0)]
    return pos, rot


def color(item):
    e = props(item).find("Color3uint8[@name='Color3uint8']")
    if e is None or not e.text:
        return DEFAULT_COLOR
    packed = int(e.text)
    return ((packed >> 16) & 255, (packed >> 8) & 255, packed & 255)


def material(item, where):
    e = props(item).find("token[@name='Material']")
    token = int(e.text) if e is not None and e.text else DEFAULT_MATERIAL
    if token not in MATERIALS:
        sys.exit("%s uses material token %d, which build_place.py cannot write.\n"
                 "Add it to MATERIALS in both scripts, or pick another material."
                 % (where, token))
    return MATERIALS[token]


def number(item, prop, fallback=0.0):
    e = props(item).find("float[@name='%s']" % prop)
    return float(e.text) if e is not None and e.text else fallback


def content(item, prop):
    c = props(item).find("Content[@name='%s']" % prop)
    if c is None:
        return ""
    u = c.find("url")
    text = (u.text or "").strip() if u is not None else ""
    return text.rsplit("/", 1)[-1] if text else ""


def aabb(pos, rot, size):
    """
    World-axis-aligned bounds of an ORIENTED box.

    The whole reason this file has a centring step. See the module docstring:
    measuring position +/- half the size ignores rotation and overstates this
    building's width by more than a factor of two.
    """
    lo, hi = [0.0] * 3, [0.0] * 3
    for i in range(3):
        reach = sum(abs(rot[i * 3 + j]) * (size[j] / 2) for j in range(3))
        lo[i], hi[i] = pos[i] - reach, pos[i] + reach
    return lo, hi


DEFAULT_MODEL = "ApartmentTemplate"


def listing(models, cap=12):
    """
    A few model names, not all of them.

    A whole place has 562 models in it -- every brainrot is one -- and printing
    the lot buries the error message that matters under a screen of names.
    """
    names = sorted({name_of(m) for m in models if name_of(m)})
    shown = ", ".join(names[:cap])
    if len(names) > cap:
        shown += ", ... and %d more" % (len(names) - cap)
    return shown or "none"


def find_model(root, wanted):
    """
    The model to lift out.

    Named if you said so; otherwise ApartmentTemplate if it is present, since
    that is what this tool is for and a whole place always carries hundreds of
    models; otherwise the only one, when a saved .rbxmx holds exactly one.
    """
    models = [it for it in root.iter("Item") if it.get("class") == "Model"]
    if not models:
        sys.exit("that file contains no Model. Save the MODEL, not its parent.")

    if wanted:
        named = [m for m in models if name_of(m) == wanted]
        if not named:
            sys.exit("no Model named %r in that file.\nmodels present: %s"
                     % (wanted, listing(models)))
        return named[0]

    default = [m for m in models if name_of(m) == DEFAULT_MODEL]
    if default:
        return default[0]

    if len(models) > 1:
        sys.exit("that file has %d models and none called %s; say which with "
                 "--model.\nmodels: %s"
                 % (len(models), DEFAULT_MODEL, listing(models)))
    return models[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help=".rbxmx model, or a .rbxlx place")
    ap.add_argument("--model", default=None,
                    help="model to extract (default: %s, or the only one there is)"
                         % DEFAULT_MODEL)
    ap.add_argument("--out", default=str(OUT), help="where to write (default: %s)" % OUT)
    args = ap.parse_args()

    path = pathlib.Path(args.source)
    if not path.is_file():
        sys.exit("no such file: %s" % path)

    model = find_model(ET.parse(path).getroot(), args.model)

    # Every BasePart under it, at any depth: Studio models nest freely and a
    # folder in the middle should not lose you a wall.
    parts, lossy = [], []
    for item in model.iter("Item"):
        cls = item.get("class")
        size = vector3(item, "size")
        pos, rot = cframe(item)
        if size is None or pos is None:
            continue  # models, folders, attachments, scripts -- not geometry

        if cls in LOSSY:
            lossy.append((cls, name_of(item)))

        mesh = content(item, "MeshId")
        native = vector3(item, "InitialSize")
        if mesh and native is None:
            sys.exit("MeshPart %r has a MeshId but no InitialSize.\n"
                     "Without the mesh's true size it renders at the wrong scale."
                     % name_of(item))

        parts.append({
            "class": cls,
            "name": name_of(item) or cls,
            "size": size,
            "pos": pos,
            "rot": rot,
            "color": color(item),
            "material": material(item, "%s %r" % (cls, name_of(item))),
            "transparency": number(item, "Transparency"),
            "mesh": mesh,
            "texture": content(item, "TextureID"),
            "native": native,
        })

    if not parts:
        sys.exit("found the model but no Part/MeshPart inside it.")

    lo = [1e30] * 3
    hi = [-1e30] * 3
    for p in parts:
        plo, phi = aabb(p["pos"], p["rot"], p["size"])
        for i in range(3):
            lo[i] = min(lo[i], plo[i])
            hi[i] = max(hi[i], phi[i])

    # Footprint centre in X/Z, ground level in Y.
    origin = ((lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2)

    lines = [HEADER.rstrip("\n")]
    for p in parts:
        rel = [p["pos"][i] - origin[i] for i in range(3)]
        lines.append("|".join([
            p["class"],
            p["name"],
            ",".join("%.3f" % v for v in p["size"]),
            ",".join("%.3f" % v for v in rel),
            ",".join("%.4f" % v for v in p["rot"]),
            ",".join(str(v) for v in p["color"]),
            p["material"],
            "%.2f" % p["transparency"],
            p["mesh"],
            p["texture"],
            ",".join("%.3f" % v for v in p["native"]) if p["mesh"] else "",
        ]))

    out = pathlib.Path(args.out)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("wrote %s" % out)
    print("  %d parts   footprint %.1f x %.1f   height %.1f"
          % (len(parts), hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))
    if lossy:
        print("  %d solid-model part(s) kept but FLATTENED to their bounding box:"
              % len(lossy))
        for cls, nm in lossy[:10]:
            print("    %-18s %s" % (cls, nm))
        if len(lossy) > 10:
            print("    ... and %d more" % (len(lossy) - 10))
        print("  Their geometry is a binary blob rather than properties, so")
        print("  there is nothing to write down. Separate them into plain parts")
        print("  in Studio if their exact shape matters.")


if __name__ == "__main__":
    main()
