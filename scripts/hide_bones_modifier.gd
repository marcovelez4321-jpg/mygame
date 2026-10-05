class_name HideBonesModifier
extends SkeletonModifier3D

## Shrinks the listed bones -- and everything attached below them -- to
## nothing, every frame, AFTER animation has posed the skeleton. That's how
## the local player's own head and arms vanish from their first-person view
## while the rest of the body stays. Add it as a child of the Skeleton3D.
## Hidden parts don't cast a shadow either; the rest of the body still does.

## Bone names (Godot humanoid names, e.g. "Head", "LeftUpperArm").
@export var bone_names: PackedStringArray = []

var _bones: PackedInt32Array = []
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
	# Not exactly zero: a fully collapsed bone can produce invalid skinning
	# math on some drivers. This is far too small to ever see.
	for bone in _bones:
		skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0001)
