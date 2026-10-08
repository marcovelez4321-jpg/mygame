class_name JiggleLimb
extends Node3D

## An arm or a leg -- cut off one of the civilian character models
## (MeshCut) -- hanging out of a Harvestman's body, swinging on jiggle bones
## (Half-Life 2's $jigglebone idea): every joint is a point on a spring that
## pulls it back toward the limb's own shape, with gravity dragging it down
## and some damping. The root is carried by the body, so as the Harvestman
## steps, lurches and sways, the limb lags behind, swings out, bounces and
## settles -- no physics bodies, so it's cheap and never explodes or jitters.
##
## Made once by HarvestmanBuilder (build()) and saved in the Harvestman's
## model scene; loaded from there it finds its own model and bones (_ready).
## The limb sticks out along this node's -Z: turn the node in the model
## scene to aim it, move it to move where it comes out of the body.
## Later: `can_grab` is where a grabbing attack would hook in (reaching for a
## player under the body); for now they're decoration.
## Rule 1 (co-op): pure looks, every peer runs its own.

const ARM := ["UpperArm", "LowerArm", "Hand"]
const LEG := ["UpperLeg", "LowerLeg", "Foot"]

## Which limb this is: "Left"/"Right", and an arm or a leg.
@export var side: String = "Left"
@export var is_leg: bool = false
## Pull back toward its own shape (higher = stiffer), how quickly a swing dies
## down, and how hard gravity drags it (m/s²).
@export var stiffness: float = 7.0
@export var damping: float = 2.2
@export var gravity: float = 9.8
## Not simulated past this far from the camera (it holds its pose).
@export var sim_distance: float = 70.0
var can_grab := false

var _skeleton: Skeleton3D
var _bones := PackedInt32Array()
var _rest_local: Array[Transform3D] = []
var _child_offset: Array[Vector3] = []
var _parent_rest := Transform3D.IDENTITY
## Each joint past the root (the end of each bone), world space, and its
## velocity.
var _points := PackedVector3Array()
var _velocities := PackedVector3Array()
var _ready_ok := false


## Builds the limb from `character` (HarvestmanBuilder): the `side` arm (or
## leg when `leg`), `length` meters from root to tip whatever size the model
## was made. False if the model hasn't got that limb.
func build(character: PackedScene, limb_side: String, leg: bool, length: float) -> bool:
	side = limb_side
	is_leg = leg
	var model := character.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	for animator in model.find_children("*", "AnimationPlayer", true, false):
		animator.get_parent().remove_child(animator) # the bones are ours
		animator.free()
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		model.queue_free()
		return false
	var root := skeleton.find_bone(side + ("UpperLeg" if is_leg else "Shoulder"))
	if root == -1:
		root = skeleton.find_bone(side + ("UpperLeg" if is_leg else "UpperArm"))
	if root == -1 or not MeshCut.keep(model, skeleton, MeshCut.subtree(skeleton, root)):
		model.queue_free()
		return false
	if not _setup(skeleton):
		model.queue_free()
		return false
	# Lay the model so the limb's root is at our origin and it points down -Z.
	var skeleton_in_model := model.global_transform.affine_inverse() * skeleton.global_transform
	var start := skeleton_in_model * (_parent_rest * _rest_local[0]).origin
	var tip_skeleton := _parent_rest * _rest_local[0]
	for i in range(1, _bones.size()):
		tip_skeleton = tip_skeleton * _rest_local[i]
	var tip := skeleton_in_model * (tip_skeleton * _child_offset[-1])
	var along := (tip - start).normalized()
	var size := length / maxf(start.distance_to(tip), 0.0001)
	var turn := Basis(Quaternion(along, Vector3.FORWARD)).scaled(Vector3.ONE * size)
	model.transform = Transform3D(turn, -(turn * start))
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true


func _ready() -> void:
	if not _ready_ok:
		var skeleton := _find_skeleton(self)
		if skeleton:
			_setup(skeleton)
	if _ready_ok:
		_reset_points.call_deferred()


func _find_skeleton(under: Node) -> Skeleton3D:
	var skeletons := under.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] as Skeleton3D if not skeletons.is_empty() else null


## The limb's bones and their rest shape, from its skeleton.
func _setup(skeleton: Skeleton3D) -> bool:
	_skeleton = skeleton
	# Everything here works from the rest pose; a model's saved pose can differ.
	_skeleton.reset_bone_poses()
	_bones.clear()
	_rest_local.clear()
	_child_offset.clear()
	for part in (LEG if is_leg else ARM):
		var bone := _skeleton.find_bone(side + part)
		if bone == -1:
			break
		_bones.append(bone)
	if _bones.size() < 2:
		return false
	for i in _bones.size():
		_rest_local.append(_skeleton.get_bone_rest(_bones[i]))
		var children := _skeleton.get_bone_children(_bones[i])
		if i + 1 < _bones.size():
			_child_offset.append(_skeleton.get_bone_rest(_bones[i + 1]).origin)
		elif not children.is_empty():
			_child_offset.append(_skeleton.get_bone_rest(children[0]).origin)
		else:
			_child_offset.append(_child_offset[-1] * 0.6) # a hand/foot as long as most of the bone before
	var parent := _skeleton.get_bone_parent(_bones[0])
	_parent_rest = _skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
	_ready_ok = true
	return true


## Every joint where the limb's own shape puts it (spawning).
func _reset_points() -> void:
	if not is_inside_tree():
		return
	var to_world := _skeleton.global_transform
	_points.clear()
	_velocities.clear()
	var current := _parent_rest
	for i in _bones.size():
		current = current * _rest_local[i]
		_points.append(to_world * (current * _child_offset[i]))
		_velocities.append(Vector3.ZERO)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _ready_ok or _points.size() != _bones.size() or delta <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(global_position) > sim_distance:
		return
	delta = minf(delta, 0.05)
	var to_world := _skeleton.global_transform
	var to_skeleton := to_world.affine_inverse()
	var parent := _parent_rest
	for i in _bones.size():
		var current := parent * _rest_local[i]
		var joint := to_world * current.origin
		# Where the end of this bone would be if it held its shape off its
		# parent as it is now: what the spring pulls toward.
		var want := to_world * (current.origin + current.basis * _child_offset[i])
		var length := joint.distance_to(want)
		var velocity := _velocities[i]
		velocity += (stiffness * (want - _points[i]) - damping * velocity + Vector3.DOWN * gravity) * delta
		var point := _points[i] + velocity * delta
		var reach := point - joint
		point = joint + (reach.normalized() if reach.length_squared() > 0.000001 else (want - joint).normalized()) * length
		_velocities[i] = (point - _points[i]) / delta
		_points[i] = point
		# Turn the bone onto where its end went.
		var was := current.basis * _child_offset[i]
		var wants := to_skeleton * point - current.origin
		if was.length_squared() > 0.0000001 and wants.length_squared() > 0.0000001:
			var turned := Basis(Quaternion(was.normalized(), wants.normalized())) * current.basis
			_skeleton.set_bone_pose_rotation(_bones[i], (parent.basis.inverse() * turned).get_rotation_quaternion())
			current = Transform3D(turned, current.origin)
		parent = current
