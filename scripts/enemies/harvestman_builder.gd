class_name HarvestmanBuilder
extends RefCounted

## Puts a Harvestman's model together out of the asset packs -- a Frankenstein
## job, like the worm boss -- for tools/bake_harvestmen.gd to save as a scene
## (scenes/enemy/harvestman/models/), which you can then open and change by
## hand. The Harvestman (harvestman.gd) loads that scene; nothing here runs in
## the game.
##
## The model:
##   HarvestmanModel
##     Body                  the middle of the body (the sack); everything hangs off it
##       Core                HarvestmanCore: the sack (barnacle / coiled Deepmaw / fused torsos)
##       Face                the unrigged PSX spider, hung under the front of the sack:
##         Eyes              its eye cluster, glowing
##         Searchlight       a SpotLight3D out of the eyes
##         Mouth             where the hose and the feeding tube come out
##       Limbs               3-4 JiggleLimbs: civilian arms/legs hanging out of it
##       Legs                Leg0..Leg2, each at its hip:
##         (spider legs)     the enemy spider's back leg, cut out (MeshCut),
##                           stretched to leg_length and slimmed (leg_thinness)
##         (leech legs)      a barnacle lump for the knee (the leech-segment legs
##                           are drawn in game, along the IK)

const SPIDER_MODEL := "res://NEWPSXMODELS/PSX Mega Pack/Models/Spider/Spider.fbx"
const FACE_MODEL := "res://art/Spider(no-rigged).fbx"
const BARNACLE_MODEL := "res://art/props/PSX Creatures/Models/FBX/barnacle.fbx"
const BARNACLE_TEXTURE := "res://art/props/PSX Creatures/Textures/barnacle.png"
const DEEPMAW_MODEL := "res://art/DEEPMAW- Retro psx  monster/DEEPMAW.fbx"
## Which of the spider's legs gets stretched into a Harvestman's: its back
## leg, the longest.
const SPIDER_LEG := "BL"
## The three legs, degrees round the body from its front: two forward, one back.
const LEG_ANGLES := [60.0, 180.0, 300.0]


class Settings:
	var core := HarvestmanCore.Kind.BARNACLE
	var leech_legs := false
	## The sack across (m), and how long each leg is laid out straight.
	var core_size := 3.6
	var leg_length := 11.0
	## How much thinner than the spider's own (scaled up) the legs are.
	var leg_thinness := 0.45
	var limb_count := 4
	var torso_count := 5
	var seed := 1


static func civilians() -> PackedStringArray:
	var paths := PackedStringArray()
	for i in range(1, 17):
		paths.append("res://art/characters/Characters_psx/Models/Male/Character_%02d.fbx" % i)
		paths.append("res://art/characters/Characters_psx/Models/Female/Character_Female_%02d.fbx" % i)
	for i in range(29, 33):
		paths.append("res://art/characters/Characters_psx/Models/Male/Character_%02d.fbx" % i)
	return paths


## Builds a model under `parent` (it has to be in the tree: the parts are
## measured where they end up).
static func build(settings: Settings, parent: Node) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed
	var root := Node3D.new()
	root.name = "HarvestmanModel"
	parent.add_child(root)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var core_radius := settings.core_size * 0.5

	var core := HarvestmanCore.new()
	core.name = "Core"
	core.kind = settings.core
	body.add_child(core)
	match settings.core:
		HarvestmanCore.Kind.BARNACLE:
			_barnacle(core, settings.core_size, Color(0.78, 0.82, 0.55), true)
		HarvestmanCore.Kind.DEEPMAW:
			_deepmaw_coil(core, settings.core_size)
		HarvestmanCore.Kind.FUSED:
			_fused(core, settings, rng)

	# The core's real surface (whatever shape it came out), so the limbs and
	# legs can start right on it.
	var surface := surface_points(core, body)

	_face(body, core_radius)

	var limbs := Node3D.new()
	limbs.name = "Limbs"
	body.add_child(limbs)
	var people := civilians()
	var made := 0
	var tries := 0
	while made < settings.limb_count and tries < settings.limb_count * 4:
		tries += 1
		var character := load(people[rng.randi() % people.size()]) as PackedScene
		if character == null:
			continue
		var limb := JiggleLimb.new()
		limb.name = "Limb%d" % made
		limbs.add_child(limb)
		# Out of the lower half of the sack, all the way round.
		var around := rng.randf() * TAU
		var down := rng.randf_range(-0.85, 0.15)
		var out := Vector3(sin(around) * sqrt(1.0 - down * down), down, cos(around) * sqrt(1.0 - down * down)).normalized()
		# On the surface, sunk in a little so it grows out of the flesh.
		limb.position = surface_at(surface, out, core_radius) - out * 0.15
		limb.basis = Basis.looking_at(out, Vector3.UP if absf(out.y) < 0.95 else Vector3.FORWARD)
		var is_leg := rng.randf() < 0.4
		if limb.build(character, "Left" if rng.randf() < 0.5 else "Right", is_leg, 1.9 if is_leg else 1.5):
			made += 1
		else:
			limb.free()

	var legs := Node3D.new()
	legs.name = "Legs"
	body.add_child(legs)
	for i in LEG_ANGLES.size():
		var angle := deg_to_rad(LEG_ANGLES[i])
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		legs.add_child(leg)
		# Hips on the surface round the top half of the sack (sunk in a
		# little), so the legs rise out of it and arch over before coming down.
		var hip_dir := Vector3(sin(angle), 0.45, -cos(angle)).normalized()
		leg.position = surface_at(surface, hip_dir, core_radius) - hip_dir * 0.2
		if settings.leech_legs:
			_barnacle(leg, 1.1, Color(0.6, 0.45, 0.45), false).name = "Knee"
		else:
			_spider_leg(leg, angle, settings)
	return root


## Every node under `root` saved with it (and imported models as plain nodes,
## not links to their files), ready for PackedScene.pack().
static func claim(root: Node) -> void:
	for node in root.find_children("*", "", true, false):
		# The character models all call their skeleton "%GeneralSkeleton",
		# which can only be unique once per scene: not needed here.
		node.unique_name_in_owner = false
		node.owner = root
		if node != root and not node.scene_file_path.is_empty():
			node.scene_file_path = ""


# ---- Parts ------------------------------------------------------------------

## A barnacle `size` across, tinted `tint`, under `parent`; upside down
## (mouth hanging) when `hang`.
static func _barnacle(parent: Node3D, size: float, tint: Color, hang: bool) -> Node3D:
	var model := (load(BARNACLE_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Barnacle"
	parent.add_child(model)
	var bounds := _bounds(model)
	var across := maxf(maxf(bounds.size.x, bounds.size.z), 0.0001)
	var turn := Basis(Vector3.RIGHT, PI) if hang else Basis.IDENTITY
	var shape := turn.scaled(Vector3.ONE * size / across)
	model.transform = Transform3D(shape, -(shape * bounds.get_center()))
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(BARNACLE_TEXTURE)
	material.albedo_color = tint
	material.roughness = 0.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for mesh in _meshes(model):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


## A Deepmaw curled round into a ball `size` across: its spine bones laid on
## a coil and that written into the skeleton's rest pose (and pose), so the
## saved scene shows the coil.
static func _deepmaw_coil(core: HarvestmanCore, size: float) -> void:
	var model := (load(DEEPMAW_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Deepmaw"
	core.add_child(model)
	_drop_animators(model)
	var skeleton := _skeleton(model)
	if skeleton == null:
		return
	var chain := PackedInt32Array()
	var bone := skeleton.find_bone("Bone")
	while bone != -1:
		chain.append(bone)
		var children := skeleton.get_bone_children(bone)
		bone = children[0] if not children.is_empty() else -1
	if chain.size() < 3:
		return
	# The spine at rest, in the skeleton's space.
	var joints := PackedVector3Array()
	for b in chain:
		joints.append(skeleton.get_bone_global_rest(b).origin)
	var last := skeleton.get_bone_global_rest(chain[-1])
	var before := joints[-1] - joints[-2]
	joints.append(last.origin + before)
	var total := 0.0
	for i in joints.size() - 1:
		total += joints[i].distance_to(joints[i + 1])
	var along := (joints[-1] - joints[0]).normalized()
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var axis := along.cross(side).normalized()
	# A coil 1.15 turns round, stepping sideways a little each turn so it
	# doesn't run through itself.
	var turns := 1.15
	var radius := total / (TAU * turns)
	var coil := PackedVector3Array()
	var run := 0.0
	for i in joints.size():
		if i > 0:
			run += joints[i - 1].distance_to(joints[i])
		var angle := run / radius
		coil.append(joints[0] + (along * sin(angle) + side * (1.0 - cos(angle))) * radius + axis * (angle / TAU) * radius * 0.7)
	# Turn each bone onto its new direction, root to tip, and keep that as
	# its rest (and pose).
	var parent_bone := skeleton.get_bone_parent(chain[0])
	var parent := skeleton.get_bone_global_rest(parent_bone) if parent_bone >= 0 else Transform3D.IDENTITY
	for i in chain.size():
		var rest := skeleton.get_bone_rest(chain[i])
		var current := parent * rest
		var child_offset := current.basis.inverse() * (joints[i + 1] - joints[i]) if i + 1 < joints.size() else Vector3.ZERO
		var was := current.basis * child_offset
		var wants := coil[i + 1] - current.origin
		var turned := current.basis
		if was.length_squared() > 0.0000001 and wants.length_squared() > 0.0000001:
			turned = Basis(Quaternion(was.normalized(), wants.normalized())) * current.basis
		var local := Transform3D(parent.basis.inverse() * turned, rest.origin)
		skeleton.set_bone_rest(chain[i], local)
		skeleton.set_bone_pose_rotation(chain[i], local.basis.get_rotation_quaternion())
		parent = Transform3D(turned, current.origin)
	core.set_meta("coil_axis", axis)
	# Size it from the coil itself (the mesh's own box is still the straight
	# worm): `size` across, centred on the core.
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	var middle := Vector3.ZERO
	for point in coil:
		middle += to_model * point
	middle /= coil.size()
	var reach := 0.0
	for point in coil:
		reach = maxf(reach, (to_model * point).distance_to(middle))
	var across := maxf(reach * 2.0 + radius * to_model.basis.get_scale().x * 0.8, 0.0001)
	var scale_by := size / across
	model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_by), -middle * scale_by)
	for mesh in _meshes(model):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Civilian torsos (head, neck, chest -- no arms or legs: those are the
## dangling limbs) fused into a ball round a dark fleshy middle, each pointing
## out a different way, heads lolling outward.
static func _fused(core: HarvestmanCore, settings: Settings, rng: RandomNumberGenerator) -> void:
	_barnacle(core, settings.core_size * 0.6, Color(0.45, 0.2, 0.2), false).name = "Flesh"
	var people := civilians()
	var radius := settings.core_size * 0.5
	for i in settings.torso_count:
		var character := load(people[rng.randi() % people.size()]) as PackedScene
		if character == null:
			continue
		var model := character.instantiate() as Node3D
		model.name = "Torso%d" % i
		core.add_child(model)
		_drop_animators(model)
		var skeleton := _skeleton(model)
		if skeleton == null:
			model.queue_free()
			continue
		skeleton.reset_bone_poses()
		var keep := {}
		for bone_name in ["Hips", "Spine", "Chest", "UpperChest", "Neck"]:
			var b := skeleton.find_bone(bone_name)
			if b != -1:
				keep[b] = true
		keep.merge(MeshCut.subtree(skeleton, skeleton.find_bone("Head")))
		MeshCut.keep(model, skeleton, keep)
		var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
		var hips := to_model * skeleton.get_bone_global_rest(maxi(skeleton.find_bone("Hips"), 0)).origin
		var head := to_model * skeleton.get_bone_global_rest(maxi(skeleton.find_bone("Head"), 0)).origin
		var up_in_model := (head - hips).normalized()
		# Spread round the ball (a golden-angle spiral), a little jitter.
		var t := (i + 0.5) / settings.torso_count
		var y := 1.0 - 2.0 * t
		var around := i * 2.39996 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(around) * sqrt(1.0 - y * y), y * 0.8, sin(around) * sqrt(1.0 - y * y)).normalized()
		var size := radius * 1.1 / maxf(hips.distance_to(head), 0.0001) * rng.randf_range(0.9, 1.15)
		var turn := Basis(out, rng.randf() * TAU) * Basis(Quaternion(up_in_model, out))
		var shape := turn.scaled(Vector3.ONE * size)
		model.transform = Transform3D(shape, out * radius * 0.15 - shape * hips)
		for mesh in _meshes(model):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The unrigged PSX spider hung under the front of the sack as its face: the
## eyes glow, a searchlight shines out of them, and Mouth marks where the
## hose and the feeding tube come out.
static func _face(body: Node3D, core_radius: float) -> void:
	var face := Node3D.new()
	face.name = "Face"
	body.add_child(face)
	face.position = Vector3(0.0, -core_radius * 0.75, -core_radius * 0.55)
	face.basis = Basis(Vector3.RIGHT, deg_to_rad(-30.0)) # looking down and ahead
	var model := (load(FACE_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Spider"
	face.add_child(model)
	var bounds := _bounds(model)
	var across := maxf(maxf(bounds.size.x, bounds.size.z), 0.0001)
	var shape := Basis.IDENTITY.scaled(Vector3.ONE * core_radius * 1.2 / across)
	model.transform = Transform3D(shape, -(shape * bounds.get_center()))
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.8, 1.0, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(0.7, 1.0, 0.4)
	glow.emission_energy_multiplier = 3.0
	for mesh in _meshes(model):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.name.contains("Eye"):
			mesh.material_override = glow
	var light := SpotLight3D.new()
	light.name = "Searchlight"
	face.add_child(light)
	light.position = Vector3(0.0, 0.0, -core_radius * 0.3)
	light.light_color = Color(0.75, 1.0, 0.5)
	light.light_energy = 6.0
	light.spot_range = 34.0
	light.spot_angle = 20.0
	light.shadow_enabled = false
	var mouth := Marker3D.new()
	mouth.name = "Mouth"
	face.add_child(mouth)
	mouth.position = Vector3(0.0, -core_radius * 0.2, -core_radius * 0.35)


## The enemy spider's back leg on its own, stretched to leg_length, slimmed,
## hanging from `leg` (its hip). It hangs straight down until the game's IK
## stands it up.
static func _spider_leg(leg: Node3D, angle: float, settings: Settings) -> void:
	var model := (load(SPIDER_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "SpiderLeg"
	leg.add_child(model)
	_drop_animators(model)
	var skeleton := _skeleton(model)
	if skeleton == null:
		return
	# The file's saved pose isn't its rest pose: everything here (and the
	# game's IK) works from the rest pose, so show that.
	skeleton.reset_bone_poses()
	MeshCut.keep(model, skeleton, MeshCut.subtree(skeleton, skeleton.find_bone(SPIDER_LEG + "A")), settings.leg_thinness)
	var body_rest := skeleton.get_bone_global_rest(skeleton.find_bone("body"))
	var chain := Transform3D(body_rest)
	var joints := PackedVector3Array()
	for part in ["A", "B", "C", "D"]:
		chain = chain * skeleton.get_bone_rest(skeleton.find_bone(SPIDER_LEG + part))
		joints.append(chain.origin)
	joints.append(chain * skeleton.get_bone_rest(skeleton.find_bone(SPIDER_LEG + "D_end")).origin)
	var to_world := skeleton.global_transform
	var length := 0.0
	for i in joints.size() - 1:
		length += (to_world * joints[i]).distance_to(to_world * joints[i + 1])
	var scale_by := settings.leg_length / maxf(length, 0.0001)
	model.transform = Transform3D(Basis(Vector3.UP, -angle).scaled(Vector3.ONE * scale_by), Vector3.ZERO)
	# Hip on the leg node's origin.
	var hip := leg.to_local(skeleton.global_transform * joints[0])
	model.position -= hip
	for mesh in _meshes(model):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---- Helpers ----------------------------------------------------------------

## Every vertex of the core's visible meshes, where it's actually drawn
## (skinned ones as their skeleton poses them), in `space`'s coordinates.
static func surface_points(core: Node3D, space: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var to_space := space.global_transform.affine_inverse()
	for mesh_instance in _meshes(core):
		if not mesh_instance.visible or mesh_instance.mesh == null:
			continue
		var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
		var skin := mesh_instance.skin
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var skinned := skeleton != null and skin != null and bones != null and weights != null and not (bones as PackedInt32Array).is_empty()
			var per_vertex := (bones as PackedInt32Array).size() / maxi(vertices.size(), 1) if skinned else 0
			# Every few vertices is plenty to find the surface.
			for v in range(0, vertices.size(), 3):
				var at := vertices[v]
				if skinned:
					var posed := Vector3.ZERO
					for k in per_vertex:
						var weight: float = weights[v * per_vertex + k]
						if weight <= 0.0:
							continue
						var bind: int = bones[v * per_vertex + k]
						var bone := skin.get_bind_bone(bind)
						if bone < 0:
							bone = skeleton.find_bone(skin.get_bind_name(bind))
						if bone < 0:
							continue
						posed += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * at) * weight
					points.append(to_space * (skeleton.global_transform * posed))
				else:
					points.append(to_space * (mesh_instance.global_transform * at))
	return points


## Where the surface is going out from the middle along `dir`: the furthest
## of `points` within a narrow cone round it (or `fallback` meters out).
static func surface_at(points: PackedVector3Array, dir: Vector3, fallback: float) -> Vector3:
	var best := -1.0
	var cone := cos(deg_to_rad(18.0))
	for point in points:
		var length := point.length()
		if length < 0.001:
			continue
		if point.dot(dir) / length >= cone and point.dot(dir) > best:
			best = point.dot(dir)
	return dir * (best if best > 0.0 else fallback)

static func _meshes(model: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if model is MeshInstance3D:
		found.append(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		found.append(node as MeshInstance3D)
	return found


static func _skeleton(model: Node) -> Skeleton3D:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] as Skeleton3D if not skeletons.is_empty() else null


static func _drop_animators(model: Node) -> void:
	for animator in model.find_children("*", "AnimationPlayer", true, false):
		animator.get_parent().remove_child(animator)
		animator.free()


## The visible meshes' bounds, in `model`'s own space.
static func _bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var has := false
	var to_model := model.global_transform.affine_inverse()
	for mesh in _meshes(model):
		if not mesh.visible or mesh.mesh == null:
			continue
		var box := to_model * mesh.global_transform * mesh.get_aabb()
		bounds = box if not has else bounds.merge(box)
		has = true
	return bounds
