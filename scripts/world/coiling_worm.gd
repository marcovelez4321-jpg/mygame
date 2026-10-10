class_name CoilingWorm
extends MultiMeshInstance3D

## A colossal worm wound round a megastructure's tower (scenery -- Rule 9):
## hundreds of metres of segments sliding slowly along a spiral up the
## tower and back down, the boss worm's kin. One MultiMesh (one draw call);
## its segments are laid along the spiral each frame, only while it's in
## view range. The skyline's fog, so it shows coiling high above the murk.

## The spiral (local space): round `radius` of the tower's middle, between
## `bottom` and `top`, `turns` times round.
@export var radius: float = 140.0
@export var bottom: float = 200.0
@export var top: float = 2200.0
@export var turns: float = 5.0
## Segments, how far apart along the spiral (metres), and how thick.
@export var segments: int = 90
@export var spacing: float = 22.0
@export var thickness: float = 28.0
## How fast it slides along the spiral (metres a second), up then down.
@export var crawl_speed: float = 10.0
@export var draw_distance: float = 9000.0

const SEGMENT_MESH := "res://art/worm_boss/worm_segment_mesh.res"
const SKIN := preload("res://art/props/PSX Creatures/Textures/tape_worm.png")
const SKYLINE := preload("res://shaders/skyline.gdshader")
## The baked segment's length along Z (BurrowWorm: SEGMENT_MESH_LENGTH).
const SEGMENT_LENGTH := 1.55

var _along := 0.0
var _direction := 1.0
var _length := 0.0


func _ready() -> void:
	var mesh := load(SEGMENT_MESH) as Mesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = segments
	var skin := ShaderMaterial.new()
	skin.shader = SKYLINE
	skin.set_shader_parameter("albedo_texture", SKIN)
	material_override = skin
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = draw_distance
	# Every segment's somewhere on the spiral: a box round all of it.
	custom_aabb = AABB(Vector3(-radius - thickness, bottom - thickness, -radius - thickness),
			Vector3((radius + thickness) * 2.0, top - bottom + thickness * 2.0, (radius + thickness) * 2.0))
	var climb := (top - bottom) / turns
	_length = turns * sqrt(pow(TAU * radius, 2.0) + climb * climb)
	_along = randf() * (_length - segments * spacing)
	_lay()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(global_position) > draw_distance:
		return
	_along += crawl_speed * _direction * delta
	var room := _length - segments * spacing
	if _along > room or _along < 0.0:
		_direction = -_direction # up to the top, then back down
		_along = clampf(_along, 0.0, room)
	_lay()


## Each segment on the spiral, facing along it, the head leading.
func _lay() -> void:
	for i in segments:
		var distance := _along + (segments - i) * spacing
		var at := _point(distance)
		# Facing along the spiral: across the segment, a metre back to a metre
		# ahead (at the very end of the spiral "ahead" is clamped onto the
		# point itself, and a zero direction can't be faced).
		var along := _point(distance + 1.0) - _point(distance - 1.0)
		if along.length_squared() < 0.000001:
			continue
		var taper := lerpf(0.6, 1.0, sin(float(i) / segments * PI)) # thinner at both ends
		var basis := Basis.looking_at(along.normalized(), Vector3.UP)
		basis = basis * Basis(Vector3.BACK, i * 0.3) * Basis.from_scale(Vector3(thickness * taper, thickness * taper, spacing * 1.3 / SEGMENT_LENGTH))
		multimesh.set_instance_transform(i, Transform3D(basis, at))


## The point `distance` along the spiral from its bottom (local space).
func _point(distance: float) -> Vector3:
	var t := clampf(distance / maxf(_length, 1.0), 0.0, 1.0)
	var angle := t * turns * TAU
	var wobble := sin(t * 40.0) * radius * 0.06 # it hugs the tower unevenly
	return Vector3(cos(angle) * (radius + wobble), lerpf(bottom, top, t), sin(angle) * (radius + wobble))
