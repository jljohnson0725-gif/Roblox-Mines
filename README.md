# Brainrot Mines — setup

Roblox Mines, but the payout is brainrots that pay you rent.
**Read `DESIGN.md` first** — it's the source of truth for direction.

This repo is files-on-disk mirroring the Studio Explorer tree, meant to be
copy-pasted in. There's no Rojo project and no build step.

## Just want to play it?

Double-click **`Play.cmd`**. That's it.

Don't double-click the `.rbxlx` directly — Windows has no file association for
it by default and hands it to a text editor. `Play.cmd` sidesteps that: it finds
Roblox Studio and opens the place with it. Studio lives in a version-hashed
folder that changes on every update, so the path is resolved at run time rather
than hardcoded.

(File → Open from inside Studio also works, any time.)

The world assembles itself at runtime on top of the imported map: `MapStyle`
restyles it to dusk, `PlotService` binds to the map's 8 bases, and
`MinesLandmark` / `UpgradeService` build the two street structures. With no map
present it falls back to generating plots on a blank baseplate instead.

Regenerate the place file after editing anything in `src/`:

```bash
python tools/build_place.py
```

## How the build works — read this before editing in Studio

The build has two modes and picks automatically:

| | |
|---|---|
| `assets/map.rbxlx` **exists** | loads that map and **injects** the scripts into it, preserving its Workspace, Lighting, Terrain, scenery and bases |
| no map | emits a bare place; the world is generated at runtime by `PlotService` |

Injection is a **merge by name**, so the map's own `WindController` under
StarterPlayerScripts survives alongside `ClientMain` and `UI`. Re-running is
idempotent — same-named items get replaced, not duplicated.

**⚠ The one rule: `BrainrotMines.rbxlx` is a build artefact, not your project.**
Every rebuild overwrites it from `assets/map.rbxlx` + `src/`. So:

- Changing **code**? Edit `src/`, rebuild. ✅
- Changing the **map** (moving buildings, adding props)? Do it in Studio, then
  **File → Save to File As → `.rbxlx`** over `assets/map.rbxlx`. Otherwise your
  edits vanish on the next build.

Saving the place file itself and expecting it to stick is the mistake to avoid.

## File suffix convention

| suffix        | make this in Studio |
|---------------|---------------------|
| `.server.lua` | **Script**          |
| `.client.lua` | **LocalScript**     |
| `.lua`        | **ModuleScript**    |

The instance name is the filename with all suffixes stripped —
`Bootstrap.server.lua` → a Script named `Bootstrap`.

## Explorer tree to build

```
ReplicatedStorage
└── Shared                    (Folder)
    ├── Config                (ModuleScript)
    ├── Rarity                (ModuleScript)
    ├── Variants              (ModuleScript)
    ├── Brainrots             (ModuleScript)
    ├── Economy               (ModuleScript)
    ├── MinesMath             (ModuleScript)
    ├── DropTable             (ModuleScript)
    ├── Format                (ModuleScript)
    ├── Assets                (ModuleScript)
    ├── Sounds                (ModuleScript)
    ├── Upgrades              (ModuleScript)
    ├── Events                (ModuleScript)
    └── Net                   (ModuleScript)

ServerScriptService
├── Bootstrap                 (Script)          ← the only Script in the game
└── Modules                   (Folder)
    ├── DataService           (ModuleScript)
    ├── PlayerState           (ModuleScript)
    ├── EventService          (ModuleScript)
    ├── ModelFactory          (ModuleScript)
    ├── MapStyle              (ModuleScript)
    ├── PlotService           (ModuleScript)
    ├── MinesService          (ModuleScript)
    ├── MinesLandmark         (ModuleScript)
    └── UpgradeService        (ModuleScript)

StarterPlayer
└── StarterPlayerScripts
    ├── ClientMain            (LocalScript)
    └── UI                    (Folder)
        ├── Theme             (ModuleScript)
        ├── HUD               (ModuleScript)
        ├── Fx                (ModuleScript)
        ├── MinesUI           (ModuleScript)
        ├── InventoryUI       (ModuleScript)
        └── UpgradeUI         (ModuleScript)
```

Folder names and nesting matter — modules resolve each other by path
(`script.Parent.Theme`, `ReplicatedStorage.Shared.Config`).

## Steps

1. New Baseplate in Studio. You don't need to build anything — plots are
   generated in code, and the whole UI is built in code too.
2. Create the three folders above (`Shared`, `Modules`, `UI`).
3. For each file in `src/`, create the matching instance and paste the contents.
4. Press Play.

For persistence in Studio: **Game Settings → Security → Enable Studio Access to
API Services**. Without it the game still runs — you'll see a
`running without persistence` warning and profiles just won't save.

## Controls

| input | action |
|-------|--------|
| `C`   | open/close Collection |
| `Esc` | close everything |
| walk to a pad + `E` | place, store, or unlock |
| walk to the red button + `E` | arm/disarm your laser door |
| walk to the **Mines console** + `E` | play Mines |
| walk to the **Upgrade shop** + `E` | buy upgrades |

**Mines has no keybind on purpose.** It only opens at the console under the
neon rings, so gambling pulls you out of your base and into the street. `M`
closes the panel but never opens it, and the server rejects `StartRound` from
out of range — the UI check alone wouldn't stop a remote being called from
anywhere. A live round can always be finished wherever you walk.

The **⚡ EQUIP BEST** button in the Collection panel clears every pad and refills
it with your highest-earning brainrots, sorted by actual income — a Galaxy Common
out-earns a Normal Epic, so it ranks by money, not by rarity badge.

## Events

One server-wide event at a time, starting every ~6 minutes and running about a
quarter of the time. The HUD card under your money shows the running event and
how long is left, or a countdown to the next one. The event *type* is hidden
until it starts, on purpose — see `DESIGN.md`.

Adding one is a single table entry in `Shared/Events.lua`. `weight` is how often
it's picked (rarer should mean stronger), and `mods` bends the existing drop
knobs. Watch `Frost` in `Variants.lua` for how an event-exclusive variant works:
base weight `0`, surfaced only by that event's `variantAdd`.

## Upgrades

Bought at the shop in the street, next to the Mines. Four axes, all permanent
and stacking, defined in `Shared/Upgrades.lua`:

| upgrade | at max | total cost |
|---|---|---|
| Rent Multiplier | ×6.00 income | ~$417M |
| Vault Capacity | 13h of storage | ~$29M |
| Fast Feet | 34 walk speed | ~$1.4M |
| Long Arms | 39 stud collect reach | ~$2.3M |

**There is deliberately no luck upgrade.** Buying better drop odds would attack
the first design pillar — *the multiplier IS the luck stat*. If luck is
purchasable, the mine-count dial and the cash-out decision both matter less.
Every upgrade here moves money, time or distance; none touch the drop table.

Costs are geometric, so sanity-check any change — an early draft used 40 levels
at 1.9× growth and put the last level at **$371 trillion**, a curve players
abandon rather than a sink they spend into.

## Balance tuning

Every tunable lives in `Shared/Config.lua`, `Shared/Rarity.lua`, and
`Shared/Variants.lua`. After changing any of them:

```bash
python tools/balance.py
```

It re-derives the drop odds, the payout curve, and — most importantly — whether
any mine count has become strictly dominant. If the reported spread goes above
1.6× the risk selector is dying; see pillar 3 in `DESIGN.md`.

## Swapping the sounds

Audio uses Roblox's **built-in** `rbxasset://sounds/...` cues, so it works with
zero uploads and nothing can be moderated out from under you. It's a plain
palette — replace it when you have real SFX.

Every cue is one line in `Shared/Sounds.lua`. Change the `id` and nothing else
needs to know. Worth doing first, in order: `bust`, `cashout`, `stinger` — those
three carry the emotional beats.

`Sounds.Spectacle` in the same file controls how loud a drop gets to be per
tier — shake, flash, confetti count, stinger pitch, hold time, and whether it
announces server-wide. Common and Uncommon are deliberately silent spectacle-wise
(`level = 0`); see `DESIGN.md` for why.

## Art assets

Two kinds, with very different workflows.

**UI pack (`.rbxmx`)** — its images are *already uploaded to Roblox*, so they
work immediately. Convert the pack to XML in Studio (right-click the ScreenGui →
**Save to File As** → set the dropdown to **Roblox XML Model Files**; renaming
the extension does nothing), then:

```bash
python tools/extract_assets.py "path/to/YourUiPack!.rbxmx"
```

That regenerates `Shared/Assets.lua` with every id, grouped by screen.

**Icon PNGs** — these are local files and *must be uploaded* to get an asset id.
A shortlist of 23, already renamed to their UI roles, is staged in
`assets/icons/_upload/`. Import them via Studio's **Asset Manager → Images →
Import**, then paste the ids into `Assets.UI`.

### How the UI consumes them

`Assets.UI` is the only table the game reads, and it's never regenerated —
`Assets.Pack` is. A slot set to `nil` means "keep the text-glyph fallback", so
adopting the art is incremental and instantly reversible: blank a slot and the
`✕`/`◆`/`⚡` glyph comes straight back. Wire one up with
`Theme.iconify(button, "slot")` or `Theme.image({ slot = "..." })`.

## Adding a brainrot

One line in `Shared/Brainrots.lua`:

```lua
{ id = "my_guy", name = "My Guy", tier = "Epic", mul = 1.0, color = Color3.fromRGB(200, 120, 60) },
```

`mul` (0.85–1.20) varies income within the tier. Nothing else needs to know.

## Using real models

Make a folder `ReplicatedStorage/BrainrotModels` and put models in it named
exactly the character `id` from `Brainrots.lua` (e.g. `tung_tung_sahur`).
`ModelFactory` picks them up automatically, applies the variant tint, and
anchors them. No code change. Anything without a model keeps its placeholder.
