# The World — open-world plan

The game's world, as decided with the user on 2026-10-09. RULES.md's
Creative Direction is the short version; this is the full plan we build from.
Everything here still goes through the rules (co-op ready, simple and
optimized, exports for balance, sound as a pillar, Metroidvania).

## The idea

Grandma's suburban house is the one untouched piece of the old world. Past
her yard the land has changed: purple and blue, wavy and wrong, grown over
with coral-reef growths, with the old world's megastructures standing
half-swallowed in it. You walk out of her yard into one open world. Grandma
gives you quests, and so do the people living out there. No portals.

## Decisions

| Topic | Decision |
|---|---|
| Setting | The alien world replaces the lawless city |
| Structure | One continuous world, loaded in chunks around each player (Minecraft-style), no gates or loading screens |
| How it's made | Hybrid: procedural alien terrain and growth fill the wilds; hand-made islands, megastructures and quest spots are placed on top |
| Terrain | Terrain3D (Godot 4 terrain addon) with our PS1 shader and big low-poly spacing |
| First playable size | 1 x 1 km |
| Co-op | Free roam: the host keeps chunks loaded around every player (Valheim-style) |
| Gravity zones | None |
| Quests | From Grandma and from people in the world; data-driven |
| Day/night | Full cycle; coral, glow grass and kelp glow at night |
| Enemies | The changed world's creatures + scavenger/cultist factions (A-Life) |

## Look: purple and blue

The terrain shader colours the ground by:
- **Height:** deep indigo valleys, through violet, to lavender and periwinkle ridges.
- **Slope:** steep faces darker and bluer, like wet rock.
- **World noise:** large slow blotches of teal-blue moss and magenta rust, so it never reads flat.

PS1 fog is a purple haze, so distance fades to purple instead of grey. The
sky is a sickly gradient, violet at the horizon to deep blue above.
Everything goes through the PS1 shader (vertex snap, per-vertex light,
nearest textures).

## Growth (coral reef on land)

| Growth | What it is | Role |
|---|---|---|
| Staghorn thickets | Branching coral, knee to tree height, glowing tips | "Forests", sightline blockers |
| Kelp stalks | Tall swaying stalks with glowing bulbs | Vertical "trees", silhouettes in fog |
| Brain coral | Low ridged domes | Ground cover |
| Glow grass | Dense bioluminescent carpets | Fills ground cheaply |
| Sea fans | Flat lace sheets that sway | Cheap cut-out cards |
| Anemone fields | Tendril clumps that snap shut when you get close | Interactive, sound |
| Tube sponges | Clusters of hollow chimneys that puff spores | Landmarks |
| Reef crust | Coral growing over the megastructures | Ties the old world to the new |

**Gameplay growth:**
- **Breakable coral walls:** Metroidvania locks, broken later with explosives.
- **Healing polyps:** pop for health, nature's HL2 health charger.
- **Stinging coral:** damage on touch, keeps you on paths.

**How:**
- The procedural layer scatters growth by biome noise (coral forest, glow-grass plains, sponge flats).
- Terrain3D's instancer draws thousands of copies in one batch. Hero pieces are placed by hand.
- Models are low-poly, from Blender. A small generator can bake many branching-coral variations.
- Sway runs in the vertex shader.
- Growth fades out at distance under the fog, and far forests become cards.

## Life (not enemies)

- **Sky:** flocks of fish or birds; sky jellyfish (drift overhead, pop into goo when shot); passive flying beetles (car-sized, slow and heavy, in loose groups of two or three, a drone you hear before you see them, faint glow at night, panic and buzz off when shot); giant silhouettes drifting far off in the fog, never reachable (Shadow of the Colossus).
- **Ground:** hermit beetles wearing old-world junk as shells (traffic cones, TVs, mailboxes); giant isopods grazing glow grass that roll up when scared.
- **Walls and coral:** nautilus-shelled snails climbing megastructures; urchin ticks clinging to coral that puff spines when touched.

All of it is cheap ambient life:
- Flocking for the flocks.
- Simple wander and flee for the rest.
- Simulated only near players, and run on the host only where it matters for gameplay.

## Structure and streaming

- **Ground:** Terrain3D holds it as region tiles and draws distant ground in less detail.
- **Chunks:** everything on top (growth, megastructures, enemies, loot, quest spots) lives in chunks of roughly 64–128 m, each its own scene, loaded in the background around each player and freed behind them.
- **Landmarks:** PS1 fog hides the load edge. Megastructures get a cheap always-loaded silhouette so they stay visible across the map.
- **Co-op:** the host keeps chunks loaded around every player; each player's game loads what's near them (Rule 1).
- **Persistence:** per-chunk world state (dead bosses, opened walls, looted stashes) plus player progression, synced by the host.

## A-Life

S.T.A.L.K.E.R.-style:
- Squads near a player run full AI.
- Squads far away are simulated cheaply on a map of points of interest (travel, fight, claim, scavenge).
- It runs on the host and builds on the existing Factions system.
- Starts as "lite": squads patrol between points and clash.

## Sound (a pillar)

- Ambience and reverb zones per area.
- Distant megastructure groans.
- Coral creaks, anemones snapping, sponge bubbling, wind through sea fans.
- The flying beetles' drone.
- Night has its own soundscape.

## Milestones

1. **M0, tech spike:** Terrain3D installed; purple/blue PS1 terrain shader; purple fog and sky; a 3 x 3 chunk streamer; one coral type scattered by the instancer; a frame-time and memory budget.
2. **M1, vertical slice:** Grandma's yard + 1 x 1 km of land, one megastructure, a few growth types, a first quest from Grandma and one from someone in the world.
3. **M2, life:** day/night with glow, sky jellyfish, flying beetles, flocks, fog silhouettes, ground critters.
4. **M3, A-Life lite:** squads, points of interest, faction clashes.
5. **M4, scale:** persistence, co-op streaming, the world grows past 1 km.

## References (Rule 6)

- **S.T.A.L.K.E.R.:** A-Life (online/offline simulation).
- **Minecraft:** chunk streaming.
- **Valheim:** co-op streaming around each player.
- **Silent Hill:** fog as both mood and draw distance.
- **Shadow of the Colossus:** awe of giant shapes.
- **Metroid Prime / Hollow Knight:** locks and shortcuts in an open space.
- **Half-Life 2:** health chargers (healing polyps).
- **Subnautica:** reef life and bioluminescence.

## The skyline: giants past the fog (SkylineLayer)

Megastructures and growths kilometres tall, kilometres away, that you see rising out of the murk but never reach. It's the Half-Life 2 3D-skybox idea (the Citadel), done as real geometry at real distance, so they shift slowly as you walk, like mountains.

**Making your own:**
1. Build it in TrenchBroom (or Blender) at any comfortable size, e.g. a 100 m tower.
2. Build the map with func_godot as usual (or export the Blender model as glTF).
3. In the world scene, put the scene under the `SkylineLayer` node, place it 2–8 km out, and scale the instance up (×16 turns a 100 m tower into 1.6 km).
4. That's it. On load, SkylineLayer swaps its materials for `skyline.gdshader` (same textures and colours), turns off its shadows and collision, and pushes the camera's view distance out to `view_distance`.

**Notes:**
- Everything scales with it (doorways become 30 m tall, textures chunkier). That's fine for things you never reach. Walk-up megastructures are built at real size and not scaled.
- Keep them low-poly: a few hundred to a couple of thousand triangles. They're always loaded and never stream.
- Their fog (`thin_height`, `near_reach`, `far_reach` on SkylineLayer) is as thick as the world's at the ground and thins with height. That's what makes the feet vanish and the tops loom.
- Small glowing lights or windows on them tell your eye how big they are.
- While nothing is under SkylineLayer, it grows stand-ins: colossal silhouettes of the giant growths, plus a tower and a loop of land.
