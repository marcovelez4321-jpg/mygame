class_name RoachCarry
extends Node

## Roaches lifting a body to eat it in the air -- one of these per body being
## carried, made by the roaches themselves (RoachCarry.recruit()).
##
## It takes at least MIN_ROACHES idle roaches near a body to try (more can
## join, up to MAX_ROACHES). They each fly to a grab point around it; once
## MIN_ROACHES have hold, they lift it by the torso (arms and legs dangle)
## up to CARRY_HEIGHT. Only when NO part of it is touching the ground do they
## start eating -- blood flies, and every BITES_PER_ROACH bites a new roach
## bursts out of the body (at most ROACHES_PER_BODY). After EAT_TIME, or if
## fewer than MIN_ROACHES are left holding it, they let it drop.
##
## Rule 1 (co-op): the host runs this. Ragdolls are drawn on each player's
## own screen, so the lift will be sent as a "carry this body" event.

const GROUP := "roach_carries"
const ROACH_SCENE := preload("res://scenes/enemy/roach.tscn")
const MIN_ROACHES := 3
const MAX_ROACHES := 6
## Idle roaches this close to a body can claim it.
const RECRUIT_RANGE := 12.0
## How high the body's hips are held above the floor, and how fast it rises.
const CARRY_HEIGHT := 1.6
const LIFT_SPEED := 1.2
## A roach counts as holding the body inside this distance of its grab point.
const HOLD_DISTANCE := 0.7
const EAT_TIME := 8.0
const BITES_PER_ROACH := 25
const ROACHES_PER_BODY := 3
const BLOOD := Color(0.55, 0.02, 0.02)

enum Phase { GATHER, LIFT, EAT }

var body: Node3D
var ragdoll: EnemyRagdoll
var roaches: Array[FlyingRoach] = []
var phase := Phase.GATHER
var _timer := 6.0
var _bites := 0
var _ground_check := 0.0
var _airborne := false


## An idle roach looking for a meal: joins a carry near it that has room, or
## starts one on a body near it if enough other idle roaches are around.
static func recruit(roach: FlyingRoach) -> void:
	var tree := roach.get_tree()
	for node in tree.get_nodes_in_group(GROUP):
		var carry := node as RoachCarry
		if carry and carry.roaches.size() < MAX_ROACHES and is_instance_valid(carry.ragdoll) \
				and carry.ragdoll.body_position().distance_to(roach.global_position) <= RECRUIT_RANGE:
			carry.join(roach)
			return
	for node in tree.get_nodes_in_group(RatSwarm.CORPSE_GROUP):
		var corpse := node as Node3D
		if corpse == null or corpse.has_meta("dragged"):
			continue
		var corpse_ragdoll := corpse.get_node_or_null("EnemyRagdoll") as EnemyRagdoll
		if corpse_ragdoll == null:
			continue
		var at := corpse_ragdoll.body_position()
		if at.distance_to(roach.global_position) > RECRUIT_RANGE:
			continue
		var crew: Array[FlyingRoach] = []
		for other in tree.get_nodes_in_group(Factions.GROUPS[Factions.Side.ROACH]):
			var idle := other as FlyingRoach
			if idle and idle.is_idle() and idle.global_position.distance_to(at) <= RECRUIT_RANGE:
				crew.append(idle)
				if crew.size() >= MAX_ROACHES:
					break
		if crew.size() < MIN_ROACHES:
			return
		var carry := RoachCarry.new()
		carry.body = corpse
		carry.ragdoll = corpse_ragdoll
		corpse.set_meta("dragged", true) # rats leave it alone
		tree.current_scene.add_child(carry)
		for member in crew:
			carry.join(member)
		return


func _ready() -> void:
	add_to_group(GROUP)


func join(roach: FlyingRoach) -> void:
	if roaches.has(roach) or roaches.size() >= MAX_ROACHES:
		return
	roaches.append(roach)
	roach.start_carry(self, roaches.size() - 1)


func leave(roach: FlyingRoach) -> void:
	roaches.erase(roach)


## Where `slot` holds on: spread around the torso, a little above it.
func grab_point(slot: int) -> Vector3:
	var angle := TAU * slot / float(MAX_ROACHES)
	return ragdoll.body_position() + Vector3(cos(angle), 0.0, sin(angle)) * 0.45 + Vector3.UP * 0.35


func is_eating() -> bool:
	return phase == Phase.EAT


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var still: Array[FlyingRoach] = []
	for roach in roaches:
		if is_instance_valid(roach) and roach.is_carrying(self):
			still.append(roach)
	roaches = still
	if not is_instance_valid(body) or not is_instance_valid(ragdoll):
		_finish()
		return
	_timer -= delta
	var holding := 0
	for i in roaches.size():
		if roaches[i].global_position.distance_to(grab_point(roaches[i].carry_slot)) <= HOLD_DISTANCE:
			holding += 1
	match phase:
		Phase.GATHER:
			if holding >= MIN_ROACHES:
				phase = Phase.LIFT
			elif _timer <= 0.0 or roaches.size() < MIN_ROACHES:
				_finish() # couldn't get enough of a grip
		Phase.LIFT, Phase.EAT:
			if holding < MIN_ROACHES:
				_finish() # not enough of them left holding it: it drops
				return
			_lift()
			_ground_check -= delta
			if _ground_check <= 0.0:
				_ground_check = 0.2
				_airborne = not ragdoll.is_touching_ground()
			if phase == Phase.LIFT and _airborne:
				phase = Phase.EAT
				_timer = EAT_TIME
			elif phase == Phase.EAT and not _airborne:
				phase = Phase.LIFT # sagged back down: lift it again first
			elif phase == Phase.EAT and _timer <= 0.0:
				_finish()


## Holds the torso up at CARRY_HEIGHT above the floor under it.
func _lift() -> void:
	var hips := ragdoll.body_position()
	var query := PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.5, hips + Vector3.DOWN * 4.0)
	query.collision_mask = 1
	var floor_hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	var floor_y: float = floor_hit.position.y if not floor_hit.is_empty() else hips.y - CARRY_HEIGHT
	var rise := clampf((floor_y + CARRY_HEIGHT - hips.y) * 3.0, -LIFT_SPEED, LIFT_SPEED)
	ragdoll.carry(Vector3(0.0, rise, 0.0))


## A roach took a bite (FlyingRoach, while eating). Enough bites and a new
## roach bursts out of the body.
func bitten() -> void:
	_bites += 1
	if _bites < BITES_PER_ROACH:
		return
	_bites = 0
	var born: int = body.get_meta("roaches_born", 0)
	if born >= ROACHES_PER_BODY:
		return
	body.set_meta("roaches_born", born + 1)
	var at := ragdoll.body_position()
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, at, Vector3.UP, BLOOD, 2.5)
	var roach := ROACH_SCENE.instantiate() as FlyingRoach
	world.add_child(roach)
	roach.global_position = at + Vector3.UP * 0.3
	roach.burst_out.call_deferred() # after its own setup: a springy pop out of the body
	BloodFX.spawn_impact(world, at + Vector3.UP * 0.2, (Vector3.UP + Vector3(randf() - 0.5, 0.0, randf() - 0.5)).normalized(), BLOOD, 1.5)


func _finish() -> void:
	if is_instance_valid(ragdoll):
		ragdoll.carry(Vector3.ZERO)
	if is_instance_valid(body):
		body.remove_meta("dragged")
	for roach in roaches:
		if is_instance_valid(roach):
			roach.end_carry(self)
	roaches.clear()
	queue_free()
