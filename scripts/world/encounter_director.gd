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
##   reef: more spiders and Harvestmen): a gang of 2-4 tweakers, a rat
##   swarm, a roach swarm, a spider pack, or 2-3 Harvestmen.
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

enum Band { TWEAKERS, RATS, ROACHES, SPIDERS, HARVESTMEN }

## How likely each band is: [sewer, reef] weights.
const WEIGHTS := {
	Band.TWEAKERS: [2.0, 1.0],
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


func _ready() -> void:
	_check_left = first_delay


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
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var near := 0
		for group in _groups:
			if group.home.distance_to(player.global_position) < despawn_distance:
				near += 1
		if near < groups_per_player:
			_start_band(player)
			return # one a check: they trickle in


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
		Band.TWEAKERS:
			for i in randi_range(2, 4):
				_add(group, TWEAKERS[randi() % TWEAKERS.size()].instantiate(), i)
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
