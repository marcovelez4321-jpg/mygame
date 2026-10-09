class_name PS1Look

## Puts things through shaders/ps1.gdshader: screen-space vertex snapping
## (the PS1 wobble), per-vertex (Gouraud) lighting and nearest-filtered
## textures. Cheaper than the standard material, not dearer: lighting is
## worked out per vertex instead of per pixel.
##
## Every enemy goes through it as it spawns (watch_enemies(), hooked up by
## the GameSettings autoload); the first-person arms and the grapple's
## symbiote use material() directly.
##
## A standard material is swapped for a PS1 one with the same texture and
## colour. Left alone: see-through, glowing, unshaded or vertex-coloured
## materials (the shader has none of those) and custom shaders. Swapped
## materials are cached, so every copy of an enemy still shares one.

const SHADER_PATH := "res://shaders/ps1.gdshader"
## Every enemy class (and everything extending one).
const ENEMY_CLASSES: Array[StringName] = [&"Enemy", &"Harvestman", &"BurrowWorm", &"Deepmaw",
		&"DeepmawCrawler", &"FlyingRoach", &"Rat", &"Leech", &"Barnacle", &"Spider", &"SwarmKing"]

## Opaque and two-sided variants of the shader, made once.
static var _shaders := {}
## Original material -> its PS1 version.
static var _converted := {}


## A PS1 material. Opaque: the shader file writes ALPHA, which would sort a
## mesh as see-through (no depth writes), so that line's taken out here.
static func material(texture: Texture2D, color: Color, two_sided: bool) -> ShaderMaterial:
	var key := 1 if two_sided else 0
	if not _shaders.has(key):
		var code := (load(SHADER_PATH) as Shader).code
		code = code.replace("ALPHA = tex_color.a * albedo_color.a;", "")
		if two_sided:
			code = code.replace("render_mode ", "render_mode cull_disabled, ")
		var shader := Shader.new()
		shader.code = code
		_shaders[key] = shader
	var result := ShaderMaterial.new()
	result.shader = _shaders[key]
	if texture:
		result.set_shader_parameter("albedo_texture", texture)
	result.set_shader_parameter("albedo_color", color)
	return result


## Swaps every suitable material under `root` (itself included).
static func apply(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var nodes := root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		nodes.append(root)
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if geometry.material_override:
			geometry.material_override = _convert(geometry.material_override)
		var mesh_instance := geometry as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			for surface in mesh_instance.mesh.get_surface_count():
				var current := mesh_instance.get_active_material(surface)
				var swapped := _convert(current)
				if swapped != current:
					mesh_instance.set_surface_override_material(surface, swapped)


## Hooks every enemy that enters the game from now on (called once).
static func watch_enemies(tree: SceneTree) -> void:
	tree.node_added.connect(func(node: Node) -> void:
		if _is_enemy(node):
			# After its _ready, when it has built its model.
			apply.call_deferred(node)
	)


## By class name (its script or any script it extends), so this file doesn't
## load every enemy script with the GameSettings autoload.
static func _is_enemy(node: Node) -> bool:
	var script := node.get_script() as Script
	while script:
		if ENEMY_CLASSES.has(script.get_global_name()):
			return true
		script = script.get_base_script()
	return false


static func _convert(original: Material) -> Material:
	if original == null:
		return original
	if _converted.has(original):
		return _converted[original]
	var base := original as BaseMaterial3D
	var swapped: Material = original
	if base and base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and base.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			and not base.emission_enabled and not base.vertex_color_use_as_albedo:
		swapped = material(base.albedo_texture, base.albedo_color, base.cull_mode == BaseMaterial3D.CULL_DISABLED)
	_converted[original] = swapped
	return swapped
