class_name FlyingRoach
extends RigidBody3D

## A flying roach that fights like Half-Life 2's manhack (npc_manhack.cpp in
## Valve's Source SDK 2013): a real physics body with gravity off that
## steers itself with capped acceleration and a bit of random wobble, dives
## at you in short bursts, bounces off whatever it hits, and lines up again.
## A swarm takes turns: only max_divers dive at once while the rest circle,
## like the manhack's squad "attack slots".
##
##   HUNT     - flying toward the target (straight if it can see them,
##              otherwise following the level's ground navigation map from
##              above, so it finds you around corners and through doors)
##   CIRCLE   - orbiting the target, waiting for a dive slot
##   DIVE     - a committed burst straight at the target
##   RECOVER  - knocked back after a dive, drifting before lining up again
##   STUNNED  - engine stalled: thrown, or held with F; falls and tumbles
##   DEAD     - drops out of the air, bursts into goo
##
## Touching the player always bites (any state but stunned or dead), like a
## manhack slicing whatever its blades touch -- a roach brushing past you
## and doing nothing read as a bug.
##
## Being a RigidBody3D is the point: shots shove it, it bounces off walls,
## and PhysicsGrabber can pick it up like the gravity gun.
##
## Rule 1 (co-op): only the host runs the AI and the forces; a client will
## just smooth between the host's positions. Wings, buzz and goo are
## presentation (RoachVisual) computed on each machine from the synced
## velocity, so a whole swarm costs very little to send.

## SPIT is the spitter's attack (see the Spitter group): it hangs back,
## rears up, and lobs a glob of acid on an arc instead of diving.
enum State { HUNT, CIRCLE, DIVE, RECOVER, STUNNED, DEAD, SPIT }
## Random rolls spitter_chance when it spawns; mappers can force either.
enum Kind { RANDOM, NORMAL, SPITTER }

signal state_changed(new_state: State)
## A bite connected. Presentation hook (bite sound), like Enemy.attack_started.
signal bit_player
## Decided normal or spitter (a frame after spawning) -- RoachVisual builds
## the matching look on this.
signal kind_decided(spitter: bool)
## A glob just left its mouth -- RoachVisual jolts it forward.
signal spat
## Dead and just hit the ground -- RoachVisual squashes it flat and plays
## the splat.
signal splatted

## Everyone mid-dive, so the swarm can count how many are diving.
const DIVING_GROUP := "roach_diving"
const CHEST_HEIGHT := 1.0
## The player's body, as a vertical line from just above the feet to the
## top of the head (their capsule is 1.8 m tall), for "is it touching them".
const BODY_LOW := 0.3
const BODY_HIGH := 1.6
## A dead roach counts as landed once the floor is this close below its
## centre: its own radius (about 0.25) plus a little.
const SPLAT_HEIGHT := 0.35

@export_group("Flight")
## Cruising speed in m/s (HL2's manhack tops out around 5 m/s; ours is a
## touch faster to keep up with this game's movement).
@export var cruise_speed: float = 6.0
## How quickly it can change velocity, in m/s per second. Lower = floatier,
## swings wider; higher = darts.
@export var acceleration: float = 14.0
## Keeps at least this far off the floor while cruising (HL2: about 1.3 m).
@export var hover_height: float = 1.3
## Random drift (m/s) layered on top, so it never flies a perfect line.
@export var wobble: float = 1.5
## How far ahead it looks for walls to steer around (m).
@export var avoid_distance: float = 1.2

@export_group("Senses")
@export var sight_range: float = 25.0
## Seconds between "who's nearest?" checks.
@export var retarget_interval: float = 0.5

@export_group("Attack")
## Starts a dive from this close (m) -- HL2: about 5 m.
@export var dive_range: float = 5.0
## How directly it must be facing you to start a dive (1 = dead on).
@export var dive_aim: float = 0.75
@export var dive_speed: float = 13.0
## Longest a dive lasts before it gives up and pulls out (HL2: 1 s).
@export var dive_time: float = 1.0
## Seconds after a dive before it can dive again (HL2: 2 s).
@export var dive_cooldown: float = 2.0
@export var damage: float = 10.0
## How close (m) its centre gets to the player's body when it's touching
## them: the player is 0.4 m wide and the roach about 0.25 m, so contact is
## about 0.65 -- a little extra so a graze still counts.
@export var bite_reach: float = 0.75
## The shortest gap between two bites, so one touch can't bite twice.
@export var bite_gap: float = 0.3
## How hard it's thrown back after a bite (m/s).
@export var bounce_speed: float = 9.0
## Seconds it drifts after bouncing off before it flies again.
@export var recover_time: float = 0.6
## Most roaches allowed to dive at once; the rest circle and wait.
@export var max_divers: int = 2
## How far from you the waiting roaches circle (m).
@export var circle_radius: float = 3.5
## Circling speed, in turns per second around you.
@export var circle_turn_rate: float = 0.12

@export_group("Spitter")
## Random, Normal or Spitter -- set per placement in TrenchBroom (the
## monster_roach "kind" choice); Random rolls spitter_chance.
@export var kind: Kind = Kind.RANDOM
## Chance (0-1) a Random roach turns out to be a spitter.
@export_range(0.0, 1.0, 0.05) var spitter_chance: float = 0.2
## Spits when you're between these distances (m) and it can see you.
@export var spit_min_range: float = 6.0
@export var spit_max_range: float = 14.0
## Hangs back about this far from you, and backs off if you get closer
## than back_off_distance -- it never dives.
@export var keep_distance: float = 9.0
@export var back_off_distance: float = 5.0
## Seconds between spits.
@export var spit_cooldown: float = 2.5
## How long it rears back before spitting -- the tell.
@export var spit_windup: float = 0.25
## Horizontal speed of a glob (m/s). Slower = a higher, loopier arc that's
## easier to dodge. Flight time is kept between the two limits below.
@export var spit_speed: float = 10.0
@export var spit_flight_time_min: float = 0.6
@export var spit_flight_time_max: float = 1.6
## How hard the glob falls (m/s²) -- higher = a more pronounced arc.
@export var spit_gravity: float = 12.0
## 0 = aims where you are, 1 = aims fully where you'll be when it lands
## (from your current speed). Changing direction always dodges it.
@export_range(0.0, 1.0, 0.05) var spit_prediction: float = 0.8
## How much of spit_prediction applies to you moving TOWARD or AWAY from it
## (sideways movement always gets all of it). People running at an enemy
## usually stop or swerve, so leading that fully lobbed globs short, between
## you and the roach. 0 = ignore toward/away movement, 1 = lead it fully.
@export_range(0.0, 1.0, 0.05) var spit_prediction_toward: float = 0.3
## Aims this far (m) PAST you along its line of fire. Aiming to arrive
## exactly at your chest meant anything slightly off dropped short in front
## of you; a little extra reach carries a near-miss into your body.
@export var spit_aim_past: float = 0.4
## Each spit guesses differently where you're going, so a group of spitters
## covers several possible paths instead of all hitting the same spot: it
## uses a random share of the full lead (between these two) ...
@export var spit_guess_min: float = 0.4
@export var spit_guess_max: float = 1.3
## ... plus a random sideways guess of up to this many meters, across your
## direction of travel (only when you're moving).
@export var spit_guess_sideways: float = 1.2
## Small random miss (m) around the final aim point.
@export var spit_scatter: float = 0.25
@export var spit_damage: float = 12.0
@export var spit_color: Color = Color(0.6, 0.85, 0.1)

@export_group("Physics")
## How much harder than normal bullets shove it -- every gun's
## impact_force times this (weapon_controller.gd reads it). 2 = twice as hard.
@export var shot_push_multiplier: float = 2.0
## How long the engine stays stalled after being thrown (HL2: 2 s).
@export var stun_time: float = 2.0
## Turn rate of its facing, in radians per second.
@export var turn_speed: float = 8.0

@export_group("Death")
## Seconds the body stays after it dies.
@export var corpse_time: float = 8.0
## What it bleeds -- weapon_controller.gd's hit spray reads this too, so any
## enemy can bleed its own colour.
@export var blood_color: Color = Color(0.42, 0.5, 0.08)
## Size (m) of the goo spot it leaves where it lands.
@export var splat_size: float = 0.7

var _state: State = State.HUNT:
	set(value):
		if value == _state:
			return
		_state = value
		state_changed.emit(value)
## Which way it's pointing -- RoachVisual turns the model to match.
var facing: Vector3 = Vector3.FORWARD
## Spits acid instead of diving (decided in _decide_kind()).
var is_spitter := false
## Dead and already splatted on the ground.
var _splatted := false

var _target: Node3D
var _retarget_timer := 0.0
var _state_time := 0.0
var _dive_cooldown_left := 0.0
var _bite_gap_left := 0.0
var _dive_direction := Vector3.ZERO
var _held := false
var _circle_angle := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0

@onready var health: Health = $Health
@onready var _nav_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D") as NavigationAgent3D


func get_state() -> State:
	return _state


func _ready() -> void:
	add_to_group("enemies")
	add_to_group(Factions.GROUPS[Factions.Side.ROACH])
	gravity_scale = 0.0
	lock_rotation = true # the model shows tumbling; the body stays upright
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_noise.seed = randi()
	_noise.frequency = 0.6
	_circle_angle = randf() * TAU
	_retarget_timer = randf() * retarget_interval # spread a swarm's checks out
	BloodFX.warm_splat_texture(blood_color) # no hitch on its first death
	# Deferred: when a map is built while the game runs, func_godot sets a
	# mapper's "kind" choice only after this node is added.
	_decide_kind.call_deferred()


## Normal or spitter: the mapper's choice, or a spitter_chance roll.
## Rule 1: rolled by the host; in co-op the result goes with the spawn.
func _decide_kind() -> void:
	match kind:
		Kind.SPITTER:
			is_spitter = true
		Kind.NORMAL:
			is_spitter = false
		_:
			is_spitter = randf() < spitter_chance
	if is_spitter:
		BloodFX.warm_splat_texture(spit_color)
	kind_decided.emit(is_spitter)


func _physics_process(delta: float) -> void:
	# Only the host thinks and pushes. Offline, multiplayer.is_server() is true.
	if not multiplayer.is_server():
		return
	if _state == State.DEAD:
		_think_dead()
		return
	_time += delta
	_state_time += delta
	_dive_cooldown_left = maxf(_dive_cooldown_left - delta, 0.0)
	_bite_gap_left = maxf(_bite_gap_left - delta, 0.0)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_target = Factions.nearest_hostile(get_tree(), Factions.Side.ROACH, global_position, sight_range, self)

	if _state == State.STUNNED:
		_think_stunned()
		return
	if _try_bite():
		return
	match _state:
		State.RECOVER:
			if _state_time >= recover_time:
				_set_state(State.HUNT)
			return # drifting: no steering
		State.DIVE:
			_think_dive(delta)
			return
		State.SPIT:
			_think_spit(delta)
			return

	if _target == null:
		_steer(_hover_correction(Vector3.ZERO), delta)
		return
	var chest := Factions.aim_point(_target)
	var can_see := _can_see(chest)
	var distance := global_position.distance_to(chest)
	_turn_toward(chest - global_position, delta)

	if is_spitter:
		_think_spitter(chest, distance, can_see, delta)
		return

	if _state == State.CIRCLE:
		if not can_see or distance > circle_radius + 3.0:
			_set_state(State.HUNT)
		elif _can_start_dive(chest, distance):
			_start_dive(chest)
			return
		_circle_angle += TAU * circle_turn_rate * delta
		var orbit := Vector3(cos(_circle_angle), 0.0, sin(_circle_angle)) * circle_radius
		var spot := _target.global_position + orbit + Vector3.UP * (hover_height + 0.6)
		_steer(_seek(spot, cruise_speed), delta)
		return

	# HUNT
	if can_see and distance <= circle_radius + 1.0:
		_set_state(State.CIRCLE)
		return
	if can_see and _can_start_dive(chest, distance):
		_start_dive(chest)
		return
	var goal := chest if can_see else _path_point(chest)
	_steer(_hover_correction(_seek(goal, cruise_speed)), delta)


## The spitter's whole fight: hang back about keep_distance from the target
## (a slow drift around them so it isn't a sitting duck), back off if they
## close in, and start a spit whenever it's ready and in range.
func _think_spitter(chest: Vector3, distance: float, can_see: bool, delta: float) -> void:
	if not can_see:
		_steer(_hover_correction(_seek(_path_point(chest), cruise_speed)), delta)
		return
	if _dive_cooldown_left <= 0.0 and distance >= spit_min_range and distance <= spit_max_range:
		_set_state(State.SPIT)
		return
	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	_circle_angle += TAU * circle_turn_rate * 0.5 * delta
	var drift := Vector3(cos(_circle_angle), 0.0, sin(_circle_angle)) * 2.0
	var hold := _target.global_position + away.normalized() * keep_distance + drift + Vector3.UP * (hover_height + 1.0)
	var speed := cruise_speed * (1.5 if distance < back_off_distance else 1.0)
	_steer(_hover_correction(_seek(hold, speed)), delta)


## Rears back for spit_windup (holding still, staring), then spits and goes
## back to hanging around until the next one.
func _think_spit(delta: float) -> void:
	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, acceleration * delta)
	if _target == null:
		_set_state(State.HUNT)
		return
	var chest := Factions.aim_point(_target)
	_turn_toward(chest - global_position, delta * 2.0)
	if _state_time < spit_windup:
		return
	_spit_at(_target)
	_dive_cooldown_left = spit_cooldown
	_set_state(State.HUNT)


## Lobs a glob at where the target will be when it lands, then works out the
## exact launch velocity for that arc (AcidSpit.lob_velocity()).
##
## The lead: the target's ground speed, split into sideways (fully led, times
## spit_prediction) and toward/away from the roach (only partly led, see
## spit_prediction_toward), carried forward for the flight time. The flight
## time itself depends on where it lands, so the two are refined together a
## few times (an "iterative intercept") -- using the time to where the target
## is NOW was what made globs land short when you ran at it.
func _spit_at(target: Node3D) -> void:
	var mouth := global_position + facing * 0.3
	var aim := Factions.aim_point(target)
	var to_target := Vector3(aim.x - mouth.x, 0.0, aim.z - mouth.z)
	var line := to_target.normalized() if to_target.length_squared() > 0.0001 else facing

	# This shot's own guess at your path (see spit_guess_*): a random share of
	# the lead, and a random sideways step across your direction of travel.
	var lead_velocity := Vector3.ZERO
	var sideways_guess := Vector3.ZERO
	var target_body := target as CharacterBody3D
	if target_body:
		var ground_velocity := Vector3(target_body.velocity.x, 0.0, target_body.velocity.z)
		var toward_away := line * ground_velocity.dot(line)
		var sideways := ground_velocity - toward_away
		var guess := randf_range(spit_guess_min, spit_guess_max)
		lead_velocity = (sideways + toward_away * spit_prediction_toward) * spit_prediction * guess
		if ground_velocity.length_squared() > 1.0:
			var across := ground_velocity.normalized().cross(Vector3.UP)
			sideways_guess = across * randf_range(-spit_guess_sideways, spit_guess_sideways)

	aim += line * spit_aim_past + sideways_guess
	var landing := aim
	var flight_time := spit_flight_time_min
	for _pass in 3:
		var flat := Vector2(landing.x - mouth.x, landing.z - mouth.z).length()
		flight_time = clampf(flat / spit_speed, spit_flight_time_min, spit_flight_time_max)
		landing = aim + lead_velocity * flight_time

	# Never aim almost on top of itself: keep the landing at least 2 m out
	# along the line to the target.
	var out := (landing - mouth).dot(line)
	if out < 2.0:
		landing += line * (2.0 - out)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * spit_scatter
	landing += scatter
	var velocity := AcidSpit.lob_velocity(mouth, landing, flight_time, spit_gravity)
	AcidSpit.launch(get_tree().current_scene, mouth, velocity, spit_gravity, spit_damage, spit_color, [get_rid()])
	spat.emit()


## Steers velocity toward `desired` (plus wobble and wall avoidance), never
## changing it faster than `acceleration` -- the manhack's capped thrust.
func _steer(desired: Vector3, delta: float) -> void:
	var drift := Vector3(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(_time, 50.0) * 0.5,
			_noise.get_noise_2d(_time, 100.0)) * wobble
	desired += drift + _avoidance(desired)
	linear_velocity = linear_velocity.move_toward(desired, acceleration * delta)


func _seek(point: Vector3, speed: float) -> Vector3:
	var offset := point - global_position
	if offset.length() < 0.3:
		return Vector3.ZERO
	return offset.normalized() * speed


## Lifts it when it sinks below hover_height off the floor (HL2's
## MaintainGroundHeight). Not used mid-dive, when it means to come down.
func _hover_correction(desired: Vector3) -> Vector3:
	var floor_hit := _ray(global_position, global_position + Vector3.DOWN * hover_height)
	if not floor_hit.is_empty():
		desired.y = maxf(desired.y, cruise_speed * 0.5)
	return desired


## A short feeler along the way it wants to go: if a wall's in the way,
## push away from it along the wall's normal.
func _avoidance(desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.01:
		return Vector3.ZERO
	var hit := _ray(global_position, global_position + desired.normalized() * avoid_distance)
	if hit.is_empty() or hit.collider is PlayerMovement:
		return Vector3.ZERO
	return (hit.normal as Vector3) * cruise_speed


## Out of sight: the next corner of the ground path toward the target,
## raised to hover height. Straight at them if there's no navigation map.
func _path_point(chest: Vector3) -> Vector3:
	if _nav_agent == null:
		return chest
	_nav_agent.target_position = _target.global_position
	return _nav_agent.get_next_path_position() + Vector3.UP * hover_height


func _can_start_dive(chest: Vector3, distance: float) -> bool:
	if _dive_cooldown_left > 0.0 or distance > dive_range:
		return false
	if facing.dot((chest - global_position).normalized()) < dive_aim:
		return false
	return get_tree().get_nodes_in_group(DIVING_GROUP).size() < max_divers


func _start_dive(chest: Vector3) -> void:
	_dive_direction = (chest - global_position).normalized()
	add_to_group(DIVING_GROUP)
	_set_state(State.DIVE)


## Committed: flies along the line it picked, re-aiming a little so a
## sidestep at the last moment still matters.
func _think_dive(delta: float) -> void:
	if _target == null or _state_time >= dive_time:
		_end_dive()
		return
	var chest := Factions.aim_point(_target)
	_dive_direction = _dive_direction.slerp((chest - global_position).normalized(), 2.0 * delta).normalized()
	facing = _dive_direction
	linear_velocity = linear_velocity.move_toward(_dive_direction * dive_speed, acceleration * 2.0 * delta)


## Bites whenever it's touching the target's body -- measured to the
## player's whole body (a line from the feet to the head), not one point on
## the chest, so any visible contact counts. True if it bit.
func _try_bite() -> bool:
	if _target == null or _bite_gap_left > 0.0:
		return false
	# Measured to the target's whole body, feet to head -- scaled down for a
	# rat or another roach.
	var feet := _target.global_position
	var tall := Factions.height_of(_target)
	var body_point := Vector3(feet.x, clampf(global_position.y, feet.y + minf(BODY_LOW, tall * 0.2), feet.y + minf(BODY_HIGH, tall * 0.9)), feet.z)
	var to_body := body_point - global_position
	if to_body.length() > bite_reach:
		return false
	_bite(_target, to_body.normalized() if to_body.length_squared() > 0.0001 else facing)
	return true


func _bite(player: Node3D, direction: Vector3) -> void:
	var player_health := player.get_node_or_null("Health") as Health
	if player_health:
		player_health.take_damage(damage, Health.NO_ATTACKER, direction, global_position, 1.0)
		Factions.provoke(player, self)
	bit_player.emit()
	_bite_gap_left = bite_gap
	# Thrown back and a little up and sideways, like the manhack's
	# ComputeSliceBounceVelocity, so a second roach doesn't hit the same line.
	var side := direction.cross(Vector3.UP).normalized() * randf_range(-0.5, 0.5)
	linear_velocity = (-direction + Vector3.UP * 0.4 + side).normalized() * bounce_speed
	_end_dive()


func _end_dive() -> void:
	remove_from_group(DIVING_GROUP)
	_dive_cooldown_left = dive_cooldown
	_set_state(State.RECOVER)


## Engine stalled: gravity takes over until stun_time runs out (or it's let
## go, if it's being held with F).
func _think_stunned() -> void:
	if _held or _state_time < stun_time:
		return
	gravity_scale = 0.0
	_set_state(State.HUNT)


## Stalls the engine for stun_time -- being thrown, or an explosion later.
func stun() -> void:
	if _state == State.DEAD:
		return
	remove_from_group(DIVING_GROUP)
	gravity_scale = 1.0
	_set_state(State.STUNNED)


## PhysicsGrabber calls this when F picks it up or lets it go -- the
## gravity gun: held, it's helpless; thrown, its engine stalls.
func set_held(held: bool) -> void:
	_held = held
	stun()


func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state == State.DIVE:
		_end_dive() # getting shot knocks it out of a dive


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	remove_from_group(DIVING_GROUP)
	remove_from_group("enemies")
	_set_state(State.DEAD)
	gravity_scale = 1.0
	# Layer 0: shots and players pass through the body, but it still lands
	# on the floor (mask 1) instead of falling through the world.
	collision_layer = 0
	collision_mask = 1
	BloodFX.spawn_impact(get_tree().current_scene, global_position, Vector3.UP, blood_color)
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


## Falling dead: the moment it reaches the ground it splats -- stops dead
## (no rolling around like a ball), leaves a goo spot where it landed, and
## tells RoachVisual to squash it flat and play the splat.
func _think_dead() -> void:
	if _splatted:
		return
	var floor_hit := _ray(global_position, global_position + Vector3.DOWN * SPLAT_HEIGHT)
	if floor_hit.is_empty():
		return
	_splatted = true
	freeze = true
	linear_velocity = Vector3.ZERO
	global_position = floor_hit.position + Vector3.UP * 0.03
	var world := get_tree().current_scene
	BloodFX.spawn_splatter(world, floor_hit.position, floor_hit.normal, splat_size, blood_color)
	BloodFX.spawn_impact(world, floor_hit.position, floor_hit.normal, blood_color)
	splatted.emit()


func _set_state(state: State) -> void:
	_state_time = 0.0
	_state = state


func _turn_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	facing = facing.slerp(direction.normalized(), clampf(turn_speed * delta, 0.0, 1.0)).normalized()


func _can_see(point: Vector3) -> bool:
	var hit := _ray(global_position, point)
	return hit.is_empty() or hit.collider == _target


## World-only ray (layer 1) that ignores this roach.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query)
