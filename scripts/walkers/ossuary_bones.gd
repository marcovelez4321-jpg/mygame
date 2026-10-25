class_name OssuaryBones
extends RefCounted

## The Crawling Ossuary's body, made from shapes (the user's, 2026-10-25: all
## bone and flesh; the building on its back is a TrenchBroom map): a spine of
## giant vertebrae under rib arches rising over it like a vaulted roof (the
## deck for the cathedral-crypt along the top), a skull at the head, and the
## legs' long bones. Its own space: the spine's middle at the origin, the
## head toward -Z. Merged into a few meshes (bone, flesh) so the whole body is
## a handful of draws; its collision a set of simple shapes.

const LENGTH := 1500.0
## Vertebrae from just behind the skull to the tail, this far apart.
const VERTEBRA_FROM := -620.0
const VERTEBRA_GAP := 50.0
const VERTEBRA_COUNT := 28
const CENTRUM_RADIUS := 16.0
## Rib arches over the spine: from RIB_FROM back, RIB_GAP apart; each rises
## from RIB_FOOT (beside and below the spine: on the ground when it rests
## belly-down) over the top to RIB_TOP.
const RIB_FROM := -560.0
const RIB_GAP := 50.0
const RIB_COUNT := 25
const RIB_WIDTH := 72.0
const RIB_FOOT := -14.0
const RIB_TOP := 80.0
const RIB_RADIUS := 4.5
const RIB_PIECES := 10
## The deck along the vault's top, where the cathedral-crypt stands.
const DECK := Vector3(120.0, 4.0, 330.0)
const DECK_Y := 84.0
const SKULL_AT := Vector3(0.0, 20.0, -690.0)
const SKULL_RADIUS := 72.0
const BONE := Color(0.82, 0.76, 0.62)
const BONE_DARK := Color(0.55, 0.48, 0.38)
const FLESH := Color(0.42, 0.07, 0.07)

static var _bone_material: StandardMaterial3D
static var _flesh_material: StandardMaterial3D


static func bone_material() -> StandardMaterial3D:
	if _bone_material == null:
		_bone_material = StandardMaterial3D.new()
		_bone_material.albedo_color = BONE
		_bone_material.roughness = 0.9
	return _bone_material


static func flesh_material() -> StandardMaterial3D:
	if _flesh_material == null:
		_flesh_material = StandardMaterial3D.new()
		_flesh_material.albedo_color = FLESH
		_flesh_material.roughness = 0.6
		_flesh_material.metallic_specular = 0.7
	return _flesh_material


## The rib arch's points (x, y) from one foot over the top to the other.
static func rib_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in RIB_PIECES + 1:
		var a := PI * float(i) / RIB_PIECES
		var x := -cos(a) * RIB_WIDTH
		var y := RIB_FOOT + sin(a) * (RIB_TOP - RIB_FOOT)
		points.append(Vector2(x, y))
	return points


## The body (spine, ribs, deck, skull) as one mesh: a bone surface, a flesh one.
static func body_mesh() -> ArrayMesh:
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := Basis(Vector3.RIGHT, PI * 0.5) # a cylinder's Y onto Z
	for i in VERTEBRA_COUNT:
		var z := VERTEBRA_FROM + i * VERTEBRA_GAP
		var taper := 1.0 - clampf((z - 300.0) / 500.0, 0.0, 0.6) # (thinning to the tail)
		_add(bone, _cylinder(CENTRUM_RADIUS * taper, 36.0), Transform3D(along, Vector3(0.0, 0.0, z)))
		_add(flesh, _cylinder(CENTRUM_RADIUS * 0.8 * taper, 16.0), Transform3D(along, Vector3(0.0, 0.0, z + 25.0)))
		_add(bone, _box(Vector3(6.0, 34.0, 14.0) * taper), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0.0, 28.0 * taper, z + 4.0)))
		for side: float in [-1.0, 1.0]:
			_add(bone, _box(Vector3(36.0, 6.0, 10.0) * taper), Transform3D(Basis.IDENTITY, Vector3(side * 28.0 * taper, 2.0, z)))
	var points := rib_points()
	for r in RIB_COUNT:
		var z := RIB_FROM + r * RIB_GAP
		for i in points.size() - 1:
			var a := Vector3(points[i].x, points[i].y, z)
			var b := Vector3(points[i + 1].x, points[i + 1].y, z)
			_add(bone, _cylinder(RIB_RADIUS, a.distance_to(b) + RIB_RADIUS), _between(a, b))
		for foot: int in [0, points.size() - 1]:
			_add(flesh, _sphere(RIB_RADIUS * 1.6), Transform3D(Basis.IDENTITY, Vector3(points[foot].x, points[foot].y, z)))
	# The deck: bone plates across the vault's top.
	_add(bone, _box(DECK), Transform3D(Basis.IDENTITY, Vector3(0.0, DECK_Y, 0.0)))
	# The skull: a long cranium, its eye holes dark, a jaw, teeth.
	_add(bone, _sphere(SKULL_RADIUS), Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 1.35)), SKULL_AT))
	for side: float in [-1.0, 1.0]:
		_add(flesh, _sphere(16.0), Transform3D(Basis.IDENTITY, SKULL_AT + Vector3(side * 30.0, 14.0, -82.0)))
	_add(bone, _box(Vector3(90.0, 24.0, 90.0)), Transform3D(Basis(Vector3.RIGHT, 0.2), SKULL_AT + Vector3(0.0, -52.0, -40.0)))
	for t in 10:
		_add(bone, _box(Vector3(6.0, 14.0, 6.0)), Transform3D(Basis.IDENTITY, SKULL_AT + Vector3(-36.0 + t * 8.0, -34.0, -88.0)))
	var mesh := bone.commit()
	flesh.commit(mesh)
	mesh.surface_set_material(0, bone_material())
	mesh.surface_set_material(1, flesh_material())
	return mesh


## The body's collision: [{shape, xf}], in its own space.
static func body_shapes() -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	for i in VERTEBRA_COUNT:
		var z := VERTEBRA_FROM + i * VERTEBRA_GAP
		var capsule := CapsuleShape3D.new()
		capsule.radius = CENTRUM_RADIUS
		capsule.height = VERTEBRA_GAP + CENTRUM_RADIUS
		shapes.append({shape = capsule, xf = Transform3D(along, Vector3(0.0, 0.0, z))})
	var points := rib_points()
	for r in RIB_COUNT:
		var z := RIB_FROM + r * RIB_GAP
		for i in points.size() - 1:
			var a := Vector3(points[i].x, points[i].y, z)
			var b := Vector3(points[i + 1].x, points[i + 1].y, z)
			var piece := CapsuleShape3D.new()
			piece.radius = RIB_RADIUS
			piece.height = a.distance_to(b) + RIB_RADIUS * 2.0
			shapes.append({shape = piece, xf = _between(a, b)})
	var deck := BoxShape3D.new()
	deck.size = DECK
	shapes.append({shape = deck, xf = Transform3D(Basis.IDENTITY, Vector3(0.0, DECK_Y, 0.0))})
	var skull := SphereShape3D.new()
	skull.radius = SKULL_RADIUS * 0.9
	shapes.append({shape = skull, xf = Transform3D(Basis.IDENTITY, SKULL_AT)})
	return shapes


## A leg's long bone, `length` m along its Y (centred), knobbed at both
## ends, sinew at the joints; `taper`: the far end's share (a tibia narrows
## to a claw).
static func leg_mesh(length: float, radius: float, taper: float) -> ArrayMesh:
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius
	shaft.bottom_radius = radius * taper
	shaft.height = length
	shaft.radial_segments = 10
	shaft.rings = 1
	_add(bone, shaft, Transform3D.IDENTITY)
	_add(bone, _sphere(radius * 1.6), Transform3D(Basis.IDENTITY, Vector3.UP * length * 0.5))
	_add(flesh, _sphere(radius * 1.2), Transform3D(Basis.IDENTITY, Vector3.UP * (length * 0.5 + radius * 0.8)))
	if taper < 0.5:
		var claw := CylinderMesh.new()
		claw.top_radius = radius * taper
		claw.bottom_radius = 0.0
		claw.height = radius * 3.0
		claw.radial_segments = 8
		claw.rings = 1
		_add(bone, claw, Transform3D(Basis.IDENTITY, Vector3.DOWN * (length * 0.5 + radius * 1.5)))
	else:
		_add(bone, _sphere(radius * 1.4), Transform3D(Basis.IDENTITY, Vector3.DOWN * length * 0.5))
	var mesh := bone.commit()
	flesh.commit(mesh)
	mesh.surface_set_material(0, bone_material())
	mesh.surface_set_material(1, flesh_material())
	return mesh


## A piece from `a` to `b`: its Y along them, centred between.
static func _between(a: Vector3, b: Vector3) -> Transform3D:
	var dir := (b - a).normalized()
	var basis := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	return Transform3D(basis, (a + b) * 0.5)


static func _add(tool: SurfaceTool, mesh: Mesh, xf: Transform3D) -> void:
	tool.append_from(mesh, 0, xf)


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
