class_name RoachCarry
extends Node

## Roaches lifting a body to eat it in the air -- one of these per body being
## carried, made by the roaches themselves (RoachCarry.recruit()).
##
## It takes at least MIN_ROACHES idle roaches near a body to try (more can
## join, up to MAX_ROACHES). Each one grabs its own body part (GRIP_BONES: hips,
## a hand, a foot, the head...) and flies it up; once MIN_ROACHES have hold,
## the body rises toward CARRY_HEIGHT, hanging between the roaches holding it.
## Every roach holding on takes WEIGHT_PER_ROACH of the body's weight and adds
## lift speed, so the more of them, the easier and faster it goes up.
## Once lifting they commit: only getting hurt makes one let go.
## They start eating the moment they start lifting -- however high they manage
## to get it -- blood flies, and every BITES_PER_ROACH bites ROACHES_PER_BREED
## new roaches burst out of the body (at most BREEDS_PER_BODY times). Once it's clear of the
## ground they fly off with it at FLY_SPEED, still eating, toward the quietest
## spot nearby (fewest hostiles around it: Factions.danger_at()), re-picked
## every REPICK_TIME as things move. After EAT_TIME of eating, or if fewer
## than MIN_ROACHES are left holding it, they let it drop.
##
## Rule 1 (co-op): the host runs this. Ragdolls are drawn on each player's
## own screen, so the lift will be sent as a "carry this body" event.

const GROUP := "roach_carries"
const ROACH_SCENE := preload("res://scenes/enemy/roach.tscn")
const MIN_ROACHES := 3
const MAX_ROACHES := 6
## Idle roaches this close to a body can claim it.
const RECRUIT_RANGE := 12.0
## How high the held body parts are carried above the floor.
const CARRY_HEIGHT := 1.6
## How fast held parts rise with MIN_ROACHES holding; scales up with each extra
## roach (4 roaches = 4/3 as fast, 6 = twice as fast).
const LIFT_SPEED := 1.5
## Share of the body's weight each holding roach takes off: 3 roaches (the
## minimum) leave it at 10% of its weight -- light enough that they always
## get it all the way up, heavy enough that the limbs they aren't holding
## still hang -- and 4 or more make it weightless. (At 0.2, three left it at
## 40%, and the unheld limbs could weigh the lift down to a stall short of
## CARRY_HEIGHT.)
const WEIGHT_PER_ROACH := 0.3
## How hard a held part is pulled toward CARRY_HEIGHT: rise speed per meter
## still to go (capped at the lift speed). Higher closes the last bit of the
## gap instead of settling a little short of it under the hanging weight.
const LIFT_PULL := 6.0
## The body part each grab slot holds, in the order roaches join: the first
## three (the minimum to lift) hold the hips and opposite corners so it rises
## level; later ones fill in the other hand, foot and the head.
const GRIP_BONES := ["Hips", "LeftHand", "RightFoot", "RightHand", "LeftFoot", "Head"]
## A roach counts as holding the body inside this distance of its grab point.
const HOLD_DISTANCE := 0.875 # 1.25x the original 0.7: easier to count as holding
const EAT_TIME := 8.0
## Flying off with it: how fast (well under a roach's cruise_speed, so the
## holders keep up), how far it looks for somewhere quieter, and how often.
const FLY_SPEED := 2.0
const FLY_DISTANCE := 12.0
const REPICK_TIME := 2.0
## Hostiles within this of a spot count against it (Factions.danger_at()).
const DANGER_RADIUS := 15.0
## A spot has to be this much quieter than where it's headed to change course
## (so it doesn't dither between two equally quiet spots).
const REPICK_MARGIN := 0.25
const BITES_PER_ROACH := 25
## Roaches born each time they've bitten enough, and how many times one body
## can breed them (2 x 3 = up to 6 new roaches per body).
const ROACHES_PER_BREED := 2
const BREEDS_PER_BODY := 3
const BLOOD := Color(0.55, 0.02, 0.02)

## GATHER: getting hold of it. LIFT: raising it as high as they can (eating
## already). FLY: clear of the ground, flying it somewhere quiet (eating).
enum Phase { GATHER, LIFT, FLY }

var body: Node3D
var ragdoll: EnemyRagdoll
var roaches: Array[FlyingRoach] = []
var phase := Phase.GATHER
var _timer := 6.0
var _bites := 0
var _ground_check := 0.0
var _airborne := false
var _eating := false
## Where it's flying the body (FLY), and when to look for a quieter spot.
var _destination := Vector3.ZERO
var _has_destination := false
var _repick := 0.0


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
	# The lowest grip nobody holds -- after a roach lets go, its body part is
	# the next one filled, instead of two roaches sharing a hand.
	var slot := 0
	while roaches.any(func(other: FlyingRoach) -> bool: return other.carry_slot == slot):
		slot += 1
	roaches.append(roach)
	roach.start_carry(self, slot)


func leave(roach: FlyingRoach) -> void:
	roaches.erase(roach)


## Where `slot`'s roach holds on: just above its body part (GRIP_BONES), so
## it follows that hand or foot as the body swings.
func grab_point(slot: int) -> Vector3:
	var bone := grip_bone(slot)
	var at := bone.global_position if bone else ragdoll.body_position()
	return at + Vector3.UP * 0.3


## The body part `slot` holds (GRIP_BONES), falling back to the hips on a body
## missing that bone.
func grip_bone(slot: int) -> PhysicalBone3D:
	var bone := ragdoll.bone_named(GRIP_BONES[slot % GRIP_BONES.size()])
	return bone if bone else ragdoll.bone_named("Hips")


func is_eating() -> bool:
	return _eating


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
	var holders := _holders()
	var holding := holders.size()
	match phase:
		Phase.GATHER:
			if holding >= MIN_ROACHES:
				phase = Phase.LIFT
				_eating = true # dig in as soon as it's coming up
				_timer = EAT_TIME
			elif _timer <= 0.0 or roaches.size() < MIN_ROACHES:
				_finish() # couldn't get enough of a grip
		Phase.LIFT, Phase.FLY:
			if holding < MIN_ROACHES:
				_finish() # not enough of them left holding it: it drops
				return
			if _timer <= 0.0:
				_finish() # eaten its fill
				return
			_ground_check -= delta
			if _ground_check <= 0.0:
				_ground_check = 0.2
				_airborne = not ragdoll.is_touching_ground()
			if phase == Phase.LIFT and _airborne:
				phase = Phase.FLY
				_repick = 0.0
			elif phase == Phase.FLY and not _airborne:
				phase = Phase.LIFT # sagged back down (or snagged): lift it clear first
			_lift(holders, _fly_velocity(delta) if phase == Phase.FLY else Vector3.ZERO)


## The roaches actually holding on right now: close enough to their grab point.
func _holders() -> Array[FlyingRoach]:
	var found: Array[FlyingRoach] = []
	for roach in roaches:
		if roach.global_position.distance_to(grab_point(roach.carry_slot)) <= HOLD_DISTANCE:
			found.append(roach)
	return found


## Each holding roach pulls its own body part toward CARRY_HEIGHT above the
## floor (and along at `travel`, flying off with it), and the body as a whole
## gets lighter with every roach on it.
func _lift(holders: Array[FlyingRoach], travel: Vector3 = Vector3.ZERO) -> void:
	var hips := ragdoll.body_position()
	var query := PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.5, hips + Vector3.DOWN * 4.0)
	query.collision_mask = 1
	var floor_hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	var floor_y: float = floor_hit.position.y if not floor_hit.is_empty() else hips.y - CARRY_HEIGHT
	var target_y := floor_y + CARRY_HEIGHT
	var speed := LIFT_SPEED * holders.size() / float(MIN_ROACHES)
	var held := {}
	for roach in holders:
		var bone := grip_bone(roach.carry_slot)
		if bone == null or held.has(bone):
			continue
		var rise := clampf((target_y - bone.global_position.y) * LIFT_PULL, -speed, speed)
		# Sideways it eases toward `travel` (zero = damped to a stop, so held
		# parts don't swing wildly); up/down is the roach's pull.
		held[bone] = Vector3(lerpf(bone.linear_velocity.x, travel.x, 0.2), rise, lerpf(bone.linear_velocity.z, travel.z, 0.2))
	ragdoll.carry(held, maxf(1.0 - WEIGHT_PER_ROACH * holders.size(), 0.0))


## Which way to fly the body this tick: toward the quietest spot nearby
## (re-picked every REPICK_TIME), slowing to a hover once it's there.
func _fly_velocity(delta: float) -> Vector3:
	var at := ragdoll.body_position()
	_repick -= delta
	if _repick <= 0.0:
		_repick = REPICK_TIME
		_pick_destination(at)
	var to := _destination - at
	to.y = 0.0
	if to.length() < 0.5:
		return Vector3.ZERO
	return to.normalized() * FLY_SPEED * clampf(to.length(), 0.3, 1.0)


## The quietest of: staying here, carrying on to where it's headed, or one of
## 8 spots FLY_DISTANCE around (cut short at walls, at carry height).
func _pick_destination(at: Vector3) -> void:
	var tree := get_tree()
	var space := body.get_world_3d().direct_space_state
	var best := at
	var best_danger := Factions.danger_at(tree, Factions.Side.ROACH, at, DANGER_RADIUS)
	if _has_destination:
		var current := Factions.danger_at(tree, Factions.Side.ROACH, _destination, DANGER_RADIUS)
		if current <= best_danger + REPICK_MARGIN:
			best = _destination
			best_danger = current - REPICK_MARGIN # sticking with it is a bit better
	var turn := randf() * TAU
	for i in 8:
		var out := Vector3.FORWARD.rotated(Vector3.UP, turn + TAU * i / 8.0) * FLY_DISTANCE
		var query := PhysicsRayQueryParameters3D.create(at, at + out)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		var spot := at + out
		if not hit.is_empty():
			spot = hit.position - out.normalized() * 1.0 # stop short of the wall
		if spot.distance_to(at) < 3.0:
			continue # boxed in that way
		var danger := Factions.danger_at(tree, Factions.Side.ROACH, spot, DANGER_RADIUS)
		if danger < best_danger:
			best = spot
			best_danger = danger
	_destination = best
	_has_destination = true


## A roach took a bite (FlyingRoach, while eating). Enough bites and
## ROACHES_PER_BREED new roaches burst out of the body.
func bitten() -> void:
	_bites += 1
	if _bites < BITES_PER_ROACH:
		return
	_bites = 0
	var breeds: int = body.get_meta("roach_breeds", 0)
	if breeds >= BREEDS_PER_BODY:
		return
	body.set_meta("roach_breeds", breeds + 1)
	var at := ragdoll.body_position()
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, at, Vector3.UP, BLOOD, 2.5)
	var turn := randf() * TAU
	for i in ROACHES_PER_BREED:
		var roach := ROACH_SCENE.instantiate() as FlyingRoach
		world.add_child(roach)
		# Spread around the body, so they don't start inside each other.
		var side := Vector3.RIGHT.rotated(Vector3.UP, turn + TAU * i / ROACHES_PER_BREED) * 0.25
		roach.global_position = at + Vector3.UP * 0.3 + side
		roach.burst_out.call_deferred() # after its own setup: a springy pop out of the body
		BloodFX.spawn_impact(world, at + Vector3.UP * 0.2, (Vector3.UP + Vector3(randf() - 0.5, 0.0, randf() - 0.5)).normalized(), BLOOD, 1.5)


func _finish() -> void:
	if is_instance_valid(ragdoll):
		ragdoll.carry({})
	if is_instance_valid(body):
		body.remove_meta("dragged")
	for roach in roaches:
		if is_instance_valid(roach):
			roach.end_carry(self)
	roaches.clear()
	queue_free()
