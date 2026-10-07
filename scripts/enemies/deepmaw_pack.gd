class_name DeepmawPack
extends Node3D

## A pack of DeepmawCrawlers guarding a spot (a barnacle clump), with the
## rats' pack behaviour (RatSwarm): one brain, a few bodies. Every crawler
## has its own spot in the pack that breathes in and out and drifts round
## the others, weaves on its own rhythm, keeps a little room from its
## packmates (boids separation) and moves in stop-start bursts. They patrol
## round home. Once any of them notices a player (notice_range, and it can
## see them) the whole pack goes -- creeping in, then charging from
## charge_range -- and closes in a ring round them, darting in and out and
## churning round, each one biting or tail-swiping when it's in reach. They
## give up on anyone who leaves their ground (guard_range from home) and go
## back to guarding. Shoot one and the pack comes for you.
##
## Place one in a level, or BarnacleCluster grows one under each clump.
## Rule 1 (co-op): the host runs this.

enum Order { ROAM, HUNT }

const CRAWLER_SCENE := preload("res://scenes/enemy/deepmaw_crawler.tscn")

@export var count: int = 4
@export var crawler_speed: float = 4.5
## Patrolling, they go at this share of their speed.
@export_range(0.05, 1.0, 0.05) var roam_pace: float = 0.4
@export var pack_radius_min: float = 1.5
@export var pack_radius_max: float = 3.5
@export var separation_distance: float = 2.0
@export var separation_strength: float = 1.6

@export_group("Alive")
@export var weave_amount: float = 0.45
@export var weave_speed: float = 1.4
@export_range(0.0, 1.0, 0.05) var burstiness: float = 0.45
@export_range(0.0, 1.0, 0.05) var ebb_amount: float = 0.4
@export var ebb_speed: float = 0.2
@export var drift_speed: float = 0.25

@export_group("Guarding")
@export var notice_range: float = 12.0
## Players further than this from home are left alone (and dropped).
@export var guard_range: float = 18.0
## Far from their prey they creep in at creep_pace, then charge.
@export var charge_range: float = 7.0
@export_range(0.1, 1.0, 0.05) var creep_pace: float = 0.6
## The ring they close in on round their prey (about bite distance), darting
## in and out and churning round.
@export var engulf_radius_min: float = 1.4
@export var engulf_radius_max: float = 2.6
@export var dart_speed: float = 1.2
@export var churn_speed: float = 0.4
@export var roam_radius: float = 6.0
@export var roam_interval: float = 7.0

var order := Order.ROAM
var target: Node3D
var home := Vector3.ZERO
var crawlers: Array[DeepmawCrawler] = []

var _time := 0.0
var _lookout := 0.0
var _roam_left := 0.0
var _wander_to := Vector3.ZERO
var _threat = null
var _threat_at := -INF


func _ready() -> void:
	home = global_position
	_wander_to = home
	if count > 0:
		_spawn.call_deferred()


func _spawn() -> void:
	if not multiplayer.is_server():
		return
	var world := get_tree().current_scene
	var space := get_world_3d().direct_space_state
	for i in count:
		var crawler := CRAWLER_SCENE.instantiate() as DeepmawCrawler
		crawler.pack = self
		crawler.slot = Vector2.from_angle(TAU * i / maxf(count, 1) + randf() * 0.5)
		crawler.slot_radius = randf_range(pack_radius_min, pack_radius_max)
		var spot := home + Vector3(crawler.slot.x, 0.0, crawler.slot.y) * crawler.slot_radius
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 5.0)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		crawler.position = (hit.position as Vector3) + Vector3.UP * 0.1 if not hit.is_empty() else spot # the level's root sits at the origin
		world.add_child(crawler)
		crawlers.append(crawler)


func forget(crawler: DeepmawCrawler) -> void:
	crawlers.erase(crawler)


## One of them was hurt: the pack goes for whoever did it (if they're on
## its ground) for a while.
func threatened_by(attacker) -> void:
	if is_instance_valid(attacker) and attacker is Node3D:
		_threat = attacker
		_threat_at = Time.get_ticks_msec()
		_lookout = 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or crawlers.is_empty():
		return
	_time += delta
	_look_out(delta)
	if order == Order.ROAM:
		_roam(delta)
	var speed := crawler_speed
	if order == Order.HUNT and target and _flat(_pack_center(), target.global_position) > charge_range:
		speed *= creep_pace
	elif order == Order.ROAM:
		speed *= roam_pace
	for i in crawlers.size():
		crawlers[i].desired_velocity = _steer(crawlers[i], i, speed, delta)


func _look_out(delta: float) -> void:
	_lookout -= delta
	if _lookout > 0.0:
		return
	_lookout = 0.5
	if target and (not Factions.is_alive_target(target) or _flat(target.global_position, home) > guard_range):
		target = null
	if target == null:
		if is_instance_valid(_threat) and Time.get_ticks_msec() - _threat_at < 6000 \
				and Factions.is_alive_target(_threat) and _flat((_threat as Node3D).global_position, home) <= guard_range:
			target = _threat
		else:
			target = _noticed_player()
	order = Order.HUNT if target else Order.ROAM


## The nearest player some crawler can see within notice_range (and on the
## pack's ground).
func _noticed_player() -> Node3D:
	var best: Node3D = null
	var best_distance := notice_range
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player) or _flat(player.global_position, home) > guard_range:
			continue
		for crawler in crawlers:
			var distance := crawler.global_position.distance_to(player.global_position)
			if distance >= best_distance:
				continue
			var query := PhysicsRayQueryParameters3D.create(crawler.global_position + Vector3.UP * 0.5, Factions.aim_point(player))
			query.collision_mask = 1
			query.exclude = [crawler.get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.collider == player:
				best = player
				best_distance = distance
				break
	return best


func _roam(delta: float) -> void:
	_roam_left -= delta
	if _roam_left > 0.0 and _flat(_pack_center(), _wander_to) > 1.5:
		return
	_roam_left = randf_range(roam_interval * 0.5, roam_interval * 1.5)
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(roam_radius * 0.3, roam_radius)
	_wander_to = home + Vector3(offset.x, 0.0, offset.y)


## One crawler's velocity: toward its own spot, weaving, kept apart from the
## others, in stop-start bursts (RatSwarm._steer()).
func _steer(crawler: DeepmawCrawler, index: int, speed: float, delta: float) -> Vector3:
	if order == Order.ROAM and randf() < delta / 4.0:
		crawler.slot = Vector2.from_angle(randf() * TAU) # restless
	var spot := _spot_for(crawler)
	var to_spot := spot - crawler.global_position
	to_spot.y = 0.0
	var distance := to_spot.length()
	var push := _separation(crawler, index)
	if distance < 0.4:
		return push * speed * 0.5
	var heading := to_spot / distance
	var t := _time * weave_speed + crawler.rhythm_seed
	heading = heading.rotated(Vector3.UP, (sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3) * weave_amount)
	var velocity := (heading + push * separation_strength).normalized() * speed * crawler.speed_scale
	var wave := sin(_time * 2.4 + crawler.rhythm_seed * 3.1)
	var burst := burstiness * (0.4 if order == Order.HUNT else 1.0)
	var pace := 1.0 - burst * 0.5 * (1.0 - wave)
	if wave < -0.9 and order == Order.ROAM:
		pace = 0.0
	return velocity * pace * clampf(distance, 0.3, 1.0)


func _spot_for(crawler: DeepmawCrawler) -> Vector3:
	if order == Order.HUNT and target:
		var dart := 0.5 + 0.5 * sin(_time * dart_speed * PI + crawler.rhythm_seed * 1.3)
		var ring := lerpf(engulf_radius_min, engulf_radius_max, dart)
		var churn := churn_speed if int(crawler.rhythm_seed) % 2 == 0 else -churn_speed
		var slot := crawler.slot.rotated(_time * churn)
		return target.global_position + Vector3(slot.x, 0.0, slot.y) * ring
	var ebb := 0.5 + 0.5 * sin(_time * ebb_speed * TAU + crawler.rhythm_seed * 0.7)
	var radius := crawler.slot_radius * lerpf(1.0 - ebb_amount, 1.0 + ebb_amount, ebb)
	var drift := drift_speed if int(crawler.rhythm_seed) % 2 == 0 else -drift_speed
	var slot := crawler.slot.rotated(_time * drift)
	return _wander_to + Vector3(slot.x, 0.0, slot.y) * radius


func _separation(crawler: DeepmawCrawler, index: int) -> Vector3:
	var push := Vector3.ZERO
	var spacing := separation_distance * (0.6 if order == Order.HUNT else 1.0)
	for j in crawlers.size():
		if j == index:
			continue
		var away := crawler.global_position - crawlers[j].global_position
		away.y = 0.0
		var d := away.length()
		if d < spacing and d > 0.001:
			push += away / d * (1.0 - d / spacing)
	return push


func _pack_center() -> Vector3:
	var sum := Vector3.ZERO
	for crawler in crawlers:
		sum += crawler.global_position
	return sum / maxi(crawlers.size(), 1)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
