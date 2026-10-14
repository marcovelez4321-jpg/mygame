class_name PlayerGrapple
extends Node3D

## The tentacle grapple (right mouse, or E). Only with a one-handed gun out
## (WeaponData.one_handed): the right hand keeps the gun, the left throws the
## tentacle. With anything else out, it switches to the last one-handed gun.
##
## Charge it, then it pulls you (docs/CLIMB_VISION.md):
##   CHARGE: hold right mouse; the ring shows where it'll bite. It only fires
##   once held at least min_charge_share of charge_time (no spamming), and
##   costs one bar of the player's stamina -- the same bars dashes use.
##   Let go right as it fills (good_window): a tiny extra boost, and a sound.
##   PULL (the user's: back to the original, Titanfall 2 style -- the straight
##   launch didn't feel natural): once it bites it hauls you toward the spot,
##   building up to pull_speed, no gravity; you can still steer, and you keep
##   your speed when you let go. Press right mouse again in the last moments
##   before you arrive (perfect_window): let go at speed with another tiny
##   boost and a second sound, flying on past.
##   PERCH: arriving (or pressed against something on the way, getting no
##   closer), you stick to the wall there.
##   RAPPEL (back, S) lets line out and down -- you hang on it under the spot
##   and can sway; REEL (forward, W) climbs back up it to the spot.
##   Space lets go (with a hop). One grapple at a time: a new one only once
##   this one's let go.
##   While it holds you (pulling, perched, hanging, riding) your stamina
##   drains (drain_per_second: a bar every 4 s); empty, it lets go and you fall.
## Big enemies (BIG_GROUP: the Harvestman, the worm) pull you to them: kick them
## on arrival and bounce off, or press again during the flight to latch on
## and ride them until you jump. Small enemies are a miss.
##
## References: HL2 and Titanfall 2's grapples (straight at the point, keep
## your momentum), Spider-Man's web-zip, Opposing Force's barnacle grapple
## (an organic one).
##
## Rule 1 (co-op): tick() and apply_pull() run inside the player's simulation
## step from the input packet (PlayerInput.grapple), so the host runs them for
## every player; the kick's damage happens there too. Only _process() draws:
## your own grapple as the tentacle in your chosen style (GrappleTentacle,
## GameSettings.tentacle_style), everyone else's as a plain line. The timing
## sounds are your own (local).

signal fired(power: float)
signal attached(to_enemy: bool)
signal missed
signal kicked(damage: float)
signal released
## The timing rewards: let go right as it filled; let go perfectly mid-flight.
signal charge_timed
signal launch_timed

## Anything in this group (on the node itself or any parent of the part hit)
## is a big enemy you zip to. Small enemies are a miss.
const BIG_GROUP := "grapple_big"

enum Rope { NONE, LASH, PULL, PERCH, HANG, RIDE, MISS }

@export_group("Charge")
## Seconds of holding for a full-power grapple.
@export var charge_time: float = 1.5
## It only fires once held at least this share of charge_time (the user's:
## half -- no spamming); let go sooner and nothing happens, nothing's spent.
@export_range(0.0, 1.0, 0.05) var min_charge_share: float = 0.5
## Let go within this many seconds of it filling: the charge reward.
@export var good_window: float = 0.15
## How much faster the pull is for it.
@export var charge_boost: float = 1.16

@export_group("Lash")
## Reach at full power, in meters (half at the least charge).
@export var max_range: float = 45.0
## How fast the tentacle flies out, m/s (the pull starts when it bites).
@export var lash_speed: float = 150.0
## How long a miss takes to whip out and snap back.
@export var miss_time: float = 0.45

@export_group("Pull")
## Pull speed at full power, m/s; at the least charge, this share of it.
@export var pull_speed: float = 17.0
@export_range(0.0, 1.0, 0.05) var min_speed_scale: float = 0.6
## How hard it pulls you up to that speed, m/s per second.
@export var pull_accel: float = 60.0
## Slows the pull near the spot so you settle onto it (speed is capped at
## distance x this).
@export var arrive_slowdown: float = 1.0
## The last seconds before arriving in which a press lets go perfectly, and
## how much faster you fly on for it.
@export var perfect_window: float = 0.3
@export var perfect_boost: float = 1.16
## How close to the spot counts as arriving.
@export var arrive_distance: float = 4.0

@export_group("Hold")
## Stamina bars drained a second while it holds you (0.25: one every 4 s).
@export var drain_per_second: float = 0.25
## How far off the wall you perch, and the line's speeds.
@export var perch_standoff: float = 1.0
@export var reel_speed: float = 3.0
@export var rappel_speed: float = 4.5
## Upward speed added when you let go with Space.
@export var release_hop: float = 2.5

@export_group("Big Enemies")
## How close (to the grabbed spot) counts as arriving: kick or latch on.
@export var kick_reach: float = 3.5
## Kick damage per m/s you were going when you hit (15.6 m/s x 4 = 62).
@export var kick_damage_per_speed: float = 4.0
## How hard you bounce back off after a kick, and up.
@export var kick_bounce: float = 13.5
@export var kick_bounce_up: float = 8.0
## How far off the enemy's surface you hang while riding.
@export var ride_standoff: float = 1.0

@export_group("Sound")
## The timing rewards' sounds (empty: a generated chime).
@export var charge_timed_sound: AudioStream
@export var launch_timed_sound: AudioStream

@export_group("Look")
## Where your grapple comes from on screen (camera space), until the new arms
## give it a real left hand.
@export var view_origin: Vector3 = Vector3(-0.32, -0.3, -0.45)
## Where other players see it come from (their body space: the left shoulder).
@export var body_origin: Vector3 = Vector3(-0.3, 1.35, 0.0)
## The plain line other players see.
@export var line_color: Color = Color(0.08, 0.02, 0.03)
@export var line_width: float = 0.04

## Testing: the grapple costs and drains no stamina (the pause menu's
## "Infinite Grapples" switch, like Infinite Ammo).
var infinite_charges: bool = true
## 0..1 how coiled the tentacle is right now (the arm animation reads this).
var coil: float = 0.0

var _player: PlayerMovement
var _rope := Rope.NONE
var _held_prev := false
var _coiling := false
var _hold := 0.0
var _power := 0.0
## This pull got the charge reward (and so goes charge_boost faster).
var _charge_bonus := false
var _pull_speed := 0.0
## How long the pull has made no headway against something (perch there).
var _stalled := 0.0
var _last_distance := INF
## The line's length while hanging.
var _rope_length := 0.0
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
## This tick's move input (x = strafe, y = back(+)/forward(-)): reel/rappel.
var _move := Vector2.ZERO

var _line: MeshInstance3D
var _tentacle: GrappleTentacle
## Your own view: the landing ring while you hold the grapple.
var _indicator: GrappleIndicator
var _chime: AudioStreamPlayer
## Co-op, someone else's grapple on a client: where its tip is, from the host
## (INF: not out). Their grapple isn't run here, just drawn.
var _remote_tip := Vector3.INF
## Your first-person arms (set by the Viewmodel): the tentacle coils round
## the left forearm and lashes out of that palm.
var arms: FirstPersonArms


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	charge_timed.connect(_chime_play.bind(true))
	launch_timed.connect(_chime_play.bind(false))


## Called by PlayerMovement every simulation tick, before gravity and the
## move. `held` = right mouse (or E), `jump_pressed` = a fresh Space, `move`
## = this tick's move input. Returns true if Space was used up letting go
## (so it isn't also a wall jump).
func tick(held: bool, jump_pressed: bool, delta: float, origin: Vector3, aim: Vector3, attacker_id: int, move: Vector2 = Vector2.ZERO) -> bool:
	_attacker_id = attacker_id
	_move = move
	var pressed := held and not _held_prev
	_held_prev = held

	var weapons := _player.weapons
	var gun := weapons.current_weapon()
	var hand_free := gun != null and gun.one_handed

	# Out of the one-handed gun (picked a two-handed one): the left hand's
	# needed on it, so the tentacle lets go.
	if not hand_free and not _coiling and is_pulling():
		release()

	if _rope == Rope.LASH or _rope == Rope.MISS:
		_lash_time += delta
		if _lash_time >= _lash_total:
			if _rope == Rope.LASH:
				_land()
			else:
				_rope = Rope.NONE

	if is_pulling() and not is_instance_valid(_anchor):
		release()

	if jump_pressed and is_pulling():
		_let_go()
		return true

	# Holding on costs stamina; out of it, you fall.
	if is_pulling() and not infinite_charges:
		# (A heavy pack drains it faster: Backpack.drain_scale().)
		if not _player.drain_stamina(drain_per_second * delta * _player.backpack.drain_scale()):
			release()
			return false

	# Pulled at a big enemy, a press means "ride it" (held till you arrive);
	# at a wall, a press in the last moments means let go at speed.
	if _rope == Rope.LASH or _rope == Rope.PULL:
		if _to_enemy:
			if pressed:
				_ride_wanted = true
			elif not held:
				_ride_wanted = false
		elif pressed and _rope == Rope.PULL and _time_to_arrive() <= perfect_window:
			_perfect_release()
		return false

	if _coiling:
		if not hand_free:
			_coiling = false # switched to a two-handed gun mid-coil
		elif held:
			_hold += delta
		else:
			_coiling = false
			if _hold >= charge_time * min_charge_share:
				_charge_bonus = _hold >= charge_time and _hold <= charge_time + good_window
				_fire(origin, aim)
	elif pressed and _rope == Rope.NONE and not weapons.is_busy() and (infinite_charges or _player.stamina >= 1.0):
		if hand_free or weapons.switch_to_one_handed():
			_coiling = true
			_hold = 0.0

	coil = clampf(_hold / charge_time, 0.0, 1.0) if _coiling else 0.0
	return false


## Holding it, winding it up.
func is_coiling() -> bool:
	return _coiling


## The tentacle is out (flying, stuck, or snapping back from a miss).
func is_out() -> bool:
	return _rope != Rope.NONE


## True while the line is holding you (gravity and ground movement change).
func is_pulling() -> bool:
	return _rope == Rope.PULL or _rope == Rope.PERCH or _rope == Rope.HANG or _rope == Rope.RIDE


## True while it moves you entirely itself (perched, riding): no steering in
## the air then. Pulled, or hanging on the line, you can still steer and sway.
func holds_still() -> bool:
	return _rope == Rope.PERCH or _rope == Rope.RIDE


## No gravity while it pulls or holds you; hanging on the line, full.
func gravity_scale() -> float:
	return 0.0 if holds_still() or _rope == Rope.PULL else 1.0


## Called by PlayerMovement just before move_and_slide().
func apply_pull(delta: float) -> void:
	match _rope:
		Rope.RIDE:
			_ride(delta)
		Rope.PULL:
			_pull(delta)
		Rope.PERCH:
			_perch(delta)
		Rope.HANG:
			_hang(delta)


## Lets go without a hop (death, mantling, switching guns, out of stamina).
func release() -> void:
	if is_pulling():
		released.emit()
	_rope = Rope.NONE
	_coiling = false
	_anchor = null
	_ride_wanted = false


func _fire(origin: Vector3, aim: Vector3) -> void:
	if not infinite_charges and not _player.spend_stamina():
		_hold = 0.0
		return # out of stamina: nothing to throw it with
	_power = clampf(_hold / charge_time, min_charge_share, 1.0)
	_hold = 0.0
	release()
	if _charge_bonus:
		charge_timed.emit()
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


## It bit: the pull starts.
func _land() -> void:
	if not is_instance_valid(_anchor):
		_rope = Rope.NONE
		return
	var power_t := inverse_lerp(min_charge_share, 1.0, _power) if min_charge_share < 1.0 else 1.0
	_pull_speed = pull_speed * lerpf(min_speed_scale, 1.0, clampf(power_t, 0.0, 1.0))
	if _charge_bonus:
		_pull_speed *= charge_boost
	_rope = Rope.PULL
	_stalled = 0.0
	_last_distance = INF
	attached.emit(_to_enemy)


## The pull (the original, Titanfall 2 style): you're hauled toward the spot
## (it follows a moving one), building up to the pull speed and easing off
## as you get there; your own steering adds to it. Arriving -- or pressed
## against something on the way and getting no closer -- you perch; at a big
## enemy, you kick it or latch on.
func _pull(delta: float) -> void:
	var to := _to_spot()
	var distance := to.length()
	var reach := kick_reach if _to_enemy else arrive_distance
	if distance <= reach:
		if _to_enemy:
			if _ride_wanted:
				_start_ride()
			else:
				_kick(to / maxf(distance, 0.001))
		else:
			_start_perch()
		return
	# Up against a ledge or a beam, no closer: perch where you are.
	var blocked := _player.get_slide_collision_count() > 0 and distance > _last_distance - 0.5 * delta
	_stalled = _stalled + delta if blocked else 0.0
	_last_distance = distance
	if _stalled > 0.3 and not _to_enemy:
		_start_perch()
		return
	var direction := to / distance
	# A heavy pack: pulled slower, and building up slower (Backpack.pull_scale()).
	var heavy := _player.backpack.pull_scale()
	var speed := minf(_pull_speed * heavy, distance * arrive_slowdown)
	var along := _player.velocity.dot(direction)
	if along < speed:
		_player.velocity += direction * minf(pull_accel * heavy * delta, speed - along)


## Seconds left till you arrive (INF if not pulled).
func _time_to_arrive() -> float:
	if _rope != Rope.PULL or _pull_speed <= 0.0:
		return INF
	var to := _to_spot()
	var closing := maxf(_player.velocity.dot(to.normalized()), _pull_speed * 0.5)
	return maxf(to.length() - arrive_distance, 0.0) / closing


## Let go at just the right moment in the flight: on past it, faster.
func _perfect_release() -> void:
	release()
	_player.velocity *= perfect_boost
	launch_timed.emit()


func _start_perch() -> void:
	_rope = Rope.PERCH
	_player.velocity = Vector3.ZERO


## Stuck to the wall at the spot. Back (S) lets the line out: hanging under it.
func _perch(delta: float) -> void:
	var normal := (_anchor.global_basis * _normal_local).normalized()
	var spot := _anchor_point() + normal * perch_standoff - Vector3.UP * 0.9
	_player.velocity = ((spot - _player.global_position) / maxf(delta, 0.001)).limit_length(20.0)
	if _move.y > 0.1:
		_rope = Rope.HANG
		_rope_length = maxf(_to_spot().length(), arrive_distance)


## On the line under the spot: gravity and a little sway, but never further
## than the line's length. Back (S) rappels down, forward (W) reels up --
## all the way up, and you're perched again.
func _hang(delta: float) -> void:
	if _move.y > 0.1:
		_rope_length = minf(_rope_length + rappel_speed * delta, max_range)
	elif _move.y < -0.1:
		_rope_length -= reel_speed * delta
		if _rope_length <= arrive_distance:
			_start_perch()
			return
	var point := _anchor_point()
	var chest := _player.global_position + Vector3.UP * 0.9
	var next := chest + _player.velocity * delta
	var out := next - point
	var stretch := out.length() - _rope_length
	if stretch > 0.0:
		# Taut: no more moving outward, and pulled back in to the line's length.
		var along := out / out.length()
		var outward := _player.velocity.dot(along)
		if outward > 0.0:
			_player.velocity -= along * outward
		_player.velocity -= along * (stretch / maxf(delta, 0.001)) * 0.5


## From the chest to the spot it's stuck to.
func _to_spot() -> Vector3:
	return _anchor_point() - (_player.global_position + Vector3.UP * 0.9)


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


# --- Sound (your own: the timing rewards) ---

func _chime_play(for_charge: bool) -> void:
	if not _player.is_multiplayer_authority():
		return
	if _chime == null:
		_chime = AudioStreamPlayer.new()
		_chime.bus = &"Player" if AudioServer.get_bus_index(&"Player") != -1 else &"Master"
		add_child(_chime)
	var custom := charge_timed_sound if for_charge else launch_timed_sound
	_chime.stream = custom if custom else _make_chime(880.0 if for_charge else 1320.0, 0.14 if for_charge else 0.2)
	_chime.play()


## A short bright chime, rising a fifth (placeholder until the user's sounds).
static func _make_chime(pitch: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for i in frames:
		var t := float(i) / frames
		phase += TAU * pitch * lerpf(1.0, 1.5, minf(t * 3.0, 1.0)) / rate
		var envelope := minf(t * 40.0, 1.0) * pow(1.0 - t, 2.0)
		var sample := (sin(phase) * 0.7 + sin(phase * 2.0) * 0.2) * envelope * 0.6
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


# --- Drawing (per peer, never touches the simulation) ---

## Your own view: while you hold the grapple, the ring (GrappleIndicator) on
## whatever it would grab at the reach this charge gives -- the same ray it
## fires -- filling like a dial; red where it'd give out if there's nothing.
func _update_indicator(delta: float) -> void:
	var camera := _player.camera
	if not _coiling or camera == null or not camera.current:
		if _indicator:
			_indicator.hide_ring()
		return
	if _indicator == null:
		_indicator = GrappleIndicator.new()
		add_child(_indicator)
	var origin := camera.global_position
	var aim := -camera.global_basis.z
	var power := clampf(_hold / charge_time, min_charge_share, 1.0)
	var reach := max_range * power
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach)
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var fill := clampf(_hold / charge_time, 0.0, 1.0)
	if hit.is_empty():
		_indicator.show_at(origin + aim * reach, Vector3.UP, false, fill, origin, delta)
		return
	var target := hit.collider as Node3D
	var grabs := target != null and (_big_enemy(target) != null or not _is_small_enemy(target))
	_indicator.show_at(hit.position, hit.normal, grabs, fill, origin, delta)


## Where the tentacle's tip is right now, or INF while it isn't out (the host
## sends this with each player's update).
func rope_tip() -> Vector3:
	match _rope:
		Rope.LASH:
			return _start_point().lerp(_lash_end, clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0))
		Rope.MISS:
			var t := clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0)
			return _start_point().lerp(_lash_end, sin(t * PI)) # out and snaps back
		Rope.PULL, Rope.PERCH, Rope.HANG, Rope.RIDE:
			if is_instance_valid(_anchor):
				return _anchor_point()
	return Vector3.INF


## Co-op: someone else's grapple, drawn from the host's word (INF: not out).
func show_remote(tip: Vector3) -> void:
	_remote_tip = tip


func _process(delta: float) -> void:
	var tip := rope_tip()
	if not tip.is_finite() and _rope == Rope.NONE:
		tip = _remote_tip
	var showing := tip.is_finite()
	if not showing:
		tip = Vector3.ZERO
	var mine := _player.is_multiplayer_authority()
	if mine:
		_ensure_tentacle()
		var normal := (_anchor.global_basis * _normal_local).normalized() if is_instance_valid(_anchor) else Vector3.UP
		var stuck := is_pulling()
		var arm_points: Array[Vector3] = []
		var arm_coil := 0.0
		if is_instance_valid(arms) and arms.raise > 0.01:
			arm_points = arms.left_arm_points()
			arm_coil = arms.coil
		_tentacle.show_rope(showing, _start_point(), tip, normal, stuck, arm_points, arm_coil, delta)
		_update_indicator(delta)
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
