extends RefCounted

## The Crawling Ossuary's building (the user's, 2026-10-25): a massive bone-
## dark cathedral-crypt, 400 x 200 m at its base and about 1 km tall, written
## as a TrenchBroom map and built into a scene; the four legs that carry it are
## the game's (Ossuary). Run by tools/make_the_ossuary.gd. Re-running
## overwrites the map and the scene: once the map's been edited in
## TrenchBroom, rebuild it with the scene's own FuncGodotMap ("Map", Build).
##   THE NAVE on its underside (the user's: the great doors on the ground when
##   it's set down): 300 m long, 60 m tall, its arcades and side aisles, an
##   open archway in the front between the spires' feet.
##   TWIN SPIRES at the front to about 1 km: hollow shafts with ledges up their
##   insides (grapple and wall-jump), ledges and corner ribs up their outsides,
##   narrowing in tiers; the chapel atop the left (the reliquary skull's), the
##   belfry atop the right.
##   AT THE BACK: skull-lined crypts off a gallery, and over them the
##   catacombs, a maze of narrow tunnels.
##   THE CASTLE (the user's, 2026-10-26: the rest of the base a massive gothic
##   castle, a massive silhouette, 1 km tall): over the nave and the back, four
##   stepped tiers (CASTLE_TIERS) to 1 km -- halls stacked inside every
##   HALL_GAP (holes to climb up through, in turn front and back), tall slit
##   windows, flying buttresses leaping from piers on each step to the tier
##   above, and a crown of spikes: battlements and spikes along every edge
##   (decor: no collision), great spikes on top. Its way in: a shaft up from
##   the catacombs into its first hall.
## Its own space: the underside's middle at the origin, the front toward -Z;
## megastructure maps are 8 units a metre.

const MAP := "res://maps/megastructures/the_ossuary.map"
const MAP_SETTINGS := "res://maps/megastructures/megastructure_map_settings.tres"
const SCENE := "res://scenes/megastructures/the_ossuary.tscn"
const UNITS := 8.0

## The user's: the Horror set to start (swap them in TrenchBroom).
const OUTSIDE := "Horror_Stone_01-256x256"
const INSIDE := "Horror_Wall_01-256x256"
const FLOOR := "Horror_Floor_01-256x256"
const TRIM := "Plaster_01-256x256"
const CLIP := "clip"
## Metres one tile of each covers.
const TILE := {OUTSIDE: 4.0, INSIDE: 4.0, FLOOR: 4.0, TRIM: 4.0, CLIP: 4.0}

const HALF_X := 100.0
const FRONT := -200.0
const BACK := 200.0
const WALL := 6.0
const SLAB := 3.0
## The nave and its aisles.
const NAVE_FRONT := -150.0
const NAVE_BACK := 150.0
const NAVE_HALF := 60.0
const AISLE_TOP := 33.0
const NAVE_TOP := 62.0
const RIDGE := 86.0
const BAY := 30.0
## The spires: their footprints, the hollow shafts' walls, their tiers.
const SPIRE_X := [-70.0, 70.0]
const SPIRE_HALF := Vector2(30.0, 25.0)
const SPIRE_Z := -175.0
const SPIRE_WALL := 5.0
const TIERS := [[0.0, 600.0, 1.0], [600.0, 700.0, 0.8], [700.0, 800.0, 0.62], [800.0, 880.0, 0.46]]
const ROOM := [880.0, 925.0, 0.4]
const TIP := 965.0
const LEDGE_EVERY := 25.0
const LEDGE_DEEP := 4.0
const OUTSIDE_LEDGE_EVERY := 40.0
## The doors: an open archway between the spires' feet (the user's).
const ARCH_HALF := 20.0
const ARCH_TOP := 45.0
## The back: crypts, then catacombs over them.
const CRYPT_TOP := 21.0
const CATACOMB_FLOOR := 24.0
const CATACOMB_TOP := 34.0
const BACK_TOP := 37.0
const CELL := 6.0
const TUNNEL := 4.0
## The castle's tiers: [bottom, top, half its width, its front, its back].
const CASTLE_TIERS := [[36.0, 300.0, 95.0, -150.0, 195.0], [300.0, 550.0, 78.0, -130.0, 180.0],
		[550.0, 800.0, 60.0, -105.0, 150.0], [800.0, 1000.0, 42.0, -70.0, 110.0]]
const CASTLE_WALL := 6.0
## The first hall's floor (over the nave's roof), then every HALL_GAP.
const FIRST_HALL := 89.0
const HALL_GAP := 30.0
const HALL_HOLE := 7.0
const PILLAR_GAP := 60.0
const WINDOW_GAP := 30.0
const BUTTRESS_GAP := 40.0
const MERLON_GAP := 8.0
const SPIKE_GAP := 40.0
## The shaft up from the catacombs (its middle; half its inside).
const SHAFT := Vector3(78.0, 0.0, 173.0)
const SHAFT_HALF := 7.0

var _world: Array = []
## Decor: no collision (func_detail_illusionary) -- the crown of spikes.
var _decor: Array = []
var _points: Array = []
var _dice := RandomNumberGenerator.new()


func run(_tree: SceneTree) -> void:
	_dice.seed = 1666
	for path in [MAP, SCENE]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_base()
	_nave()
	_front()
	for i in SPIRE_X.size():
		_spire(float(SPIRE_X[i]), i == 0)
	_back()
	_castle()
	print("map: ", MAP, " (", _world.size(), " brushes, ", _decor.size(), " decor; error ", _write_map(ProjectSettings.globalize_path(MAP)), ")")
	var settings := load(MAP_SETTINGS)
	var map := (load("res://addons/func_godot/src/map/func_godot_map.gd") as GDScript).new() as Node3D
	map.name = "Map"
	map.set("map_settings", settings)
	map.set("local_map_file", MAP)
	# Its faces are clipped from a square this big round the origin: its
	# spires go to 965 m (the default 512 cut everything above that).
	map.set("hyperplane_size", 2048.0)
	for attempt in 6:
		map.call("build")
		var empty := _empty_meshes(map)
		if empty.is_empty():
			break
		print("empty meshes ", empty, " -- building again")
	var building := Node3D.new()
	building.name = "TheOssuary"
	building.add_child(map)
	map.owner = building
	_own(map, map, building)
	var scene := PackedScene.new()
	var error := scene.pack(building)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE)
	print("the Ossuary's building: ", map.get_child_count(), " entities -> ", SCENE, " (error ", error, ")")
	building.free()


func _empty_meshes(map: Node) -> Array[String]:
	var empty: Array[String] = []
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if node.owner == map and (mesh == null or mesh.get_aabb().size == Vector3.ZERO):
			empty.append(str(node.get_parent().name))
	return empty


func _own(node: Node, map: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child.owner == map or child.owner == null:
			child.owner = owner_node
		if child.scene_file_path.is_empty():
			_own(child, map, owner_node)


# ---- The building ----------------------------------------------------------------------------

## Its underside: one great slab, the floor of everything on it.
func _base() -> void:
	_world.append(_box(Vector3(-HALF_X, 0.0, FRONT), Vector3(HALF_X, SLAB, BACK), OUTSIDE, {"+y": FLOOR}))


## The nave: the outer walls with their tall slits, the aisles' roofs, the
## arcades' piers and the clerestory over them, the gable roof.
func _nave() -> void:
	for side: float in [-1.0, 1.0]:
		var out := side * HALF_X
		var inn := side * (HALF_X - WALL)
		var slits: Array = []
		var z := NAVE_FRONT + BAY * 0.5
		while z < NAVE_BACK:
			slits.append([z - 3.0, z + 3.0, 12.0, 26.0])
			z += BAY
		_wall_z(minf(out, inn), maxf(out, inn), NAVE_FRONT, NAVE_BACK, SLAB, AISLE_TOP, slits, side)
		# The aisle's roof.
		_world.append(_box(Vector3(minf(side * NAVE_HALF, inn), AISLE_TOP, NAVE_FRONT), Vector3(maxf(side * NAVE_HALF, inn), AISLE_TOP + 3.0, NAVE_BACK), OUTSIDE, {"-y": INSIDE}))
		# The arcade: piers, the beam over them, the clerestory with its windows.
		z = NAVE_FRONT + BAY
		while z < NAVE_BACK:
			_world.append(_box(Vector3(side * NAVE_HALF - 3.0, SLAB, z - 3.0), Vector3(side * NAVE_HALF + 3.0, AISLE_TOP, z + 3.0), TRIM))
			z += BAY
		var clerestory: Array = []
		z = NAVE_FRONT + BAY * 0.5
		while z < NAVE_BACK:
			clerestory.append([z - 4.0, z + 4.0, AISLE_TOP + 8.0, NAVE_TOP - 6.0])
			z += BAY
		var c0 := side * NAVE_HALF
		var c1 := side * (NAVE_HALF + 3.0)
		_wall_z(minf(c0, c1), maxf(c0, c1), NAVE_FRONT, NAVE_BACK, AISLE_TOP, NAVE_TOP, clerestory, side)
	# The gable roof, its ridge along the nave.
	var slope := (RIDGE - NAVE_TOP) / (NAVE_HALF + 3.0)
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side * slope, 1.0, 0.0).normalized()
		var base := Vector3(side * (NAVE_HALF + 3.0), NAVE_TOP, 0.0)
		_world.append([
			_f(base, -n, INSIDE), _f(base + Vector3.UP * 3.0, n, OUTSIDE),
			_f(Vector3(maxf(side * (NAVE_HALF + 6.0), 0.0), 0.0, 0.0), Vector3.RIGHT, OUTSIDE),
			_f(Vector3(minf(side * (NAVE_HALF + 6.0), 0.0), 0.0, 0.0), Vector3.LEFT, OUTSIDE),
			_f(Vector3(0.0, 0.0, NAVE_BACK), Vector3.BACK, OUTSIDE), _f(Vector3(0.0, 0.0, NAVE_FRONT), Vector3.FORWARD, OUTSIDE)])
	# The nave's back wall: an arch through to the crypts.
	_wall_x(-HALF_X + WALL, HALF_X - WALL, NAVE_BACK, NAVE_BACK + WALL, SLAB, NAVE_TOP, [[-10.0, 10.0, SLAB, 20.0]], 1)
	_gable(NAVE_BACK, NAVE_BACK + WALL)
	_gable(NAVE_FRONT - WALL, NAVE_FRONT) # (over the porch at the front)


## The front: the facade between the spires with its great open archway,
## its gable over the nave, the walls closing the spires' feet to the aisles.
func _front() -> void:
	var inner := SPIRE_X[1] - SPIRE_HALF.x
	_wall_x(-inner, inner, FRONT, FRONT + WALL, SLAB, NAVE_TOP + 20.0, [[-ARCH_HALF, ARCH_HALF, SLAB, ARCH_TOP]], -1)
	_world.append(_box(Vector3(-inner, NAVE_TOP + 20.0, FRONT), Vector3(inner, NAVE_TOP + 24.0, FRONT + WALL + 2.0), TRIM))
	# From the facade back to the nave: its side walls, roofed over.
	for side: float in [-1.0, 1.0]:
		_world.append(_box(Vector3(minf(side * inner, side * (inner - WALL)), SLAB, FRONT + WALL), Vector3(maxf(side * inner, side * (inner - WALL)), NAVE_TOP, NAVE_FRONT), OUTSIDE, {"-x" if side > 0.0 else "+x": INSIDE}))
	_world.append(_box(Vector3(-inner, NAVE_TOP, FRONT + WALL), Vector3(inner, NAVE_TOP + 3.0, NAVE_FRONT), OUTSIDE, {"-y": INSIDE}))


## A spire: a hollow shaft in narrowing tiers, ledges up its inside, ledges
## round and ribs up its outside, windows; an arch into it from the nave; at
## the top the chapel (`chapel`) or the belfry, and its tip.
func _spire(cx: float, chapel: bool) -> void:
	var cz := SPIRE_Z
	var toward_nave := -signf(cx)
	var prev := Vector2.ZERO
	for t: Array in TIERS:
		var y0: float = t[0]
		var y1: float = t[1]
		var hx: float = SPIRE_HALF.x * float(t[2])
		var hz: float = SPIRE_HALF.y * float(t[2])
		var wall := SPIRE_WALL * maxf(float(t[2]), 0.6)
		var bottom := maxf(y0, SLAB)
		# Its walls, windows every 50 m on the three outer faces; the arch
		# from the nave at its foot.
		var windows: Array = []
		var y := bottom + 40.0
		while y + 14.0 < y1:
			windows.append([-4.0, 4.0, y, y + 14.0])
			y += 50.0
		var nave_arch: Array = [[-12.0, 12.0, SLAB, 30.0]] if y0 == 0.0 else []
		_wall_x(cx - hx, cx + hx, cz - hz, cz - hz + wall, bottom, y1, _shift(windows, cx), -1)
		_wall_x(cx - hx, cx + hx, cz + hz - wall, cz + hz, bottom, y1, _shift(windows, cx), 1)
		var side_out := cx + signf(cx) * hx
		var side_in := cx - signf(cx) * hx
		_wall_z(minf(side_out, side_out - signf(cx) * wall), maxf(side_out, side_out - signf(cx) * wall), cz - hz + wall, cz + hz - wall, bottom, y1, _shift(windows, cz), signf(cx))
		_wall_z(minf(side_in, side_in + signf(cx) * wall), maxf(side_in, side_in + signf(cx) * wall), cz - hz + wall, cz + hz - wall, bottom, y1, _shift(nave_arch + windows, cz), toward_nave)
		# Its floor over the tier below -- the whole of that tier's top (its
		# step outside), a hole in the middle to climb up through.
		if y0 > 0.0:
			_ring(cx, cz, prev.x, prev.y, 6.0, y0 - 2.0, y0)
		prev = Vector2(hx, hz)
		# Ledges up its inside, round the walls in turn (grapple, wall-jump).
		var ledge_y := bottom + LEDGE_EVERY
		var turn := 0
		while ledge_y < y1 - 4.0:
			var ix := hx - wall
			var iz := hz - wall
			match turn % 4:
				0:
					_world.append(_box(Vector3(cx - ix, ledge_y - 2.0, cz - iz), Vector3(cx + ix * 0.4, ledge_y, cz - iz + LEDGE_DEEP), TRIM))
				1:
					_world.append(_box(Vector3(cx + ix - LEDGE_DEEP, ledge_y - 2.0, cz - iz), Vector3(cx + ix, ledge_y, cz + iz * 0.4), TRIM))
				2:
					_world.append(_box(Vector3(cx - ix * 0.4, ledge_y - 2.0, cz + iz - LEDGE_DEEP), Vector3(cx + ix, ledge_y, cz + iz), TRIM))
				3:
					_world.append(_box(Vector3(cx - ix, ledge_y - 2.0, cz - iz * 0.4), Vector3(cx - ix + LEDGE_DEEP, ledge_y, cz + iz), TRIM))
			turn += 1
			ledge_y += LEDGE_EVERY
		# Outside: ledges round it every OUTSIDE_LEDGE_EVERY, ribs up its corners.
		var out_y := bottom + OUTSIDE_LEDGE_EVERY
		while out_y < y1 - 2.0:
			_band(cx, cz, hx, hz, 3.0, out_y - 2.0, out_y)
			out_y += OUTSIDE_LEDGE_EVERY
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var px := cx + corner.x * hx
			var pz := cz + corner.y * hz
			_world.append(_box(Vector3(px - 2.5, bottom, pz - 2.5), Vector3(px + 2.5, y1, pz + 2.5), TRIM))
	# The top room: the chapel (the reliquary skull's altar) or the belfry,
	# arched open on all four sides; then its tip.
	var r0: float = ROOM[0]
	var r1: float = ROOM[1]
	var rx: float = SPIRE_HALF.x * float(ROOM[2])
	var rz: float = SPIRE_HALF.y * float(ROOM[2])
	_ring(cx, cz, prev.x, prev.y, 5.0, r0 - 2.0, r0) # (its floor over the last tier, the way up through it)
	var arches: Array = [[-4.0, 4.0, r0 + 4.0, r1 - 8.0]]
	_wall_x(cx - rx, cx + rx, cz - rz, cz - rz + 2.0, r0, r1, _shift(arches, cx), -1)
	_wall_x(cx - rx, cx + rx, cz + rz - 2.0, cz + rz, r0, r1, _shift(arches, cx), 1)
	_wall_z(cx - rx, cx - rx + 2.0, cz - rz + 2.0, cz + rz - 2.0, r0, r1, _shift(arches, cz), -1)
	_wall_z(cx + rx - 2.0, cx + rx, cz - rz + 2.0, cz + rz - 2.0, r0, r1, _shift(arches, cz), 1)
	_world.append(_box(Vector3(cx - rx, r1, cz - rz), Vector3(cx + rx, r1 + 2.0, cz + rz), OUTSIDE, {"-y": INSIDE}))
	if chapel:
		_world.append(_box(Vector3(cx - 3.0, r0, cz + rz - 8.0), Vector3(cx + 3.0, r0 + 1.6, cz + rz - 5.0), TRIM)) # (the altar: Ossuary.CHAPEL_ALTAR)
	else:
		_world.append(_box(Vector3(cx - 1.0, r1 - 6.0, cz - 1.0), Vector3(cx + 1.0, r1, cz + 1.0), TRIM)) # (the bell's beam: Ossuary.BELL_AT)
	# The tip: a pyramid over the room.
	var top := Vector3(cx, TIP, cz)
	var lo := r1 + 2.0
	_world.append([
		_f(Vector3(cx, lo, cz), Vector3.DOWN, OUTSIDE),
		_f(top, _pyramid_face(Vector3(cx + rx, lo, cz), top, Vector3.RIGHT), OUTSIDE),
		_f(top, _pyramid_face(Vector3(cx - rx, lo, cz), top, Vector3.LEFT), OUTSIDE),
		_f(top, _pyramid_face(Vector3(cx, lo, cz + rz), top, Vector3.BACK), OUTSIDE),
		_f(top, _pyramid_face(Vector3(cx, lo, cz - rz), top, Vector3.FORWARD), OUTSIDE)])


## The pyramid's face through `edge` (its base edge's middle) and the `top`,
## facing out `out`.
func _pyramid_face(edge: Vector3, top: Vector3, out: Vector3) -> Vector3:
	var up := (top - edge).normalized()
	var along := out.cross(Vector3.UP).normalized()
	var n := up.cross(along).normalized()
	return n if n.dot(out) > 0.0 else -n


## The back: the crypts (a gallery across, skull-lined chambers off it), and
## over them the catacombs (a maze of narrow tunnels), a ramp up between;
## walled and roofed.
func _back() -> void:
	var z0 := NAVE_BACK + WALL
	var z1 := BACK - WALL
	var x0 := -HALF_X + WALL
	var x1 := HALF_X - WALL
	# The outer walls round the back, up to its roof.
	_wall_x(-HALF_X, HALF_X, z1, BACK, SLAB, BACK_TOP, [], 1)
	for side: float in [-1.0, 1.0]:
		_world.append(_box(Vector3(minf(side * HALF_X, side * (HALF_X - WALL)), SLAB, NAVE_BACK), Vector3(maxf(side * HALF_X, side * (HALF_X - WALL)), BACK_TOP, BACK), OUTSIDE, {"-x" if side > 0.0 else "+x": INSIDE}))
	# The crypts: a gallery across (z0..z0+12), the chambers behind it.
	var gallery := z0 + 12.0
	var chamber := 16.0
	var x := x0
	while x + chamber <= x1:
		_world.append(_box(Vector3(x + chamber, SLAB, gallery), Vector3(minf(x + chamber + 4.0, x1), CRYPT_TOP, z1), INSIDE))
		x += chamber + 4.0
	# The gallery's back wall, an arch into each chamber.
	var doors: Array = []
	x = x0
	while x + chamber <= x1:
		doors.append([x + 4.0, x + chamber - 4.0, SLAB, 14.0])
		x += chamber + 4.0
	_wall_x(x0, x1, gallery, gallery + 1.5, SLAB, CRYPT_TOP, doors, 0)
	# Between the crypts and the catacombs (a hole for the ramp at the east end).
	_world.append(_box(Vector3(x0, CRYPT_TOP, z0), Vector3(x1 - 14.0, CATACOMB_FLOOR, z1), INSIDE, {"+y": FLOOR}))
	_world.append(_box(Vector3(x1 - 14.0, CRYPT_TOP, gallery), Vector3(x1, CATACOMB_FLOOR, z1), INSIDE, {"+y": FLOOR}))
	# The ramp up from the gallery's east end (clip to walk, steps to see).
	var steps := 10
	var run := 12.0 / steps
	var rise := (CATACOMB_FLOOR - SLAB) / steps
	for i in steps:
		_world.append(_box(Vector3(x1 - 14.0, SLAB, z0 + i * run), Vector3(x1, SLAB + (i + 1) * rise, z0 + (i + 1) * run), INSIDE, {"+y": FLOOR}))
	# The catacombs: a maze of TUNNEL-wide ways, CELL apart (its walls).
	var cols := int((x1 - x0) / CELL)
	var rows := int((z1 - z0) / CELL)
	var open := _maze(cols, rows)
	for c in cols + 1:
		for r in rows + 1:
			# A post at every corner.
			var px := x0 + c * CELL
			var pz := z0 + r * CELL
			_world.append(_box(Vector3(px - 1.0, CATACOMB_FLOOR, pz - 1.0), Vector3(px + 1.0, CATACOMB_TOP, pz + 1.0), INSIDE))
	for c in cols:
		for r in rows + 1:
			if not open.has(Vector3i(c, r, 0)): # (a wall along x, at row r)
				var px := x0 + c * CELL
				var pz := z0 + r * CELL
				_world.append(_box(Vector3(px + 1.0, CATACOMB_FLOOR, pz - 1.0), Vector3(px + CELL - 1.0, CATACOMB_TOP, pz + 1.0), INSIDE))
	for c in cols + 1:
		for r in rows:
			if not open.has(Vector3i(c, r, 1)): # (a wall along z, at column c)
				var px := x0 + c * CELL
				var pz := z0 + r * CELL
				_world.append(_box(Vector3(px - 1.0, CATACOMB_FLOOR, pz + 1.0), Vector3(px + 1.0, CATACOMB_TOP, pz + CELL - 1.0), INSIDE))
	# Its roof (a hole where the shaft goes up into the castle).
	_hole_slab(-HALF_X, HALF_X, NAVE_BACK + WALL, BACK, Vector2(SHAFT.x, SHAFT.z), SHAFT_HALF, CATACOMB_TOP, BACK_TOP, OUTSIDE)


## A maze (deterministic: _dice): the walls knocked through, as
## Vector3i(col, row, 0 = the wall along x at row `row` / 1 = along z at col).
func _maze(cols: int, rows: int) -> Dictionary:
	var open := {}
	var seen := {}
	var stack: Array[Vector2i] = [Vector2i(cols - 1, 0)]
	seen[stack[0]] = true
	while not stack.is_empty():
		var at: Vector2i = stack[stack.size() - 1]
		var ways: Array[Vector2i] = []
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if next.x >= 0 and next.y >= 0 and next.x < cols and next.y < rows and not seen.has(next):
				ways.append(next)
		if ways.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = ways[_dice.randi() % ways.size()]
		seen[next] = true
		if next.x != at.x:
			open[Vector3i(maxi(next.x, at.x), at.y, 1)] = true
		else:
			open[Vector3i(at.x, maxi(next.y, at.y), 0)] = true
		stack.append(next)
	# Ways in: from over the ramp, and a few more knocked through.
	open[Vector3i(cols - 1, 0, 0)] = true
	for i in int(cols * rows * 0.06):
		open[Vector3i(_dice.randi() % cols, 1 + _dice.randi() % maxi(rows - 1, 1), _dice.randi() % 2)] = true
	return open


# ---- The castle ------------------------------------------------------------------------------

func _castle() -> void:
	# The shaft up from the catacombs: walled, ledges up its inside, into
	# the first hall.
	var sx := SHAFT.x
	var sz := SHAFT.z
	var h := SHAFT_HALF
	for side: float in [-1.0, 1.0]:
		_world.append(_box(Vector3(sx - h - 2.0, BACK_TOP, sz + side * h - (2.0 if side < 0.0 else 0.0)), Vector3(sx + h + 2.0, FIRST_HALL, sz + side * h + (2.0 if side > 0.0 else 0.0)), INSIDE))
		_world.append(_box(Vector3(sx + side * h - (2.0 if side < 0.0 else 0.0), BACK_TOP, sz - h), Vector3(sx + side * h + (2.0 if side > 0.0 else 0.0), FIRST_HALL, sz + h), INSIDE))
	var y := BACK_TOP + 18.0
	var turn := 0
	while y < FIRST_HALL - 6.0:
		var along := Vector3(1, 0, 0) if turn % 2 == 0 else Vector3(0, 0, 1)
		var side := -1.0 if (turn / 2) % 2 == 0 else 1.0
		if along.x > 0.0:
			_world.append(_box(Vector3(sx - h, y - 1.5, sz + side * h - (3.0 if side > 0.0 else 0.0)), Vector3(sx + h * 0.3, y, sz + side * h + (3.0 if side < 0.0 else 0.0)), TRIM))
		else:
			_world.append(_box(Vector3(sx + side * h - (3.0 if side > 0.0 else 0.0), y - 1.5, sz - h), Vector3(sx + side * h + (3.0 if side < 0.0 else 0.0), y, sz + h * 0.3), TRIM))
		turn += 1
		y += 16.0
	# The tiers.
	for i in CASTLE_TIERS.size():
		var t: Array = CASTLE_TIERS[i]
		var below: Array = CASTLE_TIERS[i - 1] if i > 0 else []
		_tier(t, below, i == CASTLE_TIERS.size() - 1)
		if i > 0:
			_buttresses(t, below)
	# The crown on top: great spikes.
	var top: Array = CASTLE_TIERS[CASTLE_TIERS.size() - 1]
	var top_y: float = top[1] + 3.0
	var mid_z := (float(top[3]) + float(top[4])) * 0.5
	_decor.append(_pyramid(0.0, mid_z, 10.0, top_y, top_y + 90.0, OUTSIDE))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_decor.append(_pyramid(corner.x * (float(top[2]) - 8.0), mid_z + corner.y * (float(top[4]) - mid_z - 8.0), 6.0, top_y, top_y + 55.0, OUTSIDE))


## One tier: its walls (slit windows a hall), its halls' floors inside (a
## hole to climb through, in turn front and back), pillars in the big halls,
## its roof (the step round the next tier: the floor of its first hall too),
## and its crown of battlements and spikes.
func _tier(t: Array, below: Array, last: bool) -> void:
	var y0: float = t[0]
	var y1: float = t[1]
	var hx: float = t[2]
	var z0: float = t[3]
	var z1: float = t[4]
	var w := CASTLE_WALL
	# Its halls' floors.
	var floors: Array[float] = []
	var fy := FIRST_HALL if below.is_empty() else y0 + HALL_GAP
	while fy < y1 - 10.0:
		floors.append(fy)
		fy += HALL_GAP
	# The walls, a slit window a hall.
	var slits_x: Array = []
	var slits_z: Array = []
	var x := -hx + WINDOW_GAP * 0.5
	while x < hx - 8.0:
		for f in floors:
			slits_x.append([x - 3.0, x + 3.0, f + 6.0, f + 22.0])
		x += WINDOW_GAP
	var z := z0 + WINDOW_GAP * 0.5
	while z < z1 - 8.0:
		for f in floors:
			slits_z.append([z - 3.0, z + 3.0, f + 6.0, f + 22.0])
		z += WINDOW_GAP
	_wall_x(-hx, hx, z0, z0 + w, y0, y1, slits_x, -1)
	_wall_x(-hx, hx, z1 - w, z1, y0, y1, slits_x, 1)
	_wall_z(-hx, -hx + w, z0 + w, z1 - w, y0, y1, slits_z, -1)
	_wall_z(hx - w, hx, z0 + w, z1 - w, y0, y1, slits_z, 1)
	# The halls' floors, their holes in turn front and back (the first over
	# the shaft from the catacombs).
	for n in floors.size():
		var hole := Vector2(SHAFT.x, SHAFT.z) if below.is_empty() and n == 0 else Vector2(0.0, z0 + 30.0 if n % 2 == 0 else z1 - 30.0)
		_hole_slab(-hx + w, hx - w, z0 + w, z1 - w, hole, HALL_HOLE, floors[n] - 3.0, floors[n], FLOOR)
		# Pillars in the big halls (the lower two tiers).
		if hx >= 70.0 and n + 1 < floors.size():
			var px := -hx + PILLAR_GAP
			while px < hx - 20.0:
				var pz := z0 + PILLAR_GAP
				while pz < z1 - 20.0:
					if Vector2(px, pz).distance_to(hole) > 25.0:
						_world.append(_box(Vector3(px - 3.0, floors[n], pz - 3.0), Vector3(px + 3.0, floors[n + 1] - 3.0, pz + 3.0), TRIM))
					pz += PILLAR_GAP
				px += PILLAR_GAP
	# Its roof: the step round the tier above (and that tier's floor), a hole
	# up into the tier above's first hall.
	if last:
		_world.append(_box(Vector3(-hx, y1, z0), Vector3(hx, y1 + 3.0, z1), OUTSIDE, {"-y": INSIDE}))
	else:
		_hole_slab(-hx, hx, z0, z1, Vector2(0.0, z1 - 30.0 if floors.size() % 2 == 0 else z0 + 30.0), HALL_HOLE, y1, y1 + 3.0, OUTSIDE)
	# Its crown: battlements along its top edges, spikes at its corners and
	# along its sides (decor).
	var top := y1 + 3.0
	x = -hx
	while x < hx:
		for edge: float in [z0, z1 - 3.0]:
			_decor.append(_box(Vector3(x, top, edge), Vector3(minf(x + 4.0, hx), top + 5.0, edge + 3.0), TRIM))
		x += MERLON_GAP
	z = z0
	while z < z1:
		for edge: float in [-hx, hx - 3.0]:
			_decor.append(_box(Vector3(edge, top, z), Vector3(edge + 3.0, top + 5.0, minf(z + 4.0, z1)), TRIM))
		z += MERLON_GAP
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var cx := corner.x * (hx - 4.0)
		var cz := z0 + 4.0 if corner.y < 0.0 else z1 - 4.0
		_decor.append(_box(Vector3(cx - 4.0, top, cz - 4.0), Vector3(cx + 4.0, top + 20.0, cz + 4.0), OUTSIDE))
		_decor.append(_pyramid(cx, cz, 4.0, top + 20.0, top + 60.0, OUTSIDE))
	z = z0 + SPIKE_GAP
	while z < z1 - 10.0:
		for side: float in [-1.0, 1.0]:
			_decor.append(_pyramid(side * (hx - 2.0), z, 2.5, top, top + 30.0, OUTSIDE))
		z += SPIKE_GAP


## Flying buttresses up the long sides: a pier on the step below, a spike on
## it, and an arm leaping from the pier's top to the tier's wall.
func _buttresses(t: Array, below: Array) -> void:
	var step_y: float = below[1] + 3.0
	var hx: float = t[2]
	var lower_hx: float = below[2]
	var pier_x := (hx + lower_hx) * 0.5
	var z0: float = t[3]
	var z1: float = t[4]
	var z := z0 + BUTTRESS_GAP * 0.5
	while z < z1 - 10.0:
		for side: float in [-1.0, 1.0]:
			var px := side * pier_x
			_world.append(_box(Vector3(px - 3.0, step_y, z - 3.0), Vector3(px + 3.0, step_y + 60.0, z + 3.0), OUTSIDE))
			_decor.append(_pyramid(px, z, 3.0, step_y + 60.0, step_y + 85.0, OUTSIDE))
			_world.append(_beam(Vector3(px, step_y + 55.0, z), Vector3(side * hx, step_y + 150.0, z), 4.0, 3.0, OUTSIDE))
		z += BUTTRESS_GAP


## A slab x0..x1, z0..z1, y0..y1 with a square hole (`half`) round `hole`.
func _hole_slab(x0: float, x1: float, z0: float, z1: float, hole: Vector2, half: float, y0: float, y1: float, texture: String) -> void:
	var hx0 := clampf(hole.x - half, x0, x1)
	var hx1 := clampf(hole.x + half, x0, x1)
	var hz0 := clampf(hole.y - half, z0, z1)
	var hz1 := clampf(hole.y + half, z0, z1)
	for piece: Array in [[x0, x1, z0, hz0], [x0, x1, hz1, z1], [x0, hx0, hz0, hz1], [hx1, x1, hz0, hz1]]:
		if piece[1] - piece[0] > 0.01 and piece[3] - piece[2] > 0.01:
			_world.append(_box(Vector3(piece[0], y0, piece[2]), Vector3(piece[1], y1, piece[3]), texture, {"+y": FLOOR}))


## A four-sided spike: a square base (`half`) at y0, its point at `top`.
func _pyramid(cx: float, cz: float, half: float, y0: float, top: float, texture: String) -> Array:
	var tip := Vector3(cx, top, cz)
	return [
		_f(Vector3(cx, y0, cz), Vector3.DOWN, texture),
		_f(tip, _pyramid_face(Vector3(cx + half, y0, cz), tip, Vector3.RIGHT), texture),
		_f(tip, _pyramid_face(Vector3(cx - half, y0, cz), tip, Vector3.LEFT), texture),
		_f(tip, _pyramid_face(Vector3(cx, y0, cz + half), tip, Vector3.BACK), texture),
		_f(tip, _pyramid_face(Vector3(cx, y0, cz - half), tip, Vector3.FORWARD), texture)]


## A slanting beam from `a` to `b` (in a plane across Z): `width` across Z,
## `thick` deep.
func _beam(a: Vector3, b: Vector3, width: float, thick: float, texture: String) -> Array:
	var along := (b - a).normalized()
	var across := Vector3.BACK
	var up := along.cross(across).normalized()
	return [
		_f(b, along, texture), _f(a, -along, texture),
		_f(a + across * width * 0.5, across, texture), _f(a - across * width * 0.5, -across, texture),
		_f(a + up * thick * 0.5, up, texture), _f(a - up * thick * 0.5, -up, texture)]


# ---- Pieces ----------------------------------------------------------------------------------

func _shift(openings: Array, by: float) -> Array:
	var moved: Array = []
	for o: Array in openings:
		moved.append([o[0] + by, o[1] + by, o[2], o[3]])
	return moved


## A floor with a square hole in its middle (`hole` half-size): four boxes.
func _ring(cx: float, cz: float, hx: float, hz: float, hole: float, y0: float, y1: float) -> void:
	_world.append(_box(Vector3(cx - hx, y0, cz - hz), Vector3(cx + hx, y1, cz - hole), FLOOR))
	_world.append(_box(Vector3(cx - hx, y0, cz + hole), Vector3(cx + hx, y1, cz + hz), FLOOR))
	_world.append(_box(Vector3(cx - hx, y0, cz - hole), Vector3(cx - hole, y1, cz + hole), FLOOR))
	_world.append(_box(Vector3(cx + hole, y0, cz - hole), Vector3(cx + hx, y1, cz + hole), FLOOR))


## A ledge `deep` out all round a footprint, y0..y1.
func _band(cx: float, cz: float, hx: float, hz: float, deep: float, y0: float, y1: float) -> void:
	_world.append(_box(Vector3(cx - hx - deep, y0, cz - hz - deep), Vector3(cx + hx + deep, y1, cz - hz), TRIM))
	_world.append(_box(Vector3(cx - hx - deep, y0, cz + hz), Vector3(cx + hx + deep, y1, cz + hz + deep), TRIM))
	_world.append(_box(Vector3(cx - hx - deep, y0, cz - hz), Vector3(cx - hx, y1, cz + hz), TRIM))
	_world.append(_box(Vector3(cx + hx, y0, cz - hz), Vector3(cx + hx + deep, y1, cz + hz), TRIM))


## A gable end over the nave's back wall (between z0..z1).
func _gable(z0: float, z1: float) -> void:
	var slope := (RIDGE - NAVE_TOP) / (NAVE_HALF + 3.0)
	_world.append([
		_f(Vector3(0.0, NAVE_TOP, 0.0), Vector3.DOWN, OUTSIDE),
		_f(Vector3(0.0, 0.0, z1), Vector3.BACK, OUTSIDE), _f(Vector3(0.0, 0.0, z0), Vector3.FORWARD, INSIDE),
		_f(Vector3(-(NAVE_HALF + 3.0), NAVE_TOP, 0.0), Vector3(-slope, 1.0, 0.0).normalized(), OUTSIDE),
		_f(Vector3(NAVE_HALF + 3.0, NAVE_TOP, 0.0), Vector3(slope, 1.0, 0.0).normalized(), OUTSIDE)])


## A wall along X (x0..x1), z0..z1 thick, y0..y1, with openings
## [x0, x1, y0, y1]; `out`: which face is outside (-1 the -Z, 1 the +Z, 0 none).
func _wall_x(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, openings: Array, out: int) -> void:
	for piece: Array in _pieces(x0, x1, y0, y1, openings):
		var faces := {"-z": OUTSIDE if out < 0 else INSIDE, "+z": OUTSIDE if out > 0 else INSIDE}
		_world.append(_box(Vector3(piece[0], piece[2], z0), Vector3(piece[1], piece[3], z1), INSIDE, faces))


## A wall along Z (z0..z1), x0..x1 thick; `out` -1 the -X face, 1 the +X.
func _wall_z(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, openings: Array, out: float) -> void:
	for piece: Array in _pieces(z0, z1, y0, y1, openings):
		var faces := {"-x": OUTSIDE if out < 0.0 else INSIDE, "+x": OUTSIDE if out > 0.0 else INSIDE}
		_world.append(_box(Vector3(x0, piece[2], piece[0]), Vector3(x1, piece[3], piece[1]), INSIDE, faces))


## A wall's solid pieces round its openings: [a0, a1, y0, y1].
func _pieces(a0: float, a1: float, y0: float, y1: float, openings: Array) -> Array:
	var cuts := [a0, a1]
	for o: Array in openings:
		cuts.append(clampf(o[0], a0, a1))
		cuts.append(clampf(o[1], a0, a1))
	cuts.sort()
	var pieces: Array = []
	for i in cuts.size() - 1:
		var s0: float = cuts[i]
		var s1: float = cuts[i + 1]
		if s1 - s0 < 0.01:
			continue
		var mid := (s0 + s1) * 0.5
		var gaps: Array = []
		for o: Array in openings:
			if o[0] < mid and mid < o[1]:
				gaps.append([maxf(o[2], y0), minf(o[3], y1)])
		gaps.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var y := y0
		for g: Array in gaps:
			if g[0] > y + 0.01:
				pieces.append([s0, s1, y, g[0]])
			y = maxf(y, g[1])
		if y < y1 - 0.01:
			pieces.append([s0, s1, y, y1])
	return pieces


func _box(lo: Vector3, hi: Vector3, texture: String, faces: Dictionary = {}) -> Array:
	return [
		_f(hi, Vector3.RIGHT, faces.get("+x", texture)),
		_f(lo, Vector3.LEFT, faces.get("-x", texture)),
		_f(hi, Vector3.UP, faces.get("+y", texture)),
		_f(lo, Vector3.DOWN, faces.get("-y", texture)),
		_f(hi, Vector3.BACK, faces.get("+z", texture)),
		_f(lo, Vector3.FORWARD, faces.get("-z", texture)),
	]


func _f(point: Vector3, normal: Vector3, texture: String) -> Dictionary:
	return {p = point, n = normal.normalized(), tex = texture}


# ---- The map ---------------------------------------------------------------------------------

func _write_map(path: String) -> Error:
	var lines := PackedStringArray()
	lines.append("// Game: 2v-2\n// Format: Valve")
	lines.append("// The Crawling Ossuary's building -- made by tools/make_the_ossuary.gd; edit freely from here (then Build the scene's Map).")
	lines.append("{\n\"classname\" \"worldspawn\"\n\"mapversion\" \"220\"")
	for brush: Array in _world:
		lines.append(_brush_text(brush))
	lines.append("}")
	if not _decor.is_empty():
		lines.append("{\n\"classname\" \"func_detail_illusionary\"")
		for brush: Array in _decor:
			lines.append(_brush_text(brush))
		lines.append("}")
	for point: Array in _points:
		var entity := PackedStringArray(["{", "\"classname\" \"%s\"" % point[0], "\"origin\" \"%s\"" % _v(_to_map(point[1]) * UNITS)])
		for key: String in point[2]:
			entity.append("\"%s\" \"%s\"" % [key, point[2][key]])
		entity.append("}")
		lines.append("\n".join(entity))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines) + "\n")
	return OK


func _brush_text(brush: Array) -> String:
	var out := PackedStringArray(["{"])
	for face: Dictionary in brush:
		out.append(_face_text(face))
	out.append("}")
	return "\n".join(out)


func _face_text(face: Dictionary) -> String:
	var n: Vector3 = face.n
	var t := Vector3.UP.cross(n)
	if t.length_squared() < 0.0001:
		t = Vector3.RIGHT
	t = t.normalized()
	var p1: Vector3 = face.p
	var p2 := p1 + t
	var p3 := p1 + t.cross(n)
	var u := t
	var v := -n.cross(u)
	var scale: float = TILE.get(face.tex, 4.0) * UNITS / 256.0
	return "( %s ) ( %s ) ( %s ) %s [ %s 0 ] [ %s 0 ] 0 %s %s" % [
		_v(_to_map(p1) * UNITS), _v(_to_map(p2) * UNITS), _v(_to_map(p3) * UNITS), face.tex,
		_v(_to_map(u)), _v(_to_map(v)), _n(scale), _n(scale)]


func _to_map(v: Vector3) -> Vector3:
	return Vector3(v.z, v.x, v.y)


func _v(v: Vector3) -> String:
	return "%s %s %s" % [_n(v.x), _n(v.y), _n(v.z)]


func _n(value: float) -> String:
	var rounded := snappedf(value, 0.0001)
	return str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)
