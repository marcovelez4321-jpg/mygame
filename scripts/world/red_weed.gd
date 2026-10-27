class_name RedWeed
extends Node3D

## The red weed (the user's, 2026-10-19): Spielberg's War of the Worlds
## (2005) crimson creeper -- knotted mounds of glossy blood-red vines, thick
## ropey runners creeping out over the ground, thin drooping tendrils curling
## at their ends, a few swollen pods. Thick round the Flesh Tree, scattered
## round the yard's edges, and climbing the back wall of Grandma's house.
## Alive (red_weed.gdshader): it writhes slowly, and its tendrils curl toward
## any player standing close. Scenery: you walk straight through it.
## Cheap: VARIANTS bush shapes made once, every bush an instance of one (one
## MultiMesh a shape: a draw call each), drawn within seen_range.
## Every game grows the same weed (a fixed seed): nothing to sync (Rule 1:
## presentation).
## Put it at the yard's middle; it finds the tree (FleshTree) and the house
## (group "grandmas_house") itself.

const SHADER := preload("res://shaders/red_weed.gdshader")
const VARIANTS := 4
const SIDES := 5

@export var seed_value: int = 2005
@export_group("Round the tree")
@export var tree_bushes: int = 40
## From the trunk's middle (its flared foot reaches about 20 m).
@export var tree_near: float = 21.0
@export var tree_far: float = 38.0
@export_group("Round the yard")
@export var yard_bushes: int = 16
@export var yard_near: float = 30.0
@export var yard_far: float = 52.0
@export_group("Size")
## A bush's height (m); its runners creep out about twice that.
@export var size_min: float = 0.5
@export var size_max: float = 2.0
@export var seen_range: float = 220.0

var _material: ShaderMaterial
var _players := PackedVector3Array()


func _ready() -> void:
	add_to_group(&"red_weed")
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	await get_tree().physics_frame
	await get_tree().physics_frame
	_grow()


## Every player, for the weed to reach toward (up to 4).
func _process(_delta: float) -> void:
	if _material == null:
		return
	_players.clear()
	for node in get_tree().get_nodes_in_group("player"):
		if _players.size() >= 4:
			break
		var player := node as Node3D
		if player:
			_players.append(player.global_position)
	_material.set_shader_parameter(&"player_count", _players.size())
	if not _players.is_empty():
		_material.set_shader_parameter(&"players", _players)


# ---- Where it grows ------------------------------------------------------------------------

## Grown again (the Tree fed: twice as thick -- QuestWorld).
func regrow() -> void:
	for child in get_children():
		child.queue_free()
	_grow()


func _grow() -> void:
	# Fed (the user's, Feed the Tree): twice the bushes.
	var thick := 2 if Quests.tree_fed() else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var house := get_tree().get_first_node_in_group(&"grandmas_house") as Node3D
	var spots: Array[Vector3] = []
	var tree := FleshTree._tree
	if tree and is_instance_valid(tree):
		var middle := Vector2(tree.global_position.x, tree.global_position.z)
		for i in tree_bushes * thick:
			# Thicker near the trunk.
			var reach := lerpf(tree_near, tree_far, pow(rng.randf(), 1.6))
			_try_spot(spots, middle + Vector2.from_angle(rng.randf() * TAU) * reach, house)
	var yard := Vector2(global_position.x, global_position.z)
	for i in yard_bushes * thick:
		_try_spot(spots, yard + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(yard_near, yard_far), house)
	# The bushes: each one of the shapes, turned and sized at random.
	var meshes: Array[ArrayMesh] = []
	for v in VARIANTS:
		meshes.append(_bush_mesh(rng))
	var placed: Array = []
	for v in VARIANTS:
		placed.append([])
	for spot in spots:
		var size := lerpf(size_min, size_max, pow(rng.randf(), 1.4))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		(placed[rng.randi() % VARIANTS] as Array).append([Transform3D(basis, to_local(spot)), rng.randf()])
	for v in VARIANTS:
		var list: Array = placed[v]
		if list.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = meshes[v]
		multimesh.instance_count = list.size()
		for i in list.size():
			multimesh.set_instance_transform(i, list[i][0])
			multimesh.set_instance_custom_data(i, Color(list[i][1], 0.0, 0.0, 0.0))
		var shown := MultiMeshInstance3D.new()
		shown.multimesh = multimesh
		shown.material_override = _material
		shown.visibility_range_end = seen_range
		add_child(shown)
	# Creeping up the back wall of the house (between its windows).
	if house:
		var size := GrandmasHouse.SIZE
		for patch: Array in [[Vector3(-3.0, 0.0, 4.0) * size, 3.0 * size, 3.4 * size], [Vector3(0.6, 0.0, 4.0) * size, 2.4 * size, 4.2 * size]]:
			var creeper := MeshInstance3D.new()
			creeper.mesh = _creeper_mesh(rng, patch[1], patch[2])
			creeper.material_override = _material
			creeper.visibility_range_end = seen_range
			add_child(creeper)
			creeper.global_transform = house.global_transform * Transform3D(Basis.IDENTITY, patch[0])


## A bush at `at` (x, z) on the ground -- not on the house, its porch or the
## path to its door.
func _try_spot(spots: Array[Vector3], at: Vector2, house: Node3D) -> void:
	var ground := _ground(at)
	if is_nan(ground):
		return
	var spot := Vector3(at.x, ground, at.y)
	if house:
		var local := house.to_local(spot)
		var size := GrandmasHouse.SIZE
		if AABB(Vector3(-6.5, -5.0, -8.0) * size, Vector3(13.0, 20.0, 13.5) * size).has_point(local):
			return
		if absf(local.x) < 2.5 * size and local.z < -6.0 * size and local.z > -40.0:
			return # (the way up to the door)
	spots.append(spot)


## The ground's height at (x, z): the terrain's own, else a ray down.
func _ground(at: Vector2) -> float:
	var terrain := get_tree().current_scene.get_node_or_null(^"Terrain3D") if get_tree().current_scene else null
	if terrain:
		var data: Object = terrain.get(&"data")
		if data and data.has_method(&"get_height"):
			var height: float = data.call(&"get_height", Vector3(at.x, 0.0, at.y))
			if not is_nan(height):
				return height
	var from := Vector3(at.x, global_position.y + 6.0, at.y)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0, 1))
	return (hit.position as Vector3).y if not hit.is_empty() else NAN


# ---- The shapes ----------------------------------------------------------------------------

## One bush, about 1 m tall (instances scale it): looping vines knotted into
## a mound, runners out over the ground, tendrils drooping and curling off
## the top, a few pods.
func _bush_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array = [] # [point, free] along the loops' upper halves
	# The loops: up out of the ground and back down into it.
	for i in 9:
		var start := Vector3.ZERO + _flat(rng, 0.3)
		var end := _flat(rng, 1.0).normalized() * rng.randf_range(0.55, 0.9)
		var height := rng.randf_range(0.5, 1.0)
		var lift := Vector3.UP * height * 1.33
		var c1 := start + lift + _flat(rng, 0.25)
		var c2 := end + lift + _flat(rng, 0.25)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var free := PackedFloat32Array()
		for k in 11:
			var u := k / 10.0
			var point := _bezier(start + Vector3.DOWN * 0.05, c1, c2, end + Vector3.DOWN * 0.05, u)
			points.append(point)
			radii.append(rng.randf_range(0.03, 0.06) * (1.0 - u * 0.3))
			free.append(0.18 * sin(u * PI))
			if u > 0.25 and u < 0.75:
				tops.append([point, 0.18 * sin(u * PI)])
		_tube(tool, points, radii, free, rng.randf_range(0.55, 1.0))
	# The runners: thick and ropey, creeping out over the ground.
	for i in 4:
		var way := Vector2.from_angle(rng.randf() * TAU)
		var length := rng.randf_range(1.6, 2.4)
		var wiggle := rng.randf() * TAU
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var free := PackedFloat32Array()
		for k in 11:
			var u := k / 10.0
			var side := Vector2(-way.y, way.x) * sin(u * 6.0 + wiggle) * 0.18 * u
			var flat := way * (0.2 + length * u) + side
			points.append(Vector3(flat.x, 0.04 + 0.03 * sin(u * 9.0 + wiggle), flat.y))
			radii.append(lerpf(0.06, 0.015, u))
			free.append(0.25 * u * u)
		_tube(tool, points, radii, free, rng.randf_range(0.45, 0.8))
	# The tendrils: thin, drooping off the top and curling at the end.
	for i in 10:
		var top: Array = tops[rng.randi() % tops.size()]
		var from: Vector3 = top[0]
		var out := Vector3(from.x, 0.0, from.z).normalized()
		if out.length_squared() < 0.01:
			out = Vector3.RIGHT
		var length := rng.randf_range(0.3, 0.7)
		var turn := rng.randf_range(2.0, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var side := out.cross(Vector3.UP)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var free := PackedFloat32Array()
		var at := from
		var heading := (out + Vector3.UP * 0.4).normalized()
		for k in 9:
			var u := k / 8.0
			points.append(at)
			radii.append(lerpf(0.02, 0.004, u))
			free.append(lerpf(top[1], 1.0, u))
			# Drooping, and curling tighter toward the end.
			heading = (heading + Vector3.DOWN * 0.18 + side * turn * 0.05 * u).normalized()
			heading = heading.rotated(out, turn * 0.06 * u * u * 4.0).normalized()
			at += heading * length / 8.0
		_tube(tool, points, radii, free, rng.randf_range(0.7, 1.0), 4)
	# The pods: swollen, glossy.
	for i in 5:
		var top: Array = tops[rng.randi() % tops.size()]
		_pod(tool, top[0], rng.randf_range(0.05, 0.11), top[1])
	return tool.commit()


## A patch climbing a wall `width` wide and up to `height` high (the wall
## at z 0, the patch on its +Z side).
func _creeper_mesh(rng: RandomNumberGenerator, width: float, height: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array = []
	for i in 7:
		var x := rng.randf_range(-width * 0.5, width * 0.5)
		var top := height * rng.randf_range(0.55, 1.0)
		var wiggle := rng.randf() * TAU
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var free := PackedFloat32Array()
		for k in 13:
			var u := k / 12.0
			var point := Vector3(x + sin(u * 7.0 + wiggle) * 0.25, -0.1 + top * u, 0.06 + 0.03 * sin(u * 11.0 + wiggle))
			points.append(point)
			radii.append(lerpf(0.06, 0.012, u))
			free.append(0.12 * u)
			if u > 0.2:
				tops.append([point, 0.12 * u])
		_tube(tool, points, radii, free, rng.randf_range(0.5, 0.95))
	for i in 12:
		var top: Array = tops[rng.randi() % tops.size()]
		var at: Vector3 = top[0]
		var heading := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.3), 1.0).normalized()
		var turn := rng.randf_range(2.0, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var length := rng.randf_range(0.25, 0.5)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var free := PackedFloat32Array()
		for k in 8:
			var u := k / 7.0
			points.append(at)
			radii.append(lerpf(0.016, 0.004, u))
			free.append(lerpf(top[1], 1.0, u))
			heading = (heading + Vector3.DOWN * 0.2).normalized().rotated(Vector3.BACK, turn * 0.08 * u)
			at += heading * length / 7.0
		_tube(tool, points, radii, free, rng.randf_range(0.7, 1.0), 4)
	for i in 4:
		var top: Array = tops[rng.randi() % tops.size()]
		_pod(tool, (top[0] as Vector3) + Vector3.BACK * 0.04, rng.randf_range(0.05, 0.09), top[1])
	return tool.commit()


## A tube through `points` (`radii`), `sides` round, each ring's vertices
## coloured (free to move, shade) for the shader.
func _tube(tool: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, free: PackedFloat32Array, shade: float, sides: int = SIDES) -> void:
	var count := points.size()
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in count:
		var forward := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := forward.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(forward).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			var out := side * cos(a) + up * sin(a)
			ring.append(points[i] + out * radii[i])
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	for i in count - 1:
		var ca := Color(free[i], shade, 0.0)
		var cb := Color(free[i + 1], shade, 0.0)
		for s in sides:
			var n := (s + 1) % sides
			for corner: Array in [[i, s, ca], [i, n, ca], [i + 1, n, cb], [i, s, ca], [i + 1, n, cb], [i + 1, s, cb]]:
				tool.set_color(corner[2])
				tool.set_normal(normals[corner[0]][corner[1]])
				tool.add_vertex(rings[corner[0]][corner[1]])


## A low, slightly squashed sphere: a pod.
func _pod(tool: SurfaceTool, at: Vector3, radius: float, free: float) -> void:
	var rings := 4
	var around := 7
	var color := Color(free, 1.0, 0.0)
	for r in rings:
		for s in around:
			var corners := [[r, s], [r, s + 1], [r + 1, s + 1], [r, s], [r + 1, s + 1], [r + 1, s]]
			for c: Array in corners:
				var lat := PI * float(c[0]) / rings - PI * 0.5
				var lon := TAU * float(c[1]) / around
				var n := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				tool.set_color(color)
				tool.set_normal(n)
				tool.add_vertex(at + Vector3(n.x, n.y * 1.25, n.z) * radius)


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var s := 1.0 - t
	return a * s * s * s + b * 3.0 * s * s * t + c * 3.0 * s * t * t + d * t * t * t


static func _flat(rng: RandomNumberGenerator, reach: float) -> Vector3:
	return Vector3(rng.randf_range(-reach, reach), 0.0, rng.randf_range(-reach, reach))
