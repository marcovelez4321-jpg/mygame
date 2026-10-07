class_name Deepmaw
extends Node3D

## A deepmaw: a single big worm (the DEEPMAW retro PSX model) that guards a
## barnacle clump from under the floor. It digs the way the BurrowWorm does
## -- passing through floors and walls, the level hiding whatever's inside
## them -- but it's one body, not segments: its own spine bones are bent
## along the path its head has swum (DeepmawBend), so it arcs out of the
## ground, curves through the air and pours back in as one creature, with
## a swimming wiggle down its length.
##
## Movement is the Terraria worm's (see BurrowWorm): in the ground, full
## steering with limited acceleration (wide arcs, overshoot); in the air,
## gravity. It lurks lurk_depth under its home, circling. A player within
## guard_range of home is attacked the boss's way (see Leap): it tunnels to
## just short of them, the ground cracks, and it bursts out under them nose
## first ("jump attack") on an arc through them and beyond, biting anyone its
## jaws reach ("BITE"), dives back in and comes round again. The whole model
## faces where it's going every tick, and its spine bends along the path on
## top. Leave its ground (guard_range x 1.5 from home) and it goes back to
## lurking.
## Rule 1 (co-op): the host moves it and deals the damage.

enum State { LURK, HUNT, DEAD }
## The attack cycle while hunting.
enum Phase { TUNNEL, WINDUP, RISE, AIR, DIVE }

@export var model_scene: PackedScene = preload("res://art/DEEPMAW- Retro psx  monster/DEEPMAW.fbx")
## The model's two materials ("cuerpo" = body, "dientes" = teeth) are
## swapped for these; the body's is tinted to the leeches' and the boss
## worm's colour (the tape worm skin).
@export var body_material: Material
@export var teeth_material: Material
## Guarding something that moves -- the BurrowWorm boss -- instead of a fixed
## spot: home follows the floor under it, so it swims along with it.
@export var guard_node: Node3D
## Past this far from the camera the spine isn't re-bent every frame
## (every 4th), and past bend_cull_distance not at all.
@export var bend_full_distance: float = 25.0
@export var bend_cull_distance: float = 70.0

@export_group("Body")
## Its length head to tail, meters (the model is sized to it).
@export var body_length: float = 5.0
## Hitbox spheres along the body, and their radius as a share of its length.
@export var hitbox_count: int = 5
@export var hitbox_radius: float = 0.07
## The swimming wiggle down its length: how far (share of its length) and
## how fast (waves a second).
@export var wiggle: float = 0.03
@export var wiggle_speed: float = 1.6

@export_group("Movement")
@export var max_speed: float = 9.0
## Inside the ground: how fast it can change velocity (lower = wider arcs).
@export var acceleration: float = 16.0
@export var air_gravity: float = 16.0
## Lurking this far under the floor, circling home this far out.
@export var lurk_depth: float = 2.5
@export var lurk_radius: float = 4.0
@export var lurk_speed: float = 0.35
@export var max_depth: float = 6.0

@export_group("Guarding")
## Players within this of home get attacked; it gives up past 1.5x this.
@export var guard_range: float = 14.0

@export_group("Leap")
## Its attack, like the boss's: it tunnels to just short of its prey, sinks
## briefly while the ground cracks there (windup_time), then bursts out under
## them -- through them, if they're still there -- on an arc leap_height
## high, nose first, landing land_beyond past them; dives back in, comes
## round (dive_time) and goes again.
@export var leap_height: float = 4.5
@export var leap_lead: float = 0.6
@export var aim_ahead: float = 0.3
@export var land_beyond: float = 4.0
@export var dive_depth: float = 4.0
@export var windup_time: float = 0.5
@export var rise_speed: float = 16.0
@export var dive_time: float = 1.0

@export_group("Attack")
@export var bite_damage: float = 18.0
## Its jaws reach this far (share of its length) ahead of its head.
@export var bite_reach: float = 0.25
@export var bite_interval: float = 1.0
@export var knockback: float = 8.0

@export_group("Look")
@export var dirt_color: Color = Color(0.13, 0.09, 0.06)
@export var blood_color: Color = Color(0.55, 0.03, 0.03)
@export var trail_interval: float = 0.2
@export var rumble_range: float = 9.0
@export var rumble: float = 0.5
@export var breach_shake: float = 3.0
@export var shake_range: float = 16.0
## Dead: how long before it sinks away into the ground.
@export var corpse_time: float = 6.0
@export var breach_sound: SoundEvent
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent
## The rumble while it hunts under the floor (empty = the placeholder).
@export var rumble_stream: AudioStream
@export var rumble_volume_db: float = -4.0

var home := Vector3.ZERO
var target: Node3D

var _state := State.LURK
var _phase := Phase.TUNNEL
var _phase_left := 0.0
var _leap_from := Vector3.ZERO
## The model's own forward/up at rest, and its head (root bone) in its own
## space: the whole model is turned to face where it's going every tick, so
## it always reads as nose-first even before the spine bends.
var _rest_frame := Basis.IDENTITY
var _root_in_model := Vector3.ZERO
var _facing := Vector3.FORWARD
var _vel := Vector3.ZERO
var _ground_y := 0.0
var _inside := true
var _time := 0.0
var _lurk_angle := 0.0
var _retarget := 0.0
var _bite_left := 0.0
var _trail_left := 0.0
var _dead_left := 0.0
## The head's path, newest first, a point every _trail_step meters.
var _trail := PackedVector3Array()
var _trail_step := 0.2
## Where each spine joint is in the world this tick (head first).
var _joints := PackedVector3Array()

# The model.
var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _anim_names := {} # "glide"/"bite"/... -> the clip's name in the model
var _chain := PackedInt32Array() # spine bones, head first
var _child_offset: Array[Vector3] = [] # next joint in each bone's frame
var _rest_local: Array[Transform3D] = []
var _bone_length := PackedFloat32Array() # meters
var _scale := 1.0
var _lod_timer := 0.0
var _bend_every := 1
var _bend_frame := 0
## Entirely under the floor: not drawn, not bent (nobody can see it).
var _buried := false
## Lurking with nobody near: it thinks every few ticks instead of every one.
var _idle_ticks := 0
var _idle_delta := 0.0
var _fx: WormFX

@onready var health: Health = $Health
@onready var _body: AnimatableBody3D = $Body


func _ready() -> void:
	add_to_group("enemies")
	home = global_position
	var floor_hit := _static_ray(home + Vector3.UP * 2.0, home + Vector3.DOWN * 50.0)
	_ground_y = (floor_hit.position as Vector3).y if not floor_hit.is_empty() else home.y
	home.y = _ground_y
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_body.top_level = true
	_body.sync_to_physics = false
	_lurk_angle = randf() * TAU
	_fx = WormFX.new()
	_fx.size = 0.55
	_fx.rumble_stream = rumble_stream
	_fx.rumble_volume_db = rumble_volume_db
	add_child(_fx)
	global_position = Vector3(home.x, _ground_y - lurk_depth, home.z)
	_vel = Vector3.FORWARD.rotated(Vector3.UP, _lurk_angle) * max_speed * lurk_speed
	_build_model()
	_build_hitboxes()
	_update_joints()
	_place_model()
	_ignore_players()


# ---- The model --------------------------------------------------------------

func _build_model() -> void:
	_model = model_scene.instantiate() as Node3D
	add_child(_model)
	_model.top_level = true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # cheap: the dirt sells it
		for surface in mesh.get_surface_override_material_count():
			var original := mesh.get_active_material(surface)
			var label := original.resource_name.to_lower() if original else ""
			if original is BaseMaterial3D and (original as BaseMaterial3D).albedo_texture:
				label += (original as BaseMaterial3D).albedo_texture.resource_path.to_lower()
			var teeth := "diente" in label
			if teeth and teeth_material:
				mesh.set_surface_override_material(surface, teeth_material)
			elif not teeth and body_material:
				mesh.set_surface_override_material(surface, body_material)
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Deepmaw: no skeleton in the model.")
		return
	_skeleton = skeletons[0] as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in _anim.get_animation_list():
			var lower := String(clip).to_lower()
			for key in ["glide", "bite", "jump attack", "tail attack", "hit reaction", "dead"]:
				if lower.ends_with(key):
					_anim_names[key] = clip
		_play("glide", true)
	# The spine: from "Bone" (the head, where the jaws hang) down its only
	# child each time to the tail.
	var bone := _skeleton.find_bone("Bone")
	if bone < 0:
		push_warning("Deepmaw: the model has no 'Bone' (head) bone.")
		return
	while bone >= 0:
		_chain.append(bone)
		_rest_local.append(_skeleton.get_bone_rest(bone))
		var children := _skeleton.get_bone_children(bone)
		bone = children[0] if not children.is_empty() else -1
	# Measured at the model's own size, then sized to body_length.
	var to_world := _skeleton.global_transform
	var natural := 0.0
	for i in _chain.size():
		var here := to_world * _skeleton.get_bone_global_rest(_chain[i]).origin
		var next_origin: Vector3
		if i + 1 < _chain.size():
			_child_offset.append(_rest_local[i + 1].origin)
			next_origin = to_world * _skeleton.get_bone_global_rest(_chain[i + 1]).origin
		else:
			# The tail bone: as long as the one before it.
			var previous := _child_offset[i - 1] if i > 0 else Vector3.UP
			_child_offset.append(previous)
			next_origin = to_world * (_skeleton.get_bone_global_rest(_chain[i]) * previous)
		var length := here.distance_to(next_origin)
		_bone_length.append(length)
		natural += length
	_scale = body_length / maxf(natural, 0.0001)
	# Its rest pose's nose-to-tail line and its head, in the model's own space
	# (measured at the identity transform it was added with).
	var to_model := _model.global_transform.affine_inverse() * _skeleton.global_transform
	_root_in_model = to_model * _skeleton.get_bone_global_rest(_chain[0]).origin
	var tail_in_model := to_model * _skeleton.get_bone_global_rest(_chain[_chain.size() - 1]).origin
	_rest_frame = _frame(_root_in_model - tail_in_model, Vector3.UP)
	_model.scale = Vector3.ONE * _scale
	for i in _bone_length.size():
		_bone_length[i] *= _scale
	# It moves far from where its mesh was modelled: never cull it by that.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var reach := body_length * 2.0 / _scale
		(node as MeshInstance3D).custom_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	var bend := DeepmawBend.new()
	bend.worm = self
	_skeleton.add_child(bend)


func _build_hitboxes() -> void:
	for i in hitbox_count:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = body_length * hitbox_radius * (1.0 - 0.4 * float(i) / maxf(hitbox_count - 1, 1))
		shape.shape = sphere
		_body.add_child(shape)


func _play(key: String, loop: bool) -> void:
	if _anim == null or not _anim_names.has(key):
		return
	var clip: StringName = _anim_names[key]
	_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(clip, 0.15)


## The spine laid along the head's path: each bone turned (from its rest
## pose) to point at the next joint down the path, keeping its belly toward
## the ground. Called by DeepmawBend after the animation has posed it.
func bend_spine(skeleton: Skeleton3D) -> void:
	if _chain.is_empty() or _joints.size() < _chain.size() + 1 or _bend_every <= 0 or _buried:
		return
	_bend_frame += 1
	if _bend_frame % _bend_every != 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var up := (to_skeleton.basis * Vector3.UP).normalized()
	var parent := Transform3D.IDENTITY
	var root_parent := skeleton.get_bone_parent(_chain[0])
	if root_parent >= 0:
		parent = skeleton.get_bone_global_pose(root_parent)
	for i in _chain.size():
		var rest_global := parent * _rest_local[i]
		if i == 0:
			rest_global.origin = to_skeleton * _joints[0] # the head goes where the head is
		var was := rest_global.basis * _child_offset[i]
		var wants := to_skeleton * _joints[i + 1] - rest_global.origin
		if was.length_squared() < 0.0000001 or wants.length_squared() < 0.0000001:
			parent = rest_global
			continue
		var turn := _frame(wants, up) * _frame(was, up).inverse()
		var turned := Basis(turn.get_rotation_quaternion()) * rest_global.basis
		var local := parent.affine_inverse() * Transform3D(turned, rest_global.origin)
		skeleton.set_bone_pose_rotation(_chain[i], local.basis.get_rotation_quaternion())
		if i == 0:
			skeleton.set_bone_pose_position(_chain[i], local.origin)
		parent = Transform3D(turned, rest_global.origin)


## An orthonormal frame pointing along `direction`, rolled to keep `up` up.
static func _frame(direction: Vector3, up: Vector3) -> Basis:
	var z := direction.normalized()
	var side := up.cross(z)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT.cross(z) if absf(z.x) < 0.9 else Vector3.FORWARD.cross(z)
	var x := side.normalized()
	return Basis(x, z.cross(x), z)


# ---- Moving (host) ----------------------------------------------------------

func _process(delta: float) -> void:
	# Spine LOD: far away it bends less often; out of sight range, not at all.
	_lod_timer -= delta
	if _lod_timer > 0.0:
		return
	_lod_timer = 0.3
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera else 0.0
	_bend_every = 1 if distance < bend_full_distance else (4 if distance < bend_cull_distance else 0)


func _physics_process(delta: float) -> void:
	_time += delta
	if _state == State.DEAD:
		_sink(delta)
		return
	if not multiplayer.is_server():
		return
	# Lurking with no player anywhere near its ground: a third of the ticks.
	if _state == State.LURK and not _player_near(guard_range * 2.0):
		_idle_ticks += 1
		_idle_delta += delta
		if _idle_ticks % 3 != 0:
			return
		delta = _idle_delta
	_idle_delta = 0.0
	_bite_left = maxf(_bite_left - delta, 0.0)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		_look_out()
		_ignore_players()
	var head := global_position
	var was_inside := _inside
	_inside = _in_ground(head)
	_update_phase(head, delta)
	var hunting := _state == State.HUNT
	if hunting and _phase == Phase.AIR:
		_vel.y -= air_gravity * delta # the arc is set: no control up there
	elif hunting and _phase == Phase.RISE:
		_vel = _vel.move_toward((_leap_from - head).normalized() * rise_speed, rise_speed * 4.0 * delta)
	elif _inside:
		var speed := max_speed if hunting else max_speed * lurk_speed
		_vel = _vel.move_toward((_goal(head, delta) - head).normalized() * speed, acceleration * delta)
	else:
		_vel.y -= air_gravity * delta
	if head.y < _ground_y - max_depth:
		_vel.y = maxf(_vel.y, 2.0)
	if not (hunting and _phase == Phase.AIR):
		_vel = _vel.limit_length(maxf(max_speed, rise_speed) * 1.2)
	var new_head := head + _vel * delta
	if was_inside != _inside:
		_breach_fx(head, new_head, _inside)
		if not _inside:
			_play("jump attack", false) # bursting out at you
		else:
			_play("glide", true)
	global_position = new_head
	_update_joints()
	_place_model()
	_trail_fx(delta)
	_try_bite()
	_fx.follow(new_head, _vel, _ground_y, lurk_depth + 1.5, body_length * hitbox_radius, new_head.y < _ground_y and _state == State.HUNT)
	# Extras: tremors under the floor while hunting, dirt shedding off it as
	# it flies. (No drool or spit: that's the boss's alone.)
	if new_head.y < _ground_y:
		if _state == State.HUNT:
			_fx.tremor(Vector3(new_head.x, _ground_y, new_head.z), delta)
	elif _phase == Phase.AIR:
		_fx.shed(_joints, _ground_y, delta)


## The head's path, kept a body's length long, and each spine joint placed
## along it (plus a swimming wiggle), head first.
func _update_joints() -> void:
	var head := global_position
	if _trail.is_empty() or _trail[0].distance_to(head) >= _trail_step:
		_trail.insert(0, head)
	else:
		_trail[0] = head
	var keep := int(body_length * 1.5 / _trail_step) + 4
	if _trail.size() > keep:
		_trail.resize(keep)
	_joints.resize(_chain.size() + 1)
	var behind := -_vel.normalized() if _vel.length_squared() > 0.01 else Vector3.BACK
	var along := 0.0
	for i in _chain.size() + 1:
		var point := _point_back(along, behind)
		# Swimming: a wave running down the body, growing toward the tail.
		var t := along / maxf(body_length, 0.01)
		var forward := (_point_back(along - 0.2, behind) - _point_back(along + 0.2, behind))
		var side := forward.cross(Vector3.UP)
		if side.length_squared() > 0.0001:
			point += side.normalized() * sin(_time * wiggle_speed * TAU - t * 5.0) * wiggle * body_length * t
		_joints[i] = point
		if i < _bone_length.size():
			along += _bone_length[i]
	# Buried: every joint under the floor -- hide it (and its skinning).
	var buried := true
	for joint in _joints:
		if joint.y > _ground_y - body_length * hitbox_radius * 1.5:
			buried = false
			break
	if buried != _buried and _model:
		_buried = buried
		_model.visible = not buried
	# Hitboxes down the body.
	_body.global_transform = Transform3D(Basis.IDENTITY, head)
	var shapes := _body.get_children()
	for k in shapes.size():
		var index := int(float(k) / maxf(shapes.size() - 1, 1) * (_joints.size() - 1))
		(shapes[k] as CollisionShape3D).position = _joints[index] - head


## The point `distance` meters back along the head's path (straight on
## behind it past the end of what it's swum so far).
func _point_back(distance: float, behind: Vector3) -> Vector3:
	if _trail.is_empty():
		return global_position + behind * distance
	if distance <= 0.0:
		return _trail[0] - behind * distance
	var left := distance
	for i in range(1, _trail.size()):
		var step := _trail[i - 1].distance_to(_trail[i])
		if step >= left and step > 0.0:
			return _trail[i - 1].lerp(_trail[i], left / step)
		left -= step
	return _trail[_trail.size() - 1] + behind * left


## Turned to face where it's going (nose first), its head on its head.
func _place_model() -> void:
	if _model == null:
		return
	if _vel.length_squared() > 0.25:
		_facing = _facing.slerp(_vel.normalized(), 0.35).normalized()
	var turn := _frame(_facing, Vector3.UP) * _rest_frame.inverse()
	var rig := turn.scaled(Vector3.ONE * _scale)
	_model.global_transform = Transform3D(rig, global_position - rig * _root_in_model)


## The attack cycle (see Leap).
func _update_phase(head: Vector3, delta: float) -> void:
	_phase_left -= delta
	if _state != State.HUNT or not is_instance_valid(target):
		if _phase != Phase.AIR:
			_phase = Phase.TUNNEL
		return
	match _phase:
		Phase.TUNNEL:
			_plan_leap(head)
			var under := Vector3(_leap_from.x, head.y, _leap_from.z)
			if head.distance_to(under) < 1.5 and head.y < _ground_y - 0.4:
				_phase = Phase.WINDUP
				_phase_left = windup_time
		Phase.WINDUP:
			_plan_leap(head)
			_fx.show_cracks(_leap_from, 0.3 + 0.7 * (1.0 - clampf(_phase_left / maxf(windup_time, 0.01), 0.0, 1.0)))
			if _phase_left <= 0.0:
				_phase = Phase.RISE
		Phase.RISE:
			_plan_leap(head)
			if not _inside or head.y > _ground_y + 0.8:
				_erupt(head)
		Phase.AIR:
			if _inside and _vel.y < 0.0:
				_phase = Phase.DIVE
				_phase_left = dive_time
		Phase.DIVE:
			if _phase_left <= 0.0:
				_phase = Phase.TUNNEL


## Where to burst out: leap_lead short of where its prey will be.
func _plan_leap(head: Vector3) -> void:
	var prey := _predicted_prey()
	var approach := Vector3(prey.x - head.x, 0.0, prey.z - head.z)
	approach = approach.normalized() if approach.length_squared() > 0.01 else Vector3(_vel.x, 0.0, _vel.z).normalized()
	_leap_from = prey - approach * leap_lead


func _predicted_prey() -> Vector3:
	var prey := target.global_position
	var moving = target.get("velocity")
	if moving is Vector3:
		prey += Vector3((moving as Vector3).x, 0.0, (moving as Vector3).z) * aim_ahead
	return Vector3(prey.x, _ground_y, prey.z)


## Out of the ground on the arc through its prey: up at sqrt(2 g h), across
## to land land_beyond past them.
func _erupt(head: Vector3) -> void:
	_phase = Phase.AIR
	var rise := sqrt(2.0 * air_gravity * maxf(leap_height, 0.5))
	var time_to_top := rise / air_gravity
	var prey := _predicted_prey()
	var gap := Vector3(prey.x - head.x, 0.0, prey.z - head.z)
	var onward := gap.normalized() if gap.length_squared() > 0.01 else Vector3(_vel.x, 0.0, _vel.z).normalized()
	var across := (gap + onward * land_beyond) / (time_to_top * 2.0)
	_vel = Vector3(across.x, rise, across.z)
	_fx.fade_cracks(1.5)
	WormFX.punch(get_tree(), head, 4.0, shake_range)


func _goal(head: Vector3, delta: float) -> Vector3:
	if _state == State.HUNT and is_instance_valid(target):
		match _phase:
			Phase.WINDUP:
				return Vector3(_leap_from.x, _ground_y - dive_depth, _leap_from.z)
			Phase.DIVE:
				var on := Vector3(_vel.x, 0.0, _vel.z).normalized() * 4.0
				return Vector3(head.x + on.x, _ground_y - lurk_depth - 0.5, head.z + on.z)
		return Vector3(_leap_from.x, _ground_y - lurk_depth, _leap_from.z)
	# Lurking: circling under home.
	_lurk_angle += delta * max_speed * lurk_speed / maxf(lurk_radius, 0.5)
	return Vector3(home.x, _ground_y - lurk_depth, home.z) + Vector3.FORWARD.rotated(Vector3.UP, _lurk_angle) * lurk_radius


## A player within guard_range of home: hunt them. Gone past 1.5x: back to lurking.
func _look_out() -> void:
	if guard_node != null:
		if is_instance_valid(guard_node):
			var at: Vector3 = guard_node.call("ground_position") if guard_node.has_method("ground_position") else guard_node.global_position
			home = Vector3(at.x, _ground_y, at.z)
		else:
			guard_node = null # what it guarded is dead: it guards where it is
	if _state == State.HUNT and (not Factions.is_alive_target(target) \
			or _flat(target.global_position, home) > guard_range * 1.5):
		target = null
		_state = State.LURK
	if _state == State.LURK:
		var best_distance := guard_range
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as Node3D
			if player and Factions.is_alive_target(player) and _flat(player.global_position, home) < best_distance:
				best_distance = _flat(player.global_position, home)
				target = player
		if target:
			_state = State.HUNT


func _try_bite() -> void:
	if _bite_left > 0.0 or not is_instance_valid(target) or _inside:
		return
	var jaws := global_position + _vel.normalized() * body_length * bite_reach * 0.5
	var middle := Factions.aim_point(target)
	if jaws.distance_to(middle) > body_length * bite_reach + 0.4:
		return
	_bite_left = bite_interval
	_play("bite", false)
	var player_health := target.get_node_or_null("Health") as Health
	if player_health:
		player_health.take_damage(bite_damage, Health.NO_ATTACKER)
	var away := middle - global_position
	away.y = 0.0
	if target.has_method("shove"):
		target.call("shove", (away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD) * knockback + Vector3.UP * knockback * 0.5)
	SoundPlayer.play_3d(bite_sound, jaws, get_tree().current_scene)
	_fx.bite_spray(jaws, (middle - jaws).normalized(), false) # gore, no spit


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


# ---- Effects (the BurrowWorm's) ---------------------------------------------

func _breach_fx(from: Vector3, to: Vector3, entering: bool) -> void:
	var world := get_tree().current_scene
	var hit := _static_ray(from, to + (to - from).normalized() * 0.5) if entering \
			else _static_ray(to, from - (to - from).normalized() * 0.5)
	var at := Vector3(to.x, _ground_y, to.z)
	var normal := Vector3.UP
	if not hit.is_empty():
		at = hit.position
		normal = hit.normal
	_fx.burst(at, normal)
	BloodFX.spawn_splatter(world, at + normal * 0.01, normal, body_length * 0.35, dirt_color)
	BloodFX.spawn_impact(world, at, normal, dirt_color.lightened(0.15), 2.5)
	SoundPlayer.play_3d(breach_sound, at, world)
	_shake_near(at, breach_shake, shake_range)


func _trail_fx(delta: float) -> void:
	var head := global_position
	if head.y >= _ground_y or head.y < _ground_y - lurk_depth - 1.0 or _state != State.HUNT:
		return
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = trail_interval
	var surface := Vector3(head.x, _ground_y + 0.05, head.z)
	BloodFX.spawn_impact(get_tree().current_scene, surface, Vector3.UP, dirt_color, 0.6)
	_shake_near(surface, rumble, rumble_range)


func _shake_near(at: Vector3, strength: float, within: float) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < within and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).shake(strength * (1.0 - distance / within))


# ---- Hurt and dying ---------------------------------------------------------

func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state == State.DEAD:
		return
	if _model:
		HitFlash.flash(_model)
	if _anim and _anim_names.has("hit reaction") and _anim.current_animation == _anim_names.get("glide", &""):
		_play("hit reaction", false)
	if _state == State.LURK and multiplayer.is_server():
		_look_out() # shot from up there: it comes for you (if you're on its ground)


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	_state = State.DEAD
	_fx.silence()
	_dead_left = corpse_time
	_body.collision_layer = 0
	_play("dead", false)
	var world := get_tree().current_scene
	for i in range(0, _joints.size(), 2):
		if _joints[i].y > _ground_y - 0.3:
			BloodFX.spawn_impact(world, _joints[i], Vector3.UP, blood_color, 1.5)
	SoundPlayer.play_3d(death_sound, global_position, world)


## Dead: it falls if it was out of the ground, lies there, then sinks away.
func _sink(delta: float) -> void:
	_dead_left -= delta
	if not _inside and global_position.y > _ground_y + 0.3:
		_vel.y -= air_gravity * delta
		global_position += _vel * delta
		_update_joints()
	elif _dead_left < 2.0:
		global_position += Vector3.DOWN * delta * 1.5
		_trail = PackedVector3Array() # sinks straight down as one
		_update_joints()
	_place_model()
	if _dead_left <= 0.0:
		queue_free()


func _ignore_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PhysicsBody3D
		if player:
			_body.add_collision_exception_with(player)


func _player_near(within: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		if _flat((node as Node3D).global_position, home) < within:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _static_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	if is_instance_valid(_body):
		exclude.append(_body.get_rid())
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D):
			return hit
		exclude.append(hit.rid)
	return {}
