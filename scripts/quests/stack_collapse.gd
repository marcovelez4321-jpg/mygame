class_name StackCollapse
extends RefCounted

## The 1.4 km tower's top blown off (the user's, 2026-10-27: the Fanatic's
## bomb -- "blast, then gone": a huge fireball, then the top's simply missing,
## a smoking stump; the top 400 m, cut at CUT_AT). For good (the world fact
## stack.top_gone), on every game:
##   its look -- the shell's skyline materials cut it away (skyline.gdshader:
##   cut_min / cut_max), anything wholly inside hidden;
##   its collision -- every shape whose middle is in it switched off;
##   live (the moment it goes) -- the blast at its top, seen from anywhere;
##   and the stump smoking from then on.

const TOWER := 4 # (StackBuilder.TOWERS: the 1.4 km tower)
const CUT_AT := 1000.0
const REACH := 85.0
const BLASTS := 6
const SMOKE_COLOR := Color(0.16, 0.15, 0.14, 0.7)

static var _done_for := 0


## The cut, in the world.
static func cut_box(stack: Megastructure) -> AABB:
	var tower: Array = StackBuilder.TOWERS[TOWER]
	var local := AABB(Vector3(float(tower[0]) - REACH, CUT_AT, float(tower[1]) - REACH), Vector3(REACH * 2.0, 2500.0, REACH * 2.0))
	return stack.global_transform * local


static func apply(tree: SceneTree, live: bool) -> void:
	var stack := tree.current_scene.get_node_or_null(^"TheStack") as Megastructure if tree.current_scene else null
	if stack == null or _done_for == stack.get_instance_id():
		return
	_done_for = stack.get_instance_id()
	var cut := cut_box(stack)
	for node in stack.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		if not cut.intersects(bounds):
			continue
		if cut.encloses(bounds):
			mesh.visible = false
			continue
		for material in _materials_of(mesh):
			if material is ShaderMaterial and (material as ShaderMaterial).shader == Megastructure.SKYLINE:
				(material as ShaderMaterial).set_shader_parameter(&"cut_min", cut.position)
				(material as ShaderMaterial).set_shader_parameter(&"cut_max", cut.end)
	for node in stack.find_children("*", "OccluderInstance3D", true, false):
		if cut.has_point((node as Node3D).global_position):
			(node as Node3D).visible = false
	for node in stack.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.shape == null:
			continue
		var middle := shape.global_transform * shape.shape.get_debug_mesh().get_aabb().get_center()
		if cut.has_point(middle):
			shape.set_deferred(&"disabled", true)
	var stump := Vector3(cut.get_center().x, cut.position.y, cut.get_center().z)
	if live:
		for i in BLASTS:
			var at := stump + Vector3(randf_range(-REACH, REACH) * 0.6, randf_range(0.0, 400.0), randf_range(-REACH, REACH) * 0.6)
			tree.create_timer(i * 0.35).timeout.connect(func() -> void:
				if tree.current_scene:
					Explosion.play_visuals(tree.current_scene, at, 90.0))
	tree.current_scene.add_child(_smoke(stump))


static func _materials_of(mesh: MeshInstance3D) -> Array[Material]:
	var found: Array[Material] = []
	if mesh.material_override:
		found.append(mesh.material_override)
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_surface_override_material(i)
		if material == null:
			material = mesh.mesh.surface_get_material(i)
		if material and not found.has(material):
			found.append(material)
	return found


## The stump's smoke, rising for good.
static func _smoke(at: Vector3) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 40.0
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = 6.0
	process.initial_velocity_max = 12.0
	process.gravity = Vector3(1.5, 1.0, 0.0)
	process.scale_min = 1.0
	process.scale_max = 2.0
	var fade := Gradient.new()
	fade.set_color(0, SMOKE_COLOR)
	fade.set_color(1, Color(SMOKE_COLOR, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	smoke.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 45.0
	var look := StandardMaterial3D.new()
	look.albedo_texture = Explosion._puff_texture()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	quad.material = look
	smoke.draw_pass_1 = quad
	smoke.amount = 40
	smoke.lifetime = 30.0
	smoke.preprocess = 30.0
	smoke.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 600, 400))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = at
	return smoke
