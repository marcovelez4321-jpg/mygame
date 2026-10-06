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
## However long the body stays, the death flail never runs longer than this.
const MAX_THRASH_TIME := 15.0
## Seconds after death (or after the flail ends) before the body may stop
## being simulated. Bodies stay a minute; dozens that never sleep would cost
## physics time for nothing. A shot or rats dragging it wake it right up.
const SETTLE_TIME := 6.0

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

## Runs instead of the normal thrash/settle above whenever _enemy.will_mutate
## is true (see enemy.gd's Mutation export group for the chance/eligibility
## roll itself -- this only handles the VISUAL sequence once it's decided to
## happen). Reuses the same limb-pair kick technique as the Death Reaction
## group above, just driven by its own accelerating rate and duration instead
## of thrash_time/thrash_rate, and it always runs regardless of
## thrash_enabled -- unlike ordinary death flail, this is a deliberate,
## always-visible mechanic, not off-by-default juice.
##
## Twitch goes straight to the explosion, with no swell/enlarge step in
## between -- an earlier version tried to scale the body up first, but a
## PhysicalBone3D's global position is set directly by the physics server,
## completely independent of any ancestor's scale/position, and
## physical_bones_stop_simulation() (needed to freeze the pose before
## scaling it) doesn't freeze the ragdoll's CURRENT fallen pose at all -- it
## hands bone control back to the Skeleton3D's own stored pose, which is
## whatever it was at the moment of death, before the ragdoll ever fell. The
## combination made the corpse visibly snap to a different pose and position
## right as it grew. Not worth fighting that interaction for a step that was
## always going to be on screen for under a second. The body-part throb
## below gets its swelling a different way that sidesteps all of that: it
## only changes how the mesh is drawn (MutationPulseModifier), never the
## physics bodies.
@export_group("Mutation Reaction")
## Total seconds spent twitching before it explodes.
@export var mutate_twitch_time: float = 10.0
## Bursts per second at the very start of the twitch.
@export var mutate_twitch_rate_start: float = 3.0
## Bursts per second right at the end, just before it explodes -- higher
## than mutate_twitch_rate_start so it reads as building toward something,
## not a constant tremor for 10 seconds straight.
@export var mutate_twitch_rate_end: float = 18.0
## Head, torso and each limb throb -- swell up and shrink back to normal --
## each on its own rhythm, building toward the explosion. Visual only (see
## MutationPulseModifier). How much bigger a part gets at the top of a throb
## (0.3 = 30% bigger) at the start and end of the mutation:
@export var mutate_pulse_amount_start: float = 0.12
@export var mutate_pulse_amount_end: float = 0.35
## Throbs per second at the start and end.
@export var mutate_pulse_rate_start: float = 1.2
@export var mutate_pulse_rate_end: float = 4.0
## How out of sync the parts are: 0 = all in step, 0.5 = each part's rhythm
## somewhere between half and one-and-a-half times the shared rate.
@export_range(0.0, 0.9, 0.05) var mutate_pulse_rhythm_variety: float = 0.5
## Killed by something that isn't a player (a roach, a rat, another tweaker):
## no twitching, no swelling -- the body lies still and flashes, faster and
## faster as it gets closer to mutating, over the same mutate_twitch_time.
## Flashes per second at the start and right before it bursts:
@export var mutate_flash_rate_start: float = 0.5
@export var mutate_flash_rate_end: float = 5.0
@export var mutate_flash_color: Color = Color(1.0, 0.25, 0.2, 1.0)
## Seconds each flash takes to fade out.
@export var mutate_flash_time: float = 0.15

@onready var _enemy: Enemy = get_parent() as Enemy

var _simulator: PhysicalBoneSimulator3D
var _animation_player: AnimationPlayer
var _bones: Array[PhysicalBone3D] = []

var _falling := false
var _fall_elapsed := 0.0
var _fall_start_y := 0.0
var _floor_y := 0.0

var _thrashing := false
## Done moving on its own (see _allow_sleep()).
var _settled := false
var _thrash_elapsed := 0.0
var _next_thrash_time := 0.0
## Each entry is {"bones": [upper, lower], "is_leg": bool} -- a 2-bone limb
## that gets kicked TOGETHER, same velocity, in one burst (see the Death
## Reaction group's own comment for why a single isolated bone doesn't
## work), tagged so legs can kick and arms can swing differently.
var _limb_pairs: Array[Dictionary] = []
var _character_right: Vector3 = Vector3.RIGHT

var _mutating := false
var _mutate_elapsed := 0.0
var _next_mutate_time := 0.0
var _pulse: MutationPulseModifier
## Mutating without the twitch and swell -- flashing instead (not a player's kill).
var _mutate_quietly := false


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
	_enemy.mutation_stopped.connect(_on_mutation_stopped)
	print("EnemyRagdoll: %s ready with %d ragdoll bones" % [_enemy.name, _bones.size()]) # TEMPORARY diagnostic


## A model can still ship its own hand-made ragdoll (Skeleton3D > "Create
## physical skeleton" saved in its scene) -- that wins if present. Otherwise one
## is built from whatever skeleton the model has, which is what lets
## EnemyModel swap models without breaking the ragdoll.
##
## Looks only at the skeleton's normal children on purpose: every Skeleton3D
## also creates a hidden, empty, inactive PhysicalBoneSimulator3D of its own
## (Skeleton3D::setup_simulator(), kept for pre-4.3 compatibility), and
## find_children() includes hidden internal nodes. Grabbing that empty one is
## what left every enemy with "no humanoid bones" and no ragdoll.
func _find_or_build_simulator() -> PhysicalBoneSimulator3D:
	var skeletons := _enemy.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("EnemyRagdoll: no Skeleton3D under %s -- no ragdoll." % _enemy.name)
		return null
	var skeleton := skeletons[0] as Skeleton3D
	for child in skeleton.get_children(): # excludes internal nodes by default
		if child is PhysicalBoneSimulator3D:
			return child as PhysicalBoneSimulator3D
	return RagdollBuilder.build(skeleton)


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
	if not _enemy.will_mutate:
		var settle := SETTLE_TIME + (thrash_time if thrash_enabled else 0.0)
		get_tree().create_timer(settle).timeout.connect(_allow_sleep)
	# Rats come and eat bodies on the floor (RatSwarm).
	_enemy.add_to_group(RatSwarm.CORPSE_GROUP)
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
	thrash_time = clampf(_enemy.corpse_time - 0.3, 0.5, MAX_THRASH_TIME)

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
		_start_post_fall_reaction()
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
## "landed" (or after reach_max_time as a safety valve), hands off to
## _start_post_fall_reaction() for whatever comes next (thrash, or the
## mutation twitch).
func _process_falling_reach(delta: float) -> void:
	_fall_elapsed += delta

	var hips := _bones.filter(func(b): return "Hips" in b.name)
	var hips_y: float = hips[0].global_position.y if not hips.is_empty() else _floor_y
	var fall_span: float = maxf(_fall_start_y - _floor_y, 0.1)
	var closeness: float = clampf(1.0 - (hips_y - _floor_y) / fall_span, 0.0, 1.0)

	if closeness >= reach_landed_fraction or _fall_elapsed >= reach_max_time:
		_falling = false
		_start_post_fall_reaction()
		print("EnemyRagdoll: landed (closeness %.2f, %.2fs)" % [closeness, _fall_elapsed])
		return

	for entry in _limb_pairs:
		if entry["is_leg"]:
			continue
		for bone: PhysicalBone3D in entry["bones"]:
			bone.can_sleep = false
			bone.angular_velocity = _character_right * reach_angular_speed * closeness


## Whatever happens right after the body stops falling (or never had a floor
## to fall toward in the first place): the mutation twitch if this death
## rolled one (see enemy.gd's will_mutate), otherwise the ordinary
## thrash_enabled-gated death flail.
func _start_post_fall_reaction() -> void:
	if _enemy.will_mutate:
		_start_mutation_twitch()
		return
	_thrashing = thrash_enabled
	_thrash_elapsed = 0.0
	_next_thrash_time = 0.0


func _physics_process(delta: float) -> void:
	if _falling:
		_process_falling_reach(delta)
		return
	if _mutating:
		_process_mutation_twitch(delta)
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
	_do_limb_burst(1.0 - (_thrash_elapsed / thrash_time))


## One kick/swing burst on a random limb pair, shared by the ordinary
## dying-down thrash above and the mutation twitch below -- they only differ
## in their trigger cadence and how `taper` moves over time (thrash tapers
## DOWN toward 0 as it settles; the mutation twitch stays high and its rate
## climbs instead, see _process_mutation_twitch()).
func _do_limb_burst(taper: float) -> void:
	var entry: Dictionary = _limb_pairs[randi() % _limb_pairs.size()]
	var pair: Array = entry["bones"]
	var is_leg: bool = entry["is_leg"]

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

	for bone: PhysicalBone3D in pair:
		bone.can_sleep = false # in case anything else along the way re-enabled it
		# A real (if small) impulse first guarantees a genuine wake event via
		# the documented "external force" mechanism -- see can_sleep's own
		# comment in _ready() -- before the actual velocity command below.
		bone.apply_central_impulse(axis * 0.05)
		bone.angular_velocity = axis * angular_speed * taper
		bone.linear_velocity += axis * linear_speed * taper


## Kicks off the mutation twitch: same limb-pair kick technique as the
## ordinary thrash, but its OWN duration/rate (mutate_twitch_time/_rate_*)
## and always runs, independent of thrash_enabled -- see that export's own
## comment.
func _start_mutation_twitch() -> void:
	_mutating = true
	_mutate_elapsed = 0.0
	_next_mutate_time = 0.0
	_mutate_quietly = not _enemy.killed_by_player
	if not _mutate_quietly:
		_start_pulse()
	else:
		get_tree().create_timer(SETTLE_TIME).timeout.connect(_allow_sleep) # lies still


## The body-part throb. Added to the skeleton AFTER the ragdoll's simulator so
## it runs after it each frame (modifiers run in child order) and swells the
## pose the ragdoll just set, not the other way round.
func _start_pulse() -> void:
	var skeleton := _simulator.get_parent() as Skeleton3D
	if skeleton == null:
		return
	_pulse = MutationPulseModifier.new()
	_pulse.amount_start = mutate_pulse_amount_start
	_pulse.amount_end = mutate_pulse_amount_end
	_pulse.rate_start = mutate_pulse_rate_start
	_pulse.rate_end = mutate_pulse_rate_end
	_pulse.rhythm_variety = mutate_pulse_rhythm_variety
	skeleton.add_child(_pulse)


func _stop_pulse() -> void:
	if is_instance_valid(_pulse):
		_pulse.queue_free()
	_pulse = null


## Rate climbs from mutate_twitch_rate_start to _rate_end over the whole
## window -- "twitch faster and faster" right up to the moment it explodes,
## instead of a constant tremor for mutate_twitch_time straight. taper is
## fixed at 1.0 (not tapering down like the ordinary thrash does) -- this
## needs to stay violent right up to the explosion, not settle.
func _process_mutation_twitch(delta: float) -> void:
	_mutate_elapsed += delta
	if _mutate_elapsed >= mutate_twitch_time:
		_mutating = false
		_explode_and_spawn_mutant()
		return
	var progress := _mutate_elapsed / mutate_twitch_time
	if _mutate_quietly:
		if _mutate_elapsed >= _next_mutate_time:
			_next_mutate_time = _mutate_elapsed + 1.0 / lerpf(mutate_flash_rate_start, mutate_flash_rate_end, progress)
			HitFlash.flash(_enemy, mutate_flash_color, mutate_flash_time)
		return
	if _mutate_elapsed < _next_mutate_time or _limb_pairs.is_empty():
		return
	if is_instance_valid(_pulse):
		_pulse.progress = progress
	var rate := lerpf(mutate_twitch_rate_start, mutate_twitch_rate_end, progress)
	_next_mutate_time = _mutate_elapsed + (1.0 / rate)
	_do_limb_burst(1.0)


## Double-tapped mid-twitch (enemy.gd's damage_mutation()): the twitch stops
## dead and the body goes limp -- no explosion, no mutant. If it's still
## falling, nothing to stop yet: _start_post_fall_reaction() sees will_mutate
## is now false and gives it the ordinary death thrash instead.
func _on_mutation_stopped() -> void:
	_mutating = false
	_stop_pulse()
	get_tree().create_timer(SETTLE_TIME).timeout.connect(_allow_sleep)


## The payoff: a blood explosion at roughly the body's center, then the
## mutant itself takes this corpse's place. _enemy.spawn_mutant() frees this
## Enemy (and everything under it, including this EnemyRagdoll) once it's
## done, so nothing here needs its own cleanup.
func _explode_and_spawn_mutant() -> void:
	var hips := _bones.filter(func(b): return "Hips" in b.name)
	var center: Vector3 = hips[0].global_position if not hips.is_empty() else _enemy.global_position
	BloodFX.spawn_mutation_explosion(_enemy.get_tree().current_scene, center)
	_enemy.spawn_mutant(center)


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


## Where the body actually is now -- its hips -- since the ragdoll slides
## and tumbles away from where the enemy died.
func body_position() -> Vector3:
	for bone in _bones:
		if "Hips" in bone.name:
			return bone.global_position
	return _bones[0].global_position if not _bones.is_empty() else _enemy.global_position


## Rats dragging the corpse (RatSwarm): every bone gets the same sideways
## velocity, so the whole body slides along as one piece -- pushing single
## bones just makes the joints fight (see _apply_hit_impulse()). ZERO lets go.
func drag(velocity: Vector3) -> void:
	var dragging := velocity != Vector3.ZERO
	for bone in _bones:
		bone.can_sleep = _settled and not dragging
		if dragging:
			bone.apply_central_impulse(Vector3.UP * 0.001) # wakes a sleeping body
		bone.linear_velocity = Vector3(velocity.x, minf(bone.linear_velocity.y, 0.5), velocity.z)


## Roaches carrying the body by its limbs (RoachCarry): `held` maps each bone a
## roach has hold of to the velocity it's being pulled at, and the whole body
## weighs `weight` of normal (1 = full, 0 = weightless) -- every roach holding
## on takes a share. Held at several points (hands, feet, hips, head) the body
## hangs between them instead of every limb dangling off one held torso, which
## used to outweigh the pull and stall the lift halfway up. Empty `held` lets
## go and restores full weight.
func carry(held: Dictionary, weight: float = 1.0) -> void:
	var holding := not held.is_empty()
	for bone in _bones:
		bone.can_sleep = _settled and not holding
		bone.gravity_scale = bone_gravity_scale * (weight if holding else 1.0)
		if held.has(bone):
			bone.apply_central_impulse(Vector3.UP * 0.001) # wakes a sleeping body
			bone.linear_velocity = held[bone]


## The ragdoll bone for humanoid bone `bone_name` ("LeftHand", "Hips"...), or null.
func bone_named(bone_name: String) -> PhysicalBone3D:
	for bone in _bones:
		if bone.bone_name == bone_name:
			return bone
	return null


## Any part of the body resting on (or just above) the ground.
func is_touching_ground() -> bool:
	var space := _enemy.get_world_3d().direct_space_state
	for bone in _bones:
		var query := PhysicsRayQueryParameters3D.create(bone.global_position, bone.global_position + Vector3.DOWN * 0.25)
		query.collision_mask = 1
		if not space.intersect_ray(query).is_empty():
			return true
	return false


## Settled: from here the physics engine may put the body to sleep.
func _allow_sleep() -> void:
	if _mutating:
		return
	_settled = true
	for bone in _bones:
		if is_instance_valid(bone):
			bone.can_sleep = true


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
