class_name FallingChunk
extends Node3D

## A chunk of concrete shaken loose by the heart's kick (the user's): it
## breaks off a wall, tumbles down, and bursts into dust and rubble where it
## lands. Landing on you: DAMAGE (the host's game decides; every game draws it).

const GRAVITY := 22.0
const DAMAGE := 20.0
const LIFETIME := 12.0
const CONCRETE := "res://art/megastructures/stack_plain.res"

var _velocity := Vector3.ZERO
var _spin := Vector3.ZERO
var _size := 2.0
var _decides := false
var _age := 0.0
var _done := false

static var _material: StandardMaterial3D


static func drop(world: Node, at: Vector3, push: Vector3, size: float, decides: bool) -> FallingChunk:
	var chunk := FallingChunk.new()
	chunk._velocity = push
	chunk._size = size
	chunk._decides = decides
	world.add_child(chunk)
	chunk.global_position = at
	return chunk


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		var texture := load(CONCRETE) as Texture2D
		if texture:
			_material.albedo_texture = texture
			_material.uv1_scale = Vector3(0.25, 0.25, 0.25)
		_material.albedo_color = Color(0.62, 0.6, 0.57)
	var rock := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(randf_range(0.7, 1.0), randf_range(0.5, 0.9), randf_range(0.7, 1.1)) * _size
	rock.mesh = box
	rock.material_override = _material
	add_child(rock)
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_spin = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	# Grit trailing off it as it falls.
	var trail := HeartQuake.dust_particles(10, 1.2, Vector2(0.3, 1.2), _size * 0.6)
	trail.local_coords = false
	add_child(trail)
	trail.emitting = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	_velocity += Vector3.DOWN * GRAVITY * delta
	var next := global_position + _velocity * delta
	rotation += _spin * delta
	if _decides:
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as PlayerMovement
			if player and not player.is_dead() and (player.global_position + Vector3.UP * 0.9).distance_to(next) < _size * 0.6 + 0.5:
				player.health.take_damage(DAMAGE, Health.NO_ATTACKER, _velocity.normalized(), next, 1.0)
				_shatter(next, Vector3.UP)
				return
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, next + _velocity.normalized() * _size * 0.4, 1))
	if not hit.is_empty():
		_shatter(hit.position, hit.normal)
		return
	global_position = next


## Into dust and rubble where it lands.
func _shatter(at: Vector3, normal: Vector3) -> void:
	_done = true
	HeartQuake.dust(get_tree().current_scene, at + normal * 0.5, _size * 1.5)
	HeartQuake.rubble(get_tree().current_scene, at + normal * 0.5, _size)
	queue_free()
