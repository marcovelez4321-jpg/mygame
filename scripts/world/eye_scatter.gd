class_name EyeScatter
extends Node

## Plants eyeball clusters (EyeCluster) in the sewer/hive land as chunks
## stream in (WorldChunks): a few here and there, never in the reef. Like the
## growths, where they go comes from the world seed and the chunk, so every
## player's game has them in the same places; they go when the chunk goes.

@export var seed: int = 91
## Clusters per 128 x 128 m of full sewer land (fewer toward a reef; scaled
## to the real chunk size): rarer than any growth, but not a rare find --
## about one every three or four of those.
@export var clusters_per_chunk: float = 0.3
## Ground too steep for them (degrees).
@export var max_slope: float = 35.0
## Keep this circle bare (Grandma's yard).
@export var clear_centre: Vector3 = Vector3.ZERO
@export var clear_radius: float = 70.0
## Which biome is where (empty = the sewer everywhere).
@export var biomes: BiomeMap
## The chunk streamer and the ground (empty = found next to this node).
@export var chunks: WorldChunks
@export var terrain: Node3D


func _ready() -> void:
	if chunks == null:
		chunks = get_parent().get_node_or_null(^"WorldChunks") as WorldChunks
	if terrain == null:
		terrain = get_parent().get_node_or_null(^"Terrain3D") as Node3D
	if chunks == null or terrain == null:
		push_warning("EyeScatter: needs a WorldChunks and a Terrain3D next to it")
		return
	chunks.chunk_loaded.connect(_on_chunk_loaded)


func _on_chunk_loaded(chunk: Vector2i, root: Node3D) -> void:
	var data: Object = terrain.call("get_data")
	if data == null:
		return
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector3i(seed, chunk.x, chunk.y))
	var size := chunks.chunk_size
	# A Poisson count: mostly none or one, now and then two or three.
	var count := 0
	var limit := exp(-clusters_per_chunk * pow(size / 128.0, 2.0))
	var product := random.randf()
	while product > limit:
		product *= random.randf()
		count += 1
	for i in count:
		var spot := Vector3((chunk.x + random.randf()) * size, 0.0, (chunk.y + random.randf()) * size)
		var cluster_seed := random.randi()
		var reef := biomes.reef(spot.x, spot.z) if biomes else 0.0
		if random.randf() < reef * 1.5: # sewer things: none in the reef, fewer near it
			continue
		if Vector2(spot.x - clear_centre.x, spot.z - clear_centre.z).length() < clear_radius:
			continue
		spot.y = data.call("get_height", spot)
		var normal: Vector3 = data.call("get_normal", spot)
		if is_nan(spot.y) or not normal.is_finite() or rad_to_deg(acos(clampf(normal.y, -1.0, 1.0))) > max_slope:
			continue
		var cluster := EyeCluster.new()
		cluster.look_seed = cluster_seed
		cluster.eye_count = random.randi_range(3, 9)
		cluster.position = spot - root.global_position
		root.add_child(cluster)
