class_name BiomeMap extends Resource

@export var image: Image
@export var area: Rect2
@export var map_texture: ImageTexture

var _bytes := PackedByteArray()
var _width := 0
var _height := 0

static func generate(world_area: Rect2, seed: int, pixel_metres: float = 8.0, biome_size: float = 700.0, reef_share: float = 0.25, border_width: float = 150.0, keep_sewer: Vector3 = Vector3.ZERO) -> BiomeMap:
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
				var near := smoothstep(keep_sewer.z + border_width, keep_sewer.z, world.distance_to(Vector2(keep_sewer.x, keep_sewer.y)))
				value -= near * 2.0
			raw[y * width + x] = value
			
	var sorted := raw.duplicate()
	sorted.sort()
	var threshold := sorted[clampi(int((1.0 - reef_share) * sorted.size()), 0, sorted.size() - 1)]
	
	var mask := PackedFloat32Array()
	mask.resize(width * height)
	for i in raw.size():
		mask[i] = 1.0 if raw[i] > threshold else 0.0
		
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

static func _blur(values: PackedFloat32Array, width: int, height: int, reach: int, rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	var lines := height if rows else width
	var length := width if rows else height
	
	for line in lines:
		var sum := 0.0
		var count := 0
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

func reef(x: float, z: float) -> float:
	# 1. Immediate out-of-bounds check (skips math entirely if outside map)
	if not area.has_point(Vector2(x, z)):
		return 0.0

	if _bytes.is_empty():
		if image == null:
			return 0.0
		_bytes = image.get_data()
		_width = image.get_width()
		_height = image.get_height()
		
	# 2. Pre-calculate coordinate scaling multipliers to eliminate 2 division operations
	var u := (x - area.position.x) * (_width / area.size.x) - 0.5
	var v := (z - area.position.y) * (_height / area.size.y) - 0.5
	
	# 3. Cache floor and clamp calculations to avoid repeating them
	var floor_u := floorf(u)
	var floor_v := floorf(v)
	
	var x0 := clampi(int(floor_u), 0, _width - 1)
	var y0 := clampi(int(floor_v), 0, _height - 1)
	var x1 := mini(x0 + 1, _width - 1)
	var y1 := mini(y0 + 1, _height - 1)
	
	var fx := clampf(u - floor_u, 0.0, 1.0)
	var fy := clampf(v - floor_v, 0.0, 1.0)
	
	# 4. Cache row index offsets to eliminate repetitive multiplication math
	var row0 := y0 * _width
	var row1 := y1 * _width
	
	var top := lerpf(_bytes[row0 + x0], _bytes[row0 + x1], fx)
	var bottom := lerpf(_bytes[row1 + x0], _bytes[row1 + x1], fx)
	
	# 5. Only divide by 255 at the very end rather than inside every lookup
	return lerpf(top, bottom, fy) * 0.00392156862 # (1.0 / 255.0)
func texture() -> ImageTexture:
	if map_texture == null and image != null:
		map_texture = ImageTexture.create_from_image(image)
	return map_texture

func area_vector() -> Vector4:
	return Vector4(area.position.x, area.position.y, area.size.x, area.size.y)
