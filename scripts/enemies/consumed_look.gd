class_name ConsumedLook
extends SkeletonModifier3D

## The Consumed's head (the user's: limbs dangling dead, the head up and aimed
## perfectly at you): its neck and head turned, every frame, to look straight
## at `target`, whatever the rest of it is doing.

var target := Vector3.INF
## How much of the turn the neck takes (the head the rest).
const NECK_SHARE := 0.35

var _neck := -1
var _head := -1


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not target.is_finite():
		return
	if _head < 0:
		_head = skeleton.find_bone("Head")
		_neck = skeleton.find_bone("Neck")
	if _head < 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var aim := to_skeleton * target
	for pair: Array in [[_neck, NECK_SHARE], [_head, 1.0]]:
		var bone: int = pair[0]
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		# Where it faces now: the model's front (+Z) turned as the bone is
		# turned from its rest (whatever way the bone's own axes lie).
		var rest := skeleton.get_bone_global_rest(bone)
		var forward := ((pose.basis * rest.basis.inverse()) * Vector3.BACK).normalized()
		var want := (aim - pose.origin).normalized()
		if forward.length_squared() < 0.0001 or want.length_squared() < 0.0001:
			continue
		var turn := Quaternion(forward, want)
		turn = Quaternion.IDENTITY.slerp(turn, float(pair[1]))
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var turned := Basis(turn) * pose.basis
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())
