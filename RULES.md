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
