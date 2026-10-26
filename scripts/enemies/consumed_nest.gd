class_name ConsumedNest
extends StaticBody3D

## A Consumed nest (the user's, 2026-10-26): a fleshy swelling stuck to a
## tower's wall (up the Stack's high towers, up the Ossuary's spires),
## pulsing; while anyone's within REACH of it, it lets one of the Consumed out
## every EVERY (at most ALIVE of its own about at once). HEALTH: shot dead,
## it's dead for the session.
## Every game makes the same nests (ConsumedDirector: the same spots from the
## same seed); the host's lets them out and decides when one dies, and tells
## every game (Network.send_nest_dead).

const HEALTH := 150.0
const REACH := 150.0
const EVERY := 60.0
const ALIVE := 2
const SIZE := 3.5
const FLESH := Color(0.45, 0.08, 0.1)

var nest_id := 0
## Circling round here, what it lets out (the Ossuary's spires); INF: none.
var circle_at := Vector3.INF

var _health: Health
var _left := 0.0
var _mine: Array[Consumed] = []
var _look: MeshInstance3D
var _time := 0.0
var _dead := false

static var _material: StandardMaterial3D


func _init() -> void:
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = HEALTH
	add_child(_health)


func _ready() -> void:
	add_to_group(&"consumed_nests")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SIZE * 0.6
	shape.shape = sphere
	add_child(shape)
	_look = MeshInstance3D.new()
	var blob := SphereMesh.new()
	blob.radius = SIZE * 0.6
	blob.height = SIZE * 1.1
	blob.radial_segments = 10
	blob.rings = 6
	_look.mesh = blob
	_look.material_override = flesh()
	add_child(_look)
	_left = randf() * EVERY
	if not (Network.is_online() and not multiplayer.is_server()):
		_health.died.connect(func(_attacker: int, _critical: bool) -> void: Network.send_nest_dead(nest_id))


static func flesh() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = FLESH
		_material.roughness = 0.4
		_material.metallic_specular = 0.8
		_material.emission_enabled = true
		_material.emission = Color(0.5, 0.05, 0.05)
		_material.emission_energy_multiplier = 0.3
	return _material


func _process(delta: float) -> void:
	_time += delta
	var beat := 1.0 + 0.06 * sin(_time * 3.0) + 0.04 * sin(_time * 7.1)
	_look.scale = Vector3(beat, 1.0 / beat, beat)


func _physics_process(delta: float) -> void:
	if _dead or (Network.is_online() and not multiplayer.is_server()):
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = EVERY
	for i in range(_mine.size() - 1, -1, -1):
		if not is_instance_valid(_mine[i]) or _mine[i].is_queued_for_deletion():
			_mine.remove_at(i)
	if _mine.size() >= ALIVE or not _anyone_within(REACH):
		return
	var one := Consumed.new()
	one.look = randi()
	one.circle_at = circle_at
	get_tree().current_scene.add_child(one)
	one.global_position = global_position + global_basis.z * (SIZE + 2.0)
	_mine.append(one)


func _anyone_within(reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(global_position) < reach:
			return true
	return false


## Dead (every game): a burst, and gone.
func kill() -> void:
	if _dead:
		return
	_dead = true
	BloodFX.spawn_burst(get_tree().current_scene, global_position, 2.0)
	queue_free()
