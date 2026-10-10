class_name GrowthScatter
extends Node

## Grows the alien land's flora (docs/WORLD.md) -- the procedural half of
## the hybrid world. Every chunk WorldChunks streams in gets its growths as
## it arrives, built the same way every time (from the world seed and the
## chunk's place), so all co-op players see the same land without sending
## any of it (Rule 1); they go when the chunk goes.
##
## Natural-looking groups, not a sprinkle:
##   Each kind has its own patchy map over the land (GrowthSpecies.patch_*),
##   so there are coral forests, kelp groves and grass plains, and stretches
##   with none.
##   Where it grows, it grows in GROUPS whose size has a long tail: mostly
##   small groups, some medium, now and then a huge horde (a Pareto draw).
##   A group spreads wider the bigger it is; members crowd toward its middle,
##   the middle ones are the big ones and stragglers at the edge are small,
##   and now and then there's an "elder" far bigger than the rest. A few
##   loners stand between the groups.
##   Each kind keeps to its ground: slope and height (kelp in the valleys,
##   sponges up on the ridges, grass on the flats) -- and off the yard and
##   out of the megastructures.
##   And to its biome (BiomeMap): reef kinds in the reef, sewer kinds in the
##   sewer/hive land, both thinning out across the border so they mix there.
##   Some climb (GrowthSpecies.wall_patches): patches up the sides of the
##   chunk's buildings too.
##   Every one rolls its own size, like the creature hordes.
## Drawing: one MultiMesh per kind and shape variant per chunk (a draw call
## each, however many plants), faded out past each kind's view distance.

## The world's growth seed: change it for a different land's flora.
@export var seed: int = 77
## The kinds that grow (empty = GrowthSpecies.defaults()).
@export var species: Array[GrowthSpecies] = []
## Ground heights treated as the lowest and highest (metres), for the
## kinds' height preferences.
@export var low_ground: float = 0.0
@export var high_ground: float = 55.0
## Which biome is where (empty = the sewer everywhere).
@export var biomes: BiomeMap
## Keep this circle bare (Grandma's yard).
@export var clear_centre: Vector3 = Vector3.ZERO
@export var clear_radius: float = 70.0
## How dark it is (0 = day, 1 = night): the growths glow more at night.
## The day/night cycle will drive this.
@export_range(0.0, 1.0, 0.01) var night: float = 0.0:
	set(value):
		night = value
		for material: ShaderMaterial in _materials.values():
			material.set_shader_parameter("night", night)
## The chunk streamer and the ground (empty = found next to this node).
@export var chunks: WorldChunks
@export var terrain: Node3D

const GROWTH_SHADER := preload("res://shaders/alien_growth.gdshader")

## How thick the flora is overall: every kind's groups and loners times this.
@export var density: float = 1.2
## Kinds grown per frame (each is one kind's plants for one chunk).
@export var kinds_per_frame: int = 3

var _data: Object
var _patches: Array[FastNoiseLite] = []
## Waiting: [chunk, its root, kind index].
var _jobs: Array = []
## GrowthSpecies -> its ShaderMaterial (shared by all its chunks).
var _materials := {}


func _ready() -> void:
	if species.is_empty():
		species = GrowthSpecies.defaults()
	if chunks == null:
		chunks = _find_sibling("WorldChunks") as WorldChunks
	if terrain == null:
		terrain = _find_sibling("Terrain3D") as Node3D
	if chunks == null or terrain == null:
		push_warning("GrowthScatter: needs a WorldChunks and a Terrain3D next to it")
		return
	for index in species.size():
		var noise := FastNoiseLite.new()
		noise.seed = seed * 31 + index
		noise.frequency = 1.0 / maxf(species[index].patch_size, 1.0)
		noise.fractal_octaves = 3
		_patches.append(noise)
		var material := ShaderMaterial.new()
		material.shader = GROWTH_SHADER
		material.set_shader_parameter("glow_color", species[index].glow_color)
		material.set_shader_parameter("sway_amount", species[index].sway_amount)
		material.set_shader_parameter("breathe_amount", species[index].breathe)
		material.set_shader_parameter("breathe_speed", species[index].breathe_speed)
		material.set_shader_parameter("night", night)
		_materials[species[index]] = material
	chunks.chunk_loaded.connect(_on_chunk_loaded)


## The node of `type` next to this one: by its usual name first (the world
## scenes name them after their type), else by type anywhere in the parent.
func _find_sibling(type: String) -> Node:
	var named := get_parent().get_node_or_null(NodePath(type))
	if named:
		return named
	var found := get_parent().find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


## A chunk arrived: queue its growing, a kind at a time (see _process).
func _on_chunk_loaded(chunk: Vector2i, root: Node3D) -> void:
	for index in species.size():
		_jobs.append([chunk, root, index])


## Grows a few kinds per frame (kinds_per_frame), so a chunk arriving never
## costs one frame all its plants at once.
func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	if _data == null:
		_data = terrain.call("get_data")
		if _data == null:
			return
	for n in kinds_per_frame:
		if _jobs.is_empty():
			return
		var job: Array = _jobs.pop_front()
		var root: Node3D = job[1] if is_instance_valid(job[1]) else null
		if root == null or not root.is_inside_tree():
			continue # the chunk's already gone again
		_grow(species[job[2]], job[2], job[0], root, _blocked_areas(root), _buildings(root))


## Places one kind's groups and loners in `chunk` and draws them.
func _grow(kind: GrowthSpecies, index: int, chunk: Vector2i, root: Node3D, blocked: Array[Rect2],
		buildings: Array[CollisionShape3D]) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector4i(seed, index, chunk.x, chunk.y))
	var size := chunks.chunk_size
	var origin := Vector2(chunk.x * size, chunk.y * size)
	# How common it is here: its patch map at the chunk's middle (with a soft
	# edge, so patches thin out rather than stopping dead).
	var patch := _patches[index].get_noise_2dv(origin + Vector2(size, size) * 0.5) * 0.5 + 0.5
	var abundance := smoothstep(1.0 - kind.patch_cover, 1.0 - kind.patch_cover + 0.2, patch)
	var placed: Array[Transform3D] = []
	var customs: Array[Color] = []
	var colors: Array[Color] = []
	var groups := _poisson(random, kind.groups_per_chunk * abundance * _area_scale())
	for g in groups:
		var centre := origin + Vector2(random.randf(), random.randf()) * size
		if _at_home(kind, centre.x, centre.y) < 0.05:
			continue # a group of it right out in the other biome: none
		# Long-tailed group size: mostly small, sometimes big, rarely a horde.
		var count := clampi(int(kind.min_group * pow(1.0 - random.randf() * 0.999, -1.0 / maxf(kind.group_tail, 0.1))),
				kind.min_group, kind.max_group)
		var radius := kind.spacing * sqrt(float(count)) * random.randf_range(0.6, 1.4)
		var stretch := random.randf_range(0.6, 1.0) # groups aren't perfect circles
		var turn := random.randf() * TAU
		for m in count:
			var t := pow(random.randf(), kind.crowding * 0.5) # crowded toward the middle
			var angle := random.randf() * TAU
			var offset := Vector2(cos(angle), sin(angle) * stretch).rotated(turn) * radius * t
			_try_place(kind, random, centre + offset, random.randf_range(kind.min_scale, kind.max_scale),
					origin, blocked, placed, customs, colors)
	var loners := _poisson(random, kind.loners_per_chunk * maxf(abundance, 0.15) * _area_scale())
	for l in loners:
		var spot := origin + Vector2(random.randf(), random.randf()) * size
		_try_place(kind, random, spot, random.randf_range(kind.min_scale, kind.max_scale), origin, blocked, placed, customs, colors)
	if kind.wall_patches > 0.0:
		_climb(kind, random, root, buildings, placed, customs, colors)
	if placed.is_empty():
		return
	_draw(kind, root, random, placed, customs, colors)


## One plant at `spot` (world x/z) if the ground there suits its kind:
## standing on the ground, leaning with it a little, sized and tinted.
func _try_place(kind: GrowthSpecies, random: RandomNumberGenerator, spot: Vector2, base_scale: float, origin: Vector2,
		blocked: Array[Rect2], placed: Array[Transform3D], customs: Array[Color], colors: Array[Color]) -> void:
	if spot.distance_to(Vector2(clear_centre.x, clear_centre.z)) < clear_radius:
		return
	# Thinning out across a biome border (gone a little before the far side).
	if random.randf() >= smoothstep(0.1, 0.6, _at_home(kind, spot.x, spot.y)):
		return
	for area in blocked:
		if area.has_point(spot):
			return
	var at := Vector3(spot.x, 0.0, spot.y)
	var height: float = _data.call("get_height", at)
	if is_nan(height):
		return
	var normal: Vector3 = _data.call("get_normal", at)
	if not normal.is_finite() or normal.length_squared() < 0.5:
		normal = Vector3.UP
	var slope := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	if slope < kind.min_slope or slope > kind.max_slope:
		return
	var level := inverse_lerp(low_ground, high_ground, height)
	if level < kind.min_height or level > kind.max_height:
		return
	var scale := base_scale
	if random.randf() < kind.elder_chance:
		scale *= kind.elder_scale
	var up := Vector3.UP.lerp(normal, kind.follow_ground).normalized()
	var facing := Basis(Vector3.UP, random.randf() * TAU)
	var lean := Basis(Quaternion(Vector3.UP, up)) if not up.is_equal_approx(Vector3.UP) else Basis.IDENTITY
	var where := Vector3(spot.x - origin.x, height - kind.sink * scale, spot.y - origin.y)
	placed.append(Transform3D(lean * facing * Basis.from_scale(Vector3.ONE * scale), where))
	_add_looks(kind, random, customs, colors)


## Its sway phase and glow (custom data) and its tint: each one a little
## different.
func _add_looks(kind: GrowthSpecies, random: RandomNumberGenerator, customs: Array[Color], colors: Array[Color]) -> void:
	customs.append(Color(random.randf(), random.randf(), 0.0, 0.0)) # sway phase, glow amount
	var shade := 1.0 + random.randf_range(-kind.tint_variation, kind.tint_variation)
	var hue := random.randf_range(-kind.tint_variation, kind.tint_variation) * 0.3
	colors.append(Color(clampf(shade + hue, 0.0, 2.0), clampf(shade, 0.0, 2.0), clampf(shade - hue, 0.0, 2.0), 1.0))


## How at home a kind is here, by biome: 1 = its own biome, 0 = the other.
func _at_home(kind: GrowthSpecies, x: float, z: float) -> float:
	if kind.biome == GrowthSpecies.Biome.ANYWHERE:
		return 1.0
	var reef := biomes.reef(x, z) if biomes else 0.0
	return reef if kind.biome == GrowthSpecies.Biome.REEF else 1.0 - reef


## Patches of a climbing kind up the sides of the chunk's buildings: about
## wall_patches per 1000 m² of wall, lying flat on it, from the ground up.
func _climb(kind: GrowthSpecies, random: RandomNumberGenerator, root: Node3D, buildings: Array[CollisionShape3D],
		placed: Array[Transform3D], customs: Array[Color], colors: Array[Color]) -> void:
	var to_chunk := root.global_transform.affine_inverse()
	for shape in buildings:
		var half := (shape.shape as BoxShape3D).size * 0.5
		var centre := shape.global_position
		var ground: float = _data.call("get_height", centre)
		if is_nan(ground):
			continue
		var top := (shape.global_transform * Vector3(0.0, half.y, 0.0)).y
		if top - ground < 1.0 or _at_home(kind, centre.x, centre.z) < 0.05:
			continue
		for side in 4:
			var normal := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][side] as Vector3
			var width := half.z * 2.0 if normal.x != 0.0 else half.x * 2.0
			var patches := _poisson(random, kind.wall_patches * width * (top - ground) / 1000.0)
			for n in patches:
				var across := random.randf_range(-0.9, 0.9)
				var local := Vector3(half.x * normal.x if normal.x != 0.0 else across * half.x, 0.0,
						half.z * normal.z if normal.z != 0.0 else across * half.z)
				var point := shape.global_transform * local
				# Thickest near the ground, thinning out up the wall.
				point.y = ground + (top - ground) * pow(random.randf(), 1.6)
				var out := (shape.global_basis * normal).normalized()
				var lie := Basis(Quaternion(Vector3.UP, out)) * Basis(Vector3.UP, random.randf() * TAU)
				var scale := random.randf_range(kind.min_scale, kind.max_scale)
				placed.append(to_chunk * Transform3D(lie * Basis.from_scale(Vector3.ONE * scale), point - out * kind.sink * scale))
				_add_looks(kind, random, customs, colors)


## Splits the placed plants over the kind's shape variants, one MultiMesh
## each, under the chunk's root (so they go with the chunk).
func _draw(kind: GrowthSpecies, root: Node3D, random: RandomNumberGenerator,
		placed: Array[Transform3D], customs: Array[Color], colors: Array[Color]) -> void:
	var buckets: Array = []
	for v in kind.variants:
		buckets.append([])
	for i in placed.size():
		(buckets[random.randi() % kind.variants] as Array).append(i)
	for v in kind.variants:
		var members: Array = buckets[v]
		if members.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = GrowthMeshes.get_mesh(kind.kind, v)
		multimesh.instance_count = members.size()
		for n in members.size():
			var i: int = members[n]
			multimesh.set_instance_transform(n, placed[i])
			multimesh.set_instance_color(n, colors[i])
			multimesh.set_instance_custom_data(n, customs[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%d" % [GrowthMeshes.Kind.keys()[kind.kind], v]
		instance.multimesh = multimesh
		instance.material_override = _materials[kind]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind.cast_shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = kind.view_distance
		instance.visibility_range_end_margin = kind.view_distance * 0.1
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(instance)


## The chunk's buildings: every box collision shape in it.
func _buildings(root: Node3D) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for node in root.find_children("*", "CollisionShape3D", true, false):
		if (node as CollisionShape3D).shape is BoxShape3D:
			found.append(node)
	return found


## The ground the chunk's own content stands on (its megastructures): their
## collision boxes' footprints in world x/z, with a little room round them.
func _blocked_areas(root: Node3D) -> Array[Rect2]:
	var areas: Array[Rect2] = []
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var bounds := shape.global_transform * AABB(-box.size * 0.5, box.size)
		areas.append(Rect2(bounds.position.x - 2.0, bounds.position.z - 2.0, bounds.size.x + 4.0, bounds.size.z + 4.0))
	return areas


## How many 128 x 128 m pieces of land a chunk is (the kinds' counts are
## per 128 m, whatever size the chunks are), times the overall density.
func _area_scale() -> float:
	return pow(chunks.chunk_size / 128.0, 2.0) * density


## A whole number of events, averaging `mean` (Poisson; Knuth's method).
func _poisson(random: RandomNumberGenerator, mean: float) -> int:
	if mean <= 0.0:
		return 0
	if mean > 30.0:
		return maxi(0, roundi(random.randfn(mean, sqrt(mean)))) # close enough for big means
	var limit := exp(-mean)
	var product := random.randf()
	var count := 0
	while product > limit:
		product *= random.randf()
		count += 1
	return count
