class_name ItemPickup
extends RigidBody3D

## Pills or a bandage lying in the level: a real physics object like a
## WeaponPickup (it falls, sits on the floor, gets shoved and shot around),
## with a separate PickupArea that hands it to a player who walks into it --
## and, like a key, says so on screen. A player already carrying as many as
## they can (WeaponController.max_pills / max_bandages) leaves it there.
## Its collision box is fitted to the model when it spawns, so any model works.

@export var item: WeaponController.Item = WeaponController.Item.PILLS
@export var amount: int = 1
@export var model_scene: PackedScene
## The PSX Mega Pack's items are real-sized (a 13 cm bottle): bigger on the
## floor so they're easy to spot.
@export var model_scale: float = 1.6
@export var pickup_sound: SoundEvent = preload("res://audio/events/pickup.tres")

@onready var _pickup_area: Area3D = $PickupArea


func _ready() -> void:
	add_to_group(InteractHighlight.GROUP) # outlined when you look at it
	_build()
	_pickup_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var weapons := body.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return
	var taken := weapons.add_item(item, amount)
	if taken <= 0:
		return # full up: it stays for later
	amount -= taken
	SoundPlayer.play_3d(pickup_sound, global_position, get_tree().current_scene)
	var what := "Pills" if item == WeaponController.Item.PILLS else ("Bandage" if taken == 1 else "Bandages")
	MapIO.show_pickup(get_tree(), "+%d %s" % [taken, what])
	if amount <= 0:
		queue_free()


## The model, scaled up and centred on the body, with a box around it to
## collide with.
func _build() -> void:
	if model_scene == null:
		return
	var model := model_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	var bounds := AABB()
	var has_bounds := false
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var box := global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	if not has_bounds:
		return
	model.position -= bounds.get_center()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
