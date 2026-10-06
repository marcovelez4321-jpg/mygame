@tool
class_name EnemyWeapon
extends Node

## The gun an enemy holds: a model attached to its hand bone, so it follows
## every animation and falls with the ragdoll. Add as a child of an Enemy.
## Presentation only (Rule 1): it never fires anything itself -- enemy.gd's
## _fire_shot() does the actual hitscan, and each client's copy just shows
## the same gun in the same hand, and draws each shot as a visible bullet
## leaving it (BulletFX).
##
## Tuning the grip: open the enemy's scene (enemy_gunner.tscn), select this
## node, and change the Grip numbers -- the gun moves on the preview model in
## the viewport as you type. The grip is measured from the hand, so once it
## looks right in the T-pose preview it holds in every animation too.

## The gun model -- e.g. the same FBX the player's starter gun uses.
@export var weapon_scene: PackedScene:
	set(value):
		weapon_scene = value
		_rebuild()
## Which bone holds it (Godot humanoid names, from the shared bone map).
@export var hand_bone: String = "RightHand":
	set(value):
		hand_bone = value
		_rebuild()

@export_group("Grip")
## Where the middle of the gun sits, measured from the hand bone, in meters.
## The gun is centred on its own middle first (see _rebuild()), so rotating
## it below spins it in place instead of swinging it around the hand.
@export var grip_position: Vector3 = Vector3.ZERO:
	set(value):
		grip_position = value
		_apply_grip()
@export var grip_rotation_degrees: Vector3 = Vector3(0.0, 0.0, -90.0):
	set(value):
		grip_rotation_degrees = value
		_apply_grip()
## The gun's size. 1 = the model's own size, regardless of how big the
## character model was imported.
@export var grip_scale: float = 1.0:
	set(value):
		grip_scale = value
		_apply_grip()

var _skeleton: Skeleton3D
var _attachment: BoneAttachment3D
## Sits on the hand (via _attachment) and carries the grip transform; the gun
## inside it is shifted so its middle is on this pivot.
var _pivot: Node3D
var _gun: Node3D


func _ready() -> void:
	_rebuild()
	# In the editor, EnemyModel swaps its preview model whenever its variants
	# change, taking the gun with it -- _process puts it back. In game the
	# model is picked once, before this runs (EnemyModel uses _enter_tree).
	set_process(Engine.is_editor_hint())
	var enemy := get_parent() as Enemy
	if enemy and not Engine.is_editor_hint():
		enemy.shot_fired.connect(_on_shot_fired)


## The bullet leaves the middle of the gun -- close enough to the muzzle on
## a pistol, and right whichever way the gun model points.
func _on_shot_fired(end_point: Vector3) -> void:
	if is_instance_valid(_pivot):
		BulletFX.spawn(get_tree().current_scene, _pivot.global_position, end_point, true)


func _process(_delta: float) -> void:
	if _find_skeleton() != _skeleton:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_attachment):
		_attachment.queue_free()
	_attachment = null
	_pivot = null
	_gun = null
	_skeleton = _find_skeleton()
	if _skeleton == null or weapon_scene == null:
		return
	if _skeleton.find_bone(hand_bone) == -1:
		if not Engine.is_editor_hint():
			push_warning("EnemyWeapon: no bone named '%s' on %s." % [hand_bone, get_parent().name])
		return
	# Never given an owner, so in the editor it's a preview only -- nothing
	# here is ever saved into the scene file.
	_attachment = BoneAttachment3D.new()
	_attachment.bone_name = hand_bone
	_skeleton.add_child(_attachment)
	_pivot = Node3D.new()
	_attachment.add_child(_pivot)
	_gun = weapon_scene.instantiate() as Node3D
	_pivot.add_child(_gun)
	_center_on_pivot(_gun)
	_apply_grip()


## The hand passes on the character model's import scale, so it's divided
## back out: grip numbers mean real meters and real gun size on every model.
func _apply_grip() -> void:
	if not is_instance_valid(_pivot) or not is_instance_valid(_skeleton):
		return
	var model_scale := _skeleton.global_basis.get_scale().x
	if model_scale <= 0.0:
		return
	var rotation := Basis.from_euler(grip_rotation_degrees * (PI / 180.0))
	_pivot.transform = Transform3D(rotation.scaled(Vector3.ONE * (grip_scale / model_scale)), grip_position / model_scale)


## Shifts the gun so the middle of its visible meshes sits on its parent's
## origin -- imported gun models often have their origin far from the mesh,
## which made rotating the grip swing the whole gun around. Same fix as the
## first-person viewmodel's (viewmodel.gd's _center_on_pivot()).
func _center_on_pivot(gun: Node3D) -> void:
	var bounds := AABB()
	var has_bounds := false
	var meshes := gun.find_children("*", "MeshInstance3D", true, false)
	if gun is MeshInstance3D:
		meshes.append(gun)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var box := gun.global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	if has_bounds:
		gun.position = -(gun.basis * bounds.get_center())


func _find_skeleton() -> Skeleton3D:
	var parent := get_parent()
	if parent == null:
		return null
	var skeletons := parent.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
