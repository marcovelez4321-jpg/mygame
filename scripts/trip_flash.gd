class_name TripFlash
extends CanvasLayer

## Feeding off the virus (Virus.fed_raw): an ANEURISM IV-style flash (the
## user's, 2026-10-15). For TIME seconds one of the user's sharp abstract
## images (IMAGE_DIR -- black until there are some) covers the screen,
## shaking and tearing, with a harsh noise burst and a heartbeat thump; raw
## meat adds TEXT, big jittering scratchy red-white lowercase. You can't see,
## but you can still move.
## Your own screen only (Rule 1: presentation). Built once and reused: the
## overlay, its shader, the sound; one image picked and loaded per flash.

const TIME := 1.5
const IMAGE_DIR := "res://art/trip"
const TEXT := "i shouldve cooked that"
const TEXT_SIZE := 72
## How hard the text and image jitter (pixels).
const JITTER := 14.0

const SHADER_CODE := "
shader_type canvas_item;
uniform float tear = 0.0;
uniform float seed = 0.0;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	// Horizontal tears: bands of the image shoved sideways.
	float band = floor(uv.y * 24.0);
	uv.x += (hash(band + seed) - 0.5) * 0.12 * tear;
	// The colours pulled apart.
	float split = 0.012 * tear;
	vec4 r = texture(TEXTURE, uv + vec2(split, 0.0));
	vec4 g = texture(TEXTURE, uv);
	vec4 b = texture(TEXTURE, uv - vec2(split, 0.0));
	vec3 colour = vec3(r.r, g.g, b.b);
	// Stark, harsh contrast.
	colour = clamp((colour - 0.5) * (1.0 + tear) + 0.5, 0.0, 1.0);
	COLOR = vec4(colour, 1.0);
}
"

var _player: PlayerMovement
var _black: ColorRect
var _image: TextureRect
var _text: Label
var _sound: AudioStreamPlayer
var _left := 0.0
var _images: Array[String] = []

static var _shader: Shader
static var _burst: AudioStreamWAV


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	if _player == null or not _player.is_multiplayer_authority():
		queue_free()
		return
	layer = 90
	visible = false
	set_process(false)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_image = TextureRect.new()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	_image.material = material
	add_child(_image)
	_text = Label.new()
	_text.text = TEXT
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", TEXT_SIZE)
	_text.add_theme_color_override("font_color", Color(1.0, 0.95, 0.92))
	_text.add_theme_color_override("font_outline_color", Color(0.75, 0.02, 0.02))
	_text.add_theme_constant_override("outline_size", 18)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_sound = AudioStreamPlayer.new()
	_sound.bus = &"Player" if AudioServer.get_bus_index(&"Player") != -1 else &"Master"
	add_child(_sound)
	_find_images()
	_player.virus.fed_raw.connect(_flash)


## A flash: one image (or black), the text for raw meat, the sound.
func _flash(with_text: bool) -> void:
	_image.texture = null
	if not _images.is_empty():
		_image.texture = load(_images[randi() % _images.size()]) as Texture2D
	_text.visible = with_text
	if _burst == null:
		_burst = _make_burst()
	_sound.stream = _burst
	_sound.play()
	_left = TIME
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		visible = false
		_image.texture = null # (let it go)
		set_process(false)
		return
	var tear := 0.6 + 0.4 * sin(_left * 37.0)
	(_image.material as ShaderMaterial).set_shader_parameter(&"tear", tear)
	(_image.material as ShaderMaterial).set_shader_parameter(&"seed", floorf(_left * 30.0))
	var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * JITTER
	_image.position = shake
	_image.scale = Vector2.ONE * (1.04 + 0.04 * sin(_left * 23.0))
	_image.pivot_offset = _image.size * 0.5
	_text.position = -shake * 0.8
	_text.rotation = randf_range(-0.03, 0.03)
	_text.pivot_offset = _text.size * 0.5
	# Flicks between white-hot and bloody.
	_text.modulate = Color(1, 1, 1) if randf() < 0.6 else Color(1.0, 0.3, 0.3)


## The user's images in IMAGE_DIR (looked up once).
func _find_images() -> void:
	if not DirAccess.dir_exists_absolute(IMAGE_DIR):
		return
	for file in ResourceLoader.list_directory(IMAGE_DIR):
		if file.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "bmp"]:
			_images.append(IMAGE_DIR.path_join(file))


## A harsh noise burst over a low heartbeat thump (a stand-in sound).
static func _make_burst() -> AudioStreamWAV:
	var rate := 22050
	var frames := int(TIME * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var phase := 0.0
	for i in frames:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0) * maxf(1.0 - t / 0.6, 0.0)
		# Screech: a falling square-ish tone inside the noise.
		phase += TAU * lerpf(1800.0, 400.0, minf(t / TIME, 1.0)) / rate
		var screech := signf(sin(phase)) * 0.25 * maxf(1.0 - t / 0.9, 0.0)
		# Two heartbeat thumps.
		var beat := 0.0
		for at: float in [0.15, 0.5]:
			var u := t - at
			if u >= 0.0 and u < 0.25:
				beat += sin(TAU * 55.0 * u) * exp(-u * 18.0)
		var sample := noise * 0.45 + screech + beat * 0.9
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
