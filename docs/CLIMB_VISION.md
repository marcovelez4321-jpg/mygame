# The climb: the game's direction (decided 2026-10-11; new direction 2026-10-14)

## The new direction (the user's, 2026-10-14)
This comes first; where an older section below disagrees, this wins (those
are marked).

- **A 1v1v1v1 race to the top of the Stacks.** Four players, one world, first
  to the top wins. The world, its creatures and its hordes are the obstacles
  as much as each other. (Player-vs-player rules, the lobby, and what's
  shared -- camps, drops, enemies -- to be chosen when it's built.)
- **The world: procedural Stacks instead of the Terrain3D open world.**
  Hand-built stack areas (prefabs: stairwells, shafts, halls, vent runs,
  outside ledges, skybridges, a vending-machine room, camp spots), made in
  TrenchBroom (func_godot) with openings on a fixed grid, snapped together
  upward by a **seeded generator** that always leaves a way to the top (with
  branches and dead ends); StackBuilder-style procedural carving fills the
  big halls between them so it never repeats. One seed from the host = the
  same world for every player (almost nothing to sync). Difficulty rises
  with height; checkpoints every few sections. Built in chunks, so far ones
  can be culled/streamed (a big performance win over Terrain3D).
  **Proved first with a greybox prototype** (placeholder boxes) before
  Terrain3D is retired. Lost with Terrain3D: the sewer and reef biomes and
  the ground encounter director; the worm moves to burrowing through floors
  and walls (see "The boss worm"). Why it's ours (not just White Knuckle's
  rooms-from-prefabs climb): the four-player race, the momentum movement and
  grapple, living hordes, money, camps and mutations together.
- **Movement, Vholume-style (built 2026-10-14):** momentum kept through
  everything; bhops (no friction, +10%) and wall jumps (any wall, buffered,
  speed kept +15%) build it up to a 28 m/s cap; the camera tilts into
  strafes and turns, sways, and the view widens with speed. (No speed lines
  or wind rush.)
- **The grapple reworked again (next):** the spot you grapple lets off
  **three tendrils** that attach to three different surfaces; an **M2 /
  right-mouse marker** floats over each spot they attached to; right click
  re-attaches you to that spot for more momentum and speed. (Details asked
  when it's built.)
- **Drops:** enemies drop **money**, plus **meat** (the user's gib model) with
  **scrap** (tweakers) or **silk** (spiders); **roaches drop wings**. Scrap and
  silk also lie around, somewhat rare.
- **Money and a vending machine:** spend money on **drinks** (what they do: to
  choose).
- **Hunger: one meter** for food and water together. **Food and water items**
  (the user's new food models to come).
- **Camps are checkpoints, not saves:** the camp building system (placement
  preview, tent, bedroll) sets where you come back; nothing is saved.
- **Flares:** thrown like grenades, with light. The **zippo** stays as an
  item. No other light sources or tools for now.
- **The order:** 1. movement (done) -> 2. the grapple -> 3. the greybox
  procedural-Stack prototype -> 4. the performance pass (measured, after the
  world change) -> 5. drops and money -> 6. hunger, food, the vending
  machine -> 7. camps as checkpoints -> 8. throwable flares -> 9. the
  1v1v1v1 race.

---

The game is becoming a hardcore climbing open world: the Stack and the
megastructures are climbed higher and higher (White Knuckle's pull upward --
not its pitons or movement), with survival, camps and mutations. Every item
here was the user's call (RULES.md Rules 10-11): for this list, anything
offered and not turned down was in (that applied to this list only). Details
still to be chosen are asked before each is built.

## Rules this rests on
- **Rule 11, hardcore:** extremely challenging and unforgiving. Death sends
  you back to the last camp you set up (for now). Dangers are brutal but
  always readable.

## Stamina (replaces any grip stamina)
- One shared stamina: the bars under the crosshair. **4 bars** (was 2).
- Dashes and grapples both spend it.
- While the grapple is out and holding you (attached, perched, reeling,
  rappelling), the bars slowly drain.

## The grapple, reworked ("set it, then launch" -- HL2-style, not a swing)
*(Since: the launch went back to the original Titanfall-style pull, 2026-10-11;
and a three-tendril rework is next -- see the new direction.)*
- Hold right mouse: the same landing ring shows where it goes; it charges.
- It only fires if held at least **half** the charge (no spamming).
- It costs **1 stamina bar**, as does a dash.
- **Charge timing:** release right as it fills = a tiny extra boost and a
  sound.
- It launches you **automatically** the moment the anchor bites, straight at
  the point like Spider-Man's zip; momentum carries on.
- **Launch timing:** a second, separate timed press while flying = another
  sound and another tiny speed boost.
- **One grapple at a time:** cancel the first before firing another.
- **Perch** (stick to the wall at the point for a few seconds), **reel**
  (in) and **rappel** (out, down).
- Anchors on creatures: big ones you launch at (kick / ride), small ones
  you yank, flying roaches can carry you up.
- **Flares:** the grapple can carry one, left burning stuck at its anchor
  (lights where you're heading: dark shafts, the hive); and flares can be
  thrown by hand, sticking where they land.
- While it holds you (attached, perched, reeling, rappelling) the bars drain
  **1 every 4 s**; **perching lasts until stamina runs out**.

## Mutations (the arm taken over)
- Swappable at camps; earned by eating creatures (you are what you eat);
  2-3 slots; each has a drawback.
- **Theme:** every mutation is something taking over the player's arm,
  slowly winding up it as it charges -- the same take-over animation as the
  grapple's symbiote (e.g. the boss worm's flesh wraps the arm for its spit).
- In: **Spider Silk** (permanent climbable lines), **Membrane Glider**,
  **Chitin Claws**, **Leech Arm**, **Bloat Sac**, **Harvestman Stride**,
  **Hive Sense**, **a flamethrower-type mutation**, **Worm Bile** (the boss
  worm's blood/acid spit).
- Out: Barnacle Tongue.

## Climbing as the progression
- **The ascent 50% longer:** the towers ×1.25 taller, plus extra detours
  (fewer direct ways up, gaps to go round).
- Altimeter on the HUD, height records, milestones.
- Surfaces matter (rotten growth tears loose, slime and barnacle crust are
  slippery, pipes and cables are routes).
- **Altitude danger:** wind gusts that push harder the higher you are, only
  outside the buildings (inside: none). Storms. (Warmth: later.)
- **Fall damage** (and injuries from bad falls).
- **Collapsing routes:** floors and bridges that fall away behind you.
- Shortcuts back down unlocked from above (lift stops, cables, ropes).
- Out for now: ledge shimmy / hangs; a threat rising from below.

## The boss worm hunts you up the Stack
- It crashes up through the Stack's floors and burrows through the
  megastructures' walls, chasing you as you climb -- immersive and scary.
  Mechanics to be chosen from the 13 offered (tells, floor cracks,
  bursting up through floors, moving in the walls, hunting by sound, bait,
  chase phases, the shaft chase, cutting you off from outside, destroying
  the way back, safe floors, its body as terrain, glimpses).

## Secrets
- **Secret rooms:** a key (the existing key asset) opens a locked door to a
  room somewhere within a set range of the key, so it can be found.
- **Secret buttons and levers** opening hidden passages and shortcuts
  between the towers.

## Camps (the only save)
*(Now: checkpoints, not saves -- see the new direction.)*
- Built with a placement preview like The Forest: a ghost of the camp where
  it'll go, confirm, and it's built. The user brings PSX camping models.
- A camp: fire (cooking), bedroll (save/respawn, sleep), storage, smoking
  rack, mutation incubator, radio.
- Camps left too long get reclaimed by nests; abandoned climbers' camps hold
  supplies and their story; resting passes time, heals, recovers.
- Out: camps linked by ziplines/fast travel.
- **Split in two (the user's, 2026-10-11; for the camps step):** the
  **tent saves the game** (it's where you respawn) and the **bedroll lets
  you sleep** (till dawn, healing). Each is crafted on its own, with
  different amounts of scrap and silk (amounts to ask at that step). The
  bedroll is the survival pack's sleeping bag (`art/survival`:
  `sleeping_bag` laid out). The tent is to be "the new pack's" -- but the
  survival pack has no tent (only the forest props' Large / Simple Large
  Tents): ask which at that step. In the backpack, both the tent and the
  bedroll show as the survival pack's rolled sleeping bag
  (`sleeping_bag_01`) for now.
## Day and night
- A day/night cycle. At night creatures climb the outside walls.

## Survival
- **Hunger** (now one meter for food and water -- see the new direction): slow drain, faster climbing hard; starving costs stamina,
  then health.
- **Collect what you kill** (roaches, spiders, rats, Harvestmen, the worm)
  and **cook** it at a fire: raw risks sickness; each creature cooks into
  something different (buffs).
- **Simple butchering:** chitin, silk glands, venom sacs, spore pods.
- Spoilage (smoking/drying preserves), water (rain, boiled sewer water),
  carried weight (slows stamina recovery), infection from bites.

## The world as a climb
*(The world itself becomes procedural Stacks -- see the new direction.)*
- Layered heights (sewer base -> halls -> cloud line -> the hive -> the
  crown), a summit goal, height relics, climbable hazards (vine pillars),
  falling debris, riding creatures upward, night climbs.
- Out for now: rival climbers.

## Co-op
*(To revisit: the game is becoming a 1v1v1v1 race -- see the new direction.)*
- A craftable tether between partners (a belay that catches a fall).
- Split roles, shared camps (respawn at your partner's camp).
- Out: boosting a partner; rescuing a downed partner.

## Gear
- Spike pods (plant your own permanent grapple anchors).
- Out: chalk, crampon claws.
