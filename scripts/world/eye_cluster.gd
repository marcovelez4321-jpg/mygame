class_name EyeCluster
extends Node3D

## A cluster of eyeballs planted in the ground (the sewer/hive land): fleshy
## sockets with an eye in each, lids shut. When a player comes within
## open_range they open, one after another, and every eye turns to follow
## the nearest player -- stalking them, never moving from the spot -- and
## blinks now and then. Once nobody's near they drift shut again, slowly.
## Look only, so each player's game runs its own (it watches whichever
## player is nearest it, the same in every game); EyeScatter grows them.

## Eyes in the cluster, and how far from its middle they grow (metres).
@export var eye_count: int = 6
@export var spread: float = 1.2
## Each eye's size (radius, metres): every one rolls its own.
@export var eye_size_min: float = 0.14
@export var eye_size_max: float = 0.42
## A player this close and they open; how fast they open (per second, each
## eye a little after the last) and close (slowly, once nobody's near).
@export var open_range: float = 25.0
@export var open_speed: float = 2.5
@export var close_speed: float = 0.35
## How quickly an eye swings onto its target (higher = snappier), and the
## little darting glances it makes round it (degrees).
@export var turn_speed: float = 5.0
@export var dart_degrees: float = 4.0
## The colour of the irises (each eye a little different).
@export var iris_color: Color = Color(0.85, 0.65, 0.1)
## Seeds the cluster's look (sizes, places): EyeScatter sets it from the
## world, so every player's game grows the same cluster.
@export var look_seed: int = 0

const GROWTH_SHADER := preload("res://shaders/alien_growth.gdshader")
## How far the lids swing back open (radians).
const LID_OPEN := 1.25

static var _material: ShaderMaterial
static var _socket_mesh: ArrayMesh
static var _lid_mesh: ArrayMesh
static var _ball_meshes := {}

var _eyes: Array[Eye] = []
var _target: Node3D
var _scan_left := 0.0

## Something big coming (WormDirector's build-up): every cluster within
## _stare_reach of _stare_point opens and stares at it until _stare_until
## (msec), whoever's near.
static var _stare_point := Vector3.ZERO
static var _stare_reach := 0.0
static var _stare_until := 0


## Every cluster within `reach` of `point` stares at it for `seconds`.
static func stare(point: Vector3, reach: float, seconds: float) -> void:
	_stare_point = point
	_stare_reach = reach
	_stare_until = Time.get_ticks_msec() + int(seconds * 1000.0)


class Eye:
	var pivot: Node3D
	var upper: Node3D
	var lower: Node3D
	## How open (0-1), and how long until this eye starts opening.
	var open := 0.0
	var delay := 0.0
	var blink_left := 0.0
	var next_blink := 3.0
	var dart := Vector3.ZERO
	var next_dart := 0.0


func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = look_seed
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = GROWTH_SHADER
		_material.set_shader_parameter("glow_color", Color(1.0, 0.85, 0.3))
		_material.set_shader_parameter("sway_amount", 0.0)
	for i in eye_count:
		_eyes.append(_grow_eye(random, i))


## One eye: a flesh socket on the ground, the ball sitting up out of it, its
## two lids (shut) on the ball.
func _grow_eye(random: RandomNumberGenerator, index: int) -> Eye:
	var radius := random.randf_range(eye_size_min, eye_size_max)
	var angle := random.randf() * TAU
	var out := Vector2.from_angle(angle) * sqrt(random.randf()) * spread if index > 0 else Vector2.ZERO
	var base := Node3D.new()
	base.position = Vector3(out.x, 0.0, out.y)
	add_child(base)
	_place_on_ground(base)
	var socket := MeshInstance3D.new()
	socket.mesh = _socket()
	socket.material_override = _material
	socket.scale = Vector3(radius * 1.5, radius * 0.7, radius * 1.5)
	socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(socket)
	var eye := Eye.new()
	eye.pivot = Node3D.new()
	eye.pivot.position = Vector3.UP * radius * 0.75
	eye.pivot.rotation.y = random.randf() * TAU
	eye.pivot.scale = Vector3.ONE * radius
	base.add_child(eye.pivot)
	var ball := MeshInstance3D.new()
	var tint := iris_color.lerp(Color(random.randf(), random.randf() * 0.5, 0.05), 0.25)
	ball.mesh = _ball(index % 3, tint)
	ball.material_override = _material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.pivot.add_child(ball)
	eye.upper = _lid(eye.pivot, 1.0)
	eye.lower = _lid(eye.pivot, -1.0)
	eye.delay = random.randf_range(0.0, 0.8) # they open one after another
	eye.next_blink = random.randf_range(2.0, 6.0)
	return eye


func _lid(pivot: Node3D, side: float) -> Node3D:
	var lid := MeshInstance3D.new()
	lid.mesh = _lid_shell()
	lid.material_override = _material
	lid.scale = Vector3(1.0, side, 1.0) # the lower lid is the upper one flipped
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(lid)
	return lid


## Sits a node on the ground under it (the open world's ground or a level's
## floor), standing up out of it.
func _place_on_ground(node: Node3D) -> void:
	var top := node.global_position + Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 8.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and LevelGeometry.is_static(hit.collider):
		node.global_position = (hit.position as Vector3) + Vector3.DOWN * 0.03


func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.25
		_target = _nearest_player()
	var look := Factions.aim_point(_target) + Vector3.UP * 0.5 if _target else Vector3.INF # their face
	if Time.get_ticks_msec() < _stare_until and global_position.distance_to(_stare_point) < _stare_reach:
		look = _stare_point
	var waking := look.is_finite()
	for eye in _eyes:
		_update_eye(eye, waking, look, delta)


func _update_eye(eye: Eye, waking: bool, look: Vector3, delta: float) -> void:
	# Lids: open one after another for a player near, drifting shut once none is.
	if waking:
		eye.delay -= delta
		if eye.delay <= 0.0:
			eye.open = minf(eye.open + open_speed * delta, 1.0)
	else:
		eye.delay = randf_range(0.0, 0.8)
		eye.open = maxf(eye.open - close_speed * delta, 0.0)
	var shown := eye.open
	if eye.open >= 1.0:
		eye.next_blink -= delta
		if eye.next_blink <= 0.0:
			eye.blink_left = 0.18
			eye.next_blink = randf_range(2.5, 7.0)
	if eye.blink_left > 0.0:
		eye.blink_left -= delta
		shown *= absf(eye.blink_left / 0.09 - 1.0) # shut and open again
	var angle := LID_OPEN * shown
	eye.upper.rotation.x = angle # its front edge swings up and back
	eye.lower.rotation.x = -angle # ...and the lower one's down and back
	if not waking or eye.open <= 0.0:
		return
	# Stalking: turn onto the player, with little darting glances round them.
	eye.next_dart -= delta
	if eye.next_dart <= 0.0:
		eye.next_dart = randf_range(0.4, 1.8)
		eye.dart = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * deg_to_rad(dart_degrees)
	var from := eye.pivot.global_position
	var to := look
	if from.distance_squared_to(to) < 0.01:
		return
	var want := Basis.looking_at(to - from, Vector3.UP) * Basis.from_euler(eye.dart)
	var size := eye.pivot.global_basis.get_scale()
	var now := eye.pivot.global_basis.orthonormalized().get_rotation_quaternion()
	var turned := now.slerp(want.get_rotation_quaternion(), 1.0 - exp(-turn_speed * delta))
	eye.pivot.global_basis = Basis(turned).scaled(size)


## The nearest living player within open_range, or null.
func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := open_range
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


# ---- Meshes (vertex coloured, the growths' look: alien_growth.gdshader) ----

## The eyeball, looking down -Z: a black pupil, an iris ring (faintly
## glowing), and bloodshot yellowed white round the rest. `variant` changes
## where its veins run.
static func _ball(variant: int, iris: Color) -> ArrayMesh:
	var key := "%d:%s" % [variant, iris.to_html()]
	if _ball_meshes.has(key):
		return _ball_meshes[key]
	var random := RandomNumberGenerator.new()
	random.seed = variant * 977 + 13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rings round the front: pupil, iris, iris edge, then the white.
	var latitudes := [0.0, 0.2, 0.45, 0.62, 0.95, 1.35, 1.9, 2.5, PI]
	var sides := 10
	var white := Color(0.82, 0.78, 0.62)
	var vein := Color(0.62, 0.1, 0.08)
	for r in latitudes.size() - 1:
		var color: Color
		var glow := 0.0
		if r == 0:
			color = Color(0.02, 0.01, 0.01)
		elif r == 1:
			color = iris
			glow = 0.5
		elif r == 2:
			color = iris.darkened(0.45)
			glow = 0.2
		for s in sides:
			var face := color
			if r >= 3: # bloodshot: some faces reddened, more toward the back
				face = white.lerp(vein, clampf(random.randf() * 0.9 * (float(r) / latitudes.size()) + (0.35 if random.randf() < 0.2 else 0.0), 0.0, 1.0))
			var a0: float = latitudes[r]
			var a1: float = latitudes[r + 1]
			var b0 := TAU * s / sides
			var b1 := TAU * (s + 1) / sides
			var p := [_sphere(a0, b0), _sphere(a0, b1), _sphere(a1, b1), _sphere(a1, b0)]
			_tri(st, p[0], p[1], p[2], face, glow)
			_tri(st, p[0], p[2], p[3], face, glow)
	st.generate_normals()
	var mesh := st.commit()
	_ball_meshes[key] = mesh
	return mesh


## The upper lid: a shell over the top half of the ball, a little bigger
## than it (the lower lid is it flipped).
static func _lid_shell() -> ArrayMesh:
	if _lid_mesh:
		return _lid_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flesh := Color(0.38, 0.22, 0.2)
	var rim := Color(0.55, 0.28, 0.25)
	var rings := 4
	var sides := 10
	for r in rings:
		for s in sides:
			var l0 := PI * 0.5 * r / rings
			var l1 := PI * 0.5 * (r + 1) / rings
			var b0 := TAU * s / sides
			var b1 := TAU * (s + 1) / sides
			var p := [_shell(l0, b0), _shell(l0, b1), _shell(l1, b1), _shell(l1, b0)]
			var color := rim if r == 0 else flesh
			_tri(st, p[0], p[1], p[2], color, 0.0)
			_tri(st, p[0], p[2], p[3], color, 0.0)
	st.generate_normals()
	_lid_mesh = st.commit()
	return _lid_mesh


## The fleshy mound each eye sits in: a squashed, lumpy dome.
static func _socket() -> ArrayMesh:
	if _socket_mesh:
		return _socket_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flesh := Color(0.30, 0.17, 0.15)
	var wet := Color(0.45, 0.24, 0.2)
	var rings := 3
	var sides := 9
	for r in rings:
		for s in sides:
			var l0 := PI * 0.5 * r / rings
			var l1 := PI * 0.5 * (r + 1) / rings
			var b0 := TAU * s / sides
			var b1 := TAU * (s + 1) / sides
			var p := [_dome(l0, b0), _dome(l0, b1), _dome(l1, b1), _dome(l1, b0)]
			var color := flesh.lerp(wet, float(r) / rings)
			_tri(st, p[0], p[1], p[2], color, 0.0)
			_tri(st, p[0], p[2], p[3], color, 0.0)
	st.generate_normals()
	_socket_mesh = st.commit()
	return _socket_mesh


## A point on the unit ball `angle` off its front (-Z), `around` it.
static func _sphere(angle: float, around: float) -> Vector3:
	return Vector3(sin(angle) * cos(around), sin(angle) * sin(around), -cos(angle))


## A point on the lid shell: `latitude` up from its rim (round the ball's
## middle) to over the top, `around` it.
static func _shell(latitude: float, around: float) -> Vector3:
	return Vector3(cos(latitude) * sin(around), sin(latitude), -cos(latitude) * cos(around)) * 1.08


static func _dome(latitude: float, around: float) -> Vector3:
	var lump := 1.0 + sin(around * 3.0) * 0.08
	return Vector3(cos(latitude) * sin(around) * lump, sin(latitude), cos(latitude) * cos(around) * lump)


## A triangle in one colour (no sway: COLOR.a 0) glowing `glow` (UV2.x).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, glow: float) -> void:
	var still := color
	still.a = 0.0
	for p in [a, b, c]:
		st.set_color(still)
		st.set_uv2(Vector2(glow, 0.0))
		st.add_vertex(p)
