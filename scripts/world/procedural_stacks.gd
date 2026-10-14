class_name ProceduralStacks
extends Node3D

## The procedural Stacks, greybox (the user's new direction, 2026-10-14 --
## docs/CLIMB_VISION.md): a world built from a seed instead of the Terrain3D
## open world. Every number here is the user's.
##
## THE TOWERS: a 5x5 grid, each its own footprint (the Stack's widths x3:
## 330-600 m) and height (1-12 km), the gaps between neighbours all
## different (50-150 m). In the Stack's own concrete (painted windows
## outside, plain inside).
## THE HALLS, stacked up each tower, 150-440 m tall:
##   - their floors broken through: caved-in holes (1 in 3 floors, 15-40 m,
##     the rubble piled on the floor below) and small shafts (0-5, 25% each,
##     twice a player's size); a stairwell if nothing else gets you up;
##   - inside: stair runs and pillars (each hall one of three mixes: 2-4 /
##     4-10, 1-2 / 2-5, 4-6 / 8-16), floating rubble high in the middle and
##     top (5-8 chunks, 10-25 m, 30-50 m apart -- grapple between them up to
##     the way out), a short lift shaft (0-1, ~50 m, cables to climb, to a
##     ledge room with a window out), a rubble slope (1 in 4);
##   - SEALED (35%): no way up inside -- out a window, up the outside, in at
##     a window of the hall above. Outside, the obstacles are dense there
##     (about every 8 m) and sparse elsewhere (about every 40 m): pipes,
##     cables to the next tower, ledges and AC units, signs, broken bridge
##     stubs, and on sealed stretches floating rubble and rebar;
##   - windows: on the painted window grid, about 2.9 a hall (10% more than
##     the Stack), 60% with curtains or blinds, 25% with a balcony.
## THE PLATES: in each group of 4 towers, 1-3 concrete plates at random
##   heights -- 5 m thick, the middle square between the four corners and an
##   arm bridging each gap wall to wall, 20-30 m long -- where people climbed
##   out of their windows: doorways onto them, cold white street lamps
##   (sparse) hanging off the walls, 5-10 clothing lines across the arms,
##   and a trader on half of them (stand-ins: a stall and a figure).
## THE WIND: outside and in the air, from 4 km up, building to 4 m/s at
##   12 km, gusting to 7 (PlayerMovement.wind_at).
##
## Only the halls and plates near a player are built in full (and their
## collision); the rest of each tower is one plain box (in the same
## concrete), cut away round what's built. Rule 1 (co-op): the same seed
## builds the same world on every machine.

@export var world_seed: int = 1

const GRID := 5
const WIDTH := Vector2(330.0, 600.0)
const GAP := Vector2(50.0, 150.0)
const HEIGHT := Vector2(1000.0, 12000.0)
const HALL := Vector2(150.0, 440.0)
const WALL := StackBuilder.WALL
const SKIN := 0.5
const SLAB := StackBuilder.SLAB
const TEX := StackBuilder.TEX_METRES

const SEALED_CHANCE := 0.35
const CAVE_IN_CHANCE := 1.0 / 3.0
const CAVE_IN_SIZE := Vector2(15.0, 40.0)
const SHAFT_ROLLS := 5
const SHAFT_CHANCE := 0.25
const SHAFT_SIZE := 1.6
## (Mine, a guarantee: an open hall with no other way up gets one.)
const STAIRWELL_SIZE := 10.0
const RUBBLE_COUNT := Vector2i(5, 8)
const RUBBLE_SIZE := Vector2(10.0, 25.0)
const RUBBLE_GAP := Vector2(30.0, 50.0)
## Stairs, pillars: each hall one of these mixes.
const MIXES := [[Vector2i(2, 4), Vector2i(4, 10)], [Vector2i(1, 2), Vector2i(2, 5)], [Vector2i(4, 6), Vector2i(8, 16)]]
const LIFT_CHANCE := 0.5
const LIFT_HEIGHT := 50.0
const SLOPE_CHANCE := 0.25
const WINDOW_W := StackBuilder.WINDOW_WIDTH
const WINDOW_H := StackBuilder.WINDOW_TOP - StackBuilder.WINDOW_BOTTOM
const CURTAIN_CHANCE := 0.6
const BALCONY_CHANCE := 0.25
const OBSTACLE_STEP_SEALED := 8.0
const OBSTACLE_STEP_OPEN := 40.0

const PLATES := Vector2i(1, 3)
const PLATE_THICK := 5.0
const ARM_LENGTH := Vector2(20.0, 30.0)
const LINES := Vector2i(5, 10)
const TRADER_CHANCE := 0.5
const LAMP_SPACING := 60.0

const WIND_FROM := 4000.0
const WIND_TOP := 12000.0
const WIND_SPEED := 4.0
const WIND_GUST := 7.0

## Built in full within this far of a player (up and down / across), freed
## past it plus KEEP.
const BUILD_UP := 700.0
const BUILD_ACROSS := 1500.0
const KEEP := 300.0
## A frame's budget for building (ms).
const BUILD_BUDGET_MS := 8.0

const TEXTURES := {
	&"windows": "res://art/megastructures/stack_concrete.res",
	&"plain": "res://art/megastructures/stack_plain.res",
}

## The plan: towers {i, j, rect (x, z), height, halls: [Vector2(y, tall)]},
## plates {square: Rect2, arms: [{rect, faces: [[tower, side, u0, u1]]}], y}.
var towers: Array[Dictionary] = []
var plates: Array[Dictionary] = []

var _materials := {}
## The washing's colours (a few shared materials, not one a piece).
var _washing: Array[StandardMaterial3D] = []
var _built := {} # "h:t:k" or "p:i" -> Node3D
var _lod: Array[MeshInstance3D] = []
var _lod_range: Array[Vector2i] = [] # per tower: the halls built (lo..hi), or (-1, -1)
var _check_left := 0.0
var _queue: Array[String] = []


func _ready() -> void:
	_make_materials()
	_plan()
	_ground()
	for t in towers.size():
		var lod := MeshInstance3D.new()
		lod.name = "Tower_%d" % t
		add_child(lod)
		_lod.append(lod)
		_lod_range.append(Vector2i(-1, -1))
		_update_lod(t)
	PlayerMovement.wind_at = wind_at
	# The players start on the ground at the middle crossing.
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		player.global_position = spawn_point()
		player.spawn_position = player.global_position


func _exit_tree() -> void:
	if PlayerMovement.wind_at == wind_at:
		PlayerMovement.wind_at = Callable()


## Where a player should start: the ground at the crossing nearest the middle.
func spawn_point() -> Vector3:
	var at := Vector2.ZERO
	var nearest := INF
	for plate: Dictionary in plates:
		var centre := (plate.square as Rect2).get_center()
		if centre.length() < nearest:
			nearest = centre.length()
			at = centre
	return Vector3(at.x, 1.0, at.y)


# ---- The plan ----------------------------------------------------------------

func _rng(a: int, b: int, tag: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, a, b, tag])
	return rng


## The grid: each column and row its own cell size (WIDTH), the streets
## between them their own widths (GAP), each tower shrunk a little inside its
## cell at random so no two gaps match (but every gap stays in GAP).
func _plan() -> void:
	var rng := _rng(0, 0, "grid")
	var cell_x := []
	var cell_z := []
	var street_x := []
	var street_z := []
	for i in GRID:
		cell_x.append(rng.randf_range(WIDTH.x, WIDTH.y))
		cell_z.append(rng.randf_range(WIDTH.x, WIDTH.y))
	for i in GRID - 1:
		street_x.append(rng.randf_range(GAP.x, GAP.y))
		street_z.append(rng.randf_range(GAP.x, GAP.y))
	var x0 := [] # each column's cell start
	var z0 := []
	var total_x := 0.0
	var total_z := 0.0
	for i in GRID:
		total_x += cell_x[i] + (street_x[i] if i < GRID - 1 else 0.0)
		total_z += cell_z[i] + (street_z[i] if i < GRID - 1 else 0.0)
	var x := -total_x * 0.5
	var z := -total_z * 0.5
	for i in GRID:
		x0.append(x)
		z0.append(z)
		x += cell_x[i] + (street_x[i] if i < GRID - 1 else 0.0)
		z += cell_z[i] + (street_z[i] if i < GRID - 1 else 0.0)
	for j in GRID:
		for i in GRID:
			var t := towers.size()
			var r := _rng(t, 0, "tower")
			# Shrunk inside its cell, each side up to half what the street
			# could still grow before reaching GAP.y.
			# (Never below WIDTH.x: half the cell's spare width a side at most.)
			var spare_x: float = (cell_x[i] - WIDTH.x) * 0.5
			var spare_z: float = (cell_z[j] - WIDTH.x) * 0.5
			var room_l: float = minf((GAP.y - (street_x[i - 1] if i > 0 else GAP.y)) * 0.5, spare_x)
			var room_r: float = minf((GAP.y - (street_x[i] if i < GRID - 1 else GAP.y)) * 0.5, spare_x)
			var room_n: float = minf((GAP.y - (street_z[j - 1] if j > 0 else GAP.y)) * 0.5, spare_z)
			var room_s: float = minf((GAP.y - (street_z[j] if j < GRID - 1 else GAP.y)) * 0.5, spare_z)
			var l := r.randf_range(0.0, room_l)
			var rr := r.randf_range(0.0, room_r)
			var n := r.randf_range(0.0, room_n)
			var s := r.randf_range(0.0, room_s)
			var rect := Rect2(x0[i] + l, z0[j] + n, cell_x[i] - l - rr, cell_z[j] - n - s)
			var height := r.randf_range(HEIGHT.x, HEIGHT.y)
			var halls: Array[Vector2] = []
			var y := 0.0
			while y < height - 60.0:
				var tall := minf(r.randf_range(HALL.x, HALL.y), height - y)
				halls.append(Vector2(y, tall))
				y += tall
			towers.append({i = i, j = j, rect = rect, height = y, halls = halls})
	# The plates: one crossing between each group of 4.
	for j in GRID - 1:
		for i in GRID - 1:
			var nw: Dictionary = towers[j * GRID + i]
			var ne: Dictionary = towers[j * GRID + i + 1]
			var sw: Dictionary = towers[(j + 1) * GRID + i]
			var se: Dictionary = towers[(j + 1) * GRID + i + 1]
			var square := Rect2()
			square.position.x = minf((nw.rect as Rect2).end.x, (sw.rect as Rect2).end.x)
			square.end.x = maxf((ne.rect as Rect2).position.x, (se.rect as Rect2).position.x)
			square.position.y = maxf((nw.rect as Rect2).end.y, (ne.rect as Rect2).end.y)
			square.end.y = minf((sw.rect as Rect2).position.y, (se.rect as Rect2).position.y)
			var group := [nw, ne, sw, se]
			var lowest := INF
			for tower: Dictionary in group:
				lowest = minf(lowest, tower.height)
			var r := _rng(i, j, "plates")
			var heights: Array[float] = []
			for attempt in 20:
				if heights.size() >= r.randi_range(PLATES.x, PLATES.y):
					break
				var y := r.randf_range(150.0, lowest - 100.0)
				if heights.any(func(h: float) -> bool: return absf(h - y) < 60.0):
					continue
				heights.append(y)
			for y in heights:
				plates.append(_plan_plate(square, nw, ne, sw, se, y, r))


## A plate's arms: each bridging a gap wall to wall (touching both towers),
## ARM_LENGTH out from the square; and the walls they touch (doors go there).
func _plan_plate(square: Rect2, nw: Dictionary, ne: Dictionary, sw: Dictionary, se: Dictionary, y: float,
		r: RandomNumberGenerator) -> Dictionary:
	var arms: Array[Dictionary] = []
	var tn := towers.find(nw)
	var te := towers.find(ne)
	var ts := towers.find(sw)
	var tse := towers.find(se)
	# North arm: between nw (its +x side) and ne (its -x side), into row j.
	var length := r.randf_range(ARM_LENGTH.x, ARM_LENGTH.y)
	var a := Rect2((nw.rect as Rect2).end.x, square.position.y - length, (ne.rect as Rect2).position.x - (nw.rect as Rect2).end.x, length)
	arms.append({rect = a, faces = [[tn, 0, a.position.y, a.end.y], [te, 1, a.position.y, a.end.y]]})
	length = r.randf_range(ARM_LENGTH.x, ARM_LENGTH.y)
	a = Rect2((sw.rect as Rect2).end.x, square.end.y, (se.rect as Rect2).position.x - (sw.rect as Rect2).end.x, length)
	arms.append({rect = a, faces = [[ts, 0, a.position.y, a.end.y], [tse, 1, a.position.y, a.end.y]]})
	length = r.randf_range(ARM_LENGTH.x, ARM_LENGTH.y)
	a = Rect2(square.position.x - length, (nw.rect as Rect2).end.y, length, (sw.rect as Rect2).position.y - (nw.rect as Rect2).end.y)
	arms.append({rect = a, faces = [[tn, 2, a.position.x, a.end.x], [ts, 3, a.position.x, a.end.x]]})
	length = r.randf_range(ARM_LENGTH.x, ARM_LENGTH.y)
	a = Rect2(square.end.x, (ne.rect as Rect2).end.y, length, (se.rect as Rect2).position.y - (ne.rect as Rect2).end.y)
	arms.append({rect = a, faces = [[te, 2, a.position.x, a.end.x], [tse, 3, a.position.x, a.end.x]]})
	return {square = square, arms = arms, y = y}


## Whether a tower's hall is sealed (no way up inside). The top one has its
## roof; the ground floor never is.
func _sealed(t: int, k: int) -> bool:
	var halls: Array = towers[t].halls
	if k <= 0 or k >= halls.size() - 1:
		return k >= halls.size() - 1
	return _rng(t, k, "sealed").randf() < SEALED_CHANCE


## The holes in hall k's floor (Rect2s, x/z): caved-in, small shafts, or a
## stairwell -- none if the hall below is sealed.
func _floor_holes(t: int, k: int) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	if k <= 0 or _sealed(t, k - 1):
		return holes
	var inner := (towers[t].rect as Rect2).grow(-WALL - 20.0)
	var r := _rng(t, k, "holes")
	if r.randf() < CAVE_IN_CHANCE:
		var size := r.randf_range(CAVE_IN_SIZE.x, CAVE_IN_SIZE.y)
		holes.append({rect = _random_rect(r, inner, Vector2(size, size * r.randf_range(0.6, 1.0))), kind = &"cave_in"})
	for roll in SHAFT_ROLLS:
		if r.randf() < SHAFT_CHANCE:
			holes.append({rect = _random_rect(r, inner, Vector2(SHAFT_SIZE, SHAFT_SIZE)), kind = &"shaft"})
	if not holes.any(func(h: Dictionary) -> bool: return h.kind == &"cave_in"):
		holes.append({rect = _random_rect(r, inner, Vector2(STAIRWELL_SIZE, STAIRWELL_SIZE)), kind = &"stairwell"})
	return holes


static func _random_rect(r: RandomNumberGenerator, inside: Rect2, size: Vector2) -> Rect2:
	var x := r.randf_range(inside.position.x, maxf(inside.end.x - size.x, inside.position.x))
	var z := r.randf_range(inside.position.y, maxf(inside.end.y - size.y, inside.position.y))
	return Rect2(x, z, size.x, size.y)


# ---- Streaming -----------------------------------------------------------------

func _process(_delta: float) -> void:
	_check_left -= _delta
	if _check_left <= 0.0:
		_check_left = 0.25
		_update_wanted()
	var start := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - start < BUILD_BUDGET_MS * 1000.0:
		var key: String = _queue.pop_front()
		if _built.has(key):
			continue
		var node := _build(key)
		if node:
			_built[key] = node
			add_child(node)
			_lod_dirty(key)


func _players() -> Array[Vector3]:
	var at: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("player"):
		at.append((node as Node3D).global_position)
	return at


## What should be built (near a player) and what's gone too far.
func _update_wanted() -> void:
	var players := _players()
	if players.is_empty():
		return
	var wanted := {}
	var keep := {}
	for t in towers.size():
		var rect: Rect2 = towers[t].rect
		var halls: Array = towers[t].halls
		for p in players:
			var across := _rect_distance(rect, Vector2(p.x, p.z))
			if across > BUILD_ACROSS + KEEP:
				continue
			for k in halls.size():
				var h: Vector2 = halls[k]
				var up := maxf(h.x - p.y, p.y - (h.x + h.y))
				var key := "h:%d:%d" % [t, k]
				if across <= BUILD_ACROSS and up <= BUILD_UP:
					wanted[key] = maxf(across, up)
				if up <= BUILD_UP + KEEP:
					keep[key] = true
	for i in plates.size():
		var square: Rect2 = plates[i].square
		var y: float = plates[i].y
		for p in players:
			var across := _rect_distance(square, Vector2(p.x, p.z))
			var up := absf(p.y - y)
			var key := "p:%d" % i
			if across <= BUILD_ACROSS and up <= BUILD_UP:
				wanted[key] = maxf(across, up)
			if across <= BUILD_ACROSS + KEEP and up <= BUILD_UP + KEEP:
				keep[key] = true
	for key: String in _built.keys():
		if not keep.has(key):
			(_built[key] as Node).queue_free()
			_built.erase(key)
			_lod_dirty(key)
	var missing: Array = wanted.keys().filter(func(key: String) -> bool: return not _built.has(key))
	missing.sort_custom(func(a: String, b: String) -> bool: return wanted[a] < wanted[b])
	_queue.assign(missing)


static func _rect_distance(rect: Rect2, at: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - at.x, at.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - at.y, at.y - rect.end.y), 0.0)
	return Vector2(dx, dz).length()


func _build(key: String) -> Node3D:
	var parts := key.split(":")
	if parts[0] == "h":
		return _build_hall(int(parts[1]), int(parts[2]))
	return _build_plate(int(parts[1]))


## A tower's plain box (far off), cut away round the halls built.
func _lod_dirty(key: String) -> void:
	if not key.begins_with("h:"):
		return
	var t := int(key.split(":")[1])
	var lo := -1
	var hi := -1
	for k in towers[t].halls.size():
		if _built.has("h:%d:%d" % [t, k]):
			lo = k if lo < 0 else lo
			hi = k
	if Vector2i(lo, hi) != _lod_range[t]:
		_lod_range[t] = Vector2i(lo, hi)
		_update_lod(t)


func _update_lod(t: int) -> void:
	var tower: Dictionary = towers[t]
	var rect: Rect2 = tower.rect
	var halls: Array = tower.halls
	var boxes: Array[Dictionary] = []
	var span := _lod_range[t]
	var bottom := 0.0
	var top: float = tower.height
	if span.x >= 0:
		var cut_lo: float = (halls[span.x] as Vector2).x - SLAB
		var cut_hi: float = (halls[span.y] as Vector2).x + (halls[span.y] as Vector2).y + SLAB
		if cut_lo > bottom:
			boxes.append(_box_between(Vector3(rect.position.x, bottom, rect.position.y), Vector3(rect.end.x, cut_lo, rect.end.y), &"shell", false))
		if cut_hi < top:
			boxes.append(_box_between(Vector3(rect.position.x, cut_hi, rect.position.y), Vector3(rect.end.x, top, rect.end.y), &"shell", false))
	else:
		boxes.append(_box_between(Vector3(rect.position.x, bottom, rect.position.y), Vector3(rect.end.x, top, rect.end.y), &"shell", false))
	_lod[t].mesh = _mesh(boxes).get(&"shell") if not boxes.is_empty() else null
	if _lod[t].mesh:
		_lod[t].material_override = _materials[&"shell"]


# ---- A hall ------------------------------------------------------------------

## Hall k of tower t: its walls (window and door openings cut), its floor
## (holes cut), the roof if it's the top, and everything in it and on its
## outside walls.
func _build_hall(t: int, k: int) -> Node3D:
	var tower: Dictionary = towers[t]
	var rect: Rect2 = tower.rect
	var hall: Vector2 = tower.halls[k]
	var y0 := hall.x
	var tall := hall.y
	var r := _rng(t, k, "hall")
	var boxes: Array[Dictionary] = []
	var extras := Node3D.new() # lights, cloth: no collision
	var openings := _hall_openings(t, k, r)
	# Walls: 0 +x, 1 -x, 2 +z, 3 -z.
	for side in 4:
		_wall(boxes, rect, side, y0, y0 + tall, openings[side])
	# The floor (not the ground floor: that's the ground).
	if k > 0:
		var holes: Array[Rect2] = []
		for hole: Dictionary in _floor_holes(t, k):
			holes.append(hole.rect)
		for piece in _subtract(rect.grow(-WALL), holes):
			boxes.append(_box_between(Vector3(piece.position.x, y0 - SLAB, piece.position.y), Vector3(piece.end.x, y0, piece.end.y), &"plain", true))
	# The roof, on the top hall.
	if k == tower.halls.size() - 1:
		boxes.append(_box_between(Vector3(rect.position.x, y0 + tall, rect.position.y), Vector3(rect.end.x, y0 + tall + SLAB, rect.end.y), &"shell", true))
	var inner := rect.grow(-WALL)
	_cave_in_rubble(boxes, t, k, y0, r)
	var mix: Array = MIXES[r.randi() % MIXES.size()]
	_stairs(boxes, inner, y0, r, r.randi_range((mix[0] as Vector2i).x, (mix[0] as Vector2i).y))
	_pillars(boxes, inner, y0, tall, r, r.randi_range((mix[1] as Vector2i).x, (mix[1] as Vector2i).y))
	_floating_rubble(boxes, t, k, inner, y0, tall, r)
	if r.randf() < SLOPE_CHANCE:
		_rubble_slope(boxes, inner, y0, tall, r)
	if openings.has("lift"):
		var lift: Dictionary = openings.lift
		_lift(boxes, rect, lift.side, lift.along, y0)
	_window_details(boxes, extras, rect, openings, r)
	_outside(boxes, t, k, rect, y0, tall, r)
	var node := _chunk("Hall_%d_%d" % [t, k], boxes)
	node.add_child(extras)
	return node


## Every opening cut in hall k's four walls: windows on the painted grid
## (about 2.9 a hall), the ground floor's doors, doorways onto plates at
## their height, a window high up out of a sealed hall, one low in for the
## hall above a sealed one, and the lift's window. Each opening:
## {u0, u1, v0, v1, kind}, u along the wall (world along its face), v height.
func _hall_openings(t: int, k: int, r: RandomNumberGenerator) -> Dictionary:
	var tower: Dictionary = towers[t]
	var rect: Rect2 = tower.rect
	var hall: Vector2 = tower.halls[k]
	var y0 := hall.x
	var y1 := hall.x + hall.y
	var openings := {0: [], 1: [], 2: [], 3: []}
	var count := 2 + (1 if r.randf() < 0.66 else 0) + (1 if r.randf() < 0.2 else 0)
	for i in count:
		_add_window(openings, rect, r, r.randi() % 4, r.randf_range(y0 + 6.0, y1 - 12.0), &"window")
	if k == 0:
		for side in 4:
			var u := _side_mid(rect, side)
			(openings[side] as Array).append({u0 = u - 3.0, u1 = u + 3.0, v0 = y0, v1 = y0 + 8.0, kind = &"door"})
	if _sealed(t, k):
		_add_window(openings, rect, r, r.randi() % 4, r.randf_range(y1 - hall.y * 0.3, y1 - 12.0), &"exit")
	if k > 0 and _sealed(t, k - 1):
		_add_window(openings, rect, r, r.randi() % 4, r.randf_range(y0 + 6.0, minf(y0 + 30.0, y1 - 12.0)), &"entry")
	for plate: Dictionary in plates:
		var py: float = plate.y
		if py < y0 + 1.0 or py > y1 - 10.0:
			continue
		for arm: Dictionary in plate.arms:
			for face: Array in arm.faces:
				if face[0] != t:
					continue
				var mid: float = (face[2] + face[3]) * 0.5
				(openings[face[1]] as Array).append({u0 = mid - 2.5, u1 = mid + 2.5, v0 = py, v1 = py + 5.0, kind = &"plate_door"})
	if r.randf() < LIFT_CHANCE and hall.y > LIFT_HEIGHT + 20.0:
		var side := r.randi() % 4
		var along := r.randf_range(_side_start(rect, side) + WALL + 12.0, _side_end(rect, side) - WALL - 12.0)
		(openings[side] as Array).append({u0 = along - 1.5, u1 = along + 1.5, v0 = y0 + LIFT_HEIGHT, v1 = y0 + LIFT_HEIGHT + WINDOW_H, kind = &"lift"})
		openings["lift"] = {side = side, along = along}
	return openings


## A window on side `side` near height y, snapped onto the painted window grid.
func _add_window(openings: Dictionary, rect: Rect2, r: RandomNumberGenerator, side: int, y: float, kind: StringName) -> void:
	var along := r.randf_range(_side_start(rect, side) + WALL + 6.0, _side_end(rect, side) - WALL - 6.0)
	# The grid runs along the face's own texture direction.
	var across := _across(side)
	var world_along := along * (across.x + across.z) # +1 or -1 along x or z
	var snapped := StackBuilder._snap_to_window(world_along) * (across.x + across.z)
	var sill := StackBuilder._snap_sill(y)
	(openings[side] as Array).append({u0 = snapped - WINDOW_W * 0.5, u1 = snapped + WINDOW_W * 0.5, v0 = sill, v1 = sill + WINDOW_H, kind = kind})


## A side's span along the wall (x for +z/-z sides, z for +x/-x).
static func _side_start(rect: Rect2, side: int) -> float:
	return rect.position.y if side < 2 else rect.position.x


static func _side_end(rect: Rect2, side: int) -> float:
	return rect.end.y if side < 2 else rect.end.x


static func _side_mid(rect: Rect2, side: int) -> float:
	return (_side_start(rect, side) + _side_end(rect, side)) * 0.5


## The way the concrete's grid runs across each side (the mesher's u).
static func _across(side: int) -> Vector3:
	return [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT][side]


static func _outward(side: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][side]


## One wall: a painted outer skin and a plain inner layer, cut round its
## openings. The +x/-x walls run the whole side; +z/-z fit between them.
func _wall(boxes: Array[Dictionary], rect: Rect2, side: int, y0: float, y1: float, openings: Array) -> void:
	var u0 := _side_start(rect, side) + (WALL if side >= 2 else 0.0)
	var u1 := _side_end(rect, side) - (WALL if side >= 2 else 0.0)
	var holes: Array[Rect2] = []
	for o: Dictionary in openings:
		holes.append(Rect2(o.u0, o.v0, o.u1 - o.u0, o.v1 - o.v0))
	for layer in 2: # 0: the painted skin, 1: the plain inside
		var out_from := SKIN if layer == 0 else WALL
		var out_to := 0.0 if layer == 0 else SKIN
		for piece in _subtract(Rect2(u0, y0, u1 - u0, y1 - y0), holes):
			var a: Vector3
			var b: Vector3
			match side:
				0:
					a = Vector3(rect.end.x - out_from, piece.position.y, piece.position.x)
					b = Vector3(rect.end.x - out_to, piece.end.y, piece.end.x)
				1:
					a = Vector3(rect.position.x + out_to, piece.position.y, piece.position.x)
					b = Vector3(rect.position.x + out_from, piece.end.y, piece.end.x)
				2:
					a = Vector3(piece.position.x, piece.position.y, rect.end.y - out_from)
					b = Vector3(piece.end.x, piece.end.y, rect.end.y - out_to)
				_:
					a = Vector3(piece.position.x, piece.position.y, rect.position.y + out_to)
					b = Vector3(piece.end.x, piece.end.y, rect.position.y + out_from)
			boxes.append(_box_between(a, b, &"shell" if layer == 0 else &"plain", true))


## `whole` minus `holes`: rectangles covering the rest (strips between the
## holes' edges along x, each split round the holes that cross it).
static func _subtract(whole: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var cuts := [whole.position.x, whole.end.x]
	var inside: Array[Rect2] = []
	for hole in holes:
		var clipped := hole.intersection(whole)
		if clipped.size.x <= 0.01 or clipped.size.y <= 0.01:
			continue
		inside.append(clipped)
		cuts.append(clipped.position.x)
		cuts.append(clipped.end.x)
	cuts.sort()
	var pieces: Array[Rect2] = []
	for i in cuts.size() - 1:
		var x0: float = cuts[i]
		var x1: float = cuts[i + 1]
		if x1 - x0 < 0.01:
			continue
		var mid := (x0 + x1) * 0.5
		var spans := [[whole.position.y, whole.end.y]]
		for hole in inside:
			if mid < hole.position.x or mid > hole.end.x:
				continue
			var next := []
			for span: Array in spans:
				if hole.end.y <= span[0] or hole.position.y >= span[1]:
					next.append(span)
					continue
				if hole.position.y > span[0]:
					next.append([span[0], hole.position.y])
				if hole.end.y < span[1]:
					next.append([hole.end.y, span[1]])
			spans = next
		for span: Array in spans:
			if span[1] - span[0] > 0.01:
				pieces.append(Rect2(x0, span[0], x1 - x0, span[1] - span[0]))
	return pieces


## The rubble from a caved-in floor above, heaped on this hall's floor under
## the hole.
func _cave_in_rubble(boxes: Array[Dictionary], t: int, k: int, y0: float, r: RandomNumberGenerator) -> void:
	if k + 1 >= towers[t].halls.size():
		return
	for hole: Dictionary in _floor_holes(t, k + 1):
		if hole.kind != &"cave_in":
			continue
		var area: Rect2 = hole.rect
		for i in r.randi_range(8, 16):
			var size := Vector3(r.randf_range(2.0, 8.0), r.randf_range(1.0, 4.0), r.randf_range(2.0, 8.0))
			var at := Vector3(r.randf_range(area.position.x, area.end.x), y0 + size.y * 0.3, r.randf_range(area.position.y, area.end.y))
			boxes.append({c = at, s = size, b = _tumbled(r, 0.5), mat = &"rubble", collide = true})


## Stair runs up from the floor (35 degrees, 4 m wide) to a landing, some
## stopping in mid-air.
func _stairs(boxes: Array[Dictionary], inner: Rect2, y0: float, r: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var rise := r.randf_range(12.0, 40.0)
		var run := rise / tan(deg_to_rad(35.0))
		var heading := Vector3.FORWARD.rotated(Vector3.UP, r.randf() * TAU)
		var start := Vector3(r.randf_range(inner.position.x + run, inner.end.x - run), y0, r.randf_range(inner.position.y + run, inner.end.y - run))
		var top := start + heading * run + Vector3.UP * rise
		var length := start.distance_to(top)
		var basis := Basis.looking_at((top - start).normalized(), Vector3.UP)
		boxes.append({c = (start + top) * 0.5, s = Vector3(4.0, 0.6, length), b = basis, mat = &"plain", collide = true})
		if r.randf() < 0.7:
			boxes.append({c = top + heading * 3.0 - Vector3.UP * 0.5, s = Vector3(6.0, 1.0, 6.0), b = Basis(Vector3.UP, heading.signed_angle_to(Vector3.FORWARD, Vector3.UP)), mat = &"plain", collide = true})


## Pillars, floor to ceiling (some broken off short).
func _pillars(boxes: Array[Dictionary], inner: Rect2, y0: float, tall: float, r: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var width := r.randf_range(3.0, 6.0)
		var height := tall if r.randf() < 0.7 else tall * r.randf_range(0.2, 0.7)
		var at := Vector3(r.randf_range(inner.position.x + 10.0, inner.end.x - 10.0), y0 + height * 0.5, r.randf_range(inner.position.y + 10.0, inner.end.y - 10.0))
		boxes.append({c = at, s = Vector3(width, height, width), b = Basis.IDENTITY, mat = &"plain", collide = true})


## The floating rubble: 5-8 chunks high in the middle and top of the hall,
## each 30-50 m from the last, rising toward the way out (the biggest hole
## in the ceiling, or the sealed hall's high window side) -- grappled
## between to climb.
func _floating_rubble(boxes: Array[Dictionary], t: int, k: int, inner: Rect2, y0: float, tall: float,
		r: RandomNumberGenerator) -> void:
	var count := r.randi_range(RUBBLE_COUNT.x, RUBBLE_COUNT.y)
	var goal := Vector3(inner.get_center().x, y0 + tall - 25.0, inner.get_center().y)
	if k + 1 < towers[t].halls.size():
		var best := Rect2()
		for hole: Dictionary in _floor_holes(t, k + 1):
			if (hole.rect as Rect2).get_area() > best.get_area():
				best = hole.rect
		if best.get_area() > 0.0:
			goal = Vector3(best.get_center().x, y0 + tall - 25.0, best.get_center().y)
	# From the goal down, each step 30-50 m away and lower.
	var at := goal
	var chain: Array[Vector3] = []
	for i in count:
		chain.append(at)
		var gap := r.randf_range(RUBBLE_GAP.x, RUBBLE_GAP.y)
		var drop := gap * r.randf_range(0.5, 0.8)
		var flat := sqrt(maxf(gap * gap - drop * drop, 0.0))
		var way := Vector2.from_angle(r.randf() * TAU) * flat
		at = Vector3(clampf(at.x + way.x, inner.position.x + 20.0, inner.end.x - 20.0), at.y - drop,
				clampf(at.z + way.y, inner.position.y + 20.0, inner.end.y - 20.0))
		if at.y < y0 + tall * 0.25: # high in the hall only
			break
	for i in chain.size():
		var size := r.randf_range(RUBBLE_SIZE.x, RUBBLE_SIZE.y)
		boxes.append({c = chain[i], s = Vector3(size, size * r.randf_range(0.3, 0.6), size * r.randf_range(0.6, 1.0)),
				b = _tumbled(r, 0.6), mat = &"rubble", collide = true})


## A rubble slope: a tilted slab of collapsed floor from the floor up to a
## broken ledge on a wall.
func _rubble_slope(boxes: Array[Dictionary], inner: Rect2, y0: float, tall: float, r: RandomNumberGenerator) -> void:
	var rise := r.randf_range(40.0, minf(80.0, tall * 0.4))
	var run := rise / tan(deg_to_rad(30.0))
	var side := r.randi() % 4
	var out := _outward(side)
	var cross := Vector3(out.z, 0.0, -out.x)
	var wall_at := Vector3(inner.end.x if side == 0 else (inner.position.x if side == 1 else inner.get_center().x), 0.0,
			inner.end.y if side == 2 else (inner.position.y if side == 3 else inner.get_center().y))
	wall_at += cross * r.randf_range(-0.3, 0.3) * (inner.size.y if side < 2 else inner.size.x)
	var top := Vector3(wall_at.x, y0 + rise, wall_at.z) - out * 8.0
	var bottom := top - out * run - Vector3.UP * rise
	boxes.append({c = (top + bottom) * 0.5, s = Vector3(12.0, 2.0, top.distance_to(bottom)),
			b = Basis.looking_at((top - bottom).normalized(), Vector3.UP), mat = &"rubble", collide = true})
	boxes.append({c = top + out * 4.0 - Vector3.UP * 0.75, s = Vector3(16.0, 1.5, 8.0) if side >= 2 else Vector3(8.0, 1.5, 16.0),
			b = Basis.IDENTITY, mat = &"plain", collide = true})


## A short lift shaft (~50 m) against a wall, cables hanging in it, up to a
## ledge room by a window out.
func _lift(boxes: Array[Dictionary], rect: Rect2, side: int, along: float, y0: float) -> void:
	var out := _outward(side)
	var cross := Vector3(absf(out.z), 0.0, absf(out.x))
	var wall_in := Vector3(rect.end.x - WALL if side == 0 else (rect.position.x + WALL if side == 1 else 0.0), 0.0,
			rect.end.y - WALL if side == 2 else (rect.position.y + WALL if side == 3 else 0.0))
	var base := Vector3(along if side >= 2 else wall_in.x, y0, along if side < 2 else wall_in.z)
	var middle := base - out * 4.0
	var height := LIFT_HEIGHT
	# Three walls round it (the fourth is the tower's), a doorway at the bottom.
	for k in [-1.0, 1.0]:
		boxes.append({c = middle + cross * 3.25 * k + Vector3.UP * (height * 0.5), s = (cross * 0.5 + out.abs() * 8.0 + Vector3.UP * height),
				b = Basis.IDENTITY, mat = &"plain", collide = true})
	boxes.append({c = middle - out * 4.25 + Vector3.UP * (height * 0.5 + 4.0), s = (cross * 6.0 + out.abs() * 0.5 + Vector3.UP * (height - 8.0)),
			b = Basis.IDENTITY, mat = &"plain", collide = true})
	# The cables.
	for k in [-1.5, 0.0, 1.5]:
		boxes.append({c = middle + cross * k + Vector3.UP * (height * 0.5), s = Vector3(0.15, height, 0.15),
				b = Basis.IDENTITY, mat = &"metal", collide = true})
	# The ledge room at the top, by the window: a ledge either side of the
	# shaft's open top (the window's right over it).
	for k in [-1.0, 1.0]:
		boxes.append({c = middle + cross * 4.5 * k + Vector3.UP * (height - 0.5), s = cross * 3.0 + out.abs() * 8.0 + Vector3.UP * 1.0,
				b = Basis.IDENTITY, mat = &"plain", collide = true})


## Curtains or blinds (60%) inside the windows, balconies (25%) outside.
func _window_details(boxes: Array[Dictionary], extras: Node3D, rect: Rect2, openings: Dictionary, r: RandomNumberGenerator) -> void:
	for side in 4:
		var out := _outward(side)
		var cross := Vector3(absf(out.z), 0.0, absf(out.x))
		var face := (rect.end.x if side == 0 else rect.position.x) if side < 2 else (rect.end.y if side == 2 else rect.position.y)
		for o: Dictionary in openings[side]:
			if o.kind == &"door" or o.kind == &"plate_door":
				continue
			var mid: float = (o.u0 + o.u1) * 0.5
			var at := Vector3(face if side < 2 else mid, o.v0, mid if side < 2 else face)
			if r.randf() < CURTAIN_CHANCE:
				var cover := r.randf_range(0.4, 1.0)
				var blind := r.randf() < 0.5
				var cloth := MeshInstance3D.new()
				var quad := QuadMesh.new()
				quad.size = Vector2(WINDOW_W * (1.0 if blind else cover), WINDOW_H * (cover if blind else 1.0))
				cloth.mesh = quad
				cloth.material_override = _materials[&"blind" if blind else &"curtain"]
				extras.add_child(cloth)
				var inside := at - out * (WALL - 0.3)
				cloth.transform = Transform3D(Basis.looking_at(-out, Vector3.UP), # (the chunk's at the origin)
						inside + Vector3.UP * (WINDOW_H - quad.size.y * 0.5) + cross * (0.0 if blind else (WINDOW_W - quad.size.x) * 0.5 * (1.0 if r.randf() < 0.5 else -1.0)))
			if r.randf() < BALCONY_CHANCE:
				boxes.append({c = at + out * 0.8 + Vector3.UP * -0.2, s = cross * 4.0 + out.abs() * 1.6 + Vector3.UP * 0.4,
						b = Basis.IDENTITY, mat = &"plain", collide = true})
				boxes.append({c = at + out * 1.55 + Vector3.UP * 0.5, s = cross * 4.0 + out.abs() * 0.1 + Vector3.UP * 1.0,
						b = Basis.IDENTITY, mat = &"metal", collide = true})


## The outside of the hall: obstacles up its walls, every ~8 m on a sealed
## stretch (you're made to climb out there), ~40 m elsewhere.
func _outside(boxes: Array[Dictionary], t: int, k: int, rect: Rect2, y0: float, tall: float, r: RandomNumberGenerator) -> void:
	var sealed: bool = _sealed(t, k) and k < towers[t].halls.size() - 1
	var step := OBSTACLE_STEP_SEALED if sealed else OBSTACLE_STEP_OPEN
	var kinds := [&"pipe", &"cable", &"ledge", &"ac", &"sign", &"bridge"]
	if sealed:
		kinds.append_array([&"floating", &"floating", &"rebar"])
	for side in 4:
		var out := _outward(side)
		var cross := Vector3(absf(out.z), 0.0, absf(out.x))
		var face := (rect.end.x if side == 0 else rect.position.x) if side < 2 else (rect.end.y if side == 2 else rect.position.y)
		var y := y0 + r.randf_range(4.0, step)
		while y < y0 + tall - 4.0:
			var along := r.randf_range(_side_start(rect, side) + 8.0, _side_end(rect, side) - 8.0)
			var at := Vector3(face if side < 2 else along, y, along if side < 2 else face)
			_obstacle(boxes, t, side, at, out, cross, r, kinds[r.randi() % kinds.size()])
			y += step * r.randf_range(0.7, 1.3)


func _obstacle(boxes: Array[Dictionary], t: int, side: int, at: Vector3, out: Vector3, cross: Vector3,
		r: RandomNumberGenerator, kind: StringName) -> void:
	match kind:
		&"pipe":
			var length := r.randf_range(20.0, 60.0)
			boxes.append({c = at + out * 1.2 + Vector3.UP * length * 0.5, s = Vector3(1.5, length, 1.5), b = Basis.IDENTITY, mat = &"metal", collide = true})
		&"ledge":
			boxes.append({c = at + out * 0.75, s = cross * r.randf_range(4.0, 10.0) + out.abs() * 1.5 + Vector3.UP * 0.5, b = Basis.IDENTITY, mat = &"plain", collide = true})
		&"ac":
			boxes.append({c = at + out * 0.7, s = cross * 2.0 + out.abs() * 1.4 + Vector3.UP * 1.2, b = Basis.IDENTITY, mat = &"metal", collide = true})
		&"sign":
			boxes.append({c = at + out * 2.0, s = cross * 0.3 + out.abs() * 4.0 + Vector3.UP * 3.0, b = Basis.IDENTITY, mat = &"metal", collide = true})
		&"bridge":
			var reach := r.randf_range(8.0, 20.0)
			boxes.append({c = at + out * reach * 0.5, s = cross * 6.0 + out.abs() * reach + Vector3.UP * 1.5, b = Basis.IDENTITY, mat = &"plain", collide = true})
		&"floating":
			var size := r.randf_range(3.0, 8.0)
			boxes.append({c = at + out * r.randf_range(5.0, 15.0), s = Vector3(size, size * 0.6, size), b = _tumbled(r, 0.7), mat = &"rubble", collide = true})
		&"rebar":
			for i in r.randi_range(3, 6):
				var offset := cross * r.randf_range(-1.5, 1.5) + Vector3.UP * r.randf_range(-1.0, 1.0)
				boxes.append({c = at + offset + out * 1.5, s = cross * 0.1 + out.abs() * 3.0 + Vector3.UP * 0.1,
						b = Basis(cross.normalized(), r.randf_range(-0.4, 0.4)), mat = &"metal", collide = true})
		&"cable":
			# Straight across the street to the facing tower, if it's that tall.
			var other := _facing(t, side, at)
			if other.is_empty():
				return
			var to: Vector3 = other.at
			boxes.append({c = (at + to) * 0.5, s = cross * 0.12 + out.abs() * at.distance_to(to) + Vector3.UP * 0.12, b = Basis.IDENTITY, mat = &"metal", collide = true})


## The tower facing side `side` of tower t at `at`, and the point on its wall
## straight across (empty if there's none, or it's not that tall there).
func _facing(t: int, side: int, at: Vector3) -> Dictionary:
	var i: int = towers[t].i
	var j: int = towers[t].j
	var di: int = [1, -1, 0, 0][side]
	var dj: int = [0, 0, 1, -1][side]
	var ni: int = i + di
	var nj: int = j + dj
	if ni < 0 or nj < 0 or ni >= GRID or nj >= GRID:
		return {}
	var other: Dictionary = towers[nj * GRID + ni]
	var rect: Rect2 = other.rect
	if at.y > other.height - 5.0:
		return {}
	match side:
		0:
			if at.z < rect.position.y or at.z > rect.end.y:
				return {}
			return {at = Vector3(rect.position.x, at.y, at.z)}
		1:
			if at.z < rect.position.y or at.z > rect.end.y:
				return {}
			return {at = Vector3(rect.end.x, at.y, at.z)}
		2:
			if at.x < rect.position.x or at.x > rect.end.x:
				return {}
			return {at = Vector3(at.x, at.y, rect.position.y)}
		_:
			if at.x < rect.position.x or at.x > rect.end.x:
				return {}
			return {at = Vector3(at.x, at.y, rect.end.y)}


static func _tumbled(r: RandomNumberGenerator, amount: float) -> Basis:
	return Basis.from_euler(Vector3(r.randf_range(-amount, amount), r.randf() * TAU, r.randf_range(-amount, amount)))


# ---- A plate -------------------------------------------------------------------

## A plate: the square and its four arms (5 m thick, top at y), cold white
## lamps hanging off the walls over the arms, clothing lines across the
## arms, and maybe a trader.
func _build_plate(index: int) -> Node3D:
	var plate: Dictionary = plates[index]
	var y: float = plate.y
	var r := _rng(index, 0, "plate")
	var boxes: Array[Dictionary] = []
	var extras := Node3D.new()
	var square: Rect2 = plate.square
	boxes.append(_box_between(Vector3(square.position.x, y - PLATE_THICK, square.position.y), Vector3(square.end.x, y, square.end.y), &"plain", true))
	for arm: Dictionary in plate.arms:
		var a: Rect2 = arm.rect
		boxes.append(_box_between(Vector3(a.position.x, y - PLATE_THICK, a.position.y), Vector3(a.end.x, y, a.end.y), &"plain", true))
		# A lamp over each doorway (sparse: one a wall, LAMP_SPACING apart at most).
		for face: Array in arm.faces:
			var side: int = face[1]
			var tower: Dictionary = towers[face[0]]
			var rect: Rect2 = tower.rect
			var wall := (rect.end.x if side == 0 else rect.position.x) if side < 2 else (rect.end.y if side == 2 else rect.position.y)
			var mid: float = (face[2] + face[3]) * 0.5
			var out := _outward(side)
			var lamp_at := Vector3(wall if side < 2 else mid, y + 9.0, mid if side < 2 else wall) + out * 2.0
			boxes.append({c = lamp_at - out * 1.0, s = out.abs() * 2.0 + Vector3(0.2, 0.2, 0.2), b = Basis.IDENTITY, mat = &"metal", collide = false})
			_lamp(extras, lamp_at)
	_clothes(boxes, extras, plate, y, r)
	if r.randf() < TRADER_CHANCE:
		_trader(boxes, extras, square, y, r)
	var node := _chunk("Plate_%d" % index, boxes)
	node.add_child(extras)
	return node


## A cold white street lamp, glowing through the fog.
func _lamp(extras: Node3D, at: Vector3) -> void:
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	bulb.mesh = sphere
	bulb.material_override = _materials[&"bulb"]
	bulb.position = at
	extras.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.9, 1.0)
	light.light_energy = 2.5
	light.omni_range = 30.0
	light.position = at
	extras.add_child(light)


## Clothing lines across the arms, wall to wall, shirts and pants hanging off
## them (stand-ins: flat cloth shapes).
func _clothes(boxes: Array[Dictionary], extras: Node3D, plate: Dictionary, y: float, r: RandomNumberGenerator) -> void:
	var count := r.randi_range(LINES.x, LINES.y)
	for i in count:
		var arm: Dictionary = plate.arms[r.randi() % plate.arms.size()]
		var a: Rect2 = arm.rect
		var face: Array = arm.faces[0]
		var across_x: bool = face[1] < 2 # the arm's walls are the towers' x sides: the line runs along x
		var height := y + r.randf_range(4.0, 12.0)
		var along := r.randf_range(a.position.y, a.end.y) if across_x else r.randf_range(a.position.x, a.end.x)
		var from := Vector3(a.position.x, height, along) if across_x else Vector3(along, height, a.position.y)
		var to := Vector3(a.end.x, height, along) if across_x else Vector3(along, height, a.end.y)
		var length := from.distance_to(to)
		var dir := (to - from) / maxf(length, 0.01)
		boxes.append({c = (from + to) * 0.5, s = (Vector3(length, 0.05, 0.05) if across_x else Vector3(0.05, 0.05, length)),
				b = Basis.IDENTITY, mat = &"metal", collide = false})
		var spot := r.randf_range(1.0, 3.0)
		while spot < length - 1.0:
			var shirt := r.randf() < 0.6
			var piece := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.7, 0.75) if shirt else Vector2(0.45, 1.0)
			piece.mesh = quad
			piece.material_override = _washing[r.randi() % _washing.size()]
			piece.position = from + dir * spot - Vector3.UP * (quad.size.y * 0.5 + 0.05)
			piece.rotation.y = 0.0 if across_x else PI * 0.5
			extras.add_child(piece)
			spot += r.randf_range(0.9, 2.2)


## A trader (stand-in): a stall -- a table, a lamp -- and a figure behind it.
func _trader(boxes: Array[Dictionary], extras: Node3D, square: Rect2, y: float, r: RandomNumberGenerator) -> void:
	var at := Vector3(r.randf_range(square.position.x + 6.0, square.end.x - 6.0), y, r.randf_range(square.position.y + 6.0, square.end.y - 6.0))
	var facing := r.randf() * TAU
	var turn := Basis(Vector3.UP, facing)
	boxes.append({c = at + Vector3.UP * 0.5, s = Vector3(3.0, 1.0, 1.4), b = turn, mat = &"wood", collide = true})
	boxes.append({c = at + Vector3.UP * 2.6 + turn * Vector3(0.0, 0.0, 0.7), s = Vector3(3.6, 0.1, 2.6), b = turn, mat = &"cloth", collide = false})
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.5
	lamp.omni_range = 8.0
	lamp.position = at + Vector3.UP * 2.3
	extras.add_child(lamp)
	var characters := PlayerModel.available_characters()
	if characters.is_empty():
		return
	var scene := load(characters[r.randi() % characters.size()]) as PackedScene
	if scene == null:
		return
	var figure := scene.instantiate() as Node3D
	extras.add_child(figure)
	figure.position = at + turn * Vector3(0.0, 0.0, 1.3)
	figure.rotation.y = facing + PI
	for player in figure.find_children("*", "AnimationPlayer", true, false):
		for name in (player as AnimationPlayer).get_animation_list():
			if String(name).to_lower().contains("idle"):
				(player as AnimationPlayer).play(name)
				break


# ---- The ground ------------------------------------------------------------------

func _ground() -> void:
	var span := Rect2()
	for i in towers.size():
		span = (towers[i].rect as Rect2) if i == 0 else span.merge(towers[i].rect)
	span = span.grow(300.0)
	add_child(_chunk("Ground", [_box_between(Vector3(span.position.x, -4.0, span.position.y), Vector3(span.end.x, 0.0, span.end.y), &"plain", true)]))


# ---- The wind ------------------------------------------------------------------

## The wind at `at` (m/s): none inside a tower or below WIND_FROM; above it,
## building to WIND_SPEED at WIND_TOP, gusting up to WIND_GUST.
func wind_at(at: Vector3) -> Vector3:
	if at.y < WIND_FROM:
		return Vector3.ZERO
	for tower: Dictionary in towers:
		if (tower.rect as Rect2).has_point(Vector2(at.x, at.z)) and at.y < tower.height:
			return Vector3.ZERO
	var high := clampf(inverse_lerp(WIND_FROM, WIND_TOP, at.y), 0.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	var gust := maxf(sin(t * 0.37) * 0.6 + sin(t * 1.13 + 1.7) * 0.4, 0.0) # 0..1, comes and goes
	var speed := lerpf(WIND_SPEED, WIND_GUST, gust) * high
	var way := Vector3.RIGHT.rotated(Vector3.UP, 0.6 + sin(t * 0.05) * 0.4) # a prevailing wind, wandering slowly
	return way * speed


# ---- Building blocks ---------------------------------------------------------------

func _box_between(a: Vector3, b: Vector3, mat: StringName, collide: bool) -> Dictionary:
	return {c = (a + b) * 0.5, s = (b - a).abs(), b = Basis.IDENTITY, mat = mat, collide = collide}


## A chunk: its boxes as one mesh per material, and their collision.
func _chunk(name: String, boxes: Array[Dictionary]) -> Node3D:
	var node := Node3D.new()
	node.name = name
	var meshes := _mesh(boxes)
	for mat: StringName in meshes:
		var shown := MeshInstance3D.new()
		shown.mesh = meshes[mat]
		shown.material_override = _materials.get(mat, _materials[&"plain"])
		node.add_child(shown)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for b: Dictionary in boxes:
		if not b.collide:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.s
		shape.shape = box
		shape.transform = Transform3D(b.b, b.c)
		body.add_child(shape)
	node.add_child(body)
	return node


## The boxes as one mesh per material, the concrete laid on the Stack's one
## world grid (StackBuilder._box_faces: the painted windows line up).
func _mesh(boxes: Array[Dictionary]) -> Dictionary:
	var tools := {}
	for b in boxes:
		var mat: StringName = b.mat
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		_box_faces(tools[mat], b)
	var meshes := {}
	for mat: StringName in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		meshes[mat] = st.commit()
	return meshes


static func _box_faces(st: SurfaceTool, b: Dictionary) -> void:
	var basis: Basis = b.b
	var half: Vector3 = (b.s as Vector3) * 0.5
	var centre: Vector3 = b.c
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
		var points: Array[Vector3] = []
		for corner: Vector3 in corners:
			points.append(centre + basis * (n * nh + corner))
		var world_n := basis * n
		var world_u := (basis * u).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			var at: Vector3 = points[i]
			var uv := Vector2(at.x, at.z) if absf(world_n.y) > 0.7 else Vector2(at.dot(world_u), -at.y)
			st.set_uv(uv / TEX)
			st.add_vertex(at)


func _make_materials() -> void:
	var windows := load(TEXTURES[&"windows"]) as Texture2D if ResourceLoader.exists(TEXTURES[&"windows"]) else null
	var plain := load(TEXTURES[&"plain"]) as Texture2D if ResourceLoader.exists(TEXTURES[&"plain"]) else null
	var shell := StandardMaterial3D.new()
	shell.albedo_texture = windows
	shell.albedo_color = Color(0.82, 0.8, 0.78)
	shell.roughness = 1.0
	shell.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	shell.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_materials[&"shell"] = shell
	for key in [&"plain", &"rubble"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = plain
		m.albedo_color = Color(0.66, 0.65, 0.61) if key == &"plain" else Color(0.55, 0.53, 0.5)
		m.roughness = 1.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_materials[key] = m
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.24, 0.2, 0.17)
	metal.roughness = 0.7
	metal.metallic = 0.5
	_materials[&"metal"] = metal
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.25, 0.16)
	wood.roughness = 1.0
	_materials[&"wood"] = wood
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.2, 0.18)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[&"cloth"] = cloth
	var curtain := StandardMaterial3D.new()
	curtain.albedo_color = Color(0.55, 0.42, 0.3)
	curtain.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_materials[&"curtain"] = curtain
	var blind := StandardMaterial3D.new()
	blind.albedo_color = Color(0.7, 0.68, 0.6)
	blind.cull_mode = BaseMaterial3D.CULL_DISABLED
	blind.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_materials[&"blind"] = blind
	var bulb := StandardMaterial3D.new()
	bulb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.albedo_color = Color(0.9, 0.95, 1.0)
	_materials[&"bulb"] = bulb
	var palette := _rng(0, 0, "washing")
	for i in 10:
		var wash := StandardMaterial3D.new()
		wash.albedo_color = Color.from_hsv(palette.randf(), palette.randf_range(0.15, 0.5), palette.randf_range(0.35, 0.75))
		wash.cull_mode = BaseMaterial3D.CULL_DISABLED
		wash.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_washing.append(wash)
