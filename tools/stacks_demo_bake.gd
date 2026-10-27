extends RefCounted

## The Stacks demo (the user's, 2026-10-27: docs/ZOMBIES_DIRECTION.md) --
## the first playable piece of the Zombies direction, Black Ops 1 style: a
## start room, then areas bought open one door at a time, loops to run the
## horde round, windows they come in through. Cold brutalist dusk; Babbdi /
## Vholume / liminal concrete. Written as a TrenchBroom map and built into a
## scene with everything the game needs. Run by tools/make_stacks_demo.gd.
## Re-running overwrites the map and the scene: once the map's been edited in
## TrenchBroom, rebuild it with the scene's own FuncGodotMap ("Map", Build).
##   THE DEPTHS (the start): a flooded concrete room under the main tower,
##   ankle-deep, two boarded windows (and two painted).
##   THE TUNNEL (a door): two ramp flights up through the tower's foot.
##   THE LOBBY: brutalist, pillars to loop round, a ramp to a mezzanine,
##   windows (boarded and painted) out onto the courtyard.
##   THE APARTMENT CORRIDOR (a door): low and endless, closed doors down both
##   sides, two flats open (their windows on the courtyard), round to the
##   stair hall (a door).
##   THE STAIR HALL (a door): Babbdi -- giant steps to mantle up a wall to a
##   ledge, a bridge to a central block, a ramp back down; stairs that stop
##   in mid-air.
##   THE COURTYARD (a door): concrete, open to the dusk, walled by three more
##   towers, raised walks round its sides, planters and a plinth to loop.
## The towers are the Stack's sizes (1.4, 2, 2.8, 3.6 km), its painted-window
## concrete outside; the giants (SkylineLayer) stand round in the fog.
## Half the windows are real (boarded: Barricade), half painted (the user's).
## Its own space: the lobby's floor at y 0, metres; maps are 8 units a metre.

const MAP := "res://maps/zombies/stacks_demo.map"
const MAP_SETTINGS := "res://maps/megastructures/megastructure_map_settings.tres"
const SCENE := "res://scenes/zombies/stacks_demo.tscn"
const UNITS := 8.0

const FACADE := "Megastructure/stack_concrete"
const WALL := "Megastructure/stack_plain"
const FLOOR := "Megastructure/stack_stained"
const TILE := {FACADE: 8.0, WALL: 4.0, FLOOR: 4.0}

## The towers: [lo, hi] (the Stack's sizes and heights).
const TOWERS := [
	[Vector3(-60.0, 0.0, -60.0), Vector3(60.0, 1400.0, 60.0)],
	[Vector3(-170.0, 0.0, 64.0), Vector3(-72.0, 2000.0, 170.0)],
	[Vector3(72.0, 0.0, 64.0), Vector3(190.0, 2800.0, 190.0)],
	[Vector3(-70.0, 0.0, 152.0), Vector3(70.0, 3600.0, 260.0)],
]
## The courtyard's corners, walled where the towers don't meet.
const GAP_WALLS := [
	[Vector3(-74.0, 0.0, 60.0), Vector3(-60.0, 40.0, 64.0)],
	[Vector3(60.0, 0.0, 60.0), Vector3(74.0, 40.0, 64.0)],
	[Vector3(-73.0, 0.0, 150.0), Vector3(-69.0, 40.0, 172.0)],
	[Vector3(69.0, 0.0, 150.0), Vector3(73.0, 40.0, 172.0)],
]
const GROUND := [Vector3(-300.0, -40.0, -200.0), Vector3(300.0, 0.0, 340.0)]
## A crawl window's opening (Barricade.SIZE) and its sill.
const WINDOW := Vector2(1.6, 1.6)
const SILL := 0.9
const PLAYER := "res://scenes/player/player.tscn"
const HUD := "res://scenes/ui/hud.tscn"
const LOADOUT := ["res://weapons/starter_gun.tres", "res://weapons/shotgun.tres", "res://weapons/grenade.tres",
		"res://weapons/pkm.tres", "res://weapons/ppsh.tres", "res://weapons/rpg.tres", "res://weapons/revolver.tres",
		"res://weapons/machine_gun.tres", "res://weapons/sniper.tres"]
## Cold dusk (the user's).
const DUSK_FOG := Color(0.4, 0.43, 0.5)
const SKY_TOP := Color(0.16, 0.19, 0.27)
const SKY_HORIZON := Color(0.52, 0.42, 0.42)
const SUN := Color(1.0, 0.64, 0.48)
const LAMP := Color(0.72, 0.82, 1.0)

## [lo, hi, outer lo, outer hi, is a tower (its outer faces painted)].
var _solids: Array = []
var _voids: Array[AABB] = []
## Brushes added whole (ramps, steps, pillars): [faces].
var _extra: Array = []
var _world: Array = []
## Nodes for the scene: [kind, transform, settings].
var _things: Array = []


func run(_tree: SceneTree) -> void:
	for path in [MAP, SCENE]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_solids.append([GROUND[0], GROUND[1], GROUND[0], GROUND[1], false])
	for t: Array in TOWERS:
		_solids.append([t[0], t[1], t[0], t[1], true])
	for w: Array in GAP_WALLS:
		_solids.append([w[0], w[1], w[0], w[1], true])
	_depths()
	_tunnel()
	_lobby()
	_corridor()
	_stair_hall()
	_courtyard()
	_carve()
	print("map: ", MAP, " (", _world.size(), " brushes; error ", _write_map(ProjectSettings.globalize_path(MAP)), ")")
	var root := Node3D.new()
	root.name = "StacksDemo"
	var map := (load("res://addons/func_godot/src/map/func_godot_map.gd") as GDScript).new() as Node3D
	map.name = "Map"
	map.set("map_settings", load(MAP_SETTINGS))
	map.set("local_map_file", MAP)
	map.set("hyperplane_size", 8192.0) # (the towers go to 3.6 km)
	map.call("build")
	root.add_child(map)
	map.owner = root
	_own(map, map, root)
	_build_things(root)
	var scene := PackedScene.new()
	var error := scene.pack(root)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE)
	print("the Stacks demo -> ", SCENE, " (error ", error, ")")
	root.free()


func _own(node: Node, map: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child.owner == map or child.owner == null:
			child.owner = owner_node
		if child.scene_file_path.is_empty():
			_own(child, map, owner_node)


# ---- The places ------------------------------------------------------------------------------

## The start: flooded, under the main tower.
func _depths() -> void:
	_room(Vector3(24.0, -12.0, 30.0), Vector3(48.0, -5.0, 50.0))
	_thing(&"water", Transform3D(Basis.IDENTITY, Vector3(36.0, -11.75, 40.0)), {size = Vector2(24.0, 20.0)})
	_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3(36.0, -6.0, 40.0)), {energy = 1.2, range = 16.0})
	# Boarded windows (the horde's way in), with closets behind; painted ones.
	_crawl_window(Vector3(23.0, -12.0, 36.0), Vector3.LEFT, Vector3(16.0, -12.0, 32.0), Vector3(22.0, -8.0, 40.0))
	_crawl_window(Vector3(49.0, -12.0, 44.0), Vector3.RIGHT, Vector3(50.0, -12.0, 40.0), Vector3(56.0, -8.0, 48.0))
	_painted_window(Vector3(24.0, -12.0, 44.0), Vector3.RIGHT)
	_painted_window(Vector3(48.0, -12.0, 36.0), Vector3.LEFT)
	_thing(&"spawn", Transform3D(Basis.IDENTITY, Vector3(36.0, -11.9, 44.0)), {})


## Two ramp flights up through the tower's foot, to the lobby (a door first).
func _tunnel() -> void:
	_room(Vector3(44.0, -12.0, 28.0), Vector3(48.0, -8.0, 30.0)) # the doorway
	_door(Vector3(46.0, -10.0, 29.0), Vector3(4.0, 4.0, 0.4), 0.0)
	_room(Vector3(44.0, -12.0, -2.0), Vector3(48.0, -2.0, 28.0))
	_ramp_z(44.0, 48.0, 28.0, -12.0, -2.0, -6.0)
	_room(Vector3(24.0, -6.0, -6.0), Vector3(48.0, 2.0, -2.0)) # the turn
	_room(Vector3(24.0, -6.0, -2.0), Vector3(28.0, 4.0, 28.0))
	_ramp_z(24.0, 28.0, -2.0, -6.0, 28.0, 0.0)
	_room(Vector3(20.0, 0.0, 28.0), Vector3(28.0, 5.0, 34.0)) # up into the lobby
	_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3(36.0, -1.0, -4.0)), {energy = 0.8, range = 12.0})


## The lobby: pillars, a ramp up to a mezzanine, windows on the courtyard.
func _lobby() -> void:
	_room(Vector3(-20.0, 0.0, 28.0), Vector3(20.0, 12.0, 58.0))
	for x: float in [-10.0, 0.0, 10.0]:
		_block(Vector3(x - 2.0, 0.0, 38.0), Vector3(x + 2.0, 12.0, 42.0))
	_block(Vector3(-20.0, 5.0, 50.0), Vector3(20.0, 5.6, 58.0)) # the mezzanine
	_ramp_z(-20.0, -16.0, 28.0, 0.0, 50.0, 5.6)
	# The doors: the courtyard, the corridor, the stair hall.
	_room(Vector3(-3.0, 0.0, 58.0), Vector3(3.0, 5.0, 60.0))
	_door(Vector3(0.0, 2.5, 59.0), Vector3(6.0, 5.0, 0.4), 0.0)
	_room(Vector3(-24.0, 0.0, 40.0), Vector3(-20.0, 3.0, 44.0))
	_door(Vector3(-22.0, 1.5, 42.0), Vector3(4.0, 3.0, 0.4), PI * 0.5)
	_room(Vector3(-3.0, 0.0, 24.0), Vector3(3.0, 4.0, 28.0))
	_door(Vector3(0.0, 2.0, 26.0), Vector3(6.0, 4.0, 0.4), 0.0)
	# Windows on the courtyard: two boarded, two painted.
	_crawl_window(Vector3(-14.0, 0.0, 59.0), Vector3.BACK)
	_crawl_window(Vector3(10.0, 0.0, 59.0), Vector3.BACK)
	_painted_window(Vector3(-9.0, 0.0, 58.0), Vector3.FORWARD)
	_painted_window(Vector3(15.0, 0.0, 58.0), Vector3.FORWARD)
	for x: float in [-12.0, 12.0]:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3(x, 10.0, 45.0)), {energy = 1.0, range = 20.0})


## Low, long, the same door after door; two flats open.
func _corridor() -> void:
	_room(Vector3(-56.0, 0.0, 40.0), Vector3(-24.0, 3.2, 44.0))
	_room(Vector3(-56.0, 0.0, -20.0), Vector3(-52.0, 3.2, 44.0))
	_room(Vector3(-52.0, 0.0, -20.0), Vector3(-28.0, 3.2, -16.0))
	_room(Vector3(-28.0, 0.0, -20.0), Vector3(-24.0, 3.0, -16.0))
	_door(Vector3(-26.0, 1.5, -18.0), Vector3(4.0, 3.0, 0.4), PI * 0.5)
	# The flats, their windows on the courtyard.
	for flat: Array in [[-50.0, -40.0, -45.0], [-36.0, -26.0, -31.0]]:
		_room(Vector3(flat[0], 0.0, 46.0), Vector3(flat[1], 3.2, 58.0))
		_room(Vector3(flat[2] - 1.0, 0.0, 44.0), Vector3(flat[2] + 1.0, 2.2, 46.0))
		_crawl_window(Vector3(flat[0] + 3.0, 0.0, 59.0), Vector3.BACK)
		_painted_window(Vector3(flat[1] - 2.5, 0.0, 58.0), Vector3.FORWARD)
		_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3((flat[0] + flat[1]) * 0.5, 2.8, 52.0)), {energy = 0.5, range = 8.0})
	# Closed doors down both sides, the same every 6 m.
	for along in range(0, 6):
		var at := -50.0 + along * 5.0
		if absf(at - (-45.0)) > 1.5 and absf(at - (-31.0)) > 1.5:
			_thing(&"apartment_door", Transform3D(Basis(Vector3.UP, PI), Vector3(at, 1.05, 44.0 - 0.06)), {})
		_thing(&"apartment_door", Transform3D(Basis.IDENTITY, Vector3(at, 1.05, 40.0 + 0.06)), {})
	for along in range(0, 9):
		var at := -14.0 + along * 6.0
		_thing(&"apartment_door", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-56.0 + 0.06, 1.05, at)), {})
		_thing(&"apartment_door", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-52.0 - 0.06, 1.05, at)), {})
	for at: Vector3 in [Vector3(-40.0, 2.9, 42.0), Vector3(-54.0, 2.9, 20.0), Vector3(-54.0, 2.9, -4.0), Vector3(-40.0, 2.9, -18.0)]:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, at), {energy = 0.45, range = 9.0})


## Babbdi's stair hall: giant steps, a bridge, a ramp down, stairs to nowhere.
func _stair_hall() -> void:
	_room(Vector3(-24.0, 0.0, -24.0), Vector3(20.0, 24.0, 24.0))
	# Giant steps up the east wall (1.2 m each: mantle them).
	for i in 8:
		_block(Vector3(11.0, 0.0, -20.0 + i * 3.0), Vector3(20.0, 1.2 * (i + 1), -17.0 + i * 3.0))
	_block(Vector3(11.0, 0.0, 4.0), Vector3(20.0, 9.6, 24.0)) # the ledge they reach
	_block(Vector3(-6.0, 0.0, -6.0), Vector3(6.0, 9.6, 6.0)) # the central block
	_block(Vector3(6.0, 9.0, -2.0), Vector3(11.0, 9.6, 2.0)) # the bridge
	_ramp_z(-10.0, -6.0, -22.0, 0.0, 6.0, 9.6) # down the far side
	_ramp_z(-20.0, -14.0, -20.0, 0.0, -6.0, 6.0) # stairs to nowhere
	_block(Vector3(-20.0, 5.7, -6.0), Vector3(-14.0, 6.0, -4.0))
	# Windows: two boarded (closets behind), two painted high up.
	_crawl_window(Vector3(-14.0, 0.0, -25.0), Vector3.FORWARD, Vector3(-18.0, 0.0, -32.0), Vector3(-10.0, 4.0, -26.0))
	_crawl_window(Vector3(8.0, 0.0, -25.0), Vector3.FORWARD, Vector3(4.0, 0.0, -32.0), Vector3(12.0, 4.0, -26.0))
	_painted_window(Vector3(-2.0, 14.0, -24.0), Vector3.BACK)
	_painted_window(Vector3(-24.0, 12.0, 10.0), Vector3.RIGHT)
	for at: Vector3 in [Vector3(-12.0, 20.0, -12.0), Vector3(12.0, 20.0, 12.0)]:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, at), {energy = 1.0, range = 26.0})


## The concrete courtyard between the towers, open to the dusk.
func _courtyard() -> void:
	for side: float in [-1.0, 1.0]:
		var x0 := -72.0 if side < 0.0 else 66.0
		_block(Vector3(x0, 0.0, 74.0), Vector3(x0 + 6.0, 1.2, 148.0)) # the raised walk
		_ramp_z(x0, x0 + 6.0, 64.0, 0.0, 74.0, 1.2)
	for at: Vector2 in [Vector2(-24.0, 90.0), Vector2(24.0, 90.0), Vector2(-24.0, 125.0), Vector2(24.0, 125.0)]:
		_block(Vector3(at.x - 3.0, 0.0, at.y - 3.0), Vector3(at.x + 3.0, 1.0, at.y + 3.0)) # planters
	_block(Vector3(-5.0, 0.0, 100.0), Vector3(5.0, 10.0, 110.0)) # the plinth
	# Windows on the other towers: boarded into closets in them.
	_crawl_window(Vector3(-73.0, 0.0, 100.0), Vector3.LEFT, Vector3(-82.0, 0.0, 96.0), Vector3(-74.0, 4.0, 104.0))
	_crawl_window(Vector3(73.0, 0.0, 120.0), Vector3.RIGHT, Vector3(74.0, 0.0, 116.0), Vector3(82.0, 4.0, 124.0))
	_crawl_window(Vector3(31.0, 0.0, 153.0), Vector3.BACK, Vector3(27.0, 0.0, 154.0), Vector3(35.0, 4.0, 162.0))
	for at: Vector3 in [Vector3(-40.0, 0.0, 80.0), Vector3(40.0, 0.0, 80.0), Vector3(-40.0, 0.0, 135.0), Vector3(40.0, 0.0, 135.0)]:
		_thing(&"lamp_post", Transform3D(Basis.IDENTITY, at), {})


# ---- Pieces ----------------------------------------------------------------------------------

func _room(lo: Vector3, hi: Vector3) -> void:
	_voids.append(AABB(lo, hi - lo))


func _block(lo: Vector3, hi: Vector3) -> void:
	_extra.append(_box(lo, hi, WALL, {"+y": FLOOR}))


## A ramp along Z between (z_low, y_low) and (z_high, y_high), x0..x1 wide.
func _ramp_z(x0: float, x1: float, z_low: float, y_low: float, z_high: float, y_high: float) -> void:
	var normal := Vector3(0.0, z_high - z_low, -(y_high - y_low)).normalized()
	if normal.y < 0.0:
		normal = -normal
	var bottom := minf(y_low, y_high) - 0.5
	var z0 := minf(z_low, z_high)
	var z1 := maxf(z_low, z_high)
	_extra.append([
		_f(Vector3(x0, y_low, z_low), normal, FLOOR),
		_f(Vector3(x0, bottom, z0), Vector3.DOWN, WALL),
		_f(Vector3(x1, bottom, z1), Vector3.RIGHT, WALL),
		_f(Vector3(x0, bottom, z0), Vector3.LEFT, WALL),
		_f(Vector3(x1, bottom, z1), Vector3.BACK, WALL),
		_f(Vector3(x0, bottom, z0), Vector3.FORWARD, WALL),
	])


## A boarded window at `at` (its middle along the wall, at floor level),
## looking out `out`; `closet_lo/hi`: the room behind it the horde comes
## from (none: it opens on open ground).
func _crawl_window(at: Vector3, out: Vector3, closet_lo := Vector3.INF, closet_hi := Vector3.INF) -> void:
	var across := Vector3.UP.cross(out).abs()
	var half := across * WINDOW.x * 0.5 + out.abs() * 1.05
	var middle := at + Vector3.UP * (SILL + WINDOW.y * 0.5)
	_room(middle - half - Vector3.UP * WINDOW.y * 0.5, middle + half + Vector3.UP * WINDOW.y * 0.5)
	if closet_lo.is_finite():
		_room(closet_lo, closet_hi)
	_thing(&"barricade", Transform3D(Basis.looking_at(out, Vector3.UP), middle), {})


## A painted window: a shallow dark pane set into the wall at `at` (floor
## level), its glass facing `facing` (into the room).
func _painted_window(at: Vector3, facing: Vector3) -> void:
	var across := Vector3.UP.cross(facing).abs()
	var middle := at + Vector3.UP * (SILL + WINDOW.y * 0.5) - facing * 0.15
	var half := across * WINDOW.x * 0.5 + facing.abs() * 0.15 + Vector3.UP * WINDOW.y * 0.5
	_room(middle - half, middle + half)
	_thing(&"pane", Transform3D(Basis.looking_at(-facing, Vector3.UP), middle - facing * 0.12), {})


func _door(at: Vector3, size: Vector3, turn: float) -> void:
	_thing(&"door", Transform3D(Basis(Vector3.UP, turn), at), {size = size})


func _thing(kind: StringName, xf: Transform3D, settings: Dictionary) -> void:
	_things.append([kind, xf, settings])


# ---- Carving ---------------------------------------------------------------------------------

## Every solid with every room cut out of it, as boxes; their outer faces
## (a tower's own walls) painted with windows.
func _carve() -> void:
	for solid: Array in _solids:
		var pieces: Array[AABB] = [AABB(solid[0], (solid[1] as Vector3) - (solid[0] as Vector3))]
		for room in _voids:
			var next: Array[AABB] = []
			for piece in pieces:
				next.append_array(_subtract(piece, room))
			pieces = next
		for piece in pieces:
			_world.append(_piece_brush(piece, solid))
	_world.append_array(_extra)


static func _subtract(a: AABB, b: AABB) -> Array[AABB]:
	if not a.intersects(b) or a.intersection(b).get_volume() < 0.0001:
		return [a]
	var out: Array[AABB] = []
	var lo := a.position
	var hi := a.end
	var c := a.intersection(b)
	if c.position.x > lo.x:
		out.append(AABB(lo, Vector3(c.position.x - lo.x, hi.y - lo.y, hi.z - lo.z)))
	if c.end.x < hi.x:
		out.append(AABB(Vector3(c.end.x, lo.y, lo.z), Vector3(hi.x - c.end.x, hi.y - lo.y, hi.z - lo.z)))
	var x0 := c.position.x
	var x1 := c.end.x
	if c.position.y > lo.y:
		out.append(AABB(Vector3(x0, lo.y, lo.z), Vector3(x1 - x0, c.position.y - lo.y, hi.z - lo.z)))
	if c.end.y < hi.y:
		out.append(AABB(Vector3(x0, c.end.y, lo.z), Vector3(x1 - x0, hi.y - c.end.y, hi.z - lo.z)))
	var y0 := c.position.y
	var y1 := c.end.y
	if c.position.z > lo.z:
		out.append(AABB(Vector3(x0, y0, lo.z), Vector3(x1 - x0, y1 - y0, c.position.z - lo.z)))
	if c.end.z < hi.z:
		out.append(AABB(Vector3(x0, y0, c.end.z), Vector3(x1 - x0, y1 - y0, hi.z - c.end.z)))
	return out


func _piece_brush(piece: AABB, solid: Array) -> Array:
	var outer_lo: Vector3 = solid[2]
	var outer_hi: Vector3 = solid[3]
	var tower: bool = solid[4]
	var faces := {}
	for axis in 3:
		for side in 2:
			var key := ("+" if side == 1 else "-") + "xyz"[axis]
			var at := piece.end[axis] if side == 1 else piece.position[axis]
			var outer := outer_hi[axis] if side == 1 else outer_lo[axis]
			if tower and absf(at - outer) < 0.01 and key != "-y":
				faces[key] = FACADE
			elif key == "+y":
				faces[key] = FLOOR
			else:
				faces[key] = WALL
	return _box(piece.position, piece.end, WALL, faces)


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


# ---- The scene's things ----------------------------------------------------------------------

func _build_things(root: Node3D) -> void:
	_add(root, _environment())
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.basis = Basis.from_euler(Vector3(deg_to_rad(-9.0), deg_to_rad(-35.0), 0.0))
	_add(root, sun)
	var skyline := Node3D.new()
	skyline.name = "SkylineLayer"
	skyline.set_script(load("res://scripts/world/skyline_layer.gd"))
	_add(root, skyline)
	var navigation := Node.new()
	navigation.name = "WorldNavigation"
	navigation.set_script(load("res://scripts/world/world_navigation.gd"))
	_add(root, navigation)
	var spawner := Node.new()
	spawner.name = "WindowSpawner"
	spawner.set_script(load("res://scripts/zombies/window_spawner.gd"))
	_add(root, spawner)
	var loadout := Node.new()
	loadout.name = "Loadout"
	loadout.set_script(load("res://scripts/world/loadout.gd"))
	var guns: Array[WeaponData] = []
	for path: String in LOADOUT:
		if ResourceLoader.exists(path):
			guns.append(load(path) as WeaponData)
	loadout.set(&"weapons", guns)
	_add(root, loadout)
	var holder := Node3D.new()
	holder.name = "Things"
	_add(root, holder)
	var counts := {}
	for thing: Array in _things:
		var kind: StringName = thing[0]
		var xf: Transform3D = thing[1]
		var settings: Dictionary = thing[2]
		counts[kind] = int(counts.get(kind, 0)) + 1
		var node := _made(kind, settings)
		if node == null:
			continue
		node.name = "%s_%d" % [kind, counts[kind]]
		node.transform = xf
		if kind == &"spawn":
			node.name = "Player"
			_add(root, node)
			continue
		_add(holder, node)
	var hud := (load(HUD) as PackedScene).instantiate()
	hud.name = "HUD"
	_add(root, hud)
	print("things: ", counts)


func _made(kind: StringName, settings: Dictionary) -> Node3D:
	match kind:
		&"spawn":
			return (load(PLAYER) as PackedScene).instantiate() as Node3D
		&"barricade":
			var window := StaticBody3D.new()
			window.set_script(load("res://scripts/zombies/barricade.gd"))
			return window
		&"door":
			var door := StaticBody3D.new()
			door.set_script(load("res://scripts/zombies/zombie_door.gd"))
			door.set(&"size", settings.get("size", Vector3(4.0, 3.0, 0.4)))
			return door
		&"lamp":
			var light := OmniLight3D.new()
			light.light_color = LAMP
			light.light_energy = float(settings.get("energy", 1.0))
			light.omni_range = float(settings.get("range", 12.0))
			light.shadow_enabled = false
			return light
		&"lamp_post":
			var post := Node3D.new()
			post.add_child(_mesh(Vector3(0.25, 6.0, 0.25), Vector3(0.0, 3.0, 0.0), Color(0.2, 0.2, 0.22)))
			post.add_child(_mesh(Vector3(1.2, 0.2, 0.4), Vector3(0.5, 6.0, 0.0), Color(0.2, 0.2, 0.22)))
			var bulb := OmniLight3D.new()
			bulb.light_color = LAMP
			bulb.light_energy = 1.4
			bulb.omni_range = 18.0
			bulb.position = Vector3(0.9, 5.7, 0.0)
			post.add_child(bulb)
			return post
		&"water":
			var water := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = settings.get("size", Vector2(10.0, 10.0))
			water.mesh = plane
			var look := StandardMaterial3D.new()
			look.albedo_color = Color(0.05, 0.08, 0.07, 0.82)
			look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			look.roughness = 0.05
			look.metallic_specular = 1.0
			water.material_override = look
			return water
		&"pane":
			var pane := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = WINDOW
			pane.mesh = quad
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.03, 0.04, 0.06)
			glass.roughness = 0.1
			glass.metallic_specular = 0.9
			pane.material_override = glass
			return pane
		&"apartment_door":
			var door := Node3D.new()
			door.add_child(_mesh(Vector3(1.0, 2.1, 0.08), Vector3.ZERO, Color(0.3, 0.27, 0.24)))
			door.add_child(_mesh(Vector3(0.08, 0.08, 0.1), Vector3(0.38, -0.05, 0.05), Color(0.55, 0.5, 0.35)))
			return door
	return null


func _mesh(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var look := StandardMaterial3D.new()
	look.albedo_color = color
	look.roughness = 0.9
	mesh.material_override = look
	mesh.position = at
	return mesh


func _environment() -> WorldEnvironment:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var look := ProceduralSkyMaterial.new()
	look.sky_top_color = SKY_TOP
	look.sky_horizon_color = SKY_HORIZON
	look.ground_horizon_color = DUSK_FOG
	look.ground_bottom_color = DUSK_FOG.darkened(0.5)
	sky.sky_material = look
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = DUSK_FOG
	environment.fog_depth_begin = 40.0
	environment.fog_depth_end = 700.0
	environment.fog_depth_curve = 1.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	return world


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = parent.owner if parent.owner else parent


# ---- The map ---------------------------------------------------------------------------------

func _write_map(path: String) -> Error:
	var lines := PackedStringArray()
	lines.append("// Game: 2v-2\n// Format: Valve")
	lines.append("// The Stacks demo -- made by tools/make_stacks_demo.gd; edit freely from here (then Build the scene's Map).")
	lines.append("{\n\"classname\" \"worldspawn\"\n\"mapversion\" \"220\"")
	for brush: Array in _world:
		lines.append(_brush_text(brush))
	lines.append("}")
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
	var scale: float = TILE.get(face.tex, 4.0) * UNITS / 64.0
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
