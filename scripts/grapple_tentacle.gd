class_name GrappleTentacle
extends Node3D

## What you see of your OWN grapple (PlayerGrapple draws everyone else's as a
## plain line). Three looks, picked in the pause menu
## (GameSettings.tentacle_style):
##   SYMBIOTE: a wet, glossy black tentacle (Venom) whose tip splits into
##     little tendrils that grip the surface;
##   FLESH_WORM: a raw, ringed sewer worm, the leeches' and worm boss's skin;
##   SPIDER_HORDE: no rope at all -- hundreds of tiny spiders (the PSX spider)
##     clinging round each other in a living cable, always streaming out
##     toward the grabbed spot.
## It writhes while it flies out and pulls taut once it's stuck. Purely
## cosmetic and local (Rule 1). Built fresh every frame: one rope, a few
## hundred vertices, an ImmediateMesh (and a MultiMesh for the spiders).
## With the first-person arms (FirstPersonArms) it coils round the left
## forearm while you hold E and lashes out of that palm; without them it
## starts at PlayerGrapple.view_origin, the bottom-left of the screen. The
## symbiote and the coil go through the PS1 shader.

const SPIDER_MODEL := "res://NEWPSXMODELS/PSX Mega Pack/Models/Spider/Spider.fbx"
const WORM_TEXTURE := "res://art/props/PSX Creatures/Textures/tape_worm.png"
## Sides of the tube.
const SIDES := 6
## The bones the wrap coils along (EnemyRagdoll's: whichever it has), the
## torso first.
const WRAP_CHAINS := [["Hips", "Spine", "Spine1", "Spine2", "Chest", "UpperChest", "Neck", "Head"],
		["LeftUpperArm", "LeftLowerArm", "LeftHand"], ["RightUpperArm", "RightLowerArm", "RightHand"],
		["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
const WRAP_STEP := 0.05

@export_group("Shape")
## Rope points per meter (smoother, more vertices), and the most it uses.
@export var points_per_meter: float = 5.0
@export var max_points: int = 140
## Sideways wobble while it flies out (meters), and once it's pulled taut.
@export var writhe: float = 0.35
@export var writhe_taut: float = 0.04
## How fast the wobble settles once it's stuck.
@export var settle_speed: float = 1.5
@export var writhe_speed: float = 10.0
## Wobble waves along the whole rope.
@export var waves: float = 2.5

@export_group("Symbiote")
@export var symbiote_radius: float = 0.045
## Gripping tendrils its tip splits into, and how long they are.
@export var tendrils: int = 5
@export var tendril_length: float = 0.7
@export var symbiote_color: Color = Color(0.015, 0.015, 0.02)
## The coil round your forearm: how far out from the arm's middle it wraps,
## how many turns from elbow to wrist, how thick it is (x symbiote_radius),
## and how fast it slowly crawls round the arm.
@export var coil_radius: float = 0.05
@export var coil_turns: float = 3.5
@export var coil_thickness: float = 0.7
@export var coil_crawl_speed: float = 0.6
## Holding an enemy (the user's, 2026-10-27: the strands off the main
## tentacle are what wrap it): the tip's tendrils run from where it holds it
## and coil round its bones instead -- up its torso, down each arm and leg
## (its ragdoll's: WRAP_CHAINS) -- this far out round the torso and a limb,
## this many turns a metre, growing out over wrap_grow_time and writhing.
@export var wrap_torso_radius: float = 0.17
@export var wrap_limb_radius: float = 0.09
@export var wrap_turns_per_meter: float = 2.2
@export var wrap_grow_time: float = 0.35
@export var wrap_writhe: float = 3.0

@export_group("Flesh Worm")
@export var worm_radius: float = 0.06
## Bulging rings per meter.
@export var worm_rings_per_meter: float = 1.5
## How many times the worm texture repeats per meter along it.
@export var worm_texture_per_meter: float = 1.2
@export var worm_tint: Color = Color(1.0, 0.82, 0.82)

@export_group("Spider Horde")
@export var spiders_per_meter: float = 18.0
@export var max_spiders: int = 600
## Size of one spider (meters, its longest side).
@export var spider_size: float = 0.08
## How far round the rope's middle they cling.
@export var horde_radius: float = 0.07
## How fast they stream out toward the grabbed spot, m/s.
@export var spider_flow: float = 5.0
## Turns every spider round its up axis, in case the model faces the wrong way.
@export var spider_turn_degrees: float = 0.0

static var _spider_mesh: Mesh
static var _spider_material: Material
static var _spider_scale := 1.0

var _time := 0.0
var _wobble := 0.0
var _was_showing := false
var _points := PackedVector3Array()
var _tube: MeshInstance3D
var _immediate: ImmediateMesh
var _horde: MultiMeshInstance3D
var _symbiote_material: ShaderMaterial
var _worm_material: StandardMaterial3D
var _coil_points := PackedVector3Array()
var _wrap_grow := 0.0


func _ready() -> void:
	top_level = true # works in world space
	global_transform = Transform3D.IDENTITY
	_immediate = ImmediateMesh.new()
	_tube = MeshInstance3D.new()
	_tube.mesh = _immediate
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tube)

	# PS1 look: through the PS1 shader (vertex snap, per-vertex lighting) with
	# a tiny nearest-filtered texture.
	_symbiote_material = PS1Look.material(symbiote_texture(), Color.WHITE, true)

	_worm_material = StandardMaterial3D.new()
	_worm_material.albedo_texture = load(WORM_TEXTURE) as Texture2D
	_worm_material.albedo_color = worm_tint
	_worm_material.roughness = 0.35
	_worm_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Called every frame by PlayerGrapple. `stuck` = it has hold of something
## (pulled taut); `normal` = the grabbed surface's facing. `arm` = the left
## arm's [elbow, wrist, palm, finger direction] (empty while it's down) and
## `coil` how much of it is wrapped round the forearm (0..1).
## `path`: a shape of its own to draw (the whip's), with no writhe on top.
## `held`: the enemy it's holding (its tendrils wrap it), or null.
func show_rope(showing: bool, start: Vector3, tip: Vector3, normal: Vector3, stuck: bool, arm: Array[Vector3], coil: float, delta: float,
		path: PackedVector3Array = PackedVector3Array(), held: Enemy = null) -> void:
	_time += delta
	var ragdoll := held.get(&"_ragdoll") as EnemyRagdoll if is_instance_valid(held) else null
	_wrap_grow = move_toward(_wrap_grow, 1.0, delta / wrap_grow_time) if ragdoll and showing else 0.0
	_immediate.clear_surfaces()
	if _horde:
		_horde.visible = false
	var length := start.distance_to(tip)
	var rope := showing and length >= 0.05
	if not rope:
		_was_showing = false
	else:
		if not _was_showing:
			_wobble = writhe # each new lash starts out writhing
		_was_showing = true
		_wobble = move_toward(_wobble, writhe_taut if stuck else writhe, settle_speed * delta * writhe)
		if path.size() >= 2:
			_points = path
		else:
			_build_curve(start, tip, length)
	var coiled := arm.size() == 4 and coil > 0.01
	if coiled:
		_build_coil(arm, coil)
	if not rope and not coiled:
		return

	match GameSettings.tentacle_style:
		GameSettings.TentacleStyle.SYMBIOTE:
			_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _symbiote_material)
			if coiled:
				_tube_along(_coil_points, _coil_radius_at, 0.0)
			if rope:
				_tube_along(_points, _symbiote_radius.bind(length), length * 2.0)
				if ragdoll:
					_draw_wrap(tip, ragdoll)
				elif stuck:
					_draw_tendrils(tip, normal, start)
			_immediate.surface_end()
		GameSettings.TentacleStyle.FLESH_WORM:
			_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _worm_material)
			if coiled:
				_tube_along(_coil_points, _coil_radius_at, 0.0)
			if rope:
				_tube_along(_points, _worm_radius.bind(length), length * worm_texture_per_meter)
			_immediate.surface_end()
		GameSettings.TentacleStyle.SPIDER_HORDE:
			if rope:
				_draw_horde(length)


## The coil: slides down out of the elbow and winds round the forearm toward
## the wrist (as far as `coil` says), slowly crawling round it; fully wound,
## it runs on into the palm, where the lash comes out.
func _build_coil(arm: Array[Vector3], coil: float) -> void:
	var elbow := arm[0]
	var wrist := arm[1]
	var palm := arm[2]
	var axis := wrist - elbow
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis.normalized())
	var steps := maxi(int(28.0 * coil), 3)
	_coil_points.resize(0)
	for i in steps + 1:
		var u := coil * i / steps
		var angle := u * coil_turns * TAU + _time * coil_crawl_speed
		var around := (side * cos(angle) + up * sin(angle)) * coil_radius
		_coil_points.append(elbow + axis * u + around)
	if coil > 0.95:
		_coil_points.append(wrist.lerp(palm, 0.5))
		_coil_points.append(palm + arm[3] * 0.06)


func _coil_radius_at(s: float) -> float:
	return symbiote_radius * coil_thickness * lerpf(1.0, 0.7, s)


## A tiny 8 x 16 texture (nearest-filtered by the PS1 shader): wet black with
## a lighter sheen streak down one side and a few glints, so the vertex-lit
## tube still reads as glossy.
## Shared (made once): the grapple's and Seeded Growth's.
static var _shared_texture: Texture2D
const SYMBIOTE_SHADE := Color(0.015, 0.015, 0.02)


static func symbiote_texture() -> Texture2D:
	if _shared_texture:
		return _shared_texture
	var image := Image.create(8, 16, false, Image.FORMAT_RGB8)
	var shade := SYMBIOTE_SHADE
	for y in 16:
		for x in 8:
			var sheen := 0.09 if x == 2 else (0.04 if x == 1 or x == 3 else 0.0)
			var glint := 0.12 if (x * 7 + y * 3) % 11 == 0 else 0.0
			var value := shade.r + sheen + glint
			image.set_pixel(x, y, Color(value, value, value * 1.15))
	_shared_texture = ImageTexture.create_from_image(image)
	return _shared_texture


## The rope's centre line, start to tip, writhing side to side (most in the
## middle, pinned at both ends).
func _build_curve(start: Vector3, tip: Vector3, length: float) -> void:
	var count := clampi(int(length * points_per_meter), 10, max_points)
	_points.resize(count + 1)
	var along := (tip - start) / length
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(along).normalized()
	var amount := _wobble * clampf(length / 6.0, 0.2, 1.0)
	for i in count + 1:
		var s := float(i) / count
		var pinned := sin(s * PI)
		var wave := s * waves * TAU - _time * writhe_speed
		var offset := side * sin(wave) * amount + up * cos(wave * 0.7 + 1.3) * amount * 0.6
		_points[i] = start.lerp(tip, s) + offset * pinned


## A tube round `points`. `radius_at(s)` gives the radius 0..1 along it;
## `v_length` is how far the texture runs along it (0 = untextured).
func _tube_along(points: PackedVector3Array, radius_at: Callable, v_length: float) -> void:
	var count := points.size()
	if count < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var reference := Vector3.UP
	for i in count:
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var n := tangent.cross(reference)
		if n.length_squared() < 0.001:
			n = tangent.cross(Vector3.RIGHT)
		n = n.normalized()
		reference = n.cross(tangent) # carried along so the tube doesn't twist
		var b := tangent.cross(n)
		var radius: float = radius_at.call(float(i) / (count - 1))
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in SIDES + 1:
			var angle := TAU * k / SIDES
			var out := n * cos(angle) + b * sin(angle)
			ring.append(points[i] + out * radius)
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	for i in count - 1:
		var v0 := v_length * i / (count - 1)
		var v1 := v_length * (i + 1) / (count - 1)
		for k in SIDES:
			var u0 := float(k) / SIDES
			var u1 := float(k + 1) / SIDES
			_vertex(rings[i][k], normals[i][k], Vector2(u0, v0))
			_vertex(rings[i + 1][k], normals[i + 1][k], Vector2(u0, v1))
			_vertex(rings[i + 1][k + 1], normals[i + 1][k + 1], Vector2(u1, v1))
			_vertex(rings[i][k], normals[i][k], Vector2(u0, v0))
			_vertex(rings[i + 1][k + 1], normals[i + 1][k + 1], Vector2(u1, v1))
			_vertex(rings[i][k + 1], normals[i][k + 1], Vector2(u1, v0))


func _vertex(point: Vector3, normal: Vector3, uv: Vector2) -> void:
	_immediate.surface_set_normal(normal)
	_immediate.surface_set_uv(uv)
	_immediate.surface_add_vertex(point)


## The symbiote's tip splitting into tendrils that spread out over the
## grabbed surface and slowly flex, like fingers holding on.
func _draw_tendrils(tip: Vector3, normal: Vector3, start: Vector3) -> void:
	var flat := (tip - start).slide(normal)
	if flat.length_squared() < 0.001:
		flat = normal.cross(Vector3.RIGHT)
	flat = flat.normalized()
	for t in tendrils:
		var direction := flat.rotated(normal, TAU * t / tendrils + 0.4 * sin(_time * 1.3 + t))
		var strand := PackedVector3Array()
		for i in 7:
			var u := i / 6.0
			var lift := sin(u * PI) * 0.12 * (0.6 + 0.4 * sin(_time * 3.0 + t * 1.7))
			strand.append(tip + direction * u * tendril_length + normal * (0.02 + lift))
		_tube_along(strand, _tendril_radius, 0.0)


## Holding an enemy: the tendrils off the tip, each running from it to the
## start of one of the body's chains of bones and coiling on along it (as
## far as they've grown), drawn on its ragdoll's bones where they are now.
func _draw_wrap(tip: Vector3, ragdoll: EnemyRagdoll) -> void:
	var grown := smoothstep(0.0, 1.0, _wrap_grow)
	for c in WRAP_CHAINS.size():
		var chain := PackedVector3Array()
		for bone_name: String in WRAP_CHAINS[c]:
			var bone := ragdoll.bone_named(bone_name)
			if bone:
				chain.append(bone.global_position)
		if chain.size() < 2:
			continue
		var strand := _wrap_strand(tip, chain, wrap_torso_radius if c == 0 else wrap_limb_radius, float(c) * 1.7, grown)
		_tube_along(strand, _wrap_radius, 0.0)


## One tendril: from the tip to the chain's first bone, then spiralling round
## the chain, `grown` (0..1) of the way along it all.
func _wrap_strand(tip: Vector3, chain: PackedVector3Array, radius: float, phase: float, grown: float) -> PackedVector3Array:
	var length := 0.0
	for i in chain.size() - 1:
		length += chain[i].distance_to(chain[i + 1])
	var first := _coil_point(chain, 0.0, radius, phase)
	var bridge := tip.distance_to(first)
	var reach := (bridge + length) * grown
	var strand := PackedVector3Array([tip])
	# Across from the tip to the chain.
	var steps := maxi(int(bridge / WRAP_STEP), 1)
	for i in range(1, steps + 1):
		var d := bridge * i / steps
		if d > reach:
			strand.append(tip.lerp(first, reach / maxf(bridge, 0.001)))
			return strand
		strand.append(tip.lerp(first, float(i) / steps))
	# Round and on along it.
	var s := WRAP_STEP
	while s <= minf(reach - bridge, length):
		strand.append(_coil_point(chain, s, radius, phase))
		s += WRAP_STEP
	return strand


## The point `s` metres along `chain`, coiled round it, writhing.
func _coil_point(chain: PackedVector3Array, s: float, radius: float, phase: float) -> Vector3:
	var at := chain[chain.size() - 1]
	var dir := Vector3.DOWN
	var left := s
	for i in chain.size() - 1:
		var piece := chain[i].distance_to(chain[i + 1])
		if left <= piece or i == chain.size() - 2:
			dir = (chain[i + 1] - chain[i]) / piece if piece > 0.0001 else Vector3.DOWN
			at = chain[i] + dir * minf(left, piece)
			break
		left -= piece
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var turn := s * wrap_turns_per_meter * TAU + _time * wrap_writhe + phase
	var wobble := 1.0 + 0.15 * sin(_time * 5.0 + s * 9.0 + phase)
	return at + (side * cos(turn) + up * sin(turn)) * radius * wobble


func _wrap_radius(s: float) -> float:
	return symbiote_radius * 0.6 * (1.0 - s * 0.6)


## Radius along the symbiote (s = 0 at your hand, 1 at the tip): tapering,
## with slow pulses running along it.
func _symbiote_radius(s: float, length: float) -> float:
	return symbiote_radius * lerpf(1.0, 0.5, s) * (1.0 + 0.18 * sin(s * length * 3.0 - _time * 5.0))


func _tendril_radius(s: float) -> float:
	return symbiote_radius * 0.45 * (1.0 - s * 0.85)


## Radius along the worm: tapering, bulging out in rings.
func _worm_radius(s: float, length: float) -> float:
	var ring := absf(sin(s * length * worm_rings_per_meter * PI))
	return worm_radius * lerpf(1.0, 0.65, s) * (0.8 + 0.3 * ring)


## The horde: spiders spread round and along the rope, each crawling toward
## the tip and wrapping back to the start.
func _draw_horde(length: float) -> void:
	if not _ensure_horde():
		return
	var count := clampi(int(length * spiders_per_meter), 20, max_spiders)
	var multimesh := _horde.multimesh
	multimesh.visible_instance_count = count
	var last := _points.size() - 1
	var turn := Basis(Vector3.UP, deg_to_rad(spider_turn_degrees))
	for k in count:
		var phase := fmod(k * 0.6180339 + _time * spider_flow / length, 1.0)
		var at := phase * last
		var i := mini(int(at), last - 1)
		var center := _points[i].lerp(_points[i + 1], at - i)
		var tangent := (_points[i + 1] - _points[i]).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(tangent)
		var angle := k * 2.3999632 + _time * 0.7
		var radial := side * cos(angle) + up * sin(angle)
		var spread := horde_radius * (0.4 + 0.6 * fmod(k * 0.381966, 1.0))
		var facing := Basis.looking_at(tangent, radial) * turn
		multimesh.set_instance_transform(k, Transform3D(facing.scaled(Vector3.ONE * _spider_scale), center + radial * spread))
	_horde.visible = true


func _ensure_horde() -> bool:
	if _horde:
		return true
	if _spider_mesh == null:
		var scene := load(SPIDER_MODEL) as PackedScene
		if scene == null:
			return false
		var model := scene.instantiate()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			model.free()
			return false
		var source := meshes[0] as MeshInstance3D
		_spider_mesh = source.mesh
		_spider_material = source.get_active_material(0)
		var size := _spider_mesh.get_aabb().size
		_spider_scale = spider_size / maxf(maxf(size.x, size.y), maxf(size.z, 0.001))
		model.free()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _spider_mesh
	multimesh.instance_count = max_spiders
	multimesh.visible_instance_count = 0
	_horde = MultiMeshInstance3D.new()
	_horde.multimesh = multimesh
	_horde.material_override = _spider_material
	_horde.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_horde)
	return true
