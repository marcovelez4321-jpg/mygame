class_name HitFlash
extends RefCounted

## A brief white flash across every mesh on a hit character, so getting shot
## reads as an immediate, felt impact. Rule 2: one shared helper every enemy
## type calls instead of each variant rigging its own flash logic.
##
## Uses MeshInstance3D.material_overlay -- verified against the class
## reference: it renders on top of whatever material/texture a surface
## already has, for every surface on that mesh at once, rather than
## replacing it the way material_override would. That means the model's real
## skin stays untouched and just gets bathed in white for a moment, instead
## of vanishing during the flash.
##
## A fresh material is created per flash() call rather than one shared
## static material -- two enemies flashing at overlapping times would
## otherwise fight over the same alpha tween on the same shared resource.

const FLASH_COLOR := Color(1.0, 1.0, 1.0, 1.0)
## Seconds the flash takes to fade back out. "Split second" -- kept short so
## it reads as a hit reaction, not a status effect.
const FLASH_TIME := 0.08


## Flashes every MeshInstance3D under `root` white, then fades back out.
static func flash(root: Node) -> void:
	var meshes := _find_mesh_instances(root)
	if meshes.is_empty():
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = FLASH_COLOR
	for mesh in meshes:
		mesh.material_overlay = mat

	var tree := root.get_tree()
	if tree == null:
		for mesh in meshes:
			mesh.material_overlay = null
		return

	var tween := tree.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, FLASH_TIME)
	tween.tween_callback(func() -> void:
		for mesh in meshes:
			# Only clear it if nothing hit again and replaced it with a
			# newer flash material in the meantime.
			if is_instance_valid(mesh) and mesh.material_overlay == mat:
				mesh.material_overlay = null
	)


static func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_mesh_instances(node, result)
	return result


static func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)
