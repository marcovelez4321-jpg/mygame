class_name HideBonesModifier
extends SkeletonModifier3D

## Shrinks the listed bones -- and everything attached below them -- to
## nothing, every frame, AFTER animation has posed the skeleton. That's how
## the local player's own head and arms vanish from their first-person view
## while the rest of the body stays. Add it as a child of the Skeleton3D.
## Hidden parts don't cast a shadow either; the rest of the body still does.

## Bone names (Godot humanoid names, e.g. "Head", "LeftUpperArm").
@export var bone_names: PackedStringArray = []
## Bones (with everything below them) put back exactly where they were after
## the hiding -- so you can hide a body but keep its arms: hide "Hips", keep
## "LeftShoulder" and "RightShoulder" (the first-person arms do this, so the
## torso can't swing into view when the gun's lowered).
@export var keep_bones: PackedStringArray = []
## Bones put back where they were but still shrunk to nothing, before the
## keep_bones: the parts of a hidden body that the kept ones hang off. The
## skin between them (a shoulder blended with the chest) then pulls in to
## that spot, right behind the arm, instead of stretching off to the hips.
@export var collapse_in_place: PackedStringArray = []

var _bones: PackedInt32Array = []
var _kept: PackedInt32Array = []
var _in_place: PackedInt32Array = []
var _resolved := false


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not _resolved:
		_resolved = true
		for bone_name in bone_names:
			var index := skeleton.find_bone(bone_name)
			if index != -1:
				_bones.append(index)
		for bone_name in keep_bones:
			var index := skeleton.find_bone(bone_name)
			if index != -1:
				_kept.append(index)
		for bone_name in collapse_in_place:
			var index := skeleton.find_bone(bone_name)
			if index != -1:
				_in_place.append(index)
	var in_place_poses: Array[Transform3D] = []
	for bone in _in_place:
		in_place_poses.append(skeleton.get_bone_global_pose(bone))
	var kept_poses: Array[Transform3D] = []
	for bone in _kept:
		kept_poses.append(skeleton.get_bone_global_pose(bone))
	# Not exactly zero: a fully collapsed bone can produce invalid skinning
	# math on some drivers. This is far too small to ever see.
	for bone in _bones:
		skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0001)
	for i in _in_place.size():
		var pose := in_place_poses[i]
		skeleton.set_bone_global_pose(_in_place[i], Transform3D(pose.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * 0.0001), pose.origin))
	for i in _kept.size():
		skeleton.set_bone_global_pose(_kept[i], kept_poses[i])
