class_name BurrowWorm
extends Node3D

## A giant worm that swims through the ground and walls, Terraria-style
## (the Eater of Worlds / Devourer): no terrain is dug -- it just passes
## through everything, and the floor and walls hide whatever's underground.
##
## Movement is the Terraria worm's: only the head thinks. Inside the ground
## (or a wall) it has full control -- it accelerates toward where it wants
## to be, a limited acceleration, so it overshoots and comes round in big
## arcs. Out in the open air it has (almost) no control: gravity takes it,
## so a lunge at you erupts out of the floor, arcs over and dives back in.
## Far from you it tunnels under the floor toward you (lurk_depth down),
## shaking the camera and kicking up a trail of dirt you can follow; within
## breach_range it comes straight up at you.
##
## The body is follow-the-leader: each segment keeps segment_spacing behind
## the one in front, so the whole worm traces the head's path. Every segment
## can be shot (each has its own hitbox and Health, all feeding the worm's
## one Health); touching any of it hurts, the head bites hardest.
##
## Look: the PSX Creatures kit's tape_worm, which is flat -- so each segment
## is slices_per_segment copies of it fanned round the body's axis (60 degrees
## apart for 3), each a little longer than a segment so they overlap like
## scales, and every segment twisted a little more than the last so the
## ridges spiral down the body. Reads as a round, ribbed, fleshy tube from
## any angle. The head's maw is the kit's barnacle, mouth forward.
## Rule 1 (co-op): the host moves it and deals the damage.

const TAPE_WORM := preload("res://art/props/PSX Creatures/Models/FBX/tape_worm.fbx")
const MAW := preload("res://art/props/PSX Creatures/Models/FBX/barnacle.fbx")

@export_group("Body")
@export var segment_count: int = 20
## Distance between segment centres, meters.
@export var segment_spacing: float = 0.75
## Body thickness (radius, meters) at the head, tapering to tail_radius.
@export var head_radius: float = 0.75
@export var tail_radius: float = 0.3
## Tape worm slices fanned round each segment (3 = 60 degrees apart).
@export var slices_per_segment: int = 3
## Each slice's length as a multiple of segment_spacing (above 1 they
## overlap), and how thick a slice is as a share of the segment's radius.
@export var slice_overlap: float = 1.8
@export var slice_thickness: float = 0.45
## Each segment is turned this many more degrees round the body than the
## one in front, so the ridges spiral.
@export var twist_per_segment: float = 17.0
@export var skin_material: Material
@export var maw_material: Material
## Size of the barnacle maw across, as a multiple of the head's diameter.
@export var maw_size: float = 1.15

@export_group("Movement")
@export var max_speed: float = 11.0
## How fast it can change velocity inside the ground (m/s²): lower = wider,
## lazier arcs and more overshoot.
@export var acceleration: float = 14.0
## Out of the ground: gravity, and the little steering it has left.
@export var air_gravity: float = 16.0
@export var air_control: float = 2.0
## Far from its prey it tunnels this far under the floor...
@export var lurk_depth: float = 3.0
## ...never deeper than this...
@export var max_depth: float = 7.0
## ...and within this (flat distance) it comes straight up at them.
@export var breach_range: float = 14.0
## Players further than this are ignored: it wanders, breaching now and then.
@export var notice_range: float = 45.0
@export var wander_radius: float = 25.0
## Chance a wander goal is up in the air (so it breaches just to show off).
@export_range(0.0, 1.0, 0.05) var wander_breach_chance: float = 0.3

@export_group("Attack")
## The head's bite and any other segment's touch, and how often each can
## hurt the same player.
@export var bite_damage: float = 20.0
@export var contact_damage: float = 6.0
@export var contact_interval: float = 0.7
## How hard a hit throws you (m/s), plus half that upward.
@export var knockback: float = 9.0
## One explosion catching several segments only counts the worst-hit one
## fully, plus this share of the rest (so a rocket isn't x6).
@export_range(0.0, 1.0, 0.05) var multi_hit_share: float = 0.35

@export_group("Look")
@export var dirt_color: Color = Color(0.13, 0.09, 0.06)
@export var blood_color: Color = Color(0.55, 0.03, 0.03)
## Dirt kicked up above it as it tunnels (every trail_interval s), and the
## camera rumble while it's this close underneath you.
@export var trail_interval: float = 0.18
@export var rumble_range: float = 10.0
@export var rumble: float = 0.6
## Camera shake when it bursts out of or dives into a surface near you.
@export var breach_shake: float = 4.0
@export var shake_range: float = 20.0
@export var breach_sound: SoundEvent
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent

var target: Node3D

var _segments: Array[AnimatableBody3D] = []
var _visuals: Array[Node3D] = []
var _pos := PackedVector3Array()
var _radii := PackedFloat32Array()
var _below := PackedByteArray() # each segment under the floor plane last tick
var _vel := Vector3.ZERO
var _ground_y := 0.0
var _home := Vector3.ZERO
var _inside := true
var _wander_to := Vector3.ZERO
var _wander_left := 0.0
var _retarget := 0.0
var _trail_left := 0.0
var _hit_cooldowns := {} # player -> seconds
var _dead := false
var _death_step := 0.0
var _death_index := 0
## This physics frame's damage per segment (multi_hit_share).
var _hit_frame := -1
var _frame_hits := {}
var _frame_applied := 0.0

## The tape worm measured once: [lay basis, centre, size along x/y/z after
## laying (x = width, y = thickness, z = length)].
static var _slice_fit: Array = []

@onready var health: Health = $Health


func _ready() -> void:
	_home = global_position
	var floor_hit := _static_ray(global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 50.0)
	_ground_y = (floor_hit.position as Vector3).y if not floor_hit.is_empty() else global_position.y
	health.died.connect(_on_died)
	var start := Vector3(_home.x, _ground_y - lurk_depth, _home.z)
	var back := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_vel = -back * max_speed * 0.5
	for i in segment_count:
		var t := float(i) / maxf(segment_count - 1, 1)
		var radius := lerpf(head_radius, tail_radius, t * t)
		_radii.append(radius)
		_pos.append(start + back * segment_spacing * i)
		_below.append(1)
		_build_segment(i, radius)
	_pick_wander()
	_place_segments()
	_ignore_players()


# ---- Building the body ------------------------------------------------------

func _build_segment(index: int, radius: float) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.top_level = true
	body.collision_layer = 1
	body.collision_mask = 0
	body.name = "Segment%d" % index
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.9
	shape.shape = sphere
	body.add_child(shape)
	# Its own Health so shots find it; everything it takes goes to the worm's.
	var segment_health := Health.new()
	segment_health.name = "Health"
	segment_health.max_health = 1000000.0
	body.add_child(segment_health)
	segment_health.damaged.connect(_on_segment_damaged.bind(index))
	var visual := Node3D.new()
	body.add_child(visual)
	_add_slices(visual, radius, index)
	if index == 0:
		_add_maw(visual, radius)
	add_child(body)
	_segments.append(body)
	_visuals.append(visual)


## The tape worm laid along the body (length on Z, flat side up) -- worked out
## from its own bounds, the same as the leech does it.
func _measure_slice() -> Array:
	if not _slice_fit.is_empty():
		return _slice_fit
	var probe := TAPE_WORM.instantiate() as Node3D
	add_child(probe)
	var bounds := _bounds_of(probe)
	probe.queue_free()
	var size := bounds.size
	var thin := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
	var long := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	if thin == long:
		long = (thin + 1) % 3
	var mid := 3 - thin - long
	var columns := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	columns[thin] = Vector3.UP
	columns[long] = Vector3.BACK
	columns[mid] = Vector3.RIGHT
	var lay := Basis(columns[0], columns[1], columns[2])
	if lay.determinant() < 0.0:
		columns[mid] = Vector3.LEFT
		lay = Basis(columns[0], columns[1], columns[2])
	_slice_fit = [lay, bounds.get_center(), Vector3(size[mid], size[thin], size[long])]
	return _slice_fit


## slices_per_segment tape worms fanned round the body's axis, each stretched
## to the segment's length (overlapping the next) and width.
func _add_slices(visual: Node3D, radius: float, index: int) -> void:
	var fit := _measure_slice()
	var lay: Basis = fit[0]
	var center: Vector3 = fit[1]
	var size: Vector3 = fit[2]
	var stretch := Basis.from_scale(Vector3(
			radius * 2.0 / maxf(size.x, 0.0001),
			radius * slice_thickness / maxf(size.y, 0.0001),
			segment_spacing * slice_overlap / maxf(size.z, 0.0001)))
	var twist := deg_to_rad(twist_per_segment) * index
	for k in slices_per_segment:
		var spin := Basis(Vector3.BACK, twist + PI * k / maxf(slices_per_segment, 1))
		var slice := TAPE_WORM.instantiate() as Node3D
		visual.add_child(slice)
		var basis := spin * stretch * lay
		slice.transform = Transform3D(basis, -(basis * center))
		_skin(slice, skin_material)


## The barnacle's maw on the head, its mouth facing forward (-Z).
func _add_maw(visual: Node3D, radius: float) -> void:
	var maw := MAW.instantiate() as Node3D
	visual.add_child(maw)
	var bounds := _bounds_of(maw)
	var across := maxf(maxf(bounds.size.x, bounds.size.z), 0.0001)
	var face := Basis(Vector3.RIGHT, -PI * 0.5) # its up (the mouth) to forward
	maw.transform = Transform3D(face.scaled(Vector3.ONE * radius * 2.0 * maw_size / across),
			Vector3(0.0, 0.0, -segment_spacing * 0.35))
	_skin(maw, maw_material)


func _skin(model: Node3D, material: Material) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node in meshes:
		if material:
			(node as MeshInstance3D).material_override = material


func _bounds_of(model: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var to_model := model.global_transform.affine_inverse()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node in meshes:
		var mesh := node as MeshInstance3D
		var box := to_model * mesh.global_transform * mesh.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	return bounds


# ---- Moving (host) ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		_die_step(delta)
		return
	if not multiplayer.is_server():
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		target = _nearest_player()
		_ignore_players()
	var head := _pos[0]
	var was_inside := _inside
	_inside = _in_ground(head)
	var goal := _goal(head, delta)
	if _inside:
		# In the ground: full control, but only so much acceleration -- it
		# overshoots and comes round in arcs.
		_vel = _vel.move_toward((goal - head).normalized() * max_speed, acceleration * delta)
	else:
		# In the open: gravity has it.
		_vel.y -= air_gravity * delta
		var flat := Vector3(goal.x - head.x, 0.0, goal.z - head.z)
		if flat.length_squared() > 0.01:
			_vel += flat.normalized() * air_control * delta
	if head.y < _ground_y - max_depth:
		_vel.y = maxf(_vel.y, 2.0)
	_vel = _vel.limit_length(max_speed * 1.6)
	var new_head := head + _vel * delta
	if was_inside != _inside:
		_breach_fx(head, new_head, _inside)
	_pos[0] = new_head
	# Follow the leader.
	for i in range(1, _pos.size()):
		var away := _pos[i] - _pos[i - 1]
		if away.length_squared() < 0.000001:
			away = -_vel.normalized() if _vel.length_squared() > 0.0001 else Vector3.BACK
		_pos[i] = _pos[i - 1] + away.normalized() * segment_spacing
	_crossings()
	_trail(delta)
	_contact(delta)
	_place_segments()


func _place_segments() -> void:
	for i in _segments.size():
		var forward := (_pos[i - 1] - _pos[i]) if i > 0 else _vel
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var up := Vector3.UP if absf(forward.normalized().y) < 0.98 else Vector3.BACK
		_segments[i].global_transform = Transform3D(Basis.looking_at(forward.normalized(), up), _pos[i])


## Where the head's headed: under the floor toward its prey from afar, then
## straight at them; with nobody about, wandering (now and then breaching).
func _goal(head: Vector3, delta: float) -> Vector3:
	if target and is_instance_valid(target):
		var prey := Factions.aim_point(target)
		var flat := Vector2(prey.x - head.x, prey.z - head.z).length()
		if flat > breach_range:
			return Vector3(prey.x, _ground_y - lurk_depth, prey.z)
		return prey
	_wander_left -= delta
	if _wander_left <= 0.0 or head.distance_to(_wander_to) < 2.0:
		_pick_wander()
	return _wander_to


func _pick_wander() -> void:
	_wander_left = randf_range(4.0, 9.0)
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(wander_radius * 0.3, wander_radius)
	var height := _ground_y + 3.0 if randf() < wander_breach_chance else _ground_y - lurk_depth
	_wander_to = Vector3(_home.x + offset.x, height, _home.z + offset.y)


## Players walk through it (contact damage does the hurting) -- including
## ones who join after it spawned.
func _ignore_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PhysicsBody3D
		if player == null:
			continue
		for segment in _segments:
			segment.add_collision_exception_with(player)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := notice_range
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var distance := player.global_position.distance_to(_pos[0])
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## In the ground: under the floor it lives in, or inside level geometry (a
## wall, a pillar, a platform).
func _in_ground(point: Vector3) -> bool:
	if point.y < _ground_y - 0.05:
		return true
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	for result in get_world_3d().direct_space_state.intersect_point(query, 8):
		var collider = result.collider
		if collider is StaticBody3D and not collider is AnimatableBody3D:
			return true
	return false


# ---- Effects ----------------------------------------------------------------

## Bursting out of (or diving into) a surface: a spray of dirt and a dark
## hole where it went through, a crunch, and the camera shakes nearby.
func _breach_fx(from: Vector3, to: Vector3, entering: bool) -> void:
	var world := get_tree().current_scene
	var hit := _static_ray(from, to + (to - from).normalized() * 0.5) if entering \
			else _static_ray(to, from - (to - from).normalized() * 0.5)
	var at := Vector3(to.x, _ground_y, to.z)
	var normal := Vector3.UP
	if not hit.is_empty():
		at = hit.position
		normal = hit.normal
	var size := _radii[0]
	BloodFX.spawn_splatter(world, at + normal * 0.01, normal, size * 3.0, dirt_color)
	BloodFX.spawn_impact(world, at, normal, dirt_color.lightened(0.15), 3.0)
	BloodFX.spawn_impact(world, at, (normal + Vector3(randf() - 0.5, 0.0, randf() - 0.5)).normalized(), dirt_color, 2.0)
	SoundPlayer.play_3d(breach_sound, at, world)
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < shake_range and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).shake(breach_shake * (1.0 - distance / shake_range))


## Body segments crossing the floor (out or back in): a smaller puff of dirt
## where each goes through, so the whole length visibly pours out and back.
func _crossings() -> void:
	var world := get_tree().current_scene
	for i in range(1, _pos.size()):
		var below := 1 if _pos[i].y < _ground_y else 0
		if below != _below[i] and i % 2 == 0:
			BloodFX.spawn_impact(world, Vector3(_pos[i].x, _ground_y + 0.05, _pos[i].z), Vector3.UP, dirt_color, 1.0)
		_below[i] = below


## Tunnelling under the floor: dirt kicked up above its head, and the ground
## rumbling under anyone it's passing beneath.
func _trail(delta: float) -> void:
	var head := _pos[0]
	if head.y >= _ground_y or head.y < _ground_y - lurk_depth - 1.5:
		return
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = trail_interval
	var surface := Vector3(head.x, _ground_y + 0.05, head.z)
	BloodFX.spawn_impact(get_tree().current_scene, surface, Vector3.UP, dirt_color, 0.75)
	if randf() < 0.3:
		BloodFX.spawn_splatter(get_tree().current_scene, surface, Vector3.UP, _radii[0] * 1.2, dirt_color.darkened(0.2))
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player.global_position.distance_to(surface) < rumble_range and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).shake(rumble)


# ---- Hurting and being hurt -------------------------------------------------

## Any part of it touching a player hurts (the head bites), each player at
## most every contact_interval, and throws them.
func _contact(delta: float) -> void:
	for player in _hit_cooldowns.keys():
		_hit_cooldowns[player] = float(_hit_cooldowns[player]) - delta
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player) or float(_hit_cooldowns.get(player, 0.0)) > 0.0:
			continue
		var middle := Factions.aim_point(player)
		var touching := -1
		for i in _pos.size():
			if _pos[i].y < _ground_y - _radii[i]:
				continue # underground
			if _pos[i].distance_to(middle) < _radii[i] + 0.7:
				touching = i
				break
		if touching < 0:
			continue
		_hit_cooldowns[player] = contact_interval
		var player_health := player.get_node_or_null("Health") as Health
		if player_health:
			player_health.take_damage(bite_damage if touching == 0 else contact_damage, Health.NO_ATTACKER)
		var away := (middle - _pos[touching])
		away.y = 0.0
		var throw := (away.normalized() if away.length_squared() > 0.001 else _vel.normalized()) * knockback + Vector3.UP * knockback * 0.5
		if player.has_method("shove"):
			player.call("shove", throw)
		if touching == 0:
			SoundPlayer.play_3d(bite_sound, _pos[0], get_tree().current_scene)


## A segment was hit: it bleeds and flashes, and the worm takes the damage --
## all of one hit, but only multi_hit_share of the rest when one blast catches
## several segments in the same physics frame.
func _on_segment_damaged(amount: float, attacker_id: int, index: int) -> void:
	if _dead or index >= _segments.size():
		return
	var segment_health := _segments[index].get_node("Health") as Health
	segment_health.current_health = segment_health.max_health
	HitFlash.flash(_visuals[index])
	BloodFX.spawn_impact(get_tree().current_scene, _pos[index], Vector3.UP, blood_color, 1.0)
	var frame := Engine.get_physics_frames()
	if frame != _hit_frame:
		_hit_frame = frame
		_frame_hits.clear()
		_frame_applied = 0.0
	_frame_hits[index] = float(_frame_hits.get(index, 0.0)) + amount
	var most := 0.0
	var total := 0.0
	for value in _frame_hits.values():
		most = maxf(most, value)
		total += value
	var owed := most + (total - most) * multi_hit_share
	if owed > _frame_applied:
		health.take_damage(owed - _frame_applied, attacker_id)
		_frame_applied = owed


## Dead: it comes apart from the head down, a burst of blood per segment.
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	_dead = true
	_death_step = 0.0
	_death_index = 0
	SoundPlayer.play_3d(death_sound, _pos[0], get_tree().current_scene)


func _die_step(delta: float) -> void:
	_death_step -= delta
	if _death_step > 0.0:
		return
	_death_step = 0.06
	if _death_index >= _segments.size():
		queue_free()
		return
	var at := _pos[_death_index]
	var world := get_tree().current_scene
	if at.y > _ground_y - _radii[_death_index]:
		BloodFX.spawn_impact(world, at, Vector3.UP, blood_color, 2.0 * _radii[_death_index] / maxf(head_radius, 0.01) + 0.5)
		var floor_hit := _static_ray(at, at + Vector3.DOWN * 6.0)
		if not floor_hit.is_empty():
			BloodFX.spawn_splatter(world, floor_hit.position, floor_hit.normal, _radii[_death_index] * 2.5, blood_color)
	_segments[_death_index].visible = false
	_segments[_death_index].collision_layer = 0
	_death_index += 1


## Level geometry only.
func _static_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for segment in _segments:
		exclude.append(segment.get_rid())
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D):
			return hit
		exclude.append(hit.rid)
	return {}
