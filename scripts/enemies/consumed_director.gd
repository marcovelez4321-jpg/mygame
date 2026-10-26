class_name ConsumedDirector
extends Node

## Where the heights' creatures are (the user's, 2026-10-26). Every game
## makes the same nests and bells (the same spots, the same seed); the host
## lets the Consumed out and decides the rest.
##   THE STACK: STACK_NESTS (3-4) fleshy nests up every tower taller than
##   HIGH (ConsumedNest); and whenever someone's above HIGH on it, FREE (2-4)
##   of the Consumed about them, turning up out of their sight FREE_FROM off.
##   THE OSSUARY (OssuaryLife: once it's walking): three nests up each spire;
##   CIRCLING of the Consumed looping round its spires' tops whenever someone's
##   within NEAR_OSSUARY of it; and its twelve Bell-wraiths -- eight in the
##   nave's rafters, four in the belfry -- woken by its bell as it settles
##   and rises.
## Gone again once nobody's near (GONE_PAST).

const HIGH := 400.0
const STACK_NESTS := Vector2i(3, 4)
const FREE := Vector2i(2, 4)
const FREE_FROM := Vector2(60.0, 100.0)
const STACK_REACH := 700.0
const CIRCLING := 10
const NEAR_OSSUARY := 600.0
const GONE_PAST := 900.0
const FREE_GONE := 500.0
const CHECK_EVERY := 5.0
const SEED := 7177
## TESTING (the user's, 2026-10-26): a nest on Grandma's house, a Bell-wraith
## hanging over her yard, and TEST_CONSUMED of the Consumed about it. Off
## (false) once they've been looked at.
const TEST_AT_HOUSE := true
const TEST_CONSUMED := 3

## The Ossuary's, in its building's own space (tools/ossuary_bake.gd): nests
## up the spires' outer faces, [where, facing]; the Bell-wraiths' hanging
## points; the spires' tops (what the Consumed loop round).
const OSSUARY_NESTS := [[Vector3(-101.5, 200.0, -175.0), Vector3.LEFT], [Vector3(-70.0, 450.0, -201.5), Vector3.FORWARD],
		[Vector3(-95.5, 650.0, -175.0), Vector3.LEFT], [Vector3(101.5, 250.0, -175.0), Vector3.RIGHT],
		[Vector3(70.0, 500.0, -201.5), Vector3.FORWARD], [Vector3(95.5, 680.0, -175.0), Vector3.RIGHT]]
const OSSUARY_BELLS := [Vector3(-25.0, 66.0, -110.0), Vector3(25.0, 66.0, -110.0), Vector3(-25.0, 66.0, -40.0), Vector3(25.0, 66.0, -40.0),
		Vector3(-25.0, 66.0, 40.0), Vector3(25.0, 66.0, 40.0), Vector3(-25.0, 66.0, 110.0), Vector3(25.0, 66.0, 110.0),
		Vector3(63.0, 918.0, -180.0), Vector3(77.0, 918.0, -180.0), Vector3(63.0, 918.0, -170.0), Vector3(77.0, 918.0, -170.0)]
const SPIRE_TOPS := [Vector3(-70.0, 900.0, -175.0), Vector3(70.0, 900.0, -175.0)]

var _check_left := 2.0
var _ossuary: Ossuary
var _ossuary_nests: Array[ConsumedNest] = []
var _circlers: Array[Consumed] = []
var _wanted := {}


static func ensure(tree: SceneTree) -> void:
	if tree.current_scene == null or not tree.get_nodes_in_group(&"consumed_director").is_empty():
		return
	var director := ConsumedDirector.new()
	director.name = "ConsumedDirector"
	tree.current_scene.add_child(director)


func _ready() -> void:
	add_to_group(&"consumed_director")
	_stack_nests.call_deferred()
	if TEST_AT_HOUSE:
		_test_at_house.call_deferred()


func _host() -> bool:
	return not Network.is_online() or multiplayer.is_server()


## Up every tower taller than HIGH: nests on its walls (rays in from outside).
func _stack_nests() -> void:
	var stack := get_tree().current_scene.get_node_or_null(^"TheStack") as Megastructure
	if stack == null:
		return
	var dice := RandomNumberGenerator.new()
	dice.seed = SEED
	var space := stack.get_world_3d().direct_space_state
	var id := 0
	for column in stack.nest_columns:
		if column.y <= HIGH + 100.0:
			continue
		var count := dice.randi_range(STACK_NESTS.x, STACK_NESTS.y)
		for i in count:
			var y := lerpf(HIGH + 50.0, column.y * 0.85, (float(i) + dice.randf()) / float(count))
			var out := Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU)
			var middle := stack.to_global(Vector3(column.x, y, column.z))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(middle + out * 600.0, middle, 1))
			if hit.is_empty():
				continue
			var nest := ConsumedNest.new()
			nest.nest_id = id
			id += 1
			get_tree().current_scene.add_child(nest)
			var normal: Vector3 = hit.normal
			nest.global_transform = Transform3D(Basis.looking_at(-normal, Vector3.UP) if absf(normal.y) < 0.95 else Basis.IDENTITY, (hit.position as Vector3) + normal * 1.5)


## TESTING: the nest on the house's right-hand wall (a ray in from outside),
## letting one out 5 s on; the Bell-wraith 30 m off its front, 14 m up; the
## host's TEST_CONSUMED Consumed 30-50 m round it, in the air.
func _test_at_house() -> void:
	var house := get_tree().get_first_node_in_group(&"grandmas_house") as GrandmasHouse
	if house == null:
		return
	var space := house.get_world_3d().direct_space_state
	var wall := house.to_global(Vector3(0.0, 7.0, 2.0))
	var out := house.global_basis.x
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(wall + out * 40.0, wall, 1))
	if not hit.is_empty():
		var nest := ConsumedNest.new()
		nest.nest_id = 2000
		nest.first_after = 5.0
		get_tree().current_scene.add_child(nest)
		var normal: Vector3 = hit.normal
		nest.global_transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), (hit.position as Vector3) + normal * 1.5)
	var wraith := BellWraith.new()
	wraith.wraith_id = 2000
	get_tree().current_scene.add_child(wraith)
	wraith.global_position = house.to_global(Vector3(0.0, 14.0, -30.0))
	if not _host():
		return
	for i in TEST_CONSUMED:
		var one := Consumed.new()
		one.look = randi()
		get_tree().current_scene.add_child(one)
		var about := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / TEST_CONSUMED) * randf_range(30.0, 50.0)
		one.global_position = house.global_position + about + Vector3.UP * randf_range(12.0, 20.0)


func _process(delta: float) -> void:
	if _ossuary == null or not is_instance_valid(_ossuary):
		_ossuary = get_tree().get_first_node_in_group(&"ossuary") as Ossuary
		if _ossuary:
			_ossuary_life()
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	if _ossuary:
		_keep_circling()
	if _host():
		_free_ones()


## The Ossuary's own: nests up its spires, its Bell-wraiths, on the walking
## building (they ride it); its bell wakes the wraiths.
func _ossuary_life() -> void:
	var body := _ossuary.building()
	if body == null:
		return
	for i in OSSUARY_NESTS.size():
		var spot: Array = OSSUARY_NESTS[i]
		var nest := ConsumedNest.new()
		nest.nest_id = 1000 + i
		body.add_child(nest)
		nest.transform = Transform3D(Basis.looking_at(-(spot[1] as Vector3), Vector3.UP), spot[0])
		_ossuary_nests.append(nest)
	for i in OSSUARY_BELLS.size():
		var wraith := BellWraith.new()
		wraith.wraith_id = i
		body.add_child(wraith)
		wraith.position = OSSUARY_BELLS[i]
	_ossuary.bell_tolled.connect(func() -> void:
		for node in get_tree().get_nodes_in_group(&"bell_wraiths"):
			(node as BellWraith).wake())


## Its spires' tops, where the building is now.
func _spire_top(i: int) -> Vector3:
	return _ossuary.building().global_transform * (SPIRE_TOPS[i % SPIRE_TOPS.size()] as Vector3)


## The Consumed round its spires: CIRCLING of them while anyone's within
## NEAR_OSSUARY; their loops kept on the spires as it walks; the nests' too.
func _keep_circling() -> void:
	for nest in _ossuary_nests:
		if is_instance_valid(nest):
			nest.circle_at = _spire_top(_ossuary_nests.find(nest))
	for i in range(_circlers.size() - 1, -1, -1):
		if not is_instance_valid(_circlers[i]):
			_circlers.remove_at(i)
	for i in _circlers.size():
		_circlers[i].circle_at = _spire_top(i)
	if not _host():
		return
	var centre := _ossuary.building().global_position
	var near := _anyone_within(centre, NEAR_OSSUARY)
	if not near and not _anyone_within(centre, GONE_PAST):
		for one in _circlers:
			one.queue_free()
		_circlers.clear()
		return
	if near and _circlers.size() < CIRCLING:
		for i in CIRCLING - _circlers.size():
			var one := Consumed.new()
			one.look = randi()
			one.circle_at = _spire_top(_circlers.size())
			get_tree().current_scene.add_child(one)
			one.global_position = one.circle_at + Vector3(randf_range(-80, 80), randf_range(-40, 40), randf_range(-80, 80))
			_circlers.append(one)


## The host: FREE of the Consumed about anyone above HIGH on the Stack,
## turning up out of their sight; the far ones gone.
func _free_ones() -> void:
	var stack := get_tree().current_scene.get_node_or_null(^"TheStack") as Node3D
	var loose: Array[Consumed] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Consumed and node.has_meta(&"free"):
			loose.append(node as Consumed)
	for one in loose:
		if not _anyone_within(one.global_position, FREE_GONE):
			one.queue_free()
	if stack == null:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var local := stack.to_local(player.global_position)
		if local.y < HIGH or Vector2(local.x, local.z).length() > STACK_REACH:
			continue
		var key := player.get_multiplayer_authority()
		if not _wanted.has(key):
			_wanted[key] = randi_range(FREE.x, FREE.y)
		var about := 0
		for one in loose:
			if is_instance_valid(one) and one.global_position.distance_to(player.global_position) < 300.0:
				about += 1
		if about < int(_wanted[key]):
			_turn_up_near(player)


## One of the Consumed, out of `player`'s sight FREE_FROM off, in the open air.
func _turn_up_near(player: PlayerMovement) -> void:
	var look := -player.head.global_basis.z
	var space := player.get_world_3d().direct_space_state
	for attempt in 8:
		var out := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
		if out.dot(look) > 0.2:
			continue
		var at := player.global_position + out * randf_range(FREE_FROM.x, FREE_FROM.y) + Vector3.UP * randf_range(-10.0, 25.0)
		var query := PhysicsRayQueryParameters3D.create(player.head.global_position, at, 1, [player.get_rid()])
		if not space.intersect_ray(query).is_empty():
			continue # (in a wall: not there)
		var one := Consumed.new()
		one.look = randi()
		one.set_meta(&"free", true)
		get_tree().current_scene.add_child(one)
		one.global_position = at
		return


func _anyone_within(at: Vector3, reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(at) < reach:
			return true
	return false
