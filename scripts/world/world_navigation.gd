class_name WorldNavigation
extends Node

## Pathfinding for the open world (docs/WORLD.md), the way big open worlds
## do it: the navmesh is BAKED OFFLINE in tiles (the world bake tool calls
## bake_tiles()), and while you play the tiles are only LOADED round each
## player and unloaded behind -- streamed like the world's chunks, no baking
## at runtime (Recast's tiled navmesh: Unreal, Unity, Horizon; and Half-Life
## 2's / Left 4 Dead's nav was built at map-compile time too). Neighbouring
## tiles are baked with a shared border so their edges meet exactly and join
## into one walkable surface.
## Fallback: with no baked tiles (a scene the tool hasn't baked), it bakes
## round each player at runtime on a background thread instead.
## Enemies ask for routes through PathRequests (the budgeted queue).
## Rule 1 (co-op): AI and its paths run on the host, so only the host loads
## navigation; it keeps tiles loaded round every player.
## (Fallback bake adapted from Terrain3D's demo RuntimeNavigationBaker, MIT.)

## Where the baked tiles are (tile_<x>_<z>.res), and their size in metres.
@export_dir var tiles_dir: String = ""
@export var tile_size: float = 128.0
## Tiles loaded round each player, in tiles each way (2 = 5 x 5 tiles).
@export var load_radius: int = 2

@export_group("Agent")
## The navmesh's agent: matches MapLevel's (enemies' capsules, rounded).
@export var agent_radius: float = 0.5
@export var agent_height: float = 2.0
## Steepest slope they'll walk (degrees: the player's own floor limit, so
## they can follow you anywhere you can walk) and the biggest step up
## (metres). The step has to be at least a cell's rise on the steepest
## walkable slope (cell_size x tan(slope)), or slopes bake as ledges.
@export var agent_max_slope: float = 45.0
@export var agent_max_climb: float = 1.0
## Navmesh resolution (metres). The terrain's own triangles are 4 m, so 1 m
## loses nothing that matters -- and a finer grid made 4x the polygons,
## files and search time (0.5 m: ~1,100 polygons a 128 m tile).
@export var cell_size: float = 1.0
## Polygon merging: islands smaller than region_min_size (cells^2) are
## dropped, regions under region_merge_size are merged; and how far edges
## may stray from the real outline (cells). Bigger = fewer, bigger polygons.
@export var region_min_size: float = 8.0
@export var region_merge_size: float = 40.0
@export var edge_max_error: float = 2.0

@export_group("Runtime Fallback")
## Only with no baked tiles: ground baked round each player (x, height, z),
## rebaked once they've moved this far, at most this often (seconds).
@export var fallback_area: Vector3 = Vector3(256.0, 512.0, 256.0)
@export var fallback_rebake_distance: float = 64.0
@export var fallback_cooldown: float = 1.0
## The ground (a Terrain3D node). Empty = found in the scene.
@export var terrain: Node3D

## Recast keeps a tile's height in 13 bits of cells (8,191 x 0.25 m: 2,047 m);
## anything above that was silently left out -- the Stack's halls past
## ~1,750 m had no navmesh. A taller tile's baked in slices SLICE tall
## (overlapping SLICE_OVERLAP, so a floor on a seam is in one whole), each its
## own file (tile_x_z.res, then tile_x_z_s1.res...) and region; regions'
## edge connections join them where a ramp crosses a seam.
const SLICE := 1900.0
const SLICE_OVERLAP := 6.0
const MAX_SLICES := 6

var _template: NavigationMesh
## Slice files known not to be there (not asked about again).
var _missing := {}
## Baked tiles: Vector3i (tile x, tile z, slice) -> NavigationRegion3D once loaded, or the path
## while it's loading in the background.
var _tiles := {}
var _use_tiles := false
## Fallback: static colliders (parsed once) and, per player, [region,
## centre last baked, bake task id (-1 = none), cooldown left].
var _static_geometry: NavigationMeshSourceGeometryData3D
var _baking := {}


## The navmesh settings everything here bakes with (the bake tool too).
func make_template() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = agent_radius
	mesh.agent_height = agent_height
	mesh.agent_max_slope = agent_max_slope
	mesh.agent_max_climb = agent_max_climb
	mesh.cell_size = cell_size
	mesh.cell_height = 0.25
	mesh.region_min_size = region_min_size
	mesh.region_merge_size = region_merge_size
	mesh.edge_max_error = edge_max_error
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1 # world geometry
	return mesh


## OFFLINE (the world bake tool): bakes every tile over `area` (x/z bounds)
## from the terrain plus `static_root`'s static colliders, into tiles_dir.
## Each tile takes in a border of geometry past its edges and cuts it off
## again (border_size), so neighbouring tiles' edges line up exactly.
func bake_tiles(area: Rect2, terrain_node: Node3D, static_root: Node, height_range: Vector2) -> int:
	var template := make_template()
	var border := cell_size * 4.0
	template.border_size = border
	var statics := NavigationMeshSourceGeometryData3D.new()
	if static_root:
		NavigationServer3D.parse_source_geometry_data(template, statics, static_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tiles_dir))
	var first := Vector2i(floori(area.position.x / tile_size), floori(area.position.y / tile_size))
	var last := Vector2i(ceili(area.end.x / tile_size) - 1, ceili(area.end.y / tile_size) - 1)
	# Each tile's source geometry is gathered here (the terrain's faces have
	# to be read on this thread); the bakes then run on every CPU core at
	# once, and the finished tiles are saved compressed.
	var jobs: Array = []
	var bottom := height_range.x - 5.0
	var top := height_range.y + 5.0
	var slices := mini(maxi(1, ceili((top - bottom) / SLICE)), MAX_SLICES)
	for tz in range(first.y, last.y + 1):
		for tx in range(first.x, last.x + 1):
			for slice in slices:
				var y0 := maxf(bottom + slice * SLICE - SLICE_OVERLAP, bottom)
				var y1 := minf(bottom + (slice + 1) * SLICE + SLICE_OVERLAP, top) if slice < slices - 1 else top
				var box := AABB(Vector3(tx * tile_size, y0, tz * tile_size), Vector3(tile_size, y1 - y0, tile_size))
				var mesh: NavigationMesh = template.duplicate()
				# Baked over the tile plus its border, then the border's trimmed
				# off (border_size), so the edges land on the tile's bounds (to
				# within a cell -- the region's edge connections bridge that).
				var bake_box := box.grow(border)
				bake_box.position.y = box.position.y
				bake_box.size.y = box.size.y
				mesh.filter_baking_aabb = bake_box
				var source: NavigationMeshSourceGeometryData3D = statics.duplicate()
				var faces: PackedVector3Array = terrain_node.call("generate_nav_mesh_source_geometry", box.grow(border), false)
				source.add_faces(faces, Transform3D.IDENTITY)
				if source.has_data():
					jobs.append([Vector3i(tx, tz, slice), mesh, source])
			# Slices from an earlier, taller bake that this one doesn't make.
			for slice in range(slices, MAX_SLICES):
				var stale := ProjectSettings.globalize_path(_tile_path(Vector2i(tx, tz), slice))
				if FileAccess.file_exists(stale):
					DirAccess.remove_absolute(stale)
	var group := WorkerThreadPool.add_group_task(_bake_job.bind(jobs), jobs.size(), -1, true, "Bake navmesh tiles")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for job in jobs:
		var key: Vector3i = job[0]
		ResourceSaver.save(job[1], _tile_path(Vector2i(key.x, key.y), key.z), ResourceSaver.FLAG_COMPRESS)
	return jobs.size()


## One tile's bake, on a worker thread (bake_tiles()): jobs[index] is
## [tile, its NavigationMesh, its source geometry].
func _bake_job(index: int, jobs: Array) -> void:
	var job: Array = jobs[index]
	NavigationServer3D.bake_from_source_geometry_data(job[1], job[2])


func _tile_path(tile: Vector2i, slice: int = 0) -> String:
	if slice > 0:
		return tiles_dir.path_join("tile_%d_%d_s%d.res" % [tile.x, tile.y, slice])
	return tiles_dir.path_join("tile_%d_%d.res" % [tile.x, tile.y])


func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_process(false) # clients don't run AI, so don't need paths
		return
	_template = make_template()
	var map := get_viewport().find_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, _template.cell_size)
	NavigationServer3D.map_set_cell_height(map, _template.cell_height)
	# Tiles' edges sit a cell apart; join anything closer than a cell and a half.
	NavigationServer3D.map_set_edge_connection_margin(map, _template.cell_size * 1.5)
	_use_tiles = not tiles_dir.is_empty() and DirAccess.dir_exists_absolute(tiles_dir)
	if not _use_tiles:
		if terrain == null:
			var found := get_parent().find_children("*", "Terrain3D", true, false)
			terrain = found[0] as Node3D if not found.is_empty() else null
		_parse_static.call_deferred() # after the rest of the scene's set up


func _process(delta: float) -> void:
	if _use_tiles:
		_stream_tiles()
	else:
		_fallback_bake(delta)


# --- Baked tiles: load round every player, unload behind ---

func _stream_tiles() -> void:
	var wanted := {}
	for player in get_tree().get_nodes_in_group("player"):
		var body := player as Node3D
		if body == null:
			continue
		var centre := Vector2i(floori(body.global_position.x / tile_size), floori(body.global_position.z / tile_size))
		for dz in range(-load_radius, load_radius + 1):
			for dx in range(-load_radius, load_radius + 1):
				wanted[centre + Vector2i(dx, dz)] = true
	# Start loading what's wanted (in the background); finish what's loaded.
	# Every slice of a tile (most have only the one).
	for tile: Vector2i in wanted:
		for slice in MAX_SLICES:
			var key := Vector3i(tile.x, tile.y, slice)
			if not _tiles.has(key):
				if _missing.has(key):
					continue
				var path := _tile_path(tile, slice)
				if ResourceLoader.exists(path):
					ResourceLoader.load_threaded_request(path, "NavigationMesh")
					_tiles[key] = path
				else:
					_missing[key] = true
			elif _tiles[key] is String:
				var path: String = _tiles[key]
				if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
					var region := NavigationRegion3D.new()
					# Joins this tile to its neighbours across the one-cell seam the
					# bake leaves (worked out once as the tile loads, not per frame),
					# and to its other slices where a ramp crosses between them.
					region.use_edge_connections = true
					region.navigation_mesh = ResourceLoader.load_threaded_get(path) as NavigationMesh
					add_child(region)
					_tiles[key] = region
	# Unload tiles no player's near any more (one ring of slack, so walking
	# back and forth over a tile edge doesn't load/unload it every time).
	for key: Vector3i in _tiles.keys():
		var tile := Vector2i(key.x, key.y)
		if wanted.has(tile) or _near_any(tile, wanted):
			continue
		var held: Variant = _tiles[key]
		if held is NavigationRegion3D:
			(held as Node).queue_free()
			_tiles.erase(key)
		elif ResourceLoader.load_threaded_get_status(held) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_tiles.erase(key)


func _near_any(tile: Vector2i, wanted: Dictionary) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if wanted.has(tile + Vector2i(dx, dz)):
				return true
	return false


# --- Fallback: bake round each player at runtime ---

func _parse_static() -> void:
	_static_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_template, _static_geometry, get_parent())


## Something solid built after the start (the Stacks' Flesh Tree): parsed
## again, and every player's ground baked again with it.
func refresh_static() -> void:
	if _use_tiles:
		return
	_parse_static()
	for body: Variant in _baking:
		(_baking[body] as Array)[1] = Vector3(INF, INF, INF)


func _fallback_bake(delta: float) -> void:
	if _static_geometry == null:
		return
	for player in get_tree().get_nodes_in_group("player"):
		var body := player as Node3D
		if body == null:
			continue
		if not _baking.has(body):
			var region := NavigationRegion3D.new()
			region.use_edge_connections = false
			add_child(region)
			_baking[body] = [region, Vector3(INF, INF, INF), -1, 0.0]
		var state: Array = _baking[body]
		if state[2] != -1:
			continue # still baking
		state[3] = maxf(float(state[3]) - delta, 0.0)
		if state[3] > 0.0:
			continue
		var centre := body.global_position
		if body is CharacterBody3D:
			centre += (body as CharacterBody3D).velocity * fallback_cooldown # where they're about to be
		if centre.distance_squared_to(state[1]) < fallback_rebake_distance * fallback_rebake_distance:
			continue
		state[1] = centre
		state[3] = fallback_cooldown
		state[2] = WorkerThreadPool.add_task(_bake.bind(body, centre), false, "WorldNavigation")
	for body in _baking.keys():
		if not is_instance_valid(body):
			var state: Array = _baking[body]
			if state[2] == -1:
				(state[0] as Node).queue_free()
				_baking.erase(body)


## On a worker thread: static geometry + the terrain's faces round `centre`.
func _bake(body: Node3D, centre: Vector3) -> void:
	var mesh: NavigationMesh = _template.duplicate()
	mesh.filter_baking_aabb = AABB(-fallback_area * 0.5, fallback_area)
	mesh.filter_baking_aabb_offset = centre
	var source: NavigationMeshSourceGeometryData3D = _static_geometry.duplicate()
	if is_instance_valid(terrain):
		var box := AABB(centre - fallback_area * 0.5, fallback_area)
		var faces: PackedVector3Array = terrain.call("generate_nav_mesh_source_geometry", box, false)
		source.add_faces(faces, Transform3D.IDENTITY)
	if source.has_data():
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	else:
		mesh = null
	_baked.call_deferred(body, mesh)


func _baked(body: Node3D, mesh: NavigationMesh) -> void:
	if not _baking.has(body):
		return
	var state: Array = _baking[body]
	WorkerThreadPool.wait_for_task_completion(state[2]) # already done; frees the task
	state[2] = -1
	if mesh:
		(state[0] as NavigationRegion3D).navigation_mesh = mesh
