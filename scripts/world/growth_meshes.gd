class_name GrowthMeshes

## The alien land's growths (docs/WORLD.md), built in code as low-poly
## meshes -- PS1-chunky (few sides, flat facets), several shape variants of
## each so no two clumps match. Every vertex carries:
##   COLOR.rgb  its colour (purples, blues, teals, magentas),
##   COLOR.a    how much it sways in the wind (0 at the roots, 1 at the tips),
##   UV2.x      how much it glows (tips and bulbs; brighter at night).
## alien_growth.gdshader reads all three. Meshes are made once per kind and
## variant and shared (GrowthScatter draws them with MultiMeshes).
## Sizes are in metres for a scale-1 instance; GrowthScatter scales them.

enum Kind {
	STAGHORN,    ## branching coral, knee to tree height, glowing tips
	KELP,        ## tall wavy stalks with glowing bulbs
	BRAIN_CORAL, ## low ridged domes
	GLOW_GRASS,  ## clumps of thin glowing blades
	SEA_FAN,     ## flat lattice fans
	ANEMONE,     ## tendril clumps
	TUBE_SPONGE, ## clusters of hollow chimneys
	PUFFBALL,    ## spore balls on short stalks
	SPIRE,       ## tall twisted spikes (the stinging coral, later)
	BLADDER,     ## clusters of swollen glowing pods
	# The sewer/hive biome's: the land the insects overran.
	HAIR_MOLD,      ## fuzzy grey-green mould tufts carpeting the ground
	EGG_SACS,       ## heaps of glistening insect eggs in a slick of mucus
	HIVE_MOUND,     ## lumpy clay chimneys the bugs built, glowing down the throat
	FUNGUS_SHELF,   ## pale slimy shelf caps stacked up a rotten stalk
	PUS_BOILS,      ## fleshy swellings crowned with yellow heads
	CHITIN_RIBS,    ## a dead giant bug's husk, ribs arching out of the ground
	COCOON,         ## silk cocoons on web stalks, threads strung between
	SLIME_CAPS,     ## toxic mushrooms dripping and glowing sickly green
	FLESH_TENDRILS, ## meaty tendrils worming up out of the ground
	LARVAE_PILE,    ## heaps of pale fat grubs
	# Both biomes, and up the buildings.
	BLACK_VINES,    ## black tentacle vines snaking out of the surface and over each other, breathing
	# Giants: half a megastructure tall, in forests (solid: GrowthScatter gives
	# each a trunk to collide with, from the mesh's "trunk" meta).
	KELP_TOWER,     ## reef: kelp stalks towering into the fog, glowing bulbs
	CORAL_TREE,     ## reef: staghorn coral grown into branching trees
	FUNGUS_TOWER,   ## sewer: a huge rotten stalk stacked with shelf caps
	HIVE_SPIRE,     ## sewer: a hive mound grown into a towering spire
	FLESH_STALK,    ## sewer: a giant meaty tendril with boils along it
	VINE_PILLAR,    ## both: black vines coiled round each other into a breathing pillar
}

## Built meshes: "kind:variant" -> ArrayMesh.
static var _cache := {}


## One of `kind`'s shape variants (0..variants-1), built the first time.
static func get_mesh(kind: Kind, variant: int) -> ArrayMesh:
	var key := "%d:%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(kind, variant)) # the same every time, on every machine
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Vector2.ZERO
	if kind == Kind.BLACK_VINES or kind == Kind.VINE_PILLAR:
		# For breathing: each vertex's outward direction from its vine's
		# middle (see _vine_vertex).
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_HALF)
	match kind:
		Kind.STAGHORN: _staghorn(st, random)
		Kind.KELP: _kelp(st, random)
		Kind.BRAIN_CORAL: _brain_coral(st, random)
		Kind.GLOW_GRASS: _glow_grass(st, random)
		Kind.SEA_FAN: _sea_fan(st, random)
		Kind.ANEMONE: _anemone(st, random)
		Kind.TUBE_SPONGE: _tube_sponge(st, random)
		Kind.PUFFBALL: _puffball(st, random)
		Kind.SPIRE: _spire(st, random)
		Kind.BLADDER: _bladder(st, random)
		Kind.HAIR_MOLD: _hair_mold(st, random)
		Kind.EGG_SACS: _egg_sacs(st, random)
		Kind.HIVE_MOUND: _hive_mound(st, random)
		Kind.FUNGUS_SHELF: _fungus_shelf(st, random)
		Kind.PUS_BOILS: _pus_boils(st, random)
		Kind.CHITIN_RIBS: _chitin_ribs(st, random)
		Kind.COCOON: _cocoon(st, random)
		Kind.SLIME_CAPS: _slime_caps(st, random)
		Kind.FLESH_TENDRILS: _flesh_tendrils(st, random)
		Kind.LARVAE_PILE: _larvae_pile(st, random)
		Kind.BLACK_VINES: _black_vines(st, random)
		Kind.KELP_TOWER: trunk = _kelp_tower(st, random)
		Kind.CORAL_TREE: trunk = _coral_tree(st, random)
		Kind.FUNGUS_TOWER: trunk = _fungus_tower(st, random)
		Kind.HIVE_SPIRE: trunk = _hive_spire(st, random)
		Kind.FLESH_STALK: trunk = _flesh_stalk(st, random)
		Kind.VINE_PILLAR: trunk = _vine_pillar(st, random)
	st.generate_normals()
	var mesh := st.commit()
	if trunk != Vector2.ZERO:
		mesh.set_meta(&"trunk", trunk) # (radius, height) of the solid part, metres at scale 1
	_cache[key] = mesh
	return mesh


# --- The kinds ---

## Branching coral: a trunk that splits two or three ways, three or four
## times, thinning and shortening; tips glow and sway most.
static func _staghorn(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1.2, 2.2)
	var base := Color(0.32, 0.14, 0.50)
	var tip := Color(0.85, 0.35, 0.80) if random.randf() < 0.5 else Color(0.35, 0.80, 0.90)
	_branch(st, random, Vector3.ZERO, Vector3.UP, height * 0.4, 0.09, 0, 4, height, base, tip)


static func _branch(st: SurfaceTool, random: RandomNumberGenerator, from: Vector3, direction: Vector3,
		length: float, radius: float, depth: int, max_depth: int, height: float, base: Color, tip: Color) -> void:
	var to := from + direction * length
	var last := depth == max_depth - 1
	var t_from := clampf(from.y / height, 0.0, 1.0)
	var t_to := clampf(to.y / height, 0.0, 1.0)
	_tube(st, from, to, radius, radius * 0.7, 5,
			base.lerp(tip, t_from), base.lerp(tip, t_to), t_from * t_from, t_to * t_to,
			0.0, 1.0 if last else 0.0)
	if last:
		return
	var forks := random.randi_range(2, 3)
	for i in forks:
		var spread := deg_to_rad(random.randf_range(22.0, 48.0))
		var around := TAU * (float(i) / forks) + random.randf() * 0.8
		var side := direction.cross(Vector3.RIGHT if absf(direction.x) < 0.9 else Vector3.FORWARD).normalized()
		var bent := direction.rotated(side.rotated(direction, around), spread).normalized()
		bent = (bent + Vector3.UP * 0.35).normalized() # coral reaches up
		_branch(st, random, to, bent, length * random.randf_range(0.6, 0.8), radius * 0.68,
				depth + 1, max_depth, height, base, tip)


## A tall kelp stalk that wanders as it rises, a few glowing bulbs along it
## and one at the top.
static func _kelp(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(5.0, 11.0)
	var segments := 9
	var phase := random.randf() * TAU
	var stalk := Color(0.10, 0.30, 0.42)
	var top := Color(0.30, 0.55, 0.70)
	var previous := Vector3.ZERO
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var point := Vector3(sin(t * 5.0 + phase) * 0.35 * t, t * height, cos(t * 4.0 + phase) * 0.3 * t)
		var t_prev := float(i - 1) / segments
		_tube(st, previous, point, lerpf(0.13, 0.05, t_prev), lerpf(0.13, 0.05, t), 4,
				stalk.lerp(top, t_prev), stalk.lerp(top, t), pow(t_prev, 1.5), pow(t, 1.5), 0.0, 0.0)
		if i % 3 == 0 or i == segments:
			var bulb_color := Color(0.55, 0.85, 0.95) if random.randf() < 0.6 else Color(0.90, 0.50, 0.85)
			_blob(st, point + Vector3(0.12, 0.0, 0.0) * (1.0 if i % 2 == 0 else -1.0), random.randf_range(0.14, 0.26),
					bulb_color, pow(t, 1.5), 1.0)
		previous = point


## A low ridged dome: a half-sphere whose surface folds in and out.
static func _brain_coral(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var radius := random.randf_range(0.5, 1.0)
	var flat := random.randf_range(0.45, 0.7)
	var folds := random.randf_range(5.0, 9.0)
	var color := Color(0.42, 0.20, 0.55) if random.randf() < 0.5 else Color(0.22, 0.30, 0.62)
	var ridge := color.lightened(0.35)
	var rings := 5
	var sides := 9
	var points := []
	for r in rings + 1:
		var row := []
		var latitude := (float(r) / rings) * PI * 0.5
		for s in sides:
			var longitude := TAU * s / sides
			var bump := 1.0 + sin(longitude * folds + latitude * 7.0) * 0.12
			var p := Vector3(cos(longitude) * cos(latitude), sin(latitude) * flat, sin(longitude) * cos(latitude)) * radius * bump
			row.append(p)
		points.append(row)
	for r in rings:
		for s in sides:
			var a: Vector3 = points[r][s]
			var b: Vector3 = points[r][(s + 1) % sides]
			var c: Vector3 = points[r + 1][(s + 1) % sides]
			var d: Vector3 = points[r + 1][s]
			var c_low := color.lerp(ridge, float(r) / rings)
			var c_high := color.lerp(ridge, float(r + 1) / rings)
			_quad(st, a, b, c, d, c_low, c_low, c_high, c_high, 0.0, 0.0, 0.05)


## A clump of thin curved blades, glowing toward their tips.
static func _glow_grass(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var blades := random.randi_range(6, 10)
	var root := Color(0.10, 0.18, 0.40)
	var tip := Color(0.40, 0.90, 0.95) if random.randf() < 0.55 else Color(0.80, 0.45, 0.95)
	_blades(st, random, blades, root, tip, Vector2(0.1, 0.45), Vector2(0.35, 0.8), Vector2(0.05, 0.08), 0.18, 1.0)


## `count` thin curved blades from round the foot: grass, mould hairs.
## lean/height/width are (min, max) ranges; `glow` = how much the tips glow.
static func _blades(st: SurfaceTool, random: RandomNumberGenerator, count: int, root: Color, tip: Color,
		leans: Vector2, heights: Vector2, widths: Vector2, spread: float, glow: float) -> void:
	for i in count:
		var angle := random.randf() * TAU
		var lean := random.randf_range(leans.x, leans.y)
		var height := random.randf_range(heights.x, heights.y)
		var width := random.randf_range(widths.x, widths.y)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var start := out * random.randf_range(0.0, spread)
		var side := out.cross(Vector3.UP) * width
		var mid := start + out * lean * height * 0.4 + Vector3.UP * height * 0.55
		var end := start + out * lean * height + Vector3.UP * height
		var mid_color := root.lerp(tip, 0.55)
		var mid_glow := glow * 0.3
		_quad(st, start - side, start + side, mid + side * 0.6, mid - side * 0.6, root, root, mid_color, mid_color, 0.0, 0.3, mid_glow)
		_triangle(st, mid - side * 0.6, mid + side * 0.6, end, mid_color, mid_color, tip, 0.3, 0.3, 1.0, mid_glow, mid_glow, glow)


## A flat fan: ribs radiating up from the foot, braced by cross ribs.
static func _sea_fan(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var radius := random.randf_range(0.8, 1.6)
	var ribs := random.randi_range(6, 9)
	var color := Color(0.65, 0.20, 0.55) if random.randf() < 0.5 else Color(0.30, 0.40, 0.80)
	var edge := color.lightened(0.3)
	var ends: Array[Vector3] = []
	for i in ribs:
		var angle := lerpf(deg_to_rad(20.0), deg_to_rad(160.0), float(i) / (ribs - 1))
		var end := Vector3(cos(angle) * radius, sin(angle) * radius * 1.1, random.randf_range(-0.05, 0.05))
		_tube(st, Vector3.ZERO, end, 0.035, 0.015, 3, color, edge, 0.0, 1.0, 0.0, 0.25)
		ends.append(end)
	for ring in [0.45, 0.75]:
		for i in ribs - 1:
			_tube(st, ends[i] * ring, ends[i + 1] * ring, 0.015, 0.015, 3,
					color.lerp(edge, ring), color.lerp(edge, ring), ring, ring, 0.0, 0.0)


## A clump of tendrils curling up and out from a short stalk; tips glow.
static func _anemone(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var color := Color(0.80, 0.30, 0.60) if random.randf() < 0.5 else Color(0.30, 0.75, 0.75)
	var body := Color(0.25, 0.12, 0.35)
	var stalk := random.randf_range(0.15, 0.3)
	_tube(st, Vector3.ZERO, Vector3.UP * stalk, 0.18, 0.22, 6, body, body, 0.0, 0.05, 0.0, 0.0)
	var tendrils := random.randi_range(12, 20)
	for i in tendrils:
		var angle := TAU * i / tendrils + random.randf() * 0.3
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var length := random.randf_range(0.35, 0.7)
		var a := Vector3.UP * stalk + out * 0.15
		var b := a + out * length * 0.4 + Vector3.UP * length * 0.6
		var c := b + out * length * 0.5 + Vector3.UP * length * 0.15
		_tube(st, a, b, 0.035, 0.025, 3, body.lerp(color, 0.4), color, 0.1, 0.6, 0.0, 0.3)
		_tube(st, b, c, 0.025, 0.01, 3, color, color.lightened(0.3), 0.6, 1.0, 0.3, 1.0)


## Hollow chimneys of different heights, flared at the rim, glowing inside.
static func _tube_sponge(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var tubes := random.randi_range(3, 7)
	var color := Color(0.55, 0.15, 0.40) if random.randf() < 0.5 else Color(0.18, 0.35, 0.55)
	for i in tubes:
		var at := Vector3(random.randf_range(-0.35, 0.35), 0.0, random.randf_range(-0.35, 0.35))
		var height := random.randf_range(0.5, 1.8)
		var radius := random.randf_range(0.1, 0.22)
		var lean := Vector3(random.randf_range(-0.15, 0.15), 1.0, random.randf_range(-0.15, 0.15)).normalized()
		var top := at + lean * height
		_tube(st, at, top, radius, radius * 1.25, 6, color, color.lightened(0.25), 0.0, 0.2, 0.0, 0.0, true)
		# The glowing inside, a little down from the rim.
		_tube(st, top - lean * 0.25, top, radius * 0.9, radius * 1.1, 6, color.lightened(0.5), color.lightened(0.6),
				0.2, 0.2, 0.8, 1.0, true)


## Spore balls on short wobbly stalks, in a little bunch.
static func _puffball(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var balls := random.randi_range(2, 5)
	var stalk := Color(0.30, 0.22, 0.45)
	var ball := Color(0.75, 0.70, 0.95) if random.randf() < 0.5 else Color(0.55, 0.85, 0.75)
	for i in balls:
		var at := Vector3(random.randf_range(-0.3, 0.3), 0.0, random.randf_range(-0.3, 0.3))
		var height := random.randf_range(0.15, 0.5)
		var top := at + Vector3(random.randf_range(-0.08, 0.08), height, random.randf_range(-0.08, 0.08))
		_tube(st, at, top, 0.04, 0.03, 4, stalk, stalk, 0.0, 0.4, 0.0, 0.0)
		_blob(st, top + Vector3.UP * 0.1, random.randf_range(0.12, 0.25), ball, 0.5, 0.6)


## Tall twisted spikes: a few cones that turn as they rise.
static func _spire(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var spikes := random.randi_range(3, 6)
	var color := Color(0.30, 0.10, 0.40)
	var point := Color(0.95, 0.30, 0.55)
	for i in spikes:
		var at := Vector3(random.randf_range(-0.4, 0.4), 0.0, random.randf_range(-0.4, 0.4))
		var height := random.randf_range(1.0, 3.2)
		var twist := random.randf_range(-0.3, 0.3)
		var previous := at
		var steps := 4
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var p := at + Vector3(sin(t * 3.0) * twist, t * height, cos(t * 3.0) * twist - twist)
			var t_prev := float(s - 1) / steps
			_tube(st, previous, p, lerpf(0.22, 0.02, t_prev), lerpf(0.22, 0.02, t), 4,
					color.lerp(point, t_prev), color.lerp(point, t), t_prev * 0.3, t * 0.3,
					0.0, 1.0 if s == steps else 0.0)
			previous = p


## A heap of swollen pods, some big some small, glowing from within.
static func _bladder(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var pods := random.randi_range(3, 7)
	var color := Color(0.85, 0.45, 0.70) if random.randf() < 0.5 else Color(0.45, 0.80, 0.80)
	for i in pods:
		var size := random.randf_range(0.18, 0.45)
		var at := Vector3(random.randf_range(-0.45, 0.45), size * 0.7, random.randf_range(-0.45, 0.45))
		_blob(st, at, size, color, 0.15, 0.7)


# --- The sewer/hive land's ---

## Fuzzy mould: a dense tuft of short grey-green hairs, the tips a little
## slimy-bright. The sewer's grass.
static func _hair_mold(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var hairs := random.randi_range(8, 12) # fewer, wider: it's everywhere
	var root := Color(0.10, 0.10, 0.06)
	var tip := Color(0.45, 0.50, 0.22) if random.randf() < 0.6 else Color(0.55, 0.52, 0.38)
	_blades(st, random, hairs, root, tip, Vector2(0.05, 0.6), Vector2(0.15, 0.45), Vector2(0.03, 0.055), 0.25, 0.3)


## Insect eggs heaped in a slick of mucus: glistening pale yellow, the odd
## one dark (something moving inside), faintly glowing.
static func _egg_sacs(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var eggs := random.randi_range(6, 14)
	var shell := Color(0.85, 0.80, 0.45) if random.randf() < 0.6 else Color(0.78, 0.84, 0.58)
	var slime := Color(0.28, 0.30, 0.12)
	_tube(st, Vector3.ZERO, Vector3.UP * 0.06, 0.6, 0.5, 6, slime, slime, 0.0, 0.0, 0.0, 0.0)
	for i in eggs:
		var radius := random.randf_range(0.08, 0.16)
		var angle := random.randf() * TAU
		var out := sqrt(random.randf()) * 0.45
		var at := Vector3(cos(angle) * out, radius * 1.2 + (0.45 - out) * 0.35 * random.randf(), sin(angle) * out)
		var color := shell if random.randf() > 0.15 else shell.darkened(0.55)
		_blob(st, at, radius, color, 0.02, 0.35, Vector3(1.0, 1.5, 1.0), false)


## A hive mound: a lumpy clay chimney the bugs built, vents up its sides
## and a dim glow down its throat.
static func _hive_mound(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1.2, 3.0)
	var clay := Color(0.28, 0.22, 0.13)
	var crust := Color(0.42, 0.35, 0.20)
	var lean := Vector2(random.randf_range(-0.2, 0.2), random.randf_range(-0.2, 0.2)) * height * 0.3
	var steps := 5
	var previous := Vector3.ZERO
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(lean.x * t + random.randf_range(-0.06, 0.06), t * height, lean.y * t + random.randf_range(-0.06, 0.06))
		_tube(st, previous, p, lerpf(0.75, 0.18, pow(t_prev, 0.8)), lerpf(0.75, 0.18, pow(t, 0.8)), 6,
				clay.lerp(crust, t_prev), clay.lerp(crust, t), 0.0, 0.0, 0.0, 0.0, s == steps)
		previous = p
	# Its throat, glowing a way down.
	_tube(st, previous - Vector3.UP * 0.3, previous, 0.14, 0.17, 6, Color(0.55, 0.50, 0.15), Color(0.6, 0.55, 0.2),
			0.0, 0.0, 0.6, 0.9, true)
	for i in random.randi_range(2, 4):
		var t := random.randf_range(0.2, 0.7)
		var angle := random.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var base := Vector3(lean.x * t, t * height, lean.y * t) + out * lerpf(0.75, 0.18, pow(t, 0.8)) * 0.85
		_tube(st, base, base + (out + Vector3.UP * 0.3).normalized() * 0.25, 0.12, 0.09, 5, clay, crust,
				0.0, 0.0, 0.0, 0.4, true)


## Shelf fungus: pale, slimy caps stacked up a rotten stalk.
static func _fungus_shelf(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(0.6, 1.6)
	var stalk := Color(0.24, 0.19, 0.11)
	var cap := Color(0.70, 0.62, 0.40) if random.randf() < 0.5 else Color(0.55, 0.58, 0.35)
	_tube(st, Vector3.ZERO, Vector3.UP * height, 0.12, 0.08, 5, stalk, stalk.lightened(0.2), 0.0, 0.05, 0.0, 0.0)
	var caps := random.randi_range(3, 6)
	for i in caps:
		var t := lerpf(0.25, 1.0, float(i) / maxf(caps - 1, 1))
		var angle := random.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var width := lerpf(0.55, 0.25, t) * random.randf_range(0.8, 1.2)
		var at := Vector3.UP * height * t + out * width * 0.5
		_tube(st, at - Vector3.UP * 0.05, at + Vector3.UP * 0.04, width, width * 0.7, 7,
				cap.darkened(0.4), cap, 0.02, 0.05, 0.0, 0.15)


## Pus boils: a fleshy swelling of the ground crowned with swollen yellow
## heads fit to burst.
static func _pus_boils(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var flesh := Color(0.45, 0.25, 0.22)
	var pus := Color(0.85, 0.78, 0.35)
	_blob(st, Vector3.UP * 0.05, random.randf_range(0.45, 0.7), flesh, 0.0, 0.0, Vector3(1.0, 0.4, 1.0))
	for i in random.randi_range(3, 7):
		var angle := random.randf() * TAU
		var out := random.randf_range(0.0, 0.4)
		var radius := random.randf_range(0.07, 0.16)
		var at := Vector3(cos(angle) * out, 0.22 - out * 0.3 + radius * 0.5, sin(angle) * out)
		_blob(st, at, radius, flesh.lerp(pus, 0.4), 0.02, 0.0, Vector3.ONE, false)
		_blob(st, at + Vector3.UP * radius * 0.8, radius * 0.5, pus, 0.02, 0.45, Vector3.ONE, false)


## A dead giant bug's husk: curved chitin ribs arching out of the ground
## either side of its spine, bone-pale with dark tips.
static func _chitin_ribs(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var length := random.randf_range(1.5, 3.5)
	var shell := Color(0.62, 0.55, 0.38)
	var dark := Color(0.18, 0.13, 0.08)
	var ribs := random.randi_range(3, 6)
	_tube(st, Vector3(0.0, 0.05, -length * 0.5), Vector3(0.0, 0.12, length * 0.5), 0.12, 0.08, 5,
			shell.darkened(0.3), shell, 0.0, 0.0, 0.0, 0.0)
	for i in ribs:
		var z := lerpf(-length * 0.4, length * 0.4, float(i) / maxf(ribs - 1, 1))
		var size := random.randf_range(0.7, 1.3) * (1.0 - absf(z) / length * 0.6)
		for side in [-1.0, 1.0]:
			var previous := Vector3(0.0, 0.1, z)
			for s in range(1, 4):
				var t := s / 3.0
				var t_prev := (s - 1) / 3.0
				var p := Vector3(side * sin(t * 2.2) * size, 0.1 + sin(t * PI * 0.9) * size * 1.1, z + t * 0.15)
				_tube(st, previous, p, lerpf(0.08, 0.02, t_prev), lerpf(0.08, 0.02, t), 4,
						shell.lerp(dark, t_prev * 0.6), shell.lerp(dark, t * 0.8), 0.0, 0.0, 0.0, 0.0)
				previous = p


## Silk cocoons: grey-white husks stood up on stalks of web, something dark
## showing through some, threads strung between them.
static func _cocoon(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var silk := Color(0.70, 0.68, 0.60)
	var tops: Array[Vector3] = []
	for i in random.randi_range(1, 3):
		var at := Vector3(random.randf_range(-0.5, 0.5), 0.0, random.randf_range(-0.5, 0.5))
		var stalk := random.randf_range(0.1, 0.6)
		var size := random.randf_range(0.25, 0.45)
		_tube(st, at, at + Vector3.UP * stalk, 0.05, 0.03, 3, silk.darkened(0.3), silk, 0.0, 0.2, 0.0, 0.0)
		var centre := at + Vector3.UP * (stalk + size * 1.6)
		var color := silk if random.randf() < 0.7 else silk.lerp(Color(0.35, 0.2, 0.15), 0.4)
		_blob(st, centre, size, color, 0.25, 0.0, Vector3(0.8, 1.7, 0.8))
		tops.append(centre + Vector3.UP * size * 1.2)
	for i in tops.size() - 1:
		_tube(st, tops[i], tops[i + 1], 0.01, 0.01, 3, silk, silk, 0.3, 0.3, 0.0, 0.0)


## Toxic mushrooms: thin stalks under drooping caps that drip and glow
## sickly green.
static func _slime_caps(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var stalk := Color(0.55, 0.52, 0.38)
	var cap := Color(0.35, 0.60, 0.12) if random.randf() < 0.6 else Color(0.62, 0.55, 0.12)
	for i in random.randi_range(3, 8):
		var at := Vector3(random.randf_range(-0.35, 0.35), 0.0, random.randf_range(-0.35, 0.35))
		var height := random.randf_range(0.15, 0.6)
		var radius := random.randf_range(0.08, 0.2)
		var top := at + Vector3(random.randf_range(-0.06, 0.06), height, random.randf_range(-0.06, 0.06))
		_tube(st, at, top, 0.03, 0.025, 4, stalk.darkened(0.3), stalk, 0.0, 0.3, 0.0, 0.0)
		# The cap: a drooping cone, its brim below the top.
		_tube(st, top - Vector3.UP * radius * 0.5, top + Vector3.UP * radius * 0.3, radius, radius * 0.25, 6,
				cap.darkened(0.3), cap, 0.3, 0.3, 0.4, 0.9)
		if random.randf() < 0.5: # a drip off the brim
			_blob(st, top - Vector3.UP * radius * 0.9 + Vector3(radius * 0.8, 0.0, 0.0), 0.025, cap, 0.3, 1.0,
					Vector3(1.0, 2.0, 1.0), false)


## Meaty tendrils worming up out of the ground, glistening, swaying.
static func _flesh_tendrils(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var meat := Color(0.50, 0.22, 0.22)
	var tip := Color(0.75, 0.50, 0.42)
	for i in random.randi_range(2, 5):
		var at := Vector3(random.randf_range(-0.3, 0.3), 0.0, random.randf_range(-0.3, 0.3))
		var height := random.randf_range(0.6, 1.6)
		var phase := random.randf() * TAU
		var previous := at
		var steps := 5
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var t_prev := float(s - 1) / steps
			var p := at + Vector3(sin(t * 4.0 + phase) * 0.2 * t, t * height, cos(t * 3.5 + phase) * 0.2 * t)
			_tube(st, previous, p, lerpf(0.1, 0.02, t_prev), lerpf(0.1, 0.02, t), 4,
					meat.lerp(tip, t_prev), meat.lerp(tip, t), t_prev * t_prev, t * t, 0.0, 0.0)
			previous = p


## A heap of pale grubs: fat segmented bodies piled together, a dark head
## on each.
static func _larvae_pile(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var pale := Color(0.85, 0.80, 0.62)
	var head := Color(0.25, 0.15, 0.08)
	for i in random.randi_range(3, 6):
		var angle := random.randf() * TAU
		var out := sqrt(random.randf()) * 0.5
		var at := Vector3(cos(angle) * out, 0.08 + (0.5 - out) * 0.4 * random.randf(), sin(angle) * out)
		var heading := random.randf() * TAU
		var direction := Vector3(cos(heading), random.randf_range(-0.2, 0.3), sin(heading)).normalized()
		var size := random.randf_range(0.06, 0.1)
		for s in 4:
			_blob(st, at + direction * s * size * 1.4, size * (1.0 - s * 0.12), pale.darkened(0.1 * s), 0.05, 0.05,
					Vector3.ONE, false)
		_blob(st, at - direction * size * 1.3, size * 0.6, head, 0.05, 0.0, Vector3.ONE, false)


# --- Both biomes ---

## Black tentacle vines (like the player's black coiling tentacle): a few
## thin black tubes snaking out of the surface, over and under each other,
## diving back in and coming up again, their ends curling up into coils.
## Built lying on the surface (its up = out of the ground or wall), so a
## patch lies over whatever it grows on. They breathe (alien_growth.gdshader).
static func _black_vines(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var black := Color(0.03, 0.02, 0.04)
	var sheen := Color(0.13, 0.09, 0.15)
	var vines := random.randi_range(3, 6)
	for v in vines:
		var heading := random.randf() * TAU
		var at := Vector3(random.randf_range(-0.6, 0.6), 0.0, random.randf_range(-0.6, 0.6))
		var steps := random.randi_range(6, 11)
		var thick := random.randf_range(0.035, 0.07)
		var phase := random.randf() * TAU
		var waves := random.randf_range(1.2, 2.4)
		# Each vine rides a little higher than the last: over the ones before.
		var ride := 0.02 + v * 0.03
		var points := PackedVector3Array()
		for s in steps:
			var t := float(s) / (steps - 1)
			heading += random.randf_range(-0.6, 0.6) # snaking
			# Up out of the surface and back into it along its length.
			var y := sin(t * PI * waves + phase) * 0.14 + ride
			points.append(Vector3(at.x, y, at.z))
			at += Vector3(cos(heading), 0.0, sin(heading)) * 0.28
		# The end curls up off the surface into a coil, like the tentacle's tip.
		var coil_at := Vector3(at.x, maxf(points[points.size() - 1].y, 0.05), at.z)
		var turns := random.randf_range(1.0, 1.8)
		var coil_radius := random.randf_range(0.08, 0.14)
		for c in range(1, 6):
			var t := float(c) / 5.0
			var angle := heading + t * turns * TAU
			points.append(coil_at + Vector3(cos(angle), 0.0, sin(angle)) * coil_radius * (1.0 - t * 0.6)
					+ Vector3.UP * t * 0.35)
		# Begin under the surface: it's growing out of it.
		points[0] = Vector3(points[0].x, -0.12, points[0].z)
		var along := 0.0
		for i in points.size() - 1:
			var t_a := float(i) / (points.size() - 1)
			var t_b := float(i + 1) / (points.size() - 1)
			var length := points[i].distance_to(points[i + 1])
			var coiling_a := t_a > float(steps - 1) / (points.size() - 1)
			var coiling_b := t_b > float(steps - 1) / (points.size() - 1)
			_vine_tube(st, points[i], points[i + 1], lerpf(thick, thick * 0.3, t_a), lerpf(thick, thick * 0.3, t_b),
					black.lerp(sheen, 0.5 + 0.5 * sin(along * 9.0)), black.lerp(sheen, 0.5 + 0.5 * sin((along + length) * 9.0)),
					0.6 if coiling_a else 0.08, 0.6 if coiling_b else 0.08)
			along += length


## A vine's tube from `a` to `b` (4 sides, PS1-chunky), each vertex
## carrying what breathing needs (_vine_vertex).
static func _vine_tube(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float,
		color_a: Color, color_b: Color, sway_a: float, sway_b: float) -> void:
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	for i in 4:
		var d0 := side * cos(TAU * i / 4.0) + up * sin(TAU * i / 4.0)
		var d1 := side * cos(TAU * (i + 1) / 4.0) + up * sin(TAU * (i + 1) / 4.0)
		for corner in [[a, d0, radius_a, color_a, sway_a], [a, d1, radius_a, color_a, sway_a], [b, d1, radius_b, color_b, sway_b],
				[a, d0, radius_a, color_a, sway_a], [b, d1, radius_b, color_b, sway_b], [b, d0, radius_b, color_b, sway_b]]:
			_vine_vertex(st, corner[0] + corner[1] * corner[2], corner[1], corner[2], corner[3], corner[4])


## One vine vertex: its colour and sway (as every growth's), plus its
## outward direction (CUSTOM0) and the vine's thickness there (UV.x), which
## the shader swells it along when it breathes.
static func _vine_vertex(st: SurfaceTool, at: Vector3, out: Vector3, radius: float, color: Color, sway: float) -> void:
	var c := color
	c.a = sway
	st.set_color(c)
	st.set_uv(Vector2(radius, 0.0))
	st.set_uv2(Vector2.ZERO)
	st.set_custom(0, Color(out.x, out.y, out.z, 0.0))
	st.add_vertex(at)


# --- Giants (each returns its trunk: radius and height, metres) ---

## A kelp stalk towering into the fog: wandering up, thinning, with glowing
## bulbs all the way up and a cluster at the top. The top sways most.
static func _kelp_tower(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(25.0, 45.0)
	var segments := 14
	var phase := random.randf() * TAU
	var stalk := Color(0.08, 0.25, 0.36)
	var top := Color(0.28, 0.52, 0.68)
	var previous := Vector3.ZERO
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var t_prev := float(i - 1) / segments
		var point := Vector3(sin(t * 4.0 + phase) * 1.8 * t, t * height, cos(t * 3.3 + phase) * 1.5 * t)
		_tube(st, previous, point, lerpf(0.7, 0.2, t_prev), lerpf(0.7, 0.2, t), 6,
				stalk.lerp(top, t_prev), stalk.lerp(top, t), pow(t_prev, 2.0), pow(t, 2.0), 0.0, 0.0)
		if i % 2 == 0:
			var color := Color(0.55, 0.85, 0.95) if random.randf() < 0.6 else Color(0.9, 0.5, 0.85)
			var side := Vector3(cos(i * 2.1), 0.0, sin(i * 2.1)) * 0.6
			_blob(st, point + side, random.randf_range(0.6, 1.2), color, pow(t, 2.0), 1.0)
		previous = point
	for b in 3:
		_blob(st, previous + Vector3(random.randf_range(-1.0, 1.0), random.randf_range(0.0, 1.5), random.randf_range(-1.0, 1.0)),
				random.randf_range(0.9, 1.6), Color(0.55, 0.85, 0.95), 1.0, 1.0)
	return Vector2(0.7, height * 0.6)


## Staghorn coral grown into a tree: a thick trunk forking up and out into
## a crown of glowing tips.
static func _coral_tree(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(20.0, 32.0)
	var base := Color(0.30, 0.12, 0.46)
	var tip := Color(0.85, 0.35, 0.80) if random.randf() < 0.5 else Color(0.35, 0.80, 0.90)
	_branch(st, random, Vector3.ZERO, Vector3.UP, height * 0.32, 1.1, 0, 5, height, base, tip)
	return Vector2(1.1, height * 0.32)


## A huge rotten stalk stacked with shelf-fungus caps, a spiral of them up
## its side like platforms, and a wide cap on top.
static func _fungus_tower(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(20.0, 35.0)
	var stalk := Color(0.22, 0.17, 0.10)
	var cap := Color(0.68, 0.60, 0.38) if random.randf() < 0.5 else Color(0.52, 0.56, 0.32)
	var previous := Vector3.ZERO
	var segments := 6
	var lean := Vector2(random.randf_range(-1.5, 1.5), random.randf_range(-1.5, 1.5))
	var spine: Array[Vector3] = [Vector3.ZERO]
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var t_prev := float(i - 1) / segments
		var point := Vector3(lean.x * t * t, t * height, lean.y * t * t)
		_tube(st, previous, point, lerpf(1.6, 0.9, t_prev), lerpf(1.6, 0.9, t), 6,
				stalk, stalk.lightened(0.15), 0.0, 0.02, 0.0, 0.0)
		spine.append(point)
		previous = point
	var caps := random.randi_range(6, 11)
	for i in caps:
		var t := lerpf(0.25, 0.95, float(i) / maxf(caps - 1, 1))
		var angle := i * 2.4 + random.randf() * 0.6
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var width := lerpf(6.0, 3.0, t) * random.randf_range(0.8, 1.2)
		var on := spine[int(t * segments)].lerp(spine[mini(int(t * segments) + 1, segments)], fmod(t * segments, 1.0))
		var at := on + out * width * 0.55
		_tube(st, at - Vector3.UP * 0.35, at + Vector3.UP * 0.25, width, width * 0.7, 8,
				cap.darkened(0.45), cap, 0.0, 0.01, 0.15, 0.2)
	_tube(st, previous - Vector3.UP * 0.6, previous + Vector3.UP * 1.2, 7.0, 2.5, 9, cap.darkened(0.4), cap, 0.0, 0.01, 0.2, 0.15)
	return Vector2(1.6, height)


## A hive mound grown into a towering spire: lumpy clay narrowing up to an
## open, glowing mouth, vents all the way up.
static func _hive_spire(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(22.0, 40.0)
	var clay := Color(0.27, 0.21, 0.12)
	var crust := Color(0.42, 0.35, 0.20)
	var lean := Vector2(random.randf_range(-0.12, 0.12), random.randf_range(-0.12, 0.12)) * height
	var steps := 9
	var previous := Vector3.ZERO
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(lean.x * t + random.randf_range(-0.3, 0.3), t * height, lean.y * t + random.randf_range(-0.3, 0.3))
		_tube(st, previous, p, _spire_radius(t_prev), _spire_radius(t), 7,
				clay.lerp(crust, t_prev), clay.lerp(crust, t), 0.0, 0.0, 0.0, 0.0, s == steps)
		previous = p
	_tube(st, previous - Vector3.UP * 1.5, previous, 0.7, 0.85, 7, Color(0.55, 0.5, 0.15), Color(0.6, 0.55, 0.2), 0.0, 0.0, 0.7, 1.0, true)
	for i in random.randi_range(6, 12):
		var t := random.randf_range(0.1, 0.85)
		var angle := random.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var base := Vector3(lean.x * t, t * height, lean.y * t) + out * _spire_radius(t) * 0.9
		_tube(st, base, base + (out + Vector3.UP * 0.3).normalized() * 1.2, 0.6, 0.45, 6, clay, crust,
				0.0, 0.0, 0.0, 0.6, true)
	return Vector2(3.5, height * 0.5)


## The hive spire's thickness 	 of the way up: wide at the foot, narrowing.
static func _spire_radius(t: float) -> float:
	return lerpf(5.5, 0.9, pow(t, 0.7))


## A giant meaty tendril rising out of the ground, wavering, swaying slowly,
## with pus boils along it.
static func _flesh_stalk(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(18.0, 35.0)
	var meat := Color(0.48, 0.20, 0.20)
	var tip := Color(0.75, 0.48, 0.40)
	var pus := Color(0.85, 0.78, 0.35)
	var phase := random.randf() * TAU
	var previous := Vector3.ZERO
	var steps := 10
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(sin(t * 3.5 + phase) * 2.0 * t, t * height, cos(t * 3.0 + phase) * 2.0 * t)
		var radius := lerpf(1.6, 0.3, t)
		_tube(st, previous, p, lerpf(1.6, 0.3, t_prev), radius, 6, meat.lerp(tip, t_prev), meat.lerp(tip, t),
				t_prev * t_prev, t * t, 0.0, 0.0)
		if s < steps and random.randf() < 0.7:
			var angle := random.randf() * TAU
			var out := Vector3(cos(angle), 0.0, sin(angle))
			_blob(st, p + out * radius * 0.8, radius * 0.45, meat.lerp(pus, 0.4), t * t, 0.0, Vector3.ONE, false)
			_blob(st, p + out * radius * 1.2, radius * 0.22, pus, t * t, 0.45, Vector3.ONE, false)
		previous = p
	return Vector2(1.4, height * 0.5)


## Black vines coiled round each other up into a pillar, their tips curling
## off the top; it breathes like the small vines.
static func _vine_pillar(st: SurfaceTool, random: RandomNumberGenerator) -> Vector2:
	var height := random.randf_range(15.0, 32.0)
	var black := Color(0.03, 0.02, 0.04)
	var sheen := Color(0.13, 0.09, 0.15)
	var vines := random.randi_range(5, 8)
	for v in vines:
		var phase := TAU * v / vines + random.randf() * 0.4
		var coil := random.randf_range(0.8, 1.6) # radius round the pillar's middle
		var turns := random.randf_range(1.5, 3.0) * (1.0 if v % 2 == 0 else -1.0) # wound both ways
		var thick := random.randf_range(0.28, 0.5)
		var top := height * random.randf_range(0.8, 1.05)
		var steps := 18
		var points := PackedVector3Array()
		for s in steps + 1:
			var t := float(s) / steps
			var angle := phase + t * turns * TAU
			var r := coil * (1.0 - t * 0.5) + sin(t * 9.0 + phase) * 0.15
			points.append(Vector3(cos(angle) * r, t * top - 0.5, sin(angle) * r))
		# Its tip peels off the top and curls.
		var last := points[points.size() - 1]
		var out := Vector3(last.x, 0.0, last.z).normalized()
		for c in range(1, 5):
			var t := float(c) / 4.0
			points.append(last + out * t * 1.6 + Vector3.UP * sin(t * PI) * 1.2 - Vector3.UP * t * t * 1.0)
		var along := 0.0
		for i in points.size() - 1:
			var t_a := float(i) / (points.size() - 1)
			var t_b := float(i + 1) / (points.size() - 1)
			var length := points[i].distance_to(points[i + 1])
			_vine_tube(st, points[i], points[i + 1], lerpf(thick, thick * 0.35, t_a), lerpf(thick, thick * 0.35, t_b),
					black.lerp(sheen, 0.5 + 0.5 * sin(along * 1.5)), black.lerp(sheen, 0.5 + 0.5 * sin((along + length) * 1.5)),
					t_a * t_a * 0.5, t_b * t_b * 0.5)
			along += length
	return Vector2(1.6, height)


# --- Shape pieces ---

## A tapered prism from `a` to `b`: `sides` faces (few: PS1-chunky), with a
## colour, sway and glow at each end. `open` = no cap (a hollow tube); the
## tube's inside is drawn too (the growth material is two-sided).
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float, sides: int,
		color_a: Color, color_b: Color, sway_a: float, sway_b: float, glow_a: float, glow_b: float,
		open: bool = false) -> void:
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		_quad(st, a + d0 * radius_a, a + d1 * radius_a, b + d1 * radius_b, b + d0 * radius_b,
				color_a, color_a, color_b, color_b, sway_a, sway_b, 0.0, glow_a, glow_b)
	if not open and radius_b > 0.005:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			_triangle(st, b + (side * cos(a0) + up * sin(a0)) * radius_b, b + (side * cos(a1) + up * sin(a1)) * radius_b, b,
					color_b, color_b, color_b, sway_b, sway_b, sway_b, glow_b, glow_b, glow_b)


## A low-poly ball (an octahedron, split once): bulbs, pods, spore balls.
## `stretch` squashes or stretches it (eggs, cocoons); `fine` = false keeps
## it a plain octahedron (8 faces, for small things there are lots of).
static func _blob(st: SurfaceTool, centre: Vector3, radius: float, color: Color, sway: float, glow: float,
		stretch: Vector3 = Vector3.ONE, fine: bool = true) -> void:
	var points := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 3, 4], [0, 4, 2], [0, 2, 5], [0, 5, 3], [1, 4, 3], [1, 2, 4], [1, 5, 2], [1, 3, 5]]
	var dark := color.darkened(0.35)
	var size := stretch * radius
	for face in faces:
		var a: Vector3 = points[face[0]]
		var b: Vector3 = points[face[1]]
		var c: Vector3 = points[face[2]]
		var tris := [[a, b, c]]
		if fine:
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			tris = [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]
		for tri in tris:
			var p: Array = tri
			var colors := []
			for v in p:
				colors.append(dark.lerp(color, (v as Vector3).y * 0.5 + 0.5))
			_triangle(st, centre + (p[0] as Vector3) * size, centre + (p[1] as Vector3) * size, centre + (p[2] as Vector3) * size,
					colors[0], colors[1], colors[2], sway, sway, sway, glow, glow, glow)


## Two triangles: a-b-c-d round the quad. Sway/glow: a/b get the first value,
## c/d the second (a middle value can also be given for glow at the base).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, sway_low: float, sway_high: float,
		glow: float, glow_low: float = -1.0, glow_high: float = -1.0) -> void:
	var g_low := glow if glow_low < 0.0 else glow_low
	var g_high := glow if glow_high < 0.0 else glow_high
	_triangle(st, a, b, c, ca, cb, cc, sway_low, sway_low, sway_high, g_low, g_low, g_high)
	_triangle(st, a, c, d, ca, cc, cd, sway_low, sway_high, sway_high, g_low, g_high, g_high)


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color,
		sa: float, sb: float, sc: float, ga: float, gb: float, gc: float) -> void:
	for corner in [[a, ca, sa, ga], [b, cb, sb, gb], [c, cc, sc, gc]]:
		var color: Color = corner[1]
		color.a = corner[2] # sway weight rides in the colour's alpha
		st.set_color(color)
		st.set_uv2(Vector2(corner[3], 0.0)) # glow
		st.add_vertex(corner[0])
