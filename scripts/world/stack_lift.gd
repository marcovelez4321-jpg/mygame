class_name StackLift
extends AnimatableBody3D

## Something still running on a megastructure that you can ride: a lift
## climbing the outside of a tower, or a cable car swinging between towers.
## A deck (railed, lamp-lit) that travels from stop to stop (`stops`, in its
## parent's space), easing in and out, pausing at each, then back the way it
## came. Its deck's top is level with the floor at each stop. An
## AnimatableBody3D, so whatever stands on it rides with it.
## Rule 1 (co-op): the host moves it; it's synced like any moving platform.

@export var stops := PackedVector3Array()
## Top speed (m/s), how quickly it gets up to it, and the pause at each stop.
@export var speed: float = 35.0
@export var acceleration: float = 6.0
@export var pause: float = 8.0
@export var size: Vector3 = Vector3(18.0, 2.0, 18.0)
## Hangs under a cable (a cable car) rather than running up a wall.
@export var hanging: bool = false

var _target := 1
var _step := 1
var _wait := 0.0
var _speed := 0.0


func _ready() -> void:
	sync_to_physics = true
	if stops.size() > 0:
		position = stops[0] - Vector3.UP * size.y * 0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.2, 0.18)
	metal.roughness = 0.9
	_piece(Vector3.ZERO, size, metal)
	# Railings round three sides (the fourth is the way on and off), and a
	# frame up to where it hangs from, if it hangs.
	_piece(Vector3(-size.x * 0.5, 1.5, 0.0), Vector3(0.4, 3.0, size.z), metal)
	_piece(Vector3(size.x * 0.5, 1.5, 0.0), Vector3(0.4, 3.0, size.z), metal)
	_piece(Vector3(0.0, 1.5, -size.z * 0.5), Vector3(size.x, 3.0, 0.4), metal)
	if hanging:
		_piece(Vector3(0.0, 9.0, 0.0), Vector3(0.8, 16.0, 0.8), metal)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.25)
	lamp.light_energy = 6.0
	lamp.omni_range = 60.0
	lamp.position = Vector3(0.0, 6.0, 0.0)
	add_child(lamp)


func _piece(at: Vector3, piece_size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = piece_size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or stops.size() < 2:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var goal := stops[_target] - Vector3.UP * size.y * 0.5
	var left := position.distance_to(goal)
	# Ease: speed up, cruise, slow down to stop at the goal.
	var can := sqrt(2.0 * acceleration * left)
	_speed = minf(minf(_speed + acceleration * delta, speed), maxf(can, 1.0))
	position = position.move_toward(goal, _speed * delta)
	if position.is_equal_approx(goal):
		_speed = 0.0
		_wait = pause
		if _target + _step < 0 or _target + _step >= stops.size():
			_step = -_step # back the way it came
		_target += _step
