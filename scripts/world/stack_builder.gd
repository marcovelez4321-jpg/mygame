class_name StackBuilder
extends RefCounted

## The Stack (docs/WORLD.md -- every detail the user's choice, Rules 9-10):
## seven brutalist towers, the tallest 5 km, tangled by skybridges, overgrown the
## whole way up, windows lit and blinkers climbing it, swarms circling the
## tops, a colossal worm coiling up one tower. Built for something far bigger
## than a person, and you can get into it at every height:
##   LOW: grapple to the lowest skybridge; climb the collapsed block's rubble
##   into a torn-open wall; walk into the sewer outfall's culvert, down to
##   the flooded depths; or climb in through any lit apartment window.
##   MID (~1.1 km): the lift's loading dock with its half-open door, and the
##   hive tunnel off a ledge of hive spires.
##   HIGH (~3.5 km, above the clouds): the cable car from the next tower's
##   hall, and the broken bridge you grapple across.
##   CROWN (~4.8 km): the lift's summit station, and the hangar open to the sky.
## Inside: cavernous brutalist halls at several heights in every tower --
## mezzanines up walkable ramps, leaning columns, stepped pyramids hanging
## from the ceilings, stairs that stop in mid-air -- hollow skybridges
## between halls, the main tower's shaft running the whole height with
## platforms across it (a slip is a drop, not the bottom), and its base:
## ten 40 m floors of apartment blocks round the shaft, down to the flooded
## depths. The express lift joins base, mid and the high hall (60% up).
## The hive (tower 5, 4.5 km): dark, stained, bitten into and bursting with
## growth, its eight halls a panic-built tangle of stairs. The stump (tower
## 6): 600 m, fused to the main tower's -X side, its top torn open and broken
## through into the main tower's 440 m hall. Cobwebs in a few corners, in
## and out, each with its spiders.
##
## Laid out as boxes (seeded, the same every build): towers stacked from
## blocks, then spaces CARVED out of them (halls, rooms, corridors, the
## shaft), then everything inside and on them added. Made into:
##   scenes/megastructures/the_stack.scn -- a Megastructure scene;
##   maps/megastructures/the_stack.map -- the same boxes for TrenchBroom
##   (8 units a metre), to edit by hand from now on.
## tools/make_the_stack.gd runs it.

const SEED := 5000
const TEX_METRES := 8.0 # one texture tile every 8 m
## The windows painted on the concrete (make_concrete): one a tile, 3 m wide,
## centred 4 m into each 8 m along a wall, from 2.25 m to 6 m up each 8 m.
## The texture's laid on one grid for the whole Stack (_box_faces), so they
## line up everywhere -- and the real windows (lit, or a room behind) sit
## exactly on painted ones.
const WINDOW_WIDTH := 3.0
const WINDOW_BOTTOM := 2.25
const WINDOW_TOP := 6.0
const MAP_UNITS := 8.0 # TrenchBroom units a metre (megastructure maps)
const TOWERS := [ # x, z, footprint (m), height (m)
	[0.0, 0.0, 200.0, 5000.0],
	[260.0, 60.0, 140.0, 3600.0],
	[-200.0, 190.0, 150.0, 2800.0],
	[80.0, -270.0, 120.0, 2000.0],
	[-250.0, -170.0, 110.0, 1400.0],
	[320.0, -240.0, 180.0, 4500.0], # the hive, between towers 1 and 3
	[-160.0, 0.0, 120.0, 600.0], # the stump, fused to the main tower's -X side
]
## The hive tower and the stump (the user's): which TOWERS they are.
const HIVE := 5
const STUMP := 6
## The hive: its two window rooms (its only windows), how much more growth
## its insides have than other halls', its bites and holes.
const HIVE_WINDOWS := 2
const HIVE_GROWTH := 3.0
const HIVE_BITES := 4 # a block
const HIVE_HOLES := 3 # a hall
## Its halls' panic stairs: flights in all (no dead ends), the air above
## PANIC_HEIGHT of the hall left open for the grapple.
const PANIC_FLIGHTS := 30
const PANIC_HEIGHT := 0.6
const PANIC_WIDTH := 6.0
## Cobwebs: one for about every two halls inside, two outside a tower;
## this many of the inside ones huge.
const WEB_HUGE_CHANCE := 0.15
const WEBS_OUTSIDE := 2
const COBWEBS := [
	"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Decals/cobweb_1_cobweb_1.png",
	"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Decals/cobweb_2_cobweb_2.png",
	"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Decals/cobweb_4_cobweb_4.png",
	"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Decals/cobweb_5_cobweb_5.png",
]
## Every tower's halls: [bottom, top] heights. The main tower's base (0-400)
## is its own thing (the apartment floors), not in this list.
## The user likes the halls best: they take up much of every tower. The
## first two of each are the ones things join onto (the main tower's: mid,
## high, crown; towers 1 and 3's mid halls share its floor, 900 m, for the
## hollow bridges; the main tower's high hall (3000 m, where the lift tops out)
## and tower 1's (3300 m) are both open at 3306 m, for the broken bridge and
## the cable car).
const HALLS := [
	[[900.0, 1400.0], [3000.0, 3400.0], [4650.0, 4960.0], [1900.0, 2400.0], [440.0, 600.0]],
	[[900.0, 1350.0], [3300.0, 3560.0], [1950.0, 2400.0]],
	[[950.0, 1400.0], [2350.0, 2720.0], [1650.0, 2000.0]],
	[[900.0, 1350.0], [1650.0, 1930.0], [300.0, 600.0]],
	[[200.0, 560.0], [950.0, 1340.0]],
	[[250.0, 560.0], [780.0, 1100.0], [1320.0, 1640.0], [1860.0, 2180.0],
			[2400.0, 2720.0], [2940.0, 3260.0], [3480.0, 3800.0], [4000.0, 4300.0]],
	[[440.0, 600.0]], # the stump's: open to the sky, broken into the main tower's 440 m hall
]
## Barnacles (the user's: more the higher you go): a spot's chance of a nest
## is this many times higher at the top of the tallest tower than at the
## bottom; the outside walls get OUTSIDE_NESTS, thickening the same way up
## every tower.
const NEST_TOP_DENSITY := 3.0
const OUTSIDE_NESTS := 30
## Human gangs camped in the main tower (the user's; the other towers, for
## now, have none): on the floor of about one hall in three, and up on some
## mezzanines.
const GANG_HALL_CHANCE := 1.0 / 3.0
const GANG_DECK_CHANCE := 0.15
const FLOOR := 40.0 # the base's storeys
const SLAB := 4.0
const WALL := 6.0
const HALL_WALL := 10.0 # the least wall left round a hall
const INTERIOR_TOP := 400.0 # the main tower's base: 10 storeys
const SHAFT := 60.0 # the base's shaft
const UPPER_SHAFT := 30.0 # the shaft above the base
const SHAFT_BOTTOM := -240.0
const DEPTHS_FLOOR := -293.0
const DEPTHS_SIZE := 320.0
const WATER_LEVEL := -290.0
const ENTRANCE_UNDERSIDE := 28.0 # within the grapple's 35 m from the ground
const RAMP_SLOPE := 28.0 # degrees: every ramp you walk up
## The lift's stops: the base (its -Z storey-1 dock), the mid hall, and the
## high hall, 60% of the way up the main tower (the user's call). The crown
## is beyond it: on foot and by grapple.
const LIFT_STOPS := [40.0, 900.0, 3000.0]
## The express lift (the user's, 2026-10-17: out for now -- it ran through
## some skybridges). Its docks stay; the car, its call buttons and cable go.
const LIFT_ENABLED := false
## Each hall's window rooms: two, and a third this often (2.6 a hall on
## average: 30% more than two, the user's). The hive keeps its own two.
const WINDOW_THIRD_CHANCE := 0.6
## How often a window room has an old radio left playing in it (the user's).
const RADIO_CHANCE := 0.5
## Skybridges keep this far off anything carved, the windows' fronts, the
## lift's way and the high crossings.
const BRIDGE_MARGIN := 4.0

## Every box: {c: centre, s: size, b: Basis, part: &"shell" or &"interior",
## solid: a tower block (carved, an occluder), tower: index or -1,
## group: which mesh it joins, mat: &"concrete" (windowed), &"plain",
## &"rubble", &"clay" or &"metal"}.
var boxes: Array[Dictionary] = []
## The towers' blocks before anything was carved (windows and growth go on
## their outsides).
var blocks: Array[Dictionary] = []
## Everything carved out (nothing outside goes in these).
var carved: Array[AABB] = []
## Openings to the outside (the wind howls through them).
var openings := PackedVector3Array()
## Each hall: {tower, box: AABB, name}.
var halls: Array[Dictionary] = []
## Each lit apartment window: {at, normal, size, room: AABB}.
var window_rooms: Array[Dictionary] = []
## Lamps: [position, colour, energy, range].
var lamps: Array = []
## Where the ground must be holed (local AABBs): the shaft, the outfall's mouth.
var terrain_holes: Array[AABB] = []
## The lift's stops (local) and the cable car's.
var lift_stops := PackedVector3Array()
var cable_stops := PackedVector3Array()
var lift_face := 0.0
## Where each lift stop's call button stands (local).
var lift_buttons := PackedVector3Array()
## Spots near every entrance (floor level): eyeball clusters gather there.
var entrance_spots := PackedVector3Array()
## Spots on floors and mezzanines inside where a barnacle nest may grow.
var nest_spots := PackedVector3Array()
## Where human gangs camp (Megastructure.gang_spots): x, y, z on a floor,
## w how far round it they wander.
var gang_spots := PackedVector4Array()
## Floors the sewer growths grow on inside: {rect (x/z), y, zone, kinds
## (Kind -> weight), density, shaft (keep its middle clear)}.
var growth_floors: Array[Dictionary] = []
## Skybridges waiting to be placed once everything else is (_place_sky_bridges).
var sky_bridges: Array[Dictionary] = []
## Round the broken bridge and the cable car: no skybridge through them.
var crossing_clear := AABB()
## The radios left in window rooms: [place on its floor, facing].
var radio_spots: Array = []
## Each lift landing: the walkway from the lift to the tower's opening and
## the air over it -- no skybridge across them.
var lift_landings: Array[AABB] = []
## What happened to the skybridges: placed where drawn, moved, or dropped.
var bridge_report := {placed = 0, moved = 0, dropped = 0}
## The holes punched through the hive's walls: {at (on the face), normal, size}.
var hive_holes: Array[Dictionary] = []
## Cobwebs: how each is drawn ({xform, variant, indoors}) and its spiders
## ({at: the floor by it, size: its width, indoors, radius: their patrol}).
var web_quads: Array[Dictionary] = []
var web_nests: Array[Dictionary] = []
## Each hive hall's tangle: {hall, landings, flights, dead_ends} (none, ever).
var panic_report: Array[Dictionary] = []
## Every mezzanine deck: {hall, side (its wall), y, span (along the wall)}.
var decks: Array[Dictionary] = []
## The secrets (_secrets()): each door {kind, lock, hinge: Transform3D,
## panel (a box like the wall, for a button door), mat, model, button:
## Transform3D (a button door's), button_model}; the grown-on blocks, the
## loot rooms, where keys may lie and where a dead climber may be.
var secrets: Array[Dictionary] = []
var secret_blocks: Array[AABB] = []
var secret_rooms: Array[AABB] = []
var key_spots := PackedVector3Array()
var climber_spots := PackedVector3Array()
var secret_report := {loot = 0, shortcut = 0, entrance = 0, tries = 0, no_deck = 0, bottom = 0, top = 0, fits = 0}
## What barnacles grow on inside (Megastructure.inner_nest_*): pillars, stair
## steps and ramps in the halls, and the shortcut shafts' insides.
var nest_objects: Array[AABB] = []
var secret_shafts: Array[AABB] = []
## What grows indoors: the sewer kinds that would, by where they are.
const HALL_GROWTH := {
	GrowthMeshes.Kind.HAIR_MOLD: 3.0, GrowthMeshes.Kind.EGG_SACS: 2.0, GrowthMeshes.Kind.FUNGUS_SHELF: 2.0,
	GrowthMeshes.Kind.LARVAE_PILE: 2.0, GrowthMeshes.Kind.FLESH_TENDRILS: 1.5, GrowthMeshes.Kind.COCOON: 1.5,
	GrowthMeshes.Kind.PUS_BOILS: 1.5, GrowthMeshes.Kind.SLIME_CAPS: 1.0, GrowthMeshes.Kind.BLACK_VINES: 2.0,
}
## The base: damper, closer to the depths -- more slime and boils.
const BASE_GROWTH := {
	GrowthMeshes.Kind.HAIR_MOLD: 3.0, GrowthMeshes.Kind.SLIME_CAPS: 2.5, GrowthMeshes.Kind.PUS_BOILS: 2.0,
	GrowthMeshes.Kind.EGG_SACS: 1.5, GrowthMeshes.Kind.FUNGUS_SHELF: 1.5, GrowthMeshes.Kind.LARVAE_PILE: 1.5,
	GrowthMeshes.Kind.BLACK_VINES: 2.0, GrowthMeshes.Kind.FLESH_TENDRILS: 1.0,
}
## A window room: a little of the quieter ones.
const ROOM_GROWTH := {
	GrowthMeshes.Kind.HAIR_MOLD: 3.0, GrowthMeshes.Kind.FUNGUS_SHELF: 1.5, GrowthMeshes.Kind.EGG_SACS: 1.0,
	GrowthMeshes.Kind.COCOON: 1.0,
}

var random := RandomNumberGenerator.new()


## `build` false: an empty builder (no Stack built) -- for borrowing its hall
## generator (ProceduralStacks: the original halls, the user's).
func _init(build: bool = true) -> void:
	random.seed = SEED
	if not build:
		return
	for t in TOWERS.size():
		if t == STUMP:
			_stump_blocks()
		else:
			_solid_tower(t, INTERIOR_TOP if t == 0 else 0.0)
	_base()
	_depths()
	_bridges()
	# Spaces carved out of the towers.
	_main_shaft()
	for t in TOWERS.size():
		for range_ in HALLS[t]:
			_hall(t, range_[0], range_[1])
	_stump_top()
	_window_rooms()
	_hive_bites()
	_hollow_bridges()
	# Entrances.
	_lift()
	_collapsed_block()
	_outfall()
	_hive_tunnel()
	_high_crossings()
	_crown_hangar()
	# What's inside the halls.
	for hall in halls:
		_hall_features(hall)
	_shaft_platforms()
	_cobwebs()
	_secrets()
	# The heart's cathedral on the hive (its own dice: nothing above moves).
	_cathedral()
	# Last, round everything else: the skybridges.
	_place_sky_bridges()
	blocks.append_array(cathedral_blocks)


# ---- Boxes and carving --------------------------------------------------------

func _add(c: Vector3, s: Vector3, part: StringName, group: String, mat: StringName = &"plain",
		basis: Basis = Basis.IDENTITY, solid: bool = false, tower: int = -1) -> void:
	if part == &"shell" and basis == Basis.IDENTITY and absf(c.y - s.y * 0.5) < 0.01:
		# Standing on the ground: sunk 3 m into it, so no gap shows on a slope.
		s.y += 3.0
		c.y -= 1.5
	boxes.append({c = c, s = s, b = basis, part = part, solid = solid, tower = tower, group = group, mat = mat})


## Cuts `space` out of every tower block it touches (each block becomes the
## pieces of it left round the space).
func _carve(space: AABB) -> void:
	carved.append(space)
	var kept: Array[Dictionary] = []
	for b in boxes:
		if not b.solid:
			kept.append(b)
			continue
		var own := AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s)
		if not own.intersects(space):
			kept.append(b)
			continue
		for piece in _subtract(own, space):
			if piece.size.x > 0.05 and piece.size.y > 0.05 and piece.size.z > 0.05:
				var copy: Dictionary = b.duplicate()
				copy.c = piece.get_center()
				copy.s = piece.size
				kept.append(copy)
	boxes = kept


## `a` with `b` taken out: up to six boxes.
func _subtract(a: AABB, b: AABB) -> Array[AABB]:
	var i := a.intersection(b)
	var out: Array[AABB] = []
	if i.position.y > a.position.y:
		out.append(AABB(a.position, Vector3(a.size.x, i.position.y - a.position.y, a.size.z)))
	if i.end.y < a.end.y:
		out.append(AABB(Vector3(a.position.x, i.end.y, a.position.z), Vector3(a.size.x, a.end.y - i.end.y, a.size.z)))
	if i.position.x > a.position.x:
		out.append(AABB(Vector3(a.position.x, i.position.y, a.position.z), Vector3(i.position.x - a.position.x, i.size.y, a.size.z)))
	if i.end.x < a.end.x:
		out.append(AABB(Vector3(i.end.x, i.position.y, a.position.z), Vector3(a.end.x - i.end.x, i.size.y, a.size.z)))
	if i.position.z > a.position.z:
		out.append(AABB(Vector3(i.position.x, i.position.y, a.position.z), Vector3(i.size.x, i.size.y, i.position.z - a.position.z)))
	if i.end.z < a.end.z:
		out.append(AABB(Vector3(i.position.x, i.position.y, i.end.z), Vector3(i.size.x, i.size.y, a.end.z - i.end.z)))
	return out


## The tower's block at height y (before carving), or {}.
func _block_at(t: int, y: float) -> Dictionary:
	for b in blocks:
		if b.tower == t and absf(y - (b.c as Vector3).y) <= (b.s as Vector3).y * 0.5:
			return b
	return {}


## The room a tower has round its middle between two heights: the biggest
## box centred on its axis that leaves HALL_WALL of every block there.
func _room_in(t: int, bottom: float, top: float) -> AABB:
	var centre := Vector2(TOWERS[t][0], TOWERS[t][1])
	var half := Vector2(INF, INF)
	for b in blocks:
		if b.tower != t:
			continue
		var c: Vector3 = b.c
		var s: Vector3 = b.s
		if c.y + s.y * 0.5 < bottom or c.y - s.y * 0.5 > top:
			continue
		half.x = minf(half.x, minf(c.x + s.x * 0.5 - centre.x, centre.x - (c.x - s.x * 0.5)) - HALL_WALL)
		half.y = minf(half.y, minf(c.z + s.z * 0.5 - centre.y, centre.y - (c.z - s.z * 0.5)) - HALL_WALL)
	half = half.max(Vector2(12.0, 12.0))
	return AABB(Vector3(centre.x - half.x, bottom, centre.y - half.y), Vector3(half.x * 2.0, top - bottom, half.y * 2.0))


## The tower's outside face at height y on `side` (0 -Z, 1 +Z, 2 -X, 3 +X):
## how far out from the tower's middle (along that axis).
func _face(t: int, y: float, side: int) -> float:
	var b := _block_at(t, y)
	if b.is_empty():
		return TOWERS[t][2] * 0.5
	var c: Vector3 = b.c
	var s: Vector3 = b.s
	match side:
		0: return TOWERS[t][1] - (c.z - s.z * 0.5)
		1: return (c.z + s.z * 0.5) - TOWERS[t][1]
		2: return TOWERS[t][0] - (c.x - s.x * 0.5)
	return (c.x + s.x * 0.5) - TOWERS[t][0]


static func _outward(side: int) -> Vector3:
	return [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT][side]


## A passage straight out of `room` through the tower's wall on `side`, at
## floor height y (`width` across, `tall` high), past the outside by `beyond`.
func _passage_out(t: int, room: AABB, side: int, y: float, along: float, width: float, tall: float, beyond: float = 4.0) -> Vector3:
	var out := _outward(side)
	var face := _face(t, y + tall * 0.5, side)
	var centre := Vector3(TOWERS[t][0], y, TOWERS[t][1])
	var cross := Vector3(out.z, 0.0, out.x).abs() # the axis along the wall
	var start := centre + cross * along
	var reach := face + beyond
	var a := start + out * minf(room.size.x if side >= 2 else room.size.z, reach * 2.0) * 0.25
	var b := start + out * reach
	var lo := Vector3(minf(a.x, b.x), y, minf(a.z, b.z)) - cross * width * 0.5
	var hi := Vector3(maxf(a.x, b.x), y + tall, maxf(a.z, b.z)) + cross * width * 0.5
	_carve(AABB(lo, hi - lo))
	var mouth := centre + cross * along + out * face + Vector3.UP * tall * 0.5
	openings.append(mouth)
	return centre + cross * along + out * face # where the passage comes out, at floor height


# ---- The towers -----------------------------------------------------------------

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
		var width := foot * lerpf(1.0, 0.42, progress) * random.randf_range(0.85, 1.15)
		var depth := foot * lerpf(1.0, 0.42, progress) * random.randf_range(0.85, 1.15)
		var nudge := Vector2(random.randf_range(-0.08, 0.08) * width, random.randf_range(-0.08, 0.08) * depth)
		var c := Vector3(x + nudge.x, y + tall * 0.5, z + nudge.y)
		var s := Vector3(width, tall, depth)
		_add(c, s, &"shell", "Tower_%d" % t, &"stained" if t == HIVE else &"concrete", Basis.IDENTITY, true, t)
		blocks.append(boxes[boxes.size() - 1].duplicate())
		y += tall


## The stump (the user's): two stepped blocks, 0-400 m and 400-600 m,
## 120 m wide (the upper a little narrower), fused to the main tower's -X
## side -- each sunk 3 m into the main tower's wall at its height, so nothing
## of the stump ever reaches into the main tower's insides.
func _stump_blocks() -> void:
	var t := STUMP
	var outer: float = TOWERS[t][0] - TOWERS[t][2] * 0.5
	for step: Array in [[0.0, INTERIOR_TOP, TOWERS[t][2]], [INTERIOR_TOP, TOWERS[t][3], TOWERS[t][2] * 0.87]]:
		var bottom: float = step[0]
		var top: float = step[1]
		var main_face := TOWERS[0][2] * 0.5 if top <= INTERIOR_TOP else _face(0, (bottom + top) * 0.5, 2)
		var inner := -main_face + 3.0
		var c := Vector3((inner + outer) * 0.5, (bottom + top) * 0.5, TOWERS[t][1])
		_add(c, Vector3(inner - outer, top - bottom, step[2]), &"shell", "Tower_%d" % t, &"concrete", Basis.IDENTITY, true, t)
		blocks.append(boxes[boxes.size() - 1].duplicate())


## The stump's top (the user's): its hall open to the sky, broken through
## into the main tower's 440 m hall, its walls broken off partway up, rubble
## heaped on its floor.
func _stump_top() -> void:
	var hall := _hall_box(STUMP, 445.0)
	var main := _hall_box(0, 445.0)
	var floor_y := hall.position.y
	# The breach: through both towers' walls, 70 m wide, 90 m tall.
	var z0 := maxf(maxf(hall.position.z, main.position.z), -35.0)
	var z1 := minf(minf(hall.end.z, main.end.z), 35.0)
	_carve(AABB(Vector3(hall.end.x - 2.0, floor_y, z0), Vector3(main.position.x - hall.end.x + 4.0, 90.0, z1 - z0)))
	# The walls broken off: notches down from the top on its three open sides.
	var top: float = TOWERS[STUMP][3]
	var face := TOWERS[STUMP][2] * 0.5 + 4.0
	var centre := Vector3(TOWERS[STUMP][0], 0.0, TOWERS[STUMP][1])
	for side: int in [0, 1, 2]:
		var out := _outward(side)
		var cross := Vector3(out.z, 0.0, out.x).abs()
		var reach := (hall.size.x if side >= 2 else hall.size.z) * 0.5
		var wide := (hall.size.z if side >= 2 else hall.size.x) * 0.5
		for k in random.randi_range(2, 4):
			var along := random.randf_range(-wide, wide)
			var width := random.randf_range(20.0, 50.0)
			var down := minf(random.randf_range(30.0, 140.0), top - floor_y - 10.0)
			var at := centre + cross * along
			_carve(_span(at + out * (reach - 1.0), at + out * face, cross, width, top - down, down + 10.0))
			openings.append(at + out * face + Vector3.UP * (top - down * 0.5))
	# Rubble heaped on the floor, in three heaps.
	for heap in 3:
		var spot := Vector3(random.randf_range(hall.position.x + 15.0, hall.end.x - 15.0), floor_y, random.randf_range(hall.position.z + 15.0, hall.end.z - 15.0))
		for i in 8:
			var size := Vector3(random.randf_range(4.0, 16.0), random.randf_range(3.0, 10.0), random.randf_range(4.0, 16.0))
			var at := spot + Vector3(random.randf_range(-14.0, 14.0), size.y * random.randf_range(0.2, 0.9) + i * 1.5, random.randf_range(-14.0, 14.0))
			var tumble := Basis.from_euler(Vector3(random.randf_range(-0.5, 0.5), random.randf() * TAU, random.randf_range(-0.5, 0.5)))
			_add(at, size, &"interior", "Rubble_Stump", &"rubble", tumble)


## The main tower's base: ten 40 m storeys of outer walls with great
## openings, floors round the 60 m shaft, and a maze of apartment blocks.
func _base() -> void:
	var foot: float = TOWERS[0][2]
	var half := foot * 0.5
	var inner := foot - WALL * 2.0
	var floors := int(INTERIOR_TOP / FLOOR)
	for f in floors:
		for side in 4:
			_base_wall(side, f * FLOOR, half, f)
	for f in floors + 1:
		_slab_with_hole(f * FLOOR - SLAB * 0.5, inner, SHAFT, "Base")
	for f in floors:
		for n in _nests_at(0.45, f * FLOOR):
			var ring := Vector2.from_angle(random.randf() * TAU) * random.randf_range(SHAFT * 0.5 + 12.0, inner * 0.5 - 10.0)
			nest_spots.append(Vector3(ring.x, f * FLOOR, ring.y))
		growth_floors.append({rect = Rect2(-inner * 0.5, -inner * 0.5, inner, inner), y = f * FLOOR, zone = "Base_%d" % f,
				kinds = BASE_GROWTH, density = 1.0, shaft = SHAFT * 0.5 + 6.0})
	for f in floors:
		var y0 := f * FLOOR
		for gx in range(-2, 2):
			for gz in range(-2, 2):
				var cell := Vector2(gx + 0.5, gz + 0.5) * 46.0
				if absf(cell.x) < SHAFT * 0.5 + 20.0 and absf(cell.y) < SHAFT * 0.5 + 20.0:
					continue # the shaft and the ring round it stay open
				if random.randf() > 0.32:
					continue # most cells open: a few blocks, wide halls between
				var tall := random.randf_range(16.0, FLOOR - 6.0)
				var size := Vector3(random.randf_range(24.0, 34.0), tall, random.randf_range(24.0, 34.0))
				_add(Vector3(cell.x, y0 + tall * 0.5, cell.y), size, &"interior", "Base")
	# The shaft's walls, down through the ground to the depths.
	var down := -SHAFT_BOTTOM
	for side in 4:
		var out := (SHAFT + WALL) * 0.5
		var centre := _on_wall(side, out, 0.0, SHAFT_BOTTOM * 0.5 - SLAB)
		var along := SHAFT + WALL * 2.0 if side < 2 else SHAFT
		var size := Vector3(along, down, WALL) if side < 2 else Vector3(WALL, down, along)
		_add(centre, size, &"interior", "Depths")
	terrain_holes.append(AABB(Vector3(-SHAFT * 0.5 - WALL, -20.0, -SHAFT * 0.5 - WALL), Vector3(SHAFT + WALL * 2.0, 40.0, SHAFT + WALL * 2.0)))


## One storey of a base wall (side 0..3: -Z, +Z, -X, +X): solid, except
## where you walk in -- the
## bridge's end (+X, storey 1, round z 30), the lift's dock (-Z, storey 1,
## round x 0) -- and on +Z, storeys 1-2, the wall the falling block tore
## open (no wall there at all, but its ends).
func _base_wall(side: int, y0: float, half: float, storey: int) -> void:
	var length := half * 2.0
	var gap := 34.0
	var opening := INF # where along the wall a way in is (INF: none)
	if side == 3 and storey == 1:
		opening = 30.0
	elif side == 0 and storey == 1:
		opening = 0.0
	elif side == 1 and (storey == 1 or storey == 2):
		# Torn open: only the wall's ends are left.
		var ends := length * 0.2
		_wall_piece(side, half, -half + ends * 0.5, ends, y0, FLOOR)
		_wall_piece(side, half, half - ends * 0.5, ends, y0, FLOOR)
		openings.append(_on_wall(side, half, 0.0, y0 + FLOOR * 0.5))
		return
	if is_inf(opening):
		_wall_piece(side, half, 0.0, length, y0, FLOOR)
		return
	# The way in: open floor to lintel, wall either side of it.
	var lintel := 12.0
	var left := (opening - gap * 0.5) + half
	var right := half - (opening + gap * 0.5)
	_wall_piece(side, half, -half + left * 0.5, left, y0, FLOOR)
	_wall_piece(side, half, half - right * 0.5, right, y0, FLOOR)
	_wall_piece(side, half, opening, gap, y0 + FLOOR - lintel, lintel)
	openings.append(_on_wall(side, half, opening, y0 + (FLOOR - lintel) * 0.5))

func _wall_piece(side: int, half: float, along: float, width: float, y0: float, tall: float) -> void:
	var centre := _on_wall(side, half - WALL * 0.5, along, y0 + tall * 0.5)
	var size := Vector3(width, tall, WALL) if side < 2 else Vector3(WALL, tall, width)
	_add(centre, size, &"shell", "Tower_0", &"concrete", Basis.IDENTITY, true, 0)


## A point on wall `side` of the main tower, `along` it, at height y.
func _on_wall(side: int, out: float, along: float, y: float) -> Vector3:
	match side:
		0: return Vector3(along, y, -out)
		1: return Vector3(along, y, out)
		2: return Vector3(-out, y, along)
	return Vector3(out, y, along)


## A floor slab with a square hole in the middle (four boxes).
func _slab_with_hole(y: float, inner: float, hole: float, group: String) -> void:
	var rim := (inner - hole) * 0.5
	var off := hole * 0.5 + rim * 0.5
	_add(Vector3(0.0, y, -off), Vector3(inner, SLAB, rim), &"interior", group)
	_add(Vector3(0.0, y, off), Vector3(inner, SLAB, rim), &"interior", group)
	_add(Vector3(-off, y, 0.0), Vector3(rim, SLAB, hole), &"interior", group)
	_add(Vector3(off, y, 0.0), Vector3(rim, SLAB, hole), &"interior", group)


## The flooded depths: a vast drowned hall at the shaft's foot, pillars out
## of black water, half-sunk blocks, sewer tunnels off into the dark, and on
## its west side the way in from the outfall.
func _depths() -> void:
	var half := DEPTHS_SIZE * 0.5
	var tall := SHAFT_BOTTOM - DEPTHS_FLOOR
	_add(Vector3(0.0, DEPTHS_FLOOR - 5.0, 0.0), Vector3(DEPTHS_SIZE, 10.0, DEPTHS_SIZE), &"interior", "Depths")
	_slab_with_hole(SHAFT_BOTTOM + SLAB * 0.5, DEPTHS_SIZE, SHAFT, "Depths")
	for side in 4:
		var centre := _on_wall(side, half + WALL * 0.5, 0.0, DEPTHS_FLOOR + tall * 0.5)
		if side == 2:
			# The west wall: holed where the outfall comes in (z -140, 30 x 24).
			var span := DEPTHS_SIZE + WALL * 2.0
			var hole_lo := -140.0 - 17.0
			var hole_hi := -140.0 + 17.0
			var x := centre.x
			_add(Vector3(x, centre.y, (-span * 0.5 + hole_lo) * 0.5), Vector3(WALL, tall, hole_lo + span * 0.5), &"interior", "Depths")
			_add(Vector3(x, centre.y, (hole_hi + span * 0.5) * 0.5), Vector3(WALL, tall, span * 0.5 - hole_hi), &"interior", "Depths")
			_add(Vector3(x, DEPTHS_FLOOR + 28.0 + (tall - 28.0) * 0.5, -140.0), Vector3(WALL, tall - 28.0, 34.0), &"interior", "Depths")
			continue
		var size := Vector3(DEPTHS_SIZE + WALL * 2.0, tall, WALL) if side < 2 else Vector3(WALL, tall, DEPTHS_SIZE + WALL * 2.0)
		_add(centre, size, &"interior", "Depths")
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if gx == 0 and gz == 0:
				continue
			var at := Vector2(gx, gz) * 60.0
			if random.randf() < 0.3:
				var block := random.randf_range(18.0, 30.0)
				_add(Vector3(at.x, DEPTHS_FLOOR + block * 0.5, at.y), Vector3(28.0, block, 28.0), &"interior", "Depths")
			else:
				_add(Vector3(at.x, DEPTHS_FLOOR + tall * 0.5, at.y), Vector3(10.0, tall, 10.0), &"interior", "Depths")
	for k in 5:
		lamps.append([Vector3(random.randf_range(-130.0, 130.0), WATER_LEVEL + random.randf_range(15.0, 45.0), random.randf_range(-130.0, 130.0)),
				Color(1.0, 0.62, 0.3), 4.0, 120.0])


## Skybridges between the towers at every height (walked on, not through:
## the hollow ones are _hollow_bridges), and the entrance bridge.
func _bridges() -> void:
	var start := Vector3(TOWERS[1][0] - TOWERS[1][2] * 0.5 + 4.0, 0.0, 30.0)
	var finish := Vector3(TOWERS[0][2] * 0.5 + WALL, 0.0, 30.0)
	var thick := FLOOR - ENTRANCE_UNDERSIDE
	_add(Vector3((start.x + finish.x) * 0.5, FLOOR - thick * 0.5, 30.0), Vector3(start.x - finish.x, thick, 26.0), &"shell", "Bridges", &"plain")
	openings.append(Vector3((start.x + finish.x) * 0.5, FLOOR + 8.0, 30.0))
	entrance_spots.append(Vector3(finish.x + 12.0, FLOOR, 30.0))
	entrance_spots.append(Vector3(finish.x - 20.0, FLOOR, 40.0)) # just inside
	for i in 34:
		var a := random.randi() % TOWERS.size()
		var b := (a + 1 + random.randi() % (TOWERS.size() - 1)) % TOWERS.size()
		var top := minf(TOWERS[a][3], TOWERS[b][3]) - 120.0
		var y := random.randf_range(140.0, top)
		var from := Vector3(TOWERS[a][0], y, TOWERS[a][1])
		var to := Vector3(TOWERS[b][0], y, TOWERS[b][1])
		var across := Vector2(to.x - from.x, to.z - from.z)
		sky_bridges.append({a = a, b = b, y = y, top = top, width = random.randf_range(14.0, 40.0), tall = random.randf_range(8.0, 26.0),
				basis = Basis(Vector3.UP, atan2(across.x, across.y))})


## The skybridges, placed once everything else is: each runs from one tower's
## face to the other's (not through the towers' insides), and keeps clear of
## every window and its room, the halls, the lift's way and the high
## crossings (the user's ask: none blocking a window or the lift). One that
## would touch any of them moves up or down 8 m at a time until it doesn't,
## or is left out.
func _place_sky_bridges() -> void:
	var keep_clear: Array[AABB] = []
	for space in carved:
		keep_clear.append(space.grow(BRIDGE_MARGIN))
	for window in window_rooms:
		var at: Vector3 = window.at
		var normal: Vector3 = window.normal
		var size: Vector2 = window.size
		var cross := Vector3(normal.z, 0.0, normal.x).abs()
		keep_clear.append(_span(at - normal, at + normal * 25.0, cross, size.x + 16.0, at.y - size.y * 0.5 - 10.0, size.y + 20.0))
	# The lift's way up, the car (StackLift's 18 m) and its docks.
	var lift_top: float = LIFT_STOPS[LIFT_STOPS.size() - 1] + 100.0
	var wall := -TOWERS[0][2] * 0.5 + 5.0
	keep_clear.append(AABB(Vector3(-16.0, 0.0, lift_face - 15.0), Vector3(32.0, lift_top, wall - (lift_face - 15.0))))
	if crossing_clear.size != Vector3.ZERO:
		keep_clear.append(crossing_clear)
	for landing in lift_landings:
		keep_clear.append(landing.grow(BRIDGE_MARGIN))
	for grown in secret_blocks:
		keep_clear.append(grown.grow(BRIDGE_MARGIN + 8.0)) # (and the air round them: a balcony, a way in)
	keep_clear.append_array(bridge_avoid)
	for bridge in sky_bridges:
		var placed := false
		for k in 61:
			var y: float = bridge.y + ceilf(k * 0.5) * 8.0 * (1.0 if k % 2 == 1 else -1.0)
			if y < 140.0 or y > bridge.top:
				continue
			var span := _sky_bridge_span(bridge, y)
			if span.is_empty():
				continue
			var hits := false
			for space in keep_clear:
				if _bridge_hits(span.c, span.s * 0.5, bridge.basis, space):
					hits = true
					break
			if hits:
				continue
			_add(span.c, span.s, &"shell", "Bridges", &"plain", bridge.basis)
			openings.append((span.c as Vector3) + Vector3.UP * ((span.s as Vector3).y * 0.5 + 6.0))
			if k == 0:
				bridge_report.placed += 1
			else:
				bridge_report.moved += 1
			placed = true
			break
		if not placed:
			bridge_report.dropped += 1


## Where a skybridge between its towers goes at height y: {c, s}, from one
## tower's face to the other's (sunk into each just enough that no corner
## shows a gap), or {} if they're too close there.
func _sky_bridge_span(bridge: Dictionary, y: float) -> Dictionary:
	var a: int = bridge.a
	var b: int = bridge.b
	var from := Vector2(TOWERS[a][0], TOWERS[a][1])
	var to := Vector2(TOWERS[b][0], TOWERS[b][1])
	var dir := (to - from).normalized()
	var half_wide: float = bridge.width * 0.5
	var bottom: float = y - bridge.tall * 0.5
	var top: float = y + bridge.tall * 0.5
	var out_a := _exit_face(a, bottom, top, dir)
	var out_b := _exit_face(b, bottom, top, -dir)
	var start := out_a.x - (half_wide * out_a.y + 1.0)
	var finish := from.distance_to(to) - (out_b.x - (half_wide * out_b.y + 1.0))
	if finish - start < 10.0:
		return {}
	var middle := from + dir * (start + finish) * 0.5
	return {c = Vector3(middle.x, y, middle.y), s = Vector3(bridge.width, bridge.tall, finish - start)}


## How far from tower t's middle, going `dir` (flat), its outside is between
## two heights (its innermost face there), and the tan of the angle the way
## out meets that face at (capped at 1): Vector2(distance, tan).
func _exit_face(t: int, bottom: float, top: float, dir: Vector2) -> Vector2:
	var centre := Vector2(TOWERS[t][0], TOWERS[t][1])
	var best := INF
	var slant := 0.0
	for b in blocks:
		if b.tower != t:
			continue
		var c: Vector3 = b.c
		var s: Vector3 = b.s
		if c.y + s.y * 0.5 < bottom or c.y - s.y * 0.5 > top:
			continue
		var tx := INF
		var tz := INF
		if absf(dir.x) > 0.0001:
			tx = ((c.x + s.x * 0.5 if dir.x > 0.0 else c.x - s.x * 0.5) - centre.x) / dir.x
		if absf(dir.y) > 0.0001:
			tz = ((c.z + s.z * 0.5 if dir.y > 0.0 else c.z - s.z * 0.5) - centre.y) / dir.y
		var d := minf(tx, tz)
		if d < best:
			best = d
			slant = absf(dir.y) / absf(dir.x) if tx < tz else absf(dir.x) / absf(dir.y)
	if best == INF:
		return Vector2(TOWERS[t][2] * 0.5, 0.0)
	return Vector2(best, minf(slant, 1.0))


## Whether a box turned only about Y (centre, half size, basis) touches `box`
## (separating axes, flat, plus the heights).
static func _bridge_hits(c: Vector3, half: Vector3, basis: Basis, box: AABB) -> bool:
	if c.y + half.y <= box.position.y or c.y - half.y >= box.end.y:
		return false
	var e := box.size * 0.5
	var mid := box.get_center()
	var d := Vector2(c.x - mid.x, c.z - mid.z)
	var u := Vector2(basis.x.x, basis.x.z)
	var v := Vector2(basis.z.x, basis.z.z)
	if absf(d.x) > e.x + half.x * absf(u.x) + half.z * absf(v.x):
		return false
	if absf(d.y) > e.z + half.x * absf(u.y) + half.z * absf(v.y):
		return false
	if absf(d.dot(u)) > half.x + e.x * absf(u.x) + e.z * absf(u.y):
		return false
	if absf(d.dot(v)) > half.z + e.x * absf(v.x) + e.z * absf(v.y):
		return false
	return true


# ---- Carved spaces ------------------------------------------------------------------

## The main tower's shaft above the base, all the way up.
func _main_shaft() -> void:
	var half := UPPER_SHAFT * 0.5
	_carve(AABB(Vector3(-half, INTERIOR_TOP - 2.0, -half), Vector3(UPPER_SHAFT, TOWERS[0][3] - 60.0 - INTERIOR_TOP, UPPER_SHAFT)))


func _hall(t: int, bottom: float, top: float) -> void:
	var room := _room_in(t, bottom, top)
	_carve(room)
	halls.append({tower = t, box = room, name = "Hall_%d_%d" % [t, int(bottom)]})


## Lit apartment windows over every tower, each with its room behind it and
## the room's corridor into a hall -- every window has its room, every room
## leads to a hall (the user's ask). Two a hall, put first on the sides of
## its tower that don't have one yet, so every side of every tower gets at
## least one (every tower has two halls or more).
func _window_rooms() -> void:
	var sides_done := {} # Vector2i(tower, side) -> true
	for hall in halls:
		var t: int = hall.tower
		if t == HIVE:
			continue # its own two, below
		var floor_y: float = (hall.box as AABB).position.y
		# Two a hall, and a third in 60% of them: 30% more (the user's).
		var wanted_rooms := 2 + (1 if random.randf() < WINDOW_THIRD_CHANCE else 0)
		var placed := 0
		for attempt in 20:
			if placed >= wanted_rooms:
				break
			var wanted: Array[int] = []
			for side in 4:
				if not sides_done.has(Vector2i(t, side)) and not _fused(t, side, floor_y):
					wanted.append(side)
			var side := wanted[random.randi() % wanted.size()] if not wanted.is_empty() and attempt < 8 else random.randi() % 4
			if _fused(t, side, floor_y):
				continue
			if _window_room(hall, side):
				sides_done[Vector2i(t, side)] = true
				placed += 1
	# The hive's only windows (the user's): two, dark, into its two lowest halls.
	var hive_halls: Array[Dictionary] = []
	for hall in halls:
		if hall.tower == HIVE:
			hive_halls.append(hall)
	hive_halls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.box as AABB).position.y < (b.box as AABB).position.y)
	for k in mini(HIVE_WINDOWS, hive_halls.size()):
		for attempt in 16:
			if _window_room(hive_halls[k], random.randi() % 4, false):
				break


## Whether a tower's side at height y is fused to its neighbour (the stump
## and the main tower's -X side, up to the stump's top): no window there.
func _fused(t: int, side: int, y: float) -> bool:
	return (t == STUMP and side == 3) or (t == 0 and side == 2 and y < TOWERS[STUMP][3] + 20.0)

## One window room on `side` of a hall's tower, at that hall's height: the
## window (one painted window, on a painted spot), the room behind it (its
## floor at the sill, a warm lamp in half of them), and a corridor at its
## back into the hall. False if there's no room for one there. Not `lit`:
## dark (the hive's), no lamp and no glow round it.
func _window_room(hall: Dictionary, side: int, lit: bool = true) -> bool:
	var t: int = hall.tower
	var room_box: AABB = hall.box
	var tall := 14.0
	var y := random.randf_range(room_box.position.y + 2.0, room_box.end.y - tall - 4.0)
	var face := _face(t, y + tall * 0.5, side)
	var out := _outward(side)
	var cross := Vector3(out.z, 0.0, out.x).abs()
	var hall_reach := (room_box.size.x if side >= 2 else room_box.size.z) * 0.5
	var hall_wide := (room_box.size.z if side >= 2 else room_box.size.x) * 0.5
	var along := random.randf_range(-hall_wide * 0.6, hall_wide * 0.6)
	# On a painted window: across, a window's middle; up, its sill.
	var along_world := (Vector3(TOWERS[t][0], 0.0, TOWERS[t][1]) + cross * along).dot(_face_across(side))
	along += (_snap_to_window(along_world) - along_world) * _face_across(side).dot(cross) # (on two sides the texture runs the other way)
	y = _snap_sill(y) # the room's floor is the window's sill
	if y < room_box.position.y or y + tall > room_box.end.y:
		return false
	var centre := Vector3(TOWERS[t][0], y, TOWERS[t][1]) + cross * along
	# The room: from 3 m inside the face, up to 22 deep.
	var depth := minf(22.0, face - hall_reach - 3.0)
	if depth < 6.0:
		return false # no room between the hall and the outside here
	var near := centre + out * (face - 3.0)
	var far := centre + out * (face - 3.0 - depth)
	var room := _span(near, far, cross, 20.0, y, tall)
	_carve(room)
	# The corridor from the room's back into the hall.
	var hall_edge := centre + out * hall_reach
	_carve(_span(far + out * 0.5, hall_edge - out * 1.0, cross, 8.0, y, 10.0))
	# The window: one painted window's size, through the 3 m of wall in front.
	var window := Vector2(WINDOW_WIDTH, WINDOW_TOP - WINDOW_BOTTOM)
	_carve(_span(centre + out * (face + 1.0), centre + out * (face - 3.5), cross, window.x, y, window.y))
	var at := centre + out * face + Vector3.UP * window.y * 0.5
	window_rooms.append({at = at, normal = out, size = window, room = room, lit = lit})
	if random.randf() < 0.6:
		growth_floors.append({rect = Rect2(room.position.x + 1.0, room.position.z + 1.0, room.size.x - 2.0, room.size.z - 2.0), y = y,
				zone = hall.name, kinds = ROOM_GROWTH, density = 1.0, shaft = 0.0})
	openings.append(at)
	if lit and random.randf() < 0.5:
		lamps.append([room.get_center(), Color(1.0, 0.68, 0.32), 5.0, 32.0])
	if random.randf() < RADIO_CHANCE:
		# Somewhere on its floor, clear of the walls (it drops onto it).
		var spot := Vector3(random.randf_range(room.position.x + 2.5, room.end.x - 2.5), y + 0.8,
				random.randf_range(room.position.z + 2.5, room.end.z - 2.5))
		radio_spots.append([spot, random.randf() * TAU])
	if random.randf() < 0.5:
		entrance_spots.append(Vector3(room.get_center().x, room.position.y, room.get_center().z))
	return true


## The direction "across" a face on `side` runs in for the texture (its u
## axis in _box_faces): what the window grid is measured along.
static func _face_across(side: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK][side]


## The middle of the painted window nearest `along` (metres along a face).
static func _snap_to_window(along: float) -> float:
	return floorf(along / TEX_METRES) * TEX_METRES + TEX_METRES * 0.5


## The sill of the painted window nearest y (its bottom).
static func _snap_sill(y: float) -> float:
	return roundf((y - WINDOW_BOTTOM) / TEX_METRES) * TEX_METRES + WINDOW_BOTTOM


## A box spanning from `a` to `b` (along an axis, at the same height), `width`
## across `cross`, from floor y up `tall`.
func _span(a: Vector3, b: Vector3, cross: Vector3, width: float, y: float, tall: float) -> AABB:
	var lo := Vector3(minf(a.x, b.x), y, minf(a.z, b.z)) - cross * width * 0.5
	var hi := Vector3(maxf(a.x, b.x), y + tall, maxf(a.z, b.z)) + cross * width * 0.5
	return AABB(lo, hi - lo)


## Hollow skybridges joining halls in different towers at the same height:
## the main tower's mid hall to tower 1's and tower 3's.
func _hollow_bridges() -> void:
	_hollow_bridge(0, 1, 900.0, 3)
	_hollow_bridge(0, 3, 900.0, 0)


## A walk-through bridge from tower a's hall to tower b's at floor height y,
## leaving a on `side` (b on the opposite side).
func _hollow_bridge(a: int, b: int, y: float, side: int) -> void:
	var tall := 16.0
	var width := 16.0
	var from := _passage_out(a, _hall_box(a, y), side, y, 0.0, width + 4.0, tall + 4.0, 2.0)
	var back := side ^ 1 # the opposite side
	var to := _passage_out(b, _hall_box(b, y), back, y, 0.0, width + 4.0, tall + 4.0, 2.0)
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var basis := Basis(Vector3.UP, atan2(to.x - from.x, to.z - from.z))
	var middle := (from + to) * 0.5
	var group := "Bridge_%d_%d" % [a, b]
	_add(middle + Vector3.UP * -2.0, Vector3(width + 8.0, 4.0, length), &"interior", group, &"plain", basis)
	_add(middle + Vector3.UP * (tall + 2.0), Vector3(width + 8.0, 4.0, length), &"interior", group, &"plain", basis)
	for s in [-1.0, 1.0]:
		_add(middle + basis * Vector3(s * (width * 0.5 + 2.0), tall * 0.5, 0.0), Vector3(4.0, tall, length), &"interior", group, &"plain", basis)
	for k in 3:
		lamps.append([from.lerp(to, (k + 1) / 4.0) + Vector3.UP * (tall - 3.0), Color(0.9, 0.95, 1.0), 2.5, 28.0])


## The hall of tower t that holds height y.
func _hall_box(t: int, y: float) -> AABB:
	for hall in halls:
		var box: AABB = hall.box
		if hall.tower == t and y >= box.position.y - 1.0 and y <= box.end.y:
			return box
	return AABB(Vector3(TOWERS[t][0], y, TOWERS[t][1]), Vector3.ONE)


# ---- Entrances --------------------------------------------------------------------

## The express lift up the main tower's -Z side: the base (storey 1, its
## dock opening), the mid hall's dock (a corridor in, a huge door hanging
## half open), the crown's summit station.
func _lift() -> void:
	var most := 0.0
	for b in blocks:
		if b.tower == 0:
			most = maxf(most, -((b.c as Vector3).z - (b.s as Vector3).z * 0.5))
	lift_face = -(maxf(most, TOWERS[0][2] * 0.5) + 14.0)
	for stop: float in LIFT_STOPS:
		lift_stops.append(Vector3(0.0, stop, lift_face))
		if stop <= INTERIOR_TOP:
			# From the wall (its storey-1 opening has no sill) out to the lift.
			var wall := -TOWERS[0][2] * 0.5
			_add(Vector3(0.0, stop - 1.5, (wall + lift_face) * 0.5), Vector3(24.0, 3.0, wall - lift_face), &"shell", "Docks", &"metal")
			lift_buttons.append(Vector3(-9.0, stop, wall - 3.0))
			entrance_spots.append(Vector3(0.0, stop, wall - 8.0))
			continue
		var mouth := _passage_out(0, _hall_box(0, stop), 0, stop, 0.0, 24.0, 22.0, 2.0)
		_add(Vector3(0.0, stop - 1.5, (lift_face + mouth.z) * 0.5 + 4.0), Vector3(24.0, 3.0, mouth.z - lift_face - 4.0), &"shell", "Docks", &"metal")
		# From beyond the car to inside the opening, and well over head height.
		lift_landings.append(AABB(Vector3(-20.0, stop - 8.0, lift_face - 15.0), Vector3(40.0, 48.0, mouth.z - lift_face + 25.0)))
		lift_buttons.append(Vector3(-9.0, stop, mouth.z - 3.0))
		entrance_spots.append(Vector3(0.0, stop, mouth.z - 8.0))
		if stop < 2000.0:
			# The mid dock's door: a slab 30 m tall, hanging half open.
			var hinge := Vector3(-12.0, stop + 15.0, mouth.z - 2.0)
			_add(hinge + Basis(Vector3.UP, -0.7) * Vector3(12.0, 0.0, 0.0), Vector3(24.0, 30.0, 3.0), &"shell", "Docks", &"metal",
					Basis(Vector3.UP, -0.7))
		lamps.append([Vector3(0.0, stop + 10.0, mouth.z - 6.0), Color(1.0, 0.55, 0.25), 4.0, 40.0])


## The collapsed block: a slab broken from a kilometre up, lying where it
## fell against the main tower's +Z side, its broken sections a ramp up into
## the torn-open wall 80 m up -- broken concrete, rubble and bent rebar,
## nothing like a wall of windows underfoot.
func _collapsed_block() -> void:
	var face := TOWERS[0][2] * 0.5
	var top := Vector3(0.0, 2.0 * FLOOR, face - 4.0) # the torn floor's edge, 80 m up
	var run := top.y / tan(deg_to_rad(RAMP_SLOPE))
	var foot := top + Vector3(0.0, -top.y, run)
	entrance_spots.append(top + Vector3(-18.0, 0.0, -14.0)) # inside the tear
	entrance_spots.append(foot + Vector3(30.0, 0.0, 8.0)) # by the rubble's foot
	var sections := 3
	for i in sections:
		var a := top.lerp(foot, float(i) / sections)
		var b := top.lerp(foot, float(i + 1) / sections)
		var length := a.distance_to(b) + 3.0 # each overlaps the next: no ledge to climb
		var dir := (b - a).normalized()
		var basis := Basis.looking_at(dir, Vector3.UP).rotated(dir, random.randf_range(-0.05, 0.05))
		basis = Basis(Vector3.UP, random.randf_range(-0.06, 0.06)) * basis
		_add((a + b) * 0.5 + basis.y * -5.0, Vector3(46.0, 10.0, length), &"shell", "Rubble", &"rubble", basis)
	# Chunks broken off it, tumbled round it; and its rebar.
	for i in 26:
		var t := random.randf()
		var along := top.lerp(foot, t)
		var side := random.randf_range(26.0, 60.0) * (1.0 if random.randf() < 0.5 else -1.0)
		var size := Vector3(random.randf_range(5.0, 18.0), random.randf_range(4.0, 14.0), random.randf_range(5.0, 18.0))
		var at := Vector3(side, maxf(along.y * random.randf_range(0.0, 0.7), size.y * 0.3), along.z + random.randf_range(-15.0, 15.0))
		var tumble := Basis.from_euler(Vector3(random.randf_range(-0.6, 0.6), random.randf() * TAU, random.randf_range(-0.6, 0.6)))
		_add(at, size, &"shell", "Rubble", &"rubble", tumble)
	for i in 20:
		var at := top.lerp(foot, random.randf()) + Vector3(random.randf_range(-22.0, 22.0), 0.0, 0.0)
		var bend := Basis.from_euler(Vector3(random.randf_range(-1.2, 1.2), random.randf() * TAU, random.randf_range(-1.2, 1.2)))
		_add(at + bend.y * 6.0, Vector3(0.5, 14.0, 0.5), &"shell", "Rubble", &"metal", bend)


## The sewer outfall: a colossal culvert mouth at the foot of the Stack,
## sludge on its floor, its tunnel going down -- one bend, in a chamber --
## to the flooded depths' west wall.
func _outfall() -> void:
	var points := [Vector3(-400.0, 0.0, 180.0), Vector3(-400.0, -150.0, -140.0), Vector3(-163.0, DEPTHS_FLOOR, -140.0)]
	var inner := Vector2(30.0, 24.0)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir := (b - a).normalized()
		var basis := Basis.looking_at(dir, Vector3.UP)
		var length := a.distance_to(b) + 6.0
		var middle := (a + b) * 0.5
		var group := "Outfall"
		_add(middle + basis.y * -2.0, Vector3(inner.x + 8.0, 4.0, length), &"interior", group, &"plain", basis)
		_add(middle + basis.y * (inner.y + 2.0), Vector3(inner.x + 8.0, 4.0, length), &"interior", group, &"plain", basis)
		for s in [-1.0, 1.0]:
			_add(middle + basis * Vector3(s * (inner.x * 0.5 + 2.0), inner.y * 0.5, 0.0), Vector3(4.0, inner.y, length), &"interior", group, &"plain", basis)
		# Sludge down the floor.
		_add(middle + basis.y * 0.2, Vector3(inner.x * 0.6, 0.4, length), &"interior", group, &"sludge", basis)
		for k in 2:
			lamps.append([a.lerp(b, (k + 1) / 3.0) + Vector3.UP * (inner.y - 4.0), Color(0.75, 0.9, 0.55), 2.0, 45.0])
	# The bend's chamber, round the joint: its floor level with the tunnel's,
	# open on +Z (the way down from the mouth) and +X (on to the depths).
	var bend: Vector3 = points[1]
	_box_room(bend + Vector3.UP * 18.0, Vector3(52.0, 40.0, 52.0), "Outfall")
	# The mouth: a retaining wall either side and a lintel over it, at ground level.
	var mouth: Vector3 = points[0]
	_add(mouth + Vector3(-34.0, 18.0, 0.0), Vector3(30.0, 36.0, 10.0), &"shell", "Outfall_Mouth", &"plain")
	_add(mouth + Vector3(34.0, 18.0, 0.0), Vector3(30.0, 36.0, 10.0), &"shell", "Outfall_Mouth", &"plain")
	_add(mouth + Vector3(0.0, 31.0, 0.0), Vector3(38.0, 10.0, 10.0), &"shell", "Outfall_Mouth", &"plain")
	terrain_holes.append(AABB(mouth + Vector3(-20.0, -40.0, -80.0), Vector3(40.0, 80.0, 84.0)))
	openings.append(mouth + Vector3(0.0, 12.0, 0.0))
	entrance_spots.append(mouth + Vector3(0.0, 0.0, 14.0))
	entrance_spots.append(mouth + Vector3(-22.0, 0.0, 20.0))


## A joint's chamber: floor, ceiling, solid -X and -Z walls, and +Z and +X
## walls each with a 36 x 30 hole where a tunnel comes in.
func _box_room(centre: Vector3, size: Vector3, group: String) -> void:
	var h := size * 0.5
	_add(centre + Vector3(0.0, -h.y, 0.0), Vector3(size.x, 4.0, size.z), &"interior", group)
	_add(centre + Vector3(0.0, h.y, 0.0), Vector3(size.x, 4.0, size.z), &"interior", group)
	_add(centre + Vector3(-h.x, 0.0, 0.0), Vector3(4.0, size.y, size.z), &"interior", group)
	_add(centre + Vector3(0.0, 0.0, -h.z), Vector3(size.x, size.y, 4.0), &"interior", group)
	var hole := Vector2(36.0, 30.0)
	var floor_y := centre.y - h.y + 2.0
	for axis: Vector3 in [Vector3.BACK, Vector3.RIGHT]:
		var cross := Vector3(axis.z, 0.0, axis.x).abs()
		var wall := centre + axis * h.x
		var side := (size.x - hole.x) * 0.5
		var thin := Vector3(4.0, 0.0, 4.0) * axis.abs()
		for s: float in [-1.0, 1.0]:
			_add(wall + cross * s * (hole.x * 0.5 + side * 0.5), cross * side + Vector3.UP * size.y + thin, &"interior", group)
		var over := size.y - hole.y - 2.0
		_add(Vector3(wall.x, floor_y + hole.y + over * 0.5, wall.z), cross * hole.x + Vector3.UP * over + thin, &"interior", group)


## The hive tunnel: a ledge jutting from the main tower's +Z side at the mid
## hall's floor, hive spires sprouting on it, and a tunnel through the wall
## lined in hive clay with glowing vents, into the hall.
func _hive_tunnel() -> void:
	var y: float = HALLS[0][0][0]
	var mouth := _passage_out(0, _hall_box(0, y), 1, y, 30.0, 18.0, 16.0, 2.0)
	_add(Vector3(mouth.x, y - 4.0, mouth.z + 22.0), Vector3(70.0, 8.0, 48.0), &"shell", "Hive", &"clay")
	entrance_spots.append(mouth + Vector3(-14.0, 0.0, 14.0))
	# Clay lumps lining the tunnel (and its mouth), glowing vents among them.
	for i in 22:
		var at := mouth + Vector3(random.randf_range(-12.0, 12.0), random.randf_range(0.0, 15.0), random.randf_range(-24.0, 6.0))
		var lump := Basis.from_euler(Vector3(random.randf() * TAU, random.randf() * TAU, random.randf() * TAU))
		_add(at, Vector3.ONE * random.randf_range(2.0, 5.0), &"interior", "Hive", &"clay", lump)
	for i in 4:
		lamps.append([mouth + Vector3(random.randf_range(-6.0, 6.0), random.randf_range(4.0, 12.0), random.randf_range(-20.0, 0.0)),
				Color(1.0, 0.75, 0.2), 3.0, 22.0])


## Above the clouds: the cable car from tower 1's high hall to the main
## tower's, and the broken bridge between them -- a 30 m gap to grapple.
func _high_crossings() -> void:
	var t0_y: float = HALLS[0][1][0]
	var t1_y: float = HALLS[1][1][0]
	# The broken bridge, low in both halls -- at one height in both.
	var deck := maxf(t0_y, t1_y) + 6.0
	var a := _passage_out(1, _hall_box(1, deck), 2, deck, -15.0, 18.0, 16.0, 2.0)
	var b := _passage_out(0, _hall_box(0, deck), 3, deck, -25.0, 18.0, 16.0, 2.0)
	entrance_spots.append(a + Vector3(-6.0, 0.0, 0.0))
	entrance_spots.append(b + Vector3(6.0, 0.0, 0.0))
	var gap := 30.0
	var middle := (a + b) * 0.5
	var dir := (b - a).normalized()
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var half_gap := dir * gap * 0.5
	for end in [[a, middle - half_gap], [middle + half_gap, b]]:
		var from: Vector3 = end[0]
		var to: Vector3 = end[1]
		_add((from + to) * 0.5 + Vector3.UP * -3.0, Vector3(16.0, 6.0, from.distance_to(to)), &"shell", "Bridges", &"plain", basis)
	# The cable car: at the same floor, alongside the bridge but clear of it
	# (its line never crosses the bridge's).
	var c := _passage_out(1, _hall_box(1, deck), 2, deck, 15.0, 22.0, 18.0, 2.0)
	var d := _passage_out(0, _hall_box(0, deck), 3, deck, 35.0, 22.0, 18.0, 2.0)
	cable_stops.append(c + Vector3(-14.0, 0.0, 0.0))
	cable_stops.append(d + Vector3(14.0, 0.0, 0.0))
	for stop in cable_stops:
		_add(stop + Vector3.UP * -1.5, Vector3(26.0, 3.0, 26.0), &"shell", "Docks", &"metal")
		entrance_spots.append(stop)
	crossing_clear = AABB(a, Vector3.ZERO).expand(b).expand(c).expand(d).grow(20.0)
	crossing_clear.position.y = deck - 20.0
	crossing_clear.size.y = 60.0


## The crown's hangar: a great mouth in the main tower's +X side, open to
## the sky, into the crown hall.
func _crown_hangar() -> void:
	var y: float = HALLS[0][2][0]
	var mouth := _passage_out(0, _hall_box(0, y), 3, y, 0.0, 70.0, 46.0, 4.0)
	entrance_spots.append(mouth + Vector3(-14.0, 0.0, 0.0))


# ---- What's inside --------------------------------------------------------------------

## A cavernous brutalist hall: mezzanines up walkable ramps, columns (some
## leaning), a stepped pyramid hanging upside down from the ceiling, a slab
## leaning on a wall, stairs that stop in mid-air -- and its lamps.
func _hall_features(hall: Dictionary) -> void:
	if hall.tower == HIVE:
		_panic_stairs(hall)
		return
	var box: AABB = hall.box
	var group: String = hall.name
	var floor_y := box.position.y
	var tall := box.size.y
	var main: bool = hall.tower == 0
	var shaft := Rect2(-UPPER_SHAFT * 0.5 - 6.0, -UPPER_SHAFT * 0.5 - 6.0, UPPER_SHAFT + 12.0, UPPER_SHAFT + 12.0)
	# A hall with its middle kept open (the heart's cathedral): `open`, the
	# radius of the circle round the middle nothing free-standing goes in --
	# and the mezzanines' ramps kept out of it too. `growth`: its floor's
	# growth that many times thicker. (Neither: every other hall, as ever.)
	var open: float = hall.get("open", 0.0)
	var middle := Vector2(box.get_center().x, box.get_center().z)
	var growth: float = hall.get("growth", 1.0)
	# Mezzanines, against a wall each, and switchback ramps up to them.
	var levels: Array = [0.4, 0.7] if tall < 250.0 else [0.25, 0.5, 0.75]
	for level: float in levels:
		if tall < 80.0 and level > 0.5:
			continue
		var side := random.randi() % 4
		var out := _outward(side)
		var cross := Vector3(out.z, 0.0, out.x).abs()
		var along_len := box.size.x if side < 2 else box.size.z
		var across_len := box.size.z if side < 2 else box.size.x
		var depth := across_len * 0.25
		if open > 0.0:
			# Shallow enough that its ramps' lanes (in from its front edge) stay
			# out of the open middle.
			var lanes := mini(ceili(tall * level / maxf((along_len - 24.0) * tan(deg_to_rad(RAMP_SLOPE)), 1.0)), 8)
			depth = minf(depth, across_len * 0.5 - open - 10.0 * lanes)
			if depth < 6.0:
				continue
		var span := along_len * 0.8
		var deck_y := floor_y + tall * level
		var wall_mid := box.get_center() + out * (across_len * 0.5 - depth * 0.5)
		_add(Vector3(wall_mid.x, deck_y - 2.0, wall_mid.z), cross * span + Vector3.UP * 4.0 + out.abs() * depth, &"interior", group)
		for n in _nests_at(0.45, deck_y):
			nest_spots.append(Vector3(wall_mid.x, deck_y, wall_mid.z) + cross * random.randf_range(-span * 0.3, span * 0.3))
		# Now and then a gang camped up on it (the main tower only, for now).
		if main and random.randf() < GANG_DECK_CHANCE:
			gang_spots.append(Vector4(wall_mid.x, deck_y, wall_mid.z, minf(depth, span) * 0.35))
		var deck_size := cross * span + out.abs() * depth
		growth_floors.append({rect = Rect2(wall_mid.x - deck_size.x * 0.5, wall_mid.z - deck_size.z * 0.5, deck_size.x, deck_size.z),
				y = deck_y, zone = group, kinds = HALL_GROWTH, density = 0.8, shaft = 0.0})
		_switchback(box, out, cross, across_len * 0.5 - depth, along_len - 24.0, floor_y, deck_y, group)
		decks.append({hall = hall, side = side, y = deck_y, span = span})
	var hall_floor := {rect = Rect2(box.position.x + 4.0, box.position.z + 4.0, box.size.x - 8.0, box.size.z - 8.0), y = floor_y,
			zone = group, kinds = HALL_GROWTH, density = 1.2 * growth, shaft = (UPPER_SHAFT * 0.5 + 6.0) if main else 0.0}
	if open > 0.0:
		hall_floor["open"] = open
		hall_floor["open_at"] = middle
	growth_floors.append(hall_floor)
	# Now and then a barnacle nest's spot on the hall floor (more the higher up).
	for n in _nests_at(0.6, floor_y):
		var spot := Vector3(random.randf_range(box.position.x + 12.0, box.end.x - 12.0), floor_y, random.randf_range(box.position.z + 12.0, box.end.z - 12.0))
		if not (main and shaft.has_point(Vector2(spot.x, spot.z))) and not (open > 0.0 and Vector2(spot.x, spot.z).distance_to(middle) < open):
			nest_spots.append(spot)
	# A gang camped on the floor of about one hall in three (the user's: the
	# main tower only, for now).
	if main and random.randf() < GANG_HALL_CHANCE:
		for attempt in 10:
			var spot := Vector3(random.randf_range(box.position.x + 20.0, box.end.x - 20.0), floor_y, random.randf_range(box.position.z + 20.0, box.end.z - 20.0))
			if main and shaft.grow(20.0).has_point(Vector2(spot.x, spot.z)):
				continue
			gang_spots.append(Vector4(spot.x, spot.y, spot.z, 18.0))
			break
	# Columns in a skewed grid, a few leaning.
	for i in random.randi_range(4, 8):
		var at := Vector3(random.randf_range(box.position.x + 8.0, box.end.x - 8.0), 0.0, random.randf_range(box.position.z + 8.0, box.end.z - 8.0))
		if main and shaft.has_point(Vector2(at.x, at.z)):
			continue
		if open > 0.0:
			for attempt in 20:
				if Vector2(at.x, at.z).distance_to(middle) > open + 6.0:
					break
				at = Vector3(random.randf_range(box.position.x + 8.0, box.end.x - 8.0), 0.0, random.randf_range(box.position.z + 8.0, box.end.z - 8.0))
			if Vector2(at.x, at.z).distance_to(middle) <= open + 6.0:
				continue
		var lean := Basis.from_euler(Vector3(random.randf_range(-0.12, 0.12), random.randf() * 0.5, random.randf_range(-0.12, 0.12)))
		var thick := random.randf_range(5.0, 9.0)
		_add(Vector3(at.x, floor_y + tall * 0.5, at.z), Vector3(thick, tall + 2.0, thick), &"interior", group, &"plain", lean)
		nest_objects.append(AABB(Vector3(at.x - thick * 0.5, floor_y, at.z - thick * 0.5), Vector3(thick, minf(tall, 60.0), thick)))
	# A stepped pyramid hanging upside down from the ceiling.
	var hang := Vector3(random.randf_range(box.position.x + 20.0, box.end.x - 20.0), box.end.y, random.randf_range(box.position.z + 20.0, box.end.z - 20.0))
	var width := minf(box.size.x, box.size.z) * 0.35
	var hang_here := not (main and shaft.has_point(Vector2(hang.x, hang.z)))
	if open > 0.0:
		for attempt in 30:
			if Vector2(hang.x, hang.z).distance_to(middle) > open + width * 0.5:
				break
			hang = Vector3(random.randf_range(box.position.x + 20.0, box.end.x - 20.0), box.end.y, random.randf_range(box.position.z + 20.0, box.end.z - 20.0))
		hang_here = Vector2(hang.x, hang.z).distance_to(middle) > open + width * 0.5
	if hang_here:
		for k in 4:
			var step := width * (1.0 - k * 0.22)
			_add(hang + Vector3.DOWN * (6.0 * k + 3.0), Vector3(step, 6.0, step), &"interior", group, &"plain")
	# A slab leaning on a wall.
	var lean_side := random.randi() % 4
	var lean_out := _outward(lean_side)
	var lean_at := box.get_center() + lean_out * ((box.size.x if lean_side >= 2 else box.size.z) * 0.5 - 10.0)
	lean_at.y = floor_y + tall * 0.3
	var lean_basis := Basis(Vector3(lean_out.z, 0.0, lean_out.x).abs().normalized(), 0.35 * (1.0 if lean_side % 2 == 0 else -1.0))
	_add(lean_at, Vector3(30.0, tall * 0.6, 3.0) if lean_side < 2 else Vector3(3.0, tall * 0.6, 30.0), &"interior", group, &"plain", lean_basis)
	# Stairs that stop in mid-air.
	var stair_at := Vector3(random.randf_range(box.position.x + 15.0, box.end.x - 15.0), floor_y, random.randf_range(box.position.z + 15.0, box.end.z - 15.0))
	var stairs_here := not (main and shaft.has_point(Vector2(stair_at.x, stair_at.z)))
	if open > 0.0:
		for attempt in 30:
			if Vector2(stair_at.x, stair_at.z).distance_to(middle) > open + 30.0:
				break
			stair_at = Vector3(random.randf_range(box.position.x + 15.0, box.end.x - 15.0), floor_y, random.randf_range(box.position.z + 15.0, box.end.z - 15.0))
		stairs_here = Vector2(stair_at.x, stair_at.z).distance_to(middle) > open + 30.0
	if stairs_here:
		var stair_turn := Basis(Vector3.UP, random.randf() * TAU)
		for k in 7:
			var step_at := stair_at + stair_turn * Vector3(0.0, 1.0 + k * 2.0, k * 4.0)
			_add(step_at, Vector3(10.0, 2.0 + k * 4.0, 4.0) if k == 0 else Vector3(10.0, 2.0, 4.0), &"interior", group, &"plain", stair_turn)
			if k % 3 == 0:
				nest_objects.append(AABB(step_at - Vector3(2.0, 1.0, 2.0), Vector3(4.0, 2.0, 4.0)))
	# Its lamps: cold up high, warm low.
	lamps.append([box.get_center() + Vector3.UP * tall * 0.35, Color(0.75, 0.85, 1.0), 4.0, maxf(box.size.x, box.size.z) * 0.8])
	lamps.append([Vector3(box.get_center().x, floor_y + 8.0, box.get_center().z) + Vector3(box.size.x * 0.3, 0.0, 0.0), Color(1.0, 0.6, 0.3), 3.0, 50.0])


## Ramps up from the floor to a deck's front edge (`edge`: its distance from
## the hall's middle along `out`): zig-zagging along the wall in lanes, each
## further out from the deck, a landing at every turn -- RAMP_SLOPE all the
## way, however high it is.
func _switchback(box: AABB, out: Vector3, cross: Vector3, edge: float, room: float, floor_y: float, deck_y: float, group: String) -> void:
	var width := 10.0
	var steepness := tan(deg_to_rad(RAMP_SLOPE))
	var top_y := deck_y
	var top_along := room * 0.5
	var going := -1.0
	var lane := 0
	var centre := box.get_center()
	while top_y - floor_y > 0.5 and lane < 8:
		var lane_at := edge - width * (lane + 0.5)
		var run := minf(room, (top_y - floor_y) / steepness)
		var bottom_along := top_along + going * run
		var bottom_y := top_y - run * steepness
		var top := centre + out * lane_at + cross * top_along
		top.y = top_y
		var bottom := centre + out * lane_at + cross * bottom_along
		bottom.y = bottom_y
		var basis := Basis.looking_at((top - bottom).normalized(), Vector3.UP)
		_add((top + bottom) * 0.5 + basis.y * -1.0, Vector3(width, 2.0, top.distance_to(bottom) + 1.0), &"interior", group, &"plain", basis)
		var ramp_mid := (top + bottom) * 0.5
		nest_objects.append(AABB(ramp_mid - Vector3(3.0, 2.0, 3.0), Vector3(6.0, 2.0, 6.0)))
		if bottom_y - floor_y > 0.5:
			# A landing across this lane and the next, where the ramp turns.
			var landing := centre + out * (lane_at - width * 0.5) + cross * bottom_along
			landing.y = bottom_y - 1.0
			_add(landing, cross * width + Vector3.UP * 2.0 + out.abs() * width * 2.0, &"interior", group)
		top_y = bottom_y
		top_along = bottom_along
		going = -going
		lane += 1


## Platforms across the main shaft every ~120 m (not inside the halls):
## half the shaft each, alternating sides -- a slip down it is a drop onto
## the next, not the bottom.
func _shaft_platforms() -> void:
	var y := INTERIOR_TOP + 120.0
	var side := 0
	while y < TOWERS[0][3] - 100.0:
		var in_hall := false
		for hall in halls:
			var box: AABB = hall.box
			if hall.tower == 0 and y > box.position.y - 20.0 and y < box.end.y + 20.0:
				in_hall = true
		if not in_hall:
			var out := _outward(side % 4)
			var size := Vector3(UPPER_SHAFT, 3.0, UPPER_SHAFT * 0.55) if side % 4 < 2 else Vector3(UPPER_SHAFT * 0.55, 3.0, UPPER_SHAFT)
			_add(out * UPPER_SHAFT * 0.225 + Vector3.UP * y, size, &"interior", "Shaft_%d" % int(y / 1000.0))
		y += random.randf_range(100.0, 140.0)
		side += 1


# ---- The hive, and the cobwebs ---------------------------------------------------------

## The hive's worn-down outside (the user's): chunks bitten out of its
## blocks' corners and top edges, and ragged holes punched through its walls
## into its halls -- growth spilling out of them, their glow (_hive_glow).
## Never through a window room.
func _hive_bites() -> void:
	var keep: Array[AABB] = []
	for w in window_rooms:
		keep.append((w.room as AABB).grow(6.0))
		keep.append(AABB((w.at as Vector3) - Vector3(10.0, 10.0, 10.0), Vector3(20.0, 20.0, 20.0)))
	for b in blocks:
		if b.tower != HIVE:
			continue
		var c: Vector3 = b.c
		var s: Vector3 = b.s
		for k in HIVE_BITES:
			var size := Vector3(random.randf_range(14.0, 40.0), random.randf_range(14.0, 50.0), random.randf_range(14.0, 40.0))
			var sx := 1.0 if random.randf() < 0.5 else -1.0
			var sz := 1.0 if random.randf() < 0.5 else -1.0
			var at := Vector3(c.x + s.x * 0.5 * sx, random.randf_range(c.y - s.y * 0.4, c.y + s.y * 0.4), c.z + s.z * 0.5 * sz)
			if random.randf() < 0.4:
				# A top edge instead of a corner: somewhere along one side's top.
				at.y = c.y + s.y * 0.5
				if random.randf() < 0.5:
					at.x = c.x + random.randf_range(-0.4, 0.4) * s.x
				else:
					at.z = c.z + random.randf_range(-0.4, 0.4) * s.z
			_ragged_carve(AABB(at - size * 0.5, size), keep)
	for hall in halls:
		if hall.tower != HIVE:
			continue
		var box: AABB = hall.box
		for k in HIVE_HOLES:
			var side := random.randi() % 4
			var out := _outward(side)
			var cross := Vector3(out.z, 0.0, out.x).abs()
			var wide := (box.size.z if side >= 2 else box.size.x) * 0.5
			var reach := (box.size.x if side >= 2 else box.size.z) * 0.5
			var size := Vector2(random.randf_range(12.0, 30.0), random.randf_range(12.0, 30.0))
			var y := random.randf_range(box.position.y + 2.0, box.end.y - size.y - 20.0)
			var face := _face(HIVE, y + size.y * 0.5, side)
			var centre := Vector3(TOWERS[HIVE][0], y, TOWERS[HIVE][1]) + cross * random.randf_range(-wide * 0.7, wide * 0.7)
			var hole := _span(centre + out * (reach - 2.0), centre + out * (face + 3.0), cross, size.x, y, size.y)
			if _touches(hole, keep):
				continue
			_ragged_carve(hole, keep)
			var at := centre + out * face + Vector3.UP * size.y * 0.5
			hive_holes.append({at = at, normal = out, size = size})
			openings.append(at)
			# Growth heaped in it, spilling out.
			growth_floors.append({rect = Rect2(hole.position.x, hole.position.z, hole.size.x, hole.size.z), y = y, zone = hall.name,
					kinds = HALL_GROWTH, density = 2.0 * HIVE_GROWTH, shaft = 0.0})


## Carves `box` and a couple of smaller boxes round its rim (so the hole's
## ragged, not a clean box), each unless it'd touch something kept.
func _ragged_carve(box: AABB, keep: Array[AABB]) -> void:
	if _touches(box, keep):
		return
	_carve(box)
	for k in 2:
		var size := box.size * Vector3(random.randf_range(0.35, 0.6), random.randf_range(0.35, 0.6), random.randf_range(0.35, 0.6))
		var at := box.position + box.size * Vector3(random.randf(), random.randf(), random.randf())
		var rim := AABB(at - size * 0.5, size)
		if not _touches(rim, keep):
			_carve(rim)


static func _touches(box: AABB, keep: Array[AABB]) -> bool:
	for space in keep:
		if space.intersects(box):
			return true
	return false


## The hive's halls (the user's): no mezzanines -- landings and stair flights
## built in a panic, at every angle, tangled up through the lower PANIC_HEIGHT
## of the hall (the air above stays open for the grapple), about
## PANIC_FLIGHTS of them. It all connects, and there are no dead ends: every
## landing has two flights off it at least. Choked with growth (HIVE_GROWTH).
func _panic_stairs(hall: Dictionary) -> void:
	var box: AABB = hall.box
	var group: String = hall.name
	var floor_y := box.position.y
	var top_y := floor_y + box.size.y * PANIC_HEIGHT
	var lo := Vector2(box.position.x + 10.0, box.position.z + 10.0)
	var hi := Vector2(box.end.x - 10.0, box.end.z - 10.0)
	# Landings: {c: its top's middle, r: half its size, links}; 0 is the floor.
	var landings: Array[Dictionary] = [{c = Vector3(box.get_center().x, floor_y, box.get_center().z), r = 0.0, links = 0, floor = true, alive = true}]
	var flights: Array[Dictionary] = [] # {a, b: ends (their top), from, to: landings}
	# Grown out from the floor and each other, mostly climbing...
	var tries := 0
	while flights.size() < PANIC_FLIGHTS * 2 / 3 and tries < 800:
		tries += 1
		var p := random.randi() % landings.size()
		var q := random.randi() % landings.size()
		var parent := p if (landings[p].c as Vector3).y >= (landings[q].c as Vector3).y else q
		if not landings[parent].alive:
			continue
		var dir := Vector2.from_angle(random.randf() * TAU)
		var dir3 := Vector3(dir.x, 0.0, dir.y)
		var slope := deg_to_rad(random.randf_range(16.0, RAMP_SLOPE))
		var length := random.randf_range(14.0, 34.0)
		var rise := length * sin(slope) * (1.0 if random.randf() < 0.85 else -1.0)
		var start: Vector3
		if landings[parent].floor:
			start = Vector3(random.randf_range(lo.x, hi.x), floor_y, random.randf_range(lo.y, hi.y))
			rise = absf(rise)
		else:
			start = (landings[parent].c as Vector3) + dir3 * float(landings[parent].r)
		var finish := start + dir3 * length * cos(slope) + Vector3.UP * rise
		var r := random.randf_range(5.0, 8.0)
		var centre := finish + dir3 * r
		if not _landing_fits(centre, r, lo, hi, floor_y, top_y, landings, flights):
			continue
		if not _flight_clear(start, finish, landings, flights, parent, -1):
			continue
		landings.append({c = centre, r = r, links = 1, floor = false, alive = true})
		landings[parent].links += 1
		flights.append({a = start, b = finish, from = parent, to = landings.size() - 1})
	# ...then no dead ends: every landing with one way off gets another, or,
	# with nowhere for one to go, is taken away (and so on back).
	var changed := true
	var passes := 0
	while changed and passes < 50:
		changed = false
		passes += 1
		for i in range(1, landings.size()):
			if not landings[i].alive or landings[i].links >= 2:
				continue
			if not _link_landing(i, landings, flights, lo, hi, floor_y):
				_drop_landing(i, landings, flights)
			changed = true
	# ...and loops on top, up to PANIC_FLIGHTS in all.
	tries = 0
	while flights.size() < PANIC_FLIGHTS and tries < 200:
		tries += 1
		var i := 1 + random.randi() % maxi(landings.size() - 1, 1)
		if i < landings.size() and landings[i].alive:
			_link_landing(i, landings, flights, lo, hi, floor_y)
	var alive := 0
	var dead_ends := 0
	for l in landings:
		if not l.floor and l.alive:
			alive += 1
			if l.links < 2:
				dead_ends += 1
	panic_report.append({hall = group, landings = alive, flights = flights.size(), dead_ends = dead_ends})
	panic_tangles[group] = {landings = landings, flights = flights, lo = lo, hi = hi, floor_y = floor_y}
	# Built: flat landings at any turn, ramps (RAMP_SLOPE at most), growth on them all.
	for l in landings:
		if l.floor or not l.alive:
			continue
		var c: Vector3 = l.c
		var r: float = l.r
		_add(c + Vector3.DOWN, Vector3(r * 2.0, 2.0, r * 2.0), &"interior", group, &"plain", Basis(Vector3.UP, random.randf() * TAU))
		growth_floors.append({rect = Rect2(c.x - r * 0.7, c.z - r * 0.7, r * 1.4, r * 1.4), y = c.y, zone = group,
				kinds = HALL_GROWTH, density = 0.8 * HIVE_GROWTH, shaft = 0.0})
	for f in flights:
		var a: Vector3 = f.a
		var b: Vector3 = f.b
		var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
		var length := a.distance_to(b)
		_add((a + b) * 0.5 + basis.y * -1.0, Vector3(PANIC_WIDTH, 2.0, length + 1.5), &"interior", group, &"plain", basis)
		growth_floors.append({rect = Rect2(-PANIC_WIDTH * 0.5 + 0.5, -length * 0.5, PANIC_WIDTH - 1.0, length), y = 0.0, zone = group,
				kinds = HALL_GROWTH, density = 0.8 * HIVE_GROWTH, shaft = 0.0, xform = Transform3D(basis, (a + b) * 0.5)})
	growth_floors.append({rect = Rect2(box.position.x + 4.0, box.position.z + 4.0, box.size.x - 8.0, box.size.z - 8.0), y = floor_y,
			zone = group, kinds = HALL_GROWTH, density = 1.2 * HIVE_GROWTH, shaft = 0.0})
	for n in _nests_at(0.6, floor_y):
		nest_spots.append(Vector3(random.randf_range(box.position.x + 12.0, box.end.x - 12.0), floor_y, random.randf_range(box.position.z + 12.0, box.end.z - 12.0)))


## How many barnacle nests a spot at height y gets, for a `chance` at the
## bottom: NEST_TOP_DENSITY times that by the top of the tallest tower (the
## user's: barnacles more common the higher you go), so up there a floor can
## have two.
func _nests_at(chance: float, y: float) -> int:
	var up := clampf(y / float(TOWERS[0][3]), 0.0, 1.0)
	var expected := chance * lerpf(1.0, NEST_TOP_DENSITY, up)
	return int(expected) + (1 if random.randf() < expected - floorf(expected) else 0)


## Whether a landing (top middle `centre`, half size r) fits: inside the
## hall, between 8 m up and the top of the tangle, clear of the others
## (with headroom) and of every flight.
func _landing_fits(centre: Vector3, r: float, lo: Vector2, hi: Vector2, floor_y: float, top_y: float,
		landings: Array[Dictionary], flights: Array[Dictionary]) -> bool:
	if centre.x - r < lo.x or centre.x + r > hi.x or centre.z - r < lo.y or centre.z + r > hi.y:
		return false
	if centre.y < floor_y + 8.0 or centre.y > top_y:
		return false
	for other in landings:
		if other.floor or not other.alive:
			continue
		var at: Vector3 = other.c
		if Vector2(at.x - centre.x, at.z - centre.z).length() < r + float(other.r) + 3.0 and absf(at.y - centre.y) < 9.0:
			return false
	for f in flights:
		if _point_to_segment(centre, f.a, f.b) < r + 4.0:
			return false
	return true


## Whether a flight from `a` to `b` (joining landings `from` and `to`, -1
## for none yet) keeps clear of every other landing and flight.
func _flight_clear(a: Vector3, b: Vector3, landings: Array[Dictionary], flights: Array[Dictionary], from: int, to: int) -> bool:
	for i in landings.size():
		var l: Dictionary = landings[i]
		if i == from or i == to or l.floor or not l.alive:
			continue
		if _point_to_segment(l.c, a, b) < float(l.r) + 3.0:
			return false
	for f in flights:
		var shares: bool = f.from == from or f.to == from or (to >= 0 and (f.from == to or f.to == to))
		if not shares and _segment_gap(a, b, f.a, f.b) < 7.0:
			return false
	return true


## One more flight off landing i: to the nearest landing it isn't joined to
## that a flight (RAMP_SLOPE at most, 6-90 m) can reach clear, or else down
## to the floor. False if there's nowhere.
func _link_landing(i: int, landings: Array[Dictionary], flights: Array[Dictionary], lo: Vector2, hi: Vector2, floor_y: float) -> bool:
	var steep := tan(deg_to_rad(RAMP_SLOPE))
	var c: Vector3 = landings[i].c
	var r: float = landings[i].r
	var best := -1
	var best_ends := []
	var best_flat := INF
	for j in range(1, landings.size()):
		var other: Dictionary = landings[j]
		if j == i or not other.alive or _joined(i, j, flights):
			continue
		var oc: Vector3 = other.c
		var dir := Vector3(oc.x - c.x, 0.0, oc.z - c.z).normalized()
		var a := c + dir * r
		var b := oc - dir * float(other.r)
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		if flat < 6.0 or flat > 90.0 or absf(b.y - a.y) > flat * steep or flat >= best_flat:
			continue
		if _flight_clear(a, b, landings, flights, i, j):
			best = j
			best_ends = [a, b]
			best_flat = flat
	if best < 0 and not _joined(i, 0, flights):
		# Down to the floor.
		var run := (c.y - floor_y) / steep * 1.05
		for k in 8:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, random.randf() * TAU)
			var a := c + dir * r
			var b := a + dir * run
			b.y = floor_y
			if b.x < lo.x or b.x > hi.x or b.z < lo.y or b.z > hi.y:
				continue
			if _flight_clear(a, b, landings, flights, i, 0):
				best = 0
				best_ends = [a, b]
				break
	if best < 0:
		return false
	flights.append({a = best_ends[0], b = best_ends[1], from = i, to = best})
	landings[i].links += 1
	landings[best].links += 1
	return true


static func _joined(i: int, j: int, flights: Array[Dictionary]) -> bool:
	for f in flights:
		if (f.from == i and f.to == j) or (f.from == j and f.to == i):
			return true
	return false


## Takes landing i away, and the flights to it.
static func _drop_landing(i: int, landings: Array[Dictionary], flights: Array[Dictionary]) -> void:
	landings[i].alive = false
	for k in range(flights.size() - 1, -1, -1):
		var f: Dictionary = flights[k]
		if f.from == i or f.to == i:
			var other: int = f.to if f.from == i else f.from
			landings[other].links -= 1
			flights.remove_at(k)


static func _point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The least distance between two segments.
static func _segment_gap(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.length_squared()
	var e := d2.length_squared()
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.0001 and e <= 0.0001:
		return p1.distance_to(p2)
	if a <= 0.0001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.0001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 0.0001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## Cobwebs (the user's): rare, still, pale. Inside, about one for every two
## halls, strung across a corner of a hall or a window room -- most 2-6 m
## across, now and then (in a hall) one 15-30 m. Outside, two a tower,
## huge (15-30 m), across the corner where a block's top meets the wall
## above it. Each has its spiders (Megastructure.webs): more for a bigger web.
func _cobwebs() -> void:
	var spots: Array = [] # [room, can be huge]
	for hall in halls:
		spots.append([hall.box, true])
	for w in window_rooms:
		spots.append([w.room, false])
	# One for about every two halls inside (50% more than every three: the user's).
	var count := roundi(halls.size() / 2.0)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12:
		tries += 1
		var spot: Array = spots[random.randi() % spots.size()]
		var room: AABB = spot[0]
		var huge: bool = spot[1] and random.randf() < WEB_HUGE_CHANCE
		var width := minf(random.randf_range(15.0, 30.0) if huge else random.randf_range(2.0, 6.0), minf(room.size.x, room.size.z) * 0.5)
		var tall := width * random.randf_range(0.6, 0.9)
		var sx := 1.0 if random.randf() < 0.5 else -1.0
		var sz := 1.0 if random.randf() < 0.5 else -1.0
		var corner := Vector3(room.position.x if sx > 0.0 else room.end.x, room.position.y, room.position.z if sz > 0.0 else room.end.z)
		var inward := Vector3(sx, 0.0, sz)
		# Its ends on the two walls, its foot on the floor.
		var centre := corner + inward * width * 0.3536 + Vector3.UP * (tall * 0.5 + 0.2)
		if _anything_at(AABB(centre - Vector3(width * 0.4, tall * 0.5, width * 0.4), Vector3(width * 0.8, tall, width * 0.8))):
			continue
		var along := Vector3(sx, 0.0, -sz).normalized() * (1.0 if random.randf() < 0.5 else -1.0)
		web_quads.append({xform = Transform3D(Basis(along * width, Vector3.UP * tall, inward.normalized()), centre),
				variant = random.randi() % COBWEBS.size(), indoors = true})
		web_nests.append({at = corner + inward * (width * 0.3536 + 3.0), size = width, indoors = true,
				radius = lerpf(20.0, 50.0, clampf(inverse_lerp(2.0, 30.0, width), 0.0, 1.0))})
		placed += 1
	# Outside: on the ledges where a tower steps in.
	for t in TOWERS.size():
		var own: Array[Dictionary] = []
		for b in blocks:
			if b.tower == t:
				own.append(b)
		own.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.c as Vector3).y < (b.c as Vector3).y)
		var ledges: Array = [] # [the edge's middle, out, cross, ledge depth, upper block's half width along it]
		for k in range(1, own.size()):
			var lower: Dictionary = own[k - 1]
			var upper: Dictionary = own[k]
			var y: float = (upper.c as Vector3).y - (upper.s as Vector3).y * 0.5
			for side in 4:
				var depth := _box_face(lower, side) - _box_face(upper, side)
				if depth < 12.0:
					continue
				var out := _outward(side)
				var cross := Vector3(out.z, 0.0, out.x).abs()
				var edge := Vector3((upper.c as Vector3).x, y, (upper.c as Vector3).z) + out * _box_face(upper, side)
				ledges.append([edge, out, cross, depth, ((upper.s as Vector3).z if side >= 2 else (upper.s as Vector3).x) * 0.5])
		ledges.shuffle()
		var made := 0
		for ledge: Array in ledges:
			if made >= WEBS_OUTSIDE:
				break
			var out: Vector3 = ledge[1]
			var cross: Vector3 = ledge[2]
			var depth: float = ledge[3]
			var edge: Vector3 = ledge[0] + cross * random.randf_range(-0.6, 0.6) * float(ledge[4])
			var width := random.randf_range(15.0, 30.0)
			var tall := minf(width * random.randf_range(0.6, 0.9), depth * 1.3)
			var centre := edge + (out + Vector3.UP) * tall * 0.3536
			if not _outside(centre) or not _outside(edge + (out + Vector3.UP) * 2.0):
				continue
			web_quads.append({xform = Transform3D(Basis(cross * width, (Vector3.UP - out).normalized() * tall, (Vector3.UP + out).normalized()), centre),
					variant = random.randi() % COBWEBS.size(), indoors = false})
			web_nests.append({at = edge + out * depth * 0.5, size = width, indoors = false,
					radius = minf(lerpf(20.0, 50.0, clampf(inverse_lerp(2.0, 30.0, width), 0.0, 1.0)), depth * 0.5 - 2.0)})
			made += 1


## How far a box's face on `side` is from its tower's middle.
static func _box_face(b: Dictionary, side: int) -> float:
	var c: Vector3 = b.c
	var s: Vector3 = b.s
	var t: int = b.tower
	match side:
		0: return TOWERS[t][1] - (c.z - s.z * 0.5)
		1: return (c.z + s.z * 0.5) - TOWERS[t][1]
		2: return TOWERS[t][0] - (c.x - s.x * 0.5)
	return (c.x + s.x * 0.5) - TOWERS[t][0]


## Whether anything built inside (a floor, a ramp, a column...) is in `area`.
func _anything_at(area: AABB) -> bool:
	for b in boxes:
		if b.part != &"interior":
			continue
		var basis: Basis = b.b
		var half: Vector3 = (b.s as Vector3) * 0.5
		var extent := Vector3(
				absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z,
				absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z,
				absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z)
		if AABB((b.c as Vector3) - extent, extent * 2.0).intersects(area):
			return true
	return false

# ---- The heart's cathedral (the user's, 2026-10-17) -----------------------------------

## The heart boss's room, on top of the hive: one huge hall the way the
## procedural Stacks made theirs (this builder's own hall, run in a box
## 1/CATHEDRAL_SCALE its size and everything scaled back up) -- 500 m tall,
## 300 m across (280 inside the walls), its middle CATHEDRAL_CLEAR across left
## open for the heart and the fight (mezzanines, their ramps, the leaning
## slab round the walls; no columns, mid-air stairs or hanging pyramid in it).
## The Stack's concrete, the hive's growth creeping in round its floor's edges.
## Right over the hive's top hall: the panic stairs there carry on up through
## a hole in its floor. From outside, a torn-open gap CATHEDRAL_GAP across,
## CATHEDRAL_GAP_UP up one wall (the side the dice pick); two slit windows on
## opposite walls. The hive steps out to it in CATHEDRAL_TIERS tiers from
## CATHEDRAL_TIERS_FROM up, its holes, windows and secrets kept open through
## them. Its own dice (like the secrets'), so nothing else in the Stack moves.
const CATHEDRAL_TALL := 500.0
const CATHEDRAL_WIDTH := 300.0
const CATHEDRAL_ROOF := 20.0
const CATHEDRAL_CLEAR := 160.0
const CATHEDRAL_SCALE := 1.5
const CATHEDRAL_TIERS := 4
const CATHEDRAL_TIERS_FROM := 3500.0
const CATHEDRAL_GAP := 30.0
const CATHEDRAL_GAP_UP := 165.0
const CATHEDRAL_SLIT := Vector2(3.0, 60.0) # wide, tall
const CATHEDRAL_SLIT_UP := 10.0
## How high the heart hangs over the cathedral floor (m).
const HEART_HANG := 100.0
## Its song's beat map (the beat mapper's), if it's there.
const HEART_MAP := "res://audio/music/Freddie Gibbs & The Alchemist - Skinny Suge II (Official Visualizer).beats.tres"
## The room (floor to ceiling, local), once built; empty before.
var cathedral := AABB()
## Where the stairs come up onto its floor, facing in (local): a marker in
## the scene (CathedralSpawn) the player can start at while testing.
var cathedral_entry := Transform3D()
var cathedral_random := RandomNumberGenerator.new()
var cathedral_report := {}
## What the skybridges keep clear of: the cathedral and the tiers under it.
var bridge_avoid: Array[AABB] = []
## Each hive hall's tangle (_panic_stairs): {landings, flights, lo, hi, floor_y}.
var panic_tangles := {}
## The cathedral's block and its tiers, as tower blocks (for the growth up
## their outsides) -- added to `blocks` once nothing else reads them.
var cathedral_blocks: Array[Dictionary] = []


func _cathedral() -> void:
	cathedral_random.seed = SEED + 999
	var centre := Vector2(TOWERS[HIVE][0], TOWERS[HIVE][1])
	var middle := Vector3(centre.x, 0.0, centre.y)
	var top_hall: Dictionary = {}
	for hall in halls:
		if hall.tower == HIVE and (top_hall.is_empty() or (hall.box as AABB).end.y > (top_hall.box as AABB).end.y):
			top_hall = hall
	if top_hall.is_empty():
		return
	var base_y: float = (top_hall.box as AABB).end.y
	var floor_y := base_y + SLAB
	var half := CATHEDRAL_WIDTH * 0.5
	var hive_blocks: Array[AABB] = []
	for b in blocks:
		if b.tower == HIVE:
			hive_blocks.append(AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s))
	# The hive's old top, over its top hall, makes way for the cathedral's block.
	_carve(AABB(Vector3(centre.x - half - 10.0, base_y, centre.y - half - 10.0),
			Vector3(CATHEDRAL_WIDTH + 20.0, float(TOWERS[HIVE][3]) - base_y + 10.0, CATHEDRAL_WIDTH + 20.0)))
	var block := AABB(Vector3(centre.x - half, base_y, centre.y - half), Vector3(CATHEDRAL_WIDTH, SLAB + CATHEDRAL_TALL + CATHEDRAL_ROOF, CATHEDRAL_WIDTH))
	_add(block.get_center(), block.size, &"shell", "Tower_%d" % HIVE, &"concrete", Basis.IDENTITY, true, HIVE)
	cathedral_blocks.append(boxes[boxes.size() - 1].duplicate())
	var room := AABB(Vector3(centre.x - half + HALL_WALL, floor_y, centre.y - half + HALL_WALL),
			Vector3(CATHEDRAL_WIDTH - HALL_WALL * 2.0, CATHEDRAL_TALL, CATHEDRAL_WIDTH - HALL_WALL * 2.0))
	_carve(room)
	cathedral = room
	bridge_avoid.append(block.grow(BRIDGE_MARGIN))
	var walled: Array[AABB] = [block]
	# The tiers: the hive stepping out to it, each wider than the last; every
	# tier the hive's blocks taken out (no faces doubled up on its walls), and
	# slots cut through them wherever something opens out of the hive.
	var cutters: Array[AABB] = hive_blocks.duplicate()
	for hole in hive_holes:
		var at: Vector3 = hole.at
		var out: Vector3 = hole.normal
		var size: Vector2 = hole.size
		if at.y > CATHEDRAL_TIERS_FROM - size.y and at.y < base_y + size.y:
			cutters.append(_span(at - out * 2.0, at + out * (half + 20.0), Vector3(out.z, 0.0, out.x).abs(), size.x, at.y - size.y * 0.5, size.y))
	for window in window_rooms:
		var at: Vector3 = window.at
		var out: Vector3 = window.normal
		var size: Vector2 = window.size
		if Vector2(at.x, at.z).distance_to(centre) < half and at.y > CATHEDRAL_TIERS_FROM - size.y and at.y < base_y + size.y:
			cutters.append(_span(at - out, at + out * (half + 20.0), Vector3(out.z, 0.0, out.x).abs(), size.x + 4.0, at.y - size.y * 0.5 - 2.0, size.y + 4.0))
	for grown in secret_blocks:
		var d := Vector2(grown.get_center().x - centre.x, grown.get_center().z - centre.y)
		if d.length() > half + 30.0 or grown.end.y < CATHEDRAL_TIERS_FROM or grown.position.y > base_y:
			continue
		var slot := grown.grow(4.0)
		if absf(d.x) > absf(d.y):
			slot = slot.merge(AABB(Vector3(centre.x + signf(d.x) * (half + 20.0), slot.position.y, slot.position.z), Vector3(0.1, slot.size.y, slot.size.z)))
		else:
			slot = slot.merge(AABB(Vector3(slot.position.x, slot.position.y, centre.y + signf(d.y) * (half + 20.0)), Vector3(slot.size.x, slot.size.y, 0.1)))
		cutters.append(slot)
	var widest := 0.0
	for box in hive_blocks:
		if box.end.y > CATHEDRAL_TIERS_FROM and box.position.y < base_y:
			widest = maxf(widest, 2.0 * maxf(maxf(box.end.x - centre.x, centre.x - box.position.x), maxf(box.end.z - centre.y, centre.y - box.position.z)))
	var tier_tall := (base_y - CATHEDRAL_TIERS_FROM) / CATHEDRAL_TIERS
	var tier_pieces := 0
	for k in CATHEDRAL_TIERS:
		var width := lerpf(widest, CATHEDRAL_WIDTH, float(k + 1) / CATHEDRAL_TIERS)
		var tier := AABB(Vector3(centre.x - width * 0.5, CATHEDRAL_TIERS_FROM + tier_tall * k, centre.y - width * 0.5), Vector3(width, tier_tall, width))
		var pieces: Array[AABB] = [tier]
		for cutter in cutters:
			var next: Array[AABB] = []
			for piece in pieces:
				if not piece.intersects(cutter):
					next.append(piece)
					continue
				for bit in _subtract(piece, cutter):
					if minf(bit.size.x, minf(bit.size.y, bit.size.z)) > 0.05:
						next.append(bit)
			pieces = next
		for piece in pieces:
			_add(piece.get_center(), piece.size, &"shell", "Tower_%d" % HIVE, &"stained", Basis.IDENTITY, true, HIVE)
		tier_pieces += pieces.size()
		cathedral_blocks.append({c = tier.get_center(), s = tier.size, tower = HIVE, mat = &"stained"})
		bridge_avoid.append(tier.grow(BRIDGE_MARGIN))
		walled.append(tier)
	# Cobwebs left outside on ledges the tiers and the cathedral now fill.
	web_quads.assign(web_quads.filter(func(w: Dictionary) -> bool: return w.indoors or not _within((w.xform as Transform3D).origin, walled)))
	web_nests.assign(web_nests.filter(func(w: Dictionary) -> bool: return w.indoors or not _within(w.at, walled)))
	# The hall itself: the procedural Stacks' way, its middle left open.
	var small := AABB(room.position / CATHEDRAL_SCALE, room.size / CATHEDRAL_SCALE)
	var inside := StackBuilder.new(false)
	inside.random.seed = SEED + 998
	inside._hall_features({tower = -1, box = small, name = "Cathedral", open = CATHEDRAL_CLEAR * 0.5 / CATHEDRAL_SCALE, growth = HIVE_GROWTH})
	var scale := CATHEDRAL_SCALE
	for b in inside.boxes:
		boxes.append({c = (b.c as Vector3) * scale, s = (b.s as Vector3) * scale, b = b.b, part = b.part, solid = false,
				tower = -1, group = "Cathedral", mat = b.mat})
	for f in inside.growth_floors:
		var g: Dictionary = f.duplicate()
		var rect: Rect2 = f.rect
		g.rect = Rect2(rect.position * scale, rect.size * scale)
		g.y = float(f.y) * scale
		g.zone = "Cathedral"
		if f.has("open_at"):
			g["open"] = float(f["open"]) * scale
			g["open_at"] = (f["open_at"] as Vector2) * scale
		growth_floors.append(g)
	for spot in inside.nest_spots:
		nest_spots.append(spot * scale)
	for o in inside.nest_objects:
		nest_objects.append(AABB(o.position * scale, o.size * scale))
	for lamp: Array in inside.lamps:
		lamps.append([(lamp[0] as Vector3) * scale, lamp[1], lamp[2], float(lamp[3]) * scale])
	# Two slit windows, on opposite walls (which pair: the dice), centred.
	var sides: Array = [0, 1] if cathedral_random.randi() % 2 == 0 else [2, 3]
	for side: int in sides:
		var out := _outward(side)
		var cross := Vector3(out.z, 0.0, out.x).abs()
		_carve(_span(middle + out * (half - HALL_WALL - 1.0), middle + out * (half + 3.0), cross, CATHEDRAL_SLIT.x, floor_y + CATHEDRAL_SLIT_UP, CATHEDRAL_SLIT.y))
		openings.append(middle + out * half + Vector3.UP * (floor_y + CATHEDRAL_SLIT_UP + CATHEDRAL_SLIT.y * 0.5))
	# The torn-open gap: a third of the way up one wall, ragged round its rim.
	var gap_side := cathedral_random.randi() % 4
	var gap_out := _outward(gap_side)
	var gap_cross := Vector3(gap_out.z, 0.0, gap_out.x).abs()
	var reach := half - HALL_WALL - CATHEDRAL_GAP
	var gap_mid := middle + gap_cross * cathedral_random.randf_range(-reach, reach)
	var gap := _span(gap_mid + gap_out * (half - HALL_WALL - 1.0), gap_mid + gap_out * (half + 3.0), gap_cross, CATHEDRAL_GAP, floor_y + CATHEDRAL_GAP_UP, CATHEDRAL_GAP)
	_carve(gap)
	for k in 3:
		var size := gap.size * Vector3(cathedral_random.randf_range(0.35, 0.6), cathedral_random.randf_range(0.35, 0.6), cathedral_random.randf_range(0.35, 0.6))
		var at := gap.position + gap.size * Vector3(cathedral_random.randf(), cathedral_random.randf(), cathedral_random.randf())
		_carve(AABB(at - size * 0.5, size))
	var mouth := gap_mid + gap_out * half + Vector3.UP * (floor_y + CATHEDRAL_GAP_UP + CATHEDRAL_GAP * 0.5)
	openings.append(mouth)
	hive_holes.append({at = mouth, normal = gap_out, size = Vector2(CATHEDRAL_GAP, CATHEDRAL_GAP)})
	growth_floors.append({rect = Rect2(gap.position.x, gap.position.z, gap.size.x, gap.size.z), y = gap.position.y, zone = "Cathedral",
			kinds = HALL_GROWTH, density = 2.0 * HIVE_GROWTH, shaft = 0.0})
	# Up from the hive's top hall: its panic stairs carry on, through the floor.
	var stairs := _panic_up(panic_tangles.get(top_hall.name, {}), top_hall.name, base_y, floor_y, room)
	halls.append({tower = HIVE, box = room, name = "Cathedral"})
	if cathedral_entry.origin == Vector3.ZERO:
		# (No way up through the floor: by the -Z wall, facing in.)
		cathedral_entry = Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(middle.x, floor_y, room.position.z + 12.0))
	cathedral_report = {floor = floor_y, roof = block.end.y, room = room.size, tiers = CATHEDRAL_TIERS, tier_pieces = tier_pieces,
			hive_width = snappedf(widest, 0.1), gap_side = gap_side, slit_sides = sides, stairs = stairs}


## The hive's top hall's tangle (_panic_stairs) grown on up, from its highest
## landings, to just under the ceiling, then one last flight up through a
## hole in the cathedral's floor onto it. What happened, for the report.
func _panic_up(tangle: Dictionary, group: String, ceiling: float, floor_y: float, room: AABB) -> String:
	if tangle.is_empty():
		return "no tangle"
	var landings: Array[Dictionary] = tangle.landings
	var flights: Array[Dictionary] = tangle.flights
	var lo: Vector2 = tangle.lo
	var hi: Vector2 = tangle.hi
	var hall_floor: float = tangle.floor_y
	var first_landing := landings.size()
	var first_flight := flights.size()
	var target := ceiling - 16.0
	var highest := -1
	for _try in 4000:
		var order: Array[int] = []
		for i in landings.size():
			if landings[i].alive and not landings[i].floor:
				order.append(i)
		if order.is_empty():
			break
		order.sort_custom(func(a: int, b: int) -> bool: return (landings[a].c as Vector3).y > (landings[b].c as Vector3).y)
		highest = order[0]
		if (landings[highest].c as Vector3).y >= target:
			break
		var parent: int = order[cathedral_random.randi() % mini(4, order.size())]
		var dir := Vector2.from_angle(cathedral_random.randf() * TAU)
		var dir3 := Vector3(dir.x, 0.0, dir.y)
		var slope := deg_to_rad(cathedral_random.randf_range(16.0, RAMP_SLOPE))
		var length := cathedral_random.randf_range(14.0, 34.0)
		var start: Vector3 = (landings[parent].c as Vector3) + dir3 * float(landings[parent].r)
		var finish := start + dir3 * length * cos(slope) + Vector3.UP * length * sin(slope)
		var r := cathedral_random.randf_range(5.0, 8.0)
		var c := finish + dir3 * r
		if not _landing_fits(c, r, lo, hi, hall_floor, ceiling - 10.0, landings, flights):
			continue
		if not _flight_clear(start, finish, landings, flights, parent, -1):
			continue
		landings.append({c = c, r = r, links = 1, floor = false, alive = true})
		landings[parent].links += 1
		flights.append({a = start, b = finish, from = parent, to = landings.size() - 1})
	if highest < 0:
		return "no landings"
	# The last flight, straight along one of the walls' ways (so its hole is a
	# clean slot), from one of the top landings up onto the cathedral floor --
	# out past the top hall's walls if it must, through a channel cut in
	# their top.
	var tops: Array[int] = []
	for i in landings.size():
		if landings[i].alive and not landings[i].floor and (landings[i].c as Vector3).y >= target - 20.0:
			tops.append(i)
	tops.sort_custom(func(a: int, b: int) -> bool: return (landings[a].c as Vector3).y > (landings[b].c as Vector3).y)
	var top: Dictionary = landings[highest]
	var placed := false
	# Clear of everything if it can be; then just clear of the landings (it
	# may brush a flight below); then anyhow -- there's always a way up.
	for strict in [2, 1, 0]:
		if placed:
			break
		for i in tops:
			var from: Dictionary = landings[i]
			var rise := floor_y - (from.c as Vector3).y
			var run := rise / tan(deg_to_rad(RAMP_SLOPE))
			var turn := cathedral_random.randi() % 4
			for k in 4:
				var out := _outward((k + turn) % 4)
				var start: Vector3 = (from.c as Vector3) + out * float(from.r)
				var finish := start + out * run + Vector3.UP * rise
				if not Rect2(room.position.x, room.position.z, room.size.x, room.size.z).grow(-10.0).has_point(Vector2(finish.x, finish.z)):
					continue
				if strict == 2 and not _flight_clear(start, finish, landings, flights, i, -1):
					continue
				if strict == 1 and not _flight_clear(start, finish, landings, [], i, -1):
					continue
				flights.append({a = start, b = finish, from = i, to = -1})
				landings[i].links += 1
				var bottom := minf(start.y - 3.0, ceiling - 1.0)
				_carve(_span(start, finish - out * 0.5, Vector3(out.z, 0.0, out.x).abs(), PANIC_WIDTH + 4.0, bottom, floor_y + 1.0 - bottom))
				cathedral_entry = Transform3D(Basis.looking_at(out, Vector3.UP), finish + out * 3.0)
				top = from
				placed = true
				break
			if placed:
				break
	# Built like the rest of the tangle.
	for i in range(first_landing, landings.size()):
		var l: Dictionary = landings[i]
		var c: Vector3 = l.c
		var r: float = l.r
		_add(c + Vector3.DOWN, Vector3(r * 2.0, 2.0, r * 2.0), &"interior", group, &"plain", Basis(Vector3.UP, cathedral_random.randf() * TAU))
		growth_floors.append({rect = Rect2(c.x - r * 0.7, c.z - r * 0.7, r * 1.4, r * 1.4), y = c.y, zone = group,
				kinds = HALL_GROWTH, density = 0.8 * HIVE_GROWTH, shaft = 0.0})
	for i in range(first_flight, flights.size()):
		var a: Vector3 = flights[i].a
		var b: Vector3 = flights[i].b
		var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
		_add((a + b) * 0.5 + basis.y * -1.0, Vector3(PANIC_WIDTH, 2.0, a.distance_to(b) + 1.5), &"interior", group, &"plain", basis)
	var reached := "%d flights up to %.0f m" % [flights.size() - first_flight, (top.c as Vector3).y]
	return reached + (", through the floor" if placed else ", NO way through the floor (grapple)")


## Whether `point` is inside any of `spaces` (a little grown).
static func _within(point: Vector3, spaces: Array[AABB]) -> bool:
	for space in spaces:
		if space.grow(2.0).has_point(point):
			return true
	return false


## A tower's top (the hive's: its cathedral's roof, once built).
func _top(t: int) -> float:
	if t == HIVE and cathedral.size != Vector3.ZERO:
		return cathedral.end.y + CATHEDRAL_ROOF
	return TOWERS[t][3]


# ---- Secrets (the user's, 2026-10-17) ----------------------------------------------------

## Thirty secret doors: SECRET_LOOT to loot rooms, SECRET_SHORTCUTS to hidden
## shafts up to a hall's mezzanine (grapple up them), SECRET_ENTRANCES into
## the towers from outside. Half open with a key (any key: universal, used
## up), half with a button within BUTTON_REACH of the door. The rooms and
## shafts are new blocks grown onto the towers' outsides -- merging out of a
## wall (sunk GROWN_SINK into it), the building's windowed concrete or plain,
## half and half -- every one clear of windows, ways in, bridges and each
## other. Doors are person-size (DOOR). Its own dice, so nothing else in the
## Stack moves.
const SECRET_LOOT := 14
const SECRET_SHORTCUTS := 10
const SECRET_ENTRANCES := 6
const SECRET_KEY_DOORS := 15
const DOOR := Vector2(2.0, 3.0)
const SECRET_ROOM := Vector3(12.0, 8.0, 12.0) # across, tall, out
const SHAFT_INNER := 5.0
const GROWN_WALL := 2.0
const GROWN_SINK := 4.0
const BUTTON_REACH := 40.0
const BUTTON_HEIGHT := 1.3
const HALL_KEY_SPOTS := 60
const CLIMBER_SPOTS := 16
## Scattered (the user's): dealt out to the towers in turn, and never within
## SECRET_SPACING of another secret.
const SECRET_SPACING := 150.0
var secret_points := PackedVector3Array()

var secret_random := RandomNumberGenerator.new()


func _secrets() -> void:
	secret_random.seed = SEED + 777
	# The pickiest first: shortcuts need a hall floor under a mezzanine, and
	# loot rooms can go up on the mezzanines too.
	var kinds: Array[String] = []
	for i in SECRET_SHORTCUTS:
		kinds.append("shortcut")
	for i in SECRET_ENTRANCES:
		kinds.append("entrance")
	for i in SECRET_LOOT:
		kinds.append("loot")
	var locks: Array[int] = []
	for i in kinds.size():
		locks.append(SecretDoor.Lock.KEY if i < SECRET_KEY_DOORS else SecretDoor.Lock.BUTTON)
	_secret_shuffle(locks)
	var usable_halls: Array[Dictionary] = []
	var by_tower := {}
	for hall in halls:
		if hall.tower != STUMP:
			usable_halls.append(hall)
			if not by_tower.has(hall.tower):
				by_tower[hall.tower] = []
			(by_tower[hall.tower] as Array).append(hall)
	var towers: Array = by_tower.keys()
	towers.sort()
	for i in kinds.size():
		var own: Array = by_tower[towers[i % towers.size()]]
		for attempt in 3000:
			secret_report.tries += 1
			# Its tower's turn first; anywhere, if its tower has no room left.
			var pool: Array = own if attempt < 600 else usable_halls
			var hall: Dictionary = pool[secret_random.randi() % pool.size()]
			var done := false
			match kinds[i]:
				"loot":
					done = _secret_room(hall, locks[i], false)
				"entrance":
					done = _secret_room(hall, locks[i], true)
				"shortcut":
					done = _secret_shaft(hall, locks[i])
			if done:
				secret_report[kinds[i]] += 1
				secret_points.append((secrets[secrets.size() - 1].hinge as Transform3D).origin)
				break
	_key_and_climber_spots()


func _secret_shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := secret_random.randi_range(0, i)
		var keep: Variant = list[i]
		list[i] = list[j]
		list[j] = keep


## A way through a hall's wall on `side` at floor y, `along` it: where it
## meets the hall (edge), the tower's face there, the passage's box -- or {}
## if there's no clean way (too thin, something in front of it, something
## already carved there).
func _secret_way(hall: Dictionary, side: int, along: float, y: float, check_front: bool = true, spaced: bool = true) -> Dictionary:
	var t: int = hall.tower
	var box: AABB = hall.box
	if _fused(t, side, y):
		return {}
	var out := _outward(side)
	var cross := Vector3(out.z, 0.0, out.x).abs()
	var hall_reach := (box.size.x if side >= 2 else box.size.z) * 0.5
	var hall_wide := (box.size.z if side >= 2 else box.size.x) * 0.5
	if absf(along) > hall_wide - 8.0:
		return {}
	var centre := Vector3(box.get_center().x, y, box.get_center().z) + cross * along
	var edge := centre + out * hall_reach
	if spaced:
		for other in secret_points:
			if other.distance_to(edge) < SECRET_SPACING:
				return {}
	var face := _face(t, y + DOOR.y, side)
	if face - hall_reach < 4.0:
		return {}
	var passage := _span(edge - out * 0.1, centre + out * (face + 0.6), cross, DOOR.x, y, DOOR.y)
	for space in carved:
		if space != box and space.intersects(passage.grow(1.0)):
			return {}
	if check_front and _anything_at(_span(edge - out * 6.0, edge - out * 0.2, cross, DOOR.x + 2.0, y + 0.3, DOOR.y)):
		return {}
	return {edge = edge, out = out, cross = cross, face = face, passage = passage, centre = centre, tower = t}


## A grown block outside a tower's face: whether `block` (all of it past the
## face) is open air -- no other box, window, way in, landing, crossing or
## grown block in it.
func _grown_fits(block: AABB, out: Vector3, face_point: Vector3) -> bool:
	var outside := block
	# Only the part past the face (the sunk part's in the wall).
	var lo := block.position
	var hi := block.end
	for k in 3:
		if absf(out[k]) > 0.5:
			if out[k] > 0.0:
				lo[k] = maxf(lo[k], face_point[k] + 0.3)
			else:
				hi[k] = minf(hi[k], face_point[k] - 0.3)
	outside = AABB(lo, hi - lo)
	if outside.size.x <= 0.0 or outside.size.y <= 0.0 or outside.size.z <= 0.0:
		return false
	if block.position.y < 30.0:
		return false # (clear of the ground and the base's ways in)
	var wide := outside.grow(6.0)
	for b in boxes:
		var basis: Basis = b.b
		var half: Vector3 = (b.s as Vector3) * 0.5
		var extent := Vector3(
				absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z,
				absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z,
				absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z)
		if AABB((b.c as Vector3) - extent, extent * 2.0).intersects(outside):
			return false
	for w in window_rooms:
		if wide.has_point(w.at):
			return false
	for opening in openings:
		if wide.has_point(opening):
			return false
	for space in carved:
		if space.intersects(outside):
			return false
	for grown in secret_blocks:
		if grown.grow(10.0).intersects(block):
			return false
	for landing in lift_landings:
		if landing.intersects(wide):
			return false
	if crossing_clear.size != Vector3.ZERO and crossing_clear.intersects(wide):
		return false
	return true


## A grown block's box: `inner` (across, tall, out) of room past the face,
## its walls round it, sunk into the tower.
func _grown_box(way: Dictionary, y: float, inner: Vector3) -> AABB:
	var out: Vector3 = way.out
	var cross: Vector3 = way.cross
	var face_point: Vector3 = way.centre + out * (way.face as float)
	var near := face_point - out * GROWN_SINK
	var far := face_point + out * (inner.z + GROWN_WALL)
	return _span(near, far, cross, inner.x + GROWN_WALL * 2.0, y - GROWN_WALL - 2.0, inner.y + GROWN_WALL * 2.0 + 2.0)


func _grown_inside(way: Dictionary, y: float, inner: Vector3) -> AABB:
	var out: Vector3 = way.out
	var face_point: Vector3 = way.centre + out * (way.face as float)
	return _span(face_point - out * 0.2, face_point + out * inner.z, way.cross, inner.x, y, inner.y)


func _grown_add(block: AABB, t: int) -> StringName:
	var mat: StringName = &"concrete" if secret_random.randf() < 0.5 else &"plain"
	_add(block.get_center(), block.size, &"shell", "Secrets", mat, Basis.IDENTITY, true, t)
	secret_blocks.append(block)
	return mat


## A loot room (or, `entrance`, a way in from outside): a grown room on the
## hall's tower at its floor, a passage through the wall to it. A loot
## room's door is in the hall's wall; an entrance's is on the room's outside
## (a balcony in front of it to grapple onto), its passage to the hall open.
func _secret_room(hall: Dictionary, lock: int, entrance: bool) -> bool:
	var box: AABB = hall.box
	var side := secret_random.randi() % 4
	var hall_wide := (box.size.z if side >= 2 else box.size.x) * 0.5
	var along := secret_random.randf_range(-hall_wide + 10.0, hall_wide - 10.0)
	var y := box.position.y
	var check_front := not entrance
	# Half the time up on one of the hall's mezzanines instead, through the
	# wall it's against (spreads them up the halls, not just their floors).
	var own: Array[Dictionary] = []
	for d in decks:
		if d.hall == hall:
			own.append(d)
	if not own.is_empty() and secret_random.randf() < 0.5:
		var deck: Dictionary = own[secret_random.randi() % own.size()]
		side = deck.side
		along = secret_random.randf_range(-(deck.span as float) * 0.4, (deck.span as float) * 0.4)
		y = deck.y
		check_front = false # (the deck's in front of it)
	var way := _secret_way(hall, side, along, y, check_front)
	if way.is_empty():
		return false
	var block := _grown_box(way, y, SECRET_ROOM)
	var face_point: Vector3 = way.centre + (way.out as Vector3) * (way.face as float)
	if not _grown_fits(block, way.out, face_point):
		return false
	var room := _grown_inside(way, y, SECRET_ROOM)
	var door := {}
	if entrance:
		# The door on the room's outside, a balcony in front of it.
		var out: Vector3 = way.out
		var outer: Vector3 = face_point + out * (SECRET_ROOM.z + GROWN_WALL)
		var balcony := _span(outer, outer + out * 5.0, way.cross, 12.0, y - 1.0, 1.0)
		for b in boxes:
			if AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s).intersects(balcony.grow(1.0)):
				return false
		var mat := _grown_add(block, way.tower)
		_carve(room)
		_carve(way.passage)
		_carve(_span(outer - out * (GROWN_WALL + 0.6), outer + out * 0.6, way.cross, DOOR.x, y, DOOR.y))
		_add(balcony.get_center(), balcony.size, &"shell", "Secrets", &"plain")
		door = _secret_door(outer, -out, way.cross, y, lock, mat, "entrance")
		if lock == SecretDoor.Lock.BUTTON:
			var side_way := 1.0 if secret_random.randf() < 0.5 else -1.0
			var at: Vector3 = outer + (way.cross as Vector3) * side_way * secret_random.randf_range(3.5, 5.5) + Vector3.UP * (y + BUTTON_HEIGHT - outer.y)
			door.button = _facing(out, at)
		openings.append(outer + Vector3.UP * (y + DOOR.y * 0.5 - outer.y))
	else:
		var wall_mat := _mat_at((way.edge as Vector3) + (way.out as Vector3) * 0.5 + Vector3.UP)
		_grown_add(block, way.tower)
		_carve(room)
		_carve(way.passage)
		door = _secret_door(way.edge, way.out, way.cross, y, lock, wall_mat, "loot")
		if lock == SecretDoor.Lock.BUTTON:
			var button := _hall_button(hall, way.edge, y)
			if button != Transform3D():
				door.button = button
		secret_rooms.append(room)
	lamps.append([room.get_center() + Vector3.UP * 2.0, Color(1.0, 0.7, 0.4), 2.0, 14.0])
	if lock == SecretDoor.Lock.BUTTON and not door.has("button"):
		door.lock = SecretDoor.Lock.KEY # (no wall for its button: a key door, then)
	secrets.append(door)
	return true


## A shortcut: a hidden door in a hall's wall under one of its mezzanines,
## and behind it a narrow shaft grown up the tower's outside, to a way back
## in at the deck -- grapple up it.
func _secret_shaft(hall: Dictionary, lock: int) -> bool:
	var own: Array[Dictionary] = []
	for d in decks:
		if d.hall == hall:
			own.append(d)
	if own.is_empty():
		secret_report.no_deck += 1
		return false
	var deck: Dictionary = own[secret_random.randi() % own.size()]
	var side: int = deck.side
	var along := secret_random.randf_range(-(deck.span as float) * 0.4, (deck.span as float) * 0.4)
	var box: AABB = hall.box
	var y := box.position.y
	var top_y: float = deck.y
	var bottom := _secret_way(hall, side, along, y)
	var top := _secret_way(hall, side, along, top_y, false, false)
	if bottom.is_empty() or top.is_empty():
		secret_report.bottom += 1 if bottom.is_empty() else 0
		secret_report.top += 1 if top.is_empty() else 0
		return false
	var inner := Vector3(SHAFT_INNER, top_y - y + DOOR.y + 4.0, SHAFT_INNER)
	var face := minf(bottom.face, top.face)
	bottom.face = face
	var block := _grown_box(bottom, y, inner)
	var face_point: Vector3 = bottom.centre + (bottom.out as Vector3) * face
	if not _grown_fits(block, bottom.out, face_point):
		secret_report.fits += 1
		return false
	var wall_mat := _mat_at((bottom.edge as Vector3) + (bottom.out as Vector3) * 0.5 + Vector3.UP)
	_grown_add(block, bottom.tower)
	_carve(_grown_inside(bottom, y, inner))
	secret_shafts.append(_grown_inside(bottom, y, inner))
	_carve(bottom.passage)
	_carve(_span((top.edge as Vector3) - (top.out as Vector3) * 0.1, face_point + (bottom.out as Vector3) * 0.6 + Vector3.UP * (top_y - y),
			top.cross, DOOR.x, top_y, DOOR.y))
	var door := _secret_door(bottom.edge, bottom.out, bottom.cross, y, lock, wall_mat, "shortcut")
	if lock == SecretDoor.Lock.BUTTON:
		var button := _hall_button(hall, bottom.edge, y)
		if button == Transform3D():
			door.lock = SecretDoor.Lock.KEY
		else:
			door.button = button
	secrets.append(door)
	return true


## A door in the plane through `at`, the side you stand on toward `toward`:
## its hinge (this frame: +X across the doorway, +Z toward you), and for a
## button door the panel that looks like the wall it's in (`mat`).
func _secret_door(at: Vector3, into: Vector3, cross: Vector3, y: float, lock: int, mat: StringName, kind: String) -> Dictionary:
	var toward := -into # the side you open it from
	var across := cross
	if across.cross(Vector3.UP).dot(toward) < 0.0:
		across = -across
	var z := across.cross(Vector3.UP).normalized()
	var hinge := Transform3D(Basis(across, Vector3.UP, z), Vector3(at.x, y, at.z) - across * DOOR.x * 0.5)
	var panel_centre := Vector3(at.x, y + DOOR.y * 0.5, at.z) - z * 0.25
	var panel := {c = panel_centre, s = across.abs() * DOOR.x + Vector3.UP * DOOR.y + z.abs() * 0.5, b = Basis.IDENTITY}
	return {kind = kind, lock = lock, hinge = hinge, panel = panel, mat = mat, model = secret_random.randi() % 64,
			button_model = secret_random.randi() % 64}


## A button set into a hall's wall within BUTTON_REACH of `door` (but not
## right by it), at hand height, on solid wall with nothing in front of it.
## Transform3D() if none fits.
func _hall_button(hall: Dictionary, door: Vector3, y: float) -> Transform3D:
	var box: AABB = hall.box
	for attempt in 150:
		var side := secret_random.randi() % 4
		var out := _outward(side)
		var cross := Vector3(out.z, 0.0, out.x).abs()
		var hall_reach := (box.size.x if side >= 2 else box.size.z) * 0.5
		var hall_wide := (box.size.z if side >= 2 else box.size.x) * 0.5
		var along := secret_random.randf_range(-hall_wide + 3.0, hall_wide - 3.0)
		var at := Vector3(box.get_center().x, y + BUTTON_HEIGHT, box.get_center().z) + cross * along + out * hall_reach
		var distance := Vector2(at.x - door.x, at.z - door.z).length()
		if distance < 8.0 or distance > BUTTON_REACH:
			continue
		if not _solid_at(at + out * 0.5):
			continue
		var front := AABB(at - out * 1.0 - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
		if _anything_at(front):
			continue
		var clear := true
		for space in carved:
			if space != box and space.has_point(at - out * 0.3):
				clear = false
				break
		if clear:
			return _facing(-out, at)
	return Transform3D()


## A frame at `at` whose +Z points `normal` (out of the wall it's on).
static func _facing(normal: Vector3, at: Vector3) -> Transform3D:
	var z := normal.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), at)


## The material of the solid block at `point` (what a wall there is made of).
func _mat_at(point: Vector3) -> StringName:
	for b in boxes:
		if b.solid and AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s).has_point(point):
			return b.mat
	return &"concrete"


## Whether `point` is inside a solid tower block.
func _solid_at(point: Vector3) -> bool:
	for b in boxes:
		if b.solid and AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s).has_point(point):
			return true
	return false


## Where keys may lie (hall floors, decks) and dead climbers may be (hall
## floors): clear of everything standing there, out of the main shaft.
func _key_and_climber_spots() -> void:
	var shaft := Rect2(-UPPER_SHAFT * 0.5 - 6.0, -UPPER_SHAFT * 0.5 - 6.0, UPPER_SHAFT + 12.0, UPPER_SHAFT + 12.0)
	var floors: Array[Dictionary] = []
	for hall in halls:
		floors.append({box = hall.box, y = (hall.box as AABB).position.y, main = hall.tower == 0})
	var tries := 0
	while (key_spots.size() < HALL_KEY_SPOTS or climber_spots.size() < CLIMBER_SPOTS) and tries < 4000:
		tries += 1
		var f: Dictionary = floors[secret_random.randi() % floors.size()]
		var box: AABB = f.box
		var spot := Vector3(secret_random.randf_range(box.position.x + 10.0, box.end.x - 10.0), f.y,
				secret_random.randf_range(box.position.z + 10.0, box.end.z - 10.0))
		if f.main and shaft.has_point(Vector2(spot.x, spot.z)):
			continue
		if _anything_at(AABB(spot + Vector3(-1.5, 0.3, -1.5), Vector3(3.0, 2.0, 3.0))):
			continue
		if climber_spots.size() < CLIMBER_SPOTS and secret_random.randf() < 0.25:
			if not _anything_at(AABB(spot + Vector3(-7.0, 0.3, -7.0), Vector3(14.0, 3.0, 14.0))):
				climber_spots.append(spot) # (room for the camp beside them)
				continue
		if key_spots.size() < HALL_KEY_SPOTS:
			key_spots.append(spot)


## The doors and buttons, in the scene (Interior > Secrets).
func _secret_nodes(root: Node, parent: Node, materials: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Secrets"
	_own(root, holder, parent)
	for i in secrets.size():
		var s: Dictionary = secrets[i]
		var door := SecretDoor.new()
		door.name = "Door_%d" % i
		door.lock = s.lock
		door.size = DOOR
		door.model_index = s.model
		door.transform = s.hinge
		_own(root, door, holder)
		if s.lock == SecretDoor.Lock.BUTTON:
			# Looks like the wall: the wall's own concrete, laid on the same grid.
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_box_faces(st, s.panel)
			st.generate_normals()
			var material: Material = materials[&"shell"] if s.mat == &"concrete" else materials.get(s.mat, materials[&"plain"])
			st.set_material(material)
			var panel := MeshInstance3D.new()
			panel.name = "Panel"
			panel.mesh = st.commit()
			panel.transform = (s.hinge as Transform3D).affine_inverse()
			_own(root, panel, door)
			if s.has("button"):
				var button := SecretButton.new()
				button.name = "Button_%d" % i
				button.model_index = s.button_model
				button.transform = s.button
				button.door_path = NodePath("../Door_%d" % i)
				_own(root, button, holder)

# ---- The scene ------------------------------------------------------------------------

## The whole Stack as a Megastructure scene (not yet saved).
func build_scene(textures: Dictionary, wind: AudioStream, drone: AudioStream) -> Megastructure:
	var root := Megastructure.new()
	root.name = "TheStack"
	var zones: Array[AABB] = []
	zones.append(AABB(Vector3(-TOWERS[0][2] * 0.5 + WALL, 0.0, -TOWERS[0][2] * 0.5 + WALL), Vector3(TOWERS[0][2] - WALL * 2.0, INTERIOR_TOP, TOWERS[0][2] - WALL * 2.0)))
	for hall in halls:
		zones.append(hall.box)
	root.inside_zones = zones
	root.inside = AABB(Vector3(-TOWERS[0][2] * 0.5, DEPTHS_FLOOR - 10.0, -TOWERS[0][2] * 0.5), Vector3(TOWERS[0][2], TOWERS[0][3] - DEPTHS_FLOOR, TOWERS[0][2]))
	root.terrain_holes = terrain_holes
	root.floor_nests = nest_spots
	root.gang_spots = gang_spots
	_fire_spots(root)
	# The outside walls (inside, floor_nests): up every tower, thicker higher up.
	root.barnacle_nests = OUTSIDE_NESTS
	root.nest_top_density = NEST_TOP_DENSITY
	var columns := PackedVector3Array()
	for t in TOWERS.size():
		columns.append(Vector3(TOWERS[t][0], _top(t), TOWERS[t][1]))
	root.nest_columns = columns
	root.webs = web_nests
	root.secret_rooms = secret_rooms
	root.secret_keys = key_spots
	root.secret_climbers = climber_spots
	root.inner_nest_objects = nest_objects
	root.inner_nest_shafts = secret_shafts
	var shell := Node3D.new()
	shell.name = "Shell"
	_own(root, shell, root)
	var interior := Node3D.new()
	interior.name = "Interior"
	_own(root, interior, root)
	var decor := Node3D.new()
	decor.name = "Decor"
	_own(root, decor, root)
	var materials := _materials(textures)
	# Meshes: one per part, group and material.
	var groups := {}
	for b in boxes:
		var key := "%s|%s|%s" % [b.part, b.group, b.mat]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(b)
	for key: String in groups:
		var bits := key.split("|")
		var parent: Node = shell if bits[0] == "shell" else interior
		var material: Material = materials[StringName(bits[2])] if bits[0] == "interior" or bits[2] != "concrete" else materials[&"shell"]
		_mesh_node(root, parent, "%s_%s" % [bits[1], bits[2]], groups[key], material, bits[0] == "shell")
	_collision(root, shell, "ShellBody", &"shell")
	_collision(root, interior, "InteriorBody", &"interior")
	_occluders(root, shell)
	_water(root, interior)
	_lamps(root, interior)
	_windows(root, decor)
	_window_glow(root, decor)
	_hive_glow(root, decor)
	_growth(root, decor)
	_indoor_growth(root, decor)
	_cobweb_nodes(root, decor)
	_radios(root, interior)
	_secret_nodes(root, interior, materials)
	_swarms(root, decor)
	var worm := CoilingWorm.new()
	worm.name = "CoilingWorm"
	worm.position = Vector3(TOWERS[2][0], 0.0, TOWERS[2][1])
	worm.radius = TOWERS[2][2] * 0.6
	worm.bottom = 300.0
	worm.top = 2500.0
	_own(root, worm, decor)
	_rides(root, decor)
	# Eyes gather at the ways in: bigger clusters than out on the land.
	var eyes := Node3D.new()
	eyes.name = "EntranceEyes"
	_own(root, eyes, decor)
	for i in entrance_spots.size():
		var cluster := EyeCluster.new()
		cluster.name = "Eyes_%d" % i
		cluster.look_seed = SEED + i
		cluster.eye_count = random.randi_range(10, 20)
		cluster.spread = 3.2
		cluster.eye_size_max = 0.55
		cluster.position = entrance_spots[i] + Vector3.UP
		_own(root, cluster, eyes)
	var sound := MegastructureSound.new()
	sound.name = "Sound"
	sound.wind_stream = wind
	sound.drone_stream = drone
	sound.drone_volume_db = -14.0 # subtle: felt more than heard (the user's); halved 2026-10-17 (was -8)
	sound.openings = openings
	sound.inside = root.inside
	# The wind's inside: every hall, the base, and every window room.
	var rooms: Array[AABB] = zones.duplicate()
	for w in window_rooms:
		rooms.append(w.room)
	sound.inside_zones = rooms
	_own(root, sound, decor)
	if cathedral.size != Vector3.ZERO:
		var entry := Marker3D.new()
		entry.name = "CathedralSpawn"
		entry.transform = cathedral_entry
		entry.add_to_group(&"cathedral_spawn", true)
		_own(root, entry, root)
		# The heart (HeartBoss), hanging HEART_HANG over the middle of its floor.
		var heart := Node3D.new()
		heart.name = "Heart"
		heart.set_script(load("res://scripts/heart/heart_boss.gd"))
		heart.position = Vector3(cathedral.get_center().x, cathedral.position.y + HEART_HANG, cathedral.get_center().z)
		heart.set("room", cathedral)
		if ResourceLoader.exists(HEART_MAP):
			heart.set("beat_map", load(HEART_MAP))
		_own(root, heart, root)
	var lair := CollisionShape3D.new()
	lair.name = "Lair"
	var lair_box := BoxShape3D.new()
	lair_box.size = Vector3(TOWERS[0][2], INTERIOR_TOP, TOWERS[0][2])
	lair.shape = lair_box
	lair.position = Vector3(0.0, INTERIOR_TOP * 0.5, 0.0)
	_own(root, lair, root)
	return root


## Every lit window room, for what the Stack rolls into them each time it's
## played (the user's: barrels, radios and pill bottles in random rooms --
## Megastructure): a spot FIRE_INSET in from the window (a barrel's smoke
## pours out of it), the way out, and the room's box.
const FIRE_INSET := 5.0


func _fire_spots(root: Megastructure) -> void:
	var spots := PackedVector3Array()
	var outs := PackedVector3Array()
	var boxes: Array[AABB] = []
	for w in window_rooms:
		if not w.lit:
			continue
		var out: Vector3 = w.normal
		var floor_y: float = (w.at as Vector3).y - (w.size as Vector2).y * 0.5
		var spot: Vector3 = (w.at as Vector3) - out * FIRE_INSET
		spots.append(Vector3(spot.x, floor_y, spot.z))
		outs.append(out)
		boxes.append(w.room)
	root.fire_spots = spots
	root.fire_outs = outs
	root.room_boxes = boxes

func _own(root: Node, node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = root


func _materials(textures: Dictionary) -> Dictionary:
	var made := {}
	var shell := StandardMaterial3D.new()
	shell.albedo_texture = textures.windows
	shell.albedo_color = Color(0.82, 0.8, 0.78)
	made[&"shell"] = shell
	# The hive's: stained, rotten (make_concrete's stained one).
	var stained := StandardMaterial3D.new()
	stained.albedo_texture = textures.stained
	stained.albedo_color = Color(0.82, 0.8, 0.78)
	made[&"stained"] = stained
	for key in [&"plain", &"rubble"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = textures.plain
		m.albedo_color = Color(0.66, 0.65, 0.61) if key == &"plain" else Color(0.55, 0.53, 0.5)
		m.roughness = 1.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		made[key] = m
	var clay := StandardMaterial3D.new()
	clay.albedo_texture = textures.plain
	clay.albedo_color = Color(0.45, 0.33, 0.18)
	clay.roughness = 1.0
	clay.emission_enabled = true
	clay.emission = Color(0.12, 0.08, 0.0)
	made[&"clay"] = clay
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.24, 0.18, 0.14)
	metal.roughness = 0.7
	metal.metallic = 0.5
	made[&"metal"] = metal
	var sludge := StandardMaterial3D.new()
	sludge.albedo_color = Color(0.12, 0.13, 0.05)
	sludge.roughness = 0.1
	sludge.metallic_specular = 0.8
	made[&"sludge"] = sludge
	made[&"concrete"] = made[&"plain"] # concrete indoors (carved faces) reads as plain
	return made


func _mesh_node(root: Node, parent: Node, name: String, picked: Array, material: Material, shadows: bool) -> void:
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


## A box's six faces, its texture laid in metres along each face (u x v =
## -outward, so the corners run clockwise seen from outside: Godot's front).
func _box_faces(st: SurfaceTool, b: Dictionary) -> void:
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
		# One texture grid for the whole Stack: laid by where each corner is
		# (across the face along its world direction, down by height), so the
		# painted windows line up on every piece of every block.
		var world_n := basis * n
		var world_u := basis * u
		for i in [0, 1, 2, 0, 2, 3]:
			var at: Vector3 = points[i]
			var uv: Vector2
			if absf(world_n.y) > 0.7:
				uv = Vector2(at.x, at.z)
			else:
				var across := world_u.normalized()
				uv = Vector2(at.dot(across), -at.y)
			st.set_uv(uv / TEX_METRES)
			st.add_vertex(at)


func _collision(root: Node, parent: Node, name: String, part: StringName) -> void:
	var body := StaticBody3D.new()
	body.name = name
	_own(root, body, parent)
	for b in boxes:
		if b.part != part or b.mat == &"sludge":
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.s
		shape.shape = box
		shape.transform = Transform3D(b.b, b.c)
		_own(root, shape, body)


## The big solid pieces of the towers block the view: what's behind them
## isn't drawn.
func _occluders(root: Node, parent: Node) -> void:
	var holder := Node3D.new()
	holder.name = "Occluders"
	_own(root, holder, parent)
	for b in boxes:
		var s: Vector3 = b.s
		if not b.solid or minf(s.x, minf(s.y, s.z)) < 12.0:
			continue
		var occluder := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = s * 0.96
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


func _lamps(root: Node, parent: Node) -> void:
	var holder := Node3D.new()
	holder.name = "Lamps"
	_own(root, holder, parent)
	for i in lamps.size():
		var spec: Array = lamps[i]
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp_%d" % i
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.light_energy = spec[2]
		lamp.omni_range = spec[3]
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 400.0
		lamp.distance_fade_length = 100.0
		_own(root, lamp, holder)


## A point on the outside of the original blocks isn't somewhere carved out.
func _outside(point: Vector3) -> bool:
	for space in carved:
		if space.grow(1.0).has_point(point):
			return false
	return true


## Lit windows scattered over the towers' outsides, and red blinkers at the
## blocks' corners all the way up.
func _windows(root: Node, parent: Node) -> void:
	var total := 0.0
	for b in blocks:
		total += ((b.s as Vector3).x + (b.s as Vector3).z) * 2.0 * (b.s as Vector3).y
	var windows: Array[Transform3D] = []
	var window_colors: Array[Color] = []
	var window_customs: Array[Color] = []
	var tries := 0
	while windows.size() < 5200 and tries < 20000:
		tries += 1
		var b: Dictionary = blocks[_weighted(blocks, total, true)]
		if b.tower == HIVE:
			continue # dark (the user's)
		var side := random.randi() % 4
		var half: Vector3 = (b.s as Vector3) * 0.5
		var along := random.randf_range(-1.0, 1.0) * (half.x if side < 2 else half.z) * 0.9
		var y := (b.c as Vector3).y + random.randf_range(-1.0, 1.0) * half.y * 0.9
		var out := (half.z if side < 2 else half.x) + 0.2
		var at := _on_wall(side, out, along, 0.0) + Vector3((b.c as Vector3).x, y, (b.c as Vector3).z)
		# Onto the painted window there.
		var across := _face_across(side)
		at += across * (_snap_to_window(at.dot(across)) - at.dot(across))
		at.y = _snap_sill(at.y - 2.0) + (WINDOW_TOP - WINDOW_BOTTOM) * 0.5
		if not _outside(at):
			continue
		windows.append(Transform3D(Basis.IDENTITY, at))
		window_colors.append(Color(1.0, random.randf_range(0.55, 0.75), random.randf_range(0.2, 0.35)) if random.randf() < 0.85 else Color(0.7, 0.85, 1.0))
		window_customs.append(Color(random.randf(), 0.0, 1.0 if random.randf() < 0.1 else 0.0, 0.0))
	_light_batch(root, parent, "Windows", Vector3(WINDOW_WIDTH, WINDOW_TOP - WINDOW_BOTTOM, WINDOW_WIDTH), windows, window_colors, window_customs)
	var blinkers: Array[Transform3D] = []
	var blinker_colors: Array[Color] = []
	var blinker_customs: Array[Color] = []
	for b in blocks:
		if b.tower == HIVE:
			continue
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
	if places.is_empty():
		return
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


## The lit apartment windows: a warm frame glowing round each, and a beam of
## its light falling out into the air.
func _window_glow(root: Node, parent: Node) -> void:
	var frames: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var beams := SurfaceTool.new()
	beams.begin(Mesh.PRIMITIVE_TRIANGLES)
	for w in window_rooms:
		if not w.lit:
			continue # the hive's: dark
		var at: Vector3 = w.at
		var out: Vector3 = w.normal
		var size: Vector2 = w.size
		var cross := Vector3(out.z, 0.0, out.x).abs()
		# The frame: four glowing bars round the opening.
		var thick := out.abs() * 0.5
		for bar: Array in [[cross * (size.x * 0.5 + 0.25), cross * 0.5 + Vector3.UP * (size.y + 1.0)],
				[-cross * (size.x * 0.5 + 0.25), cross * 0.5 + Vector3.UP * (size.y + 1.0)],
				[Vector3.UP * (size.y * 0.5 + 0.25), cross * (size.x + 1.0) + Vector3.UP * 0.5],
				[Vector3.DOWN * (size.y * 0.5 + 0.25), cross * (size.x + 1.0) + Vector3.UP * 0.5]]:
			var offset: Vector3 = bar[0]
			var extent: Vector3 = bar[1] + thick
			frames.append(Transform3D(Basis.from_scale(extent), at + offset + out * 0.4))
			colors.append(Color(1.0, 0.62, 0.25))
			customs.append(Color(random.randf(), 0.0, 0.0, 0.0))
		_beam(beams, at, out, cross, size)
	_light_batch(root, parent, "WindowFrames", Vector3.ONE, frames, colors, customs)
	var node := MeshInstance3D.new()
	node.name = "WindowBeams"
	node.mesh = beams.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/window_beam.gdshader")
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(root, node, parent)


## The hive's only light (the user's): the growth's sickly glow in its holes,
## a dim glowing pane set back in each.
func _hive_glow(root: Node, parent: Node) -> void:
	var places: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	for hole in hive_holes:
		var out: Vector3 = hole.normal
		var size: Vector2 = hole.size
		var cross := Vector3(out.z, 0.0, out.x).abs()
		places.append(Transform3D(Basis.from_scale(cross * size.x * 0.8 + Vector3.UP * size.y * 0.8 + out.abs()), (hole.at as Vector3) - out * 6.0))
		colors.append(Color(0.14, 0.22, 0.04))
		customs.append(Color(random.randf(), 0.0, 0.0, 0.0))
	_light_batch(root, parent, "HiveGlow", Vector3.ONE, places, colors, customs)


## A beam of light falling out of a window: the opening's rectangle
## spreading and sinking as it goes out 28 m, fading (UV.y 0 at the window,
## 1 at its end).
func _beam(st: SurfaceTool, at: Vector3, out: Vector3, cross: Vector3, size: Vector2) -> void:
	var near := [at - cross * size.x * 0.5 - Vector3.UP * size.y * 0.5, at + cross * size.x * 0.5 - Vector3.UP * size.y * 0.5,
			at + cross * size.x * 0.5 + Vector3.UP * size.y * 0.5, at - cross * size.x * 0.5 + Vector3.UP * size.y * 0.5]
	var far_centre := at + out * 16.0 + Vector3.DOWN * 5.0
	var spread := 2.2
	var far := [far_centre - cross * size.x * 0.5 * spread - Vector3.UP * size.y * 0.5 * spread,
			far_centre + cross * size.x * 0.5 * spread - Vector3.UP * size.y * 0.5 * spread,
			far_centre + cross * size.x * 0.5 * spread + Vector3.UP * size.y * 0.5 * spread,
			far_centre - cross * size.x * 0.5 * spread + Vector3.UP * size.y * 0.5 * spread]
	for i in 4:
		var j := (i + 1) % 4
		for p in [[near[i], 0.0], [near[j], 0.0], [far[j], 1.0], [near[i], 0.0], [far[j], 1.0], [far[i], 1.0]]:
			st.set_uv(Vector2(0.0, p[1]))
			st.add_vertex(p[0])


## Overgrown the whole way up (the sewer land's growths, made huge): black
## vines breathing over the walls, giant vine pillars climbing them,
## bracket fungus jutting from them, hive spires, egg sacs and mould on
## every terrace. Never in a carved-out space.
func _growth(root: Node, parent: Node) -> void:
	var wall_total := 0.0
	var top_total := 0.0
	for b in blocks:
		var s: Vector3 = b.s
		wall_total += (s.x + s.z) * 2.0 * s.y
		top_total += s.x * s.z
	_grow_on(root, parent, GrowthMeshes.Kind.BLACK_VINES, wall_total, true, 420, 10.0, 22.0, 2500.0, 2.8)
	_grow_on(root, parent, GrowthMeshes.Kind.VINE_PILLAR, wall_total, true, 30, 3.0, 8.0, 9000.0, 2.0)
	_grow_on(root, parent, GrowthMeshes.Kind.FUNGUS_TOWER, wall_total, true, 70, 0.8, 2.0, 6000.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.HIVE_SPIRE, top_total, false, 70, 1.2, 3.0, 9000.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.EGG_SACS, top_total, false, 220, 10.0, 20.0, 2500.0, 0.0)
	_grow_on(root, parent, GrowthMeshes.Kind.HAIR_MOLD, top_total, false, 400, 14.0, 28.0, 2000.0, 0.0)
	# The hive (the user's): far more overgrown than the rest, on top of that.
	var hive: Array[Dictionary] = []
	var hive_walls := 0.0
	var hive_tops := 0.0
	for b in blocks:
		if b.tower == HIVE:
			hive.append(b)
			var s: Vector3 = b.s
			hive_walls += (s.x + s.z) * 2.0 * s.y
			hive_tops += s.x * s.z
	if not hive.is_empty():
		_grow_on(root, parent, GrowthMeshes.Kind.BLACK_VINES, hive_walls, true, 420, 10.0, 22.0, 2500.0, 2.8, hive, "HiveGrowth")
		_grow_on(root, parent, GrowthMeshes.Kind.VINE_PILLAR, hive_walls, true, 30, 3.0, 8.0, 9000.0, 2.0, hive, "HiveGrowth")
		_grow_on(root, parent, GrowthMeshes.Kind.FUNGUS_TOWER, hive_walls, true, 70, 0.8, 2.0, 6000.0, 0.0, hive, "HiveGrowth")
		_grow_on(root, parent, GrowthMeshes.Kind.HIVE_SPIRE, hive_tops, false, 50, 1.2, 3.0, 9000.0, 0.0, hive, "HiveGrowth")
		_grow_on(root, parent, GrowthMeshes.Kind.EGG_SACS, hive_tops, false, 220, 10.0, 20.0, 2500.0, 0.0, hive, "HiveGrowth")
		_grow_on(root, parent, GrowthMeshes.Kind.HAIR_MOLD, hive_tops, false, 400, 14.0, 28.0, 2000.0, 0.0, hive, "HiveGrowth")
	# Black vines bursting out of its holes, down over the lip.
	var spilling: Array[Transform3D] = []
	for hole in hive_holes:
		var out: Vector3 = hole.normal
		var size: Vector2 = hole.size
		var cross := Vector3(out.z, 0.0, out.x).abs()
		for k in 3:
			var at: Vector3 = (hole.at as Vector3) + Vector3.DOWN * size.y * 0.5 + cross * random.randf_range(-0.4, 0.4) * size.x + out * 0.5
			var spin := Basis(Vector3.UP, random.randf() * TAU)
			spilling.append(Transform3D(Basis(Quaternion(Vector3.UP, out)) * spin * Basis.from_scale(Vector3.ONE * random.randf_range(6.0, 14.0)), at))
	_growth_batch(root, parent, GrowthMeshes.Kind.BLACK_VINES, spilling, 2500.0, 2.8, "HiveGrowth_Holes")
	# The hive tunnel's ledge: a crowd of hive spires.
	var places: Array[Transform3D] = []
	for i in 9:
		var y: float = HALLS[0][0][0]
		var at := Vector3(random.randf_range(0.0, 60.0), y, _face(0, y + 8.0, 1) + random.randf_range(8.0, 40.0))
		places.append(Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.6, 1.2)), at))
	_growth_batch(root, parent, GrowthMeshes.Kind.HIVE_SPIRE, places, 6000.0, 0.0, "Growth_HiveLedge")


## On the blocks of `pool` (empty: all of them), named `prefix`_KIND.
func _grow_on(root: Node, parent: Node, kind: GrowthMeshes.Kind, total: float, on_walls: bool,
		count: int, scale_min: float, scale_max: float, distance: float, breathe: float,
		pool: Array[Dictionary] = [], prefix: String = "Growth") -> void:
	var from: Array[Dictionary] = blocks if pool.is_empty() else pool
	var places: Array[Transform3D] = []
	var tries := 0
	while places.size() < count and tries < count * 4:
		tries += 1
		var b: Dictionary = from[_weighted(from, total, on_walls)]
		var s: Vector3 = b.s
		var half := s * 0.5
		var c: Vector3 = b.c
		var size := random.randf_range(scale_min, scale_max)
		var spin := Basis(Vector3.UP, random.randf() * TAU)
		if on_walls:
			var side := random.randi() % 4
			var normal := _outward(side)
			var along := random.randf_range(-0.9, 0.9) * (half.x if side < 2 else half.z)
			var y := c.y - half.y + s.y * pow(random.randf(), 1.4)
			var at := _on_wall(side, (half.z if side < 2 else half.x) - 0.5, along, y) + Vector3(c.x, 0.0, c.z)
			if not _outside(at + normal * 1.5):
				continue
			var lie := Basis(Quaternion(Vector3.UP, normal))
			if kind == GrowthMeshes.Kind.VINE_PILLAR:
				lie = Basis.IDENTITY
				at += normal * 4.0 * size
			places.append(Transform3D(lie * spin * Basis.from_scale(Vector3.ONE * size), at))
		else:
			var at := Vector3(c.x + random.randf_range(-0.9, 0.9) * half.x, c.y + half.y - 0.5, c.z + random.randf_range(-0.9, 0.9) * half.z)
			if not _outside(at + Vector3.UP * 1.5):
				continue
			places.append(Transform3D(spin * Basis.from_scale(Vector3.ONE * size), at))
	_growth_batch(root, parent, kind, places, distance, breathe, "%s_%s" % [prefix, GrowthMeshes.Kind.keys()[kind]])


func _growth_batch(root: Node, parent: Node, kind: GrowthMeshes.Kind, places: Array[Transform3D], distance: float, breathe: float, name: String) -> void:
	if places.is_empty():
		return
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
	node.name = name
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


## The window rooms' radios (Radio: a physics prop playing a song from
## audio/music/radio); each picks its model and song when the game runs.
func _radios(root: Node, parent: Node) -> void:
	if radio_spots.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Radios"
	_own(root, holder, parent)
	# The radios are rolled into random rooms each time it's played now
	# (Megastructure, the user's); the same numbers are still drawn here so the
	# rest of the Stack comes out exactly as before.
	for i in radio_spots.size():
		random.randi()


## The cobwebs: a quad each, a still, pale web (shaders/cobweb.gdshader:
## nothing moves, nothing runs a frame), drawn only near (inside) or within
## a few kilometres (the huge ones outside).
func _cobweb_nodes(root: Node, parent: Node) -> void:
	if web_quads.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Cobwebs"
	_own(root, holder, parent)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var materials: Array[ShaderMaterial] = []
	for path: String in COBWEBS:
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/cobweb.gdshader")
		material.set_shader_parameter("web_texture", load(path))
		materials.append(material)
	for i in web_quads.size():
		var web: Dictionary = web_quads[i]
		var node := MeshInstance3D.new()
		node.name = "Cobweb_%d" % i
		node.mesh = quad
		node.material_override = materials[web.variant]
		node.transform = web.xform
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 180.0 if web.indoors else 3000.0
		_own(root, node, holder)


## The sewer growths that would grow indoors, on the floors inside: in the
## same kind of clusters as out on the land (GrowthSpecies: long-tailed
## group sizes, crowded to the middle, every one its own size) at their
## first-tuned group sizes (indoors isn't carpeted wall to wall), never in
## the shaft or inside a block, a column or a wall. One batch per kind per
## zone (a hall, a base storey), placed at the zone so it's only drawn near.
func _indoor_growth(root: Node, parent: Node) -> void:
	var species := {}
	for s in GrowthSpecies.defaults():
		species[s.kind] = s
	var batches := {} # "zone|kind" -> Array[Transform3D]
	for f in growth_floors:
		var rect: Rect2 = f.rect
		var y: float = f.y
		if rect.size.x < 4.0 or rect.size.y < 4.0:
			continue
		# A tilted floor (a ramp): rect and y in its own space, nothing in its way.
		var tilted: bool = f.has("xform")
		var xform: Transform3D = f.xform if tilted else Transform3D.IDENTITY
		# What could be in the way on this floor.
		var blockers: Array[AABB] = []
		for b in boxes:
			if tilted:
				break
			if b.b != Basis.IDENTITY:
				continue
			var box := AABB((b.c as Vector3) - (b.s as Vector3) * 0.5, b.s)
			if box.position.y < y + 1.0 and box.end.y > y + 0.5 and Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(rect):
				blockers.append(box)
		var groups := maxi(1, int(rect.get_area() / 3500.0 * float(f.density) + random.randf()))
		for g in groups:
			var kind: int = _pick(f.kinds)
			var s: GrowthSpecies = species[kind]
			var least := maxi(1, s.min_group / GrowthSpecies.GROUP_SCALE)
			var most := clampi(s.max_group / GrowthSpecies.GROUP_SCALE, least, 120)
			var count := clampi(int(least * pow(1.0 - random.randf() * 0.999, -1.0 / maxf(s.group_tail, 0.1))), least, most)
			var centre := Vector2(random.randf_range(rect.position.x, rect.end.x), random.randf_range(rect.position.y, rect.end.y))
			var radius := s.spacing * sqrt(float(count)) * random.randf_range(0.6, 1.4)
			var key := "%s|%d" % [f.zone, kind]
			if not batches.has(key):
				var fresh: Array[Transform3D] = []
				batches[key] = fresh
			for m in count:
				var spread := pow(random.randf(), s.crowding * 0.5)
				var angle := random.randf() * TAU
				var at := centre + Vector2(cos(angle), sin(angle)) * radius * spread
				if not rect.has_point(at):
					continue
				var shaft: float = f.shaft
				if shaft > 0.0 and absf(at.x) < shaft and absf(at.y) < shaft:
					continue
				if f.has("open_at") and at.distance_to(f["open_at"]) < float(f["open"]):
					continue # (a hall's middle kept open: the cathedral's)
				var point := Vector3(at.x, y + 0.6, at.y)
				var inside := false
				for blocker in blockers:
					if blocker.has_point(point):
						inside = true
						break
				if inside:
					continue
				var size := random.randf_range(s.min_scale, s.max_scale)
				if random.randf() < s.elder_chance:
					size *= s.elder_scale
				(batches[key] as Array).append(xform * Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * size),
						Vector3(at.x, y - s.sink * size, at.y)))
	var materials := {}
	var holder := Node3D.new()
	holder.name = "IndoorGrowth"
	_own(root, holder, parent)
	for key: String in batches:
		var places: Array = batches[key]
		if places.is_empty():
			continue
		var kind := int(key.get_slice("|", 1))
		var s: GrowthSpecies = species[kind]
		if not materials.has(kind):
			var material := ShaderMaterial.new()
			material.shader = GrowthScatter.GROWTH_SHADER
			material.set_shader_parameter("glow_color", s.glow_color)
			material.set_shader_parameter("sway_amount", s.sway_amount * 0.4) # no wind indoors: a stir
			material.set_shader_parameter("breathe_amount", s.breathe)
			material.set_shader_parameter("breathe_speed", s.breathe_speed)
			materials[kind] = material
		var middle := Vector3.ZERO
		for place: Transform3D in places:
			middle += place.origin
		middle /= places.size()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = GrowthMeshes.get_mesh(kind, random.randi() % s.variants)
		multimesh.instance_count = places.size()
		for i in places.size():
			multimesh.set_instance_transform(i, (places[i] as Transform3D).translated(-middle))
			var shade := 1.0 + random.randf_range(-s.tint_variation, s.tint_variation)
			multimesh.set_instance_color(i, Color(shade, shade, shade))
			multimesh.set_instance_custom_data(i, Color(random.randf(), random.randf(), 0.0, 0.0))
		var node := MultiMeshInstance3D.new()
		node.name = key.replace("|", "_")
		node.multimesh = multimesh
		node.position = middle
		node.material_override = materials[kind]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 220.0
		node.visibility_range_end_margin = 20.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_own(root, node, holder)


## A key picked from {key: weight}, in proportion to the weights.
func _pick(weights: Dictionary) -> int:
	var total := 0.0
	for key in weights:
		total += weights[key]
	var roll := random.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]


## Roach swarms circling each tower's top like birds round a cliff.
func _swarms(root: Node, parent: Node) -> void:
	var speck := SurfaceTool.new()
	speck.begin(Mesh.PRIMITIVE_TRIANGLES)
	GrowthMeshes._blob(speck, Vector3.ZERO, 3.5, Color(0.05, 0.04, 0.03), 0.0, 0.0, Vector3(1.6, 0.5, 1.0), false)
	var mesh := speck.commit()
	for t in TOWERS.size():
		var top := _top(t)
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


## The express lift up the main tower's -Z side (and its cable), and the
## cable car between the high halls (and its cable).
func _rides(root: Node, parent: Node) -> void:
	if LIFT_ENABLED:
		var lift := StackLift.new()
		lift.name = "Lift"
		lift.stops = lift_stops
		lift.on_call = true
		_own(root, lift, parent)
		for i in lift_buttons.size():
			var button := LiftButton.new()
			button.name = "LiftCall_%d" % i
			button.lift_path = NodePath("../Lift")
			button.stop = i
			button.position = lift_buttons[i]
			_own(root, button, parent)
		_cable(root, parent, "LiftCable", Vector3(0.0, 0.0, lift_face), Vector3(0.0, LIFT_STOPS[LIFT_STOPS.size() - 1] + 80.0, lift_face))
	if cable_stops.size() == 2:
		var car := StackLift.new()
		car.name = "CableCar"
		car.hanging = true
		car.speed = 12.0
		car.stops = cable_stops
		_own(root, car, parent)
		_cable(root, parent, "CarCable", cable_stops[0] + Vector3.UP * 17.0, cable_stops[1] + Vector3.UP * 17.0)


func _cable(root: Node, parent: Node, name: String, a: Vector3, b: Vector3) -> void:
	var cable := MeshInstance3D.new()
	cable.name = name
	var line := BoxMesh.new()
	line.size = Vector3(0.8, 0.8, a.distance_to(b))
	cable.mesh = line
	cable.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.BACK), (a + b) * 0.5)
	_own(root, cable, parent)


## A block picked in proportion to its wall area (or its top's area).
func _weighted(list: Array[Dictionary], total: float, by_walls: bool) -> int:
	var roll := random.randf() * total
	for i in list.size():
		var s: Vector3 = list[i].s
		roll -= (s.x + s.z) * 2.0 * s.y if by_walls else s.x * s.z
		if roll <= 0.0:
			return i
	return list.size() - 1


# ---- The TrenchBroom map ------------------------------------------------------------------

## Every box as a brush, in two layers (Shell, Interior), Valve 220 format,
## MAP_UNITS a metre (Quake's z-up: map = (godot.z, godot.x, godot.y)).
func write_map(path: String, textures: Dictionary) -> Error:
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
				lines.append(_brush(b, textures.get(b.mat, textures[&"plain"])))
		lines.append("}")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines) + "\n")
	return OK


func _brush(b: Dictionary, texture_name: String) -> String:
	var basis: Basis = b.b
	var half: Vector3 = (b.s as Vector3) * 0.5
	# The box's own axes in map space (godot x -> map y, y -> map z, z -> map x).
	var ax := _to_map(basis * Vector3(0.0, 0.0, 1.0))
	var ay := _to_map(basis * Vector3(1.0, 0.0, 0.0))
	var az := _to_map(basis * Vector3(0.0, 1.0, 0.0))
	var extent := Vector3(half.z, half.x, half.y) * MAP_UNITS
	var c := _to_map(b.c) * MAP_UNITS
	var low := c - ax * extent.x - ay * extent.y - az * extent.z
	var high := c + ax * extent.x + ay * extent.y + az * extent.z
	var step := 64.0
	var planes := [
		[low, low + ay * step, low + az * step, Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[low, low + az * step, low + ax * step, Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[low, low + ax * step, low + ay * step, Vector3(1, 0, 0), Vector3(0, -1, 0)],
		[high, high + ay * step, high + ax * step, Vector3(1, 0, 0), Vector3(0, -1, 0)],
		[high, high + ax * step, high + az * step, Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[high, high + az * step, high + ay * step, Vector3(0, 1, 0), Vector3(0, 0, -1)],
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


# ---- Generated assets ---------------------------------------------------------------------

## Grey stained concrete, 64 px for 8 m, PS1-coarse: blotches and water
## streaks; `windowed`: one dark window a tile (the towers' outsides),
## otherwise plain (insides, rubble -- no windows underfoot).
## `stained`: the hive's -- darker, black runs down it, green-black moss.
static func make_concrete(windowed: bool = true, stained: bool = false) -> Image:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	var blotch := FastNoiseLite.new()
	blotch.seed = 11 if windowed else 21
	blotch.frequency = 0.08
	var moss := FastNoiseLite.new()
	moss.seed = 14
	moss.frequency = 0.06
	var streak := FastNoiseLite.new()
	streak.seed = 12
	streak.frequency = 0.15
	var crack := FastNoiseLite.new()
	crack.seed = 13
	crack.frequency = 0.2
	crack.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	for y in 64:
		for x in 64:
			var shade := 0.42 + blotch.get_noise_2d(x, y) * 0.08
			shade -= maxf(streak.get_noise_2d(x * 1.0, y * 0.12), 0.0) * 0.18 # streaks run down
			if not windowed and crack.get_noise_2d(x, y) > 0.8:
				shade *= 0.55 # cracks
			var color := Color(shade, shade * 0.98, shade * 0.93)
			if stained:
				shade = shade * 0.7 - maxf(streak.get_noise_2d(x * 1.7, y * 0.06), 0.0) * 0.3 # black runs
				color = Color(shade, shade * 0.98, shade * 0.9)
				var growth := smoothstep(0.1, 0.45, moss.get_noise_2d(x, y))
				color = color.lerp(Color(0.1, 0.14, 0.07), growth * 0.8)
			if windowed and x >= 20 and x < 44 and y >= 16 and y < 46:
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
	var noise_random := RandomNumberGenerator.new()
	noise_random.seed = 3
	var low := 0.0
	var band := 0.0
	var high := 0.0
	for i in frames:
		var t := float(i) / rate
		var phase := t / seconds * TAU
		var pitch := 380.0 + 220.0 * sin(phase * 2.0) + 90.0 * sin(phase * 5.0 + 1.0)
		var gust := 0.45 + 0.35 * sin(phase * 3.0) + 0.2 * sin(phase * 7.0 + 2.0)
		var f := 2.0 * sin(PI * pitch / rate)
		var noise := noise_random.randf_range(-1.0, 1.0)
		low += f * band
		high = noise - low - 0.08 * band
		band += f * high
		samples[i] = (band * 0.35 + low * 0.05) * gust
	return _wav(_crossfade_loop(samples, rate), rate)


## The drone: low tones beating slowly against each other, a rumble under
## them -- a deep, bassy hum you feel more than hear (the original; the
## user's pick over a louder buzzing one, kept subtle by the Stack's
## drone_volume_db).
static func make_drone(seconds: float = 16.0) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var noise_random := RandomNumberGenerator.new()
	noise_random.seed = 4
	var rumble := 0.0
	for i in frames:
		var t := float(i) / rate
		var swell := 0.75 + 0.25 * sin(t / seconds * TAU * 2.0)
		var tone := sin(TAU * 38.0 * t) * 0.45 + sin(TAU * 38.5 * t) * 0.35 + sin(TAU * 57.0 * t) * 0.2 \
				+ sin(TAU * 76.0 * t) * 0.1 + sin(TAU * 113.0 * t) * 0.05
		rumble += (noise_random.randf_range(-1.0, 1.0) - rumble) * 0.01
		samples[i] = (tone * 0.6 + rumble * 2.5) * swell * 0.7
	return _wav(_crossfade_loop(samples, rate), rate)

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
