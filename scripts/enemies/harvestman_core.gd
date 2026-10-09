class_name HarvestmanCore
extends Node3D

## A Harvestman's body -- the sack its legs carry -- one of three kinds
## (HarvestmanBuilder makes them, saved in the model scene):
##   BARNACLE: a huge barnacle hung upside down, tinted sickly;
##   DEEPMAW: a Deepmaw coiled round on itself into a ball (the coil is
##     written into its skeleton's rest pose, so it shows in the editor);
##   FUSED: civilian torsos fused together into a ball round a fleshy middle,
##     heads lolling out.
## In game it breathes (a slow swell), and the Deepmaw slowly writhes in its
## coil. Move/scale this node (or its parts) in the model scene to reshape it.

enum Kind { BARNACLE, DEEPMAW, FUSED }

@export var kind: Kind = Kind.BARNACLE
## How much it swells with each breath, and breaths a second.
@export var breathing: float = 0.05
@export var breath_speed: float = 0.3
## The Deepmaw's writhing: how far each bone twists (radians), and how fast.
@export var writhe: float = 0.07
@export var writhe_speed: float = 0.7

## Extra swelling on top of the breathing (0 = none, 0.3 = 30% fatter):
## the Harvestman pumps this up before its sack splits (the brood drop).
var swell := 0.0

var _time := 0.0
var _base_scale := Vector3.ONE
var _skeleton: Skeleton3D
var _chain := PackedInt32Array()
var _chain_rest: Array[Quaternion] = []
var _chain_axis: Array[Vector3] = []


func _ready() -> void:
	_base_scale = scale
	_time = randf() * 10.0
	if kind == Kind.DEEPMAW:
		var skeletons := find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_skeleton = skeletons[0] as Skeleton3D
			var axis_meta = get_meta("coil_axis", Vector3.UP)
			var coil_axis: Vector3 = axis_meta
			var bone := _skeleton.find_bone("Bone")
			while bone != -1:
				_chain.append(bone)
				var rest := _skeleton.get_bone_rest(bone)
				_chain_rest.append(rest.basis.get_rotation_quaternion())
				# The coil's axis in this bone's own frame: twisting round it
				# tightens or loosens the coil (the writhing).
				var global_rest := _skeleton.get_bone_global_rest(bone)
				_chain_axis.append((global_rest.basis.inverse() * coil_axis).normalized())
				var children := _skeleton.get_bone_children(bone)
				bone = children[0] if not children.is_empty() else -1


func _process(delta: float) -> void:
	_time += delta
	var size := 1.0 + sin(_time * TAU * breath_speed) * breathing + swell
	scale = _base_scale * Vector3(size, 1.0 + (size - 1.0) * 0.5, size)
	if _skeleton == null:
		return
	for i in _chain.size():
		var twist := sin(_time * writhe_speed * TAU - i * 0.6) * writhe
		_skeleton.set_bone_pose_rotation(_chain[i], _chain_rest[i] * Quaternion(_chain_axis[i], twist))
