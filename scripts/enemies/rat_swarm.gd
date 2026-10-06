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
@export var rat_speed: float = 4.25
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
@export var frenzy_speed: float = 1.8
@export var frenzy_bite_rate: float = 2.0
@export var frenzy_time: float = 5.0

@export_group("Eating")
## Not fighting: rats go and eat a corpse this close to the Bender.
@export var eat_range: float = 8.0

@export_group("Sound")
## One scurrying loop for the whole pack, at its middle -- not one per rat.
@export var scurry_sound: SoundEvent
@export var bite_sound: SoundEvent

var bender: Node3D
var order := Order.FOLLOW
var target: Node3D
var rats: Array[Rat] = []

var _frenzy_left := 0.0
var _time := 0.0
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


## New rats in a ring around `center`.
func spawn_rats(amount: int, center: Vector3) -> void:
	var world := get_tree().current_scene
	for i in amount:
		var rat := RAT_SCENE.instantiate() as Rat
		rat.swarm = self
		var angle := randf() * TAU
		rat.slot = Vector2.from_angle(angle)
		rat.slot_radius = randf_range(follow_radius_min, follow_radius_max)
		world.add_child(rat)
		rat.global_position = center + Vector3(rat.slot.x, 0.0, rat.slot.y) * randf_range(0.5, 1.5) + Vector3.UP * 0.3
		rats.append(rat)


func forget(rat: Rat) -> void:
	rats.erase(rat)


## A Bender spell: the whole horde goes for the player in a frenzy.
func frenzy() -> void:
	order = Order.HUNT
	_frenzy_left = frenzy_time


## The Bender's close-range spell: a frenzy, plus every rat near the player
## leaps at them in a quick ripple, one after another.
func leap_wave(within: float, stagger: float) -> void:
	frenzy()
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
		if bender == null and rats.is_empty() and multiplayer.is_server():
			queue_free() # leader and pack both gone
		return
	if not is_instance_valid(target):
		target = null
	if bender == null and order != Order.HUNT:
		order = Order.HUNT # leaderless: they just go for whoever's around
	_frenzy_left = maxf(_frenzy_left - delta, 0.0)

	var center := Vector3.ZERO
	for rat in rats:
		center += rat.global_position
	center /= rats.size()

	var goal := _goal()
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = path_interval
		_refresh_path(center, goal)
		_corpse = _find_corpse() if order == Order.FOLLOW else null

	_time += delta
	var speed := rat_speed * lerpf(1.0, frenzy_speed, _frenzy())
	var any_moving := false
	for rat in rats:
		rat.desired_velocity = _steer(rat, goal, speed, delta)
		any_moving = any_moving or rat.desired_velocity.length_squared() > 1.0
	_update_scurry(center, any_moving)


## Where the pack as a whole is headed.
func _goal() -> Vector3:
	if order == Order.HUNT and target:
		return target.global_position
	if _corpse and is_instance_valid(_corpse):
		return _corpse.global_position
	if bender:
		return bender.global_position
	return target.global_position if target else Vector3.ZERO


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
func _steer(rat: Rat, goal: Vector3, speed: float, delta: float) -> Vector3:
	var position := rat.global_position
	# Restless: now and then a resting rat picks a new spot in the pack.
	if order != Order.HUNT and randf() < delta / maxf(restless_time, 0.1):
		rat.slot = Vector2.from_angle(randf() * TAU)
	var spot := goal + _spot_offset(rat)
	rat.eating = false
	var to_spot := spot - position
	to_spot.y = 0.0
	var distance := to_spot.length()
	var crowd := _neighbours(rat)
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
func _neighbours(rat: Rat) -> Array[Vector3]:
	var push := Vector3.ZERO
	var flow := Vector3.ZERO
	var spacing := separation_distance * (0.5 if order == Order.HUNT else 1.0)
	var position := rat.global_position
	for other in rats:
		if other == rat:
			continue
		var away := position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d < spacing and d > 0.001:
			push += away / d * (1.0 - d / spacing)
		if d < neighbour_distance:
			flow += Vector3(other.linear_velocity.x, 0.0, other.linear_velocity.z)
	if flow.length_squared() > 0.01:
		flow = flow.normalized()
	return [push, flow]


## A body on the floor near the Bender to eat (EnemyRagdoll adds dead
## enemies to CORPSE_GROUP).
func _find_corpse() -> Node3D:
	if bender == null:
		return null
	for node in get_tree().get_nodes_in_group(CORPSE_GROUP):
		var corpse := node as Node3D
		if corpse and corpse.global_position.distance_to(bender.global_position) <= eat_range:
			return corpse
	return null


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
