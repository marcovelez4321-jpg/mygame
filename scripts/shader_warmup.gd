class_name ShaderWarmup
extends CanvasLayer

## Shader warm-up (the standard fix for first-use hitches): the first time an
## effect is drawn, Godot compiles its shaders -- the user's 72 ms freeze on
## the first blood hit. So at the start of a level, behind a short black cover
## (like a load fade), each effect is shown once in front of the camera for a
## few frames, then everything it made is removed. The HUD makes one.
## Your own screen only (Rule 1: presentation).

## Frames the effects are on screen for (the compiles happen on the first).
const FRAMES := 4

var _made: Array[Node] = []


func _ready() -> void:
	layer = 127
	var cover := ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var camera := get_viewport().get_camera_3d()
	var world := get_tree().current_scene
	if camera == null or world == null:
		queue_free()
		return
	get_tree().node_added.connect(_on_added)
	# In the air ahead (nothing to splash onto, so nothing's left on the ground).
	var at := camera.global_transform * Vector3(0.0, 0.5, -4.0)
	var facing := camera.global_basis.z
	BloodFX.spawn_impact(world, at, facing)
	BloodFX.spawn_splatter(world, at, facing)
	BloodFX.spawn_bullet_hole(world, at, facing)
	BloodFX.spawn_mutation_explosion(world, at)
	BurningBarrel.place(world, at + Vector3.DOWN * 1.5)
	for model in [CarryItem.meat_model(false, false), CarryItem.meat_model(false, true), CarryItem.meat_model(true, false),
			FleshTree.pod_model(Virus.WINGS), HeartOrb.look_model()]:
		if model:
			world.add_child(model)
			_made.append(model)
			model.global_position = at + camera.global_basis.x * randf_range(-1.0, 1.0)
	for i in FRAMES:
		await get_tree().process_frame
	get_tree().node_added.disconnect(_on_added)
	for node in _made:
		if is_instance_valid(node) and node.is_inside_tree():
			node.queue_free()
	queue_free()


## Only the effects it set off (never a creature or anything else that
## happened to spawn meanwhile).
func _on_added(node: Node) -> void:
	if node.get_parent() == get_tree().current_scene and (node is GPUParticles3D or node is Decal or node is BurningBarrel):
		_made.append(node)
