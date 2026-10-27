class_name RedWrap
extends Node3D

## The red creep wrapping something alive (RedCreep; the user's, 2026-10-27):
## the moment its tendril touches, it's held where it stands and drained
## (DRAIN a second), while the vines climb it, coil on coil, till it's
## covered head to foot (COVER_TIME) -- then it's frozen in place, a red
## cocoon, drained on to death unless it's freed. Shooting the cocoon
## (HITS times) or burning it cuts it free; so does cutting the tendril.
## Whatever dies in it: a new bush grows from the body (RedCreep's nurseries).
## Held: a player by held_point (as a Harvestman holds you: look about, shoot
## the ropes, but no walking), frozen: no shooting either (WeaponController);
## an enemy stopped (its thinking off, pinned), frozen: its animation too.
## Rule 1 (co-op): the host holds and drains; every game draws the cocoon
## (RedCreep tells them where, how big, and when it started).

const COVER_TIME := 6.0 # (the user's)
const DRAIN := 5.0 # health a second (the user's)
const DRAIN_EVERY := 0.5
const HITS := 3
const COILS := 7
const TURNS := 2.6
const COIL_RADIUS := 0.05
const REMAKE_EVERY := 0.15

var wrap_id := 0
var target: Node3D
var patch: RedCreepPatch
var rope := -1
var height := 1.8
var radius := 0.45
var started_msec := 0
var host := true

var _director: RedCreep
var _hits := 0
var _drain_left := DRAIN_EVERY
var _frozen := false
var _remake_left := 0.0
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _was_processing := true
var _was_frozen_body := false
var _animators: Array[Node] = []
var _seed := 0


func setup(director: RedCreep, id_: int, pin: Vector3, tall: float, wide: float, start_msec: int, is_host: bool) -> void:
	_director = director
	wrap_id = id_
	height = tall
	radius = wide
	started_msec = start_msec
	host = is_host
	_seed = id_ * 31 + 7
	top_level = true
	global_position = pin
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/red_creep.gdshader")
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## Host: what it holds (from the tendril that touched it).
func hold(what: Node3D, from_patch: RedCreepPatch, from_rope: int) -> void:
	target = what
	patch = from_patch
	rope = from_rope
	var player := target as PlayerMovement
	if player:
		player.held_point = global_position + Vector3.UP * 0.9
		return
	_was_processing = target.is_physics_processing()
	target.set_physics_process(false)
	var body := target as RigidBody3D
	if body:
		_was_frozen_body = body.freeze
		body.freeze = true


## How far it's covered (0..1).
func cover() -> float:
	return clampf(float(Time.get_ticks_msec() - started_msec) / 1000.0 / COVER_TIME, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not host:
		return
	if not is_instance_valid(target) or not Factions.is_alive_target(target):
		_director.end_wrap(self, true)
		return
	# Held where it stood.
	if not target is PlayerMovement:
		target.global_position = global_position
		var character := target as CharacterBody3D
		if character:
			character.velocity = Vector3.ZERO
	else:
		(target as PlayerMovement).held_point = global_position + Vector3.UP * 0.9
	if not _frozen and cover() >= 1.0:
		_freeze()
	_drain_left -= delta
	if _drain_left <= 0.0:
		_drain_left = DRAIN_EVERY
		var health := target.get_node_or_null("Health") as Health
		if health:
			health.take_damage(DRAIN * DRAIN_EVERY)
			if health.is_dead:
				_director.end_wrap(self, true)


## Covered head to foot: frozen.
func _freeze() -> void:
	_frozen = true
	if target is PlayerMovement:
		target.set_meta(&"red_frozen", true)
		return
	for node in target.find_children("*", "AnimationPlayer", true, false) + target.find_children("*", "AnimationTree", true, false):
		_animators.append(node)
		if node is AnimationPlayer:
			(node as AnimationPlayer).speed_scale = 0.0
		elif node is AnimationTree:
			(node as AnimationTree).active = false


## A shot through it: HITS of them and it's cut free. True: it's free.
func hit() -> bool:
	_hits += 1
	return _hits >= HITS


## Host: let go (cut free, burned, or it's dead).
func release() -> void:
	if not is_instance_valid(target):
		return
	if target is PlayerMovement:
		var player := target as PlayerMovement
		player.held_point = Vector3.INF
		player.remove_meta(&"red_frozen")
	else:
		target.set_physics_process(_was_processing)
		var body := target as RigidBody3D
		if body:
			body.freeze = _was_frozen_body
		for node in _animators:
			if not is_instance_valid(node):
				continue
			if node is AnimationPlayer:
				(node as AnimationPlayer).speed_scale = 1.0
			elif node is AnimationTree:
				(node as AnimationTree).active = true
	target = null


## Whether a shot from `a` to `b` passes through the cocoon.
func crossed_by(a: Vector3, b: Vector3) -> bool:
	var foot := global_position
	var head := global_position + Vector3.UP * height * maxf(cover(), 0.3)
	var near := Geometry3D.get_closest_points_between_segments(a, b, foot, head)
	return near[0].distance_to(near[1]) < radius + 0.15


# ---- The cocoon (every game) -------------------------------------------------------------------

func _process(delta: float) -> void:
	_remake_left -= delta
	if _remake_left > 0.0:
		return
	_remake_left = REMAKE_EVERY
	var c := cover()
	if c >= 1.0 and _mesh.mesh != null and _mesh.has_meta(&"done"):
		return
	_mesh.mesh = _cocoon(c)
	if c >= 1.0:
		_mesh.set_meta(&"done", true)


## Vines coiling up round it, each from the ground up to `c` of its height
## (and over its head once it's covered), in its own space.
func _cocoon(c: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := COILS + (5 if c >= 1.0 else 0)
	for k in count:
		var start := rng.randf() * TAU
		var turns := TURNS * rng.randf_range(0.8, 1.3) * (1.0 if k % 2 == 0 else -1.0)
		var reach := clampf(c * rng.randf_range(1.0, 1.15), 0.0, 1.05)
		if k >= COILS:
			reach = 1.08 # (over the head)
		var steps := maxi(int(reach * 26.0), 2)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var frees := PackedFloat32Array()
		var alongs := PackedFloat32Array()
		var along := 0.0
		for i in steps + 1:
			var u := float(i) / steps * reach
			var a := start + u * turns * TAU
			var r := radius * (1.0 - 0.35 * pow(maxf(u - 0.8, 0.0) / 0.28, 2.0)) + 0.03 * sin(u * 23.0 + k)
			var p := Vector3(cos(a) * r, u * height, sin(a) * r)
			if k >= COILS:
				# Over the top: a loop up over the head and down the other side.
				var over := float(i) / steps
				var b := start + over * PI
				p = Vector3(cos(b) * radius * sin(over * PI) * 0.7, height * (0.75 + 0.3 * sin(over * PI)), sin(b) * radius * 0.5)
			if i > 0:
				along += p.distance_to(points[points.size() - 1])
			points.append(p)
			radii.append(COIL_RADIUS * (1.0 - 0.5 * float(i) / steps))
			frees.append(0.06)
			alongs.append(along)
		RedCreepPatch._strand(tool, points, radii, frees, alongs, rng.randf_range(0.5, 1.0))
	return tool.commit()
