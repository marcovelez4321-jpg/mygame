extends SceneTree

## Bakes the M0 test world (docs/WORLD.md): a Terrain3D ground from
## AlienTerrain (4 x 4 km by default), saved as Terrain3D region data, its
## navmesh tiles, test chunks, plus a scene with the player standing in the
## middle (Grandma's yard) to walk around in.
##   godot --headless --path <project> --script res://tools/make_test_world.gd
##   ... --script res://tools/make_test_world.gd -- size=2048   (8 x 8 km)
## size = heightmap pixels across, 4 m each (256 = 1 km, 1024 = 4 km); a
## power of two, 256 or more. Re-run it after changing AlienTerrain's
## settings; it overwrites the terrain data, tiles, chunks and the scene.

const DATA_DIR := "res://worlds/test_world/terrain"
const NAV_DIR := "res://worlds/test_world/navigation"
const TERRAIN_SHADER := "res://shaders/alien_terrain.gdshader"
const ENVIRONMENT_PATH := "res://worlds/test_world/environment.tres"
const CHUNKS_DIR := "res://worlds/test_world/chunks"
const BIOMES_PATH := "res://worlds/test_world/biomes.res"
## Biomes (BiomeMap): how much of the land is reef (the rest is sewer/hive),
## how wide the blend between them is (metres), and the bare circle round
## the yard that's always sewer.
const REEF_SHARE := 0.25
const BIOME_BORDER := 150.0
const YARD_SEWER_RADIUS := 120.0
const CHUNK_SIZE := 128.0 # (160 tried: too heavy round the grass)
## Heightmap pixels across by default (x 4 m: 1024 = 4 km).
const DEFAULT_SIZE := 1024
## Test chunks with a megastructure stand-in (a tall monolith) in the middle:
## these near the yard, plus MORE_MONOLITHS scattered over the land at
## random (the same every bake). Chunk -> the monolith's size (width,
## height). Seen through the fog, they show chunks streaming in and out; the
## navmesh routes round them.
const NEAR_CHUNKS := {
	Vector2i(1, 0): Vector2(14.0, 70.0),
	Vector2i(-2, 1): Vector2(20.0, 45.0),
	Vector2i(0, -2): Vector2(10.0, 90.0),
	Vector2i(-3, -3): Vector2(24.0, 60.0),
	Vector2i(2, 2): Vector2(12.0, 55.0),
}
const MORE_MONOLITHS := 40

var _test_chunks := {}
const SCENE_PATH := "res://scenes/world/test_world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
## Enemies dropped round the yard to test walking, pathing and foot IK on
## the terrain: scene -> where (x, z; standing on the ground there).
const TEST_ENEMIES := {
	"res://scenes/enemy/harvestman/harvestman_leech.tscn": Vector2(80.0, 60.0),
	"res://scenes/enemy/spider_pack.tscn": Vector2(-70.0, 50.0),
	"res://scenes/enemy/rat.tscn": Vector2(55.0, -70.0),
}


func _initialize() -> void:
	# A script error stops this function before quit(); never hang on one.
	create_timer(3600.0).timeout.connect(quit)
	_bake()


## Writes each test chunk's scene: a monolith (a static box, sunk a little
## into the ground) in the middle of the chunk. Chunk-local coordinates.
func _make_test_chunks(data: Object) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHUNKS_DIR))
	# Clear the last bake's chunks first: with a different chunk size (or fewer
	# test chunks) old files would load as stray chunks in the wrong places.
	var old := DirAccess.open(CHUNKS_DIR)
	if old:
		for file in old.get_files():
			if file.begins_with("chunk_") and file.ends_with(".tscn"):
				old.remove(file)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.2, 0.28)
	material.roughness = 1.0
	for chunk: Vector2i in _test_chunks:
		var size: Vector2 = _test_chunks[chunk]
		var middle := Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)
		var ground := float(data.call("get_height", Vector3(chunk.x * CHUNK_SIZE, 0.0, chunk.y * CHUNK_SIZE) + middle))
		var content := Node3D.new()
		content.name = "Megastructure"
		var body := StaticBody3D.new()
		body.name = "Monolith"
		body.position = middle + Vector3(0.0, ground + size.y * 0.5 - 6.0, 0.0)
		body.rotation_degrees.y = float(chunk.x * 37 + chunk.y * 61) # each turned differently
		content.add_child(body)
		body.owner = content
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, size.x)
		shape.shape = box
		body.add_child(shape)
		shape.owner = content
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = box.size
		box_mesh.material = material
		mesh.mesh = box_mesh
		body.add_child(mesh)
		mesh.owner = content
		var scene := PackedScene.new()
		scene.pack(content)
		ResourceSaver.save(scene, _chunk_path(chunk))
		content.free()


## Heightmap size from the command line (-- size=2048), else the default.
func _world_size() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("size="):
			return maxi(int(argument.trim_prefix("size=")), 256)
	return DEFAULT_SIZE


## The near test chunks plus MORE_MONOLITHS at random chunks over a world
## world_metres across (seeded, so every bake places them the same).
func _pick_test_chunks(world_metres: float) -> void:
	_test_chunks = NEAR_CHUNKS.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = 4242
	var half_chunks := int(world_metres / CHUNK_SIZE / 2.0)
	for i in MORE_MONOLITHS:
		var chunk := Vector2i(random.randi_range(-half_chunks, half_chunks - 1), random.randi_range(-half_chunks, half_chunks - 1))
		if chunk.length() < 4.0:
			continue # keep the yard's surroundings as they are
		_test_chunks[chunk] = Vector2(random.randf_range(10.0, 30.0), random.randf_range(40.0, 120.0))


## How far from the yard (the middle) the nearest reef is, roughly (metres).
func _nearest_reef(biomes: BiomeMap, half: float) -> float:
	var nearest := INF
	for x in range(-int(half), int(half), 32):
		for z in range(-int(half), int(half), 32):
			if biomes.reef(x, z) > 0.5:
				nearest = minf(nearest, Vector2(x, z).length())
	return nearest


func _chunk_path(chunk: Vector2i) -> String:
	return CHUNKS_DIR.path_join("chunk_%d_%d.tscn" % [chunk.x, chunk.y])


func _bake() -> void:
	var shape := AlienTerrain.new()
	shape.size = _world_size()
	_pick_test_chunks(shape.size * shape.vertex_spacing)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_PATH.get_base_dir()))

	var root := Node3D.new()
	root.name = "TestWorld"
	get_root().add_child(root)

	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	root.add_child(terrain)
	terrain.owner = root
	terrain.set("region_size", shape.region_size)
	terrain.set("vertex_spacing", shape.vertex_spacing)
	# Terrain3D sets its data up a frame or so after entering the tree (and
	# needs a few more before it takes an import).
	var data: Object = null
	for frame in 30:
		data = terrain.call("get_data")
		if data:
			break
		await process_frame
	for frame in 5:
		await process_frame
	terrain.call("change_region_size", shape.region_size)
	if data == null:
		push_error("Terrain3D never made its data")
		quit()
		return
	var height_image := shape.make_height_image()
	data.call("import_images", [height_image, null, null], shape.corner(), 0.0, shape.height)
	print("regions: ", data.call("get_region_count"), " size ", terrain.call("get_region_size"),
			" height range: ", data.call("get_height_range"))
	# Ground height under each test enemy (before the data's swapped for the
	# saved copy below).
	var spots: Array[Vector3] = []
	for spot in TEST_ENEMIES.values():
		var xz: Vector2 = spot
		spots.append(Vector3(xz.x, float(data.call("get_height", Vector3(xz.x, 0.0, xz.y))), xz.y))
	# Pathfinding: the navmesh baked offline into tiles now (while the
	# terrain's data is still loaded), streamed round each player in game.
	var navigation := WorldNavigation.new()
	navigation.name = "WorldNavigation"
	navigation.tiles_dir = NAV_DIR
	var heights: Vector2 = data.call("get_height_range")
	var half := shape.size * shape.vertex_spacing * 0.5
	# Which biome is where: sewer almost everywhere, reef pockets.
	var biomes := BiomeMap.generate(Rect2(-half, -half, half * 2.0, half * 2.0), shape.seed + 5, 8.0, 700.0,
			REEF_SHARE, BIOME_BORDER, Vector3(0.0, 0.0, YARD_SEWER_RADIUS))
	ResourceSaver.save(biomes, BIOMES_PATH, ResourceSaver.FLAG_COMPRESS)
	biomes = load(BIOMES_PATH) as BiomeMap
	print("biomes: ", BIOMES_PATH, ", nearest reef to the yard ", _nearest_reef(biomes, half), " m")
	# Test chunks (megastructure stand-ins), made first so the navmesh takes
	# them in: every chunk scene, placed at its chunk, while baking.
	_make_test_chunks(data)
	var statics := Node3D.new()
	root.add_child(statics)
	for chunk: Vector2i in _test_chunks:
		var placed := (load(_chunk_path(chunk)) as PackedScene).instantiate() as Node3D
		placed.position = Vector3(chunk.x * CHUNK_SIZE, 0.0, chunk.y * CHUNK_SIZE)
		statics.add_child(placed)
	var tiles := navigation.bake_tiles(Rect2(-half, -half, half * 2.0, half * 2.0), terrain, statics, heights)
	statics.queue_free()
	print("navmesh tiles baked: ", tiles, " into ", NAV_DIR)
	data.call("save_directory", DATA_DIR)
	terrain.set("data_directory", DATA_DIR)
	# The alien ground's look: our shader on Terrain3D's material.
	var material: Object = terrain.call("get_material")
	material.call("set_shader_override", load(TERRAIN_SHADER))
	material.call("enable_shader_override", true)
	# Terrain3D turns its checkerboard debug view on for a terrain with no
	# textures; it draws over any shader, so it goes off.
	material.set("show_checkered", false)
	terrain.set("show_checkered", false)
	# Ground collision over the whole 1 km, not just round the camera:
	# enemies' feet and ground rays need it wherever they are.
	terrain.set("collision_mode", 3) # Terrain3DCollision.FULL_GAME
	# The rest only goes into the saved scene: out of the tree, so nothing's
	# _ready() runs here (the Harvestman would build its hitboxes and all).
	get_root().remove_child(root)
	root.add_child(navigation)
	navigation.owner = root
	# The chunk streamer: chunks load round each player as they go.
	var chunks := WorldChunks.new()
	chunks.name = "WorldChunks"
	chunks.chunks_dir = CHUNKS_DIR
	chunks.chunk_size = CHUNK_SIZE
	root.add_child(chunks)
	chunks.owner = root
	# The ground shader, re-applied after Terrain3D's setup (see TerrainLook).
	var look := TerrainLook.new()
	look.name = "TerrainLook"
	look.biomes = biomes
	root.add_child(look)
	look.owner = root
	# The flora: grown into each chunk as it streams in.
	var growth := GrowthScatter.new()
	growth.name = "GrowthScatter"
	growth.high_ground = maxf(heights.y, 1.0)
	growth.biomes = biomes
	root.add_child(growth)
	growth.owner = root
	# Barnacle nests: a chance of one on the land or a building in each chunk.
	var barnacles := ChunkBarnacles.new()
	barnacles.name = "ChunkBarnacles"
	root.add_child(barnacles)
	barnacles.owner = root
	# Eyeball clusters in the sewer land, watching.
	var eyes := EyeScatter.new()
	eyes.name = "EyeScatter"
	eyes.biomes = biomes
	root.add_child(eyes)
	eyes.owner = root
	# The boss worm as an event: up from under a megastructure players linger by.
	var worm := WormDirector.new()
	worm.name = "WormDirector"
	root.add_child(worm)
	worm.owner = root


	# Test enemies on the slopes round the yard: walking, pathing, feet.
	var index := 0
	for path in TEST_ENEMIES.keys():
		var enemy := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(enemy)
		enemy.owner = root
		enemy.position = spots[index] + Vector3.UP * 1.0
		index += 1

	# The air: purple fog (AlienAtmosphere), saved as its own file to tune in
	# the inspector. Marked as having its own look, so SewerLook (the old
	# city's green fog and grade) leaves it alone. Only made the first time,
	# so re-baking never undoes tuning done on it.
	if not ResourceLoader.exists(ENVIRONMENT_PATH):
		ResourceSaver.save(AlienAtmosphere.new().make_environment(), ENVIRONMENT_PATH)
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = load(ENVIRONMENT_PATH) as Environment
	world_environment.set_meta(&"own_look", true)
	root.add_child(world_environment)
	world_environment.owner = root
	# The air by biome: the saved environment is the reef's; the sewer's fog
	# takes over outside the reef, crossfading at the borders.
	var air := BiomeAtmosphere.new()
	air.name = "BiomeAtmosphere"
	air.biomes = biomes
	root.add_child(air)
	air.owner = root

	# Light (skyboxes later).
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	# Shadows: what grounds the creatures (and the giants' shade) -- out to
	# 90 m (the fog's thick past that), two splits so the near ones stay
	# sharp. BiomeAtmosphere tints it.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.light_energy = 1.15
	root.add_child(sun)
	sun.owner = root

	# The player in Grandma's yard, on the ground.
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	player.name = "Player"
	root.add_child(player)
	player.owner = root
	player.position = Vector3(0.0, shape.yard_level * shape.height + 2.0, 0.0)

	var scene := PackedScene.new()
	var error := scene.pack(root)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE_PATH)
	print("test world: terrain data in ", DATA_DIR, ", scene ", SCENE_PATH, " (error ", error, ")")
	quit()
