class_name EncounterDirector
extends Node

## Who you run into out in the open world. Not a simulation of the whole
## land (S.T.A.L.K.E.R.'s A-Life): like Left 4 Dead's director and HL2's
## spawners, it keeps a few bands of enemies on the move round each player,
## just out of sight, so meeting them feels like crossing paths:
##   Every few seconds it counts the bands (RoamingGroup) near each player.
##   Short of groups_per_player, it starts one spawn_min..spawn_max metres
##   off -- behind or beside them, never where they're looking, on walkable
##   ground, away from the yard and other bands -- heading somewhere.
##   What comes depends on the biome there (sewer: more rats and roaches;
##   reef: more spiders and Harvestmen): a rat swarm, a roach swarm, a
##   spider pack, 2-3 Harvestmen, or a gang of tweakers (people,
##   gang_min..gang_max, about 1 band in 7 in either biome: the user's).
##   CAMPS: the megastructures also have their own tweakers. Coming
##   within camp_range of one, a big gang (camp_min..camp_max) is there --
##   set up on its far side from you -- patrolling round it, not wandering
##   off. Wipe a camp out and that structure stays empty for camp_rest.
##   A band more than despawn_distance from every player is quietly removed
##   (far out in the fog). Bands far off sleep (RoamingGroup).
## The creature caps (Population) still hold on top of all this.
## Rule 1 (co-op): the host decides; everything it makes is a normal spawn.

@export var groups_per_player: int = 7
@export var spawn_min: float = 70.0
@export var spawn_max: float = 120.0
@export var despawn_distance: float = 240.0
## Bands keep at least this far apart when they start.
@export var group_spacing: float = 60.0
## Seconds between checks, and before the first band (the land's quiet at first).
@export var check_interval: float = 3.0
@export var first_delay: float = 15.0
## Keep this circle clear (Grandma's yard).
@export var clear_centre: Vector3 = Vector3.ZERO
@export var clear_radius: float = 100.0
## Which biome is where (empty = the sewer everywhere).
@export var biomes: BiomeMap
## A roaming gang of tweakers: this many (the user's).
@export var gang_min: int = 6
@export var gang_max: int = 12
@export_group("Camps")
## A megastructure is one this tall (metres); within camp_range of a player
## it has a camp of camp_min..camp_max tweakers; wiped out, it stays empty
## for camp_rest seconds.
@export var structure_min_height: float = 20.0
@export var camp_range: float = 250.0
@export var camp_min: int = 6
@export var camp_max: int = 12
@export var camp_rest: float = 600.0
## The chunk streamer (empty = the WorldChunks next to this node).
@export var chunks: WorldChunks

enum Band { TWEAKERS, RATS, ROACHES, SPIDERS, HARVESTMEN }

const WEIGHTS := {
	Band.TWEAKERS: [2.25, 2.25],
	Band.RATS: [3.0, 1.0],
	Band.ROACHES: [3.0, 2.0],
	Band.SPIDERS: [3.0, 4.5],
	Band.HARVESTMEN: [1.0, 2.0],
}
const TWEAKERS: Array[PackedScene] = [
	preload("res://scenes/enemy/enemy.tscn"),
	preload("res://scenes/enemy/enemy_gunner.tscn"),
	preload("res://scenes/enemy/enemy_rusher.tscn"),
]
const HARVESTMEN: Array[PackedScene] = [
	preload("res://scenes/enemy/harvestman/harvestman_leech.tscn"),
]
const RAT_NEST := preload("res://scenes/enemy/rat_nest.tscn")
const ROACH := preload("res://scenes/enemy/roach.tscn")
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")

var _check_left := 0.0
var _groups: Array[RoamingGroup] = []
var _structures := {}
var _resting := {}

# Cached squared distances to bypass slow square root evaluations
var _despawn_sq: float = 0.0
var _camp_range_sq: float = 0.0
var _clear_radius_sq: float = 0.0
var _group_spacing_sq: float = 0.0


func _ready() -> void:
	_check_left = first_delay
	_despawn_sq = despawn_distance * despawn_distance
	_camp_range_sq = camp_range * camp_range
	_clear_radius_sq = clear_radius * clear_radius
	_group_spacing_sq = group_spacing * group_spacing

	if chunks == null:
		chunks = get_parent().get_node_or_null(^"WorldChunks") as WorldChunks
	if chunks:
		chunks.chunk_loaded.connect(_on_chunk_loaded)


func _on_chunk_loaded(_chunk: Vector2i, root: Node3D) -> void:
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var box := shape.shape as BoxShape3D
		if box and box.size.y >= structure_min_height:
			_structures[shape] = null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = check_interval

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	# Fast cleanup of distant groups using squared distance
	var kept: Array[RoamingGroup] = []
	for group in _groups:
		if not is_instance_valid(group):
			continue
		var disband := true
		var group_pos := group.home
		for player_node in players:
			if (player_node as Node3D).global_position.distance_squared_to(group_pos) <= _despawn_sq:
				disband = false
				break
		if disband:
			group.disband()
			continue
		kept.append(group)
	_groups = kept

	_update_camps(players)

	# Check group counts per player efficiently
	for node in players:
		var player := node as Node3D
		var player_pos := player.global_position
		var near := 0
		for group in _groups:
			if group.home.distance_squared_to(player_pos) < _despawn_sq:
				near += 1
		if near < groups_per_player:
			_start_band(player)
			return


## Optimized camp lifecycle processing
func _update_camps(players: Array[Node]) -> void:
	var now := Time.get_ticks_msec()
	for structure: Variant in _structures.keys():
		# Ensure the object is still valid before casting or interacting
		if not is_instance_valid(structure):
			var orphan: Variant = _structures[structure]
			if orphan != null and is_instance_valid(orphan):
				(orphan as RoamingGroup).disband()
			_structures.erase(structure)
			continue

		var shape := structure as CollisionShape3D
		var camp: Variant = _structures[shape]
		if camp != null:
			if not is_instance_valid(camp):
				_structures[shape] = null
				continue
			var camp_group := camp as RoamingGroup
			var distant := true
			for player_node in players:
				if (player_node as Node3D).global_position.distance_squared_to(camp_group.home) <= _despawn_sq:
					distant = false
					break
			if distant:
				camp_group.disband()
			continue

		if int(_resting.get(shape, 0)) > now:
			continue

		var nearest_player := _nearest_player_cached(shape.global_position, players)
		if nearest_player and nearest_player.global_position.distance_squared_to(shape.global_position) < _camp_range_sq:
			_structures[shape] = _make_camp(shape, nearest_player)

func _make_camp(shape: CollisionShape3D, player: Node3D) -> RoamingGroup:
	var centre := shape.global_position
	var away := centre - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var box := shape.shape as BoxShape3D
	var reach := maxf(box.size.x, box.size.z) * 0.5
	var map := get_viewport().find_world_3d().navigation_map
	var spot := centre + away * (reach + 12.0)
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var on := NavigationServer3D.map_get_closest_point(map, spot)
		if on != Vector3.ZERO:
			spot = on
	var camp := RoamingGroup.new()
	camp.name = "Camp"
	camp.position = spot
	camp.anchor = Vector3(centre.x, spot.y, centre.z)
	camp.anchor_radius = reach + 30.0
	camp.drift_speed = 1.0
	get_tree().current_scene.add_child(camp)
	for i in randi_range(camp_min, camp_max):
		_add(camp, TWEAKERS[randi() % TWEAKERS.size()].instantiate(), i)
	camp.tree_exiting.connect(_on_camp_gone.bind(camp, shape))
	return camp


func _on_camp_gone(camp: RoamingGroup, shape: CollisionShape3D) -> void:
	if camp.members().is_empty():
		_resting[shape] = Time.get_ticks_msec() + int(camp_rest * 1000.0)


func _nearest_player_cached(from: Vector3, players: Array[Node]) -> Node3D:
	var best: Node3D = null
	var best_distance_sq := INF
	for node in players:
		var p := node as Node3D
		var distance_sq := p.global_position.distance_squared_to(from)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = p
	return best


func _start_band(player: Node3D) -> void:
	var spot := _hidden_spot(player)
	if not spot.is_finite():
		return
	var reef := biomes.reef(spot.x, spot.z) if biomes else 0.0
	var band := _roll_band(reef)
	var group := RoamingGroup.new()
	group.name = "Band_%s" % Band.keys()[band]
	group.position = spot
	get_tree().current_scene.add_child(group)
	match band:
		Band.TWEAKERS:
			for i in randi_range(gang_min, gang_max):
				_add(group, TWEAKERS[randi() % TWEAKERS.size()].instantiate(), i)
		Band.RATS:
			var nest := RAT_NEST.instantiate() as RatNest
			nest.rat_count = randi_range(5, 9)
			nest.bodyguard_count = randi_range(0, 1)
			_add(group, nest, 0)
		Band.ROACHES:
			for i in randi_range(4, 8):
				_add(group, ROACH.instantiate(), i, 1.5)
		Band.SPIDERS:
			var pack := SPIDER_PACK.instantiate() as SpiderPack
			pack.start_count = randi_range(6, 12)
			_add(group, pack, 0)
		Band.HARVESTMEN:
			_add(group, HARVESTMEN[randi() % HARVESTMEN.size()].instantiate(), 0)
	_groups.append(group)


func _add(group: RoamingGroup, member: Node, index: int, lift: float = 0.0) -> void:
	var around := Vector2.from_angle(index * 2.4 + randf()) * (0.0 if index == 0 else randf_range(1.5, 4.0))
	(member as Node3D).position = Vector3(around.x, lift, around.y)
	group.add_child(member)


func _roll_band(reef: float) -> Band:
	var total := 0.0
	var weights := {}
	for band: Band in WEIGHTS:
		var weight := lerpf(WEIGHTS[band][0], WEIGHTS[band][1], reef)
		weights[band] = weight
		total += weight
	var roll := randf() * total
	for band: Band in weights:
		roll -= weights[band]
		if roll <= 0.0:
			return band
	return Band.ROACHES


func _hidden_spot(player: Node3D) -> Vector3:
	var camera := player.get_viewport().get_camera_3d()
	var looking := -camera.global_basis.z if camera else Vector3.FORWARD
	looking.y = 0.0
	looking = looking.normalized()
	var map := player.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
		
	var player_pos := player.global_position
	for attempt in 10:
		var angle := randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		if out.dot(looking) > 0.2:
			continue
		var want := player_pos + out * randf_range(spawn_min, spawn_max)
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if on == Vector3.ZERO or Vector2(on.x - want.x, on.z - want.z).length_squared() > 144.0:
			continue
		if Vector2(on.x - clear_centre.x, on.z - clear_centre.z).length_squared() < _clear_radius_sq:
			continue
		var crowded := false
		for group in _groups:
			if is_instance_valid(group) and group.home.distance_squared_to(on) < _group_spacing_sq:
				crowded = true
				break
		if not crowded:
			return on
	return Vector3.INF
