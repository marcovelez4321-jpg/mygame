class_name BiomeMap
extends Resource

## Which biome is where in the open world (docs/WORLD.md). The sewer/hive land
## the insects overran is almost everywhere; the purple reef comes in pockets
## (reef_share of the land), with soft borders border_width wide between them.
## Baked once with the world (tools/make_test_world.gd) into a small grey map:
## white = reef, black = sewer, grey = the border. Everything that changes by
## biome reads the same map, so they all cross over in the same place:
##   the ground's colours (alien_terrain.gdshader, through TerrainLook),
##   which growths grow (GrowthScatter: each kind keeps to its biome and they
##   mix at the border),
##   and the air (BiomeAtmosphere: fog, ambient and sky blend as you walk).

## The map (one byte a pixel: 0 = sewer, 255 = reef) and the world area it
## covers (x/z, metres).
@export var image: Image
@export var area: Rect2
## The map as a texture for the ground shader, kept in the same file (so a
## scene that uses it, e.g. the Terrain3D material in the editor, points at
## it rather than carrying a copy).
@export var map_texture: ImageTexture

var _bytes := PackedByteArray()
var _width := 0
var _height := 0
var _texture: ImageTexture


## Builds the map for a world covering `area`, a pixel per `pixel_metres`.
## biome_size = how big the reef pockets and the sewer between them come
## (metres, roughly); reef_share = how much of the land is reef (0..1);
## border_width = how wide the blend between them is (metres).
## `keep_sewer` = a circle (x, z, radius) that's always sewer (the yard).
static func generate(world_area: Rect2, seed: int, pixel_metres: float = 8.0, biome_size: float = 700.0,
		reef_share: float = 0.25, border_width: float = 150.0, keep_sewer: Vector3 = Vector3.ZERO) -> BiomeMap:
	var width := maxi(int(world_area.size.x / pixel_metres), 2)
	var height := maxi(int(world_area.size.y / pixel_metres), 2)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / biome_size
	noise.fractal_octaves = 3
	var raw := PackedFloat32Array()
	raw.resize(width * height)
	for y in height:
		for x in width:
			var world := world_area.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * pixel_metres
			var value := noise.get_noise_2dv(world)
			if keep_sewer.z > 0.0:
				# Pushed down round the yard, fading out over a border's width.
				var near := smoothstep(keep_sewer.z + border_width, keep_sewer.z, world.distance_to(Vector2(keep_sewer.x, keep_sewer.y)))
				value -= near * 2.0
			raw[y * width + x] = value
	# The level the reef starts at: whatever leaves reef_share of the land above it.
	var sorted := raw.duplicate()
	sorted.sort()
	var threshold := sorted[clampi(int((1.0 - reef_share) * sorted.size()), 0, sorted.size() - 1)]
	var mask := PackedFloat32Array()
	mask.resize(width * height)
	for i in raw.size():
		mask[i] = 1.0 if raw[i] > threshold else 0.0
	# Soft borders: blurred three times (close to a gaussian) so the blend is
	# border_width wide.
	var reach := maxi(int(border_width / pixel_metres / 3.0), 1)
	for pass_index in 3:
		mask = _blur(mask, width, height, reach, true)
		mask = _blur(mask, width, height, reach, false)
	var bytes := PackedByteArray()
	bytes.resize(width * height)
	for i in mask.size():
		bytes[i] = clampi(roundi(mask[i] * 255.0), 0, 255)
	var map := BiomeMap.new()
	map.image = Image.create_from_data(width, height, false, Image.FORMAT_L8, bytes)
	map.area = world_area
	map.map_texture = ImageTexture.create_from_image(map.image)
	return map


## One box-blur pass along rows (or columns), `reach` pixels each way.
static func _blur(values: PackedFloat32Array, width: int, height: int, reach: int, rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	var lines := height if rows else width
	var length := width if rows else height
	for line in lines:
		var sum := 0.0
		var count := 0
		# A running sum along the line: add the pixel coming in, drop the one going out.
		for i in range(-reach, length + reach):
			var adding := i + reach
			if adding < length:
				sum += values[line * width + adding] if rows else values[adding * width + line]
				count += 1
			var dropping := i - reach - 1
			if dropping >= 0:
				sum -= values[line * width + dropping] if rows else values[dropping * width + line]
				count -= 1
			if i >= 0 and i < length:
				var index := line * width + i if rows else i * width + line
				out[index] = sum / maxf(count, 1)
	return out


## How much reef is at world x/z: 0 = sewer, 1 = reef, between at a border.
## Outside the map: sewer.
func reef(x: float, z: float) -> float:
	if _bytes.is_empty():
		if image == null:
			return 0.0
		_bytes = image.get_data()
		_width = image.get_width()
		_height = image.get_height()
	var u := (x - area.position.x) / area.size.x * _width - 0.5
	var v := (z - area.position.y) / area.size.y * _height - 0.5
	var x0 := clampi(floori(u), 0, _width - 1)
	var y0 := clampi(floori(v), 0, _height - 1)
	var x1 := mini(x0 + 1, _width - 1)
	var y1 := mini(y0 + 1, _height - 1)
	var fx := clampf(u - floorf(u), 0.0, 1.0)
	var fy := clampf(v - floorf(v), 0.0, 1.0)
	var top := lerpf(_bytes[y0 * _width + x0], _bytes[y0 * _width + x1], fx)
	var bottom := lerpf(_bytes[y1 * _width + x0], _bytes[y1 * _width + x1], fx)
	return lerpf(top, bottom, fy) / 255.0


## The map as a texture, for the ground shader.
func texture() -> ImageTexture:
	if map_texture:
		return map_texture
	if _texture == null and image != null:
		_texture = ImageTexture.create_from_image(image)
	return _texture


## The area as the ground shader takes it: (x, z, width, depth).
func area_vector() -> Vector4:
	return Vector4(area.position.x, area.position.y, area.size.x, area.size.y)
