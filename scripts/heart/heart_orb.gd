class_name HeartOrb
extends AnimatableBody3D

## The heart's hi-hat attack (the user's, 2026-10-18): a bubble of blood out
## of the heart. Its warning (not the beams' glow): for `warn` (a beat) it
## swells out of a random spot on the heart's surface like a blister,
## wobbling as it fills; on the hi-hat it breaks free and drifts after a
## player at SPEED, wobbling as it goes (through the heart, not stopped by it). It
## pops -- a burst of blood, a splash where it was -- when it reaches them
## (DAMAGE), runs into anything, takes a single shot (its Health: 1), or on
## its own after LIFETIME.
## Rule 1 (co-op): the host's copy moves for real and decides every pop
## (Network.send_heart_orb, send_heart_orb_pop); everyone else's chases the
## same player and pops when the host says.

## (The user's 2026-10-19: three times as fast, 6 -> 18; then 15% faster.)
const SPEED := 20.7
const DAMAGE := 15.0
const LIFETIME := 8.0
const RADIUS := 0.8
## Like a heat-seeking missile (the user's 2026-10-19): fast, but it can only
## turn this many degrees a second -- dodge late and it overshoots, swings
## wide, and if it can't come round in time it flies into a wall. (45, then
## 25% less, the user's.)
const TURN_RATE := 33.75
## Where on them it aims (their middle).
const CHEST := 0.9
const COLOR := Color(0.42, 0.02, 0.03)
## Its trail (the user's, 2026-10-19: like Skarlet's blood orb, MK11): a
## glossy blood streak tapering off behind it over TRAIL_TIME, wobbling,
## with bubbles of blood beading off it and shrinking away. Godot has no
## trail node (its trails are particles'), so the streak is drawn here
## (Trail), like a trail renderer: its path, a ribbon facing the camera.
const TRAIL_TIME := 0.6
## The streak's width where it leaves the orb (just inside its own).
const TRAIL_WIDTH := RADIUS * 1.6
const BUBBLES := 20
const BUBBLE_SIZE := RADIUS * 0.25
## How hard it blows apart when it pops (BloodFX.spawn_burst's strength).
const POP_BURST := 0.5

## Live orbs by id (every game), for the host's pops and the cap.
static var alive := {}
static var _next_id := 1

var id := 0
var target: Node3D
var decides := false
## Swelling on the heart this long yet (the warning), then off after them.
var warn := 0.0
var _swell_time := 0.0
var _exclude: Array[RID] = []
var _heading := Vector3.FORWARD
var _age := 0.0
var _popped := false
var _mesh: MeshInstance3D
var _health: Health
var _trail: Trail
var _bubbles: GPUParticles3D

static var _material: StandardMaterial3D
static var _ball: SphereMesh # (one shared by every orb)
static var _trail_material: StandardMaterial3D
static var _bubble_process: ParticleProcessMaterial
static var _bubble_mesh: SphereMesh


static func next_id() -> int:
	_next_id += 1
	return _next_id


## An orb `orb_id` out of the heart at `at`, after `toward`.
## `out`: the way off the heart's surface it swells (and first heads);
## `exclude`: what it passes through (the heart).
static func spawn(world: Node, at: Vector3, out: Vector3, toward: Node3D, orb_id: int, host: bool, swell: float, exclude: Array[RID] = []) -> HeartOrb:
	var orb := HeartOrb.new()
	orb.id = orb_id
	orb.target = toward
	orb.decides = host
	orb.warn = maxf(swell, 0.0)
	orb._swell_time = orb.warn
	orb._exclude = exclude
	orb._heading = out.normalized()
	world.add_child(orb)
	orb.global_position = at
	return orb


## Its look: the glossy blood ball (one mesh and material shared by every
## orb). ShaderWarmup shows one at the level's start so its shader's compiled
## before the first hi-hat -- the user's freeze when the first one swelled out.
static func look_model() -> MeshInstance3D:
	if _material == null:
		_material = _glossy()
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = RADIUS
		_ball.height = RADIUS * 2.0
		_ball.radial_segments = 16
		_ball.rings = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = _ball
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Glossy blood: its own look, the streak's and the bubbles'.
static func _glossy() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = 0.08
	material.metallic_specular = 0.9
	material.emission_enabled = true
	material.emission = Color(0.5, 0.02, 0.02)
	material.emission_energy_multiplier = 0.35
	material.rim_enabled = true
	material.rim = 0.6
	return material


## Bubbles of blood beading off it as it goes, left behind in the air,
## shrinking away over TRAIL_TIME (no drips: the user's).
static func make_bubbles() -> GPUParticles3D:
	if _bubble_process == null:
		_bubble_process = ParticleProcessMaterial.new()
		_bubble_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_bubble_process.emission_sphere_radius = RADIUS * 0.6
		_bubble_process.spread = 180.0
		_bubble_process.initial_velocity_min = 0.3
		_bubble_process.initial_velocity_max = 1.2
		_bubble_process.gravity = Vector3.ZERO
		_bubble_process.damping_min = 1.0
		_bubble_process.damping_max = 2.0
		_bubble_process.scale_min = 0.5
		_bubble_process.scale_max = 1.0
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 1.0))
		shrink.add_point(Vector2(1.0, 0.0))
		var shrink_texture := CurveTexture.new()
		shrink_texture.curve = shrink
		_bubble_process.scale_curve = shrink_texture
		_bubble_mesh = SphereMesh.new()
		_bubble_mesh.radius = BUBBLE_SIZE
		_bubble_mesh.height = BUBBLE_SIZE * 2.0
		_bubble_mesh.radial_segments = 8
		_bubble_mesh.rings = 4
		if _material == null:
			_material = _glossy()
		_bubble_mesh.material = _material
	var bubbles := GPUParticles3D.new()
	bubbles.amount = BUBBLES
	bubbles.lifetime = TRAIL_TIME
	bubbles.local_coords = false
	bubbles.process_material = _bubble_process
	bubbles.draw_pass_1 = _bubble_mesh
	bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bubbles


## A streak and bubbles on their own at `at` (ShaderWarmup).
static func warm_up(world: Node, at: Vector3) -> Array[Node]:
	var trail := Trail.new()
	world.add_child(trail)
	for i in 6:
		trail.add_point(at + Vector3.RIGHT * i * 0.5)
	var bubbles := make_bubbles()
	world.add_child(bubbles)
	bubbles.global_position = at
	bubbles.emitting = true
	return [trail, bubbles]


## The host's word: orb `orb_id` popped at `at` (every game).
static func pop_by_id(orb_id: int, at: Vector3) -> void:
	var orb: Variant = alive.get(orb_id, null)
	if orb is HeartOrb and is_instance_valid(orb):
		(orb as HeartOrb)._burst(at, Vector3.UP)


func _ready() -> void:
	alive[id] = self
	sync_to_physics = false
	collision_layer = 1 # (shots find it)
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)
	_mesh = look_model()
	add_child(_mesh)
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = 1.0
	_health.bleeds_out = false
	add_child(_health)
	_health.died.connect(func(_attacker: int, _critical: bool) -> void:
		if decides:
			_pop(global_position, Vector3.UP))


func _exit_tree() -> void:
	if alive.get(id) == self:
		alive.erase(id)


func _physics_process(delta: float) -> void:
	if _popped:
		return
	# The warning: swelling out of the heart, wobbling as it fills.
	if warn > 0.0:
		warn -= delta
		var full := 1.0 - clampf(warn / maxf(_swell_time, 0.01), 0.0, 1.0)
		var quiver := sin(Time.get_ticks_msec() * 0.03) * 0.1 * full
		_mesh.scale = Vector3.ONE * lerpf(0.15, 1.0, full * full) * (1.0 + quiver)
		return
	_age += delta
	if _trail == null:
		_start_trail()
	# Wobbling as it goes, like a bubble.
	var wobble := sin(_age * 9.0) * 0.08
	_mesh.scale = Vector3(1.0 - wobble, 1.0 + wobble, 1.0 - wobble)
	if not decides:
		_drift(delta) # (moved here too, so it's where the host's is, near enough)
		if _age > LIFETIME + 3.0:
			queue_free() # (the host's word got lost)
		return
	if _age > LIFETIME:
		_pop(global_position, Vector3.UP)
		return
	var from := global_position
	_drift(delta)
	var to := global_position
	# Reached them?
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and (player.global_position + Vector3.UP * CHEST).distance_to(to) < RADIUS + 0.5:
			player.health.take_damage(DAMAGE, Health.NO_ATTACKER, _heading, to, 1.0)
			_pop(to, -_heading)
			return
	# Ran into something?
	var skip: Array[RID] = [get_rid()]
	skip.append_array(_exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to + _heading * RADIUS, 1, skip))
	if not hit.is_empty() and not (hit.collider is PlayerMovement) and not (hit.collider is HeartOrb):
		_pop(hit.position, hit.normal)


## On toward them, turning at most TURN_RATE toward where they are now.
func _drift(delta: float) -> void:
	if is_instance_valid(target):
		var want := ((target.global_position + Vector3.UP * CHEST) - global_position).normalized()
		var off := _heading.angle_to(want)
		if off > 0.0001:
			var axis := _heading.cross(want)
			if axis.length_squared() < 0.000001:
				axis = _heading.cross(Vector3.UP if absf(_heading.y) < 0.9 else Vector3.RIGHT) # (dead behind it: either way round)
			_heading = _heading.rotated(axis.normalized(), minf(off, deg_to_rad(TURN_RATE) * delta)).normalized()
	global_position += _heading * SPEED * delta


## Off the heart: its streak and bubbles start behind it.
func _start_trail() -> void:
	_trail = Trail.new()
	_trail.follow = self
	add_child(_trail)
	_bubbles = make_bubbles()
	add_child(_bubbles)
	_bubbles.emitting = true


## The host: popped here -- everywhere.
func _pop(at: Vector3, normal: Vector3) -> void:
	if _popped:
		return
	Network.send_heart_orb_pop(id, at)
	_burst(at, normal)


## A bubble of blood bursting: a spray every way, a splash on what it hit.
func _burst(at: Vector3, normal: Vector3) -> void:
	if _popped:
		return
	_popped = true
	var world := get_tree().current_scene
	# A small blood explosion (the user's: every pop -- shot, hit, or run
	# into something): the burst every way, the spray off what it hit.
	BloodFX.spawn_burst(world, at, POP_BURST, BloodFX.BLOOD_COLOR)
	BloodFX.spawn_impact(world, at, normal, BloodFX.BLOOD_COLOR, 3.0)
	# Its streak and bubbles stay where they are and fade out.
	if _trail:
		_trail.follow = null
		_trail.reparent(world)
	if _bubbles:
		_bubbles.reparent(world)
		_bubbles.emitting = false
		get_tree().create_timer(TRAIL_TIME + 0.1).timeout.connect(_bubbles.queue_free)
	var below := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at, at - normal * 3.0 + Vector3.DOWN * 3.0, 1, [get_rid()]))
	if not below.is_empty():
		BloodFX.spawn_splatter(world, below.position, below.normal, RADIUS * 2.5)
	queue_free()


## Its streak: where it's been over TRAIL_TIME, drawn as a ribbon facing the
## camera, TRAIL_WIDTH where it leaves the orb narrowing to nothing, its
## width wobbling like something wet. Once the orb's gone it stops growing
## and its tail runs out, then it goes.
class Trail extends MeshInstance3D:
	var follow: Node3D
	var _points := PackedVector3Array()
	var _born := PackedFloat32Array()
	var _time := 0.0
	var _immediate := ImmediateMesh.new()

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		mesh = _immediate
		if HeartOrb._trail_material == null:
			HeartOrb._trail_material = HeartOrb._glossy()
			HeartOrb._trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = HeartOrb._trail_material
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func add_point(at: Vector3) -> void:
		_points.append(at)
		_born.append(_time)

	func _process(delta: float) -> void:
		_time += delta
		if is_instance_valid(follow):
			if _points.is_empty() or _points[_points.size() - 1].distance_squared_to(follow.global_position) > 0.0025:
				add_point(follow.global_position)
		while not _born.is_empty() and _time - _born[0] > HeartOrb.TRAIL_TIME:
			_points.remove_at(0)
			_born.remove_at(0)
		if not is_instance_valid(follow) and _points.size() < 2:
			queue_free()
			return
		_draw()

	func _draw() -> void:
		_immediate.clear_surfaces()
		var count := _points.size()
		var camera := get_viewport().get_camera_3d()
		if count < 2 or camera == null:
			return # (nothing to draw: an empty surface is an error)
		var eye := camera.global_position
		_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in count:
			var point := _points[i]
			var age := _time - _born[i]
			var t := clampf(age / HeartOrb.TRAIL_TIME, 0.0, 1.0)
			var width := HeartOrb.TRAIL_WIDTH * (1.0 - t) * (1.0 + 0.18 * sin(age * 30.0 + i * 0.7))
			var along := _points[mini(i + 1, count - 1)] - _points[maxi(i - 1, 0)]
			var to_eye := (eye - point).normalized()
			var side := along.cross(to_eye)
			side = side.normalized() if side.length_squared() > 0.000001 else Vector3.UP
			_immediate.surface_set_normal(to_eye)
			_immediate.surface_add_vertex(point + side * width * 0.5)
			_immediate.surface_set_normal(to_eye)
			_immediate.surface_add_vertex(point - side * width * 0.5)
		_immediate.surface_end()
