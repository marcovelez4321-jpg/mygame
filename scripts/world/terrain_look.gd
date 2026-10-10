class_name TerrainLook
extends Node

## Puts the alien ground shader (shaders/alien_terrain.gdshader) on the
## Terrain3D next to this node, once Terrain3D has finished setting up.
## Why not just save it on the material: a saved scene lists "override
## enabled" before "which shader", so on load Terrain3D turns the override
## on with no shader yet, builds its own default (the grey checkerboard you
## get with no textures) and doesn't rebuild when ours arrives a moment
## later. Re-applying it here, in the right order, after setup, does.

@export var shader: Shader = preload("res://shaders/alien_terrain.gdshader")
## The ground (empty = the Terrain3D next to this node).
@export var terrain: Node3D
## Which biome is where (empty = sewer everywhere): the shader blends the
## reef and sewer colours by it.
@export var biomes: BiomeMap


func _ready() -> void:
	if terrain == null:
		terrain = get_parent().get_node_or_null(^"Terrain3D") as Node3D
	if terrain == null:
		push_warning("TerrainLook: no Terrain3D next to it")
		return
	# After Terrain3D's own setup, which runs over its first frames.
	await get_tree().process_frame
	await get_tree().process_frame
	var material: Object = terrain.call("get_material")
	if material == null:
		return
	material.call("enable_shader_override", false)
	material.call("set_shader_override", shader)
	material.call("enable_shader_override", true)
	material.set("show_checkered", false)
	terrain.set("show_checkered", false)
	if biomes:
		material.call("set_shader_param", &"biome_map", biomes.texture())
		material.call("set_shader_param", &"biome_area", biomes.area_vector())
	material.call("update")
