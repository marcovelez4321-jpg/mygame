class_name RoamingGroup
extends Node3D

## A band of enemies on the move across the open world (EncounterDirector
## makes them): a gang of tweakers, a rat swarm, a roach swarm, a spider
## pack, or two or three Harvestmen. Every member keeps doing what it
## always does -- patrolling, wandering round its "home" -- and the group
## just moves that home along a route, a little at a time, toward somewhere
## far off and then somewhere else. So you come across them on their way
## somewhere, not standing about waiting for you.
## AI level of detail: members further than sleep_distance from every
## player are switched off (no thinking, no physics) until someone comes
## back near, while the group still drifts on. Far off in the fog, nobody
## can tell.
## Rule 1 (co-op): the host makes and moves them; members are normal spawns.

## Metres a second the group's home drifts along its route (members wander
## round it, so they amble along at about this).
@export var drift_speed: float = 1.4
## How far the next destination is (metres).
@export var leg_min: float = 150.0
@export var leg_max: float = 350.0
@export var sleep_distance: float = 150.0
## Tied to a place (a camp round a megastructure): every stop is within
## anchor_radius of `anchor`, so it patrols round it instead of moving on.
## Not finite = free to roam.
var anchor := Vector3.INF
var anchor_radius := 50.0
## Its stops snapped onto the navmesh (the ground). Off for a group living
## up a megastructure's floors, which the navmesh doesn't reach.
var use_navmesh := true

## Where the members wander round now, and where it's heading.
var home := Vector3.ZERO
var _destination := Vector3.ZERO
var _asleep := false
var _check_left := 0.0


func _ready() -> void:
	home = global_position
	_check_left = 2.0 # its rats and spiders take a frame or two to arrive
	_pick_destination()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# The route: home drifts toward the destination; a new one on arrival.
	var to := _destination - home
	to.y = 0.0
	if to.length() < 5.0:
		_pick_destination()
	else:
		home += to.normalized() * drift_speed * delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 1.0 # the rest once a second
	home = _on_walkable(home)
	var members := members()
	if members.is_empty():
		queue_free() # all dead
		return
	for member in members:
		if member.has_method("set_home"):
			member.call("set_home", home)
		elif "home" in member:
			member.set("home", home)
	var near := nearest_player_distance() < sleep_distance
	if near == _asleep:
		_set_asleep(not near, members)


## Its members (and the swarms and packs that own creatures), the living ones.
func members() -> Array[Node]:
	var found: Array[Node] = []
	for child in get_children():
		if child is RatNest:
			var swarm := (child as RatNest).swarm
			if is_instance_valid(swarm) and not swarm.rats.is_empty():
				found.append(swarm)
		elif child is SpiderPack:
			if not (child as SpiderPack).spiders.is_empty():
				found.append(child)
		elif child is Node3D and Factions.is_alive_target(child as Node3D):
			found.append(child)
	return found


## Every body it's responsible for: members, their rats and spiders.
func bodies() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in get_children():
		if child is RatNest:
			var swarm := (child as RatNest).swarm
			if is_instance_valid(swarm):
				for rat in swarm.rats:
					if is_instance_valid(rat):
						found.append(rat)
		elif child is SpiderPack:
			for spider in (child as SpiderPack).spiders:
				if is_instance_valid(spider):
					found.append(spider)
		elif child is Node3D:
			found.append(child)
	return found


func nearest_player_distance() -> float:
	var centre := _centre()
	var best := INF
	for node in get_tree().get_nodes_in_group("player"):
		best = minf(best, (node as Node3D).global_position.distance_to(centre))
	return best


## Gone: every body it's responsible for, and itself (EncounterDirector,
## once it's far from everyone).
func disband() -> void:
	for body in bodies():
		if body.get_parent() != self:
			body.queue_free() # rats and spiders live in the world, not under the group
	queue_free()


## Where its members are, roughly (their middle).
func _centre() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for body in bodies():
		sum += body.global_position
		count += 1
	return sum / count if count > 0 else home


func _set_asleep(asleep: bool, members: Array[Node]) -> void:
	_asleep = asleep
	var mode := Node.PROCESS_MODE_DISABLED if asleep else Node.PROCESS_MODE_INHERIT
	for node in members:
		node.process_mode = mode
	for body in bodies():
		body.process_mode = mode


## The next stop: somewhere leg_min..leg_max away (or, camped, somewhere
## round its anchor), on walkable ground.
func _pick_destination() -> void:
	if anchor.is_finite():
		var round_it := Vector2.from_angle(randf() * TAU) * randf_range(anchor_radius * 0.5, anchor_radius)
		_destination = _on_walkable(anchor + Vector3(round_it.x, 0.0, round_it.y))
		return
	var away := Vector2.from_angle(randf() * TAU) * randf_range(leg_min, leg_max)
	_destination = _on_walkable(home + Vector3(away.x, 0.0, away.y))


## The nearest walkable point (the navmesh), or the point itself if there's
## no navmesh there yet.
func _on_walkable(point: Vector3) -> Vector3:
	if not use_navmesh:
		return point
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	var on := NavigationServer3D.map_get_closest_point(map, point)
	return on if on != Vector3.ZERO else point
