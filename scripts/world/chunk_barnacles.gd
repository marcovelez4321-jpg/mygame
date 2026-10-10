class_name ChunkBarnacles
extends Node

## Barnacle nests (BarnacleCluster) in the open world: each chunk WorldChunks
## streams in has a random chance of one, grown on the land there or up the
## side of one of its buildings (the chunk's megastructures). The nest is
## put in the chunk, so it goes when the chunk goes. Both biomes get them,
## the reef and the sewer alike. The open world's version of a level's
## BarnacleScatter.
## Rule 1 (co-op): the host rolls and places them.

@export var cluster_scene: PackedScene = preload("res://scenes/enemy/barnacle_cluster.tscn")
## Chance a 128 x 128 m piece of land gets a nest (scaled up for bigger
## chunks: a chunk's chance goes up with its area).
@export_range(0.0, 1.0, 0.05) var nest_chance: float = 0.25
## Chance the nest goes up a building, when the chunk has any (else on the land).
@export_range(0.0, 1.0, 0.05) var building_chance: float = 0.4
## Land too steep for a nest (degrees).
@export var max_slope: float = 40.0
## Never this close to a player, nor in the bare circle round the yard.
@export var safe_radius: float = 25.0
@export var clear_centre: Vector3 = Vector3.ZERO
@export var clear_radius: float = 70.0
## Tries per chunk before giving up.
@export var attempts: int = 12
## The chunk streamer and the ground (empty = found next to this node).
@export var chunks: WorldChunks
@export var terrain: Node3D


func _ready() -> void:
	if chunks == null:
		chunks = get_parent().get_node_or_null(^"WorldChunks") as WorldChunks
	if terrain == null:
		terrain = get_parent().get_node_or_null(^"Terrain3D") as Node3D
	if chunks == null or terrain == null:
		push_warning("ChunkBarnacles: needs a WorldChunks and a Terrain3D next to it")
		return
	chunks.chunk_loaded.connect(_on_chunk_loaded)


func _on_chunk_loaded(chunk: Vector2i, root: Node3D) -> void:
	var chance := 1.0 - pow(1.0 - nest_chance, pow(chunks.chunk_size / 128.0, 2.0))
	if not multiplayer.is_server() or randf() >= chance:
		return
	# A physics frame first: the chunk's buildings only stop rays once their
	# collision's in the physics world.
	await get_tree().physics_frame
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var buildings := _building_boxes(root)
	for attempt in attempts:
		var spot: Transform3D
		if not buildings.is_empty() and randf() < building_chance:
			spot = _on_building(buildings[randi() % buildings.size()])
		else:
			spot = _on_land(chunk)
		if spot.origin.is_finite() and spot != Transform3D() and _clear_of_players(spot.origin):
			var cluster := cluster_scene.instantiate() as Node3D
			root.add_child(cluster)
			cluster.global_transform = spot
			return


## A spot on the land in the chunk, standing up out of the ground, or the
## identity transform if it's no good (too steep, in the yard).
func _on_land(chunk: Vector2i) -> Transform3D:
	var data: Object = terrain.call("get_data")
	if data == null:
		return Transform3D()
	var size := chunks.chunk_size
	var at := Vector3((chunk.x + randf()) * size, 0.0, (chunk.y + randf()) * size)
	if Vector2(at.x - clear_centre.x, at.z - clear_centre.z).length() < clear_radius:
		return Transform3D()
	at.y = data.call("get_height", at)
	var normal: Vector3 = data.call("get_normal", at)
	if is_nan(at.y) or not normal.is_finite() or rad_to_deg(acos(clampf(normal.y, -1.0, 1.0))) > max_slope:
		return Transform3D()
	return Transform3D(_basis_on(normal), at)


## A spot on one of a building's sides, partway up, standing out of it.
func _on_building(shape: CollisionShape3D) -> Transform3D:
	var box := shape.shape as BoxShape3D
	var half := box.size * 0.5
	var side := randi() % 4
	var normal := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][side] as Vector3
	var across := randf_range(-0.8, 0.8)
	var local := Vector3(
			half.x * normal.x if normal.x != 0.0 else across * half.x,
			0.0,
			half.z * normal.z if normal.z != 0.0 else across * half.z)
	var point := shape.global_transform * local
	# Partway up from the ground at its foot (the building's sunk into it).
	var data: Object = terrain.call("get_data")
	var ground: float = data.call("get_height", point) if data else point.y
	var top := (shape.global_transform * Vector3(0.0, half.y, 0.0)).y
	if is_nan(ground) or top - ground < 4.0:
		return Transform3D()
	point.y = randf_range(ground + 1.5, minf(ground + 12.0, top - 1.0))
	var out := (shape.global_basis * normal).normalized()
	return Transform3D(_basis_on(out), point)


## The chunk's buildings: every box collision shape in it.
func _building_boxes(root: Node3D) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for node in root.find_children("*", "CollisionShape3D", true, false):
		if (node as CollisionShape3D).shape is BoxShape3D:
			found.append(node)
	return found


func _clear_of_players(at: Vector3) -> bool:
	for player in get_tree().get_nodes_in_group("player"):
		if (player as Node3D).global_position.distance_to(at) < safe_radius:
			return false
	return true


## Standing out of a surface with this normal (its up along the normal).
func _basis_on(normal: Vector3) -> Basis:
	var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := normal.cross(reference).normalized()
	return Basis(side, normal, side.cross(normal))
