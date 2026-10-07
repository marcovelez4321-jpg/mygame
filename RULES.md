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

---

## Creative Direction — what the game IS

Working title: **Grandma's Boy**. New enemies, weapons, levels, sounds and UI
get checked against this the same way code gets checked against the rules
above.

- **Setting.** You live at Grandma's suburban house (the hub). Her portals drop
  you into a **lawless city** — not a post-apocalypse or a wasteland, but a
  living, rotten, Gotham-style city where the cops gave up and nobody's in
  charge. Alleys, rooftops, fire escapes, corner stores, trap houses, subway
  tunnels. It should feel like a real place gone wrong, not a ruin.
- **Enemies.** Crackheads and the city's lowlifes: tweakers, junkies,
  scavengers, petty crime crews. Exaggerated caricatures played for dark
  comedy — twitchy, unpredictable, desperate, occasionally pathetic, dangerous
  in a crowd.
- **The player.** Inspired by the Postal Dude: deadpan, unbothered, a little
  unhinged — the straight man in a city that's lost its mind, and just as much
  a target of the joke as everyone else.
- **Tone.** Doesn't take itself seriously, but takes its craft seriously.
  GTA / Postal-style satire: gory and shocking in a fun way, never grim. The
  violence is the punchline — artery sprays, ragdolls and stomp kills should
  land as slapstick.
- **Look.** Grimy and dirty, through an old-school PS1 lens: low-poly models,
  low-res textures, dithering (PS1Dither autoload), low internal render scale.
  Grime comes from texture and color (stains, trash, graffiti, sodium-orange
  streetlights, sickly greens, nicotine yellows), not from modern effects —
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
