class_name BurningBarrel
extends StaticBody3D

## A trash fire in a rusty barrel (the user's, 2026-10-15): the PSX pack's
## metal barrel, big bright roaring flames, sparks, a smoke column seen from
## afar, a LIGHT_RANGE warm light. Meat cooks on it, over it, or right beside
## it (FireSource).
## Where: in half the Stack's window rooms (StackBuilder -> Megastructure.
## fire_spots: their smoke pours out of the window), and one at every human
## gang's hangout (the Stack's gang spots; EncounterDirector's camps).
## Cheap: every barrel shares one set of meshes and materials; the flames and
## sparks are only drawn within FLAMES_RANGE, the light fades out by
## LIGHT_FADE, only the smoke goes far; the flicker runs only while the light
## is near a camera (checked twice a second), with no shadows.
## Rule 1 (co-op): the Stack's are made the same on every machine from the
## baked spots; a camp's is the host's, seen by clients as a puppet
## (NetEntities). Cooking itself is the host's call.

const MODEL := "res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Large Props/metal_barrel_mp_0.glb"
## A drum's real height (m).
const HEIGHT := 0.9
const RADIUS := 0.3
const LIGHT_RANGE := 12.0
const LIGHT_COLOR := Color(1.0, 0.6, 0.25)
const LIGHT_ENERGY := 2.6
const LIGHT_FADE := 90.0
const FLAMES_RANGE := 150.0
const SMOKE_RANGE := 1500.0
## How tall the flames roar, and the smoke column's climb.
const FLAME_HEIGHT := 1.6
const SMOKE_SPEED := 3.0
const SMOKE_LIFE := 14.0

## Which way its smoke drifts (a window room's: out of the window), besides up.
var smoke_out := Vector3.ZERO

var _light: OmniLight3D
var _flicker_on := false
var _check_left := 0.0
var _time := 0.0

static var _barrel_scene: PackedScene
static var _flame_process: ParticleProcessMaterial
static var _spark_process: ParticleProcessMaterial
static var _smoke_processes := {}
static var _flame_mesh: QuadMesh
static var _spark_mesh: QuadMesh
static var _smoke_mesh: QuadMesh


## One at `at` (on the floor there) under `parent`.
static func place(parent: Node, at: Vector3, drift: Vector3 = Vector3.ZERO) -> BurningBarrel:
	var barrel := BurningBarrel.new()
	barrel.smoke_out = drift
	parent.add_child(barrel)
	barrel.global_position = at
	return barrel


# ---- Co-op (a camp's, NetEntities) -----------------------------------------------------

func net_spawn_args() -> Dictionary:
	return {smoke_out = smoke_out}


func net_restore(data: Dictionary) -> void:
	smoke_out = data.get("smoke_out", Vector3.ZERO)


func _ready() -> void:
	_build_barrel()
	var fire := FireSource.new()
	fire.radius = RADIUS
	fire.height = HEIGHT + FLAME_HEIGHT
	add_child(fire)
	_add_particles(_flames(), 28, 0.7, FLAMES_RANGE, Vector3.UP * HEIGHT, AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2)))
	_add_particles(_sparks(), 14, 1.6, FLAMES_RANGE, Vector3.UP * HEIGHT, AABB(Vector3(-3, 0, -3), Vector3(6, 10, 6)))
	var climb := SMOKE_SPEED * SMOKE_LIFE
	var smoke_box := AABB(Vector3(-climb, 0, -climb), Vector3(climb * 2.0, climb * 1.2, climb * 2.0))
	_add_particles(_smoke(smoke_out), 18, SMOKE_LIFE, SMOKE_RANGE, Vector3.UP * (HEIGHT + 1.0), smoke_box)
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = LIGHT_FADE * 0.7
	_light.distance_fade_length = LIGHT_FADE * 0.3
	_light.position = Vector3.UP * (HEIGHT + 0.8)
	add_child(_light)
	_check_left = randf() * 0.5


## The light's flicker -- only while a camera's near enough to see it.
func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.5
		var camera := get_viewport().get_camera_3d()
		_flicker_on = camera != null and camera.global_position.distance_squared_to(global_position) < LIGHT_FADE * LIGHT_FADE
	if not _flicker_on:
		return
	_time += delta
	_light.light_energy = LIGHT_ENERGY * (0.85 + 0.1 * sin(_time * 13.0) + 0.05 * sin(_time * 31.0 + 1.7))


func _build_barrel() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = HEIGHT
	shape.shape = cylinder
	shape.position = Vector3.UP * HEIGHT * 0.5
	add_child(shape)
	if _barrel_scene == null and ResourceLoader.exists(MODEL):
		_barrel_scene = load(MODEL) as PackedScene
	if _barrel_scene == null:
		return
	var model := _barrel_scene.instantiate() as Node3D
	add_child(model)
	var box := BackpackView._bounds(model)
	if box.size.y > 0.001:
		var fit := HEIGHT / box.size.y
		model.scale = Vector3.ONE * fit
		model.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * fit
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = FLAMES_RANGE * 2.0


func _add_particles(look: Array, amount: int, life: float, seen: float, at: Vector3, box: AABB) -> void:
	var particles := GPUParticles3D.new()
	particles.process_material = look[0]
	particles.draw_pass_1 = look[1]
	particles.amount = amount
	particles.lifetime = life
	particles.preprocess = minf(life, 4.0) # already burning when it's made
	particles.visibility_aabb = box
	particles.visibility_range_end = seen
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = at
	add_child(particles)


# ---- The looks (made once, shared) -------------------------------------------------------

static func _flames() -> Array:
	if _flame_process == null:
		_flame_process = ParticleProcessMaterial.new()
		_flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_flame_process.emission_sphere_radius = RADIUS * 0.8
		_flame_process.direction = Vector3.UP
		_flame_process.spread = 12.0
		_flame_process.gravity = Vector3.UP * 1.5
		_flame_process.initial_velocity_min = 1.2
		_flame_process.initial_velocity_max = 2.4
		_flame_process.scale_min = 0.6
		_flame_process.scale_max = 1.1
		_flame_process.scale_curve = _curve([Vector2(0, 0.7), Vector2(0.3, 1.0), Vector2(1, 0.1)])
		_flame_process.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.55, 0.12, 0.9), Color(0.7, 0.12, 0.03, 0.5), Color(0.2, 0.05, 0.02, 0)])
		_flame_process.turbulence_enabled = true
		_flame_process.turbulence_noise_strength = 0.6
		_flame_mesh = _glow_quad(0.9, BaseMaterial3D.BLEND_MODE_ADD)
	return [_flame_process, _flame_mesh]


static func _sparks() -> Array:
	if _spark_process == null:
		_spark_process = ParticleProcessMaterial.new()
		_spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_spark_process.emission_sphere_radius = RADIUS * 0.6
		_spark_process.direction = Vector3.UP
		_spark_process.spread = 25.0
		_spark_process.gravity = Vector3.UP * 0.5
		_spark_process.initial_velocity_min = 2.5
		_spark_process.initial_velocity_max = 5.5
		_spark_process.turbulence_enabled = true
		_spark_process.turbulence_noise_strength = 3.0
		_spark_process.color_ramp = _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 1), Color(0.6, 0.1, 0.0, 0)])
		_spark_mesh = _glow_quad(0.05, BaseMaterial3D.BLEND_MODE_ADD)
	return [_spark_process, _spark_mesh]


## The smoke column, drifting `out` as it climbs (one look per way it drifts).
static func _smoke(out: Vector3) -> Array:
	var key := out.snappedf(0.01)
	if not _smoke_processes.has(key):
		var smoke := ParticleProcessMaterial.new()
		smoke.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = RADIUS
		smoke.direction = (Vector3.UP + out * 0.8).normalized()
		smoke.spread = 8.0
		smoke.gravity = Vector3.UP * 0.05 + out * 0.3
		smoke.initial_velocity_min = SMOKE_SPEED * 0.8
		smoke.initial_velocity_max = SMOKE_SPEED * 1.2
		smoke.damping_min = 0.02
		smoke.damping_max = 0.05
		smoke.scale_min = 1.0
		smoke.scale_max = 1.6
		smoke.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 6.0)], 6.0)
		smoke.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.18, 0.16, 0.15, 0.55), Color(0.25, 0.24, 0.24, 0.35), Color(0.3, 0.3, 0.3, 0.0)])
		smoke.turbulence_enabled = true
		smoke.turbulence_noise_strength = 0.4
		_smoke_processes[key] = smoke
	if _smoke_mesh == null:
		_smoke_mesh = _glow_quad(1.6, BaseMaterial3D.BLEND_MODE_MIX)
	return [_smoke_processes[key], _smoke_mesh]


## A soft round billboard (its colour from the particle).
static func _glow_quad(size: float, blend: BaseMaterial3D.BlendMode) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = blend
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	material.albedo_texture = texture
	quad.material = material
	return quad


static func _curve(points: Array, top: float = 1.0) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = top
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _ramp(colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.remove_point(1)
	gradient.set_color(0, colors[0])
	for i in range(1, colors.size()):
		gradient.add_point(float(i) / float(colors.size() - 1), colors[i])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
