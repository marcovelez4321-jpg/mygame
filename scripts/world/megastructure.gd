class_name Megastructure
extends Node3D

## A walk-up megastructure (docs/WORLD.md, Rule 9): kilometres tall, and you
## can reach it, climb it and go inside. Four versions of itself by
## distance, so it's a spectacle from anywhere and cheap everywhere:
##   Shell (child "Shell"): the outside -- towers, bridges, walls. Always
##   drawn (in the world's fog like everything else); casts its shadow; its
##   collision always on (you land on it, grapple it). Simple boxes: cheap.
##   Interior (child "Interior"): the insides -- floors, halls, shafts,
##   depths. Only drawn within interior_distance (its collision stays: static
##   boxes cost almost nothing).
##   Decor (child "Decor"): windows, lights, growth, things moving on it --
##   each piece sets its own draw distance.
##   Occluders: every big solid block of the shell (built by StackBuilder,
##   or any OccluderInstance3D you add): what's behind it isn't drawn.
## Its base is a lair for the boss worm (child CollisionShape3D "Lair", in
## no body, so it collides with nothing: WormDirector only reads its size).
## Barnacle nests grow on it: barnacle_nests up its outside walls (up to
## nest_height, found by rays against it), and inside on its floors
## (floor_nests: spots the builder picked) -- each of those only while a
## player's within floor_nest_reach of it, gone again once they've left, so
## a building full of them costs nothing where nobody is.
## Made from TrenchBroom: build the outside and the inside as separate maps
## (megastructure maps are 8 units a metre:
## maps/megastructures/megastructure_map_settings.tres), func_godot them, and
## put the outside's scene under Shell and the inside's under Interior.

@export var interior_distance: float = 600.0
## Its insides (local space): the whole of them (inside nests, the sound),
## and its rooms and halls one by one (where the infestation lives).
@export var inside := AABB()
@export var inside_zones: Array[AABB] = []
## Where the ground has to be holed for it (local space): its shafts and
## tunnels going down. The world bake tool punches these into the terrain.
@export var terrain_holes: Array[AABB] = []
@export_group("Nests")
@export var barnacle_nests: int = 20
## The outside nests grow up to this high (where players get to).
@export var nest_height: float = 600.0
## Its towers (local: x, height, z), if it has them: the outside nests grow
## up all of them, thicker the higher up (nest_top_density times as thick at
## the top as at the bottom -- the user's: barnacles more common the higher
## you go). Empty: up its middle to nest_height, evenly.
@export var nest_columns := PackedVector3Array()
@export var nest_top_density: float = 3.0
@export var cluster_scene: PackedScene = preload("res://scenes/enemy/barnacle_cluster.tscn")
## Spots on its floors (local space) where a nest grows while a player's near.
@export var floor_nests := PackedVector3Array()
@export var floor_nest_reach: float = 90.0
## Inside (the user's, 2026-10-17): barnacles on what stands in its halls --
## pillars, stairs, ramps (inner_nest_objects) -- and especially up its
## secret shortcut shafts (inner_nest_shafts): SHAFT_NESTS and OBJECT_NESTS.
@export var inner_nest_objects: Array[AABB] = []
@export var inner_nest_shafts: Array[AABB] = []
const SHAFT_NESTS := 6
const OBJECT_NESTS := 4
@export_group("Infestation")
## While a player's within infest_range of it, its insides are infested:
## roach swarms, spider hordes and big rat hordes, each wandering its own
## patch of a floor (RoamingGroup, staying put). Gone again once everyone's
## more than infest_range + 150 m away; far-off ones sleep meanwhile.
@export var infest_range: float = 500.0
@export var roach_swarms: int = 3
@export var spider_hordes: int = 3 # x1.5 (the user's)
@export var rat_hordes: int = 2
## Everything in its infestation is this much bigger (bites x size; health
## stays the same) -- a place not built for people breeds things to match.
## Only its own hordes: a Rat Bender's keep their size.
@export var infest_magnify: float = 2.0
@export_group("Gangs")
## Human gangs camped on its floors (the builder's spots, local; the user's:
## about one hall in three). Each is there while a player's within gang_reach
## of it and gone once everyone's left, like the floor nests. Each spot:
## x, y, z (local, on the floor), w = how far round it they wander.
@export var gang_spots := PackedVector4Array()

@export_group("Fires")
## Burning barrels (the user's): in half the window rooms (the builder's
## spots, local; fire_outs: the window's way out, for their smoke) and one
## at every gang's hangout. Each is there while a player's within fire_reach
## (far enough that their smoke columns are seen from well off); made the
## same on every machine from these spots.
@export var fire_spots := PackedVector3Array()
@export var fire_outs := PackedVector3Array()
@export var fire_reach: float = 1200.0
## Every lit window room's box (same order as fire_spots).
@export var room_boxes: Array[AABB] = []
## Each time it's played, each room rolls these (the user's: 50% each):
## a barrel, a radio, a pill bottle -- the host's roll, the same for everyone.
@export_range(0.0, 1.0, 0.05) var fire_chance: float = 0.5
@export_range(0.0, 1.0, 0.05) var radio_chance: float = 0.5
@export_range(0.0, 1.0, 0.05) var pill_chance: float = 0.5
## (Kept short: each gang is 6-12 people with ragdolls; only the ones round
## you are there.)
@export var gang_reach: float = 100.0
## A gang's people stand still (asleep: no AI, no physics) until a player's
## this close -- the halls above and below you cost nothing.
@export var gang_wake: float = 70.0
@export var gang_min: int = 6
@export var gang_max: int = 12
@export_group("Secrets")
## The Stack's secrets (StackBuilder; StackSecrets fills them each play):
## the loot rooms behind its secret doors, the hall-floor spots a key may
## lie on, and where a dead climber may be (all local).
@export var secret_rooms: Array[AABB] = []
@export var secret_keys := PackedVector3Array()
@export var secret_climbers := PackedVector3Array()
@export_group("Webs")
## Cobwebs with a spider horde each (the builder's: {at: the floor by the
## web, local; size: the web's width, m; indoors; radius: how far its
## spiders patrol round it}). A web's horde is there while a player's within
## web_reach of its patrol, gone once everyone's left (like the floor nests):
## a 2 m web 4-8 spiders, a 30 m one 20-30; indoors magnified like the rest
## of the infestation.
@export var webs: Array[Dictionary] = []
@export var web_reach: float = 120.0
## How far the camera sees (metres): enough for its top from anywhere.
@export var view_distance: float = 16000.0

const SKYLINE := preload("res://shaders/skyline.gdshader")
const ROACH := preload("res://scenes/enemy/roach.tscn")
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")
const RAT_NEST := preload("res://scenes/enemy/rat_nest.tscn")
const TWEAKERS: Array[PackedScene] = [
	preload("res://scenes/enemy/enemy.tscn"),
	preload("res://scenes/enemy/enemy_gunner.tscn"),
	preload("res://scenes/enemy/enemy_rusher.tscn"),
]
## Megastructure lairs (WormDirector picks them up).
const LAIR_GROUP := "megastructure_lairs"

var _camera_check := 0.0
var _infestation: Array[RoamingGroup] = []
## floor_nests index -> its nest, while it's grown.
var _floor_nests := {}
## webs index -> its spiders' group, while they're there.
var _web_hordes := {}
## gang_spots index -> its gang, while it's there.
var _gangs := {}
## Fire index (fire_spots, then gang_spots after them) -> its barrel.
var _fires := {}
## This play's roll (-1: not known yet -- a client waits for the host's),
## and the rooms it gave a barrel.
var _room_seed := -1
var _fire_rooms := {}
const PILLS_SCENE := preload("res://scenes/pills_pickup.tscn")


func _ready() -> void:
	var shell := get_node_or_null(^"Shell")
	if shell:
		_skyline_shell(shell)
	var interior := get_node_or_null(^"Interior")
	if interior:
		for node in interior.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			geometry.visibility_range_end = interior_distance
			geometry.visibility_range_end_margin = interior_distance * 0.1
			geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var lair := get_node_or_null(^"Lair")
	if lair:
		lair.add_to_group(LAIR_GROUP)
		lair.set_meta(&"hunger_scale", 2.0) # its home: it gets hungry here twice as fast
	if multiplayer.is_server() and barnacle_nests > 0:
		_grow_nests.call_deferred()
	# Its lines between towers and lamp posts in its halls (StackDressing).
	if not inside_zones.is_empty():
		var dressing := StackDressing.new()
		dressing.name = "Dressing"
		add_child(dressing)
	# Swarms moving through its halls and hordes climbing its walls (TowerLife).
	if not inside_zones.is_empty():
		var life := TowerLife.new()
		life.name = "TowerLife"
		add_child(life)
	if multiplayer.is_server() and (not inner_nest_shafts.is_empty() or not inner_nest_objects.is_empty()):
		_grow_inner_nests.call_deferred()
	if not secret_rooms.is_empty() or not secret_keys.is_empty():
		var secrets := StackSecrets.new()
		secrets.name = "Secrets"
		add_child(secrets)
	if not Network.is_online() or multiplayer.is_server():
		_roll_rooms(randi() % 1000000 + 1)
	else:
		_net_ask_rooms.rpc_id(1)


## The inside barnacles: SHAFT_NESTS up different shortcut shafts (a ray
## from the shaft's middle out to its wall), OBJECT_NESTS on pillars and
## stairs (a ray in at one from beside it).
func _grow_inner_nests() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var shafts := inner_nest_shafts.duplicate()
	shafts.shuffle()
	var placed := 0
	for shaft: AABB in shafts:
		if placed >= SHAFT_NESTS:
			break
		var at := Vector3(shaft.get_center().x, randf_range(shaft.position.y + 8.0, shaft.end.y - 6.0), shaft.get_center().z)
		var way := Vector3.FORWARD.rotated(Vector3.UP, (randi() % 4) * PI * 0.5)
		if _nest_by_ray(space, at, at + way * 12.0):
			placed += 1
	placed = 0
	for attempt in OBJECT_NESTS * 8:
		if placed >= OBJECT_NESTS or inner_nest_objects.is_empty():
			break
		var thing: AABB = inner_nest_objects[randi() % inner_nest_objects.size()]
		var middle := thing.get_center()
		middle.y = randf_range(thing.position.y + 1.0, thing.end.y - 0.5)
		var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var from := middle + way * (maxf(thing.size.x, thing.size.z) * 0.5 + 4.0)
		if _nest_by_ray(space, from, middle):
			placed += 1


## A nest where a ray (local) first meets something solid; false if none.
func _nest_by_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(to_global(from), to_global(to))
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not LevelGeometry.is_static(hit.collider):
		return false
	var cluster := cluster_scene.instantiate() as Node3D
	add_child(cluster)
	var normal := hit.normal as Vector3
	var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := normal.cross(reference).normalized()
	cluster.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), hit.position)
	return true


## Barnacle nests on it: rays from outside in at the walls (half), and from
## inside out at the walls and blocks there (half), each nest where one lands.
func _grow_nests() -> void:
	await get_tree().physics_frame # its collision has to be in the world first
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var grown := 0
	for attempt in barnacle_nests * 6:
		if grown >= barnacle_nests:
			return
		var outside := floor_nests.size() > 0 or grown % 2 == 0 or inside.size == Vector3.ZERO
		var direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var from: Vector3
		var to: Vector3
		if outside:
			var column := Vector3(0.0, nest_height, 0.0)
			if not nest_columns.is_empty():
				column = nest_columns[randi() % nest_columns.size()]
			var y := lerpf(8.0, column.y, _toward_top(randf()))
			from = Vector3(column.x, y, column.z) - direction * 900.0
			to = Vector3(column.x, y, column.z)
		else:
			from = inside.position + Vector3(randf(), randf(), randf()) * inside.size
			to = from + direction * 120.0
		var query := PhysicsRayQueryParameters3D.create(to_global(from), to_global(to))
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not LevelGeometry.is_static(hit.collider):
			continue
		var cluster := cluster_scene.instantiate() as Node3D
		add_child(cluster)
		var normal := hit.normal as Vector3
		var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var side := normal.cross(reference).normalized()
		cluster.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), hit.position)
		grown += 1


## A height share (0 bottom .. 1 top) for a random `u` (0..1), spread so the
## top is nest_top_density times as likely as the bottom (inverse of a
## straight-line density rising up the tower).
func _toward_top(u: float) -> float:
	var a := (nest_top_density - 1.0) * 0.5
	if absf(a) < 0.0001:
		return u
	return (-1.0 + sqrt(1.0 + 4.0 * a * u * (1.0 + a))) / (2.0 * a)


func _process(delta: float) -> void:
	_camera_check -= delta
	if _camera_check > 0.0:
		return
	_camera_check = 1.0
	var camera := get_viewport().get_camera_3d()
	if camera and camera.far < view_distance:
		camera.far = view_distance
	_update_fires()
	if multiplayer.is_server() and inside.size != Vector3.ZERO:
		_update_infestation()
	if multiplayer.is_server():
		_update_floor_nests()
		_update_webs()
		_update_gangs()


## The floor nests near a player grown; the ones nobody's near any more gone.
func _update_floor_nests() -> void:
	var players := get_tree().get_nodes_in_group("player")
	for i in floor_nests.size():
		var at := to_global(floor_nests[i])
		var nearest := INF
		for node in players:
			nearest = minf(nearest, (node as Node3D).global_position.distance_to(at))
		var nest: Node3D = _floor_nests.get(i)
		if nest != null and not is_instance_valid(nest):
			_floor_nests.erase(i)
			nest = null
		if nest == null and nearest < floor_nest_reach:
			nest = cluster_scene.instantiate() as Node3D
			nest.position = floor_nests[i] # standing up out of the floor
			add_child(nest)
			_floor_nests[i] = nest
		elif nest != null and nearest > floor_nest_reach + 50.0:
			nest.queue_free()
			_floor_nests.erase(i)


## This play's rooms (the user's: random each time): each lit window room
## rolls a barrel, a radio and a pill bottle (fire_chance, radio_chance,
## pill_chance). The radios and pills are made now; the barrels as players
## come near (_update_fires).
func _roll_rooms(seed_value: int) -> void:
	if _room_seed != -1:
		return
	_room_seed = seed_value
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	var radios := Node3D.new()
	radios.name = "RoomRadios"
	add_child(radios)
	for i in fire_spots.size():
		var box: AABB = room_boxes[i] if i < room_boxes.size() else AABB(fire_spots[i] - Vector3(3, 0, 3), Vector3(6, 3, 6))
		if dice.randf() < fire_chance:
			_fire_rooms[i] = true
		var radio_roll := dice.randf()
		var radio_at := _on_room_floor(dice, box)
		var radio_turn := dice.randf() * TAU
		var radio_model := dice.randi()
		if radio_roll < radio_chance:
			var radio := Radio.new()
			radio.model_index = radio_model % Radio.MODELS.size()
			radio.position = radio_at + Vector3.UP * 0.8
			radio.rotation.y = radio_turn
			radios.add_child(radio)
		var pill_roll := dice.randf()
		var pill_at := _on_room_floor(dice, box)
		if pill_roll < pill_chance:
			var pills := PILLS_SCENE.instantiate() as Node3D
			pills.position = pill_at + Vector3.UP * 0.5
			add_child(pills)


## A random point on a room's floor, clear of its walls (local).
static func _on_room_floor(dice: RandomNumberGenerator, box: AABB) -> Vector3:
	var inset := minf(2.5, minf(box.size.x, box.size.z) * 0.3)
	return Vector3(dice.randf_range(box.position.x + inset, box.end.x - inset), box.position.y,
			dice.randf_range(box.position.z + inset, box.end.z - inset))


## A client asks the host for this play's roll.
@rpc("any_peer", "call_remote", "reliable")
func _net_ask_rooms() -> void:
	if multiplayer.is_server() and _room_seed != -1:
		_net_rooms.rpc_id(multiplayer.get_remote_sender_id(), _room_seed)


@rpc("authority", "call_remote", "reliable")
func _net_rooms(seed_value: int) -> void:
	_roll_rooms(seed_value)


## The barrels near a player lit; the ones nobody's near put out (every
## machine, once a second: squared distances only).
func _update_fires() -> void:
	var players := get_tree().get_nodes_in_group("player")
	var reach_sq := fire_reach * fire_reach
	var count := fire_spots.size() + gang_spots.size()
	for i in count:
		var local: Vector3
		var out := Vector3.ZERO
		if i < fire_spots.size() and not _fire_rooms.has(i):
			continue # not one of this play's barrel rooms
		if i < fire_spots.size():
			local = fire_spots[i]
			out = fire_outs[i] if i < fire_outs.size() else Vector3.ZERO
		else:
			var spot := gang_spots[i - fire_spots.size()]
			local = Vector3(spot.x, spot.y, spot.z)
		var at := to_global(local)
		var near := false
		for node in players:
			if (node as Node3D).global_position.distance_squared_to(at) < reach_sq:
				near = true
				break
		var barrel: Variant = _fires.get(i)
		if barrel != null and not is_instance_valid(barrel):
			_fires.erase(i)
			barrel = null
		if barrel == null and near:
			_fires[i] = BurningBarrel.place(self, at, global_basis * out)
		elif barrel != null and not near:
			(barrel as Node).queue_free()
			_fires.erase(i)


## The floors' gangs near a player there; the ones nobody's near cleared.
func _update_gangs() -> void:
	var players := get_tree().get_nodes_in_group("player")
	for i in gang_spots.size():
		var spot := gang_spots[i]
		var at := to_global(Vector3(spot.x, spot.y, spot.z))
		var nearest := INF
		for node in players:
			nearest = minf(nearest, (node as Node3D).global_position.distance_to(at))
		var gang = _gangs.get(i) # untyped: it may have been freed
		if gang != null and not is_instance_valid(gang):
			_gangs.erase(i)
			gang = null
		if gang == null and nearest < gang_reach:
			var group := RoamingGroup.new()
			group.name = "Gang"
			group.use_navmesh = false
			group.anchor = at
			group.anchor_radius = spot.w
			group.drift_speed = 1.0
			group.sleep_distance = gang_wake
			add_child(group)
			group.global_position = at
			_fill_gang(group, randi_range(gang_min, gang_max))
			_gangs[i] = group
		elif gang != null and nearest > gang_reach + 60.0:
			(gang as RoamingGroup).disband()
			_gangs.erase(i)


## A gang's people added one a frame (each is a body, a ragdoll and a gun:
## all at once is a hitch).
func _fill_gang(group: RoamingGroup, count: int) -> void:
	for member in count:
		if not is_instance_valid(group) or not group.is_inside_tree():
			return
		_member(group, TWEAKERS[randi() % TWEAKERS.size()].instantiate(), member)
		await get_tree().process_frame


## The webs near a player with their spiders; the ones nobody's near cleared.
func _update_webs() -> void:
	var players := get_tree().get_nodes_in_group("player")
	for i in webs.size():
		var web: Dictionary = webs[i]
		var at := to_global(web.at)
		var nearest := INF
		for node in players:
			nearest = minf(nearest, (node as Node3D).global_position.distance_to(at))
		var horde = _web_hordes.get(i) # untyped: it may have been freed
		if horde != null and not is_instance_valid(horde):
			_web_hordes.erase(i)
			horde = null
		var reach := web_reach + float(web.radius)
		if horde == null and nearest < reach:
			_web_hordes[i] = _web_horde(web)
		elif horde != null and nearest > reach + 60.0:
			(horde as RoamingGroup).disband()
			_web_hordes.erase(i)


## A web's spiders: a pack staying on its patch round the web, more of them
## the bigger it is.
func _web_horde(web: Dictionary) -> RoamingGroup:
	var big := clampf(inverse_lerp(2.0, 30.0, float(web.size)), 0.0, 1.0)
	var group := RoamingGroup.new()
	group.name = "WebSpiders"
	group.use_navmesh = false
	group.anchor = to_global(web.at)
	group.anchor_radius = float(web.radius)
	group.drift_speed = 0.8
	add_child(group)
	group.global_position = group.anchor
	var pack := SPIDER_PACK.instantiate() as SpiderPack
	pack.start_count = randi_range(roundi(lerpf(4.0, 20.0, big)), roundi(lerpf(8.0, 30.0, big)))
	pack.spider_scale = infest_magnify if web.indoors else 1.0
	_member(group, pack, 0)
	return group


## Infested while someone's near; cleared once everyone's well away.
func _update_infestation() -> void:
	var nearest := INF
	var middle := to_global(inside.get_center())
	for node in get_tree().get_nodes_in_group("player"):
		var at := (node as Node3D).global_position
		nearest = minf(nearest, Vector2(at.x - middle.x, at.z - middle.z).length())
	var live: Array[RoamingGroup] = []
	for group in _infestation:
		if is_instance_valid(group):
			live.append(group)
	_infestation = live
	if nearest < infest_range and _infestation.is_empty():
		_infest()
	elif nearest > infest_range + 150.0 and not _infestation.is_empty():
		for group in _infestation:
			group.disband()
		_infestation.clear()


## Each group within the frame budget (FrameBudget: the whole infestation in
## one frame was the worst stutter by the Stack, ~87 ms).
func _infest() -> void:
	for i in roach_swarms:
		while FrameBudget.over():
			await get_tree().process_frame
		var group := _floor_group("Roaches")
		if group:
			for r in randi_range(6, 12):
				while FrameBudget.over():
					await get_tree().process_frame
				if not is_instance_valid(group):
					break
				var roach := ROACH.instantiate() as FlyingRoach
				roach.size = infest_magnify
				_member(group, roach, r, 1.5 * infest_magnify)
	for i in spider_hordes:
		while FrameBudget.over():
			await get_tree().process_frame
		var group := _floor_group("Spiders")
		if group:
			var pack := SPIDER_PACK.instantiate() as SpiderPack
			pack.start_count = randi_range(12, 20)
			pack.spider_scale = infest_magnify
			_member(group, pack, 0)
	for i in rat_hordes:
		while FrameBudget.over():
			await get_tree().process_frame
		var group := _floor_group("Rats")
		if group:
			var nest := RAT_NEST.instantiate() as RatNest
			nest.rat_count = randi_range(15, 22) # x2 (leaderless): 30-44
			nest.bodyguard_count = randi_range(2, 3)
			var swarm := nest.get_node(^"RatSwarm") as RatSwarm
			swarm.rat_scale = infest_magnify
			swarm.rat_damage_multiplier = infest_magnify
			swarm.separation_distance *= infest_magnify
			_member(group, nest, 0)


## A band wandering round `at` (global) within `radius` (TowerLife's roaming
## swarms), added and counted as part of its infestation.
func band_group(at: Vector3, radius: float, drift: float, name_: String) -> RoamingGroup:
	var group := RoamingGroup.new()
	group.name = name_
	group.use_navmesh = false
	group.anchor = to_local(at)
	group.anchor_radius = radius
	group.drift_speed = drift
	add_child(group)
	group.global_position = at
	return group


## Fills a band with its kind, within the frame budget: "rats", "roaches"
## (`body`: with a dead person among them for the roaches to carry off) or
## "spiders" -- the infestation's own sizes.
func fill_band(group: RoamingGroup, kind: String, body: bool = false) -> void:
	match kind:
		"roaches":
			for r in randi_range(6, 12):
				while FrameBudget.over():
					await get_tree().process_frame
				if not is_instance_valid(group):
					return
				var roach := ROACH.instantiate() as FlyingRoach
				roach.size = infest_magnify
				_member(group, roach, r, 1.5 * infest_magnify)
			if body and is_instance_valid(group):
				# A dead person (or a climber who didn't make it) for them to lift.
				var dead := (load("res://scenes/enemy/enemy.tscn") as PackedScene).instantiate() as Enemy
				dead.can_mutate = false
				dead.corpse_time = 1.0e9
				dead.set_meta(&"climber", true) # (stays while its band does)
				dead.set_meta(&"culled", true) # nothing to drop
				_member(group, dead, 3)
				var health := dead.get_node(^"Health") as Health
				health.take_damage(health.current_health + 1.0)
		"spiders":
			var pack := SPIDER_PACK.instantiate() as SpiderPack
			pack.start_count = randi_range(12, 20)
			pack.spider_scale = infest_magnify
			# The towers' roaming spiders see you from twice as far (the user's).
			pack.notice_range *= 2.0
			pack.lose_range *= 2.0
			_member(group, pack, 0)
		_:
			var nest := RAT_NEST.instantiate() as RatNest
			nest.rat_count = randi_range(15, 22)
			nest.bodyguard_count = randi_range(2, 3)
			var swarm := nest.get_node(^"RatSwarm") as RatSwarm
			swarm.rat_scale = infest_magnify
			swarm.rat_damage_multiplier = infest_magnify
			swarm.separation_distance *= infest_magnify
			_member(group, nest, 0)


## A group staying on a patch of floor somewhere inside, or null if no
## floor turned up.
func _floor_group(what: String) -> RoamingGroup:
	var spot := _inside_spot()
	if not spot.is_finite():
		return null
	var group := RoamingGroup.new()
	group.name = "Infestation_" + what
	group.use_navmesh = false
	group.anchor = spot
	group.anchor_radius = 45.0
	group.drift_speed = 0.8
	add_child(group)
	group.global_position = spot
	_infestation.append(group)
	return group


func _member(group: RoamingGroup, member: Node, index: int, lift: float = 0.0) -> void:
	var around := Vector2.from_angle(index * 2.4 + randf()) * (0.0 if index == 0 else randf_range(1.5, 4.0))
	(member as Node3D).position = Vector3(around.x, lift, around.y)
	group.add_child(member)


## A spot on a floor inside (a random point in `inside`, straight down onto
## whatever's under it), or a non-finite vector if none turned up.
func _inside_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	for attempt in 30:
		var zone := inside if inside_zones.is_empty() else inside_zones[randi() % inside_zones.size()]
		var from := to_global(zone.position + Vector3(randf(), randf(), randf()) * zone.size)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and LevelGeometry.is_static(hit.collider) and (hit.normal as Vector3).y > 0.7:
			return hit.position
	return Vector3.INF


## The shell's materials made skyline (texture and colour kept), unless
## they already are.
func _skyline_shell(shell: Node) -> void:
	var converted := {}
	for node in shell.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.get_active_material(surface)
			if original is ShaderMaterial and (original as ShaderMaterial).shader == SKYLINE:
				continue
			if not converted.has(original):
				converted[original] = _skyline_material(original as BaseMaterial3D)
			mesh_instance.set_surface_override_material(surface, converted[original])


func _skyline_material(base: BaseMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SKYLINE
	if base:
		if base.albedo_texture:
			material.set_shader_parameter("albedo_texture", base.albedo_texture)
		material.set_shader_parameter("albedo_color", base.albedo_color)
	return material
