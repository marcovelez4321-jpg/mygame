class_name TowerLife
extends Node

## Life moving through the Stack's towers (the user's, 2026-10-17), on top of
## its parked infestation (Megastructure):
##   ROAMING SWARMS: coming near a hall, it has HALL_SWARM of a swarm moving
##   through it -- rats or spiders on the floor, or roaches swarming up in the
##   air near its ceiling (ROACH_BELOW_CEILING), a third of those carrying a
##   body about (RoachCarry). The main shaft's stretches (it runs from hall to
##   hall) get roach swarms in the air too.
##   CLIMBING HORDES: CLIMB_CHANCE of halls, and of the main shaft's
##   stretches, have a spider horde (CLIMB_SPIDERS) crawling up a wall as you
##   go up past it; get close and they turn on you.
## Never in sight (the user's: they'd pop up in front of you -- Left 4 Dead's
## rule): a spot only counts if no player could see it -- behind them or off
## to the side, or a wall between -- and not right on top of them
## (UNSEEN_NEAREST). Rolled once as you come within NEAR; if there's no
## hidden spot yet, it keeps trying each second till there is. Cleared once
## everyone's FAR off (rolled again next time). The host's.

const HALL_SWARM := 0.5
const SHAFT_SWARM := 0.5
const CARRY_BODY := 1.0 / 3.0
const CLIMB_CHANCE := 1.0 / 3.0
const CLIMB_SPIDERS := Vector2i(15, 30)
const ROACH_BELOW_CEILING := 20.0
const NEAR := 40.0
const FAR := 200.0
const SHAFT_STRETCH := 150.0
const CHECK_EVERY := 1.0
## Unseen: outside this cone of where a player looks (degrees off centre) or
## behind a wall -- and never closer than UNSEEN_NEAREST.
const VIEW_CONE := 65.0
const UNSEEN_NEAREST := 25.0
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")

## Each place things happen: {box (local), shaft, rolled, want_swarm,
## want_horde, swarm, horde}.
var _places: Array[Dictionary] = []
var _stack: Megastructure
var _check_left := 2.0
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	_stack = get_parent() as Megastructure
	if _stack == null or (Network.is_online() and not multiplayer.is_server()):
		set_process(false)
		return
	for zone in _stack.inside_zones:
		_places.append(_place(zone, false))
	# The main shaft, in stretches (StackBuilder's: its middle, the whole way up).
	var half := StackBuilder.UPPER_SHAFT * 0.5
	var y := StackBuilder.INTERIOR_TOP
	while y < StackBuilder.TOWERS[0][3] - SHAFT_STRETCH:
		_places.append(_place(AABB(Vector3(-half, y, -half), Vector3(half * 2.0, SHAFT_STRETCH, half * 2.0)), true))
		y += SHAFT_STRETCH


static func _place(box: AABB, shaft: bool) -> Dictionary:
	return {box = box, shaft = shaft, rolled = false, want_swarm = false, want_horde = false, swarm = null, horde = null}


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	_space = _stack.get_world_3d().direct_space_state
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
			place.want_swarm = randf() < (SHAFT_SWARM if place.shaft else HALL_SWARM)
			place.want_horde = randf() < CLIMB_CHANCE
		elif place.rolled and nearest > FAR:
			place.rolled = false
			place.want_swarm = false
			place.want_horde = false
			_clear(place)
			continue
		# Whatever's still waiting for a spot nobody can see.
		if place.want_swarm:
			place.swarm = _swarm_in(box, place.shaft)
			place.want_swarm = place.swarm == null
		if place.want_horde:
			place.horde = _horde_on_wall(box, place.shaft)
			place.want_horde = place.horde == null
		_climb(place)


static func _distance_to_box(at: Vector3, box: AABB) -> float:
	return at.distance_to(at.clamp(box.position, box.end))


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


## Whether no player could see `at` (global): outside every player's view
## cone or behind a wall, and none of them within UNSEEN_NEAREST.
func _unseen(at: Vector3) -> bool:
	var cone := cos(deg_to_rad(VIEW_CONE))
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null:
			continue
		var eye := player.head.global_position
		var to := at - eye
		var distance := to.length()
		if distance < UNSEEN_NEAREST:
			return false
		if (-player.head.global_basis.z).dot(to / distance) < cone:
			continue # behind them or off to the side
		var query := PhysicsRayQueryParameters3D.create(eye, at, 1, [player.get_rid()])
		var hit := _space.intersect_ray(query)
		if hit.is_empty() or (hit.position as Vector3).distance_to(at) < 3.0:
			return false # in plain sight
	return true


## A swarm out of sight: rats or spiders on a hall's floor, or roaches up in
## the air (near a hall's ceiling, or in the shaft's middle). Null if there's
## no hidden spot this time.
func _swarm_in(box: AABB, shaft: bool) -> RoamingGroup:
	var kind: String = "roaches" if shaft else ["rats", "roaches", "spiders"][randi() % 3]
	for attempt in 8:
		var spot: Vector3
		if kind == "roaches":
			var height := box.get_center().y if shaft else maxf(box.end.y - ROACH_BELOW_CEILING, box.position.y + 10.0)
			spot = Vector3(randf_range(box.position.x + 8.0, box.end.x - 8.0), height, randf_range(box.position.z + 8.0, box.end.z - 8.0))
		else:
			spot = _floor_in(box)
			if not spot.is_finite():
				continue
		var at := _stack.to_global(spot)
		if not _unseen(at):
			continue
		var reach := minf(box.size.x, box.size.z) * (0.35 if shaft else 0.4)
		var group := _stack.band_group(at, reach, 2.0, "Roaming_" + kind)
		_stack.fill_band(group, kind, kind == "roaches" and randf() < CARRY_BODY)
		return group
	return null


## A spot on the hall's floor (straight down from somewhere in it), local.
func _floor_in(box: AABB) -> Vector3:
	var from := Vector3(randf_range(box.position.x + 10.0, box.end.x - 10.0), box.position.y + 6.0,
			randf_range(box.position.z + 10.0, box.end.z - 10.0))
	var query := PhysicsRayQueryParameters3D.create(_stack.to_global(from), _stack.to_global(from + Vector3.DOWN * 12.0), 1)
	var hit := _space.intersect_ray(query)
	return _stack.to_local(hit.position) if not hit.is_empty() else Vector3.INF


## A spider horde on a wall near the bottom (out of sight), set to crawl up it.
func _horde_on_wall(box: AABB, shaft: bool) -> Variant:
	for attempt in 8:
		var way := Vector3.FORWARD.rotated(Vector3.UP, (randi() % 4) * PI * 0.5 + randf_range(-0.3, 0.3))
		var start := Vector3(box.get_center().x, box.position.y + 4.0, box.get_center().z)
		var query := PhysicsRayQueryParameters3D.create(_stack.to_global(start), _stack.to_global(start + way * maxf(box.size.x, box.size.z)), 1)
		var hit := _space.intersect_ray(query)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		if not _unseen(hit.position):
			continue
		var normal := hit.normal as Vector3
		var side := normal.cross(Vector3.UP).normalized()
		var pack := SPIDER_PACK.instantiate() as SpiderPack
		pack.start_count = randi_range(CLIMB_SPIDERS.x, CLIMB_SPIDERS.y)
		pack.spider_scale = _stack.infest_magnify
		pack.free_when_empty = true
		# Onward and upward, a short hop at a time.
		pack.climb = true
		pack.notice_range *= 2.0 # (the towers' spiders: twice as far, the user's)
		pack.lose_range *= 2.0
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
func _climb(place: Dictionary) -> void:
	var horde: Variant = place.horde
	if not (horde is Dictionary) or not is_instance_valid(horde.pack):
		return
	var pack := horde.pack as SpiderPack
	if pack.climb and not pack.spiders.is_empty() and pack.pack_center().y >= float(horde.top):
		pack.climb = false
		pack.home = pack.pack_center()