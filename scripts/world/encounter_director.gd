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
##   spider pack, or 2-3 Harvestmen.
##   CAMPS: the tweakers (people) only live at the megastructures. Coming
##   within camp_range of one, a big gang (camp_min..camp_max) is there --
##   set up on its far side from you -- patrolling round it, not wandering
##   off. Wipe a camp out and that structure stays empty for camp_rest.
##   A band more than despawn_distance from every player is quietly removed
##   (far out in the fog). Bands far off sleep (RoamingGroup).
## The creature caps (Population) still hold on top of all this.
## Rule 1 (co-op): the host decides; everything it makes is a normal spawn.

@export var groups_per_player: int = 5
@export var spawn_min: float = 80.0
@export var spawn_max: float = 140.0
@export var despawn_distance: float = 240.0
## Bands keep at least this far apart when they start.
@export var group_spacing: float = 70.0
## Seconds between checks, and before the first band (the land's quiet at first).
@export var check_interval: float = 4.0
@export var first_delay: float = 20.0
## Keep this circle clear (Grandma's yard).
@export var clear_centre: Vector3 = Vector3.ZERO
@export var clear_radius: float = 100.0
## Which biome is where (empty = the sewer everywhere).
@export var biomes: BiomeMap
@export_group("Camps")
## A megastructure is one this tall (metres); within camp_range of a player
## it has a camp of camp_min..camp_max tweakers; wiped out, it stays empty
## for camp_rest seconds.
@export var structure_min_height: float = 20.0
@export var camp_range: float = 200.0
@export var camp_min: int = 6
@export var camp_max: int = 12
@export var camp_rest: float = 600.0
## The chunk streamer (empty = the WorldChunks next to this node).
@export var chunks: WorldChunks

enum Band { TWEAKERS, RATS, ROACHES, SPIDERS, HARVESTMEN }

## How likely each roaming band is: [sewer, reef] weights. (Tweakers don't
## roam: they're camps.)
const WEIGHTS := {
	Band.RATS: [3.0, 1.0],
	Band.ROACHES: [3.0, 2.0],
	Band.SPIDERS: [2.0, 3.0],
	Band.HARVESTMEN: [1.0, 2.0],
}
const TWEAKERS: Array[PackedScene] = [
	preload("res://scenes/enemy/enemy.tscn"),
	preload("res://scenes/enemy/enemy_gunner.tscn"),
	preload("res://scenes/enemy/enemy_rusher.tscn"),
]
const HARVESTMEN: Array[PackedScene] = [
	preload("res://scenes/enemy/harvestman/harvestman_leech.tscn"),
	preload("res://scenes/enemy/harvestman/harvestman_barnacle.tscn"),
	preload("res://scenes/enemy/harvestman/harvestman_deepmaw.tscn"),
	preload("res://scenes/enemy/harvestman/harvestman_fused.tscn"),
]
const RAT_NEST := preload("res://scenes/enemy/rat_nest.tscn")
const ROACH := preload("res://scenes/enemy/roach.tscn")
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")

var _check_left := 0.0
var _groups: Array[RoamingGroup] = []
## Loaded megastructures (their collision shapes) -> their camp (a
## RoamingGroup), or null while it has none.
var _structures := {}
## Wiped-out camps' structures -> msec they can have one again.
var _resting := {}


func _ready() -> void:
	_check_left = first_delay
	if chunks == null:
		chunks = get_parent().get_node_or_null(^"WorldChunks") as WorldChunks
	if chunks:
		chunks.chunk_loaded.connect(_on_chunk_loaded)


func _on_chunk_loaded(_chunk: Vector2i, root: Node3D) -> void:
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var box := (node as CollisionShape3D).shape as BoxShape3D
		if box and box.size.y >= structure_min_height:
			_structures[node] = null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = check_interval
	var kept: Array[RoamingGroup] = []
	for group in _groups:
		if not is_instance_valid(group):
			continue
		if group.nearest_player_distance() > despawn_distance:
			group.disband()
			continue
		kept.append(group)
	_groups = kept
	_update_camps()
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var near := 0
		for group in _groups:
			if group.home.distance_to(player.global_position) < despawn_distance:
				near += 1
		if near < groups_per_player:
			_start_band(player)
			return # one a check: they trickle in


## Camps: a structure near a player with no camp gets one (unless it's
## resting after being wiped out); a camp wiped out sets its structure resting.
func _update_camps() -> void:
	var now := Time.get_ticks_msec()
	for structure: Variant in _structures.keys():
		if not is_instance_valid(structure):
			# Its chunk went: its camp goes with it.
			var orphan: Variant = _structures[structure]
			if orphan != null and is_instance_valid(orphan):
				(orphan as RoamingGroup).disband()
			_structures.erase(structure)
			continue
		var shape := structure as CollisionShape3D
		var camp: Variant = _structures[shape]
		if camp != null and not is_instance_valid(camp):
			_structures[shape] = null # gone (see _on_camp_gone)
			continue
		if camp != null:
			if (camp as RoamingGroup).nearest_player_distance() > despawn_distance:
				(camp as RoamingGroup).disband() # nobody about: empty till someone comes back
			continue
		if int(_resting.get(shape, 0)) > now:
			continue
		var player := _nearest_player(shape.global_position)
		if player and player.global_position.distance_to(shape.global_position) < camp_range:
			_structures[shape] = _make_camp(shape, player)


## A big gang of tweakers set up by `shape`'s megastructure, on its far side
## from `player`, patrolling round it.
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
	camp.position = spot # the world's root sits at the origin
	camp.anchor = Vector3(centre.x, spot.y, centre.z)
	camp.anchor_radius = reach + 30.0
	camp.drift_speed = 1.0
	get_tree().current_scene.add_child(camp)
	for i in randi_range(camp_min, camp_max):
		_add(camp, TWEAKERS[randi() % TWEAKERS.size()].instantiate(), i)
	camp.tree_exiting.connect(_on_camp_gone.bind(camp, shape))
	return camp


## A camp leaving the world: if none of its people are left it was wiped
## out, and its structure rests (disbanded far off, its people are still
## about, so it doesn't).
func _on_camp_gone(camp: RoamingGroup, shape: CollisionShape3D) -> void:
	if camp.members().is_empty():
		_resting[shape] = Time.get_ticks_msec() + int(camp_rest * 1000.0)


func _nearest_player(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var distance := (node as Node3D).global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = node as Node3D
	return best


## A new band somewhere round `player`, out of their sight.
func _start_band(player: Node3D) -> void:
	var spot := _hidden_spot(player)
	if not spot.is_finite():
		return
	var reef := biomes.reef(spot.x, spot.z) if biomes else 0.0
	var band := _roll_band(reef)
	var group := RoamingGroup.new()
	group.name = "Band_%s" % Band.keys()[band]
	group.position = spot # the world's root sits at the origin
	get_tree().current_scene.add_child(group)
	match band:
		Band.RATS:
			var nest := RAT_NEST.instantiate() as RatNest
			nest.rat_count = randi_range(5, 9) # x2: a leaderless pack (RatNest)
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
			# One brings its own company: 2-3 in all (Harvestman.group_min).
			_add(group, HARVESTMEN[randi() % HARVESTMEN.size()].instantiate(), 0)
	_groups.append(group)


## A member, placed round the group's middle (`lift` up off the ground:
## flyers), before it's added so it starts there.
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


## A walkable spot spawn_min..spawn_max from `player`, behind or beside them
## (not in front of their camera), clear of the yard and other bands; or a
## non-finite vector if none turned up.
func _hidden_spot(player: Node3D) -> Vector3:
	var camera := player.get_viewport().get_camera_3d()
	var looking := -camera.global_basis.z if camera else Vector3.FORWARD
	looking.y = 0.0
	looking = looking.normalized()
	var map := player.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	for attempt in 10:
		var angle := randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		if out.dot(looking) > 0.2:
			continue # in front of them: they'd see it appear
		var want := player.global_position + out * randf_range(spawn_min, spawn_max)
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if on == Vector3.ZERO or Vector2(on.x - want.x, on.z - want.z).length() > 12.0:
			continue
		if Vector2(on.x - clear_centre.x, on.z - clear_centre.z).length() < clear_radius:
			continue
		var crowded := false
		for group in _groups:
			if is_instance_valid(group) and group.home.distance_to(on) < group_spacing:
				crowded = true
				break
		if not crowded:
			return on
	return Vector3.INF
