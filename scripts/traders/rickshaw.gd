class_name Rickshaw
extends Node3D

## The trader's shop (the user's, 2026-10-25): a Japanese jinrikisha he pulls
## himself, oversized -- about 3 m long, 2.5 m tall -- in worn dark red
## lacquer, two big spoked wood wheels, a small wooden roof with curved
## eaves, his counter where the seat was (a hanging scale, a small oil lamp,
## a bell), a deep red cloth banner with an eye painted on it, paper lanterns
## and the growth's glow both, and overgrown with the world's coral (on the
## wheels and frame, glowing tips), glow moss, and kelp trailing with glowing
## bulbs. Its goods are always on show (slots): guns and grenades on hooks,
## ammo, food and camp kits on fold-down side shelves, small things hanging
## from the eaves. Made from shapes; it faces -Z (the shafts he pulls by),
## its origin on the ground under the axle.

const WHEEL_RADIUS := 0.75
const TRACK := 0.85
const LACQUER := Color(0.33, 0.06, 0.05)
const WORN := Color(0.44, 0.4, 0.35)
const WOOD := Color(0.3, 0.21, 0.14)
const PAPER := Color(0.93, 0.86, 0.7)
const BRASS := Color(0.62, 0.48, 0.2)
const LANTERN_GLOW := Color(1.0, 0.62, 0.3)
const CORAL := Color(0.75, 0.62, 0.68)
const CORAL_TIPS := [Color(1.0, 0.35, 0.75), Color(0.3, 0.9, 1.0)]
const MOSS := Color(0.22, 0.8, 0.72)
const KELP := Color(0.12, 0.22, 0.14)
const BULB := Color(0.55, 1.0, 0.7)
const BANNER_RED := Color(0.42, 0.03, 0.04)
## Where he stands to pull it, between the shafts (local).
const PULL_POINT := Vector3(0.0, 0.0, -1.3)

## Display spots: [{show: &"hook"/&"shelf"/&"eave", xf: Transform3D}], local.
var slots: Array[Dictionary] = []
var _wheels: Array[Node3D] = []
var _seed := 0
var _banner_mesh: MeshInstance3D
var _lanterns: Array[MeshInstance3D] = []
var _light: OmniLight3D

static var _materials := {}
static var _banner_texture: ImageTexture


func _init(look_seed: int = 1) -> void:
	_seed = look_seed
	name = "Rickshaw"
	_build()


## Wrecked where he died (the user's: tipped on its side, a wheel off, the
## banner in the dirt, the lanterns out -- the growth still glows). `ground`:
## the node it lies under (the wheel and the banner go there).
func wreck(ground: Node3D) -> void:
	rotation.z = deg_to_rad(-78.0)
	position.y = 0.72
	if _wheels.size() > 0:
		var wheel := _wheels[0]
		_wheels.remove_at(0)
		remove_child(wheel)
		ground.add_child(wheel)
		wheel.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.6), Vector3(-1.3, 0.06, 1.5))
	if _banner_mesh:
		remove_child(_banner_mesh)
		ground.add_child(_banner_mesh)
		_banner_mesh.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, 0.3), Vector3(0.6, 0.02, -2.0))
	for lantern in _lanterns:
		lantern.material_override = _material(PAPER.darkened(0.35))
	if _light:
		_light.visible = false


## Rolled `distance` m forward: the wheels turn with it.
func roll(distance: float) -> void:
	for wheel in _wheels:
		wheel.rotation.x -= distance / WHEEL_RADIUS


func _build() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = _seed
	# The wheels and the axle.
	for side: float in [-1.0, 1.0]:
		var wheel := Node3D.new()
		wheel.position = Vector3(side * TRACK, WHEEL_RADIUS, 0.15)
		add_child(wheel)
		_wheels.append(wheel)
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = WHEEL_RADIUS - 0.07
		torus.outer_radius = WHEEL_RADIUS
		torus.rings = 24
		torus.ring_segments = 6
		rim.mesh = torus
		rim.material_override = _material(WOOD)
		rim.rotation = Vector3(0.0, 0.0, PI * 0.5)
		wheel.add_child(rim)
		for i in 12:
			var angle := TAU * i / 12.0
			_box(Vector3(0.035, WHEEL_RADIUS - 0.1, 0.035), Vector3(0.0, cos(angle), sin(angle)) * (WHEEL_RADIUS * 0.5),
					WORN if i % 5 == 0 else WOOD, Vector3(angle, 0.0, 0.0), 0.0, wheel)
		_cylinder(0.09, 0.18, Vector3.ZERO, BRASS, Vector3(0.0, 0.0, PI * 0.5), 0.0, wheel)
		# Coral grown through the spokes (it turns with them).
		for c in 2:
			var angle := dice.randf() * TAU
			_coral(wheel, Vector3(side * 0.02, cos(angle), sin(angle)) * (WHEEL_RADIUS - 0.05), dice, 0.6)
	_cylinder(0.04, TRACK * 2.0, Vector3(0.0, WHEEL_RADIUS, 0.15), WORN, Vector3(0.0, 0.0, PI * 0.5))
	# The tub, the footboard, the back and sides.
	_box(Vector3(1.3, 0.45, 1.0), Vector3(0.0, 0.95, 0.35), LACQUER)
	_box(Vector3(1.32, 0.04, 1.02), Vector3(0.0, 1.19, 0.35), WORN) # (its rim, worn through)
	_box(Vector3(1.0, 0.05, 0.5), Vector3(0.0, 0.55, -0.4), WOOD)
	_box(Vector3(0.05, 0.4, 0.05), Vector3(-0.45, 0.75, -0.2), WOOD)
	_box(Vector3(0.05, 0.4, 0.05), Vector3(0.45, 0.75, -0.2), WOOD)
	_box(Vector3(1.3, 1.25, 0.06), Vector3(0.0, 1.6, 0.86), LACQUER)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.9, 1.0), Vector3(side * 0.66, 1.65, 0.35), LACQUER)
	# His counter where the seat was: the hanging scale, the oil lamp, the bell.
	_box(Vector3(1.3, 0.06, 0.45), Vector3(0.0, 1.22, 0.15), WOOD)
	_scale(Vector3(0.38, 1.25, 0.15))
	_cylinder(0.05, 0.05, Vector3(-0.42, 1.28, 0.2), BRASS)
	_lanterns.append(_cylinder(0.035, 0.1, Vector3(-0.42, 1.36, 0.2), LANTERN_GLOW, Vector3.ZERO, 3.0))
	_cylinder(0.05, 0.08, Vector3(0.02, 1.3, 0.25), BRASS)
	_sphere(0.05, Vector3(0.02, 1.34, 0.25), BRASS)
	# The roof: front posts, a gable with its ridge across, curved eaves.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.06, 1.0, 0.06), Vector3(side * 0.62, 1.71, -0.15), WOOD)
	_box(Vector3(1.75, 0.05, 0.8), Vector3(0.0, 2.33, 0.02), WOOD, Vector3(0.38, 0.0, 0.0))
	_box(Vector3(1.75, 0.05, 0.8), Vector3(0.0, 2.33, 0.7), WOOD, Vector3(-0.38, 0.0, 0.0))
	_box(Vector3(1.85, 0.07, 0.07), Vector3(0.0, 2.48, 0.36), WORN)
	for side: float in [-1.0, 1.0]:
		for end: float in [-0.36, 1.08]:
			_box(Vector3(0.3, 0.04, 0.22), Vector3(side * 0.95, 2.2, end), WOOD, Vector3(0.0, 0.0, side * 0.45))
	# The shafts he pulls by, and the bar across their ends.
	for side: float in [-1.0, 1.0]:
		_pole(Vector3(side * 0.6, 0.95, -0.1), Vector3(side * 0.32, 0.88, -1.6), 0.035, LACQUER)
	_cylinder(0.03, 0.7, Vector3(0.0, 0.88, -1.58), WORN, Vector3(0.0, 0.0, PI * 0.5))
	# The banner, the eye on it, hung from the front of the roof.
	var banner := MeshInstance3D.new()
	var cloth := QuadMesh.new()
	cloth.size = Vector2(1.05, 0.62)
	banner.mesh = cloth
	var look := StandardMaterial3D.new()
	look.albedo_texture = _banner()
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.roughness = 1.0
	banner.material_override = look
	banner.position = Vector3(0.0, 1.88, -0.37)
	banner.rotation = Vector3(0.0, PI, 0.0)
	add_child(banner)
	_banner_mesh = banner
	# Paper lanterns at the front corners, and their warm light.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.01, 0.15, 0.01), Vector3(side * 0.86, 2.08, -0.38), WORN)
		_lanterns.append(_cylinder(0.12, 0.3, Vector3(side * 0.86, 1.86, -0.38), PAPER.lerp(LANTERN_GLOW, 0.4), Vector3.ZERO, 2.2))
	var light := OmniLight3D.new()
	_light = light
	light.light_color = LANTERN_GLOW
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.95, -0.45)
	add_child(light)
	# The growth: coral on the frame, glow moss, kelp hung with bulbs.
	for at: Vector3 in [Vector3(-0.62, 0.75, -0.12), Vector3(0.6, 0.78, 0.82), Vector3(-0.5, 2.42, 0.36), Vector3(0.7, 2.25, 0.9),
			Vector3(0.45, 0.92, -0.6), Vector3(-0.3, 1.2, 0.84)]:
		_coral(self, at, dice, 1.0)
	for i in 7:
		var on_roof := i < 4
		var at := Vector3(dice.randf_range(-0.7, 0.7), 2.37, dice.randf_range(0.0, 0.7)) if on_roof \
				else Vector3(dice.randf_range(-0.5, 0.5), 0.58, dice.randf_range(-0.6, -0.2))
		_box(Vector3(dice.randf_range(0.15, 0.35), 0.03, dice.randf_range(0.12, 0.3)), at, MOSS, Vector3(0.0, dice.randf() * TAU, 0.0), 0.8)
	for i in 5:
		var at := Vector3(dice.randf_range(-0.85, 0.85), 2.16, 1.08 if i % 2 == 0 else -0.36)
		var length := dice.randf_range(0.6, 1.1)
		_box(Vector3(0.05, length, 0.01), at + Vector3.DOWN * length * 0.5, KELP, Vector3(0.0, dice.randf() * TAU, dice.randf_range(-0.1, 0.1)))
		for b in dice.randi_range(1, 3):
			_sphere(0.035, at + Vector3.DOWN * dice.randf_range(0.2, length), BULB, 2.0)
	_make_slots()


## The goods' spots: hooks on the back panel and the front posts, fold-down
## shelves on both sides (on their chains), strings under the back eave.
func _make_slots() -> void:
	for row: float in [1.9, 1.4]:
		for x: float in [-0.32, 0.32]:
			_box(Vector3(0.02, 0.06, 0.06), Vector3(x, row + 0.12, 0.92), WORN) # the hook
			slots.append({show = &"hook", xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, row, 0.97))})
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.02, 0.06, 0.06), Vector3(side * 0.66, 1.9, -0.19), WORN)
		slots.append({show = &"hook", xf = Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * 0.72, 1.72, -0.19))})
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.34, 0.04, 0.95), Vector3(side * 0.86, 1.6, 0.35), WOOD) # the shelf, let down
		_box(Vector3(0.01, 0.42, 0.01), Vector3(side * 1.02, 1.81, -0.1), WORN) # its chains
		_box(Vector3(0.01, 0.42, 0.01), Vector3(side * 1.02, 1.81, 0.8), WORN)
		for z: float in [0.05, 0.35, 0.65]:
			slots.append({show = &"shelf", xf = Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * 0.86, 1.64, z))})
	for x: float in [-0.6, -0.2, 0.2, 0.6]:
		slots.append({show = &"eave", xf = Transform3D(Basis.IDENTITY, Vector3(x, 1.85, 1.1))})


## A bit of staghorn coral: a few branches, each ending in a glowing tip.
func _coral(parent: Node3D, at: Vector3, dice: RandomNumberGenerator, size: float) -> void:
	var tip: Color = CORAL_TIPS[dice.randi() % CORAL_TIPS.size()]
	for i in dice.randi_range(3, 5):
		var length := dice.randf_range(0.12, 0.28) * size
		var lean := Vector3(dice.randf_range(-0.7, 0.7), 1.0, dice.randf_range(-0.7, 0.7)).normalized()
		var end := at + lean * length
		_pole(at, end, 0.015 * size, CORAL, parent)
		_sphere(0.025 * size, end, tip, 2.5, parent)


func _scale(at: Vector3) -> void:
	_box(Vector3(0.015, 0.45, 0.015), at + Vector3(0.0, 0.62, 0.0), BRASS)
	_box(Vector3(0.3, 0.015, 0.015), at + Vector3(0.0, 0.84, 0.0), BRASS)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.005, 0.18, 0.005), at + Vector3(side * 0.14, 0.75, 0.0), BRASS)
		_cylinder(0.07, 0.015, at + Vector3(side * 0.14, 0.66, 0.0), BRASS)


## The banner's cloth: deep red, a pale almond eye painted on it.
static func _banner() -> ImageTexture:
	if _banner_texture:
		return _banner_texture
	var w := 128
	var h := 80
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	var middle := Vector2(w * 0.5, h * 0.5)
	for y in h:
		for x in w:
			var color := BANNER_RED.darkened(dice.randf_range(0.0, 0.15))
			var p := Vector2(x, y) - middle
			# The almond: inside two big circles at once.
			var in_eye := p.distance_to(Vector2(0.0, 26.0)) < 46.0 and p.distance_to(Vector2(0.0, -26.0)) < 46.0 and absf(p.x) < 44.0
			if in_eye:
				color = Color(0.86, 0.8, 0.68).darkened(dice.randf_range(0.0, 0.1))
				var r := p.length()
				if r < 15.0:
					color = Color(0.16, 0.1, 0.06)
				if r < 6.0:
					color = Color(0.02, 0.02, 0.02)
				if Vector2(x, y).distance_to(middle + Vector2(-4.0, -4.0)) < 2.0:
					color = Color(0.9, 0.9, 0.85)
			image.set_pixel(x, y, color)
	_banner_texture = ImageTexture.create_from_image(image)
	return _banner_texture


static func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material


func _box(size: Vector3, at: Vector3, color: Color, turn := Vector3.ZERO, glow := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _put(mesh, at, color, turn, glow, parent)


func _cylinder(radius: float, height: float, at: Vector3, color: Color, turn := Vector3.ZERO, glow := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return _put(mesh, at, color, turn, glow, parent)


func _sphere(radius: float, at: Vector3, color: Color, glow := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return _put(mesh, at, color, Vector3.ZERO, glow, parent)


## A thin pole from `a` to `b`.
func _pole(a: Vector3, b: Vector3, radius: float, color: Color, parent: Node3D = null) -> void:
	var piece := _cylinder(radius, a.distance_to(b), (a + b) * 0.5, color, Vector3.ZERO, 0.0, parent)
	var along := (b - a).normalized()
	if absf(along.dot(Vector3.UP)) < 0.999:
		piece.basis = Basis(Quaternion(Vector3.UP, along))


func _put(mesh: Mesh, at: Vector3, color: Color, turn: Vector3, glow: float, parent: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(color, glow)
	part.position = at
	part.rotation = turn
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if glow <= 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(part)
	return part
