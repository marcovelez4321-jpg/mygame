class_name Leech
extends RigidBody3D

## A fat leech (the PSX Creatures kit's tape_worm) guarding a barnacle clump
## (BarnacleCluster spawns them). It squirms -- the model mirror-flips across
## its width with a smooth tween, so it seems to writhe side to side -- and
## pulses. It crawls around its home within guard_radius; get within
## notice_range and it comes at you, and within leap_range it leaps at you
## like a rat does. If it reaches you it latches on: it hangs off your face
## biting every bite_interval, and your gun won't fire -- every fresh click
## tugs at it instead, and tugs_to_remove clicks inside tug_window seconds of
## each other rips it off and flings it away. Shoot it dead and it bursts in a
## small spray of blood, leaving a red splat on the floor.
## Rule 1 (co-op): the host runs it; a latch is the host telling that
## player's WeaponController (latch_leech()).

enum State { CRAWL, LEAP, LATCHED, DEAD }

@export_group("Guarding")
@export var guard_radius: float = 4.0
@export var crawl_speed: float = 0.9
## Comes at you within this; leaves you alone again past guard_radius x 2
## from home.
@export var notice_range: float = 7.0

@export_group("Leap")
@export var leap_range: float = 4.5
## Seconds in the air for a leap (shorter = flatter and faster).
@export var leap_time: float = 0.45
@export var leap_cooldown: float = 2.5
## Gets you if it passes this close to your chest mid-leap.
@export var latch_reach: float = 0.9

@export_group("Latched")
@export var bite_damage: float = 6.0
@export var bite_interval: float = 0.8
## Clicks to rip it off, each within tug_window seconds of the last (stop
## clicking and the count starts over).
@export var tugs_to_remove: int = 8
@export var tug_window: float = 0.6
## Where it hangs off you: up from your feet, and out in front of you.
@export var latch_height: float = 1.35
@export var latch_forward: float = 0.4

@export_group("Look")
## Mirror-flips per second while crawling (faster when latched).
@export var squirm_rate: float = 1.4
## How much it swells on each pulse (0.15 = 15%).
@export var pulse_amount: float = 0.15
@export var model_scale: float = 1.0
## Turns the model if its head points the wrong way (degrees).
@export var model_yaw: float = 0.0
## Laid over every mesh of the model (the kit's texture).
@export var skin_material: Material
@export var blood_color: Color = Color(0.5, 0.03, 0.03)
@export var death_gore: float = 1.2
@export var splat_size: float = 0.6
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent

var _state := State.CRAWL
var _home := Vector3.ZERO
var _has_home := false
var _victim: Node3D
var _leap_cooldown_left := 0.0
var _leap_time := 0.0
var _bite_left := 0.0
var _tugs := 0
var _tug_left := 0.0
var _wander_to := Vector3.ZERO
var _wander_left := 0.0
var _squirm: Tween
var _pulse: Tween

@onready var health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _flip: Node3D = $Visual/Flip
@onready var _swell: Node3D = $Visual/Flip/Swell


func _ready() -> void:
	add_to_group("leeches")
	lock_rotation = true
	health.died.connect(_on_died)
	health.damaged.connect(func(_amount: float, _attacker: int) -> void: HitFlash.flash(self))
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D) # you walk through them
	if skin_material:
		for mesh in _swell.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = skin_material
	_swell.scale = Vector3.ONE * model_scale
	_swell.rotation_degrees.y = model_yaw
	_start_squirm(squirm_rate)
	_leap_cooldown_left = randf() * leap_cooldown


## Writhing: the model mirror-flips across its width and back, smoothly
## (through flat), while it swells and shrinks on its own beat.
func _start_squirm(rate: float) -> void:
	if _squirm:
		_squirm.kill()
	_squirm = create_tween().set_loops()
	var half := 0.5 / maxf(rate, 0.01)
	_squirm.tween_property(_flip, "scale:x", -1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_squirm.tween_property(_flip, "scale:x", 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _pulse == null:
		var size := Vector3.ONE * model_scale
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_swell, "scale", size * Vector3(1.0 + pulse_amount, 1.0 + pulse_amount * 1.5, 1.0 - pulse_amount * 0.5), 0.35) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse.tween_property(_swell, "scale", size, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _state == State.DEAD:
		return
	_leap_cooldown_left = maxf(_leap_cooldown_left - delta, 0.0)
	match _state:
		State.CRAWL:
			_think_crawl(delta)
		State.LEAP:
			_think_leap(delta)
		State.LATCHED:
			_think_latched(delta)


func _think_crawl(delta: float) -> void:
	if not _on_ground():
		return # falling (dropped off a wall clump, or thrown): let it land
	if not _has_home:
		_has_home = true
		_home = global_position
		_wander_to = _home
	var target := _nearest_player()
	var goal := _wander_to
	if target:
		var offset := Factions.aim_point(target) - global_position
		var flat := Vector2(offset.x, offset.z).length()
		if flat <= leap_range and offset.y < 2.5 and _leap_cooldown_left <= 0.0 and _sees(target):
			_leap_at(target)
			return
		goal = target.global_position
	else:
		_wander_left -= delta
		if _wander_left <= 0.0 or Vector2(global_position.x - _wander_to.x, global_position.z - _wander_to.z).length() < 0.3:
			_wander_left = randf_range(2.0, 5.0)
			var away := Vector2.from_angle(randf() * TAU) * randf_range(0.0, guard_radius)
			_wander_to = _home + Vector3(away.x, 0.0, away.y)
	var to := goal - global_position
	to.y = 0.0
	var speed := crawl_speed * (1.6 if target else 1.0)
	var velocity := to.normalized() * speed if to.length() > 0.2 else Vector3.ZERO
	linear_velocity = Vector3(velocity.x, linear_velocity.y, velocity.z)
	if velocity.length_squared() > 0.01:
		_face(velocity, delta)


## A player worth going for: alive, visible to enemies, within notice_range
## of it, and not dragging it more than guard_radius x 2 from home.
func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := notice_range
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance and player.global_position.distance_to(_home) <= guard_radius * 2.0 + notice_range:
			best = player
			best_distance = distance
	return best


## A rat's leap: the launch velocity that lands it on your chest in leap_time.
func _leap_at(target: Node3D) -> void:
	var gap := Factions.aim_point(target) - global_position
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	linear_velocity = gap / leap_time + Vector3.UP * 0.5 * gravity * leap_time
	_face(gap, 1.0)
	_victim = target
	_leap_time = 0.0
	_leap_cooldown_left = leap_cooldown
	_state = State.LEAP
	_start_squirm(squirm_rate * 3.0)


func _think_leap(delta: float) -> void:
	_leap_time += delta
	if is_instance_valid(_victim) and Factions.is_alive_target(_victim) \
			and global_position.distance_to(Factions.aim_point(_victim)) <= latch_reach:
		_latch()
		return
	if _leap_time > 0.2 and _on_ground():
		_state = State.CRAWL # missed
		_start_squirm(squirm_rate)


## Got you: stuck to your face, biting, and your gun's jammed until you tug it
## off (WeaponController.latch_leech()).
func _latch() -> void:
	var weapons := _victim.get_node_or_null("WeaponController")
	if weapons == null or not weapons.has_method("latch_leech"):
		_state = State.CRAWL
		return
	_state = State.LATCHED
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_tugs = 0
	_bite_left = 0.0
	weapons.call("latch_leech", self)
	_start_squirm(squirm_rate * 2.5)


func _think_latched(delta: float) -> void:
	if not is_instance_valid(_victim) or not Factions.is_alive_target(_victim):
		_fall_off(Vector3.ZERO)
		return
	var forward := -_victim.global_basis.z
	global_position = _victim.global_position + Vector3.UP * latch_height + forward * latch_forward
	_visual.global_basis = Basis.looking_at(-forward, Vector3.UP) # facing you
	_tug_left -= delta
	if _tug_left <= 0.0:
		_tugs = 0 # too slow: it settles back in
	_bite_left -= delta
	if _bite_left <= 0.0:
		_bite_left = bite_interval
		var victim_health := _victim.get_node_or_null("Health") as Health
		if victim_health:
			victim_health.take_damage(bite_damage, Health.NO_ATTACKER)
		var world := get_tree().current_scene
		BloodFX.spawn_impact(world, global_position, -forward, BloodFX.BLOOD_COLOR, 0.8)
		SoundPlayer.play_3d(bite_sound, global_position, world)


## A click while it's on you (WeaponController): enough of them, fast enough,
## and it's ripped off.
func tug() -> void:
	if _state != State.LATCHED:
		return
	_tugs += 1
	_tug_left = tug_window
	_visual.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.06 # yanked
	create_tween().tween_property(_visual, "position", Vector3.ZERO, 0.1)
	if _tugs >= tugs_to_remove:
		var away := _victim.global_basis.z + Vector3.UP * 0.6 # flung out in front of you
		_fall_off(away.normalized() * 6.0)


func _fall_off(fling: Vector3) -> void:
	if is_instance_valid(_victim):
		var weapons := _victim.get_node_or_null("WeaponController")
		if weapons and weapons.has_method("unlatch_leech"):
			weapons.call("unlatch_leech", self)
	_victim = null
	freeze = false
	collision_layer = 1
	collision_mask = 1
	linear_velocity = fling
	_visual.rotation = Vector3.ZERO
	_leap_cooldown_left = leap_cooldown * 1.5
	_state = State.CRAWL
	_start_squirm(squirm_rate)


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	if _state == State.LATCHED:
		_fall_off(Vector3.ZERO)
	_state = State.DEAD
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, global_position + Vector3.UP * 0.1, Vector3.UP, blood_color, death_gore)
	# (Far enough down to find the floor even when it dies stuck to your face.)
	var floor_hit := _ray(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 3.0)
	if not floor_hit.is_empty():
		BloodFX.spawn_splatter(world, floor_hit.position, floor_hit.normal, splat_size, blood_color)
	SoundPlayer.play_3d(death_sound, global_position, world)
	queue_free()


func _face(direction: Vector3, delta: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	var target := Basis.looking_at(flat.normalized(), Vector3.UP)
	_visual.global_basis = _visual.global_basis.slerp(target, clampf(delta * 8.0, 0.0, 1.0)).orthonormalized()


func _sees(target: Node3D) -> bool:
	var hit := _ray(global_position + Vector3.UP * 0.2, Factions.aim_point(target))
	return hit.is_empty() or hit.collider == target


func _on_ground() -> bool:
	return not _ray(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.2).is_empty()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query)
