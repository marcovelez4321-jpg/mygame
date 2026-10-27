class_name ZombieDoor
extends StaticBody3D

## A way on, blocked (the user's, 2026-10-27: Black Ops 1's doors -- areas
## open up as you buy your way through). A slab of rusted sheet metal and
## boards wedged in the doorway; F clears it: it sinks into the floor
## (OPEN_TIME) and is gone. Free for now -- points come with the rounds.
## Rule 1 (co-op): the host's word, every game opens it (_net_open).

const OPEN_TIME := 1.2
const METAL := Color(0.27, 0.2, 0.17)
const WOOD := Color(0.3, 0.22, 0.15)

## The doorway (width, height, depth).
@export var size := Vector3(4.0, 3.0, 0.4)

var use_prompt: String = "Clear the way (free for now)"

var _open := false


func _ready() -> void:
	add_to_group(PlayerMovement.USABLE_GROUP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	var slab := MeshInstance3D.new()
	var sheet := BoxMesh.new()
	sheet.size = size
	slab.mesh = sheet
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL
	metal.roughness = 0.9
	metal.metallic = 0.3
	slab.material_override = metal
	add_child(slab)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD
	wood.roughness = 1.0
	for i in 3:
		var board := MeshInstance3D.new()
		var plank := BoxMesh.new()
		plank.size = Vector3(size.x * 1.05, 0.25, 0.08)
		board.mesh = plank
		board.material_override = wood
		board.position = Vector3(0.0, lerpf(-size.y * 0.3, size.y * 0.3, i / 2.0), size.z * 0.5 + 0.05)
		board.rotation.z = 0.12 * (1 - i)
		add_child(board)


func can_use() -> bool:
	return not _open


func use_by(_player: Node) -> void:
	if _open or (Network.is_online() and not multiplayer.is_server()):
		return
	_do_open()
	if Network.is_online():
		_net_open.rpc()


@rpc("authority", "call_remote", "reliable")
func _net_open() -> void:
	_do_open()


func _do_open() -> void:
	if _open:
		return
	_open = true
	var tween := create_tween()
	tween.tween_property(self, ^"position:y", position.y - size.y - 0.1, OPEN_TIME).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		collision_layer = 0
		visible = false)
