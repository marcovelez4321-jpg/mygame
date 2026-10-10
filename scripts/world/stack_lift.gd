class_name StackLift
extends AnimatableBody3D

## A lift still running up the outside of a megastructure: a cabin you can
## ride, crawling between `bottom` and `top` (local heights) along its
## cable, pausing at each end. An AnimatableBody3D, so whatever stands on it
## rides with it. Rule 1 (co-op): the host moves it; it's synced like any
## moving platform.

@export var bottom: float = 40.0
@export var top: float = 1400.0
@export var speed: float = 6.0
@export var pause: float = 8.0
@export var size: Vector3 = Vector3(18.0, 10.0, 18.0)

var _going_up := true
var _wait := 0.0
var _base := Vector3.ZERO


func _ready() -> void:
	_base = position
	position.y = _base.y + bottom
	sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = size
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.2, 0.18)
	metal.roughness = 0.9
	cabin_mesh.material = metal
	cabin.mesh = cabin_mesh
	add_child(cabin)
	# Its lamp: a small light so you can see it climbing in the murk.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.25)
	lamp.light_energy = 6.0
	lamp.omni_range = 60.0
	lamp.position = Vector3(0.0, size.y * 0.5 + 1.0, 0.0)
	add_child(lamp)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var goal := _base.y + (top if _going_up else bottom)
	position.y = move_toward(position.y, goal, speed * delta)
	if is_equal_approx(position.y, goal):
		_going_up = not _going_up
		_wait = pause
