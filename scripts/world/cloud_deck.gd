class_name CloudDeck
extends MeshInstance3D

## A layer of cloud high over the land (shaders/clouds.gdshader): the
## megastructures and the skyline giants vanish into it and rise out of it
## (their own fog thickens in the same band: cloud_bottom..cloud_top in
## skyline.gdshader and the rest). One huge flat sheet at `height`, kept
## under (or over) the camera wherever it goes, so it never ends.

@export var height: float = 800.0
@export var size: float = 40000.0

const SHADER := preload("res://shaders/clouds.gdshader")


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh = plane
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1000.0


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		# Snapped to whole kilometres so the drifting billows don't slide with you.
		global_position = Vector3(snappedf(camera.global_position.x, 1000.0), height, snappedf(camera.global_position.z, 1000.0))
