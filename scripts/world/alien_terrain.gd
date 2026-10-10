class_name AlienTerrain
extends Resource

## The procedural half of the hybrid world (docs/WORLD.md): the alien land's
## shape, as a heightmap for Terrain3D. Rolling wave ridges (the land looks
## like a sea that set solid) over warped hills, with the middle flattened
## for Grandma's yard. Hand-made places go on top of this later.
## Variety, so it doesn't read as one repeating pattern:
##   the ridges swell tall in places and fade to nothing in others, their
##   crests change from soft to sharp, and a second, longer swell crosses
##   them where they fade;
##   the hills change height across the land, with rougher craggy ground
##   coming and going between the smooth parts.
## Finally no slope is left steeper than max_slope_degrees: anything steeper
## is slumped back to it, the way loose ground settles.
## Deterministic from `seed`, so every co-op player builds the same ground.

## How many heightmap pixels across (each one is a terrain vertex) and the
## metres between vertices: 256 x 4 m = 1 km. Bigger spacing = bigger,
## flatter triangles (the PS1 look).
@export var size: int = 256
@export var vertex_spacing: float = 4.0
## Terrain3D's region size, in vertices (64..2048, a power of two). The world
## is centred on 0, 0, so this has to divide size in two (or smaller) for the
## regions to line up with it: 128 x 4 m = 512 m regions, 2 x 2 of them.
@export var region_size: int = 128
@export var seed: int = 1987
## Tallest the land gets, in metres.
@export var height: float = 70.0
## Nothing's left steeper than this (degrees). 66.7 = the steepest the
## first version of this land got; 50 since the user found the land away
## from the yard too steep. 45 = everything walkable for the player and enemies.
@export_range(10.0, 80.0, 0.1) var max_slope_degrees: float = 50.0
## How many settling passes the slope limit gets (more = closer to exact).
@export var slope_passes: int = 40

@export_group("Passes")
## Walkable saddles cut through the steep ridges so the land stays one
## connected place for walkers: about one every pass_spacing metres (each
## nudged randomly), pass_radius across, where nothing's steeper than
## pass_slope_degrees (45 = the player's and enemies' walking limit).
@export var pass_spacing: float = 110.0
@export var pass_radius: float = 28.0
@export_range(10.0, 45.0, 0.5) var pass_slope_degrees: float = 40.0

@export_group("Hills")
## Size of the hills (bigger = broader), and how much they're twisted.
@export var hill_scale: float = 250.0 # was 180: hills less often
@export var warp: float = 60.0
@export_range(0.0, 1.0, 0.05) var hill_share: float = 0.6
## How much each hill's height differs from the next (0 = all the same,
## 1 = anything from flat mounds to full height). Hill by hill: the height
## field changes about as fast as the hills themselves do.
@export_range(0.0, 1.0, 0.05) var hill_variation: float = 0.8
## Craggy ground between the smooth hills: its height share, its size, and
## how much of the land it covers.
@export_range(0.0, 1.0, 0.05) var crag_share: float = 0.12
@export var crag_scale: float = 70.0
@export_range(0.0, 1.0, 0.05) var crag_cover: float = 0.25
## How much the distance between hills changes across the land (0 = even,
## 0.6 = from crowded together to well spread out).
@export_range(0.0, 0.9, 0.05) var hill_spacing_variation: float = 0.5

@export_group("Waves")
## The frozen-sea ridges: their spacing (metres), height share, and how much
## they meander.
@export var wave_length: float = 130.0 # was 90: ridges further apart
@export_range(0.0, 1.0, 0.05) var wave_share: float = 0.3
@export var wave_meander: float = 40.0
## How sharp the crests are (1 = a plain rolling sine), and how much
## sharper they get in places.
@export var wave_sharpness: float = 1.0
@export var wave_sharpness_variation: float = 0.4
## How much the ridges' height changes across the land (0 = all the same,
## 1 = from full height down to nothing).
@export_range(0.0, 1.0, 0.05) var wave_variation: float = 0.7
## How much the distance between ridges changes across the land.
@export_range(0.0, 0.9, 0.05) var wave_spacing_variation: float = 0.45
## A second, longer swell crossing the first where it fades.
@export var cross_wave_length: float = 150.0
@export_range(0.0, 1.0, 0.05) var cross_wave_share: float = 0.6

@export_group("Grandma's Yard")
## A flat plateau in the middle (radius, then a gentle edge), at this share
## of the height.
@export var yard_radius: float = 45.0
@export var yard_edge: float = 60.0
@export_range(0.0, 1.0, 0.05) var yard_level: float = 0.45
## More flat places (a megastructure's footing): each (x, z, radius, level
## as a share of the height), easing out to the land over flat_edge metres.
@export var flats: Array[Vector4] = []
@export var flat_edge: float = 250.0


## The heightmap, 0..1 per pixel (Image.FORMAT_RF): height in metres is
## value x `height`. Pixel (0, 0) is the world's -X/-Z corner.
func make_height_image() -> Image:
	var hills := _noise(seed, 1.0 / hill_scale, 4)
	hills.domain_warp_enabled = true
	hills.domain_warp_amplitude = warp
	hills.domain_warp_frequency = 1.0 / (hill_scale * 1.5)
	var hill_height := _noise(seed + 2, 1.0 / (hill_scale * 1.1), 2)
	var crags := _noise(seed + 3, 1.0 / crag_scale, 3)
	crags.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var crag_mask := _noise(seed + 4, 1.0 / (crag_scale * 4.0), 2)
	var meander := _noise(seed + 1, 1.0 / (wave_length * 4.0), 1)
	var wave_height := _noise(seed + 5, 1.0 / (wave_length * 3.5), 2)
	var wave_sharp := _noise(seed + 6, 1.0 / (wave_length * 5.0), 1)
	# Slow fields that stretch and squeeze the land, so hills and ridges sit
	# closer together in some places and further apart in others.
	var hill_spread := _noise(seed + 7, 1.0 / (hill_scale * 4.0), 1)
	var wave_spread := _noise(seed + 8, 1.0 / (wave_length * 6.0), 1)
	var half := size * vertex_spacing * 0.5
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var world := Vector2(x * vertex_spacing - half, y * vertex_spacing - half)
			# Hills, closer together in some parts of the land and further
			# apart in others (the land under them stretched by a slow field),
			# and taller in some parts than others.
			var hill_stretch := 1.0 + hill_spread.get_noise_2dv(world) * hill_spacing_variation
			var hill := _unit(hills.get_noise_2dv(world * hill_stretch))
			hill *= lerpf(1.0, _unit(hill_height.get_noise_2dv(world)), hill_variation)
			# Craggy ground, only where its mask says.
			var crag := _unit(crags.get_noise_2dv(world))
			var crag_here := smoothstep(1.0 - crag_cover, 1.0 - crag_cover + 0.25, _unit(crag_mask.get_noise_2dv(world)))
			# Ridges like frozen swell: a sine across the land, bent by noise
			# so they curve, their height and sharpness changing as they go.
			var spacing := wave_length * (1.0 + wave_spread.get_noise_2dv(world) * wave_spacing_variation)
			var phase := (world.x * 0.8 + world.y * 0.6 + meander.get_noise_2dv(world) * wave_meander) / spacing
			var sharp := wave_sharpness + _unit(wave_sharp.get_noise_2dv(world)) * wave_sharpness_variation
			var swell := lerpf(1.0, _unit(wave_height.get_noise_2dv(world)), wave_variation)
			var wave := pow(sin(phase * TAU) * 0.5 + 0.5, sharp) * swell
			# The crossing swell fills in where the main ridges fade.
			var cross_phase := (world.x * -0.35 + world.y * 0.94) / cross_wave_length
			var cross := (sin(cross_phase * TAU) * 0.5 + 0.5) * (1.0 - swell) * cross_wave_share
			var value := hill * hill_share + crag * crag_share * crag_here + (wave + cross) * wave_share
			heights[y * size + x] = value * height
	_limit_slopes(heights)
	# Grandma's yard: flat in the middle, easing out to the land.
	var image := Image.create(size, size, false, Image.FORMAT_RF)
	for y in size:
		for x in size:
			var world := Vector2(x * vertex_spacing - half, y * vertex_spacing - half)
			var value := heights[y * size + x] / height
			var yard := smoothstep(yard_radius + yard_edge, yard_radius, world.length())
			value = lerpf(value, yard_level, yard)
			for flat in flats:
				var near := smoothstep(flat.z + flat_edge, flat.z, world.distance_to(Vector2(flat.x, flat.y)))
				value = lerpf(value, flat.w, near)
			image.set_pixel(x, y, Color(clampf(value, 0.0, 1.0), 0.0, 0.0))
	return image


## Where the heightmap's corner goes in the world (it's centred on 0, 0).
func corner() -> Vector3:
	var half := size * vertex_spacing * 0.5
	return Vector3(-half, 0.0, -half)


## Settles every slope steeper than allowed back to it: where two
## neighbouring points differ by more than the slope allows, both move
## toward each other by half the excess (a "thermal erosion" pass), until
## nothing's over or the passes run out. Allowed = max_slope_degrees, or
## pass_slope_degrees near a pass (easing between the two at its edge).
func _limit_slopes(heights: PackedFloat32Array) -> void:
	var steps := _allowed_steps()
	for pass_index in slope_passes:
		var moved := false
		for y in size:
			for x in size:
				var i := y * size + x
				if x + 1 < size:
					moved = _settle(heights, i, i + 1, minf(steps[i], steps[i + 1])) or moved
				if y + 1 < size:
					moved = _settle(heights, i, i + size, minf(steps[i], steps[i + size])) or moved
		if not moved:
			return


## Per point: the most its height may differ from a neighbour's (metres).
## The passes sit on a grid pass_spacing apart, each nudged randomly within
## its cell (deterministic from the seed).
func _allowed_steps() -> PackedFloat32Array:
	var steep := tan(deg_to_rad(max_slope_degrees)) * vertex_spacing
	var gentle := tan(deg_to_rad(pass_slope_degrees)) * vertex_spacing
	var random := RandomNumberGenerator.new()
	var half := size * vertex_spacing * 0.5
	var cells := ceili(size * vertex_spacing / pass_spacing) + 1
	var passes: Array[Vector2] = []
	for cy in cells:
		for cx in cells:
			random.seed = hash(Vector3i(seed, cx, cy))
			var jitter := Vector2(random.randf(), random.randf())
			passes.append(Vector2(cx + jitter.x, cy + jitter.y) * pass_spacing - Vector2(half, half))
	var steps := PackedFloat32Array()
	steps.resize(size * size)
	for y in size:
		for x in size:
			var world := Vector2(x * vertex_spacing - half, y * vertex_spacing - half)
			var cell := Vector2i(floori((world.x + half) / pass_spacing), floori((world.y + half) / pass_spacing))
			var nearest := INF
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := cell + Vector2i(dx, dy)
					if c.x >= 0 and c.y >= 0 and c.x < cells and c.y < cells:
						nearest = minf(nearest, world.distance_to(passes[c.y * cells + c.x]))
			var in_pass := smoothstep(pass_radius, pass_radius * 0.5, nearest)
			steps[y * size + x] = lerpf(steep, gentle, in_pass)
	return steps


func _settle(heights: PackedFloat32Array, a: int, b: int, step: float) -> bool:
	var difference := heights[a] - heights[b]
	var excess := absf(difference) - step
	if excess <= 0.0:
		return false
	var shift := excess * 0.5 * signf(difference)
	heights[a] -= shift
	heights[b] += shift
	return true


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	return noise


## -1..1 noise to 0..1.
func _unit(value: float) -> float:
	return clampf(value * 0.5 + 0.5, 0.0, 1.0)
