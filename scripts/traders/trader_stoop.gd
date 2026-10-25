class_name TraderStoop
extends SkeletonModifier3D

## Bent from pulling (the user's, 2026-10-25: a heavy stoop): over whatever
## the walk or idle does, his back bent forward `degrees` (shared down the
## spine), and his head lifted a little back up so he still looks where he's
## going -- pushed forward, the old puller's way.

@export var degrees := 35.0
const SPINE := ["Spine", "Chest", "UpperChest"]
const HEAD := ["Neck", "Head"]
## How much of the bend the neck and head take back.
const LOOK_UP := 0.35

var _spine: Array[int] = []
var _head: Array[int] = []


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _spine.is_empty():
		for bone: String in SPINE:
			var i := skeleton.find_bone(bone)
			if i >= 0:
				_spine.append(i)
		for bone: String in HEAD:
			var i := skeleton.find_bone(bone)
			if i >= 0:
				_head.append(i)
	if _spine.is_empty():
		return
	var bend := Quaternion(Vector3.RIGHT, deg_to_rad(degrees) / _spine.size())
	for i in _spine:
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * bend)
	if not _head.is_empty():
		var back := Quaternion(Vector3.RIGHT, -deg_to_rad(degrees) * LOOK_UP / _head.size())
		for i in _head:
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * back)
