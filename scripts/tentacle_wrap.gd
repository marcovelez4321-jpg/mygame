class_name TentacleWrap
extends MeshInstance3D

## The tentacle's grab (the user's, 2026-10-27: procedural tentacles wrap
## round what it holds, like Venom): tendrils burst out of the grabbed spot
## (the chest) and coil round the body -- up the torso to the neck, down each
## arm and leg -- each a tube spiralling round its chain of bones, growing out
## over GROW and writhing while it's held; let go, they draw back in and are
## gone. Every game draws its own (Enemy: held), in the symbiote's skin.

const CHAINS := [["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"],
		["LeftUpperArm", "LeftLowerArm", "LeftHand"], ["RightUpperArm", "RightLowerArm", "RightHand"],
		["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
## Round the torso this far out; round a limb this far.
const TORSO_RADIUS := 0.17
const LIMB_RADIUS := 0.09
const THICKNESS := 0.03
const TURNS_PER_METRE := 2.2
const GROW := 0.35
const WRITHE := 3.0
const SIDES := 5
const STEP := 0.05

var _skeleton: Skeleton3D
var _chains: Array = []
var _grow := 0.0
var _letting_go := false
var _time := 0.0
var _mesh := ImmediateMesh.new()

static var _material: Material


## Wrapped round `body`'s skeleton (an Enemy, held).
static func wrap(body: Node3D) -> TentacleWrap:
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var made := TentacleWrap.new()
	made._skeleton = skeletons[0] as Skeleton3D
	body.add_child(made)
	return made


## Let go: they draw back in, then it's gone.
func unwrap() -> void:
	_letting_go = true


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = PS1Look.material(GrappleTentacle.symbiote_texture(), Color.WHITE, true)
	for names: Array in CHAINS:
		var ids: Array[int] = []
		for bone_name: String in names:
			var id := _skeleton.find_bone(bone_name) if _skeleton else -1
			if id >= 0:
				ids.append(id)
		if ids.size() >= 2:
			_chains.append(ids)


func _process(delta: float) -> void:
	_time += delta
	_grow = move_toward(_grow, 0.0 if _letting_go else 1.0, delta / GROW)
	if _letting_go and _grow <= 0.0:
		queue_free()
		return
	_mesh.clear_surfaces()
	if not is_instance_valid(_skeleton) or _chains.is_empty():
		return
	var world := _skeleton.global_transform
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for c in _chains.size():
		var ids: Array = _chains[c]
		var points := PackedVector3Array()
		for id: int in ids:
			points.append(world * _skeleton.get_bone_global_pose(id).origin)
		_tendril(points, TORSO_RADIUS if c == 0 else LIMB_RADIUS, float(c) * 1.7)
	_mesh.surface_end()


## One tendril, spiralling down `points` (a chain of bones) as far as it's
## grown.
func _tendril(points: PackedVector3Array, radius: float, phase: float) -> void:
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	var reach := length * smoothstep(0.0, 1.0, _grow)
	var rings: Array[PackedVector3Array] = []
	var centres := PackedVector3Array()
	var s := 0.0
	while s <= reach:
		var along := _along(points, s)
		var at: Vector3 = along[0]
		var dir: Vector3 = along[1]
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		var turn := s * TURNS_PER_METRE * TAU + _time * WRITHE + phase
		var wobble := 1.0 + 0.15 * sin(_time * 5.0 + s * 9.0 + phase)
		var centre := at + (side * cos(turn) + up * sin(turn)) * radius * wobble
		var thick := THICKNESS * lerpf(1.0, 0.35, s / maxf(length, 0.01))
		rings.append(_ring(centre, dir, thick))
		centres.append(centre)
		s += STEP
	for r in rings.size() - 1:
		var a := rings[r]
		var b := rings[r + 1]
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for corner: Array in [[a[k], r, k], [b[k], r + 1, k], [b[k2], r + 1, k + 1],
					[a[k], r, k], [b[k2], r + 1, k + 1], [a[k2], r, k + 1]]:
				var point: Vector3 = corner[0]
				_mesh.surface_set_normal((point - centres[int(corner[1])]).normalized())
				_mesh.surface_set_uv(Vector2(float(corner[2]) / SIDES, float(corner[1]) * STEP * 2.0))
				_mesh.surface_add_vertex(point)


## The point `s` metres down the chain, and which way it runs there.
static func _along(points: PackedVector3Array, s: float) -> Array:
	for i in points.size() - 1:
		var piece := points[i].distance_to(points[i + 1])
		if s <= piece or i == points.size() - 2:
			var dir := (points[i + 1] - points[i]).normalized() if piece > 0.0001 else Vector3.DOWN
			return [points[i] + dir * minf(s, piece), dir]
		s -= piece
	return [points[0], Vector3.DOWN]


static func _ring(centre: Vector3, dir: Vector3, radius: float) -> PackedVector3Array:
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var ring := PackedVector3Array()
	for k in SIDES:
		var a := TAU * k / SIDES
		ring.append(centre + (side * cos(a) + up * sin(a)) * radius)
	return ring
