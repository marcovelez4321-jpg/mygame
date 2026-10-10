class_name LiftButton
extends StaticBody3D

## A button for a megastructure's lift (StackLift), pressed like any other
## (look at it, F: PlayerMovement's usable things). At a stop it calls the
## lift there; on the lift's deck it sends it on to the next stop. A post
## with a lit button: red while the lift's on its way, amber when it's ready.

## The lift (empty = the StackLift this is on, for the deck's panel).
@export var lift_path: NodePath
## Which stop this calls the lift to (-1: on the deck, sends it on).
@export var stop: int = -1

var use_prompt: String = "Call lift"
var _lift: StackLift
var _light_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(PlayerMovement.USABLE_GROUP)
	_lift = (get_node_or_null(lift_path) if not lift_path.is_empty() else get_parent()) as StackLift
	if stop < 0:
		use_prompt = "Send lift"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.5, 0.8)
	shape.shape = box
	shape.position = Vector3.UP * 0.75
	add_child(shape)
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.5, 1.3, 0.5)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.2, 0.18, 0.16)
	post_mesh.material = metal
	post.mesh = post_mesh
	post.position = Vector3.UP * 0.65
	add_child(post)
	var button := MeshInstance3D.new()
	var button_mesh := SphereMesh.new()
	button_mesh.radius = 0.16
	button_mesh.height = 0.2
	button_mesh.radial_segments = 8
	button_mesh.rings = 4
	_light_material = StandardMaterial3D.new()
	_light_material.emission_enabled = true
	button_mesh.material = _light_material
	button.mesh = button_mesh
	button.position = Vector3(0.0, 1.35, 0.0)
	add_child(button)
	_show_ready(true)


func can_use() -> bool:
	return _lift != null and not _lift.is_travelling()


func use_by(_player: Node) -> void:
	if _lift == null:
		return
	if stop >= 0:
		_lift.call_to(stop)
	else:
		_lift.go_next()


func _process(_delta: float) -> void:
	if _lift:
		_show_ready(not _lift.is_travelling())


func _show_ready(ready: bool) -> void:
	var color := Color(1.0, 0.6, 0.15) if ready else Color(1.0, 0.1, 0.05)
	_light_material.albedo_color = color
	_light_material.emission = color * 1.5
