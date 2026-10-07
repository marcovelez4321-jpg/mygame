extends Node

## The grimy sewer-city look, laid over every level when it loads (autoloaded
## as SewerLook; tune it in scenes/sewer_look.tscn). Four effects, each its
## own switch in the pause menu's Graphics panel (GameSettings):
##   - Color grade: a sickly green-yellow tint with crushed blacks, through
##     the level's WorldEnvironment (adjustment + a 1D colour-correction
##     gradient).
##   - Grime: filth streaking down the walls and blotching the floors, wet
##     glossy puddles (shaders/sewer_world.gdshader).
##   - Ground fog: thick greenish haze that pools low and thins out above
##     fog_height -- the environment's height fog, nearly free.
##   - Texture warp: the PS1's swimming, affine-mapped textures
##     (sewer_world.gdshader).
## Grime and warp need the level's walls and floors on sewer_world.gdshader:
## when a level loads, every mesh on a StaticBody3D (the map itself -- not
## enemies, props or pickups) has its plain StandardMaterial3Ds swapped for
## it (one converted copy per original, shared). Big BoxMesh/PlaneMesh
## surfaces get split into pieces about warp_segment meters across first, so
## warping bends them instead of tearing a 120 m floor apart.
## Visual only (Rule 1): each player's game does this to its own copy.

const WORLD_SHADER := preload("res://shaders/sewer_world.gdshader")

@export_group("Color Grade")
## Dark-to-light colours every pixel is mapped through (each channel on its
## own): black crushed, mids pulled green, highlights a dirty yellow.
@export var grade_gradient: Gradient
@export var grade_contrast: float = 1.12
@export var grade_saturation: float = 0.85

@export_group("Ground Fog")
@export var fog_color: Color = Color(0.32, 0.38, 0.22)
## Thin overall haze, and the thick layer below fog_height.
@export var fog_density: float = 0.012
@export var fog_height: float = 1.2
@export var fog_height_density: float = 0.55

@export_group("Grime and Warp")
## How strong the grime and the warping are when switched on (0..1).
@export_range(0.0, 1.0, 0.05) var grime_amount: float = 1.0
@export_range(0.0, 1.0, 0.05) var warp_amount: float = 0.6
## Big flat primitive meshes are split into pieces about this many meters
## across, so the warp bends them gently.
@export var warp_segment: float = 2.0

var _environment: Environment
var _converted := {} # StandardMaterial3D -> ShaderMaterial
var _split := {} # big BoxMesh/PlaneMesh -> its split copy


func _ready() -> void:
	if grade_gradient == null:
		grade_gradient = Gradient.new()
		grade_gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
		grade_gradient.colors = PackedColorArray([Color(0, 0, 0), Color(0.02, 0.035, 0.0),
				Color(0.43, 0.5, 0.3), Color(0.95, 1.0, 0.74)])
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 256
	noise_texture.height = 256
	noise_texture.seamless = true
	noise_texture.noise = noise
	RenderingServer.global_shader_parameter_set("sewer_grime_noise", noise_texture)
	apply_settings()
	get_tree().node_added.connect(_on_node_added)


## Re-applies every switch (the pause menu calls this when one changes).
func apply_settings() -> void:
	RenderingServer.global_shader_parameter_set("sewer_affine", warp_amount if GameSettings.texture_warp else 0.0)
	RenderingServer.global_shader_parameter_set("sewer_grime", grime_amount if GameSettings.grime else 0.0)
	if _environment:
		_apply_environment(_environment)


## A level's WorldEnvironment arriving: grade and fog it, and once the level
## has finished loading, put its walls and floors on the world shader.
func _on_node_added(node: Node) -> void:
	var world_environment := node as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	_environment = world_environment.environment
	_apply_environment(_environment)
	await get_tree().process_frame # the rest of the level is in by now
	_convert_level()


func _apply_environment(environment: Environment) -> void:
	if not environment.has_meta("sewer_original"):
		environment.set_meta("sewer_original", {
			"adjustment_enabled": environment.adjustment_enabled,
			"adjustment_contrast": environment.adjustment_contrast,
			"adjustment_saturation": environment.adjustment_saturation,
			"adjustment_color_correction": environment.adjustment_color_correction,
			"fog_enabled": environment.fog_enabled,
			"fog_mode": environment.fog_mode,
			"fog_light_color": environment.fog_light_color,
			"fog_density": environment.fog_density,
			"fog_height": environment.fog_height,
			"fog_height_density": environment.fog_height_density,
		})
	var original: Dictionary = environment.get_meta("sewer_original")
	for key: String in original:
		environment.set(key, original[key])
	if GameSettings.color_grade:
		var lut := GradientTexture1D.new()
		lut.gradient = grade_gradient
		environment.adjustment_enabled = true
		environment.adjustment_contrast = grade_contrast
		environment.adjustment_saturation = grade_saturation
		environment.adjustment_color_correction = lut
	if GameSettings.ground_fog:
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		environment.fog_light_color = fog_color
		environment.fog_density = fog_density
		environment.fog_height = fog_height
		environment.fog_height_density = fog_height_density


func _convert_level() -> void:
	var level := get_tree().current_scene
	if level == null:
		return
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var body := mesh_instance.get_parent() as StaticBody3D
		if body == null or body is Barnacle or mesh_instance.mesh == null:
			continue
		_split_big_primitive(mesh_instance)
		if mesh_instance.material_override:
			mesh_instance.material_override = _converted_material(mesh_instance.material_override)
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_surface_override_material(surface)
			if material == null:
				material = mesh_instance.mesh.surface_get_material(surface)
			if material:
				mesh_instance.set_surface_override_material(surface, _converted_material(material))


## Its world-shader version, if it's a plain opaque StandardMaterial3D (one
## shared copy per original); anything else is left as it is.
func _converted_material(material: Material) -> Material:
	var standard := material as StandardMaterial3D
	if standard == null or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or standard.uv1_triplanar:
		return material
	if _converted.has(standard):
		return _converted[standard]
	var shader_material := ShaderMaterial.new()
	shader_material.shader = WORLD_SHADER
	shader_material.set_shader_parameter("albedo_texture", standard.albedo_texture)
	shader_material.set_shader_parameter("has_texture", standard.albedo_texture != null)
	shader_material.set_shader_parameter("albedo_color", standard.albedo_color)
	shader_material.set_shader_parameter("uv1_scale", standard.uv1_scale)
	shader_material.set_shader_parameter("uv1_offset", standard.uv1_offset)
	shader_material.set_shader_parameter("roughness", standard.roughness)
	shader_material.set_shader_parameter("metallic", standard.metallic)
	_converted[standard] = shader_material
	return shader_material


## A big BoxMesh or PlaneMesh split into pieces about warp_segment meters
## across (its own copy), so affine warping bends it instead of tearing it.
func _split_big_primitive(mesh_instance: MeshInstance3D) -> void:
	if _split.has(mesh_instance.mesh):
		mesh_instance.mesh = _split[mesh_instance.mesh]
		return
	var original := mesh_instance.mesh
	var box := mesh_instance.mesh as BoxMesh
	if box:
		var split := box.duplicate() as BoxMesh
		split.subdivide_width = clampi(int(box.size.x / warp_segment), 0, 64)
		split.subdivide_height = clampi(int(box.size.y / warp_segment), 0, 64)
		split.subdivide_depth = clampi(int(box.size.z / warp_segment), 0, 64)
		mesh_instance.mesh = split
		_split[original] = split
		return
	var plane := mesh_instance.mesh as PlaneMesh
	if plane:
		var split_plane := plane.duplicate() as PlaneMesh
		split_plane.subdivide_width = clampi(int(plane.size.x / warp_segment), 0, 64)
		split_plane.subdivide_depth = clampi(int(plane.size.y / warp_segment), 0, 64)
		mesh_instance.mesh = split_plane
		_split[original] = split_plane
