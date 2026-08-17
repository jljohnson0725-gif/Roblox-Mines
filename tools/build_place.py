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

import json
import pathlib
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
MAP = ROOT / "assets" / "map.rbxlx"
MESHES = ROOT / "assets" / "meshes.json"
OUT = ROOT / "BrainrotMines.rbxlx"

SERVICES = ["ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Lighting"]

#[[ Variants that get a REAL model rather than a tinted shell. Only the ones
#   whose art actually exists in meshes.json: Rainbow ships untextured in the
#   pack and Frost was never in it, so both stay on the shell. Hacker has art
#   but no variant in Variants.lua, so emitting it would be dead weight in the
#   place -- add the name here the day that variant exists. ]]
VARIANT_MODELS = ["Gold", "Diamond", "Lava", "Galaxy"]

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


def _bool(props, name, value):
    e = ET.SubElement(props, "bool", {"name": name})
    e.text = "true" if value else "false"


def _vector3(props, name, x, y, z):
    v = ET.SubElement(props, "Vector3", {"name": name})
    for axis, val in (("X", x), ("Y", y), ("Z", z)):
        e = ET.SubElement(v, axis)
        e.text = "%.6f" % val


def _content(props, name, url):
    c = ET.SubElement(props, "Content", {"name": name})
    u = ET.SubElement(c, "url")
    u.text = url


def make_meshpart(name, mesh_id, texture_id, native, scale):
    """One MeshPart. `size` != `InitialSize` is what scales the geometry."""
    item = ET.Element("Item", {"class": "MeshPart", "referent": fresh_referent()})
    props = ET.SubElement(item, "Properties")
    n = ET.SubElement(props, "string", {"name": "Name"})
    n.text = name

    _content(props, "MeshId", mesh_id)
    _content(props, "TextureID", texture_id or "")
    _vector3(props, "InitialSize", *native)
    _vector3(props, "size", *[v * scale for v in native])
    _bool(props, "Anchored", True)
    _bool(props, "CanCollide", False)
    _bool(props, "CanQuery", False)
    _bool(props, "CanTouch", False)
    return item


def build_mesh_library():
    """
    ReplicatedStorage.BrainrotModels, baked from assets/meshes.json.

    This exists because MeshPart.MeshId is NOT writable from a runtime script --
    a MeshPart has to already be in the place and be cloned. Keeping the asset
    ids in JSON and emitting the parts here means the library is reproducible
    from source rather than something hand-placed in Studio that the next build
    would wipe.
    """
    if not MESHES.is_file():
        return None, 0

    data = json.loads(MESHES.read_text(encoding="utf-8"))
    models = data.get("models", {})
    default_target = data.get("defaultTarget", 4.4)

    folder = make_item("Folder", "BrainrotModels")
    variant_folders = {}
    variant_count = 0

    for char_id in sorted(models):
        entry = models[char_id]
        native = entry["native"]
        target = entry.get("target", default_target)
        scale = target / max(native)

        model = make_item("Model", char_id)
        # Body carries the paint job; BodyPlain is the same geometry with no
        # texture, so a variant WITHOUT real art has something to tint.
        model.append(make_meshpart("Body", entry["mesh"], entry["texture"], native, scale))
        model.append(make_meshpart("BodyPlain", entry["mesh"], "", native, scale))
        folder.append(model)

        #[[ A variant with real art becomes its own Model under a folder named
        #   after the variant, and needs no BodyPlain -- the shell exists only to
        #   fake a colour we don't have a texture for. Same mesh id as Normal,
        #   because the pack's variants are pure retextures. ]]
        for variant in VARIANT_MODELS:
            texture = entry.get("variants", {}).get(variant)
            if not texture:
                continue
            sub = variant_folders.get(variant)
            if sub is None:
                sub = make_item("Folder", variant)
                variant_folders[variant] = sub
                folder.append(sub)
            skin = make_item("Model", char_id)
            skin.append(make_meshpart("Body", entry["mesh"], texture, native, scale))
            sub.append(skin)
            variant_count += 1

    return folder, len(models), variant_count


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

        # Baked mesh library rides along in ReplicatedStorage. Built after the
        # referent namespace is claimed so its ids can't collide with the map's.
        mesh_folder, mesh_count, skin_count = build_mesh_library()
        if mesh_folder is not None:
            for service, items in service_items:
                if service == "ReplicatedStorage":
                    items.append(mesh_folder)
                    break

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
        if mesh_folder is not None:
            print("  mesh library: %d characters, %d variant skins" % (mesh_count, skin_count))
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
