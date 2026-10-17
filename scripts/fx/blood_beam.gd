class_name BloodBeam
extends Node3D

## The heart's blood beam (the user's, 2026-10-17: the Avatar State's glowing
## eyes and mouth, in blood). A hole tears open on the heart's surface and
## glows white-hot for the warning (one beat: the caller's `warn`), then blood
## blasts out of it in a beam for BLAST_TIME:
##   - a near-white core inside a blood-red glow, THICKNESS across, a little
##     wider (SPREAD) at its far end, a faint haze round it;
##   - blood streaming along it (blood_beam.gdshader), droplets and red mist
##     spraying off its sides;
##   - its red light flooding the room; a splash and blood where it hits.
## It stops at whatever it hits (walls, mezzanines, pillars: you can hide).
## Caught in it: DAMAGE, and blasted backwards at PUSH m/s, once a blast.
## Rule 1 (co-op): the host fires it (Network.send_blood_beam): every game
## draws the same beam from (from, direction, warn); only the host's deals hits.

const THICKNESS := 4.0
const BLAST_TIME := 0.4
const DAMAGE := 35.0
const PUSH := 15.0
## How far it can reach with nothing in the way (m).
const MAX_REACH := 600.0
## Its far end this many times wider than at the hole.
const SPREAD := 1.3
## The white-hot core's share of its thickness.
const CORE := 0.3
## In and out: how fast it snaps to full thickness, and thins away after.
const SNAP_IN := 0.06
const FADE_OUT := 0.14
const CORE_COLOR := Color(1.0, 0.95, 0.88)
const GLOW_COLOR := Color(0.9, 0.05, 0.03)
## Its light: the hole's while it glows, and the room's while it blasts.
const WARN_LIGHT := 2.0
const BLAST_LIGHT := 9.0
const LIGHT_RANGE := 160.0
## The player's body, for "in the beam": their capsule (feet up).
const PLAYER_RADIUS := 0.4
const PLAYER_MIDDLE := 0.9
## Shaken this hard (degrees) right by it, none past SHAKE_RANGE.
const SHAKE := 2.5
const SHAKE_RANGE := 45.0

const SHADER := preload("res://shaders/blood_beam.gdshader")

var _from := Vector3.ZERO
var _direction := Vector3.FORWARD
var _length := 0.0
var _hit_normal := Vector3.UP
var _warn := 0.5
var _age := 0.0
var _decides := false
var _exclude: Array[RID] = []
var _hit_players := {}
var _fired := false
var _impact_left := 0.0

var _pivot: Node3D
var _layers: Array[ShaderMaterial] = []
var _hole: Decal
var _flare: MeshInstance3D
var _light: OmniLight3D
var _impact_light: OmniLight3D
var _spray: GPUParticles3D
var _mist: GPUParticles3D

static var _glow_texture: GradientTexture2D
static var _hole_texture: GradientTexture2D


## A beam from the heart's surface at `from`, blasting out along `direction`
## after `warn` seconds of its hole glowing. `decides`: this game deals its
## hits (the host's, or offline). `exclude`: what it passes through (the heart).
static func fire(world: Node, from: Vector3, direction: Vector3, warn: float, decides: bool, exclude: Array[RID] = []) -> BloodBeam:
	var beam := BloodBeam.new()
	beam._from = from
	beam._direction = direction.normalized()
	beam._warn = maxf(warn, 0.0)
	beam._decides = decides
	beam._exclude = exclude
	world.add_child(beam)
	beam.global_position = from
	return beam


func _ready() -> void:
	# Where it stops: the first thing in its way (from just off the heart, so
	# its own surface doesn't stop it on a game that can't exclude it).
	var query := PhysicsRayQueryParameters3D.create(_from + _direction * 0.3, _from + _direction * MAX_REACH, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_length = _from.distance_to(hit.position) if not hit.is_empty() else MAX_REACH
	_hit_normal = hit.normal if not hit.is_empty() else -_direction
	_build_hole()
	_build_beam()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.35, 0.25)
	_light.light_energy = 0.0
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = _direction * 2.0


func _process(delta: float) -> void:
	_age += delta
	var blast := _age - _warn
	if blast < 0.0:
		# The warning: the hole tearing open, glowing hotter and hotter.
		var opening := clampf(_age / maxf(_warn, 0.01), 0.0, 1.0)
		_hole.emission_energy = lerpf(0.5, 6.0, opening * opening)
		_hole.modulate.a = opening
		_set_flare(lerpf(0.5, THICKNESS * 1.2, opening), opening)
		_light.light_energy = WARN_LIGHT * opening
		_light.light_color = Color(1.0, lerpf(0.35, 0.8, opening), lerpf(0.25, 0.7, opening))
		return
	if not _fired:
		_fire()
	var thick := clampf(blast / SNAP_IN, 0.0, 1.0)
	var fade := 1.0
	if blast > BLAST_TIME:
		fade = clampf(1.0 - (blast - BLAST_TIME) / FADE_OUT, 0.0, 1.0)
		thick *= fade
		_spray.emitting = false
		_mist.emitting = false
	_pivot.basis = Basis(Quaternion(Vector3.UP, _direction)) * Basis.from_scale(Vector3(maxf(thick, 0.05), 1.0, maxf(thick, 0.05)))
	for layer in _layers:
		layer.set_shader_parameter("fade", fade)
	_hole.emission_energy = 8.0 * fade
	_set_flare(THICKNESS * lerpf(2.4, 1.6, clampf(blast / BLAST_TIME, 0.0, 1.0)), fade)
	_light.light_energy = BLAST_LIGHT * fade
	_impact_light.light_energy = BLAST_LIGHT * 0.6 * fade
	# Splashing where it hits all the while it blasts.
	if blast <= BLAST_TIME:
		_impact_left -= delta
		if _impact_left <= 0.0:
			_impact_left = 0.08
			BloodFX.spawn_impact(get_tree().current_scene, _from + _direction * _length, _hit_normal, BloodFX.BLOOD_COLOR, 2.5)
	if blast > BLAST_TIME + FADE_OUT:
		set_process(false)
		_pivot.visible = false
		_flare.visible = false
		_hole.visible = false
		# The last droplets fall, then it's gone.
		get_tree().create_timer(1.0).timeout.connect(queue_free)


func _physics_process(_delta: float) -> void:
	var blast := _age - _warn
	if not _decides or blast < 0.0 or blast > BLAST_TIME:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead() or _hit_players.has(player):
			continue
		var body := player.global_position + Vector3.UP * PLAYER_MIDDLE
		var along := clampf((body - _from).dot(_direction), 0.0, _length)
		var widening := lerpf(1.0, SPREAD, along / maxf(_length, 0.01))
		if body.distance_to(_from + _direction * along) > THICKNESS * 0.5 * widening + PLAYER_RADIUS:
			continue
		_hit_players[player] = true
		player.health.take_damage(DAMAGE, Health.NO_ATTACKER, _direction, body, 1.0)
		# Blasted backwards, off the floor (a push along the ground is eaten by it).
		var push := _direction * PUSH
		push.y = maxf(push.y, PUSH * 0.2)
		player.shove(push)
		BloodFX.spawn_impact(get_tree().current_scene, body, -_direction, BloodFX.BLOOD_COLOR, 2.0)


## The blast: in at full thickness, the spray and mist on, a splash and
## blood where it hits, your camera shaken if you're close.
func _fire() -> void:
	_fired = true
	_pivot.visible = true
	_spray.emitting = true
	_mist.emitting = true
	var world := get_tree().current_scene
	var reach := _from + _direction * _length
	if _length < MAX_REACH:
		BloodFX.spawn_splatter(world, reach, _hit_normal, THICKNESS * 0.9)
	_light.light_color = Color(1.0, 0.18, 0.12)
	var camera := get_viewport().get_camera_3d() as CameraJuice
	if camera:
		var at := camera.global_position
		var along := clampf((at - _from).dot(_direction), 0.0, _length)
		var near := at.distance_to(_from + _direction * along)
		var strength := SHAKE * clampf(1.0 - near / SHAKE_RANGE, 0.0, 1.0)
		if strength > 0.0:
			camera.shake(strength)
			camera.kick_fov(strength * 1.5)


# ---- Looks ---------------------------------------------------------------------

## The hole: glowing white-hot from inside, on whatever surface it's on (a
## decal pressed onto the heart there), and a flare of light over it.
func _build_hole() -> void:
	_hole = Decal.new()
	_hole.texture_albedo = _hole_tex()
	_hole.texture_emission = _hole_tex()
	_hole.emission_energy = 0.0
	_hole.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_hole.size = Vector3(THICKNESS * 1.4, 4.0, THICKNESS * 1.4)
	add_child(_hole)
	# A decal presses down its -Y: into the heart, against the beam.
	_hole.basis = Basis(Quaternion(Vector3.UP, _direction))
	_flare = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flare.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = _glow_tex()
	material.vertex_color_use_as_albedo = false
	_flare.material_override = material
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flare)
	_flare.position = _direction * 0.5
	_set_flare(0.0, 0.0)


func _set_flare(size: float, brightness: float) -> void:
	_flare.scale = Vector3.ONE * maxf(size, 0.01)
	(_flare.material_override as StandardMaterial3D).albedo_color = Color(1.0, 1.0, 1.0, clampf(brightness, 0.0, 1.0))


## The beam: three nested cones out from the hole (haze, glow, core), its
## spray and mist, and the light where it hits.
func _build_beam() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.basis = Basis(Quaternion(Vector3.UP, _direction))
	_pivot.visible = false
	var radius := THICKNESS * 0.5
	for layer: Array in [[radius * 1.7, GLOW_COLOR, 0.7, 4.0, 0.3], [radius, GLOW_COLOR, 2.4, 2.2, 0.7], [radius * CORE, CORE_COLOR, 3.5, 1.2, 0.25]]:
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = layer[0]
		mesh.top_radius = float(layer[0]) * SPREAD
		mesh.height = _length
		mesh.radial_segments = 16
		mesh.rings = 1
		mesh.cap_top = false
		mesh.cap_bottom = false
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("color", layer[1])
		material.set_shader_parameter("intensity", layer[2])
		material.set_shader_parameter("edge_power", layer[3])
		material.set_shader_parameter("flow_amount", layer[4])
		material.set_shader_parameter("beam_length", _length)
		_layers.append(material)
		var shape := MeshInstance3D.new()
		shape.mesh = mesh
		shape.material_override = material
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shape.position = Vector3.UP * _length * 0.5
		shape.custom_aabb = AABB(Vector3(-radius * 3.0, -_length * 0.5, -radius * 3.0), Vector3(radius * 6.0, _length, radius * 6.0))
		_pivot.add_child(shape)
	# Droplets flying off its sides the whole way along, and a red mist.
	_spray = _particles(mini(int(_length * 4.0) + 60, 600), 0.8, BloodFX.droplet_mesh(), BloodFX.BLOOD_COLOR, Vector2(3.0, 11.0), Vector3(0.0, -14.0, 0.0), Vector2(1.0, 2.5))
	_mist = _particles(mini(int(_length * 0.8) + 20, 160), 1.2, _mist_mesh(), Color(0.7, 0.04, 0.03, 0.35), Vector2(0.5, 2.5), Vector3(0.0, -1.0, 0.0), Vector2(1.5, 4.0))
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = Color(1.0, 0.15, 0.1)
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = LIGHT_RANGE * 0.4
	_impact_light.shadow_enabled = false
	add_child(_impact_light)
	_impact_light.position = _direction * maxf(_length - 2.0, 0.0)


func _particles(amount: int, lifetime: float, mesh: Mesh, color: Color, speed: Vector2, gravity: Vector3, sizes: Vector2) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.emitting = false
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-THICKNESS * 4.0, -THICKNESS * 4.0, -THICKNESS * 4.0), Vector3(THICKNESS * 8.0, _length + THICKNESS * 8.0, THICKNESS * 8.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(THICKNESS * 0.35, _length * 0.5, THICKNESS * 0.35)
	process.direction = Vector3(1.0, 0.4, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = gravity
	process.scale_min = sizes.x
	process.scale_max = sizes.y
	process.color = color
	particles.process_material = process
	_pivot.add_child(particles)
	particles.position = Vector3.UP * _length * 0.5
	return particles


static func _mist_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _glow_tex()
	quad.material = material
	return quad


## A soft round glow: white-hot middle, red, then nothing.
static func _glow_tex() -> GradientTexture2D:
	if _glow_texture == null:
		_glow_texture = _radial(PackedColorArray([Color(1.0, 0.97, 0.9, 1.0), Color(1.0, 0.4, 0.3, 0.8), Color(0.8, 0.03, 0.02, 0.35), Color(0.5, 0.0, 0.0, 0.0)]),
				PackedFloat32Array([0.0, 0.18, 0.5, 1.0]))
	return _glow_texture


## The hole torn in the heart: a white-hot middle, a red rim, gone at the edge.
static func _hole_tex() -> GradientTexture2D:
	if _hole_texture == null:
		_hole_texture = _radial(PackedColorArray([Color(1.0, 0.95, 0.85, 1.0), Color(1.0, 0.3, 0.2, 1.0), Color(0.45, 0.0, 0.0, 0.9), Color(0.2, 0.0, 0.0, 0.0)]),
				PackedFloat32Array([0.0, 0.3, 0.6, 1.0]))
	return _hole_texture


static func _radial(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
