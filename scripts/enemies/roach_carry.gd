class_name RoachCarry
extends Node

## Roaches lifting a body to eat it in the air -- one of these per body being
## carried, made by the roaches themselves (RoachCarry.recruit()).
##
## It takes at least MIN_ROACHES idle roaches near a body to try (more can
## join, up to MAX_ROACHES). Each one grabs its own body part (GRIP_BONES: hips,
## a hand, a foot, the head...) and pulls it up; once MIN_ROACHES have hold,
## the body rises toward CARRY_HEIGHT, hanging between the roaches holding it.
## It's a real tug against the body's weight, not a scripted lift: each roach
## can only pull its part with GRIP_STRENGTH (a share of the body's weight) and
## bears a little more of it overall (SUPPORT_PER_ROACH), so three only just
## manage -- the parts with the most body hanging off them (the hips) sag
## lower than a hand or a foot, the roaches end up at different heights, and
## they bob harder the closer they are to their limit (strain()). Every roach
## that joins adds its strength, so more of them lift it easier and faster.
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
## The most each roach can pull its own body part up with, as a share of the
## whole body's weight. Applied as a force on that one bone: the joints pass
## it on to whatever hangs off it.
const GRIP_STRENGTH := 0.3
## Each roach holding on also bears this share of the weight spread over the
## whole body (its gravity is scaled down) -- keeps the joints from being
## yanked apart with everything hanging off three points. Three roaches:
## 3 x 0.3 pull + 3 x 0.12 spread = 1.26x the body's weight, only just enough;
## six: 2.5x, easy.
const SUPPORT_PER_ROACH := 0.12
## How a roach works its pull (0 = slack, 1 = all it's got): just enough to
## hold the body's weight between however many of them there are (so six
## don't haul it up into the sky), more the further below CARRY_HEIGHT its
## part is (EFFORT_PER_METER), less above it, and less while it's already
## rising (EFFORT_DAMPING per m/s) so it doesn't overshoot and bounce.
const EFFORT_PER_METER := 1.5
const EFFORT_DAMPING := 0.5
## Steering the body sideways (flying off with it, or holding it steady): how
## quickly the held parts are brought to the travel velocity, per second.
const STEER_RATE := 3.0
## Never carried more than this far above the floor where they picked it up
## (on top of CARRY_HEIGHT) -- flying over a pillar or a ledge, or with no
## floor found under it at all, it doesn't climb with it.
const MAX_EXTRA_HEIGHT := 1.0
## How far down to look for the floor under the body.
const FLOOR_PROBE := 30.0
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
## Chance a newborn roach is a spitter (else a normal one). roach.tscn itself
## is set to always be a spitter, so births roll their own.
const BRED_SPITTER_CHANCE := 0.5
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
## The floor height where they started lifting it (MAX_EXTRA_HEIGHT).
var _ground_y := 0.0
## How hard each grab slot's roach is pulling right now, 0..1 (strain()).
var _strain := {}
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
				_ground_y = _floor_under(ragdoll.body_position(), ragdoll.body_position().y - 0.2)
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


## How hard `slot`'s roach is pulling right now: 0 = slack, 1 = flat out.
## The roach bobs and strains with it (FlyingRoach._think_carry()).
func strain(slot: int) -> float:
	return _strain.get(slot, 0.0)


## Each holding roach pulls its own body part up toward CARRY_HEIGHT above the
## floor with a force it can't exceed (GRIP_STRENGTH), and steers it along at
## `travel` (flying off with it); every roach also bears SUPPORT_PER_ROACH of
## the weight spread over the body. Real forces against real weight: the
## parts with the most body hanging off them sag lowest.
func _lift(holders: Array[FlyingRoach], travel: Vector3 = Vector3.ZERO) -> void:
	var hips := ragdoll.body_position()
	var floor_y := _floor_under(hips, _ground_y)
	var target_y := minf(floor_y, _ground_y + MAX_EXTRA_HEIGHT) + CARRY_HEIGHT
	var delta := get_physics_process_delta_time()
	var mass := ragdoll.total_mass()
	var weight := mass * ragdoll.gravity_strength()
	var grip_force := weight * GRIP_STRENGTH
	var share := mass / maxf(holders.size(), 1.0) # the body mass each roach steers
	# Each one's share of holding the body's weight up, after what they all
	# bear spread over it (SUPPORT_PER_ROACH): 3 roaches about 0.7, 6 about 0.16.
	var hover := clampf((1.0 - SUPPORT_PER_ROACH * holders.size()) / (GRIP_STRENGTH * holders.size()), 0.0, 1.0)
	var pushes := {}
	_strain.clear()
	for roach in holders:
		var bone := grip_bone(roach.carry_slot)
		if bone == null:
			continue
		var effort := clampf(hover + (target_y - bone.global_position.y) * EFFORT_PER_METER \
				- bone.linear_velocity.y * EFFORT_DAMPING, 0.0, 1.0)
		_strain[roach.carry_slot] = effort
		# Sideways: bring the part to `travel` (zero = hold it steady, so it
		# doesn't swing wildly), within what the roach can manage.
		var flat := Vector3(travel.x - bone.linear_velocity.x, 0.0, travel.z - bone.linear_velocity.z)
		var steer := (flat * share * STEER_RATE).limit_length(grip_force * 0.5)
		var push: Vector3 = (Vector3.UP * grip_force * effort + steer) * delta
		pushes[bone] = pushes.get(bone, Vector3.ZERO) + push # two roaches on one part add up
	ragdoll.carry(pushes, maxf(1.0 - SUPPORT_PER_ROACH * holders.size(), 0.0))


## The floor height under `at`, or `otherwise` if there's none within
## FLOOR_PROBE (never "wherever the body is", which let it climb forever).
func _floor_under(at: Vector3, otherwise: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * FLOOR_PROBE)
	query.collision_mask = 1
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else otherwise


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
		# Spread around the body, so they don't start inside each other.
		var side := Vector3.RIGHT.rotated(Vector3.UP, turn + TAU * i / ROACHES_PER_BREED) * 0.25
		hatch(world, at + Vector3.UP * 0.3 + side)
		BloodFX.spawn_impact(world, at + Vector3.UP * 0.2, (Vector3.UP + Vector3(randf() - 0.5, 0.0, randf() - 0.5)).normalized(), BLOOD, 1.5)


## A newborn roach bursting out at `at`: a spitter or a normal one, 50/50
## (BRED_SPITTER_CHANCE). Shared by every roach birth -- a carried body
## (bitten()) and a rat eaten in mid-air (FlyingRoach). Rule 1: host only;
## the roll goes with the spawn in co-op.
static func hatch(world: Node, at: Vector3) -> void:
	var roach := ROACH_SCENE.instantiate() as FlyingRoach
	roach.kind = FlyingRoach.Kind.SPITTER if randf() < BRED_SPITTER_CHANCE else FlyingRoach.Kind.NORMAL
	world.add_child(roach)
	roach.global_position = at
	roach.burst_out.call_deferred() # after its own setup: a springy pop out of the body


func _finish() -> void:
	_strain.clear()
	if is_instance_valid(ragdoll):
		ragdoll.carry({})
	if is_instance_valid(body):
		body.remove_meta("dragged")
	for roach in roaches:
		if is_instance_valid(roach):
			roach.end_carry(self)
	roaches.clear()
	queue_free()
