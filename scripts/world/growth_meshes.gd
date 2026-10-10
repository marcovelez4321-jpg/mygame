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
	st.generate_normals()
	var mesh := st.commit()
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
	var blades := random.randi_range(8, 14)
	var root := Color(0.10, 0.18, 0.40)
	var tip := Color(0.40, 0.90, 0.95) if random.randf() < 0.55 else Color(0.80, 0.45, 0.95)
	_blades(st, random, blades, root, tip, Vector2(0.1, 0.45), Vector2(0.35, 0.8), Vector2(0.04, 0.07), 0.18, 1.0)


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
static func _blob(st: SurfaceTool, centre: Vector3, radius: float, color: Color, sway: float, glow: float) -> void:
	var points := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 3, 4], [0, 4, 2], [0, 2, 5], [0, 5, 3], [1, 4, 3], [1, 2, 4], [1, 5, 2], [1, 3, 5]]
	var dark := color.darkened(0.35)
	for face in faces:
		var a: Vector3 = points[face[0]]
		var b: Vector3 = points[face[1]]
		var c: Vector3 = points[face[2]]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for tri in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			var p: Array = tri
			var colors := []
			for v in p:
				colors.append(dark.lerp(color, (v as Vector3).y * 0.5 + 0.5))
			_triangle(st, centre + (p[0] as Vector3) * radius, centre + (p[1] as Vector3) * radius, centre + (p[2] as Vector3) * radius,
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
