# Audio Design — research and system plan

Rule 7 says sound design is a core pillar. This doc is the research behind it:
how Valve (HL2, GMod, Alyx) builds physics and ragdoll audio, how we copy it,
how the PS1 sound gets applied to everything, and the exact list of sounds
needed. **Direction: Valve's system as the foundation, plus our own extra
ragdoll layers on top** (a heavy body drop, per-bone variety, a ground
layer, a drag loop and bone crunches) for audio that goes
further than GMod.

---

## 1. How Valve does it (Source engine: HL2, GMod)

GMod's ragdoll and prop audio is not a GMod feature. It's Half-Life 2's
physics audio, which GMod inherited unchanged. So "sounds like GMod" means
"uses Source's system", and that system is public in Valve's SDK code.

### 1a. Every sound is a definition, not a file ("soundscripts")
A sound name like `Flesh.ImpactHard` points to a soundscript entry that sets:
- a **list of wav variations**, one picked at random each play (`rndwave`)
- a **volume range** and **pitch range**, re-rolled each play
- a **soundlevel** (how fast it fades with distance)
- a channel

**We already have this:** `SoundEvent` (clips list, volume/pitch variance,
bus). Missing: per-sound distance falloff and per-sound voice limits.

### 1b. Every material has its own sound set ("surface properties")
Each material (flesh, metal, wood, concrete, dirt...) defines:
`impacthard`, `impactsoft`, `scraperough`, `scrapesmooth`, `bulletimpact`,
`break`, `stepleft`/`stepright`, plus physical numbers (density, friction,
elasticity) and audio numbers:
- **hardnessFactor / hardThreshold**: decides hard vs soft impact sound
- **hardVelocityThreshold**: below this speed it's always the soft sound
- **roughnessFactor / roughThreshold**: decides rough vs smooth scrape
- **reflectivity**: how much sound bounces off it

Models declare a material with `$surfaceprop`. Ragdolls can give **individual
bones their own material** with `$jointsurfaceprop` (a helmeted head can
clank like metal while the body thuds like flesh).

### 1c. The impact pipeline (from Valve's SDK source)
This is the part that makes GMod bodies sound right instead of like a
machine gun of clicks:

1. **Ignore tiny or repeated hits.** No sound if impact speed is under 70
   units/s (about 1.8 m/s), or if that object already made an impact sound
   less than **0.05 s** ago.
2. **Loudness grows with speed squared:** `volume = speed² / 320²`
   (320 units/s ≈ 8 m/s is full volume), clamped to 1. A gentle tap is very
   quiet; a slam is loud. That curve is why it feels physical.
3. **Hard or soft:** play the soft impact if the thing it hit is softer than
   this material's hardThreshold, or the speed is under hardVelocityThreshold.
   Otherwise hard.
4. **Merge per frame:** all impacts of the same material in one physics frame
   become **one** sound. The volumes add up, it plays from the loudest hit's
   position, and keeps the highest speed. After 4 sounds in a frame,
   everything merges. That's why 15 ragdoll bones hitting the floor at once
   sound like one meaty thud.
5. **Scrapes are loops, not one-shots.** A sliding object gets one looping
   scrape sound whose volume follows sliding energy (squared, same idea as
   impacts), rough or smooth picked by roughness. It stops 0.1 s after the
   sliding stops. Only a few scrapes can run at once.

### 1d. Environments
- **Soundscapes**: per-area ambient beds plus random one-shots (distant
  creaks, wind) so a place sounds alive.
- **DSP presets**: per-area reverb/room treatment, including an automatic
  mode that guesses the room.

### 1e. What Valve added later
- **Portal 2 / CS:GO, "sound operator stacks"**: per-sound start/update/stop
  logic (voice limits, distance mixes, fades). Valve needed real mixing
  rules, not just files.
- **Half-Life: Alyx (Source 2)**: Steam Audio (HRTF, occlusion), prop
  impacts with **velocity-driven layering** and "many thousands of possible
  variations", props that rattle with their contents (matches in a box, ammo
  in a clip), and a big emphasis on close, intimate Foley for bodies and
  movement.

## 2. Valve's system mapped to ours

| Valve (Source / GMod) | Ours (Godot) |
|---|---|
| soundscripts (variations, pitch/volume ranges, soundlevel) | `SoundEvent` + distance falloff + voice limit |
| surface properties per material | `SurfaceAudio` resource per material |
| `$surfaceprop` / `$jointsurfaceprop` (per bone) | material on each prop / each ragdoll bone |
| impact volume = speed², clamped | same formula |
| 70 u/s speed gate + 0.05 s cooldown | same, in meters |
| hard vs soft by hardness + speed thresholds | same |
| same-material impacts merged per frame | same |
| looping scrape that follows sliding energy | same |
| soundscapes + DSP presets | ambience beds + `Area3D` reverb zones |
| (nothing — Source stops here) | **our extra ragdoll layers**, section 3D |

## 3. The system we'd build

**A. SoundEvent upgrades.** Add distance falloff and a max-voices limit, so
any sound can say "never more than 3 of me at once".

**B. SurfaceAudio (one resource per material).** Holds impact soft/hard,
scrape loop, bullet impact, footsteps and break, plus the hardness/roughness
thresholds. Your TrenchBroom textures are already named by material
(`Brick_`, `Metal_`, `Wood_`, `Dirt_`, `Tile_`, `Stone_`, `Plaster_`), so the
level's materials can be mapped automatically from texture name. No per-face
setup.

**C. PhysicsAudio (shared by ragdolls and props).** Every physics body reports
its contacts, and the system runs the Source pipeline from 1c: speed
threshold, 0.05 s cooldown, speed² volume, hard/soft choice, merge per frame,
looping scrapes.
Engine note: Godot's ragdoll bones (`PhysicalBone3D`) don't have the contact
signals regular rigid bodies do. The plan is to turn on contact reporting
through `PhysicsServer3D` and read contacts each physics frame. Fallback is
detecting impacts from a sudden velocity drop on a bone. Either needs a quick
in-game test.

**D. Ragdolls: Valve's base, plus our layers.**

*The base (exactly GMod):*
1. **Death vocal**: already exists (`enemy_death`), plays when it dies.
2. **Every bone is flesh.** Each ragdoll bone carries the flesh material and
   runs through C: speed gate, 0.05 s cooldown, speed² volume, soft or hard
   depending on what it hit, same-material hits merged per frame.

*Our layers on top (what Source doesn't do):*
3. **The drop**: the first big hips/torso hit after death also plays a
   heavy body-fall sound (deep thump + clothing and gear rattle). Valve's
   merge already makes landing loud; this makes it *heavy*. One per death.
4. **Per-bone variety**: bones don't all sound alike. Arms and legs play
   lighter flesh slaps, the torso the full thud, and the head its own skull
   knock (Valve's `$jointsurfaceprop` per-bone idea, pushed further).
5. **Ground layer**: every body impact also plays the *surface it hit*,
   quieter, scaled by how hard the hit was. A body on a metal grate gets a
   clang under the thud, on wood a hollow knock, on dirt a dull puff. In
   Source only the body's own flesh sound plays; this gives the floor a
   voice too. It reuses the surface impact sounds, so no extra files.
6. **Drag loop**: a corpse skidding along the floor (stomp or shotgun launch)
   plays a looping flesh-and-cloth scrape, rough or smooth depending on the
   floor, following its speed and stopping 0.1 s after it stops.
7. **Bone crunch**: an extra crack only on the very hardest impacts, above a
   speed threshold, so it stays rare and hits hard.
8. **Voice budget**: on top of the merge, a global voice cap so a pile of
   bodies can never machine-gun.

**E. Props**: same pipeline, prop material + break sound. Later, Alyx-style
"contents" rattles.

**F. The PS1 filter** (three layers, cheapest and most authentic first):
1. **At import, free at runtime.** The PS1 stored samples as 4-bit ADPCM,
   usually at reduced sample rates. Godot's WAV import can do both per file:
   *Force > Max Rate* (e.g. 22050 Hz, or 11025 for grittier sounds) and
   *Compress > Mode: IMA ADPCM*, the closest thing to the PS1's codec. You
   master in full quality; the PS1 crunch happens on import and stays
   reversible.
2. **Bus chain**: an SFX bus with a low-pass (~9–11 kHz) and a subtle
   Distortion in LoFi mode (bit reduction) for the shared console character.
   The PS1's reverb ran at half the output rate (22.05 kHz), so it has a dark
   tail; low-passing the reverb return gets that.
3. **Rooms**: Godot `Area3D` reverb buses per area (small room, hall,
   outdoors). That's Valve's DSP-per-area idea.

Also authentic: the PS1 had 24 hardware voices. A global cap around 24–32
voices is both period-correct and a good mixing tool.

**Producer tip:** there are free PlayStation 1 SPU plugins (an ADPCM sampler
and the SPU reverb) you can use in your DAW to print the PS1 character into
the source files themselves: <https://github.com/BodbDearg/PlayStation1Vsts>

---

## 4. Sounds needed from you

### Delivery format
- **WAV, 44.1 or 48 kHz, 24-bit.** Master at full quality; the PS1 downgrade
  happens at import.
- **Mono for anything that exists in the world** (bodies, props, enemies,
  impacts, footsteps). 3D positioning needs mono. **Stereo only** for UI,
  music, and the player's own first-person sounds.
- **No silence at the start** (it reads as lag), short fade at the end,
  peaks around -1 dBFS. Relative loudness gets balanced in-engine.
- **Loops**: seamless, cut on zero crossings.
- **Naming**: `name_01.wav`, `name_02.wav`... inside the matching folder.

**The folders already exist** in `audio/sfx/`, and each one has a
`README.txt` listing exactly which files go in it. Just drag your WAVs in
with the listed names:

```
audio/sfx/
  body/                      ragdoll and corpse sounds
  surface/concrete|metal|wood|dirt/
  gore/
  props/
  weapons/pistol|machine_gun|shotgun|casings/
  enemy/base|rusher|gunner/
  player/
  hits/
  ambience/
```

References: the HL2/GMod sounds named below are the exact files Source uses.
You can hear them in GMod, or browse them on The Sounds Resource:
<https://sounds.spriters-resource.com/pc_computer/halflife2/asset/401974/>

### Priority 1 — ragdolls
The first five are Valve's base flesh set; the rest are our extra layers
(section 3D). The ground layer needs no files of its own: it reuses the
surface impacts in Priority 2.

| File | Variations | What it should sound like | Reference |
|---|---|---|---|
| `body/impact_soft` | 6–8 | light contact: a limb flopping onto something soft, short dull flesh slap | HL2 `body_medium_impact_soft1-7` |
| `body/impact_hard` | 6–8 | a body hitting something hard: heavy thud, low end, a bit of crack | HL2 `body_medium_impact_hard1-6` |
| `body/limb_slap` | 6 | lighter, quicker slaps for arms and legs hitting things | — |
| `body/scrape_rough_loop` | 1–2 loops, 2–4 s | a body sliding on a rough floor (concrete, dirt): grinding flesh and cloth | HL2 `body_medium_scrape_rough_loop1` |
| `body/scrape_smooth_loop` | 1 loop, 2–4 s | sliding on a smooth floor (tile, metal): a softer, slicker drag | HL2 `body_medium_scrape_smooth_loop1` |
| `body/drop_heavy` | 4–6 | the full-body collapse: deep thump with clothing and gear rattling | GTA V / RDR2 body falls are a good listening reference |
| `body/head_knock` | 4–6 | skull hitting the floor: harder, shorter, a bit higher than the body | — |
| `body/bone_crunch` | 4 | a crack for only the hardest impacts; rare, so make it count | — |

### Priority 2 — surfaces (start with concrete, metal, wood, dirt)
Per material, the same set Valve's surface properties use. These are what a
prop **made of** that material sounds like, plus bullets and footsteps on it:
| File | Variations | What it should sound like |
|---|---|---|
| `surface/<mat>/impact_soft` | 4 | an object of this material landing lightly |
| `surface/<mat>/impact_hard` | 4 | an object of this material slamming into something |
| `surface/<mat>/scrape_rough_loop` | 1 | it being dragged across a rough surface |
| `surface/<mat>/scrape_smooth_loop` | 1 | it being dragged across a smooth surface |
| `surface/<mat>/bullet` | 4 | a bullet hitting it |
| `surface/<mat>/step` | 6–8 | footsteps on it |

### Priority 3 — gore and mutation
| File | Variations | What it should sound like |
|---|---|---|
| `gore/twitch` | 6 | wet twitches/squelches during the mutation twitch |
| `gore/burst_big` | 3 | the mutation explosion: big wet burst |
| `gore/splat_small` | 6 | blood/gib splats landing |
| `gore/spurt_loop` | 1 | artery/headshot spray hiss, loopable |

### Priority 4 — props, enemies, player, weapons, ambience
- **Props**: impact soft/hard + scrape per prop material; `break` for anything breakable.
- **Weapons**: shell casings bouncing (concrete, metal, wood, 6 each). Classic and very physical.
- **Enemies** (per type: base, rusher, gunner): death vocal 4–6, pain 6, idle loop, attack 4.
- **Player**: jump, land soft/hard (by fall speed), dash, wall jump, mantle, stomp-kill impact.
- **Hits**: hit tick, headshot ding, kill confirm.
- **Ambience**: one loop bed per area type plus random one-shots.

The existing stub `SoundEvent`s in `audio/events/` already cover the enemy,
player and weapon slots; the body, surface and gore ones get added when the
system is built.

---

## Build order
1. **Built.** SFX bus + PS1 chain + import presets, so every sound you
   deliver already runs through the PS1 character.
2. **Built for ragdolls** (`surface_audio.gd`, `physics_audio.gd`).
   `SurfaceAudio` + the physics impact pipeline; props join it later.
3. **Built** (`ragdoll_audio.gd`). Ragdoll layers: the drop, per-bone
   variety, the ground layer, the drag loop and bone crunches.
4. Footsteps by surface.
5. Area reverb zones + ambience beds.

## Sources
- Valve SDK, `vphysics_sound.h` (impact queue, merging, hard/soft choice): <https://swarm.workshop.perforce.com/files/guest/knut_wikstrom/ValveSDKCodegame_shared/vphysics_sound.h>
- Valve SDK, `physics.cpp` (speed² volume, 70 u/s and 0.05 s gates, friction fade): <https://swarm.workshop.perforce.com/files/guest/knut_wikstrom/ValveSDKCodedlls/physics.cpp>
- Valve SDK, `physics_shared.cpp` (scrape energy² volume, rough vs smooth): <https://swarm.workshop.perforce.com/files/guest/knut_wikstrom/ValveSDKCode/game_shared/physics_shared.cpp>
- Surface property fields (GMod wiki): <https://wiki.facepunch.com/gmod/Structures/SurfacePropertyData>
- `$jointsurfaceprop` (VDC): <https://developer.valvesoftware.com/wiki/$jointsurfaceprop>
- Soundscripts (VDC): <https://developer.valvesoftware.com/wiki/Soundscript>
- Soundscapes tutorial (TWHL): <https://twhl.info/wiki/page/Tutorial:_Soundscapes>
- Portal 2 sound operator stacks: <https://thinking.withportals.com/forum/topic/guide-introduction-to-the-portal2-sound-operator-stacks-t10514/>
- Half-Life: Alyx sound design interview: <https://www.asoundeffect.com/half-life-alyx-vr-sound/>
- PS1 SPU specs (psx-spx): <https://psx-spx.consoledev.net/soundprocessingunitspu/>
- Godot WAV import options: <https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html>
- Godot `Area3D` reverb buses: <https://docs.godotengine.org/en/stable/classes/class_area3d.html>
