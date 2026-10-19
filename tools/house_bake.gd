extends RefCounted

## Grandma's house (the user's, 2026-10-19: every choice theirs), written as a
## TrenchBroom map and built into a scene. Run by tools/make_grandmas_house.gd
## once it has stood in for the autoloads. Re-running overwrites the map and
## the scene: once the map's been edited in TrenchBroom, rebuild it with the
## scene's own FuncGodotMap ("Map", its Build button) instead.
##   Outside, like the user's reference, twice real size (GrandmasHouse.SIZE,
##   the user's: 20 x 16 m, two 6 m storeys; every measure below is real
##   size, doubled where the faces are made), Plaster_19 walls with a Plaster_20 band between the floors, a
##   Roofs_01 gable roof, a centre bay under its own gable, a porch with two
##   posts and a pediment, dark opaque panes in near-black Wood_22 frames
##   with cross bars, a Wood_22 front door. Front (-Z) toward the Stack.
##   Inside: the living room (Horror_Wall_01 walls, Wood_06 floorboards) is
##   open, the front door straight into it, the stairs up its back wall.
##   Seven rooms wait behind locked doors (each a door with a targetname,
##   "Locked.", for quests and rare 1-of-1 keys to open later through
##   MapIO): the kitchen, the study, the cellar (a door under the stairs),
##   and upstairs behind the landing door at the top of the stairs, two
##   bedrooms, the bathroom and the attic (a hatch in the hall's ceiling).
##   Everything inside (func_detail "house_interior", the locked doors,
##   Grandma, the lamp) is GrandmasHouse's to show only while the front door's
##   open or someone's in: the HL2 way (Valve's areaportals), no loading.

const MAP := "res://maps/grandmas_house.map"
const MAP_SETTINGS := "res://maps/grandmas_house_map_settings.tres"
const SCENE := "res://scenes/world/grandmas_house.tscn"
const SCRIPT := "res://scripts/world/grandmas_house.gd"
const WINDOW_PNG := "res://trenchbroom/textures/House/window_dark.png"
## TrenchBroom units a metre (func_godot's default map settings).
const UNITS := 32.0
## Twice real size (the user's): GrandmasHouse.SIZE, read here without
## naming the class (so the bake compiles in --script mode).
const SIZE := 2.0

const WALL := "Plaster_19-256x256"
const TRIM := "Plaster_20-256x256"
const INSIDE := "Horror_Wall_01-256x256"
const FLOOR := "Wood/Wood_06-256x256"
const ROOF := "Roofs/Roofs_01-256x256"
const WOOD := "Wood/Wood_22-256x256"
const GLASS := "House/window_dark"
const CLIP := "clip"
## Metres one tile of each texture covers.
const TILE := {WALL: 2.0, TRIM: 2.0, INSIDE: 2.0, FLOOR: 2.0, ROOF: 2.0, WOOD: 1.0, GLASS: 1.0, CLIP: 2.0}

## The shape (metres; x across the front, z front -4 to back +4, y up).
const HALF_W := 5.0
const HALF_D := 4.0
const T := 0.25 # wall thickness
const FLOOR_0 := 0.3 # ground floor's top
const CEIL_0 := 3.0
const FLOOR_1 := 3.3
const CEIL_1 := 6.0
const WALL_TOP := 6.3
const PITCH := 40.0 # the main roof, degrees
const BAY_HALF := 1.8 # the centre bay's half width
const BAY_FRONT := -4.6
const PORCH_FRONT := -6.2
const SILL := 1.0 # windows' sills over each floor
const WINDOW_H := 1.6
const DOOR_W := 0.9
const DOOR_H := 2.1

var _world: Array = []
var _interior: Array = []
var _doors: Array = [] # [brush, {properties}]
var _points: Array = [] # [classname, position, {properties}]


func run(tree: SceneTree) -> void:
	for path in [MAP, MAP_SETTINGS, SCENE, WINDOW_PNG]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if not FileAccess.file_exists(WINDOW_PNG):
		_window_image().save_png(ProjectSettings.globalize_path(WINDOW_PNG))
		print("made ", WINDOW_PNG, " -- run the editor once (or --editor --quit) to import it, then bake again")
		return
	_outside()
	_inside()
	print("map: ", MAP, " (error ", _write_map(ProjectSettings.globalize_path(MAP)), ")")
	var settings := (load("res://addons/func_godot/func_godot_default_map_settings.tres") as Resource).duplicate()
	settings.set("entity_name_property", "targetname")
	print("map settings: ", MAP_SETTINGS, " (error ", ResourceSaver.save(settings, MAP_SETTINGS), ")")
	settings = load(MAP_SETTINGS)
	# Built the way the editor's Build button does it.
	var map := (load("res://addons/func_godot/src/map/func_godot_map.gd") as GDScript).new() as Node3D
	map.name = "Map"
	map.set("map_settings", settings)
	map.set("local_map_file", MAP)
	# Headless (--script) the renderer's a stand-in, and now and then it drops
	# a mesh (an empty door): built again till every piece has its mesh.
	for attempt in 6:
		map.call("build")
		var empty := _empty_meshes(map)
		if empty.is_empty():
			break
		print("empty meshes ", empty, " -- building again")
	var house := Node3D.new()
	house.name = "GrandmasHouse"
	house.set_script(load(SCRIPT))
	house.add_child(map)
	map.owner = house
	_own(map, map, house)
	# The living room's lamp (inside: shown with the rest).
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 1.4
	lamp.omni_range = 8.0 * SIZE
	lamp.position = Vector3(-1.5, CEIL_0 - 0.4, 0.0) * SIZE
	house.add_child(lamp)
	lamp.owner = house
	var scene := PackedScene.new()
	var error := scene.pack(house)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE)
	print("house: ", map.get_child_count(), " entities -> ", SCENE, " (error ", error, ")")
	house.free()


## The pieces whose built mesh came out empty.
func _empty_meshes(map: Node) -> Array[String]:
	var empty: Array[String] = []
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if node.scene_file_path.is_empty() and node.owner == map and (mesh == null or mesh.get_aabb().size == Vector3.ZERO):
			empty.append(str(node.get_parent().name))
	return empty


## Owns what func_godot made (owned by the map) to the house; scenes it
## instanced (Grandma) keep their own insides.
func _own(node: Node, map: Node, house: Node) -> void:
	for child in node.get_children():
		if child.owner == map or child.owner == null:
			child.owner = house
		if child.scene_file_path.is_empty():
			_own(child, map, house)


# ---- Outside ---------------------------------------------------------------------------------

func _outside() -> void:
	var w := HALF_W
	var d := HALF_D
	var up0 := FLOOR_0 + SILL
	var up1 := FLOOR_1 + SILL + 0.2
	# Front wall (outside -Z): two windows a floor either side, the bay's
	# opening in the middle (both floors).
	_wall(_world, "x", -w, w, -d, -d + T, 0.0, WALL_TOP, [
		[-3.7, -2.5, up0, up0 + WINDOW_H], [2.9, 4.1, up0, up0 + WINDOW_H],
		[-3.7, -2.5, up1, up1 + WINDOW_H], [2.9, 4.1, up1, up1 + WINDOW_H],
		[-BAY_HALF + T, BAY_HALF - T, FLOOR_0, CEIL_1]], -1)
	for a: Array in [[-3.7, -2.5, up0], [2.9, 4.1, up0], [-3.7, -2.5, up1], [2.9, 4.1, up1]]:
		_window("x", a[0], a[1], -d, -d + T, a[2], a[2] + WINDOW_H, -1)
	# Back wall (outside +Z): the kitchen, the bathroom, the stairwell.
	_wall(_world, "x", -w, w, d - T, d, 0.0, WALL_TOP, [
		[2.9, 4.1, up0, up0 + WINDOW_H], [2.9, 4.1, up1 + 0.2, up1 + 1.2], [-3.0, -2.0, up1, up1 + WINDOW_H]], 1)
	_window("x", 2.9, 4.1, d - T, d, up0, up0 + WINDOW_H, 1)
	_window("x", 2.9, 4.1, d - T, d, up1 + 0.2, up1 + 1.2, 1)
	_window("x", -3.0, -2.0, d - T, d, up1, up1 + WINDOW_H, 1)
	# Left side (outside -X): the living room, bedroom 1.
	_wall(_world, "z", -d + T, d - T, -w, -w + T, 0.0, WALL_TOP, [
		[-2.0, -0.8, up0, up0 + WINDOW_H], [-2.0, -0.8, up1, up1 + WINDOW_H]], -1)
	_window("z", -2.0, -0.8, -w, -w + T, up0, up0 + WINDOW_H, -1)
	_window("z", -2.0, -0.8, -w, -w + T, up1, up1 + WINDOW_H, -1)
	# Right side (outside +X): the study and kitchen, bedroom 2 and the bathroom.
	_wall(_world, "z", -d + T, d - T, w - T, w, 0.0, WALL_TOP, [
		[-2.6, -1.4, up0, up0 + WINDOW_H], [1.4, 2.6, up0, up0 + WINDOW_H],
		[-2.6, -1.4, up1, up1 + WINDOW_H], [2.0, 2.8, up1 + 0.2, up1 + 1.2]], 1)
	_window("z", -2.6, -1.4, w - T, w, up0, up0 + WINDOW_H, 1)
	_window("z", 1.4, 2.6, w - T, w, up0, up0 + WINDOW_H, 1)
	_window("z", -2.6, -1.4, w - T, w, up1, up1 + WINDOW_H, 1)
	_window("z", 2.0, 2.8, w - T, w, up1 + 0.2, up1 + 1.2, 1)
	# The centre bay: its front (the door, a window over it) and sides.
	_wall(_world, "x", -BAY_HALF, BAY_HALF, BAY_FRONT, BAY_FRONT + T, 0.0, WALL_TOP, [
		[-0.5, 0.5, FLOOR_0, FLOOR_0 + 2.2], [-0.5, 0.5, up1, up1 + WINDOW_H]], -1)
	_window("x", -0.5, 0.5, BAY_FRONT, BAY_FRONT + T, up1, up1 + WINDOW_H, -1)
	_door_frame(_world, "x", -0.5, 0.5, BAY_FRONT, BAY_FRONT + T, FLOOR_0, FLOOR_0 + 2.2)
	_door({"use": "1"}, "x", -0.5, 0.5, BAY_FRONT, BAY_FRONT + T, FLOOR_0, FLOOR_0 + 2.2) # (F opens it, it shuts once you're through: the user's)
	_wall(_world, "z", BAY_FRONT + T, -d, -BAY_HALF, -BAY_HALF + T, 0.0, WALL_TOP, [], -1)
	_wall(_world, "z", BAY_FRONT + T, -d, BAY_HALF - T, BAY_HALF, 0.0, WALL_TOP, [], 1)
	# The band between the floors (Plaster_20), proud of the walls.
	var o := 0.06
	for band: Array in [
			[-w - o, -BAY_HALF, -d - o, -d], [BAY_HALF, w + o, -d - o, -d], [-w - o, w + o, d, d + o],
			[-w - o, -w, -d, d], [w, w + o, -d, d],
			[-BAY_HALF - o, BAY_HALF + o, BAY_FRONT - o, BAY_FRONT],
			[-BAY_HALF - o, -BAY_HALF, BAY_FRONT, -d], [BAY_HALF, BAY_HALF + o, BAY_FRONT, -d]]:
		_world.append(_box(Vector3(band[0], CEIL_0, band[2]), Vector3(band[1], FLOOR_1 - 0.05, band[3]), TRIM))
	_roof()
	_porch()


## The main gable roof (ridge along X), its gable ends, and the bay's own
## gable roof and front gable.
func _roof() -> void:
	var w := HALF_W
	var d := HALF_D
	var slope := tan(deg_to_rad(PITCH))
	var thick := 0.22 / cos(deg_to_rad(PITCH)) # its thickness, measured upright
	var overhang := 0.4
	var ends := 0.3
	# Front slope: its underside rises from the walls' top at the front
	# wall's face to the ridge over the middle. The bay's part starts at the
	# wall (its own roof covers the rest).
	for span: Array in [[-w - ends, -BAY_HALF, -d - overhang], [-BAY_HALF, BAY_HALF, -d], [BAY_HALF, w + ends, -d - overhang]]:
		_world.append(_slope_slab(span[0], span[1], span[2], 0.0, -d, 1.0, slope, thick))
	_world.append(_slope_slab(-w - ends, w + ends, 0.0, d + overhang, d, -1.0, slope, thick))
	# The gable ends: plaster triangles from the walls' top up under the roof.
	for side: float in [-1.0, 1.0]:
		var outer := side * w
		var inner := side * (w - T)
		_world.append([
			_f(Vector3(0.0, WALL_TOP, 0.0), Vector3.DOWN, WALL),
			_f(Vector3(maxf(outer, inner), 0.0, 0.0), Vector3.RIGHT, WALL if side > 0.0 else INSIDE),
			_f(Vector3(minf(outer, inner), 0.0, 0.0), Vector3.LEFT, WALL if side < 0.0 else INSIDE),
			_f(Vector3(0.0, WALL_TOP, -d), Vector3(0.0, 1.0, -slope).normalized(), WALL),
			_f(Vector3(0.0, WALL_TOP, d), Vector3(0.0, 1.0, slope).normalized(), WALL),
		])
	# The bay's gable roof: ridge along Z over the middle, 45 degrees, from
	# past the bay's front back into the main roof.
	var bay_slope := 1.0
	var bay_thick := 0.22 / cos(deg_to_rad(45.0))
	for side: float in [-1.0, 1.0]:
		var eave := side * (BAY_HALF + 0.3)
		_world.append(_bay_slab(side, minf(eave, 0.0), maxf(eave, 0.0), bay_slope, bay_thick))
	# Its front gable: a plaster triangle over the bay's front wall.
	_world.append([
		_f(Vector3(0.0, WALL_TOP, 0.0), Vector3.DOWN, WALL),
		_f(Vector3(0.0, 0.0, BAY_FRONT), Vector3.FORWARD, WALL),
		_f(Vector3(0.0, 0.0, BAY_FRONT + T), Vector3.BACK, INSIDE),
		_f(Vector3(-BAY_HALF, WALL_TOP, 0.0), Vector3(-bay_slope, 1.0, 0.0).normalized(), WALL),
		_f(Vector3(BAY_HALF, WALL_TOP, 0.0), Vector3(bay_slope, 1.0, 0.0).normalized(), WALL),
	])


## One side of the main roof: between x0..x1 and z0..z1, its underside
## rising `rise_dir` (1: toward +Z from z at `wall_z`, -1: toward -Z).
func _slope_slab(x0: float, x1: float, z0: float, z1: float, wall_z: float, rise_dir: float, slope: float, thick: float) -> Array:
	var base := Vector3(0.0, WALL_TOP, wall_z)
	# Underside: y = WALL_TOP + (z - wall_z) * rise_dir * slope; the slab is above it.
	var up_n := Vector3(0.0, 1.0, -rise_dir * slope).normalized()
	return [
		_f(base, -up_n, ROOF),
		_f(base + Vector3.UP * thick, up_n, ROOF),
		_f(Vector3(x1, 0.0, 0.0), Vector3.RIGHT, ROOF),
		_f(Vector3(x0, 0.0, 0.0), Vector3.LEFT, ROOF),
		_f(Vector3(0.0, 0.0, z1), Vector3.BACK, ROOF),
		_f(Vector3(0.0, 0.0, z0), Vector3.FORWARD, ROOF),
	]


## One side of the bay's roof (side -1 left, +1 right), x from lo to hi.
func _bay_slab(side: float, lo: float, hi: float, slope: float, thick: float) -> Array:
	# Underside: y = WALL_TOP + (BAY_HALF - side * x) * slope, rising toward the
	# middle; the slab is above it.
	var base := Vector3(side * BAY_HALF, WALL_TOP, 0.0)
	var up_n := Vector3(side * slope, 1.0, 0.0).normalized()
	return [
		_f(base, -up_n, ROOF),
		_f(base + Vector3.UP * thick, up_n, ROOF),
		_f(Vector3(hi, 0.0, 0.0), Vector3.RIGHT, ROOF),
		_f(Vector3(lo, 0.0, 0.0), Vector3.LEFT, ROOF),
		_f(Vector3(0.0, 0.0, -1.2), Vector3.BACK, ROOF),
		_f(Vector3(0.0, 0.0, BAY_FRONT - 0.3), Vector3.FORWARD, ROOF),
	]


## The porch: a step, two posts, beams, and a little gable roof with a
## pediment, in front of the bay's door.
func _porch() -> void:
	var half := 1.4
	var post := 0.08
	var beam_y := 2.75
	var top := 2.95
	_world.append(_box(Vector3(-half, 0.0, PORCH_FRONT), Vector3(half, FLOOR_0, BAY_FRONT), TRIM))
	for x: float in [-half + 0.2, half - 0.2]:
		_world.append(_box(Vector3(x - post, FLOOR_0, PORCH_FRONT + 0.2 - post), Vector3(x + post, beam_y, PORCH_FRONT + 0.2 + post), TRIM))
		_world.append(_box(Vector3(x - post, beam_y, PORCH_FRONT + 0.1), Vector3(x + post, top, BAY_FRONT), TRIM))
	_world.append(_box(Vector3(-half, beam_y, PORCH_FRONT + 0.1), Vector3(half, top, PORCH_FRONT + 0.3), TRIM))
	# Its roof: 35 degrees, ridge along Z over the door.
	var slope := tan(deg_to_rad(35.0))
	var thick := 0.16 / cos(deg_to_rad(35.0))
	for side: float in [-1.0, 1.0]:
		var edge := side * (half + 0.15)
		var base := Vector3(side * half, top, 0.0)
		var up_n := Vector3(side * slope, 1.0, 0.0).normalized()
		_world.append([
			_f(base, -up_n, ROOF),
			_f(base + Vector3.UP * thick, up_n, ROOF),
			_f(Vector3(maxf(edge, 0.0), 0.0, 0.0), Vector3.RIGHT, ROOF),
			_f(Vector3(minf(edge, 0.0), 0.0, 0.0), Vector3.LEFT, ROOF),
			_f(Vector3(0.0, 0.0, BAY_FRONT), Vector3.BACK, ROOF),
			_f(Vector3(0.0, 0.0, PORCH_FRONT - 0.1), Vector3.FORWARD, ROOF),
		])
	# The pediment: a plaster triangle under the porch roof's front.
	_world.append([
		_f(Vector3(0.0, top, 0.0), Vector3.DOWN, TRIM),
		_f(Vector3(0.0, 0.0, PORCH_FRONT + 0.1), Vector3.FORWARD, TRIM),
		_f(Vector3(0.0, 0.0, PORCH_FRONT + 0.25), Vector3.BACK, TRIM),
		_f(Vector3(-half, top, 0.0), Vector3(-slope, 1.0, 0.0).normalized(), TRIM),
		_f(Vector3(half, top, 0.0), Vector3(slope, 1.0, 0.0).normalized(), TRIM),
	])


# ---- Inside ----------------------------------------------------------------------------------

func _inside() -> void:
	var w := HALF_W - T
	var d := HALF_D - T
	var stairs_x0 := -4.65
	var stairs_x1 := -0.75
	var stairs_z0 := 2.75
	var stairs_z1 := d
	# The floors: the ground floor, between the floors (a hole over the
	# stairs), the ceiling upstairs (a hole for the attic hatch), and the bay's.
	var floor_faces := {"+y": FLOOR}
	_interior.append(_box(Vector3(-w, 0.0, -d), Vector3(w, FLOOR_0, d), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-BAY_HALF + T, 0.0, BAY_FRONT + T), Vector3(BAY_HALF - T, FLOOR_0, -d), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-w, CEIL_0, -d), Vector3(w, FLOOR_1, stairs_z0), INSIDE, floor_faces))
	_interior.append(_box(Vector3(stairs_x1, CEIL_0, stairs_z0), Vector3(w, FLOOR_1, d), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-w, CEIL_0, stairs_z0), Vector3(stairs_x0, FLOOR_1, d), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-BAY_HALF + T, CEIL_0, BAY_FRONT + T), Vector3(BAY_HALF - T, FLOOR_1, -d), INSIDE, floor_faces))
	var hatch := [-0.45, 0.45, -2.0, -1.1]
	_interior.append(_box(Vector3(-w, CEIL_1, -d), Vector3(w, WALL_TOP, hatch[2]), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-w, CEIL_1, hatch[3]), Vector3(w, WALL_TOP, d), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-w, CEIL_1, hatch[2]), Vector3(hatch[0], WALL_TOP, hatch[3]), INSIDE, floor_faces))
	_interior.append(_box(Vector3(hatch[1], CEIL_1, hatch[2]), Vector3(w, WALL_TOP, hatch[3]), INSIDE, floor_faces))
	_interior.append(_box(Vector3(-BAY_HALF + T, CEIL_1, BAY_FRONT + T), Vector3(BAY_HALF - T, WALL_TOP, -d), INSIDE, floor_faces))
	_door({"targetname": "house_attic", "message": "Locked.", "axis": "2", "hinge": "3"}, "", hatch[0], hatch[1], hatch[2], hatch[3], CEIL_1, CEIL_1 + 0.06)
	# Ground floor: the living room (left, open) and, past the wall at x 2,
	# the study (front) and the kitchen (back), each behind a locked door.
	var door_y := FLOOR_0 + DOOR_H
	_wall(_interior, "z", -d, d, 2.0, 2.2, FLOOR_0, CEIL_0, [[-2.45, -1.55, FLOOR_0, door_y], [1.55, 2.45, FLOOR_0, door_y]], 0)
	_locked_door("house_study", "z", -2.45, -1.55, 2.0, 2.2, FLOOR_0, door_y)
	_locked_door("house_kitchen", "z", 1.55, 2.45, 2.0, 2.2, FLOOR_0, door_y)
	_wall(_interior, "x", 2.2, w, -0.1, 0.1, FLOOR_0, CEIL_0, [], 0)
	# The stairs: 15 steps of 20 cm up the living room's back wall, with a
	# smooth ramp to walk on (clip: collision only).
	var steps := 15
	var run := (stairs_x1 - stairs_x0) / steps
	var rise := (FLOOR_1 - FLOOR_0) / steps
	for i in steps:
		_interior.append(_box(Vector3(stairs_x0 + i * run, FLOOR_0, stairs_z0), Vector3(stairs_x0 + (i + 1) * run, FLOOR_0 + (i + 1) * rise, stairs_z1),
				INSIDE, {"+y": FLOOR, "-x": FLOOR}))
	var k := rise / run
	_world.append([
		_f(Vector3(0.0, FLOOR_0, 0.0), Vector3.DOWN, CLIP),
		_f(Vector3(stairs_x1, 0.0, 0.0), Vector3.RIGHT, CLIP),
		_f(Vector3(0.0, 0.0, stairs_z0), Vector3.FORWARD, CLIP),
		_f(Vector3(0.0, 0.0, stairs_z1), Vector3.BACK, CLIP),
		_f(Vector3(stairs_x0, FLOOR_0, 0.0), Vector3(-k, 1.0, 0.0).normalized(), CLIP),
	])
	# The cellar door: under the stairs, on their side.
	_locked_door("house_cellar", "x", -2.3, -1.5, stairs_z0 - 0.06, stairs_z0, FLOOR_0, FLOOR_0 + 1.8)
	# Upstairs: the stairwell walled off from bedroom 1, the landing at the
	# top with its locked door to the hall; off the hall, bedroom 1 (left),
	# bedroom 2 and the bathroom (right).
	var up_door := FLOOR_1 + DOOR_H
	_wall(_interior, "x", -w, 0.75, 2.5, stairs_z0, FLOOR_1, CEIL_1, [[-0.45, 0.45, FLOOR_1, up_door]], 0)
	_locked_door("house_landing", "x", -0.45, 0.45, 2.5, stairs_z0, FLOOR_1, up_door)
	_wall(_interior, "z", BAY_FRONT + T, 2.5, -1.0, -0.75, FLOOR_1, CEIL_1, [[-1.45, -0.55, FLOOR_1, up_door]], 0)
	_locked_door("house_bedroom_1", "z", -1.45, -0.55, -1.0, -0.75, FLOOR_1, up_door)
	_wall(_interior, "z", BAY_FRONT + T, d, 0.75, 1.0, FLOOR_1, CEIL_1, [[-2.45, -1.55, FLOOR_1, up_door], [1.6, 2.4, FLOOR_1, up_door]], 0)
	_locked_door("house_bedroom_2", "z", -2.45, -1.55, 0.75, 1.0, FLOOR_1, up_door)
	_locked_door("house_bathroom", "z", 1.6, 2.4, 0.75, 1.0, FLOOR_1, up_door)
	_wall(_interior, "x", 1.0, w, 0.9, 1.1, FLOOR_1, CEIL_1, [], 0)
	# Grandma, in the living room, facing the front door.
	_points.append(["npc_grandma", Vector3(-2.6, FLOOR_0, -1.2) * SIZE, {"angle": "180"}])


func _locked_door(name: String, along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float) -> void:
	_door_frame(_interior, along, a0, a1, t0, t1, y0, y1)
	_door({"targetname": name, "message": "Locked."}, along, a0, a1, t0, t1, y0, y1)


# ---- Pieces ----------------------------------------------------------------------------------

## A wall along `along` ("x" or "z") from a0 to a1, t0..t1 thick across,
## y0..y1 high, with openings [a0, a1, y0, y1]. `out`: which side faces
## outside (-1 the low side, 1 the high side, 0 inside both).
func _wall(into: Array, along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float, openings: Array, out: int) -> void:
	var cuts := [a0, a1]
	for o: Array in openings:
		cuts.append(clampf(o[0], a0, a1))
		cuts.append(clampf(o[1], a0, a1))
	cuts.sort()
	for i in cuts.size() - 1:
		var s0: float = cuts[i]
		var s1: float = cuts[i + 1]
		if s1 - s0 < 0.001:
			continue
		var mid := (s0 + s1) * 0.5
		var gaps: Array = []
		for o: Array in openings:
			if o[0] < mid and mid < o[1]:
				gaps.append([o[2], o[3]])
		gaps.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var y := y0
		for g: Array in gaps:
			if g[0] > y + 0.001:
				into.append(_wall_piece(along, s0, s1, t0, t1, y, g[0], out))
			y = maxf(y, g[1])
		if y < y1 - 0.001:
			into.append(_wall_piece(along, s0, s1, t0, t1, y, y1, out))


func _wall_piece(along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float, out: int) -> Array:
	var skin := WALL if out != 0 else INSIDE
	var low := WALL if out < 0 else INSIDE
	var high := WALL if out > 0 else INSIDE
	if along == "x":
		return _box(Vector3(a0, y0, t0), Vector3(a1, y1, t1), skin, {"-z": low, "+z": high})
	return _box(Vector3(t0, y0, a0), Vector3(t1, y1, a1), skin, {"-x": low, "+x": high})


## A box across a wall: a0..a1 along it, t0..t1 through it, y0..y1.
func _across(along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float, texture: String) -> Array:
	if along == "x":
		return _box(Vector3(a0, y0, t0), Vector3(a1, y1, t1), texture)
	return _box(Vector3(t0, y0, a0), Vector3(t1, y1, a1), texture)


## A window in an opening: a dark frame round it, a dark pane in the middle
## of the wall, cross bars both sides of it, and a sill outside.
func _window(along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float, out: int) -> void:
	var f := 0.07
	var mid := (t0 + t1) * 0.5
	_world.append(_across(along, a0, a0 + f, t0, t1, y0, y1, WOOD))
	_world.append(_across(along, a1 - f, a1, t0, t1, y0, y1, WOOD))
	_world.append(_across(along, a0 + f, a1 - f, t0, t1, y0, y0 + f, WOOD))
	_world.append(_across(along, a0 + f, a1 - f, t0, t1, y1 - f, y1, WOOD))
	_world.append(_across(along, a0 + f, a1 - f, mid - 0.02, mid + 0.02, y0 + f, y1 - f, GLASS))
	var am := (a0 + a1) * 0.5
	var ym := y0 + (y1 - y0) * 0.6
	for side in [[mid - 0.06, mid - 0.02], [mid + 0.02, mid + 0.06]]:
		_world.append(_across(along, am - 0.025, am + 0.025, side[0], side[1], y0 + f, y1 - f, WOOD))
		_world.append(_across(along, a0 + f, am - 0.025, side[0], side[1], ym - 0.025, ym + 0.025, WOOD))
		_world.append(_across(along, am + 0.025, a1 - f, side[0], side[1], ym - 0.025, ym + 0.025, WOOD))
	var outside := [t0 - 0.08, t0] if out < 0 else [t1, t1 + 0.08]
	_world.append(_across(along, a0 - 0.06, a1 + 0.06, outside[0], outside[1], y0 - 0.06, y0, TRIM))


## A doorway's frame: the sides and the top, through the wall.
func _door_frame(into: Array, along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float) -> void:
	var f := 0.07
	into.append(_across(along, a0, a0 + f, t0, t1, y0, y1, WOOD))
	into.append(_across(along, a1 - f, a1, t0, t1, y0, y1, WOOD))
	into.append(_across(along, a0 + f, a1 - f, t0, t1, y1 - f, y1, WOOD))


## A swinging door (func_door_rotating) in a doorway, hinged at its low end.
## along "" = a flat hatch (a0..a1 x, t0..t1 z, y0..y1).
func _door(properties: Dictionary, along: String, a0: float, a1: float, t0: float, t1: float, y0: float, y1: float) -> void:
	var brush: Array
	if along.is_empty():
		brush = _box(Vector3(a0, y0, t0), Vector3(a1, y1, t1), WOOD)
	else:
		var f := 0.07
		var mid := (t0 + t1) * 0.5
		brush = _across(along, a0 + f, a1 - f, mid - 0.04, mid + 0.04, y0, y1 - f, WOOD)
	var props := {"hinge": "3"}
	props.merge(properties, true)
	_doors.append([brush, props])


func _box(lo: Vector3, hi: Vector3, texture: String, faces: Dictionary = {}) -> Array:
	return [
		_f(hi, Vector3.RIGHT, faces.get("+x", texture)),
		_f(lo, Vector3.LEFT, faces.get("-x", texture)),
		_f(hi, Vector3.UP, faces.get("+y", texture)),
		_f(lo, Vector3.DOWN, faces.get("-y", texture)),
		_f(hi, Vector3.BACK, faces.get("+z", texture)),
		_f(lo, Vector3.FORWARD, faces.get("-z", texture)),
	]


## A brush face: the plane through `point` facing out along `normal` (the
## house at GrandmasHouse.SIZE).
func _f(point: Vector3, normal: Vector3, texture: String) -> Dictionary:
	return {p = point * SIZE, n = normal.normalized(), tex = texture}


# ---- The map ---------------------------------------------------------------------------------

func _write_map(path: String) -> Error:
	var lines := PackedStringArray()
	lines.append("// Game: 2v-2\n// Format: Valve")
	lines.append("// Grandma's house -- made by tools/make_grandmas_house.gd; edit freely from here (then Build the scene's Map).")
	lines.append("{\n\"classname\" \"worldspawn\"\n\"mapversion\" \"220\"")
	for brush: Array in _world:
		lines.append(_brush_text(brush))
	lines.append("}")
	lines.append("{\n\"classname\" \"func_detail\"\n\"targetname\" \"house_interior\"")
	for brush: Array in _interior:
		lines.append(_brush_text(brush))
	lines.append("}")
	for door: Array in _doors:
		var entity := PackedStringArray(["{", "\"classname\" \"func_door_rotating\""])
		for key: String in door[1]:
			entity.append("\"%s\" \"%s\"" % [key, door[1][key]])
		entity.append(_brush_text(door[0]))
		entity.append("}")
		lines.append("\n".join(entity))
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


## Valve 220: three points on the plane (in that order its normal faces
## out: (p3 - p1) x (p2 - p1)), the texture, its U and V axes, scale.
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
	var scale: float = TILE.get(face.tex, 2.0) * UNITS / 256.0
	return "( %s ) ( %s ) ( %s ) %s [ %s 0 ] [ %s 0 ] 0 %s %s" % [
		_v(_to_map(p1) * UNITS), _v(_to_map(p2) * UNITS), _v(_to_map(p3) * UNITS), face.tex,
		_v(_to_map(u)), _v(_to_map(v)), _n(scale), _n(scale)]


## Godot (y up) to Quake/TrenchBroom (z up): map = (z, x, y).
func _to_map(v: Vector3) -> Vector3:
	return Vector3(v.z, v.x, v.y)


func _v(v: Vector3) -> String:
	return "%s %s %s" % [_n(v.x), _n(v.y), _n(v.z)]


func _n(value: float) -> String:
	var rounded := snappedf(value, 0.0001)
	return str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)


# ---- The window texture ----------------------------------------------------------------------

## Dark, filthy glass you can't see through (the user's): near-black with a
## greenish tint, grime blotches, a few streaks down it, a faint sheen.
func _window_image() -> Image:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 1957
	noise.frequency = 0.08
	var dice := RandomNumberGenerator.new()
	dice.seed = 1957
	var streaks: Array = []
	for i in 7:
		streaks.append([dice.randi_range(0, size - 1), dice.randf_range(0.3, 1.0)])
	for y in size:
		for x in size:
			var grime := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var shade := 0.05 + grime * 0.07
			var sheen := maxf(0.0, 1.0 - absf((x + y) - size * 0.7) / 10.0) * 0.04
			for s: Array in streaks:
				if absi(x - int(s[0])) <= 0 and float(y) / size < s[1]:
					shade += 0.025
			image.set_pixel(x, y, Color(shade * 0.85 + sheen, shade + sheen, shade * 0.9 + sheen))
	return image
