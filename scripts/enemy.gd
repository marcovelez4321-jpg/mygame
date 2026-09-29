class_name Enemy
extends CharacterBody3D

## A basic melee enemy, built the classic Quake/Doom way: a state machine,
## meaning the enemy is always in exactly one state and each state decides
## what it does and when to switch.
##
##   IDLE   - waits until it can see a player
##   CHASE  - walks straight toward the nearest living player
##   ATTACK - close enough: hits the player on a cooldown
##   PAIN   - brief stagger after being hit
##   DEAD   - stops, disappears after a moment
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

enum State { IDLE, CHASE, LUNGE, ATTACK, PAIN, DEAD }

## Emitted whenever the state changes. Animation (and later, sound) listens
## to this. In co-op the host will send its state to the other player, whose
## copy of this enemy emits the same signal, so both screens animate alike
## without ever sending animation data itself.
signal state_changed(new_state: State)

## Emitted at the START of each swing (the wind-up), not when damage lands.
## The animator plays the attack clip on this. In co-op the host sends it to
## the other player so both screens show the swing together.
signal attack_started

@export_group("Movement")
@export var move_speed: float = 4.0
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

@export_group("Reactions")
@export var pain_time: float = 0.25
## Seconds the body stays after death before it's removed.
@export var corpse_time: float = 3.0

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

@export_group("Approach Prediction")
## Leads a moving target instead of walking straight at their literal current
## position -- the "smarter" read L4D-style chase AI is known for. This is a
## general, well-established game-AI technique (target leading / intercept
## prediction), built from scratch here -- not anything decompiled or
## referenced from an actual L4D build, which isn't something I have access
## to. Seconds of lead time; 0 disables it entirely (chases the real position).
@export var prediction_time: float = 0.4
## Caps how far ahead the prediction can reach. A player dashing, wall-
## jumping, or getting launched off a stomp kill shouldn't send the enemy
## charging at a point way off in empty space -- it just clamps back toward
## their actual position instead.
@export var prediction_max_offset: float = 4.0

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
		state_changed.emit(value)
var _target: Node3D
var _retarget_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _pain_timer: float = 0.0
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

## Target memory (every enemy type) -- see memory_time's own comment.
var _last_seen_position: Vector3 = Vector3.ZERO
var _time_since_seen: float = 0.0
var _has_seen_target: bool = false


func _ready() -> void:
	add_to_group("enemies")
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	# Only the host thinks. Offline, multiplayer.is_server() is true.
	if not multiplayer.is_server() or _state == State.DEAD:
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_lunge_cooldown_left = maxf(_lunge_cooldown_left - delta, 0.0)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_update_memory(_find_nearest_player())

	match _state:
		State.IDLE:
			_think_idle()
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


func _think_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _target and _can_see(_target):
		_state = State.CHASE


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
		if can_see_now and shoot_distance <= attack_range and shoot_distance >= shoot_min_range:
			_state = State.ATTACK
			return
		# Backing off just negates the approach direction rather than pathing
		# a real retreat route -- a crude but fine approximation for a short
		# "get some distance" step, not true flee-pathfinding.
		# Leads a currently-visible target instead of walking straight at
		# their literal position (see prediction_time's own comment) -- no
		# velocity to lead with once they're only a last-seen memory spot.
		var nav_target: Vector3 = _predicted_position(_target) if can_see_now else aim_pos
		var shoot_dir := _nav_direction_to(nav_target)
		if can_see_now and shoot_distance < shoot_min_range:
			shoot_dir = -shoot_dir
		velocity.x = shoot_dir.x * move_speed
		velocity.z = shoot_dir.z * move_speed
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
		# defeat the point of the telegraph. It DOES still lead the target
		# (set again, with prediction, right as the burst actually commits).
		_lunge_direction = _flat_direction_to_position(aim_pos)
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Leads a currently-visible target instead of walking straight at their
	# literal position (see prediction_time's own comment) -- no velocity to
	# lead with once they're only a last-seen memory spot.
	var nav_target: Vector3 = _predicted_position(_target) if can_see_now else aim_pos
	var direction := _nav_direction_to(nav_target)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed


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
			# them the instant it falls back to CHASE afterward. Leads their
			# CURRENT velocity too -- an intercept dash toward where they're
			# headed, not just their position at this exact instant.
			if _target:
				_lunge_direction = _flat_direction_to_position(_predicted_position(_target))
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
		if distance > attack_range or distance < shoot_min_range or not _can_see(_target):
			_state = State.CHASE
			return
	# Target stepped away: go back to chasing (with some slack so it doesn't
	# flicker between the two states right at the edge of attack range).
	elif distance > attack_range * 1.3:
		_state = State.CHASE
		return

	if _attack_cooldown > 0.0:
		return

	if can_shoot:
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


## Hitscan shot at the target, fired the moment the windup completes --
## same idea as the player's own gun (weapon_controller.gd's resolve_shot()),
## a single ray with no spread. A miss if something (the target ducking
## behind cover, another body) stepped into the way between windup and now.
func _fire_shot() -> void:
	if _target == null:
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.5
	var to := _target.global_position + Vector3.UP * 1.0
	var direction := (to - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world + players; ignore ragdoll corpses (layer 4)
	var result := space.intersect_ray(query)
	if result.is_empty() or result.collider != _target:
		return
	var target_health := result.collider.get_node_or_null("Health") as Health
	if target_health:
		target_health.take_damage(attack_damage, Health.NO_ATTACKER, direction, result.position, shoot_impact_force)
	BloodFX.spawn_impact(get_tree().current_scene, result.position, -direction)


func _think_pain(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_pain_timer -= delta
	if _pain_timer <= 0.0:
		_state = State.CHASE


func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state == State.DEAD:
		return
	HitFlash.flash(self)
	# Getting shot wakes it up and makes it flinch.
	_update_memory(_find_nearest_player())
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
	if _can_see(_target):
		_last_seen_position = _target.global_position
		_time_since_seen = 0.0
		_has_seen_target = true
		return
	_time_since_seen += retarget_interval
	if _has_seen_target and _time_since_seen >= memory_time:
		_target = null
		_has_seen_target = false


func _on_died(_attacker_id: int) -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	# Turn off collision so shots and players pass through the body.
	$CollisionShape3D.set_deferred("disabled", true)
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


## Read-only access to the current state, for the animator.
func get_state() -> State:
	return _state


## Nearest living player, or null. In co-op this is "nearest of two".
func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var player_health := player.get_node_or_null("Health") as Health
		if player_health == null or player_health.is_dead:
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = player
	return nearest


## Clear line of sight within range? A ray from our eyes to the player's
## chest; if a wall is hit first, we can't see them.
func _can_see(target: Node3D) -> bool:
	if global_position.distance_to(target.global_position) > sight_range:
		return false
	var from := global_position + Vector3.UP * 1.5
	var to := target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # ignore ragdoll corpses (layer 4)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target


## Where `target` will likely be shortly, based on its CURRENT velocity --
## not its true current position. Real players are CharacterBody3D with a
## real velocity to read; anything else (or a target with prediction_time at
## 0) just returns its actual position, unled.
func _predicted_position(target: Node3D) -> Vector3:
	var body := target as CharacterBody3D
	if body == null or prediction_time <= 0.0:
		return target.global_position
	var offset: Vector3 = body.velocity * prediction_time
	offset.y = 0.0
	offset = offset.limit_length(prediction_max_offset)
	return target.global_position + offset


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
	_nav_agent.target_position = destination
	var next_point := _nav_agent.get_next_path_position()
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
	return offset.normalized()


func _flat_distance_to_position(pos: Vector3) -> float:
	var offset := pos - global_position
	offset.y = 0.0
	return offset.length()


func _face_position(pos: Vector3) -> void:
	var flat_target := Vector3(pos.x, global_position.y, pos.z)
	if flat_target.distance_to(global_position) > 0.01:
		look_at(flat_target, Vector3.UP)
