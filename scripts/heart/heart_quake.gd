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

const DAMAGE := 15.0 # (the user's: was 50)
const LAUNCH := 30.0
const CHUNKS := 4
## Everyone inside's screen: a bit of a shake (the user's), degrees.
const SHAKE := 2.0
## Dust bursts on the floor and crumbling spots on the walls, each kick.
const FLOOR_DUST := 6
const WALL_CRUMBLES := 8
## Curtains of dust and grit pouring down from high up across the room
## (the user's), this many a kick, from this high, this long.
const DUST_SHEETS := 4
const SHEET_HEIGHT := Vector2(60.0, 150.0)
const SHEET_LENGTH := Vector2(12.0, 30.0)
## Chunks fall from this high over the floor (out of the dark overhead, the
## user's: in the arena, not off at the walls): half scattered round the
## players (within NEAR_PLAYER), half anywhere in the arena round the heart
## (its open middle, ARENA across).
const CHUNK_HEIGHT := Vector2(100.0, 150.0)
## At most this many falling at once (the user's): a kick drops only as many
## as there's room for.
const MAX_CHUNKS := 5
const NEAR_PLAYER := 12.0
const ARENA := StackBuilder.CATHEDRAL_CLEAR
## The chunks that hurt: twice the size they were (the user's), so they stand
## out from the harmless rubble.
const CHUNK_SIZE := Vector2(2.4, 5.2)

const DUST_COLOR := Color(0.42, 0.38, 0.33, 0.55)
const RUBBLE_COLOR := Color(0.5, 0.48, 0.45)

static var _dust_mesh: QuadMesh
static var _rubble_mesh: BoxMesh


## The host: where this kick's chunks fall from -- every other one over a
## player inside (scattered round them), the rest anywhere in the arena
## round the heart (`centre`); high over the floor either way.
static func pick_chunks(room: AABB, players: Array[Node3D], centre: Vector3) -> PackedVector3Array:
	var spots := PackedVector3Array()
	var room_for := MAX_CHUNKS - FallingChunk.alive
	for i in mini(CHUNKS, room_for):
		var over: Vector3
		if i % 2 == 0 and not players.is_empty():
			over = players[randi() % players.size()].global_position + _scatter(NEAR_PLAYER)
		else:
			over = centre + _scatter(ARENA * 0.5)
		over.x = clampf(over.x, room.position.x + 3.0, room.end.x - 3.0)
		over.z = clampf(over.z, room.position.z + 3.0, room.end.z - 3.0)
		spots.append(Vector3(over.x, room.position.y + randf_range(CHUNK_HEIGHT.x, CHUNK_HEIGHT.y), over.z))
	return spots


## Somewhere within `radius` across the floor (evenly over the disc).
static func _scatter(radius: float) -> Vector3:
	var flat := Vector2.from_angle(randf() * TAU) * radius * sqrt(randf())
	return Vector3(flat.x, 0.0, flat.y)


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
	for i in DUST_SHEETS:
		var at := Vector3(randf_range(room.position.x + 10.0, room.end.x - 10.0), room.position.y + randf_range(SHEET_HEIGHT.x, SHEET_HEIGHT.y),
				randf_range(room.position.z + 10.0, room.end.z - 10.0))
		sheet(world, at, randf_range(SHEET_LENGTH.x, SHEET_LENGTH.y), randf() * PI)
	for spot in spots:
		var drift := Vector3(randf_range(-1.5, 1.5), -randf_range(4.0, 8.0), randf_range(-1.5, 1.5))
		FallingChunk.drop(world, spot, drift, randf_range(CHUNK_SIZE.x, CHUNK_SIZE.y), decides)
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


## A curtain of dust pouring down from `at`: a long thin strip of it
## (`length` across, turned `turn`), grit falling through it.
static func sheet(world: Node, at: Vector3, length: float, turn: float) -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_position = at
	holder.rotation.y = turn
	var dust_fall := dust_particles(70, 5.0, Vector2(1.0, 3.0), 3.0)
	var process := dust_fall.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(length * 0.5, 0.5, 1.0)
	process.direction = Vector3.DOWN
	process.spread = 8.0
	process.gravity = Vector3(0.0, -7.0, 0.0)
	dust_fall.one_shot = true
	dust_fall.explosiveness = 0.6
	dust_fall.local_coords = false
	dust_fall.visibility_aabb = AABB(Vector3(-length, -200.0, -length), Vector3(length * 2.0, 210.0, length * 2.0))
	holder.add_child(dust_fall)
	dust_fall.emitting = true
	rubble(holder, at, 1.5)
	dust_fall.finished.connect(holder.queue_free)


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
