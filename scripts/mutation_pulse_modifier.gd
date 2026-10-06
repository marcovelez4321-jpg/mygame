class_name MutationPulseModifier
extends SkeletonModifier3D

## Makes a mutating corpse's body parts throb -- head, torso and each limb
## swelling and shrinking back to normal, each on its own rhythm, faster and
## bigger as the mutation nears its explosion. EnemyRagdoll adds it to the
## skeleton when the mutation twitch starts and sets `progress` every tick.
##
## Visual only. It runs after the ragdoll's PhysicalBoneSimulator3D (it's
## added after it, and modifiers run in child order), so it only changes how
## the mesh is drawn this frame -- the physics bodies never change size, which
## is what broke the old "swell" step. Skeleton3D restores the bone poses
## after drawing, so nothing builds up from frame to frame.
##
## Scaling a bone normally scales everything attached below it too (a bigger
## chest would inflate the arms and head). Each bone's own pose is divided by
## its parent's pulse, so every part swells on its own and the joints stay
## exactly where the ragdoll put them.

## The body parts that throb. Fingers, toes and the like just ride along.
const PULSING_BONES: PackedStringArray = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]

## 0 at the start of the mutation, 1 at the explosion. Set by EnemyRagdoll.
var progress: float = 0.0
## How much bigger a part gets at the top of a throb (0.3 = 30% bigger), at
## the start and at the end of the mutation.
var amount_start: float = 0.12
var amount_end: float = 0.35
## Throbs per second at the start and at the end.
var rate_start: float = 1.2
var rate_end: float = 4.0
## How differently each part is timed: 0.5 = each part's rhythm is somewhere
## between 50% and 150% of the shared rate.
var rhythm_variety: float = 0.5

## Per bone index: its rhythm multiplier and where it is in its cycle.
var _bone_ids: PackedInt32Array = []
var _rhythms: PackedFloat32Array = []
var _phases: PackedFloat32Array = []
## Per bone index (every bone): this frame's pulse, 1.0 = normal size.
var _scales: PackedFloat32Array = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_scales.resize(skeleton.get_bone_count())
	for bone_name in PULSING_BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone == -1:
			continue
		_bone_ids.append(bone)
		_rhythms.append(randf_range(1.0 - rhythm_variety, 1.0 + rhythm_variety))
		_phases.append(randf() * TAU) # start out of step with each other


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _bone_ids.is_empty():
		return
	var rate := lerpf(rate_start, rate_end, progress)
	var amount := lerpf(amount_start, amount_end, progress)

	_scales.fill(1.0)
	for i in _bone_ids.size():
		_phases[i] = fmod(_phases[i] + TAU * rate * _rhythms[i] * delta, TAU)
		# 0 most of the cycle, rising to 1 and back: a swell-and-release
		# throb that always returns to normal size, never smaller.
		var throb := pow(0.5 - 0.5 * cos(_phases[i]), 2.0)
		_scales[_bone_ids[i]] = 1.0 + amount * throb

	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var parent_scale := _scales[parent] if parent >= 0 else 1.0
		var own_scale := _scales[bone]
		if own_scale == 1.0 and parent_scale == 1.0:
			continue
		# Undo the parent's pulse so only this bone's own pulse shows, and
		# pull its joint back to where it was before the parent grew.
		skeleton.set_bone_pose_scale(bone, skeleton.get_bone_pose_scale(bone) * (own_scale / parent_scale))
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) / parent_scale)
