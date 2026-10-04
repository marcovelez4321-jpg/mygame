class_name RagdollBuilder
extends RefCounted

## Builds a ragdoll at runtime for any humanoid Skeleton3D: a
## PhysicalBoneSimulator3D with one PhysicalBone3D per body part.
##
## Why this exists: the ragdoll used to be made with Skeleton3D's "Create
## physical skeleton" button and saved INSIDE one specific model instance in
## enemy.tscn. Swapping the model threw those nodes away with it -- that's the
## "ragdoll broke when we changed the model" bug. Building it in code from
## whatever skeleton is actually there means any model imported with the
## shared bone map (art/animations/mixamo_bonemap.tres) gets a ragdoll fitted
## to its own proportions, with no editor work.
##
## The shape/offset math is a port of the editor button itself
## (Skeleton3DEditor::create_physical_bone() in Godot's
## editor/scene/3d/skeleton_3d_editor_plugin.cpp, MIT -- notice at the bottom
## of this file), so it produces what the button produced. The joint table is
## copied from the hand-tuned values that were in enemy.tscn.

const NONE := PhysicalBone3D.JOINT_TYPE_NONE
const PIN := PhysicalBone3D.JOINT_TYPE_PIN
const CONE := PhysicalBone3D.JOINT_TYPE_CONE
const HINGE := PhysicalBone3D.JOINT_TYPE_HINGE

## One entry per body part that gets a physics body, keyed by Godot's standard
## humanoid bone name (what the bone map renames Mixamo bones to). Bones not
## listed here -- fingers, toes, the head's end bone -- get no body, the same
## ones that were deleted by hand from the old baked ragdoll.
## cone: swing/twist spans in degrees. hinge: lower/upper limits in degrees.
## rotation: the joint frame's rotation in degrees (lines up a hinge's axis).
## The left/right differences (upper-arm swing, lower-arm rotation) are
## carried over from the old ragdoll as-is.
const JOINTS := {
	"Hips": {"type": NONE},
	"Spine": {"type": CONE, "swing": 20.0, "twist": 20.0},
	"Chest": {"type": CONE, "swing": 15.0, "twist": 15.0},
	"UpperChest": {"type": CONE, "swing": 15.0, "twist": 15.0},
	"Neck": {"type": CONE, "swing": 30.0, "twist": 30.0},
	"Head": {"type": CONE, "swing": 40.0, "twist": 40.0},
	"LeftShoulder": {"type": CONE, "swing": 15.0, "twist": 30.0},
	"RightShoulder": {"type": CONE, "swing": 15.0, "twist": 30.0},
	"LeftUpperArm": {"type": CONE, "swing": 60.0, "twist": 45.0},
	"RightUpperArm": {"type": CONE, "swing": 80.0, "twist": 45.0},
	"LeftLowerArm": {"type": HINGE, "lower": -140.0, "upper": 0.0},
	"RightLowerArm": {"type": HINGE, "lower": -140.0, "upper": 0.0, "rotation": Vector3(90.0, 0.0, 0.0)},
	"LeftHand": {"type": CONE, "swing": 30.0, "twist": 20.0},
	"RightHand": {"type": CONE, "swing": 30.0, "twist": 20.0},
	"LeftUpperLeg": {"type": PIN},
	"RightUpperLeg": {"type": PIN},
	"LeftLowerLeg": {"type": HINGE, "lower": 0.0, "upper": 140.0, "rotation": Vector3(0.0, 90.0, 0.0)},
	"RightLowerLeg": {"type": HINGE, "lower": 0.0, "upper": 140.0, "rotation": Vector3(0.0, 90.0, 0.0)},
	"LeftFoot": {"type": CONE, "swing": 30.0, "twist": 15.0},
	"RightFoot": {"type": CONE, "swing": 30.0, "twist": 15.0},
}


## Adds a PhysicalBoneSimulator3D to `skeleton` with a body for every bone in
## JOINTS that it has, and returns it. A skeleton that wasn't imported with
## the humanoid bone map has none of these names and gets an empty simulator.
static func build(skeleton: Skeleton3D) -> PhysicalBoneSimulator3D:
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)

	var skeleton_scale := skeleton.global_transform.basis.get_scale().x
	# Same walk the editor button does: a bone gets a body the first time one
	# of its children is seen, and that first child decides the body's length.
	var built := {}
	for bone_id in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone_id)
		if parent < 0 or built.has(parent):
			continue
		if not JOINTS.has(skeleton.get_bone_name(parent)):
			continue
		built[parent] = true
		simulator.add_child(_make_bone(skeleton, parent, bone_id, skeleton_scale))
	return simulator


## One capsule body spanning from `bone_id` to `child_id`.
##
## Scale: physics bodies can't be scaled, but enemy models are (enemy.tscn's
## Model node is 0.45). The editor handled that by cancelling the scale out of
## the body's rotation and scaling the joint position instead, while leaving
## capsule sizes in skeleton units -- this reproduces exactly those numbers
## (checked against the old baked ragdoll), so tuning carries over unchanged.
static func _make_bone(skeleton: Skeleton3D, bone_id: int, child_id: int, skeleton_scale: float) -> PhysicalBone3D:
	var bone_name := skeleton.get_bone_name(bone_id)
	var config: Dictionary = JOINTS[bone_name]
	var child_rest := skeleton.get_bone_rest(child_id)
	var half_height := child_rest.origin.length() * 0.5

	var capsule := CapsuleShape3D.new()
	capsule.height = half_height * 2.0
	capsule.radius = half_height * 0.2
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = capsule
	# Lays the capsule (Y-up by default) along the body's Z axis, i.e. the bone.
	shape.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)

	var up := Vector3.UP
	if up.cross(child_rest.origin).is_zero_approx():
		up = Vector3.BACK
	var body_basis := Basis.looking_at(child_rest.origin, up)

	var body := PhysicalBone3D.new()
	body.name = "Physical Bone %s" % bone_name # weapon_controller.gd finds the neck by this name
	body.bone_name = bone_name
	body.body_offset = Transform3D(body_basis.scaled(Vector3.ONE / skeleton_scale),
			body_basis * Vector3(0.0, 0.0, -half_height))
	var rotation_degrees: Vector3 = config.get("rotation", Vector3.ZERO)
	body.joint_offset = Transform3D(Basis.from_euler(rotation_degrees * (PI / 180.0)),
			Vector3(0.0, 0.0, half_height * skeleton_scale))
	_apply_joint(body, config)
	body.add_child(shape)
	return body


## Joint type first: the joint_constraints/* properties only exist once a type
## is set. Anything not set here keeps Godot's defaults, which are what the old
## ragdoll used too (bias 0.3, softness 0.8 cone / 0.9 hinge, relaxation 1).
static func _apply_joint(body: PhysicalBone3D, config: Dictionary) -> void:
	body.joint_type = config["type"]
	match body.joint_type:
		CONE:
			body.set("joint_constraints/swing_span", config["swing"])
			body.set("joint_constraints/twist_span", config["twist"])
		HINGE:
			body.set("joint_constraints/angular_limit_enabled", true)
			body.set("joint_constraints/angular_limit_lower", config["lower"])
			body.set("joint_constraints/angular_limit_upper", config["upper"])


# Portions of _make_bone() are ported from Godot Engine:
#
# Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
# Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
