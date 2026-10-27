class_name PoseBlendOut
extends SkeletonModifier3D

## A pose the skeleton was just in (a knocked-down enemy's ragdoll as it gets
## up: EnemyRagdoll.stand_up()) eased out into whatever's animating it, over
## TIME -- held in the world where it was, so the body rises out of where it
## lay instead of snapping upright. Frees itself after.

const TIME := 0.7

## Every bone's pose in the world, when it started.
var world_poses: Array[Transform3D] = []

var _left := TIME


func _process(delta: float) -> void:
	_left -= delta
	influence = clampf(_left / TIME, 0.0, 1.0)
	if _left <= 0.0:
		queue_free()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for i in mini(world_poses.size(), skeleton.get_bone_count()):
		var global := to_skeleton * world_poses[i]
		var parent := skeleton.get_bone_parent(i)
		var local := global if parent < 0 else (to_skeleton * world_poses[parent]).affine_inverse() * global
		skeleton.set_bone_pose(i, local.orthonormalized())
