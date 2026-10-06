class_name AcidSpit
extends Node3D

## A glob of acid a spitter roach lobs at you: a real projectile on a
## gravity arc, much slower than a bullet so you can see it coming and
## sidestep. A green blob dripping a trail of goo (the same particle-droplet
## look as the blood), and a splash plus an acid splat wherever it lands.
##
## Each physics tick it moves along its arc and checks the stretch it just
## covered with a ray, so a fast glob can't skip through a wall or a player.
##
## Rule 1 (co-op): the arc is pure maths from (start, launch velocity,
## gravity), so the host only sends "spit fired here with this velocity" and
## every game draws the identical arc; the host alone decides what it hit.

## The glob's size (m) -- both how big it looks and how close it has to get
## to count as touching you.
const BLOB_RADIUS := 0.138
## The player's body for "did the glob touch them": their capsule is 0.4 m
## wide and 1.8 m tall from the feet. Checked with the glob's own size, not
## just a thin line through its centre -- that missed globs that visibly
## clipped your side or splashed at your feet, so hits felt random.
const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.8
## Longest a glob can fly before it's removed (it'll have hit something).
const MAX_LIFETIME := 4.0
const DROP_LIFETIME := 0.35
const SPLASH_SOUND := preload("res://audio/events/enemy/roach_splash.tres")

var _velocity := Vector3.ZERO
var _gravity := 12.0
var _damage := 12.0
var _color := Color(0.6, 0.8, 0.1)
var _exclude: Array[RID] = []
var _age := 0.0
var _done := false
var _blob: MeshInstance3D
var _drips: GPUParticles3D


## Fires a glob from `from` with `velocity`, falling at `gravity` m/s².
## `exclude` is the spitter itself, so it can't hit its own mouth.
static func launch(world: Node, from: Vector3, velocity: Vector3, gravity: float, damage: float,
		color: Color, exclude: Array[RID]) -> AcidSpit:
	var spit := AcidSpit.new()
	spit._velocity = velocity
	spit._gravity = gravity
	spit._damage = damage
	spit._color = color
	spit._exclude = exclude
	world.add_child(spit)
	spit.global_position = from
	return spit


## The launch velocity that lands a glob at `target` exactly `flight_time`
## seconds after leaving `from`, under `gravity` -- the standard ballistic
## formula: v = d / t + (half of gravity's pull over t) upward.
static func lob_velocity(from: Vector3, target: Vector3, flight_time: float, gravity: float) -> Vector3:
	return (target - from) / flight_time + Vector3.UP * (0.5 * gravity * flight_time)


func _ready() -> void:
	_blob = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BLOB_RADIUS
	sphere.height = BLOB_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_blob.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = _color
	material.emission_enabled = true
	material.emission = _color
	material.emission_energy_multiplier = 0.6
	material.roughness = 0.2
	_blob.material_override = material
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)

	# Goo dripping off behind it: droplets left in the world (not carried
	# along) that sag as they fade, which draws the arc it's flying.
	_drips = GPUParticles3D.new()
	_drips.amount = 24
	_drips.lifetime = DROP_LIFETIME
	_drips.local_coords = false
	_drips.draw_pass_1 = BloodFX.droplet_mesh()
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drip_material := ParticleProcessMaterial.new()
	drip_material.direction = Vector3.DOWN
	drip_material.spread = 40.0
	drip_material.initial_velocity_min = 0.2
	drip_material.initial_velocity_max = 0.8
	drip_material.gravity = Vector3(0.0, -6.0, 0.0)
	drip_material.scale_min = 0.69
	drip_material.scale_max = 1.38
	drip_material.color = _color
	_drips.process_material = drip_material
	add_child(_drips)
	_drips.emitting = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= MAX_LIFETIME:
		_finish()
		return
	var gravity_step := Vector3.DOWN * _gravity
	var next := global_position + _velocity * delta + gravity_step * (0.5 * delta * delta)
	_velocity += gravity_step * delta

	# Players first, by body size. A glob moves well under the 0.52 m of
	# player + glob radius per tick, so checking where it ends up can't skip
	# past anyone.
	var player := _player_touching(next)
	if player:
		_hit_player(player, next)
		return

	var query := PhysicsRayQueryParameters3D.create(global_position, next)
	query.exclude = _exclude
	query.collision_mask = 1 # world and enemies; not corpses
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next
		return
	if hit.collider is PlayerMovement:
		_hit_player(hit.collider, hit.position)
	else:
		_splash(hit.position, hit.normal, true)


## A living player whose body the glob at `point` overlaps, or null.
func _player_touching(point: Vector3) -> PlayerMovement:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.health.is_dead:
			continue
		var feet := player.global_position
		var flat := Vector2(point.x - feet.x, point.z - feet.z).length()
		if flat <= PLAYER_RADIUS + BLOB_RADIUS \
				and point.y >= feet.y - BLOB_RADIUS and point.y <= feet.y + PLAYER_HEIGHT + BLOB_RADIUS:
			return player
	return null


## Only players take the acid -- a glob that clips another roach just
## splashes off it.
func _hit_player(player: PlayerMovement, point: Vector3) -> void:
	player.health.take_damage(_damage, Health.NO_ATTACKER, _velocity.normalized(), point, 1.0)
	_splash(point, -_velocity.normalized(), false)


## Splash particles and sound; a lasting acid splat too when it hit a wall
## or floor (not a body).
func _splash(point: Vector3, normal: Vector3, leave_splat: bool) -> void:
	var world := get_tree().current_scene
	if leave_splat:
		BloodFX.spawn_splatter(world, point, normal, 0.7, _color)
	BloodFX.spawn_impact(world, point, normal, _color)
	SoundPlayer.play_3d(SPLASH_SOUND, point, world)
	global_position = point
	_finish()


## Stops the glob but lets the last drips finish falling before freeing.
func _finish() -> void:
	_done = true
	_blob.visible = false
	_drips.emitting = false
	get_tree().create_timer(DROP_LIFETIME + 0.1).timeout.connect(queue_free)
