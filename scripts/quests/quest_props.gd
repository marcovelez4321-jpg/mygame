class_name QuestProps
extends RefCounted

## The quests' things, made from shapes (and a few of the PSX packs' props):
## what you carry (Backpack.QUEST_KINDS) and what stands in the world for them
## -- the cult's flesh-root altar and its camps' totems, the summit cairn, the
## Fanatic's sled, a cold fire. Every one a fresh copy, its feet (or middle,
## for a carried thing) at its origin. Shared materials (warmed up by
## ShaderWarmup).

const MEGA := BackpackView.MEGA
const GAS_MODEL := MEGA + "Small Props/jerrycan_1.glb"
const PIPE_MODEL := MEGA + "Large Props/pipe_1_short.glb"
const TIN_MODEL := MEGA + "Small Props/tin_can_mp_1_rusty.glb"
const BONE := Color(0.82, 0.77, 0.64)
const STONE := Color(0.32, 0.3, 0.3)
const ROOT := Color(0.45, 0.07, 0.08)
const TWINE := Color(0.3, 0.22, 0.14)
const TOOTH := Color(0.92, 0.88, 0.76)
const STEEL := Color(0.55, 0.56, 0.58)
const COPPER := Color(0.62, 0.35, 0.18)
const WAX := Color(0.5, 0.08, 0.06)
const WOOD := Color(0.3, 0.21, 0.14)
const RUBBLE := Color(0.42, 0.41, 0.39)

static var _materials := {}


## A carried quest thing's model (Backpack.QUEST_KINDS).
static func item_model(kind: int) -> Node3D:
	match kind:
		Backpack.Kind.SKULL:
			return skull(0.22)
		Backpack.Kind.OFFERING:
			return offering()
		Backpack.Kind.TAGS:
			return tags()
		Backpack.Kind.BLACK_BLOOD:
			return jar()
		Backpack.Kind.BOMB_GAS:
			return _prop(GAS_MODEL, 0.3)
		Backpack.Kind.BOMB_PIPE:
			return pipe()
		Backpack.Kind.BOMB_WIRE:
			return wire_coil()
	return null


static func material(color: Color, glow: float = 0.0, see_through: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), glow, see_through]
	if _materials.has(key):
		return _materials[key]
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(color, see_through)
	look.roughness = 0.85
	if see_through < 1.0:
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		look.emission_enabled = true
		look.emission = color
		look.emission_energy_multiplier = glow
	_materials[key] = look
	return look


## Every material these use (ShaderWarmup).
static func materials() -> Array[Material]:
	var all: Array[Material] = []
	for color: Color in [BONE, STONE, ROOT, TWINE, TOOTH, STEEL, COPPER, WAX, WOOD, RUBBLE, Color(0.02, 0.01, 0.01)]:
		all.append(material(color))
	all.append(material(Color(0.8, 0.85, 0.9), 0.0, 0.35))
	all.append(material(Color(1.0, 0.25, 0.1), 3.0))
	return all


# ---- Carried things ----------------------------------------------------------------------

## A human skull, `size` long: the cranium, the jaw, dark sockets and nose.
static func skull(size: float) -> Node3D:
	var root := Node3D.new()
	var s := size / 0.22
	_ball(root, Vector3(0.075, 0.07, 0.09) * s, Vector3(0.0, 0.03, 0.0) * s, BONE)
	_ball(root, Vector3(0.06, 0.045, 0.06) * s, Vector3(0.0, -0.02, -0.04) * s, BONE)
	_box(root, Vector3(0.09, 0.03, 0.07) * s, Vector3(0.0, -0.06, -0.05) * s, BONE)
	for side: float in [-1.0, 1.0]:
		_ball(root, Vector3(0.022, 0.02, 0.012) * s, Vector3(side * 0.03, 0.0, -0.085) * s, Color(0.02, 0.01, 0.01))
	_box(root, Vector3(0.016, 0.022, 0.01) * s, Vector3(0.0, -0.03, -0.092) * s, Color(0.02, 0.01, 0.01))
	return root


## The offering (the user's: a bound bundle of meat and teeth): a raw chunk,
## twine bound round it, teeth pushed into it.
static func offering() -> Node3D:
	var root := Node3D.new()
	var meat := CarryItem.meat_model(false, false)
	if meat:
		var bounds := BackpackView._bounds(meat)
		var fit := 0.22 / maxf(bounds.get_longest_axis_size(), 0.001)
		meat.scale = Vector3.ONE * fit
		meat.position = -bounds.get_center() * fit
		root.add_child(meat)
	else:
		_ball(root, Vector3(0.11, 0.08, 0.09), Vector3.ZERO, ROOT)
	for turn: float in [0.0, PI * 0.5]:
		var band := _ring(root, 0.105, 0.008, TWINE)
		band.rotation = Vector3(PI * 0.5, turn, 0.0)
	var dice := RandomNumberGenerator.new()
	dice.seed = 31
	for i in 7:
		var tooth := _box(root, Vector3(0.012, 0.03, 0.012), Vector3.ZERO, TOOTH)
		var out := Vector3(dice.randf_range(-1, 1), dice.randf_range(0.2, 1), dice.randf_range(-1, 1)).normalized()
		tooth.position = out * 0.085
		tooth.basis = Basis(Quaternion(Vector3.UP, out))
	return root


## His tags: two dog tags on a ball chain.
static func tags() -> Node3D:
	var root := Node3D.new()
	for i in 2:
		var tag := _box(root, Vector3(0.05, 0.028, 0.003), Vector3(0.004 * i, -0.012 * i, 0.003 * i), STEEL)
		tag.rotation.z = 0.25 * i
	var chain := _ring(root, 0.035, 0.0025, STEEL)
	chain.position = Vector3(-0.02, 0.03, 0.0)
	chain.rotation.x = PI * 0.5
	return root


## A small glass jar of thick black blood, wax-sealed, string round its neck.
static func jar() -> Node3D:
	var root := Node3D.new()
	_cylinder(root, 0.04, 0.09, Vector3.ZERO, Color(0.8, 0.85, 0.9), 0.35)
	_cylinder(root, 0.034, 0.075, Vector3(0.0, -0.006, 0.0), Color(0.02, 0.01, 0.01))
	_cylinder(root, 0.042, 0.018, Vector3(0.0, 0.052, 0.0), WAX)
	var string := _ring(root, 0.041, 0.003, TWINE)
	string.position = Vector3(0.0, 0.038, 0.0)
	return root


## A short length of pipe (the Fanatic's).
static func pipe() -> Node3D:
	var model := _prop(PIPE_MODEL, 0.3)
	if model:
		return model
	var root := Node3D.new()
	var tube := _cylinder(root, 0.03, 0.3, Vector3.ZERO, STEEL)
	tube.rotation.z = PI * 0.5
	return root


## A coil of copper wire.
static func wire_coil() -> Node3D:
	var root := Node3D.new()
	for i in 4:
		var loop := _ring(root, 0.06 - 0.004 * i, 0.006, COPPER)
		loop.position.y = i * 0.012
		loop.rotation.z = 0.08 * (i % 2)
	return root


# ---- In the world ------------------------------------------------------------------------

## The cult's flesh-root altar (the user's): a stone slab overgrown with the
## Flesh Tree's red roots, bones pushed into it, a ring of skulls round it.
## `size` 1: the shrine's (about 3 m across); smaller for a camp's totem.
static func altar(size: float, seed_value: int) -> Node3D:
	var root := Node3D.new()
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	_box(root, Vector3(2.4, 1.0, 1.3) * size, Vector3(0.0, 0.5, 0.0) * size, STONE)
	_box(root, Vector3(2.7, 0.15, 1.6) * size, Vector3(0.0, 1.05, 0.0) * size, STONE)
	# The roots: out of the ground, over the slab, back into the ground.
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var along := dice.randf_range(-1.1, 1.1)
		var points := PackedVector3Array([
			Vector3(along + dice.randf_range(-0.3, 0.3), -0.2, side * 1.6),
			Vector3(along, 0.8, side * 0.85),
			Vector3(along + dice.randf_range(-0.2, 0.2), 1.25, side * 0.2),
			Vector3(along + dice.randf_range(-0.4, 0.4), 1.2, -side * 0.5),
			Vector3(along + dice.randf_range(-0.3, 0.3), 0.6, -side * 0.9),
			Vector3(along + dice.randf_range(-0.5, 0.5), -0.2, -side * 1.7)])
		for j in points.size():
			points[j] *= size
		_tube(root, points, 0.11 * size, ROOT)
	# Bones pushed in.
	for i in 5:
		var bone := _cylinder(root, 0.035 * size, dice.randf_range(0.5, 0.8) * size, Vector3.ZERO, BONE)
		bone.position = Vector3(dice.randf_range(-1.0, 1.0), 1.3, dice.randf_range(-0.5, 0.5)) * size
		bone.rotation = Vector3(dice.randf_range(-0.6, 0.6), 0.0, dice.randf_range(-0.6, 0.6))
	# The ring of skulls.
	var count := 10
	for i in count:
		var a := TAU * i / count
		var head := skull(0.24 * maxf(size, 0.6))
		root.add_child(head)
		head.position = Vector3(cos(a) * 2.2, 0.08, sin(a) * 1.7) * size
		head.rotation.y = -a - PI * 0.5 + dice.randf_range(-0.4, 0.4)
	return root


## The summit cairn (the user's: F there with his tags lays them on it): a
## knee-high pile of rubble and broken concrete.
static func cairn() -> Node3D:
	var root := Node3D.new()
	var dice := RandomNumberGenerator.new()
	dice.seed = 5
	var y := 0.0
	for layer in 4:
		var stones := 5 - layer
		var size := 0.45 - layer * 0.08
		for i in stones:
			var a := TAU * i / stones + layer * 0.7
			var reach := (0.35 - layer * 0.08) if stones > 1 else 0.0
			var stone := _box(root, Vector3(size, size * 0.6, size * 0.8), Vector3(cos(a) * reach, y + size * 0.3, sin(a) * reach), RUBBLE)
			stone.rotation.y = dice.randf() * TAU
		y += size * 0.55
	return root


## His tags hung on the cairn's top (a bit of rebar stuck in it).
static func tags_on_cairn() -> Node3D:
	var root := Node3D.new()
	_cylinder(root, 0.012, 0.5, Vector3(0.0, 1.1, 0.0), Color(0.35, 0.2, 0.12))
	var hung := tags()
	hung.position = Vector3(0.03, 1.25, 0.0)
	hung.scale = Vector3.ONE * 2.0
	root.add_child(hung)
	return root


## The Fanatic's sled (the user's: a junk pile on a sled he drags) -- bigger
## the higher he's got (`grown` 0..1): planks on runners, the pile of cans,
## pipes and wire lashed onto it.
static func sled(grown: float) -> Node3D:
	var root := Node3D.new()
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(0.08, 0.1, 2.2), Vector3(side * 0.55, 0.05, 0.0), WOOD)
		var tip := _box(root, Vector3(0.08, 0.08, 0.4), Vector3(side * 0.55, 0.14, -1.18), WOOD)
		tip.rotation.x = -0.6
	for z: float in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		_box(root, Vector3(1.3, 0.05, 0.3), Vector3(0.0, 0.13, z), WOOD)
	var dice := RandomNumberGenerator.new()
	dice.seed = 99
	var pieces := 4 + int(grown * 14.0)
	for i in pieces:
		var up := 0.3 + float(i) / pieces * (0.4 + grown * 1.2)
		var at := Vector3(dice.randf_range(-0.45, 0.45), up, dice.randf_range(-0.8, 0.8)) * Vector3(1.0, 1.0, 1.0 - float(i) / pieces * 0.5)
		var piece: Node3D
		match i % 3:
			0:
				piece = _prop(GAS_MODEL, 0.45)
			1:
				piece = pipe()
				piece.scale = Vector3.ONE * 2.2
			_:
				piece = _prop(TIN_MODEL, 0.25)
		if piece == null:
			continue
		root.add_child(piece)
		piece.position = at
		piece.rotation = Vector3(dice.randf_range(-0.4, 0.4), dice.randf() * TAU, dice.randf_range(-0.4, 0.4))
	# The wire lashing it all down.
	for z: float in [-0.5, 0.0, 0.5]:
		var lash := _ring(root, 0.65, 0.01, COPPER)
		lash.position = Vector3(0.0, 0.5 + grown * 0.5, z)
		lash.scale = Vector3(1.0, 1.0 + grown, 1.0)
		lash.rotation.x = PI * 0.5
	return root


## A cold fire's logs and ash (the bounty man's is lit: lit_fire()).
static func fire_logs() -> Node3D:
	var root := Node3D.new()
	for i in 5:
		var a := TAU * i / 5.0
		var stick := _cylinder(root, 0.06, 0.8, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2), WOOD)
		stick.rotation = Vector3(0.0, -a, PI * 0.5 - 0.35)
	_cylinder(root, 0.45, 0.04, Vector3(0.0, 0.02, 0.0), Color(0.12, 0.11, 0.1))
	return root


## A lit campfire: logs, flames, sparks, a warm light; meat cooks on it.
static func lit_fire() -> Node3D:
	var root := fire_logs()
	var fire := FireSource.new()
	fire.radius = 0.5
	fire.height = 1.2
	root.add_child(fire)
	for look: Array in [BurningBarrel._flames(), BurningBarrel._sparks()]:
		var particles := GPUParticles3D.new()
		particles.process_material = look[0]
		particles.draw_pass_1 = look[1]
		particles.amount = 16
		particles.lifetime = 0.7
		particles.scale = Vector3.ONE * 0.6
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.visibility_range_end = 150.0
		particles.position = Vector3.UP * 0.2
		root.add_child(particles)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 1.8
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 20.0
	light.position = Vector3.UP * 0.8
	root.add_child(light)
	return root


## A human model from the Characters PSX set, sized `height` m, its feet at
## its origin, facing -Z; with its AnimationPlayer (PlayerModel.animator_for).
static func human(path: String, height: float = 1.8) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var bounds := BackpackView._bounds(model)
	model.scale = Vector3.ONE * height / maxf(bounds.size.y, 0.01)
	model.rotation.y = PI # (they face +Z)
	return model


# ---- Shapes --------------------------------------------------------------------------------

static func _prop(path: String, size: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var bounds := BackpackView._bounds(model)
	var fit := size / maxf(bounds.get_longest_axis_size(), 0.001)
	var holder := Node3D.new()
	holder.add_child(model)
	model.scale = Vector3.ONE * fit
	model.position = -bounds.get_center() * fit
	return holder


static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(root, mesh, at, color)


static func _ball(root: Node3D, radii: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var made := _add(root, mesh, at, color)
	made.scale = radii
	return made


static func _cylinder(root: Node3D, radius: float, height: float, at: Vector3, color: Color, see_through: float = 1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var made := _add(root, mesh, at, color)
	if see_through < 1.0:
		made.material_override = material(color, 0.0, see_through)
	return made


static func _ring(root: Node3D, radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 16
	mesh.ring_segments = 4
	return _add(root, mesh, Vector3.ZERO, color)


## A bent tube through `points` (a root): a cylinder per stretch.
static func _tube(root: Node3D, points: PackedVector3Array, radius: float, color: Color) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var piece := _cylinder(root, radius * lerpf(1.0, 0.6, float(i) / points.size()), a.distance_to(b) + radius, (a + b) * 0.5, color)
		var dir := (b - a).normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			piece.basis = Basis(Quaternion(Vector3.UP, dir))


static func _add(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var made := MeshInstance3D.new()
	made.mesh = mesh
	made.material_override = material(color)
	made.position = at
	root.add_child(made)
	return made
