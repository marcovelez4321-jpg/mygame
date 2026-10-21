# Project Rules

These apply to every change, in every script, scene, or system, for the rest of
the project. I re-check all four before and after touching anything. The user
adds more over time — new ones get appended below, never silently dropped.

## Rule 1 — Multiplayer-ready from day one
Nothing gets added in a way that only works in single-player and has to be
torn up later. In practice:
- **Input and simulation are separate.** A function that moves the player
  never reads `Input`/keyboard state directly — input is gathered once,
  stored in a small struct/dictionary, and simulation functions take that as
  a parameter. This is what makes client prediction and server reconciliation
  possible later.
- **Every script that affects gameplay state assumes it may run on a
  server authority with multiple peers.** Node paths, singletons, and
  `@onready` references are written so they still make sense once there are
  N player instances instead of 1.
- **No global mutable state that only makes sense for one local player**
  (e.g. a single global "the player" reference) unless it's explicitly
  documented as client-local presentation stuff (camera, HUD) that will
  never need to sync.
- New systems get a one-line note on how they'll eventually map onto
  server-authoritative multiplayer (even if we're not wiring up
  `MultiplayerSynchronizer`/RPCs yet).

## Rule 2 — Simple, readable, optimized code
- No spaghetti. If a function is doing three unrelated things, split it.
- Prefer clear, boring code over clever code. You should be able to read a
  function top to bottom and understand what it does without me explaining
  it.
- Comment *why*, not *what*, when the reason isn't obvious from the code
  itself.
- Avoid needless per-frame allocations, redundant lookups, or repeated
  `get_node()` calls in hot paths (`_process`/`_physics_process`) — cache
  with `@onready` or exported node paths.
- **"Clever" here means complexity that isn't earning its keep** — golfing
  code into one dense line, premature micro-optimizations, or abstractions
  built before there are 2+ real cases that need them. It does NOT mean
  "avoid optimization." A technique that's genuinely faster/more robust and
  can be explained in a sentence (object pooling for projectiles, spatial
  partitioning for hit checks, delta-compressed network state, a
  fixed-tick simulation step) gets used, gets flagged when introduced, and
  gets a short comment saying why it's there — that's complexity that pays
  rent, not spaghetti.

## Rule 3 — Competitive balance
- This is a competitive 2v2 shooter, not a sandbox. Every weapon, movement
  tweak, and ability gets thought about in terms of: is it fair, is it
  readable/counterable by an opponent, does it create a dominant strategy
  that isn't fun to play against.
- Numbers (damage, speed, cooldowns, etc.) live as `@export` values up top
  of their script so they're easy to find and tune without digging through
  logic.

## Rule 4 — You're in the loop
- Before any major change (new system, refactor of existing code, a change
  that touches multiple files, anything architectural), I explain what I'm
  about to do and why, in plain terms, before doing it.
- Small, obviously-correct tweaks (a typo fix, a number tweak you asked for
  directly) don't need a pre-brief — but I still say what changed.
- The goal is for you to follow along and learn how a multiplayer game gets
  built, not just receive finished files.

## Rule 5 — Teach, don't just deliver
- Treat this like a class you're taking, not a repo you're paying someone
  to maintain. Every non-trivial change comes with the *why*: what problem
  it solves, what the alternative approaches were, and why this one was
  picked over them.
- When a new concept shows up for the first time (an engine feature, a
  networking idea, a design pattern), explain it like it's new to you —
  don't assume prior knowledge, but don't over-explain things you've
  already been taught either.
- If there's a genuinely instructive tradeoff (performance vs. readability,
  simplicity vs. flexibility, this bug being a good example of a general
  class of bug), point it out even if you didn't ask — that's the whole
  point of rule 5.
- It's fine for explanations to run long when the concept is meaty. Depth
  over brevity here, unlike rule 4's "small tweaks don't need a pre-brief."

## Rule 6 — Ground design decisions in real references
- For level design, visual clarity, movement feel, and competitive design
  questions, pull from documented sources instead of guessing from scratch:
  GDC talks/post-mortems, published level-design writing, and well-known
  conventions from both old-school arena shooters (Quake, Unreal
  Tournament) and modern competitive shooters (CS:GO/CS2, Valorant,
  Overwatch, Quake Champions).
- When I bring in an idea this way, I say which game/talk/concept it's
  from and why it applies here — not just "trust me," an actual citation
  you could go look up yourself.
- This doesn't mean copying a specific map or ability wholesale — it means
  reusing *principles* that are already proven to work (readability, guide
  colors, why dev-textures exist, etc.) instead of reinventing them badly.

## Rule 7 — Sound design is a core pillar, not polish
- Audio gets the same weight as code and feel. Anything that moves, hits,
  breaks, dies or falls makes sound, and that sound reacts to *how* it
  happened (speed, force, material) instead of one clip on repeat.
- Immersion first, PS1 second: every sound should feel physical and
  present, then get pushed through a shared PS1-style character (lower
  sample rate, ADPCM-style grit, SPU-style reverb) so the whole game sounds
  like one console.
- Physics audio (ragdolls, props, debris) follows the Source/GMod model:
  material-driven impact and scrape sounds scaled by impact energy, with
  variation and voice limiting so a pile of bodies never machine-guns the
  same clip. Ragdolls get extra layers on top of that (body drop, ground
  layer, bone crunch). See AUDIO_DESIGN.md for the full system.
- New sounds are data (SoundEvents), never hard-coded clips -- the owner is
  a music producer and should be able to swap and tune any sound without
  touching code.

## Rule 8 — Backtracking is the structure (Metroidvania-style)
- Levels aren't one-and-done. Later missions hand you things — weapons,
  movement abilities, keys, items bought with brownie points — that open
  paths, secrets and shortcuts in EARLIER levels, so going back is rewarded.
- Every new level, ability or item gets checked: what does it unlock that
  already exists, and what in this level stays locked until something
  later? A level should ship with at least one visible thing you can't
  reach yet.
- Reference (Rule 6): Super Metroid and Castlevania: Symphony of the Night
  (ability gating — the "lock" is a gap you can't jump or a wall you can't
  break yet), and Hollow Knight (shortcuts that loop back to earlier areas).
- Map-side, this means locks are DATA a mapper places in TrenchBroom (a key
  door, a breakable wall, a ledge that needs the rocket jump), never
  hard-coded per level — same as the door/key system.
- Progress (what you own, what's unlocked, secrets found) must persist
  between missions and is per-player data that co-op will need to sync or
  share (Rule 1).

## Rule 9 — Spectacle, always
- The game is a spectacle. Structures, growths and creatures are built to
  make your jaw drop: unearthly, megalophobic scale that reaches past the
  fog and past what you can see.
- Size pushes the limits as far as the tech allows, every time. When
  something big is made, ask "can it be bigger?" and find the technique
  that makes the answer yes (the skyline layer, far shells, occluders,
  silhouettes) rather than settling for smaller.
- Scale has to READ: human-sized details (windows, stairs, lights) that
  shrink to texture, things moving on it, fog that drowns the base while
  the top looms, reveals over ridges, sound you feel.
- Spectacle is never an excuse for a bad frame rate: it's done the cheap
  way (HL2's 3D skybox, LOD shells, occlusion, no physics where nothing's
  reachable). Spectacle AND optimized.
- The user decides the details of each spectacle piece: offer ideas,
  let them choose.
- Reference (Rule 6): HL2's Citadel, Shadow of the Colossus, Blame!, Dark
  Souls' Anor Londo, Destiny's skyboxes.

## Rule 10 — The user chooses every creative detail
- Whenever something creative is being decided -- how a thing looks,
  sounds, behaves or is laid out; what's in a place; its size, shape,
  colour, mood, story; a creature, a weapon, a growth, a room, a sound --
  the user chooses every detail. Claude offers the options (with the
  trade-offs, and a recommendation where it has one) and waits for the
  choice; it never fills in a creative detail on its own.
- Ask in rounds until nothing creative is left open, rather than deciding
  the rest. Technical choices with no creative side (how a thing is coded,
  optimized or batched) stay Claude's, following Rule 6 (the HL2 way).
- This widens Rule 9's "the user decides the details of each spectacle
  piece" to everything creative.

## Rule 11 — Hardcore: a serious, unforgiving challenge
- The game is hardcore: extremely challenging and unforgiving. Climbing is
  dangerous, mistakes are costly, resources are scarce. Systems are tuned
  toward punishing rather than forgiving -- no hand-holding, no free saves.
- Death sends you back to the last camp you set up (for now -- this will
  change later). Nothing else saves your progress through a climb.
- When a choice is between "easier" and "harder but fair", pick harder but
  fair: a danger is always readable (telegraphed, heard, seen) before it
  kills you, even when it's brutal.

---

## Creative Direction — what the game IS

Working title: **Grandma's Boy**. New enemies, weapons, levels, sounds and UI
get checked against this the same way code gets checked against the rules
above.

- **Setting.** You live at Grandma's suburban house, the one piece of the old
  world that didn't change. Everything past her yard did: an **alien land** of
  purple and blue, wavy and wrong, grown over with coral-reef growths, where
  the old world's **megastructures** (towers, overpasses, malls, hulks nobody
  can name) stand half-swallowed. It's one open world you walk out into from
  her yard (no portals). Grandma gives you quests, and so do the people still
  living out there. It should feel like somewhere that used to be normal,
  gone very wrong, not a clean sci-fi planet. (The world plan: docs/WORLD.md.)
- **Enemies.** Two kinds. The changed world's creatures (Harvestman, worms,
  Deepmaw, leeches, roaches, spiders): grotesque, biological, sewer-gross.
  And the people still out there: scavenger crews, tweakers, cultists and
  squatters living in the megastructures, in factions that fight each other
  and you (S.T.A.L.K.E.R.-style). Both are exaggerated caricatures played for
  dark comedy: twitchy, unpredictable, desperate, occasionally pathetic,
  dangerous in a crowd.
- **The player.** Inspired by the Postal Dude: deadpan, unbothered, a little
  unhinged — the straight man in a city that's lost its mind, and just as much
  a target of the joke as everyone else.
- **Tone.** Doesn't take itself seriously, but takes its craft seriously.
  GTA / Postal-style satire: gory and shocking in a fun way, never grim. The
  violence is the punchline — artery sprays, ragdolls and stomp kills should
  land as slapstick.
- **Look.** Grimy and dirty, through an old-school PS1 lens: low-poly models,
  low-res textures, dithering (PS1Dither autoload), low internal render scale.
  The alien land is purple and blue in gradients (indigo valleys, violet and
  periwinkle ridges, teal moss, magenta rust) under purple fog, glowing at
  night. Grime comes from texture and color (stains, trash, graffiti,
  sodium-orange lamps on dead megastructures, sickly greens, nicotine
  yellows), not from modern effects —
  no realistic PBR wear, no film grain stacks, nothing that breaks the PS1
  illusion.
- **Feel.** Old-school boomer-shooter movement: fast, VQ3 strafe-jumping, dash,
  wall jump, mantle.

---

## Notes log
A running list of decisions made against these rules, so we don't relitigate
them:

- 2026-09-27: Initial player movement (`player_movement.gd`) was written
  single-player-only — it reads `Input` directly inside `_physics_process`,
  which breaks Rule 1. Flagged for refactor (see chat).
- 2026-09-27: Refactored `player_movement.gd` to split input from
  simulation: `_gather_input()` is now the only function that touches
  `Input`/mouse, returning a `PlayerInput` struct that `_simulate_movement()`
  consumes. Mouse-look is buffered in `_unhandled_input` and applied inside
  the physics tick instead of instantly, so all state changes happen in one
  deterministic place. No behavior change — same feel, same presets.
- 2026-09-27: Added a resolution/window-mode/vsync settings system
  (`game_settings.gd`, autoloaded as `GameSettings`) and a pause menu
  (`pause_menu.gd`/`pause_menu.tscn`, autoloaded, Escape to open/close) that
  exposes it. Settings persist to `user://settings.cfg`. Switched
  `window/stretch/mode` from `canvas_items` to `disabled` so the game
  renders at the real chosen resolution instead of an upscaled framebuffer
  (crisper image, correct 1:1 mouse aim — this is what AAA shooters do).
  Set `Camera3D.keep_aspect = KEEP_HEIGHT` explicitly on the player camera
  (Rule 3: this is a competitive-fairness call, not just a default —
  vertical FOV/visibility stays identical across every aspect ratio, only
  horizontal FOV changes, so no monitor shape gives an advantage). Moved
  Escape/mouse-capture ownership from `player_movement.gd` entirely into
  `PauseMenu`, since two systems fighting over the same mouse-mode state
  was the same "one owner per piece of state" problem the earlier
  input/simulation refactor solved.
- 2026-09-27: Added a Sensitivity slider and moved the VQ3 Air Accel slider
  from the always-on HUD into the pause menu (one owner for tunable
  settings instead of the same control existing in two scenes). **Rule 3
  flag:** air acceleration is a real competitive movement stat, and right
  now it's a free-form per-client slider. That's fine while solo-tuning
  movement feel offline, but it must NOT ship as a player-facing option
  once multiplayer exists — if every client could set their own physics
  constants, whoever cranks their air accel highest wins, which is a
  fairness-breaking exploit, not a preference. Labeled in the pause menu
  itself as "testing only" as a visible reminder. Before real multiplayer
  testing: either lock movement constants to server-authoritative values,
  or gate this slider behind a dev-only build flag.
- 2026-09-27: Added Rule 6. Fixed the test map's "everything looks blue,
  can't judge speed/depth" problem using two documented principles (Rule 6
  in action): (1) **dev/checker textures** — the industry-standard grey-box
  technique of tiling a small checkerboard across flat surfaces so your eye
  has something to track as you move past it (optical flow is how humans
  actually perceive speed; a flat color gives it nothing to measure
  against). Built as a small reusable generator (`dev_checker.gd`) rather
  than a hand-made image file, since it derives correct tiling from each
  surface's real size automatically. (2) **Guide colors** (GDC level-design
  principle, David Shaver and others — games like Uncharted/TLOU reserve
  one color, e.g. yellow, exclusively for "climbable/important," so it pops
  out from everything else): the ground checker is deliberately neutral
  grey so the platform's warm orange checker is the one thing that visually
  demands attention. Also added alternating red/white landmark pillars
  along the runway (a classic technique for judging speed/distance by how
  fast fixed objects pass you) and subtle depth fog (aerial perspective —
  distant things read as hazier, giving another depth cue). Shifted the
  wall color off blue toward neutral warm-grey so the environment isn't
  monochrome. CS:GO's de_cache readability rework (going from
  high-contrast/shadowy to bright/evenly-lit) was the reference point for
  why visual clarity gets treated as a first-class competitive concern, not
  just an aesthetic one.
- 2026-09-27: **Committed to networking-first development** (grounded in
  Tim Ford's "Overwatch Gameplay Architecture and Netcode," GDC 2017 —
  prediction/reconciliation designed in from the start, not bolted on).
  Agreed sequencing: get basic client/server replication (listen-server,
  one player hosts) working with the simplest possible movement *before*
  adding any more gameplay systems on top, then layer client-side
  prediction + server reconciliation onto the existing `PlayerInput` /
  `_simulate_movement` split specifically built for this. Godot's built-in
  `MultiplayerSynchronizer`/RPCs only give plain replication, not
  prediction — the harder half still has to be hand-built on our own tick
  structure.
- 2026-09-27: Locked movement to **VQ3 only** (air_accel = 10, final
  competitive constant, no longer a slider). Removed the `Preset` enum,
  CPMA/Hybrid code paths, the 1/2/3 switching, and the pause-menu air-accel
  slider entirely — fewer branches means less surface area the networking
  layer has to reproduce exactly on the server. This also fully resolves
  the earlier Rule 3 flag about air accel being a live per-client dial: it
  is now a plain `@export` constant, set once, by design, not by whoever's
  playing.
- 2026-09-27: **Deferred** the Deadlock-style stamina-gated wall-jump /
  slide / dash / kill-speed-boost movement system (see chat) until *after*
  basic multiplayer replication is proven with the simple VQ3-only
  movement. Reasoning: every new movement input is more surface area the
  prediction/reconciliation system has to get right, and validating that
  system works at all is much cheaper with the smallest possible movement
  set. Not abandoned — revisit once Level 0 (replication) and Level 1
  (prediction) both work for plain VQ3 movement.
- 2026-09-28: Added **auto step-up** to `player_movement.gd`
  (`_try_step_up`, `step_height = 0.5 m` / 16 map units). Sources (Rule 6):
  Quake 1/2/3 step up 18 units in engine code (`PM_StepSlideMove` in
  `bg_slidemove.c`), Doom allows 24-unit floor differences, and Source
  mappers use clip ramps over stairs. Chose the engine-side approach over
  hand-placed ramps so every staircase works automatically. It runs inside
  `_simulate_movement` so a server would compute the same result (Rule 1),
  reuses its physics-query objects instead of allocating per tick (Rule 2),
  and only lifts the player vertically so horizontal speed is preserved
  (Rule 3). **Untested at time of writing**: no Godot executable was
  available to run it, and it depends on `body_test_motion` working under
  Jolt. Known follow-ups: camera "pop" when stepping (presentation-only
  smoothing), and whether descending stairs should keep the player grounded
  (`floor_snap_length`) — left off on purpose since being grounded means
  friction, which costs speed.
- Mapping convention: keep stair risers at 16 units (0.5 m) or lower.
- 2026-09-28: **Direction change (user decision): campaign first, 2v2 PvP
  later.** Working title "Grandma's Boy" (or a variation): start in a
  suburban house you can't leave, then take a portal to a demon
  realm/dungeon and fight monsters, Doom/Quake style. This supersedes the
  earlier "networking first" ordering: building Level 0/1 netcode is now
  postponed until after the campaign is playable. **Rule 1 still applies
  in full** — we keep the multiplayer-ready structure (input separated from
  simulation, no single-player-only globals) so PvP isn't a rewrite, we
  just aren't building the network layer yet. Risk accepted knowingly:
  combat/enemy systems written now must not assume a single local player.
  Planned NPC art: "Characters PSX" by elbolilloduro (CC0, FBX/blend,
  rigged; reported scale/orientation quirks on import).
- 2026-09-28: Multiplayer plan refined: **2-player co-op first**, then 2v2
  PvP later. Host-authoritative model. User wants lag compensation for
  hit detection designed in early because laggy/unresponsive shooting is
  unacceptable even in co-op. Hub/campaign design decided: grandma NPC
  opens a mission-select menu, plays an animation, places a portal; a
  return portal opens when a mission is complete; the hub changes over
  time (doors unlock via a list of unlocked flags). Weapons: grandma gives
  the first gun (hitscan), all others are found in levels and **kept
  permanently**; **shared ammo pools by type** (bullets/shells/rockets).
  Planned build order: health/damage interface, weapon data resources,
  fire as part of the input packet, pickups, a projectile weapon, then
  viewmodel/sound. **Step 1 done:** `health.gd` (reusable Health
  component, attacker as an int id for networking), `weapon_data.gd`
  (per-weapon resource, `weapons/starter_gun.tres`), and a `test_target`
  scene with three targets in the test map. **Step 2 done:** firing.
  `weapon_controller.gd` (cooldown, ammo, hitscan; `tick()` builds a Shot
  and `resolve_shot()` casts the ray, split so the host can own resolution
  in co-op and lag compensation can rewind to `shot.tick`), `fire` added to
  `PlayerInput`, `shot_tracer.gd` (debug ray lines), HUD ammo count and hit
  marker. Health and shooting confirmed working by the user in-game.
  **Enemy + player feedback:** first melee enemy (`enemy.gd`, state
  machine IDLE/CHASE/ATTACK/PAIN/DEAD, host-only AI, nearest-living-player
  targeting; built by the user by hand from pasted code). Player now has a
  HUD health number, a red damage-flash overlay, and death handling (freeze,
  "YOU DIED", level restart after `respawn_delay`; restart is offline-only
  and becomes a respawn in co-op). Found while testing: the player's
  `Health.max_health` was set to 1 in the scene, so the first enemy hit
  killed them and the enemy (correctly) went idle with no living target.
  **Enemy animation:** `enemy.gd` now emits `state_changed` (via a setter on
  `_state`), and `enemy_animator.gd` plays the matching clip (idle, walk,
  attack, hurt, die; death holds its last pose). Presentation only; in co-op
  each player's copy runs from the host's shared state, so no animation data
  is sent. The character's skeleton uses Mixamo bone names, so Mixamo clips
  should retarget cleanly via Godot's BoneMap/SkeletonProfileHumanoid.
  **Attack wind-up:** enemy swings now have a wind-up (`attack_windup`);
  `attack_started` is emitted per swing and the animator plays the clip
  then; damage lands after the wind-up. Leaving range mid-swing = miss;
  being shot interrupts the swing. The animator also gained per-state clip
  lists with a random pick per enemy (seeded from its node path so co-op
  players choose the same variant), a `hurt_speed`, and a shared
  `AnimationLibrary` attached at spawn so new models need no animation
  setup. **Ragdoll death:** `enemy_ragdoll.gd` starts the model's
  `PhysicalBoneSimulator3D` (built in-editor via "Create physical
  skeleton") when the enemy dies, with a push away from its facing.
  Cosmetic and local in co-op (nothing synced). Ragdoll bones sit on physics
  layer 4; the gun ray and enemy sight ray now use collision mask 1 so
  corpses can't block shots or sight. Swings are now committed (they play
  out fully; the hit lands only if the target is still in range at impact;
  `attack_recovery` added; getting shot still interrupts).
  **Standing design requirement (user):** anything movable in the game
  (props, crates, corpses) should behave like Half-Life physics objects:
  they react to explosions, shots, pushes and impacts. Implications to
  honor: explosions must apply impulses to everything in radius including
  ragdolls (layer 4); shots should eventually push props and corpses
  without letting corpses block bullets (needs a separate physics-only
  query, since the gun ray currently ignores layer 4); in co-op,
  gameplay-critical props are host-simulated and cosmetic ones (debris,
  corpses) are simulated locally on each player's game.
  Known balance note (Rule 3): 0.4 s fire interval vs 0.25 s pain time
  lets rapid fire keep enemies flinching. **Physics engine note:** Box3D (Erin Catto, MIT, alpha, announced
  2026-06-30; community Godot extensions exist as drop-in PhysicsServer3D
  replacements) looks promising but is deferred; we stay on Jolt for now.
  Revisit when building physics puzzles, testing on a project copy first
  (movement, `body_test_motion` step-up and shot rays must all still work).
  Keep using standard Godot physics nodes so switching stays a settings
  change. **Code reuse decision:** do not copy GPL (Quake) or
  non-commercial (Valve SDK) code, even lightly modified; reuse designs and
  ideas, write our own, and only reuse MIT-licensed Godot code with its
  licence notice kept. Physics puzzles wanted: gameplay-critical props are
  host-simulated, cosmetic ones local only. Immediate priority: weapons and enemies
  (friends are starting to build maps in TrenchBroom). All combat code
  must treat "the player" as one of several players (Rule 1).

- 2026-09-28: Ragdoll tuning notes. Bones ignore players and other enemies via collision exceptions (a fast player running over a corpse tied it in knots), so walking over bodies doesn't move them. This deliberately trades away 'corpses react to being walked into' for stability; the standing Half-Life-style requirement (react to explosions, shots, deliberate pushes) is still to be met with controlled impulses later. Tuning knobs on EnemyRagdoll: death_push, bone_length_scale, bone_radius_scale, linear_damping, angular_damping. Joint limits are set per PhysicalBone3D in the editor (hinges for LowerLeg/LowerArm, cones elsewhere; delete finger/toe/hand/foot bones). The edit tool failed repeatedly on scripts in this folder, so recent edits were done via direct PowerShell writes.

- 2026-09-28: Reverted the ragdoll collision exceptions at the user's request: the ragdoll collides with everything again, as before. Ragdoll work is parked; revisit later (the run-over twisting problem is still open).

- 2026-09-28: **Weapon system.** WeaponData gained pellets/spread, draw_time, icon, viewmodel scene/offsets and a placeholder colour. WeaponController now owns an inventory, switching (draw_time blocks firing and the old weapon's cooldown carries over, so switching can't fire faster: Rule 3) and shotgun-style pellets; select_weapon is part of PlayerInput (the wheel is local UI, the host decides what's equipped: Rule 1). New: weapon_wheel.gd (hold middle mouse, move the mouse to a slice, release; camera look pauses while open), iewmodel.gd (first-person gun with lower/raise switch animation and fire kick; stand-in block until a model is assigned), test weapons shotgun.tres and machine_gun.tres. TEMPORARY: TEST_WEAPON_PATHS in weapon_controller.gd gives the player all three at start until pickups and campaign state exist. Untested at time of writing. Known gaps: viewmodel can clip into walls, no gun models yet, no third-person weapon model for other players, rockets/projectile weapons not built.

- 2026-09-28: Weapon sway added to iewmodel.gd: the gun lags behind camera turning and settles back, driven by the camera's own turn speed (no mouse input read: Rule 1), on its own pivot so it never fights the switch animation or fire kick. Cosmetic only; tunable via the Sway exports on the Viewmodel node. Also added: pivot centring for imported gun models, and a debug-only live tuning tool (F2 toggle, F3 saves into the weapon's .tres).

- 2026-09-28: Ragdolls now react to the killing blow. Health.take_damage() takes optional hit direction/position/impact_force and remembers the last blow (last_hit_impulse, last_hit_position; blows within 100 ms merge so shotgun pellets add up). WeaponData.impact_force is per weapon (pistol 2.0 default, machine gun 1.0, shotgun 1.5 per pellet). EnemyRagdoll gives the bone nearest the impact the full push and every bone ody_share of it, plus a small upward pop. Cosmetic only; in co-op the host will send the hit info with the death message. Corpses still ignore shots (gun ray uses mask 1), so shooting an already-dead body does nothing yet.

- 2026-09-28: **Decision: adopt Box3D** (osimuka/box3d-godot binding, its own node types: Box3DWorld, Box3DBody, Box3DCharacterBody, Box3DCollisionShape, joints) for ragdolls and physics props, after side-by-side testing in a separate copy of their demo project. User's verdict: 'way more realistic... love it a lot more than what we have' vs our Jolt PhysicalBone3D ragdoll. Confirmed working on Godot 4.7.2. Known integration cost (not yet started): this is NOT a drop-in replacement like the other Box3D extension -- it's a SECOND physics world alongside Godot's own, so using it means (1) mirroring level collision into a Box3DWorld, (2) a player stand-in body so it can push Box3D props, (3) shots checked against both worlds, (4) ragdolls need a bridge that reads each Box3DBody's transform every frame and applies it to the matching Skeleton3D bone, since Box3D's own ragdoll sample drives its own plain mannequin mesh, not an arbitrary imported character skeleton. Plan: start with physics PROPS (crates etc, no skeleton bridge needed, immediate Half-Life-style win), then build the ragdoll skeleton-bridge as its own step. Test files live in C:\Users\qtres\GodotProjects\2v-2-box3d-test and two extracted copies of the demo at C:\Users\qtres\box3d\ and C:\Users\qtres\box3d-godot-main\ (the latter has no .godot cache and can be deleted once the former is confirmed working).

- 2026-09-29: **Sound system, hit ticks, mantle.** Sound: `SoundEvent` resource (list of clips + volume/pitch variance + bus; a random clip per play) and `SoundPlayer` static helper (`play_2d` / `play_3d` / `play_loop_3d`), same shape as BloodFX. Presentation-only listener nodes (`EnemySound`, `PlayerSound`, `WeaponSound`) hook signals that already existed, plus new `jumped`/`dashed`/`wall_jumped`/`mantled` on PlayerMovement and `artery_kill(bone)` on WeaponController. Per-weapon fire/reload/switch sounds live on WeaponData. Every slot points at a stub `.tres` in `audio/events/`; drag audio into its `clips` in the Inspector. The artery spurt sound is parented to the neck bone so it follows the ragdoll. Buses default to "SFX" and fall back to Master until an SFX bus exists. Hit ticks: four thin red lines at the crosshair's sides flash on a hit (Quake 2 "hit indicator"). Mantle: press space while LOOKING at a ledge (camera ray, not body facing) between `mantle_min_height` and `mantle_max_height`; a forward ray finds the wall, a downward ray finds its top, a body_test_motion clearance check guards the landing; the climb is a physics-process Tween on global_position. Rule 3 flag: watch `mantle_max_height` so it doesn't trivialize heights opponents must work for in PvP. Untested at time of writing (no Godot executable in that environment). Known gap: `enemy_gunner.tscn` inherits the base melee `attack_sound`; give its EnemySound its own gunshot event.

- 2026-10-04: **Creative direction locked in** (see the Creative Direction section above). Supersedes the 2026-09-28 "demon realm/dungeon" destination: Grandma's portals now lead to a lawless Gotham-style city; enemies are crackheads and lowlifes; the protagonist is Postal Dude-inspired; tone is GTA/Postal satire; look is grimy and dirty through a PS1 lens. The suburban hub, Grandma's mission select and the portals are unchanged. Next: an IK-driven enemy using the IKModifier3D nodes Godot brought back in 4.6 (TwoBoneIK3D, SplineIK3D, FABRIK3D, CCDIK3D, JacobianIK3D). Rule 1 note: TwoBoneIK3D and SplineIK3D are deterministic (no dependence on the previous frame), so in co-op each client computes the same pose from the same replicated target with no pose data sent; the iterative solvers may drift slightly between clients, which is fine for cosmetic limbs only.

- 2026-10-04: **Any Killer model can be an enemy now; ragdolls are built in code.** Why swapping the model used to break the ragdoll: (1) the 20 PhysicalBone3D nodes were baked by the editor's "Create physical skeleton" INSIDE the Killer_05 instance in enemy.tscn, so replacing the model threw them away; (2) only Killer_02/05 were imported with `art/animations/mixamo_bonemap.tres`, so the others kept raw `mixamorig_*` bone names that the shared animations, ragdoll and artery Neck lookup can't find. Fixes: all 8 Killer FBX imports now use the bone map (all 8 share the same 34-bone Mixamo skeleton; Monster_02/03/05 do too and could get the same treatment, Monster/01/04 have extra bones). New `RagdollBuilder` (static helper) builds the PhysicalBoneSimulator3D at spawn from whatever skeleton is present, porting the editor button's math (MIT notice kept in the file) plus the old hand-tuned joint table; it reproduces the old baked numbers exactly, including the editor's quirk of sizing capsules in skeleton units (~2.2x the world bone length on a 0.45-scaled model) -- kept on purpose so the existing tuning carries over; fixing that is a separate, testable change. A model that ships its own baked ragdoll still wins. New `EnemyModel` node (`Model` in enemy.tscn) picks one of its `variants` per spawn, in `_enter_tree()` so the model exists before EnemyAnimator/EnemyRagdoll `_ready()`; seeded like EnemyAnimator for co-op; `@tool` editor preview of the first variant (never saved). The shared AnimationLibrary is now assigned through EnemyAnimator.animation_library instead of an override on one model's AnimationPlayer. Each type has its own models so they stay readable (Rule 3): melee Killer/01/05, rusher Killer_02/03/06, gunner Killer_04/07. enemy_rusher.tscn was a full 500-line copy of enemy.tscn; it's now an inherited scene like the gunner, with only its own stats. Untested at time of writing (no Godot executable in this environment). Noticed while porting: the old ragdoll's left/right elbows differ (only the right has a 90 degree joint rotation) and the upper-arm swing differs (60 vs 80); carried over as-is.

- 2026-10-04: **Ragdoll fix: Godot's hidden compat simulator.** Every Skeleton3D creates its own hidden (internal), empty, inactive PhysicalBoneSimulator3D on enter-tree for pre-4.3 compatibility (`Skeleton3D::setup_simulator()`), and `find_children()` includes internal nodes. EnemyRagdoll searched with `find_children()`, found that empty one instead of building a real ragdoll, and every enemy logged "no humanoid bones". It now checks only the skeleton's normal children (`get_children()` excludes internal nodes) before building. The old hand-baked ragdoll only worked because it happened to sort first. Gotcha for later: never search for PhysicalBoneSimulator3D with `find_children()`. Also fixed: base enemy's walk list had a typo (`moves/a` -> `moves/Walk`), and four scenes referenced the weapon .tres files with stale UIDs.

- 2026-10-04: **Ragdoll tuning: less stretch, more weight.** User report: ragdolls (now working on all models) felt stretchy, limbs splayed apart, not enough weight. Causes and changes: (1) capsules were ~2.2x the real bone length (the editor sizes them in skeleton units on a 0.45-scaled model), so non-neighbor capsules overlapped and shoved each other apart -- `bone_length_scale` 0.8 -> 0.5 brings them to roughly the real bone length while keeping their thickness; (2) Jolt's joint solver was running few correction passes, so joints visibly stretched under load -- `physics/jolt_physics_3d/simulation/position_steps=8`, `velocity_steps=16` (project-wide; costs some CPU, revisit if physics gets heavy with many props/corpses); (3) the killing blow yanked one limb -- `body_share` 0.4 -> 0.75 so the hit moves the whole body; (4) `bone_gravity_scale` 2.2 -> 3.0 and `angular_damping` 1.0 -> 2.0 for a heavier, less noodly fall. All on EnemyRagdoll in enemy.tscn (inherited by rusher/gunner). Untested at time of writing.

- 2026-10-04: **Headshots, hit zones, new hit marker, bleeding wounds, landing-accurate blood.** Hit zones (Player > WeaponController > Hit Zones): `_hit_kind()` classifies each hit against the live skeleton as NORMAL, HEADSHOT (within `headshot_radius` of the head's middle, halfway from the Head bone to its child) or ARTERY (within `artery_hit_radius` of the Neck bone, shrunk 30% to 0.2625); where the zones overlap at the jaw, whichever center the shot is closer to wins. Damage = weapon damage x `body_damage_multiplier` / `headshot_damage_multiplier` (2.0), or artery = instant kill (`artery_instant_kill`, else x `artery_damage_multiplier`). Rule 3 flag: these apply to every weapon and, later, to players in PvP. `hit_confirmed` now carries `(killed, kind)`. Hit marker: new `HitMarker` node (hit_marker.gd, `@tool` with an editor preview) replaces the four tick ColorRects and the crosshair tint -- white on normal hits, red on headshot/artery, bigger on kills; colors, gap, length, thickness, angle (0 = Quake 2 +, 45 = X), offset and timing are all exports. Headshots pour blood from the wound on the skull (same spurt as the artery, attached to the head's physical bone, `headshot_bleed_time`); one wound per bone at a time so shotgun pellets don't stack 8 spurts. Spurt droplets drag trails (TubeTrailMesh, tuned in `fx/blood_trail.tres` / BloodTrailSettings). Spurt splats now land where the stream actually comes down: an invisible droplet with the same speed/spread/gravity as the visible ones is traced along its arc every 0.2 s and leaves a splat where it hits (GPU particles can't report collisions). Rule 1: all hit visuals go through `_play_hit_effects()`, the hook clients will call from the host's hit message in co-op; blood is cosmetic and local, so traced splat positions may differ slightly per player. New `headshot` SoundEvent slot on WeaponSound. Untested at time of writing.

- 2026-10-04: **Fixed "Lambda capture at index 0 was freed".** Scene-tree timers (`get_tree().create_timer()`) outlive the nodes they were made for; a lambda connected to one still fires after its captured node is freed (gun swapped mid muzzle flash, corpse removed mid spurt, level restarted mid hit-stop). Fixed everywhere: the muzzle flash, spurt stop/free and artery spurt sound connect straight to the node's own methods (`node.queue_free`, `node.set.bind(...)`), which Godot disconnects automatically when the node is freed; the spurt's landing trace runs on a Timer node parented to the emitter so it dies with it; hit-stop restores speed via `Engine.set_time_scale.bind(1.0)`. Convention going forward: never connect a lambda that captures a node to a scene-tree timer -- connect the node's own method, or use a Timer child of that node.

- 2026-10-06: **Fixed "Invalid type in function 'nearest_hostile' ... argument 6 (previously freed)".** NPCs re-pick targets every retarget interval and pass their old `_target` in as `current` (for STICKINESS); if that target was freed since (a body eaten, a corpse removed), Godot refuses to pass a freed object into a typed `Node3D` parameter. `Factions.nearest_hostile()` now takes `current` untyped and nulls it if freed, and FlyingRoach, Enemy and RatBender drop a freed `_target` at the top of each physics tick -- the same `if not is_instance_valid(x): x = null` idiom RatSwarm already uses. Convention: a node reference held across frames can be freed under you; null it with `is_instance_valid()` before passing it to a typed parameter or touching it.

- 2026-10-06: **Roach lift, prey eating, scavenger behavior, rat leaps, human-enemy jitter.** (1) Roach lift: carries stalled halfway because only the torso was pulled up while gravity (`bone_gravity_scale` 3.0) worked on the ~80% of the body hanging off it; the per-tick velocity couldn't beat that once enough hung. Now each roach grabs its own body part (`RoachCarry.GRIP_BONES`: hips, opposite hand/foot, then the rest and the head; a roach that lets go frees its slot), every held part is pulled toward CARRY_HEIGHT, and each holder takes `WEIGHT_PER_ROACH` (0.2) of the weight off and adds lift speed (`EnemyRagdoll.carry(held, weight)` scales the gravity on every bone). (2) Prey: a roach that kills a rat (or a rat that kills a roach) holds it in its mouth (duck-typed `seize`/`is_holding`/`mouth_position`/`consumed` on both) for `prey_eat_time`, biting blood out of it, then one new roach/rat is born (rats respect `feed_limit`). Whatever is holding it dies, it drops. (3) Scavengers first: roaches and leaderless rat packs only go for non-prey (players, tweakers) inside `threat_range` (roach 6, rats 4), or after it hurt them (`Factions.provoked_by`, REVENGE_TIME); hurting a roach alarms every roach within `alarm_radius`, killing a rat threatens its whole pack (`RatSwarm.threatened_by`); a rat pack drops a non-prey target beyond `disengage_range`. Prey (each other) is still hunted at full range. The Rat Bender's own pack still follows his orders. (4) Rats leap at roaches from further and higher (`leap_max_height`, `flier_leap_chance_multiplier`). (5) Human enemy jitter: STICKINESS had already fixed target flip-flopping; the remaining shake was (a) `_nav_direction_to` once a path finished returning the enemy's own feet as the next point, which normalized to a full-speed step in a random direction every tick (now stops inside `arrive_distance`, and walks straight once nav is finished), (b) `look_at` snapping round every tick at something circling it (now turns at `turn_speed` deg/s, HL2's yaw speed), (c) gunners stepping back and forth across `shoot_min_range` (now 0.8x slack while attacking). The nav target is only re-set when it moved >0.1 m, which also stops a repath every tick. Rule 1: all of it is host-only AI; carries, prey held in jaws and births will need "carry/hold/spawn" sync events when co-op replication lands. Untested at time of writing (no Godot executable here).

- 2026-10-06: First level: the three L-shaped test walls (`MazeWalls`) now have a mirror-image set (`MazeWallsMirrored`) on the spawn side of the map, reflected across the map's center line (z -> -z). Built as proper rotations with the short arm's offset flipped, not a negative scale, which physics bodies don't handle. Grandma ends up in the corner of the mirrored L2; nothing overlaps.

- 2026-10-06: Rat Bender frenzy 25% slower: `RatSwarm.frenzy_speed` 2.7 -> 2.025 (frenzied rats run at 2.025x their normal speed instead of 2.7x). No scene overrides it, so this applies to every Bender pack.

- 2026-10-06: **Boss level is now the first map plus the Rat Bender.** `rat_bender_level.tscn` was its own older, smaller (60x60) copy of the test map; it's now an inherited scene of `test_map.tscn`: same 120x120 floor, pillars, cover pillars, maze walls, pickups, enemies, roach herds and rat nests, and any later change to the first map shows up in the boss level automatically. It only adds the RatBender (same spot and tuning as before) and switches Grandma off (hidden, process_mode Disabled, which also takes her collision out) so you can't start a mission from inside one. The boss level's 2 extra roach herds are gone with the old copy. Also fixed "rat.gd _ray(): Condition !is_inside_tree()": the Bender's leap wave queues each rat's leap on a scene-tree timer, which can fire after the rat (or the whole level) has left the tree; `RatSwarm._leap()` and `Rat.leap()` now check `is_inside_tree()` first.

- 2026-10-06: **Scavengers eat on the move, toward somewhere quiet.** Roaches (RoachCarry) start eating the moment they start lifting -- however high they can get the body -- instead of only once it's clear of the ground; EAT_TIME now runs from then. Once it's fully off the ground they fly off with it at FLY_SPEED (2 m/s, well under their 6 m/s cruise so holders keep up), still eating, toward the quietest of 8 spots FLY_DISTANCE (12 m) around (cut short at walls) or staying put, re-picked every REPICK_TIME (2 s) with a REPICK_MARGIN so they don't dither; if it sags back to the ground they lift it clear again before moving on. Rats eat the whole time they're hauling a body (so packs also breed off it sooner), and `_pick_drag_spot()` now picks the quietest of up to 4 valid spots instead of the first. "Quiet" is the new `Factions.danger_at()`: each hostile within the radius adds 1 fading to 0 at the edge (Rule 6: Source NPCs score flee/cover hint nodes by distance from their enemies the same way). Costs: one score per candidate spot, only when picking (every 2 s per carried body, once per drag). Boss map: only one rat nest (RatNest) besides the Bender's own horde -- RatNest2-4 are switched to 0 rats there (the first map keeps all four). Untested at time of writing.

- 2026-10-06: **Quiet mutation for non-player kills; roaches breed in pairs.** Enemy now records `killed_by_player` with `will_mutate` (any attacker id other than Health.NO_ATTACKER: players hurt with their peer id, and their grenades, rockets and the barrels they set off carry it; tweakers, roaches and rats hurt with NO_ATTACKER). Every mutating corpse now flashes; killed by a player it also twitches and swells as before. Killed by anything else it lies still (no limb bursts, no MutationPulseModifier) and only flashes (`HitFlash.flash()` now takes an optional color and fade time), faster and faster from `mutate_flash_rate_start` (0.5/s) to `mutate_flash_rate_end` (5/s) over the same `mutate_twitch_time`, in `mutate_flash_color` (red), then still bursts into a mutant; double-tapping it still calls it off. Rule 1: who got the kill is decided on the host; clients will need it in the death message to show the right version. RoachCarry: every BITES_PER_ROACH bites now births ROACHES_PER_BREED (2) roaches instead of 1, up to BREEDS_PER_BODY (3) times per body (so up to 6 per body instead of 3). Untested at time of writing.

- 2026-10-06: Roach lift strength: 3 roaches (MIN_ROACHES) can now always lift a body all the way. `WEIGHT_PER_ROACH` 0.2 -> 0.3 (3 holding leave it at 10% of its weight instead of 40%; 4+ make it weightless) and the held parts' pull toward CARRY_HEIGHT is now `LIFT_PULL` 6 (was a hard-coded 3) so they don't settle short under the hanging limbs. Still fully physics-driven: held bones get a velocity each tick, every bone's gravity is scaled down, and the joints carry the rest -- nothing is moved kinematically. Untested at time of writing.

- 2026-10-06: **Roach lift is a real tug of war.** Held parts were driven to the same target height by setting their velocity, so every roach ended up level and nothing looked heavy. Now each roach pulls its own body part up with a capped force (`GRIP_STRENGTH` 0.3 of the whole body's weight, an impulse on that bone each tick; `EnemyRagdoll.carry(pushes, weight)`) and bears `SUPPORT_PER_ROACH` (0.12) spread over the body as reduced gravity (keeps the joints from being yanked apart). Three roaches = 1.26x the body's weight, only just enough; six = 2.5x. How hard each pulls is a clamped PD effort (`HOVER_EFFORT`, `EFFORT_PER_METER`, `EFFORT_DAMPING`), so a part with more body hanging off it (the hips) sags lower than a hand, the roaches sit at different heights, and each bobs harder the closer it is to flat out (`RoachCarry.strain()`, `FlyingRoach.CARRY_BOB`). Sideways steering (flying off with it) is also a capped force (`STEER_RATE`). Also: spitter globs 20% faster (roach.tscn `spit_speed` 14 -> 16.8, and its flight-time limits 0.6/1.6 s -> 0.5/1.333 s so short and long lobs speed up too, not just mid-range ones). Untested at time of writing.

- 2026-10-06: **Rats haul bodies by the limbs, with real forces.** `EnemyRagdoll.drag()` (every bone set to the same sideways velocity) is gone. Each dragging rat now bites onto its own body part (`RatSwarm.DRAG_GRIP_BONES`: hands and feet first, then head, forearms, shins, torso) and pulls it along with at most `drag_pull` (0.08) of the body's weight, lifting it toward `drag_limb_height` (0.3 m) with at most `drag_lift` (0.04), and bears `drag_support` (0.03) of the weight overall -- through the same `EnemyRagdoll.carry(pushes, weight)` the roaches use. The torso scrapes along with real floor friction; ten rats (eat_min_rats) haul at `drag_speed`, more haul faster (up to 1.5x), and each rat's pull eases off as its part reaches that pace. Rats crowd just ahead of their own part while hauling. Joint safety: `carry()` now spreads every pull up the limb (`GRIP_CHAIN_SHARES` 50/30/20% on the held bone and the two above it), since a hard shove on one small bone makes the joints fight and stretch (same lesson as body_share on the killing blow) -- this applies to the roaches' lift too. Untested at time of writing.

- 2026-10-06: All decals fade away: everything placed through `BloodFX._place_decal()` (blood and goo splatter, pools, bullet holes, rat dig holes) now lasts `DECAL_LIFETIME` 25 s, each randomly +-`DECAL_LIFETIME_VARIANCE` 5 s (so 20-30 s, never all at once), then fades out over `DECAL_FADE_OUT_TIME` 2 s and is freed -- on the decal's own tween, so nothing outlives it. Also caps decal build-up in long fights (Rule 2). Consts, since BloodFX is a static helper with no node to export on.

- 2026-10-06: Bred roaches are a 50/50 spitter-or-normal roll (`RoachCarry.BRED_SPITTER_CHANCE`). roach.tscn is set to `kind = Spitter`, so every bred roach used to be a spitter. All roach births (a carried body, a rat eaten mid-air) now go through `RoachCarry.hatch()`, which sets `kind` before the roach enters the tree.

- 2026-10-06: **Roach patrols, wider rat roaming, carries capped in height.** Idle roaches (nothing to fight or eat) used to hover in place. Now they flock with the idle roaches within `flock_radius` (boids: `cohesion_strength`, `separation_distance`/`separation_strength`, `alignment_strength`) and patrol together: each flock follows one leader -- the lowest instance id among them, so merged flocks agree on one without any coordination -- which picks a spot within `patrol_radius` of its home (spawn point) every `patrol_interval` or on arrival, flying at `patrol_speed_scale` of cruise; with `gather_chance` it heads for the nearest roaches outside its flock within `gather_range` instead, so scattered groups meet up and merge. Spots sit hover_height (+0-1 m) over the floor and are cut short at walls. Cost: each roach rescans the roach group every ~0.5 s. Rats: `roam_radius` 15 -> 30. Carry height bug: the floor probe under a carried body only reached 4 m; past that, "no floor" made the target height wherever the body already was, so with 4+ roaches (more than enough pull at a fixed `HOVER_EFFORT` 0.6) it climbed forever. Now the probe reaches 30 m (`FLOOR_PROBE`) and falls back to the floor where they picked it up; the target never goes more than `MAX_EXTRA_HEIGHT` (1 m) above that floor (no climbing over pillars); and each roach's baseline effort is its exact share of the weight for however many are holding (replaces HOVER_EFFORT), so six roaches hold it at the same height three do. Untested at time of writing.

- 2026-10-06: Rat nest swarms 5% faster: `rat_speed` 5.3 -> 5.565 on rat_nest.tscn's RatSwarm only (the Rat Bender's horde keeps the script default 5.3).

- 2026-10-06: **Gangs, smarter tweakers, the "dies without reacting" bug, a messier roach swarm.**
  - Bug 1, sight: `Enemy._can_see()` counted any creature in the way as a wall, so in a swarm another rat or roach was always blocking and a tweaker never "saw" what was eating it. Only StaticBody3D (the level) blocks sight now; and whatever just hurt it counts as seen (`_update_memory()` checks `Factions.provoked_by`).
  - Bug 2, stunlock: every hit flinched it (PAIN) and cancelled its swing; rats biting a few times a second kept it stunned until it died. Hits from non-players now flinch at most once per `creature_pain_cooldown` (1.5 s); a player's hits still stagger every time (Rule 3: unchanged feel for players).
  - Gunners: a stray shot now hurts whatever non-tweaker it hits (only gang mates are spared), and a gunner with a gang mate in its line of fire holds fire and sidesteps (`_mate_in_line()`).
  - Gangs (tweakers only; the Rat Bender keeps his own AI): new `Enemy.State.PATROL` (appended to the enum; animator plays walk at `patrol_speed_scale`). Idle tweakers within `gang_radius` patrol together behind the lowest-instance-id idle one, which picks navmesh spots within `patrol_radius` of home (or, with `gather_chance`, another gang within `gather_range` to merge with); the rest take a sunflower spread (`gang_spacing`) around its spot. `_separation()` keeps `personal_space` between tweakers while patrolling and chasing. Spotting a target alerts every tweaker within `alert_radius`; getting hurt provokes them all against the attacker (`_protect_gang()`, deferred because the provoke lands after the damage). Melee tweakers closing in fan out to flank (`flank_spread`). Cost: one gang scan per tweaker every 0.5 s; alert scans only on events.
  - Roaches: `patrol_radius` 14 -> 28. Per-roach personality (`messiness`): pace, preferred height, flock stickiness (about 1 in 8 straggle), its own scattered spot near the flock's goal (re-picked every 2-6 s), random darts (`dart_chance`), and its own circling distance / spitter hang-back distance. `group_attack`: a roach with nothing to fight joins what a roach within flock_radius is fighting. Diving is unchanged: still only `max_divers` (2) at once.
  - Untested at time of writing.

- 2026-10-07: **Barnacles: roach-spitting fungal growths.** New `Barnacle` (scenes/enemy/barnacle.tscn, the PSX Creatures kit's barnacle.fbx with its barnacle.png on a nearest-filtered material; StaticBody3D + Health, no Factions group so nothing but you hunts them) and `BarnacleCluster` (scenes/enemy/barnacle_cluster.tscn). A cluster placed on a floor, wall or ceiling with its +Y pointing out of the surface grows `count` (6) barnacles across it by raycasting back into the surface, each standing on the hit normal, sizes spread evenly from `size_min` 0.6 to `size_max` 1.6 (biggest in the middle) with a little jitter, among `fungus_count` flat fungal mounds (one shared SphereMesh, no collision). Each barnacle: every 5-10 s (`spit_interval_min/max`) it throbs three times, each bigger (`swell_time`, `swell_amount`; a scale tween on its Model, since the kit mesh has no skeleton or animations), then spits `roaches_per_spit` out of its mouth along its own up -- 1 for the smallest, 3 for the biggest, 2 between -- through `RoachCarry.hatch()` (random spitter/normal; `hatch()` and `FlyingRoach.burst_out()` now take a direction). Shot dead: a red blood explosion (four BloodFX impacts), a red splatter on the surface it grew on (floor, wall or ceiling), a splat sound (new audio/events/enemy/barnacle_splat.tres = sfx/gore burst_big), and its full spit's worth spills out. It won't spit past `roach_cap` (50) roaches alive. `model_scale` fixes the look if the FBX (authored in cm) imports at the wrong size. Three clusters on the first map (floor at -18,-8; north wall; east wall), so the boss map has them too. Rule 1: host grows and spits; mounds are cosmetic. Untested at time of writing.

- 2026-10-07: **Baked the procedural art into files you can edit.** (1) Decal textures: BloodFX used to paint each splat colour's 128x128 texture pixel by pixel in GDScript (once per colour, plus `warm_splat_texture()` calls to dodge the hitch) and the bullet hole the same way. They're now `art/fx/splat.png` (white -- every decal tints it through `Decal.modulate`, the HUD screen splats through `self_modulate`, so one texture serves blood, goo and dirt) and `art/fx/bullet_hole.png`, baked with the exact same math (seeded). Edit them in any image editor; keep the splat white. `warm_splat_texture()` and the generators are gone. (2) Roach model: RoachVisual built a fresh set of meshes and materials (body, head, antennae, wings, and the spitter's sac) for every roach. They're now `scenes/enemy/roach_model.tscn` and `roach_spitter_model.tscn` (the defaults of `model_scene` / `spitter_model_scene`); every roach shares one set of meshes and materials. Wings flap through any `WingPivot*` nodes. The spitter sac's glow is now a fixed colour in its scene (it used to follow the roach's `spit_color`). Untested at time of writing.

- 2026-10-07: **The Swarm King: a second boss who commands rats AND roaches** (own mission, "Dethrone the Swarm King", order 2 in Grandma's list; scenes/swarm_king_level.tscn inherits the first map like the Rat Bender level: Grandma off, one rat nest). `SwarmKing` extends `RatBender` (scenes/enemy/swarm_king.tscn inherits rat_bender.tscn): Character_Monster_02 (its import now uses the Mixamo bone map, so the Bender's animations fit; reimports on next editor open), green tint, 800 health (Rat Bender + 200), and his heal is half as effective and twice as long as the Rat Bender's in his level (`heal_animation_speed` 0.4 vs 0.8, `heal_per_second` 2.5 vs 10: half the total, twice the time to interrupt). He keeps every Rat Bender ability and adds a cloud of `roach_count` (18) roaches (topped up with his summon). Every spell drives both swarms, by range: far (`rush_min_range` 14+) RUSH = rat frenzy + Swarm Rush (every roach dives for `swarm_rush_time`, ignoring max_divers); mid (`volley_min_range` 6 to 14) VOLLEY = every spitter spits in a ripple (`volley_stagger`) + rats near you pounce; closing in (within `shield_range` 10 and approaching faster than `approach_speed`) SHIELD = roaches pull in tight around him (`shield_radius`, fast swirl) and rats crowd his feet for `shield_time`; close (`leap_range`) LEAP = rat leap wave + roach dives for `close_rush_time`. FlyingRoach gained a Controlled mode (`master`): no flocking, carrying or eating; a loose cloud around him that ebbs and flows (`cloud_breathing`, `cloud_drift`, per-roach noise paths, darts) rather than a rigid ring; orders via `swarm_rush()` / `spit_now()`. Truce: `Factions.master_of()` / `allied()` -- rats and roaches commanded by the same living rat-and-roach boss skip each other (and him) in `nearest_hostile()`; when he dies (`controls_roaches()` goes false) they're wild again and fight. A plain Rat Bender's rats still fight roaches. His level's `rat_cap` is 70 (he brings roaches too). Untested at time of writing.

- 2026-10-07: **Roach cap, the sewer-city look, a Graphics panel.**
  - Roaches: a game-wide cap of `RoachCarry.MAX_ROACHES_ALIVE` (50) living roaches. Every birth goes through `RoachCarry.room_for_roaches()` (breeding and prey births via `hatch()`, barnacles, the Swarm King's cloud); hand-placed map roaches still spawn. Counts only living ones.
  - SewerLook (autoload scenes/sewer_look.tscn, scripts/sewer_look.gd; tune its exports in that scene), four effects, each a saved switch in GameSettings: (1) sickly colour grade -- the level WorldEnvironment's adjustment (contrast 1.12, saturation 0.85) plus a 1D colour-correction gradient (crushed blacks, green mids, dirty-yellow highlights); (2) grime & wet floors and (4) PS1 texture warp -- shaders/sewer_world.gdshader on the level's walls and floors (world-space noise streaks down walls, blotches and glossy puddles on floors; affine UVs via the UV*w / w varying trick), driven by global shader uniforms `sewer_grime` / `sewer_affine` / `sewer_grime_noise` (declared in project.godot [shader_globals]) so a switch changes every surface live; (3) ground fog -- the environment's exponential + height fog (`fog_height` 1.2, greenish), restoring the level's own fog when off. On every level load, each MeshInstance3D directly on a StaticBody3D (map geometry, not enemies/props/pickups/barnacles) has its plain opaque StandardMaterial3Ds swapped for one shared world-shader copy each (albedo texture/colour, uv1 scale/offset, roughness, metallic carry over; normal maps, emission and vertex colours don't), and big BoxMesh/PlaneMesh surfaces are split into ~`warp_segment` (2 m) pieces so the warp bends rather than tears (PS1 games subdivided floors for the same reason). Meshes built after load (a runtime-loaded .map) aren't converted.
  - Pause menu: a new Graphics button opens a Graphics panel with resolution, window mode, VSync and outlines (moved from the main panel) plus the four switches. Sub-panels share `_make_sub_panel()` / `_finish_sub_panel()`.
  - Untested at time of writing.

- 2026-10-07: **Every sewer-look value is adjustable in-game; fewer puddles, rarer wall grime.** Graphics panel now scrolls and, under "Look Values", has a slider for each entry in `SewerLook.VALUES` (grade strength/contrast/saturation, fog haze/layer height/layer thickness, grime overall, wall grime strength and amount, floor grime strength, puddle wetness and amount, warp strength) and a colour picker for each in `SewerLook.COLORS` (fog, grime), plus "Reset Look Values". Changes apply live (`SewerLook.set_value()`) and are saved (`GameSettings.look_values`, config section [look]); the scene's exports are the defaults Reset returns to. The grime's knobs became global shader uniforms (`sewer_grime_color`, `sewer_wall_streaks`, `sewer_wall_coverage`, `sewer_floor_blotches`, `sewer_puddles`, `sewer_puddle_coverage`, in project.godot [shader_globals]) so they change every surface at once. Coverage maps to where on the noise the effect starts (wall: 0.8 -> 0.35, puddles: 0.85 -> 0.45). New defaults: puddle coverage 0.42 (start ~0.68 vs the old 0.6 -- roughly a third of the puddles, judged from the noise's spread), wall coverage 0.35 and wall strength 0.6 (was effectively 0.42 start, 0.75 strength). Grade strength blends the colour-correction gradient from no change to the full grade. SewerLook autoloads before PauseMenu now (the menu reads its VALUES list when it builds). Untested at time of writing.

- 2026-10-07: Enemy model pools: normal (enemy.tscn) = Character_Monster_01, Character_Monster_04, Character_Killer_05; rusher = Character_Monster, Character_Killer_02; gunner = Character_Killer_07. (Killer, Killer_01, Killer_03 -- still the Rat Bender's -- Killer_04 and Killer_06 are out of the enemy pools.) Character_Monster, _01 and _04 now import with the Mixamo bone map like the Killers (they reimport on the next editor open). The 2026-10-04 note says Monster/_01/_04 carry extra bones beyond the shared 34-bone skeleton; the bone map renames the shared ones and leaves the extras, so the animations and the ragdoll (built from the humanoid bones) should fit -- check them in game. Untested at time of writing.

- 2026-10-07: **Leeches guard the barnacles; model pool tweak.** New `Leech` (scenes/enemy/leech.tscn: the PSX Creatures kit's tape_worm.fbx with tape_worm.png, a RigidBody3D with Health 25 and a small sphere; players walk through it). `BarnacleCluster` spawns `leech_count` (3) around each clump (wall/ceiling clumps' leeches drop to the floor). Look: it "squirms" by tweening its Flip node's scale.x 1 -> -1 -> 1 (a smooth mirror-flip through flat, TRANS_SINE) at `squirm_rate`, faster mid-leap and latched, while its Swell node pulses (`pulse_amount`). Brain (host): crawls about its home within `guard_radius`; a player within `notice_range` it crawls at, and within `leap_range` it leaps at like a rat (velocity that lands on your chest in `leap_time`). Passing within `latch_reach` of your chest it latches: frozen, collision off, held `latch_height` up and `latch_forward` in front of you, facing you, biting `bite_damage` every `bite_interval`. While any leech is on, `WeaponController.tick()` returns early -- no firing, switching, reloading or throwing -- and every fresh fire press calls `Leech.tug()`; `tugs_to_remove` (8) presses each within `tug_window` (0.6 s) of the last rip it off and fling it away (too slow and the count resets). HUD shows "LEECH! Spam click to rip it off!" on `leech_latched(true)`. Shot dead: a small blood burst, a red splat on the floor below (looks 3 m down, so it lands even if it died on your face), the gore splat sound. `model_scale` / `model_yaw` fix the model's size/heading if the FBX imports oddly. Pools: normal = Monster_01, Killer_01, Killer_05 (Monster_04 out); rusher = Monster, Killer_02, Monster_01. Rule 1: the host runs it; the latch is the host telling that player's WeaponController. Untested at time of writing.

- 2026-10-07: Leech latch reworked: a latched leech now clamps over the victim's eyes -- `face_distance` (0.22 m) in front of their Head/Camera3D, its underside toward the camera, its length running up the screen, scaled `face_scale` (2.4x) so it covers most of the view while it keeps writhing. Getting it off is a meter instead of a click count: each fresh click adds `pull_per_click` (0.12, ~9 clicks) and it drains `meter_drain` (0.45/s), so you have to click fast; full and it's flung off (`_visual` reset to its own size). HUD: a red "LEECH! SPAM CLICK TO RIP IT OFF!" bar (`WeaponController.leech_progress()`) shows while one's on, replacing the centre message. Untested at time of writing.

- 2026-10-07: **Pills and bandages; a fourth barnacle clump.** Pickups: `ItemPickup` (scripts/item_pickup.gd; scenes/pills_pickup.tscn = PSX Mega Pack pills_bottle_2, scenes/bandage_pickup.tscn = bandage_mp_1) is a real physics body like WeaponPickup -- falls, can be shoved and shot -- with a PickupArea; walk into it and it's yours with a centre message like a key (`MapIO.show_message`), unless you're already carrying `max_pills` (2) / `max_bandages` (3). Its collision box is fitted to the model at spawn (`model_scale` 1.6 so it's spottable). Use: `WeaponController.tick_items()` (fed `PlayerInput.use_pills` = H, `use_bandage` = B, every tick after `tick()`): with one to use, no leech on you and no throw in progress, it starts the item -- `tick()` returns early (no firing/reloading/switching) until `item_lower_time + *_use_time` is up, then the item's used and the heal lands: pills `Health.heal(pills_heal)` (50, instant, Left 4 Dead 2's pills), bandage `Health.regenerate(bandage_heal, bandage_heal_time)` (40 over 8 s; stacks like bleed()). The gun then can't fire for `item_recover_time` while it comes back up. Viewmodel (`_on_item_used`): the gun drops; the item model comes up in camera space in the other hand; pills tip back 115 degrees toward the mouth and lift up past the top of the screen (L4D2's pill pop); a bandage wraps round in two little circles then drops away; the gun comes back. HUD ammo line shows "[H] Pills: n" / "[B] Bandages: n" when carrying any. Placed on the first map: three of each (one of each by the spawn). Also a fourth barnacle cluster on the floor at (35, 0, 35). Untested at time of writing.

- 2026-10-07: **PKM machine gun, and its stretched carry handle fixed.** Why the handle stretched: in PKM.glb the Carry Handle is a child of the Barrel node, which is scaled ~18x along its length (the barrel was lengthened by scaling the object); the handle is also rotated, so that non-uniform parent scale hits it at an angle and shears it ~9 m straight back (rotated child under a non-uniformly scaled parent = shear). Other parts under the barrel aren't rotated against it, so they're fine. Fix without Blender: art/weapons/NEWPSXWEAPONS/PKM/pkm_import_fix.gd is the import script of both PKM.glb and PKM.fbx; on import it multiplies the handle's local transform by diag(1, |barrel.x|/|barrel.y|, 1) -- as if the barrel were scaled evenly -- which lands it as a compact handle on top of the receiver; it also hides "Bipod Deployed" (the model has the bipod folded and deployed at once). The proper source fix would be applying the Barrel's scale in Blender (Ctrl+A > Scale) before parenting things to it. Lesson for any imported model with a part flying off in a straight line: look for a rotated child under a non-uniformly scaled parent. Weapon: weapons/pkm.tres (13 dmg, ~650 rpm, 100-round belt, 3.2 s reload, 2 penetrations, heavier recoil pattern; viewmodel_scale 0.22, its viewmodel_position and muzzle_offset are first guesses -- tune with the F2/F3 viewmodel tool), scenes/pkm_pickup.tscn (physics pickup, 200 rounds), one by the first map's spawn. Also: pills and bandages are 3x bigger in your hand (`WeaponController.item_view_scale` 3.0); the pickups in the level keep their size. Untested at time of writing.

- 2026-10-07: PKM retuned against the Submachine Gun (7 dmg, 0.0667 s = 900 rpm, recoil_scale 4.5, jitter 0.4, spread 3.5): PKM 10 dmg (+43%), 0.055 s (~1090 rpm, faster), same recoil pattern shape at recoil_scale 5.2 (+~15%) and jitter 0.45 -- a little more kick -- spread 3.8. Rule 3 flag: it out-DPSes the SMG by ~75% (182 vs 105 per second); the 100-round belt and 3.2 s reload are what keep it honest.

- 2026-10-07: PKM reload 3.2 -> 4.0 s.

- 2026-10-07: **Lowered pistol pose, leeches flat, pickup notices, centred text, a game font, a meta error.**
  - Pistol/grenade hold: "Lower Pistol.fbx" (Mixamo, the character sits -- harmless: the first-person arms freeze the first frame, hide the head and legs, and are placed by where the right hand lands) now imports with the Mixamo bone map and saves its animation to art/animations/LowerPistol.res; starter_gun.tres and grenade.tres use it and their arms_position was cleared so `Viewmodel._auto_place_arms()` puts the hand back on the grip (fine-tune with F2/F3). The gunner enemies keep PistolIdle.res (they play it full-body, so a sitting pose would sit them down).
  - Leech: `_lay_flat()` measures the model and turns it so its thinnest side is up and its longest runs along Z, resting on the ground -- the kit FBX carries a baked Blender axis turn and came in on its side, so it orients itself whatever the import did. Latched: the mirror-flip squirm stops (it flapped across the screen), it lies flat over the middle of the view with a slight writhe, and `face_scale` 2.4 -> 1.4 leaves the edges of the screen visible.
  - Pickup notices: everything added to the inventory now uses the HUD's bottom-centre pickup pop-up (`HUD.show_pickup()`, or `MapIO.show_pickup()` from anywhere): weapons, ammo, grenades, pills/bandages ("+1 Pills"), keys.
  - Centred: pills/bandages counts moved off the top-left ammo line (they overflowed it) to their own bottom-centre line; Graphics menu headings centred.
  - Font: the project now has a theme, scenes/ui/game_theme.tres (Project Settings > GUI > Theme > Custom). Open it and set Default Font (and Default Font Size) in the Inspector -- every HUD/menu label uses it; per-label size overrides still apply.
  - Fixed "get_meta: no 'meta' values with the key 'provoked_by'" (enemy.gd _protect_gang, rat.gd _remove): Godot treats a null default in get_meta() as no default, so a missing key errors. Convention: `get_meta(k) if has_meta(k) else null`.
  - Untested at time of writing.

- 2026-10-07: First-person arms are always Character_18_Police's (`Viewmodel.arms_character`; empty = your own character's), whichever character your body is: every gun's hand placement was tuned on those arms, and other characters' arm lengths knocked the hands off the grips. Their size comes from their own head height (`PlayerModel.fit_scale_for()`, the same fit the body uses), not the chosen body's scale.

- 2026-10-07: Pills and bandages back to real size in hand (`item_view_scale` 1.0), and one shared use animation for both: the grenade quick-throw played backwards (`THROW_SWING_OFFSET`/`TILT` -> `THROW_WINDUP_OFFSET`/`TILT`, in camera space from the hand spot), then on up past the top of the screen. The bandage's circling wrap is gone.

- 2026-10-07: **Fixed 10,000+ "not enough room in the RESOURCES descriptor heap" errors (D3D12).** Every GPUParticles3D holds GPU descriptors while alive, and every new ParticleProcessMaterial adds its own. BloodFX.spawn_impact() made a new particle system AND material per call, and gameplay calls it constantly (rats eating, roaches biting, barnacles spitting, every hit), so after a couple of minutes hundreds were alive and the D3D12 descriptor heap ran out. Fixes: (1) `BloodFX.MAX_LIVE_BURSTS` (48) caps live impact bursts (group "blood_bursts"; past it a burst is skipped); (2) one shared ParticleProcessMaterial per colour + strength (snapped to 0.25), sprayed along its +Y with the node turned onto the normal instead of baking the direction into the material; (3) rat dig dirt goes through spawn_impact (was its own system + material per rat); (4) bullet tracers capped at `BulletFX.MAX_LIVE_TRACERS` (24); (5) project.godot `rendering/rendering_device/d3d12/max_resource_descriptors` = 262144 (4x Godot's default) for headroom. Rule 2 lesson: anything spawned per hit or per bite must be capped and must share its resources. Vulkan (Godot's normal Windows driver; this project pins D3D12) doesn't have the fixed heap at all.

- 2026-10-07: The starter gun is now a pistol: weapons/starter_gun.tres ("Pistol") and scenes/starter_gun_pickup.tscn use the PSX Mega Pack's pistol_mp_1.glb instead of Revolver_glb.glb. That model is real-sized (0.27 m) and points along +X, so viewmodel_rotation 90 deg Y, viewmodel_scale 1.4 (same on-screen length as the revolver at 0.105), muzzle_offset (0.14, 0.073, 0) = the front of the slide from the gun's centre (the viewmodel centres the gun on its pivot); the pickup lies it flat on its side at real size. Stats are unchanged (still a 6-round magazine). Placement is a first guess -- tune with F2/F3.

- 2026-10-07: **Rat and roach caps at 60, culling the oldest.** New `Population` (scripts/enemies/population.gd): `MAX_RATS` 60 and `MAX_ROACHES` 60 living at once, game-wide (roaches were 50, rats had no global cap). Every rat birth goes through `RatSwarm.spawn_rats()` and every roach birth through `RoachCarry.hatch()` / the Swarm King's top-up, which first call `Population.make_room_for_*()`: at the cap, the oldest living ones (by their "born" meta, stamped in _ready -- hand-placed ones are oldest) are killed outright (a normal death) so the new ones always spawn. Only plain Rat / FlyingRoach scripts are culled (never the Rat Bender or Swarm King, who share those faction groups). A spawn of more than the cap is clamped to it; the Rat Bender's `rat_cap` is clamped to MAX_RATS (his levels asked for 110 / 70) so he doesn't summon-and-cull his own horde forever. The barnacle's own `roach_cap` is gone (the global cap covers it). Also: rat nest swarms (the leaderless ones) 10% faster, rat_speed 5.565 -> 6.12.

- 2026-10-07: Leeches: `_lay_flat()` now also measures the model's root when it's a MeshInstance3D (a one-mesh FBX can import with the mesh as the scene root; find_children() skips the root, so it found nothing and the worm stayed on its edge). 20% bigger (`model_scale` 1.2) and easier to shoot: hit sphere radius 0.16 -> 0.32 (still resting at the body's origin). Shotgun: any single pellet (weapons with `pellets` > 1) kills a normal rat outright -- not bodyguards (`Rat.health_bonus` > 1). Rule 3: rats only.

- 2026-10-07: Bodyguard rats +20 health (`Rat.bodyguard_extra_health`, added after the multipliers). New `Rat.is_bodyguard` (a nest's big rats, health_bonus > 1, or a Rat Bender's -- `RatSwarm.bodyguards`, set on his Bodyguards swarm), which the shotgun's one-pellet rat kill now checks (his guards were spawned with health_bonus 1 and would have been one-shot).

- 2026-10-07: **Spiders: wall-and-ceiling crawling packs with IK legs; zombies; spider nests; taller walls and ceilings on the first map.**
  - `Spider` (scripts/enemies/spider.gd, scenes/enemy/spider.tscn; the PSX Mega Pack Spider.fbx, rigged with a bone per leg joint) + `SpiderPack` brain (scripts/enemies/spider_pack.gd, scenes/enemy/spider_pack.tscn), new Factions side SPIDER (group "spiders"), hostile to every other side and they to it, but focused on players: whenever any spider sees a player within notice_range, the pack drops anything else and goes for the player (`_seen_player()`); with no player in sight it fights the rest (rats/roaches, then tweakers) out to notice_range (`prefer_players` limits non-players to threat_range). Population cap `MAX_SPIDERS` 40 (oldest culled).
  - Crawling: an AnimatableBody3D moved by raycasts, the "wall walker" approach -- ray ahead (a wall in the way: climb onto it), ray down (stay stuck), ray back under the edge (walked off a ledge: wrap round onto the far face), nothing: fall. On a wall with its goal through it, it goes up and over. Surface rays skip anything that moves (players, creatures), so it only ever crawls on level geometry. No navmesh: it crawls over things.
  - Pack (like RatSwarm): slots that ebb and drift, weave, stop-start bursts, boids separation, notice/lose/charge ranges, roam. Top speed `spider_speed` 10.6 = twice a rat's 5.3. Patrol is the rat packs': a new spot within `roam_radius` 30 m of home every `roam_interval` 10 s x 0.5-1.5 (or on arrival), at `roam_pace` 0.5 (= a rat pack's speed) with the same bursts/ebb; a wall pack's spots stay within `roam_height` 3 m of home, so it patrols along its wall. Hunting, `wall_preference` (75%) of them go up: the pack finds each a wall on the way (8 rays/s, `wall_detour`), they climb it and make for a spot `perch_height` above the prey (via the ceiling if there is one), then leap from up to `wall_leap_range` 7 m (`wall_leap_chance` 1.8/s); if a spider stops gaining for `wall_give_up_time` it drops off and comes along the floor for `wall_retry_time`. The rest engulf on the floor and leap from 1.5-4 m like rats. Bites 6 / leap 12.
  - Legs: FABRIK IK per leg on the model's own bones (Aristidou & Lasenby 2011), solved from the rest pose each frame so knees bend as built; feet stay planted in the world and step (eased arc, `stride`, `step_time` scaled by speed, `step_lead`) in the alternating-tetrapod gait (two sets of four never step together); pedipalps and fangs animate; in the air the legs splay and paddle; dead, they curl and it lies on its back. Body: rides the legs on a spring (`spring_stiffness`/`spring_damping`) -- follows the feet's height and tilt (`body_follow`), dips per lifted leg (`weight_dip`), shifts onto planted feet (`weight_shift`), twists with each gait set (`gait_twist`), lags/leans on acceleration and turns (`inertia`), breathes; the abdomen swings after it. LOD: IK every other frame past 15 m, frozen past 35 m. Model orientation, size (`leg_span` 0.8 m x size 0.8-1.25) and ride height are worked out from the bones at runtime.
  - Death: shot -> spurt, drops off walls/ceilings, on its back with curled legs in a pool for `corpse_time`; killed by a blast -> bursts. Explosions and melee shove it (`shove()`).
  - Barnacle nests: each BarnacleCluster is a roach or spider nest (`nest`, RANDOM rolls `spider_nest_chance` 0.4): spider nests have paler barnacles (`spider_nest_tint`) and grey fungus and spit spiders into one shared SpiderPack. New `BarnacleScatter` (scripts/enemies/barnacle_scatter.gd) grows up to `max_nests` 3 (each 50%) extra nests on random walls/ceilings at load, `min_spacing` 15 m apart and `safe_radius` 15 m from players.
  - Zombies: art/animations/rigify_bonemap.tres maps the PSX Retro Zombies' Rigify skeleton (spine..spine.006, upper_arm.L, thigh.L...) to Godot's humanoid names, set on all 5 zombie glbs' import (Skeleton3D > Retarget > Bone Map) so the shared animations and ragdoll work. scenes/enemy/zombie.tscn (normal) and zombie_rusher.tscn inherit enemy/enemy_rusher and pick a random one of the 5 zombies; `EnemyModel.fit_height` (1.75 m) sizes any model by its mesh bounds. One of each by the first map's spawn. If they T-pose or don't ragdoll, check the bone map in each zombie glb's Advanced Import Settings.
  - First map: maze walls 4.5 -> 9 m; boundary walls 4 -> 13.5 m (triple the old maze walls) plus eight 13.5 m buttress walls jutting in from the edges; ceiling sections to test spider ceiling crawling (overhangs on the west and north walls at 7 m, a covered nook in the L1 maze corner at 4 m); two 10-spider hordes starting on the west and north walls under the overhangs; a BarnacleScatter.
  - Untested at time of writing (written without running Godot): check the spider legs/orientation in game first; every number above is an export.

- 2026-10-07: **Zombies and leeches off for now; spiders twice as big; spider hips swing.**
  - Zombies: the two test zombies are taken off the first map (they didn't work well). Everything else is kept for fixing later: scenes/enemy/zombie.tscn, zombie_rusher.tscn, art/animations/rigify_bonemap.tres and the bone map on the 5 zombie glbs. Put them back by dropping either scene into a level.
  - Leeches: `BarnacleCluster.spawn_leeches` (new, default off) -- clumps grow no leech guards until it's turned back on; leech.gd/leech.tscn and the face-latch code are untouched. Barnacle clumps are the only thing that spawns leeches.
  - Spiders 2x: `Spider.leg_span` 0.8 -> 1.6 m, hit sphere 0.2 -> 0.4, `bite_reach` 0.9 -> 1.4; pack spacing to match (`pack_radius` 1.0-3.5, `separation_distance` 1.2, `engulf_radius` 0.7-2.2).
  - Spider IK: the first leg segment (the coxa, "<leg>A") barely moved -- FABRIK with a fixed root puts nearly all the bend into the long outer segments, so the short base segment stayed close to its rest angle. Now each leg first swings at the hip round the body's up axis to point at its foot (`hip_swing_limit` 1 rad), then FABRIK bends the rest, so the coxa sweeps forward and back with each step like a real spider's. Untested at time of writing.

- 2026-10-07: Spider legs stood out nearly straight. Why: each foot's rest spot came from the model's rest-pose leg tips, which sit near the end of the leg's reach, and the body was raised to make room under it -- so the IK targets were at (or past) full reach and the solve came out straight. Fix: (1) feet now stand out from each hip by `foot_reach` (0.55) of the leg's length, toward where the rest tip points, with the body `ride_height` (0.3) of a leg length off the surface -- well inside the leg's reach; (2) `knee_lift` (0.35): before each solve the knee joints are pushed up along the body's up axis (most at the middle "C" joint), and since FABRIK keeps the bend it starts from, the legs settle into a high arch. Lower foot_reach / higher knee_lift = more curl. Untested at time of writing.

- 2026-10-07: **Pills and bandages are equippable slots; grenade and heals share the pistol's hold; bigger grenade pickups.**
  - New weapons/pills.tres and weapons/bandage.tres (WeaponData with the new `heal_item`: 0 pills, 1 bandage). While you carry any, the item is a slot in your inventory/weapon wheel like the grenade (`WeaponController._sync_item_slots()`: added on the first pickup, removed when you use the last -- back to your previous weapon if it was in hand). Equipped, a click uses one; H / B still use one straight off whatever you're holding (the gun drops, the item's slot comes up, then the gun returns). HUD shows "Pills x2" for the slot.
  - Their look in hand is now ordinary weapon data -- `viewmodel_position/rotation/scale` and the arms (`hold_animation` = LowerPistol, `arms_position`, ...) -- so equip one and line it up with F2 (H = arms), F3 saves to its .tres. The use animation moves the whole viewmodel (arms + item) through the grenade throw in reverse: up from below the throw's end (`ITEM_RISE_FROM`), back up through the wind-up and past the top of the screen (`ITEM_AWAY`, `ITEM_AWAY_TILT`), so it plays from wherever you placed it. `pills_model`, `bandage_model` and `item_view_scale` on WeaponController are replaced by `pills_weapon` / `bandage_weapon`.
  - Grenade: `hide_left_arm` off, so it holds in the exact same LowerPistol pose as the pistol (both arms). Tune its arms with F2 > H like the others.
  - Grenade pickup: the instance's own transform was overriding frag_grenade.tscn's x6, so the pickup was ~1 cm across (a speck). Now x12 = twice the size of the grenade in your hand (~20 cm), centred on a refitted collision box.
  - Untested at time of writing.

- 2026-10-07: **Fixed grenade switching glitches; first-person arms hide their torso.**
  - Holding a grenade while firing bullets: after a throw the viewmodel waits for the next grenade to reach your hand (`_waiting_for_grenade`), and `_update_held_grenade()` killed whatever tween was running to raise it. Switching weapons during that wait meant it killed the switch tween before its swap callback -- the grenade model stayed in hand with the pistol equipped (WeaponController was right; only the picture was wrong). Now a weapon switch clears the wait, the raise only happens with the grenade actually equipped and shown and no tween running, and a safety net (`_keep_in_step()`) re-shows the equipped weapon whenever nothing's animating and the model in hand doesn't match (`_shown_weapon`).
  - Pistol pose changed after visiting the grenade: with F2 on, the tuning loop applied (and edited, and F3 saved) the EQUIPPED weapon's numbers onto whatever model was showing -- mid-switch that's the other weapon's model. The tool now works on the weapon actually shown (`_shown_weapon`) and pauses while a switch is animating.
  - Torso in view when switching: the lowered gun tilts down by rotating the whole view rig round the camera, which swings the arms model's torso up from below. `Viewmodel.hide_torso` (on): the arms model hides everything but its arms -- `HideBonesModifier` gained `keep_bones` (put back exactly where they were after hiding: the shoulders, and so the arms) and `collapse_in_place` (the chest, shrunk to nothing where it is, so skin blended between chest and shoulder pulls in behind the arm instead of stretching to the hips). Uses `Skeleton3D.set_bone_global_pose()`. Turn hide_torso off on the Viewmodel node to go back.
  - Untested at time of writing.

- 2026-10-07: **Spiders haul bodies up walls to eat and breed; pills on T.**
  - `SpiderPack` "Hauling Bodies" (like RatSwarm's corpse dragging and RoachCarry): a roaming pack of at least `haul_min_spiders` (4) sometimes (`haul_chance` 0.3/s) picks a body (RatSwarm.CORPSE_GROUP, not already "dragged") within `haul_find_range` and the quietest wall within `haul_seek_range` (8 rays from the body; Factions.danger_at(SPIDER); the wall must really go `haul_height` 3 m up, or the spot goes in the corner under a lower ceiling). Up to `haul_max_spiders` grab a limb each (HAUL_GRIP_BONES: hands, feet, head, hips...) and it goes GATHER -> DRAG (along the floor: real pulls on the ragdoll bones, `haul_pull` 0.15 of its weight each, rats' method) -> HOIST (up the wall: each lifts with just enough to hold the weight between them plus more the further below the spot -- the roaches' lift; `hoist_strength` 0.3, `hoist_support` 0.12; steered onto the spot and pressed against the wall) -> EAT (held pinned there for `eat_time` 12 s, then they let go and it drops). Haulers on the floor head into the wall to climb it; on the wall they hold from just above their part. Stuck dragging: they eat it where it lies. Eating: a bite every `bite_interval`/holders (fangs, blood); every `bites_per_spider` 12 bites a spider bursts out of the body onto the wall (max `spiders_per_body` 4 per body -- remembered on the body -- and `feed_limit` 30 per pack). Haulers ignore prey; the rest of the pack carries on. Haulers get collision exceptions with the body's bones (no kinematic shoving).
  - Pills moved from H to T (H is the F2 tool's arms key). Bandages stay on B.
  - Untested at time of writing.

- 2026-10-07: Healing now plays exactly the grenade throw (`Viewmodel._on_item_used()`): same wind-up, swing and follow-through offsets/tilts as the grenade slot and Q, with the item in the hand; it's used up as it leaves the hand, and the heal lands then. Off a gun (T / B) it's the Q sequence (gun down, item up, throw, gun back); from its own slot it's the grenade slot's (next one comes up into the hand). The reverse animation (ITEM_RISE_FROM / ITEM_AWAY / ITEM_AWAY_TILT, which tipped the view rig ~110 degrees and swung the arms model's torso across the camera) is gone. `pills_use_time` / `bandage_use_time` 0.9 / 1.4 -> 0.25 (= the grenade's throw_release_delay, so the throw plays at the grenade's speed); heal amounts unchanged. Untested at time of writing.

- 2026-10-07: Barnacles spawn half as often: `spit_interval_min/max` 5-10 s -> 10-20 s (roach and spider nests alike). What one spills when killed is unchanged.

- 2026-10-07: Torso flash in first person: every swap of the model in hand (switch, Q throw, heal) builds a fresh arms model, which was drawn whole for a frame before its HideBonesModifier first ran -- a one-frame flash of the torso at the bottom of the screen. New arms now stay hidden for `ARMS_REVEAL_FRAMES` (2) frames (`Viewmodel._reveal_arms()`). Untested at time of writing.

- 2026-10-07: **First-person arms are now truly arms-only.** The bone-shrinking torso hide (HideBonesModifier keep_bones / collapse_in_place, and the ARMS_REVEAL_FRAMES delay) did not take effect in game -- the torso still flashed up at the bottom of the screen on throws and heals. Replaced with a mesh cut: when the arms model is built, `Viewmodel._strip_to_arms()` rebuilds each skinned mesh keeping only the triangles whose three corners are at least half skinned to a shoulder/arm/hand bone (the right side, plus the left unless the weapon has hide_left_arm); unskinned parts are hidden. Vertex bone indices are skin bind slots, mapped to skeleton bones through the Skin (bind bone, or bind name). Cut meshes are cached per mesh+skin+side (`_arms_only_meshes`), so a swap costs nothing after the first. Per-surface material overrides follow their surfaces. The full body (PlayerModel) is untouched, so looking down still shows your legs. `hide_torso` off = the old head/legs shrink. HideBonesModifier keeps its new options for other uses. Untested at time of writing.

- 2026-10-07: Fixed a parse error that stopped the game loading (viewmodel.gd: "Cannot infer the type of flags"): `Mesh.surface_get_format()` returns a BitField, so `&` on it has no static type for `:=`. Typed it explicitly as int.

- 2026-10-07: **Burrowing worm (Terraria Eater of Worlds / Devourer style), first version.** `BurrowWorm` (scripts/enemies/burrow_worm.gd, scenes/enemy/burrow_worm.tscn), one on the first map at (25, 0, 5). No terrain is dug: it passes through floors and walls, and they hide whatever's inside them.
  - Movement (Terraria's worm AI, from how those bosses behave): only the head steers. "In the ground" = below the floor it spawned over (`_ground_y`, found by a ray down) or inside static level geometry (a physics point query) -- there it accelerates toward its goal at `acceleration` (14 m/s^2, so it overshoots and arcs round); in open air it has only `air_control` and falls under `air_gravity`, so lunges erupt, arc over and dive back. Goal: a player within `notice_range` -- tunnelling `lurk_depth` under the floor toward them while further than `breach_range`, straight at them inside it; nobody about, it wanders round home, sometimes breaching for show (`wander_breach_chance`). Never deeper than `max_depth`. Body: follow-the-leader, each segment `segment_spacing` behind the one in front.
  - Look: the tape worm is flat, so each segment is `slices_per_segment` (3) tape worms fanned round the body axis 60 degrees apart, stretched to overlap the next segment (`slice_overlap`), thickened (`slice_thickness`), each segment twisted `twist_per_segment` more than the last so the ridges spiral -- a round, ribbed tube from any angle. Radius tapers `head_radius` -> `tail_radius`. The head's maw is the barnacle model, mouth forward. Model orientation is measured at runtime from the meshes' bounds (like the leech).
  - Effects: breaching in or out of a surface = dirt hole decal, dirt bursts, a sound, camera shake within `shake_range`; body segments crossing the floor puff dirt; tunnelling under the floor kicks up a dirt trail above the head and rumbles the camera of anyone within `rumble_range`.
  - Combat: every segment is an AnimatableBody3D hitbox with its own Health that forwards to the worm's one Health (800). One explosion catching several segments counts the worst-hit fully plus `multi_hit_share` (0.35) of the rest. Touching any above-ground segment hurts (head bite 20, body 6, per player every `contact_interval`) and throws you (`knockback`); players pass through it. Dies from the head down, a blood burst and splat per segment. Not in any Factions group yet (nothing else fights it); it only hunts players.
  - Rule 1: host moves it and deals damage; segment positions aren't synced yet (same as the other creatures). Untested at time of writing.

- 2026-10-07: **Worm boss: cinematic leaps, fixes, escorts; Deepmaw defenders.**
  - BurrowWorm attack cycle (`The Leap` exports): TUNNEL to the spot `leap_lead` (3 m) short of its prey along its approach, WINDUP (`windup_time` 1.1 s: sinks to `dive_depth` under it while the ground there shakes harder and kicks up dirt -- the warning), RISE (shoots up at `rise_speed`), AIR (erupts on exactly the ballistic arc that peaks `leap_height` 9 m over the prey: up at sqrt(2 g h), across at the gap / time-to-top; no control, the whole body pours out after it; `eruption_shake`), DIVE (back in, on down and round for `dive_time`), and again. `hop_chance` 0.25: a 3.5 m skimming hop instead. Wandering with no prey as before. Speed +15%: `max_speed` 11 -> 12.65, `acceleration` 14 -> 16.1.
  - Fixed: "_bounds_of(): !is_inside_tree()" -- the segment is now added to the tree before its maw is measured. Too many digging noises and lag: the head grazing the floor line flipped in/out every frame and fired the full breach effects (sound, decal, bursts) each time -- now at most every `breach_fx_cooldown` 0.6 s; the tunnel trail no longer drops decals (bursts only) and only while tunnelling; body crossings puff every 4th segment; the 60 tape-worm slices don't cast shadows.
  - Escorts: `escort_count` 3 Deepmaws spawn with it (host) with `guard_node` = the worm -- their home follows the floor under its head (`BurrowWorm.ground_position()`), so they swim along with it and come up at anyone near it.
  - `Deepmaw` (scripts/enemies/deepmaw.gd + deepmaw_bend.gd, scenes/enemy/deepmaw.tscn; the DEEPMAW retro PSX model): one worm, no segments. Digs like the boss (in ground: steering with limited acceleration; in air: gravity), lurks `lurk_depth` under home circling, hunts a player within `guard_range` of home (gives up at 1.5x): tunnels under them, within `breach_range` lunges up through the floor ("jump attack" clip), bites within `bite_reach` ("BITE"; 18 dmg + knockback). Its own spine bones (Bone -> ... -> Bone.010) are bent along the path its head swam each frame by DeepmawBend (a SkeletonModifier3D, after the animation -- jaws still animate): each bone turned from rest to point at the next joint down the path, rolled to keep its belly down, plus a swimming wave (`wiggle`). Sized to `body_length` 5 m. Hitboxes: `hitbox_count` spheres along the body on one AnimatableBody3D. Body material tinted (0.78, 0.48, 0.37) so its texture averages the leech/tape-worm colour (measured: tape_worm.png avg (0.18, 0.10, 0.06), cuerpo gusano.png (0.23, 0.21, 0.16)). Dies: "dead" clip, falls if airborne, sinks away after `corpse_time`.
  - Barnacle defenders: `BarnacleCluster.defender_count` 1 Deepmaw per clump (`defender_scene`), on the floor under it (wall/ceiling clumps: the floor below). Leeches stay off.
  - Optimisation: a Deepmaw entirely under the floor isn't drawn or bent; its spine bends every frame within `bend_full_distance` 25 m, every 4th to `bend_cull_distance` 70 m, not at all beyond; lurking with no player within 2x guard_range it thinks every 3rd physics tick; no shadows. Co-op: all of this is host-only AI (Rule 1) with the visuals driven from a few numbers per creature (head position + velocity -> path), so syncing them later is cheap -- note the project has no network replication of creatures yet (no MultiplayerSynchronizer/RPCs anywhere); that's its own task.
  - Untested at time of writing.

- 2026-10-07: **Worm boss mission: "The Thing Beneath".** missions/worm_boss.tres (order 3, in Grandma's list) -> scenes/worm_boss_level.tscn: a copy of the first map (inherits test_map.tscn, like the Swarm King's), Grandma hidden, the BurrowWorm at (0, 0, -25) with its 3 Deepmaw escorts. Barnacle nests (and their Deepmaw defenders, spat roaches/spiders, the random BarnacleScatter nests) are kept as they are. Every other creature is cut 70% by a `SpawnThinner` node (scripts/missions/spawn_thinner.gd, `keep_share` 0.3): placed tweakers/roaches/rats/spiders/deepmaws keep round(30%) of each kind, evenly spread through the map (by node order, so the same ones on every co-op player's game); rat nests' rat/bodyguard counts and spider packs' start counts x0.3. It works in _enter_tree as the level's last child (before any of the level's nodes is ready, so nests and packs spawn the reduced numbers). The BurrowWorm is no longer on the first map itself -- it's this mission's boss. Untested at time of writing.

- 2026-10-07: **Worm effects (boss + Deepmaws), kept cheap.** New `WormFX` (scripts/fx/worm_fx.gd), one per worm:
  - Dirt mound: one flattened low-poly sphere ploughing along the floor over the head while it tunnels shallow (bigger the shallower; boss within lurk_depth + 2 m, Deepmaws only while hunting).
  - Ground cracks (shaders/worm_cracks.gdshader): procedural jagged cracks + dark pit + pulsing hot glow on one quad, growing through the boss's wind-up at the eruption spot, fading 2.5 s after it erupts. `grow`/`fade` are per-instance shader uniforms, so one shared material.
  - Dust + rubble on every breach: slow billowing dust puffs (soft radial GradientTexture2D, 10 particles, 2.8 s; two emitters used in turn so a dive doesn't cut off the eruption's cloud) and 14 tumbling rubble chunks (1.6 s, fall back into the floor -- no particle collision).
  - Rumble: a looping AudioStreamPlayer3D at the head while underground (Deepmaws: only while hunting), 3D falloff = louder up close. Placeholder generated procedurally: audio/sfx/worm_rumble.wav (4 s seamless loop: low-passed brown noise + a wobbling 38 Hz tone, slow swells). Swap via `rumble_stream` on BurrowWorm/Deepmaw; `rumble_volume_db`.
  - Wet flesh (shaders/worm_flesh.gdshader) on the boss's tape-worm skin and the Deepmaw body (tint kept): per-vertex lit like ps1.gdshader, low roughness + rim sheen, the texture's dark grooves glowing blood red in pulsing waves. One material per worm type.
  - Peristalsis (BurrowWorm `bulge_amount` / `bulge_speed` / `bulge_spacing`): swallowing bulges rolling down the body -- each segment's visual scaled up across (not along) as the wave passes.
  - Optimisation: all meshes/materials/particle setups are static and shared by every worm; a worm's emitters are only made the first time it breaks the surface; nothing new casts shadows; no new raycasts. Visual only (every peer can run it from the worm's position). Untested at time of writing.

- 2026-10-07: **Worm feedback pass.**
  - Boss skin back to its original look (plain tape-worm StandardMaterial); the wet-flesh shader is removed (shaders/worm_flesh.gdshader deleted). Peristalsis kept.
  - Boss leaps INTO the player now: it erupts `leap_lead` 0.8 m short of where they'll be (`aim_ahead` 0.35 s of their velocity), so it comes up through them, and arcs `leap_height` high to land `land_beyond` 6 m past them; it keeps re-aiming while rising.
  - Landing shockwave (`Shockwave` exports): every landing from a leap sends a ring of dust tearing out to `shockwave_radius` 9 m (WormFX.shockwave(): one pooled torus, scaled out + faded with GeometryInstance3D.transparency, plus a dust/rubble burst) and throws everything in it -- players and spiders via shove(), enemies via the new `Enemy.shove()`, rats/roaches/props as RigidBody impulses (+ stun()), corpses' physical bones -- out `shockwave_force` 14 and up `shockwave_lift` 6, scaled by distance, plus `shockwave_damage` 10 (scaled). Its own escort Deepmaws are skipped. Grandma is a StaticBody (can't be thrown). Host-only physics query (one sphere query per landing).
  - `Enemy.shove(push)`: throws a tweaker (horizontal speed overrules its walking until it slides to a stop: 18 m/s² on the floor, 5 in the air; vertical added to its velocity).
  - Deepmaws: body material twice as dark (tint 0.78/0.48/0.37 -> 0.39/0.24/0.185, a dark brown). They "flopped" and had no direction: the model never moved itself (only the spine bend was meant to place it), and their lunge was a soft steer-up-and-fall. Now the whole model is placed every tick nose-first along its velocity (`_place_model()`: its rest pose's nose-to-tail line turned onto the direction of travel, head on the head), the spine bend on top; and they attack with the boss's leap cycle, smaller (`Leap` exports: `leap_height` 4.5, `leap_lead` 0.6, `land_beyond` 4, `windup_time` 0.5 with small ground cracks, `rise_speed` 16, `dive_time` 1). `breach_range` and `air_control` are gone.
  - Untested at time of writing.

- 2026-10-07: **More worm effects** (boss + Deepmaws), all rate-limited:
  - Cracks judder and throb faster as the eruption nears (worm_cracks.gdshader: UV jitter ∝ grow², glow pulse 8 -> 30 Hz with grow; `shake` uniform).
  - Tremors (`WormFX.tremor()`, every ~0.4 s while it's under the floor near the surface -- boss always, Deepmaws while hunting): one ray straight up from the floor above it; a ceiling/overhang there sheds dust and a drop of pebbles (one pooled emitter); and (host) loose physics props within 3.5 m get a small random hop (one sphere query; creatures and frozen bodies skipped).
  - Camera punch (`WormFX.punch()`, CameraJuice.kick_fov, subtle): boss eruption 8, boss landing 5, Deepmaw eruption 4, fading with distance. The rumble loop's 3D falloff already makes it louder as it nears.
  - Jaws: drool dripping (every ~0.3 s) while out of the ground; a bite sprays gore and spit (blood + a pale spit burst) along the bite; while flying, clods of dirt shed off random points along the body (every 0.12 s). All through BloodFX's capped bursts.
  - Untested at time of writing.

- 2026-10-07: **Worm boss: spider brood at the top of its leaps** (`Spider Brood` exports). On a big leap (not a skimming hop; `brood_chance` 1.0), once it stops rising it hangs at the top for `apex_hang` 0.6 s (gravity x `apex_gravity` 0.15, sideways speed bleeding off) -- a camera shake, then a swelling (`brood_bulge` 0.7 fatter, a smooth eased Gaussian bump on top of the peristalsis) rolls from behind its head to its tail, and `brood_count` 6 spiders tear out one after another as it passes their segments (spread evenly down the body): each flung out sideways (a random way round the body) and up at `brood_speed` 7 in a spray of blood with a wet crunch, falling and grabbing onto whatever they hit. Then it drops and lands (shockwave as usual -- its brood and escorts are spared). The spiders join one SpiderPack of the worm's own (made on the first burst, kept for later leaps), capped by Population like all spiders. Host only (spawns). Untested at time of writing.

- 2026-10-07: Jaw spit is the boss's alone: Deepmaws no longer drool, and their bites spray gore only (`WormFX.bite_spray(..., with_spit = false)`). The boss keeps its drool and spit+gore bite spray.

- 2026-10-07: **Worm leaps aim like the spitter roach; cinematic eruption; Deepmaw horde, hitboxes and arc.**
  - Erupting from right under you is reverted: both worms come up `leap_distance` away (boss 7 m, Deepmaw 4.5 m) from where they mean to land and arc down onto it. Where they land = the spitter roach's lead (FlyingRoach._spit_at, same values), shared in scripts/enemies/worm_leap.gd (`WormLeap`): your ground speed split into sideways (x PREDICTION 0.8) and toward/away (x PREDICTION_TOWARD 0.3), carried forward for the time until it comes down, AIM_PAST 0.4 m beyond you, and a per-leap guess (roll_guess(): a random share 0.4-1.3 of the lead + a random sideways step up to 1.2 m across your travel). Planned while tunnelling/winding up (time = time until it erupts + air time) and re-made at the eruption. `leap_lead` / `aim_ahead` / `land_beyond` are gone.
  - Smooth mid-air re-aim (`air_steer` boss 5, Deepmaw 6 m/s²): every tick in the air the guess is re-made with the actual time left (WormLeap.steer_toward()) and the sideways velocity eased toward it -- easing in over `steer_ramp` (boss 0.6 s, Deepmaw 0.5 s, smoothstep) after it leaves the ground. The arc stays a simple arc (no dive-bombing): the brood hang no longer bleeds off sideways speed or re-aims the fall.
  - Boss eruption: the rumble swells up to `windup_rumble_boost` +10 dB through the wind-up; out it comes in a column of dirt (`WormFX.eruption()`: two dust/rubble bursts + three dirt bursts climbing the column), a camera punch of 9 and a roar (`roar_sound`: new audio/events/enemy/worm_roar.tres -- the rusher's attack clips at pitch 0.45, +6 dB, unit_size 30; swap for a real roar when you have one).
  - Deepmaws leap as a horde: the first in position for what they guard calls a volley `volley_gather` 1.2 s out (a static map: guarded thing -> volley time), others that get there in time hold their wind-up for it, and they all go together -- each with its own guess, sideways spread `guess_spread` 1.8x wider, so they cover where you might run. Their body now turns to a new heading gradually (`turn_rate` 5, exponential).
  - Deepmaws couldn't be shot: their hitbox body had no Health of its own (shots look for one on the collider). It now has a proxy Health forwarding to the worm's (with a blood spurt); hitboxes bigger and more (`hitbox_count` 7, `hitbox_radius` 0.11 of its length).
  - Deepmaw body arc: the spine bend now runs in the Deepmaw's own _process with process_priority 100 (after its AnimationPlayer), setting the bones directly -- the SkeletonModifier3D route (DeepmawBend, deleted) wasn't reliably bending it.
  - Deepmaws no longer defend barnacle clumps (`BarnacleCluster.defender_count` 0); they escort the worm boss only.
  - Untested at time of writing.

- 2026-10-07: Worm tuning: boss 15% bigger (`segment_spacing` 0.75 -> 0.8625, `head_radius` 0.75 -> 0.8625, `tail_radius` 0.3 -> 0.345); leaps 40% higher (boss `leap_height` 9 -> 12.6, `hop_height` 3.5 -> 4.9; Deepmaw `leap_height` 4.5 -> 6.3 -- the aim works out the longer air time itself); the boss's drool twice as big and half again as often (strength x2, every ~0.2 s instead of ~0.3).

- 2026-10-07: Worm boss brood 6 -> 30 spiders per big leap (`brood_count`): several burst from each segment as the swelling passes (spread from just behind the head to the tail). Population.MAX_SPIDERS is 40, so a second leap culls the oldest spiders to make room.

- 2026-10-07: **Worms breach from further away; no cracks; spider cap 60; faster Deepmaw leaps.**
  - The worms sometimes followed the player around underground: their eruption spot was re-worked out every tick a fixed distance from a moving guess, so they chased it and never arrived. Now they tunnel toward where they mean to land and breach from wherever they are once they're within `leap_distance` of it (boss 16 m, Deepmaw 11 m) -- or after `tunnel_timeout` (boss 4 s, Deepmaw 3 s), wherever they've got to. The spot is locked when the wind-up starts. The arc and the spitter-roach aim (WormLeap) are unchanged: longer leaps just cover more ground.
  - The ground-crack effect is gone (worm_cracks.gdshader deleted, WormFX crack code removed). The boss's wind-up keeps its dirt bursts, shaking and rumble swell.
  - Population.MAX_SPIDERS 40 -> 60.
  - Deepmaws faster in the air: their own `air_gravity` 16 -> 28 (same 6.3 m peak, ~1.3x quicker leaps, faster across; the boss keeps 16).
  - Untested at time of writing.

- 2026-10-07: **Deepmaw Crawlers: surface deepmaws guarding the barnacles in packs.** `DeepmawCrawler` (scripts/enemies/deepmaw_crawler.gd, scenes/enemy/deepmaw_crawler.tscn): the DEEPMAW model as a CharacterBody3D that doesn't burrow, half the escorts' length (`body_length` 2.5), on the model's own animations: "Glide" to slither (speed-scaled with its pace), "BITE" at a target in front of its jaws within `bite_range` (14 dmg), "TAIL ATTACK" at one by its tail within `tail_range` (10 dmg) -- the hit lands `hit_delay` into the clip, knockback via shove() -- "hit reaction" when shot, "dead" on death. Death: the dying clip plays out, then it swells in three throbs (`swell_amount` 0.45 over `swell_time`) and bursts in a blood explosion (three bursts down its length, `death_gore`, a `swell_splat` splat, a wet crunch). Model oriented/sized/belly-on-floor from its bones at spawn; hitbox a capsule along its body, a little fat for easy shooting; animation paused past `animate_distance`; no shadows. Same dark-brown tint as the escorts. Health 60.
  - `DeepmawPack` (scripts/enemies/deepmaw_pack.gd, scenes/enemy/deepmaw_pack.tscn): the rats' pack behaviour (RatSwarm) for crawlers -- slots that ebb and drift, weave, separation, stop-start bursts, patrol round home (`roam_radius` 6), notice a player they can see within `notice_range` 12 on their ground (`guard_range` 18 from home), creep then charge (`charge_range`), close in a darting/churning ring at about bite distance; shooting one sets the pack on the shooter (if on its ground); they drop anyone who leaves their ground. Players only.
  - BarnacleCluster grows one under each clump: `guard_pack_scene`, `guard_count` 4 (on the floor below a wall/ceiling clump). The burrowing Deepmaws stay boss escorts only.
  - Untested at time of writing.

- 2026-10-07: **Worm boss body baked into one draw call.** The body was 3 tape-worm copies per segment = 60 separate meshes (60 draw calls every frame; they were only built once at spawn, but the GPU still drew 60). Now one segment mesh (the slices merged: positions, normals, UVs) is baked and stamped once per segment by a MultiMeshInstance3D (`BurrowWorm._build_body()`), each copy placed / twisted (`twist_per_segment`) / sized (radius taper) / swollen (peristalsis, brood) per tick by `set_instance_transform()` -- 1 draw call. The baked segment is cached (static, shared by every worm) and, when run from the editor, saved to art/worm_boss/worm_segment_mesh.res (re-baked automatically if `slices_per_segment` / `slice_overlap` / `slice_thickness` / `segment_spacing` change -- stored as a "bake_key" meta) so it's a real file you can open, and later runs skip the baking. Hitboxes (one sphere per segment) and the head's barnacle maw are unchanged. HitFlash now also flashes MultiMeshInstance3Ds (the whole body flashes on a hit). Untested at time of writing.

- 2026-10-07: Fixed Deepmaw Crawlers drawn floating high above their hitboxes (you took damage from "nothing"): the model was lifted by its mesh AABB's lowest point, but on the skinned DEEPMAW FBX the mesh's own box isn't in the units it's drawn in. Now its spine (head-to-tail bones, centred on the body) rides `belly_height` (0.08 of its length) above the floor.

- 2026-10-07: Deepmaws (burrowing escorts and crawlers) now the barnacles' colour: body tint (1.88, 0.83, 0.61) -- the barnacle texture's average (0.43, 0.18, 0.10) over the DEEPMAW body texture's (0.23, 0.21, 0.16), so the worm's texture averages out to the barnacle's reddish flesh (tint values above 1 brighten; the material multiplies). Replaces the dark-brown tint.

- 2026-10-07: Deepmaw Crawlers shelved: `BarnacleCluster.guard_count` 4 -> 0, so clumps grow no crawler packs. deepmaw_crawler.gd/.tscn and deepmaw_pack.gd/.tscn are kept for later; set guard_count back above 0 to bring them back.

- 2026-10-07: Deepmaw escorts back to their dark-brown tint (0.39, 0.24, 0.185); the barnacle-colour tint stays only on the (shelved) crawlers.

- 2026-10-07: Deepmaw escorts 30% faster (`max_speed` 9 -> 11.7, `acceleration` 16 -> 20.8, `rise_speed` 16 -> 20.8) so they actually reach the player, and a volley now breaches one after another: the first at the volley time, each next one `breach_stagger` (0.5 s) later, in the order they joined.

- 2026-10-07: Deepmaw escorts 20% slower in the air: `air_gravity` 28 -> 17.92 (28 x 0.8²: a leap of the same height takes 1.25x as long, and the sideways speed -- distance / air time -- drops 20% with it). Same peak height and aim.

- 2026-10-07: Deepmaw escorts breach 1 s apart in a volley (`breach_stagger` 0.5 -> 1.0).

- 2026-10-08: **"Torso flashing up" on heals/throws, found and fixed** (checked frame by frame with screenshots, including from a side camera). There were two causes. The torso itself was already cut away.
  - A one-frame T-pose. Every swap builds a fresh arms model. Its first frame was drawn in the rest T-pose, before the hold animation landed, so the right sleeve stuck out across the bottom of the screen. New arms now stay hidden for `ARMS_REVEAL_FRAMES` (2) frames. The arms are made at the moment the gun is out of view, so nothing is missed.
  - The sleeve swinging in. The throw tipped the whole view rig up to 40 degrees round your EYE, and the shoulder and sleeve (just beside and below the camera) swung forward into view. Throws and heals now turn round the arms model's right shoulder joint (`Viewmodel.throw_from_shoulder`, on). A new `_swing_pivot` node between the Viewmodel and `_sway_pivot` is shifted by B⁻¹·P − P (B = the Viewmodel's turn, P = the shoulder), so the same tweens turn round P. It's applied in NOTIFICATION_LOCAL_TRANSFORM_CHANGED, so it holds every frame of every tween. It's switched on/off only while there's no tilt or the arm is out of view. Switches, reloads and the pump rack still turn round the eye.
  - Verified with captures, not yet in normal play.

- 2026-10-08: **Viewmodel arms done the Half-Life 2 way: one persistent arms model, the gun in the hand.**
  - The arms are built once (`Viewmodel._ensure_arms()`) and kept, like HL2's c_arms. Before, every switch, Q throw and heal loaded the character FBX again, set up its animator and re-cut its mesh. A switch now plays the weapon's hold pose on the same AnimationPlayer (one animation per hold_animation in an "fp" library), swaps between the cached both-arms / right-arm cut meshes when `hide_left_arm` changes, and moves the arms to the weapon's `arms_position/rotation/scale` (`_pose_arms()`).
  - The gun/item hangs off a BoneAttachment3D on the arms' RightHand bone, so anything that moves the hand carries it (ready for real animations later). Each gun model is built the first time it's shown and kept hidden after (`_gun_models`), so a swap builds nothing. Measured swap cost: 0.03-0.2 ms.
  - The weapon data means the same as before. `viewmodel_position/rotation/scale` = where the item sits on screen (camera space) and `arms_*` = where the arms sit. The model's spot under the hand is worked out from those (`_apply_transform()`: hand-in-rig⁻¹ x item rest), so every existing tuning looks identical (checked in screenshots: pistol, shotgun, sniper, PPSh, RPG, grenade, heal, throw).
  - Node chain: Viewmodel (switch/throw tweens) -> _swing_pivot (shoulder pivot) -> _sway_pivot (sway, ADS) -> _kick_pivot (fire kick, NEW: `_kick_back`/`_kick_pitch` tweened, `_apply_kick()` = the old gun-only kick as a move of the whole rig) -> arms -> skeleton -> hand attachment -> _model -> gun.
  - F2 tool: arrows still move the item (now: the item in the hand). **H now moves the arms with the item staying in the hand** (its viewmodel_* numbers are re-worked out as it goes), so you line the item up in the hand once, then place the whole thing on screen with H. I previews the aimed pose by shifting the whole viewmodel (`_preview_offset`). F3 saves as before.
  - Character change rebuilds the arms and the gun models (`_free_arms()`).

- 2026-10-08: **Pills and bandages use Left 4 Dead 2's pills animation (placeholder)** in place of the grenade throw (`Viewmodel._on_item_used()`). The hand brings the item up to just under your mouth (`ITEM_MOUTH_POINT` (0, -0.13, -0.24), camera space) while tipping it back. At the top it tips right back (`ITEM_TIP_DEGREES` 40) and shakes it out `ITEM_SHAKES` 2 times (`ITEM_SHAKE_DEGREES` 14, `ITEM_SHAKE_LIFT` 0.015 m). Then it drops out of view and the gun (or the next item) comes back. The heal lands as it starts down. The tips turn round the item itself: the shoulder pivot became a general `_set_pivot(point)` (`_set_shoulder_pivot()` still does throws). `pills_use_time` 0.25 -> 0.8 s and `bandage_use_time` 0.25 -> 1.0 s (WeaponController exports), so there's time to raise, tip and shake.

- 2026-10-08: F2 tool: **U** holds an equipped healing item up at your mouth (the heal animation's top pose) so it can be lined up there.

- 2026-10-08: **Worm boss: the Plough attack, the Blood Puke, a deadlier shockwave, aimed brood, bigger drool.** (BurrowWorm)
  - Attacks: each attack is a Plough (`plough_chance` 0.55) or a Leap (0.45), never the same three times running (`_roll_plough()`).
  - **The Plough** (new export group): the first version's way of hunting, as its own move. It tunnels toward you, surfaces within `plough_start_range` 18 m and ploughs at you half buried for `plough_time` 5 s. Its middle rides the floor line (`plough_height` 0), it turns at most `plough_turn_degrees` 100/s at `plough_speed` 11 (so it swings past and comes round), and it weaves ±`plough_weave_degrees` 25. The furrow: dirt thrown out both sides of the head, a dark dirt mark every few, dust and rubble bursts with a crunch, and the ground shaking. Anything in its way (not players: its bite and body handle them; not its escorts) is thrown aside (`plough_push` 9 + `plough_lift` 4) and takes `plough_damage` 25, each at most once a second. Bodies lying there are thrown as one piece. Then it dives and goes again.
  - **A big leap does the Blood Puke (`puke_chance` 0.5) or the spider brood.** Puke: at the top of the arc it stops dead. Through `puke_turn_time` 0.5 s a swelling rolls up its body to the head, it rears back and turns its head onto you, and blood dribbles from its jaws. Then it heaves forward and retches `puke_globs` 12 red AcidSpit globs over `puke_spray_time` 0.3 s (`puke_damage` 8 each). Each glob is aimed with the spitter roach's prediction (its own WormLeap guess, refined against flight time like FlyingRoach._spit_at()) and scattered up to `puke_spread` 2.5 m. Then it carries on down its arc.
  - **Brood moved to just past the top:** it bursts once the head has come back down `brood_after_peak` 0.2 of the arc's height (i.e. at 80% of the peak, on the way down; `_air_peak` tracks the top), over `brood_time` 0.35 s. Each spider is thrown at you: WormLeap's guess at where you'll be, scattered up to `brood_spread` 3 m, on the arc that lands in about `brood_flight` 1.3 s. The brood pack is set on you as it spawns (hunting straight away). `apex_hang`/`apex_gravity` are gone. `SpiderPack.spawn_spiders()` gained `launch_spread` (0 = an exact aimed throw).
  - **Shockwave:** players are thrown and take `shockwave_damage` 10 -> 20. Everything else in the ring now dies and is thrown as a ragdoll (`Explosion.launch_ragdolls()`, made public; the RPG's throw). Its Deepmaw escorts are spared, and its brood while `shockwave_spares_brood` (they land right in it).
  - Damage: `bite_damage` 20 -> 80 (the head), `contact_damage` 6 -> 40 (the body).
  - Drool: comes off the outside of the lower lip of the maw (`_lower_lip()`), no longer from inside the head. WormFX.drool() is heavier: bigger drips spread along the lip, and now and then a big glob stringing down.
  - Untested at time of writing (not run).

- 2026-10-08: **The Harvestman: a 10 m three-legged sewer stilt-walker (Strider-style), four kinds, and its own mission.**
  - Model scenes, made once and editable: `tools/bake_harvestmen.gd` (`godot --headless --path . --script res://tools/bake_harvestmen.gd [-- force]`) runs `HarvestmanBuilder` and saves `scenes/enemy/harvestman/models/harvestman_{barnacle,deepmaw,fused,leech}_model.tscn`. An existing file is skipped unless you pass "force", so edits made in the editor are safe. Layout: Body > Core (HarvestmanCore) / Face (the unrigged PSX spider, glowing Eyes, Searchlight SpotLight3D, Mouth marker) / Limbs (JiggleLimbs) / Legs/Leg0-2 (hip nodes). Every model's pose is reset to rest so the bone maths matches what's drawn. Hips and limbs sit on the core's real surface (`_surface_points()`, works for any shape), sunk in a little.
  - Cores: BARNACLE (an upside-down tinted barnacle), DEEPMAW (a Deepmaw coiled into a ball: the coil is written into its skeleton's rest pose, and it writhes in game), FUSED (5 civilian torsos round a fleshy middle). All breathe.
  - Legs: the enemy spider's back leg (Spider.fbx "BL" chain) cut out with the new `MeshCut` (scripts/util/mesh_cut.gd: keep a bone subtree's triangles; `thin` pulls vertices toward the bone line), stretched to ~11 m and slimmed. Or (the leech kind) tape-worm segments drawn along the IK every frame (one MultiMesh), with barnacle knees.
  - Limbs: 3-4 civilian arms/legs (`JiggleLimb`, MeshCut) on jiggle bones (spring + gravity + damping per joint, HL2 $jigglebone style), swinging with the body's motion. Decoration; `can_grab` reserved for a grab attack later.
  - `Harvestman` (scripts/enemies/harvestman.gd): FABRIK legs starting from an up-and-out arch (knees high). One step at a time round the legs, the foot lifting high and coming straight down soft (tiptoe), quiet wet step sound, `slip_chance` lurches, squashes creatures under a foot. The body rides a slow spring and the sack lags behind. It sees through a sweeping searchlight cone (`sight_range` 40, 70 degrees), feels anyone within `feel_range` 9, honks a horn on spotting, searches when it loses you, patrols and listens.
  - Attacks: Skewer (a leg rears up, trembles, stabs where you'll be: 70, kills creatures), Slam (rise, drop the sack: shockwave 35 to players; exposed for 3 s with sack damage x3), Sewage hose (brown spitter-spit sweep with the roach's prediction, leaves SewagePuddles burning 5/0.5 s), Brood drop (roaches pour out; 22 s cooldown). Feeding: drags a corpse up to its face on a tube (EnemyRagdoll.carry) and eats it (+200).
  - Health 1500. Weak spots with an artery gush: sack x2 and knees x1.5 (a knee breaks at 220: the leg drags; two broken and it collapses and crawls). Leg shafts x0.5. Death: legs give one by one, it comes down, the sack bursts.
  - Drone loop (worm rumble pitched up) that rises when hunting; within `horror_range` 8 it warps down and the camera sways. Sounds: audio/events/enemy/harvestman_step.tres, harvestman_horn.tres.
  - Mission "Stilts in the Dark" (missions/harvestmen.tres, order 4) -> scenes/harvestman_level.tscn: the first map, Grandma hidden, creatures thinned to 15% (SpawnThinner), barnacle nests kept, one of each Harvestman.
  - First run: patrol, spot, skewer and slam all worked. Leg/limb attachment fixed after (rest-pose reset, surface placement) but not re-run.

- 2026-10-08: **Harvestman brood drop: twice the roaches, twice the drama.** `brood_count` 3 -> 6. The wind-up is twice as long (`brood_windup` 1.2 s, was 0.6 of nothing). The sack swells up to `brood_swell` 0.35 fatter (HarvestmanCore's new `swell`, on top of its breathing), throbbing faster and faster (6 -> 26 Hz), the body shuddering harder and blood dripping out of it more and more. Then the split: six gushes round its bottom plus a big one straight down, five blood pools splashed onto the floor below, camera shake 6 (30 m) + punch, splat/hurt/gush sounds, an artery spurt still pouring from the split for 2 s, and the roaches flung out evenly all round at 6-9 m/s. Tested: swell built to 0.34, six roaches out.

- 2026-10-08: **Harvestman: rushing into a wall stuns it.** A rush is now only stopped by a wall once the sack itself meets it (`_move_forward(..., reach = sack_radius + 0.6)`; walking still turns off early). Then `_crash()`: it's thrown back off the wall (`crash_recoil` 5 m/s into the body spring), drops (height kick), twists a little, and every planted foot skids outward. Dust/grime bursts and blood come off the wall, with a camera shake 6 (28 m) + punch and crunch sounds. It goes into the new STUNNED state for `stun_time` 7 s: sagging `stun_sag` 2 m lower, a drunken wobble, heads hanging and lolling, the searchlight stuttering, no moving or attacking (the proboscis retracts), and its sack exposed (x3) for the whole stun. Seeing or being shot doesn't wake it. After that it `_recover()`s: back to hunting with a horn, or searching. Tested: rush, crash at 2.75 s, stunned 7 s, recovered.

- 2026-10-08: **Harvestman: the Rush, heavy footsteps, fewer sprays, double-sided core.**
  - Rush (new attack, "Rush" exports; the Antlion Guard's charge): when you're past `rush_min_range` 16 m (`rush_chance` 0.5 while still in hose range, always beyond it). It rears up with a horn blast for `rush_windup` 0.6 s (the tell), then sprints at `rush_speed` 9 m/s leaning forward, turning at most `rush_turn_speed` 0.6 rad/s (sidestep it). Its gait scrambles: `rush_step_time` 0.32 s steps, two legs at once, low lift. On reaching you, hitting a wall or after `rush_max_time` 5 s, it goes straight into the slam's drop, sliding on (`_rush_slide`). Tested: from 29 m it covered the gap in ~4.5 s and slammed. Attacks now move it themselves (`_move_forward()`); the walk no longer runs during attacks.
  - Slam: a wall between it and something stops the shockwave reaching it.
  - Hose: `hose_chance` 0.7 -> 0.35, and at most `hose_max_in_a_row` 2 sprays in a row (`_hose_streak`; any other attack resets it).
  - Footsteps are heavy now (the user's call; the quiet tiptoe didn't fit): harvestman_step.tres = the heavy body-drop thuds at pitch 0.55, +4 dB, unit size 14. A dust puff at each foot, and a subtle camera shake (`step_shake` 1.2 right by the foot, fading to nothing at `step_shake_range` 22; the slam's is 7).
  - The core's meshes are made double-sided on spawn (`_double_sided_core()`): the barnacles are hollow cups, and once the heads twist you can see into them, where one-sided faces aren't drawn (parts of the core seemed to vanish).

- 2026-10-08: **Harvestman: barnacle heads, a 10.5 m proboscis, longer spray.** (`barnacle_heads`, on)
  - The core's barnacles (Core/Barnacle*) are its heads. The one hanging mouth-down is THE head: a Maw node is made at the end of its mouth, and the searchlight (reparented from the spider face, which is hidden) and the proboscis come out of it. Every barnacle turns round its own origin (its root, where it grows from the body) to point its mouth (+Y) where it looks: the head up to `head_turn_limit` 75 degrees, the others (no light, no tube) up to `crown_turn_limit` 50, eased (`head_turn_speed`). It sees from the maw. With no mouth-down barnacle it falls back to the spider face.
  - Proboscis (new group): out of the maw along the mouth, `proboscis_length` 10.5 (was 3.5), sliding out at `proboscis_extend_speed` 6 m/s while it has a target (never past them) or is feeding (reaching for the body), and back in at `proboscis_retract_speed` 2 m/s when it hasn't. 16 tape-worm segments, sagging and writhing. The hose sprays from its tip.
  - Hose: `hose_time` 1.8 -> 3.6 s with `hose_globs` 14 -> 28 (same density), and `hose_chance` 0.5 -> 0.7 so it's actually seen.
  - Hunting, the light's cone narrows to `hunt_angle_scale` 0.5 of `light_angle` (pointing across at you, its patch stretched far too wide); the beam follows the cone.
  - The editor had saved every Harvestman export as `null` in scenes/harvestman_level.tscn (it loaded harvestman.gd mid-edit, while it couldn't compile). Those 128 lines were removed. If it happens again: close/reopen the scene after the script is fixed, or delete the `= null` lines.

- 2026-10-08: **Harvestman: leech-legs only for now, fits itself to any core, red searchlight with a visible beam.**
  - The mission spawns only the leech-leg Harvestman (the user's favourite). The barnacle/deepmaw/fused scenes stay for later.
  - New "Model" exports. `center_core`: on spawn, the body's parts shift so the core's measured middle (`HarvestmanBuilder.surface_points()`, now public) is the body's middle, and the sack hitbox is sized to it. `fit_legs_to_core`: each Leg node's hip goes back onto the core's surface at its own angle. So any core built in the editor works without hand-fitting. `show_limbs` / `show_knees` (both off): the dangling civilian arms and the leech legs' barnacle knees are left out (still in the model scenes).
  - "Searchlight" exports: red (`light_color`), `light_energy` 9, `light_range` 45, `light_angle` 22, applied over the model's light. A faint additive cone (`beam_strength` 0.09) shows the beam in the air, from the eyes down to wherever the light lands (one ray every 0.1 s). Always on while alive, following the eyes.

- 2026-10-08: **Worm dirt: a real churned-dirt mound, a furrow trail, clods and dust** (WormFX, both worm kinds). Replaces the flattened sphere.
  - `shaders/worm_dirt.gdshader` on a 16 x 16 plane. Per copy (MultiMesh custom data): height, seed, churn, shape (0 mound / 1 furrow). The mound is a dome peaking a little forward with a steeper front: a bow wave of dirt pushed ahead. The furrow is two loose ridges either side of a darker trough. Lumps come from 2-octave noise in WORLD space, so the ground heaves up and falls back as the mound passes rather than a bump sliding over it; the moving mound's lumps churn (`churn_speed`). Texture: trenchbroom/textures/Dirt_03 (dark loose soil), world-mapped. Shaded darker in dips and down the trough. The outline is clumpy, cut with alpha scissor (no transparency sorting), and the rest of the plane sinks under the floor. PS1 look as ps1.gdshader: per-vertex lighting and screen-space vertex snap.
  - One MultiMeshInstance3D per worm = one draw call: instance 0 is the mound, 1..`FURROW_COUNT` (40) are furrow patches laid behind it every `FURROW_SPACING` (1.2) of its thickness. Each patch settles flat over the second half of `FURROW_LIFE` (7 s) and narrows away at the end (ring buffer, oldest reused).
  - It shows while tunnelling within max depth of the floor, and while ploughing (the boss passes `underground` during The Plough). Coming up through the floor line the mound sinks back around the worm, so it doesn't bury its head.
  - Streams while the mound shows: dirt-textured clods thrown up and outward off its sides (18 alive), and a low dust haze (6). Emitters are made once per worm and toggled.
  - Untested at time of writing (not run).

- 2026-10-08: **Bandages switched off for now; pills are the only healing.** `WeaponController.BANDAGES_ENABLED` (false): `add_item()` won't take bandages, and bandage ItemPickups remove themselves when the level loads, so you never carry any and B does nothing. Set it true to bring them back. HUD: the bottom-centre pills/bandages line is gone. The pill count is now on the top-left weapon line like the grenades (`[T] Pills: N`, while you carry any, unless the pills slot is in hand).

- 2026-10-09: **Tentacle grapple on E** (`scripts/player_grapple.gd` PlayerGrapple, a node on the Player; `scripts/grapple_tentacle.gd` GrappleTentacle). Every choice below was the user's.
  - **One-handed guns only.** New `WeaponData.one_handed`, on for Pistol and PPSh: the right hand holds the gun and the left hand throws the tentacle. With anything else out, E switches to the last one-handed gun you used (`WeaponController.switch_to_one_handed()`) and starts coiling while it's drawn. Switching to a two-handed gun lets go. No grapple while busy (pills, a grenade mid-throw, a leech on your face: `WeaponController.is_busy()`).
  - **Hold E to coil, release to lash.** `charge_time` 1.5 s gives full power. Under `min_hold` 0.3 s nothing fires and no charge is spent. From 0.3 s to 1.5 s, power goes from `min_power` 20% to 100%. Range is `max_range` 35 m x power. Pull speed tops out at `pull_speed` 26 m/s and never drops below `min_speed_scale` (0.6, so a short hold still pulls faster than you run; set it to 0.2 for strictly proportional speed).
  - **Charges:** `max_charges` 2, each regrowing in `recharge_time` 3 s, one at a time. A miss (sky, out of range, or a small enemy) still spends one: the tentacle whips out and snaps back.
  - **Pull, Titanfall 2 style:** it accelerates you toward the spot (`pull_accel` 70) up to the pull speed, with no gravity (`pull_gravity_scale`) and no ground friction. You can still air-strafe, and it slows near the spot so you settle against the wall. Space lets go, adds `release_hop`, and keeps your speed. Holding E during a world pull coils the next grapple, using your second charge. Mantling or dying lets go.
  - **Big enemies** (group `PlayerGrapple.BIG_GROUP`: the Harvestman and the burrow worm) pull you to them.
    - On arrival (`kick_reach`) you kick them for `kick_damage_per_speed` x your speed (26 m/s = 104), which counts as a hit with a hit marker, and bounce off (`kick_bounce`, `kick_bounce_up`).
    - Press and hold E again after the lash and you latch on and ride instead, carried along `ride_standoff` off its surface until Space. Space then throws you off with its speed plus a hop.
  - **Look:** your own grapple uses the pause menu's new "Tentacle style" setting (`GameSettings.tentacle_style`, saved): black glossy symbiote (tip splits into gripping tendrils), flesh worm (ringed, tape-worm skin), or spider horde (up to 600 tiny PSX spiders streaming round each other as the rope, one MultiMesh). It writhes while flying out and goes taut once stuck. Other players see a plain dark line from your left shoulder. For now it starts from the bottom-left of the screen (`view_origin`); the coil up the arm comes with the new arms (Arms/arms_rig.glb, the bare-skin texture, not the gloves).
  - Co-op: `PlayerInput.grapple` (E) is part of the input packet. tick()/apply_pull() run inside the simulation step, so the host runs them, and the kick damage too. Drawing is per peer.
  - No sounds yet (planned: wet slither while coiling, whip crack, rubber stretch while pulled, heartbeat at full coil, shared by all three looks). No HUD for the charges yet (`charges` / `recharge_fraction` / `coil` are public for it).
  - Untested at time of writing (not run).

- 2026-10-09: **New first-person arms, the symbiote coil, and the PS1 shader on the arms, the grapple and every enemy.**
  - `scripts/first_person_arms.gd` (FirstPersonArms) replaces the police-character arms (`Viewmodel.use_new_arms`, on). It uses `Arms/arms_rig.glb` with the bare-skin texture, not the gloves. HL2 c_arms style: the rig's `camera` bone sits on your eye.
    - **Right hand:** holds every weapon in the rig's `finger_gun_idle` pose. A weapon not yet fitted (`WeaponData.arms_fitted` false) gets its old arms_position/rotation/scale reset and its middle moved into the right palm when shown. F2 tunes it from there, and F3 saves the fit.
    - **Left hand:** the tentacle arm, out of view until E. With a one-handed gun out, holding E brings it up from below (`hide_drop`, `raise_speed`). It slowly reaches out toward the rig's `push_L` pose at its furthest point, up to `coil_reach` (0.65) by full charge. On release it shoves out the rest of the way (`push_speed`). It stays out while the tentacle is out, then drops.
    - Poses are read straight from the rig's animations (Animation API, no AnimationPlayer running) and written to the bones each frame. Bone positions are worked out from those poses, so they're never a frame stale.
  - **Symbiote coil** (GrappleTentacle). While you hold E it slides down from the elbow and winds round the forearm toward the wrist (`coil_turns` 3.5, `coil_radius` 0.05), slowly crawling round it. A full hold winds `coil_before_release` (80%), and letting go snaps on the rest (`release_coil_speed`). So it peaks right as it lashes, out of the palm. It unwinds after the grapple lets go. The symbiote is now the focus; the other two looks stay in the menu for now.
  - **Grapple 40% weaker:** `pull_speed` 26 to 15.6 m/s, `pull_accel` 70 to 42. A full-speed kick is now 62.
  - **PS1 shader** (`scripts/ps1_look.gd` PS1Look). `material()` makes an opaque, optionally two-sided copy of shaders/ps1.gdshader (screen-space vertex snap, per-vertex lighting, nearest texture). The arms and the symbiote use it; the symbiote keeps its 6 sides and gets a tiny 8 x 16 glossy-black texture.
    - Every enemy goes through it as it spawns: `watch_enemies()`, hooked from the GameSettings autoload, matched by class name. Standard materials are swapped for PS1 ones with the same texture and colour, cached so copies still share one. Left alone: see-through, glowing, unshaded and vertex-coloured materials, and custom shaders. Hit flashes are overlays, so they still work.
    - It's cheaper than the standard material: lighting per vertex, not per pixel.
  - Headless check run (with the user's OK): no script errors. Not yet seen in game.

- 2026-10-09: **Sideways (canted) grip, and dual Uzis.**
  - `WeaponData.hold_cant_degrees`: the gun's held tipped on its side. 90 means its top points left, like the user's reference photo. The gun rolls round the view direction on top of its own rotation (`Viewmodel._cant_basis()`). The right forearm turns over by the same amount round its own length (`FirstPersonArms.set_cant()`), so the hand stays wrapped over the top. The F2 arms mode (H) takes the cant back off before storing the rotation. Pistol: 90 (in weapons/starter_gun.tres, left uncommitted with the user's own edits).
  - `WeaponData.dual_wield`: a second copy in the left hand. The left arm takes the right arm's grip mirrored across the rig's X = 0 (`FirstPersonArms._mirrored_right()`, cant included, so the tops tip inward). The left gun sits in the left hand as the right sits in the right, mirrored (`Viewmodel.MIRROR_X`). The guns take turns: each shot's flash, and its tracer start, come from the other gun. The kick still moves both. Not one_handed, so E switches to the Pistol for the grapple.
  - **weapons/dual_uzis.tres** "Dual Uzis": the small Uzi from art/weapons/NEWPSXWEAPONS/Uzi (barrel along -Z, scaled x3). It's a bullet hose: 9 damage, 0.06 s between shots (about 16 a second across both), 64 rounds, 3 degree spread, 1.8 s reload, bullets, SMG sounds, cant 90. In the starting loadout (player.tscn) for testing; pickups later.
  - Headless check run (with the user's OK): no errors. Not yet seen in game.

- 2026-10-09: **Natural gun grip, straight wrist, grip markers, two-handed support hand.**
  - Right hand: the arm still comes from `finger_gun_idle`, but the fingers come from `knife_idle`, a hand closed round a handle (`FirstPersonArms.grip_animation`). The index finger sits `trigger_curl` (0.55) of the way from straight to curled, on the trigger. `straight_wrist` (on): the hand is in line with the forearm (the rig's rest pose for hand.R).
  - Pistol held upright again (cant removed); only the Dual Uzis stay sideways.
  - **Grip markers:** `WeaponData.grip_point`, in the gun's own space. The gun is seated so it sits in the middle of the closed right hand (`FirstPersonArms.grip_socket_in_rig()`: palm and middle finger). In F2, G = grip mode: the arrows move the grip point with a blue dot showing it through the hand, and the gun stays seated in the hand. Shift turns the gun and +/- resizes it while it stays seated. F3 saves. Pistol starts at (0.05, -0.03, 0).
  - **Two-handed guns:** the left hand comes up in one generic support pose (`support_animation` grab_L at `support_time` 0.5). It's not fitted to each gun, so it doesn't touch the gun.
  - Dual Uzis' scale 3 to 0.3 (it filled the screen).
  - Fixed: FirstPersonArms' bone maths applied scale before rotation.
  - Capture run (with the user's OK): pistol grip and wrist look right, coil arm unchanged. The Uzi screenshot was blocked by an enemy, so the Uzis are still unseen.

- 2026-10-09: **Whole-hand knife grip, per-arm tuning, PPSh two-handed, Uzi singles and pairs.**
  - Right hand: the whole hand (palm, fingers, thumb) now comes from `knife_idle`, so the fingers line up and wrap together. `FirstPersonArms.grip_room` (0.15) opens it a little toward flat to fit a gun's thicker grip. trigger_curl is gone.
  - **Per-arm tuning:** `WeaponData.right_arm_offset/_rotation_degrees` and `left_arm_offset/_rotation_degrees` (camera space) move and turn one whole arm round its shoulder (`FirstPersonArms.set_arm_offsets()`). The gun keeps its place on screen. The left one applies only while that arm holds a gun (dual, two-handed support), never to the grapple arm. F2 modes: J = right arm alone, K = left arm alone, gun mode = gun alone, H = both arms with the gun, G = grip.
  - PPSh is two-handed now (one_handed off).
  - **Uzi** (weapons/uzi.tres): one Uzi, upright, one-handed (grapple works with it). 9 damage, 0.1 s, 32 rounds, 2.5 degree spread, 1.3 s reload. `WeaponData.dual_version` points at Dual Uzis. Picking up a second Uzi pairs it (`WeaponController._pairs`). V (`PlayerInput.toggle_dual`, `WeaponController.tick_dual()`) then swaps the slot between one and two with a quick draw. Loaded rounds carry over and any that don't fit go back to reserve. E with two out puts one away instead of switching weapons.
  - Starting loadout: Pistol + Uzi. A second Uzi (scenes/uzi_pickup.tscn) lies just in front of the start in the Harvestman level.
  - Headless check run (with the user's OK): no errors. Not yet seen in game.

- 2026-10-09: **One-handed weapons start with the Pistol's arm placement.** `Viewmodel.one_handed_arms_template` (weapons/starter_gun.tres). A one-handed weapon not yet fitted to the new arms copies its arms_position/rotation/scale and right_arm_offset/rotation, then is seated in the hand by its own grip_point. Still tunable per weapon in F2 afterwards. Not run.

- 2026-10-09: **One-handed guns copy the Pistol's held angle and grip spot too**, not just its arm placement. New `WeaponData.model_facing_degrees`: how a gun's model turns to face forward and upright (PSX_Guns models point along -X: (0, -90, 0), set on the Pistol; NEWPSXWEAPONS face -Z: zero). A one-handed gun not yet fitted takes the Pistol's rotation with the Pistol model's facing taken off and its own put on, so it aims the same way. Its grip_point goes exactly where the Pistol's grip is (same hand, same arm placement). Size stays its own. Uzi grip_point (0, -0.012, 0): the top of its handle. Applies to every future one-handed gun automatically. Not run.

- 2026-10-09: **Guns from the PSX_Guns kit: UZI model, Revolver, Pump Shotgun.**
  - Uzi and Dual Uzis now use PSX_Guns/FBX/UZI.fbx (the one with "UZI" on it, not UZI_LowerRes). It points along -X like the Pistol: model_facing (0, -90, 0), scale 0.75, grip_point (0.058, -0.045, 0) on the handle, muzzle (-0.233, 0.058, 0), all measured from the mesh. The Uzi refits from the Pistol template. The Uzi pickup uses it too.
  - **Revolver** (weapons/revolver.tres, one-handed): PSX_Guns/FBX/Revolver.fbx. It was exported at 1/100 and lying along +Y with its top along +Z: scale 100, model_facing (-90, 0, 0). 50 damage, 0.6 s, 6 rounds, 2.4 s reload, heavy kick, the sniper's fire sound until it has its own.
  - **Pump Shotgun** (weapons/pump_shotgun.tres, two-handed): the new PSX_Guns/FBX/Shotgun.fbx (same 1/100 export, same fix), the Shotgun's stats copied, to compare looks.
  - The new Shotgun.fbx replaced the old file of that name, so the old Shotgun now uses the kit's original model from GLB/Shotgun.glb.
  - Revolver and Pump Shotgun are in the starting loadout for testing.

- 2026-10-09: **Muzzle flash: a PS1 look, lit the modern way** (`scripts/fx/muzzle_flash.gd` MuzzleFlash).
  - **Look:** a 16 x 16 hand-pixel star sprite (stepped, nearest-filtered, additive) facing you, plus two crossed flame petals along the barrel. Two stepped frames (full, then 65% at half brightness), a random spin and size each shot, and a colour drift toward white or deep orange (Doom/Quake/HL1 style).
  - **Lighting:** a KEY light off to the side of the muzzle (`WeaponData.muzzle_light_offset`, default (-0.15, 0.05, 0.08): left, up, back toward you) rakes across the gun and arm from that angle. It's the cinematic side-light the user liked when the flash sat off to the left. A FILL light at the muzzle (wider, softer) lights the room. Both have a sharp attack and squared falloff, and cast no shadows.
  - Mirrored for the left-hand gun. One flash per hand, made once and reused (no nodes made per shot). It follows the muzzle through kick and sway for its muzzle_flash_time (at least 0.06 s).
  - F2 then L: the arrows move the key light, which stays lit so you see the lighting live. F3 saves.
  - Headless check run (with the user's OK): no errors. Firing not yet seen in game.

- 2026-10-09: **The world: an open alien land replaces the lawless city** (full plan: docs/WORLD.md). Decided with the user:
  - Grandma's house is the one untouched piece of the old world, inside an alien land of purple and blue gradients grown over with coral-reef growths, with old-world megastructures half-swallowed.
  - One continuous world streamed in chunks (Minecraft-style), hybrid-made (procedural wilds + hand-made places), Terrain3D with the PS1 shader, first playable 1 x 1 km, free-roam co-op, no gravity zones.
  - Quests from Grandma and from people in the world; no portals.
  - Full day/night with bioluminescent growth.
  - Growth: staghorn, kelp, brain coral, glow grass, sea fans, anemones, tube sponges, reef crust; breakable coral walls, healing polyps and stinging coral as gameplay.
  - Life: sky flocks, sky jellyfish, passive flying beetles, giant fog silhouettes, hermit beetles, giant isopods, nautilus snails, urchin ticks.
  - Enemies are the changed world's creatures plus scavenger/cultist factions (A-Life). Tone and player unchanged.
  - Creative Direction (Setting, Enemies, Look) rewritten to match.

- 2026-10-09: **Arms and guns, since the muzzle flash.**
  - **Straighter elbows:** `FirstPersonArms.elbow_straighten` (0.6). The gun arms' elbows open toward straight while the hand stays exactly where it was (the arm swings back from the shoulder). Applies to the right hand, the dual second hand and the support hand; the grapple arm is unchanged.
  - **Template placement:** one-handed guns copy the Pistol's arm placement, held angle (via `WeaponData.model_facing_degrees`) and grip spot. Two-handed and dual guns start with the right arm where the one-handed guns hold theirs.
  - **Support hand:** two-handed guns use a sideways barrel grip, as in the user's reference photo. The upper arm comes from below and behind (its cut end off screen), the forearm crosses the view into the gun, and the hand is half-open (`support_hand_open` 0.5) round the barrel. It's placed automatically on `WeaponData.support_point`, which defaults to 35% from the grip toward the muzzle. `WeaponData.support_pose` OPEN_HAND keeps the old reaching pose (the PKM's).
  - **Guns and models:**
    - The MP5 (NEWPSXWEAPONS/MP5k) replaces the Uzi. The files keep their uzi names; the Dual MP5s pair as before, and you start with two.
    - The Revolver's model was already scaled and turned by its own node: scale 1, no extra turn. Its missing texture is fixed with an external material (`revolver_material.tres`, using revolver.png, since the FBX pointed at a missing .psd).
    - The Pump Shotgun was removed. The RPG is 40% bigger.
    - Gun models lose any light or camera exported with them (`Viewmodel._strip_scene_extras()`); the MP5 also skips them at import.

- 2026-10-09: **Open world M0 steps 2-4: test world, pathfinding, ground shader, fog** (docs/WORLD.md).
  - **Terrain generator** (`scripts/world/alien_terrain.gd`, AlienTerrain):
    - The land's shape: warped hills, each with its own random height and random spacing, plus craggy patches.
    - Frozen-sea ridges whose height, spacing and crest sharpness vary, crossed by a second swell.
    - Grandma's yard flat in the middle.
    - A slope cap (`max_slope_degrees` 66.7, the first version's steepest) settles anything steeper.
    - Walkable passes (40 degrees, about every 110 m) cut through steep ridges: 99.9% of the land is reachable from the yard.
  - **Bake tool** (`tools/make_test_world.gd`): a 1 x 1 km Terrain3D world (4 m vertices, 4 regions of 512 m) with full-terrain collision, navmesh tiles, the ground shader, the fog, test enemies and the player, into scenes/world/test_world.tscn.
  - **Navigation, the AAA way** (`scripts/world/world_navigation.gd`, WorldNavigation): the navmesh is baked offline into 128 m tiles (shared border; edge connections bridge the one-cell seam) and streamed around every player on the host in game. A runtime per-player baker remains only as a fallback.
  - **Path queue** (`scripts/world/path_requests.gd`, PathRequests): enemies (enemy.gd) re-path only after the target moves 1.5 m or every 0.5 s, at most 6 paths a frame, with up to 20000 polygons a search (Godot's 4096 cut cross-map routes short). Tested: all long cross-map paths reach their goal.
  - **Ground shader** (`shaders/alien_terrain.gdshader`, on Terrain3D's minimum shader): purple/blue by height, slope and moss/rust blotches, with PS1 vertex snap, faceted triangles, 1 m colour blocks and 15-bit colour.
  - **Fog** (`scripts/world/alien_atmosphere.gd`; worlds/test_world/environment.tres): purple depth fog 30-220 m, valley haze below 18 m, background in the fog colour until skyboxes, purple ambient light. SewerLook now skips any WorldEnvironment with the `own_look` meta.
  - Terrain3D 1.0.2 added (addons/terrain_3d). Its demo/ folder is left uncommitted (24 MB of samples).

- 2026-10-09: **Open world M0 step 5: chunk streamer** (`scripts/world/world_chunks.gd`, WorldChunks).
  - Minecraft-style: the world is cut into 128 m chunks (the navmesh tiles' grid), and the chunks within `load_radius` (2: 5 x 5, 640 m across, past the 220 m fog) of every player are loaded.
  - Each chunk's hand-made content is its own scene (`worlds/<world>/chunks/chunk_<x>_<z>.tscn`, chunk-local coordinates). A chunk with none is just land.
  - Scenes load on background threads, with at most `max_adds_per_frame` (1) finished chunks added per frame. Chunks unload one ring past the radius (no flicker on a chunk edge).
  - `chunk_loaded` / `chunk_unloading` signals are the hooks for procedural content (coral, next) and saved per-chunk state.
  - The bake tool writes 5 test chunks with monoliths (megastructure stand-ins, 45-90 m tall) and bakes them into the navmesh tiles (`bake_tiles` takes in static colliders).
  - Tested with a stand-in player:
    - 25 chunks load at the yard; moving 565 m loads 24 and unloads 21.
    - Paths route round a monolith (82 m vs 71 m straight).

- 2026-10-09: **4 x 4 km test world, and the navmesh optimized for it.**
  - The bake tool's size is a setting (`-- size=2048` for 8 km). Default 1024 px = 4 km: 64 terrain regions, 1024 navmesh tiles, plus 40 more monoliths scattered at random (seeded) for streaming to chew on.
  - **Navmesh:** 1 m cells (was 0.5; the terrain's triangles are 4 m) with more polygon merging (`region_min_size` 8, `region_merge_size` 40, `edge_max_error` 2). `agent_max_climb` is 1.0 m, so slopes don't bake as ledges.
  - **Bake:** tiles bake on every CPU core (`WorkerThreadPool` group task) and save compressed.
  - **Measured on the 4 km world:**

    | | Before | After |
    |---|---|---|
    | Bake | 65 s | 32 s |
    | Navmesh on disk | 35.9 MB | 6.3 MB |
    | Joining 192 tiles | 29 s | 3.5 s |

  - In game (25 tiles round a player): 59 ms to join the tiles (in the background), and path searches take 0.07-0.09 ms up to 500 m.
  - Land: 96.7% reachable from the yard; steepest 66.7 degrees.

- 2026-10-09: **Open world M0 step 6: the growths** (not yet run; the user was away).
  - `scripts/world/growth_meshes.gd` (GrowthMeshes): low-poly meshes built in code, 4 shape variants each, PS1-chunky. Kinds:
    - staghorn (branching, glowing tips)
    - kelp (tall wandering stalks, glowing bulbs)
    - brain coral (ridged domes)
    - glow grass (blade clumps)
    - sea fans (ribbed lattices)
    - anemones (tendril clumps)
    - tube sponges (hollow chimneys, glowing rims)
    - extras: puffballs (spore balls), spire coral (twisted spikes; the future stinging coral), bladder pods (glowing heaps)

    Every vertex carries its colour, a sway weight (vertex alpha) and a glow amount (UV2.x).
  - `shaders/alien_growth.gdshader`: PS1 vertex snap and per-vertex light, wind sway (out of step per plant, with slow gusts), glow (`glow_day` / `glow_night`, `night` 0..1 for the coming day/night cycle), 15-bit colour.
  - `scripts/world/growth_species.gd` (GrowthSpecies): each kind's rules, all exports:
    - where it grows: a patch map, plus slope and height bands
    - group sizes: long-tailed, so mostly small groups, some big, rarely a horde
    - spacing, crowding toward the middle, loners, size range, elders, leaning with the ground, tint spread, glow colour, sway, view distance, shadows

    `defaults()` holds the tuned set (kelp in valleys, sponges on ridges, grass carpets on flats, spires on steep ground...).
  - `scripts/world/growth_scatter.gd` (GrowthScatter): grows each chunk WorldChunks streams in, deterministic from seed and chunk (co-op: every player gets the same, nothing sent).
    - Groups are Pareto-sized and spread with their size. Members crowd toward the middle, are bigger in the middle and smaller at the edge, with rare elders. Groups are stretched ovals, not circles.
    - It keeps off Grandma's yard and out of the chunk's megastructures.
    - One MultiMesh per kind and variant per chunk, faded out past each kind's view distance. 3 kinds grown per frame, so chunks arrive without a hitch.
  - Test world: GrowthScatter added (bake tool and scene).
  - **Terrain fix:** the checkerboard was Terrain3D's `show_checkered` debug view, switched on (on the material and the node) for a terrain with no textures. It draws over any shader. Now off in the scene and in the bake tool, so the purple PS1 ground shader should show.

- 2026-10-10: **Terrain checkerboard, the real fix: `scripts/world/terrain_look.gd` (TerrainLook).**
  - A capture run showed the checkers stayed after turning `show_checkered` off. There were no shader errors, so Terrain3D was never using our shader.
  - Cause: a saved scene lists "shader override enabled" before "which shader". On load Terrain3D turns the override on with no shader, builds its default (the no-texture checkerboard) and doesn't rebuild when ours arrives.
  - TerrainLook re-applies the shader in the right order once Terrain3D has set up (two frames in) and calls `update()`. It's in the test world and the bake tool.
  - The same run also showed the growth scripts' new class names weren't registered yet (no import had run since they were written); an `--import` fixed it.
  - Not yet seen in game.

- 2026-10-10: **Enemies collide with the open world's ground; zombies out; barnacles everywhere; bigger growth groups.**
  - **Why the Harvestman walked through a hill:** Terrain3D's in-game collision has no body node, so a ray that hits the ground reports the Terrain3D node as its collider, not a StaticBody3D. Every "is this the level?" test (`collider is StaticBody3D`) took the hills for something passing by, and the rays went straight through them.
  - **New `scripts/world/level_geometry.gd` (LevelGeometry):** `is_terrain`, `is_static` and `is_solid`. Every level test now goes through it: the Harvestman, both worms, spider packs, rat swarms, barnacle scatter, gunner and enemy line of sight, explosions' line of sight (and explosions no longer try to hurt the ground). Shots that hit a body with no node no longer crash.
  - **Harvestman:** it stands on the highest ground under its whole footprint (six probes round the sack plus the middle), keeping `body_clearance` above it, so the sack never sinks into a slope. Its foot and ground rays reach further. Its "wall ahead" probe ignores the ground (it climbs hills) but still turns off walls.
  - **Proboscis:** it stops short of the first solid thing on its line (ground, walls, props; not people, creatures or corpses). Its sag and writhe rest on surfaces instead of passing through them.
  - **Burrow Worm and Deepmaw:** their floor line follows the ground under the head on Terrain3D, so they swim under hills, not through them. In levels the floor they were put on stays their floor.
  - **Ground-walking enemies (Enemy, DeepmawCrawler):** `floor_snap_length` is at least 0.5 m, so they stick to the ground walking downhill (HL2's step-height stick).
  - **Rats, leeches, roaches:** `continuous_cd` is on, so a fast step can't carry them through the ground, which is a surface with no thickness.
  - **Zombies removed** (the user doesn't want them): out of the test world and the bake tool; `zombie.tscn` and `zombie_rusher.tscn` deleted (they're in git history). The PSX zombie models are still in NEWPSXMODELS.
  - **Barnacles:**
    - Clusters have twice the barnacles (12) and fungus mounds (14), over a wider area (radius 2.5 m). The surface probes reach further for hillsides.
    - BarnacleScatter can put nests on floors too (`floor_chance` 0.3).
    - New `scripts/world/chunk_barnacles.gd` (ChunkBarnacles): each open-world chunk has a chance (`nest_chance` 0.25) of a nest as it loads, on the land or up a building. It's in the test world and the bake tool.
  - **Small hordes:** `Population` caps for rats, roaches and spiders raised from 60 to 100 each.
  - **Growths:**
    - Every default group is 4× the members (`GrowthSpecies.GROUP_SCALE`).
    - Glow grass is the commonest growth: 16 groups a chunk, 85% patch cover, 20 strays.
    - The biomes, the sewer growths, the black vines and the far-range shimmer fix are waiting on the user's design choices.

- 2026-10-10: **Two biomes, sewer growths, black vines, eyes, bigger Harvestmen and worm, 160 m chunks, frame counter.** (The user chose each growth decision.)
  - **Biomes (`scripts/world/biome_map.gd`, BiomeMap):**
    - A baked grey map (8 m a pixel; white = reef, black = sewer). Sewer almost everywhere, reef in pockets (`REEF_SHARE` 0.25), soft borders about 150 m wide (box-blurred three times). The yard's surroundings (120 m) are always sewer.
    - Made by the bake tool into `worlds/test_world/biomes.res`. The nearest reef is about 295 m from the yard.
    - Everything that changes by biome reads this one map, so they all cross over in the same place:
      - **Ground (`alien_terrain.gdshader`):** a sewer palette next to the reef one (black sludge valleys → olive mud → grimy tan → nicotine ridges, wet black grime slopes, toxic slime and rust blotches), mixed by the map. TerrainLook passes the map in. No map = sewer.
      - **Growths:** GrowthSpecies has a `biome` (REEF, SEWER or ANYWHERE). Kinds thin out across the border, so the two mix there.
      - **Air (`biome_atmosphere.gd`, BiomeAtmosphere):** fog colour and distance, valley haze, ambient light and background crossfade by the biome round the camera, eased over 1.5 s. The saved environment is the reef's air; `AlienAtmosphere.sewer()` is the sewer's.
  - **New growths (GrowthMeshes / GrowthSpecies):**
    - Sewer: hair mould (the sewer's grass, its commonest), egg sacs, hive mounds, shelf fungus, pus boils, chitin ribs (a dead giant bug), cocoons, slime caps, flesh tendrils, larvae piles.
    - **Black vines** grow in both biomes, on the ground and up the chunk's buildings (`wall_patches`). They are 4-sided black tubes snaking in and out of the surface over each other, with coiled tips. The whole vine breathes: it swells to about 2.4× its thickness and back (`breathe`, using CUSTOM0 and UV in `alien_growth.gdshader`).
  - **Growth placement:**
    - Every growth rolls its own size anywhere in its range, like the creature hordes.
    - Groups are 4× (earlier entry). Overall density is ×1.2 (`GrowthScatter.density`).
  - **Far-off flicker fix:** the growths' PS1 snap grid gets finer past `snap_fine_distance` (20 m), so thin far branches stop jumping between grid cells. Close-up wobble is unchanged.
  - **Eyeball clusters (`eye_cluster.gd`, `eye_scatter.gd`):**
    - 3–9 eyes in flesh sockets, sewer only, about 0.3 per 128 m of land (rarer than the growths, not super rare).
    - They open one after another when a player comes within 25 m, all turn to stalk the nearest player with little darting glances, blink, and drift shut slowly once nobody's near.
    - Look only: each game runs its own, and they're placed by world seed.
  - **Harvestman:**
    - `size` 2.0. The body is scaled, and every distance it works by (stance, legs, strides, ranges, hitboxes, proboscis, light) is ×2. Speeds stay as set, so it takes longer, heavier strides.
    - Always in groups of 2–3: an uncompanioned one brings 1–2 more of its kind (`group_min`/`group_max`), about `group_spread` apart, on the navmesh.
  - **Boss worm (BurrowWorm):**
    - `size` 2.0: its body and every distance it works by (depths, leaps, plough, shockwave, rumble) ×2. Its Deepmaw escorts keep their size.
    - Landing from a leap, it keeps the speed it hit the ground at, curving at up to `swallow_turn` but never braking, until its tail is under. The whole body pours in at one speed (before, the tail slowed down with the head).
  - **Rat nests (no Bender):** packs are twice their set counts (`RatNest.LEADERLESS_SCALE`).
  - **Barnacles:** ChunkBarnacles spawn in both biomes. Their chance scales with chunk area.
  - **Chunks:** 160 m (25% up). Growth, eye and barnacle counts are per 128 m of land and scaled by area, so density is unchanged. The bake tool now clears old chunk files first (stale 128 m ones had to be deleted by hand).
  - **Fog:** pulled back 10% in both biomes (reef 33–242 m, sewer 22–192.5 m, haze ×0.9). Growth view distances are +10% to match.
  - **Frame counter (`scripts/ui/frame_counter.gd`, autoload FrameCounter):** small, top right, over everything. Shows fps and the worst frame time (ms) over the last half second.
  - **`tools/stream_benchmark.gd`:** flies the player across the test world at 6, 12, 26 and 50 m/s for load radius 2, 3 and 4. It prints frame times (average, 1% worst, worst), chunks live, growth jobs queued and how often the ground under the player wasn't loaded yet. Not run yet: it needs the user's yes.

- 2026-10-10: **Stream test results; the worm as an event; terrain painter usable.**
  - **Stream test (run with the user's yes; 160 m chunks):**
    - 5×5 averaged 1–5 ms a frame, 7×7 7–11 ms, 9×9 10–15 ms.
    - The ground under the player was never late, even at 50 m/s.
    - Worst frames were 30–55 ms hitches. The growth queue backed up at grapple speed and faster (up to 380 jobs), so growths fill in late.
    - Next step: give the growth queue a per-frame time budget.
  - **WormDirector (`scripts/world/worm_director.gd`):** the boss worm comes as an event from under a megastructure. Every building at least 20 m tall is a lair.
    - Hunger fills while a player stays within 220 m of a lair (about 90 s, plus 1.5 s per shot fired) and drains while nobody's there.
    - Cooldown is 15–20 min between events; the first comes after 7.5–15 min.
    - Build-up (15 s): a rumble growing louder, camera shake, dust pouring off the structure, and nearby eye clusters staring at it (`EyeCluster.stare`).
    - It erupts 18 m off the structure's side facing the nearest player, straight into a leap (`BurrowWorm.erupt_at_once`).
    - It leaves (`BurrowWorm.retreat`: dives deep, gone in 6 s with its escorts) once everyone's been 160 m away for 8 s, or after 2 minutes. That lair then rests for an hour.
  - **Terrain painter:**
    - TerrainLook is a tool script, so the editor shows the real ground look, not checkers.
    - The ground shader multiplies by Terrain3D's colour map, so the Color brush tints the ground (`paint_strength`; white = untouched).
    - BiomeMap keeps its texture in `biomes.res`, so scenes reference it instead of embedding a copy.

- 2026-10-10: **Giant growths in forests** (the user picked all six, "forests in places", 10–30 a grove).
  - **New GrowthMeshes kinds, about 15–45 m tall (half a megastructure), scaled 0.7–1.4, with the odd 1.5× elder:**
    - Reef: KELP_TOWER (swaying stalks, glowing bulbs) and CORAL_TREE (staghorn grown into a branching tree).
    - Sewer: FUNGUS_TOWER (a rotten stalk with a spiral of shelf caps like platforms and a wide top cap), HIVE_SPIRE (a lumpy clay spire with glowing vents and mouth) and FLESH_STALK (a giant swaying tendril with pus boils).
    - Both: VINE_PILLAR (black vines wound both ways round each other, tips peeling off the top; it breathes).
  - **Forests in places** (`GrowthSpecies._giant`): each kind has its own patch map (900 m, 30% cover), so there are big stretches with none and then whole forests.
    - 10–30 to a grove, not GROUP_SCALE'd. Gentle ground only (under 25°). Standing straight, rooted 0.6 m deep.
    - They cast shadows and are seen to about 300 m (the fog hides them before that).
  - **Solid:**
    - Each giant mesh carries a "trunk" meta (radius, height). GrowthScatter gives every giant a cylinder of that size on one static body per batch.
    - You can't walk through them, and the grapple and spiders take them for level geometry.
    - The offline navmesh doesn't know about them, so enemies may bump into trunks until that's handled.

- 2026-10-10: **Back to 128 m chunks; growth optimization; more barnacles; calmer land.**
  - **Chunks:** back to 128 m. With 160 m, the frame rate dropped near grass, worst in the sewer.
  - **Why grass was heavy:** a sewer chunk had about 4,500 mould tufts at 66 triangles in one batch per kind. A batch can't be partly culled, so a whole chunk's mould was drawn whenever any of it was on screen.
  - **Growth optimization (GrowthScatter):**
    - **Cells:** every kind is drawn in 32 m cells (`cell_size`), one MultiMesh per kind, variant and cell, placed at the cell's middle. Off-screen and out-of-range cells cost nothing. Giants stay one batch per chunk.
    - **Carpets** (`GrowthSpecies.carpet`: glow grass, hair mould): full thickness to 40 m (`carpet_near`), then a second batch of 1 in 4 (`carpet_thin_every`) out to their view distance, cross-faded.
    - **Time-budgeted growing:** jobs are one kind in a quarter chunk, run for at most 2 ms a frame (`grow_budget_ms`, at least one job). This replaces the fixed 3 kinds a frame that caused the 30–55 ms hitches.
    - **Lighter meshes:** hair mould 33 triangles (was 66), glow grass 27 (was 39), larvae piles and flesh tendrils smaller.
    - **Shadows:** only the giants cast them.
  - **Barnacles:** each chunk rolls a Poisson count averaging 0.9 nests (`nests_per_chunk`; was a 25% chance of one), on land or buildings. About 3.5× as many hives.
  - **Terrain (AlienTerrain defaults):** the user found the land away from the yard too steep and too hilly.
    - Hills 250 m across (was 180), so fewer of them.
    - Ridges 130 m apart (was 90), with softer crests (sharpness variation 0.4).
    - Less crag (cover 0.25, share 0.12).
    - Max slope 50° (was 66.7).
    - Re-baked: the land now tops out at 50 m.

- 2026-10-10: **Lighting that grounds things; the worm's head no longer see-through.**
  - **Why enemies looked pasted on:**
    - The test world's sun had no shadows, so nothing cast one.
    - The ambient fill was a strong flat purple (0.7) that lit everything evenly from all round.
  - **The fix:**
    - The sun casts shadows to 120 m (2 splits; bake tool and test world).
    - Ambient is down to 0.45 (reef) and 0.4 (sewer), so the sun shapes things.
    - SSAO is on as contact shadows under feet, bodies and creases (`AlienAtmosphere.contact_shadows`; also in `environment.tres`).
    - The sun is tinted by biome and crossfades with the fog (BiomeAtmosphere): cool lavender 1.15 in the reef, sickly yellow 1.25 in the sewer.
  - **Boss worm:** its skin and maw materials are two-sided (`cull_mode` 2). The maw is a hollow barnacle cup, and from behind or inside, mid-leap, you saw straight through it. PS1Look keeps two-sided materials two-sided.

- 2026-10-10: **Low FPS and broken shadows at a barnacle nest on a monolith.**
  - **FPS:** every barnacle spat roaches or spiders every 10–20 s whether anyone was near or not. With the open world's many nests (and today's doubling), creatures were being bred constantly across all loaded chunks. At the creature caps the oldest are killed (gore and ragdolls) to make room.
    - Barnacles now only breed with a player within `wake_range` (40 m; HL2's spawners: nothing spawns for nobody to see).
    - Each keeps at most `max_brood` (4) of its own alive (tracked by weak refs; `RoachCarry.hatch` returns the roach now).
  - **Shadows:** the PS1 vertex snap ran in the sun's shadow pass too, snapping casters to the sun's coarse grid, so shadows came loose from what cast them and smeared across the monolith's faces.
    - The snap is skipped when the projection is orthographic (the directional shadow pass; the player's camera is perspective) in `ps1.gdshader`, `alien_growth.gdshader`, `alien_terrain.gdshader` and `worm_dirt.gdshader`.
  - **More optimization:**
    - Carpets full thickness to 32 m, then 1 in 5.
    - Sun shadows to 90 m (the fog's thick past that).

- 2026-10-10: **Roaming bands of enemies: an encounter director, not A-Life.** (The user asked for more enemies, human ones too, met naturally; A-Life not needed.)
  - **EncounterDirector (`scripts/world/encounter_director.gd`):** like Left 4 Dead's director and HL2's spawners, not a whole-world simulation.
    - Every 4 s (the first after 20 s) it counts the bands within 240 m of each player. Below 5, it starts one 80–140 m off: behind or beside the player (never in front of their camera), on the navmesh, at least 100 m from the yard and 70 m from other bands. One band per check, so they trickle in.
    - The biome there sets the odds (sewer → reef weights): tweakers 2 → 1, rats 3 → 1, roaches 3 → 2, spiders 2 → 3, Harvestmen 1 → 2.
    - Bands:
      - tweakers: 2–4 of enemy, gunner and rusher mixed;
      - a rat swarm: a leaderless RatNest of 5–9 (×2) plus 0–1 bodyguards (×2);
      - roaches: 4–8;
      - a spider pack: 6–12;
      - Harvestmen: one, which brings its own 1–2 companions.
    - A band more than 240 m from every player is disbanded, its rats and spiders included.
  - **RoamingGroup (`scripts/world/roaming_group.gd`):** members keep their own behaviour (patrolling or wandering round a home). The group drifts that home along a route at 1.4 m/s toward a spot 150–350 m off, then another, so you cross paths with them on their way somewhere.
    - New `set_home()` on Enemy, FlyingRoach and Harvestman; SpiderPack and RatSwarm already had `home`.
    - **AI level of detail:** members more than 150 m from every player are disabled. No scripts run, and their physics bodies leave the physics world (the default disable mode). They wake when someone's near again. The group frees itself once every member is dead.
  - In the bake tool and the test world (`biomes` set).

- 2026-10-10: **Tweakers are camps at megastructures, and bigger.** (The user wanted human groups way bigger, and only near megastructures.)
  - Tweakers no longer roam. Every megastructure (a building at least 20 m tall) in a loaded chunk gets a camp when a player comes within 200 m (`camp_range`).
  - A camp is a gang of 6–12 (`camp_min`/`camp_max`) of enemy, gunner and rusher mixed. It sets up on the structure's far side from the player and patrols round it (`RoamingGroup.anchor`: every stop within the structure's half-width + 30 m), drifting at 1.0 m/s.
  - Wipe a camp out and its structure stays empty for 10 min (`camp_rest`). A camp left behind (240 m away) or whose chunk unloads is disbanded, and can be manned again later.
  - Roaming bands are now rats, roaches, spiders and Harvestmen only.

- 2026-10-10: **More enemies and nests; barnacles 40% bigger; look-only decoy barnacles.**
  - **Barnacles:**
    - `Barnacle.scale_boost` 1.4: every barnacle is 40% bigger (look, hitbox, health). How many it spits still goes by its rolled size.
    - Clusters spread to 3 m.
  - **Decoys (BarnacleCluster):**
    - 18 look-only barnacles per clump (`decoy_count`): just the model, in the PS1 look and the nest's skin. No hitbox, spawning or script.
    - When a real barnacle starts to throb (new `Barnacle.swelling` signal), the decoys within 3.5 m throb too, nearest first, a ripple spreading out. They use the same three swelling pulses and squash.
    - The real barnacles only exist on the host, so in co-op the decoys only throb there for now.
  - **More common:**
    - Barnacle nests average 1.5 per chunk (was 0.9).
    - Roaming bands: up to 7 round each player (was 5), started 70–120 m off (was 80–140), a check every 3 s (first after 15 s), at least 60 m apart.
    - Camps start for players within 250 m (was 200).

- 2026-10-10: **The skyline, and giants that rise out of the fog.** (The user wants megalophobic spectacle: structures and growths so big they go past the fog. They picked A, the skyline layer, and B, fog that thins with height.)
  - **SkylineLayer (`scripts/world/skyline_layer.gd`):** the HL2 3D-skybox idea as real geometry at real distance.
    - Whatever is put under it (func_godot TrenchBroom scenes, glTF, anything) gets `shaders/skyline.gdshader` with its texture and colour kept, no shadows, no collision (shapes removed, layers zeroed), no occlusion culling. The camera's far plane is pushed to 16 km.
    - TrenchBroom workflow: build small, scale the instance (×16 like HL2's skybox). See docs/WORLD.md.
    - Stand-ins (`SkylineMeshes` plus GrowthMeshes): a ring of 10 giants 3.5–7.5 km out, mostly darkened silhouettes of the land's own giant growths scaled to 0.9–2 km tall, plus a brutalist tower with tiny lights and a loop of land 2 km across. 500–1,400 triangles each.
  - **`skyline.gdshader`:** `fog_disabled` with its own fog. It's as thick as the world's at the ground (`near_reach` 260 m) and thins with height (`thin_height` 600 m → `far_reach` 9 km), so feet drown while tops loom. The fog is applied by hand (albedo fades out, fog colour comes in as emission).
    - The fog colour is the new global `world_fog_color` (project.godot shader_globals), set by `AlienAtmosphere.apply_blend` as the biomes crossfade.
  - **Giant growths rise out of the fog too:** `GrowthSpecies.rises_from_fog` (the giants) uses `GrowthScatter._tall_shader()`, the growth shader with the same hand-made fog (thick to 230 m at the ground, 1.4 km past 70 m up). View distance is 600 m, so their tops show past the world's fog.
  - In the bake tool and the test world.

- 2026-10-10: **Rule 9 (Spectacle, always); the walk-up Megastructure template; the Stack.**
  - **Rule 9 added** (the user's direction): spectacle at the limits of the tech, done the cheap way, with the user deciding each piece.
  - **Megastructure (`scripts/world/megastructure.gd`):**
    - Shell: always drawn with the skyline fog (materials converted, texture kept). Interior: drawn within 600 m. Decor. Lair: in the group `megastructure_lairs`, hunger ×2.
    - Barnacle nests: 16, by rays against it.
    - Pushes the camera's far plane to 16 km.
  - **MegastructureSound:**
    - Wind with height, silent below 60 m and full at 400 m.
    - Three positional wind voices kept on the openings nearest you. The user asked for wind at the windows; HL2-style, few voices placed where they matter.
    - The drone, full inside and fading in near the base.
    - The sounds are generated: `StackBuilder.make_wind` (noise through a gliding resonant filter) and `make_drone` (beating low tones with a rumble), both seamless loops.
  - **The Stack (StackBuilder, `tools/make_the_stack.gd`):** every detail the user's (see docs/WORLD.md).
    - 374 shell and 212 interior boxes, merged into one mesh per tower plus the bridges and the insides, with box collision.
    - Occluders: BoxOccluder3D per solid block; occlusion culling is turned on in project.godot.
    - 2,600 lit windows and red blinkers (`stack_lights.gdshader`: unshaded, own fog, per-instance blink and flicker).
    - Growth: GrowthMeshes kinds made huge with the tall-fog shader; vines breathe.
    - Swarms (`swarm.gdshader`: 350 specks per tower, orbiting on the GPU).
    - CoilingWorm: one MultiMesh of worm segments sliding along a spiral.
    - StackLift (an AnimatableBody3D you can ride).
    - Concrete texture generated with a window per 8 m tile.
    - Also written as `maps/megastructures/the_stack.map` (Valve 220, game "2v-2", 8 units a metre, Shell and Interior layers) and `megastructure_map_settings.tres`.
  - **In the world (bake tool):**
    - Placed at (250, -1450) on a plateau (`AlienTerrain.flats`, 480 m, eased over 250 m).
    - 361 terrain vertices holed for the shaft (Terrain3DData.set_control_hole).
    - In the navmesh bake as statics; monoliths kept 650 m away.
    - Shell blocks standing on the ground are sunk 3 m in.

- 2026-10-10: **Megastructure insides infested, with magnified creatures.**
  - While a player is within 500 m (`infest_range`), the Megastructure fills its insides:
    - 3 roach swarms of 6–12;
    - 2 spider hordes of 12–20;
    - 2 big rat hordes, leaderless nests of 15–22 (×2) plus 2–3 bodyguards (×2).
  - Each is a RoamingGroup anchored to its own patch of floor (a random point in `inside`, dropped onto the floor under it), drifting round it within 45 m.
  - New `RoamingGroup.use_navmesh` (off here): the navmesh only covers the ground and would drag them outside.
  - They're cleared once everyone's more than 650 m away, and sleep when far as usual.
  - **Magnified** (the user's ask): everything in the infestation is 2× (`infest_magnify`) in size, and bites 2× as hard (rats). Health stays the same (the user's call).
    - New `FlyingRoach.size` (look and hitbox) and `SpiderPack.spider_scale` (health put back to a normal spider's after its size roll).
    - Rats use RatSwarm's `rat_scale` and `rat_damage_multiplier`.
    - Only the megastructure's own hordes: a Rat Bender's keep their size.
  - Barnacle nests on megastructures: 20 (half inside).

- 2026-10-10: **Error spam fixed; the fog back to the original, with giants as silhouettes and a cloud deck; special touches doubled.**
  - **~2,000 errors at load:** `mesh.get_meta(&"trunk", null)` errors whenever the meta is missing (a null default counts as none). It's now `has_meta` first.
  - **The fog:**
    - The user liked the original fog, not the thinning with height. The skyline, megastructure shells, giant growths, the Stack's lights and the swarms now fog exactly like the world: the new globals `world_fog_begin`/`world_fog_end` with `world_fog_color`, kept in step by `AlienAtmosphere.apply_blend`. `height_thinning` (0 by default) keeps the old effect one slider away.
    - Still visible far off (the user's ask): past the fog's end the fog stops at `silhouette` (0.8), so distant giants and the Stack stay dim shapes in the murk, and their glow and lights shine through it (`light_pierce`).
    - **Reaching past the clouds:** a cloud band (650–1,000 m) they vanish into and rise out of, in all those shaders.
    - New CloudDeck (`scripts/world/cloud_deck.gd`, `clouds.gdshader`): a drifting layer of billows in the fog's colour at 800 m, kept over the camera. It's darker from below, lighter from above, and fades out right overhead. It's in the bake tool and the test world.
  - **Twice as dramatic (the user's ask):**
    - Stack windows 5,200 (was 2,600), bigger, brightness 5.
    - Blinkers on almost every block corner, 9 m.
    - Swarms 700 specks each, bigger.
    - The coiling worm twice as thick, longer, faster.
    - Lift lamp and depth lamps ×2 (8 lamps).
    - Breathing ×2 (vines 2.8, pillars 2.0, in the land too).
    - Growth glow ×2 on the Stack; skyline glow ×2.
    - Wind and drone +6 dB.

- 2026-10-10: **The original fog back; all fog in one inspector; another get_meta error fixed.**
  - **The user's call:** the custom fog made distant shapes white. Everything is back on the world's own fog, even though it hides the distant giants.
    - `skyline.gdshader`, `stack_lights.gdshader` and `swarm.gdshader` are plain shaders now (no `fog_disabled`, no fog by hand).
    - The giants' growth variant (`_tall_shader`, `rises_from_fog`) is removed; the giants' view distance is back to normal.
    - The fog settings are gone from SkylineLayer, Megastructure, CoilingWorm and StackBuilder.
    - The globals `world_fog_begin`/`world_fog_end` are removed. `world_fog_color` stays for the CloudDeck, which the user kept.
  - **All the fog in one place (the user asked for an inspector value): the BiomeAtmosphere node.**
    - `fog_distance` (0.25–3) scales every biome's fog distances at once; valley haze scales with it.
    - `reef_air` and `sewer_air` are written into the scene by the bake tool, so every value is there to open and tune: colour, start, end, curve, haze, ambient, sun.
    - Changes apply live: it re-applies twice a second, and right away when they change.
  - **Fix:** `barnacle_cluster.gd` `_throb` did `get_meta(&"throb", null)`, which errors when the meta is missing (a null default counts as none). It's now `has_meta` first. That was the only other one in the scripts.

- 2026-10-10: **Fix: CoilingWorm "target vector can't be zero".** At the spiral's ends the point 1 m ahead was clamped onto the point itself. Each segment now faces across itself (1 m back to 1 m ahead), and a zero direction is skipped.

- 2026-10-10: **Infinite Grapples switch (pause menu).** `PlayerGrapple.infinite_charges` (on for now, the user's ask, while testing the Stack): firing doesn't spend a charge. The pause menu gets an "Infinite Grapples" row, a copy of the Infinite Ammo row placed under it, synced from the player when the menu opens.

- 2026-10-10: **The Stack reworked: entrances at every height, halls inside every tower, eyes at the ways in.** (Every detail the user's.)
  - **StackBuilder rewritten.** Towers are stacked blocks; spaces are CARVED out of them (axis-aligned box subtraction, `_carve`); then everything inside and on them is added. Boxes carry a full Basis now (ramps, rubble, tunnels tilt). The map writer uses it too.
  - **Halls (`HALLS`), 11:** cavernous brutalist spaces in every tower at several heights. Each has:
    - mezzanines reached by switchback ramps at 28° (lanes zig-zagging along a wall with landings at each turn, `_switchback`);
    - leaning columns, an upside-down stepped pyramid hanging from the ceiling, a slab leaning on a wall, stairs that stop in mid-air;
    - lamps (cold high, warm low).
  - **The main tower's shaft runs the whole height** (30 m above the base). Platforms cross it every 100–140 m outside the halls, half the shaft, alternating sides, so a slip is a drop, not the bottom (the user didn't want to just fall through).
  - **Hollow skybridges** link the main tower's mid hall to tower 1's and tower 3's.
  - **Entrances:**
    - **Low:**
      - The collapsed block: three broken slab sections, overlapping so there's no ledge, as a 28° ramp up into the base's +Z wall, torn open at storeys 1–2, among tumbled chunks and bent rebar. Plain broken concrete, so no windows underfoot (the user's point).
      - The sewer outfall: a culvert mouth in a retaining wall, sludge down its floor, a tunnel down with one bend in a chamber (holed both ways it's met), to a hole in the depths' west wall.
      - The entrance bridge.
      - **Lit apartment windows** (the user's idea): 32 rooms carved behind windows at the halls' heights. Each has a warm lamp, a glowing frame, and a beam of light falling out into the air (`window_beam.gdshader`, additive). A corridor at each room's back leads into the hall.
    - **Mid:** the lift's dock (a corridor in, a 30 m door hanging half open) and the hive tunnel (a ledge of hive spires, a tunnel lined in clay lumps with glowing vents).
    - **High (above the clouds):** the cable car between tower 1's high hall and the main tower's, and the broken bridge (a 30 m gap to grapple) at one height in both.
    - **Crown:** the lift's summit station and the hangar (70 × 46 m), open to the sky.
  - **Lift:** StackLift is now stop to stop with easing (an express at 35 m/s: base 40 m, mid 1,100 m, crown 4,760 m). The deck's top is level with each stop, with railings and a lamp. It also runs the cable car (`hanging`).
  - **Eyes at the entrances** (the user's ask): 28 EyeClusters of 10–20 eyes, spread 3.2, sizes to 0.55, at every way in and half the window rooms.
  - **Megastructure:** `inside_zones` (the infestation picks a hall, then a floor in it) and `terrain_holes` (the bake tool punches them: the shaft and the outfall's mouth, 603 vertices).
  - **Counts:** 881 shell and 652 interior boxes, 75 lamps (distance-faded at 400 m), 158 wind openings.

- 2026-10-10: **Open-world HUD and loadout; player tracers first; the grapple landing ring.**
  - **HUD in the open world:** the test world never had `scenes/ui/hud.tscn` (the crosshair, ammo, health, stamina), which every level includes. It's added to the test world and the bake tool.
  - **Loadout (`scripts/world/loadout.gd`):** in the test world, every weapon (both Uzis for the pair, grenades), plenty of ammo, and full pills and bandages, through the pickup calls (`pickup_weapon` / `add_ammo` / `add_item`), then back to the first weapon. The user's ask.
  - **Player tracers (BulletFX):** player and enemy tracers shared one cap of 24, and a camp's gunners could take every slot. Enemy tracers now get at most 16 (`MAX_ENEMY_TRACERS`). The player's always spawn: at the cap, the oldest enemy tracer is ended to make room.
  - **Grapple landing ring (GrappleIndicator, `grapple_ring.gdshader`):** every detail the user's.
    - Only while holding the grapple.
    - A thin ring lying on the surface it would grab (floor, wall, ceiling), sized by view angle (2.6°) so it frames the crosshair instead of hiding under it.
    - It fills round like a dial with the charge (notched in eighths) and flashes when full.
    - Red where the grapple would give out when there's nothing to grab, or on a small enemy (which would be a miss).
    - It uses the grapple's own ray at the reach the current charge gives, so it shows exactly where it'll land. Your own view only.

- 2026-10-10: **Windows on the painted grid, lights dimmed in the fog, fewer floor boxes, floor nests, the depths' fog fixed.**
  - **Light through the fog:** only somewhat now (the user's ask).
    - `stack_lights.gdshader` dims windows, blinkers and frames from 30 m to 12% by 220 m (the fog does the rest).
    - `window_beam.gdshader` is additive, so it showed through fog undimmed. It now has `fog_disabled` and fades by hand from 25 m to 8% by 180 m.
  - **Windows where the texture paints them (the user's ask):**
    - The Stack's texture is laid on one grid for the whole thing, by world position rather than per box. Before, each carved piece restarted the pattern and the painted windows didn't line up.
    - Painted windows: 3 m wide, centred 4 m into each 8 m along a wall, from 2.25 m to 6 m up each 8 m (`WINDOW_*`).
    - Window rooms' openings are exactly one painted window, cut on a painted spot, the room's floor at its sill. The faces where the texture runs opposite the wall's axis are allowed for. All 32 check out on the grid.
    - The 5,200 lit windows snap onto painted ones, at the painted size. Frames and beams are scaled to match.
  - **Fewer boxes:** 60% fewer apartment blocks on each base floor (keep chance 0.32 instead of 0.8). Hall columns are unchanged (the user's call).
  - **Barnacles on the floors, cheaply:** a 45% chance on each base storey and each mezzanine, 60% on each hall floor (21 spots, `Megastructure.floor_nests`). Each nest is grown only while a player is within 90 m and freed once everyone's 140 m away. The fixed nests are now 10, all on the outside walls.
  - **The depths' fog (a bug):** the valley haze thickens with depth below its height, made for the land's low ground. At ~260 m underground it became a solid wall. BiomeAtmosphere turns it off while the camera is below `underground_y` (-15 m); the rest of the fog stays.

- 2026-10-10: **More window entrances, no big holes, the worm comes when you arrive at the Stack.**
  - **Window rooms:** 3–6 a hall (was 2–4), 50% more (the user's ask), on all five towers.
  - **The main tower's base:**
    - Its walls are solid now. The two 34 m gaps on every storey of every side are gone; the user didn't like non-window cutouts.
    - Kept: the bridge's way in (+X, storey 1, at z 30), the lift dock's (-Z, storey 1), and the torn wall (+Z, storeys 1–2).
    - Windows cut into them instead (`_base_windows`): two a side per storey, each exactly one painted window, straight onto that floor. A third are lit: a lamp just inside, the glow and the beam.
    - Base wall pieces are solid (carvable); too thin to be occluders.
  - **Totals:** 67 lit window entrances (46 rooms + 21 base windows), all on the painted grid; 110 lamps (distance-faded at 400 m); 35 entrance eye clusters.
  - **WormDirector:** a megastructure Lair is the worm's home. A player arriving within 350 m of it (`arrival_range`, across the ground) calls it up at once: the build-up, then the eruption, whatever the cooldown (the user's ask). Once per arrival: again only after everyone's left that range and come back. Megastructure lairs no longer use the hunger route.

- 2026-10-10: **Halls take up much more of the Stack; lift call buttons.**
  - **Halls (the user's favourite):** 15, much taller (the main tower's 900–1400, 3300–3700, 4650–4960 and a new 1900–2400; towers 1–4 each get a new one too). Halls over 250 m tall get three mezzanine levels (0.25, 0.5, 0.75), each up its switchbacks.
  - **Everything that joins a hall moved to its floor:**
    - lift stops 40 / 900 / 4650;
    - hollow bridges at 900, with towers 1 and 3's mid halls sharing the main tower's floor;
    - the broken bridge and the cable car both at 3306 (deck = floor + 6). Before, the cable car's doorways came out 40–60 m up the hall wall with no way up. Its line is set so it never crosses the bridge's.
  - **Window rooms come with the halls:** 86. Only half get a lamp inside (all keep the glow and beam): 99 lamps.
  - **Lift buttons (the user's ask):** LiftButton (`scripts/world/lift_button.gd`), a usable like the map's buttons (F).
    - A call button on each lift stop's dock; a panel on the deck sends it to the next stop (back down from the top).
    - The lift waits until called (`StackLift.on_call`), its buttons lit amber when it's ready and red while it travels.
    - The cable car still runs by itself.

- 2026-10-10: **Harvestman: leech-legged only, no rush, legs no longer vanish.**
  - **Only the leech-legged Harvestman spawns** (the user's call). EncounterDirector's `HARVESTMEN` holds just it; `harvestman_level.tscn`'s barnacle one is now a leech one. Companions copy their leader's scene, so they're leech ones too. The other variants' scenes stay (unused).
  - **No rush** (`can_rush`, off). It walks at you and uses its other attacks.
  - **Missing legs (a bug):** the leech legs' and the proboscis's batches are drawn in world space from the world's origin, with a fixed visibility box of ±500 m round it. Any Harvestman more than 500 m from the origin (the roaming ones, the Stack's) had them culled even right in front of you. `_follow_bounds()` moves the box with it every frame (70 m × size round it).

- 2026-10-10: **Every window has a room, every room leads to a hall: two a hall.**
  - The base windows (cut straight onto the base's floors, with no room) are gone. The base walls stay solid, with their three ways in.
  - Window rooms (`_window_room`): exactly 2 per hall (the user's call), 30 in all. Each goes first to a side of its tower that doesn't have one yet, so every side of all five towers has at least one. Checked.
  - Each is one painted window on a painted spot, a room behind it (its floor at the sill, a warm lamp in half), and a corridor at its back into the hall.

- 2026-10-10: **Sewer growth inside the Stack; a drone you can actually hear.**
  - **Indoor growth** (the user's ask: the sewer growths that would make sense growing in there, in the same kind of clusters). `StackBuilder._indoor_growth` scatters them in the same Pareto clusters as outside (GrowthSpecies sizes) on the floors it records as it builds (`growth_floors`): the hall floors and mezzanine decks (60% of them), the base, and the window rooms. Each place has its own mix:
    - halls: mould, eggs, shelf fungus, grubs, tendrils, cocoons, boils, slime caps, black vines;
    - base: damper, with more slime caps and boils;
    - window rooms: only a little of the quieter ones (mould, shelf fungus, eggs, cocoons).
    - Hive mounds and chitin ribs stay outside (too big for a room). Nothing grows in the shaft, the lift's way or the ramps.
    - About 1,000 pieces in 112 batches (MultiMesh), under Decor/IndoorGrowth, each batch drawn only within 220 m.
  - **The drone was inaudible**: it was all 38-113 Hz tones and a rumble under 40 Hz, which laptop speakers and most earbuds can't play.
    - Rebuilt (`make_drone`): a 55 Hz buzz with its overtones (two voices beating slowly) through a resonance gliding between about 150 and 330 Hz, so it moans, with the rumble under it, lightly saturated.
    - About half its energy is now above 120 Hz, against 12% before: roughly 9 dB more of it where ordinary speakers play.
  - **Where the sounds are** (unchanged): the drone is full inside and fades in within 500 m of the base. The wind rises with height (off below 60 m, full from 400 m), plus 3 voices on the nearest openings within 70 m.
  - To use your own recordings: set `wind_stream` and `drone_stream` on TheStack/Decor/Sound, or point `make_the_stack.gd`'s WIND/DRONE at them.

- 2026-10-11: **Grapple: 60% more reach, 30% harder pull** (the user's call).
  - `max_range` 35 -> 56 m: the reach at full charge. A short charge still scales it down from there, and the landing ring follows it.
  - `pull_accel` 42 -> 54.6 m/s per second: you get up to speed 30% faster. The top speed (`pull_speed` 15.6) is unchanged.
  - Every grapple value is an inspector setting on the Player's PlayerGrapple node, in groups: Charge, Lash, Pull, Big Enemies, Look.

- 2026-10-11: **Skybridges clear of windows and the lift; lift to 60%; plain bridges; grapple on right mouse.**
  - **Skybridges blocked window rooms and the lift (the user's report).** They ran from tower middle to tower middle, straight through the towers' insides and in front of whatever was on the way.
    - Now they're placed last (`_place_sky_bridges`). Each runs only from one tower's face to the other's: `_exit_face` finds the face, and the bridge is sunk in just enough that no corner leaves a gap.
    - Each keeps 4 m clear (`BRIDGE_MARGIN`) of every carved space (halls, window rooms and their corridors, the shaft, every passage), of a box 25 m out in front of every window, of the lift's way up (car, docks and cable), and of the broken bridge and cable car.
    - One that would touch any of them moves up or down 8 m at a time until it's clear, or is left out. 22 stay where they were drawn, 3 moved and 9 were left out: 25 of the 34.
    - Checked: none touches a window's front, a carved space or the lift's way.
  - **The lift tops out 60% of the way up** (the user's call): stops at 40, 900 and 3000 m of the main tower's 5000. The main tower's high hall moved down to 3000-3400 m to take the top stop. It and tower 1's high hall are still both open at 3306 m, for the broken bridge and the cable car. The crown (4650 m) is now reached on foot and by grapple.
  - **Bridges are plain concrete** (the user's call): the skybridges, the entrance bridge and the broken bridge no longer use the windowed texture.
  - **Grapple on right mouse** (the user's call). Only the sniper aims down the sights (`can_aim`), and it's two-handed, so right mouse aims the sniper and throws the grapple with anything else out (`PlayerMovement` input). E still grapples too, so you can grapple with the sniper out (switching to your one-handed gun, as before).

- 2026-10-11: **Rule 10 added: the user chooses every creative detail** (the user's ask). Claude offers options in rounds and never fills in a creative detail itself.

- 2026-10-11: **Two new towers -- the hive and the stump -- and cobwebs with spiders.** Every detail the user's (Rule 10).
  - **The hive** (tower 5, `StackBuilder.HIVE`): 4,500 m tall and 180 m wide, packed into the cluster's southeast gap between towers 1 and 3 (320, -240). Same stepped blocks as the rest.
    - Worn down: chunks bitten out of its blocks' corners and top edges, and 3 ragged holes a hall punched through its walls (24 in all; `_hive_bites`, never through a window room). Stained concrete (`make_concrete(stained)`: darker, black runs, green-black moss).
    - Growth bursting out: on top of the Stack's usual outside growth, its own pass about as big as the whole Stack's (vines, pillars, fungus, spires, eggs, mould), and black vines spilling out of every hole.
    - Dark: no lit windows, no blinkers. Its only light is the growth's sickly glow in its holes (`_hive_glow`).
    - 8 halls, choked with growth (3x: `HIVE_GROWTH`, on the floors, landings and ramps; `growth_floors` can now be tilted, with `xform`).
    - Instead of mezzanines, **panic stairs** (`_panic_stairs`): landings at any angle and stair flights (`RAMP_SLOPE` at most, walkable), tangled up through the lower 60% of the hall, so the air above stays open for the grapple. It's grown from the floor; every leaf then gets a second flight or is removed, and loops are added. So it all connects with **no dead ends** (checked: 0 in every hall). About 30 flights a hall; the narrow top three fit 18, 15 and 6.
    - Ways in: the skybridges (like any tower), plus its only 2 windows, dark, into its two lowest halls (`HIVE_WINDOWS`). No other windows.
  - **The stump** (tower 6, `STUMP`): 600 m tall and 120 m wide, fused to the main tower's -X side (`_stump_blocks`: two stepped blocks, each sunk 3 m into the main tower's wall, never into its insides; checked).
    - Its hall (440-600 m) is open to the sky. Its walls are broken off partway down on its three open sides, and rubble is heaped on its floor (`_stump_top`).
    - It breaks through, 70 m wide and 90 m tall, into a **new main-tower hall at 440-600 m** (`HALLS[0][4]`; checked open).
    - No window rooms on the fused walls (`_fused`).
  - **Cobwebs** (`_cobwebs`, `shaders/cobweb.gdshader`, the PSX Mega Pack's 4 web decals).
    - Inside: about 1 for every 3 halls (8), across a corner of a hall or a window room. Most are 2-6 m; 15% of the hall ones are 15-30 m.
    - Outside: 2 a tower, huge (15-30 m), across the corner where a block's top meets the wall above it.
    - Pale with a glint, completely still: a quad each with alpha scissor (the strands are 10-25% alpha, strengthened 4x). No vertex work, nothing run per frame (the user's).
    - **Spiders at every web** (`Megastructure.webs`, `_update_webs`, host only): a SpiderPack in a RoamingGroup patrolling round the web. 4-8 spiders for a 2 m web, up to 20-30 for a 30 m one. Patrol radius 20-50 m by size (outside, kept within the ledge). Magnified indoors like the rest of the infestation. Each horde is there while a player is within 120 m of its patrol and gone once everyone has left, like the floor nests.
  - Test world: the Stack's plateau widened to 560 m (`STACK_PLATEAU`; the hive's far corner is ~530 m out). It takes effect on the next test-world bake.
  - Counts: 25 halls, 36 window rooms, 28 skybridges (19 as drawn, 9 moved, 6 left out), 3,387 indoor growths in 189 batches.

- 2026-10-11: **Human gangs roam the whole map** (the user's ask; every number the user's). The EncounterDirector's bands can now be a gang of tweakers (`Band.TWEAKERS`): `gang_min`..`gang_max` = 6-12, weight 1.5 in both biomes (about 1 band in 7: 14% in the sewer, 16% in the reef). The megastructure camps stay as they were.

- 2026-10-11: **Co-op step 1, the core (not run yet).** Host and join by IP, the Half-Life 2 / Source model (Rule 1). Compiles; untested until the user says yes to a run.
  - `scripts/net/network.gd` (autoload **Network**): host (ENet, UDP port 7777, up to 4 players), join by IP, leave, status.
    - A joining client loads the host's scene fresh, then says it's ready with its character. The host makes its body (`Player_<id>`, owned by that client: `set_multiplayer_authority`) on every machine and sends it the bodies already there.
    - The scene's own Player is the host's body.
    - Offline nothing changes: `Network.is_online()` is false and everything runs as before.
  - **Players** (`PlayerMovement`):
    - Your own body is simulated at once on your machine (prediction). Each tick's input goes to the host as a packet: move, where you're looking (absolute, so a lost packet can't leave your aim off), buttons as bits, weapon pick, sent with the previous two inputs in case one is lost.
    - The host runs each client's packets in order on its copy of their body (exactly their moves, as Source runs user commands) and sends every body's state 30 times a second: position, look, health, dead, weapon, grapple tip.
    - Reconciliation: the client compares the host's position for a given packet with where it predicted itself at that packet. A small difference is eased in, more than 3 m is jumped, and all later predictions shift by the same amount so nothing is counted twice.
    - Other players' bodies are shown 100 ms behind the host's newest update, interpolated, with velocity worked out so their run/idle plays. Their weapon and grapple line follow the host's word (`PlayerGrapple.rope_tip/show_remote`).
    - Health comes from the host: drops go through `take_damage` (HUD, flinch, death).
    - Death in co-op is a respawn beside someone alive (host-decided, `respawn()`, `respawned` hides the HUD's death label), not a level reload.
    - The shooter's id is the body's owner (`get_multiplayer_authority()`), not this machine's.
    - Hit-stop slow motion is off online (`Engine.time_scale` is the whole game's).
    - The keys are ignored while a menu has the mouse (the game runs on under the pause menu in co-op).
  - **Shots and explosions:**
    - Only the host's `resolve_shot` hurts anything. A client's own shot casts the same rays for its tracers, blood and holes. The host sends the hit marker back (`_net_hit`), and other players' shots (`_net_shot` tracer per pellet, `_net_fired` sound once a shot).
    - `Explosion.explode` hurts only on the host. Its look goes to everyone who didn't set it off (`Network.send_explosion`).
  - **Enemies** (`scripts/net/net_entities.gd`, NetEntities): the host gives every creature in "enemies" (or `net_entities`) an id.
    - Each client gets a spawn when one comes within 320 m of its player (900 m for big ones), 20 updates a second (position, rotation, health, plus `net_state()` extras), and a despawn when it's gone.
    - The client makes a puppet from the same scene: meta `net_puppet`, physics bodies frozen, size settings pinned. Puppets are shown 100 ms behind and interpolated, with their velocity set so their animation plays.
    - Health drops go through the puppet's own `take_damage`, so flinches and deaths play the same as offline.
    - Creatures that are part of the scene are found by their path rather than made again.
  - **The Stack:**
    - The lift and cable car run the same motion on every machine. The host sends their exact state 10 times a second, and a client runs it on by half its ping, so the platform under you matches the host's (`StackLift._sync`). A button press is predicted like any input.
    - Its hordes, web spiders and camps are ordinary host spawns, carried by NetEntities.
  - **Loadout:** bodies made later (joiners) get theirs too.
  - **Pause menu:** a Co-op panel (status, Host, IP + Join, Leave, how to test alone). Online, Esc doesn't pause the game.
  - **Chunks:** the host streams chunks round every player (it already did). The ground's collision is the whole map's everywhere (Terrain3D FULL_GAME), so a far-off player costs the host only their chunks. If that's too much, the first fix is a smaller radius round remote players.
  - **Still to do in step 1** (the user's call: synced, not switched off): the boss worm and the barnacles. Then a test run.
  - **To test alone:** run two copies (Godot: Debug > Customize Run Instances > 2). Host in one, Join 127.0.0.1 in the other.
  - **Full compile check** (scratchpad `full_check.gd`): every script under scripts/ and tools/, with the autoloads stood in as engine singletons. It caught a deliberately broken script. 133 scripts, 0 failures.

- 2026-10-11: **Co-op on a LAN: games found automatically** (the user's ask: same house, same Wi-Fi).
  - While hosting, Network broadcasts a small UDP announcement on the local network once a second (port 7778, tagged so nothing else's broadcasts count; `LAN_*`).
  - The Co-op panel listens while it's open and lists every game it hears: "Join <name>'s game (address, N in)", one click. Games drop off 4 s after their last announcement.
  - The panel also shows this machine's LAN address (`Network.lan_addresses()`), for typing it in if the list doesn't show the game (e.g. Wi-Fi with client isolation).
  - Windows asks to let the game through its firewall the first time: allow it on private networks.

- 2026-10-11: **Support arm: IK as the posing tool, baked per gun** (the user's: "IK + per-gun hand poses", elbow out to the side in an L, hand cupped under, a cup setting, and bake the pose rather than run IK).
  - `FirstPersonArms._solve_support_arm`, step by step:
    - the hand is cupped (`support_cup`: 0 flat .. 1 fist) and turned so its fingers run across under the gun and its palm faces up;
    - the wrist goes where that puts the hand's middle exactly on `support_point`;
    - the shoulder moves to where an arm bent `support_elbow_degrees` (90 = an L) reaches it from (its end is off screen);
    - the elbow comes from the bones' lengths (law of cosines), out along `support_elbow_direction`;
    - upper arm and forearm sit on **one hinge** (the rig's elbows bend round their bones' X), so nothing twists at the elbow;
    - the palm's remaining roll is split between forearm and wrist (`support_twist_share`), since the rig has no forearm twist bones.
  - Checked headless: the hand lands 0 mm off its target, the bend comes out exactly as set, and the elbow points where it's told.
  - **Found:** the twisting the user kept seeing is anatomical. In this rig a zero-twist hand faces along the elbow's hinge, so with the elbow out to the side, palm-up needs ~170 degrees of forearm roll (~130 even with the elbow down). Whatever the split, something has to turn a lot, so it's tuned by eye and baked.
  - **Tuning (F2, then K on a two-handed gun):**
    - arrows / PgUp, PgDn: the grip spot;
    - Shift: turn the hand;
    - Alt + arrows: the elbow's direction; Alt + PgUp, PgDn: its bend;
    - `[` `]`: cup; `,` `.`: the forearm's twist share;
    - **B bakes** the pose onto the gun (`support_baked_pose`, every left-arm bone, fingers included), and F3 saves it; N unbakes.
  - Baked guns just play the pose back: no IK at runtime.
  - Replaced: the old aimed-direction exports (`support_upper_arm_direction`, `support_forearm_direction`, `support_hand_roll_degrees`, `support_hand_open`) and the nudge onto the barrel.

- 2026-10-11: **Lift landings clear of skybridges; window rooms +30%; `Net` helper.**
  - **A skybridge blocked a lift landing** (the user's report). The lift's keep-clear column was sized from the main tower's widest block. Higher up the tower is narrower, so the walkway from the lift to the tower's opening runs further in than the column reached. Now every landing is its own keep-clear zone (`lift_landings`: from beyond the car to inside the opening, 40 m wide, up to 40 m over the floor). Checked: none touched.
  - **Window rooms +30%** (the user's): each hall gets 2 and a third in 60% of halls (`WINDOW_THIRD_CHANCE`, 2.6 on average), still only on painted windows, each with its room and corridor into the hall. The hive keeps its own 2. This build: 49 (was 36).
  - **Bug fixed along the way:** `StackLift` used the `Network` autoload, which doesn't exist in bake tools, so a rebuild would have left the Stack with no lift or cable car. New `scripts/net/net.gd` (**Net**: `is_online(node)`, `half_ping(node)`) asks the node's own multiplayer instead. World scripts use Net; `Network.is_online()` now just calls it. Checked: the rebuilt Stack has both (3 and 2 stops) and its 3 call buttons.

- 2026-10-11: **Radios in the window rooms** (`scripts/world/radio.gd`, Radio; every detail the user's).
  - Half the window rooms have an old radio on the floor (`StackBuilder.RADIO_CHANCE` 0.5; this build has 26 in 45 rooms). Each is any of the entertainment pack's 4 radios (`art/Entertainment`), chosen at build time.
  - A physics prop (RigidBody3D, 4 kg, a box fitted to its model, the PS1 look): pick it up with F and toss it on release like any prop. It keeps playing wherever it lands.
  - **Music:** every .ogg/.mp3/.wav in `audio/music/radio/` (the user fills it; add or remove songs any time, no rebake). Each radio picks one, seeded from its place, so co-op players hear the same song.
  - **Sound** ("both", the user's choice): two voices play the song in step.
    - The radio's own **voice** (bus RadioVoice: 380 Hz to 3.6 kHz, a little lo-fi grit, like an old speaker) reaches 45 m.
    - The hall's **echo** (bus RadioEcho: muffled to 1.8 kHz, delays at 340 and 610 ms with feedback, a vast reverb, nearly all wet) reaches 220 m, muffled further with distance.
    - The echo fades as you close in (+2 dB from 70 m out, down to -14 dB at the radio), so far off it's a smeared echo rolling through the halls, and up close it's the tinny radio itself.
    - Both buses feed Ambience (its volume slider).
  - **Cheap:** a radio only plays within 220 m (checked twice a second). Coming back, it picks the song up where it would be by now, as if it never stopped.
  - Checked headless: all 4 models build with collision, both voices play a song from the folder, and the buses are made.

- 2026-10-11: **Worm dirt follows the land; the shockwave throws again; more inside cobwebs; a Music slider.**
  - **Worm effects on the terrain** (the user's ask: the mound, the dirt it pushes, its holes, all following the land, not one flat level).
    - The dirt shader (`worm_dirt.gdshader`) now reads Terrain3D's own height maps: its private uniforms, copied from the terrain's material by `WormFX.link_terrain()`. Every vertex of the mound, bow wave and furrow sits on the real ground under it (bilinear between the terrain's vertices), with the dirt's height on top; normals include the ground's slope.
    - Only under the open world's terrain (custom.w + 2, from `BurrowWorm._on_terrain`). A level's floor and a cave stay flat, as before.
    - The landing ring lies on the ground and tilts with it.
    - Dust bursts, the trail puffs and the body's crossing puffs sit on the real ground under each point, facing its slope (`WormFX.ground()`: Terrain3D's height and normal, no raycasts). Breach holes already used the hit surface.
  - **The shockwave didn't throw anyone** (the user's report). A bug from making the boss 2x: `_apply_size` doubled `shockwave_radius` but not `shockwave_force`/`shockwave_lift`, so a 24 m ring pushed like a 12 m one, and ground friction ate it.
    - Fixed: the throw scales with size too (the boss: 28 m/s out, 20 up at the middle).
    - Players get a squared falloff (strong over most of the ring), so a landing sends you flying.
    - Co-op: the host also sends the shove to the player's own game (`PlayerMovement._net_shove`), so they're thrown, not dragged back by corrections.
  - **Inside cobwebs 50% more common** (the user's): about one for every two halls (13 inside this build, was 8).
  - **Music has its own slider** (the user's): a Music bus (`default_bus_layout.tres`, `GameSettings.AUDIO_BUSES`). The radios feed it instead of Ambience, so the ambient stings and the music are set separately. It goes through the SFX bus's PS1 crunch like everything else (the user's).

- 2026-10-11: **Play works again; lag compensation (Source's).**
  - **"Couldn't detect whether to run the editor..." on Play** (the user's report): the project's main scene points at `test_world.tscn` by uid (`uid://8csi35th24b5`). The test-world re-bake saved the scene with no uid (a `--script` save doesn't write one), and the editor then gave it a new one, so Play couldn't find the main scene. Fixed: the scene has its uid back, and `make_test_world.gd` now reads the uid from the scene's header before saving and puts it back after (`_uid_in_header`; `ResourceLoader.get_resource_uid` needs the editor's cache, which a `--script` run doesn't have).
  - **Lag compensation** (the user's ask, "however AAA games or Valve do it": Source's, since Half-Life):
    - The host keeps every creature's transform over the last second (`NetEntities._record_history`, every physics frame).
    - A client sees creatures in the past: its round trip plus the 100 ms interpolation. When the host runs that client's input (`PlayerMovement._run_their_inputs` passes when it arrived), its hitscan shot first moves every living creature within the gun's range back to then (`rewind_for`), casts, and puts them back (`restore`), all in the same instant. Aim where they are on your screen and it hits.
    - The whole creature moves, skeleton included, so head and artery hits are judged where they were.
    - Its bodies are made static for that instant: in Jolt a kinematic body only goes where it's put at the next physics step, a static one at once. They go back to kinematic after.
    - Checked headless end to end: rewound, a ray at the old spot hits and the real spot misses; restored, the reverse, and the body's mode is back.
    - Hitscan only: rockets and grenades fly in real time on the host, as in Source. The known trade-off (Source's too): a target can be hit just after ducking behind cover, because on the shooter's screen they hadn't yet.
  - `Net` (`scripts/net/net.gd`) gained `round_trip_msec(node, peer)` and `body_of(node, id)` (returns Node3D: naming PlayerMovement would tie Net to the player's script, which needs the game's autoloads, and Net has to load in bakes). NetEntities uses Net, not the Network autoload, for the same reason.

- 2026-10-11: **The Stack's original low drone is back, subtle** (the user's: the buzzing hum near the Stack was far too loud -- they'd had their audio off before). `make_drone` is the original again: 38-113 Hz tones beating against each other and a sub-40 Hz rumble, a bassy hum felt more than heard (checked: it measures the same as the original). The Stack plays it at `drone_volume_db` -8 dB (was +2), a setting on TheStack/Decor/Sound.

- 2026-10-11: **The Stack's wind like a real building; the radios clearer up close, one song at a time.**
  - **Wind** (the user's: far too loud; only right by windows, or high up by the clouds outside; inside it should come only from the windows and outside):
    - The open-sky wind plays only OUTSIDE (in none of the sound's `inside_zones`: every hall, the base and every window room) and up by the clouds. It fades in from 300 m under the cloud deck (its height read from the scene's CloudDeck, 1300 m in the test world) and is full 60 m over it. Inside, none at all (it was a quarter).
    - The window and opening voices are heard only right by them (`opening_reach` 18 m, was 70; `unit_size` 2.5, was 12), so inside, the wind you hear comes from the windows and holes.
    - Quieter: `wind_volume_db` -12 (was 0).
    - Checked headless: by the clouds outside, -12 dB; in a hall at that height, on the ground, or 30 m from a window inside, silent; 4 m from a window, its voice there.
    - (Found on the way: `Rp`, the edit helper I'd named, is PowerShell's alias for Remove-ItemProperty, and an alias wins over a function. The edits hadn't applied; nothing was removed. Helpers are now `Swap-Text`.)
  - **Radios** (the user's: drowned out and tiny up close; clearer and less echo the closer you are; never two songs at once):
    - A third voice, CLEAR (bus RadioClear: only the lowest rumble cut), takes over within a few metres. The tinny AM voice covers the middle distance, and the echo is for far off, falling to -30 dB right by the radio.
    - Only the nearest radio in earshot plays. Another takes over when it's clearly nearer (within 80% of the distance), the old one fading out as the new one fades in. Radios not playing stop their players.
    - Checked headless: 2 m from A, clear +2 dB, echo -30, B silent; 25 m, the tinny voice; 90 m, the echo at full; 2 m from B, A silent and B clear.

- 2026-10-11: **Rule 11 (hardcore) added; the climbing vision written up** (`docs/CLIMB_VISION.md`: everything decided for the climbing direction, what's out for now, and the build order).

- 2026-10-11: The "ideas not turned down count as wanted" rule was meant for that one list only (the user's correction): it's not a standing rule, and is gone from Rule 10. The climbing list's decisions stand.

- 2026-10-11: **The grapple reworked: set it, then launch; one shared stamina (4 bars).** Every rule the user's (docs/CLIMB_VISION.md).
  - **Stamina** (`PlayerMovement`): one shared pool, 4 bars (was 3), now fractional (`stamina`). A dash, a wall jump and a grapple each spend one bar (`spend_stamina()`). While the grapple holds you it drains (`drain_stamina()`, `PlayerGrapple.drain_per_second` 0.25: a bar every 4 s) and doesn't refill. The HUD builds its pips from `max_stamina_charges`. Respawning refills it.
  - **The grapple** (`player_grapple.gd`; states NONE, LASH, LAUNCH, PERCH, HANG, RIDE, MISS). Its own charges are gone (the pause menu's Infinite Grapples now means no stamina cost or drain).
    - Hold right mouse to charge (the ring as before). It fires only once held at least half of `charge_time` (no cost if let go sooner).
    - Let go within `good_window` (0.15 s) of it filling: `charge_timed` (a chime) and a `charge_boost` x1.12 faster launch.
    - When it bites you're **launched** straight at the spot at `launch_speed` (32 m/s at full, 75% at half charge), no gravity, no air steering. It follows a moving spot.
    - A press in the last `perfect_window` (0.3 s) of the flight: `launch_timed` (a second chime), you let go and fly on x1.15 faster.
    - Arriving, or stopped short by something in the way, you **perch** on the wall at the spot. Back (S) **rappels** onto the line, hanging under the spot with gravity and a little sway (`rappel_speed` 4.5). Forward (W) **reels** back up to the perch (`reel_speed` 3). Space lets go with a hop.
    - **One at a time:** a new grapple only once this one's let go.
    - Big enemies: launched at, then kicked on arrival, or press during the flight to ride (as before).
    - The chimes are generated placeholders (`charge_timed_sound`/`launch_timed_sound` take the user's sounds), local to your own game.
  - Checked by driving the real player with input packets, as the host does: under half a charge, nothing fires or is spent; a timed full charge gives the reward and launches to a wall 30 m off and perches; a press while perched starts nothing; rappel and reel work; Space lets go; a perfect mid-flight press gives the second reward (28.6 to 32.9 m/s).
  - (From now on no test or check runs without the user's yes.)

- 2026-10-11: **The diegetic backpack (stage 1 of camps and death).** Every rule the user's (docs/CLIMB_VISION.md).
  - **Backpack** (`scripts/backpack.gd`, a node made on every Player): everything but the gun in your hands -- the second gun, ammo, grenades, pills, bandages, and its own scrap, silk and camp kits (one at most; you start with one).
    - 12 stacks (one a kind).
    - Weight (kg a unit, `WEIGHTS`) slows stamina refill past 6 kg, down to 45% at 22 kg (`refill_scale()`, recounted twice a second).
    - `use()` from a click: pills/bandage taken, the spare gun swapped into your hands, grenades taken out, a camp kit brought out to place (`placing_camp`, for stage 3).
    - The WeaponController still counts guns, ammo, pills and bandages; the backpack is the view and the rules.
  - **Two guns** (`WeaponController.MAX_GUNS`): one in hand, one in the bag. A third picked up takes the hand's place, and the old one drops at your feet as a real pickup (`WeaponPickup.drop()`, ignoring you until you step off it). Starting weapons are capped too. The test Loadout gives the pistol, the shotgun and grenades.
  - **The weapon wheel is off** (`hud.gd` `WEAPON_WHEEL_ENABLED`), kept as a future option: guns are swapped through the backpack.
  - **Tab** (`PlayerMovement.bag_open`, in the input packet) brings the bag out.
    - Your left arm swings it off your back and holds it up by the top handle in a fist (the support-arm IK: `FirstPersonArms.set_bag`).
    - Its top unzips (`shaders/backpack_open.gdshader`: the top cut away, the inside darker).
    - A cursor appears (looking stops, walking doesn't: it's real time). No shooting, aiming, throwing or grappling while it's out.
    - Tab puts it back.
  - **Inside** (`scripts/backpack_view.gd`): every item a prop -- a pills packet, bandage, ammo box, shells, tin can (scrap), silk cocoon, rolled sleeping pad (kit), the spare gun shrunk to fit inside (the user's: never through the bag) -- in a small physics world in the bag's own space.
    - The items are boxes that fall, slide, pile up and knock apart, pushed by gravity (tilted with the bag) and the bag's own movement; they lean as they slide.
    - On your back the same world steps ten times a second, positions only, from your body's movement, so climbing rearranges them.
    - The item under the cursor gets the interactables' yellow outline; click it to use it.
  - **How it's held** is `BackpackHold` (`scenes/player/backpack_hold.tres`): the bag's place, turn and size; the hand's place on it, its turn and fist; the elbow; the unzip; the items' space. Tuned in game with F2 then O (bag open), F3 saves.
  - **On your back:** the pack rides the character's upper chest bone (`PlayerModel._wear_backpack`), gone while you hold it out.
  - Compiled (with the user's yes): 138 scripts, 0 failures. Not yet seen in game.
- **More enemies up the towers; barnacles thicker higher up and bursting at you (2026-10-11).** The user's: spiders and humans more common, humans camped on the towers' floors, barnacles more common the higher you go, and a barnacle you get too close to spurts out its brood.
  - **More spiders and humans** (x1.5): the roaming bands' weights (`EncounterDirector.WEIGHTS`: tweakers 2.25 both, spiders 3.0 / 4.5) and the Stack's infestation (`Megastructure.spider_hordes` 3).
  - **Gangs in the towers** (`Megastructure.gang_spots`, from `StackBuilder`): on the floor of about one hall in three (`GANG_HALL_CHANCE`, not the hive, clear of the main shaft) and on some mezzanines (`GANG_DECK_CHANCE` 0.15). 6-12 tweakers (grunts, gunners, rushers) camp there while a player's within 160 m; gone once everyone's 240 m off.
  - **Barnacles thicker higher up** (x3 by the top, `NEST_TOP_DENSITY`): a floor or mezzanine's chance of a nest rises from its old chance at the ground to three times it at the top of the tallest tower (two on one floor up there). The outside nests (30 now, `OUTSIDE_NESTS`) grow up every tower, three times as thick at its top as at its foot (`Megastructure.nest_columns`, `_toward_top`).
  - **The burst** (`Barnacle.burst_range` 5 m, `burst_cooldown` 6 s): come within 5 m of an awake barnacle and it swells and spits its brood straight away, again every 6 s while you stay close (up to twice its usual brood).
  - The Stack rebaked. Compiled (with the user's yes): 138 scripts, 0 failures. Not yet seen in game.
- **Backpack fixes, free aim, cheaper gangs (2026-10-11).** The user's playtest: FPS down to ~30, items hard to see, the bag too small, no texture, tuning didn't work, and they wanted to keep looking around with it open.
  - **Free aim** (the user's pick): the mouse stays captured. With the bag open it moves a small dot over the bag first; pushed past the edge of a box round the bag (`BackpackView.AIM_BOX`), the rest turns your view (`PlayerMovement.look_filter`). The dot picks and clicks the items.
  - **On your back, nearly free** (the user's): no simulation any more. Twice a second it adds up how much you've been thrown about (metres moved + jolts); at 40 the items shuffle once and settle (`_shuffle`). Held open it's the full simulation every frame, as before; what's in the pack is checked four times a second, not every frame.
  - **Bigger and clearer:** the bag 60% bigger (`bag_scale` 0.672), the items bigger (`item_size` 0.12), the inside less dark (0.38), the items showing from a third of the unzip.
  - **Texture:** the forest props' model doesn't link its texture; the bag in your hand, the pack on your back and the sleeping pad now use `art/Texture/Texture Forest.png` (`BackpackView.textured`).
  - **Tuning:** O on its own (no F2) with the bag out tunes the hold; it no longer needs a gun in hand. New: Ctrl+Alt + arrows/PgUp,PgDn points the elbow; 1-5 picks a finger (thumb..pinky) for [ ] to curl on its own, 0 back to the whole fist (`BackpackHold.finger_curl`, `FirstPersonArms.set_bag_fingers`). F3 saves.
  - **Tower gangs** (the user's): the main tower only, for now. For the frame rate: they're there within 100 m (was 160), gone past 160 m; their people stand asleep until you're within 70 m (`gang_wake`); they're added one a frame instead of all at once.
  - **Barnacles:** the burst at 4 m (was 5, the user's); the spitting over time is unchanged.
  - The Stack rebaked. Not compiled or run (asks first).
- **Backpack picking with Left Alt; the crosshair is the same dot (2026-10-11).** The user's: instead of the free-aim box, the mouse looks around as normal with the bag open; hold Left Alt and looking stops, the cursor dot appears over the bag's opening and the mouse moves it (kept on screen) to hover and click items; let go and you're looking again (`BackpackView._picking`, `_free_aim`). The crosshair (`scenes/ui/hud.tscn`) is now that same dot -- 7 px, dark outline, pale middle -- and it's hidden while the bag's out. (Alt is also the bag-tuning modifier: holding it while tuning just stops looking.) Not compiled or run (asks first).
- **Backpack items really inside it, never through each other; the bag 30% smaller (2026-10-11).** The user's: the items lay in one flat layer on top of the bag, clipping through each other.
  - **Why:** their space was a thin slab poking above the opening, and wider than the main compartment (into the front pocket's side).
  - **Now:** the space is the main compartment, measured off the model (82 vertices): inside its walls, from a false bottom at about half height up to just under the unzip (`BackpackHold.items_area`). Items fall into it and pile up under the opening, where you see them.
  - **Never through each other:** items turn only in quarter turns, their boxes turned with them, so what you see is exactly what's kept apart; they lean only a little (`MAX_LEAN`); each frame is split into steps of 1/90 s (`MAX_STEP`), each pushing everything apart 8 times (`SOLVER_PASSES`) with the walls last. The shuffle on your back drops them in four falls, settled the same way.
  - The bag 30% smaller (`bag_scale` 0.47), same place (its middle stays put); the items to match (`item_size` 0.084).
  - Not compiled or run (asks first).
- **The grapple's pull back to the original (2026-10-11).** The user's: the straight launch didn't feel as natural as the old grapple. Their pick: the old pull, keeping the newer extras.
  - **Back:** the Titanfall 2 pull (`PlayerGrapple._pull`): once it bites it hauls you toward the spot, building up at `pull_accel` 54.6 m/s^2 to `pull_speed` 15.6 m/s (60% of that at the least charge), easing off near it (`arrive_slowdown` 5), no gravity; you can steer (air movement stays on), and you keep your speed when you let go.
  - **Kept:** the charge (half minimum, the good-timing chime and boost), the 4 shared stamina bars (a bar to fire, draining while it holds you), perching on arrival (and now when pressed against something on the way, getting no closer), rappel/reel, the perfect let-go near the end (`_time_to_arrive` now from your real closing speed), kick/ride for big enemies.
  - Not compiled or run (asks first).
- **The backpack items' box: deeper, and tuned live (2026-10-11).** The user's: the items need to sit deeper in the bag, and they want to match the box to the bag themselves. The box's false bottom is now about a quarter of the way up (`items_area` from y -0.3, 0.56 tall: shares of the bag). In the bag's tuning (O), **X** switches the keys to the box: arrows / PgUp,PgDn move it along the bag's own axes, Shift + those grow or shrink it about its middle, Ctrl finer; it's drawn as a yellow wireframe seen through the bag (`BackpackView.show_box`), and the items keep to it live. F3 saves it with the rest of the hold. Not compiled or run (asks first).
- **Backpack weight: shown, per gun, and it slows you down (2026-10-11).** All the user's picks.
  - **Each gun its own weight** (`WeaponData.carry_weight`, kg): pistol 1, revolver 1.3, MP5 2.5, SMG 3, shotgun 3.5, PPSh 3.6, dual MP5s 5, sniper 5.5, RPG 6.5, PKM 7.5. Everything else as before (`Backpack.WEIGHTS`).
  - **Limits kept:** overweight past 6 kg (`free_weight`), too heavy at 22 kg (`heavy_at`); between them every effect ramps up (`Backpack.heaviness()`, weighed twice a second).
  - **Shown:** only once you're overweight, the weight ("14.2 kg") floats just above the open bag (straight up on screen, a billboard drawn over everything); white, red once too heavy.
  - **What it does at the worst** (all exports on Backpack): stamina refills at 45% (`slowest_refill`, as before), walking/running at 80% (`slowest_move`), jumps and wall jumps 85% as high (`lowest_jump`), the grapple pulls at 80% and builds up as slowly (`slowest_pull`), and holding on drains stamina 1.5x as fast (`heaviest_drain`). The 85% / 80% / 1.5x numbers are mine (the user picked which effects; only the 80% walk was in the question) -- change on Backpack.
  - Weight counts what's in the pack, not the gun in your hand.
  - Not compiled or run (asks first).
- **The backpack is the survival pack's (2026-10-11).** The user's: use the backpack from `art/survival` whose straps sit close, so they don't clip.
  - `Survival.fbx` has two: `Backpack` (straps sticking out 0.56 m to one side) and `Backpack_001` (straps in at 0.29 m). It's `Backpack_001` (`BackpackView.BAG_NODE`).
  - It's stored lying down at 1/170 scale: `BackpackView.pack_mesh()` makes an upright, metric copy once (shared by the bag in your hand and the one on your back), turned so its straps face +x like the first pack -- so the saved hold still roughly fits.
  - Its texture is loaded directly (`BAG_TEXTURE`: `art/survival/Textures/Backpack.png`): the model links it as `art/Survival/...` (capital S), which an exported game's case-sensitive file system wouldn't find.
  - Same size as before: 0.8 m model x `bag_scale` 0.76 = 0.61 m. The items' box refitted to its main compartment (measured off the model): `items_area` (-0.40, -0.32, -0.40) size (0.69, 0.57, 0.79).
  - On your back: straps against you (`PlayerModel._wear_backpack`).
  - The camp kit's sleeping pad still comes from the forest props (`FOREST_SCENE`).
  - Also noted for the camps step (docs/CLIMB_VISION.md): the tent saves, the bedroll sleeps, each its own recipe; in the backpack both show as the rolled sleeping bag. The survival pack has no tent -- to ask then.
  - Not compiled or run (asks first).
- **Backpack items: real rigid bodies in the pack's own shape (2026-10-11).** The user's: the box container wasn't doing it (the shape should match the model, nothing to fit by hand); items should tumble over each other naturally, at about their real size, the long gun taking real room; the new pack exactly where the old one was, same size.
  - **Where it sits:** the 180-degree turn added with the swap was wrong -- both packs have their straps at -x upright -- so it's gone: the new pack's middle, size (0.608 m vs 0.609) and facing match the old one's. On your back its straps now face your back (it was being worn sideways).
  - **The container** is the pack's convex hull (`BackpackView.pack_hull()`, worked out once from the model), brought in by a 2.5 cm wall, with a lid just under the opening; it's built as slabs outside each side (`_build_container`). X in the bag tuning shows it as a yellow wireframe (no editing: `items_area` and `item_size` are gone).
  - **The items** are RigidBody3Ds (Jolt) in a physics world of their own (a never-drawn SubViewport with its own World3D), each shaped like its model (convex, so cans roll), continuous collision, friction 0.55, bounce 0.15. They're pulled by gravity turned into the bag's frame less the bag's acceleration (`INERTIA` 0.6) via constant_force, and a flick of the bag (a change in its turning) swirls them (`SWIRL` 0.35). The props you see copy their bodies.
  - **Sizes** (`REAL_SIZE`, longest side): pills 9 cm, bandage 10, bullets 9, shells 11, rockets 28, grenade 11, scrap 11, silk 12, camp kit 30. A gun is `WeaponData.backpack_length` (pistol 22 cm, revolver 27, MP5 36), else as long as fits across the floor's diagonal (92%).
  - **On your back:** frozen; the shuffle now wakes them with a knock and lets them tumble 1.2 s, then freezes them.
  - The texture paths use `art/Survival` (the folder's real name; my earlier "wrong case" note was wrong).
  - Not compiled or run (asks first).
- **The shotgun is the sawed-off double barrel, one-handed (2026-10-11).** The user's: the new `art/Sawed Off Double Barrel` model replaces the old shotgun, held in one hand, starting from the pistol's pose.
  - `weapons/shotgun.tres`: `Double_Barrel_glb.glb` (its barrels along +z: `model_facing_degrees` (0, 180, 0)), `one_handed`, the pistol's hold animation, and `arms_fitted` off so the Viewmodel fits it from the pistol (`one_handed_arms_template`: the same arms and held angle, its grip seated in the hand) the first time it's shown. Starting numbers measured off the model (4.9 units long): `viewmodel_scale` 0.112 (about 0.55 m), `grip_point` (0, -0.3, -1.6) just behind the trigger, `muzzle_offset` (0, 0.35, 2.43) at the barrels' mouths. Tune in game with F2 (G grip, M muzzle, +/- size), F3 saves.
  - Its two-handed settings (support hand, baked pose, arm nudges) are gone. Stats unchanged (one shell, 8 pellets); weight 2.5 kg, 50 cm in the backpack.
  - The folder's `.blend` files are the model's sources; Godot only imports them if Blender's set up.
  - Not compiled or run (asks first).
- **Simpler AI for the frame rate; bodies stay their 120 s and fade out (2026-10-11).** The user's picks.
  - **Human enemies think 10 times a second** (`Enemy.think_interval` 0.1, the HL2 way): target, gang, aim and state decisions every think, working in the time since the last (`_dt`); moving, gravity and turning stay every tick (turning toward `_want_yaw` in `_turn()`, so it's smooth). A swing or lunge in progress thinks every tick (timed).
  - **Far ones go simple** (past `far_distance` 30 m from every player): thinking every 0.4 s, no aiming (an attacking gunner keeps its aim), and their animation stepped at 10 frames a second (`EnemyAnimator.set_far`, the AnimationPlayer in manual mode).
  - **Ragdoll made at death:** `EnemyRagdoll` builds its 18 bones when the enemy dies, not at spawn (a model that ships its own ragdoll -- the mutant -- still sets it up at spawn); its physics tick is off till then.
  - **Hordes think 10 times a second:** spider packs' and rat packs' steering (each creature's way, roaming, the rats' grid and path) every 0.1 s, every 0.5 s past 40 m from every player; their body hauling and dragging still every tick (it pulls on the body). Roaches unchanged (their every-tick steering is their flight; their target picking was already timed).
  - **Bodies vanishing in ~5 s (the user's bug):** a group's members are its children, and the group freed itself the moment none was alive -- taking the bodies with it. Now it waits till its last body has gone (`RoamingGroup`).
  - **Bodies fade out** at the end of `corpse_time` (120 s, the user's) over `corpse_fade_time` 2.5 s, instead of vanishing.
  - **Pills in the backpack** are the bottle you hold (`pills_bottle_2.glb`), the user's.
  - Not compiled or run (asks first).
- **Backpack items fit and stay inside; guns on the ground at real size (2026-10-11).** The user's: everything in the bag was far too big and poked through it (shrink to fit, or something smarter).
  - **Why:** new items dropped at random points in the bag's bounding box -- the pack narrows, so many started outside its walls and were pushed out through them; the container (the whole pack's hull) took in the gap between the straps and its back; and some sizes (shotgun 50 cm, kit 30, rockets 28) were wider than the inside.
  - **Now:** the container is the hull of the main body only (the straps' 10% of its width left out, `STRAP_CUT`), walls 3.5 cm thick (`WALL`). The inside is measured through its middle (`_measure_inside`: about 35 x 42 x 45 cm), and nothing's longer than 85% of its narrowest width (`FIT_SHARE`, the user's shrink-to-fit). New items drop over the middle of the opening, checked against the walls (`_drop_point`); anything that ever gets outside is dropped back in (`_push_items`).
  - **Tested** (the user's go-ahead; a headless run of the real player and bag, 20 items -- two guns, ammo, pills, bandages, scrap, silk, the kit -- settled, shaken and turned for 4 s, settled again): every item's shape stayed within 2 cm of its wall plane, i.e. at least 1.5 cm inside the pack. Compiled: 138 scripts, 0 failures. (A screenshot of it couldn't be had: the bare test scene renders a flat green screen.)
  - **Guns on the ground** (`WeaponPickup._show_gun`): a dropped gun, and a bare pickup scene, shows its model at about its real length (`backpack_length`, or 0.9 m), with a box round it -- the sawed-off's model is 5 units long. `scenes/weapon_pickup.tscn` (the test map's shotgun) was showing the old shotgun's model: now it shows the sawed-off.
- **The backpack 30% bigger, same spot (2026-10-11).** The user's: `bag_scale` 0.76 -> 0.988 (0.61 m -> 0.79 m tall); it's centred on its middle, so it stays where it was, and the items' container and their fit grow with it. Also dropped the leftover `items_area` from `scenes/player/backpack_hold.tres` (the property's gone).
- **Backpack: the real shape as walls, item sizes, drag and double-click; the sawed-off's own grip (2026-10-11).** The user's asks, in one go.
  - **The walls are the pack's real surface** (`BackpackView._inset_faces`): its mesh pushed 4.5 cm inward along its smoothed normals (`WALL`), as a concave collision shape on its own layer (`CONTAINER_LAYER`), plus the lid; the old hull slabs stay outside as a backstop. A test against the real mesh (rays from the inside's middle to every point of every item's shape) showed the hull let items poke out up to 7 cm: the pack's front slopes in, so its hull was much wider than the real inside (36 vs 29 cm front to back). Now, over repeated runs of 19 items (guns, bullets, shells, rockets, grenades, pills, bandages, scrap, silk, the kit) settled, shaken and turned: 0.0 cm outside, but for a rocket's fin tip once touching 1.2 cm into a corner seam. The inside is measured to the real walls (about 20 x 46 x 35 cm); long things drop in lengthwise; anything whose middle gets outside is dropped back in (`_escaped`). At most 2 of a kind shown (`MAX_COPIES`: a crowded pack squeezes things through).
  - **Sizes:** each kind's own scale (`BackpackHold.item_scales`, the user's): in bag tuning (O), hold Left Alt over an item and scroll; F3 saves. Still never longer than 80% of the inside's long way (`FIT_SHARE`). Grenades 22 cm (the user's: twice as large), rockets 26 cm.
  - **New props:** shells are `shotgun_ammo_2` (a box of modelled shells); rockets are the RPG's own rocket (its `Rocket` part). The "Big Chief" box the user saw was the rockets' `ammo_box_1`.
  - **The straps** are hidden while it's open (the shader's `strap_x`): held up, they lay across the opening.
  - **Drag and use** (the user's): with Left Alt held, press and hold left click on an item to grab it -- it follows the cursor on a plane through it, facing you, kept inside the walls, shoving the others -- and let go to drop it; double-click an item to use it.
  - **The bag 15% smaller** (`bag_scale` 0.84, about 0.67 m), same spot.
  - **The sawed-off's own right-hand grip** (`WeaponData.right_grip*`, `FirstPersonArms.set_right_grip`): its fingers cupped round the grip (`right_grip_cup` 0.85 of the way from flat to the fist), each finger tunable, the wrist turnable; the arm stays where it was. F2 then Y tunes it ([ ] curl, 1-5 a finger, Shift + arrows the wrist, which turns the gun with it); F3 saves.
  - Compiled (138 scripts, 0 failures). The drag/double-click and the grip haven't been tried in game.
- **Fixed: thousands of "apply central impulse ... without a physics space" errors; the backpack's rocket looked like a mushroom (2026-10-14).** The user's reports.
  - **The errors** (`EnemyRagdoll.carry()` from `RoachCarry._lift()`, about 60 a second): since a group keeps its dead members' bodies (the 5-second-vanishing fix), a group gone to sleep (every player far off: `RoamingGroup._set_asleep`) switched its bodies off too -- and a switched-off body is out of the physics world, while the roaches carrying it kept pulling. Now a sleeping group switches off only its living members, and `carry()` does nothing for a body that's asleep or not a ragdoll yet.
  - **The rocket:** in `RPG.glb` the `Rocket` part's mesh is stored squashed, stretched 6.6x along its length by its own node's transform; the backpack copied the mesh without it. It keeps the part's own transform now.
  - Not compiled or run (asks first).
- **Movement rework, Vholume-style: momentum, wall jumps, speed juice (2026-10-14).** The user's picks (the first step of their order: movement, grapple, performance, drops and money, hunger and the vending machine, camps as checkpoints, flares, then the 1v1v1v1 race).
  - **Momentum** (`PlayerMovement` "Momentum" group): gains stop at `speed_cap` 28 m/s (4x a run); nothing slows you to it. **Bhops**: jumping the tick you land skips ground friction and adds 10% (`bhop_gain`); Quake air strafing still gains, capped (`_cap_gain`).
  - **Wall jumps** (the user: "unresponsive" -- only a wall straight behind you counted, once per ground touch): any wall round you in the air (a ring of 8 rays at chest height, `_look_for_wall`); a jump pressed up to 0.15 s before reaching it, or a wall left up to 0.15 s ago, still counts (`wall_jump_buffer`, `wall_coyote_time`); they chain as far as stamina goes (a bar each, as before). Your speed is kept (at least 7 m/s), sent where you look -- mirrored off the wall if you look into it -- pushed a bit off the wall, plus 15% (`wall_jump_gain`), up to the cap.
  - **Speed juice** (`CameraJuice.set_motion`, your own camera only, from a run up to the cap): the camera rolls into strafes and turns and sways; the view widens up to 12 degrees; speed lines rush out at the screen's edges (`shaders/speed_lines.gdshader`); a generated rushing-air loop gets louder and higher; a light rattle past 80%.
  - Reference: VHOLUME (2026) -- momentum kept between moves, bhops with no penalty, wall moves that redirect instead of stopping.
  - Not compiled or run (asks first).
- **Speed juice: no speed lines, no wind rush (2026-10-14).** The user's: took both out; the camera's tilt, sway, speed FOV and rattle stay. `shaders/speed_lines.gdshader` deleted. Not compiled or run (asks first).
- **The grapple's three tendrils and M2 re-attach (2026-10-14).** The user's design (step 2 of the new order; the procedural-Stack direction written into docs/CLIMB_VISION.md the same day).
  - When it bites the level (not a creature), three tendrils shoot on from the spot to surfaces up to 15 m away (`tendril_reach`), fanned ahead the way you're flying, 30 degrees apart (`tendril_spread` FAN_AHEAD; UP_AND_ONWARD -- up and on -- is the other choice, the user's). More angles are tried if one misses; spots closer than 2 m to the bite or each other don't count; creatures don't.
  - Each spot shows its tendril (a dark line from the bite) and an "M2" marker over it (same size at any distance, seen through walls; yellow under your crosshair) -- your own view only.
  - Look right at a marker (within 4 degrees, `marker_aim_degrees`) and right click: re-attached there at once, no charge-up, for half a stamina bar (`reattach_cost`), your speed (at least the pull's) +25% (`reattach_boost`), up to the speed cap, heading there; the other markers vanish at once (the user's), and the new spot sprouts three more -- a chain as long as your stamina lasts. Unused, they stay till you fire a brand-new charged grapple. Works mid-pull, perched, hanging, or after letting go.
  - Not compiled or run (asks first).
- **One stamina meter, insect wings instead of the dash, harder falls; tendrils off (2026-10-14).** The user's design, their numbers.
  - **Falling** (`scripts/fall.gd`, `Fall`): one gravity for the player and every creature (20), 1.7x as strong on the way down -- asymmetric gravity, the usual fix for a floaty jump (Mario, Celeste; a common derivation lands near 1.7x). Jumps keep their height. Spiders and rats were on real-world 9.8, half everyone's -- the "low gravity" fall the user saw: now 20, and harder falling except mid-leap (their leaps are aimed with plain gravity). Human enemies fall harder too.
  - **The meter** (`PlayerMovement` "Stamina"): one bar under the crosshair (`hud.gd`; it was 4 pips), holding 10 s of the grapple holding you. The grapple costs nothing to fire (it needs 0.5 left: `stamina_to_start`) and drains 1 a second while it holds you; wall jumps are free; the dash is gone. Refills 1.5 s after use, empty to full in 10 s (a heavy pack slower).
  - **Wings** (Shift in the air; `PlayerMovement` "Wings"): a burst where you aim to 34 m/s, easing over 0.6 s to a 26 m/s cruise; you fly where you look (turning 150 deg/s, wider the faster) and A/D bank-turns you (80 deg/s), no gravity -- or, switched to `BURST_AND_GLIDE`, a 22 m/s glide that turns slower and sinks. 4 s on a full meter (2.5 a second). Let go, run dry, grapple or land: folded, momentum carries on. Not while grappling. Placeholder look and sound (`InsectWings`): see-through veined wings beating in a blur and a generated buzz -- on others' backs (the host sends `flying`), and in your own view just in front and below, tips at the screen's edges.
  - **Tendrils** switched off (`PlayerGrapple.tendrils_enabled`), the user's: to come back to.
  - Not compiled or run (asks first).
- **Flying in first person: no wings over the crosshair; the hands dip (2026-10-14).** The user's: the first-person wings covered the middle of the screen (not intended: their roots sat in front of the view). Your own wings are now heard, not seen (`InsectWings` builds no meshes in first person; others still see yours). Instead, while you fly, the hands ease down into the reload's lowered pose (`LOWERED_OFFSET`, `LOWERED_TILT_DEGREES`) and back up after -- on the sway layer (`Viewmodel._update_sway`, `_flight_lower`), so the reload's and the switch's own dips are untouched. Not compiled or run (asks first).
- **First-person wing tips flicker at the screen's edges, hands still dipped (2026-10-14).** The user's. Your own wings sit beside your head (`InsectWings`, first person), lying flat, swept forward so they rest just past the sides of the 90-degree view (`FP_REST_DEGREES` 38); each beat swings them 8 degrees in (`FP_BEAT_DEGREES`), so the tips flicker at the lower left and right edges, nowhere near the crosshair. The hands' flight dip stays. (From now on: commits batched, not one per change -- the user's.) Not compiled or run (asks first).
- **The procedural Stacks greybox (2026-10-14).** Step 3 of the new order, every value the user's (several rounds of questions). `scripts/world/procedural_stacks.gd` (`ProceduralStacks`), in its own test scene `scenes/world/procedural_stacks_test.tscn` (the open world untouched).
  - **Towers:** a 5x5 grid built from `world_seed`; footprints 330-600 m (the Stack's x3), heights 1-12 km, every gap between neighbours different, 50-150 m. In the Stack's concrete (`art/megastructures/stack_concrete.res` outside -- the painted windows on the same world grid -- `stack_plain.res` inside).
  - **Halls** 150-440 m tall stacked up each tower. Floors broken through: cave-ins 1 in 3 (15-40 m, rubble heaped on the floor below), small shafts 0-5 at 25% (1.6 m, twice a player), and -- mine, a guarantee -- a 10 m stairwell when an open hall has no cave-in. Inside: stairs and pillars in one of three mixes (2-4/4-10, 1-2/2-5, 4-6/8-16), floating rubble high in the middle and top (5-8, 10-25 m, 30-50 m apart, rising to the way out), a ~50 m lift shaft half the time (cables, ledges by a window out at the top), a rubble slope 1 in 4. 35% of halls sealed: no way up inside, a window out high up, one in low in the hall above. Windows on the painted grid (2 + 66% + 20% a hall: ~10% more than the Stack), 60% with curtains or blinds, 25% with a balcony. Ground floor: a door each side.
  - **Outside:** obstacles every ~8 m up sealed stretches, ~40 m elsewhere (the user: prioritised where you're made to go out) -- pipes, cables across to the facing tower, ledges, AC units, signs, broken bridge stubs; on sealed stretches also floating rubble and rebar.
  - **Plates:** 1-3 per group of 4 towers at random heights; 5 m thick; the middle square plus four arms bridging the gaps wall to wall, 20-30 m long; doorways onto them; a cold white lamp over each doorway; 5-10 clothing lines across the arms (shirt/pant stand-ins); a trader on half of them (stand-in: a stall, a lamp, a character model).
  - **Wind** (`wind_at`, `PlayerMovement.wind_at` + `_blow`): outside a tower and in the air, from 4 km, building to 4 m/s at 12 km, gusting to 7, a prevailing direction wandering slowly. How quickly it takes hold (`wind_grip` 0.8/s) is a placeholder for the user to set.
  - **Streaming:** halls and plates within 700 m up/down and 1.5 km across a player are built in full (one mesh per material + box collision, 8 ms a frame); the rest of each tower is one plain box cut away round what's built.
  - Wind grip set by the user: gentle, about 2 s (`wind_grip` 0.5). The stairwell guarantee kept (the user's). Towers never below 330 m (the gap jitter now leaves at least that); players start at the crossing nearest the middle.
  - Tested (the user's yes): compiled, 141 scripts, 0 failures; a headless build from seed 1 -- 25 towers 1.2-11.2 km, 433 halls (37% sealed), 31 plates; the world planned in under 0.5 s; near the start 88 halls/plates to build, 2.8 ms each typically, the slowest 31 ms; 6 km up, 63, 2.1 ms typically; the wind at 10 km in the open 3.2 m/s. Not yet played.
- **Greybox: towers x2 not x3, and the test world's look (2026-10-14).** The user's: x3 was too big, and the map looked weirder than the test world (the fog). Tower footprints now 220-400 m (the Stack's x2), heights still 1-12 km. The look matched to the test world: its sewer air laid on a copy of the environment (`AlienAtmosphere.sewer()` -- the murky green-brown fog, haze, fill and sun tint its BiomeAtmosphere gives outside the reef), the test world's sun, its cloud deck (`CloudDeck`, at 900 m), the camera seeing 16 km (it was the default, cutting the towers off), and the towers' outside through the Stack's skyline shader so they fade into the murk and the clouds the same way. Not compiled or run (asks first); not committed yet.
- **Greybox halls: the original Stack's, 1.5x (2026-10-14).** The user's: the rooms were too empty; they love the original Stack's interior, especially the halls. Their picks: the original generator 95% of the time and the new mix 5%; towers 1.5x the Stack's widths (165-300 m) so the halls fill them; hall heights the originals x1.5 (240-750 m); and every new thing kept on top (floating rubble, cave-ins and small shafts, lifts and slopes, sealed halls and the outside). How: `StackBuilder._hall_features` -- the same code that built the Stack's halls (mezzanines up switchback ramps, the column grid, the hanging stepped pyramid, the leaning slab, mid-air stairs, its lamps) -- is run in a box 1/1.5 the hall's size and everything it makes is scaled up 1.5x (`ProceduralStacks._original_hall`), so the whole look grows, not just the room. `StackBuilder.new(false)` makes an empty builder for this (its constructor otherwise builds the whole Stack; the Stack's bake is unchanged). Not compiled or run (asks first); not committed yet. Flight missing in this scene (the user's report) still to look into.
- **Focus moves to the open world; feeding off the virus, the Flesh Tree, your right hand (2026-10-15).** The user's: the procedural Stacks wait until co-op is done; survival is built on the open world (`scenes/world/test_world.tscn`). Every value the user's (many rounds; all in docs/CLIMB_VISION.md "Focus now"). Built co-op-ready and aggressively optimized (the user's, twice), with standard AAA techniques: relevance, think-rate throttling, LOD and draw ranges, shared resources, registries rather than scene searches.
  - **Stamina:** the 4 bars and the dash are back. The dash now ADDS 16 m/s on top of your speed for 0.3 s (twice as far), keeps what you went in with, and lifts 30% more (6.5). Wall jumps stay free. The grapple is free to fire and drains 1 bar every 3.5 s while attached to anything. Infinite Grapples is off by default. Momentum is kept by the wings (never slower than you opened them at), mantles (speed given back at the top) and perches (given back when you let go).
  - **Fall damage:** over 22 m/s landing, 3 hp per m/s (softer than HL2).
  - **Virus** (`scripts/virus.gd`):
    - **Points:** fresh +2, rotten +1, boss +3; 14 points = a mutation.
    - **Eating raw:** 35 damage fresh, 90 rotten (Roach gut: 20/50; Chitin doesn't help).
    - **Hunger:** one meter for food and water, full to empty in 20 minutes; empty costs 1 hp every 2 s. Raw meat fills 25%, rotten 15%, cooked 45%.
    - **On death:** the newest mutation withers, the points are lost, and the tree shrinks a step.
    - **The pool:** wings (Shift in the air), Chitin (35% less damage, via `Health.damage_scale`), Roach gut, Rat lungs (+50% refill), Mantis legs (+50% jump height, half fall damage), Spinnerets (+25% reach), Tendrils (the parked ones), and the Tentacle whip (double-tap right click; 0.4 s; 5 m; 50 to everything the tentacle touches, its hitbox capsules along the lash; 1 bar).
  - **The big ones** (`scripts/big_ones.gd`): 75% of every group gets one member at 2x size, 2x health, 0.8x speed and 1.5x damage, made big before its `_ready`. It drops a meat chunk (1 kg from a rat, roach or spider; 2 kg from a person). Bosses (the worm, Harvestman, Rat Bender, Swarm King) drop a 4 kg boss chunk.
  - **Items:**
    - **Meat** (`scripts/carry_item.gd`, `CarryItem`): the user's `New assets/Flesh2.fbx` raw and `Flesh.fbx` cooked; rotten is tinted green-grey, with flies. It rots after 10 minutes anywhere (aged in 2-minute steps, the user's). It cooks in 25 s on, over or within 1 m of a fire, keeping partial progress (checked once a second).
    - **Fires** (`FireSource`: a static registry of distance checks; `BurningBarrel`): a rusty barrel with roaring flames, sparks, a smoke column (seen to 1.5 km) and a 12 m light. They go in half the Stack's window rooms (`StackBuilder._fire_spots` -> `Megastructure.fire_spots`; needs a Stack re-bake), at every Stack gang spot, and at every open-world camp.
  - **Your right hand** (`scripts/player_hand.gd`):
    - **Pulling things in:** the grapple pulls any item (meat, pods, guns, ammo, pills, CarryItems) in at 20 m/s, and the gun goes away. Other props up to 15 kg hang off the tentacle: left click throws them (25 m/s), right click lets go, and holding one drains stamina. Over 15 kg is an anchor.
    - **Using what you hold:** left click uses it ("left click to feed off the virus" shows to its left), G drops it, and F stows it. Grappling a second item stows the first.
    - **The backpack:** double-clicking an item in the bag brings it into your hand. With your hand empty, F (when not looking at a button) stows the gun; both guns can sit in the bag.
    - **The old F prop mover** (`PhysicsGrabber`) is removed.
    - **Looks:** the gripping tendrils show on whatever the tentacle holds. The viewmodel shows the held thing at real size, at most 30 cm.
  - **Screen and sound:**
    - **Trip flash** (`scripts/trip_flash.gd`): one of the user's images from `art/trip/` (black until added), tearing and shaking for 1.5 s, "i shouldve cooked that" (meat only), and a generated noise burst.
    - **Hunger cues** (`scripts/hunger_cues.gd`, under 15%): edges dim to 60% and the hands shake. The growl (every ~10 s) and breathing are sound slots for the user.
    - **HUD:** a thin amber hunger bar under the pips.
  - **The Flesh Tree** (`scripts/world/flesh_tree.gd`, 40 m behind the yard's middle, its roots arching round the yard):
    - **Shape:** a meat-and-bone oak, 0.5 km tall plus 0.5 km per mutation, with its trunk 25 m wide at 0.5 km (keeping its proportions as it grows). A limb comes about every 10 m, spiralling up. About 20 of the user's eldritch creatures are scattered on it.
    - **Growing:** it regrows only when nobody can see it (an engine frustum notifier; clients report to the host), with a new layout seed every time (the user's).
    - **Cost:** one mesh, two surfaces and one trimesh, every look value an export.
    - **Pods:** three pods with random mutations ripen at the top, each with its name shown on highlight; ripening plays a heartbeat and shows "something is ripening". Taking one shrivels the rest. Testing: `pods_on_start` (on).
  - **Yard grass:** Grass_01 within 45 m of the yard's middle, fading out over 10 m (`alien_terrain.gdshader` `yard_*`, set by `TerrainLook`).
  - **Co-op:** NetEntities now replicates things made in code (`net_spawn_args`/`net_restore`) and big ones' sizes. Hunger and the hand/backpack meat go to their owner by rpc. All damage is the host's.
  - **Worm fix (the user's bug, body invisible):** its body's culling box was fixed to ±500 m round the world's origin, and the worm lives about 1.5 km out; it now follows the segments each tick.
  - Edits went through a scratch folder and PowerShell: Windows Controlled folder access blocks the app writing to Documents. Not compiled or run (asks first); not committed yet.
  - **Tested (the user's yes):**
    - **Compiled:** 151 scripts, 0 failures.
    - **Stack re-baked:** 25 barrel spots in its 44 window rooms, plus its 3 gang spots. The bake tools now stand in for the autoloads before loading their body (`tools/stack_bake.gd`, `tools/test_world_bake.gd`), since the Stack and the world now reach `Network`.
    - **Open-world walk-through, headless: 22/22 pass.** Checked:
      - the tree builds (about 6k triangles, a 17 ms rebuild, 20 creatures), and 3 pods are ripe on start;
      - a big person gets 2x health and 0.8x speed, and drops a chunk where it dies;
      - grappled into the hand, the chunk shows the prompt; eaten raw it does 35 damage, gives 2 points and fills 25% hunger;
      - meat cooks on a barrel in 25 s;
      - a pod comes into the hand and gives its mutation, the points are spent, and the other pods shrivel;
      - the whip hits for 50;
      - fall damage is 24 at 30 m/s;
      - F stows the gun, with both guns in the bag.
    - **Found and fixed on the way:**
      - a pod was being unfrozen mid-pull;
      - the population cap's culls dropped meat (now they don't, and big ones are culled last);
      - **`web_reach` was 5000 in the open-world scene:** all 20 Stack web hordes (about 317 spiders) spawned at load, km away, and were mostly culled at once. The user set it back to 120 m (the override was removed).
  - **CPU profile, headless:**
    - **Physics:** 6.45 ms a tick (of 16.7). Enemies take about 3.3 ms of it (83 creatures), world-chunk streaming about 1 ms, and the player about 1 ms. Everything added today is within the noise (±1 ms).
    - **Nodes:** 24.4k, including 5.8k MultiMeshes, 5k meshes, 872 barnacles, 151 particle systems and 81 lights. Rendering isn't measurable headless (frames are paced there).
- **Grapple: half a bar a throw, no drain, no rappelling (2026-10-16).** The user's. `PlayerGrapple.fire_cost` 0.5 bars is spent when it's thrown; nothing drains while it's out or holding (the drain while attached is gone). Rappelling (S lets line out, hanging on it) and reeling (W back up) are removed with everything tied to them (the HANG state, the line length, `reel_speed`/`rappel_speed`); a perch now lasts till you jump off. Not compiled or run (the user's testing).
- **Grapple wall kick (2026-10-16).** The user's. Pulled into a wall you never slam to a stop: you bounce along the natural path (your speed reflected off the wall). Space in the last 0.4 s before the hit, or within 0.1 s of touching, kicks off at 120% of your speed; in the last 0.2 s (or the moment you touch), 30% more again, with the grapple's chime. No press: a weak bounce at 30%. Wall pulls no longer ease off as they arrive (the bounce needs the speed); big enemies still do. A stall against a ledge on the way still perches. (`PlayerGrapple` Wall Kick exports, the TOUCH state.) Not compiled or run (the user's testing).
- **Spiders: bite and leap from their body's edge (2026-10-16).** The user's: after they scaled spiders up, they stopped leaping and bit from too far -- bite range was 1.4 m x their size (up to ~7 m), and the scene's leap range 0.8-1.5 m, both from their middle. Now both are measured from the edge of the body (`Spider._gap_to`), the same for every size: bite within 0.6 m; leap at 4-10 m (walls and ceilings up to 10 m). Not compiled or run (the user's testing).
- **Gangs no longer fall asleep mid-fight (2026-10-16).** The user's bug: after killing one of a human group, the rest froze -- unhittable, walk-through (asleep: processing off, out of the physics world). A group judged 'is a player near?' from the middle of ALL its bodies, the dead included (and a body being removed could make it fail outright), so it could think you'd gone. Now: the distance to its nearest LIVING member (bad positions skipped), and never asleep within 10 s of any member being hurt (`RoamingGroup.FIGHT_AWAKE`). Not compiled or run (the user's testing).
- **Harvestman proboscis grab (2026-10-16).** The user's. With its proboscis already out (the hunt, a hose), it rushes you, tip reaching; within 2.5 m you're snatched onto the tip (`PlayerMovement.held_point`). It slowly reels you in over 3.5 s, rearing back, while you spam left click (the leech meter, 'GRABBED! SPAM CLICK TO BREAK FREE!'; 16 clicks, slipping back 0.1/s). Break free: you drop. Don't: it lunges and flings you at 35 m/s for 30 damage. 12 s before the next grab. Released if it dies, unloads or you respawn. Not compiled or run (the user's testing); co-op: the meter shows on the host's screen only for now.
- **Camps (2026-10-16).** The user's. Humans always drop 1 scrap, spiders half the time 1 silk (`Drops`). A camp kit is 4 scrap + 2 silk: the kit's slot shows in the bag once you have enough, and double-clicking it crafts it into your hand. With the kit in hand a see-through camp follows your aim (`CampBuilder`): green where it fits (not too steep or bumpy, nothing in the way), red where it doesn't. The mouse wheel turns it, left click builds it, right click puts the kit back. A camp (`Camp`) is a random Large Tent (1 or 2), the survival sleeping bag (F: Sleep, which heals 50 and costs 25% hunger, with a fade; `Bedroll`), and the forest Fire, crane and pot (flames, warm light, cooks meat). Build as many as you like. Die with one built: you wake at the camp nearest where you fell, and everything you carried is left in a backpack where you died (`DeathPack`, `Backpack.take_all/give_all`, `WeaponController.take_all/give_all`). Walk into it or grapple it to get it all back; only its owner can. No camp: the level restarts as before. Co-op: the host builds and decides, and clients see camps and packs through NetEntities. Also: the meat chunk is twice as big (`CarryItem.MEAT_SIZE` 6). Not compiled or run (the user's testing).
- **Camp fixes (2026-10-16).** The user's. The placing ghost is 50% see-through (was 35%). Meat cooks in 5 s (was 25). A chunk lying about now reaches the fire from its edge, not its middle (`CarryItem.cook` reach + half its size), so a big chunk dropped beside the fire cooks. The camp Fire's flat flame cards (pictures crossing in a plus) are left out (`Camp._is_card`); the particle flames burn there. Not compiled or run (the user's testing).
- **Cooking reach 2 m (2026-10-16).** The user's: `CarryItem.COOK_REACH` 1 -> 2 m from the fire's edge (from a lying chunk's edge, or the hand). Not compiled or run (the user's testing).
- **Glued meat; cooked meat heals (2026-10-16).** The user's. Two fresh chunks plus 1 silk make glued meat: raw with raw, or cooked with cooked. Rotten or already-glued chunks can't be used. The craft works like the camp kit: the Glued Meat / Glued Cooked slot shows in the bag when you have the makings and none glued yet, and double-clicking crafts it into your hand. With glued ones already in the bag, double-click takes one of those. The glued chunk weighs both chunks together, counts as boss meat if either was, and is as old as the older one. It rots and cooks like raw meat (glued raw cooks into glued cooked). Eaten, it gives 1.2x one chunk's food. Glued raw also gives 1 extra virus point (best chunk +1) and hurts like raw. Cooked meat now heals 35, glued cooked 42 (`Virus.COOKED_HEAL`, `GLUED_BONUS`, `GLUED_POINTS`). Look: two chunks pressed together with a silk ball between them (`CarryItem.glued_model`). Not compiled or run (the user's testing).
- **Long-fight slowdown fixes (2026-10-17).** The user's (FPS sank to ~20 after staying in one area). All values are the user's.
  - **Kills:** scrap, silk and meat drop only on a player's kill (the attacker isn't `Health.NO_ATTACKER`).
  - **Enemy drops expire:** gone after 25 s untaken, or sooner once every player is 60 m off (`CarryItem.expire_unclaimed`, checked once a second on the host). Guns and what you drop yourself stay.
  - **Spawn budget** (`EncounterDirector`, Pacing): each new band costs a point; points refill 1 per 30 s, max 3. This replaced the old "a new band 3 s after one's wiped, forever".
  - **Harvestmen** start twice as far off (140-240 m) and despawn past 360 m (group meta `despawn_sq`).
  - **Corpses:** last 1 minute (was 2; `corpse_time` 60 in enemy.gd and the enemy scenes), and at most 20 at once; past that the oldest fades early (`Enemy.MAX_CORPSES`).
  - **Decals:** blood splats and bullet holes capped at 100 (`BloodFX.MAX_DECALS`), oldest first.
  - **Leaks fixed:** a mutant from a corpse, roaches bred on a carried body or out of an eaten rat, and a Harvestman's brood were all put into the open world, outside their band. They never slept, never despawned and went on breeding. Now they join the band. Rats and spiders were already tracked by their swarm or pack.
  - **Burning barrels** stand on the surface under them, tilted to match it (at most 20 degrees), retrying while the ground streams in (`BurningBarrel._settle`).
  - Not compiled or run (the user's testing).
- **Encounter distances follow the fog (2026-10-17).** The user's. The director reads the fog's solid distance live (`fog_depth_end`: ~192 m in the sewer; it changes with the biome and the view distance setting). Bands spawn mid-fog, 60-90% of the way out (~115-175 m; was 70-120 m). Harvestmen spawn 80-95% (~154-183 m), at the edge of what you can see, still behind or beside you. Every band, Harvestmen too, despawns 10 m past the fog end (~202 m; was 240 m, and 360 m for Harvestmen). A megastructure camp forms once it's inside the fog end (was 250 m, which would have been made and removed over and over). Not compiled or run (the user's testing).
- **Stowed two-handed gun: no floating support hand (2026-10-17).** The user's. With a two-handed gun stowed, the left arm drops its support pose (`set_support(false)` on stow). It stays out of sight until you grapple, then shows in its normal grapple animation (`free_hand` counts empty hands). Drawing the gun again brings the support pose back. Not compiled or run (the user's testing).
- **Hills: skim and boost (2026-10-17).** The user's, Source's ramp rules. Moving up faster than `skim_speed` 2.7 m/s you don't count as landed (`PlayerMovement._on_ground`), so you skim up and over a hill instead of re-jumping on it every few frames. Landing on a downhill turns the speed that went into the slope into speed along it, times `slope_landing_boost` 1.1, up to `speed_cap` (`_land_on_slope`). Uphill and flat landings are as before. Jump sounds closer together than 0.6 s play once (`PlayerSound.JUMP_SOUND_GAP_MSEC`). Not compiled or run (the user's testing).
- **Skim sound (2026-10-17).** The user's. Skimming up a hill plays a loop while it lasts. It starts somewhere new in the file each time, fades in over 0.08 s and out over 0.3 s, and is held on for 0.15 s through flickering touches. It gets louder (60-100%) and higher (0.9-1.2x) with speed, on the Surface (Footsteps & Movement) bus at footstep level. Settings > Audio > Skim Sound picks Wet glide (the user's `universfield-worm-movement-277577.mp3`, the default), Chitin skate or Wing flutter. The last two are greyed out until their files are added to `PlayerSound.SKIM_FILES`. Saved in settings.cfg. Not compiled or run (the user's testing).
- **Jump sound gap 0.4 s (2026-10-17).** The user's: `PlayerSound.JUMP_SOUND_GAP_MSEC` 600 -> 400. Landings keep their own 0.6 s gap (`LAND_SOUND_GAP_MSEC`).
- **Seeded Growth mutation (2026-10-17).** The user's.
  - **Trigger:** tap right click (released within 0.2 s; holding still winds up the grapple). With the Tentacle Whip too, a tap waits out the 0.3 s double-tap first, and a double-tap whips.
  - **Where:** five tentacles burst out of the surface where you aim, spread over a 4 m circle. Range is the grapple's reach, on anything it could grab (not when the ring would be red); aimed at a big enemy, they burst from the ground under it.
  - **The tentacles:** black symbiote, 4 m tall, 0.35 m thick (`SeededGrowth`). Squid-style: a fast straight thrust with a little overshoot, then 2 s of lashing, with bends running base to tip on two axes and curling tips, then sucked back into the ground in 0.35 s.
  - **Damage:** 40 on bursting out, then 10/s to everything in the circle while they're out.
  - **Small enemies** (rats, roaches, spiders, people): 50/50 flung at 18 m/s along the tentacle, or grabbed. A grabbed one is wrapped (0.6 s) and slowly reeled under (3 s); it's gone with no drops and no meat, and that tentacle goes with it.
  - **Big enemies** (big ones, bosses): hurt and flung where they can be. Harvestmen only take the damage.
  - **You:** standing within 1.5 m of a tentacle as it bursts, you're launched along it at 20 m/s.
  - **Cost:** 1 bar, 4 s cooldown. The left arm pushes out as it goes.
  - **Cheap:** one ImmediateMesh for all five, one sphere query at the burst and one every 0.25 s.
  - **Co-op:** the host decides everything; other peers get the look by rpc. A client's own copy doesn't show the wrap.
  - **Pod look:** a seed with five shoots.
- **Mutation pods: newest first (2026-10-17).** The user's. The Flesh Tree offers the most recently made mutations first (`Virus.MUTATIONS` order, reversed) instead of at random.
- **Tentacle Whip slung like a real whip (2026-10-17).** The user's: less wriggling. Drawn back behind you to the right, then the arm sweeps right to left as a loop rolls down from the hand to the tip; the part past the loop lies back where it was. Once it's straight out, the tip snaps 8% past full length (the crack), then the whip goes slack and comes back in. It's drawn along that exact shape with no writhe (`GrappleTentacle.show_rope` path), and only hurts while it's slung.
- Not compiled or run (the user's testing).
- **Taking a mutation heals and feeds you (2026-10-17).** The user's: eating a pod heals to full health and fills hunger (`Virus.take_mutation`; the host's, sent with the usual virus sync). Not compiled or run (the user's testing).
- **The Stack's express lift is out for now (2026-10-17).** The user's: it ran through some skybridges. `StackBuilder.LIFT_ENABLED` false: no car, call buttons or cable (its docks stay; the cable car between the high halls stays). The Stack was re-baked (`tools/make_the_stack.gd`): scene and map rewritten. docs/CLIMB_VISION.md now carries the earlier (2026-10-14) roadmap with each step's status, and the next step: the Stack's secrets.
- **The Stack's secrets (2026-10-17).** The user's: every detail below.
  - **The doors:** 30 person-size (2 x 3 m) secret doors: 14 to loot rooms, 10 to shortcuts, 6 secret entrances. 15 open with a key, 15 with a button.
    - Key doors are visible locked doors (one of the Mega Pack's loose doors, at random). F with a key in the bag: the key's used up and it swings in. Without one it rattles locked ("Locked. It needs a key."). Any key opens any key door, never a button door.
    - Button doors look like the wall they're in: a panel of the wall's own concrete on the same texture grid, with nothing to use. Their button is within 40 m (8 m at the least), at hand height on a hall wall. It's a random small button, call button, button panel, light switch, valve or lever (`SecretButton`). F presses or pulls it and the door swings in.
    - Sounds are the existing door_locked / door_move / door_stop.
  - **The rooms:** new blocks grown onto the towers' outsides, merging out of the wall (sunk 4 m into it), half windowed building concrete and half plain. All are clear of windows, ways in, the lift's landings, crossings, bridges and each other; skybridges keep 12 m clear of them.
    - **Loot room:** 12 x 12 x 8 m with a dim warm lamp, its door in a hall's wall at the floor.
    - **Shortcut:** a door in a hall's wall under one of its mezzanines, and behind it a 5 m shaft grown up the outside to a way back in onto the deck. Grapple up it.
    - **Entrance:** a grown room whose door is on its outside, with a balcony to grapple onto, its passage to the hall open. An entrance's button sits on the room's outside wall beside it.
  - **Per play (`StackSecrets`, the host's; made only once a player first comes within 150 m):**
    - Each loot room has 1-2 boxes of ammo (30 bullets or 8 shells), pills half the time, 1-3 scrap, 0-2 silk, a gun 15% of the time and a key 3%.
    - 14 keys lie on hall floors (from 60 spots).
    - 4 dead climbers (from 16 spots), each a person who fell as a ragdoll and settled, with a key on them. 30% have an abandoned camp beside them: cold fire, a bedroll you can still sleep in, not a camp you wake at.
    - Every window room has an 8% chance of a key.
  - **Keys:** a backpack item (`Backpack.Kind.KEY`, `key_mp_1`). Walk into one or grapple it. They drop with the rest of your gear when you die at a camp.
  - **How it's built:** `StackBuilder._secrets()`, with its own dice so nothing else in the Stack moved. Re-baked: 30 doors, 15 with buttons.
  - Not compiled or run in game (the user's testing). The bake's editor scan showed no script errors.
- **Speed effects from 32 to 40 m/s (2026-10-17).** The user's: the camera's speed juice (FOV widening, strafe/turn roll lean, sway, the rattle) starts lightly at 32 m/s and is full at 40 (`CameraJuice.speed_floor`/`speed_top`; was 7 to 28). That's past the 28 m/s bhop cap, so it comes from grapple kicks, launches and downhill boosts.
- **Mouse look freezing at random (2026-10-17).** The user's bug (their friend had it too): the crosshair stopped moving. Look was read in `_unhandled_input`, so any UI rect under the hidden, captured cursor ate the motion; the stamina and hunger pips (code-made ColorRects, which take the mouse by default) sit 14 px under the crosshair and change size. Now: look is read in `PlayerMovement._input` (before the UI), the pips ignore the mouse, the camp ghost's clicks are read in `_input` too, and coming back into the window (an overlay, a notification, alt-tab) re-grabs the mouse capture. Not compiled or run (the user's testing).
- **Life in the Stack's towers (2026-10-17).** The user's: every detail below. The parked infestation stays.
  - **Roaming swarms (`TowerLife`):** as you come within 40 m of a hall, it has a 50% chance of a swarm moving through it (rats, roaches or spiders, wandering the whole hall). A roach swarm carries a body a third of the time: a dead person or climber the roaches lift and fly off to eat.
  - **Climbing hordes:** a third of halls, and of the main shaft's 150 m stretches, have a spider horde of 15-30 crawling up a wall as you go up past it (`SpiderPack.climb`). They turn on you if you get close.
  - **Rolls:** each is rolled as you come near, cleared once everyone's 200 m off, and rolled again next time. The host does it all.
  - **Inside barnacles:** 10 more, 6 up different secret shortcut shafts and 4 on the halls' pillars, stair steps and ramps (`Megastructure.inner_nest_*`, from the builder; re-baked, same layout).
- **Spiders roam simply (2026-10-17).** The user's bug: packs walked in circles together forever, because idle spots slowly turned round the pack's middle. Now an idle pack heads for a random spot on the walls round it: off the floor to a wall it can see, then on along the wall in any direction, round its edges and out of an opening up the building's outside if it goes that way. It heads back if it's 3x its roam radius from home. Spots no longer spin.
- **Spiders no longer stuck in barnacles (2026-10-17).** Spiders spat out of a spider barnacle landed back on its body and clung to it. A barnacle is no longer a surface to a spider, and they come out clear of its body.
- **Spider sounds (2026-10-17).** The user's: like the roaches' buzz, each one its own (`SpiderSound`, made in code).
  - **Crawling:** a skitter loop of leg clicks, one of 6, each spider with its own pitch and start point, louder the faster it crawls, paused when still.
  - **Leaping:** a chittering rasp, one of 6.
  - Bigger spiders sound lower. Heard within 45 m, on the Enemies bus.
- **Roach sounds heard from 25% less far (2026-10-17).** The user's: every roach SoundEvent's `unit_size` is x0.75 (the buzz 12 -> 9); the spiders' use the same 9.
- Not compiled or run in game (the user's testing). The editor scan showed no script errors.
- **Secrets scattered (2026-10-17).** The user's: no two secrets within 150 m (`StackBuilder.SECRET_SPACING`), and dealt out to the towers in turn (each tries its own tower first, then anywhere). Loot rooms and entrances can also open off a hall's mezzanine, through the wall it's against, not only the hall floor. Shortcuts are placed first (the pickiest). That spacing fits 4 shortcuts, not 10, which the user OK'd: 24 doors (14 loot, 4 shortcuts, 6 entrances), 13 with buttons. Re-baked.
- **Secret doors echo like the radio (2026-10-17).** The user's: a door's opening sounds (door_move, door_stop) play exactly the way a radio is heard (`SecretDoor.echo()`, Radio's three voices, buses and mix): clear up close, tinny further off, and far away a muffled echo through the halls whose long reverb fades slowly. (Being the radio's buses, it rides the Music slider.)
- **The towers' roaming spiders see you from twice as far (2026-10-17).** The user's: the halls' roaming spider swarms and the climbing hordes have double `notice_range` and `lose_range`.
- **Shoot one, the horde comes (2026-10-17).** The user's: a spider hurt by a player sends its whole pack after that player, however far off, and it won't give up for 20 s (`SpiderPack.alert`, `ALERT_TIME`); after that it's the usual lose range.
- **Spider leaps 25% further (2026-10-17).** The user's: spider.tscn `leap_range_max` 10 -> 12.5, `wall_leap_range` 10 -> 12.5 (the least stays 4).
- Not compiled or run in game (the user's testing).
- **Switch sounds and 'Something opened.'; one spot for messages (2026-10-17).** The user's. Pressing a secret button or switch plays `audio/events/map/button_press.tres`, a lever `lever_pull.tres` (the user's to set: drop button_press_01.wav / lever_pull_01.wav in audio/sfx/map, or point the events at any clips). 'Something opened.' shows at the bottom middle of the presser's screen. Every HUD message and pickup line (`MapIO.show_message`/`show_pickup`) now pops up in that one spot (`HUD.MESSAGE_HEIGHT` 0.84); the backpack's own text is unchanged. Note: audio/sfx/map has no clips yet (only its README), so the door sounds are silent until files are added. Not compiled or run (the user's testing).
- **Soft cloud deck (2026-10-17).** The user's: the towers looked cut off where they went into the clouds. The cloud sheet (shaders/clouds.gdshader) now reads the depth behind it. Something just past the deck shows through, and the cloud thickens over `soft_depth` (500 m) beyond, so a tower fades up into the clouds instead of stopping at a line. Anything solid behind it always shows `see_through` (25%), so the towers loom through faintly, like the lit windows through the fog; open sky is covered as before. Both are uniforms on the CloudDeck's material to tune. Not run (the user's testing).
- **Roaches up in the air; nothing spawns in sight (2026-10-17).** The user's.
  - **Airborne roaches:** the towers' roaming roach swarms (`TowerLife`) swarm in the air 20 m under a hall's ceiling, not on the floor. The main shaft's 150 m stretches (it runs hall to hall) get airborne roach swarms too, 50% each.
  - **Bodies:** a carried body starts up there with them; they take hold at once (`RoachCarry.recruit`) and go about their usual carrying.
  - **Aggro:** those roaches pick fights from twice as far (`threat_range` x2).
  - **Out of sight (Left 4 Dead's rule):** a roaming swarm or climbing horde only spawns where no player could see it, meaning outside a 65-degree cone of where they're looking or behind a wall, and never within 25 m. If there's no hidden spot when it's rolled, it keeps trying each second until there is.
  - **Fix:** a roaming band's patrol anchor was in the Stack's local space, not the world's.
  - Not run (the user's testing).
- **Camp fire: no more flame pictures (2026-10-17).** The user's: the crossed fire images were still there. In the forest props the part named "Fire" IS the crossed flame cards (a 1 m cube of pictures, hung off the "Bonfire"), and the logs are "Bonfire". The camp now uses "Bonfire" and leaves out any mesh named Fire or Flame (`Camp._is_card`); the old flat-card guess is gone (it also took the pot's food).
- **The Stack's sound inside (2026-10-17).** The user's, with their files.
  - **Hollow loop:** inside any part of it (its inside box, a hall, the base, a window room), `audio/sfx/map/hallowloop.wav` loops on the Ambience bus. It crossfades with the approach's drone and open-sky wind over 2.5 s both ways (`MegastructureSound`). Outside, the drone only plays as you approach.
  - **Distant noises:** while you're inside, every 20-45 s one of the ambience one-shots (`oneshot_anylevel_*`) goes off 60-200 m away, above you or off in the distance, through the radio's echo (`HallEcho.play`: the same three voices, buses and mix as a radio).
  - **Lamp hum:** the halls' lamp posts hum (`lighthum.wav`), heard within 16 m, playing only while you're that near (`LampHum`).
  - **Gunshot echo:** fired inside the Stack, every gunshot, yours and the gunners', also rolls on through the halls on the radio's echo bus with its long reverb (`HallEcho.tail`, `Megastructure.contains`).
  - The door's radio-style sound now goes through `HallEcho` too.
  - Not run (the user's testing).
- **Crash fix: empty roach scene (2026-10-17).** The user's crash: `Megastructure._infest` got a null roach (its preloaded roach scene came out empty: 'node count is 0'). The gunshot echo made the weapon and enemy sound scripts load Megastructure, which preloads the creature scenes, so a load cycle ran through roach.tscn. Now `HallEcho` (which loads nothing) keeps the list of places sound echoes in (each Megastructure adds itself), and the sound scripts ask `HallEcho.inside()`. Nothing in the player's or enemies' scripts names Megastructure.
- **The Stalker, stage 1: the crawler (2026-10-17).** The user's (design in docs/CLIMB_VISION.md). `Stalker`: `Character_Monster_03` laid chest-down on all fours, sized to a 1.9 m person.
  - **Movement:** it crawls on floors, walls and ceilings the spider's way, and falls off edges.
  - **Body (every screen):**
    - two-bone IK on each arm and leg, elbows and knees bent up and out;
    - hands and feet planted, stepping in diagonal pairs in three jerky snatches each (The Grudge's broken joints);
    - the spine settling to their height and tilt on a spring;
    - the head locked on your camera, tilted wrong, snapping to a new tilt every 2-5 s.
  - **Brain (host):**
    - It always knows roughly where you are and stalks 30 m off at 9 m/s.
    - Seen by any player (within 55 degrees of where they look, a clear line to any of six points over its body), it freezes 0.8 s staring, then scrambles away at 13 m/s (slow enough to watch it skitter off) to the nearest spot none of them can see, and waits there 1.5 s.
    - 200 damage drives it off: it flees at 18 m/s for 4 s, then it's gone for 5-8 min. It's never killed.
    - Everyone 280 m+ off for 5 s: it turns up again unseen, 55-85 m behind one of you.
  - **Spawn:** made once by the EncounterDirector after its first delay (the host's).
  - **Co-op:** a NetEntities puppet whose transform carries the surface it's on.
  - Stunts, the fear meter and the strike are stages 2-3.
  - Not compiled or run (the user's testing).
- **The high wind, everywhere (2026-10-17).** The user's: the procedural Stacks' wind now blows in every world (`WorldWind`): in the open air from 4 km up, building to 4 m/s by 12 km, gusting to 7, a prevailing wind wandering slowly round. None indoors (a megastructure's halls and rooms). `PlayerMovement._blow` pulls you along it while you're in the air, using a world's own wind if it has one (the procedural Stacks' still), else this. In the open world that's the top kilometre of the Stack. Not run (the user's testing).
- **The Stalker, stage 2: the stunts and the fear meter (2026-10-17).** The user's: every detail below.
  - **When:** every 30-60 s, while it stalks unseen, it stages a stunt for one of the players.
  - **The stunts:**
    - **Behind you:** right behind you, still and staring, with a rattle after 3 s. Turn and see it: it holds 0.8 s, then bolts.
    - **Ceiling at the edge of view:** across the ceiling indoors (a wall or the ground outside), 55-65 degrees off where you look, scuttling on out of view at 13 m/s.
    - **Doorway pass:** across your way 16-26 m ahead, cover to cover.
    - **Drags a corpse past:** the same crossing at 5 m/s, a dead person pulled along by the foot (the roaches' carry hold).
    - **Watching from the dark:** off to the side 20-35 m, still and rattling. Look away a second and it's gone; stare straight at it (12 degrees) and it holds 0.8 s, then goes.
    - **The rattle close by:** its croak behind and above you, with nothing there.
    - **The help scream:** the user's scream from 70-140 m off, through the halls' echo; then it follows, unseen.
    - **The leap:** when you're climbing a megastructure's outside above 150 m, by preference: a silhouette leaping 30-150 m between two tower faces 120-400 m off, then gone.
    - Each stunt ends with it hiding again.
  - **Fear:** one shared meter, hidden (printed in debug runs). Each counts once a stunt, within 3 s of its moment:
    - seeing it +15% (each glimpse outside a stunt too);
    - panic firing +10%;
    - running off at 7 m/s+ away from it +10%;
    - whipping round (270 degrees/s) +5%;
    - staying within 20 m of where it screamed for help for 10 s +50%.
    - It drains over 5 min and stays full once full (the strike comes in stage 3).
  - **Sounds** (`StalkerSound`, made in code until the user's files): a dry throat rattle (4 of them), a shriek when it's driven off (with the halls' echo), and a heavier, slower skitter while it crawls. The help scream is the user's mp3. The host's are relayed to every machine (`Network.send_stalker_sound`).
  - Not run (the user's testing).
- **Twice the keys lying about in the Stack (2026-10-17).** The user's: `StackSecrets.HALL_KEYS` 14 -> 28 (from the same 60 spots).
- **The Stalker, stage 3: the strike and the drag (2026-10-17).** The user's: every detail below.
  - **The strike:** once the fear is full, it goes for a player caught off guard (any one: looking away from it, reloading or hands busy, alone with no teammate within 25 m, or grappling). It closes in unseen to 8 m behind them at 18 m/s; seen, it hides as ever. Within 12 m, it rattles and lunges at 25 m/s (2.5 s, then it gives up into hiding).
  - **The drag:** it grabs them and drags them off by the left foot at 8 m/s for 15 s, away from the other players (`StalkerDrag`, on every machine).
    - The player goes limp: a ragdoll of their own character (`RagdollBuilder`), on their back, their real body hidden and the player carried at its hips.
    - Their camera rides the ragdoll's head, just in front of the face, out of their control. The gun and arms are hidden.
  - **Getting loose:** spam click (20 clicks, slipping back 0.15/s: the Harvestman grab's meter, 'IT'S GOT YOU! SPAM CLICK TO BREAK FREE!'), or 30 damage to it from a teammate. Then it scrambles off into hiding.
  - **Not loose in 15 s:** 70 damage, left where it dropped them, and it's gone for 2-3 min. The fear is spent either way.
  - **Driven off mid-strike** (200 damage): it lets go and flees as before.
  - **Co-op:** the host starts and ends the drag (`Network.send_stalker_drag`).
- **The Stalker is never culled (2026-10-17).** The user's: past the fog it carries on, kept for every player however far (`net_always` in NetEntities).
- Not run (the user's testing).
- **The drag, smooth both ways (2026-10-17).** The user's: never immersion-breaking. Taken: the ragdoll starts in the very pose and place the body was in, and the yank on the foot topples it backward. Your view eases from where you were looking into the ragdoll's head over 0.35 s, then follows it a touch smoothed. A jolt (shake, FOV kick) as it hits, and the gun drops out of view a beat later. Let go (`StalkerDrag.release`): you're back on your feet where you lay, facing the way you lay, the view easing up to your eyes over 0.5 s, then your gun comes back up with its draw. Checked (the user OK'd): an editor scan (no script errors) and 70 s of the test world headless with the Stalker spawning (no errors).
- **The Stalker: twice a person, hittable, grabs when you come close (2026-10-17).** The user's.
  - **Size:** it was tiny. Its size was measured without its model's import scale, so it came out far smaller than meant, and its person-size hitbox sat above the little body, which is why shots seemed to do nothing. Now it's measured as the meshes really sit, and everything scales with `Stalker.SIZE` 2: 3.8 m standing, about 3.2 m long on all fours, its back ~1.2 m up, its hitbox (radius 0.7 m) matching.
  - **Rushed at:** a player within 20 m coming at it faster than 2 m/s sends it flat out (18 m/s) to cover.
  - **Too close:** one that still gets within 5 m is grabbed and dragged off, always (not mid-stunt, not during its cooldown).
  - **After any drag** (broken free, freed by a teammate, or run its course): it runs flat out to cover, then waits 2-3 min before staging or striking again, stalking meanwhile. It no longer vanishes after a full drag.
  - Not run (the user's testing).
- **Player Fear Meter setting; reactions doubled (2026-10-17).** The user's, for tuning the Stalker. Settings > Graphics > Player Fear Meter (saved; off by default) shows a purple bar right under the hunger bar, filled to the Stalker's shared fear meter. It's sent to every machine with its updates (`Stalker.net_state`/`net_apply`). Every reaction counts double now: seen 30%, panic firing 20%, running off 20%, whipping round 10%, investigating the help scream 100%. Not run (the user's testing).
- **The Stalker keeps up (2026-10-17).** The user's: it lost them too easily. Alien: Isolation's 'backstage': while nobody can see it, more than 90 m from everyone for 6 s, or not gaining 2 m on them in 6 s while stalking (hung up on a wall, a ceiling, the land), it turns up again out of sight 35-55 m behind one of them. Still also: everyone 280 m+ off for 5 s, 55-85 m. Not run (the user's testing).
- **The Stalker climbs like a spider (2026-10-17).** The user's. It always could stick to walls and ceilings, but only climbed what it bumped into. Now it stalks from a perch: a spot 2-6 m up a wall within 15 m of where it means to be, or indoors (half the time) on the ceiling over it, picked again every 3 s. It crawls up the wall to reach it, over the corner onto a ceiling. Hiding, it also looks up walls and onto ceilings round it (16 rays, 25 m), unseen, scoring higher spots better, as readily as round a corner. Not run (the user's testing).
- **The Stalker 25% less clingy (2026-10-17).** The user's: it can be left further behind. Backstage now after 112.5 m from everyone for 7.5 s, or 7.5 s without gaining on them, turning up 44-69 m behind (was 90 m, 6 s, 6 s, 35-55 m).
- **The Stalker gets away, and unsticks (2026-10-17).** The user's. Going to hide, it first runs straight off away from the players for 1.5 s (flat out if rushed), then picks cover at least 5 m further from all of them than it is (`_start_hide`). If it isn't moving 0.6 m in 1.5 s while it means to (stuck on some geometry, clinging to a wall): on a wall or ceiling it lets go, pushed out and down, drops to the floor and hides on the floor; on the floor it picks other cover (`_unstick`). Not run (the user's testing).
- **Walls don't hold the Stalker back (2026-10-17).** The user's: preferring walls mustn't stop it getting away or hiding. Hiding, it takes cover on the floor first (the nearest unseen spot further from everyone) and only goes up a wall or onto a ceiling when there's none. Stalking, it perches up a wall or on a ceiling only 40% of the time (`PERCH_CHANCE`), else it keeps to the ground.
- **The Stalker takes every hit (2026-10-17).** The user's: shots hit only sometimes. One capsule down its spine missed the sprawled limbs, and the drawn body trailed the real one by up to a metre at a scramble. Now its hitboxes follow its bones: a capsule each for the torso, neck, upper and lower arms and legs, and a ball for the head, sized with it, moved onto the bones every physics tick (`Stalker._update_hitboxes`). The host draws it exactly where it is (where shots are judged); a puppet eases after its updates. Not run (the user's testing).
- **The Stalker flashes when hit (2026-10-17).** It never loses health (it's driven off at 200 damage), so hits showed nothing; now it flashes like the spiders (`HitFlash`). Note for the user: the shotgun only reaches 40 m (`max_range`), and the Stalker stalks from ~30 m and scrambles further off, so long shots never land.
- **'A tingle goes down your spine.'; it hides properly; grab range 10 m (2026-10-17).** The user's. Each stunt shows those words on its player's screen (`Network.send_message`). Being seen is judged on its real body too (each bone hitbox), with a half-size slack for points just inside the ground or a wall; it sometimes thought it was hidden in plain sight and stayed put. Grab range doubled to 10 m. Not run (the user's testing).
- **Break out and it throws you (2026-10-17).** The user's: spam-clicking free of the Stalker's grip gets you flung off in a random direction at 25 m/s (20 degrees up) for 15 damage (`Stalker.drag_broken`). Control comes straight back (the view still eases up from the ragdoll). A teammate shooting it off doesn't throw you. Not run (the user's testing).
- **After the stare, it bolts (2026-10-17).** The user's: every time it goes to hide, the first 1.5 s straight away from the players is flat out (18 m/s), including after its 0.8 s stare when spotted and after the 'behind you' and 'watching' stunts. Then it heads for cover further off (13 m/s, flat out if it was rushed).
- **The Stalker's head bobbles (2026-10-17).** The user's: like the Harvestmen's jiggle limbs (`JiggleLimb`, Half-Life 2's \). Its neck and head each ride a spring (stiffness 9, damping 2.4, gravity 6): the body's moves swing them, and every hand or foot planting gives them a little upward jolt. The head still locks on you, its bobble laid over the aim (`Stalker._jiggle_neck`). Not run (the user's testing).
- **Ragdoll pushes skip bones out of the physics (2026-10-17).** A body switched off (a Seeded Growth tendril's grab, a sleeping group, a burst) is taken out of the physics space, and Jolt errored on the death push sent to it next frame. `EnemyRagdoll._in_space()` checks each bone first.
- **Tendrils out of the mutation pool (2026-10-17).** The user's: it didn't work well (Seeded Growth does). Removed from `Virus.MUTATIONS`; anyone holding it loses it; its grapple code stays, switched off.
- **Stalker fear holds full for 2 minutes (2026-10-17).** The user's: maxed, it stays maxed `FEAR_HOLD` (120 s) if it hasn't had you, then drains at the usual slow rate (`FEAR_DRAIN_TIME`). Before, a full meter never drained.
- **Stalker skitter pitch 0.45 (2026-10-17).** The user's (was 0.55).
- **Stalker gets about the Stack (2026-10-17).** It went ages unseen indoors with the fear full. Why: its relocations dropped it from 300 m up, onto the roof or another storey, and from there it could never reach you; a floor above you at stalking distance never even counted as stuck. Now, the Left 4 Dead director's way: indoors it turns up behind you in your own room on your floor (rays from your eye, stopped short of the walls); its stalk spot is kept on your side of the walls; and with no line to you for `STUCK_TIME` (7.5 s, unseen), stalking or closing in for the strike, it slips round and turns up near you (`_cut_off_tick`). Outdoors it's dropped from 60 m over your head, not 300 (not onto bridges and roofs).
- **Stalker stages more reliably (2026-10-17).** The user's: no events for a long time. A stunt with nowhere to fit now retries in 2 s (it used to wait a whole 30-60 s); `_ground_at` starts under the ceiling indoors (it used to find the floor above, staging stunts where you'd never see them); and a hide that never gets there gives up after `STUCK_TIME` (it could hide for ever, never stalking or staging).
- **The Stack's navmesh covers every floor (2026-10-17).** The world bake's tiles only took the terrain's height range, so pathfinding knew the Stack's ground storey and nothing above it. `tools/rebake_stack_nav.gd` re-bakes just the 48 tiles under the Stack, over its whole height (the terrain, chunks and scene untouched). Afterwards ~13,000 of the 32,000 vertices in those tiles sit above 60 m, from floors up to ~1,800 m. Re-run it after any Stack re-bake. A full world bake (`make_test_world.gd`) puts the old short tiles back, so run this after that too.
- **Inside ambience halved (2026-10-17).** The user's: the hollow loop inside megastructures down 50% (`MegastructureSound.hollow_volume_db` -6 -> -12 dB, half the amplitude). The far-off one-shots are unchanged.
- **Approach drone halved (2026-10-17).** The user's: the drone you hear nearing the Stack's base down 50% (StackBuilder sets `drone_volume_db` -8 -> -14 dB). It's baked into the_stack.scn, so it takes effect at the next Stack re-bake.
- **The heart's cathedral (2026-10-17).** The user's: on top of the hive (tower 5), built the procedural Stacks' way. The Stack generator's own hall is run in a box 1/1.5 its size and scaled back up. It's 500 m tall and 300 m across (280 m inside the walls), floor at 4,304 m and roof at 4,824 m. The middle 160 m across is kept open: no columns, mid-air stairs or hanging pyramid there, and the mezzanines are made shallow enough that their ramps stay out. It uses the Stack's concrete, with the hive's growth (x3) creeping in round the floor's edges. Two slit windows (3 x 60 m, 10 m up) sit on opposite walls (which pair: seeded). A torn-open gap 30 m across is 165 m up one wall (seeded side). The hive's top hall's panic stairs carry on up through a hole in its floor, with the last flight running through a channel cut in the hall's wall top. The hive steps out to it in 4 tiers from 3,500 m: it's ~118 m wide there, widening to 300 m flush with the cathedral. Holes, window rooms and secrets are kept open through the tiers by slots. It uses its own dice (`SEED + 998/999`), so nothing else in the Stack moved; skybridges keep clear of it. `StackBuilder._cathedral`. The hall generator takes `open`/`growth` for this; every other hall builds exactly as before.
- **Tall navmesh tiles bake in slices (2026-10-17).** Recast stores a tile's height in 13 bits of cells (8,191 x 0.25 m = 2,047 m), so everything above ~1,750 m in the Stack had silently been left out. That included the earlier re-bake, which only reached ~1,750 m, not every floor as first reported. `WorldNavigation.bake_tiles` now bakes a taller tile in 1,900 m slices (6 m overlap), saved as `tile_x_z.res`, `tile_x_z_s1.res` and so on. Each loads as its own region, and edge connections join the seams. The Stack's 48 tiles are now 144 files, with navmesh on every floor up to ~5,000 m.
- **CREDITS.md (2026-10-17).** The heart (neshallads) and chain (Kutejnikov) models are CC BY 4.0 and credited there.
- **The heart's blood beam (2026-10-17).** The user's: like the Avatar State's glowing eyes and mouth, in blood. A hole tears open anywhere on the heart's surface and glows white-hot for one beat (the caller's `warn`). Then a beam blasts for 0.4 s: a white-hot core in a red glow, 4 m thick, 1.3x wider at its far end. Blood streams along it, droplets and mist spray off it, and red light floods the room. It stops at what it hits, leaving a splash and blood there. A hit does 35 damage and shoves you backwards at 15 m/s (lifted off the floor), once per blast. `BloodBeam.fire` and `shaders/blood_beam.gdshader`; co-op via `Network.send_blood_beam` (the host deals hits). The plan so far is in docs/HEART_BOSS.md.
- **The beat mapper (2026-10-17).** The user's: a scene you run (`scenes/tools/beat_mapper.tscn`, F6) to tap out a song's drums for the heart. 1 = kick, 2 = snare, 3 = hi-hat. Each tap lands where you heard the song (playback position plus the time since the last mix, minus the output latency). There's an optional snap to 1/16 notes from the BPM and first beat, and the song's waveform under the lanes (decoded with `AudioStreamPlayback.mix_audio`, a slice a frame). You can seek, click to jump, zoom, right-click a hit to delete it, Ctrl+Z undo and Ctrl+S save. It saves a `BeatMap` resource (`scripts/heart/beat_map.gd`: song, bpm, offset, kicks/snares/hats in order). The game's dither and pause menu are off while it runs.
- **The heart, chained (2026-10-17).** `HeartBoss` (`scripts/heart/heart_boss.gd`) is put in by the Stack's bake, hanging `HEART_HANG` (100 m) over the cathedral's middle. It's the real model at 30 m tall, beating lub-dub with a pulsing red light, dripping blood and splattering the floor. 8 chains (4 to the walls, 4 to the ceiling) run from its surface to wherever a ray meets the cathedral: the chain model laid link by link along a sag, every other link turned a quarter, jolting on each beat. It only runs while someone's in the cathedral (its looks within 700 m). Its song's beat map (`StackBuilder.HEART_MAP`: the user's Skinny Suge II map) plays: kicks beat it, and a hole opens a beat before each snare and fires a `BloodBeam` at a player inside. With no map it runs at `test_bpm` 80. These values are first picks while the user was short on time; all are exports. The player's `spawn_in_cathedral` (inspector, Testing) starts you at the top of the stairs into it (the `CathedralSpawn` marker).
- **Beam volleys and ricochets (2026-10-17).** The user's: each snare's volley is one beam mainly at a player (aimed from the side of the heart facing them) and 4 more (`HeartBoss.random_beams`) straight out of random spots on it, all warning together. Every beam ricochets once (`BloodBeam.RICOCHETS`) off what it hits, at the mirror angle (`Vector3.bounce`), blasting at the same moment with no hole of its own. Each game works out the ricochets itself from the same geometry, so nothing more is sent; only the host's beams deal hits, and each beam and ricochet hits on its own.
- **The heart's kick and snare (2026-10-17).** The user's. On a snare, the volley's holes glow open on the beat and blast one beat later on their own. On a kick, the heart beats and the cathedral quakes (`HeartQuake`): a bit of a screen shake (2 degrees) for everyone inside, dust kicking up off the floor (some by the players), 8 crumbling spots on the walls, and 4 concrete chunks breaking off the wall nearest the players, 25-90 m up (`FallingChunk`, 20 damage if one lands on you). Anyone on the ground, against a wall or perched by the grapple when it hits takes 50 damage and is launched 30 m/s up (`PlayerMovement.launch`: off any perch, then the shove; the owner's game lets go too). Being in the air dodges it. Co-op: the host picks the chunks' spots and does the launching and hurting (`Network.send_heart_kick`); every game draws it all. With no beat map, the test tempo alternates kick and snare.
- **Switching the heart's song (2026-10-17).** The user's: the new song Project_34 (its beat map: 158 kicks, 266 snares) is the heart's own now (`StackBuilder.HEART_MAP`). To switch, drop any beat map (`.beats.tres`) into the player's **Heart Song** in the inspector (Testing). Empty means the heart's own. It's picked each time someone enters the cathedral (`HeartBoss._chosen_map`).
- **The heart beats twice as hard (2026-10-17).** The user's: it swells 14% on the lub and 9% on the dub (was 7% and 4.5%), and its red glow pulses twice as bright (`HeartBoss.LUB`, `DUB`, `GLOW`).
- **The beams blast ON the snare (2026-10-17).** The user's final call: the volley fires on each snare, and its holes glow open the beat before. The heart looks a beat ahead in the map (`HeartBoss._snares_to`), so the first snares of the song get a shorter glow. Test tempo without a map: kick on even beats; the snare's volley lands on the odd ones.
- **The heart thumps once a kick (2026-10-17).** The user's: one big thump instead of lub-dub, so fast kicks each land their own. It swells 20% in a snap (rise 60/s) and eases back fast (fall 9/s: mostly settled in ~0.3 s), with the glow and chains pulsing with it (`HeartBoss.THUMP`, `THUMP_RISE`, `THUMP_FALL`).
- **Kick chunks fall in the arena (2026-10-17).** The user's: they were landing off at the walls. Now they fall from 40-70 m over the floor: every other one scattered within 12 m of a player inside, the rest anywhere in the arena round the heart (its open middle, 160 m across), drifting a little as they drop (`HeartQuake.pick_chunks`). The wall dust and crumbling stay at the walls as effects.
- **Kick and chunks retuned (2026-10-17).** The user's: the kick's launch does 15 damage (was 50). Chunks fall from 100-150 m (was 40-70) and keep falling till they land (no time limit; freed only if they drop out of the world). At most 5 fall at once (`HeartQuake.MAX_CHUNKS`, counted by `FallingChunk.alive`): a kick drops only as many as there's room for.
- **The kick shakes the cathedral (2026-10-17).** The user's picks. Its walls, columns and mezzanines judder for ~0.45 s (the `Cathedral_plain` and `Tower_5_concrete` meshes move 0.45 m, easing off; collision stays put, so your footing doesn't change). Its lamps flicker and dim for 0.35 s. 4 curtains of dust and grit pour down from 60-150 m up across the room (`HeartQuake.sheet`).
- **The predicting beam (2026-10-17).** The user's: each volley adds one beam at where the chosen player is heading. It uses the flying roaches' spit lead and the same values (`HeartBoss._predict`): sideways speed x0.8, toward/away 0.3 of that, a random 0.4-1.3 share each time, up to 1.2 m sideways guess, 0.4 m past them, 0.25 m scatter. It's carried on for the glow time until it blasts.
- **Beam sounds (2026-10-17).** The user's: heard when you're near (90 m). A rising whine while a hole glows (pitched to peak as it blasts), and a roar while it blasts (low boom, gushing rush, sizzle) placed at the point on the beam nearest you. They're placeholders generated in code (`BloodBeam._make_sounds`) until there are real files.
- **5 more cathedral lamps (2026-10-17).** The user's: scattered round it, warm and low (8-40 m up, 80 m range) and cold and high (60-160 m up, 140 m range) in turn, from the cathedral's own dice (`StackBuilder.CATHEDRAL_LAMPS`). They flicker with the kick too. Re-baked.
- **Dying, immersively (2026-10-17).** The user's: no "YOU DIED" text any more. Your body goes limp: a ragdoll of your own character in the pose it stood in, every bone carrying on at the speed you were going (and tipped the way you were heading). Your view leaves your head and pulls back 15 m over 5 s, looking down at the body (stopping short of walls), as the screen slowly fades to black. 0.4 s after full black you're back: at your camp if you had one, else the level restarts. You wake up on your back, the view rising to your eyes over 1 s (like getting up after the Stalker's throw), the black lifting over 0.8 s, controls back once you're up. `PlayerDeath` (`begin` on `Health.died`, `wake` on respawn or after the restart). Co-op: every machine's copy dies and drops its own ragdoll; only your screen pulls back, fades and wakes.
- **Dying in the Stalker's grip (2026-10-17).** The user's: no second body and no fight over the camera. The dragged ragdoll goes limp where it lies and becomes the body (`StalkerDrag.die`): no more pulling, no more riding its head, and the Stalker letting go of the corpse doesn't snap your view back (`release` does nothing once dead). The death view pulls back from where the drag view was. Waking frees the drag and puts your eyes back where they were before the grab.
- **The Stalker's eyes glow (2026-10-17).** The user's: blue, glaring, unmissable through the fog and the dark. Two hot billboard points on its head (its eyes, 0.2 m x SIZE), each with a glare that stays a few pixels big at any range (`fixed_size`), a soft round halo, all with fog off (`disable_fog`) and added over the dark, plus a faint blue light on what's in front of its face. Walls still hide them. They follow the posed head bone every frame, and keep updating even past 90 m (`Stalker._update_eyes`).
- **Stalker fear gains halved (2026-10-17).** The user's: it filled too fast. Seen 0.15, panic fire 0.10, running off 0.10, whipping round 0.05, investigating the scream 0.5 (were 0.30, 0.20, 0.20, 0.10, 1.0).
- **Hurting chunks twice as big (2026-10-17).** The user's: the falling chunks that can hurt are 2.4-5.2 m (were 1.2-2.6), so they stand out from the harmless rubble. Their hit size grows with them. The bits they burst into stay rubble-sized.
- **Half the cosmetic debris (2026-10-17).** The user's: each burst of harmless rubble (wall crumbles, dust curtains' grit, a chunk bursting) throws 7 bits (was 14). The chunks that hurt are unchanged.
- **Stalker head bobble halved (2026-10-17).** The user's: it shook too wildly. The neck and head show half their springs' swing (`Stalker.JIGGLE_AMOUNT` 0.5), with the same rhythm. The user's stiffness of 13 is kept.
- **Death ragdoll falls heavier (2026-10-17).** The user's: it floated. Its bones fall at 2x the world's gravity (`PlayerDeath.BODY_GRAVITY`), matching the player's own 20 m/s². This includes a drag ragdoll that becomes the body.
- **Stalker eyes: just the piercing points (2026-10-17).** The user's: the soft round glow and the blue light off its face are gone. The two blue eye points and their screen-steady glare stay, still unmissable through fog and dark.
- **Stalker eyes are pinpoints (2026-10-17).** The user's: a glow still covered the whole Stalker. That was the screen-steady glare (`fixed_size`): 0.045 meant ~20 px an eye at any range, bigger than its whole body far off (the halo, gone since, was ~75 px). The glare is now 0.012 (~6 px) and the eye core 0.12 m x SIZE (was 0.2): sharp blue points.
- **The cathedral rearranges itself (2026-10-17).** The user's: no hiding behind the same wall. Its structures (each mezzanine with its ramps, the columns, the hanging pyramid, the leaning slab, the mid-air stairs) are baked as their own moving pieces (`StackBuilder._moving_pieces`: an `AnimatableBody3D` each under `CathedralPieces`, tagged by `_unit` in `_hall_features`; no random numbers used, so every other hall is unchanged). Every 10 kicks (`HeartBoss.SHIFT_EVERY`) each heads for a new spot within 25 m of where it was built, level, at 1 m a beat, staying in the room and out of the open middle. A new shift retargets from wherever a piece is. Standing on one carries you. Co-op: the host picks (`Network.send_heart_shift`). The cathedral's deck growth and deck nests are dropped (they'd float); floor growth stays.
- **Shifting pieces never clip the heart (2026-10-17).** The user's: each new spot, and the slide there (checked every 2 m), must stay clear of the heart's bounds swollen by a full thump plus 6 m. Otherwise it tries again (12 tries), or stays put. Tested over 50 rounds: no clips, nearest piece 84 m from the heart.
- **Shifting pieces judder on kicks too (2026-10-17).** The user's: each piece's mesh shakes with the walls on a kick. Only the look moves: its body, and anyone standing on it, stays steady.
- **The Stalker keeps out of the cathedral (2026-10-17).** The user's: it won't follow you in. Players in the heart's cathedral (`HeartBoss.room_contains`) don't count for it: not stalked, staged for, struck or turned up near. With everyone in there it waits. Caught inside itself, it slips out unseen to the floor under the stairs up (below `CathedralSpawn`) and waits there. If its target gets in mid-approach it lets them go and hides. It picks up again when you come out (`Stalker._in_cathedral`, `_leave_cathedral`).
- **Cathedral pieces lurch on the kicks (2026-10-17).** The user's: the old slide at 1 m a beat was too slow to notice. Now every 10th kick picks the new spots; on each of the next 5 kicks every piece lurches a fifth of the way (up to 5 m), snapping there over 0.25 s (fast, then settling). It arrives on the 5th kick and holds for 5 more till the next shift. The lurches ride the kick's relay (`HeartBoss.quake`), so every game lurches together. Tested headless: 21.5 m went in five 4.3 m lurches, then held.
- **Bigger cathedral shifts (2026-10-17).** The user's: up to 50 m from where each piece was built (was 25), and each move at least half that before the room's walls or the open middle hold it back (`HeartBoss.SHIFT_RANGE`, `SHIFT_LEAST`). Still never clipping the heart. Tested over 50 rounds: no clips, median move 34 m, nearest piece 71 m from the heart. Each lurch is now up to 10 m.
- **Steam co-op invites (2026-10-17).** The user's: `SteamCoop` (`scripts/net/steam_coop.gd`, made in `Network._init` because the pause menu asks after it before Network is ready). Host on Steam makes a friends-only lobby and hosts with GodotSteam's `SteamMultiplayerPeer`. Invite friends opens Steam's invite list. Joining comes from an accepted invite, Join Game, or `+connect_lobby` on launch, then connects to the lobby's owner. After that it's Network's usual flow (`use_steam_peer`). Every Steam call goes through `Engine.get_singleton` / `ClassDB`, so the game runs without the extension, and the Co-op panel says why Steam's off. Pings are measured by the game (`Network.round_trips`) for non-ENet peers; `Net.half_ping` and `round_trip_msec` fall back to them. App ID 480 (Spacewar) in `SteamCoop.APP_ID` and `steam_appid.txt`. The extension isn't installed yet (it needs the user's download OK); setup and testing steps are in docs/STEAM.md.
- **GodotSteam installed and working in the editor (2026-10-18).** GodotSteam GDExtension 4.23.1 (the user's install, the right one: it includes `SteamMultiplayerPeer`). The Steam edition of Godot ships an older `steam_api64.dll` (10.24) that Windows loads first, breaking GodotSteam (Error 127). With the user's OK it was swapped for GodotSteam's 10.83 in Godot's Steam folder, with the original kept as `steam_api64.dll.godot-original.bak`. Checked: the singleton and peer class are there, and Steam starts (app 480) with the user's account. Two-account invite test still to do. Details in docs/STEAM.md.
- **The heart can be hurt, stunned and killed (2026-10-17).** The user's. It has a body for shots (`HeartHitbox`: the model's own convex shape) with 700 health, and flashes white on every hit. Every 150 damage (not counting what lands while stunned) it's stunned for 10 s. The music record-scratches down (playback speed sliding to a stop over 0.7 s, then paused). It only beats, at 60 BPM on the first stun and 10 faster each stun after, spurting blood from 3 spots on its surface each beat. Every shot into it counts as an artery shot (red hitmarker, its own artery spurt where hit, 1.5x damage; no lingering bleed). Then the music DJ-scratches back up (0.03x to 1x over 0.5 s) from exactly where it stopped, and the attacks pick up with the song. At 0: a big blood burst, it hangs still and silent (music scratches to a stop), your screen fades to black over 7 s, "You've killed the heart... but what about the brain?" fades in (1 s), holds 4 s, fades out (1 s), and the game fades back (2 s). Co-op: the host's Health decides; hits, stuns, recovery and death go to everyone (`Network.send_heart_event`). WeaponController asks a target for its hit kind if it says (`artery_now`) and lets it spray its own artery blood (`artery_spray`). `Health.bleeds_out` (off on the heart) stops lingering bleed damage. Tested headless: no stun at 100 damage, stun at 160, recovery, death past 700.
- **The heart's song crossfades as it loops (2026-10-18).** The user's: its last 2 s blend into its start (a second player fades in from the top as the old one fades out), and the beat map starts over with it (`HeartBoss._loop`). A stun cuts the fading tail.
- **The laser beats the kick (2026-10-18).** The user's: you can't be hurt by a beam and the kick's launch at the same moment. Within 0.3 s of each other, only the beam's 35 counts: a kick on someone a beam just hit does no damage (it still launches them), and a beam on someone the kick just hit gives the kick's 15 back (`HeartQuake.laser_over_kick`, `SAME_TIME`).
- **Hi-hat blood orbs (2026-10-18).** The user's (`HeartOrb`). On each hi-hat, a bubble of blood swells out of a random spot on the heart for the beat before. That's its warning instead of a glow: a blister growing and quivering. On the hat it breaks free and drifts after a player inside at 6 m/s, steering round as they move and passing through the heart. It pops (a burst of blood, a splash under it) when it reaches them (15 damage), runs into anything, is shot once (1 health; shootable while still swelling), or on its own after 8 s. At most 10 at once. It's 0.8 m across, glossy dark red. Co-op: the host's moves for real and calls the pops (`Network.send_heart_orb` / `send_heart_orb_pop`). Tested headless: swells in place, drifts after its target, pops when shot.
- **get_meta errors on death (2026-10-18).** The user's report: `get_meta(key, null)` still errors in Godot 4.7 when the key's missing. `PlayerDeath` and `StalkerDrag` now check `has_meta` first.
- **Heart boss optimised (2026-10-18).** The user's ask; same looks and play. **Chains** (~2,000 links): each link's turn is worked out once at rest and only positions are redone (1.35 -> 0.23 ms an update, measured), and only when the pulse has moved (skipped while the heart's at rest). **Room shake:** does nothing between kicks. **The cathedral's world box** is worked out once. **Beam volleys** (7 beams + 7 ricochets): at most 4 light the room, 4 whine and 6 roar at once (`BloodBeam.MAX_LIT/MAX_CHARGING/MAX_ROARING`); ricochets carry half the spray and no mist; the mist mesh is shared. **Kick effects** reuse shared particle materials (per kind and size bucket: `HeartQuake._materials`) instead of ~30 new ones a kick. **Orbs** share one sphere mesh. **Stalker:** finds the heart once instead of several times a tick.
- **A predicting beam per player (2026-10-18).** The user's: in co-op every player in the cathedral gets their own predicting beam each volley (the roaches' lead), on top of the one aimed beam at a random player and the random ones.
- **Heart health and stun doubled (2026-10-18).** The user's: 1,400 health (was 700), stunned every 300 damage (was 150), so still 4 stuns before the last stretch.
- **Gun ranges doubled (2026-10-18).** The user's: every hitscan gun but the sniper reaches twice as far. Uzi, dual Uzis, machine gun and shotgun 80 m (were 40); PKM 120 (60); PPSh 160 (80); revolver and pistol 200 (were the 100 default). Sniper stays 300. The RPG (a rocket) and grenade (thrown) don't use range.
- **Heart hitbox fits it (2026-10-18).** The user saw hits not flash. The hitbox is now the heart's exact outline (it was simplified, which cut in under its bulges) at its thump size, so a shot that looks like a hit is one. The main cause, though, is range: measured from the floor, the heart is 77 m away right under it, 84 m from 40 m out, 140 m from near the walls, so the 80 m guns only reach it from almost underneath.
- **Wind climbs from the cloud deck to the top (2026-10-18).** The user's: barely there at the cloud deck, only getting stronger to the very top. `WorldWind.strength()` runs 0 at the level's CloudDeck height (650 m) to 1 at its tallest megastructure's top (~5,030 m: the Stack), eased in (squared). The push is 0.16 m/s at 1,500 m, 0.8 at 2,500, 1.8 at 3,500, 3.3 at 4,500 and 4-7 (gusting) at the top. The open-sky wind sound follows the same climb (`MegastructureSound`). It used to start at a fixed 4,000 m left over from the procedural Stacks.
- **The Stalker hunts you down your trail (2026-10-18).** The user's design, replacing the leash teleports (which made moving fast meet no one). Every player leaves a trail: a crumb every 3 m where they touch ground or a wall, gaps jumped (over 6 m) kept as leaps, the last 600 m, and a jump too fast to have been travelled (a respawn) starts it over. Out of its sight 3 s (any fear, and over 30 m off), it hunts the nearest player at 25 m/s along the very way they went, leaping their gaps. More than 300 m behind along the trail, it skips on between crumbs no one can see, never past their newest. Seeing them again or within 30 m, it stalks (or flanks). Spotted while hunting, it bolts and hides, then picks the trail back up. Its skitter carries 3x as far and 4 dB louder while it hunts. The far-off and stuck teleports are gone; cut off indoors, it hunts. Back from AWAY it turns up down your trail (55-85 m back, unseen) when it can. **Full fear:** not looked at, it flanks round you at 18 m/s on a 20 m ring toward your back, then creeps in. Within 20 m (`GRAB_RANGE`, was 10; looking at it or not) it lunges for the grab instead of an instant grab. Spotted further off at full fear, there's no stare: it bolts at once. **Every bolt** goes sideways out of the nearest viewer's view as much as away, zigzagging (`_flee_dir`), so it stops loitering in plain sight. **The cathedral rule is gone** (the user's): it can reach you in the boss fight. Not yet run.
- **Fear only from what you really noticed (2026-10-18).** The user's: it rose with nothing seen. **Glimpsed** now needs it clearly in view: within 30 deg of the middle of your view, within 60 m (through the fog), for 0.3 s, once a sighting (`_clearly_seen`, `GLIMPSE_*`). It still hides whenever it's anywhere in view. **Reactions** (running off, whipping round, panic fire) count only after a stunt you saw, or one right beside you (the rattle behind you, being grabbed): `_moment(perceived)`. Glimpses no longer open a window. **The scream** counts only if you go to it on purpose: within 15 m of it inside 60 s of hearing it (it's 70-140 m off). **A note** under the fear bar shows why each time it rises (`+15%  glimpsed`), fading after 2.5 s, with the fear meter setting on (`Network.send_fear_note` to every screen).
- **The Stalker only teleports past 600 m (2026-10-18).** The user's: no skipping on at 300 m. It runs your whole trail itself. Only fallen more than the trail's 600 m behind (making for its oldest crumb and still more than 40 m from it: `FELL_OFF`) is it put back on your trail at its far end, 600 m back, at the first crumb from there no one can see (`_to_trail_end`).
- **Stalker eye glow halved (2026-10-18).** The user's: the blue glare round each eye is drawn at half strength (`EYE_GLOW` 0.5). The white-blue eye points themselves are unchanged.
- **Watch yourself get dragged (2026-10-18).** The user's: while the Stalker drags you, the view pulls out of your head (over 0.6 s) to 8 m off to one side and above, framing you and the Stalker together (the middle between your body and it). It follows smoothly and stops short of walls, the side picked once so it never flips. It eases back to your eyes when you get up, or the death view takes over from it (`StalkerDrag.DRAG_VIEW_*`).
- **Drag camera back to the old one (2026-10-18).** The user preferred it: the 8 m third-person drag view is reverted, and the camera rides the ragdoll's head again. Also, Godot's hot-reload `~` DLL copies and `.TMP` files are now in .gitignore, and the ones that had slipped into commits are untracked.
- **A sound slot for everything the Stalker does (2026-10-18).** The user's: they have many screech samples, plus "help me" / "follow me" lines to make players paranoid. `StalkerVoices` (`audio/events/stalker/stalker_voices.tres`) has 26 slots, each a `SoundEvent`:
  - hurt: hurt, driven_off, leaves;
  - attacking: lunge, grab, dragging, thrown_off, dropped;
  - stalking and hunting: starts_stalking, starts_hunting, hunting, flanking, turns_up, fear_full;
  - seen and hiding: spotted, runs_away, hiding;
  - stunts: croak_behind, help_scream, lure, behind_you, watching, ceiling_scuttle, doorway_dash, corpse_drag, leap.

  Fill a slot by dragging clips in, or drop files named `<slot>_<n>` into `audio/sfx/stalker` (README there). One plays at random, through the halls' echo, on every machine (`Network.send_stalker_voice`). Empty slots are silent, except the croak, shriek and help scream, which fall back to the old sounds. It's kept sparse: no voice within 6 s of the last, except the urgent ones; everyday ones play only 40% of the time; hunting voices come every 12-20 s, dragging every 4-7 s. **The lure** is a new sound-only stunt in its usual rotation: "help me / follow me" from out of sight nearby, whispered right behind you, or far off through the echo, picked at random. Players may still linger; nothing about that changed (the user's call).
- **Half the radios (2026-10-18).** The user's: a window room rolls a radio a quarter of the time (`Megastructure.radio_chance` 0.25, was 0.5), so about half as many play. StackBuilder's own `RADIO_CHANCE` is a leftover that only keeps its dice in step; it places none.
- **Stalker voices: echo only in the Stack or far off; the grab and lunge always heard (2026-10-18).** The user's. Inside a megastructure its voices go through the halls' echo as before. Out in the open (`StalkerSound._open_air`) a voice is dry and clear close by, increasingly muffled further off (a distant call), and only from 60% of the way to the fog line (the level's live `fog_depth_end`, 242 m in the open world: so from ~145 m) does the echo fade in under it, full at the fog. Going for you (lunge) and grabbing you always make a noise: both are urgent (past the spacing and chance), and an empty slot falls back to the croak (lunge) or the shriek (grab).

- 2026-10-18: Sleeping at a bedroll moves the Stalker 40% of the way down your trail at once (Stalker.slept, SLEEP_PROGRESS 0.4). The 40% is of the trail between it and you, and it lands on a crumb no one can see, never past your newest. It does nothing mid-drag, lunge, flee, stunt, while away, or while someone can see it.

- 2026-10-19: Crash fix: PathRequests skips a waiting request whose enemy has left the level (it read a null world's navigation_map). SeededGrowth draws nothing when no tendril is out, instead of erroring with an empty ImmediateMesh surface.

- 2026-10-19: The Stalker's body rides 25% lower to the ground (BODY_HEIGHT 0.6 -> 0.45 x SIZE). Its hands and feet stay planted, and its eye line and fallback hitbox drop with it.

- 2026-10-19: Reverted: the Stalker's body is back at its old height (BODY_HEIGHT 0.6 x SIZE). The user preferred it.

- 2026-10-19: Invite friends still tries Steam's overlay invite window, which is often missing when the game runs from the editor. It now also lists your online Steam friends (online, away or busy, sorted by name) in the Co-op panel. Clicking one invites them straight to the lobby (SteamCoop.invite_friend / inviteUserToLobby), no overlay needed.

- 2026-10-19: Every Stalker voice line plays 1.25x faster at the same pitch (StalkerSound.VOICE_SPEED). Each line is sped up with pitch_scale, then fed through HallEcho.sped_bus, an AudioEffectPitchShift that puts the pitch back before the usual bus and its echo. The echo itself is unchanged, and the two looping clips stay looping (both the user's choice).

- 2026-10-19: The heart's record scratches take twice as long: SCRATCH_DOWN 0.7 -> 1.4 s and SCRATCH_UP 0.5 -> 1.0 s. The slow-down on death uses SCRATCH_DOWN too, so it's longer as well.

- 2026-10-19: The heart's blood orbs fly three times as fast (HeartOrb.SPEED 6 -> 18 m/s). Their turn rate is unchanged, so they swing round in wider arcs.

- 2026-10-19: Blood orbs steer like heat-seeking missiles. They turn at most 45 degrees a second (HeartOrb.TURN_RATE, replacing the old eased TURN), so at 18 m/s a late dodge makes them overshoot and swing wide. Ones that can't come round in time pop on the wall they fly into.

- 2026-10-19: Hitch fix: the blood orb's look (HeartOrb.look_model) is now shown in ShaderWarmup at level start. Its shader used to compile when the first orb swelled out, freezing the game for a moment.

- 2026-10-19: ShaderWarmup now covers everything made mid-game, not only blood and barrels (the user: "all other materials"). That means every effect: artery spurts, tracers, explosions, heart quake dust and sheets, falling chunks, blood beams, acid spit, seeded growth, rocket flame and trail, worm dirt, backblast, muzzle flash, meat flies and the hit flash. It also covers the materials made in code (wings, Stalker eyes, backpack, grapple ring, pickup outline) and the hunger and trip screen overlays. And it covers every scene that can turn up after load: the scenes/enemy, npc and props folders, the pickups, the weapon and item models from the weapons data, the Stalker model, and every model those scenes' scripts hold. Each scene is shown as a lifeless copy, with scripts, groups, scene connections, autoplay sounds, cameras and multiplayer nodes stripped and processing off. New visual-only builders for this: Explosion.play_visuals, CarryItem.make_flies, Viewmodel.backblast_smoke, Rocket.warm_up and WormFX.warm_up.

- 2026-10-19: Blood orbs got a few changes. Speed 18 -> 20.7 m/s (+15%) and turning 45 -> 33.75 deg/s (-25%). A trail like Skarlet's blood orb (MK11): a glossy blood streak tapering behind it over 0.6 s, wobbling, with 20 glossy bubbles beading off and shrinking away, no drips (the user's picks). Godot 4.7 has no trail node, so the streak is HeartOrb.Trail, a camera-facing ribbon drawn from its path. Every pop (shot, hit or contact) now makes a small blood explosion: BloodFX.spawn_burst, the mutation explosion's core at half strength, which replaces 3 of the 4 sprays. The streak and bubbles are in ShaderWarmup.

- 2026-10-19: Grandma's house, in the middle of her yard with its front (-Z) toward the Stack. Every choice was the user's, based on their reference image.
  - **Outside:** real size (10 x 8 m, two 3 m storeys). Plaster_19 walls, a Plaster_20 band between the floors, a Roofs_01 gable roof, a centre bay under its own gable, and a porch with posts and a pediment. Dark opaque panes (House/window_dark, generated) sit in Wood_22 frames with cross bars, and the front door is Wood_22.
  - **Inside:** the living room is open (Horror_Wall_01 walls, Wood/Wood_06 floorboards), with the stairs up its back wall and Grandma in it. Seven rooms are locked for quests and rare 1-of-1 keys later. Each has a func_door_rotating with targetname house_<room> and "Locked.", which a quest or key opens by firing that targetname through MapIO. The rooms: kitchen, study, cellar (a door under the stairs), and, behind the house_landing door at the top of the stairs, bedroom 1, bedroom 2, the bathroom and the attic (a ceiling hatch).
  - **No loading screen (the HL2 way, like areaportals):** GrandmasHouse shows the inside only while the front door's open or a player's in the house. That covers the func_detail house_interior, the locked doors, Grandma and the lamp. Otherwise they're hidden, and Grandma and the doors are asleep. Hidden rooms keep their collision.
  - **How it's built:** tools/make_grandmas_house.gd (house_bake.gd) writes maps/grandmas_house.map (TrenchBroom, 32 units/m, editable; the stairs have a clip ramp) and builds scenes/world/grandmas_house.tscn with func_godot. After TrenchBroom edits, use the scene's Map > Build. test_world_bake places the house too, so re-baking the world keeps it.
  - **Spawn:** the player's start (0, 33.5, 0) is now in Grandma's living room.

- 2026-10-19: The Flesh Tree's roots take over Grandma's house (the user's: a few draping, 2 roots, solid). FleshTree.HOUSE_ROOTS paths are in house space: one runs over the roof ridge and off the front-left corner, the other onto the back slope and down the back wall between the windows. They're part of the tree's one muscle mesh and trimesh collider, so you can walk and grapple them. The house joins the group grandmas_house so the tree can find it.
- 2026-10-19: The red weed (RedWeed, shaders/red_weed.gdshader), the user's picks:
  - **Look:** Spielberg's 2005 War of the Worlds. Knotted mounds of glossy blood-red vines with ropey runners creeping out over the ground, thin drooping tendrils curling at their ends, and swollen pods.
  - **Where:** 40 bushes 21-38 m from the trunk (thicker near it), 16 round the yard's edge 30-52 m out (never on the house, porch or path to the door), and two patches climbing the house's back wall between the windows.
  - **Size and cost:** 0.5-2 m tall. Four shapes made once; every bush is a MultiMesh instance, drawn within 220 m.
  - **Behaviour:** you pass straight through it. It writhes slowly, and its tendrils curl toward any player within 5 m (the players' positions go to the shader each frame).
  - **Co-op:** a fixed seed means the same weed in every game.

- 2026-10-19: Grandma's house is twice as big (the user's): GrandmasHouse.SIZE 2, giving 20 x 16 m and 6 m storeys. The bake builds at it, and the tree's roots over the house, the house bounds and the red weed's house exclusion and wall patches all follow it. Grounding fix: it was floating, because its ray down from 200 m up landed on the Flesh Tree's limbs or the player. It now takes the terrain's own height there (Terrain3DData.get_height), else a short ray from just above that skips the players. Collision was checked headless: walls, floors, roof, stairs and door all stop a ray.

- 2026-10-19: Grandma is a Fallout-style quest giver now (the user's): her missions and portals are gone from grandma.gd and grandma_dialogue.gd. GrandmaQuests holds her quests, one so far.
  - **The quest:** CIGARETTES, the last pack in the world (Backpack.Kind.CIGARETTES, the PSX pack's cigs_packet_1). StackSecrets puts exactly one somewhere inside the Stack: any hall key spot or window room, any tower, any height. It's never made while someone carries one, and never once she has it.
  - **Grandma's lines:** the user's 'sweet but off' set. She hints which tower and how high (GrandmaQuests.where_in, from the Stack's nest_columns: e.g. 'the second-tallest tower, about halfway up').
  - **Reward:** 14 virus points for every player (Virus.gain_points).
  - **Co-op:** shared and host-owned. Network.quests is mirrored to everyone and sent to late joiners. Network.ask_quest carries 'accept' and 'hand_in', and Network.send_backpack_take keeps the owner's pack in step. It survives deaths and reloads.
  - **Pickup look:** keys and the cigarettes float 1 m over the floor, spinning and bobbing like San Andreas pickups (CarryItem.SPIN_KINDS). They're frozen till taken (walk into or grapple), and only the model turns, so nothing moves on the network.

- 2026-10-19: Grandma's front door was invisible. Headless bakes run a stand-in renderer that now and then drops a mesh, and the last rebake lost the front, study, kitchen and cellar doors. The bake now rebuilds until no piece's mesh is empty. The front door is press-to-open (the user's): MapDoor 'use' 1, also offered in TrenchBroom on func_door and func_door_rotating. F opens it ('[F] Open'), walking up doesn't, and it shuts by itself 0.8 s or more after opening, once no player is within 1.5 m of it (walked all the way through).

- 2026-10-21: Wendigo Stalker, chunk 1 (the user's picks):
  - **Pacing:** stunts come 3-5 min apart (STUNT_EVERY 180-300), twice as often while anyone carries raw meat.
  - **Wrong silence:** a stunt picks its player first, and that player's world sounds (the Ambience and Enemies buses) fade out over 4 s before it's staged. They come back 1.5 s after it's done, or 6 s after a sound-only one. StalkerSigns.silence relays through Network.send_stalker_sign, with a 90 s failsafe.
  - **Its own bus:** the Stalker's voices and skitter play on the new Stalker bus, so the silence never mutes it.
  - **No tingle:** 'A tingle goes down your spine.' is gone.
  - **F9 test menu:** StalkerTestMenu, in every build, host only. One click per stunt, plus wrong silence and breathing; Stalker.test_event forces it on you through the same silence lead.

- 2026-10-21: Wendigo Stalker, chunk 2, its look (the user's picks: small broken antlers, clearly stretched, frostbitten grey):
  - **Stretched:** its joints are moved apart, so the skin stretches without the limbs fattening. Arms 1.4x, fingers 1.5x, legs 1.15x, and the waist 20% thinner (Spine squeezed, Spine2 set back).
  - **Skin:** grey-blue (SKIN_TINT), a little glossy (roughness 0.42). Each vertex is shaded by its hand and foot bone weights, so the hands and feet are darkest (FROSTBITE) and the forearms and shins a little.
  - **Antlers:** small broken ones out of the skull on a BoneAttachment3D, bone-coloured. The right has one tine; the left is snapped half-grown and ragged.

- 2026-10-21: Wendigo Stalker, chunk 3: breathing (the user's: when it's close). Within 15 m of your camera and out of your sight, its slow wet breathing fades in from where it is (louder closer), and fades out in sight or further off. Each game handles this for its own camera. New StalkerVoices slots: breathing, knock and chewing. The fallbacks are a generated breath loop, three generated knocks, and the bone_crunch clips.

- 2026-10-21: Wendigo Stalker, chunk 4, the stunts reworked (the user's picks):
  - **Upright:** the body can stand at full height on every game, carried in net_state. The spine stands straight, the long arms hang nearly to its knees, the feet step under it and the head goes over at 90 degrees. It unfolds over about 0.6 s.
  - **Behind you:** standing, holds 16 s. Noticed, it looks at you a beat (1 s), then scrambles off.
  - **Watching:** unchanged, holds 30 s.
  - **Ceiling, doorway and corpse drag:** one of two styles at random. Either it stops dead halfway for 1.2 s and looks at you, then goes on at 45% speed; or it crosses slow and wrong, in jerky snatches at 30%, its head turned away (head_averted, also carried in net_state).
  - **Help scream:** where it came from there's nobody, only signs (StalkerSigns.help_signs, on every game, gone after 5 min): a blood trail off into the dark, four long scratches gouged in the ground, and torn clothes, one bloodied.
  - **Leap:** landed across the gap, it stands and stares 2.5 s, then it's gone.
  - **New: Angel, the weeping-angel stunt.** It stands dead still about 40 m off, 5 m closer each time you look away and back (where you can't see it move). Within 8 m it's gone. 90 s at most.

- 2026-10-21: Wendigo Stalker, chunk 5, Grandma's house stunts (the user's picks). They join the rotation only while their player is inside the house (GrandmasHouse.has_inside).
  - **Knock:** three slow knocks at the front door (the 'knock' slot; a generated stand-in till the user's clip). Opened within 40 s, it's out at the fog's edge 45 m off, upright, head turned away, walking away at 1.4 m/s. It's gone after 12 s, or once they step out after it.
  - **Window:** one of the living room's windows they face (GrandmasHouse.WINDOWS: front-left, left side, the stairwell's) goes pale, lit from outside, with its antlered shadow standing against the pane: too tall, thin, arms hanging past its hips. Every game sees it (StalkerSigns.window_shadow). It fades if you walk at it (within 4 m, or 2 m closer than you were) or after 15 s. Looking at it counts as seeing it.

- 2026-10-21: Wendigo Stalker, chunk 6, the camp visit (the user's: 1 in 4 sleeps; tracks, fire out, antler totem). Sleeping at a bedroll (Bedroll passes itself to Stalker.slept), one sleep in 4 (CAMP_VISIT_CHANCE) it came while you slept, and every game shows its signs (StalkerSigns.camp_visit). There are 14 long-fingered hand and foot prints circling the bedroll, gone after 10 min. The camp's fire is put out (Camp.put_out: no flames, light or cooking). A little totem of three lashed sticks, crowned with a small antler and with a bone hung off it, stands stuck in the ground by your head and stays with the camp. The F9 menu gets a 'Camp visit' button (the nearest camp).

- 2026-10-21: The camp visit's totem is gone (the user's). Only the tracks round the bedroll and the fire out remain.

- 2026-10-21: Wendigo Stalker, chunk 7, hunger (the user's: draws and hunts):
  - **Raw meat:** with raw meat in a player's pack, it stalks them at half the distance (MEAT_CLOSER), and stunts come twice as often.
  - **Rotten meat:** it hunts that player straight down their trail (from STALK or WAIT, while they're past HUNT_UNTIL).
  - **Eating (new State.EAT):** raw meat or a body lying within 80 m that nobody can see (not climbers, not its own stunt corpse, not dragged ones), it goes to and eats for 7 s, chewing every ~0.9 s (the 'chewing' slot; bone_crunch stand-ins). It leaves only bones (StalkerSigns.bones: long bones and a curve of ribs in a dark stain, for 10 min). Seen while eating, it hides like ever.
  - **Test menu:** F9 gets 'Eat (nearest meat or body)'.

- 2026-10-21: Wendigo Stalker, holding (the user's: hand-accurate, a human dragged by the head in its hand, ragdoll physics, immersive).
  - **Reach and grip:** its right arm reaches with IK for what it takes (REACH_TIME 0.3 s), then grips it by its hip (GRIP).
  - **Ragdolls:** a ragdoll's head is pulled to the real hand bone each tick (HOLD_PULL; the rest drags loose behind, carried at 75% weight). A thing with no ragdoll is carried whole in the hand.
  - **Co-op:** ragdolls are each game's own, so every game holds its own copy. The host names the body by where its head is (signs 'reach', 'hold', 'let_go'; clients look again for 1.5 s if the puppet isn't there yet), and net_state carries HOLD and REACH.
  - **Corpse drag:** now by the head, in its hand (was a foot).
  - **Open world:** the skitter-past and corpse-drag stunts now work out on open land. With no cover beside the path, they come from past the edge of everyone's view (_out_of_view_beside), and when the player's moving fast they aim 1.5 s ahead of them.
  - **Grapple:** PlayerGrapple.anchor_point() added, for the grapple stunt.

- 2026-10-21: Wendigo Stalker, fast stunts (the user's picks; moving fast = 18 m/s and up, flat). They go first in the pick then. Gone in sight never means vanishing: it scrambles off out of sight. That now also covers the leap, the angel and the knock when they end in view.
  - **PACER:** alongside you 40 m out, keeping pace (up to 32 m/s). Watched 2 s, or after 10 s, it peels off into the murk (gone once unseen).
  - **PATH:** standing upright where you're heading, 2-4 s on (lateral tries of 0, 8 and 15 m), placed only where you can't see it yet. Within 20 m it scrambles off, fast. 12 s at most.
  - **CROSS:** one long bound across your way ahead, 1.3 s in the air (apex ~4.6 m), from past the edge of your view. It lands and scrambles off.
  - **GRAPPLE:** while you're on the grapple (PlayerGrapple.anchor_point; also if you grapple during the silence before a stunt), it races from somewhere near the anchor you can't see (6-14 m off) to the anchor and crouches facing you. Within 6 m of you, or the grapple let go, it scrambles off.
  - **Fights:** each player's last shot is now tracked, for the fight stunts.

- 2026-10-21: Wendigo Stalker, fight stunts (the user's picks: no silence for them, on the normal clock, the snatch takes anything). Fighting means a shot within 8 s and a live enemy within 45 m (no bosses: over 500 health); these go first then.
  - **SNATCH:** it rushes from out of sight at one of the things you're fighting (preferring one off to the side), its right arm reaches (REACH), and at the grab it kills it (no drops) and holds it by the head. A human screams (help_scream). It drags it off flat out for 6 s, gone once unseen. A thing with no ragdoll was carried whole, and is eaten when it's done.
  - **FIGHT_WATCH:** upright at the edge of the fight, 25-35 m off and just past the edge of your view. The fight over 5 s, or you looking straight at it: it scrambles off.
  - **FALLEN** (as a fight ends: shots within 25 s, nobody alive within 25 m, a body you can't see within 45 m): it's crouched over the body, head down, eating (chewing). Seen, it looks up at you 1.2 s, then drags it off by the head.
  - **AMONG:** from just past the edge of your view beside one of the chargers, it joins the charge upright. A fake charge: it never comes within 24 m (outside its grab range), 1.8 s at most, then it veers off scrambling.
  - **Grace after stunts:** no grab for 4 s after any stunt (it's leaving), and 'In your path' now flees at 24 m. Without this, it would have lunged right after scrambling off.
