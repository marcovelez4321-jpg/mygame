extends Node

## Debug visual: draws each shot's ray as a short-lived glowing line so you
## can see exactly where shots go. Red = hit something with Health, yellow =
## hit a wall or missed. Presentation only -- it never affects gameplay, so it
## can be switched off (or replaced with real bullet effects) at any time.

const LIFETIME := 0.6   # seconds the line stays visible
const THICKNESS := 0.03 # meters
const HIT_COLOR := Color(1.0, 0.2, 0.2)
const MISS_COLOR := Color(1.0, 0.9, 0.2)

@export var enabled: bool = true

@onready var _weapons: WeaponController = get_parent().get_node("WeaponController")


func _ready() -> void:
	_weapons.shot_resolved.connect(_on_shot_resolved)


func _on_shot_resolved(from: Vector3, to: Vector3, hit_target: bool) -> void:
	if not enabled:
		return

	# The real ray starts at the eye, so from your point of view it's a dot.
	# Start the drawn line a little right/below/ahead so you can see it.
	var direction := (to - from).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var start := from + right * 0.25 + Vector3.DOWN * 0.2 + direction * 0.5
	var length := start.distance_to(to)
	if length < 0.01:
		return

	var box := BoxMesh.new()
	box.size = Vector3(THICKNESS, THICKNESS, length)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = HIT_COLOR if hit_target else MISS_COLOR

	var line := MeshInstance3D.new()
	line.mesh = box
	line.material_override = material
	# Added to the scene root (not the player) so the line stays in the world
	# instead of following you as you move.
	get_tree().current_scene.add_child(line)
	line.global_position = (start + to) * 0.5
	# look_at fails when the line is exactly vertical, so swap the "up" hint.
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	line.look_at(to, up)

	var tween := line.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, LIFETIME)
	tween.tween_callback(line.queue_free)
