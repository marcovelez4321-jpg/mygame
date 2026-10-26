class_name TraderDirector
extends RefCounted

## Where the traders are (the user's, 2026-10-25; the host's, as the level
## starts -- every game sees them through NetEntities):
##   PARKED: one at each landmark -- under the Flesh Tree (among its roots, on
##   the side the road out leaves from), and at the Stack's plateau edge (where
##   the land drops from it, toward Grandma's) -- and three up the Stack at
##   STACK_HEIGHTS, each session on a new spot near that height: a skybridge or
##   a block-top terrace (open ground found by rays down), or a room grown onto
##   a tower, WINDOW_CHANCE of the time a lit window room.
##   WANDERERS: WANDERERS of them, spread out (the user's, 2026-10-26: never
##   next to each other, each its own route): each walks its own third of the
##   world round Grandma's. The first the road between Grandma's yard edge and
##   the Stack's plateau edge, by WILD_STOPS rests out in the wilds each way;
##   the others LOOP_STOPS rests in a loop out in their own wilds,
##   LOOP_RADIUS from Grandma's. Each starts out on its own route, at the stop
##   furthest from every other trader. New landmarks join the routes as
##   they're made.

const WANDERERS := 3
const WILD_STOPS := 2
const WILD_SIDEWAYS := Vector2(80.0, 200.0)
const LOOP_STOPS := 5
const LOOP_RADIUS := Vector2(900.0, 2800.0)
## Its share of the world: this far either side of its third's middle.
const LOOP_SPREAD := 0.8
const WORLD_EDGE := 3500.0
const STACK_HEIGHTS := [400.0, 2000.0, 4000.0]
const WINDOW_CHANCE := 0.1
## Under the Flesh Tree: this far out past its trunk.
const UNDER_TREE := 12.0
## Grandma's yard edge, from her house toward the Stack.
const YARD_EDGE := 60.0
## The plateau's edge: where the land's this far below the Stack's foot.
const PLATEAU_DROP := 4.0
## Rays down for open ground up the Stack, per height.
const LEDGE_RAYS := 400


static func ensure(tree: SceneTree) -> void:
	if Network.is_online() and not tree.get_multiplayer().is_server():
		return
	if not tree.get_nodes_in_group(&"trader_keeper").is_empty():
		return
	var scene := tree.current_scene
	if scene == null:
		return
	var house := scene.get_node_or_null(^"GrandmasHouse") as Node3D
	var stack := scene.get_node_or_null(^"TheStack") as Megastructure
	if house == null or stack == null:
		return
	var terrain := scene.get_node_or_null(^"Terrain3D")
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	var toward := _flat(stack.global_position - house.global_position)
	# Under the Flesh Tree.
	var flesh_tree := scene.get_node_or_null(^"FleshTree") as Node3D
	var tree_at := flesh_tree.global_position if flesh_tree else house.global_position
	var trunk := float(flesh_tree.get(&"trunk_width")) * 0.5 if flesh_tree and flesh_tree.get(&"trunk_width") != null else 12.5
	var plans := {}
	var under := _on_ground(terrain, tree_at + toward * (trunk + UNDER_TREE))
	plans["grandma"] = {at = under, facing = toward.rotated(Vector3.UP, PI * 0.5), parked = true}
	# The Stack's plateau edge.
	var edge := _plateau_edge(terrain, stack.global_position, -toward)
	plans["stack_base"] = {at = edge, facing = toward, parked = true}
	# Up the Stack.
	for height: float in STACK_HEIGHTS:
		var spot := _stack_spot(stack, height, dice)
		if spot.is_finite():
			plans["stack_%d" % int(height)] = {at = spot, facing = Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU), parked = true}
	# The wanderers, each its own third of the world.
	var yard := _on_ground(terrain, house.global_position + toward * YARD_EDGE)
	var foot := edge + toward.rotated(Vector3.UP, PI * 0.5) * 15.0 # (beside the one parked there)
	var taken: Array[Vector3] = [under, edge] # (where traders already are)
	for w in WANDERERS:
		var route := PackedVector3Array()
		if w == 0:
			# The road: Grandma's yard, the wilds, the Stack's plateau, back.
			route.append(yard)
			for there_and_back in 2:
				var from := yard if there_and_back == 0 else foot
				var to := foot if there_and_back == 0 else yard
				for s in WILD_STOPS:
					var along := from.lerp(to, float(s + 1) / float(WILD_STOPS + 1))
					var side := toward.rotated(Vector3.UP, PI * 0.5) * dice.randf_range(WILD_SIDEWAYS.x, WILD_SIDEWAYS.y) * (1.0 if dice.randf() < 0.5 else -1.0)
					route.append(_on_ground(terrain, along + side))
				if there_and_back == 0:
					route.append(foot)
		else:
			# A loop out in its own wilds: stops round its third, in order.
			var middle := toward.rotated(Vector3.UP, TAU * float(w) / float(WANDERERS))
			for s in LOOP_STOPS:
				var turn := lerpf(-LOOP_SPREAD, LOOP_SPREAD, float(s) / float(LOOP_STOPS - 1))
				var out := middle.rotated(Vector3.UP, turn + dice.randf_range(-0.1, 0.1))
				var at := house.global_position + out * dice.randf_range(LOOP_RADIUS.x, LOOP_RADIUS.y)
				at.x = clampf(at.x, -WORLD_EDGE, WORLD_EDGE)
				at.z = clampf(at.z, -WORLD_EDGE, WORLD_EDGE)
				route.append(_on_ground(terrain, at))
		# It starts at the stop furthest from every trader placed so far.
		var leg := 0
		var best := -1.0
		for i in route.size():
			var nearest := INF
			for other in taken:
				nearest = minf(nearest, Vector2(route[i].x - other.x, route[i].z - other.z).length())
			if nearest > best:
				best = nearest
				leg = i
		var start := route[leg]
		taken.append(start)
		var next := (leg + 1) % route.size()
		plans["wanderer_%d" % w] = {at = start, facing = _flat(route[next] - start), parked = false, route = route, leg = next}
	# The keeper: spawns them (a wreck where one died; none yet till the
	# replacement's due), and the replacements as they come.
	var keeper := TraderKeeper.new()
	keeper.plans = plans
	scene.add_child(keeper)


## A trader from its plan (a replacement: `fresh`, starting its route over).
static func spawn(scene: Node, id: String, plan: Dictionary, fresh: bool = false) -> Trader:
	var trader := Trader.new()
	trader.name = "Trader_%s" % id
	trader.trader_id = id
	trader.parked = bool(plan.parked)
	trader.look_seed = randi_range(1, 1 << 20)
	var at: Vector3 = plan.at
	var facing: Vector3 = plan.facing
	if plan.has("route"):
		trader.route = plan.route
		trader.set(&"_leg", 1 if fresh else int(plan.leg))
		if fresh:
			at = (plan.route as PackedVector3Array)[0]
			facing = _flat((plan.route as PackedVector3Array)[1] - at)
	scene.add_child(trader)
	trader.global_transform = Transform3D(Basis.looking_at(_flat(facing), Vector3.UP), at)
	return trader


## From the Stack's foot out `out` until the land's dropped PLATEAU_DROP.
static func _plateau_edge(terrain: Node, foot: Vector3, out: Vector3) -> Vector3:
	var top := _height(terrain, foot)
	var at := foot
	for step in range(20, 1500, 5):
		at = foot + out * float(step)
		if _height(terrain, at) < top - PLATEAU_DROP:
			return _on_ground(terrain, foot + out * float(step - 10))
	return _on_ground(terrain, foot + out * 200.0)


## A spot up the Stack near `height` (above its foot): a room grown onto a
## tower, open ground (a skybridge, a terrace), or -- WINDOW_CHANCE -- a lit
## window room. INF if there's none.
static func _stack_spot(stack: Megastructure, height: float, dice: RandomNumberGenerator) -> Vector3:
	var picks: Array[Vector3] = []
	if dice.randf() < WINDOW_CHANCE:
		for room in stack.room_boxes:
			if absf(room.get_center().y - height) < 150.0:
				picks.append(stack.to_global(Megastructure._on_room_floor(dice, room)))
	if picks.is_empty():
		for room in stack.secret_rooms:
			if absf(room.position.y - height) < 150.0:
				picks.append(stack.to_global(Megastructure._on_room_floor(dice, room)))
		picks.append_array(_open_ledges(stack, height, dice))
	if picks.is_empty():
		return Vector3.INF
	return picks[dice.randi() % picks.size()]


## Open ground near `height`: rays down onto the Stack's flat tops (out in
## the open: not inside its halls or rooms).
static func _open_ledges(stack: Megastructure, height: float, dice: RandomNumberGenerator) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var space := stack.get_world_3d().direct_space_state
	var area := stack.inside if stack.inside.size != Vector3.ZERO else AABB(Vector3(-300, 0, -300), Vector3(600, 5000, 600))
	for i in LEDGE_RAYS:
		var local := Vector3(dice.randf_range(area.position.x, area.end.x), height + 60.0, dice.randf_range(area.position.z, area.end.z))
		var from := stack.to_global(local)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0, 1))
		if hit.is_empty() or (hit.normal as Vector3).y < 0.9:
			continue
		var landed := stack.to_local(hit.position)
		if absf(landed.y - height) > 120.0:
			continue
		var indoors := false
		for zone in stack.inside_zones:
			if zone.grow(1.0).has_point(landed):
				indoors = true
				break
		if not indoors:
			found.append(hit.position)
	return found


static func _height(terrain: Node, at: Vector3) -> float:
	if terrain:
		var data: Object = terrain.get(&"data")
		if data and data.has_method(&"get_height"):
			var h: float = data.call(&"get_height", at)
			if not is_nan(h):
				return h
	return at.y


static func _on_ground(terrain: Node, at: Vector3) -> Vector3:
	return Vector3(at.x, _height(terrain, at), at.z)


static func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
