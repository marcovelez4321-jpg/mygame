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

const SPEED := 6.0
const DAMAGE := 15.0
const LIFETIME := 8.0
const RADIUS := 0.8
## How fast it swings round toward them (its heading eased this much a second).
const TURN := 2.5
## Where on them it aims (their middle).
const CHEST := 0.9
const COLOR := Color(0.42, 0.02, 0.03)

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

static var _material: StandardMaterial3D


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
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = COLOR
		_material.roughness = 0.08
		_material.metallic_specular = 0.9
		_material.emission_enabled = true
		_material.emission = Color(0.5, 0.02, 0.02)
		_material.emission_energy_multiplier = 0.35
		_material.rim_enabled = true
		_material.rim = 0.6
	_mesh = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = RADIUS
	ball.height = RADIUS * 2.0
	ball.radial_segments = 16
	ball.rings = 8
	_mesh.mesh = ball
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## On toward them, swinging round as they move.
func _drift(delta: float) -> void:
	if is_instance_valid(target):
		var want := ((target.global_position + Vector3.UP * CHEST) - global_position).normalized()
		_heading = _heading.slerp(want, clampf(TURN * delta, 0.0, 1.0)).normalized()
	global_position += _heading * SPEED * delta


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
	BloodFX.spawn_impact(world, at, normal, BloodFX.BLOOD_COLOR, 3.0)
	for i in 3:
		var way := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		BloodFX.spawn_impact(world, at, way, BloodFX.BLOOD_COLOR, 2.0)
	var below := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at, at - normal * 3.0 + Vector3.DOWN * 3.0, 1, [get_rid()]))
	if not below.is_empty():
		BloodFX.spawn_splatter(world, below.position, below.normal, RADIUS * 2.5)
	queue_free()
