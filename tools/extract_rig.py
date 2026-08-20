#!/usr/bin/env python3
"""
extract_rig.py -- lift a rig out of a SAVED PLACE and into assets/<name>.rbxmx

    python tools/extract_rig.py Emo ex

Takes the model called Emo out of BrainrotMines.rbxlx and writes assets/ex.rbxmx,
which is what the RIGS list in build_place.py injects back in as a template.

WHY THIS EXISTS AT ALL, given Studio has a "Save to File" on the right-click
menu: that menu item opens a file dialog, and a dialog is a place to end up in
the wrong folder under the wrong name. It happened -- the save reported as done
and no .rbxmx existed anywhere on the machine. Ctrl+S has no such ambiguity: one
keystroke, one destination, already known to both of us. So the rig comes out of
the place file instead, and the only human step is the one that cannot be
mistyped.

Studio will not do this itself. There is no `game:Save()`, no SaveInstance, and
no `plugin` global in the command bar, all three checked; and the asset delivery
endpoint answers 401 without an account cookie. The saved place is the one copy
of those bytes reachable from here.

THE SHARED STRINGS COME TOO. Roblox XML keeps mesh and physics blobs once at the
end of the file in a <SharedStrings> block and has properties point at them by
md5. Copying the <Item> alone leaves those pointers aimed at nothing and Studio
refuses to open the result at all -- "Unknown referenced shared string md5 ..."
-- which is how a previous rig cost an evening. So the references inside the
subtree are collected and their definitions carried across with it.
"""

import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLACE = ROOT / "BrainrotMines.rbxlx"


def name_of(item):
    props = item.find("Properties")
    if props is None:
        return None
    node = props.find("string[@name='Name']")
    return node.text if node is not None else None


def find_model(root, wanted):
    """Every Item in the file, not just the top level -- the rig sits inside
    Workspace, and a wrapper Model around it is normal rather than exceptional."""
    for item in root.iter("Item"):
        if item.get("class") == "Model" and name_of(item) == wanted:
            return item
    return None


def shared_refs(subtree):
    """md5s the subtree points at. A SharedString used as a PROPERTY carries the
    md5 as its text; the definitions in the block carry it as an attribute."""
    return {
        node.text.strip()
        for node in subtree.iter("SharedString")
        if node.text and node.text.strip()
    }


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    wanted, out_name = sys.argv[1], sys.argv[2]
    if not PLACE.is_file():
        print("no %s -- open the place in Studio and save it first" % PLACE.name)
        return 1

    tree = ET.parse(PLACE)
    root = tree.getroot()

    model = find_model(root, wanted)
    if model is None:
        names = sorted(
            {
                name_of(i)
                for i in root.iter("Item")
                if i.get("class") == "Model" and name_of(i)
            }
        )
        print("no Model named %r in %s" % (wanted, PLACE.name))
        print("models present: %s" % (", ".join(names[:40]) or "none"))
        print()
        print("If you just saved in Studio, check the save actually landed --")
        print("and do NOT run build_place.py in between, it rewrites this file.")
        return 1

    refs = shared_refs(model)
    block = root.find("SharedStrings")
    have = {}
    if block is not None:
        for node in block.findall("SharedString"):
            have[node.get("md5")] = node

    carried, missing = [], []
    for md5 in sorted(refs):
        if md5 in have:
            carried.append(have[md5])
        else:
            missing.append(md5)

    out_root = ET.Element("roblox", {"version": "4"})
    out_root.append(model)
    if carried:
        out_block = ET.SubElement(out_root, "SharedStrings")
        for node in carried:
            out_block.append(node)

    out_path = ROOT / "assets" / ("%s.rbxmx" % out_name)
    ET.ElementTree(out_root).write(out_path, encoding="utf-8", xml_declaration=True)

    parts = sum(
        1
        for i in model.iter("Item")
        if i.get("class") in ("Part", "MeshPart", "WedgePart", "TrussPart")
    )
    print("wrote %s" % out_path.relative_to(ROOT))
    print("  %d items, %d parts" % (sum(1 for _ in model.iter("Item")), parts))
    print("  shared strings: %d referenced, %d carried" % (len(refs), len(carried)))
    if missing:
        #[[ Not fatal here -- a blob the place itself was missing is a problem
        #   that already existed -- but it is exactly the failure that stops the
        #   place opening later, so it gets said out loud now. ]]
        print("  WARNING: %d referenced blob(s) not in the place: %s"
              % (len(missing), ", ".join(missing[:3])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
