class_name OssuaryBones
extends RefCounted

## The Crawling Ossuary's legs, made from shapes (the user's, 2026-10-25:
## four very thick, sharp, spidery legs of bone carrying the building -- the
## building's a TrenchBroom map). Each bone merged into one mesh (bone and the
## sinew at its joints): a handful of draws for all four legs.

const BONE := Color(0.82, 0.76, 0.62)
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


## A leg's bone, `length` m along its Y (centred): a shaft `radius` thick at
## its top, `taper` of that at its bottom, a knob and sinew at its top joint;
## `sharp`: it ends in a point (the foot), else a knob.
static func leg_mesh(length: float, radius: float, taper: float, sharp: bool = false) -> ArrayMesh:
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius
	shaft.bottom_radius = radius * taper
	shaft.height = length
	shaft.radial_segments = 12
	shaft.rings = 1
	_add(bone, shaft, Transform3D.IDENTITY)
	_add(bone, _sphere(radius * 1.35), Transform3D(Basis.IDENTITY, Vector3.UP * length * 0.5))
	_add(flesh, _sphere(radius * 1.1), Transform3D(Basis.IDENTITY, Vector3.UP * (length * 0.5 + radius * 0.6)))
	if sharp:
		var point := CylinderMesh.new()
		point.top_radius = radius * taper
		point.bottom_radius = 0.0
		point.height = radius * 4.0
		point.radial_segments = 12
		point.rings = 1
		_add(bone, point, Transform3D(Basis.IDENTITY, Vector3.DOWN * (length * 0.5 + radius * 2.0)))
	else:
		_add(bone, _sphere(radius * taper * 1.3), Transform3D(Basis.IDENTITY, Vector3.DOWN * length * 0.5))
	var mesh := bone.commit()
	flesh.commit(mesh)
	mesh.surface_set_material(0, bone_material())
	mesh.surface_set_material(1, flesh_material())
	return mesh


## A piece from `a` to `b`: its Y along them, centred between.
static func between(a: Vector3, b: Vector3) -> Transform3D:
	var dir := (b - a).normalized()
	var basis := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	return Transform3D(basis, (a + b) * 0.5)


static func _add(tool: SurfaceTool, mesh: Mesh, xf: Transform3D) -> void:
	tool.append_from(mesh, 0, xf)


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh
