class_name SkylineMeshes

## Stand-in skyline giants (SkylineLayer grows them while there are no real
## ones yet): kilometre-scale silhouettes, a few hundred triangles each,
## dark and vertex coloured, with tiny glowing lights here and there -- the
## lights are what tell your eye how big they are. Built with the growths'
## shape pieces (GrowthMeshes).


static func build(kind: StringName, random: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		&"tower": _tower(st, random)
		&"hive": _hive(st, random)
		&"kelp": _kelp(st, random)
		&"vines": _vines(st, random)
		&"loop": _loop(st, random)
	st.generate_normals()
	return st.commit()


## A brutalist megastructure: a tapering, stepped column with fins up its
## sides, a flared crown, and rows of tiny lights.
static func _tower(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1300.0, 2400.0)
	var base_radius := random.randf_range(110.0, 200.0)
	var stone := Color(0.16, 0.15, 0.16)
	var top := Color(0.26, 0.24, 0.26)
	var steps := 10
	var previous := Vector3.ZERO
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(0.0, t * height, 0.0)
		var r_prev := base_radius * lerpf(1.0, 0.35, t_prev) * (0.85 if s % 3 == 0 else 1.0)
		var r := base_radius * lerpf(1.0, 0.35, t)
		GrowthMeshes._tube(st, previous, p, r_prev, r, 6, stone.lerp(top, t_prev), stone.lerp(top, t), 0.0, 0.0, 0.0, 0.0, false)
		previous = p
	# Fins.
	for f in 4:
		var angle := TAU * f / 4.0 + random.randf() * 0.2
		var out := Vector3(cos(angle), 0.0, sin(angle))
		GrowthMeshes._tube(st, out * base_radius * 0.9, out * base_radius * 0.5 + Vector3.UP * height * 0.75,
				base_radius * 0.12, base_radius * 0.04, 4, stone, top, 0.0, 0.0, 0.0, 0.0, false)
	# The crown.
	GrowthMeshes._tube(st, previous - Vector3.UP * height * 0.04, previous + Vector3.UP * height * 0.03,
			base_radius * 0.7, base_radius * 0.9, 8, top, top.lightened(0.1), 0.0, 0.0, 0.0, 0.0, false)
	_lights(st, random, height, base_radius, 0.35, 120)


## A hive spire grown kilometres high: lumpy, leaning, vents glowing.
static func _hive(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1400.0, 2200.0)
	var base_radius := random.randf_range(200.0, 320.0)
	var clay := Color(0.20, 0.16, 0.10)
	var crust := Color(0.32, 0.27, 0.16)
	var lean := Vector2(random.randf_range(-0.1, 0.1), random.randf_range(-0.1, 0.1)) * height
	var steps := 9
	var previous := Vector3.ZERO
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(lean.x * t * t + random.randf_range(-20.0, 20.0), t * height, lean.y * t * t + random.randf_range(-20.0, 20.0))
		GrowthMeshes._tube(st, previous, p, base_radius * lerpf(1.0, 0.15, pow(t_prev, 0.7)), base_radius * lerpf(1.0, 0.15, pow(t, 0.7)), 7,
				clay.lerp(crust, t_prev), clay.lerp(crust, t), 0.0, 0.0, 0.0, 0.0, s == steps)
		previous = p
	GrowthMeshes._tube(st, previous - Vector3.UP * 60.0, previous, base_radius * 0.12, base_radius * 0.16, 7,
			Color(0.6, 0.5, 0.15), Color(0.7, 0.6, 0.2), 0.0, 0.0, 1.0, 1.0, true)
	_lights(st, random, height, base_radius, 0.15, 60, Color(0.8, 0.65, 0.2))


## A kelp stalk a kilometre tall, bending, glowing bulbs all the way up.
static func _kelp(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1000.0, 1600.0)
	var stalk := Color(0.08, 0.20, 0.28)
	var tip := Color(0.22, 0.42, 0.55)
	var phase := random.randf() * TAU
	var previous := Vector3.ZERO
	var steps := 14
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var t_prev := float(s - 1) / steps
		var p := Vector3(sin(t * 3.0 + phase) * 120.0 * t, t * height, cos(t * 2.5 + phase) * 90.0 * t)
		GrowthMeshes._tube(st, previous, p, lerpf(45.0, 12.0, t_prev), lerpf(45.0, 12.0, t), 6,
				stalk.lerp(tip, t_prev), stalk.lerp(tip, t), 0.0, 0.0, 0.0, 0.0, false)
		if s % 2 == 0:
			GrowthMeshes._blob(st, p + Vector3(30.0, 0.0, 0.0).rotated(Vector3.UP, s * 2.0), random.randf_range(30.0, 60.0),
					Color(0.5, 0.85, 0.95), 0.0, 1.0)
		previous = p


## A coil of black vines wound into a column a kilometre and a half high.
static func _vines(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var height := random.randf_range(1200.0, 1800.0)
	var black := Color(0.04, 0.03, 0.05)
	var sheen := Color(0.14, 0.10, 0.16)
	for v in 6:
		var phase := TAU * v / 6.0
		var turns := random.randf_range(1.5, 2.5) * (1.0 if v % 2 == 0 else -1.0)
		var coil := random.randf_range(60.0, 110.0)
		var thick := random.randf_range(25.0, 45.0)
		var previous := Vector3(cos(phase) * coil, -20.0, sin(phase) * coil)
		var steps := 16
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var angle := phase + t * turns * TAU
			var p := Vector3(cos(angle) * coil * (1.0 - t * 0.4), t * height, sin(angle) * coil * (1.0 - t * 0.4))
			GrowthMeshes._tube(st, previous, p, thick * (1.0 - (t - 1.0 / steps) * 0.6), thick * (1.0 - t * 0.6), 5,
					black, black.lerp(sheen, float(s % 2)), 0.0, 0.0, 0.0, 0.0, false)
			previous = p


## A loop of land: a ring of rock standing on edge, half sunk, so big a ship
## could fly through the hole.
static func _loop(st: SurfaceTool, random: RandomNumberGenerator) -> void:
	var radius := random.randf_range(700.0, 1000.0)
	var thick := random.randf_range(70.0, 110.0)
	var rock := Color(0.18, 0.15, 0.17)
	var moss := Color(0.14, 0.20, 0.10)
	var centre := Vector3(0.0, radius * 0.6, 0.0)
	var steps := 28
	var previous := centre + Vector3(radius, 0.0, 0.0)
	for s in range(1, steps + 1):
		var angle := TAU * s / steps
		var wobble := 1.0 + sin(angle * 5.0) * 0.06
		var p := centre + Vector3(cos(angle), sin(angle), 0.0) * radius * wobble
		var color := rock.lerp(moss, 0.5 + 0.5 * sin(angle * 3.0))
		GrowthMeshes._tube(st, previous, p, thick, thick, 7, color, color, 0.0, 0.0, 0.0, 0.0, false)
		previous = p


## Tiny lights scattered up a giant's height (what tells you its size):
## `count` of them, `shrink` = how much it narrows to its top.
static func _lights(st: SurfaceTool, random: RandomNumberGenerator, height: float, base_radius: float, shrink: float,
		count: int, color: Color = Color(1.0, 0.45, 0.25)) -> void:
	for i in count:
		var t := random.randf_range(0.05, 0.95)
		var angle := random.randf() * TAU
		var r := base_radius * lerpf(1.0, shrink, t) * 1.01
		var at := Vector3(cos(angle) * r, t * height, sin(angle) * r)
		GrowthMeshes._blob(st, at, random.randf_range(2.5, 5.0), color, 0.0, 1.0, Vector3.ONE, false)
