class_name DemoWindowRooms
extends Node3D

## The window rooms in the Stacks demo (the user's, 2026-10-27: the open
## world's, up to MAX_A_HALL a hall, rolled each run, the stair chains up the
## halls leading to them): a small apartment room hung on a hall's window
## wall -- its window one of the real glass ones the bake kept for it
## (`feet`), its doorway into the hall, a warm lamp in it -- and a chain of
## the procedural Stack's abstract stairs (SLOPE flights, each up to a
## platform, the next off that) climbing to its door from the hall's floor.
## Each run: MIN_A_HALL..MAX_A_HALL in every hall, at spots of the bake's,
## wherever the room and its stairs keep clear of the hall's decor, blocks,
## doorways and things (`blocked`) and of each other.
## Rule 1 (co-op): the host rolls the run's seed; every game builds the same
## from it (one joining asks for it).

const MAX_A_HALL := 3 # (the user's)
const MIN_A_HALL := 1
## The room: across, into the hall, up (to its roof's top; the bake's
## ROOM_TALL), its walls' and slabs' thickness, its doorway.
const WIDE := 6.0
const DEEP := 5.0
const TALL := 5.9
const WALL := 0.3
const SLAB := 0.4
const DOOR := Vector2(2.0, 2.6)
## The stairs (the bake's were these): 35-degree flights 4 m wide, 6 m
## platforms, each flight rising RISE; kept HALL_EDGE in from the hall's walls
## and MARGIN clear of everything.
const SLOPE := 35.0
const FLIGHT_WIDE := 4.0
const FLIGHT_THICK := 0.6
const LANDING := 6.0
const RISE := Vector2(3.0, 7.0)
const MAX_FLIGHTS := 12
const HALL_EDGE := 2.0
const MARGIN := 0.5
const LAMP := Color(1.0, 0.68, 0.32) # (the open world's window rooms')
const PLAIN := "res://trenchbroom/textures/Megastructure/stack_plain.tres"
const STAINED := "res://trenchbroom/textures/Megastructure/stack_stained.tres"
const TILE := 4.0 # (metres a texture, as the map's)

@export var halls: Array[AABB] = []
## Each spot: its window's foot on the hall's inner wall face (the room's
## floor), the window's way out, its hall.
@export var feet := PackedVector3Array()
@export var outs := PackedVector3Array()
@export var spot_halls := PackedInt32Array()
@export var blocked: Array[AABB] = []

var _seed := 0
var _built := false
var _taken: Array[AABB] = []
var _walls: Material
var _floors: Material


func _ready() -> void:
	if not Network.is_online() or multiplayer.is_server():
		_seed = randi_range(1, 1 << 30)
		_build.call_deferred(_seed)
	else:
		_net_ask.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _net_ask() -> void:
	if multiplayer.is_server() and _seed != 0:
		_net_seed.rpc_id(multiplayer.get_remote_sender_id(), _seed)


@rpc("authority", "call_remote", "reliable")
func _net_seed(seed_: int) -> void:
	if not _built:
		_build(seed_)


func _build(seed_: int) -> void:
	_built = true
	_walls = _material(PLAIN)
	_floors = _material(STAINED)
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_
	for h in halls.size():
		var spots: Array[int] = []
		for i in feet.size():
			if spot_halls[i] == h:
				spots.append(i)
		for i in range(spots.size() - 1, 0, -1): # (shuffled by the run's dice)
			var j := dice.randi() % (i + 1)
			var keep := spots[i]
			spots[i] = spots[j]
			spots[j] = keep
		var want := dice.randi_range(MIN_A_HALL, MAX_A_HALL)
		var made := 0
		for i in spots:
			if made >= want:
				break
			if _try_room(halls[h], feet[i], outs[i], dice):
				made += 1
	# Built after the navmesh was read: read again (as the Flesh Tree does).
	var navigation := get_tree().current_scene.get_node_or_null(^"WorldNavigation")
	if navigation and navigation.has_method(&"refresh_static"):
		navigation.call(&"refresh_static")


## The texture laid on in world space (pieces turned any way line up).
static func _material(path: String) -> Material:
	var source := load(path) as StandardMaterial3D if ResourceLoader.exists(path) else null
	var made := source.duplicate() as StandardMaterial3D if source else StandardMaterial3D.new()
	made.uv1_triplanar = true
	made.uv1_world_triplanar = true
	made.uv1_scale = Vector3.ONE / TILE
	return made


## A room at this spot, and stairs up to it from the floor. False: no room
## for them here.
func _try_room(hall: AABB, foot: Vector3, out: Vector3, dice: RandomNumberGenerator) -> bool:
	var inward := -out
	var across := Vector3.UP.cross(out).normalized()
	var turn := Basis(across, Vector3.UP, out)
	var room := {c = foot + inward * DEEP * 0.5 + Vector3.UP * (TALL - SLAB) * 0.5, s = Vector3(WIDE, TALL + SLAB, DEEP), b = turn}
	var box := _bounds_of(room)
	var none: Array[AABB] = []
	if not hall.grow(0.05).encloses(box) or _clashes(box, none):
		return false
	for attempt in 8:
		var chain := _chain(hall, foot + inward * (DEEP + LANDING * 0.5), hall.position.y, turn, box, dice)
		if chain.is_empty():
			continue
		_make_room(foot, inward, across, turn)
		var stairs := Node3D.new()
		stairs.name = "Stairs_%d" % get_child_count()
		add_child(stairs)
		for piece: Dictionary in chain:
			_solid(stairs, piece.c, piece.s, piece.b, _floors)
			_taken.append_array(_parts_of(piece))
		_taken.append(box)
		return true
	return false


## The stair chain down from a landing at `top` (the room's door, its floor
## level) to the floor at `floor_y`: the landing, then flight, platform,
## flight... each flight heading any way, rising RISE (the last what's left).
## Its pieces ({c, s, b}), or [] if no way down fits.
func _chain(hall: AABB, top: Vector3, floor_y: float, turn: Basis, room: AABB, dice: RandomNumberGenerator) -> Array:
	var pieces: Array = []
	var landing := {c = top - Vector3.UP * 0.5, s = Vector3(LANDING, 1.0, LANDING), b = turn}
	var none: Array[AABB] = [] # (it's up against the room's front: that's the point)
	if not _fits(hall, landing, none):
		return []
	pieces.append(landing)
	var at := top
	for step in MAX_FLIGHTS:
		var left := at.y - floor_y
		if left < 0.3:
			return pieces # (the landing's on the floor)
		var placed := false
		for tries in 24:
			var heading := Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU)
			var rise := minf(dice.randf_range(RISE.x, RISE.y), left)
			if left - rise < RISE.x * 0.5:
				rise = left # (no stub of a last flight)
			var run := rise / tan(deg_to_rad(SLOPE))
			# Arriving at this landing's edge, from the next one down's middle.
			var upper := at - heading * LANDING * 0.5
			var lower := upper - heading * run - Vector3.UP * rise
			var flight := {c = (upper + lower) * 0.5, s = Vector3(FLIGHT_WIDE, FLIGHT_THICK, upper.distance_to(lower)),
					b = Basis.looking_at((upper - lower).normalized(), Vector3.UP)}
			var others: Array[AABB] = [room]
			for k in pieces.size() - 1: # (not the landing it arrives at)
				others.append_array(_parts_of(pieces[k]))
			if not _fits(hall, flight, others):
				continue
			var last := lower.y - floor_y < 0.3
			var platform := {c = lower - Vector3.UP * 0.5, s = Vector3(LANDING, 1.0, LANDING), b = Basis(Vector3.UP, dice.randf() * TAU)}
			if not last:
				others.append_array(_parts_of(pieces[pieces.size() - 1]))
				others.append_array(_parts_of(flight).slice(0, -1)) # (not its foot: the platform's under it)
				if not _fits(hall, platform, others):
					continue
			pieces.append(flight)
			if last:
				return pieces
			pieces.append(platform)
			at = lower
			placed = true
			break
		if not placed:
			return []
	return []


## Whether a piece stands inside the hall (HALL_EDGE in from its walls, under
## its ceiling) clear of what's blocked, what's built, and `others`.
func _fits(hall: AABB, piece: Dictionary, others: Array[AABB]) -> bool:
	var box := _bounds_of(piece)
	var inner := hall.grow(-HALL_EDGE)
	if box.position.x < inner.position.x or box.end.x > inner.end.x or box.position.z < inner.position.z \
			or box.end.z > inner.end.z or box.end.y > hall.end.y - 0.5:
		return false
	for part in _parts_of(piece):
		if _clashes(part, others):
			return false
	return true


## A piece's bounds in short lengths along it (a sloping flight's one box
## would take in the whole air under it).
static func _parts_of(piece: Dictionary) -> Array[AABB]:
	var size: Vector3 = piece.s
	var count := maxi(1, ceili(size.z / 2.0))
	var parts: Array[AABB] = []
	var basis: Basis = piece.b
	for k in count:
		var along := (float(k) + 0.5) / count - 0.5
		parts.append(_bounds_of({c = (piece.c as Vector3) + basis.z * along * size.z, s = Vector3(size.x, size.y, size.z / count), b = basis}))
	return parts


func _clashes(box: AABB, others: Array[AABB]) -> bool:
	var near := box.grow(MARGIN)
	var hit := func(other: AABB) -> bool: return other.intersects(near)
	return blocked.any(hit) or _taken.any(hit) or others.any(hit)


## A turned box's bounds (its eight corners).
static func _bounds_of(piece: Dictionary) -> AABB:
	var basis: Basis = piece.b
	var half: Vector3 = (piece.s as Vector3) * 0.5
	var c: Vector3 = piece.c
	var box := AABB(c, Vector3.ZERO)
	for corner in 8:
		var sign := Vector3(1.0 if corner & 1 else -1.0, 1.0 if corner & 2 else -1.0, 1.0 if corner & 4 else -1.0)
		box = box.expand(c + basis * (half * sign))
	return box


## The room: its floor at `foot`, back against the window wall, a doorway in
## its front, a roof, a warm lamp.
func _make_room(foot: Vector3, inward: Vector3, across: Vector3, turn: Basis) -> void:
	var room := Node3D.new()
	room.name = "WindowRoom_%d" % get_child_count()
	add_child(room)
	var inside := TALL - SLAB # (floor to ceiling)
	var middle := foot + inward * DEEP * 0.5
	_solid(room, middle - Vector3.UP * SLAB * 0.5, Vector3(WIDE, SLAB, DEEP), turn, _floors) # its floor
	_solid(room, middle + Vector3.UP * (inside + SLAB * 0.5), Vector3(WIDE, SLAB, DEEP), turn, _walls) # its roof
	for side: float in [-1.0, 1.0]:
		_solid(room, middle + across * side * (WIDE - WALL) * 0.5 + Vector3.UP * inside * 0.5, Vector3(WALL, inside, DEEP), turn, _walls)
	# Its front: a doorway in the middle.
	var front := foot + inward * (DEEP - WALL * 0.5)
	var jamb := (WIDE - DOOR.x) * 0.5
	for side: float in [-1.0, 1.0]:
		_solid(room, front + across * side * (DOOR.x + jamb) * 0.5 + Vector3.UP * inside * 0.5, Vector3(jamb, inside, WALL), turn, _walls)
	_solid(room, front + Vector3.UP * (DOOR.y + inside) * 0.5, Vector3(DOOR.x, inside - DOOR.y, WALL), turn, _walls)
	var lamp := OmniLight3D.new()
	lamp.light_color = LAMP
	lamp.light_energy = 1.0
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	room.add_child(lamp)
	lamp.global_position = middle + Vector3.UP * (inside - 0.5)


## A solid box (drawn, and something to stand on).
func _solid(parent: Node3D, centre: Vector3, size: Vector3, turn: Basis, look: Material) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = look
	body.add_child(mesh)
	parent.add_child(body)
	body.global_transform = Transform3D(turn, centre)
