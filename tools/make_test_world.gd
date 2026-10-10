extends SceneTree

## Bakes the M0 test world (docs/WORLD.md): a 1 x 1 km Terrain3D ground from
## AlienTerrain, saved as Terrain3D region data, plus a scene with the
## player standing in the middle (Grandma's yard) to walk around in.
##   godot --headless --path <project> --script res://tools/make_test_world.gd
## Re-run it after changing AlienTerrain's settings below; it overwrites the
## terrain data and the scene.

const DATA_DIR := "res://worlds/test_world/terrain"
const NAV_DIR := "res://worlds/test_world/navigation"
const TERRAIN_SHADER := "res://shaders/alien_terrain.gdshader"
const ENVIRONMENT_PATH := "res://worlds/test_world/environment.tres"
const SCENE_PATH := "res://scenes/world/test_world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
## Enemies dropped round the yard to test walking, pathing and foot IK on
## the terrain: scene -> where (x, z; standing on the ground there).
const TEST_ENEMIES := {
	"res://scenes/enemy/harvestman/harvestman_leech.tscn": Vector2(80.0, 60.0),
	"res://scenes/enemy/spider_pack.tscn": Vector2(-70.0, 50.0),
	"res://scenes/enemy/zombie.tscn": Vector2(-60.0, -60.0),
	"res://scenes/enemy/zombie_rusher.tscn": Vector2(-70.0, -50.0),
	"res://scenes/enemy/rat.tscn": Vector2(55.0, -70.0),
}


func _initialize() -> void:
	# A script error stops this function before quit(); never hang on one.
	create_timer(600.0).timeout.connect(quit)
	_bake()


func _bake() -> void:
	var shape := AlienTerrain.new()
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
	var tiles := navigation.bake_tiles(Rect2(-half, -half, half * 2.0, half * 2.0), terrain, null, heights)
	print("navmesh tiles baked: ", tiles, " into ", NAV_DIR)
	data.call("save_directory", DATA_DIR)
	terrain.set("data_directory", DATA_DIR)
	# The alien ground's look: our shader on Terrain3D's material.
	var material: Object = terrain.call("get_material")
	material.call("set_shader_override", load(TERRAIN_SHADER))
	material.call("enable_shader_override", true)
	# Ground collision over the whole 1 km, not just round the camera:
	# enemies' feet and ground rays need it wherever they are.
	terrain.set("collision_mode", 3) # Terrain3DCollision.FULL_GAME
	# The rest only goes into the saved scene: out of the tree, so nothing's
	# _ready() runs here (the Harvestman would build its hitboxes and all).
	get_root().remove_child(root)
	root.add_child(navigation)
	navigation.owner = root


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

	# Light (skyboxes later).
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
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
