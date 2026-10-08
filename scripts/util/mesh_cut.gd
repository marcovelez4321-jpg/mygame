class_name MeshCut
extends RefCounted

## Cuts a skinned model down to one part of its body: only the triangles
## whose three corners are mostly (half their skin weight or more) on the
## bones you keep -- an arm, a leg, a spider's leg, a torso. Everything else
## on that mesh is dropped; unskinned meshes in the model are hidden. The
## same idea as Viewmodel._strip_to_arms(), for any bones.
##
## `thin` (optional) pulls each kept vertex toward the line of the bone it
## mostly hangs off (1 = as modelled, 0.5 = half as thick) -- how a spider's
## leg scaled up to 10 m stays a needle instead of a tree trunk.
##
## The cut meshes are made once per mesh + skin + bones + thinness and
## shared by every copy (_cache), so building a second Harvestman costs
## nothing.

static var _cache := {}


## The bone `root` and everything below it, as a set ({bone: true}).
static func subtree(skeleton: Skeleton3D, root: int) -> Dictionary:
	var bones := {}
	if root >= 0:
		_add(skeleton, root, bones)
	return bones


static func _add(skeleton: Skeleton3D, bone: int, into: Dictionary) -> void:
	into[bone] = true
	for child in skeleton.get_bone_children(bone):
		_add(skeleton, child, into)


## Cuts every skinned mesh of `model` (skinned to `skeleton`) down to
## `keep` ({bone: true}). False if nothing was left to show.
static func keep(model: Node, skeleton: Skeleton3D, keep_bones: Dictionary, thin: float = 1.0) -> bool:
	var keep_key := str(keep_bones.keys())
	var any := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.skin == null:
			mesh_instance.visible = false
			continue
		var key := "%d|%d|%s|%.3f" % [mesh_instance.mesh.get_instance_id(), mesh_instance.skin.get_instance_id(), keep_key, thin]
		var cut: Array = _cache.get(key, [])
		if cut.is_empty():
			cut = _cut(mesh_instance.mesh, mesh_instance.skin, skeleton, keep_bones, thin)
			_cache[key] = cut
		var mesh: ArrayMesh = cut[0]
		var kept_surfaces: PackedInt32Array = cut[1]
		if mesh.get_surface_count() == 0:
			mesh_instance.visible = false
			continue
		var overrides: Array[Material] = []
		for surface in kept_surfaces:
			overrides.append(mesh_instance.get_surface_override_material(surface))
		mesh_instance.mesh = mesh
		for i in overrides.size():
			mesh_instance.set_surface_override_material(i, overrides[i])
		any = true
	return any


## [the cut ArrayMesh, the original index of each surface it kept].
static func _cut(mesh: Mesh, skin: Skin, skeleton: Skeleton3D, keep_bones: Dictionary, thin: float) -> Array:
	# Skin bind slots -> skeleton bones (vertex bone indices are bind slots).
	var bind_bones := PackedInt32Array()
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		bind_bones.append(bone)
	var out := ArrayMesh.new()
	var kept_surfaces := PackedInt32Array()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones == null or weights == null or (bones as PackedInt32Array).is_empty():
			continue
		var per_vertex := (bones as PackedInt32Array).size() / vertices.size()
		var keep_vertex := PackedByteArray()
		keep_vertex.resize(vertices.size())
		for v in vertices.size():
			var on_kept := 0.0
			var heaviest := -1
			var heaviest_weight := 0.0
			for k in per_vertex:
				var bind: int = bones[v * per_vertex + k]
				var weight: float = weights[v * per_vertex + k]
				if bind >= 0 and bind < bind_bones.size() and keep_bones.has(bind_bones[bind]):
					on_kept += weight
				if weight > heaviest_weight:
					heaviest_weight = weight
					heaviest = bind
			keep_vertex[v] = 1 if on_kept >= 0.5 else 0
			if keep_vertex[v] and thin < 0.999 and heaviest >= 0 and heaviest < bind_bones.size():
				vertices[v] = _thinned(vertices[v], skin, skeleton, heaviest, bind_bones[heaviest], thin)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null or (indices as PackedInt32Array).is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var kept := PackedInt32Array()
		for i in range(0, (indices as PackedInt32Array).size() - 2, 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			if keep_vertex[a] and keep_vertex[b] and keep_vertex[c]:
				kept.append(a)
				kept.append(b)
				kept.append(c)
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags: int = int(mesh.surface_get_format(surface)) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(surface))
		kept_surfaces.append(surface)
	return [out, kept_surfaces]


## `vertex` (mesh space) pulled `thin` of the way toward the line its bone
## runs along (from the bone to its first child), worked out in the bone's
## own bind space.
static func _thinned(vertex: Vector3, skin: Skin, skeleton: Skeleton3D, bind: int, bone: int, thin: float) -> Vector3:
	if bone < 0:
		return vertex
	var to_bone := skin.get_bind_pose(bind)
	var local := to_bone * vertex
	var children := skeleton.get_bone_children(bone)
	var along := skeleton.get_bone_rest(children[0]).origin if not children.is_empty() else Vector3.ZERO
	var closest := Vector3.ZERO
	if along.length_squared() > 0.0000001:
		closest = along * clampf(local.dot(along) / along.length_squared(), 0.0, 1.0)
	var pulled := closest + (local - closest) * thin
	return to_bone.affine_inverse() * pulled
