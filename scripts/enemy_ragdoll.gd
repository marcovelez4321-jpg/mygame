class_name EnemyRagdoll
extends Node

## Turns the enemy's body into a ragdoll when it dies. Attach as a child of
## the Enemy. The physical bones are built at spawn by RagdollBuilder from
## whatever model EnemyModel picked (see _find_or_build_simulator()); this
## script switches them on.
##
## While the enemy is alive its physical bones have NO collision at all. They
## sit inside the enemy's own capsule, so if they collided, the enemy would be
## shoved around by its own bones and shots would hit bones instead of the
## enemy. They only get collision when the enemy dies.
##
## Presentation only (Rule 1, co-op): the ragdoll never affects gameplay and
## isn't sent over the network. Each player's game starts its own from the
## same shared facts (the enemy died, and which way it was facing), so the
## bodies fall in roughly the same way. Small differences don't matter.

## Physics layer 4 (layers are numbered from 1). Everything else in the game,
## including the gun's ray and the enemy's sight ray, only looks at layer 1,
## so corpses can't block shots, sight, or the player.
const RAGDOLL_LAYER := 1 << 3
## Ragdoll parts collide with the world (layer 1) and with each other
## (layer 4). Without the second part, limbs pass through the torso and the
## body crumples into a heap. Bones joined together don't collide with their
## direct neighbours, which is what keeps them from fighting at the joints.
const WORLD_MASK := 1 | RAGDOLL_LAYER

## PhysicalBone3D has no apply_torque()/apply_torque_impulse() at all --
## confirmed directly against the class reference after the first version of
## this crashed with "Nonexistent function 'apply_torque_impulse'". The
## death-reaction effects below instead SET angular_velocity directly (a
## real property on PhysicalBone3D, also confirmed against the class
## reference) -- the same "command the motion, don't hope an impulse
## survives damping" approach physics_grabber.gd already uses for holding
## props via linear_velocity.

## Fallback when the killing blow has no direction (not a shot): a plain shove
## away from where the enemy was facing, per bone.
@export var death_push: float = 1.0
## Scales every shot's push. 1.0 = the weapon's own impact_force as-is;
## 1.5 = 50% more force on every weapon.
@export var hit_push_scale: float = 1.5
## Fraction of a shot's push given to EVERY bone, so the whole body moves. The
## bone nearest the impact gets the full push on top of that. Low = only the
## hit limb reacts; high = the body moves as one.
@export_range(0.0, 1.0, 0.05) var body_share: float = 0.4
## Extra upward pop, as a fraction of the push, so bodies don't just drag along
## the floor.
@export var hit_lift: float = 0.15
## Shrinks every bone's capsule length at startup (1.0 = as generated). The
## generated shapes often overlap their neighbours at the joints, which makes
## the ragdoll jitter or crumple. Lower this until they just meet.
@export_range(0.2, 1.0, 0.05) var bone_length_scale: float = 0.75
## Same idea for thickness. Limbs clipping into each other is usually capsules
## that are fatter than the limbs they cover.
@export_range(0.2, 1.0, 0.05) var bone_radius_scale: float = 0.9
## Damping makes limbs settle instead of flopping and folding up. 0 = free
## flopping; higher = the body moves as if through thick air and lands flatter.
@export var linear_damping: float = 0.5
@export var angular_damping: float = 4.0
## Multiplies the physics engine's own gravity for every ragdoll bone.
## Verified against the class reference: PhysicalBone3D has a real
## gravity_scale property, defaulting to 1.0 (i.e. the project's plain
## default gravity, ~9.8 m/s^2 unless changed in Project Settings). That's
## HALF the player's own custom gravity constant (20.0, see
## player_movement.gd) -- corpses falling at the physics engine's slower
## default next to a player who falls twice as fast is a big part of why
## they read as "floaty" instead of heavy. >1.0 here closes that gap.
@export var bone_gravity_scale: float = 2.2
## Heavier bones resist getting shoved around by small forces (a joint
## correction, brushing a wall) and carry momentum through instead of
## drifting -- reads as an actual body's weight instead of a balloon in a
## skin suit. Also verified against the class reference: PhysicalBone3D has a
## real mass property, defaulting to 1.0 (same as a basketball).
@export var bone_mass: float = 4.0
## Seconds to wait after death before marking the ground -- long enough for
## the ragdoll to actually stop tumbling first.
@export var blood_pool_delay: float = 1.5

## A violent thrash layered on top of the real physics ragdoll right after
## death -- purely physics (direct velocity kicks on the same PhysicalBone3D
## bones already falling under gravity), not a blended animation.
## PhysicalBoneSimulator3D drives the skeleton entirely from physics once
## active, so there's no separate pose-driver layer to blend an animation
## into the way the earlier Box3D ragdoll experiment had -- this has to be
## real forces, and it reads as a violent reaction to dying rather than the
## body going instantly and perfectly limp.
## REWRITE 2: kicking ONE isolated bone (even with a guaranteed-wake impulse
## first) still didn't produce visible motion. The likely reason: a resting
## ragdoll's cone/hinge joints actively correct a bone back toward its
## neighbor every solver substep -- that's what holds a settled ragdoll
## together at all -- so a single bone moving relative to its still-resting
## neighbor gets fought almost as fast as it happens, no matter how strong
## the velocity. A real flailing limb doesn't move that way anyway: the
## WHOLE limb (upper arm and forearm together) swings as one unit from the
## shoulder, not one segment twitching against the elbow. Giving both bones
## in a limb pair the SAME velocity at once means there's no relative motion
## between them for their shared joint to correct -- only the shoulder/hip
## joint has to allow it, and cone/hinge limits are built to allow rotation
## within their range, just not exceeding it.
@export_group("Death Reaction")
## Off for now (kept, not deleted): there's a future mechanic planned where
## NOT finishing an enemy off cleanly (no double-tap) makes it twitch,
## enlarge, and explode into something stronger -- this same kick/swing
## system is the planned starting point for that twitch, so it stays intact
## and just switched off rather than ripped out.
@export var thrash_enabled: bool = false
## How long the body violently thrashes after death before going fully
## still. Set dynamically from the enemy's own corpse_time at the moment of
## death (see _start_death_reaction()) so the thrash lasts until the corpse
## is about to be removed, rather than a fixed duration disconnected from it.
@export var thrash_time: float = 2.5
## Roughly how many bursts happen per second (a different random limb each
## time) -- high = reads as genuine convulsing, not occasional twitching.
@export var thrash_rate: float = 10.0

## Legs rotate mostly around the character's own sideways axis (a forward/
## back swing from the hip) instead of a fully random axis -- that's what
## actually reads as a KICK instead of a random flail. `kick_wobble` mixes
## in a little randomness on top so both legs don't look identically robotic.
@export var kick_angular_speed: float = 18.0
@export var kick_linear_speed: float = 7.0
@export_range(0.0, 1.0, 0.05) var kick_wobble: float = 0.25

## Arms use a much wider, more random axis spread than legs -- a real arm
## swing isn't confined to one plane the way a kick is, it windmills.
@export var swing_angular_speed: float = 14.0
@export var swing_linear_speed: float = 5.0

## The ORIGINAL ask, revisited now that the whole-limb-pair trick above is
## proven: the closer the body gets to the floor while still falling, the
## faster its arms raise up, like a bracing reflex -- so it lands flat
## instead of just crumpling. This runs BEFORE the thrash above: falls,
## reaching as it nears the ground, then switches to thrashing once landed.
@export_group("Falling Reach")
## Both arm bones get the SAME angular velocity (the limb-pair trick) around
## the character's own sideways axis, scaled by how close to the floor the
## body currently is -- 0 right after death, 1 at floor height.
@export var reach_angular_speed: float = 10.0
## Safety valve: if the body never reads as "landed" (e.g. it's tumbling off
## a ledge), stop reaching and fall through to the thrash anyway after this
## many seconds, rather than reaching forever.
@export var reach_max_time: float = 1.5
## Counts as "landed" once the body has covered this fraction of its total
## drop from death height to floor height.
@export_range(0.5, 1.0, 0.05) var reach_landed_fraction: float = 0.9

@onready var _enemy: Enemy = get_parent() as Enemy

var _simulator: PhysicalBoneSimulator3D
var _animation_player: AnimationPlayer
var _bones: Array[PhysicalBone3D] = []

var _falling := false
var _fall_elapsed := 0.0
var _fall_start_y := 0.0
var _floor_y := 0.0

var _thrashing := false
var _thrash_elapsed := 0.0
var _next_thrash_time := 0.0
## Each entry is {"bones": [upper, lower], "is_leg": bool} -- a 2-bone limb
## that gets kicked TOGETHER, same velocity, in one burst (see the Death
## Reaction group's own comment for why a single isolated bone doesn't
## work), tagged so legs can kick and arms can swing differently.
var _limb_pairs: Array[Dictionary] = []
var _character_right: Vector3 = Vector3.RIGHT


func _ready() -> void:
	_simulator = _find_or_build_simulator()
	if _simulator == null:
		return
	_animation_player = _enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer

	for child in _simulator.get_children():
		var bone := child as PhysicalBone3D
		if bone:
			bone.collision_layer = 0 # no collision while alive
			bone.collision_mask = 0
			bone.linear_damp = linear_damping
			bone.angular_damp = angular_damping
			bone.gravity_scale = bone_gravity_scale
			bone.mass = bone_mass
			# A settled bone can go to sleep (a standard physics optimization) --
			# setting angular_velocity/linear_velocity directly on a SLEEPING
			# body is a well-known Godot pitfall: the assignment can be
			# silently ignored until something else wakes it, which fits
			# exactly with "the thrash code runs and logs fire, but nothing
			# visibly moves." Ragdoll corpses are cheap enough to simulate
			# that never sleeping is a non-issue.
			bone.can_sleep = false
			_shrink_shapes(bone)
			_bones.append(bone)

	if _bones.is_empty():
		push_warning("EnemyRagdoll: the model on %s has no humanoid bones -- was it imported with art/animations/mixamo_bonemap.tres? No ragdoll." % _enemy.name)
		return
	_enemy.state_changed.connect(_on_state_changed)
	print("EnemyRagdoll: %s ready with %d ragdoll bones" % [_enemy.name, _bones.size()]) # TEMPORARY diagnostic


## A model can still ship its own hand-made ragdoll (Skeleton3D > "Create
## physical skeleton" saved in its scene) -- that wins if present. Otherwise one
## is built from whatever skeleton the model has, which is what lets
## EnemyModel swap models without breaking the ragdoll.
func _find_or_build_simulator() -> PhysicalBoneSimulator3D:
	var simulators := _enemy.find_children("*", "PhysicalBoneSimulator3D", true, false)
	if not simulators.is_empty():
		return simulators[0] as PhysicalBoneSimulator3D
	var skeletons := _enemy.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("EnemyRagdoll: no Skeleton3D under %s -- no ragdoll." % _enemy.name)
		return null
	return RagdollBuilder.build(skeletons[0] as Skeleton3D)


## Shrinks a bone's capsule around its centre (length and thickness). The
## shape is copied first, so a shape shared between bones is never shrunk twice.
func _shrink_shapes(bone: PhysicalBone3D) -> void:
	for child in bone.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node and shape_node.shape is CapsuleShape3D:
			var capsule := (shape_node.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
			capsule.radius *= bone_radius_scale
			# A capsule can't be shorter than its own width.
			capsule.height = maxf(capsule.height * bone_length_scale, capsule.radius * 2.0)
			shape_node.shape = capsule


func _on_state_changed(state: Enemy.State) -> void:
	if state == Enemy.State.DEAD:
		_start_ragdoll()


func _start_ragdoll() -> void:
	print("EnemyRagdoll: %s died, starting ragdoll (animation player found: %s)" % [_enemy.name, _animation_player != null]) # TEMPORARY diagnostic
	# Stop the animation so it doesn't fight the physics for control of the bones.
	if _animation_player:
		_animation_player.stop(true)

	for bone in _bones:
		bone.collision_layer = RAGDOLL_LAYER
		bone.collision_mask = WORLD_MASK

	_simulator.physical_bones_start_simulation()

	# Re-apply can_sleep = false HERE, not just back in _ready(). Before this
	# call each bone is still an inactive/kinematic placeholder, not a real
	# simulating body yet -- an earlier assignment made before that may not
	# survive the bone becoming active. Setting it again at the exact moment
	# it starts simulating removes any doubt about that ordering.
	for bone in _bones:
		bone.can_sleep = false

	_apply_hit_impulse()
	_start_death_reaction()
	get_tree().create_timer(blood_pool_delay).timeout.connect(_spawn_blood_pool)


## Builds the two-bone limb pairs and kicks off the falling-reach phase
## (falls through to the thrash once landed -- see _process_falling_reach()).
## TEMPORARY diagnostic print -- if the pair count here isn't 4 (both arms,
## both legs), the bone-name filter itself is the problem, not the velocity math.
func _start_death_reaction() -> void:
	_character_right = _enemy.global_transform.basis.x.normalized()
	_limb_pairs = []
	for entry in [["LeftUpperArm", "LeftLowerArm", false], ["RightUpperArm", "RightLowerArm", false],
			["LeftUpperLeg", "LeftLowerLeg", true], ["RightUpperLeg", "RightLowerLeg", true]]:
		var pair: Array = _bones.filter(func(b): return entry[0] in b.name or entry[1] in b.name)
		if pair.size() == 2:
			_limb_pairs.append({"bones": pair, "is_leg": entry[2]})

	# Track the thrash to the corpse's own remaining lifetime rather than a
	# fixed duration disconnected from it, so it's still going right up until
	# the body is about to be removed.
	thrash_time = maxf(_enemy.corpse_time - 0.3, 0.5)

	# Find the floor below the body right now (still roughly at standing
	# height) so the falling-reach phase has a start height and a target
	# height to measure "closeness to the ground" against. Same raycast
	# pattern as _spawn_blood_pool(). If there's no floor below (fell off a
	# ledge, over a pit), skip straight to thrashing -- there's no ground to
	# reach toward.
	var hips := _bones.filter(func(b): return "Hips" in b.name)
	var start_pos: Vector3 = hips[0].global_position if not hips.is_empty() else _enemy.global_position
	var space := _enemy.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			start_pos + Vector3.UP * 0.5, start_pos + Vector3.DOWN * 10.0)
	query.collision_mask = 1
	var result := space.intersect_ray(query)

	if result.is_empty():
		_falling = false
		_thrashing = thrash_enabled
		_thrash_elapsed = 0.0
		_next_thrash_time = 0.0
		print("EnemyRagdoll: no floor found below, skipping reach, thrash_time %.1fs" % thrash_time)
		return

	_floor_y = result.position.y
	_fall_start_y = start_pos.y
	_fall_elapsed = 0.0
	_falling = true
	_thrashing = false
	print("EnemyRagdoll: falling-reach starting (%d limb pairs), drop %.2fm, thrash_time %.1fs" % [_limb_pairs.size(), _fall_start_y - _floor_y, thrash_time])


## While the body is still dropping, both bones of each ARM pair get matching
## angular velocity around the character's own sideways axis -- the same
## limb-pair trick the thrash uses -- scaled by how close to the floor the
## body currently is, so the arms raise up faster the nearer it gets. Once
## "landed" (or after reach_max_time as a safety valve), hands off to the
## thrash for the post-impact convulsing.
func _process_falling_reach(delta: float) -> void:
	_fall_elapsed += delta

	var hips := _bones.filter(func(b): return "Hips" in b.name)
	var hips_y: float = hips[0].global_position.y if not hips.is_empty() else _floor_y
	var fall_span: float = maxf(_fall_start_y - _floor_y, 0.1)
	var closeness: float = clampf(1.0 - (hips_y - _floor_y) / fall_span, 0.0, 1.0)

	if closeness >= reach_landed_fraction or _fall_elapsed >= reach_max_time:
		_falling = false
		_thrashing = thrash_enabled
		_thrash_elapsed = 0.0
		_next_thrash_time = 0.0
		print("EnemyRagdoll: landed (closeness %.2f, %.2fs), thrash starting" % [closeness, _fall_elapsed])
		return

	for entry in _limb_pairs:
		if entry["is_leg"]:
			continue
		for bone: PhysicalBone3D in entry["bones"]:
			bone.can_sleep = false
			bone.angular_velocity = _character_right * reach_angular_speed * closeness


func _physics_process(delta: float) -> void:
	if _falling:
		_process_falling_reach(delta)
		return
	if not _thrashing:
		return
	_thrash_elapsed += delta
	if _thrash_elapsed > thrash_time:
		_thrashing = false
		print("EnemyRagdoll: death reaction finished")
		return
	if _thrash_elapsed < _next_thrash_time or _limb_pairs.is_empty():
		return
	_next_thrash_time = _thrash_elapsed + (1.0 / thrash_rate)

	var entry: Dictionary = _limb_pairs[randi() % _limb_pairs.size()]
	var pair: Array = entry["bones"]
	var is_leg: bool = entry["is_leg"]
	var taper: float = 1.0 - (_thrash_elapsed / thrash_time)

	# Legs: mostly a forward/back swing from the hip (character_right), like
	# an actual kick, with a little randomness mixed in so both legs don't
	# move identically. Arms: a fully random axis each burst -- a real arm
	# swing windmills, it isn't confined to one plane the way a kick is.
	var axis: Vector3
	var angular_speed: float
	var linear_speed: float
	if is_leg:
		var wobble := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		axis = (_character_right.lerp(wobble, kick_wobble)).normalized()
		if randf() < 0.5:
			axis = -axis
		angular_speed = kick_angular_speed
		linear_speed = kick_linear_speed
	else:
		axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		angular_speed = swing_angular_speed
		linear_speed = swing_linear_speed

	var names: Array[String] = []
	for bone: PhysicalBone3D in pair:
		bone.can_sleep = false # in case anything else along the way re-enabled it
		# A real (if small) impulse first guarantees a genuine wake event via
		# the documented "external force" mechanism -- see can_sleep's own
		# comment in _ready() -- before the actual velocity command below.
		bone.apply_central_impulse(axis * 0.05)
		bone.angular_velocity = axis * angular_speed * taper
		bone.linear_velocity += axis * linear_speed * taper
		names.append(bone.name)
	print("EnemyRagdoll: %s burst on %s (taper %.2f)" % ["kick" if is_leg else "swing", names, taper]) # TEMPORARY diagnostic


## Waits for the corpse to settle before marking the ground, rather than
## placing it at the moment of death -- a ragdoll can tumble a couple of
## meters from where it died, so a pool placed immediately would end up under
## empty air relative to where the body actually ends up.
func _spawn_blood_pool() -> void:
	var hips := _bones.filter(func(b): return "Hips" in b.name)
	var settle_pos: Vector3 = hips[0].global_position if not hips.is_empty() else _enemy.global_position

	# Raycast straight down from the settled body to find the actual floor,
	# whatever it's made of -- a hand-built StaticBody3D or a func_godot-baked
	# TrenchBroom floor look identical to a plain raycast.
	var space := _enemy.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			settle_pos + Vector3.UP * 0.5, settle_pos + Vector3.DOWN * 3.0)
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if result.is_empty():
		return # nothing below (fell off the map, or over a pit) -- no floor to mark
	BloodFX.spawn_splatter(_enemy.get_tree().current_scene, result.position, Vector3.UP, 1.3)


## Pushes the body the way the killing blow pushed it: the bone nearest the
## impact gets the full shove and every other bone gets a smaller share. So a
## shot to the arm kicks the arm, a shot to the chest rocks the whole body, and
## a weak weapon like the pistol just makes the body go limp.
func _apply_hit_impulse() -> void:
	var health := _enemy.health
	var impulse := health.last_hit_impulse * hit_push_scale
	if impulse == Vector3.ZERO:
		# Not a shot: a plain shove away from where the enemy was facing.
		var push := _enemy.global_transform.basis.z * death_push
		for bone in _bones:
			bone.apply_central_impulse(push)
		return

	impulse.y += impulse.length() * hit_lift
	var nearest: PhysicalBone3D = _bones[0]
	for bone in _bones:
		if bone.global_position.distance_to(health.last_hit_position) < nearest.global_position.distance_to(health.last_hit_position):
			nearest = bone
	for bone in _bones:
		bone.apply_central_impulse(impulse if bone == nearest else impulse * body_share)
