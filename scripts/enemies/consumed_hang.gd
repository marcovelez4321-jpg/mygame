class_name ConsumedHang
extends SkeletonModifier3D

## The Consumed's limbs farther off than its limbs' real physics
## (Consumed.LIMB_PHYSICS_NEAR): each upper and lower limb turned to hang
## straight down, swaying a little -- what the physics would show, for
## nothing (no physics bodies). Active only while the ragdoll isn't.

const CHAIN: Array[StringName] = [&"LeftUpperArm", &"LeftLowerArm", &"RightUpperArm", &"RightLowerArm",
		&"LeftUpperLeg", &"LeftLowerLeg", &"RightUpperLeg", &"RightLowerLeg"]
## How far they sway (radians) and how fast.
const SWAY := 0.12
const SWAY_SPEED := 1.3

var _bones: Array[int] = []
var _ends: Array[int] = []
var _phase := randf() * TAU


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bones.is_empty():
		for bone_name in CHAIN:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				continue
			var children := skeleton.get_bone_children(bone)
			if children.is_empty():
				continue
			_bones.append(bone)
			_ends.append(children[0])
		if _bones.is_empty():
			_bones.append(-1) # (none: never looked for again)
	var t := Time.get_ticks_msec() * 0.001 * SWAY_SPEED + _phase
	var sway := Basis(Vector3.RIGHT, sin(t) * SWAY) * Basis(Vector3.BACK, sin(t * 0.73) * SWAY)
	var down := (skeleton.global_basis.orthonormalized().inverse() * (sway * Vector3.DOWN)).normalized()
	for i in _bones.size():
		var bone := _bones[i]
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var now := skeleton.get_bone_global_pose(_ends[i]).origin - pose.origin
		if now.length_squared() < 0.000001:
			continue
		var turn := Quaternion(now.normalized(), down)
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * (Basis(turn) * pose.basis)).get_rotation_quaternion())
