class_name GrappleIndicator
extends MeshInstance3D

## Where your grapple will land (the user's design): while you hold the
## grapple, a ring lies on the surface it would grab -- flat on a floor, up
## a wall, on a ceiling -- sized so it frames the crosshair rather than
## hiding under it, filling round like a dial as the charge builds. With
## nothing to grab in reach it shows red, out where the grapple would give
## out. Your own view only (PlayerGrapple drives it); nothing it does
## touches the game.

## How big it looks: its radius is this many degrees of your view (so it's
## the same size on screen near or far), at least min_radius metres.
@export var view_degrees: float = 2.6
@export var min_radius: float = 0.35
@export var grab_color: Color = Color(0.92, 0.85, 1.0, 0.95)
@export var miss_color: Color = Color(1.0, 0.18, 0.12, 0.9)

const SHADER := preload("res://shaders/grapple_ring.gdshader")

var _material: ShaderMaterial
var _was_full := false
var _flash := 0.0


func _ready() -> void:
	top_level = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 10
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Shows it for this frame: `at` on a surface facing `normal` that it would
## grab (`grabs`), or where it'd give out (`grabs` false: red, facing the
## camera); `fill` = how charged (0..1).
func show_at(at: Vector3, normal: Vector3, grabs: bool, fill: float, camera: Vector3, delta: float) -> void:
	visible = true
	var distance := camera.distance_to(at)
	var radius := maxf(distance * tan(deg_to_rad(view_degrees)), min_radius)
	var facing := normal if grabs else (camera - at).normalized()
	var up := Vector3.UP if absf(facing.y) < 0.95 else Vector3.FORWARD
	# The quad faces +Z: turned so +Z is the surface's normal, lifted off it a touch.
	global_transform = Transform3D(Basis.looking_at(-facing, up).scaled(Vector3.ONE * radius), at + facing * 0.06)
	var full := fill >= 0.999
	if full and not _was_full:
		_flash = 1.0
	_was_full = full
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_material.set_shader_parameter("color", grab_color if grabs else miss_color)
	_material.set_shader_parameter("fill", fill)
	_material.set_shader_parameter("flash", _flash)


func hide_ring() -> void:
	visible = false
	_was_full = false
