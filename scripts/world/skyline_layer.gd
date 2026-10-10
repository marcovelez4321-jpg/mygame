class_name SkylineLayer
extends Node3D

## The skyline: megastructures and growths kilometres tall, kilometres off,
## rising out of the murk past anything you can reach -- Half-Life 2's 3D
## skybox (the Citadel), done as real geometry at real distance so it shifts
## slowly as you walk, like mountains.
## Put anything under this node: TrenchBroom maps (func_godot scenes),
## Blender models (glTF), anything. Build them small if that's easier --
## HL2 built its skybox at 1/16 -- and scale the instance up (x16: a 100 m
## TrenchBroom tower becomes a 1.6 km one). On load everything under it is
## made skyline:
##   its materials swapped for shaders/skyline.gdshader (same texture and
##   colour; its own fog, thick low and thinning with height),
##   no shadows, no collision (nothing out there is reachable),
## and the camera's far plane pushed out to view_distance.
## Cheap: a few hundred triangles a giant, always loaded, no streaming, no
## physics; a dozen of them cost a handful of draw calls.
## With nothing under it (and placeholders on) it grows a few stand-ins.

## Grow stand-in giants if there's nothing under this node.
@export var placeholders: bool = true
## How far the camera sees (metres): past the furthest giant.
@export var view_distance: float = 16000.0
@export_group("Fog")
## The skyline's fog (skyline.gdshader): the ground level, how high it
## thins out over, and how far you see through it at the ground and up high.
@export var fog_floor: float = 0.0
@export var thin_height: float = 600.0
@export var near_reach: float = 260.0
@export var far_reach: float = 9000.0

const SHADER := preload("res://shaders/skyline.gdshader")

## Original material -> its skyline version.
var _converted := {}
var _vertex_colored: ShaderMaterial
var _silhouette: ShaderMaterial
var _camera_check := 0.0


func _ready() -> void:
	if placeholders and get_child_count() == 0:
		_grow_placeholders()
	_make_skyline(self)
	child_entered_tree.connect(func(node: Node) -> void: _make_skyline.call_deferred(node))


func _process(delta: float) -> void:
	_camera_check -= delta
	if _camera_check > 0.0:
		return
	_camera_check = 1.0
	var camera := get_viewport().get_camera_3d()
	if camera and camera.far < view_distance:
		camera.far = view_distance


## Everything under `root`: skyline materials, no shadows, no collision.
func _make_skyline(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var nodes := root.find_children("*", "", true, false)
	nodes.append(root)
	for node in nodes:
		if node is CollisionShape3D or node is CollisionPolygon3D:
			node.queue_free()
		elif node is CollisionObject3D:
			(node as CollisionObject3D).collision_layer = 0
			(node as CollisionObject3D).collision_mask = 0
		if node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			geometry.ignore_occlusion_culling = true
			if geometry.material_override:
				geometry.material_override = _convert(geometry.material_override)
			var mesh_instance := geometry as MeshInstance3D
			if mesh_instance and mesh_instance.mesh:
				for surface in mesh_instance.mesh.get_surface_count():
					mesh_instance.set_surface_override_material(surface, _convert(mesh_instance.get_active_material(surface)))


## The skyline version of a material: its texture and colour kept.
func _convert(original: Material) -> Material:
	if original is ShaderMaterial and (original as ShaderMaterial).shader == SHADER:
		return original
	if original != null and _converted.has(original):
		return _converted[original]
	var result := _fresh()
	var base := original as BaseMaterial3D
	if base:
		if base.albedo_texture:
			result.set_shader_parameter("albedo_texture", base.albedo_texture)
		result.set_shader_parameter("albedo_color", base.albedo_color)
		result.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	elif original == null:
		result.set_shader_parameter("use_vertex_color", true)
	if original != null:
		_converted[original] = result
	return result


func _fresh() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("fog_floor", fog_floor)
	material.set_shader_parameter("thin_height", thin_height)
	material.set_shader_parameter("near_reach", near_reach)
	material.set_shader_parameter("far_reach", far_reach)
	return material


# ---- Stand-ins (until real ones are made) -----------------------------------

## A ring of giants round the world, out past its edge: colossal
## silhouettes of the land's own giant growths (the kelp towers, coral
## trees, fungus towers, hive spires, flesh stalks and vine pillars you walk
## among, a kilometre or two tall out there), and two megastructure
## stand-ins (a tower, a loop of land) until real ones are built.
func _grow_placeholders() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 6060
	var giants: Array = [GrowthMeshes.Kind.KELP_TOWER, GrowthMeshes.Kind.FUNGUS_TOWER, &"tower",
			GrowthMeshes.Kind.HIVE_SPIRE, GrowthMeshes.Kind.VINE_PILLAR, GrowthMeshes.Kind.CORAL_TREE,
			&"loop", GrowthMeshes.Kind.FLESH_STALK, GrowthMeshes.Kind.KELP_TOWER, GrowthMeshes.Kind.HIVE_SPIRE]
	for i in giants.size():
		var angle := TAU * i / giants.size() + random.randf_range(-0.2, 0.2)
		var distance := random.randf_range(3500.0, 7500.0)
		var giant := MeshInstance3D.new()
		if giants[i] is StringName:
			giant.name = "Giant_%s_%d" % [giants[i], i]
			giant.mesh = SkylineMeshes.build(giants[i], random)
			giant.material_override = _vertex_material()
		else:
			# One of the growths, scaled up from tens of metres to one or two kilometres.
			var kind: GrowthMeshes.Kind = giants[i]
			giant.name = "Giant_%s_%d" % [GrowthMeshes.Kind.keys()[kind], i]
			giant.mesh = GrowthMeshes.get_mesh(kind, random.randi() % 4)
			giant.material_override = _silhouette_material()
			giant.scale = Vector3.ONE * random.randf_range(900.0, 2000.0) / maxf(giant.mesh.get_aabb().size.y, 1.0)
		giant.position = Vector3(cos(angle) * distance, -30.0, sin(angle) * distance)
		giant.rotation.y = random.randf() * TAU
		add_child(giant)


## The growths as silhouettes: their own colours, darkened; their bulbs and
## vents still glowing.
func _silhouette_material() -> ShaderMaterial:
	if _silhouette == null:
		_silhouette = _fresh()
		_silhouette.set_shader_parameter("use_vertex_color", true)
		_silhouette.set_shader_parameter("albedo_color", Color(0.45, 0.45, 0.45))
		_silhouette.set_shader_parameter("glow_color", Color(2.0, 2.0, 2.0))
	return _silhouette

func _vertex_material() -> ShaderMaterial:
	if _vertex_colored == null:
		_vertex_colored = _fresh()
		_vertex_colored.set_shader_parameter("use_vertex_color", true)
	return _vertex_colored
