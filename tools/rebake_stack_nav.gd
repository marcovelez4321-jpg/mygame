extends SceneTree

## Re-bakes just the test world's navmesh tiles under the Stack, over its whole
## height -- every floor, not only the ground storey (the world bake's tiles
## take the terrain's height range, so the Stack's upper floors were never in
## them). Nothing else of the world bake is touched (terrain, chunks, biomes,
## the scene); the tiles round it keep theirs and still meet these at the ground.
##   godot --headless --path <project> --script res://tools/rebake_stack_nav.gd
## Re-run it after a Stack re-bake (tools/make_the_stack.gd) changes its shape.
## Autoloads stood in for first, as tools/make_test_world.gd does.

const DATA_DIR := "res://worlds/test_world/terrain"
const NAV_DIR := "res://worlds/test_world/navigation"
const CHUNKS_DIR := "res://worlds/test_world/chunks"
const STACK_SCENE := "res://scenes/megastructures/the_stack.scn"
const WORLD_SCENE := "res://scenes/world/test_world.tscn"


func _initialize() -> void:
	create_timer(3600.0).timeout.connect(quit)
	for name in ["GameSettings", "SewerLook", "PauseMenu", "FrameCounter", "Network", "PS1Dither"]:
		if not Engine.has_singleton(name):
			Engine.register_singleton(name, Node.new())
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	# The ground, from the saved data.
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.set("vertex_spacing", 4.0)
	root.add_child(terrain)
	terrain.set("data_directory", DATA_DIR)
	var data: Object = null
	for frame in 120:
		data = terrain.call("get_data")
		if data and int(data.call("get_region_count")) > 0:
			break
		await process_frame
	if data == null or int(data.call("get_region_count")) == 0:
		push_error("rebake_stack_nav: the terrain data never loaded")
		quit(1)
		return
	# The Stack where the world has it.
	var stack_at := _stack_transform()
	var statics := Node3D.new()
	root.add_child(statics)
	var stack := (load(STACK_SCENE) as PackedScene).instantiate() as Node3D
	stack.set("barnacle_nests", 0) # only its shape's wanted here
	stack.transform = stack_at
	statics.add_child(stack)
	for frame in 3:
		await process_frame
	# Its extent: every collider's box.
	var box := AABB()
	var first := true
	for node in stack.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled:
			continue
		var local := shape_node.shape.get_debug_mesh().get_aabb()
		var world_box := shape_node.global_transform * local
		box = world_box if first else box.merge(world_box)
		first = false
	if first:
		push_error("rebake_stack_nav: the Stack has no colliders")
		quit(1)
		return
	# The test chunks over the same ground (the world bake took them in too).
	var navigation: Node = (load("res://scripts/world/world_navigation.gd") as GDScript).new()
	navigation.set("tiles_dir", NAV_DIR)
	var tile: float = navigation.get("tile_size")
	for tz in range(floori(box.position.z / tile), ceili(box.end.z / tile)):
		for tx in range(floori(box.position.x / tile), ceili(box.end.x / tile)):
			var path := CHUNKS_DIR.path_join("chunk_%d_%d.tscn" % [tx, tz])
			if ResourceLoader.exists(path):
				var placed := (load(path) as PackedScene).instantiate() as Node3D
				placed.position = Vector3(tx * tile, 0.0, tz * tile)
				statics.add_child(placed)
	await process_frame
	var ground: Vector2 = data.call("get_height_range")
	var heights := Vector2(minf(ground.x, box.position.y), maxf(ground.y, box.end.y))
	var area := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	print("STACKNAV the Stack spans ", box, "; tiles over ", area, ", heights ", heights)
	var started := Time.get_ticks_msec()
	var tiles: int = navigation.call("bake_tiles", area, terrain, statics, heights)
	print("STACKNAV baked %d tiles in %.1f s into %s" % [tiles, (Time.get_ticks_msec() - started) / 1000.0, NAV_DIR])
	navigation.free()
	quit()


## TheStack's transform in the test world's scene (read from it, not
## instantiated -- the world's own scripts aren't wanted here).
func _stack_transform() -> Transform3D:
	var state := (load(WORLD_SCENE) as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) == &"TheStack":
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == &"transform":
					return state.get_node_property_value(i, p)
	return Transform3D(Basis.IDENTITY, Vector3(250.0, 31.5, -1450.0))
