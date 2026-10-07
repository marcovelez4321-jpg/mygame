class_name BarnacleScatter
extends Node3D

## Grows a few barnacle nests (BarnacleCluster) in random spots on the
## level's walls and ceilings when it loads, so no two runs have them in the
## same places. Light by design: up to max_nests, each only `chance` likely,
## kept min_spacing apart from each other (and every hand-placed nest) and
## safe_radius away from every player at the start. Each one rolls its own
## roach-or-spider nest like any other.
##
## How it finds a spot: a random point in the area, then a ray out sideways
## for a wall, or up for a ceiling -- the same probing the level designer
## would do by hand. Rule 1 (co-op): the host picks the spots.

@export var cluster_scene: PackedScene = preload("res://scenes/enemy/barnacle_cluster.tscn")
## Most nests it can grow, and the chance each one actually does.
@export var max_nests: int = 3
@export_range(0.0, 1.0, 0.05) var chance: float = 0.5
## The area searched (meters, centred on this node), and how high above it
## the probes start.
@export var area_size: Vector2 = Vector2(110.0, 110.0)
@export var probe_height_min: float = 1.0
@export var probe_height_max: float = 3.5
## How far a probe reaches for a wall or a ceiling.
@export var probe_reach: float = 12.0
## Chance a nest goes on a ceiling (if a probe finds one) instead of a wall.
@export_range(0.0, 1.0, 0.05) var ceiling_chance: float = 0.35
## A ceiling has to be at least this high above the floor under it.
@export var min_ceiling_height: float = 2.5
@export var min_spacing: float = 15.0
@export var safe_radius: float = 15.0
## Tries per nest before giving up on it.
@export var attempts: int = 30


func _ready() -> void:
	_scatter.call_deferred() # once the level around it exists


func _scatter() -> void:
	if not multiplayer.is_server():
		return
	for i in max_nests:
		if randf() >= chance:
			continue
		for attempt in attempts:
			var spot := _find_spot(randf() < ceiling_chance)
			if spot.is_empty():
				continue
			var cluster := cluster_scene.instantiate() as Node3D
			add_child(cluster)
			cluster.global_transform = Transform3D(_basis_on(spot.normal), spot.position)
			break


## A spot on a wall (or a ceiling) clear of players and other nests, or {}.
func _find_spot(ceiling: bool) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var half := area_size * 0.5
	var from := global_position + Vector3(randf_range(-half.x, half.x), randf_range(probe_height_min, probe_height_max), randf_range(-half.y, half.y))
	var to := from + (Vector3.UP if ceiling else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)) * probe_reach
	var hit := _static_ray(space, from, to)
	if hit.is_empty():
		return {}
	var normal := hit.normal as Vector3
	if ceiling:
		if normal.y > -0.7:
			return {}
		var floor_hit := _static_ray(space, hit.position + Vector3.DOWN * 0.1, hit.position + Vector3.DOWN * 50.0)
		if floor_hit.is_empty() or (hit.position as Vector3).y - (floor_hit.position as Vector3).y < min_ceiling_height:
			return {}
	elif absf(normal.y) > 0.3:
		return {}
	var at := hit.position as Vector3
	for node in get_tree().get_nodes_in_group(BarnacleCluster.GROUP):
		if (node as Node3D).global_position.distance_to(at) < min_spacing:
			return {}
	for player in get_tree().get_nodes_in_group("player"):
		if (player as Node3D).global_position.distance_to(at) < safe_radius:
			return {}
	return hit


## Level geometry only (not players, props or creatures).
func _static_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D:
			return hit
		exclude.append(hit.rid)
	return {}


## Standing out of a surface with this normal (its up along the normal).
func _basis_on(normal: Vector3) -> Basis:
	var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := normal.cross(reference).normalized()
	return Basis(side, normal, side.cross(normal))
