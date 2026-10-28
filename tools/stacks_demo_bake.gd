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
const GROUND := [Vector3(-460.0, -40.0, -980.0), Vector3(540.0, 0.0, 340.0)]
## The open world's Stack (the user's, 2026-10-27: kept as it is, attached,
## not combined): its own baked scene, south of the demo's towers across open
## ground, its torn north wall and rubble facing them. The stair hall's door
## out on the main tower's south face leads to it.
const STACK := "res://scenes/megastructures/the_stack.scn"
const STACK_AT := Vector3(0.0, 0.0, -330.0)
## The Stack's grid windows (StackBuilder's: one a tile, 3 m wide, sills 2.25
## up each 8 m storey, 3.75 tall), and how many of them are real (the user's:
## most) -- of the real, half boarded for the horde, half glass.
const GRID := StackBuilder.TEX_METRES
const GRID_WIDE := StackBuilder.WINDOW_WIDTH
const GRID_SILL := StackBuilder.WINDOW_BOTTOM
const GRID_TALL := StackBuilder.WINDOW_TOP - StackBuilder.WINDOW_BOTTOM
const REAL_SHARE := 1.0 # (the user's, 2026-10-27: windows along all the walls, like the open world Stack)
## The original Stack's hall decorator runs this many times the room's size,
## everything it makes scaled back down (StackBuilder._hall_features).
const HALL_SCALE := 0.4
## The boarded windows (the user's: lower and smaller than the grid's, so the
## horde can climb them): their size and sill.
const CRAWL := Vector2(2.4, 2.6)
const CRAWL_SILL := 0.9
## The crates lying about (the PSX pack's boxes).
const CRATE_MODELS := ["res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Large Props/cardboard_box_1.glb",
		"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Large Props/cardboard_box_2.glb",
		"res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Large Props/metal_barrel_mp_1.glb"]
## THE GREAT HALL (the user's: the open world's bigger rooms) over the ground
## floor, the main tower's width; the hatch up into it from the stair hall.
const GREAT := AABB(Vector3(-56.0, 30.0, -56.0), Vector3(112.0, 60.0, 112.0))
const STAIR_SLOPE := 35.0
## A crawl window's opening (Barricade.SIZE) and its sill.
const WINDOW := Vector2(1.6, 1.6)
const SILL := 0.9
const PLAYER := "res://scenes/player/player.tscn"
const HUD := "res://scenes/ui/hud.tscn"
const LOADOUT := ["res://weapons/starter_gun.tres", "res://weapons/shotgun.tres", "res://weapons/grenade.tres",
		"res://weapons/pkm.tres", "res://weapons/ppsh.tres", "res://weapons/rpg.tres", "res://weapons/revolver.tres",
		"res://weapons/machine_gun.tres", "res://weapons/sniper.tres"]
## Cold dusk (the user's).
## The Flesh Tree (the user's, 2026-10-27: in the middle of the towers, 4 km
## tall, a 50 m trunk; the bridge ends at it, a branch carries on to tower D):
## its foot in the courtyard, and how far round it nothing else is put.
const TREE_AT := Vector3(0.0, 0.0, 108.0)
const TREE_HEIGHT := 4000.0
const TREE_WIDTH := 50.0
const TREE_CLEAR := 36.0
## Where its walkway branch meets tower D (its doorway's floor).
const TREE_WALKWAY_TO := Vector3(0.0, 30.0, 153.0)
## Its tentacle branches' grips up the towers' corners: one in each band of
## heights a corner (the lowest within the tentacle's reach of the courtyard).
const TREE_GRIPS := [Vector2(12.0, 35.0), Vector2(60.0, 400.0), Vector2(400.0, 3000.0)]
const OPEN_ENVIRONMENT := "res://worlds/test_world/environment.tres"
const OPEN_FOG := 1.3333 # (the open world's BiomeAtmosphere.fog_distance)
## The demo's own fog colour (its reworked fog, kept: the user's).
const DEMO_FOG := Color(0.4, 0.43, 0.5)
## The open world's cloud deck height.
const CLOUDS_AT := 500.0
const LAMP := Color(0.72, 0.82, 1.0)

## [lo, hi, outer lo, outer hi, is a tower (its outer faces painted)].
var _solids: Array = []
var _voids: Array[AABB] = []
## Brushes added whole (ramps, steps, pillars): [faces].
var _extra: Array = []
var _world: Array = []
## Nodes for the scene: [kind, transform, settings].
var _things: Array = []
## Doorways nothing may stand in (the hall decorator's columns, ramps).
var _keep_clear: Array[AABB] = []
## Rebar: decor, no collision (func_detail_illusionary) -- nothing snags on it.
var _decor_bars: Array = []
## Where the rooms' decor already stands (each piece's bounds): nothing new
## is put within DECOR_GAP of it (the user's, 2026-10-27: dispersed, not
## merging into each other).
var _decor_bounds: Array[AABB] = []
const DECOR_GAP := 1.0
var _dice := RandomNumberGenerator.new()
var _sun: DirectionalLight3D


func run(_tree: SceneTree) -> void:
	for path in [MAP, SCENE]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_solids.append([GROUND[0], GROUND[1], GROUND[0], GROUND[1], false])
	for t: Array in TOWERS:
		_solids.append([t[0], t[1], t[0], t[1], true])
	for w: Array in GAP_WALLS:
		_solids.append([w[0], w[1], w[0], w[1], true])
	_dice.seed = 2701
	for hole in _stack_holes():
		_room(hole.position, hole.end)
	_depths()
	_tunnel()
	_lobby()
	_corridor()
	_stair_hall()
	_courtyard()
	_great_hall()
	_bridge()
	_stair_chains(AABB(Vector3(-20.0, 0.0, 28.0), Vector3(40.0, 12.0, 30.0)), 2, Vector2(2.5, 4.5), "LobbyStairs")
	_stair_chains(AABB(Vector3(-24.0, 0.0, -56.0), Vector3(44.0, 24.0, 80.0)), 3, Vector2(3.0, 6.0), "HallStairs")
	_dressing()
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
	if ResourceLoader.exists(STACK):
		var stack := (load(STACK) as PackedScene).instantiate() as Node3D
		stack.name = "TheStack"
		stack.position = STACK_AT
		_add(root, stack)
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


## The lobby: the original Stack's hall (columns, a mezzanine and its
## switchback ramps, the hanging pyramid, the leaning slab, stairs to
## nowhere) at human size; grid windows on the courtyard.
func _lobby() -> void:
	var room := AABB(Vector3(-20.0, 0.0, 28.0), Vector3(40.0, 12.0, 30.0))
	_room(room.position, room.end)
	# The doors: the courtyard, the corridor, the stair hall (and where the
	# tunnel comes up): kept clear.
	_room(Vector3(-3.0, 0.0, 58.0), Vector3(3.0, 5.0, 60.0))
	_door(Vector3(0.0, 2.5, 59.0), Vector3(6.0, 5.0, 0.4), 0.0)
	_room(Vector3(-24.0, 0.0, 40.0), Vector3(-20.0, 3.0, 44.0))
	_door(Vector3(-22.0, 1.5, 42.0), Vector3(4.0, 3.0, 0.4), PI * 0.5)
	_room(Vector3(-3.0, 0.0, 24.0), Vector3(3.0, 4.0, 28.0))
	_door(Vector3(0.0, 2.0, 26.0), Vector3(6.0, 4.0, 0.4), 0.0)
	_keep_clear.append(AABB(Vector3(14.0, 0.0, 26.0), Vector3(8.0, 6.0, 12.0))) # the tunnel's landing
	_hall_decor(room, "Lobby")
	_grid_windows(room, Vector3.BACK, 58.0, 60.0)


## Low, long, the same door after door; two flats open.
func _corridor() -> void:
	_room(Vector3(-56.0, 0.0, 40.0), Vector3(-24.0, 6.5, 44.0))
	_room(Vector3(-56.0, 0.0, -20.0), Vector3(-52.0, 6.5, 44.0))
	_room(Vector3(-52.0, 0.0, -20.0), Vector3(-28.0, 6.5, -16.0))
	# Its west leg on the tower's west face: windows out.
	_grid_windows(AABB(Vector3(-56.0, 0.0, -20.0), Vector3(4.0, 6.5, 64.0)), Vector3.LEFT, -56.0, -60.0)
	_room(Vector3(-28.0, 0.0, -20.0), Vector3(-24.0, 3.0, -16.0))
	_door(Vector3(-26.0, 1.5, -18.0), Vector3(4.0, 3.0, 0.4), PI * 0.5)
	# The flats, their windows on the courtyard.
	for flat: Array in [[-50.0, -40.0, -45.0], [-36.0, -26.0, -31.0]]:
		_room(Vector3(flat[0], 0.0, 46.0), Vector3(flat[1], 6.5, 58.0))
		_room(Vector3(flat[2] - 1.0, 0.0, 44.0), Vector3(flat[2] + 1.0, 2.2, 46.0))
		_grid_windows(AABB(Vector3(flat[0], 0.0, 46.0), Vector3(flat[1] - flat[0], 6.5, 12.0)), Vector3.BACK, 58.0, 60.0)
		_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3((flat[0] + flat[1]) * 0.5, 6.0, 52.0)), {energy = 0.5, range = 9.0})
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
	for at: Vector3 in [Vector3(-40.0, 6.0, 42.0), Vector3(-54.0, 6.0, 20.0), Vector3(-54.0, 6.0, -4.0), Vector3(-40.0, 6.0, -18.0)]:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, at), {energy = 0.45, range = 9.0})


## Babbdi's stair hall: giant steps, a bridge, a ramp down, stairs to nowhere.
func _stair_hall() -> void:
	_room(Vector3(-24.0, 0.0, -56.0), Vector3(20.0, 24.0, 24.0))
	# Its far end against the main tower's south face: the original Stack's
	# hall there, grid windows out, and the way out to the Stack (a door).
	_room(Vector3(-3.0, 0.0, -60.0), Vector3(3.0, 5.0, -56.0))
	_door(Vector3(0.0, 2.5, -58.0), Vector3(6.0, 5.0, 0.4), 0.0)
	_keep_clear.append(AABB(Vector3(10.0, 0.0, -22.0), Vector3(10.0, 12.0, 46.0))) # the giant steps
	_keep_clear.append(AABB(Vector3(-11.0, 0.0, -24.0), Vector3(18.0, 11.0, 30.0))) # the block, the ramps
	_hall_decor(AABB(Vector3(-24.0, 0.0, -56.0), Vector3(44.0, 24.0, 32.0)), "StairHall")
	_grid_windows(AABB(Vector3(-24.0, 0.0, -56.0), Vector3(44.0, 24.0, 80.0)), Vector3.FORWARD, -56.0, -60.0)
	# Giant steps up the east wall (1.2 m each: mantle them).
	for i in 8:
		_block(Vector3(11.0, 0.0, -20.0 + i * 3.0), Vector3(20.0, 1.2 * (i + 1), -17.0 + i * 3.0))
	_block(Vector3(11.0, 0.0, 4.0), Vector3(20.0, 9.6, 24.0)) # the ledge they reach
	_block(Vector3(-6.0, 0.0, -6.0), Vector3(6.0, 9.6, 6.0)) # the central block
	_block(Vector3(6.0, 9.0, -2.0), Vector3(11.0, 9.6, 2.0)) # the bridge
	_ramp_z(-10.0, -6.0, -22.0, 0.0, 6.0, 9.6) # down the far side
	for at: Vector3 in [Vector3(-12.0, 20.0, -12.0), Vector3(12.0, 20.0, 12.0)]:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, at), {energy = 1.0, range = 26.0})


## The concrete courtyard between the towers, open to the dusk.
func _courtyard() -> void:
	for side: float in [-1.0, 1.0]:
		var x0 := -72.0 if side < 0.0 else 66.0
		_block(Vector3(x0, 0.0, 74.0), Vector3(x0 + 6.0, 1.2, 148.0)) # the raised walk
		_ramp_z(x0, x0 + 6.0, 64.0, 0.0, 74.0, 1.2)
	# Planters out round the Flesh Tree (its trunk stands where the plinth was).
	for at: Vector2 in [Vector2(-50.0, 90.0), Vector2(50.0, 90.0), Vector2(-50.0, 125.0), Vector2(50.0, 125.0)]:
		_block(Vector3(at.x - 3.0, 0.0, at.y - 3.0), Vector3(at.x + 3.0, 1.0, at.y + 3.0)) # planters
	# Windows on the other towers: boarded into closets in them.
	_crawl_window(Vector3(-73.0, 0.0, 100.0), Vector3.LEFT, Vector3(-82.0, 0.0, 96.0), Vector3(-74.0, 4.0, 104.0))
	_crawl_window(Vector3(73.0, 0.0, 120.0), Vector3.RIGHT, Vector3(74.0, 0.0, 116.0), Vector3(82.0, 4.0, 124.0))
	_crawl_window(Vector3(31.0, 0.0, 153.0), Vector3.BACK, Vector3(27.0, 0.0, 154.0), Vector3(35.0, 4.0, 162.0))
	for at: Vector3 in [Vector3(-40.0, 0.0, 80.0), Vector3(40.0, 0.0, 80.0), Vector3(-40.0, 0.0, 135.0), Vector3(40.0, 0.0, 135.0)]:
		_thing(&"lamp_post", Transform3D(Basis.IDENTITY, at), {})


## The great hall: the original Stack's hall at a bigger scale, chains of
## floating rubble bristling with rebar, abstract stair chains up to
## platforms, glass all round; up through the hatch from the stair hall, out
## by its north door onto the bridge.
func _great_hall() -> void:
	_room(GREAT.position, GREAT.end)
	# The hatch: a long abstract stair up the stair hall's west side, up
	# through the floor; the hatch over the hole slides aside (F).
	_ramp_z(-19.0, -15.0, -52.0, 0.0, -9.0, 30.0)
	_room(Vector3(-19.0, 23.5, -24.0), Vector3(-15.0, 30.5, -9.0))
	_thing(&"door", Transform3D(Basis.IDENTITY, Vector3(-17.0, 29.8, -16.5)), {size = Vector3(4.0, 0.4, 15.0), open_move = Vector3(-4.6, 0.0, 0.0)})
	_keep_clear.append(AABB(Vector3(-22.0, 0.0, -56.0), Vector3(10.0, 31.0, 50.0)))
	_keep_clear.append(AABB(Vector3(-22.0, 30.0, -26.0), Vector3(10.0, 6.0, 22.0)))
	# The way out north, onto the bridge.
	_room(Vector3(-3.0, 30.0, 56.0), Vector3(3.0, 36.0, 60.0))
	_door(Vector3(0.0, 33.0, 58.0), Vector3(6.0, 6.0, 0.4), 0.0)
	_hall_decor(GREAT, "GreatHall", 0.8)
	_stair_chains(GREAT, 4, Vector2(5.0, 11.0), "GreatStairs")
	for k in 3:
		_floating_chain(GREAT, 7)
	for side: Array in [[Vector3.BACK, 56.0, 60.0], [Vector3.FORWARD, -56.0, -60.0], [Vector3.LEFT, -56.0, -60.0], [Vector3.RIGHT, 56.0, 60.0]]:
		_grid_windows(GREAT, side[0], side[1], side[2])
	_thing(&"climber", Transform3D(Basis.IDENTITY, Vector3(38.0, 30.0, -38.0)), {})
	_camp(Vector3(42.0, 30.0, -42.0))


## The bridge (the procedural Stack's plates, the user's): 30 m over the
## courtyard from the great hall to the tower opposite, its edges bristling
## with rebar, washing strung along it, lamps, and rubble floating round it.
func _bridge() -> void:
	# Into the Flesh Tree's trunk (its walkway branch carries on to tower D).
	_block(Vector3(-5.0, 29.0, 60.0), Vector3(5.0, 30.0, TREE_AT.z - TREE_WIDTH * 0.36))
	_room(Vector3(-3.0, 30.0, 152.0), Vector3(3.0, 36.0, 154.0))
	_room(Vector3(-8.0, 30.0, 154.0), Vector3(8.0, 38.0, 166.0)) # a landing inside, for now
	_thing(&"lamp", Transform3D(Basis.IDENTITY, Vector3(0.0, 36.0, 160.0)), {energy = 0.8, range = 14.0})
	var bridge_end := int(TREE_AT.z - TREE_WIDTH * 0.5)
	for z in range(66, bridge_end, 12):
		for side: float in [-1.0, 1.0]:
			_thing(&"pole", Transform3D(Basis.IDENTITY, Vector3(side * 4.6, 30.0, float(z))), {})
			if z + 12 < bridge_end:
				_thing(&"clothes", Transform3D(Basis.IDENTITY, Vector3(side * 4.6, 32.8, float(z))), {to = Vector3(side * 4.6, 32.8, float(z + 12))})
		if z % 36 == 6:
			_thing(&"lamp_post", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(4.2, 30.0, float(z))), {})
	for k in 10:
		var along := _dice.randf_range(64.0, float(bridge_end) - 2.0)
		var side := -1.0 if _dice.randf() < 0.5 else 1.0
		_rebar(Vector3(side * 5.0, 29.5, along), Vector3(side, -0.4, 0.0))
	# Rubble floating in the courtyard's air, round the bridge.
	for k in 16:
		var at := Vector3(_dice.randf_range(-62.0, 62.0), _dice.randf_range(12.0, 62.0), _dice.randf_range(66.0, 146.0))
		if absf(at.x) < 9.0 and at.y > 24.0 and at.y < 40.0:
			at.x += 14.0 * signf(at.x if at.x != 0.0 else 1.0)
		if not _off_tree(at, 6.0):
			continue
		_chunk(at, _dice.randf_range(2.0, 7.0))


## Chains of abstract stairs (the procedural Stack's: 35-degree flights, each
## up to a small platform, the next flight off that), spread round `room`:
## `count` chains, each flight rising `rise` (metres).
func _stair_chains(room: AABB, count: int, rise: Vector2, name: String) -> void:
	var made := 0
	for attempt in count * 12:
		if made >= count:
			break
		var at := Vector3(_dice.randf_range(room.position.x + 6.0, room.end.x - 6.0), room.position.y,
				_dice.randf_range(room.position.z + 6.0, room.end.z - 6.0))
		var flights: Array = []
		var ok := true
		for step in _dice.randi_range(2, 4):
			var up := _dice.randf_range(rise.x, rise.y)
			if at.y + up > room.end.y - 3.5:
				break
			var run := up / tan(deg_to_rad(STAIR_SLOPE))
			var heading := Vector3.FORWARD.rotated(Vector3.UP, _dice.randf() * TAU)
			var top := at + heading * run + Vector3.UP * up
			var landing := top + heading * 3.0
			if not room.grow(-4.0).has_point(Vector3(landing.x, room.get_center().y, landing.z)):
				break
			var lean := Basis.looking_at((top - at).normalized(), Vector3.UP)
			var flight := {c = (at + top) * 0.5, s = Vector3(4.0, 0.6, at.distance_to(top)), b = lean}
			var platform := {c = landing - Vector3.UP * 0.5, s = Vector3(6.0, 1.0, 6.0), b = Basis(Vector3.UP, _dice.randf() * TAU)}
			if _blocks_a_door(flight) or _blocks_a_door(platform) or _hits_decor(flight) or _hits_decor(platform):
				ok = false
				break
			flights.append(flight)
			flights.append(platform)
			at = landing
		if not ok or flights.size() < 2:
			continue
		for piece: Dictionary in flights:
			_extra.append(_oriented(piece.c, piece.s, piece.b))
			_decor_bounds.append(_bounds_of(piece))
		made += 1
	print(name, ": ", made, " stair chains")


## A chain of floating rubble (the procedural Stack's: tumbled chunks hung
## high in the hall, each a jump or a grapple from the last), rebar
## bristling off them.
func _floating_chain(room: AABB, count: int) -> void:
	var at := Vector3(_dice.randf_range(room.position.x + 10.0, room.end.x - 10.0), room.end.y - 8.0,
			_dice.randf_range(room.position.z + 10.0, room.end.z - 10.0))
	for i in count:
		_chunk(at, _dice.randf_range(3.0, 7.0))
		var way := Vector2.from_angle(_dice.randf() * TAU) * _dice.randf_range(6.0, 11.0)
		at = Vector3(clampf(at.x + way.x, room.position.x + 8.0, room.end.x - 8.0), at.y - _dice.randf_range(3.0, 6.0),
				clampf(at.z + way.y, room.position.z + 8.0, room.end.z - 8.0))
		if at.y < room.position.y + 10.0:
			break


## One floating chunk of rubble, tumbled, rebar sticking out of it.
func _chunk(at: Vector3, size: float) -> void:
	var tumble := Basis.from_euler(Vector3(_dice.randf_range(-0.6, 0.6), _dice.randf() * TAU, _dice.randf_range(-0.6, 0.6)))
	var piece := {c = at, s = Vector3(size, size * _dice.randf_range(0.3, 0.6), size * _dice.randf_range(0.6, 1.0)), b = tumble}
	if _hits_decor(piece):
		return # (it'd sink into the decor: left out)
	_decor_bounds.append(_bounds_of(piece))
	_extra.append(_oriented(piece.c, piece.s, piece.b))
	if _dice.randf() < 0.6:
		_rebar(at, tumble * Vector3(1.0, 0.0, 0.0))


## Rebar: 3-6 bent bars sticking out of `at` along `out`.
func _rebar(at: Vector3, out: Vector3) -> void:
	for i in _dice.randi_range(3, 6):
		var way := (out.normalized() + Vector3(_dice.randf_range(-0.4, 0.4), _dice.randf_range(-0.4, 0.4), _dice.randf_range(-0.4, 0.4))).normalized()
		var length := _dice.randf_range(1.5, 3.5)
		var bar := {c = at + way * length * 0.5, s = Vector3(0.25, 0.25, length), b = Basis.looking_at(way, Vector3.UP if absf(way.y) < 0.95 else Vector3.RIGHT)}
		_decor_bars.append(_oriented(bar.c, bar.s, bar.b))


## A dead climber's cold camp (the open world's): tent, bedroll and dead fire,
## and their supplies -- ammo, pills, a bandage, a grenade -- and a crate.
func _camp(at: Vector3) -> void:
	_thing(&"camp", Transform3D(Basis(Vector3.UP, _dice.randf() * TAU), at), {})
	var spots := [["res://scenes/ammo_pickup.tscn", Vector3(2.5, 0.3, -1.0)], ["res://scenes/ammo_pickup.tscn", Vector3(3.0, 0.3, 0.2)],
			["res://scenes/pills_pickup.tscn", Vector3(-2.0, 0.3, 2.2)], ["res://scenes/bandage_pickup.tscn", Vector3(-2.6, 0.3, 1.4)],
			["res://scenes/grenade_pickup.tscn", Vector3(1.2, 0.3, 2.6)]]
	for spot: Array in spots:
		_thing(&"pickup", Transform3D(Basis.IDENTITY, at + (spot[1] as Vector3)), {scene = spot[0]})
	_thing(&"crate", Transform3D(Basis(Vector3.UP, _dice.randf() * TAU), at + Vector3(-3.5, 0.0, -2.0)), {})


## The open world's details, scattered (the user's): fire barrels, explosive
## barrels in groups, crates, dead climbers' camps, cables across the
## courtyard, washing strung from its walls.
func _dressing() -> void:
	var floors := [[AABB(Vector3(-60.0, 0.0, 66.0), Vector3(120.0, 0.0, 80.0)), 3, 2, 6], # the courtyard
			[AABB(Vector3(-16.0, 0.0, 32.0), Vector3(30.0, 0.0, 22.0)), 1, 1, 2], # the lobby
			[AABB(Vector3(-12.0, 0.0, -52.0), Vector3(28.0, 0.0, 26.0)), 1, 1, 4], # the stair hall's far end
			[AABB(Vector3(-50.0, 30.0, -50.0), Vector3(100.0, 0.0, 100.0)), 2, 2, 8]] # the great hall
	for spread: Array in floors:
		var area: AABB = spread[0]
		for i in int(spread[1]):
			_thing(&"fire", Transform3D(Basis.IDENTITY, _on(area)), {})
		for g in int(spread[2]):
			var middle := _on(area)
			for i in _dice.randi_range(3, 5):
				_thing(&"explosive", Transform3D(Basis(Vector3.UP, _dice.randf() * TAU), middle + Vector3(_dice.randf_range(-1.6, 1.6), 0.0, _dice.randf_range(-1.6, 1.6))), {})
		for i in int(spread[3]):
			_thing(&"crate", Transform3D(Basis(Vector3.UP, _dice.randf() * TAU), _on(area)), {})
	_thing(&"climber", Transform3D(Basis.IDENTITY, Vector3(-46.0, 0.0, 140.0)), {})
	_camp(Vector3(-52.0, 1.2, 128.0))
	# Cables across the courtyard, tower to tower, high up.
	# (Any that would run through the Flesh Tree's trunk are tied onto it.)
	for k in 7:
		var y := _dice.randf_range(18.0, 80.0)
		var from: Vector3
		var to: Vector3
		if _dice.randf() < 0.5:
			var z := _dice.randf_range(70.0, 145.0)
			from = Vector3(-72.0, y, z)
			to = Vector3(72.0, y - _dice.randf_range(0.0, 6.0), z + _dice.randf_range(-10.0, 10.0))
		else:
			var x := _dice.randf_range(-60.0, 60.0)
			from = Vector3(x, y, 60.0)
			to = Vector3(x + _dice.randf_range(-15.0, 15.0), y - _dice.randf_range(0.0, 6.0), 152.0)
		var near := Geometry2D.get_closest_point_to_segment(Vector2(TREE_AT.x, TREE_AT.z), Vector2(from.x, from.z), Vector2(to.x, to.z))
		var miss := near.distance_to(Vector2(TREE_AT.x, TREE_AT.z))
		var trunk := TREE_WIDTH * 0.5
		if miss < trunk:
			var flat_from := Vector2(from.x, from.z)
			var length := flat_from.distance_to(Vector2(to.x, to.z))
			var meets := flat_from.distance_to(near) - sqrt(trunk * trunk - miss * miss)
			to = from.lerp(to, clampf(meets / maxf(length, 0.01), 0.05, 1.0))
		_thing(&"wire", Transform3D(Basis.IDENTITY, from), {to = to})
	# Washing from the courtyard's walls to poles.
	for k in 4:
		var side := -1.0 if k < 2 else 1.0
		var z := _dice.randf_range(80.0, 140.0)
		var pole := Vector3(side * 50.0, 0.0, z)
		_thing(&"pole", Transform3D(Basis.IDENTITY, pole), {tall = 9.0})
		_thing(&"clothes", Transform3D(Basis.IDENTITY, Vector3(side * 72.0, 8.0, z)), {to = pole + Vector3.UP * 8.0})


## A spot on `area`'s floor, at random.
## (Never in the Flesh Tree's trunk.)
func _on(area: AABB) -> Vector3:
	var at := Vector3.ZERO
	for attempt in 20:
		at = Vector3(_dice.randf_range(area.position.x, area.end.x), area.position.y, _dice.randf_range(area.position.z, area.end.z))
		if _off_tree(at):
			break
	return at


## Clear of the Flesh Tree's trunk (by `margin` more).
func _off_tree(at: Vector3, margin: float = 0.0) -> bool:
	return Vector2(at.x - TREE_AT.x, at.z - TREE_AT.z).length() > TREE_CLEAR + margin


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
	_keep_clear.append(AABB(Vector3(at.x - 4.0, at.y - size.y * 0.5, at.z - 4.0), Vector3(8.0, size.y + 1.0, 8.0)))


## Where the open world's Stack has its ground holed (its shaft, its outfall):
## carved out of this ground too, down through it.
func _stack_holes() -> Array[AABB]:
	var holes: Array[AABB] = []
	if not ResourceLoader.exists(STACK):
		return holes
	var stack := (load(STACK) as PackedScene).instantiate()
	for hole: AABB in stack.get(&"terrain_holes"):
		var moved := AABB(hole.position + STACK_AT, hole.size)
		moved.position.y = GROUND[0].y - 1.0
		moved.size.y = -GROUND[0].y + 2.0
		holes.append(moved)
	stack.free()
	return holes


## The Stack's grid windows (the user's: as many as the original) in
## `room`'s wall on side `out`, the wall running from `inner` to `outer`
## along that axis: one a tile wherever a whole one fits the room, every
## storey it reaches -- REAL_SHARE of them real (half boarded, the lowest row
## only; half glass), the rest left painted (the facade's own).
func _grid_windows(room: AABB, out: Vector3, inner: float, outer: float, rows: int = 99) -> void:
	var along_x := absf(out.z) > 0.5
	var lo := room.position.x if along_x else room.position.z
	var hi := room.end.x if along_x else room.end.z
	var depth := absf(outer - inner)
	var middle_out := (inner + outer) * 0.5
	var k := floorf(lo / GRID)
	while k * GRID < hi:
		var centre := k * GRID + GRID * 0.5
		k += 1.0
		if centre - GRID_WIDE * 0.5 < lo + 0.5 or centre + GRID_WIDE * 0.5 > hi - 0.5:
			continue
		var storey := 0
		while true:
			var sill := floorf(room.position.y / GRID) * GRID + GRID_SILL + storey * GRID
			storey += 1
			if sill < room.position.y + 0.5:
				continue
			if sill + GRID_TALL > room.end.y - 0.2 or storey > rows:
				break
			var middle := Vector3(centre, sill + GRID_TALL * 0.5, middle_out) if along_x else Vector3(middle_out, sill + GRID_TALL * 0.5, centre)
			var half := Vector3(GRID_WIDE * 0.5, GRID_TALL * 0.5, depth * 0.5 + 0.05) if along_x else Vector3(depth * 0.5 + 0.05, GRID_TALL * 0.5, GRID_WIDE * 0.5)
			var opening := AABB(middle - half, half * 2.0)
			if _keep_clear.any(func(clear: AABB) -> bool: return clear.intersects(opening.grow(0.5))):
				continue
			if _dice.randf() > REAL_SHARE:
				continue # painted (the facade's own)
			var low := sill - room.position.y < GRID and room.position.y < 1.0
			if low and _dice.randf() < 0.5:
				# Boarded (the user's: lower and smaller, so the horde can use it):
				# in the grid window's column, down near the floor.
				var crawl_mid := middle
				crawl_mid.y = room.position.y + CRAWL_SILL + CRAWL.y * 0.5
				var crawl_half := Vector3(CRAWL.x * 0.5, CRAWL.y * 0.5, depth * 0.5 + 0.05) if along_x else Vector3(depth * 0.5 + 0.05, CRAWL.y * 0.5, CRAWL.x * 0.5)
				_room(crawl_mid - crawl_half, crawl_mid + crawl_half)
				_thing(&"barricade", Transform3D(Basis.looking_at(out, Vector3.UP), crawl_mid),
						{size = CRAWL, drop = CRAWL_SILL + CRAWL.y * 0.5, depth = depth})
			else:
				_room(opening.position, opening.end)
				_thing(&"glass", Transform3D(Basis.looking_at(out, Vector3.UP), middle), {size = Vector2(GRID_WIDE, GRID_TALL)})


## The original Stack's hall (StackBuilder._hall_features: its columns, a
## mezzanine and its switchback ramps, the hanging stepped pyramid, the
## leaning slab, stairs to nowhere, its lamps), made 1/HALL_SCALE the room's
## size and everything scaled back down into it. Each feature (its `unit`: a
## column, the pyramid, a deck and its ramps...) is kept only if it stands
## clear of the ones kept before it (DECOR_GAP) and out of every doorway
## (_keep_clear); rerolled for the layout that loses the fewest.
func _hall_decor(room: AABB, name: String, scale: float = HALL_SCALE) -> void:
	var builder := StackBuilder.new(false)
	var best: Array = []
	var best_bounds: Array[AABB] = []
	var best_lamps: Array = []
	var fewest := 1 << 30
	for attempt in 24:
		builder.boxes.clear()
		builder.lamps.clear()
		builder.growth_floors.clear()
		builder.nest_spots = PackedVector3Array()
		builder.gang_spots = PackedVector4Array()
		builder.random.seed = hash([name, attempt])
		var big := AABB(room.position / scale, room.size / scale)
		builder._hall_features({tower = -1, box = big, name = name})
		# Its features, each its pieces.
		var units := {}
		var order: Array = []
		for b: Dictionary in builder.boxes:
			var unit: int = b.get("unit", 0)
			if not units.has(unit):
				units[unit] = []
				order.append(unit)
			(units[unit] as Array).append({c = (b.c as Vector3) * scale, s = (b.s as Vector3) * scale, b = b.b})
		var kept: Array = []
		var bounds: Array[AABB] = _decor_bounds.duplicate()
		var lost := 0
		for unit: int in order:
			var pieces: Array = units[unit]
			var clear := true
			var mine: Array[AABB] = []
			for piece: Dictionary in pieces:
				var box := _bounds_of(piece)
				if _blocks_a_door(piece) or bounds.any(func(other: AABB) -> bool: return other.intersects(box.grow(DECOR_GAP))):
					clear = false
					break
				mine.append(box)
			if not clear:
				lost += 1
				continue
			kept.append_array(pieces)
			bounds.append_array(mine)
		if lost < fewest:
			fewest = lost
			best = kept
			best_bounds = bounds
			best_lamps = builder.lamps.duplicate()
		if lost == 0:
			break
	_decor_bounds = best_bounds
	for piece: Dictionary in best:
		_extra.append(_oriented(piece.c, piece.s, piece.b))
	for lamp: Array in best_lamps:
		_thing(&"lamp", Transform3D(Basis.IDENTITY, (lamp[0] as Vector3) * scale),
				{energy = float(lamp[2]) * scale, range = float(lamp[3]) * scale, color = lamp[1]})
	print(name, ": the Stack's hall, ", best.size(), " pieces (", fewest, " features left out: in a doorway or too close)")


## A turned box's bounds (its eight corners).
func _bounds_of(piece: Dictionary) -> AABB:
	var basis: Basis = piece.b
	var half: Vector3 = (piece.s as Vector3) * 0.5
	var c: Vector3 = piece.c
	var box := AABB(c, Vector3.ZERO)
	for corner in 8:
		var sign := Vector3(1.0 if corner & 1 else -1.0, 1.0 if corner & 2 else -1.0, 1.0 if corner & 4 else -1.0)
		box = box.expand(c + basis * (half * sign))
	return box


## Whether `piece` would stand within DECOR_GAP of the decor already there.
func _hits_decor(piece: Dictionary) -> bool:
	var box := _bounds_of(piece).grow(DECOR_GAP)
	return _decor_bounds.any(func(other: AABB) -> bool: return other.intersects(box))

func _blocks_a_door(piece: Dictionary) -> bool:
	var reach := (piece.s as Vector3).length() * 0.5
	var bounds := AABB((piece.c as Vector3) - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	# Only near enough to matter: its real extent, roughly (a turned box's
	# corners within reach).
	for clear in _keep_clear:
		if not clear.intersects(bounds):
			continue
		var basis: Basis = piece.b
		var half: Vector3 = (piece.s as Vector3) * 0.5
		for corner in 8:
			var sign := Vector3(1.0 if corner & 1 else -1.0, 1.0 if corner & 2 else -1.0, 1.0 if corner & 4 else -1.0)
			if clear.has_point((piece.c as Vector3) + basis * (half * sign)):
				return true
		if clear.has_point(piece.c):
			return true
	return false


## A box turned by `basis` (the hall decorator's leaning columns, ramps):
## a brush of its six planes; its most upward face the floor.
func _oriented(c: Vector3, s: Vector3, basis: Basis) -> Array:
	var faces: Array = []
	var up_most := -2.0
	for axis in 3:
		for sign: float in [-1.0, 1.0]:
			up_most = maxf(up_most, (basis[axis] * sign).normalized().y)
	for axis in 3:
		for sign: float in [-1.0, 1.0]:
			var n := (basis[axis] * sign).normalized()
			var point := c + n * s[axis] * 0.5
			faces.append(_f(point, n, FLOOR if is_equal_approx(n.y, up_most) and n.y > 0.5 else WALL))
	return faces


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
			# (func_godot can't build a brush much under 0.1 m: such slivers fall
			# between window openings; left out.)
			if piece.size.x < 0.15 or piece.size.y < 0.15 or piece.size.z < 0.15:
				continue # (a sliver: nothing to build)
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
	# The open world's sun (its angle and shadows), tinted by its air.
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.transform = Transform3D(Vector3(0.8660254, 0.0, -0.5), Vector3(-0.38302222, 0.64278764, -0.66341394), Vector3(0.32139382, 0.76604444, 0.5566704), Vector3.ZERO)
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 90.0
	_add(root, _environment())
	_add(root, _sun)
	var clouds := MeshInstance3D.new()
	clouds.name = "CloudDeck"
	clouds.set_script(load("res://scripts/world/cloud_deck.gd"))
	clouds.set(&"height", CLOUDS_AT)
	_add(root, clouds)
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
	_add(root, _flesh_tree())
	_add(root, _red_creep())
	var horde := Node.new()
	horde.name = "DemoHorde"
	horde.set_script(load("res://scripts/zombies/demo_horde.gd"))
	_add(root, horde)
	var traders := Node.new()
	traders.name = "DemoTraders"
	traders.set_script(load("res://scripts/zombies/demo_traders.gd"))
	_add(root, traders)
	var sound := Node.new()
	sound.name = "DemoSound"
	sound.set_script(load("res://scripts/zombies/demo_sound.gd"))
	# Its inside: every room (not the holes down through the ground); its
	# windows: every real one (boarded or glass).
	var rooms: Array[AABB] = []
	for void_box in _voids:
		if void_box.position.y > -20.0 and void_box.size.y >= 2.0:
			rooms.append(void_box)
	var openings := PackedVector3Array()
	for thing: Array in _things:
		if thing[0] == &"barricade" or thing[0] == &"glass":
			openings.append((thing[1] as Transform3D).origin)
	sound.set(&"rooms", rooms)
	sound.set(&"openings", openings)
	_add(root, sound)
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
	var climbers := PackedVector3Array()
	var counts := {}
	for thing: Array in _things:
		var kind: StringName = thing[0]
		var xf: Transform3D = thing[1]
		var settings: Dictionary = thing[2]
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind == &"climber":
			climbers.append(xf.origin)
			continue
		var node := _made(kind, settings)
		if node == null:
			continue
		node.name = "%s_%d" % [kind, counts[kind]]
		node.transform = xf
		if node.has_meta(&"to"):
			_string_up(node)
		if kind == &"spawn":
			node.name = "Player"
			_add(root, node)
			continue
		_add(holder, node)
	var dressing := Node.new()
	dressing.name = "DemoDressing"
	dressing.set_script(load("res://scripts/zombies/demo_dressing.gd"))
	dressing.set(&"climbers", climbers)
	_add(root, dressing)
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
			for key: String in ["size", "drop", "depth"]:
				if settings.has(key):
					window.set(StringName(key), settings[key])
			return window
		&"glass":
			# A real window you see out of (the user's: no painted pane showing
			# the empty sky): dirty glass, not see-through to bullets' path
			# blockers -- it stops you and the horde.
			var pane := StaticBody3D.new()
			var size: Vector2 = settings.get("size", WINDOW)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(size.x, size.y, 0.3)
			shape.shape = box
			pane.add_child(shape)
			var sheet := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = size
			sheet.mesh = quad
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.55, 0.6, 0.66, 0.16)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			sheet.material_override = glass
			sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pane.add_child(sheet)
			return pane
		&"door":
			var door := StaticBody3D.new()
			door.set_script(load("res://scripts/zombies/zombie_door.gd"))
			door.set(&"size", settings.get("size", Vector3(4.0, 3.0, 0.4)))
			door.set(&"open_move", settings.get("open_move", Vector3.ZERO))
			return door
		&"fire":
			var fire := StaticBody3D.new()
			fire.set_script(load("res://scripts/world/burning_barrel.gd"))
			return fire
		&"explosive":
			return (load("res://scenes/props/explosive_barrel.tscn") as PackedScene).instantiate() as Node3D
		&"pickup":
			return (load(str(settings.scene)) as PackedScene).instantiate() as Node3D
		&"camp":
			var camp := Node3D.new()
			camp.set_script(load("res://scripts/world/camp.gd"))
			camp.set(&"tent", _dice.randi() % 2)
			camp.set(&"abandoned", true)
			return camp
		&"crate":
			var crate := RigidBody3D.new()
			crate.mass = 12.0
			var model := QuestProps._prop(CRATE_MODELS[_dice.randi() % CRATE_MODELS.size()], 1.4)
			if model:
				model.position.y = 0.7
				crate.add_child(model)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.1, 1.1, 1.1)
			shape.shape = box
			shape.position.y = 0.6
			crate.add_child(shape)
			return crate
		&"pole":
			var pole := Node3D.new()
			var tall: float = settings.get("tall", 3.2)
			pole.add_child(_mesh(Vector3(0.12, tall, 0.12), Vector3(0.0, tall * 0.5, 0.0), Color(0.22, 0.2, 0.19)))
			return pole
		&"wire", &"clothes":
			return _strung(settings.get("to", Vector3.ZERO), kind == &"clothes")
		&"lamp":
			var light := OmniLight3D.new()
			light.light_color = settings.get("color", LAMP)
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


## A cable (or a washing line, its shirts and trousers hanging off it --
## the procedural Stack's) from the node's own spot to 	o (world).
func _strung(to: Vector3, washing: bool) -> Node3D:
	var root := Node3D.new()
	root.set_meta(&"to", to)
	root.set_meta(&"washing", washing)
	return root


## Strung lines get built once they know where they start (_build_things).
func _string_up(root: Node3D) -> void:
	var to: Vector3 = root.get_meta(&"to")
	var washing: bool = root.get_meta(&"washing")
	var from := root.position
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var line := _mesh(Vector3(0.05, 0.05, length), Vector3.ZERO, Color(0.12, 0.12, 0.12))
	line.transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), (to - from) * 0.5)
	root.add_child(line)
	if not washing:
		return
	var colours := [Color(0.45, 0.38, 0.32), Color(0.32, 0.36, 0.42), Color(0.5, 0.47, 0.42), Color(0.38, 0.22, 0.2), Color(0.25, 0.3, 0.26)]
	var dir := (to - from) / length
	var spot := _dice.randf_range(0.8, 2.0)
	while spot < length - 0.8:
		var shirt := _dice.randf() < 0.6
		var piece := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.7, 0.75) if shirt else Vector2(0.45, 1.0)
		piece.mesh = quad
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = colours[_dice.randi() % colours.size()]
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.roughness = 1.0
		piece.material_override = cloth
		piece.position = dir * spot - Vector3.UP * (quad.size.y * 0.5 + 0.05)
		piece.rotation.y = atan2(dir.x, dir.z) + PI * 0.5
		root.add_child(piece)
		spot += _dice.randf_range(0.9, 2.2)


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


## The Flesh Tree in the courtyard (FleshTree's towers layout): 4 km tall, a
## 50 m trunk, its tentacles gripping the four towers' corners, orbs on every
## one; its walkway round from the bridge's end to tower D. It doesn't grow
## here; only its crown has the open world's spiral of limbs.
func _flesh_tree() -> Node3D:
	var tree := Node3D.new()
	tree.name = "FleshTree"
	tree.set_script(load("res://scripts/world/flesh_tree.gd"))
	tree.position = TREE_AT + Vector3.DOWN * 1.0 # (sunk in a little)
	var towers: Array[AABB] = []
	for t: Array in TOWERS:
		towers.append(AABB(t[0], t[1] - t[0]))
	var grips := PackedVector2Array()
	for band: Vector2 in TREE_GRIPS:
		grips.append(band)
	var settings := {
		start_height = TREE_HEIGHT, grow_step = 0.0, trunk_width = TREE_WIDTH,
		flare_share = 0.3, flare_reach = 15.0, limbs_from = 3700.0,
		roots = 6, root_reach = 40.0, root_arch = 4.0,
		grip_towers = towers, grip_heights = grips,
		walkway_from = Vector3(0.0, 30.0, TREE_AT.z - TREE_WIDTH * 0.36), walkway_to = TREE_WALKWAY_TO,
		orbs_everywhere = true, orb_read_range = 45.0, sit_on_ground = false,
	}
	for key: String in settings:
		tree.set(StringName(key), settings[key])
	return tree


## The red creep (RedCreep; docs/RED_CREEP.md): one bush in each area (the
## user's), never in the Flesh Tree's trunk.
func _red_creep() -> Node3D:
	var creep := Node3D.new()
	creep.name = "RedCreep"
	creep.set_script(load("res://scripts/zombies/red_creep.gd"))
	var areas: Array[AABB] = []
	for box: Array in [
			[Vector3(24.0, -12.0, 30.0), Vector3(48.0, -5.0, 50.0)], # the depths
			[Vector3(44.0, -12.0, -2.0), Vector3(48.0, -2.0, 28.0)], # the tunnel
			[Vector3(-20.0, 0.0, 28.0), Vector3(20.0, 12.0, 58.0)], # the lobby
			[Vector3(-56.0, 0.0, -20.0), Vector3(-52.0, 6.5, 44.0)], # the corridor
			[Vector3(-50.0, 0.0, 46.0), Vector3(-40.0, 6.5, 58.0)], # a flat
			[Vector3(-24.0, 0.0, -56.0), Vector3(20.0, 24.0, 24.0)], # the stair hall
			[GREAT.position, GREAT.end], # the great hall
			[Vector3(-60.0, 0.0, 66.0), Vector3(60.0, 20.0, 146.0)]]: # the courtyard
		areas.append(AABB(box[0], box[1] - box[0]))
	var trunk := AABB(TREE_AT - Vector3(TREE_CLEAR, 5.0, TREE_CLEAR), Vector3(TREE_CLEAR * 2.0, 80.0, TREE_CLEAR * 2.0))
	var keep_out: Array[AABB] = [trunk]
	creep.set(&"areas", areas)
	creep.set(&"keep_out", keep_out)
	return creep


## The open world's sky, fog and light (the user's, 2026-10-27: the same sky,
## clouds and fog, the giants looming in it): its environment, in the sewer's
## air (BiomeAtmosphere's: the open world's own values, fog pushed out as
## there, OPEN_FOG), applied once here -- the demo is all one air.
func _environment() -> WorldEnvironment:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var environment := (load(OPEN_ENVIRONMENT) as Environment).duplicate() as Environment
	var sewer := AlienAtmosphere.new()
	sewer.fog_color = Color(0.27, 0.29, 0.16)
	sewer.fog_start = 22.0
	sewer.fog_end = 192.5
	sewer.haze_height = 14.0
	sewer.haze_density = 0.081
	sewer.ambient_color = Color(0.32, 0.31, 0.2)
	sewer.ambient_energy = 0.4
	sewer.sun_color = Color(1.0, 0.93, 0.72)
	sewer.sun_energy = 1.25
	AlienAtmosphere.apply_blend(environment, sewer, sewer, 0.0, _sun, OPEN_FOG)
	# But the fog the demo's own (the user's, 2026-10-27: the open world's was
	# far too thick): its distance, curve and colour from before, no valley haze.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = DEMO_FOG
	environment.background_color = DEMO_FOG
	environment.fog_depth_begin = 40.0
	environment.fog_depth_end = 700.0
	environment.fog_depth_curve = 1.4
	environment.fog_height_density = 0.0
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
	if not _decor_bars.is_empty():
		lines.append("{\n\"classname\" \"func_detail_illusionary\"")
		for brush: Array in _decor_bars:
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
