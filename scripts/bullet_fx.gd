class_name BulletFX
extends RefCounted

## Visible bullets for hitscan guns. Each one is a single GPU particle fired
## from the muzzle to where the shot landed, with particle trails on (the same
## TubeTrailMesh trail the blood spurts use), so the particle IS the bullet
## and the trail is its streak. It lives exactly as long as the flight takes,
## so it vanishes on impact. Look tuned in fx/bullet_trail.tres.
##
## Presentation only (Rule 1): the shot already hit or missed before this is
## drawn; each player's game draws its own copy.

const SETTINGS_PATH := "res://fx/bullet_trail.tres"
## A point-blank shot is slowed down just enough to stay on screen this long,
## or it would be gone before it was ever drawn.
const MIN_VISIBLE_TIME := 0.05

static var _settings: BulletTrailSettings
static var _mesh: TubeTrailMesh


## Most tracers alive at once (see spawn()).
const MAX_LIVE_TRACERS := 24
const TRACER_GROUP := "bullet_tracers"


## `from_enemy` picks the enemy colour instead of the player's.
static func spawn(world: Node, from: Vector3, to: Vector3, from_enemy: bool = false) -> void:
	var settings := _get_settings()
	if not settings.enabled or world == null:
		return
	var distance := from.distance_to(to)
	if distance < 0.05:
		return
	var travel_time := maxf(distance / settings.speed, MIN_VISIBLE_TIME)
	# Capped like BloodFX's bursts: every tracer is a particle system holding
	# GPU descriptors, and a firefight of machine guns stacked them up.
	if world.get_tree().get_nodes_in_group(TRACER_GROUP).size() >= MAX_LIVE_TRACERS:
		return

	var particles := GPUParticles3D.new()
	particles.add_to_group(TRACER_GROUP)
	particles.amount = 1
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = travel_time
	particles.fixed_fps = 0 # update every frame: a bullet only lives a few
	particles.trail_enabled = true
	particles.trail_lifetime = minf(settings.trail_lifetime, travel_time)
	particles.draw_pass_1 = _get_mesh(settings)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Covers the whole flight (the emitter faces the target down -Z), so the
	# bullet isn't culled once it leaves the default box around the muzzle.
	particles.visibility_aabb = AABB(Vector3(-0.5, -0.5, -distance - 0.5), Vector3(1.0, 1.0, distance + 1.0))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.FORWARD
	mat.spread = 0.0
	mat.initial_velocity_min = distance / travel_time
	mat.initial_velocity_max = distance / travel_time
	mat.gravity = Vector3.ZERO
	mat.color = settings.enemy_color if from_enemy else settings.player_color
	particles.process_material = mat

	world.add_child(particles)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	particles.look_at_from_position(from, to, up)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


static func _get_settings() -> BulletTrailSettings:
	if _settings == null:
		_settings = load(SETTINGS_PATH) as BulletTrailSettings
		if _settings == null:
			_settings = BulletTrailSettings.new() # file missing: use the defaults
	return _settings


## Built once and shared by every bullet. White, tinted per bullet by the
## process material's colour (vertex_color_use_as_albedo). use_particle_trails
## makes the tube bend along the bullet's path instead of a straight stick.
static func _get_mesh(settings: BulletTrailSettings) -> TubeTrailMesh:
	if _mesh == null:
		_mesh = TubeTrailMesh.new()
		_mesh.radius = settings.radius
		_mesh.radial_steps = settings.radial_steps
		_mesh.sections = 2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.use_particle_trails = true
		_mesh.material = mat
	return _mesh
