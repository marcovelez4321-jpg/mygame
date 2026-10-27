class_name DemoTraders
extends Node

## The Stacks demo's wandering traders (the user's, 2026-10-27: they walk
## around, and once they're far enough from the player they're gone). Up to
## AT_ONCE about: each turns up out of every player's sight, SPAWN_FROM off,
## walking his rickshaw back and forth along a stretch of open floor (a
## straight run, nothing in the way, the floor solid under it all the way:
## he walks straight lines, Trader._walk_tick), resting at each end. Past
## GONE_PAST from every player, he's gone (a new one turns up later).
## Rule 1 (co-op): the host's (traders are NetEntities).

const CHECK := 5.0
const FIRST := 30.0
const AT_ONCE := 2
const SPAWN_FROM := Vector2(25.0, 60.0)
const GONE_PAST := 90.0
const RUN := Vector2(14.0, 40.0)
## Room either side of his line (the rickshaw's width), and floor steps he
## can't take (his height is kept with no terrain: Trader._ground).
const HALF_WIDTH := 1.0
const STEP := 0.4

var _check_left := FIRST
var _made := 0
var _traders: Array[Trader] = []


func _physics_process(delta: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK
	var players := _players()
	if players.is_empty():
		return
	var kept: Array[Trader] = []
	for trader in _traders:
		if not is_instance_valid(trader):
			continue
		if _nearest(trader.global_position, players) > GONE_PAST:
			trader.queue_free()
			continue
		kept.append(trader)
	_traders = kept
	if _traders.size() < AT_ONCE and NavigationServer3D.map_get_iteration_id(_map()) != 0:
		_bring_one(players.pick_random())


func _players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead():
			out.append(player)
	return out


func _nearest(at: Vector3, players: Array[Node3D]) -> float:
	var best := INF
	for player in players:
		best = minf(best, player.global_position.distance_to(at))
	return best


func _map() -> RID:
	return get_viewport().find_world_3d().navigation_map


func _bring_one(player: Node3D) -> void:
	var space := player.get_world_3d().direct_space_state
	for attempt in 16:
		var want := player.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(SPAWN_FROM.x, SPAWN_FROM.y)
		var a := NavigationServer3D.map_get_closest_point(_map(), want)
		if a == Vector3.ZERO or Vector2(a.x - want.x, a.z - want.z).length() > 10.0:
			continue
		var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var b := a + way * randf_range(RUN.x, RUN.y)
		if not _clear_run(a, b, space) or _seen(a, space) or _seen(b, space):
			continue
		if _near_trader(a):
			continue
		var plan := {at = a, facing = way, parked = false, route = PackedVector3Array([a, b])}
		var trader := TraderDirector.spawn(get_tree().current_scene, "demo_wanderer_%d" % _made, plan)
		_made += 1
		_traders.append(trader)
		return


## A straight run he can walk: nothing in the way at knee and chest height
## across his width, and floor under it every metre at the same height.
func _clear_run(a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized() * HALF_WIDTH
	for height: float in [0.5, 1.6]:
		for offset: Vector3 in [Vector3.ZERO, side, -side]:
			var from := a + Vector3.UP * height + offset - along * 2.0
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, b + Vector3.UP * height + offset + along * 2.0, 1)).is_empty():
				return false
	var steps := int(a.distance_to(b))
	for i in steps + 1:
		var at := a.lerp(b, float(i) / maxf(steps, 1))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 1.0, 1))
		if hit.is_empty() or absf((hit.position as Vector3).y - a.y) > STEP:
			return false
	return true


func _seen(at: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for player in _players():
		var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.6, at + Vector3.UP * 1.5, 1)
		query.exclude = [(player as CollisionObject3D).get_rid()]
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _near_trader(at: Vector3) -> bool:
	for trader in _traders:
		if is_instance_valid(trader) and trader.global_position.distance_to(at) < 30.0:
			return true
	return false
