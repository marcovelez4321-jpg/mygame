class_name Ossuary
extends Node3D

## THE CRAWLING OSSUARY (the user's, 2026-10-25; docs/QUESTS_TRADERS_WALKERS.md):
## a massive ossuary on four very thick, sharp, spidery legs of bone -- not a
## creature, the building itself walking. The building's a TrenchBroom map
## (tools/make_the_ossuary.gd: scenes/megastructures/the_ossuary.tscn): a
## cathedral-crypt 400 x 200 m at its base and about 1 km tall -- its nave on
## its underside, the open archway at its front, twin spires (the chapel atop
## the left, the belfry atop the right), the crypts and catacombs at its back.
## The legs (OssuaryBones): three bones each (a high knee, a long shin, a sharp
## point), at its four corners, stepping in diagonal pairs, STRIDE a step, at
## SPEED; they hold its underside BODY_HEIGHT up.
##   It wanders at random over the open world (keeping clear of the Stack and
##   Grandma's: AVOID), resting every WALK_TIME for REST_TIME -- setting down
##   onto the ground (SETTLE_TIME), its legs folding up round it, so its
##   archway's on the ground and you walk in -- then rising again.
##   A foot coming down: crushed under it (CRUSH), knocked off your feet near
##   it (QUAKE), a crater left (CRATER_TIME), a boom heard BOOM_RANGE off.
##   Its legs creak as it walks; its bell tolls as it settles and as it
##   rises; a faint choir in its chapel (WalkerSound).
## Ride it: the building and its legs are moving platforms (AnimatableBody3D;
## the map's collision is taken onto the building's body).
## Rule 1 (co-op): where it is and how it stands are all worked out from one
## number -- its time, `time` (and its route's seed) -- the same on every game:
## the host's runs it and sends its time now and then (Network); every game
## builds and walks its own copy from it.

## Its bell's tolled (it's settling, or rising): every game (the Bell-wraiths
## wake: ConsumedDirector).
signal bell_tolled

const BUILDING := "res://scenes/megastructures/the_ossuary.tscn"
const BUILDING_LENGTH := 400.0
const BODY_HEIGHT := 150.0
const SPEED := 6.0
const STRIDE := 150.0
## A foot's lift at the top of its step (m), and the share of each step it
## swings (the user's, 2026-10-26: higher, snappier -- a quick whipped reach,
## then a long heavy plant: it reads from far off).
const LIFT := 140.0 # (the user's: 100, then a little more)
const SWING := 1.0 / 3.0
## The building lurching with its steps (the user's: clearly): rocking side
## to side ROCK, dropping BOB as each pair of feet comes down.
const ROCK := deg_to_rad(2.5)
const BOB := 8.0
const WALK_TIME := 600.0
const REST_TIME := 180.0
const SETTLE_TIME := 20.0
## The legs: hips at its corners, feet out at FOOT_OUT; three bones each (the
## user's: 40 m thick, sharp).
const HIP := Vector3(100.0, 12.0, 195.0)
const FOOT_OUT := Vector3(470.0, 0.0, 420.0)
const FEMUR := 430.0
const TIBIA := 380.0
const SHIN := 150.0
const FEMUR_RADIUS := 20.0
const TIBIA_RADIUS := 17.0
const SHIN_RADIUS := 15.0
## In the building (its own space; tools/ossuary_bake.gd): the chapel atop
## the left spire, its altar; the belfry atop the right.
const CHAPEL_AT := Vector3(-70.0, 900.0, -175.0)
const ALTAR_AT := Vector3(-70.0, 881.6, -171.5)
const BELL_AT := Vector3(70.0, 915.0, -175.0)
const CRUSH := 15.0
const QUAKE := 80.0
const QUAKE_SHOVE := Vector2(10.0, 6.0) # out, up (m/s)
const CRATER_TIME := 600.0
const CRATER_FADE := 30.0
const BOOM_RANGE := 1000.0
const CREAK_RANGE := 350.0
const CREAK_EVERY := Vector2(3.0, 7.0)
const BELL_RANGE := 1500.0
const CHOIR_RANGE := 220.0
## Its wandering: within WORLD_HALF of the world's middle, waypoints LEG_MIN
## to LEG_MAX apart, turning at most TURN_PER_STEP a PATH_STEP.
const WORLD_HALF := 3200.0
const LEG_MIN := 1200.0
const LEG_MAX := 2500.0
const PATH_STEP := 20.0
const TURN_PER_STEP := 0.05
const AVOID := {"TheStack": 1500.0, "GrandmasHouse": 1000.0}
const MAX_PITCH := 0.05
const SYNC_EVERY := 0.5

var route_seed := 0
var time := 0.0
## Where its route starts and which way (INF: from its seed, at random).
var start_at := Vector3.INF
var start_heading := Vector3.ZERO

var _walking_known := false
var _body: AnimatableBody3D
var _legs: Array[Dictionary] = []
var _terrain: Object
var _path := PackedVector3Array()
var _waypoints := PackedVector3Array()
var _path_dice := RandomNumberGenerator.new()
var _heading := Vector3.FORWARD
var _avoid: Array[Array] = []
var _sync_left := 0.0
var _host_time := -1.0
var _host_seen_msec := 0
var _creak_left := 2.0
var _phase_was := -1
var _choir: AudioStreamPlayer3D
var _craters: Array[Array] = [] # [decal, born msec]

static var _crater_texture: ImageTexture


## Every game: the Ossuary (once). The host picks its route: it starts far
## off, right on the edge of the fog (the user's, 2026-10-26) -- its nearest
## foot at the fog's end from you -- walking along it, so it looms there.
static func ensure(tree: SceneTree) -> void:
	if not tree.get_nodes_in_group(&"ossuary").is_empty():
		return
	var scene := tree.current_scene
	if scene == null or scene.get_node_or_null(^"Terrain3D") == null:
		return
	var walker := Ossuary.new()
	walker.name = "CrawlingOssuary"
	scene.add_child(walker)
	if Network.is_online() and not tree.get_multiplayer().is_server():
		return
	var player := PlayerMovement.local_player(tree)
	if player == null:
		walker.start(randi(), randf() * WALK_TIME)
		return
	var far := fog_edge(tree) + FOOT_OUT.x
	var seed := randi()
	var dice := RandomNumberGenerator.new()
	dice.seed = seed
	for attempt in 24:
		var out := Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU)
		var at := player.global_position + out * far
		if absf(at.x) > WORLD_HALF or absf(at.z) > WORLD_HALF or not walker._clear_way(at, at):
			continue
		var along := out.rotated(Vector3.UP, PI * 0.5 * (1.0 if dice.randf() < 0.5 else -1.0))
		walker.start(seed, 0.0, Vector3(at.x, 0.0, at.z), along)
		return
	walker.start(seed, randf() * WALK_TIME) # (nowhere clear out there: anywhere)


## Where the fog's solid from you (the world's environment), as the
## encounters reckon it.
static func fog_edge(tree: SceneTree) -> float:
	var viewport := tree.root.get_viewport()
	var environment: Environment = viewport.world_3d.environment if viewport and viewport.world_3d else null
	var camera := viewport.get_camera_3d() if viewport else null
	if environment == null and camera:
		environment = camera.environment
	return environment.fog_depth_end if environment and environment.fog_enabled and environment.fog_depth_end > 1.0 else 600.0


func _ready() -> void:
	add_to_group(&"ossuary")
	process_physics_priority = -30 # (moved before whoever's riding it: no frame behind)
	var scene := get_tree().current_scene
	_terrain = scene.get_node_or_null(^"Terrain3D")
	for node_name: String in AVOID:
		var node := scene.get_node_or_null(NodePath(node_name)) as Node3D
		if node:
			_avoid.append([node.global_position, float(AVOID[node_name])])
	_body = AnimatableBody3D.new()
	_body.name = "Building"
	_body.sync_to_physics = true
	_body.top_level = true
	add_child(_body)
	_take_building()
	var femur := OssuaryBones.leg_mesh(FEMUR, FEMUR_RADIUS, 0.85)
	var tibia := OssuaryBones.leg_mesh(TIBIA, TIBIA_RADIUS, 0.85)
	var shin := OssuaryBones.leg_mesh(SHIN, SHIN_RADIUS, 0.6, true)
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			# Diagonal pairs (the user's): front-left with back-right, then the others.
			var set_b := (side < 0.0) != (end < 0.0)
			_legs.append({side = side, end = end, offset = STRIDE * 0.5 if set_b else 0.0, planted = -999999, cache = {},
					femur = _leg_part(femur, FEMUR, FEMUR_RADIUS), tibia = _leg_part(tibia, TIBIA, TIBIA_RADIUS),
					shin = _leg_part(shin, SHIN + SHIN_RADIUS * 2.0, SHIN_RADIUS)})
	_choir = AudioStreamPlayer3D.new()
	_choir.stream = WalkerSound.pick("choir")
	_choir.max_distance = CHOIR_RANGE
	_choir.unit_size = 25.0
	_choir.volume_db = -8.0
	_body.add_child(_choir)
	_choir.position = CHAPEL_AT
	visible = false
	# Out of the way (deep under the world) till it knows where it is.
	_body.global_position = Vector3.DOWN * 5000.0
	for leg in _legs:
		for part: String in ["femur", "tibia", "shin"]:
			(leg[part] as Node3D).global_position = Vector3.DOWN * 5000.0


## The building, from its baked map, on the moving body. Its collision: one
## trimesh made from the map's solid mesh (not its thousands of brushes --
## a moving body with that many shapes would cost every frame), on the moving
## body so it carries you; the map's own static bodies left with none. Its
## decor (the crown of spikes: func_detail_illusionary) collides with nothing.
func _take_building() -> void:
	if not ResourceLoader.exists(BUILDING):
		push_warning("Ossuary: no building yet -- run tools/make_the_ossuary.gd")
		return
	var building := (load(BUILDING) as PackedScene).instantiate() as Node3D
	_body.add_child(building)
	for node in building.find_children("*", "StaticBody3D", true, false):
		var holder := node as StaticBody3D
		for child in holder.get_children():
			if child is CollisionShape3D:
				child.queue_free()
			elif child is MeshInstance3D and (child as MeshInstance3D).mesh:
				var look := child as MeshInstance3D
				var shape := CollisionShape3D.new()
				shape.shape = look.mesh.create_trimesh_shape()
				_body.add_child(shape)
				shape.transform = _body.global_transform.affine_inverse() * look.global_transform
		holder.collision_layer = 0
		holder.collision_mask = 0


## The walking building (what rides it goes on this: ConsumedDirector).
func building() -> AnimatableBody3D:
	return _body


func _leg_part(mesh: Mesh, length: float, radius: float) -> AnimatableBody3D:
	var part := AnimatableBody3D.new()
	part.sync_to_physics = true
	part.top_level = true
	var look := MeshInstance3D.new()
	look.mesh = mesh
	part.add_child(look)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = length
	shape.shape = capsule
	part.add_child(shape)
	add_child(part)
	return part


## Its route (a seed) and where along its walk it is: the host's, and every
## game's from the host's word (synced()).
func start(seed: int, at_time: float, from: Vector3 = Vector3.INF, heading: Vector3 = Vector3.ZERO) -> void:
	route_seed = seed
	time = at_time
	start_at = from
	start_heading = heading
	_path.clear()
	_waypoints.clear()
	_path_dice.seed = seed
	var first := from if from.is_finite() else _random_point(_path_dice)
	_path.append(first)
	_heading = heading.normalized() if heading.length_squared() > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, _path_dice.randf() * TAU)
	_waypoints.append(first + _heading * LEG_MAX if from.is_finite() else _next_waypoint(first))
	_walking_known = true
	for leg in _legs:
		leg.planted = -999999
		(leg.cache as Dictionary).clear()
	visible = true


## A client: the host's seed and time (late joiners start from this).
func synced(seed: int, host_time: float, from: Vector3 = Vector3.INF, heading: Vector3 = Vector3.ZERO) -> void:
	if seed != route_seed or not _walking_known:
		start(seed, host_time, from, heading)
	_host_time = host_time
	_host_seen_msec = Time.get_ticks_msec()


## The F9 menu (testing; the host's): "here" -- a new route starting 1.2 km
## off, walking straight past `player`; "rest" -- settling now.
func test(kind: StringName, player: PlayerMovement) -> String:
	match kind:
		&"here":
			var toward := Vector3(player.global_basis.z.x, 0.0, player.global_basis.z.z).normalized()
			start(randi(), 0.0, player.global_position - toward * 1200.0, toward)
			return "The Ossuary: 1.2 km in front of you, walking your way"
		&"rest":
			time = floorf(time / _cycle()) * _cycle() + WALK_TIME - 0.5
			return "The Ossuary: settling now"
	return ""


func _physics_process(delta: float) -> void:
	if not _walking_known:
		return
	time += delta
	var host := not Network.is_online() or multiplayer.is_server()
	if host:
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_EVERY
			if Network.is_online():
				Network.send_walker_time(route_seed, time, start_at, start_heading)
	elif _host_time >= 0.0:
		var theirs := _host_time + float(Time.get_ticks_msec() - _host_seen_msec) / 1000.0
		time = theirs if absf(theirs - time) > 5.0 else lerpf(time, theirs, minf(delta * 2.0, 1.0))
	var walked := _walked(time)
	var lower := _lowered(time)
	var body_xf := _body_transform(walked, lower, true)
	_body.global_transform = body_xf
	for leg in _legs:
		_pose_leg(leg, walked, body_xf, host)
	_phase_sounds()
	_creak(delta)
	_fade_craters()


# ---- Its time: walking, settling, resting, rising ----------------------------------------

func _cycle() -> float:
	return WALK_TIME + SETTLE_TIME + REST_TIME + SETTLE_TIME


## How far it's walked (m) by `t`.
func _walked(t: float) -> float:
	var n := floorf(t / _cycle())
	var u := t - n * _cycle()
	return (n * WALK_TIME + minf(u, WALK_TIME)) * SPEED


## 0 standing, 1 set down.
func _lowered(t: float) -> float:
	var u := fmod(t, _cycle())
	if u < WALK_TIME:
		return 0.0
	if u < WALK_TIME + SETTLE_TIME:
		return smoothstep(0.0, 1.0, (u - WALK_TIME) / SETTLE_TIME)
	if u < WALK_TIME + SETTLE_TIME + REST_TIME:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (u - WALK_TIME - SETTLE_TIME - REST_TIME) / SETTLE_TIME)


## 0 walking, 1 settling, 2 resting, 3 rising.
func _phase(t: float) -> int:
	var u := fmod(t, _cycle())
	if u < WALK_TIME:
		return 0
	if u < WALK_TIME + SETTLE_TIME:
		return 1
	return 2 if u < WALK_TIME + SETTLE_TIME + REST_TIME else 3


# ---- Its route --------------------------------------------------------------------------

## Where it is `s` m along its route (on the ground, flat) and which way it's
## heading. The route's made as far as it's needed, the same on every game.
func _route_at(s: float) -> Array:
	s = maxf(s, 0.0) # (its first steps: from where it starts)
	var index := int(floorf(s / PATH_STEP))
	while _path.size() < index + 3:
		_grow_path()
	var a := _path[index]
	var b := _path[index + 1]
	var t := s / PATH_STEP - float(index)
	return [a.lerp(b, t), (b - a).normalized()]


## One PATH_STEP more: turned (at most TURN_PER_STEP) toward the waypoint;
## reached, a new one.
func _grow_path() -> void:
	var last := _path[_path.size() - 1]
	var target := _waypoints[_waypoints.size() - 1]
	var to := Vector3(target.x - last.x, 0.0, target.z - last.z)
	if to.length() < 100.0:
		_waypoints.append(_next_waypoint(last))
		target = _waypoints[_waypoints.size() - 1]
		to = Vector3(target.x - last.x, 0.0, target.z - last.z)
	var turn := clampf(_heading.signed_angle_to(to.normalized(), Vector3.UP), -TURN_PER_STEP, TURN_PER_STEP)
	_heading = _heading.rotated(Vector3.UP, turn).normalized()
	_path.append(last + _heading * PATH_STEP)


func _next_waypoint(from: Vector3) -> Vector3:
	for attempt in 40:
		var angle := _path_dice.randf() * TAU
		var point := from + Vector3(cos(angle), 0.0, sin(angle)) * _path_dice.randf_range(LEG_MIN, LEG_MAX)
		if absf(point.x) > WORLD_HALF or absf(point.z) > WORLD_HALF or not _clear_way(from, point):
			continue
		return point
	return Vector3.ZERO.lerp(from, 0.3) # (boxed in: back toward the middle)


func _random_point(dice: RandomNumberGenerator) -> Vector3:
	for attempt in 60:
		var point := Vector3(dice.randf_range(-WORLD_HALF, WORLD_HALF), 0.0, dice.randf_range(-WORLD_HALF, WORLD_HALF))
		if _clear_way(point, point):
			return point
	return Vector3(WORLD_HALF * 0.8, 0.0, WORLD_HALF * 0.8)


## The way from `a` to `b` keeps clear of everything in AVOID.
func _clear_way(a: Vector3, b: Vector3) -> bool:
	for keep: Array in _avoid:
		var centre: Vector3 = keep[0]
		var flat := Vector2(centre.x, centre.z)
		var p := Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if p.distance_to(flat) < float(keep[1]):
			return false
	return true


# ---- The building and its legs ------------------------------------------------------------

func _ground(at: Vector3) -> float:
	if _terrain:
		var data: Object = _terrain.get(&"data")
		if data and data.has_method(&"get_height"):
			var height: float = data.call(&"get_height", at)
			if not is_nan(height):
				return height
	return 0.0


## The building `s` along, `lower` set down: its underside over the ground
## under it (BODY_HEIGHT up standing, on the ground set down), barely tipped;
## `lurch`: rocking and dropping with its steps (not where its feet aim).
func _body_transform(s: float, lower: float, lurch: bool = false) -> Transform3D:
	var route := _route_at(s)
	var centre: Vector3 = route[0]
	var heading: Vector3 = route[1]
	# The ground under it, averaged wide (smooth to ride: no bump from every
	# rise it passes over -- the user's: it jolted you about).
	var across := heading.cross(Vector3.UP).normalized()
	var front := 0.0
	var back := 0.0
	var base := 0.0
	for i in 5:
		var along := lerpf(-0.5, 0.5, float(i) / 4.0) * BUILDING_LENGTH
		for side: float in [-1.0, 0.0, 1.0]:
			var h := _ground(centre + heading * along + across * side * 90.0)
			base += h
			if i == 0:
				back += h
			elif i == 4:
				front += h
	base /= 15.0
	front /= 3.0
	back /= 3.0
	var pitch := clampf(atan2(front - back, BUILDING_LENGTH), -MAX_PITCH, MAX_PITCH)
	var basis := Basis.looking_at(heading, Vector3.UP)
	basis = basis * Basis(Vector3.RIGHT, pitch)
	var height := base + lerpf(BODY_HEIGHT, 0.0, lower)
	if lurch:
		var still := 1.0 - lower
		# Rocking side to side, a sway a full step (one pair, then the other).
		basis = basis * Basis(Vector3.FORWARD, ROCK * sin(TAU * s / STRIDE) * still)
		# Dropping as each pair comes down (twice a full step), easing back up.
		var half := STRIDE * 0.5
		var since := fposmod(s - STRIDE * SWING, half) / half # (0: a pair's just come down)
		var near := minf(since, 1.0 - since)
		height -= BOB * (1.0 - smoothstep(0.0, 0.35, near)) * still
	return Transform3D(basis, Vector3(centre.x, height, centre.z))


## Where leg `leg`'s foot comes down on its `k`th step: out at its corner,
## under where its hip will be mid-stride, on the ground.
func _foot_down(leg: Dictionary, k: int) -> Vector3:
	var cache: Dictionary = leg.cache
	if cache.has(k):
		return cache[k]
	var s := float(leg.offset) + float(k) * STRIDE + STRIDE * (SWING + (1.0 - SWING) * 0.5) # (mid-plant)
	var xf := _body_transform(s, 0.0)
	var at := xf * Vector3(float(leg.side) * FOOT_OUT.x, 0.0, float(leg.end) * FOOT_OUT.z)
	at.y = _ground(at)
	cache[k] = at
	if cache.size() > 4:
		cache.erase(cache.keys().min())
	return at


## The foot `s` along: swinging (the first half of its step) from where it
## last came down to the next, lifted; planted the rest (a foot coming down:
## its footfall). Its bones: the sharp shin standing up off the point, the
## femur and tibia from the hip to the shin's top, the knee high and out.
func _pose_leg(leg: Dictionary, s: float, body_xf: Transform3D, host: bool) -> void:
	var rel := s - float(leg.offset)
	var k := int(floorf(rel / STRIDE))
	var c := rel - float(k) * STRIDE
	var foot: Vector3
	if c < STRIDE * SWING:
		var a := c / (STRIDE * SWING)
		foot = _foot_down(leg, k - 1).lerp(_foot_down(leg, k), smoothstep(0.0, 1.0, a)) + Vector3.UP * LIFT * sin(PI * a)
	else:
		foot = _foot_down(leg, k)
		if int(leg.planted) < k:
			if int(leg.planted) > -999999:
				_footfall(foot, host)
			leg.planted = k
	var hip := body_xf * Vector3(float(leg.side) * HIP.x, HIP.y, float(leg.end) * HIP.z)
	var out := Vector3(foot.x - hip.x, 0.0, foot.z - hip.z).normalized()
	var ankle := foot + (Vector3.UP * 0.95 + out * 0.31).normalized() * SHIN
	var reach := clampf(hip.distance_to(ankle), 1.0, (FEMUR + TIBIA) * 0.999)
	var dir := (ankle - hip).normalized()
	var pole := (Vector3.UP * 1.4 + out) - dir * (Vector3.UP * 1.4 + out).dot(dir)
	pole = pole.normalized() if pole.length_squared() > 0.0001 else Vector3.UP
	var cos_a := clampf((FEMUR * FEMUR + reach * reach - TIBIA * TIBIA) / (2.0 * FEMUR * reach), -1.0, 1.0)
	var knee := hip + dir * FEMUR * cos_a + pole * FEMUR * sqrt(1.0 - cos_a * cos_a)
	ankle = hip + dir * reach
	(leg.femur as AnimatableBody3D).global_transform = OssuaryBones.between(knee, hip)
	(leg.tibia as AnimatableBody3D).global_transform = OssuaryBones.between(ankle, knee)
	(leg.shin as AnimatableBody3D).global_transform = OssuaryBones.between(foot, ankle)
	leg.knee = knee


# ---- Footfalls, and its sounds ------------------------------------------------------------

## A foot down at `at`: a boom heard far off, a crater, the ground shaking --
## and, the host's, whoever's under it crushed and whoever's near knocked down.
func _footfall(at: Vector3, host: bool) -> void:
	var world := get_tree().current_scene
	WalkerSound.play("footfall", at, world, BOOM_RANGE, 6.0, 80.0)
	_crater(at)
	HeartQuake.dust(world, at, 6.0)
	var me := PlayerMovement.local_player(get_tree())
	if me and me.camera and _flat_distance(me.global_position, at) < QUAKE:
		me.camera.shake(4.0)
	if not host:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var gap := _flat_distance(player.global_position, at)
		if gap < CRUSH and player.global_position.y < at.y + 25.0:
			player.health.hurt_unscaled(player.health.max_health * 10.0) # (under it)
		elif gap < QUAKE and player.is_on_floor():
			var away := Vector3(player.global_position.x - at.x, 0.0, player.global_position.z - at.z).normalized()
			player.shove(away * QUAKE_SHOVE.x + Vector3.UP * QUAKE_SHOVE.y)
	for node in get_tree().get_nodes_in_group("enemies"):
		var creature := node as Node3D
		if creature and _flat_distance(creature.global_position, at) < CRUSH and creature.global_position.y < at.y + 25.0:
			var health := creature.get_node_or_null(^"Health") as Health
			if health and health.current_health > 0.0:
				health.take_damage(health.current_health + 1.0)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Its footprint: cracked, dark ground, gone after CRATER_TIME (fading out).
func _crater(at: Vector3) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _crater_look()
	decal.size = Vector3(CRUSH * 2.4, 30.0, CRUSH * 2.4)
	decal.cull_mask = 1
	get_tree().current_scene.add_child(decal)
	decal.global_position = at
	decal.rotation.y = randf() * TAU
	_craters.append([decal, Time.get_ticks_msec()])


func _fade_craters() -> void:
	var now := Time.get_ticks_msec()
	for i in range(_craters.size() - 1, -1, -1):
		var decal := _craters[i][0] as Decal
		var age := float(now - int(_craters[i][1])) / 1000.0
		if not is_instance_valid(decal):
			_craters.remove_at(i)
		elif age > CRATER_TIME:
			decal.queue_free()
			_craters.remove_at(i)
		elif age > CRATER_TIME - CRATER_FADE:
			decal.albedo_mix = (CRATER_TIME - age) / CRATER_FADE


## A crater's look (made once): a dark pressed ring, cracks running out.
static func _crater_look() -> ImageTexture:
	if _crater_texture:
		return _crater_texture
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dice := RandomNumberGenerator.new()
	dice.seed = 99
	var cracks: Array[float] = []
	for i in 9:
		cracks.append(dice.randf() * TAU)
	var middle := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x, y) - middle
			var r := p.length() / (size * 0.5)
			var alpha := 0.0
			if r < 0.55:
				alpha = 0.75 * (1.0 - smoothstep(0.35, 0.55, r))
			var angle := p.angle()
			for crack in cracks:
				var off := absf(angle_difference(angle, crack))
				if off < 0.035 * (1.2 - r) and r < 0.98:
					alpha = maxf(alpha, 0.8 * (1.0 - r))
			image.set_pixel(x, y, Color(0.08, 0.06, 0.05, alpha))
	_crater_texture = ImageTexture.create_from_image(image)
	return _crater_texture


## The bell in its belfry: as it settles, and as it rises; the choir in its
## chapel, always.
func _phase_sounds() -> void:
	var phase := _phase(time)
	if phase != _phase_was:
		if _phase_was >= 0 and (phase == 1 or phase == 3):
			WalkerSound.play("bell", _body.global_transform * BELL_AT, get_tree().current_scene, BELL_RANGE, 4.0, 60.0)
			bell_tolled.emit()
		_phase_was = phase
	if _choir and not _choir.playing and is_inside_tree():
		_choir.play()


## Its legs creak as it walks: now and then, at one of its knees.
func _creak(delta: float) -> void:
	_creak_left -= delta
	if _creak_left > 0.0:
		return
	_creak_left = randf_range(CREAK_EVERY.x, CREAK_EVERY.y)
	if _phase(time) == 2:
		return # (still, resting)
	var leg := _legs[randi() % _legs.size()]
	if leg.has("knee"):
		WalkerSound.play("creak", leg.knee, get_tree().current_scene, CREAK_RANGE, 0.0, 30.0)
