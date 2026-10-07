class_name WormFX
extends Node3D

## The extra show for a burrowing worm (BurrowWorm, Deepmaw), kept cheap:
##   - a mound of dirt ploughing along the floor above it while it tunnels
##     near the surface (Tremors/Dune) -- one flattened sphere;
##   - ground cracking open where it's about to erupt (a procedural crack
##     shader on one quad, worm_cracks.gdshader), fading after;
##   - slow, lingering dust clouds and a fling of rubble when it breaks the
##     surface (two dust emitters used in turn, one rubble emitter);
##   - a low rumble loop from its head while it's underground, louder the
##     closer it is (3D falloff does the "closer" part).
## Optimisation: every mesh, material and particle setup is made once and
## shared by every worm (static); a worm's emitters are only created the
## first time it breaks the surface; nothing casts shadows; no raycasts.
## Visual only -- every peer runs its own from the worm's position.

const DUST_COLOR := Color(0.36, 0.3, 0.24, 0.55)
const RUBBLE_COLOR := Color(0.17, 0.12, 0.08)
const MOUND_COLOR := Color(0.2, 0.15, 0.1)
const RUMBLE_PATH := "res://audio/sfx/worm_rumble.wav"
const SPIT_COLOR := Color(0.72, 0.68, 0.42)
const BLOOD_COLOR := Color(0.55, 0.03, 0.03)
const DIRT_COLOR := Color(0.13, 0.09, 0.06)
## Tremors (ceiling dust, props jittering) at most this often, and how far
## up a ceiling can be / how far out props feel it.
const TREMOR_INTERVAL := 0.4
const CEILING_REACH := 14.0
const PROP_REACH := 3.5
## Jaws: a drip of drool this often while it's out; dirt shed off its body
## this often while it's in the air.
const DROOL_INTERVAL := 0.3
const SHED_INTERVAL := 0.12

## How big this worm's effects are (1 = the boss).
var size := 1.0
## Set by the worm; null = the placeholder rumble (RUMBLE_PATH).
var rumble_stream: AudioStream
var rumble_volume_db := 0.0
var rumble_range := 30.0

static var _mound_mesh: SphereMesh
static var _mound_material: StandardMaterial3D
static var _crack_mesh: PlaneMesh
static var _crack_material: ShaderMaterial
static var _dust_process: ParticleProcessMaterial
static var _dust_mesh: QuadMesh
static var _rubble_process: ParticleProcessMaterial
static var _rubble_mesh: BoxMesh
static var _fall_process: ParticleProcessMaterial
static var _ring_mesh: TorusMesh
static var _ring_material: StandardMaterial3D

var _mound: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_tween: Tween
var _dust: Array[GPUParticles3D] = []
var _next_dust := 0
var _rubble: GPUParticles3D
var _rumble: AudioStreamPlayer3D
var _ring: MeshInstance3D
var _ring_tween: Tween
var _fall: GPUParticles3D
var _tremor_left := 0.0
var _drool_left := 0.0
var _shed_left := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_make_shared()
	_mound = MeshInstance3D.new()
	_mound.mesh = _mound_mesh
	_mound.material_override = _mound_material
	_mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mound.visible = false
	add_child(_mound)
	_cracks = MeshInstance3D.new()
	_cracks.mesh = _crack_mesh
	_cracks.material_override = _crack_material
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cracks.visible = false
	add_child(_cracks)
	_rumble = AudioStreamPlayer3D.new()
	var stream := rumble_stream
	if stream == null and ResourceLoader.exists(RUMBLE_PATH):
		stream = load(RUMBLE_PATH) as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_rumble.stream = stream
	_rumble.volume_db = rumble_volume_db
	_rumble.max_distance = rumble_range * size
	_rumble.unit_size = 6.0 * size
	_rumble.bus = "Enemies" if AudioServer.get_bus_index("Enemies") != -1 else "Master"
	add_child(_rumble)


## Every frame from the worm: the mound over its head while it's tunnelling
## shallow enough (bigger the shallower), and the rumble while it's under.
func follow(head: Vector3, velocity: Vector3, ground_y: float, max_depth: float, radius: float, underground: bool) -> void:
	var depth := ground_y - head.y
	var show_mound := underground and depth > 0.0 and depth < max_depth
	_mound.visible = show_mound
	if show_mound:
		var near := 1.0 - depth / max_depth
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var facing := Basis.looking_at(flat.normalized(), Vector3.UP) if flat.length_squared() > 0.01 else _mound.global_basis.orthonormalized()
		var width := radius * 2.6 * (0.6 + 0.4 * near)
		_mound.global_transform = Transform3D(facing * Basis.from_scale(Vector3(width, radius * 1.1 * near, width * 1.5)), Vector3(head.x, ground_y, head.z))
	if _rumble.stream:
		_rumble.global_position = head
		if underground and not _rumble.playing:
			_rumble.play()
		elif not underground and _rumble.playing:
			_rumble.stop()


## Dead (or gone): the rumble stops and the mound and cracks go.
func silence() -> void:
	_rumble.stop()
	_mound.visible = false
	fade_cracks(0.5)


## The ground cracking open at `at` (on the floor), `grow` 0..1.
func show_cracks(at: Vector3, grow: float) -> void:
	if _crack_tween:
		_crack_tween.kill()
		_crack_tween = null
	_cracks.visible = true
	var span := 5.0 * size
	_cracks.global_transform = Transform3D(Basis.from_scale(Vector3(span, 1.0, span)), at + Vector3.UP * 0.03)
	_cracks.set_instance_shader_parameter("grow", clampf(grow, 0.0, 1.0))
	_cracks.set_instance_shader_parameter("fade", 1.0)


## It's out: the cracks stay open a moment, then fade away.
func fade_cracks(time: float = 2.5) -> void:
	if not _cracks.visible:
		return
	if _crack_tween:
		_crack_tween.kill()
	_crack_tween = create_tween()
	_crack_tween.tween_method(func(value: float) -> void:
		_cracks.set_instance_shader_parameter("fade", value), 1.0, 0.0, time)
	_crack_tween.tween_callback(func() -> void: _cracks.visible = false)


## Breaking the surface at `at`: a slow cloud of dust and a fling of rubble.
func burst(at: Vector3, normal: Vector3) -> void:
	if _dust.is_empty():
		for i in 2:
			_dust.append(_make_emitter(_dust_process, _dust_mesh, 10, 2.8))
		_rubble = _make_emitter(_rubble_process, _rubble_mesh, 14, 1.6)
	var dust := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	for emitter: GPUParticles3D in [dust, _rubble]:
		emitter.global_transform = Transform3D(_up_basis(normal).scaled(Vector3.ONE * size), at)
		emitter.restart()


## A landing: a ring of dust tearing outward to `radius` and fading, with a
## dust cloud and rubble.
func shockwave(at: Vector3, radius: float) -> void:
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.mesh = _ring_mesh
		_ring.material_override = _ring_material
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	if _ring_tween:
		_ring_tween.kill()
	_ring.visible = true
	_ring.global_position = at + Vector3.UP * 0.15
	_ring.scale = Vector3(0.5, 1.0, 0.5)
	_ring.transparency = 0.0
	_ring_tween = create_tween()
	_ring_tween.tween_property(_ring, "scale", Vector3(radius, 1.5, radius), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ring_tween.parallel().tween_property(_ring, "transparency", 1.0, 0.45).set_ease(Tween.EASE_IN)
	_ring_tween.tween_callback(func() -> void: _ring.visible = false)
	burst(at, Vector3.UP)


## Passing under the floor at `surface` (the floor point above it): every
## TREMOR_INTERVAL, dust and pebbles shake loose from a ceiling or overhang
## above (one ray up), and loose props on the floor nearby jitter (host:
## one small sphere query -- they're physics).
func tremor(surface: Vector3, delta: float) -> void:
	_tremor_left -= delta
	if _tremor_left > 0.0:
		return
	_tremor_left = TREMOR_INTERVAL * randf_range(0.8, 1.2)
	var space := get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(surface + Vector3.UP * 2.2, surface + Vector3.UP * CEILING_REACH)
	up.collision_mask = 1
	var hit := space.intersect_ray(up)
	if not hit.is_empty() and hit.collider is StaticBody3D and (hit.normal as Vector3).y < -0.5:
		if _fall == null:
			_fall = _make_emitter(_fall_process, _rubble_mesh, 10, 1.2)
			_fall.explosiveness = 0.6
		_fall.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), (hit.position as Vector3) - Vector3.UP * 0.1)
		_fall.restart()
		BloodFX.spawn_impact(get_tree().current_scene, (hit.position as Vector3) - Vector3.UP * 0.15, Vector3.DOWN, Color(DUST_COLOR, 1.0), 0.5)
	if not multiplayer.is_server():
		return
	var sphere := SphereShape3D.new()
	sphere.radius = PROP_REACH * size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, surface + Vector3.UP * 0.5)
	query.collision_mask = 1
	for result in space.intersect_shape(query, 12):
		var prop := result.collider as RigidBody3D
		if prop == null or prop.has_method("stun") or prop.freeze:
			continue # creatures (rats, roaches) aren't props
		var kick := Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.6), randf_range(-0.6, 0.6))
		prop.apply_central_impulse(kick * prop.mass)


## A quick zoom-out punch on the camera of anyone within `within` of `at`
## (stronger closer). Static: any worm (or anything) can call it.
static func punch(tree: SceneTree, at: Vector3, amount: float, within: float) -> void:
	for node in tree.get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < within and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).kick_fov(amount * (1.0 - distance / within))


## Out of the ground: drool dripping from its jaws now and then.
func drool(jaws: Vector3, delta: float) -> void:
	_drool_left -= delta
	if _drool_left > 0.0:
		return
	_drool_left = DROOL_INTERVAL * randf_range(0.6, 1.4)
	BloodFX.spawn_impact(get_tree().current_scene, jaws, Vector3.DOWN, SPIT_COLOR, 0.25 * size + 0.15)


## A bite: gore and spit spraying out of its jaws along `forward`.
func bite_spray(jaws: Vector3, forward: Vector3, with_spit: bool = true) -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, jaws, forward, BLOOD_COLOR, 1.5 * size + 0.5)
	if with_spit:
		BloodFX.spawn_impact(world, jaws, (forward + Vector3.UP * 0.5).normalized(), SPIT_COLOR, 1.0 * size + 0.3)


## Flying out of the ground: clods of dirt shedding off its body (one of
## `points`, picked at random, each time).
func shed(points: PackedVector3Array, ground_y: float, delta: float) -> void:
	_shed_left -= delta
	if _shed_left > 0.0 or points.is_empty():
		return
	_shed_left = SHED_INTERVAL
	var at := points[randi() % points.size()]
	if at.y > ground_y + 0.3:
		BloodFX.spawn_impact(get_tree().current_scene, at, Vector3.DOWN, DIRT_COLOR, 0.5 * size + 0.25)


func _make_emitter(process: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.process_material = process
	emitter.draw_pass_1 = mesh
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.9
	emitter.emitting = false
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 12, 16))
	add_child(emitter)
	return emitter


static func _up_basis(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up))


## The shared resources, made once for every worm.
static func _make_shared() -> void:
	if _mound_mesh != null:
		return
	_mound_mesh = SphereMesh.new()
	_mound_mesh.radius = 0.5
	_mound_mesh.height = 1.0
	_mound_mesh.radial_segments = 10 # PS1-chunky, and cheap
	_mound_mesh.rings = 5
	_mound_material = StandardMaterial3D.new()
	_mound_material.albedo_color = MOUND_COLOR
	_mound_material.roughness = 1.0
	_crack_mesh = PlaneMesh.new()
	_crack_mesh.size = Vector2.ONE
	_crack_material = ShaderMaterial.new()
	_crack_material.shader = load("res://shaders/worm_cracks.gdshader")
	# Dust: soft round puffs that billow up slowly, swell and fade.
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 32
	puff.height = 32
	var puff_gradient := Gradient.new()
	puff_gradient.set_color(0, Color(1, 1, 1, 1))
	puff_gradient.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = puff_gradient
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_material.vertex_color_use_as_albedo = true
	dust_material.albedo_texture = puff
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2.ONE
	_dust_mesh.material = dust_material
	_dust_process = ParticleProcessMaterial.new()
	_dust_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_dust_process.emission_sphere_radius = 0.8
	_dust_process.direction = Vector3.UP
	_dust_process.spread = 70.0
	_dust_process.initial_velocity_min = 1.0
	_dust_process.initial_velocity_max = 3.0
	_dust_process.gravity = Vector3(0.0, 0.3, 0.0)
	_dust_process.damping_min = 1.0
	_dust_process.damping_max = 2.0
	_dust_process.scale_min = 1.5
	_dust_process.scale_max = 3.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	_dust_process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, DUST_COLOR)
	fade.set_color(1, Color(DUST_COLOR, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	_dust_process.color_ramp = fade_texture
	# Rubble: chunks of floor flung up, tumbling, falling back (and into the
	# floor, which hides them -- no collision needed).
	var rubble_material := StandardMaterial3D.new()
	rubble_material.albedo_color = RUBBLE_COLOR
	rubble_material.roughness = 1.0
	_rubble_mesh = BoxMesh.new()
	_rubble_mesh.size = Vector3(0.18, 0.12, 0.15)
	_rubble_mesh.material = rubble_material
	_rubble_process = ParticleProcessMaterial.new()
	_rubble_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_rubble_process.emission_sphere_radius = 0.6
	_rubble_process.direction = Vector3.UP
	_rubble_process.spread = 45.0
	_rubble_process.initial_velocity_min = 5.0
	_rubble_process.initial_velocity_max = 10.0
	_rubble_process.gravity = Vector3(0.0, -18.0, 0.0)
	_rubble_process.angular_velocity_min = -360.0
	_rubble_process.angular_velocity_max = 360.0
	_rubble_process.scale_min = 0.6
	_rubble_process.scale_max = 1.8
	# Ceiling dust: pebbles shaken loose, dropping.
	_fall_process = ParticleProcessMaterial.new()
	_fall_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_fall_process.emission_box_extents = Vector3(1.2, 0.05, 1.2)
	_fall_process.direction = Vector3.DOWN
	_fall_process.spread = 10.0
	_fall_process.initial_velocity_min = 0.0
	_fall_process.initial_velocity_max = 0.5
	_fall_process.gravity = Vector3(0.0, -12.0, 0.0)
	_fall_process.angular_velocity_min = -180.0
	_fall_process.angular_velocity_max = 180.0
	_fall_process.scale_min = 0.3
	_fall_process.scale_max = 0.8
	# Shockwave ring: a thin, low torus of dust, scaled out and faded per use.
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.82
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(DUST_COLOR, 0.7)
