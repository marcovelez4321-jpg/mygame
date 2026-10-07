class_name Enemy
extends CharacterBody3D

## A basic melee enemy, built the classic Quake/Doom way: a state machine,
## meaning the enemy is always in exactly one state and each state decides
## what it does and when to switch.
##
##   IDLE      - waits until it can see a player
##   CHASE     - walks straight toward the nearest living player
##   ATTACK    - close enough: hits the player on a cooldown
##   PAIN      - brief stagger after being hit
##   DEAD      - stops, disappears after a moment
##   SPAWNING  - just been born from a mutation explosion; inert until
##               spawning_time elapses, then drops into IDLE like any other
##               enemy. See the Mutation export group below.
##
## Rule 1 (co-op): only the host runs the AI (offline you ARE the host, so
## nothing changes now). It picks its target from the list of players instead
## of assuming there is one, and it uses the shared Health component, so the
## player's gun hurts it with no extra code.
##
## Two opt-in behaviors turn this same script into different enemy TYPES
## (Rule 2/6: one state machine, tuned by data, instead of near-duplicate
## scripts) -- each lives in its own scene as an inherited variant of
## enemy.tscn with these flipped on and stats retuned:
##   can_lunge - CHASE bursts into a fast telegraphed dash once close enough
##               (the "rusher"). See _think_chase()/_think_lunge().
##   can_shoot - ATTACK fires a hitscan shot instead of a melee swing, and
##               CHASE backs away if the target gets inside shoot_min_range
##               instead of always closing in (the "gunner", HL2-Combine-
##               style keep-your-distance-and-shoot). See _land_hit()/_fire_shot().

## PATROL: walking with its gang (added last so the others keep their numbers).
enum State { IDLE, CHASE, LUNGE, ATTACK, PAIN, DEAD, SPAWNING, PATROL }

## Emitted whenever the state changes. Animation (and later, sound) listens
## to this. In co-op the host will send its state to the other player, whose
## copy of this enemy emits the same signal, so both screens animate alike
## without ever sending animation data itself.
signal state_changed(new_state: State)

## Emitted when a mutating corpse is shot enough to empty its
## mutation_health -- the transformation is called off. EnemyRagdoll stops
## the twitch on this.
signal mutation_stopped

## Emitted at the START of each swing (the wind-up), not when damage lands.
## The animator plays the attack clip on this. In co-op the host sends it to
## the other player so both screens show the swing together.
signal attack_started

## Emitted the instant a gunner's shot fires (end of the wind-up), hit or
## miss, with where the bullet ended up -- the gunshot sound and the visible
## bullet (EnemyWeapon) play on this. Presentation hook like the two above;
## in co-op the host sends it so every screen sees and hears the same shots.
signal shot_fired(end_point: Vector3)

@export_group("Movement")
@export var move_speed: float = 4.0
## How fast it turns to face where it's going or what it's fighting, degrees a
## second (0 = snaps instantly). Snapping straight round every tick is what
## made them shake on the spot with something darting around them -- a roach
## circling their head, two targets either side -- like HL2's NPCs it turns
## at a set yaw speed instead (CAI_BaseNPC::UpdateYaw / m_flYawSpeed).
@export var turn_speed: float = 540.0
## Close enough to where it's walking to stop: closer than this it stands
## still instead of twitching back and forth over the spot.
@export var arrive_distance: float = 0.4
@export var gravity: float = 20.0

@export_group("Senses")
## How far away it can notice a player (meters), if it has a clear line of sight.
@export var sight_range: float = 25.0
## Seconds between "who is nearest?" checks. Cheaper than every tick.
@export var retarget_interval: float = 0.5
## How long after losing sight of the target ANY enemy type keeps heading for
## where it last SAW them (instead of their true, unseen position -- no
## X-ray tracking through walls) before giving up and going back to IDLE.
## Source/HL2-style "last known position" memory.
@export var memory_time: float = 4.0

@export_group("Gang")
## Tweakers run in gangs (only tweakers -- the Rat Bender keeps his own AI).
## With nobody to fight, the ones within gang_radius of each other group up
## and patrol together: the one that's been around longest leads, picking a
## spot within patrol_radius of its home (where it spawned) every
## patrol_interval or so, and the rest walk with it in a loose spread
## (gang_spacing apart) at patrol_speed_scale of move_speed. Now and then
## (gather_chance per new spot) the leader heads for another gang within
## gather_range instead, and the two merge.
@export var gang_radius: float = 12.0
@export var patrol_radius: float = 15.0
@export var patrol_interval: float = 10.0
@export_range(0.1, 1.0, 0.05) var patrol_speed_scale: float = 0.45
@export var gang_spacing: float = 2.0
@export_range(0.0, 1.0, 0.05) var gather_chance: float = 0.25
@export var gather_range: float = 30.0
## They keep personal_space from each other, patrolling or fighting, instead
## of walking into each other (separation_strength = how hard, x move_speed).
@export var personal_space: float = 1.3
@export var separation_strength: float = 1.0
## They look out for each other: one spotting something tells the gang
## within alert_radius, and anything that hurts one of them gets the gang
## within alert_radius on it (Factions.provoke) -- rats biting one, a roach,
## you.
@export var alert_radius: float = 18.0
## Melee tweakers closing on a target fan out around it (flanking, up to
## flank_spread meters off the straight line) instead of queueing up.
@export var flank_spread: float = 3.0

@export_group("Attack")
@export var attack_range: float = 1.6
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
## Seconds between the swing starting and the hit landing. Tune this to the
## moment in the attack clip where the arm actually connects.
@export var attack_windup: float = 0.5
## Seconds after the hit lands before it can move or swing again. Windup plus
## recovery should be about the length of the attack clip, so the whole
## animation plays out.
@export var attack_recovery: float = 0.5
## A melee hit shoves the player back: horizontal push in m/s, plus a small
## hop so floor friction doesn't eat it instantly. A real shove, not a
## launch -- a few meters. 0 = no shove. (The gunner's shots don't shove.)
@export var melee_shove: float = 12.0
@export var melee_shove_up: float = 4.0

@export_group("Reactions")
@export var pain_time: float = 0.25
## Hurt by something that isn't a player (a rat's bite, a roach, another
## tweaker's stray shot), it only flinches once per this many seconds. Every
## bite used to flinch it and cancel its swing, so a swarm biting a few times
## a second kept it stunned until it died without ever hitting back. A
## player's hits still stagger it every time.
@export var creature_pain_cooldown: float = 1.5
## Seconds the body stays after death before it's removed.
@export var corpse_time: float = 120.0

@export_group("Lunge (rusher)")
## Turns on the dash-in burst below. Off by default -- the base enemy just
## walks in and swings.
@export var can_lunge: bool = false
## Trigger the lunge once the target is this close (meters) -- further out
## than attack_range so it reads as "closing the gap fast", not a melee move.
@export var lunge_trigger_range: float = 8.0
## Brief pause before the burst actually happens -- a dead-instant lunge
## would be unreadable/unfair; this is the tell that lets you actually react
## (dash/wall-jump away) if you're paying attention.
@export var lunge_telegraph_time: float = 0.3
@export var lunge_speed: float = 14.0
@export var lunge_duration: float = 0.5
## Seconds before another lunge can trigger, counted from the moment it ends
## (or gets interrupted by pain) -- keeps it from being a permanent speed boost.
@export var lunge_cooldown: float = 2.5

@export_group("Ranged Attack (gunner)")
## Turns ATTACK into a hitscan shot instead of a melee swing. Reuses
## attack_range/attack_damage/attack_interval/attack_windup/attack_recovery
## above for the shared timing -- this group only adds what's specific to
## shooting.
@export var can_shoot: bool = false
## Closer than this and a shooter backs away instead of standing still to
## shoot -- HL2 Combine-style "don't let the player get in your face".
@export var shoot_min_range: float = 5.0
## Fed into the target's ragdoll/knockback the same way a gunshot's
## impact_force is (see health.gd's take_damage()).
@export var shoot_impact_force: float = 6.0
## Shots fired quickly in a row before the longer attack_interval pause --
## HL2 Combine-style burst fire instead of one continuous stream. 1 = no
## burst, just attack_interval between every single shot.
@export var burst_shot_count: int = 3
## Seconds between shots WITHIN a burst -- much shorter than attack_interval,
## which instead governs the pause BETWEEN bursts.
@export var burst_shot_interval: float = 0.15
## Accuracy, the Half-Life 2 way (Source SDK 2013): NPCs don't aim worse,
## every bullet just leaves inside a random cone around where they aim (the
## weapon's spread times the NPC's proficiency -- weapon_smg1.cpp's
## GetProficiencyValues()). A fixed cone means misses grow with distance on
## their own: deadly up close, wild far away. Half-angle in degrees.
@export var shot_spread_degrees: float = 3.0
## HL2's "defocused" first shots (ai_basenpc.cpp: ai_spread_defocused_cone_
## multiplier 3.0, ai_spread_cone_focus_time 0.6): right after it gets a
## clear shot at you, the cone starts this many times wider and tightens to
## normal over shot_focus_time seconds -- the opening shots of a fight, or
## after you break line of sight, usually miss and warn you instead.
@export var shot_unfocused_multiplier: float = 3.0
@export var shot_focus_time: float = 0.6
## Its aim trails behind you by about this many seconds, so it fires at
## where you just WERE: standing still gets you hit, strafing, dashing and
## wall-jumping make it miss. Not from HL2 (Source NPCs aim at your current
## position) -- added for this game's fast movement. 0 = perfect tracking.
@export var aim_lag_time: float = 0.1

@export_group("Mutation")
## Dying to anything OTHER than a clean/critical kill (a headshot, see
## weapon_controller.gd -- artery and body kills both count as messy) rolls
## a chance to mutate instead of just dying -- Doom's
## Pain Elemental and Painkiller's exploding fatties are the reference point
## here (Rule 6): failing to finish something off cleanly makes it WORSE, not
## just delayed. The mutant is a fresh copy of this same enemy scene wearing
## the same model (see spawn_mutant()), so a mutated rusher is still a rusher,
## just red, tougher and faster -- no separate mutant scene to keep in sync.
@export var can_mutate: bool = true
## Chance (0..1) a non-critical kill mutates rather than just dying outright.
@export_range(0.0, 1.0, 0.05) var mutate_chance: float = 0.5
## What the mutant gets on top of being a copy of this enemy. Rule 3: these
## multiply this enemy's own numbers, so each type's mutant scales with it.
@export var mutant_tint: Color = Color(0.82464653, 0.0, 0.1482195, 1.0)
@export var mutant_health_multiplier: float = 2.0
## The double tap: once a corpse starts mutating it gets this fresh pool of
## health. Shoot it empty before the twitch ends and it never transforms --
## it just stays dead. Uses the normal hit zones, so a headshot or artery hit
## on the twitching body finishes it fastest.
@export var mutation_health: float = 15.0
@export var mutant_speed_multiplier: float = 1.2
## How long a freshly-spawned mutant sits inert (no AI, no movement) before
## joining the fight -- a hook for a spawn animation, not implemented yet
## (see enemy_animator.gd's spawn_animations, currently an empty stub list
## same as die_animations). 0 skips straight to IDLE.
@export var spawning_time: float = 0.6
## Multiplies every mesh's albedo color -- a cheap, permanent recolor that
## reads instantly as "not the same enemy", unlike hit_flash.gd's overlay
## trick (that one's a brief FLASH and would fight this for the same
## property). White (1,1,1,1) means "no tint, leave the model as imported".
@export var tint_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Set right before entering State.DEAD (see _on_died()) so EnemyRagdoll can
## read it the same tick, before it decides between a normal death reaction
## and the mutation twitch. Public: EnemyRagdoll reads it directly, the same
## way it already reads health/corpse_time.
var will_mutate: bool = false
## A player landed the killing blow (any attacker id -- players are peer ids,
## NPCs, roaches and rats hurt with Health.NO_ATTACKER; a player's grenade,
## rocket or the barrel they set off carries their id). Set with will_mutate.
## EnemyRagdoll reads it: only a player's kill gets the twitching, swelling
## mutation; anything else mutates quietly, flashing instead.
var killed_by_player: bool = false
## What's left of mutation_health while the corpse is mutating -- see
## damage_mutation(). Public so weapon_controller.gd can size an instant
## artery hit to exactly this.
var mutation_health_left: float = 0.0
var _spawning_time_left: float = 0.0
## The gang (_refresh_gang()): every living tweaker within gang_radius
## (untyped: any of them may be freed between refreshes), the patrol leader,
## and this one's place in the spread. Plus its home and where it's heading.
var _gang: Array = []
var _gang_leader = null
var _gang_index := 0
var _gang_timer := 0.0
var _home := Vector3.ZERO
var _patrol_to := Vector3.ZERO
var _patrol_timer := 0.0
## A gunner stepping aside because a gang mate is in its line of fire.
var _sidestep_time := 0.0
var _sidestep := Vector3.ZERO

@onready var health: Health = $Health
## Optional -- routes chase movement around walls/corners via the level's
## baked NavigationMesh (see map_level.gd's _bake_navigation()) instead of a
## straight line through them. get_node_or_null so a scene/test map with no
## MapLevel (no baked navmesh) doesn't crash, just falls back to straight-line
## movement -- see _nav_direction_to().
@onready var _nav_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

# A "setter": every time _state is assigned anywhere in this script, this
# runs, so the signal fires automatically without editing each assignment.
var _state: State = State.IDLE:
	set(value):
		if value == _state:
			return
		_state = value
		if value == State.ATTACK:
			_time_aiming = 0.0 # a fresh shot at the target: aim starts unfocused
		state_changed.emit(value)
var _target: Node3D
var _retarget_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _pain_timer: float = 0.0
var _creature_pain_left: float = 0.0
## Seconds since the current swing began. -1 means no swing in progress.
var _swing_time: float = -1.0
## True from the swing starting until its hit lands.
var _hit_pending: bool = false

## Lunge state (can_lunge only). _lunge_timer counts DOWN through both the
## telegraph and the burst itself; which one depends on _lunge_telegraphing.
var _lunge_timer: float = 0.0
var _lunge_telegraphing: bool = false
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_cooldown_left: float = 0.0

## Burst-fire progress (can_shoot only). Counts DOWN within a burst; 0 means
## "start a fresh burst next time we're off cooldown".
var _burst_shots_left: int = 0
## Seconds since this enemy last got a clear shot (entered ATTACK) -- drives
## the defocused-first-shots spread (shot_focus_time).
var _time_aiming: float = 0.0
## Where a gunner is actually aiming: chases the target's chest, aim_lag_time
## behind (see _track_aim()).
var _aim_point: Vector3 = Vector3.ZERO
var _has_aim_point: bool = false

## Target memory (every enemy type) -- see memory_time's own comment.
var _last_seen_position: Vector3 = Vector3.ZERO
var _time_since_seen: float = 0.0
var _has_seen_target: bool = false


func _ready() -> void:
	add_to_group("enemies")
	add_to_group(Factions.GROUPS[faction()])
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_apply_tint()
	_set_home.call_deferred() # once whoever spawned it has put it in place
	_gang_timer = randf() * 0.5 # spread the gang's checks out


func _set_home() -> void:
	_home = global_position
	_patrol_to = global_position


## Multiplies every MeshInstance3D's material albedo by tint_color. Duplicates
## each material first (StandardMaterial3D is a shared resource by default --
## editing it in place would tint every OTHER enemy using the same imported
## model too, not just this one).
func _apply_tint() -> void:
	if tint_color == Color(1.0, 1.0, 1.0, 1.0):
		return
	for mesh in _find_mesh_instances(self):
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i)
			if mat is StandardMaterial3D:
				var tinted := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				tinted.albedo_color *= tint_color
				mesh.set_surface_override_material(i, tinted)


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


## Starts a freshly-spawned mutant inert for spawning_time before it joins the
## fight -- called on the new mutant by spawn_mutant() (see EnemyRagdoll's
## _explode_and_spawn_mutant()), never by this enemy on itself.
func start_spawning() -> void:
	if spawning_time <= 0.0:
		return
	_state = State.SPAWNING
	_spawning_time_left = spawning_time


func _physics_process(delta: float) -> void:
	# Only the host thinks. Offline, multiplayer.is_server() is true.
	if not multiplayer.is_server() or _state == State.DEAD:
		return

	if _state == State.SPAWNING:
		_spawning_time_left -= delta
		if _spawning_time_left <= 0.0:
			_state = State.IDLE
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# A target freed since the last re-pick (eaten, corpse removed) is gone, not
	# "still there": drop it before anything below touches it.
	if not is_instance_valid(_target):
		_target = null
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_lunge_cooldown_left = maxf(_lunge_cooldown_left - delta, 0.0)
	_creature_pain_left = maxf(_creature_pain_left - delta, 0.0)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_update_memory(_find_nearest_hostile())
	_gang_timer -= delta
	if _gang_timer <= 0.0:
		_gang_timer = 0.5
		_refresh_gang()
	if can_shoot:
		_track_aim(delta)

	match _state:
		State.IDLE, State.PATROL:
			_think_idle(delta)
		State.CHASE:
			_think_chase()
		State.LUNGE:
			_think_lunge(delta)
		State.ATTACK:
			_think_attack()
		State.PAIN:
			_think_pain(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


func _think_idle(delta: float) -> void:
	if _target and (_can_see(_target) or _has_seen_target):
		_alert_gang(_target) # "over there!" -- the gang goes in together
		_state = State.CHASE
		return
	_think_gang_patrol(delta)


# ---- Gangs -------------------------------------------------------------------

## Every living tweaker within gang_radius, and of the idle ones (patrolling or
## standing around), which leads: the one that's been in the game longest
## (lowest instance id), so a merged gang settles on one leader without any of
## them having to agree on it. _gang_index is this one's place in the spread.
func _refresh_gang() -> void:
	_gang.clear()
	_gang_leader = self
	_gang_index = 0
	if faction() != Factions.Side.TWEAKER:
		return
	for node in get_tree().get_nodes_in_group(Factions.GROUPS[Factions.Side.TWEAKER]):
		var other := node as Enemy
		if other == null or other == self or other.get_state() == State.DEAD:
			continue
		if other.global_position.distance_to(global_position) > gang_radius:
			continue
		_gang.append(other)
		if not other.is_patrolling():
			continue
		if other.get_instance_id() < (_gang_leader as Object).get_instance_id():
			_gang_leader = other
		if other.get_instance_id() < get_instance_id():
			_gang_index += 1


## Standing around or walking with its gang, not fighting.
func is_patrolling() -> bool:
	return _state == State.IDLE or _state == State.PATROL


## Walk with the gang: the leader picks the spots, everyone else takes their
## own place around wherever it's headed (a sunflower spread, so nobody
## shares a spot) and keeps out of each other's way.
func _think_gang_patrol(delta: float) -> void:
	var leader = _gang_leader if is_instance_valid(_gang_leader) and _gang_leader.is_patrolling() else self
	if leader == self:
		_patrol_timer -= delta
		if _patrol_timer <= 0.0:
			_patrol_timer = randf_range(patrol_interval * 0.6, patrol_interval * 1.4)
			_pick_patrol_spot()
	var spread := Vector2.from_angle(_gang_index * 2.39996) * gang_spacing * sqrt(float(_gang_index))
	var spot: Vector3 = leader._patrol_to + Vector3(spread.x, 0.0, spread.y)
	var push := _separation()
	# (Slack: once standing, it only sets off again when its spot is clearly
	# further away, so it doesn't flicker between walking and standing.)
	if _flat_distance_to_position(spot) <= arrive_distance * (4.0 if _state == State.IDLE else 2.0):
		velocity.x = push.x
		velocity.z = push.z
		_state = State.IDLE
		return
	var walk := _nav_direction_to(spot) * move_speed * patrol_speed_scale + push
	velocity.x = walk.x
	velocity.z = walk.z
	_face_position(global_position + walk)
	_state = State.PATROL


## The leader's next spot: usually somewhere walkable within patrol_radius of
## home; now and then (gather_chance) the nearest other gang within
## gather_range, to join up with it.
func _pick_patrol_spot() -> void:
	var spot := _home
	var found := false
	if randf() < gather_chance:
		var nearest := gather_range
		for node in get_tree().get_nodes_in_group(Factions.GROUPS[Factions.Side.TWEAKER]):
			var other := node as Enemy
			if other == null or other == self or _gang.has(other) or not other.is_patrolling():
				continue
			var distance := other.global_position.distance_to(global_position)
			if distance < nearest:
				nearest = distance
				spot = other.global_position
				found = true
	if not found:
		var away := Vector2.from_angle(randf() * TAU) * randf_range(patrol_radius * 0.3, patrol_radius)
		spot = _home + Vector3(away.x, 0.0, away.y)
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		spot = NavigationServer3D.map_get_closest_point(map, spot) # somewhere it can walk
	_patrol_to = spot


## A push away from gang mates closer than personal_space, so they don't walk
## into each other (patrolling or fighting).
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in _gang:
		if not is_instance_valid(other):
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < personal_space and distance > 0.01:
			push += offset / distance * (1.0 - distance / personal_space)
	return push.limit_length(1.0) * move_speed * separation_strength


## Tells the gang within alert_radius about `target`: any of them standing
## around or patrolling come at it too, knowing where it is.
func _alert_gang(target: Node3D) -> void:
	for other in _tweakers_within(alert_radius):
		other.alert(target)


## Every other living tweaker within `radius` (only on events -- spotting
## something, getting hurt -- not every tick).
func _tweakers_within(radius: float) -> Array[Enemy]:
	var found: Array[Enemy] = []
	if faction() != Factions.Side.TWEAKER:
		return found
	for node in get_tree().get_nodes_in_group(Factions.GROUPS[Factions.Side.TWEAKER]):
		var other := node as Enemy
		if other and other != self and other.get_state() != State.DEAD \
				and other.global_position.distance_to(global_position) <= radius:
			found.append(other)
	return found


## A gang mate spotted `target` or got hurt by it: go for it, if not already
## busy fighting.
func alert(target: Node3D) -> void:
	if not is_instance_valid(target) or _state == State.DEAD or not is_patrolling():
		return
	_target = target
	_last_seen_position = target.global_position
	_time_since_seen = 0.0
	_has_seen_target = true
	_state = State.CHASE


## Hurt: whatever did it (Factions.provoke, recorded right after the damage --
## hence deferred) becomes the whole gang's problem -- they turn on it even
## mid-fight with something else (revenge priority), and the idle ones come.
func _protect_gang() -> void:
	var attacker = get_meta("provoked_by") if has_meta("provoked_by") else null
	if not Factions.provoked_by(self, attacker) or not attacker is Node3D:
		return
	for other in _tweakers_within(alert_radius):
		Factions.provoke(other, attacker)
		other.alert(attacker)


func _think_chase() -> void:
	if _target == null:
		_state = State.IDLE
		return

	if can_shoot:
		# Heads for the LAST SEEN position while out of sight, not the
		# target's true live position -- no tracking through walls. Only a
		# currently-visible target can actually be engaged or trigger the
		# back-off-if-too-close behavior below.
		var can_see_now := _can_see(_target)
		var aim_pos: Vector3 = _target.global_position if can_see_now else _last_seen_position
		_face_position(aim_pos)
		var shoot_distance := _flat_distance_to_position(aim_pos)

		# In range, close enough, AND still have a clear shot: go fire.
		# Too close: back off instead of closing in like a melee enemy would
		# -- a gunner keeps its distance (HL2 Combine-style), it doesn't
		# rush you.
		# (Slack on the near edge too, like melee's 1.3x below: it backs off
		# to shoot_min_range, then holds and fires until you're well inside
		# it, instead of stepping back and forth across that one line.)
		if can_see_now and shoot_distance <= attack_range and shoot_distance >= shoot_min_range * (0.8 if _state == State.ATTACK else 1.0):
			_state = State.ATTACK
			return
		# Backing off just negates the approach direction rather than pathing
		# a real retreat route -- a crude but fine approximation for a short
		# "get some distance" step, not true flee-pathfinding.
		var shoot_dir := _nav_direction_to(aim_pos)
		if can_see_now and shoot_distance < shoot_min_range:
			shoot_dir = -shoot_dir
		var push := _separation()
		velocity.x = shoot_dir.x * move_speed + push.x
		velocity.z = shoot_dir.z * move_speed + push.z
		return

	# Same last-seen-position pattern the gunner branch above uses: heads for
	# where it last SAW the target while out of sight, not their true live
	# position -- no X-ray tracking through walls for melee/rusher either.
	# Attacking or lunging still requires an ACTUAL current sighting -- you
	# can't swing at, or dash toward, someone through a wall just because you
	# remember roughly where they went.
	var can_see_now := _can_see(_target)
	var aim_pos: Vector3 = _target.global_position if can_see_now else _last_seen_position
	_face_position(aim_pos)
	var distance := _flat_distance_to_position(aim_pos)

	if can_see_now and distance <= attack_range:
		_state = State.ATTACK
		return

	if can_lunge and can_see_now and _lunge_cooldown_left <= 0.0 and distance <= lunge_trigger_range:
		_state = State.LUNGE
		_lunge_telegraphing = true
		_lunge_timer = lunge_telegraph_time
		# The lunge itself stays a straight committed line, not nav-routed --
		# see _think_lunge()'s own comment for why re-aiming mid-burst would
		# defeat the point of the telegraph. It's re-aimed once more right as
		# the burst actually commits.
		_lunge_direction = _flat_direction_to_position(aim_pos)
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# At the target (or its last-seen spot), routed around walls by the navmesh
	# -- no leading/prediction, by design: simple and readable. A gang closing
	# in fans out (each to its own side, by its place in the gang) so they
	# come at it from several angles instead of single file, and they keep
	# out of each other's way.
	var goal := aim_pos
	if distance > attack_range + 2.0 and _gang_index > 0:
		var side := _flat_direction_to_position(aim_pos).cross(Vector3.UP)
		var flank := 1.0 if _gang_index % 2 == 0 else -1.0
		goal += side * flank * minf(flank_spread, distance * 0.3)
	var direction := _nav_direction_to(goal)
	var push := _separation()
	velocity.x = direction.x * move_speed + push.x
	velocity.z = direction.z * move_speed + push.z


## Burst toward the target: a short telegraph (standing still -- the tell),
## then a fast dash covering lunge_duration seconds. Ends early into ATTACK
## if it reaches melee range mid-burst, otherwise falls back to CHASE once
## the burst runs out (which puts it on cooldown either way, see both exits).
func _think_lunge(delta: float) -> void:
	_lunge_timer -= delta

	if _lunge_telegraphing:
		velocity.x = 0.0
		velocity.z = 0.0
		if _lunge_timer <= 0.0:
			_lunge_telegraphing = false
			_lunge_timer = lunge_duration
			# Re-aim right as the burst actually commits, not back when the
			# telegraph merely started -- otherwise up to lunge_telegraph_time
			# seconds of the target moving goes unaccounted for and the burst
			# fires at where they USED to be, then visibly "snaps" back onto
			# them the instant it falls back to CHASE afterward.
			if _target:
				_lunge_direction = _flat_direction_to(_target)
		return

	velocity.x = _lunge_direction.x * lunge_speed
	velocity.z = _lunge_direction.z * lunge_speed

	if _target and _flat_distance_to(_target) <= attack_range:
		_lunge_cooldown_left = lunge_cooldown
		_state = State.ATTACK
		return
	if _lunge_timer <= 0.0:
		_lunge_cooldown_left = lunge_cooldown
		_state = State.CHASE


func _think_attack() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_time_aiming += get_physics_process_delta_time()

	# Committed to a swing/shot: it plays out completely, even if the target
	# steps away. The hit only lands if they're still in range (melee) or in
	# sight (ranged) at the moment of impact.
	if _swing_time >= 0.0:
		_run_swing(get_physics_process_delta_time())
		return

	if _target == null:
		_state = State.IDLE
		return
	_face(_target)
	var distance := _flat_distance_to(_target)

	if can_shoot:
		# Too close, too far, or lost the shot: back to CHASE, which backs a
		# gunner away if the target's the one that got too close.
		if distance > attack_range or distance < shoot_min_range * 0.8 or not _can_see(_target):
			_state = State.CHASE
			return
	# Target stepped away: go back to chasing (with some slack so it doesn't
	# flicker between the two states right at the edge of attack range).
	elif distance > attack_range * 1.3:
		_state = State.CHASE
		return

	if _sidestep_time > 0.0:
		_sidestep_time -= get_physics_process_delta_time()
		velocity.x = _sidestep.x * move_speed
		velocity.z = _sidestep.z * move_speed
		return
	if _attack_cooldown > 0.0:
		return

	if can_shoot:
		# A gang mate in the line of fire: hold it and step aside for a clear
		# shot, instead of shooting through them.
		if _mate_in_line():
			_sidestep = _flat_direction_to(_target).cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			_sidestep_time = 0.6
			return
		if _burst_shots_left <= 0:
			_burst_shots_left = burst_shot_count
		_burst_shots_left -= 1
		# Between shots in the SAME burst: a short gap (burst_shot_interval).
		# After the burst's last shot: the full attack_interval pause before
		# the next one -- HL2 Combine-style burst fire, not one steady stream.
		_attack_cooldown = burst_shot_interval if _burst_shots_left > 0 else attack_interval
	else:
		_attack_cooldown = attack_interval

	_swing_time = 0.0
	_hit_pending = true
	attack_started.emit()
	_run_swing(0.0)


## Advances the swing: the hit lands once the wind-up is over, and the swing
## ends after the recovery time.
func _run_swing(delta: float) -> void:
	_swing_time += delta
	if _hit_pending:
		if _target:
			_face(_target) # keeps aiming until the hit lands
		if _swing_time >= attack_windup:
			_hit_pending = false
			_land_hit()
	if _swing_time >= attack_windup + attack_recovery:
		_swing_time = -1.0


func _land_hit() -> void:
	if can_shoot:
		_fire_shot()
		return
	# The target may have moved out of reach during the wind-up: a miss.
	if _target == null or _flat_distance_to(_target) > attack_range * 1.3:
		return
	var target_health := _target.get_node_or_null("Health") as Health
	if target_health:
		target_health.take_damage(attack_damage, Health.NO_ATTACKER)
		Factions.provoke(_target, self)
	if _target.has_method("shove") and (melee_shove > 0.0 or melee_shove_up > 0.0):
		_target.call("shove", _flat_direction_to(_target) * melee_shove + Vector3.UP * melee_shove_up)


## Hitscan shot at the target, fired the moment the windup completes --
## same idea as the player's own gun (weapon_controller.gd's resolve_shot()):
## aimed at where it thinks the target's chest is (a beat behind, see
## aim_lag_time), then thrown off by the spread cone (see
## shot_spread_degrees). A miss carries on past them and leaves a bullet hole
## in whatever it hits -- the "they're shooting at me" warning.
func _fire_shot() -> void:
	if _target == null:
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.5
	var aim := (_aim_point - from).normalized()
	var direction := _spread_direction(aim, _current_spread_degrees())
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * sight_range)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world + players; ignore ragdoll corpses (layer 4)
	var result := space.intersect_ray(query)
	if result.is_empty():
		shot_fired.emit(from + direction * sight_range)
		return
	shot_fired.emit(result.position)
	var hit_health := (result.collider as Node).get_node_or_null("Health") as Health
	if hit_health == null:
		BloodFX.spawn_bullet_hole(get_tree().current_scene, result.position, result.normal)
		return
	if result.collider != _target and Factions.side_of(result.collider) == faction():
		return # a gang mate stepped in the way -- no friendly fire
	# Anything else it hits takes the shot (a rat or roach that got in the
	# way, or another target).
	hit_health.take_damage(attack_damage, Health.NO_ATTACKER, direction, result.position, shoot_impact_force)
	Factions.provoke(result.collider, self)
	BloodFX.spawn_impact(get_tree().current_scene, result.position, -direction)


## A gang mate between this gunner and where it's aiming.
func _mate_in_line() -> bool:
	var from := global_position + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, _aim_point if _has_aim_point else Factions.aim_point(_target))
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider != _target and Factions.side_of(hit.collider) == faction()


## Eases _aim_point toward the target's chest every tick. An exponential
## follow with a time constant of aim_lag_time trails a steadily moving
## target by exactly that long -- a reaction delay, with no position history
## to store. Snaps straight on when there's no aim point yet.
func _track_aim(delta: float) -> void:
	if _target == null:
		_has_aim_point = false
		return
	var chest := Factions.aim_point(_target)
	if not _has_aim_point or aim_lag_time <= 0.0:
		_aim_point = chest
		_has_aim_point = true
		return
	_aim_point = _aim_point.lerp(chest, 1.0 - exp(-delta / aim_lag_time))


## shot_spread_degrees, widened by shot_unfocused_multiplier right after it
## got its shot and eased back to normal over shot_focus_time (HL2 eases
## this with a spline; smoothstep is the same curve).
func _current_spread_degrees() -> float:
	var focus := 1.0
	if shot_focus_time > 0.0:
		focus = smoothstep(0.0, 1.0, _time_aiming / shot_focus_time)
	return shot_spread_degrees * lerpf(shot_unfocused_multiplier, 1.0, focus)


## A random direction inside a cone of `degrees` around `aim`. The distance
## from the middle is picked evenly (not by area), so shots cluster toward
## where it aimed and only some stray to the edge -- the same idea as HL2's
## shot bias (shot_manipulator.h's ApplySpread()), which blends a flat spread
## toward a centre-heavy one.
func _spread_direction(aim: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return aim
	var up := Vector3.UP if absf(aim.y) < 0.99 else Vector3.RIGHT
	var aim_basis := Basis.looking_at(aim, up) # -Z of this basis is `aim`
	var angle := randf() * TAU
	var radius := randf() * tan(deg_to_rad(degrees))
	return (aim_basis * Vector3(cos(angle) * radius, sin(angle) * radius, -1.0)).normalized()


func _think_pain(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_pain_timer -= delta
	if _pain_timer <= 0.0:
		_state = State.CHASE


func _on_damaged(_amount: float, attacker_id: int) -> void:
	if _state == State.DEAD:
		return
	HitFlash.flash(self)
	_protect_gang.call_deferred()
	# Getting shot wakes it up and makes it flinch.
	_update_memory(_find_nearest_hostile())
	if attacker_id == Health.NO_ATTACKER:
		if _creature_pain_left > 0.0:
			return # bitten again too soon to flinch: keep fighting
		_creature_pain_left = creature_pain_cooldown
	_pain_timer = pain_time
	_swing_time = -1.0 # getting shot interrupts a swing in progress
	_hit_pending = false
	_burst_shots_left = 0 # getting staggered breaks off a burst too
	_lunge_cooldown_left = lunge_cooldown # getting staggered also interrupts a lunge
	_state = State.PAIN


## Source/HL2-style target memory, shared by every enemy type: while we can
## actually see the chosen target, remember where they are. Once sight is
## lost, CHASE keeps heading for that LAST seen spot instead of their true
## (unseen) position -- see _think_chase() -- for up to memory_time, then
## this gives up (_target = null), which drops the enemy back to IDLE the
## same as if it had never spotted anyone.
func _update_memory(found: Node3D) -> void:
	if found == null:
		_target = null
		return
	_target = found
	# Seen -- or it just hurt us, so we know exactly where it is.
	if _can_see(_target) or Factions.provoked_by(self, _target):
		_last_seen_position = _target.global_position
		_time_since_seen = 0.0
		_has_seen_target = true
		return
	_time_since_seen += retarget_interval
	if _has_seen_target and _time_since_seen >= memory_time:
		_target = null
		_has_seen_target = false


func _on_died(attacker_id: int, is_critical: bool) -> void:
	# Rolled and stored BEFORE entering State.DEAD: the state setter emits
	# state_changed synchronously, which EnemyRagdoll is listening for to
	# kick off its own death reaction right then -- it needs will_mutate
	# already decided by the time that happens, not after.
	will_mutate = can_mutate and not scene_file_path.is_empty() and not is_critical and randf() < mutate_chance
	killed_by_player = attacker_id != Health.NO_ATTACKER
	mutation_health_left = mutation_health
	_state = State.DEAD
	velocity = Vector3.ZERO
	# Turn off collision so shots and players pass through the body.
	$CollisionShape3D.set_deferred("disabled", true)
	# A mutating corpse isn't removed on the usual timer -- EnemyRagdoll's
	# mutation sequence frees it itself once the explosion spawns the mutant
	# (see spawn_mutant() below), whenever that ends up being.
	if not will_mutate:
		get_tree().create_timer(corpse_time).timeout.connect(queue_free)


## A shot landing on this corpse while it's mutating (weapon_controller.gd's
## _hit_mutating_corpse()). Returns true if this shot emptied the pool and
## called the transformation off -- the corpse then goes the way of any
## normal kill and is removed after corpse_time.
func damage_mutation(amount: float) -> bool:
	if not will_mutate:
		return false
	mutation_health_left -= amount
	if mutation_health_left > 0.0:
		return false
	will_mutate = false
	mutation_stopped.emit()
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)
	return true


## Called by EnemyRagdoll once its twitch/enlarge/explode sequence finishes
## (see _explode_and_spawn_mutant()) -- replaces this corpse with the mutant
## at the explosion's center, facing the way this enemy was facing, then
## removes this corpse. Spawning stays here rather than in EnemyRagdoll
## because it's a real gameplay entity, not a cosmetic effect (Rule 1: will
## eventually need to be host-authoritative and replicated, same as any other
## enemy spawn).
##
## Everything is set BEFORE add_child: EnemyModel picks its model in
## _enter_tree() and Health fills up from max_health in _ready(), both of
## which run inside add_child. Handing over this enemy's model_seed makes the
## mutant roll the exact same model from the same variants list.
func spawn_mutant(at_position: Vector3) -> void:
	var mutant := (load(scene_file_path) as PackedScene).instantiate() as Enemy
	mutant.can_mutate = false
	mutant.tint_color = mutant_tint
	mutant.move_speed = move_speed * mutant_speed_multiplier
	var mutant_health := mutant.get_node("Health") as Health
	mutant_health.max_health = health.max_health * mutant_health_multiplier
	var model := get_node_or_null("Model") as EnemyModel
	var mutant_model := mutant.get_node_or_null("Model") as EnemyModel
	if model and mutant_model:
		mutant_model.model_seed = model.model_seed
	get_tree().current_scene.add_child(mutant)
	mutant.global_position = at_position
	mutant.global_rotation.y = global_rotation.y
	mutant.start_spawning()
	queue_free()


## Read-only access to the current state, for the animator.
func get_state() -> State:
	return _state


## Which side it fights for (Factions). Tweakers; the Rat Bender overrides.
func faction() -> int:
	return Factions.Side.TWEAKER


## The nearest living thing it's hostile to -- a player, or a roach or rat
## (Factions) -- or null. In co-op, players are just more candidates.
func _find_nearest_hostile() -> Node3D:
	return Factions.nearest_hostile(get_tree(), faction(), global_position, INF, self, _target)


## Clear line of sight within range? A ray from our eyes to the player's
## chest; if a wall is hit first, we can't see them.
func _can_see(target: Node3D) -> bool:
	if global_position.distance_to(target.global_position) > sight_range:
		return false
	var from := global_position + Vector3.UP * 1.5
	var to := Factions.aim_point(target)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # ignore ragdoll corpses (layer 4)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	# Only the level blocks sight. A rat, a roach or another tweaker in the
	# way used to count as a wall, so in a swarm they never "saw" what was
	# eating them and died without fighting back.
	return result.is_empty() or result.collider == target or not result.collider is StaticBody3D



## Direction to walk RIGHT NOW to make progress toward `destination`, routed
## around obstacles via the level's baked NavigationMesh (map_level.gd's
## _bake_navigation()) instead of a straight line through walls. Falls back
## to a direct line if there's no NavigationAgent3D on this enemy at all
## (e.g. a bare test scene with no MapLevel/baked navmesh) -- see _nav_agent's
## own comment. Only the WALK direction routes through this; distance/line-of
## -sight checks elsewhere still use the real straight-line position, which is
## what "am I close enough to attack" should mean, not path length.
func _nav_direction_to(destination: Vector3) -> Vector3:
	if _nav_agent == null:
		return _flat_direction_to_position(destination)
	# Already there: stand still. Past this point the path is "finished" and
	# its next point is our own feet, which pointed a full-speed walk in a
	# random direction every tick -- the shaking on the spot.
	if _flat_distance_to_position(destination) <= arrive_distance:
		return Vector3.ZERO
	if _nav_agent.target_position.distance_squared_to(destination) > 0.01:
		_nav_agent.target_position = destination
	if _nav_agent.is_navigation_finished():
		return _flat_direction_to_position(destination)
	var next_point := _nav_agent.get_next_path_position()
	# No walkable route there -- e.g. the player is down below a ledge with no
	# stairs: the path just ends at the brink. Walk straight at them instead
	# and drop off the edge (gravity does the rest), like Quake's monsters,
	# rather than standing stuck at the top.
	if not _nav_agent.is_target_reachable() or _flat_distance_to_position(next_point) < 0.05:
		return _flat_direction_to_position(destination)
	return _flat_direction_to_position(next_point)


## Position-based versions below, so a gunner's memory system (which tracks a
## bare Vector3 -- the last SEEN spot, not a live Node3D) can share the exact
## same math as chasing a real target. The Node3D-taking versions just
## forward to these.

func _flat_direction_to(target: Node3D) -> Vector3:
	return _flat_direction_to_position(target.global_position)


func _flat_distance_to(target: Node3D) -> float:
	return _flat_distance_to_position(target.global_position)


## Turn to face the target, staying upright. If the model ends up facing
## away from the player, rotate the Model node 180 degrees in the scene.
func _face(target: Node3D) -> void:
	_face_position(target.global_position)


func _flat_direction_to_position(pos: Vector3) -> Vector3:
	var offset := pos - global_position
	offset.y = 0.0
	# Right on top of it there's no real direction (a hair's offset normalizes
	# to a full step any which way): none, rather than a random one.
	if offset.length_squared() < 0.0025:
		return Vector3.ZERO
	return offset.normalized()


func _flat_distance_to_position(pos: Vector3) -> float:
	var offset := pos - global_position
	offset.y = 0.0
	return offset.length()


func _face_position(pos: Vector3) -> void:
	var offset := Vector3(pos.x - global_position.x, 0.0, pos.z - global_position.z)
	# A target right overhead or underfoot (a roach, a rat) has no real
	# direction -- turning toward it would spin it in place every tick.
	if offset.length() <= 0.3:
		return
	var yaw := atan2(-offset.x, -offset.z) # facing -Z, same as look_at()
	if turn_speed <= 0.0:
		global_rotation.y = yaw
	else:
		global_rotation.y = rotate_toward(global_rotation.y, yaw, deg_to_rad(turn_speed) * get_physics_process_delta_time())
