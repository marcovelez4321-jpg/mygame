class_name Camp
extends Node3D

## A camp (the user's, 2026-10-16): placed whole from a camp kit (CampBuilder)
## -- a tent (the forest props' Large Tent 1 or 2, at random), the bedroll
## beside it (the survival pack's sleeping bag: F to sleep, Bedroll), and a
## fire in front (the forest props' Fire, its crane and pot; flames, a warm
## light, and meat cooks on it: FireSource). Die and you wake at the camp
## nearest where you fell (PlayerMovement), your gear left behind in a
## backpack (DeathPack). As many as you like.
## Rule 1 (co-op): the host's; clients see it through NetEntities
## (net_spawn_args: which tent). Cheap: no shadows from its light; the
## flames are the barrels' shared particle looks.

const FOREST := "res://art/PSX Forest Props.fbx"
const SURVIVAL := "res://art/Survival/Models/Survival.fbx"
const TENTS := ["Large Tent 1", "Large Tent 2"]
## Where everything sits (local: the tent faces +Z).
const TENT_LENGTH := 3.2
const FIRE_AT := Vector3(0.0, 0.0, 4.0)
const FIRE_SIZE := 1.4
const BED_AT := Vector3(2.4, 0.0, 1.6)
const BED_LENGTH := 2.0
## Where you wake (in front of the tent's door).
const WAKE_AT := Vector3(-1.2, 1.0, 2.6)
const GROUP := "camps"

var tent := 0

static var _forest_scene: PackedScene
static var _survival_scene: PackedScene


## A camp at `place` (the host's).
static func build(world: Node, place: Transform3D, tent_variant: int) -> Camp:
	var camp := Camp.new()
	camp.tent = tent_variant
	world.add_child(camp)
	camp.global_transform = place
	return camp


## The camp nearest `at`, or null.
static func nearest(tree: SceneTree, at: Vector3) -> Camp:
	var best: Camp = null
	var best_distance := INF
	for node in tree.get_nodes_in_group(GROUP):
		var camp := node as Camp
		if camp and camp.is_inside_tree():
			var distance := camp.global_position.distance_squared_to(at)
			if distance < best_distance:
				best_distance = distance
				best = camp
	return best


func wake_point() -> Vector3:
	return global_transform * WAKE_AT


func net_spawn_args() -> Dictionary:
	return {tent = tent}


func net_restore(data: Dictionary) -> void:
	tent = data.get("tent", 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(NetEntities.GROUP)
	add_child(make_look(tent))
	# Something solid round the tent.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TENT_LENGTH * 0.75, 1.8, TENT_LENGTH)
	shape.shape = box
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	add_child(body)
	# The fire: cooks (FireSource), burns (the barrels' flames), glows.
	var fire := FireSource.new()
	fire.radius = 0.5
	fire.height = 1.2
	fire.position = FIRE_AT
	add_child(fire)
	for look: Array in [BurningBarrel._flames(), BurningBarrel._sparks()]:
		var particles := GPUParticles3D.new()
		particles.process_material = look[0]
		particles.draw_pass_1 = look[1]
		particles.amount = 16
		particles.lifetime = 0.7
		particles.scale = Vector3.ONE * 0.6
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.visibility_range_end = 120.0
		particles.position = FIRE_AT + Vector3.UP * 0.2
		add_child(particles)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 1.8
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.position = FIRE_AT + Vector3.UP * 0.8
	add_child(light)
	# The bedroll: F to sleep.
	var bed := Bedroll.new()
	bed.position = BED_AT
	add_child(bed)


## The camp's look (also the placing ghost's): tent, bedroll, fire, crane, pot.
static func make_look(tent_variant: int) -> Node3D:
	var root := Node3D.new()
	if _forest_scene == null and ResourceLoader.exists(FOREST):
		_forest_scene = load(FOREST) as PackedScene
	if _survival_scene == null and ResourceLoader.exists(SURVIVAL):
		_survival_scene = load(SURVIVAL) as PackedScene
	_part(root, _forest_scene, TENTS[tent_variant % TENTS.size()], Vector3.ZERO, TENT_LENGTH, null)
	_part(root, _forest_scene, "Fire", FIRE_AT, FIRE_SIZE, null)
	_part(root, _forest_scene, "Campfire crane", FIRE_AT, FIRE_SIZE * 1.3, null)
	_part(root, _forest_scene, "Pot", FIRE_AT + Vector3.UP * 0.7, 0.35, null)
	_part(root, _survival_scene, "sleeping_bag", BED_AT, BED_LENGTH, _bed_material())
	return root


## One named part of a model pack, sized (its longest side `size`), its feet
## on the ground at `at`. `look`: its material (null: the forest props' own).
static func _part(root: Node3D, pack: PackedScene, name: String, at: Vector3, size: float, look: Material) -> void:
	if pack == null:
		return
	var whole := pack.instantiate() as Node3D
	var part := whole.find_child(name, true, false) as Node3D
	if part == null:
		whole.free()
		return
	# Its own turn kept (the packs are stored turned), its place dropped.
	var turned := Node3D.new()
	turned.basis = part.basis
	var meshes: Array[Node] = part.find_children("*", "MeshInstance3D", true, false)
	meshes.push_front(part)
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or _is_card(mesh):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mesh.mesh
		if look:
			copy.material_override = look
		else:
			BackpackView.textured(copy, mesh)
		var place := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk and walk != part:
			place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		copy.transform = place
		copy.visibility_range_end = 400.0
		turned.add_child(copy)
	whole.free()
	var holder := Node3D.new()
	holder.add_child(turned)
	var box := BackpackView._bounds(holder)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := size / maxf(longest, 0.0001)
	holder.scale = Vector3.ONE * fit
	holder.position = at - Vector3(box.get_center().x, box.position.y, box.get_center().z) * fit
	root.add_child(holder)


## A flat picture card (the Fire's crossed flame planes -- they showed as
## pictures in a plus over it): left out, the camp's own flames burn there.
static func _is_card(mesh: MeshInstance3D) -> bool:
	if String(mesh.name).to_lower().contains("flame"):
		return true
	var size := mesh.get_aabb().size
	return minf(size.x, minf(size.y, size.z)) < maxf(size.x, maxf(size.y, size.z)) * 0.02


static var _bed_look: StandardMaterial3D


static func _bed_material() -> StandardMaterial3D:
	if _bed_look == null:
		_bed_look = StandardMaterial3D.new()
		var texture := "res://art/Survival/Textures/sleeping_bag.png"
		_bed_look.albedo_texture = load(texture) as Texture2D if ResourceLoader.exists(texture) else null
		_bed_look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_bed_look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_bed_look.roughness = 1.0
	return _bed_look