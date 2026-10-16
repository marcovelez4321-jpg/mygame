class_name StackDressing
extends Node3D

## The Stack's lived-in bits (the user's, 2026-10-16), laid out when it loads
## from its own halls and towers -- the same on every machine (a fixed seed):
##   LINES between the towers: in LINE_HALL_CHANCE of the halls, LINES of them
##   strung out from that hall's tower to its nearest neighbour at the hall's
##   height -- electrical cable or a clothing line with clothes (the
##   greybox's), CLOTHES_CHANCE each.
##   LAMP POSTS inside the halls: LAMPS of them a hall, rooted in its inside
##   wall (found by a ray, so nothing pokes out through the shell) and
##   reaching in, a cold white bulb on the end.
## Cheap: every wire and post is ONE mesh (one draw call), the cables one
## static body of thin boxes, the bulbs one MultiMesh, the clothes one
## MultiMesh coloured per piece; the lamps' lights cast no shadows and fade
## out; the insides are only drawn within the Stack's interior_distance.

const LINE_HALL_CHANCE := 0.5
const LINES := Vector2i(1, 3)
const CLOTHES_CHANCE := 0.5
const LAMPS := Vector2i(1, 2)
## The greybox's lamp: an arm out of the wall, a short drop, a bulb; cold white.
const ARM_LENGTH := 2.0
const BULB_RADIUS := 0.35
const LAMP_COLOR := Color(0.85, 0.9, 1.0)
const LAMP_ENERGY := 2.5
const LAMP_RANGE := 30.0
const LAMP_FADE := 150.0
const CABLE_THICK := 0.12
const LINE_THICK := 0.05
## The greybox's washing: its stand-in colours.
const WASHING := [Color(0.75, 0.2, 0.18), Color(0.2, 0.35, 0.7), Color(0.85, 0.82, 0.7), Color(0.3, 0.55, 0.3),
		Color(0.55, 0.45, 0.3), Color(0.9, 0.9, 0.88), Color(0.2, 0.2, 0.22), Color(0.7, 0.55, 0.15),
		Color(0.5, 0.25, 0.5), Color(0.45, 0.6, 0.7)]

var _stack: Megastructure
var _rng := RandomNumberGenerator.new()
var _wires := SurfaceTool.new()
var _wire_count := 0
var _cables: StaticBody3D
var _bulbs: Array[Transform3D] = []
var _clothes: Array = [] # [Transform3D, Color, Vector2 size]
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	_stack = get_parent() as Megastructure
	if _stack == null:
		return
	# Its collision has to be in the world first (the rays find its walls).
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	_rng.seed = StackBuilder.SEED + 4242
	_wires.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cables = StaticBody3D.new()
	_cables.name = "Cables"
	add_child(_cables)
	var halls := _stack.inside_zones
	for i in halls.size():
		var hall: AABB = halls[i]
		var tower := _tower_of(hall.get_center())
		if tower < 0:
			continue
		if _rng.randf() < LINE_HALL_CHANCE:
			for k in _rng.randi_range(LINES.x, LINES.y):
				_line_from(tower, hall)
		for k in _rng.randi_range(LAMPS.x, LAMPS.y):
			_lamp_in(hall)
	_finish()


## Which tower (StackBuilder.TOWERS) a point's footprint is in, or -1.
static func _tower_of(at: Vector3) -> int:
	for t in StackBuilder.TOWERS.size():
		var tower: Array = StackBuilder.TOWERS[t]
		var half: float = tower[2] * 0.5
		if absf(at.x - tower[0]) <= half and absf(at.z - tower[1]) <= half:
			return t
	return -1


## A line from tower `t` (at a height in `hall`) to its nearest neighbour
## that's tall enough: both ends where rays meet their outside walls.
func _line_from(t: int, hall: AABB) -> void:
	var y := _rng.randf_range(hall.position.y + 4.0, hall.end.y - 4.0)
	var here: Array = StackBuilder.TOWERS[t]
	var best := -1
	var best_distance := INF
	for o in StackBuilder.TOWERS.size():
		var other: Array = StackBuilder.TOWERS[o]
		if o == t or other[3] < y + 5.0:
			continue
		var distance := Vector2(other[0] - here[0], other[1] - here[1]).length()
		if distance < best_distance:
			best_distance = distance
			best = o
	if best < 0:
		return
	var there: Array = StackBuilder.TOWERS[best]
	var a := Vector3(here[0], y, here[1])
	var b := Vector3(there[0], y, there[1])
	var middle := (a + b) * 0.5
	var across := (b - a).cross(Vector3.UP).normalized()
	middle += across * _rng.randf_range(-25.0, 25.0)
	var start := _hit(middle, a)
	var end := _hit(middle, b)
	if not start.is_finite() or not end.is_finite() or start.distance_to(end) < 4.0:
		return
	if _rng.randf() < CLOTHES_CHANCE:
		_line(start, end, LINE_THICK)
		_hang_washing(start, end)
	else:
		_line(start, end, CABLE_THICK)
		_cable_body(start, end)


## A cold white lamp on an arm out of the hall's inside wall.
func _lamp_in(hall: AABB) -> void:
	var y := _rng.randf_range(hall.position.y + 4.0, hall.end.y - 3.0)
	var middle := Vector3(hall.get_center().x, y, hall.get_center().z)
	var angle := _rng.randf() * TAU
	var way := Vector3(cos(angle), 0.0, sin(angle))
	var reach := maxf(hall.size.x, hall.size.z)
	var wall := _hit(middle, middle + way * reach)
	if not wall.is_finite():
		return
	var root := wall - way * 0.05 # (just inside the wall's face)
	var tip := root - way * ARM_LENGTH
	_line(root, tip, 0.2)
	var drop := tip + Vector3.DOWN * 0.6
	_line(tip, drop, 0.12)
	var bulb := drop + Vector3.DOWN * BULB_RADIUS
	_bulbs.append(Transform3D(Basis.IDENTITY, bulb))
	var light := OmniLight3D.new()
	light.light_color = LAMP_COLOR
	light.light_energy = LAMP_ENERGY
	light.omni_range = LAMP_RANGE
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = LAMP_FADE * 0.7
	light.distance_fade_length = LAMP_FADE * 0.3
	light.position = bulb
	add_child(light)


## Where a ray from `from` toward `to` first meets the Stack (local), or INF.
func _hit(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(_stack.to_global(from), _stack.to_global(to))
	query.collision_mask = 1
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return _stack.to_local(hit.position)


## A thin square bar from `a` to `b` into the one wire mesh.
func _line(a: Vector3, b: Vector3, thick: float) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.01:
		return
	var forward := along / length
	var side := forward.cross(Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT).normalized() * thick * 0.5
	var up := side.cross(forward).normalized() * thick * 0.5
	var corners := [side + up, -side + up, -side - up, side - up]
	for s in 4:
		var c0: Vector3 = corners[s]
		var c1: Vector3 = corners[(s + 1) % 4]
		for point: Vector3 in [a + c0, b + c0, b + c1, a + c0, b + c1, a + c1]:
			_wires.add_vertex(point)
	_wire_count += 1


## A cable you can stand on or grapple: a thin box along it.
func _cable_body(a: Vector3, b: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CABLE_THICK, CABLE_THICK, a.distance_to(b))
	shape.shape = box
	var forward := (b - a).normalized()
	shape.transform = Transform3D(Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT), (a + b) * 0.5)
	_cables.add_child(shape)


## Shirts and pants along a clothing line (the greybox's stand-ins).
func _hang_washing(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var forward := (b - a) / length
	var facing := Basis.looking_at(forward.cross(Vector3.UP).normalized(), Vector3.UP)
	var spot := _rng.randf_range(1.0, 3.0)
	while spot < length - 1.0:
		var shirt := _rng.randf() < 0.6
		var size := Vector2(0.7, 0.75) if shirt else Vector2(0.45, 1.0)
		var at := a + forward * spot - Vector3.UP * (size.y * 0.5 + 0.05)
		_clothes.append([Transform3D(facing.scaled(Vector3(size.x, size.y, 1.0)), at), WASHING[_rng.randi() % WASHING.size()]])
		spot += _rng.randf_range(0.9, 2.2)


## Everything into its few draw calls.
func _finish() -> void:
	if _wire_count > 0:
		_wires.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "Wires"
		mesh.mesh = _wires.commit()
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.08, 0.08, 0.08)
		metal.roughness = 0.6
		mesh.material_override = metal
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	if not _bulbs.is_empty():
		var sphere := SphereMesh.new()
		sphere.radius = BULB_RADIUS
		sphere.height = BULB_RADIUS * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var glow := StandardMaterial3D.new()
		glow.albedo_color = LAMP_COLOR
		glow.emission_enabled = true
		glow.emission = LAMP_COLOR
		glow.emission_energy_multiplier = 3.0
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = glow
		add_child(_multimesh("Bulbs", sphere, _bulbs.size(), func(i: int, mm: MultiMesh) -> void:
			mm.set_instance_transform(i, _bulbs[i]), false))
	if not _clothes.is_empty():
		var quad := QuadMesh.new()
		var cloth := StandardMaterial3D.new()
		cloth.vertex_color_use_as_albedo = true
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.roughness = 1.0
		quad.material = cloth
		add_child(_multimesh("Washing", quad, _clothes.size(), func(i: int, mm: MultiMesh) -> void:
			mm.set_instance_transform(i, _clothes[i][0])
			mm.set_instance_color(i, _clothes[i][1]), true))
	_bulbs.clear()
	_clothes.clear()


static func _multimesh(name: String, mesh: Mesh, count: int, fill: Callable, coloured: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = coloured
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		fill.call(i, mm)
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
