#!/usr/bin/env python3
"""
build_place.py -- produce BrainrotMines.rbxlx.

Two modes, chosen automatically:

  assets/map.rbxlx present  ->  load that map and INJECT the scripts into it.
                                Keeps its Workspace, Lighting, Terrain, bases
                                and scenery intact.
  no map                    ->  emit a bare place with just the scripts; the
                                world is generated at runtime by PlotService.

The injection is a merge-by-name, not an overwrite: the map's own
StarterPlayerScripts contains WindController, and clobbering the whole folder
would delete it. Containers that exist on both sides are recursed into;
same-named leaves are replaced so re-running is idempotent.

Referents are never renumbered. The map uses <Ref> properties internally
(PrimaryPart, ObjectValue targets, ...) and rewriting ids would mean rewriting
every reference in a 17 MB file. Instead, new items get referents drawn from a
namespace the map provably doesn't use.

    python tools/build_place.py
"""

import pathlib
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
MAP = ROOT / "assets" / "map.rbxlx"
OUT = ROOT / "BrainrotMines.rbxlx"

SERVICES = ["ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Lighting"]

# classes that hold children and should be merged into rather than replaced
CONTAINERS = {"Folder", "StarterPlayerScripts", "StarterCharacterScripts"}

_used_referents = set()
_counter = [0]


def fresh_referent():
    while True:
        _counter[0] += 1
        candidate = "BRM%d" % _counter[0]
        if candidate not in _used_referents:
            _used_referents.add(candidate)
            return candidate


def class_for(path):
    if path.name.endswith(".server.lua"):
        return "Script"
    if path.name.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def instance_name(path):
    return path.name.split(".")[0]


def name_of(item):
    p = item.find("Properties")
    if p is None:
        return None
    n = p.find("string[@name='Name']")
    return n.text if n is not None and n.text else None


def make_item(cls, name, source=None):
    item = ET.Element("Item", {"class": cls, "referent": fresh_referent()})
    props = ET.SubElement(item, "Properties")
    n = ET.SubElement(props, "string", {"name": "Name"})
    n.text = name
    if source is not None:
        s = ET.SubElement(props, "ProtectedString", {"name": "Source"})
        s.text = source
    return item


def build_tree(directory):
    """Mirror a src/ directory as Roblox Items."""
    items = []
    for entry in sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name)):
        if entry.is_dir():
            cls = "StarterPlayerScripts" if entry.name == "StarterPlayerScripts" else "Folder"
            folder = make_item(cls, entry.name)
            for child in build_tree(entry):
                folder.append(child)
            items.append(folder)
        elif entry.suffix == ".lua":
            items.append(
                make_item(class_for(entry), instance_name(entry),
                          entry.read_text(encoding="utf-8"))
            )
    return items


def merge_into(dest, new_child):
    """Merge one item into dest, replacing or recursing by Name."""
    nm = name_of(new_child)
    existing = None
    for child in dest.findall("Item"):
        if name_of(child) == nm:
            existing = child
            break

    if existing is None:
        dest.append(new_child)
        return

    both_containers = (
        existing.get("class") in CONTAINERS and new_child.get("class") in CONTAINERS
    )
    if both_containers:
        for grandchild in list(new_child.findall("Item")):
            merge_into(existing, grandchild)
    else:
        dest.remove(existing)
        dest.append(new_child)


def bare_place(service_items):
    """Fallback: hand-rolled XML with no map."""
    body = []
    for name, items in service_items:
        kids = "".join(ET.tostring(i, encoding="unicode") for i in items)
        body.append(
            '  <Item class="%s" referent="%s">\n'
            "    <Properties>\n"
            '      <string name="Name">%s</string>\n'
            "    </Properties>\n"
            "%s"
            "  </Item>\n" % (name, fresh_referent(), escape(name), kids)
        )
    body.append(
        '  <Item class="Workspace" referent="%s">\n'
        "    <Properties>\n"
        '      <string name="Name">Workspace</string>\n'
        "    </Properties>\n"
        "  </Item>\n" % fresh_referent()
    )
    return (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
        'version="4">\n'
        "  <External>null</External>\n"
        "  <External>nil</External>\n"
        '  <Meta name="ExplicitAutoJoints">true</Meta>\n'
        + "".join(body)
        + "</roblox>\n"
    )


def main():
    if not SRC.is_dir():
        print("error: %s not found" % SRC, file=sys.stderr)
        return 1

    service_items = []
    for service in SERVICES:
        directory = SRC / service
        if directory.is_dir():
            service_items.append((service, build_tree(directory)))

    if MAP.is_file():
        print("map found -- injecting scripts into assets/map.rbxlx")
        tree = ET.parse(MAP)
        root = tree.getroot()

        # claim every referent the map already uses before minting new ones
        for item in root.iter("Item"):
            ref = item.get("referent")
            if ref:
                _used_referents.add(ref)
        # rebuild our items now that the namespace is known
        service_items = []
        for service in SERVICES:
            directory = SRC / service
            if directory.is_dir():
                service_items.append((service, build_tree(directory)))

        injected = 0
        for service, items in service_items:
            target = None
            for item in root.findall("Item"):
                if item.get("class") == service:
                    target = item
                    break
            if target is None:
                target = ET.SubElement(root, "Item",
                                       {"class": service, "referent": fresh_referent()})
                props = ET.SubElement(target, "Properties")
                n = ET.SubElement(props, "string", {"name": "Name"})
                n.text = service

            for item in items:
                merge_into(target, item)
                injected += 1

        tree.write(OUT, encoding="utf-8", xml_declaration=False)
        print("  injected %d top-level items across %d services"
              % (injected, len(service_items)))
    else:
        print("no assets/map.rbxlx -- emitting a bare place")
        OUT.write_text(bare_place(service_items), encoding="utf-8")

    scripts = sum(1 for _ in SRC.rglob("*.lua"))
    print("wrote %s" % OUT.relative_to(ROOT))
    print("  %d scripts, %.1f MB" % (scripts, OUT.stat().st_size / 1024 / 1024))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
