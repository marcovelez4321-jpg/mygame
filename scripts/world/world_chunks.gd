class_name WorldChunks
extends Node3D

## The open world's chunk streamer (docs/WORLD.md), Minecraft-style: the
## world is cut into chunk_size squares, and the chunks round every player
## are loaded while the rest aren't -- no gates, no loading screens.
##   Hand-made content: each chunk's own scene, chunks_dir/chunk_<x>_<z>.tscn
##   (its contents in chunk-local coordinates: (0, 0, 0) is the chunk's -X/-Z
##   corner on the ground plane). A chunk with no scene is just empty land.
##   Loading: the scene file loads on a background thread; at most
##   max_adds_per_frame finished chunks are added to the world per frame, so
##   a burst of loading never hitches a frame.
##   Unloading: one ring of chunks past load_radius before a chunk goes, so
##   walking back and forth over a chunk edge doesn't load/unload it.
##   Procedural content (the hybrid half -- coral, critters) and per-chunk
##   saved state hook in through chunk_loaded / chunk_unloading.
## Same grid as WorldNavigation's navmesh tiles (chunk_size = tile_size).
## Rule 1 (co-op): the host loads chunks round every player (it runs the AI
## and physics in them); a client would load round its own player.

signal chunk_loaded(chunk: Vector2i, root: Node3D)
signal chunk_unloading(chunk: Vector2i, root: Node3D)

## Where the chunk scenes are, and the chunks' size (metres).
@export_dir var chunks_dir: String = ""
@export var chunk_size: float = 160.0
## Chunks loaded round each player, in chunks each way (2 = 5 x 5).
@export var load_radius: int = 2
## Most finished chunks added to the world per frame.
@export var max_adds_per_frame: int = 1

## Vector2i -> the chunk's root (Node3D) once in the world; or its scene path
## while that's loading (or "" for a chunk with no scene, nothing to load).
var _chunks := {}
## Chunks whose scene has finished loading, waiting their turn to be added.
var _ready_to_add: Array[Vector2i] = []


## The chunk a world position is in.
func chunk_at(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / chunk_size), floori(world_position.z / chunk_size))


## Whether a chunk's in the world right now.
func is_loaded(chunk: Vector2i) -> bool:
	return _chunks.get(chunk) is Node3D


func chunk_path(chunk: Vector2i) -> String:
	return chunks_dir.path_join("chunk_%d_%d.tscn" % [chunk.x, chunk.y])


func _process(_delta: float) -> void:
	var wanted := _wanted_chunks()
	# Start what's newly wanted.
	for chunk in wanted:
		if _chunks.has(chunk):
			continue
		var path := chunk_path(chunk)
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "PackedScene")
			_chunks[chunk] = path
		else:
			_chunks[chunk] = ""
			_add_chunk(chunk, null) # empty land: still a chunk (procedural content goes in)
	# Notice loads that finished.
	for chunk in _chunks:
		var held: Variant = _chunks[chunk]
		if held is String and held != "" and not _ready_to_add.has(chunk):
			var status := ResourceLoader.load_threaded_get_status(held)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_ready_to_add.append(chunk)
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("WorldChunks: couldn't load %s" % held)
				_chunks[chunk] = ""
				_add_chunk(chunk, null)
	# Add a few, nearest-first is not needed at this size; oldest first.
	var added := 0
	while added < max_adds_per_frame and not _ready_to_add.is_empty():
		var chunk: Vector2i = _ready_to_add.pop_front()
		var path: Variant = _chunks.get(chunk)
		if path is String and path != "":
			_add_chunk(chunk, ResourceLoader.load_threaded_get(path) as PackedScene)
			added += 1
	# Drop chunks no player's near any more.
	for chunk in _chunks.keys():
		if wanted.has(chunk) or _near_wanted(chunk, wanted):
			continue
		_remove_chunk(chunk)


## Every chunk within load_radius of any player.
func _wanted_chunks() -> Dictionary:
	var wanted := {}
	for player in get_tree().get_nodes_in_group("player"):
		var body := player as Node3D
		if body == null:
			continue
		var centre := chunk_at(body.global_position)
		for dz in range(-load_radius, load_radius + 1):
			for dx in range(-load_radius, load_radius + 1):
				wanted[centre + Vector2i(dx, dz)] = true
	return wanted


func _near_wanted(chunk: Vector2i, wanted: Dictionary) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if wanted.has(chunk + Vector2i(dx, dz)):
				return true
	return false


## Puts a chunk in the world: a root at its corner holding its scene (if it
## has one), then anything procedural (chunk_loaded).
func _add_chunk(chunk: Vector2i, scene: PackedScene) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	root.position = Vector3(chunk.x * chunk_size, 0.0, chunk.y * chunk_size)
	if scene:
		root.add_child(scene.instantiate())
	add_child(root)
	_chunks[chunk] = root
	chunk_loaded.emit(chunk, root)


func _remove_chunk(chunk: Vector2i) -> void:
	var held: Variant = _chunks[chunk]
	if held is Node3D:
		chunk_unloading.emit(chunk, held)
		(held as Node).queue_free()
	elif held is String and held != "" and ResourceLoader.load_threaded_get_status(held) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return # let the load finish first (it can't be cancelled); dropped next time
	_chunks.erase(chunk)
	_ready_to_add.erase(chunk)
