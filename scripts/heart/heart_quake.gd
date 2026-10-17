class_name HeartQuake
extends RefCounted

## The heart's kick (the user's, 2026-10-17): a shockwave through the whole
## cathedral on every kick drum -- the tower shaking (everyone inside's
## camera), dust kicking up off the floor and the walls, concrete crumbling
## off them and CHUNKS chunks breaking loose near the players (FallingChunk:
## 20 if one lands on you). Caught on the ground, against a wall or perched
## on one when it hits: launched LAUNCH m/s into the air and DAMAGE -- in the
## air, you ride it out.
## Rule 1 (co-op): the host picks where the chunks break off and does the
## launching and hurting (Network.send_heart_kick); every game shakes and
## draws it all.

const DAMAGE := 50.0
const LAUNCH := 30.0
const CHUNKS := 4
## Everyone inside's screen: a bit of a shake (the user's), degrees.
const SHAKE := 2.0
## Dust bursts on the floor and crumbling spots on the walls, each kick.
const FLOOR_DUST := 6
const WALL_CRUMBLES := 8
## Chunks break off the walls this high (over the floor), near players.
const CHUNK_HEIGHT := Vector2(25.0, 90.0)
const CHUNK_SIZE := Vector2(1.2, 2.6)

const DUST_COLOR := Color(0.42, 0.38, 0.33, 0.55)
const RUBBLE_COLOR := Color(0.5, 0.48, 0.45)

static var _dust_mesh: QuadMesh
static var _rubble_mesh: BoxMesh


## The host: where this kick's chunks break off -- on the wall nearest a
## player inside (one picked each), above them, just off it.
static func pick_chunks(room: AABB, players: Array[Node3D]) -> PackedVector3Array:
	var spots := PackedVector3Array()
	for i in CHUNKS:
		var near := players[randi() % players.size()].global_position if not players.is_empty() else room.get_center()
		var x := clampf(near.x + randf_range(-15.0, 15.0), room.position.x + 2.0, room.end.x - 2.0)
		var z := clampf(near.z + randf_range(-15.0, 15.0), room.position.z + 2.0, room.end.z - 2.0)
		# Onto whichever wall is closest there.
		var to_walls := [x - room.position.x, room.end.x - x, z - room.position.z, room.end.z - z]
		var wall := 0
		for k in 4:
			if to_walls[k] < to_walls[wall]:
				wall = k
		match wall:
			0: x = room.position.x + 2.0
			1: x = room.end.x - 2.0
			2: z = room.position.z + 2.0
			3: z = room.end.z - 2.0
		spots.append(Vector3(x, room.position.y + randf_range(CHUNK_HEIGHT.x, CHUNK_HEIGHT.y), z))
	return spots


## Every game: the shake, the dust, the crumbling and the chunks; the host's
## also launches whoever it caught.
static func hit(heart: Node3D, room: AABB, spots: PackedVector3Array, decides: bool) -> void:
	var world := heart.get_tree().current_scene
	# Your camera, if you're in there.
	var camera := heart.get_viewport().get_camera_3d() as CameraJuice
	if camera and room.grow(10.0).has_point(camera.global_position):
		camera.shake(SHAKE)
		camera.kick_fov(SHAKE * 0.8)
	# Dust kicking up off the floor (some by the players), crumbling off the walls.
	var players: Array[Node3D] = []
	for node in heart.get_tree().get_nodes_in_group("player"):
		if room.grow(2.0).has_point((node as Node3D).global_position + Vector3.UP):
			players.append(node as Node3D)
	for i in FLOOR_DUST:
		var at := Vector3(randf_range(room.position.x, room.end.x), room.position.y + 0.3, randf_range(room.position.z, room.end.z))
		if i < players.size():
			at = players[i].global_position + Vector3(randf_range(-6.0, 6.0), 0.3, randf_range(-6.0, 6.0))
		dust(world, at, randf_range(3.0, 6.0))
	for i in WALL_CRUMBLES:
		var side := randi() % 4
		var at := Vector3(randf_range(room.position.x, room.end.x), room.position.y + randf_range(8.0, 160.0), randf_range(room.position.z, room.end.z))
		match side:
			0: at.x = room.position.x + 1.0
			1: at.x = room.end.x - 1.0
			2: at.z = room.position.z + 1.0
			3: at.z = room.end.z - 1.0
		dust(world, at, randf_range(2.0, 4.0))
		rubble(world, at, 0.6)
	for spot in spots:
		var inward := (Vector3(room.get_center().x, spot.y, room.get_center().z) - spot).normalized()
		FallingChunk.drop(world, spot, inward * randf_range(2.0, 6.0), randf_range(CHUNK_SIZE.x, CHUNK_SIZE.y), decides)
	if not decides:
		return
	# Caught standing, against a wall or perched: thrown up, hurt.
	for node in players:
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		if player.is_on_floor() or player.is_on_wall() or player.grapple.is_perched():
			player.health.take_damage(DAMAGE, Health.NO_ATTACKER, Vector3.UP, player.global_position, 1.0)
			player.launch(Vector3.UP * LAUNCH)


## A puff of dust (billboards spreading and settling).
static func dust(world: Node, at: Vector3, size: float) -> void:
	var particles := dust_particles(16, 2.0, Vector2(1.0, 4.0), size)
	particles.one_shot = true
	particles.explosiveness = 0.85
	world.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Bits of concrete falling (no harm: the chunks do that).
static func rubble(world: Node, at: Vector3, size: float) -> void:
	if _rubble_mesh == null:
		_rubble_mesh = BoxMesh.new()
		_rubble_mesh.size = Vector3(0.25, 0.2, 0.25)
		var material := StandardMaterial3D.new()
		material.albedo_color = RUBBLE_COLOR
		_rubble_mesh.material = material
	var particles := GPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = 2.5
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.local_coords = false
	particles.draw_pass_1 = _rubble_mesh
	particles.visibility_aabb = AABB(Vector3(-20.0, -200.0, -20.0), Vector3(40.0, 220.0, 40.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, -20.0, 0.0)
	process.scale_min = 0.6 * size
	process.scale_max = 2.0 * size
	process.angular_velocity_min = -300.0
	process.angular_velocity_max = 300.0
	particles.process_material = process
	world.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


static func dust_particles(amount: int, lifetime: float, speed: Vector2, size: float) -> GPUParticles3D:
	if _dust_mesh == null:
		_dust_mesh = QuadMesh.new()
		_dust_mesh.size = Vector2.ONE
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 32
		texture.height = 32
		material.albedo_texture = texture
		_dust_mesh.material = material
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.draw_pass_1 = _dust_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-30.0, -30.0, -30.0), Vector3(60.0, 60.0, 60.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.4
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3(0.0, -1.5, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = size * 0.5
	process.scale_max = size
	var fade := Gradient.new()
	fade.colors = PackedColorArray([DUST_COLOR, Color(DUST_COLOR, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	return particles
