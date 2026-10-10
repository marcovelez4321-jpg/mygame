class_name StackBuilder
extends RefCounted

## The Stack (docs/WORLD.md -- every detail the user's choice, Rule 9): a
## cluster of five brutalist towers, the tallest 5 km, tangled together by
## skybridges at every height, overgrown with the sewer land's growth the
## whole way up, scattered lit windows and red blinkers climbing it, roach
## swarms circling the tops, a colossal worm coiling up one tower, a lift
## still running. The way in is up: grapple to the lowest skybridge (28 m
## up) and walk it into the main tower. Inside, built for something far
## bigger than a person: 40 m floors of huge apartment blocks round a
## central shaft that drops through the ground to the flooded sewer depths.
## The boss worm's home: its lair is the main tower's foot.
##
## Laid out as boxes (seeded, the same every build) and made into:
##   scenes/megastructures/the_stack.scn -- a Megastructure scene (Shell,
##   Interior, Decor, Lair), ready to place;
##   maps/megastructures/the_stack.map -- the same boxes as a TrenchBroom
##   map (8 units a metre), to edit by hand from now on.
## tools/make_the_stack.gd runs it.

const SEED := 5000
const TEX_METRES := 8.0 # one concrete tile (with its window) every 8 m
const MAP_UNITS := 8.0 # TrenchBroom units a metre (megastructure maps)
const TOWERS := [ # x, z, footprint (m), height (m)
	[0.0, 0.0, 200.0, 5000.0],
	[260.0, 60.0, 140.0, 3600.0],
	[-200.0, 190.0, 150.0, 2800.0],
	[80.0, -270.0, 120.0, 2000.0],
	[-250.0, -170.0, 110.0, 1400.0],
]
const FLOOR := 40.0 # ceiling height inside
const SLAB := 4.0
const WALL := 6.0
const INTERIOR_TOP := 400.0 # the main tower's hollow, walkable part: 10 floors
const SHAFT := 60.0
const SHAFT_BOTTOM := -240.0
const DEPTHS_FLOOR := -293.0
const DEPTHS_SIZE := 320.0
const WATER_LEVEL := -290.0
const ENTRANCE_UNDERSIDE := 28.0 # within the grapple's 35 m from the ground

## Every box: {c: centre, s: size, yaw: radians round Y, part: &"shell" or
## &"interior", solid: a big closed block (an occluder), tower: index or -1}.
var boxes: Array[Dictionary] = []
## Openings to the outside (the wind howls through them).
var openings := PackedVector3Array()
var random := RandomNumberGenerator.new()


func _init() -> void:
	random.seed = SEED
	_main_tower()
	for t in range(1, TOWERS.size()):
		_solid_tower(t, 0.0)
	_bridges()
	_depths()


func _box(centre: Vector3, size: Vector3, part: StringName, solid: bool = false, tower: int = -1, yaw: float = 0.0) -> void:
	if part == &"shell" and absf(centre.y - size.y * 0.5) < 0.01:
		# Standing on the ground: sunk 3 m into it, so no gap shows on a slope.
		size.y += 3.0
		centre.y -= 1.5
	boxes.append({c = centre, s = size, yaw = yaw, part = part, solid = solid, tower = tower})


# ---- Layout -----------------------------------------------------------------

## The main tower: hollow for its first ten floors (walls with openings,
## floors round the shaft, apartment blocks), solid stacked blocks above.
func _main_tower() -> void:
	var foot: float = TOWERS[0][2]
	var half := foot * 0.5
	var inner := foot - WALL * 2.0
	var floors := int(INTERIOR_TOP / FLOOR)
	for f in floors:
		var y0 := f * FLOOR
		for side in 4:
			_wall_with_openings(side, y0, half, f)
	# Floors (and the ceiling at the top), each with the shaft's hole.
	for f in floors + 1:
		_slab_with_hole(f * FLOOR - SLAB * 0.5, inner)
	# Apartment blocks: a maze of huge blocks round the shaft on every floor,
	# corridors 30 m wide between them.
	for f in floors:
		var y0 := f * FLOOR
		for gx in range(-2, 2):
			for gz in range(-2, 2):
				var cell := Vector2(gx + 0.5, gz + 0.5) * 46.0
				if absf(cell.x) < SHAFT * 0.5 + 20.0 and absf(cell.y) < SHAFT * 0.5 + 20.0:
					continue # the shaft and the ring round it stay open
				if random.randf() < 0.2:
					continue # a gap: a hall
				var tall := random.randf_range(16.0, FLOOR - 6.0)
				var size := Vector3(random.randf_range(24.0, 34.0), tall, random.randf_range(24.0, 34.0))
				_box(Vector3(cell.x, y0 + tall * 0.5, cell.y), size, &"interior")
	# The shaft's walls, down through the ground to the depths.
	var down := -SHAFT_BOTTOM
	var ring := SHAFT + WALL * 2.0
	for side in 4:
		var along := ring if side < 2 else SHAFT
		var out := (SHAFT + WALL) * 0.5
		var centre := Vector3(0.0, SHAFT_BOTTOM * 0.5 - SLAB, 0.0)
		match side:
			0: centre.z = -out
			1: centre.z = out
			2: centre.x = -out
			3: centre.x = out
		var size := Vector3(along, down, WALL) if side < 2 else Vector3(WALL, down, along)
		_box(centre, size, &"interior")
	_solid_tower(0, INTERIOR_TOP)


## One storey of an outer wall (side 0..3: -Z, +Z, -X, +X) with two great
## openings in it -- and on the entrance side, the floor the bridge comes in at.
func _wall_with_openings(side: int, y0: float, half: float, storey: int) -> void:
	var length := half * 2.0
	var sill := 8.0
	var lintel := 12.0
	var gap := 34.0
	var entrance := side == 3 and storey == 1 # +X, 40 m up: the bridge's end
	if entrance:
		sill = 0.0
	# Pieces along the wall: pillar, opening, pillar, opening, pillar.
	var pillar := (length - gap * 2.0) / 3.0
	var cursor := -half
	for piece in 5:
		var width := pillar if piece % 2 == 0 else gap
		var middle := cursor + width * 0.5
		if piece % 2 == 0:
			_wall_piece(side, half, middle, width, y0, FLOOR)
		else:
			if sill > 0.0:
				_wall_piece(side, half, middle, width, y0, sill)
			_wall_piece(side, half, middle, width, y0 + FLOOR - lintel, lintel)
			openings.append(_on_wall(side, half, middle, y0 + sill + (FLOOR - lintel - sill) * 0.5))
		cursor += width


func _wall_piece(side: int, half: float, along: float, width: float, y0: float, tall: float) -> void:
	var centre := _on_wall(side, half - WALL * 0.5, along, y0 + tall * 0.5)
	var size := Vector3(width, tall, WALL) if side < 2 else Vector3(WALL, tall, width)
	_box(centre, size, &"shell", false, 0)


## A point on wall `side`, `along` it, at height y (`out` from the middle).
func _on_wall(side: int, out: float, along: float, y: float) -> Vector3:
	match side:
		0: return Vector3(along, y, -out)
		1: return Vector3(along, y, out)
		2: return Vector3(-out, y, along)
	return Vector3(out, y, along)


## A floor slab with the shaft's square hole in the middle (four boxes).
func _slab_with_hole(y: float, inner: float) -> void:
	var rim := (inner - SHAFT) * 0.5
	var off := SHAFT * 0.5 + rim * 0.5
	_box(Vector3(0.0, y, -off), Vector3(inner, SLAB, rim), &"interior")
	_box(Vector3(0.0, y, off), Vector3(inner, SLAB, rim), &"interior")
	_box(Vector3(-off, y, 0.0), Vector3(rim, SLAB, SHAFT), &"interior")
	_box(Vector3(off, y, 0.0), Vector3(rim, SLAB, SHAFT), &"interior")


## A tower of stacked blocks from `from` up to its height: each block a
## different size and nudged off the one below, narrowing as it climbs.
func _solid_tower(t: int, from: float) -> void:
	var x: float = TOWERS[t][0]
	var z: float = TOWERS[t][1]
	var foot: float = TOWERS[t][2]
	var height: float = TOWERS[t][3]
	var y := from
	while y < height - 20.0:
		var tall := minf(random.randf_range(140.0, 340.0), height - y)
		var progress := y / height
		var width := foot * lerpf(1.0, 0.42, progress) * random.randf_range(0.8, 1.15)
		var depth := foot * lerpf(1.0, 0.42, progress) * random.randf_range(0.8, 1.15)
		var nudge := Vector2(random.randf_range(-0.12, 0.12) * width, random.randf_range(-0.12, 0.12) * depth)
		_box(Vector3(x + nudge.x, y + tall * 0.5, z + nudge.y), Vector3(width, tall, depth), &"shell", true, t)
		y += tall


## Skybridges: the entrance (28 m up, into the main tower's second floor),
## and dozens more between the towers at every height.
func _bridges() -> void:
	# The entrance: from tower 1 to the main tower's +X wall, its deck level
	# with the main tower's floor at 40 m.
	var start := Vector3(TOWERS[1][0] - TOWERS[1][2] * 0.5 + 4.0, 0.0, 30.0)
	var finish := Vector3(TOWERS[0][2] * 0.5 + WALL, 0.0, 30.0)
	var deck := FLOOR
	var thick := deck - ENTRANCE_UNDERSIDE
	_box(Vector3((start.x + finish.x) * 0.5, deck - thick * 0.5, 30.0), Vector3(start.x - finish.x, thick, 26.0), &"shell")
	openings.append(Vector3((start.x + finish.x) * 0.5, deck + 8.0, 30.0))
	for i in 34:
		var a := random.randi() % TOWERS.size()
		var b := (a + 1 + random.randi() % (TOWERS.size() - 1)) % TOWERS.size()
		var top := minf(TOWERS[a][3], TOWERS[b][3]) - 120.0
		var y := random.randf_range(140.0, top)
		var from := Vector3(TOWERS[a][0], y, TOWERS[a][1])
		var to := Vector3(TOWERS[b][0], y, TOWERS[b][1])
		var across := Vector2(to.x - from.x, to.z - from.z)
		var size := Vector3(random.randf_range(14.0, 40.0), random.randf_range(8.0, 26.0), across.length())
		_box((from + to) * 0.5, size, &"shell", false, -1, atan2(across.x, across.y))
		openings.append((from + to) * 0.5 + Vector3.UP * (size.y * 0.5 + 6.0))


## The flooded depths: a vast drowned hall at the shaft's foot, pillars
## rising out of black water, half-sunk apartment blocks, sewer tunnels
## leading off into the dark.
func _depths() -> void:
	var half := DEPTHS_SIZE * 0.5
	var top := SHAFT_BOTTOM
	var tall := top - DEPTHS_FLOOR
	_box(Vector3(0.0, DEPTHS_FLOOR - 5.0, 0.0), Vector3(DEPTHS_SIZE, 10.0, DEPTHS_SIZE), &"interior")
	# Its ceiling, holed for the shaft.
	_slab_with_hole(top + SLAB * 0.5, DEPTHS_SIZE)
	for side in 4:
		var centre := _on_wall(side, half + WALL * 0.5, 0.0, DEPTHS_FLOOR + tall * 0.5)
		var size := Vector3(DEPTHS_SIZE + WALL * 2.0, tall, WALL) if side < 2 else Vector3(WALL, tall, DEPTHS_SIZE + WALL * 2.0)
		_box(centre, size, &"interior")
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if gx == 0 and gz == 0:
				continue # under the shaft
			var at := Vector2(gx, gz) * 60.0
			if random.randf() < 0.3:
				# A half-sunk apartment block.
				var block := random.randf_range(18.0, 30.0)
				_box(Vector3(at.x, DEPTHS_FLOOR + block * 0.5, at.y), Vector3(28.0, block, 28.0), &"interior")
			else:
				_box(Vector3(at.x, DEPTHS_FLOOR + tall * 0.5, at.y), Vector3(10.0, tall, 10.0), &"interior")
	# Sewer tunnels off two sides: arches of three boxes going off into the dark.
	for side in [0, 3]:
		for k in 4:
			var out := half + WALL + 20.0 + k * 40.0
			var centre := _on_wall(side, out, 0.0, DEPTHS_FLOOR)
			var length := 40.0
			var sx := Vector3(30.0, 4.0, length) if side < 2 else Vector3(length, 4.0, 30.0)
			_box(centre + Vector3(0.0, -2.0, 0.0), sx, &"interior")
			_box(centre + Vector3(0.0, 26.0, 0.0), sx, &"interior")
			var wall_size := Vector3(4.0, 28.0, length) if side < 2 else Vector3(length, 28.0, 4.0)
			var offset := Vector3(17.0, 12.0, 0.0) if side < 2 else Vector3(0.0, 12.0, 17.0)
			_box(centre + offset, wall_size, &"interior")
			_box(centre + Vector3(-offset.x, offset.y, -offset.z), wall_size, &"interior")
		# Where the tunnel meets the hall: a hole in that wall (the wall
		# stays solid for now -- the tunnel mouths are dark alcoves).


# ---- The scene --------------------------------------------------------------

## The whole Stack as a Megastructure scene (not yet saved).
func build_scene(concrete: Texture2D, wind: AudioStream, drone: AudioStream) -> Megastructure:
	var root := Megastructure.new()
	root.name = "TheStack"
	root.inside = AABB(Vector3(-TOWERS[0][2] * 0.5 + WALL, 0.0, -TOWERS[0][2] * 0.5 + WALL),
			Vector3(TOWERS[0][2] - WALL * 2.0, INTERIOR_TOP, TOWERS[0][2] - WALL * 2.0))
	var shell := Node3D.new()
	shell.name = "Shell"
	_own(root, shell, root)
	var interior := Node3D.new()
	interior.name = "Interior"
	_own(root, interior, root)
	var decor := Node3D.new()
	decor.name = "Decor"
	_own(root, decor, root)
	# Meshes: the shell per tower (so each can be culled), the bridges, the inside.
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_texture = concrete
	shell_material.albedo_color = Color(0.82, 0.8, 0.78)
	var inside_material := StandardMaterial3D.new()
	inside_material.albedo_texture = concrete
	inside_material.albedo_color = Color(0.62, 0.62, 0.58)
	inside_material.roughness = 1.0
	inside_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	inside_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	for t in range(-1, TOWERS.size()):
		var picked := boxes.filter(func(b: Dictionary) -> bool: return b.part == &"shell" and b.tower == t)
		_mesh_node(root, shell, "Tower_%d" % t if t >= 0 else "Bridges", picked, shell_material, true)
	_mesh_node(root, interior, "Insides", boxes.filter(func(b: Dictionary) -> bool: return b.part == &"interior"), inside_material, false)
	_collision(root, shell, "ShellBody", &"shell")
	_collision(root, interior, "InteriorBody", &"interior")
	_occluders(root, shell)
	_water(root, interior)
	_depth_lights(root, interior)
	_windows(root, decor)
	_growth(root, decor)
	_swarms(root, decor)
	var worm := CoilingWorm.new()
	worm.name = "CoilingWorm"
	worm.position = Vector3(TOWERS[2][0], 0.0, TOWERS[2][1])
	worm.radius = TOWERS[2][2] * 0.6
	worm.bottom = 300.0
	worm.top = 2500.0
	_own(root, worm, decor)
	_lift(root, decor)
	var sound := MegastructureSound.new()
	sound.name = "Sound"
	sound.wind_stream = wind
	sound.drone_stream = drone
	sound.openings = openings
	sound.inside = AABB(Vector3(-TOWERS[0][2] * 0.5, DEPTHS_FLOOR - 10.0, -DEPTHS_SIZE * 0.5),
			Vector3(TOWERS[0][2], INTERIOR_TOP - DEPTHS_FLOOR + 10.0, DEPTHS_SIZE))
	_own(root, sound, decor)
	# The boss worm's lair: the main tower's foot (a shape in no body).
	var lair := CollisionShape3D.new()
	lair.name = "Lair"
	var lair_box := BoxShape3D.new()
	lair_box.size = Vector3(TOWERS[0][2], INTERIOR_TOP, TOWERS[0][2])
	lair.shape = lair_box
	lair.position = Vector3(0.0, INTERIOR_TOP * 0.5, 0.0)
	_own(root, lair, root)
	return root


func _own(root: Node, node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = root


func _mesh_node(root: Node, parent: Node, name: String, picked: Array, material: Material, shadows: bool) -> void:
	if picked.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in picked:
		_box_faces(st, b)
	st.generate_normals()
	st.set_material(material)
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(root, node, parent)


## A box's six faces, its texture laid in metres (a tile every TEX_METRES)
## along each face, upright on the walls.
func _box_faces(st: SurfaceTool, b: Dictionary) -> void:
	var basis := Basis(Vector3.UP, b.yaw)
	var half: Vector3 = b.s * 0.5
	var centre: Vector3 = b.c
	# Each face: its outward axis, and its two in-plane axes (u across, v up/along;
	# u x v = -outward, so the corners below run clockwise seen from outside,
	# Godot's front faces).
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	]
	for face in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var nh := absf(n.dot(half))
		var uh := absf(u.dot(half))
		var vh := absf(v.dot(half))
		var corners := [-u * uh - v * vh, u * uh - v * vh, u * uh + v * vh, -u * uh + v * vh]
		var uvs := [Vector2(0.0, vh * 2.0), Vector2(uh * 2.0, vh * 2.0), Vector2(uh * 2.0, 0.0), Vector2(0.0, 0.0)]
		var points: Array[Vector3] = []
		for corner: Vector3 in corners:
			points.append(centre + basis * (n * nh + corner))
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv((uvs[i] as Vector2) / TEX_METRES)
			st.add_vertex(points[i])


## Every box of `part` as a box shape on one static body.
func _collision(root: Node, parent: Node, name: String, part: StringName) -> void:
	var body := StaticBody3D.new()
	body.name = name
	_own(root, body, parent)
	for b in boxes:
		if b.part != part:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.s
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.UP, b.yaw), b.c)
		_own(root, shape, body)


## The solid tower blocks block the view: what's behind them isn't drawn.
func _occluders(root: Node, parent: Node) -> void:
	var holder := Node3D.new()
	holder.name = "Occluders"
	_own(root, holder, parent)
	for b in boxes:
		if not b.solid:
			continue
		var occluder := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = (b.s as Vector3) * 0.96 # a touch inside, so it never hides its own faces
		occluder.occluder = box
		occluder.position = b.c
		_own(root, occluder, holder)


func _water(root: Node, parent: Node) -> void:
	var water := MeshInstance3D.new()
	water.name = "FloodWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(DEPTHS_SIZE, DEPTHS_SIZE)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.08, 0.04, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	material.metallic_specular = 0.8
	plane.material = material
	water.mesh = plane
	water.position = Vector3(0.0, WATER_LEVEL, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(root, water, parent)


## A few dim lamps still burning down in the depths.
func _depth_lights(root: Node, parent: Node) -> void:
	for i in 8:
		var lamp := OmniLight3D.new()
		lamp.name = "DepthLamp_%d" % i
		lamp.light_color = Color(1.0, 0.62, 0.3)
		lamp.light_energy = 4.0
		lamp.omni_range = 120.0
		lamp.position = Vector3(random.randf_range(-130.0, 130.0), WATER_LEVEL + random.randf_range(15.0, 45.0), random.randf_range(-130.0, 130.0))
		_own(root, lamp, parent)


## Lit windows scattered over the towers' sides (one in twenty or so), and
## red blinkers at block corners all the way up.
func _windows(root: Node, parent: Node) -> void:
	var walls: Array[Dictionary] = []
	var total := 0.0
	for b in boxes:
		if b.solid:
			walls.append(b)
			total += ((b.s as Vector3).x + (b.s as Vector3).z) * 2.0 * (b.s as Vector3).y
	var windows: Array[Transform3D] = []
	var window_colors: Array[Color] = []
	var window_customs: Array[Color] = []
	for i in 5200:
		var b: Dictionary = walls[_weighted(walls, total)]
		var side := random.randi() % 4
		var half: Vector3 = (b.s as Vector3) * 0.5
		var along := random.randf_range(-1.0, 1.0) * (half.x if side < 2 else half.z) * 0.95
		var y := (b.c as Vector3).y + random.randf_range(-1.0, 1.0) * half.y * 0.95
		var out := (half.z if side < 2 else half.x) + 0.3
		var at := _on_wall(side, out, along, 0.0) + Vector3((b.c as Vector3).x, y, (b.c as Vector3).z)
		windows.append(Transform3D(Basis.IDENTITY, at))
		window_colors.append(Color(1.0, randf_range(0.55, 0.75), randf_range(0.2, 0.35)) if random.randf() < 0.85 else Color(0.7, 0.85, 1.0))
		window_customs.append(Color(random.randf(), 0.0, 1.0 if random.randf() < 0.1 else 0.0, 0.0))
	_light_batch(root, parent, "Windows", Vector3(4.2, 5.6, 3.0), windows, window_colors, window_customs)
	var blinkers: Array[Transform3D] = []
	var blinker_colors: Array[Color] = []
	var blinker_customs: Array[Color] = []
	for b in walls:
		var half: Vector3 = (b.s as Vector3) * 0.5
		for corner in 4:
			if random.randf() < 0.1:
				continue
			var at := (b.c as Vector3) + Vector3(half.x * (1 if corner % 2 == 0 else -1), half.y - 2.0, half.z * (1 if corner < 2 else -1))
			blinkers.append(Transform3D(Basis.IDENTITY, at))
			blinker_colors.append(Color(1.0, 0.08, 0.05))
			blinker_customs.append(Color(random.randf(), 1.0, 0.0, 0.0))
	_light_batch(root, parent, "Blinkers", Vector3(9.0, 9.0, 9.0), blinkers, blinker_colors, blinker_customs)


func _light_batch(root: Node, parent: Node, name: String, size: Vector3, places: Array[Transform3D], colors: Array[Color], customs: Array[Color]) -> void:
	var box := BoxMesh.new()
	box.size = size
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = box
	multimesh.instance_count = places.size()
	for i in places.size():
		multimesh.set_instance_transform(i, places[i])
		multimesh.set_instance_color(i, colors[i])
		multimesh.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/stack_lights.gdshader")
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(root, node, parent)


## Overgrown the whole way up (the sewer land's growths, made huge): black
## vines breathing over the walls, giant vine pillars climbing them,
## bracket fungus jutting from them, hive spires, egg sacs and mould on
## every terrace.
func _growth(root: Node, parent: Node) -> void:
	var walls: Array[Dictionary] = []
	var tops: Array[Dictionary] = []
	var wall_total := 0.0
	var top_total := 0.0
	for b in boxes:
		if b.part != &"shell" or not b.solid:
			continue
		var s: Vector3 = b.s
		walls.append(b)
		wall_total += (s.x + s.z) * 2.0 * s.y
		tops.append(b)
		top_total += s.x * s.z
	_grow_on(root, parent, GrowthMeshes.Kind.BLACK_VINES, walls, wall_total, true, 420, 10.0, 22.0, 2500.0, 2.8)
	_grow_on(root, parent, GrowthMeshes.Kind.VINE_PILLAR, walls, wall_total, true, 30, 3.0, 8.0, 9000.0, 2.0)
	_grow_on(root, parent, GrowthMeshes.Kind.FUNGUS_TOWER, walls, wall_total, true, 70, 0.8, 2.0, 6000.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.HIVE_SPIRE, tops, top_total, false, 70, 1.2, 3.0, 9000.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.EGG_SACS, tops, top_total, false, 220, 10.0, 20.0, 2500.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.HAIR_MOLD, tops, top_total, false, 400, 14.0, 28.0, 2000.0, 0.0)


## `count` of a growth kind on the blocks' walls (standing out of them) or
## their tops, scale min..max, one MultiMesh, drawn to `distance`.
func _grow_on(root: Node, parent: Node, kind: GrowthMeshes.Kind, blocks: Array[Dictionary], total: float, on_walls: bool,
		count: int, scale_min: float, scale_max: float, distance: float, breathe: float) -> void:
	var places: Array[Transform3D] = []
	for i in count:
		var b: Dictionary = blocks[_weighted_by(blocks, total, on_walls)]
		var s: Vector3 = b.s
		var half := s * 0.5
		var c: Vector3 = b.c
		var size := random.randf_range(scale_min, scale_max)
		var spin := Basis(Vector3.UP, random.randf() * TAU)
		if on_walls:
			var side := random.randi() % 4
			var normal := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT][side] as Vector3
			var along := random.randf_range(-0.9, 0.9) * (half.x if side < 2 else half.z)
			# Thickest low down, thinning up each block.
			var y := c.y - half.y + s.y * pow(random.randf(), 1.4)
			var at := _on_wall(side, (half.z if side < 2 else half.x) - 0.5, along, y) + Vector3(c.x, 0.0, c.z)
			var lie := Basis(Quaternion(Vector3.UP, normal))
			if kind == GrowthMeshes.Kind.VINE_PILLAR:
				lie = Basis.IDENTITY # climbs straight up the wall
				at += normal * 4.0 * size
			places.append(Transform3D(lie * spin * Basis.from_scale(Vector3.ONE * size), at))
		else:
			var at := Vector3(c.x + random.randf_range(-0.9, 0.9) * half.x, c.y + half.y - 0.5, c.z + random.randf_range(-0.9, 0.9) * half.z)
			places.append(Transform3D(spin * Basis.from_scale(Vector3.ONE * size), at))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = GrowthMeshes.get_mesh(kind, random.randi() % 4)
	multimesh.instance_count = places.size()
	for i in places.size():
		multimesh.set_instance_transform(i, places[i])
		multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0))
		multimesh.set_instance_custom_data(i, Color(random.randf(), random.randf(), 0.0, 0.0))
	var node := MultiMeshInstance3D.new()
	node.name = "Growth_%s" % GrowthMeshes.Kind.keys()[kind]
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = GrowthScatter.GROWTH_SHADER
	material.set_shader_parameter("sway_amount", 0.05)
	material.set_shader_parameter("breathe_amount", breathe)
	material.set_shader_parameter("glow_color", Color(1.6, 1.4, 0.5))
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = distance
	_own(root, node, parent)


## Roach swarms circling each tower's top like birds round a cliff.
func _swarms(root: Node, parent: Node) -> void:
	var speck := SurfaceTool.new()
	speck.begin(Mesh.PRIMITIVE_TRIANGLES)
	GrowthMeshes._blob(speck, Vector3.ZERO, 3.5, Color(0.05, 0.04, 0.03), 0.0, 0.0, Vector3(1.6, 0.5, 1.0), false)
	var mesh := speck.commit()
	for t in TOWERS.size():
		var top: float = TOWERS[t][3]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = 700
		for i in 700:
			multimesh.set_instance_transform(i, Transform3D.IDENTITY)
			multimesh.set_instance_custom_data(i, Color(random.randf(), random.randf_range(-1.0, 1.0), random.randf(), random.randf()))
		var node := MultiMeshInstance3D.new()
		node.name = "Swarm_%d" % t
		node.multimesh = multimesh
		var radius: float = TOWERS[t][2] * 1.8
		node.custom_aabb = AABB(Vector3(-radius * 1.3, -200.0, -radius * 1.3), Vector3(radius * 2.6, 400.0, radius * 2.6))
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/swarm.gdshader")
		material.set_shader_parameter("swarm_radius", radius)
		material.set_shader_parameter("swarm_height", 140.0)
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(TOWERS[t][0], top - 60.0, TOWERS[t][1])
		_own(root, node, parent)


## The lift up the main tower's -Z face, from the bridge level up 1.4 km,
## and its cable.
func _lift(root: Node, parent: Node) -> void:
	var face := -TOWERS[0][2] * 0.5 - 12.0
	var lift := StackLift.new()
	lift.name = "Lift"
	lift.position = Vector3(0.0, 0.0, face)
	lift.bottom = FLOOR
	lift.top = 1400.0
	_own(root, lift, parent)
	var cable := MeshInstance3D.new()
	cable.name = "LiftCable"
	var line := BoxMesh.new()
	line.size = Vector3(0.8, 1500.0, 0.8)
	cable.mesh = line
	cable.position = Vector3(0.0, 750.0, face)
	_own(root, cable, parent)


func _weighted(blocks: Array[Dictionary], total: float) -> int:
	return _weighted_by(blocks, total, true)


## A block picked in proportion to its wall area (or its top's area).
func _weighted_by(blocks: Array[Dictionary], total: float, by_walls: bool) -> int:
	var roll := random.randf() * total
	for i in blocks.size():
		var s: Vector3 = blocks[i].s
		roll -= (s.x + s.z) * 2.0 * s.y if by_walls else s.x * s.z
		if roll <= 0.0:
			return i
	return blocks.size() - 1


# ---- The TrenchBroom map ------------------------------------------------------

## Every box as a brush, in two layers (Shell, Interior), Valve 220 format,
## MAP_UNITS a metre (Quake's z-up: map = (godot.z, godot.x, godot.y)).
func write_map(path: String, texture_name: String) -> Error:
	var lines := PackedStringArray()
	lines.append("// Game: 2v-2\n// Format: Valve")
	lines.append("// The Stack -- made by StackBuilder (tools/make_the_stack.gd); edit freely from here.")
	lines.append("{\n\"classname\" \"worldspawn\"\n\"mapversion\" \"220\"\n}")
	var layer_ids := {&"shell": 1, &"interior": 2}
	for part: StringName in layer_ids:
		lines.append("{\n\"classname\" \"func_group\"\n\"_tb_type\" \"_tb_layer\"\n\"_tb_name\" \"%s\"\n\"_tb_id\" \"%d\"" % [
				String(part).capitalize(), layer_ids[part]])
		for b in boxes:
			if b.part == part:
				lines.append(_brush(b, texture_name))
		lines.append("}")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines) + "\n")
	return OK


func _brush(b: Dictionary, texture_name: String) -> String:
	var basis := Basis(Vector3.UP, b.yaw)
	var half: Vector3 = b.s * 0.5
	var centre: Vector3 = b.c
	# Godot's axes in map space: x -> map y, y -> map z, z -> map x.
	var ax := _to_map(basis * Vector3(0.0, 0.0, 1.0)) # godot +Z = map +X
	var ay := _to_map(basis * Vector3(1.0, 0.0, 0.0)) # godot +X = map +Y
	var az := Vector3(0.0, 0.0, 1.0)
	var extent := Vector3(half.z, half.x, half.y) * MAP_UNITS
	var c := _to_map(centre) * MAP_UNITS
	var low := c - ax * extent.x - ay * extent.y - az * extent.z
	var high := c + ax * extent.x + ay * extent.y + az * extent.z
	var step := 64.0
	var planes := [
		[low, low + ay * step, low + az * step, Vector3(0, 1, 0), Vector3(0, 0, -1)], # -X
		[low, low + az * step, low + ax * step, Vector3(1, 0, 0), Vector3(0, 0, -1)], # -Y
		[low, low + ax * step, low + ay * step, Vector3(1, 0, 0), Vector3(0, -1, 0)], # -Z
		[high, high + ay * step, high + ax * step, Vector3(1, 0, 0), Vector3(0, -1, 0)], # +Z
		[high, high + ax * step, high + az * step, Vector3(1, 0, 0), Vector3(0, 0, -1)], # +Y
		[high, high + az * step, high + ay * step, Vector3(0, 1, 0), Vector3(0, 0, -1)], # +X
	]
	var out := PackedStringArray(["{"])
	for p in planes:
		out.append("( %s ) ( %s ) ( %s ) %s [ %s 0 ] [ %s 0 ] 0 1 1" % [_v(p[0]), _v(p[1]), _v(p[2]), texture_name, _v(p[3]), _v(p[4])])
	out.append("}")
	return "\n".join(out)


func _to_map(v: Vector3) -> Vector3:
	return Vector3(v.z, v.x, v.y)


func _v(v: Vector3) -> String:
	return "%s %s %s" % [_n(v.x), _n(v.y), _n(v.z)]


func _n(value: float) -> String:
	var rounded := snappedf(value, 0.001)
	return str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)


# ---- Generated assets ---------------------------------------------------------

## Grey stained concrete, 64 px for 8 m, PS1-coarse: blotches, water streaks
## running down, and one dark window a tile -- thousands of dark windows up
## the towers for nothing.
static func make_concrete() -> Image:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	var blotch := FastNoiseLite.new()
	blotch.seed = 11
	blotch.frequency = 0.08
	var streak := FastNoiseLite.new()
	streak.seed = 12
	streak.frequency = 0.15
	for y in 64:
		for x in 64:
			var shade := 0.42 + blotch.get_noise_2d(x, y) * 0.08
			shade -= maxf(streak.get_noise_2d(x * 1.0, y * 0.12), 0.0) * 0.18 # streaks run down
			var color := Color(shade, shade * 0.98, shade * 0.93)
			# The window: dark glass in a lighter frame.
			if x >= 20 and x < 44 and y >= 16 and y < 46:
				var frame := x < 22 or x >= 42 or y < 18 or y >= 44
				color = Color(0.5, 0.49, 0.46) if frame else Color(0.05, 0.05, 0.06)
			image.set_pixel(x, y, color)
	return image


## Wind howling (loopable): noise through a slowly gliding resonant filter,
## gusting up and down.
static func make_wind(seconds: float = 12.0) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var random := RandomNumberGenerator.new()
	random.seed = 3
	var low := 0.0
	var band := 0.0
	var high := 0.0
	for i in frames:
		var t := float(i) / rate
		var phase := t / seconds * TAU # whole cycles over the loop: it joins up
		var pitch := 380.0 + 220.0 * sin(phase * 2.0) + 90.0 * sin(phase * 5.0 + 1.0)
		var gust := 0.45 + 0.35 * sin(phase * 3.0) + 0.2 * sin(phase * 7.0 + 2.0)
		# State-variable filter: a resonant band round `pitch` -- the howl.
		var f := 2.0 * sin(PI * pitch / rate)
		var noise := random.randf_range(-1.0, 1.0)
		low += f * band
		high = noise - low - 0.08 * band
		band += f * high
		samples[i] = (band * 0.35 + low * 0.05) * gust
	return _wav(_crossfade_loop(samples, rate), rate)


## The drone: low tones beating slowly against each other, a rumble under
## them, swelling and ebbing (every tone whole cycles over the loop).
static func make_drone(seconds: float = 16.0) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var random := RandomNumberGenerator.new()
	random.seed = 4
	var rumble := 0.0
	for i in frames:
		var t := float(i) / rate
		var swell := 0.75 + 0.25 * sin(t / seconds * TAU * 2.0)
		var tone := sin(TAU * 38.0 * t) * 0.45 + sin(TAU * 38.5 * t) * 0.35 + sin(TAU * 57.0 * t) * 0.2 \
				+ sin(TAU * 76.0 * t) * 0.1 + sin(TAU * 113.0 * t) * 0.05
		rumble += (random.randf_range(-1.0, 1.0) - rumble) * 0.01
		samples[i] = (tone * 0.6 + rumble * 2.5) * swell * 0.7
	return _wav(_crossfade_loop(samples, rate), rate)


## The last second blended into the first, so the loop has no seam.
static func _crossfade_loop(samples: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var fade := rate
	var out := samples.slice(0, samples.size() - fade)
	for i in fade:
		var t := float(i) / fade
		out[i] = samples[i] * t + samples[samples.size() - fade + i] * (1.0 - t)
	return out


static func _wav(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav
