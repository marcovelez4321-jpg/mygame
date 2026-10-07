class_name Spider
extends AnimatableBody3D

## One spider of a pack (SpiderPack). It crawls on ANY surface -- floor,
## walls, ceilings -- sticking to it with a few raycasts a tick (the classic
## "wall walker": a ray ahead finds a wall to climb onto, a ray down keeps it
## stuck, a ray back under the edge wraps it over a corner). Its pack says
## where it wants to go (desired_velocity); it bites what it reaches and
## leaps at its prey -- from the floor like a rat, or dropping off a wall or
## ceiling from much further away, which is how it likes to do it.
##
## Its eight legs are real inverse kinematics on the model's own leg bones
## (a FABRIK solve per leg -- Aristidou & Lasenby, "FABRIK: A fast,
## iterative solver for the Inverse Kinematics problem", 2011): each foot is
## planted on the surface and stays put until the body has moved too far
## from it, then steps -- in two alternating sets of four, the way real
## spiders walk (the "alternating tetrapod" gait). The body isn't bolted on
## top: it rides the legs on a spring -- it settles to the height and tilt of
## wherever the feet are, dips as legs lift, shifts its weight toward the
## feet on the ground, twists with each set of steps, lags behind when it
## speeds up and swings out on turns, and the abdomen swings after it.
##
## Rule 1 (co-op): only the host moves, bites and leaps; the legs and body
## motion are pure looks, worked out on every screen from where it is.

enum State { CRAWL, LEAP, FALL, DEAD }

## Leg bone prefixes in the model (each leg is <prefix>A..D, tip <prefix>D_end):
## front, two middles and back, left then right; F2 are the pedipalps.
const WALKING_LEGS := ["F1L", "M1L", "M2L", "BL", "F1R", "M1R", "M2R", "BR"]
const PALPS := ["F2L", "F2R"]
## The two sets of four that step together (alternating tetrapod gait).
const GAIT_GROUP := {"F1L": 0, "M1L": 1, "M2L": 0, "BL": 1, "F1R": 1, "M1R": 0, "M2R": 1, "BR": 0}
## A surface this steep or more counts as a wall (or ceiling), not a floor.
const WALL_DOT := 0.7

@export var model_scene: PackedScene = preload("res://NEWPSXMODELS/PSX Mega Pack/Models/Spider/Spider.fbx")
## Laid over every mesh of the model, if set.
@export var skin_material: Material

@export_group("Size")
## Tip-to-tip leg span of a size-1 spider, meters.
@export var leg_span: float = 1.6
## Every spider rolls its own size in this range: bigger is tougher (by
## size²) and a little slower.
@export var size_min: float = 0.8
@export var size_max: float = 1.25
## Each spider's own speed is up to this much faster or slower.
@export var speed_variation: float = 0.12

@export_group("Crawling")
## How fast it reaches the speed its pack wants, m/s².
@export var acceleration: float = 70.0
## How far (in leg spans) it feels for the surface under it before deciding
## it walked off an edge.
@export var stick_distance: float = 0.6

@export_group("Bite")
@export var bite_damage: float = 6.0
@export var bite_interval: float = 0.7
## How close (in meters, times its size) to the target's middle it bites from.
@export var bite_reach: float = 1.4

@export_group("Leap")
## On the floor, it leaps at prey this far away (like a rat)...
@export var leap_range_min: float = 1.5
@export var leap_range_max: float = 4.0
## ...and from a wall or ceiling, from up to this far.
@export var wall_leap_range: float = 7.0
## Chance per second it takes a leap it could make: on the floor, and from a
## wall or ceiling (it's up there to leap, so much more eager).
@export var leap_chance: float = 0.6
@export var wall_leap_chance: float = 1.8
@export var leap_cooldown: float = 2.5
@export var leap_damage: float = 12.0
## Flight time to the target (s): shorter = flatter and faster.
@export var leap_time: float = 0.4

@export_group("Walls")
## Chance each spider is one that goes for walls and ceilings first.
@export_range(0.0, 1.0, 0.05) var wall_preference: float = 0.75
## Up on a wall, it gives up if it hasn't got closer for this long while
## still out of leap range -- drops off and comes along the floor instead --
## and doesn't look for a wall again for wall_retry_time seconds.
@export var wall_give_up_time: float = 2.5
@export var wall_retry_time: float = 5.0

@export_group("Legs")
## A foot steps once the spot under its hip is this far from it (in leg spans).
@export var stride: float = 0.22
## Longest a step takes (s); it steps faster the faster it runs, down to
## step_time_min.
@export var step_time: float = 0.14
@export var step_time_min: float = 0.045
## How high a foot lifts mid-step (in leg spans).
@export var step_height: float = 0.1
## Feet reach this many seconds ahead of where the body's going.
@export var step_lead: float = 0.08
@export var ik_iterations: int = 3
## Furthest a hip (the first leg segment) swings forward or back from rest,
## radians.
@export var hip_swing_limit: float = 1.0
## Past this far from the camera the legs solve every other frame, and past
## ik_far_distance not at all (they hold their pose).
@export var ik_full_distance: float = 15.0
@export var ik_far_distance: float = 35.0

@export_group("Body Motion")
## How much the body follows the height and tilt of where its feet are (0 =
## not at all, 1 = fully).
@export_range(0.0, 1.0, 0.05) var body_follow: float = 0.75
## How far the body sinks (in leg spans) for every leg in the air.
@export var weight_dip: float = 0.012
## How much it shifts toward the feet that are on the ground.
@export_range(0.0, 1.0, 0.05) var weight_shift: float = 0.35
## How much it twists toward each set of steps (radians).
@export var gait_twist: float = 0.08
## How far it lags behind (and leans) as it speeds up, slows down and turns.
@export var inertia: float = 0.004
## The spring the body rides on: stiffer = snappier, more damping = less wobble.
@export var spring_stiffness: float = 180.0
@export var spring_damping: float = 15.0
## How fast it turns to face where it's going (higher = quicker).
@export var turn_rate: float = 12.0
## How far the abdomen swings after the body, and breathes.
@export var abdomen_swing: float = 0.35
@export var breathing: float = 0.04

@export_group("Death")
@export var blood_color: Color = Color(0.5, 0.04, 0.03)
@export var death_gore: float = 1.0
@export var pool_size: float = 0.6
## Dead on its back with its legs curled for this long, then gone.
@export var corpse_time: float = 6.0
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent

## Set by SpiderPack.
var pack: SpiderPack
var slot := Vector2.RIGHT
var slot_radius := 1.0
## What the pack wants it doing this tick (world m/s; it keeps the part along
## the surface it's on).
var desired_velocity := Vector3.ZERO
var size := 1.0
var speed_scale := 1.0
var rhythm_seed := 0.0
## Goes for walls and ceilings first (rolled from wall_preference).
var wall_lover := false
## A wall the pack found for it to climb (has_wall_spot), refreshed now and then.
var wall_spot := Vector3.ZERO
var has_wall_spot := false
var wall_spot_age := INF

var _state := State.CRAWL
## The surface it's on: its "up".
var _normal := Vector3.UP
## Which way it's heading along that surface (unit).
var _heading := Vector3.FORWARD
var _velocity := Vector3.ZERO
## Leg span in meters, and how high the body rides off the surface.
var _span := 0.8
var _ride := 0.16
var _bite_cooldown := 0.0
var _leap_cooldown := 0.0
var _leap_bit := false
var _air_time := 0.0
var _wall_cooldown := 0.0
var _stall_time := 0.0
var _best_distance := INF
var _dying := false
var _shoved := false
var _corpse_left := 0.0
var _landed_dead := false

# ---- Looks (every peer) ----
var _skeleton: Skeleton3D
var _legs: Array[Leg] = []
var _body_bone := -1
var _body_rest := Transform3D.IDENTITY
## The spider's "up" in the skeleton's own space: the axis its hips swing round.
var _up_skeleton := Vector3.UP
var _abdomen := -1
var _abdomen_rest := Basis.IDENTITY
var _fangs: Array[int] = []
var _fang_rest: Array[Basis] = []
var _fang_open := 0.0
var _looks_ready := false
var _time := 0.0
var _lod_timer := 0.0
var _lod := 0 # 0 full, 1 every other frame, 2 frozen
var _frame := 0
var _last_position := Vector3.ZERO
var _smooth_velocity := Vector3.ZERO
var _accel := Vector3.ZERO
var _body_pos := Vector3.ZERO
var _body_pos_vel := Vector3.ZERO
var _body_rot := Vector3.ZERO
var _body_rot_vel := Vector3.ZERO
var _abdomen_swing := Vector2.ZERO
var _abdomen_swing_vel := Vector2.ZERO
var _last_yaw_basis := Basis.IDENTITY
var _yaw_rate := 0.0

@onready var health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _pivot: Node3D = $Visual/Pivot


## One leg: its bones, its rest shape, and where its foot is.
class Leg:
	var prefix := ""
	var bones := PackedInt32Array()
	## Rest pose of each bone relative to its parent.
	var rest_local: Array[Transform3D] = []
	## Where the next joint sits in each bone's own frame (the last: the tip).
	var child_offset: Array[Vector3] = []
	## The joints (hip .. tip) at rest, relative to the body bone.
	var rest_joints: Array[Vector3] = []
	var lengths := PackedFloat32Array()
	## Where its foot rests, in the spider's own (Visual) space.
	var home := Vector3.ZERO
	var group := 0
	var palp := false
	## World positions: planted, the step it's taking, and where the foot is now.
	var planted := Vector3.ZERO
	var step_from := Vector3.ZERO
	var step_to := Vector3.ZERO
	var foot := Vector3.ZERO
	var stepping := false
	var step_t := 0.0
	var step_duration := 0.1


func _ready() -> void:
	add_to_group("enemies")
	add_to_group(Factions.GROUPS[Factions.Side.SPIDER])
	Population.mark_born(self)
	sync_to_physics = false
	_roll_variety()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D)
	_build_model()
	_last_position = global_position
	_heading = _flat_perpendicular(_normal, -global_basis.z)
	global_basis = Basis.IDENTITY # the body never turns; Visual does


## No two alike. Rule 1 (co-op): rolled on the host; size and seed travel with
## the spawn.
func _roll_variety() -> void:
	var variety := randf_range(size_min, size_max)
	size = variety
	speed_scale = randf_range(1.0 - speed_variation, 1.0 + speed_variation) / sqrt(variety)
	rhythm_seed = randf() * 1000.0
	wall_lover = randf() < wall_preference
	_span = leg_span * size
	health.max_health *= variety * variety
	health.current_health = health.max_health
	bite_reach *= size
	var shape := $CollisionShape3D as CollisionShape3D
	var sphere := (shape.shape as SphereShape3D).duplicate() as SphereShape3D
	sphere.radius *= size
	shape.shape = sphere


func is_crawling() -> bool:
	return _state == State.CRAWL


func is_dead() -> bool:
	return _state == State.DEAD or _dying


## On a wall or a ceiling rather than a floor.
func on_wall() -> bool:
	return _state == State.CRAWL and _normal.y < WALL_DOT


func surface_normal() -> Vector3:
	return _normal


## Up on a wall to get at its prey? (Not after giving up on one lately.)
func wants_wall() -> bool:
	return wall_lover and _wall_cooldown <= 0.0


# ---- Host: moving, biting, leaping -------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _dying:
		_dying = false
		if _shoved:
			_burst() # blown apart by the blast that killed it
		else:
			_start_corpse()
		return
	_bite_cooldown = maxf(_bite_cooldown - delta, 0.0)
	_leap_cooldown = maxf(_leap_cooldown - delta, 0.0)
	_wall_cooldown = maxf(_wall_cooldown - delta, 0.0)
	_shoved = false
	match _state:
		State.CRAWL:
			_crawl(delta)
			_try_bite()
			_maybe_leap(delta)
			_watch_stall(delta)
		State.LEAP, State.FALL:
			_fly(delta)
		State.DEAD:
			_corpse_physics(delta)
	if global_position.y < -60.0:
		_remove()


## Along whatever it's on: a ray ahead climbs it onto a wall in the way, a ray
## down keeps it stuck to its surface, and if that finds nothing it has
## walked off an edge -- a ray back under the edge wraps it round the corner
## onto the far face. Nothing there either: it falls.
func _crawl(delta: float) -> void:
	var up := _normal
	var wanted := desired_velocity - up * desired_velocity.dot(up)
	var into := -desired_velocity.dot(up)
	if into > 0.0 and absf(up.y) < WALL_DOT:
		# On a wall and where it wants to be is through it: up and over.
		wanted += _flat_perpendicular(up, Vector3.UP) * into
	_velocity = (_velocity - up * _velocity.dot(up)).move_toward(wanted, acceleration * delta)
	var step := _velocity * delta
	var step_length := step.length()
	var direction := step / step_length if step_length > 0.0001 else _heading
	if step_length > 0.0001:
		_heading = direction
		var ahead := _surface_ray(global_position, global_position + direction * (step_length + _ride * 1.3))
		if not ahead.is_empty() and (ahead.normal as Vector3).dot(up) < WALL_DOT:
			# Concave corner: climb onto the wall (or ceiling) in front of it,
			# carrying on away from the surface it was on.
			_set_surface(ahead.normal, up * _velocity.length())
			global_position = (ahead.position as Vector3) + _normal * _ride
			return
		global_position += step
	var down := _surface_ray(global_position + up * _ride * 0.5, global_position - up * (_ride + stick_distance * _span))
	if not down.is_empty():
		_set_surface(down.normal, _velocity)
		global_position = (down.position as Vector3) + _normal * _ride
		return
	# Convex corner: round the edge onto the face it just walked off.
	var under := global_position - up * (_ride + 0.25 * _span)
	var back := _surface_ray(under, under - direction * (step_length + _ride * 2.0 + 0.1))
	if not back.is_empty() and (back.normal as Vector3).dot(up) < WALL_DOT:
		_set_surface(back.normal, -up * _velocity.length())
		global_position = (back.position as Vector3) + _normal * _ride
		return
	_launch(_velocity, State.FALL)


## Onto a surface with this normal, keeping its speed but turned to run along
## it in the direction of `velocity` (made to lie along the new surface).
func _set_surface(normal: Vector3, velocity: Vector3) -> void:
	_normal = normal.normalized()
	var along := velocity - _normal * velocity.dot(_normal)
	_velocity = along.normalized() * velocity.length() if along.length_squared() > 0.0001 else Vector3.ZERO
	_heading = _flat_perpendicular(_normal, _heading)


## Through the air (a leap, a fall, a blast): gravity, a bite if it passes its
## prey, and it grabs on to the first surface it hits -- floor, wall or ceiling.
func _fly(delta: float) -> void:
	_air_time += delta
	var gravity := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float
	_velocity += Vector3.DOWN * gravity * delta
	if _state == State.LEAP and not _leap_bit and pack and is_instance_valid(pack.target):
		if global_position.distance_to(Factions.aim_point(pack.target)) < bite_reach:
			_leap_bit = true
			_bite(pack.target, leap_damage)
			_velocity = Vector3(-_velocity.x * 0.3, 2.0, -_velocity.z * 0.3) # bounce off them
	var move := _velocity * delta
	var reach := move + move.normalized() * _ride if move.length_squared() > 0.000001 else move
	var hit := _surface_ray(global_position, global_position + reach)
	if not hit.is_empty() and _air_time > 0.05:
		_set_surface(hit.normal, _velocity * 0.3)
		global_position = (hit.position as Vector3) + _normal * _ride
		_state = State.CRAWL
		_plant_all()
		return
	global_position += move
	if _air_time > 8.0:
		_remove() # fell out of the world


func _launch(velocity: Vector3, state: State) -> void:
	_velocity = velocity
	_state = state
	_air_time = 0.0


func _try_bite() -> void:
	if _bite_cooldown > 0.0 or pack == null or not is_instance_valid(pack.target):
		return
	if global_position.distance_to(Factions.aim_point(pack.target)) > bite_reach \
			and global_position.distance_to(pack.target.global_position) > bite_reach:
		return
	_bite_cooldown = bite_interval
	_bite(pack.target, bite_damage)


func _bite(target: Node3D, damage: float) -> void:
	var target_health := target.get_node_or_null("Health") as Health
	if target_health:
		target_health.take_damage(damage, Health.NO_ATTACKER)
		Factions.provoke(target, self)
	_fang_open = 1.0
	SoundPlayer.play_3d(bite_sound, global_position, get_tree().current_scene, 0.7)


## Close enough to its prey and it can see them: now and then, leap -- much
## more eagerly, and from much further, off a wall or ceiling.
func _maybe_leap(delta: float) -> void:
	if _leap_cooldown > 0.0 or pack == null or pack.order != SpiderPack.Order.HUNT or not is_instance_valid(pack.target):
		return
	var target := pack.target
	var distance := global_position.distance_to(Factions.aim_point(target))
	var high := on_wall()
	var in_range := distance <= wall_leap_range if high else (distance >= leap_range_min and distance <= leap_range_max)
	if in_range and randf() < (wall_leap_chance if high else leap_chance) * delta and _sees(target):
		leap(target)


## Launch at the target's middle on an arc that gets there in leap_time.
func leap(target: Node3D) -> void:
	if _state != State.CRAWL:
		return
	var aim := Factions.aim_point(target)
	var gap := aim - global_position
	var gravity := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float
	global_position += _normal * 0.05 # off the surface
	_launch(gap / leap_time + Vector3.UP * 0.5 * gravity * leap_time, State.LEAP)
	_heading = gap.normalized()
	_leap_bit = false
	_leap_cooldown = leap_cooldown
	_fang_open = 1.0


## Up a wall but not getting any closer, and too far to leap: drop off and go
## along the floor for a while.
func _watch_stall(delta: float) -> void:
	if not on_wall() or pack == null or not is_instance_valid(pack.target) or pack.order != SpiderPack.Order.HUNT:
		_stall_time = 0.0
		_best_distance = INF
		return
	var distance := global_position.distance_to(pack.target.global_position)
	if distance < _best_distance - 0.3:
		_best_distance = distance
		_stall_time = 0.0
		return
	_stall_time += delta
	if _stall_time > wall_give_up_time and distance > wall_leap_range:
		_stall_time = 0.0
		_best_distance = INF
		_wall_cooldown = wall_retry_time
		has_wall_spot = false
		global_position += _normal * 0.05
		_launch(_normal * 1.5, State.FALL)


## Set down crawling on a surface: `at` on it, `normal` out of it.
func place_on(at: Vector3, normal: Vector3) -> void:
	_normal = normal.normalized()
	_heading = _flat_perpendicular(_normal, _heading)
	global_position = at + _normal * _ride
	_last_position = global_position
	_velocity = Vector3.ZERO
	_state = State.CRAWL
	_plant_all()


## Spat out of a barnacle (or thrown): flying, legs flailing, until it grabs on.
func burst_out(velocity: Vector3) -> void:
	_launch(velocity, State.FALL)


## Explosion.push(): blasted off whatever it was on.
func shove(velocity: Vector3) -> void:
	_shoved = true
	if _state == State.DEAD:
		return
	global_position += velocity.normalized() * 0.05
	_launch(velocity, State.FALL)


func _sees(target: Node3D) -> bool:
	return _surface_ray(global_position, Factions.aim_point(target)).is_empty()


# ---- Dying ------------------------------------------------------------------

func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state != State.DEAD:
		HitFlash.flash(_visual)


## Decided next physics tick, once we know if a blast did it (Explosion
## hurts first, then pushes: shove()).
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	if _state != State.DEAD:
		_dying = true


## Blown apart: a burst of blood and a splat, gone.
func _burst() -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, global_position, _normal, blood_color, death_gore * 1.5 * size)
	var hit := _surface_ray(global_position, global_position - _normal * (_ride + 0.5))
	if not hit.is_empty():
		BloodFX.spawn_splatter(world, hit.position, hit.normal, pool_size * 1.3 * size, blood_color)
	SoundPlayer.play_3d(death_sound, global_position, world)
	_remove()


## Shot dead: a spurt of blood, it lets go of whatever it was on and drops,
## and ends up on its back with its legs curled in, in a little pool.
func _start_corpse() -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, global_position, _normal, blood_color, death_gore * size)
	SoundPlayer.play_3d(death_sound, global_position, world)
	_forget()
	var was_crawling := _state == State.CRAWL
	_state = State.DEAD
	collision_layer = 0 # shots pass through the body
	_corpse_left = corpse_time
	_air_time = 0.0
	_landed_dead = was_crawling and _normal.y >= WALL_DOT
	if _landed_dead:
		_lay_dead(global_position - _normal * _ride, _normal)
	elif was_crawling:
		_velocity = _normal * 0.5 # off the wall or ceiling, down it goes


func _corpse_physics(delta: float) -> void:
	_corpse_left -= delta
	if _corpse_left <= 0.0:
		_remove()
		return
	if _landed_dead:
		return
	_air_time += delta
	var gravity := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float
	_velocity += Vector3.DOWN * gravity * delta
	var move := _velocity * delta
	var hit := _surface_ray(global_position, global_position + move + move.normalized() * _ride)
	if not hit.is_empty():
		if (hit.normal as Vector3).y >= WALL_DOT:
			_landed_dead = true
			_lay_dead(hit.position, hit.normal)
			return
		_velocity = _velocity.slide(hit.normal) # tumbles down the wall
		move = _velocity * delta
	global_position += move
	if _air_time > 8.0:
		_remove()


func _lay_dead(at: Vector3, normal: Vector3) -> void:
	_normal = normal
	global_position = at + normal * _ride * 0.5
	BloodFX.spawn_splatter(get_tree().current_scene, at, normal, pool_size * size, blood_color)


func _forget() -> void:
	if pack:
		var attacker = get_meta("provoked_by") if has_meta("provoked_by") else null
		if Factions.provoked_by(self, attacker):
			pack.threatened_by(attacker)
		pack.forget(self)
		pack = null


func _remove() -> void:
	_forget()
	_state = State.DEAD
	queue_free()


## A ray against the level only -- floors, walls, ceilings, props bolted in
## place -- skipping anything that moves (players, rats, roaches, other
## spiders), so it never climbs onto a person.
func _surface_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var collider = hit.collider
		if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D \
				or collider is PhysicalBone3D:
			exclude.append(hit.rid)
			continue
		return hit
	return {}


## `direction` made to lie flat along a surface with this normal (or any
## direction along it, if it points straight out of it).
static func _flat_perpendicular(normal: Vector3, direction: Vector3) -> Vector3:
	var flat := direction - normal * direction.dot(normal)
	if flat.length_squared() < 0.0001:
		flat = normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD)
	return flat.normalized()


# ---- Looks: the model, IK legs, the body riding them (every peer) -------------

## Sets the model up: turned to face -Z with its back up, sized to its leg
## span, its body bone at this node's middle -- all worked out from the bones
## themselves, so it doesn't matter how the file was exported.
func _build_model() -> void:
	if model_scene == null:
		return
	var model := model_scene.instantiate() as Node3D
	_pivot.add_child(model)
	if skin_material:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = skin_material
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Spider: no Skeleton3D in the model -- no legs.")
		return
	_skeleton = skeletons[0] as Skeleton3D
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		player.stop() # the legs are ours
	_body_bone = _skeleton.find_bone("body")
	if _body_bone < 0:
		push_warning("Spider: the model has no 'body' bone.")
		return
	_body_rest = _skeleton.get_bone_global_rest(_body_bone)
	for prefix in WALKING_LEGS + PALPS:
		var leg := _make_leg(prefix)
		if leg:
			_legs.append(leg)
	if _legs.size() < 8:
		push_warning("Spider: found only %d legs on the model." % _legs.size())
	_abdomen = _skeleton.find_bone("abdomen")
	if _abdomen >= 0:
		_abdomen_rest = _skeleton.get_bone_rest(_abdomen).basis
	for fang_name in ["fangL", "fangR"]:
		var fang := _skeleton.find_bone(fang_name)
		if fang >= 0:
			_fangs.append(fang)
			_fang_rest.append(_skeleton.get_bone_rest(fang).basis)
	_orient_model(model)
	_looks_ready = true
	_plant_all()


func _make_leg(prefix: String) -> Leg:
	var leg := Leg.new()
	leg.prefix = prefix
	leg.palp = PALPS.has(prefix)
	leg.group = int(GAIT_GROUP.get(prefix, 0))
	for part in ["A", "B", "C", "D"]:
		var bone := _skeleton.find_bone(prefix + part)
		if bone < 0:
			return null
		leg.bones.append(bone)
		leg.rest_local.append(_skeleton.get_bone_rest(bone))
	for i in 3:
		leg.child_offset.append(_skeleton.get_bone_rest(leg.bones[i + 1]).origin)
	var tip := _skeleton.find_bone(prefix + "D_end")
	var d_global := _skeleton.get_bone_global_rest(leg.bones[3])
	if tip >= 0:
		leg.child_offset.append(_skeleton.get_bone_rest(tip).origin)
	else:
		# No end bone: guess the last segment from the one before it.
		var c_global := _skeleton.get_bone_global_rest(leg.bones[2])
		var guess := (d_global.origin - c_global.origin) * 1.6
		leg.child_offset.append(d_global.basis.inverse() * guess)
	var to_body := _body_rest.affine_inverse()
	for bone in leg.bones:
		leg.rest_joints.append(to_body * _skeleton.get_bone_global_rest(bone).origin)
	leg.rest_joints.append(to_body * (d_global * leg.child_offset[3]))
	for i in 4:
		leg.lengths.append(leg.rest_joints[i].distance_to(leg.rest_joints[i + 1]))
	return leg


func _orient_model(model: Node3D) -> void:
	var tips := {}
	var to_model := model.global_transform.affine_inverse() * _skeleton.global_transform
	for leg in _legs:
		tips[leg.prefix] = to_model * (_body_rest * leg.rest_joints[4])
	var left := Vector3.ZERO
	var right := Vector3.ZERO
	var front := Vector3.ZERO
	var back := Vector3.ZERO
	for prefix in WALKING_LEGS:
		if not tips.has(prefix):
			continue
		var tip: Vector3 = tips[prefix]
		if prefix.ends_with("L"):
			left += tip
		else:
			right += tip
		if prefix.begins_with("F1"):
			front += tip
		elif prefix.begins_with("B"):
			back += tip
	var body := to_model * _body_rest.origin
	var forward := front - back
	if _fangs.size() == 2 and _abdomen >= 0:
		var fangs := (to_model * _skeleton.get_bone_global_rest(_fangs[0]).origin + to_model * _skeleton.get_bone_global_rest(_fangs[1]).origin) * 0.5
		forward = fangs - to_model * _skeleton.get_bone_global_rest(_abdomen).origin
	var side := left - right
	var up := forward.cross(side).normalized()
	forward = (forward - up * forward.dot(up)).normalized()
	_up_skeleton = (to_model.basis.inverse() * up).normalized()
	var axes := Basis(forward.cross(up), up, -forward) # the model's own right/up/back
	var turn := axes.transposed() # ...turned onto ours
	var span := 0.0
	for a: Vector3 in tips.values():
		for b: Vector3 in tips.values():
			span = maxf(span, a.distance_to(b))
	var scale_by := _span / maxf(span, 0.0001)
	model.transform = Transform3D(turn.scaled(Vector3.ONE * scale_by), -(turn * body) * scale_by)
	# Where each foot rests, in our own space: its rest spot, flat on the
	# surface the body rides ride-height above.
	var to_visual := _visual.global_transform.affine_inverse() * _skeleton.global_transform
	var drop := 0.0
	var walking := 0
	for leg in _legs:
		leg.home = to_visual * (_body_rest * leg.rest_joints[4])
		if not leg.palp:
			drop -= leg.home.y
			walking += 1
	_ride = drop / maxi(walking, 1)
	if _ride < 0.12 * _span:
		_ride = 0.2 * _span # rest pose has its feet up: give it some legs to stand on
	for leg in _legs:
		if not leg.palp:
			leg.home.y = -_ride
		leg.home.x *= 1.05 # a touch wider than rest: a lower, more spidery stance


## Every foot straight down onto the surface under its rest spot (spawning,
## landing).
func _plant_all() -> void:
	if not _looks_ready:
		return
	var xf := _visual_target_transform()
	for leg in _legs:
		leg.stepping = false
		leg.planted = _foot_spot(xf * leg.home, xf.basis.y.normalized())
		leg.foot = leg.planted


func _process(delta: float) -> void:
	if not _looks_ready:
		return
	_time += delta
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.25
		var camera := get_viewport().get_camera_3d()
		var distance := camera.global_position.distance_to(global_position) if camera else 0.0
		_lod = 0 if distance < ik_full_distance else (1 if distance < ik_far_distance else 2)
	_turn_visual(delta)
	if _lod == 2:
		return
	_frame += 1
	_track_motion(delta)
	_update_legs(delta)
	_update_body(delta)
	if _lod == 1 and _frame % 2 == 1:
		return
	_solve_legs()
	_pose_extras()


## Where Visual should be: on the surface, facing where it's heading -- on its
## back once it's dead.
func _visual_target_transform() -> Transform3D:
	var up := _normal
	var forward := _flat_perpendicular(up, _heading)
	var facing := Basis(forward.cross(up), up, -forward)
	if _state == State.LEAP or _state == State.FALL:
		# In the air: nose along the flight, back up-ish.
		var flight := _velocity.normalized() if _velocity.length() > 0.5 else forward
		var air_up := _flat_perpendicular(flight, Vector3.UP) if absf(flight.y) < 0.99 else Vector3.BACK
		air_up = air_up if air_up.dot(Vector3.UP) >= 0.0 else -air_up
		facing = Basis(flight.cross(air_up), air_up, -flight).orthonormalized()
	elif _state == State.DEAD and _landed_dead:
		facing = facing.rotated(forward, PI) # legs in the air
	return Transform3D(facing, global_position)


func _turn_visual(delta: float) -> void:
	var target := _visual_target_transform().basis
	var rate := turn_rate * (0.5 if _state == State.DEAD else 1.0)
	var before := _visual.global_basis
	_visual.global_basis = before.slerp(target, 1.0 - exp(-rate * delta)).orthonormalized()
	# How fast it's turning (for the abdomen to swing after it).
	var turned := (before.z.signed_angle_to(_visual.global_basis.z, _visual.global_basis.y))
	_yaw_rate = lerpf(_yaw_rate, turned / maxf(delta, 0.001), 0.2)


## Its actual movement this frame (smoothed) and how fast that's changing,
## for the body's inertia.
func _track_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved := (global_position - _last_position) / delta
	_last_position = global_position
	if moved.length() > 40.0:
		moved = _smooth_velocity # teleported (spawned, snapped): ignore
	var before := _smooth_velocity
	_smooth_velocity = _smooth_velocity.lerp(moved, 1.0 - exp(-20.0 * delta))
	_accel = _accel.lerp((_smooth_velocity - before) / delta, 1.0 - exp(-10.0 * delta))


## Foot placement: planted feet stay put in the world; a foot too far from
## the spot under its hip (plus a little lead) steps there, in an arc --
## one set of four at a time. In the air the legs splay and paddle; dead,
## they curl in.
func _update_legs(delta: float) -> void:
	var xf := _visual.global_transform
	var up := xf.basis.y.normalized()
	var speed := _smooth_velocity.length()
	var lead := _smooth_velocity * step_lead
	var duration := clampf(stride * _span / maxf(speed, 0.01) * 0.6, step_time_min, step_time)
	var stepping_group := [false, false]
	for leg in _legs:
		if leg.stepping:
			stepping_group[leg.group] = true
	for leg in _legs:
		if leg.palp:
			var wiggle := Vector3(0.0, sin(_time * 7.0 + rhythm_seed + leg.group * 2.0) * 0.04, -_fang_open * 0.12) * _span
			leg.foot = xf * (leg.home + Vector3(0.0, _ride * 0.35, 0.0) + wiggle)
			continue
		if _state != State.CRAWL:
			leg.stepping = false
			var curl := 0.35 if _state == State.DEAD else 0.8
			var lift := -0.5 if _state == State.DEAD else 0.4
			var paddle := 0.0 if _state == State.DEAD else sin(_time * 18.0 + leg.home.z * 9.0) * 0.06
			leg.foot = xf * Vector3(leg.home.x * curl, _ride * lift + paddle * _span, leg.home.z * curl)
			leg.planted = leg.foot
			continue
		var want := xf * leg.home + lead
		if leg.stepping:
			leg.step_t += delta / leg.step_duration
			if leg.step_t >= 1.0:
				leg.stepping = false
				leg.planted = leg.step_to
				leg.foot = leg.planted
			else:
				var t := leg.step_t
				var eased := t * t * (3.0 - 2.0 * t)
				leg.foot = leg.step_from.lerp(leg.step_to, eased) + up * sin(t * PI) * step_height * _span
			continue
		leg.foot = leg.planted
		var off := leg.planted.distance_to(want)
		if off > stride * _span * 2.5:
			leg.planted = _foot_spot(want, up) # way off (a snap, a corner): just put it there
			leg.foot = leg.planted
		elif off > stride * _span and not stepping_group[1 - leg.group]:
			leg.stepping = true
			stepping_group[leg.group] = true
			leg.step_t = 0.0
			leg.step_duration = duration * randf_range(0.85, 1.15)
			leg.step_from = leg.planted
			leg.step_to = _foot_spot(want + lead, up)


## The surface under (along -up) a spot, or the spot itself if there's none.
func _foot_spot(point: Vector3, up: Vector3) -> Vector3:
	if _lod > 0:
		return point
	var hit := _surface_ray(point + up * _ride * 1.5, point - up * _ride * 1.5)
	return hit.position if not hit.is_empty() else point


## The body rides its legs on a spring: settles to the height and tilt of the
## feet, dips with each leg in the air, leans its weight onto the planted
## ones, twists into each set of steps, lags behind as it speeds up and
## swings out on turns. Nothing about it is held still.
func _update_body(delta: float) -> void:
	delta = minf(delta, 0.05)
	var to_local := _visual.global_transform.affine_inverse()
	var front_y := 0.0
	var back_y := 0.0
	var left_y := 0.0
	var right_y := 0.0
	var counts := [0, 0, 0, 0]
	var height := 0.0
	var lifted := 0
	var planted_center := Vector3.ZERO
	var home_center := Vector3.ZERO
	var planted_count := 0
	var group_lift := [0, 0]
	for leg in _legs:
		if leg.palp:
			continue
		var foot := to_local * leg.foot
		var rise := foot.y + _ride
		height += rise
		if leg.home.z < 0.0:
			front_y += rise
			counts[0] += 1
		else:
			back_y += rise
			counts[1] += 1
		if leg.home.x < 0.0:
			left_y += rise
			counts[2] += 1
		else:
			right_y += rise
			counts[3] += 1
		if leg.stepping:
			lifted += 1
			group_lift[leg.group] += 1
		else:
			planted_center += foot
			home_center += leg.home
			planted_count += 1
	var crawling := _state == State.CRAWL
	var target_pos := Vector3.ZERO
	var target_rot := Vector3.ZERO
	if crawling:
		var walking := maxf(float(counts[0] + counts[1]), 1.0)
		var length := _span * 0.6
		var width := _span * 0.6
		target_pos.y = height / walking * body_follow - lifted * weight_dip * _span
		target_rot.x = atan2(front_y / maxf(float(counts[0]), 1.0) - back_y / maxf(float(counts[1]), 1.0), length) * body_follow
		target_rot.z = atan2(right_y / maxf(float(counts[3]), 1.0) - left_y / maxf(float(counts[2]), 1.0), width) * body_follow
		if planted_count > 0:
			var shift := (planted_center - home_center) / float(planted_count) * weight_shift
			target_pos.x += shift.x
			target_pos.z += shift.z
		target_rot.y = float(group_lift[0] - group_lift[1]) / 4.0 * gait_twist
		# Inertia: the body lags behind a change of speed and leans into it.
		var accel_local := _visual.global_basis.inverse() * _accel
		target_pos.x -= accel_local.x * inertia * _span
		target_pos.z -= accel_local.z * inertia * _span
		target_rot.x += clampf(accel_local.z * inertia * 0.6, -0.3, 0.3)
		target_rot.z += clampf(-accel_local.x * inertia * 0.6, -0.3, 0.3)
	# Breathing, always.
	target_pos.y += sin(_time * 2.2 + rhythm_seed) * breathing * 0.15 * _span
	_body_pos_vel += (spring_stiffness * (target_pos - _body_pos) - spring_damping * _body_pos_vel) * delta
	_body_pos += _body_pos_vel * delta
	_body_rot_vel += (spring_stiffness * (target_rot - _body_rot) - spring_damping * _body_rot_vel) * delta
	_body_rot += _body_rot_vel * delta
	_pivot.position = _body_pos
	_pivot.basis = Basis.from_euler(_body_rot)
	# The abdomen swings after the body: out on turns, back as it speeds up.
	var accel_body := _visual.global_basis.inverse() * _accel
	var swing_target := Vector2(clampf(-_yaw_rate * 0.08, -1.0, 1.0), clampf(accel_body.z * 0.02, -1.0, 1.0)) * abdomen_swing
	_abdomen_swing_vel += (swing_target * spring_stiffness * 0.5 - _abdomen_swing * spring_stiffness * 0.5 - _abdomen_swing_vel * spring_damping * 0.6) * delta
	_abdomen_swing += _abdomen_swing_vel * delta
	_fang_open = maxf(_fang_open - delta * 3.0, 0.0)


## Every leg's bones turned so its tip reaches its foot: FABRIK over the
## joint positions (starting from the rest pose each frame, so the knees
## always bend the way they were built to), then each bone rotated, hip to
## tip, onto its new direction.
func _solve_legs() -> void:
	var to_skeleton := _skeleton.global_transform.affine_inverse()
	for leg in _legs:
		_solve(leg, to_skeleton * leg.foot)


func _solve(leg: Leg, target: Vector3) -> void:
	var joints: Array[Vector3] = []
	for joint in leg.rest_joints:
		joints.append(_body_rest * joint)
	var root := joints[0]
	# The hip swings first: the whole leg turns round the body's up axis at
	# its base until it points at the foot, so the first segment (the coxa)
	# sweeps forward and back with every step the way a spider's does. Then
	# FABRIK bends the rest. (Without this the coxa barely moved: FABRIK puts
	# almost all the bend into the long outer segments.)
	var rest_reach := joints[4] - root
	var want_reach := target - root
	rest_reach -= _up_skeleton * rest_reach.dot(_up_skeleton)
	want_reach -= _up_skeleton * want_reach.dot(_up_skeleton)
	if rest_reach.length_squared() > 0.000001 and want_reach.length_squared() > 0.000001:
		var swing := clampf(rest_reach.signed_angle_to(want_reach, _up_skeleton), -hip_swing_limit, hip_swing_limit)
		var hip := Basis(_up_skeleton, swing)
		for i in range(1, 5):
			joints[i] = root + hip * (joints[i] - root)
	var total := 0.0
	for length in leg.lengths:
		total += length
	if root.distance_to(target) >= total:
		var out := (target - root).normalized()
		for i in 4:
			joints[i + 1] = joints[i] + out * leg.lengths[i]
	else:
		for iteration in ik_iterations:
			joints[4] = target
			for i in range(3, -1, -1):
				joints[i] = joints[i + 1] + (joints[i] - joints[i + 1]).normalized() * leg.lengths[i]
			joints[0] = root
			for i in 4:
				joints[i + 1] = joints[i] + (joints[i + 1] - joints[i]).normalized() * leg.lengths[i]
	var parent := _body_rest
	for i in 4:
		var current := parent * leg.rest_local[i]
		var was := current.basis * leg.child_offset[i]
		var wants := joints[i + 1] - current.origin
		if was.length_squared() < 0.000001 or wants.length_squared() < 0.000001:
			parent = current
			continue
		var turn := Quaternion(was.normalized(), wants.normalized())
		var turned := Basis(turn) * current.basis
		_skeleton.set_bone_pose_rotation(leg.bones[i], (parent.basis.inverse() * turned).get_rotation_quaternion())
		parent = Transform3D(turned, current.origin)


## The abdomen swinging and breathing, the fangs opening to bite.
func _pose_extras() -> void:
	var to_skeleton := (_skeleton.global_basis.inverse() * _visual.global_basis).orthonormalized()
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	if _abdomen >= 0:
		var breathe := sin(_time * 2.2 + rhythm_seed) * breathing
		var swing := Basis(up, _abdomen_swing.x) * Basis(right, _abdomen_swing.y + breathe)
		var rest_global := _body_rest.basis * _abdomen_rest
		var posed := swing * rest_global
		_skeleton.set_bone_pose_rotation(_abdomen, (_body_rest.basis.inverse() * posed).get_rotation_quaternion())
	for i in _fangs.size():
		var chew := Basis(right, -_fang_open * 0.6 + sin(_time * 9.0 + rhythm_seed + i) * 0.05)
		var rest_global := _body_rest.basis * _fang_rest[i]
		_skeleton.set_bone_pose_rotation(_fangs[i], (_body_rest.basis.inverse() * chew * rest_global).get_rotation_quaternion())
