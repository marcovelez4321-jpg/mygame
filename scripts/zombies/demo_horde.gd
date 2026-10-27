class_name DemoHorde
extends Node

## The rest of the roster in the Stacks demo (the user's, 2026-10-27: "add the
## rest of the enemies in"), on top of the infected at the windows
## (WindowSpawner) and the Alpha Stalker:
##   BANDS (the open world's EncounterDirector, brought in close): a tweaker
##   gang, a rat nest, a roach swarm, a spider pack, a Harvestman, now and
##   then a Rat Bender or the Swarm King -- each turning up out of every
##   player's sight, SPAWN_FROM off, on walkable ground near their level,
##   wandering (RoamingGroup) till they find you; gone again past GONE_PAST.
##   Up to BANDS about each player; one costs a point of the budget (refills
##   one every REFILL s).
##   BARNACLES: CLUMPS barnacle clumps grown on ceilings round the map at the
##   start (their roach and spider nests with them; no leeches -- the
##   user's, 2026-10-27).
##   THE CONSUMED: now and then a pack (CONSUMED_PACK) flying in out of sight
##   wherever someone's under open sky.
##   BELL-WRAITHS: WRAITHS hung high in the great hall, every game.
##   THE OSSUARY (the user's: walking past the Stack, ringing its bell): it
##   passes OSSUARY_PASS off, tolling every OSSUARY_TOLL s (the wraiths wake
##   to it); gone far off, it comes round again.
## Not here: the Burrow Worm (it needs the open world's ground) and the
## Deepmaw crawlers (shelved).
## Rule 1 (co-op): the host's (normal spawns); the wraiths and the Ossuary are
## every game's, from the same numbers.

const CHECK := 4.0
const FIRST := 20.0
const BANDS := 3
const BUDGET := 3
const REFILL := 25.0
const SPAWN_FROM := Vector2(22.0, 50.0)
const SAME_LEVEL := 6.0
const GONE_PAST := 110.0
const SPACING := 25.0
## A Harvestman needs this much room overhead (it's ten metres tall).
const TALL_ROOM := 14.0
const CLUMPS := 8
const CONSUMED_EVERY := Vector2(45.0, 90.0)
const CONSUMED_PACK := Vector2i(2, 3)
const WRAITHS := [Vector3(-25.0, 80.0, -25.0), Vector3(25.0, 80.0, -25.0), Vector3(-25.0, 80.0, 25.0), Vector3(25.0, 80.0, 25.0)]
## Where the Ossuary walks past (between the demo's towers and the real
## Stack), how far off at its nearest, and how often its bell tolls.
const OSSUARY_CENTRE := Vector3(0.0, 0.0, -165.0)
const OSSUARY_PASS := 500.0 # (the user's: 650, then closer)
const OSSUARY_TOLL := 30.0
const OSSUARY_GONE := 3000.0

enum Band { TWEAKERS, RATS, ROACHES, SPIDERS, HARVESTMAN, RAT_BENDER, SWARM_KING }
const WEIGHTS := {Band.TWEAKERS: 3.0, Band.RATS: 2.0, Band.ROACHES: 2.0, Band.SPIDERS: 2.0,
		Band.HARVESTMAN: 0.7, Band.RAT_BENDER: 0.5, Band.SWARM_KING: 0.25}
const TWEAKERS := ["res://scenes/enemy/enemy.tscn", "res://scenes/enemy/enemy_gunner.tscn",
		"res://scenes/enemy/enemy_rusher.tscn", "res://scenes/enemy/mutant_enemy.tscn"]
const HARVESTMEN := ["res://scenes/enemy/harvestman/harvestman_leech.tscn", "res://scenes/enemy/harvestman/harvestman_barnacle.tscn",
		"res://scenes/enemy/harvestman/harvestman_fused.tscn", "res://scenes/enemy/harvestman/harvestman_deepmaw.tscn"]
const RAT_NEST := "res://scenes/enemy/rat_nest.tscn"
const ROACH := "res://scenes/enemy/roach.tscn"
const SPIDER_PACK := "res://scenes/enemy/spider_pack.tscn"
const RAT_BENDER := "res://scenes/enemy/rat_bender.tscn"
const SWARM_KING := "res://scenes/enemy/swarm_king.tscn"
const CLUMP := "res://scenes/enemy/barnacle_cluster.tscn"

var _check_left := FIRST
var _budget := float(BUDGET)
var _bands: Array[RoamingGroup] = []
var _consumed_left := 60.0
var _clumped := false


func _ready() -> void:
	_every_game.call_deferred()


func _host() -> bool:
	return not Network.is_online() or multiplayer.is_server()


## The wraiths, the Consumed's nests up the Stack, the Ossuary: every game.
func _every_game() -> void:
	var scene := get_tree().current_scene
	for i in WRAITHS.size():
		var wraith := BellWraith.new()
		wraith.wraith_id = 3000 + i
		scene.add_child(wraith)
		wraith.global_position = WRAITHS[i]
	ConsumedDirector.ensure(get_tree())
	Ossuary.pass_by(get_tree(), OSSUARY_CENTRE, OSSUARY_PASS, OSSUARY_TOLL)


func _physics_process(delta: float) -> void:
	if not _host():
		return
	_budget = minf(_budget + delta / REFILL, float(BUDGET))
	_consumed_left -= delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK
	var players := _players()
	if players.is_empty() or NavigationServer3D.map_get_iteration_id(_map()) == 0:
		return
	if not _clumped:
		_clumped = true
		_grow_clumps(players[0])
	_ossuary_again()
	_drop_far(players)
	# No leeches (the user's): any the Stack's own barnacle clumps grow, gone.
	for leech in get_tree().get_nodes_in_group(&"leeches"):
		leech.queue_free()
	if _consumed_left <= 0.0:
		_consumed_left = randf_range(CONSUMED_EVERY.x, CONSUMED_EVERY.y)
		_consumed_in(players.pick_random())
	for player: Node3D in players:
		var near := 0
		for band in _bands:
			if band.home.distance_to(player.global_position) < GONE_PAST:
				near += 1
		if near < BANDS and _budget >= 1.0:
			_start_band(player)
			return


func _players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead():
			out.append(player)
	return out


func _map() -> RID:
	return get_viewport().find_world_3d().navigation_map


func _drop_far(players: Array[Node3D]) -> void:
	var kept: Array[RoamingGroup] = []
	for band in _bands:
		if not is_instance_valid(band):
			continue
		var near := false
		for player in players:
			if player.global_position.distance_to(band.home) < GONE_PAST:
				near = true
				break
		if near:
			kept.append(band)
		else:
			band.disband()
	_bands = kept


## Somewhere SPAWN_FROM off `player`, on walkable ground about their level,
## that no player can see (and clear of the other bands). INF: nowhere.
func _hidden_spot(player: Node3D, room: float = 0.0) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	for attempt in 12:
		var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var want := player.global_position + out * randf_range(SPAWN_FROM.x, SPAWN_FROM.y)
		var on := NavigationServer3D.map_get_closest_point(_map(), want)
		if on == Vector3.ZERO or absf(on.y - player.global_position.y) > SAME_LEVEL \
				or Vector2(on.x - want.x, on.z - want.z).length() > 12.0:
			continue
		if _seen(on, space) or _crowded(on):
			continue
		if room > 0.0 and not space.intersect_ray(PhysicsRayQueryParameters3D.create(on + Vector3.UP, on + Vector3.UP * room, 1)).is_empty():
			continue
		return on
	return Vector3.INF


func _seen(at: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for player in _players():
		var eye := player.global_position + Vector3.UP * 1.6
		var query := PhysicsRayQueryParameters3D.create(eye, at + Vector3.UP, 1)
		query.exclude = [(player as CollisionObject3D).get_rid()]
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _crowded(at: Vector3) -> bool:
	for band in _bands:
		if is_instance_valid(band) and band.home.distance_to(at) < SPACING:
			return true
	return false


func _roll() -> Band:
	var total := 0.0
	for band: Band in WEIGHTS:
		total += float(WEIGHTS[band])
	var roll := randf() * total
	for band: Band in WEIGHTS:
		roll -= float(WEIGHTS[band])
		if roll <= 0.0:
			return band
	return Band.TWEAKERS


func _start_band(player: Node3D) -> void:
	var kind := _roll()
	var spot := _hidden_spot(player, TALL_ROOM if kind == Band.HARVESTMAN else 0.0)
	if not spot.is_finite():
		return
	_budget -= 1.0
	var group := RoamingGroup.new()
	group.name = "DemoBand_%s" % Band.keys()[kind]
	group.leg_min = 15.0
	group.leg_max = 45.0
	group.drift_speed = 0.8
	group.sleep_distance = 70.0
	group.position = spot
	get_tree().current_scene.add_child(group)
	match kind:
		Band.TWEAKERS:
			_fill(group, randi_range(3, 6))
		Band.RATS:
			var nest := _make(RAT_NEST) as RatNest
			if nest:
				nest.rat_count = randi_range(5, 9)
				nest.bodyguard_count = randi_range(0, 1)
				_add(group, nest, 0)
		Band.ROACHES:
			for i in randi_range(3, 6):
				_add(group, _make(ROACH), i, 1.5)
		Band.SPIDERS:
			var pack := _make(SPIDER_PACK) as SpiderPack
			if pack:
				pack.start_count = randi_range(4, 8)
				_add(group, pack, 0)
		Band.HARVESTMAN:
			_add(group, _make(HARVESTMEN.pick_random()), 0)
		Band.RAT_BENDER:
			_add(group, _make(RAT_BENDER), 0)
		Band.SWARM_KING:
			_add(group, _make(SWARM_KING), 0)
	_bands.append(group)


## A gang's people one at a time within the frame budget (FrameBudget).
func _fill(group: RoamingGroup, count: int) -> void:
	for i in count:
		while FrameBudget.over():
			await get_tree().process_frame
		if not is_instance_valid(group) or not group.is_inside_tree():
			return
		_add(group, _make(TWEAKERS.pick_random()), i)


func _make(path: String) -> Node:
	return (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else null


func _add(group: RoamingGroup, member: Node, index: int, lift: float = 0.0) -> void:
	if member == null:
		return
	var around := Vector2.from_angle(index * 2.4 + randf()) * (0.0 if index == 0 else randf_range(1.5, 3.5))
	(member as Node3D).position = Vector3(around.x, lift, around.y)
	group.add_child(member)


## Barnacle clumps on ceilings round the map (rays up from walkable ground).
func _grow_clumps(player: Node3D) -> void:
	if not ResourceLoader.exists(CLUMP):
		return
	var space := player.get_world_3d().direct_space_state
	var grown := 0
	for attempt in CLUMPS * 6:
		if grown >= CLUMPS:
			return
		var want := Vector3(randf_range(-60.0, 60.0), randf_range(0.0, 60.0), randf_range(-60.0, 150.0))
		var on := NavigationServer3D.map_get_closest_point(_map(), want)
		if on == Vector3.ZERO or on.distance_to(player.global_position) < 20.0:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(on + Vector3.UP, on + Vector3.UP * 9.0, 1))
		if hit.is_empty() or (hit.normal as Vector3).y > -0.9:
			continue
		var clump := _make(CLUMP) as BarnacleCluster
		clump.leech_count = 0 # (the user's, 2026-10-27: no leeches)
		get_tree().current_scene.add_child(clump)
		# Its up out of the ceiling (down).
		clump.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), hit.position)
		grown += 1


## A pack of the Consumed flying in, out of sight, when someone's under the sky.
func _consumed_in(player: Node3D) -> void:
	var space := player.get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 2.0,
			player.global_position + Vector3.UP * 60.0, 1)).is_empty():
		return # (under a roof)
	for attempt in 8:
		var at := player.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(40.0, 60.0) + Vector3.UP * randf_range(10.0, 20.0)
		if _seen(at, space):
			continue
		for i in randi_range(CONSUMED_PACK.x, CONSUMED_PACK.y):
			var one := Consumed.new()
			one.look = randi()
			one.set_meta(&"free", true)
			get_tree().current_scene.add_child(one)
			one.global_position = at + Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))
		return


## The Ossuary far off: round again (a new pass).
func _ossuary_again() -> void:
	var walker := get_tree().get_first_node_in_group(&"ossuary") as Ossuary
	if walker == null:
		return
	var body := walker.building()
	if body and Vector2(body.global_position.x - OSSUARY_CENTRE.x, body.global_position.z - OSSUARY_CENTRE.z).length() > OSSUARY_GONE:
		Ossuary.pass_by(get_tree(), OSSUARY_CENTRE, OSSUARY_PASS, OSSUARY_TOLL)
