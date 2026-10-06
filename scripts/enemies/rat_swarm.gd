class_name RatSwarm
extends Node

## The brain of a Rat Bender's horde: tells up to rat_cap rats (Rat) where to
## run. One brain, many bodies -- the expensive thinking happens once here:
##   - ONE navigation path per swarm, refreshed every path_interval seconds,
##     and every rat borrows it. No rat ever pathfinds on its own.
##   - Each rat then just steers along that shared path, keeping a little
##     space from its neighbours -- Craig Reynolds' "boids" (1987) separation
##     rule -- while real physics bumps them off props, doors and each other,
##     so the pack pours around obstacles like water. Where the path can't
##     reach (a drop below a ledge), they run straight and spill over.
##
## A plain Node, not Node3D: the rats are physics bodies living in world
## space, so they mustn't move along with whoever owns the swarm.
##
## Rule 1 (co-op): the host runs this; clients will get rat positions synced
## at a low rate and smooth between them.

## What the pack is doing (set by the Rat Bender).
enum Order {
	FOLLOW, ## Around the Bender's feet (and eating any corpse nearby).
	HUNT,   ## Swarming the player as a horde.
}

const RAT_SCENE := preload("res://scenes/enemy/rat.tscn")
const CORPSE_GROUP := "corpses"

@export_group("Pack")
@export var rat_speed: float = 5.3
## Every rat this swarm brings up is this much bigger, and has this many
## times the health, on top of its own little variety. 1 = normal rats.
@export var rat_scale: float = 1.0
@export var rat_health_multiplier: float = 1.0
## ...and bites (and leap-bites) this many times harder.
@export var rat_damage_multiplier: float = 1.0
## Hunting, this pack never goes more than this many meters from the Bender
## -- loyal packs swarm you only while you're near him. 0 = no leash.
@export var leash_distance: float = 0.0
## Following the Bender, rats spread between these distances around him.
@export var follow_radius_min: float = 0.9
@export var follow_radius_max: float = 2.4

## Rats this close to each other push apart (boids separation).
@export var separation_distance: float = 0.45
@export var separation_strength: float = 1.5
## Seconds between path updates (the one path everyone shares).
@export var path_interval: float = 0.3

@export_group("Alive")
## What makes it read as a living swarm instead of a formation. From real
## rats (they move in quick stop-start bursts and stream nose-to-tail along
## each other's trails) and game hordes that flow like a liquid: A Plague
## Tale's rat tides, World War Z's swarms, Dishonored's corpse-stripping rats.
## Each rat zig-zags this much (radians, either side) as it runs...
@export var weave_amount: float = 0.6
## ...this fast (wiggles a second, each rat at its own rhythm).
@export var weave_speed: float = 1.6
## Rats steer to match their neighbours' heading (boids alignment), which
## turns a crowd into streams and currents.
@export var alignment_strength: float = 0.6
@export var neighbour_distance: float = 1.2
## Stop-start bursts: each rat's pace rises and falls on its own rhythm; at
## the bottom of a dip it stops for a beat. 0 = steady.
@export_range(0.0, 1.0, 0.05) var burstiness: float = 0.45
## Ebb and flow while not fighting: each rat's distance from the middle of
## the pack swells and shrinks by up to ebb_amount (0.5 = half again in or
## out), ebb_speed times a second on its own beat, while it slowly drifts
## around the others at drift_speed radians a second -- so the pack
## stretches, contracts and churns instead of holding a formation.
@export_range(0.0, 1.0, 0.05) var ebb_amount: float = 0.5
@export var ebb_speed: float = 0.2
@export var drift_speed: float = 0.25
## Resting rats don't stand still: every this-many seconds (roughly) each one
## scurries to a new spot in the pack.
@export var restless_time: float = 3.0

@export_group("Horde")
## Hunting, the pack engulfs the player: each rat claims a spot somewhere in
## a ring between these distances all the way around them, and darts in
## (to bite) and back out on its own rhythm, while the whole ring slowly
## churns around -- a writhing mass on every side instead of a queue.
@export var engulf_radius_min: float = 0.25
@export var engulf_radius_max: float = 1.4
## Darts in and out per second (each rat on its own beat).
@export var dart_speed: float = 1.3
## How fast the ring churns around the player, radians per second.
@export var churn_speed: float = 0.5
## The Bender's spells whip the horde into a frenzy: this much faster, and
## biting this many times as often, wearing off over frenzy_time seconds.
@export var frenzy_speed: float = 2.7
@export var frenzy_bite_rate: float = 2.0
@export var frenzy_time: float = 5.0

@export_group("Summoning")
## Summoned rats burrow up one after another over this many seconds.
@export var spawn_spread: float = 1.2
## Size of the patch of floor around his feet they burrow up through
## (1 = a tight ring; it also widens with how many come up at once).
@export var spawn_circle_scale: float = 2.2

@export_group("Without a Bender")
## A pack with no Bender (a rat nest, or his horde after he dies) roams
## around `home`. The moment ANY rat is within notice_range of a player it
## can see, the whole pack knows: they creep over at creep_speed, and charge
## in once the pack is within charge_range of them. More than lose_range
## from every rat and they lose interest and roam where they are.
@export var notice_range: float = 10.0
@export var charge_range: float = 5.0
@export_range(0.1, 1.0, 0.05) var creep_speed: float = 0.5
@export var lose_range: float = 25.0
## Patrolling: the pack wanders between random walkable spots up to
## roam_radius from home -- a new one when it gets there, or after about
## roam_interval seconds -- heading for any body within corpse_seek_range
## instead, to eat it.
@export var roam_radius: float = 15.0
@export var roam_interval: float = 10.0
@export var corpse_seek_range: float = 20.0

@export_group("Corpse Dragging")
## A pack of at least drag_min_rats near a body (drag_find_range from its
## middle) sometimes -- drag_chance a second -- splits up: drag_share of the
## rats (at least 4) haul the body drag_distance away at drag_speed, then eat
## it for eat_time seconds. The rest carry on, attacking you included.
@export var drag_min_rats: int = 8
@export_range(0.0, 1.0, 0.05) var drag_chance: float = 0.15
@export var drag_find_range: float = 10.0
@export_range(0.1, 1.0, 0.05) var drag_share: float = 0.4
@export var drag_distance_min: float = 3.0
@export var drag_distance_max: float = 6.0
@export var drag_speed: float = 1.2
@export var eat_time: float = 6.0

@export_group("Eating")
## Not fighting: rats go and eat a corpse this close to the Bender.
@export var eat_range: float = 8.0

@export_group("Sound")
## One scurrying loop for the whole pack, at its middle -- not one per rat.
@export var scurry_sound: SoundEvent
@export var bite_sound: SoundEvent

enum DragPhase { NONE, GATHER, DRAG, EAT }

var bender: Node3D
var order := Order.FOLLOW
## Where a pack with no Bender roams around.
var home := Vector3.ZERO:
	set(value):
		home = value
		_wander_to = value
var _wander_to := Vector3.ZERO
var _roam_timer := 0.0
var _lookout_timer := 0.0
var _drag_phase := DragPhase.NONE
var _drag_body: Node3D
var _drag_ragdoll: EnemyRagdoll
var _drag_body_pos := Vector3.ZERO
var _drag_to := Vector3.ZERO
## The walkable route to _drag_to, and stuck-checking while hauling.
var _drag_path := PackedVector3Array()
var _drag_check_pos := Vector3.ZERO
var _drag_stuck_timer := 0.0
var _drag_timer := 0.0
var _drag_check := 2.0
var _draggers: Array[Rat] = []
## Has had rats at some point -- an empty pack only cleans itself up after
## that (a fresh nest is empty for a frame before its rats are spawned).
var _had_rats := false
var target: Node3D
var rats: Array[Rat] = []

var _frenzy_left := 0.0
var _time := 0.0
## This tick's rat positions and velocities (read once, used many times),
## and a grid of which rats are in which square -- so each rat only checks
## the rats in its own and the 8 surrounding squares for crowding, not the
## whole horde (with 90 rats: a few hundred checks instead of ~8,000).
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _cells := {} # Vector2i -> Array of rat indices
var _path := PackedVector3Array()
var _path_timer := 0.0
var _corpse: Node3D
var _scurry: AudioStreamPlayer3D
var _scurry_anchor: Node3D


func _ready() -> void:
	_scurry_anchor = Node3D.new()
	add_child.call_deferred(_scurry_anchor)


func count() -> int:
	return rats.size()


## New rats burrowing up out of the floor right around `center` (the
## Bender's feet), one after another over about spawn_spread seconds (or
## `spread`, if given). The more there are, the wider the patch of floor.
func spawn_rats(amount: int, center: Vector3, spread: float = -1.0) -> void:
	var world := get_tree().current_scene
	var space := get_viewport().find_world_3d().direct_space_state
	var reach := (0.6 + 0.12 * sqrt(float(amount))) * spawn_circle_scale
	for i in amount:
		var rat := RAT_SCENE.instantiate() as Rat
		rat.swarm = self
		var angle := randf() * TAU
		rat.slot = Vector2.from_angle(angle)
		rat.slot_radius = randf_range(follow_radius_min, follow_radius_max)
		rat.emerge_delay = randf() * (spawn_spread if spread < 0.0 else spread)
		var spot := center + Vector3(rat.slot.x, 0.0, rat.slot.y) * randf_range(0.4 * spawn_circle_scale, reach)
		# Onto the floor there (or where he stands, if there's none).
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 3.0)
		query.collision_mask = 1
		if bender:
			query.exclude = [(bender as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		world.add_child(rat)
		rat.global_position = hit.position if not hit.is_empty() else spot
		rats.append(rat)
		_had_rats = true


func forget(rat: Rat) -> void:
	rats.erase(rat)
	_draggers.erase(rat)


## The middle of the pack.
func pack_center() -> Vector3:
	var sum := Vector3.ZERO
	for rat in rats:
		sum += rat.global_position
	return sum / maxi(rats.size(), 1)


## How close the nearest rat is to `point` (INF with no rats).
func nearest_rat_distance(point: Vector3) -> float:
	var nearest := INF
	for rat in rats:
		nearest = minf(nearest, rat.global_position.distance_squared_to(point))
	return sqrt(nearest)


## A Bender spell: the whole horde goes for the player in a frenzy.
func frenzy() -> void:
	order = Order.HUNT
	_frenzy_left = frenzy_time


## The Bender's close-range spell: a frenzy, plus every rat near the player
## leaps at them in a quick ripple, one after another.
func leap_wave(within: float, stagger: float) -> void:
	frenzy()
	leap_at(within, stagger)


## Every rat within `within` of the target leaps at them, `stagger` seconds
## apart (the Bender's bodyguards pounce this way, without a frenzy).
func leap_at(within: float, stagger: float) -> void:
	if target == null:
		return
	var delay := 0.0
	for rat in rats:
		if rat.global_position.distance_to(target.global_position) <= within:
			get_tree().create_timer(delay).timeout.connect(_leap.bind(rat))
			delay += stagger


func _leap(rat: Rat) -> void:
	if is_instance_valid(rat) and is_instance_valid(target):
		rat.leap(target)


## How much of the frenzy is left, 1 = just cast, 0 = worn off.
func _frenzy() -> float:
	return clampf(_frenzy_left / maxf(frenzy_time, 0.01), 0.0, 1.0)


## Rats bite this many times faster than their own bite_interval right now.
func bite_rate() -> float:
	return lerpf(1.0, frenzy_bite_rate, _frenzy())


func rat_bit(at: Vector3) -> void:
	SoundPlayer.play_3d(bite_sound, at, get_tree().current_scene)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(bender):
		bender = null
	if not multiplayer.is_server() or rats.is_empty():
		_update_scurry(Vector3.ZERO, false)
		if bender == null and rats.is_empty() and _had_rats and multiplayer.is_server():
			queue_free() # leader and pack both gone
		return
	if not is_instance_valid(target):
		target = null
	if bender == null:
		_look_out(delta)
	_frenzy_left = maxf(_frenzy_left - delta, 0.0)

	_build_grid()
	var center := Vector3.ZERO
	for p in _pos:
		center += p
	center /= rats.size()
	_update_drag(delta, center)
	if bender == null and order == Order.FOLLOW:
		_roam(delta, center)

	var goal := _goal()
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = path_interval
		_refresh_path(center, goal)
		_corpse = _find_corpse(center) if order == Order.FOLLOW else null

	_time += delta
	var speed := rat_speed * lerpf(1.0, frenzy_speed, _frenzy())
	# A leaderless pack creeps up on a player it's noticed, then charges.
	if bender == null and target and center.distance_to(target.global_position) > charge_range:
		speed *= creep_speed
	var any_moving := false
	for i in rats.size():
		var rat := rats[i]
		rat.desired_velocity = _steer(rat, i, goal, speed, delta)
		any_moving = any_moving or rat.desired_velocity.length_squared() > 1.0
	_update_scurry(center, any_moving)


## No Bender to follow orders from: every half second, see if any rat has
## noticed a player (then the whole pack goes for them), keep after one it
## already has unless everyone's lost them, or roam.
func _look_out(delta: float) -> void:
	_lookout_timer -= delta
	if _lookout_timer > 0.0:
		return
	_lookout_timer = 0.5
	if target and (_is_dead(target) or nearest_rat_distance(target.global_position) > lose_range):
		target = null
		home = pack_center() # lost them: roam from here
	if target == null:
		target = _noticed_player()
	order = Order.HUNT if target else Order.FOLLOW


## A living player some rat is within notice_range of, and can see.
func _noticed_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if _is_dead(player):
			continue
		var nearest: Rat = null
		var nearest_distance := notice_range
		for rat in rats:
			var distance := rat.global_position.distance_to(player.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = rat
		if nearest and _rat_sees(nearest, player):
			return player
	return null


func _rat_sees(rat: Rat, player: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(rat.global_position + Vector3.UP * 0.2, player.global_position + Vector3.UP * 1.0)
	query.exclude = [rat.get_rid()]
	query.collision_mask = 1
	var hit := rat.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player


func _is_dead(player: Node3D) -> bool:
	var player_health := player.get_node_or_null("Health") as Health
	return player_health == null or player_health.is_dead


## Patrol: on to the next spot once the pack gets there (or after a while) --
## a body to eat if there's one within corpse_seek_range, else a random
## walkable spot near home.
func _roam(delta: float, middle: Vector3) -> void:
	_roam_timer -= delta
	var arrived := Vector2(middle.x - _wander_to.x, middle.z - _wander_to.z).length() < 2.0
	if _roam_timer > 0.0 and not (arrived and _corpse == null):
		return
	_roam_timer = randf_range(roam_interval * 0.5, roam_interval * 1.5)
	var body := _corpse_near(middle, corpse_seek_range)
	if body:
		var ragdoll := body.get_node_or_null("EnemyRagdoll") as EnemyRagdoll
		_wander_to = ragdoll.body_position() if ragdoll else body.global_position
		return
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(roam_radius * 0.3, roam_radius)
	_wander_to = _walkable(home + Vector3(offset.x, 0.0, offset.y))


func _walkable(point: Vector3) -> Vector3:
	var map := get_viewport().find_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		return NavigationServer3D.map_get_closest_point(map, point)
	return point


## Where the pack as a whole is headed.
func _goal() -> Vector3:
	if order == Order.HUNT and target:
		var hunt := target.global_position
		if leash_distance > 0.0 and bender:
			var reach := hunt - bender.global_position
			if reach.length() > leash_distance:
				hunt = bender.global_position + reach.normalized() * leash_distance
		return hunt
	if _corpse and is_instance_valid(_corpse):
		var ragdoll := _corpse.get_node_or_null("EnemyRagdoll") as EnemyRagdoll
		return ragdoll.body_position() if ragdoll else _corpse.global_position
	if bender:
		return bender.global_position
	return _wander_to


## The shared path from the middle of the pack to the goal. If the navmesh
## can't get all the way there (a drop below a ledge), it's extended straight
## to the goal -- rats run off the edge and spill down to it.
func _refresh_path(from: Vector3, goal: Vector3) -> void:
	_path = PackedVector3Array()
	var rat := rats[0]
	var map := rat.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		_path = NavigationServer3D.map_get_path(map, from, goal, true)
	if _path.is_empty() or _path[_path.size() - 1].distance_to(goal) > 1.0:
		_path.append(goal)


## One rat's velocity: toward its own spot near the goal -- along the shared
## path when it's far, straight in when it's close -- then made alive: it
## weaves, falls in with its neighbours' flow, keeps a little space, and
## runs in its own stop-start bursts.
func _steer(rat: Rat, index: int, goal: Vector3, speed: float, delta: float) -> Vector3:
	var position := _pos[index]
	if rat.dragging:
		return _steer_dragger(rat, index, speed)
	# Restless: now and then a resting rat picks a new spot in the pack.
	if order != Order.HUNT and randf() < delta / maxf(restless_time, 0.1):
		rat.slot = Vector2.from_angle(randf() * TAU)
	var spot := goal + _spot_offset(rat)
	rat.eating = false
	var to_spot := spot - position
	to_spot.y = 0.0
	var distance := to_spot.length()
	var crowd := _neighbours(index)
	if distance < 0.35 and order != Order.HUNT:
		rat.eating = _corpse != null
		return crowd[0] * speed * 0.5
	var heading := to_spot / distance
	if distance > 4.0 and _path.size() > 1:
		heading = _along_path(position)
	# Weave: a wobble on its own rhythm, two waves so it never looks regular.
	var t := _time * weave_speed + rat.rhythm_seed
	heading = heading.rotated(Vector3.UP, (sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3) * weave_amount)
	var steer: Vector3 = heading + crowd[0] * separation_strength + crowd[1] * alignment_strength
	var velocity := steer.normalized() * speed * rat.speed_scale
	# Bursts: pace swells and dips; at the bottom of a dip it stops for a beat.
	# A hunting pack bursts less -- it means business.
	var wave := sin(_time * 2.7 + rat.rhythm_seed * 3.1)
	var burst := burstiness * (0.4 if order == Order.HUNT else 1.0)
	var pace := 1.0 - burst * 0.5 * (1.0 - wave)
	if wave < -0.9 and order != Order.HUNT:
		pace = 0.0
	# Ease off coming into its spot, so the pack settles instead of jittering.
	return velocity * pace * clampf(distance, 0.3, 1.0)


## Where around the goal this rat wants to be. Hunting: its own spot in the
## engulfing ring, churning around the player and darting in and out.
func _spot_offset(rat: Rat) -> Vector3:
	var radius := rat.slot_radius
	var slot := rat.slot
	if order == Order.HUNT:
		var dart := 0.5 + 0.5 * sin(_time * dart_speed * TAU * 0.5 + rat.rhythm_seed * 1.3)
		radius = lerpf(engulf_radius_min, engulf_radius_max, dart)
		var churn := churn_speed if int(rat.rhythm_seed) % 2 == 0 else -churn_speed
		slot = slot.rotated(_time * churn)
	elif _corpse:
		radius = 0.7
	else:
		# Ebb and flow: breathing in and out, drifting around each other.
		var ebb := 0.5 + 0.5 * sin(_time * ebb_speed * TAU + rat.rhythm_seed * 0.7)
		radius *= lerpf(1.0 - ebb_amount, 1.0 + ebb_amount, ebb)
		var drift := drift_speed if int(rat.rhythm_seed) % 2 == 0 else -drift_speed
		slot = slot.rotated(_time * drift)
	return Vector3(slot.x, 0.0, slot.y) * radius


## Toward the next point of the shared path past the one nearest this rat.
func _along_path(position: Vector3) -> Vector3:
	var nearest := 0
	var nearest_distance := INF
	for i in _path.size():
		var d := position.distance_squared_to(_path[i])
		if d < nearest_distance:
			nearest_distance = d
			nearest = i
	var aim := _path[mini(nearest + 1, _path.size() - 1)]
	var direction := aim - position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


## One pass over the pack for the two boids rules: [separation push, the
## average heading of rats nearby (alignment)]. Swarming the player they
## barely keep apart -- so they pile up and climb over each other.
func _neighbours(index: int) -> Array[Vector3]:
	var push := Vector3.ZERO
	var flow := Vector3.ZERO
	var spacing := separation_distance * (0.5 if order == Order.HUNT else 1.0)
	var position := _pos[index]
	var cell := _cell_of(position)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var bucket: Array = _cells.get(cell + Vector2i(dx, dz), [])
			for other: int in bucket:
				if other == index:
					continue
				var away := position - _pos[other]
				away.y = 0.0
				var d := away.length()
				if d < spacing and d > 0.001:
					push += away / d * (1.0 - d / spacing)
				if d < neighbour_distance:
					flow += Vector3(_vel[other].x, 0.0, _vel[other].z)
	if flow.length_squared() > 0.01:
		flow = flow.normalized()
	return [push, flow]


## Sorts every rat into a neighbour_distance-sized square, once per tick.
func _build_grid() -> void:
	_cells.clear()
	_pos.resize(rats.size())
	_vel.resize(rats.size())
	for i in rats.size():
		var rat := rats[i]
		_pos[i] = rat.global_position
		_vel[i] = rat.linear_velocity
		var cell := _cell_of(_pos[i])
		if not _cells.has(cell):
			_cells[cell] = []
		(_cells[cell] as Array).append(i)


func _cell_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / neighbour_distance), floori(position.z / neighbour_distance))


# ---- Corpse dragging --------------------------------------------------------

func _update_drag(delta: float, center: Vector3) -> void:
	if _drag_phase == DragPhase.NONE:
		_drag_check -= delta
		if _drag_check <= 0.0:
			_drag_check = 1.0
			if rats.size() >= drag_min_rats and randf() < drag_chance:
				_start_drag(center)
		return
	if not is_instance_valid(_drag_body) or not is_instance_valid(_drag_ragdoll) or _draggers.size() < 2:
		_end_drag()
		return
	_drag_timer -= delta
	_drag_body_pos = _drag_ragdoll.body_position()
	match _drag_phase:
		DragPhase.GATHER:
			# Most of them have hold of it (or they've waited long enough): haul.
			if _draggers_at_body() >= _draggers.size() * 0.6 or _drag_timer <= 0.0:
				_drag_phase = DragPhase.DRAG
				_drag_timer = 8.0
				_drag_check_pos = _drag_body_pos
				_drag_stuck_timer = 0.5
		DragPhase.DRAG:
			var to := _drag_to - _drag_body_pos
			to.y = 0.0
			var heading := _drag_heading()
			# There (or out of time), a wall dead ahead, or not moving: eat it here.
			if to.length() < 0.6 or _drag_timer <= 0.0 or _wall_ahead(heading) or _drag_stuck(delta):
				_drag_ragdoll.drag(Vector3.ZERO)
				_drag_phase = DragPhase.EAT
				_drag_timer = eat_time
			elif _draggers_at_body() >= _draggers.size() * 0.5:
				_drag_ragdoll.drag(heading * drag_speed)
			else:
				_drag_ragdoll.drag(Vector3.ZERO) # waiting for the stragglers
				_drag_check_pos = _drag_body_pos # (not stuck, just waiting)
		DragPhase.EAT:
			if _drag_timer <= 0.0:
				_end_drag()


## Picks a body near the pack and the rats nearest it to haul it.
func _start_drag(center: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(CORPSE_GROUP):
		var body := node as Node3D
		if body == null or body.has_meta("dragged"):
			continue
		var ragdoll := body.get_node_or_null("EnemyRagdoll") as EnemyRagdoll
		if ragdoll == null:
			continue
		var at := ragdoll.body_position()
		if at.distance_to(center) > drag_find_range:
			continue
		_drag_body = body
		_drag_ragdoll = ragdoll
		_drag_body_pos = at
		body.set_meta("dragged", true)
		var by_distance := rats.duplicate()
		by_distance.sort_custom(func(a: Rat, b: Rat) -> bool:
			return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
		var how_many := maxi(4, int(rats.size() * drag_share))
		_draggers.clear()
		for i in mini(how_many, by_distance.size()):
			var rat: Rat = by_distance[i]
			rat.dragging = true
			_draggers.append(rat)
		_drag_to = _pick_drag_spot(at)
		_drag_path = _route(at, _drag_to)
		_drag_phase = DragPhase.GATHER
		_drag_timer = 6.0
		return


## Somewhere open to haul a body to: on the walkable map, a clear line from
## the body with no wall in between, not too roundabout to reach, and not
## tucked in a corner (nothing solid close around it). No good spot found:
## stay put and eat it where it lies.
func _pick_drag_spot(from: Vector3) -> Vector3:
	for attempt in 12:
		var away := Vector2.from_angle(randf() * TAU) * randf_range(drag_distance_min, drag_distance_max)
		var spot := _walkable(from + Vector3(away.x, 0.0, away.y))
		var straight := Vector2(spot.x - from.x, spot.z - from.z).length()
		if straight < drag_distance_min * 0.6:
			continue # the walkable spot snapped back toward a wall
		if _blocked(from + Vector3.UP * 0.3, spot + Vector3.UP * 0.3):
			continue
		if _path_length(_route(from, spot)) > straight * 1.4:
			continue # only reachable the long way round
		if _hemmed_in(spot):
			continue
		return spot
	return from


## Something solid within an arm's length around `spot` -- a corner or a wall.
func _hemmed_in(spot: Vector3) -> bool:
	var at := spot + Vector3.UP * 0.3
	for i in 8:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * 0.9
		if _blocked(at, at + out):
			return true
	return false


func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := get_viewport().find_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		if not path.is_empty():
			return path
	return PackedVector3Array([from, to])


func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## Which way to haul right now: toward the next corner of the walkable route.
func _drag_heading() -> Vector3:
	var aim := _drag_to
	for point in _drag_path:
		if Vector2(point.x - _drag_body_pos.x, point.z - _drag_body_pos.z).length() > 0.5:
			aim = point
			break
	var heading := aim - _drag_body_pos
	heading.y = 0.0
	return heading.normalized() if heading.length_squared() > 0.0001 else Vector3.ZERO


func _wall_ahead(heading: Vector3) -> bool:
	var at := _drag_body_pos + Vector3.UP * 0.25
	return heading != Vector3.ZERO and _blocked(at, at + heading * 0.7)


## Hauling but the body hasn't really moved in the last half second.
func _drag_stuck(delta: float) -> bool:
	_drag_stuck_timer -= delta
	if _drag_stuck_timer > 0.0:
		return false
	_drag_stuck_timer = 0.5
	var moved := _drag_body_pos.distance_to(_drag_check_pos)
	_drag_check_pos = _drag_body_pos
	return moved < drag_speed * 0.5 * 0.25 # under a quarter of the expected distance


## A wall or other map geometry (a StaticBody3D) between two points.
func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_viewport().find_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider is StaticBody3D


func _end_drag() -> void:
	for rat in _draggers:
		if is_instance_valid(rat):
			rat.dragging = false
			rat.eating = false
	_draggers.clear()
	if is_instance_valid(_drag_ragdoll):
		_drag_ragdoll.drag(Vector3.ZERO)
	if is_instance_valid(_drag_body):
		_drag_body.remove_meta("dragged")
	_drag_body = null
	_drag_ragdoll = null
	_drag_phase = DragPhase.NONE
	_drag_check = 3.0


func _draggers_at_body() -> int:
	var holding := 0
	for rat in _draggers:
		if rat.global_position.distance_to(_drag_body_pos) < 0.9 * rat.size:
			holding += 1
	return holding


## A dragger crowds in around the body (its own spot on it) -- the body
## moving drags them along -- and eats once they've got it where they want.
func _steer_dragger(rat: Rat, index: int, speed: float) -> Vector3:
	var spot := _drag_body_pos + Vector3(rat.slot.x, 0.0, rat.slot.y) * 0.45 * rat.size
	var to_spot := spot - _pos[index]
	to_spot.y = 0.0
	var distance := to_spot.length()
	var crowd := _neighbours(index)
	rat.eating = _drag_phase == DragPhase.EAT and distance < 0.5
	if distance < 0.25:
		return crowd[0] * speed * 0.3
	var steer: Vector3 = to_spot / distance + crowd[0] * separation_strength * 0.5
	return steer.normalized() * speed * rat.speed_scale * clampf(distance, 0.3, 1.0)


## A body on the floor near the Bender (or, with no Bender, near the pack)
## to eat. EnemyRagdoll adds dead enemies to CORPSE_GROUP.
func _find_corpse(middle: Vector3) -> Node3D:
	return _corpse_near(bender.global_position if bender else middle, eat_range)


## The nearest body within `within` of `point` that no pack is dragging.
func _corpse_near(point: Vector3, within: float) -> Node3D:
	var best: Node3D = null
	var best_distance := within
	for node in get_tree().get_nodes_in_group(CORPSE_GROUP):
		var corpse := node as Node3D
		if corpse == null or corpse.has_meta("dragged"):
			continue
		var distance := corpse.global_position.distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = corpse
	return best


func _update_scurry(center: Vector3, moving: bool) -> void:
	if _scurry_anchor == null or not _scurry_anchor.is_inside_tree():
		return
	if moving and _scurry == null:
		_scurry = SoundPlayer.play_loop_3d(scurry_sound, _scurry_anchor)
	elif not moving and _scurry:
		_scurry.queue_free()
		_scurry = null
	if moving:
		_scurry_anchor.global_position = center
