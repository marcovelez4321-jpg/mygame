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

var _mound: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_tween: Tween
var _dust: Array[GPUParticles3D] = []
var _next_dust := 0
var _rubble: GPUParticles3D
var _rumble: AudioStreamPlayer3D


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
