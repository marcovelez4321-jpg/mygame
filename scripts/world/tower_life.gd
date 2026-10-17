class_name TowerLife
extends Node

## Life moving through the Stack's towers (the user's, 2026-10-17), on top of
## its parked infestation (Megastructure):
##   ROAMING SWARMS: coming near a hall, it has HALL_SWARM of a swarm moving
##   through it -- rats, roaches or spiders, wandering the whole hall. A
##   roach swarm carries a body (a dead person, or a dead climber) CARRY_BODY
##   of the time: the roaches lift it and fly it off to eat (RoachCarry).
##   CLIMBING HORDES: CLIMB_CHANCE of halls, and of the main shaft's
##   stretches, have a spider horde (CLIMB_SPIDERS) crawling up a wall as
##   you go up past it; get close and they turn on you.
## Each is rolled as you come within NEAR of it and cleared once everyone's
## FAR off (rolled again next time). Cheap: one check a second, distances
## only; the swarms are normal bands (RoamingGroup: they sleep far off).
## Rule 1 (co-op): the host's; everything it makes is a normal spawn.

const HALL_SWARM := 0.5
const CARRY_BODY := 1.0 / 3.0
const CLIMB_CHANCE := 1.0 / 3.0
const CLIMB_SPIDERS := Vector2i(15, 30)
const NEAR := 40.0
const FAR := 200.0
const SHAFT_STRETCH := 150.0
const CHECK_EVERY := 1.0
const BODY := preload("res://scenes/enemy/enemy.tscn")
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")

## Each place things happen: {box (local), shaft (bool), rolled, swarm, horde}.
var _places: Array[Dictionary] = []
var _stack: Megastructure
var _check_left := 2.0


func _ready() -> void:
	_stack = get_parent() as Megastructure
	if _stack == null or (Network.is_online() and not multiplayer.is_server()):
		set_process(false)
		return
	for zone in _stack.inside_zones:
		_places.append({box = zone, shaft = false, rolled = false, swarm = null, horde = null})
	# The main shaft, in stretches (StackBuilder's: its middle, the whole way up).
	var half := StackBuilder.UPPER_SHAFT * 0.5
	var y := StackBuilder.INTERIOR_TOP
	while y < StackBuilder.TOWERS[0][3] - SHAFT_STRETCH:
		_places.append({box = AABB(Vector3(-half, y, -half), Vector3(half * 2.0, SHAFT_STRETCH, half * 2.0)), shaft = true,
				rolled = false, swarm = null, horde = null})
		y += SHAFT_STRETCH


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	var players: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("player"):
		players.append(_stack.to_local((node as Node3D).global_position))
	for place in _places:
		var box: AABB = place.box
		var nearest := INF
		for at in players:
			nearest = minf(nearest, _distance_to_box(at, box))
		if not place.rolled and nearest < NEAR:
			place.rolled = true
			_roll(place)
		elif place.rolled and nearest > FAR:
			place.rolled = false
			_clear(place)
		_climb(place, delta)


static func _distance_to_box(at: Vector3, box: AABB) -> float:
	var closest := at.clamp(box.position, box.end)
	return at.distance_to(closest)


func _roll(place: Dictionary) -> void:
	var box: AABB = place.box
	if not place.shaft and randf() < HALL_SWARM:
		place.swarm = _swarm_in(box)
	if randf() < CLIMB_CHANCE:
		place.horde = _horde_on_wall(box, place.shaft)


func _clear(place: Dictionary) -> void:
	if is_instance_valid(place.swarm):
		(place.swarm as RoamingGroup).disband()
	place.swarm = null
	var horde: Variant = place.horde
	if horde is Dictionary and is_instance_valid(horde.pack):
		var pack := horde.pack as SpiderPack
		for spider in pack.spiders:
			if is_instance_valid(spider):
				spider.queue_free()
		pack.queue_free()
	place.horde = null


## A swarm wandering the whole hall: rats, roaches (some carrying a body) or spiders.
func _swarm_in(box: AABB) -> RoamingGroup:
	var spot := _floor_in(box)
	if not spot.is_finite():
		return null
	var kind: String = ["rats", "roaches", "spiders"][randi() % 3]
	var group := _stack.band_group(_stack.to_global(spot), minf(box.size.x, box.size.z) * 0.4, 2.0, "Roaming_" + kind)
	_stack.fill_band(group, kind, kind == "roaches" and randf() < CARRY_BODY)
	return group


## A spot on the hall's floor (straight down from somewhere in it), local.
func _floor_in(box: AABB) -> Vector3:
	var space := _stack.get_world_3d().direct_space_state
	for attempt in 12:
		var from := Vector3(randf_range(box.position.x + 10.0, box.end.x - 10.0), box.position.y + 6.0,
				randf_range(box.position.z + 10.0, box.end.z - 10.0))
		var query := PhysicsRayQueryParameters3D.create(_stack.to_global(from), _stack.to_global(from + Vector3.DOWN * 12.0), 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return _stack.to_local(hit.position)
	return Vector3.INF


## A spider horde on one of the walls near the bottom, set to crawl up it.
func _horde_on_wall(box: AABB, shaft: bool) -> Variant:
	var space := _stack.get_world_3d().direct_space_state
	for attempt in 8:
		var way := Vector3.FORWARD.rotated(Vector3.UP, (randi() % 4) * PI * 0.5 + randf_range(-0.3, 0.3))
		var start := Vector3(box.get_center().x, box.position.y + 4.0, box.get_center().z)
		var query := PhysicsRayQueryParameters3D.create(_stack.to_global(start), _stack.to_global(start + way * maxf(box.size.x, box.size.z)), 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		var normal := hit.normal as Vector3
		var side := normal.cross(Vector3.UP).normalized()
		var pack := SPIDER_PACK.instantiate() as SpiderPack
		pack.start_count = randi_range(CLIMB_SPIDERS.x, CLIMB_SPIDERS.y)
		pack.spider_scale = _stack.infest_magnify
		pack.free_when_empty = true
		# Onward and upward, a short hop at a time.
		pack.climb = true
		pack.roam_interval = 3.0
		pack.roam_radius = 10.0
		# Its up out of the wall (set before it's added: it takes its surface
		# then): it lives on the wall and roams across it.
		pack.transform = Transform3D(Basis(side, normal, side.cross(normal)), hit.position + normal * 0.3)
		get_tree().current_scene.add_child(pack)
		var top := box.end.y - 15.0 if not shaft else box.end.y + SHAFT_STRETCH
		return {pack = pack, top = _stack.to_global(Vector3(0.0, top, 0.0)).y}
	return null


## Up the wall (SpiderPack.climb) till it's near the top; then it just roams.
func _climb(place: Dictionary, _delta: float) -> void:
	var horde: Variant = place.horde
	if not (horde is Dictionary) or not is_instance_valid(horde.pack):
		return
	var pack := horde.pack as SpiderPack
	if pack.climb and not pack.spiders.is_empty() and pack.pack_center().y >= float(horde.top):
		pack.climb = false
		pack.home = pack.pack_center()