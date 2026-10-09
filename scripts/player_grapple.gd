class_name PlayerGrapple
extends Node3D

## The tentacle grapple (E). Only with a one-handed gun out (WeaponData.
## one_handed): the right hand keeps the gun, the left throws the tentacle.
## With anything else out, E switches to the last one-handed gun first.
##
## Hold E to coil it (charge_time for full power), let go to lash it out.
## Releasing early gives less range and a slower pull; under min_hold nothing
## fires. It grabs any world surface and pulls you toward it Titanfall 2 style
## (you can still steer, and keep your speed when you let go with Space).
## Big enemies (BIG_GROUP: the Harvestman, the worm) pull you to them; you
## kick them on arrival and bounce off, or, holding E again during the zip,
## latch on and ride them until you jump. Two charges, regrowing one at a
## time; a miss still spends one.
##
## References: Titanfall 2's grapple (pull, steer, keep momentum), Opposing
## Force's barnacle grapple (an organic one), Bulletstorm's leash (yank).
##
## Rule 1 (co-op): tick() and apply_pull() run inside the player's simulation
## step from the input packet (PlayerInput.grapple), so the host can run them
## for every player; the kick's damage happens there too. Only _process()
## draws: your own grapple as the tentacle in your chosen style
## (GrappleTentacle, GameSettings.tentacle_style), everyone else's as a plain
## line.

signal fired(power: float)
signal attached(to_enemy: bool)
signal missed
signal kicked(damage: float)
signal released

## Anything in this group (on the node itself or any parent of the part hit)
## is a big enemy you zip to. Small enemies are a miss.
const BIG_GROUP := "grapple_big"

enum Rope { NONE, LASH, PULL, RIDE, MISS }

@export_group("Charge")
## Seconds of holding E for a full-power grapple.
@export var charge_time: float = 1.5
## Let go sooner than this and nothing fires (a tap doesn't waste a charge).
@export var min_hold: float = 0.3
## Power when fired at exactly min_hold (0.2 = 20% range); full at charge_time.
@export var min_power: float = 0.2
@export var max_charges: int = 2
## Seconds for one spent charge to grow back (one at a time).
@export var recharge_time: float = 3.0

@export_group("Lash")
## Reach at full power, in meters.
@export var max_range: float = 35.0
## How fast the tentacle flies out, m/s (the pull starts when it lands).
@export var lash_speed: float = 120.0
## How long a miss takes to whip out and snap back.
@export var miss_time: float = 0.45

@export_group("Pull")
## Pull speed at full power, m/s.
@export var pull_speed: float = 15.6
## Pull speed at min_power, as a fraction of pull_speed. Set it to min_power
## (0.2) to scale the speed exactly like the range.
@export_range(0.0, 1.0, 0.05) var min_speed_scale: float = 0.6
## How hard it pulls you up to that speed, m/s per second.
@export var pull_accel: float = 42.0
## Gravity while pulled (0 = none, 1 = full).
@export_range(0.0, 1.0, 0.05) var pull_gravity_scale: float = 0.0
## Upward speed added when you let go with Space.
@export var release_hop: float = 3.0
## Slows the pull near the point so you settle against it instead of jittering
## (speed is capped at distance x this).
@export var arrive_slowdown: float = 5.0

@export_group("Big Enemies")
## How close (to the grabbed spot) counts as arriving: kick or latch on.
@export var kick_reach: float = 2.2
## Kick damage per m/s you were going when you hit (15.6 m/s x 4 = 62).
@export var kick_damage_per_speed: float = 4.0
## How hard you bounce back off after a kick, and up.
@export var kick_bounce: float = 9.0
@export var kick_bounce_up: float = 6.0
## How far off the enemy's surface you hang while riding.
@export var ride_standoff: float = 1.3

@export_group("Look")
## Where your grapple comes from on screen (camera space), until the new arms
## give it a real left hand.
@export var view_origin: Vector3 = Vector3(-0.32, -0.3, -0.45)
## Where other players see it come from (their body space: the left shoulder).
@export var body_origin: Vector3 = Vector3(-0.3, 1.35, 0.0)
## The plain line other players see.
@export var line_color: Color = Color(0.08, 0.02, 0.03)
@export var line_width: float = 0.04

## Charges ready now, and how far the next one has grown back (0..1), for the HUD.
var charges: int = 0
var recharge_fraction: float = 0.0
## 0..1 how coiled the tentacle is right now (the arm animation reads this).
var coil: float = 0.0

var _player: PlayerMovement
var _rope := Rope.NONE
var _held_prev := false
var _coiling := false
var _hold := 0.0
var _power := 0.0
var _regen := 0.0
## What it's stuck to, and where on it (in its own space, so a moving enemy
## or prop carries the spot along).
var _anchor: Node3D
var _anchor_local := Vector3.ZERO
var _normal_local := Vector3.UP
var _to_enemy := false
## The fly-out (LASH/MISS): seconds gone, seconds it takes, and where it ends.
var _lash_time := 0.0
var _lash_total := 0.0
var _lash_end := Vector3.ZERO
var _ride_wanted := false
var _ride_prev := Vector3.ZERO
var _ride_velocity := Vector3.ZERO
var _attacker_id := 0

var _line: MeshInstance3D
var _tentacle: GrappleTentacle
## Your first-person arms (set by the Viewmodel): the tentacle coils round
## the left forearm and lashes out of that palm.
var arms: FirstPersonArms


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	charges = max_charges


## Called by PlayerMovement every simulation tick, before gravity and the
## move. `held` = E, `jump_pressed` = a fresh Space. Returns true if Space
## was used up letting go (so it isn't also a wall jump).
func tick(held: bool, jump_pressed: bool, delta: float, origin: Vector3, aim: Vector3, attacker_id: int) -> bool:
	_attacker_id = attacker_id
	var pressed := held and not _held_prev
	_held_prev = held
	_regrow(delta)

	var weapons := _player.weapons
	var gun := weapons.current_weapon()
	var hand_free := gun != null and gun.one_handed

	# Out of the one-handed gun (picked a two-handed one): the left hand's
	# needed on it, so the tentacle lets go.
	if not hand_free and not _coiling and (_rope == Rope.PULL or _rope == Rope.RIDE):
		release()

	if _rope == Rope.LASH or _rope == Rope.MISS:
		_lash_time += delta
		if _lash_time >= _lash_total:
			if _rope == Rope.LASH:
				_land()
			else:
				_rope = Rope.NONE

	if (_rope == Rope.PULL or _rope == Rope.RIDE) and not is_instance_valid(_anchor):
		release()

	if jump_pressed and (_rope == Rope.PULL or _rope == Rope.RIDE):
		_let_go()
		return true

	# During a zip to a big enemy, E means "ride it", not a new grapple: a
	# fresh press after the lash, held until you arrive.
	if (_rope == Rope.LASH or _rope == Rope.PULL) and _to_enemy:
		if pressed:
			_ride_wanted = true
		elif not held:
			_ride_wanted = false
		return false

	if _coiling:
		if not hand_free:
			_coiling = false # switched to a two-handed gun mid-coil
		elif held:
			_hold += delta
		else:
			_coiling = false
			if _hold >= min_hold:
				_fire(origin, aim)
	elif pressed and _rope != Rope.RIDE and charges > 0 and not weapons.is_busy():
		if hand_free or weapons.switch_to_one_handed():
			_coiling = true
			_hold = 0.0

	coil = clampf(_hold / charge_time, 0.0, 1.0) if _coiling else 0.0
	return false


## Holding E, winding it up.
func is_coiling() -> bool:
	return _coiling


## The tentacle is out (flying, stuck, or snapping back from a miss).
func is_out() -> bool:
	return _rope != Rope.NONE


## True while the rope is holding you (gravity and ground movement change).
func is_pulling() -> bool:
	return _rope == Rope.PULL or _rope == Rope.RIDE


func gravity_scale() -> float:
	return pull_gravity_scale if is_pulling() else 1.0


## Called by PlayerMovement just before move_and_slide(): the pull itself.
func apply_pull(delta: float) -> void:
	if _rope == Rope.RIDE:
		_ride(delta)
		return
	if _rope != Rope.PULL:
		return
	var point := _anchor_point()
	var chest := _player.global_position + Vector3.UP * 0.9
	var to := point - chest
	var distance := to.length()
	if _to_enemy and distance <= kick_reach:
		if _ride_wanted:
			_start_ride()
		else:
			_kick(to / maxf(distance, 0.001))
		return
	if distance < 0.01:
		return
	var direction := to / distance
	var power_t := inverse_lerp(min_power, 1.0, _power) if min_power < 1.0 else 1.0
	var speed := pull_speed * lerpf(min_speed_scale, 1.0, clampf(power_t, 0.0, 1.0))
	speed = minf(speed, distance * arrive_slowdown)
	var along := _player.velocity.dot(direction)
	if along < speed:
		_player.velocity += direction * minf(pull_accel * delta, speed - along)


## Lets go without a hop (death, mantling, switching guns).
func release() -> void:
	if _rope == Rope.PULL or _rope == Rope.RIDE:
		released.emit()
	_rope = Rope.NONE
	_coiling = false
	_anchor = null
	_ride_wanted = false


func _regrow(delta: float) -> void:
	if charges >= max_charges:
		_regen = 0.0
		recharge_fraction = 0.0
		return
	_regen += delta
	if _regen >= recharge_time:
		_regen = 0.0
		charges += 1
	recharge_fraction = _regen / recharge_time


func _fire(origin: Vector3, aim: Vector3) -> void:
	charges -= 1
	_power = lerpf(min_power, 1.0, clampf(inverse_lerp(min_hold, charge_time, _hold), 0.0, 1.0))
	_hold = 0.0
	release()
	var reach := max_range * _power
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach)
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	fired.emit(_power)
	var target: Node3D = null
	if not hit.is_empty():
		target = hit.collider as Node3D
	var big := _big_enemy(target)
	if target == null or (big == null and _is_small_enemy(target)):
		_rope = Rope.MISS
		_lash_end = origin + aim * reach if target == null else (hit.position as Vector3)
		_lash_time = 0.0
		_lash_total = miss_time
		missed.emit()
		return
	_anchor = target
	_anchor_local = target.global_transform.affine_inverse() * (hit.position as Vector3)
	_normal_local = (target.global_basis.inverse() * (hit.normal as Vector3)).normalized()
	_to_enemy = big != null
	_lash_end = hit.position
	_lash_time = 0.0
	_lash_total = origin.distance_to(hit.position) / lash_speed
	_rope = Rope.LASH


func _land() -> void:
	if not is_instance_valid(_anchor):
		_rope = Rope.NONE
		return
	_rope = Rope.PULL
	attached.emit(_to_enemy)


func _let_go() -> void:
	var was_riding := _rope == Rope.RIDE
	release()
	if was_riding:
		_player.velocity = _ride_velocity
	_player.velocity.y = maxf(_player.velocity.y, 0.0) + release_hop


func _kick(direction: Vector3) -> void:
	var speed := _player.velocity.length()
	var damage := kick_damage_per_speed * speed
	var health := _anchor.get_node_or_null("Health") as Health
	if health:
		health.take_damage(damage, _attacker_id, direction, _anchor_point(), 6.0)
		_player.weapons.hit_confirmed.emit(health.is_dead, WeaponController.HitKind.NORMAL)
	Factions.provoke(_anchor, _player)
	kicked.emit(damage)
	release()
	_player.velocity = -direction * kick_bounce + Vector3.UP * kick_bounce_up


func _start_ride() -> void:
	_rope = Rope.RIDE
	_ride_prev = _anchor_point()
	_ride_velocity = Vector3.ZERO


## Hanging off the enemy: you're carried along with the grabbed spot.
func _ride(delta: float) -> void:
	var point := _anchor_point()
	_ride_velocity = (point - _ride_prev) / maxf(delta, 0.001)
	_ride_prev = point
	var normal := (_anchor.global_basis * _normal_local).normalized()
	var spot := point + normal * ride_standoff - Vector3.UP * 0.9
	_player.velocity = ((spot - _player.global_position) / maxf(delta, 0.001)).limit_length(60.0)


func _anchor_point() -> Vector3:
	return _anchor.global_transform * _anchor_local


## The big enemy `node` is part of (it or a parent is in BIG_GROUP), or null.
func _big_enemy(node: Node) -> Node:
	while node != null:
		if node.is_in_group(BIG_GROUP):
			return node
		node = node.get_parent()
	return null


func _is_small_enemy(node: Node) -> bool:
	while node != null:
		if node.is_in_group("enemies"):
			return true
		node = node.get_parent()
	return false


# --- Drawing (per peer, never touches the simulation) ---

func _process(delta: float) -> void:
	var showing := _rope != Rope.NONE
	var tip := Vector3.ZERO
	match _rope:
		Rope.LASH:
			tip = _start_point().lerp(_lash_end, clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0))
		Rope.MISS:
			var t := clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0)
			tip = _start_point().lerp(_lash_end, sin(t * PI)) # out and snaps back
		Rope.PULL, Rope.RIDE:
			if is_instance_valid(_anchor):
				tip = _anchor_point()
			else:
				showing = false
	var mine := _player.is_multiplayer_authority()
	if mine:
		_ensure_tentacle()
		var normal := (_anchor.global_basis * _normal_local).normalized() if is_instance_valid(_anchor) else Vector3.UP
		var stuck := _rope == Rope.PULL or _rope == Rope.RIDE
		var arm_points: Array[Vector3] = []
		var arm_coil := 0.0
		if is_instance_valid(arms) and arms.raise > 0.01:
			arm_points = arms.left_arm_points()
			arm_coil = arms.coil
		_tentacle.show_rope(showing, _start_point(), tip, normal, stuck, arm_points, arm_coil, delta)
		if _line:
			_line.visible = false
	else:
		_ensure_line()
		_line.visible = showing
		if showing:
			var start := _start_point()
			var length := start.distance_to(tip)
			if length > 0.01:
				var along := (tip - start) / length
				var up := Vector3.UP if absf(along.y) < 0.99 else Vector3.FORWARD
				var facing := Basis.looking_at(along, up) * Basis.from_scale(Vector3(1.0, 1.0, length))
				_line.global_transform = Transform3D(facing, (start + tip) * 0.5)


func _start_point() -> Vector3:
	if is_instance_valid(arms) and arms.raise > 0.01:
		var points := arms.left_arm_points()
		return points[2] + points[3] * 0.06 # out of the palm
	if _player.is_multiplayer_authority() and _player.camera.current:
		return _player.camera.global_transform * view_origin
	return _player.global_transform * body_origin


func _ensure_tentacle() -> void:
	if _tentacle == null:
		_tentacle = GrappleTentacle.new()
		add_child(_tentacle)


func _ensure_line() -> void:
	if _line:
		return
	_line = MeshInstance3D.new()
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(line_width, line_width, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = line_color
	box.material = material
	_line.mesh = box
	add_child(_line)
