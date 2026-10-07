class_name SpiderPack
extends Node3D

## The brain of a pack of spiders (Spider), like RatSwarm is for rats: one
## brain, many bodies. It roams as a loose, breathing pack -- every spider
## with its own spot that drifts around the others, its own wobble, its own
## stop-start rhythm -- and when one of them notices prey the whole pack goes.
## Unlike rats, spiders need no navmesh: they go over anything (Spider crawls
## floors, walls and ceilings), so each just heads for its spot.
## Hunting, most of them (Spider.wall_preference) go up first: they make for
## the nearest wall on the way, climb it, and come at their prey across the
## wall or ceiling to get above it -- then drop on it (Spider's wall leap).
## The rest come along the floor in an engulfing ring like rats.
##
## Place one in a level and it hatches start_count spiders around itself on
## whatever surface its up (green Y arrow) points out of -- a floor, or a wall
## (Y sideways out of it) or ceiling (Y down) for a horde that starts up
## there and roams across it. A spider barnacle nest (Barnacle) makes one and
## spits its spiders into it.
## Rule 1 (co-op): the host runs this.

enum Order {
	ROAM, ## Wandering around home as a pack.
	HUNT, ## Going for the target.
}

const SPIDER_SCENE := preload("res://scenes/enemy/spider.tscn")

@export_group("Pack")
## Spiders hatched here when the level starts (0 for a nest's pack).
@export var start_count: int = 8
## Twice a rat's top speed (RatSwarm.rat_speed is 5.3).
@export var spider_speed: float = 10.6
## Patrolling, they go at this fraction of top speed: 0.5 = a rat pack's
## patrol pace (the same stop-start bursts and breathing spread too).
@export_range(0.05, 1.0, 0.05) var roam_pace: float = 0.5
## How spread out the pack sits, and how much room each keeps.
@export var pack_radius_min: float = 1.0
@export var pack_radius_max: float = 3.5
@export var separation_distance: float = 1.2
@export var separation_strength: float = 1.6
## Frees itself once every spider is dead (off for a nest's pack: more come).
@export var free_when_empty: bool = true

@export_group("Alive")
## Each spider's path wobbles (radians) on its own rhythm.
@export var weave_amount: float = 0.5
@export var weave_speed: float = 2.2
## Stop-start: 0 = smooth, 1 = dead stops between dashes.
@export_range(0.0, 1.0, 0.05) var burstiness: float = 0.6
## The pack breathes in and out and drifts around itself.
@export_range(0.0, 1.0, 0.05) var ebb_amount: float = 0.5
@export var ebb_speed: float = 0.25
@export var drift_speed: float = 0.3

@export_group("Hunting")
## A spider this close to anything it can see -- players, tweakers, rats,
## roaches (every side but its own: Factions) -- sets the pack on it. Players
## come first: if any spider sees one in range, the pack drops whatever else
## it's fighting and goes for the player.
@export var notice_range: float = 14.0
## On: only players are noticed out to notice_range, everything else only
## inside threat_range (unless it hurt the pack).
@export var prefer_players: bool = false
@export var threat_range: float = 9.0
## Lost once no spider is within this.
@export var lose_range: float = 30.0
## Far from the prey, they creep closer at this pace, then charge from
## charge_range.
@export var charge_range: float = 9.0
@export_range(0.1, 1.0, 0.05) var creep_pace: float = 0.55
## The ring floor spiders close in on around their prey.
@export var engulf_radius_min: float = 0.7
@export var engulf_radius_max: float = 2.2
@export var dart_speed: float = 1.4
@export var churn_speed: float = 0.6

@export_group("Walls")
## A wall-loving spider looks this far for a wall to go up on the way...
@export var wall_seek_range: float = 10.0
## ...takes it unless it's a detour of more than this many times the way
## straight there...
@export var wall_detour: float = 1.8
## ...and on the wall makes for a spot this high above its prey (it reaches
## the ceiling first if there is one lower), up to perch_spread off to the side.
@export var perch_height: float = 3.0
@export var perch_spread: float = 2.0

@export_group("Roaming")
## Patrol, the same as a rat pack's (RatSwarm roam_radius / roam_interval):
## a new spot within roam_radius of home (at least 30% of it out) every
## roam_interval x 0.5-1.5 seconds, or as soon as the pack gets there.
@export var roam_radius: float = 30.0
@export var roam_interval: float = 10.0
## A pack that lives on a wall patrols across it: its spots stay within this
## height of home (meters) and spread out sideways along the wall.
@export var roam_height: float = 3.0

var order := Order.ROAM
var target: Node3D
var home := Vector3.ZERO
## The surface the pack lives on (its up = out of it): roaming spots lie
## across it, so a wall horde roams the wall.
var _home_basis := Basis.IDENTITY
var spiders: Array[Spider] = []

var _time := 0.0
var _lookout := 0.0
var _roam_left := 0.0
var _wander_to := Vector3.ZERO
var _had_spiders := false
var _threat = null # untyped: may be freed by the time it's checked
var _threat_at := -INF


func _ready() -> void:
	home = global_position
	_home_basis = global_basis.orthonormalized()
	_wander_to = home
	if start_count > 0:
		_hatch_start.call_deferred()


func _hatch_start() -> void:
	if multiplayer.is_server():
		spawn_spiders(start_count, global_position)


func count() -> int:
	return spiders.size()


## New spiders around `center` on the surface there (or, given `launch`, all
## flying out from `center` along it, spread a little -- spat from a nest).
## At the game's spider cap the oldest die to make room (Population).
func spawn_spiders(amount: int, center: Vector3, launch := Vector3.ZERO) -> Array[Spider]:
	var made: Array[Spider] = []
	amount = mini(amount, Population.MAX_SPIDERS)
	Population.make_room_for_spiders(get_tree(), amount)
	var world := get_tree().current_scene
	var space := get_viewport().find_world_3d().direct_space_state
	for i in amount:
		var spider := SPIDER_SCENE.instantiate() as Spider
		spider.pack = self
		spider.slot = Vector2.from_angle(randf() * TAU)
		spider.slot_radius = randf_range(pack_radius_min, pack_radius_max)
		world.add_child(spider)
		if launch != Vector3.ZERO:
			spider.global_position = center
			var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.4
			spider.burst_out((launch.normalized() + spread).normalized() * launch.length())
		else:
			# Onto the surface the pack sits on (its up points out of it).
			var up := _home_basis.y
			var spot := center + _home_basis * Vector3(spider.slot.x, 0.0, spider.slot.y) * randf_range(0.2, 1.5)
			var query := PhysicsRayQueryParameters3D.create(spot + up * 1.0, spot - up * 3.0)
			query.collision_mask = 1
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.collider is PhysicsBody3D and not hit.collider is StaticBody3D:
				spider.global_position = spot
				spider.burst_out(Vector3.ZERO) # nothing there: drops onto whatever's under it
			else:
				spider.place_on(hit.position, hit.normal)
		spiders.append(spider)
		made.append(spider)
		_had_spiders = true
	return made


func forget(spider: Spider) -> void:
	spiders.erase(spider)


func pack_center() -> Vector3:
	var sum := Vector3.ZERO
	for spider in spiders:
		sum += spider.global_position
	return sum / maxi(spiders.size(), 1)


## Something killed or hurt one of the pack: the whole pack counts it as a
## threat for Factions.REVENGE_TIME.
func threatened_by(attacker) -> void:
	if is_instance_valid(attacker) and attacker is Node3D:
		_threat = attacker
		_threat_at = Time.get_ticks_msec()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if spiders.is_empty():
		if _had_spiders and free_when_empty:
			queue_free()
		return
	_time += delta
	_look_out(delta)
	var center := pack_center()
	if order == Order.ROAM:
		_roam(delta, center)
	var speed := spider_speed
	if order == Order.HUNT and target and center.distance_to(target.global_position) > charge_range:
		speed *= creep_pace
	elif order == Order.ROAM:
		speed *= roam_pace
	for i in spiders.size():
		var spider := spiders[i]
		if not spider.is_crawling():
			continue
		spider.desired_velocity = _steer(spider, i, speed, delta)


## Every half second: keep after the target unless it's dead or every spider
## has lost it; with none, see if any spider notices something.
func _look_out(delta: float) -> void:
	_lookout -= delta
	if _lookout > 0.0:
		return
	_lookout = 0.5
	if target and (not Factions.is_alive_target(target) or _nearest_spider_distance(target.global_position) > lose_range):
		target = null
		home = pack_center()
	# Players come first: one any spider can see within notice_range takes
	# the pack off whatever else it was after.
	if target == null or not target.is_in_group("player"):
		var player := _seen_player()
		if player:
			target = player
	if target == null:
		target = _noticed_target()
	order = Order.HUNT if target else Order.ROAM


## The nearest player some spider can see within notice_range, or null.
func _seen_player() -> Node3D:
	var best: Node3D = null
	var best_distance := notice_range
	for node in get_tree().get_nodes_in_group(Factions.GROUPS[Factions.Side.PLAYER]):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		for spider in spiders:
			var distance := spider.global_position.distance_to(player.global_position)
			if distance < best_distance and spider._sees(player):
				best = player
				best_distance = distance
				break
	return best


func _noticed_target() -> Node3D:
	var best: Node3D = null
	var best_priority := -1
	var best_distance := INF
	for candidate in Factions.hostiles(get_tree(), Factions.Side.SPIDER):
		var provoked := _pack_provoked_by(candidate)
		var reach := notice_range if provoked or not prefer_players else (notice_range if candidate.is_in_group("player") else threat_range)
		var spotter: Spider = null
		var spotter_distance := reach
		for spider in spiders:
			var distance := spider.global_position.distance_to(candidate.global_position)
			if distance < spotter_distance:
				spotter_distance = distance
				spotter = spider
		if spotter == null:
			continue
		var priority := Factions.priority_of(Factions.Side.SPIDER, Factions.side_of(candidate), null, candidate)
		if provoked:
			priority += Factions.REVENGE_BONUS
		if priority < best_priority or (priority == best_priority and spotter_distance >= best_distance):
			continue
		if spotter._sees(candidate):
			best = candidate
			best_priority = priority
			best_distance = spotter_distance
	return best


func _pack_provoked_by(candidate: Node3D) -> bool:
	if candidate == _threat and Time.get_ticks_msec() - _threat_at < Factions.REVENGE_TIME * 1000.0:
		return true
	for spider in spiders:
		if Factions.provoked_by(spider, candidate):
			return true
	return false


func _nearest_spider_distance(point: Vector3) -> float:
	var nearest := INF
	for spider in spiders:
		nearest = minf(nearest, spider.global_position.distance_to(point))
	return nearest


## On to a new spot around home now and then (or once the pack gets there).
func _roam(delta: float, center: Vector3) -> void:
	_roam_left -= delta
	var arrived := center.distance_to(_wander_to) < 2.0
	if _roam_left > 0.0 and not arrived:
		return
	_roam_left = randf_range(roam_interval * 0.5, roam_interval * 1.5)
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(roam_radius * 0.3, roam_radius)
	var step := _home_basis * Vector3(offset.x, 0.0, offset.y)
	step.y = clampf(step.y, -roam_height, roam_height) # a wall pack: along the wall
	_wander_to = home + step


## One spider's velocity (world space -- it keeps the part along its surface).
func _steer(spider: Spider, index: int, speed: float, delta: float) -> Vector3:
	var position := spider.global_position
	var spot := _spot_for(spider)
	var to_spot := spot - position
	if spider.surface_normal().y >= Spider.WALL_DOT and not (order == Order.HUNT and spider.wants_wall()):
		to_spot.y = 0.0 # on the floor, heading somewhere on the floor
	var distance := to_spot.length()
	if order == Order.ROAM and randf() < delta / 3.0:
		spider.slot = Vector2.from_angle(randf() * TAU) # restless: a new spot in the pack
	var push := _separation(spider, index)
	if distance < 0.3 and order == Order.ROAM:
		return push * speed * 0.5
	var heading := to_spot / maxf(distance, 0.001)
	# Weave around its own path: two waves, so it never looks regular.
	var t := _time * weave_speed + spider.rhythm_seed
	var wobble := (sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3) * weave_amount
	heading = heading.rotated(spider.surface_normal(), wobble)
	var velocity := (heading + push * separation_strength).normalized() * speed * spider.speed_scale
	# Dashes and freezes, on its own beat; hunting, it hardly stops.
	var wave := sin(_time * 3.1 + spider.rhythm_seed * 3.1)
	var burst := burstiness * (0.35 if order == Order.HUNT else 1.0)
	var pace := 1.0 - burst * 0.5 * (1.0 - wave)
	if wave < -0.85 and order == Order.ROAM:
		pace = 0.0
	return velocity * pace * clampf(distance, 0.3, 1.0)


## Where this spider is making for.
func _spot_for(spider: Spider) -> Vector3:
	if order != Order.HUNT or target == null:
		var ebb := 0.5 + 0.5 * sin(_time * ebb_speed * TAU + spider.rhythm_seed * 0.7)
		var radius := spider.slot_radius * lerpf(1.0 - ebb_amount, 1.0 + ebb_amount, ebb)
		var drift := drift_speed if int(spider.rhythm_seed) % 2 == 0 else -drift_speed
		var slot := spider.slot.rotated(_time * drift)
		return _wander_to + _home_basis * Vector3(slot.x, 0.0, slot.y) * radius
	var prey := target.global_position
	if spider.wants_wall():
		var perch_slot := spider.slot * perch_spread
		var perch := prey + Vector3(perch_slot.x, perch_height, perch_slot.y)
		if spider.on_wall():
			return perch
		_find_wall(spider, prey)
		if spider.has_wall_spot:
			return spider.wall_spot
	# On the floor: its own spot in a ring around the prey, darting in and
	# out and churning round them.
	var dart := 0.5 + 0.5 * sin(_time * dart_speed * PI + spider.rhythm_seed * 1.3)
	var ring := lerpf(engulf_radius_min, engulf_radius_max, dart)
	var churn := churn_speed if int(spider.rhythm_seed) % 2 == 0 else -churn_speed
	var slot := spider.slot.rotated(_time * churn)
	return prey + Vector3(slot.x, 0.0, slot.y) * ring


## The wall a wall-loving spider on the floor should go up: of the walls
## around it (eight rays, about once a second), the one that's least out of
## its way to its prey -- if any is worth the detour.
func _find_wall(spider: Spider, prey: Vector3) -> void:
	spider.wall_spot_age += get_physics_process_delta_time()
	if spider.wall_spot_age < 1.0:
		return
	spider.wall_spot_age = randf() * 0.3 # out of step with each other
	spider.has_wall_spot = false
	var from := spider.global_position + Vector3.UP * 0.2
	var straight := from.distance_to(prey)
	var best := INF
	for i in 8:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0 + spider.rhythm_seed)
		var hit := spider._surface_ray(from, from + direction * wall_seek_range)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		var spot := hit.position as Vector3
		var score := from.distance_to(spot) + spot.distance_to(prey) * 0.8
		if score < best and score < straight * wall_detour + 2.0:
			best = score
			spider.wall_spot = spot + (hit.normal as Vector3) * 0.05
			spider.has_wall_spot = true


## Boids separation: a push away from packmates too close (in 3D -- they
## crawl over each other on walls too). O(n²), fine for a pack's size.
func _separation(spider: Spider, index: int) -> Vector3:
	var push := Vector3.ZERO
	var spacing := separation_distance * spider.size * (0.6 if order == Order.HUNT else 1.0)
	var position := spider.global_position
	for j in spiders.size():
		if j == index:
			continue
		var away := position - spiders[j].global_position
		var d := away.length()
		if d < spacing and d > 0.001:
			push += away / d * (1.0 - d / spacing)
	return push
