# 2V2 TrenchBroom Mapping Guide

Everything here is measured straight from the actual game code (player/enemy
collision capsules, movement numbers) and the actual FuncGodot config in this
repo (`addons/func_godot/func_godot_default_map_settings.tres`,
`fgd/game_entities.tres`) — not generic Quake/Source lore. If the game's
numbers change later, this doc needs a pass too.

Your friends **never need TrenchBroom, GitHub, or Godot access to each
other's setup** — you hand them a small kit of plain files, they make a map
and send you back a single `.map` file (plus any new textures they used),
and you're the only one who ever touches Godot. Sections 1–3 below are that
whole handoff; sections 4 onward are the reference material to send along
with the kit.

## 1. Building the kit (you do this — once, and again whenever entities or textures change)

This step needs your Godot project open. The output is a handful of plain
files your friends drop into their own TrenchBroom install — nothing about
this step requires them to have Godot or this repo at all.

1. **Open this Godot project.** In the FileSystem dock, open
   `addons/func_godot/func_godot_local_config.tres`. This file is personal to
   your machine (not something you'd hand to friends) — it just tells your
   own Godot where to write the exported files in the next step:
   - **Trenchbroom Game Config Folder**: point this at a **`2v-2` subfolder**
     inside TrenchBroom's own `games` folder — on Windows that's normally
     `%AppData%\TrenchBroom\games\2v-2`. Create the folder if it doesn't
     exist yet.
   - Click **"Export func_godot settings"** in the Inspector to save that path.
2. Open `addons/func_godot/game_config/trenchbroom/func_godot_tb_game_config.tres`
   and click **"Export GameConfig"** in its Inspector. This writes three
   files into the folder from step 1: `icon.png`, `GameConfig.cfg`, and
   `game_entities.fgd`.
3. **Build the kit:** in File Explorer, right-click
   `tools/build_mapping_kit.ps1` in this project → **Run with PowerShell**.
   It makes `2v2_mapping_kit.zip` on your Desktop with the game config, every
   texture in `trenchbroom/textures/`, this guide, and a `SETUP.bat` that
   sets up TrenchBroom for them.
4. Send that zip however you'd normally send a file to friends (Discord,
   Drive, email) — no GitHub involved.

Re-run step 3 (and step 2 first, if entities changed) any time an entity
definition changes (new pickup type, new enemy variant, changed properties)
or you add new textures, and send the new zip.

## 2. Your friends' one-time setup (no GitHub, no Godot needed)

Each friend does this once, on their own machine:

1. **Install [TrenchBroom](https://trenchbroom.github.io/)** — the latest
   release (older versions can't read this game config).
2. Move the kit zip somewhere permanent, like Documents (not Downloads or a
   temp folder), then right-click it → **Extract All**.
3. Make sure TrenchBroom is closed, open the unzipped folder, and
   double-click **`SETUP.bat`**. It installs the 2v-2 game config and points
   TrenchBroom at the kit's textures. If Windows shows "Windows protected
   your PC", click **More info → Run anyway**.
4. Open TrenchBroom → **New map** → **2v-2**. All the textures are in the
   texture browser.

If you ever move the kit folder, run `SETUP.bat` again. **On a Mac** (no
SETUP.bat): copy `GameConfig.cfg`, `game_entities.fgd` and `icon.png` into
`~/Library/Application Support/TrenchBroom/games/2v-2/`, then in TrenchBroom
→ Preferences → Games → 2v-2, set **Game Path** to the unzipped kit folder
(the one with `textures` directly inside it).

## 2b. Testing your own map (no Godot needed)

1. Open the game in your browser: https://marcovelez4321-jpg.github.io/mygame/
   (first load takes a bit -- it's downloading the whole game).
2. Click into the game, press **Esc**, then **Load Test Map**, and pick your
   `.map` file (it's wherever you saved it from TrenchBroom). You can also
   just drag the `.map` file onto the game.
3. You spawn at your `info_player_start` with your enemies and pickups.
   Changed something in TrenchBroom? Save, then **Esc → Load Test Map**
   again.

Nothing gets uploaded -- the map stays on your computer. Any texture that
isn't in the kit shows up as a placeholder; send that PNG along with the map.

## 3. Making a map and sending it back

1. Friend: **File → New Map → 2v-2**, block it out, place entities
   (section 7), texture it with whatever's in the kit's `textures` folder
   (section 8 covers requesting/adding more).
2. Friend: **File → Save**, and sends you just the **`.map` file** — Discord,
   email, whatever. If they used any texture that wasn't in the kit, they
   send that PNG too.
3. You: drop the `.map` file into this project's `maps/` folder (e.g.
   `maps/their_map.map`). Duplicate `scenes/arena1_level.tscn` (the
   reference example — a `FuncGodotMap` node under a plain level scene) and
   rename the copy. Select its `FuncGodotMap` node and set `Local Map File`
   to the new `.map` path.
4. Click the **"Build Map"** button on that same node's Inspector. This
   parses the `.map`, generates collision/meshes, and drops in real Godot
   nodes for every entity they placed (enemies, pickups, the spawn point).
5. Press play on that scene to test.

Re-click **Build Map** any time you get an updated `.map` from them.

## 4. Scale & grid

This project's FuncGodot scale is **32 TrenchBroom units = 1 meter**
(`inverse_scale_factor = 32`, set in
`addons/func_godot/func_godot_default_map_settings.tres`). Every number
below is given in both meters (the game's own units) and TrenchBroom units
(what you'll actually type into TrenchBroom) so there's no unit confusion.

**Grid recommendation:** build on TrenchBroom's **16-unit grid** for
blockout — the game's own step-up height lands exactly on 16 units (see
below), so a 16-grid keeps your floors/ledges aligned with what the player
can silently walk over. Only drop to 8 or smaller for texture/detail
alignment, never for gameplay-critical geometry (ledges, doorway edges) —
off-grid seams are where collision snags happen.

## 5. Size reference

| | meters | TrenchBroom units |
|---|---|---|
| Player capsule radius | 0.4 m | 12.8 u |
| Player capsule height | 1.8 m | 57.6 u |
| Player eye height | 1.6 m | 51.2 u |
| Enemy capsule radius | 0.4 m | 12.8 u |
| **Enemy capsule height** | **2.3 m** | **73.7 u** |

The enemy is *taller* than the player — enemies are what your doorway/ceiling
heights actually need to clear, not just the player.

**Doorways & corridors** (both player and enemy are ~0.8 m / 26 u wide):
- Absolute minimum walkable corridor: **64 u** (2 m). Anything tighter and
  the player capsule will catch on corners.
- Standard doorway width: **96 u** (3 m) — comfortable for a player and an
  enemy to pass without snagging.
- Main hall / combat doorway: **128–160 u** (4–5 m).
- Doorway height: minimum **96 u** (3 m) to clear an enemy with headroom;
  **128 u** (4 m) reads as comfortable, not cramped. There's no crouch
  system in this game, so nothing should ever require ducking through — if
  a space needs to be tighter than 96 u tall, it should be enemy-inaccessible
  on purpose (a player-only shortcut), not a main path.

**Ceiling height (rooms):** standard rooms 128–192 u (4–6 m); big arena
spaces 256 u+ (8 m+).

This is also a standard, well-worn FPS convention (Quake/Half-Life-era
shooters generally keep corridors around 2–3× character width) — it's not
just a made-up number, it's this project's own measurements landing in the
same place genre convention already points to.

## 6. Traversal reference

Use these to design ledges, gaps, and verticality that are actually
reachable (or deliberately not).

| Move | Range |
|---|---|
| Auto step-up (silent, no input) | up to **16 u** (0.5 m) |
| Plain jump | up to **~34 u** (~1.06 m) |
| Mantle (hold Space near a ledge) | **19 u – 67 u** (0.6 m – 2.1 m) |
| Dash (rough burst distance) | **~65–77 u** (~2–2.4 m), treat as approximate |
| Wall-jump (needs a wall within reach behind the player) | wall must be within **~22 u** (0.7 m), in roughly a 50° cone behind them |

- **0–16 u** tall ledge: player just walks up it, no jump needed.
- **16–34 u**: needs a plain jump.
- **34–67 u**: needs a mantle — a roughly vertical face with a roughly flat
  top surface within that height range, and something to stand in front of
  within about a meter. The detection is forgiving (a wide raycast fan, not
  a pixel-perfect aim requirement), so it doesn't need to be architecturally
  perfect, just a clear wall-with-a-ledge-on-top shape.
- **Above 67 u (2.1 m)**: not reachable directly. Use stairs/platforms for
  any intended path, or leave it tall on purpose as a hard boundary /
  one-way drop.
- **Wall-jump spots**: two roughly-parallel walls (or a wall behind an open
  ledge) no more than ~0.7 m apart read as a deliberate wall-jump chance —
  good for vertical shafts or side alcoves. A wide-open room won't trigger
  it at all.
- **Dash** is a burst, not a guaranteed gap-closer — don't rely on it as the
  *only* way across a gap on a main path; fine for shortcuts/secrets.

## 7. Entities you can place

All of these are defined in `fgd/` and show up in TrenchBroom's entity
browser once the game config is exported (section 1) and each friend has
gone through section 2.

| Classname | What it is | Notes |
|---|---|---|
| `info_player_start` | Spawn point | Place exactly one per map. |
| `monster_enemy` | Base melee enemy | Walks in, swings. |
| `monster_enemy_rusher` | Fast melee enemy | Telegraphs, then dashes in. |
| `monster_enemy_gunner` | Ranged enemy | Keeps its distance, bursts fire. |
| `item_weapon_starter_gun` | Starter pistol pickup | |
| `item_weapon_machine_gun` | Machine gun pickup | |
| `item_ammo` | Ammo pickup | Has editable properties in TrenchBroom: `ammo_type` (Bullets / Shells / Rockets) and `amount` (default 20). |
| `item_key` | Silver or gold key | Walk through it to carry it. See section 7b. |
| `func_door` | Sliding door (brushes) | See section 7b. |
| `func_door_rotating` | Swinging door (brushes) | See section 7b. |
| `func_button` | Button you press with F (brushes) | See section 7b. |
| `func_lever` | Lever you pull with F (brushes) | See section 7b. |

There's currently no placeable shotgun pickup entity (the shotgun exists in
code but has no FGD point class yet) — if you want one placeable in
TrenchBroom, that needs to be added on the code side first.

## 7b. Doors, buttons, levers and keys

**Open `sample_doors_and_levers.map` from the kit first** — it has one of
each, already working. Click any of them and look at the entity panel on
the right to see how it's set up. Load it with **Load Test Map** in the game
to try it.

These work the way Quake does it: **names connect things**. A door gets a
**targetname** (its name), a button or lever gets a **target** (the name of
what it opens). If they match, pressing the button opens the door. No code,
no Godot.

**Brush entities** (doors, buttons, levers) are made from normal brushes:
build the shape, select it, then **right-click → Create Brush Entity →**
pick the type. Its settings appear in the entity panel on the right. Hover
over a setting's name to see what it does. Every setting has a sensible
default — usually you only set a name and a direction.

### A lever that opens a gate
1. Build the gate's brush(es) in the doorway. Right-click → Create Brush
   Entity → `func_door`.
2. In the entity panel: **targetname** = `gate1` (any name), **angle** = `-1`
   (slides up).
3. Build a small lever brush on a wall (e.g. 8 × 16 × 56 units). Right-click
   → Create Brush Entity → `func_lever`.
4. **target** = `gate1` (exactly the same as the gate's targetname).
5. **axis**: the line the lever swings around — if the wall it's on runs
   east-west, pick *East-west line*; north-south, pick *North-south line*.
   It pivots on its **bottom edge** by default.
6. In game: walk up, look at it, **[F] Pull** appears — press F. Pull it
   again to close the gate.

### A button that opens a door
Same as above, but make the button brush a `func_button`, set its
**target**, and set **angle** to point *into* the wall it's on (in the top
view: 0 = east, 90 = north, 180 = west, 270 = south). It pushes in, the door
opens, it pops back out after a second.

### A swinging door
`func_door_rotating` instead of `func_door`. Pick its **hinge**: e.g.
*West or south end* for a door hinged on one side. (Or the Quake way: draw
a small extra brush painted with the **origin** texture where the hinge
goes, include it in the door entity, and leave hinge on *Origin brush*.)
**distance** = how far it swings (90 = a quarter turn; negative swings the
other way).

### A door locked by a key
1. Make a `func_door` with **no targetname** (it opens when you walk up)
   and set **key** = *Gold*.
2. Place an `item_key` (point entity) somewhere else and set **key_type** =
   *Gold*.
3. Walking up without the key shows "You need the gold key".

### Common mistakes
- **Lever/button does nothing** → the target and targetname don't match
  exactly (`gate1` vs `gate_1`). Load Test Map lists every name that
  doesn't match in the top-left corner.
- **Lever spins around its middle** → hinge is set to *Origin brush* but
  there's no origin brush. Pick *Bottom edge* (the default) instead.
- **Door slides the wrong way** → change **angle**. -1 = up, -2 = down.
- **Door closes after 3 seconds when you wanted it to stay open** → set
  **wait** = `-1`. (Doors opened by a button/lever already stay open.)

## 8. Adding more textures

Textures are **plain PNG files** (not a `.wad`). In your own project they
live in `trenchbroom/textures/`; in a friend's mapping folder (section 2)
they live in the `textures` subfolder you gave them.

**You adding textures for everyone:**

1. Drop the new PNG file(s) into this project's `trenchbroom/textures/`.
   Power-of-two sizes (256×256, 512×512, etc.) are standard and tile best.
2. Send just that/those PNG file(s) to your friends (no need to re-zip and
   resend the whole kit) — they drop them into the `textures` subfolder
   inside their own mapping folder from section 2.
3. Everyone (you included): in TrenchBroom, use **View → Refresh Texture
   Collections** (or restart TrenchBroom) so it picks up the new files —
   TrenchBroom reads straight from that folder, no re-export/re-kit needed
   for textures specifically, only for entity changes (section 1).
4. Texture brushes with it in TrenchBroom like normal.
5. Whoever builds the map in Godot (you) clicks **Build Map** on the level's
   `FuncGodotMap` node. The first time a texture gets used, FuncGodot
   automatically generates a matching Godot material
   (`trenchbroom/textures/your_texture.tres`) next to the PNG — nobody
   creates materials by hand. If you want a texture to look different
   in-game (glow, transparency, a custom shader) than its flat default look,
   edit that generated `.tres` afterward in Godot; it won't be overwritten
   once it exists.

**A friend using their own custom texture:** they just need to send you that
PNG along with their `.map` file (section 3, step 2) — drop it into
`trenchbroom/textures/` on your end before you Build Map, so the name the
`.map` file references actually resolves to something.

**Tool textures** (already set up, no material needed since they're never
rendered): paint a face with a texture literally named
- `clip` — invisible collision, no visual mesh (block off a passage without
  a visible wall).
- `skip` — removed entirely, no mesh and no collision.
- `origin` — used only to mark a brush entity's origin point, removed from
  the final mesh/collision.

These names must be exact (lowercase) — they don't need to exist as actual
PNG files for TrenchBroom to treat them specially, but TrenchBroom will want
*some* texture to display in its own view, so it's worth adding a simple
placeholder PNG for each in `trenchbroom/textures/` if you don't already see
one.
