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
## A body lying about (`corpse`; the user's, 2026-10-27): no holding, no
## draining -- the cocoon's laid along it where it lies (its own up along the
## body), and BURST_AFTER after it's covered a bush bursts out of it (RedCreep.
## cocoon_burst); the cocoon stays.
## Rule 1 (co-op): the host holds and drains; every game draws the cocoon
## (RedCreep tells them where, which way, how big, and when it started).

const COVER_TIME := 6.0 # (the user's)
const DRAIN := 5.0 # health a second (the user's)
const DRAIN_EVERY := 0.5
const HITS := 3
const COILS := 7
const TURNS := 2.6
const COIL_RADIUS := 0.05
## The vines over its head show once it's covered to here (of its height).
const OVER_HEAD := 1.0
## A body's cocoon: its bush bursts out this long after it's covered.
const BURST_AFTER := 20.0

var wrap_id := 0
var target: Node3D
var patch: RedCreepPatch
var rope := -1
var height := 1.8
var radius := 0.45
var started_msec := 0
var host := true
## A body's cocoon (not something alive held).
var corpse := false
var _burst := false

var _director: RedCreep
var _hits := 0
var _drain_left := DRAIN_EVERY
var _frozen := false
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _was_processing := true
var _was_frozen_body := false
var _animators: Array[Node] = []
var _seed := 0


func setup(director: RedCreep, id_: int, pin: Vector3, tall: float, wide: float, start_msec: int, is_host: bool, turn: Basis = Basis.IDENTITY) -> void:
	_director = director
	wrap_id = id_
	height = tall
	radius = wide
	started_msec = start_msec
	host = is_host
	_seed = id_ * 31 + 7
	top_level = true
	global_transform = Transform3D(turn, pin)
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/red_creep.gdshader")
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	# Made once, whole; the shader shows it climbing (grow_to: how high).
	_mesh.mesh = _cocoon()
	_mesh.set_instance_shader_parameter(&"grow_to", 0.0)


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


## Host: the body it's laid on (from the tendril that touched it).
func lay_on(body: Node3D, from_patch: RedCreepPatch, from_rope: int) -> void:
	corpse = true
	target = body
	patch = from_patch
	rope = from_rope


## Its middle (halfway along it).
func middle() -> Vector3:
	return global_position + global_basis.y * height * 0.5


## How far it's covered (0..1).
func cover() -> float:
	return clampf(float(Time.get_ticks_msec() - started_msec) / 1000.0 / COVER_TIME, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not host:
		return
	if corpse:
		# (The body may fade away inside it: the cocoon's its own.)
		if not _burst and float(Time.get_ticks_msec() - started_msec) / 1000.0 >= COVER_TIME + BURST_AFTER:
			_burst = true
			_director.cocoon_burst(self)
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
	if not is_instance_valid(target) or corpse:
		target = null
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
	var head := global_position + global_basis.y * height * maxf(cover(), 0.3)
	var near := Geometry3D.get_closest_points_between_segments(a, b, foot, head)
	return near[0].distance_to(near[1]) < radius + 0.15


# ---- The cocoon (every game) -------------------------------------------------------------------

## Climbing it as it's covered (the shader shows the vines up to there).
func _process(_delta: float) -> void:
	var c := cover()
	var shown := c * height * 1.02
	if c >= 1.0:
		shown = height * 2.0 # (and over its head)
	_mesh.set_instance_shader_parameter(&"grow_to", shown)


## Vines coiling up round it from the ground to its full height, and loops
## over its head; how far along each point is = how high it is (the vines
## over the head after everything else), in its own space.
func _cocoon() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for k in COILS + 5:
		var start := rng.randf() * TAU
		var turns := TURNS * rng.randf_range(0.8, 1.3) * (1.0 if k % 2 == 0 else -1.0)
		var over := k >= COILS
		var steps := 26
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var frees := PackedFloat32Array()
		var alongs := PackedFloat32Array()
		var reach := rng.randf_range(0.95, 1.05)
		for i in steps + 1:
			var u := float(i) / steps
			var p: Vector3
			var along: float
			if over:
				# A loop up over the head and down the other side.
				var b := start + u * PI
				p = Vector3(cos(b) * radius * sin(u * PI) * 0.7, height * (0.75 + 0.3 * sin(u * PI)), sin(b) * radius * 0.5)
				along = height * (OVER_HEAD + 0.05 + u * 0.3)
			else:
				var h := u * reach
				var a := start + h * turns * TAU
				var r := radius * (1.0 - 0.35 * pow(maxf(h - 0.8, 0.0) / 0.28, 2.0)) + 0.03 * sin(h * 23.0 + k)
				p = Vector3(cos(a) * r, h * height, sin(a) * r)
				along = p.y
			points.append(p)
			radii.append(COIL_RADIUS * (1.0 - 0.4 * u))
			frees.append(0.06)
			alongs.append(along)
		RedCreepPatch._strand(tool, points, radii, frees, alongs, rng.randf_range(0.5, 1.0))
	return tool.commit()