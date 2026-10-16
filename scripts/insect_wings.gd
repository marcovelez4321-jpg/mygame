class_name InsectWings
extends Node3D

## The insect wings (the user's: the wings that replace the dash --
## PlayerMovement.flying). A placeholder until there's a model: two pairs of
## pale, veined, see-through wings made in code, beating in a blur while they
## fly, and a buzz.
##   On a body (first_person off): on the back, a 3D buzz from there.
##   In first person: beside your head, lying flat, resting just past the
##   screen's sides (a 90-degree view) -- each beat swings the tips in, so
##   they flicker at the lower left and right edges, never near the
##   crosshair (the user's) -- and the buzz in your ears; your hands drop
##   (Viewmodel's flight dip).
## First person: where they rest, swept forward from straight out
## (degrees), and how far each beat swings them in.
const FP_REST_DEGREES := 38.0
const FP_BEAT_DEGREES := 8.0
## Presentation only (Rule 1): it just follows the player's `flying`.

## Beats a second, and how far each beat swings (degrees).
@export var beat_rate: float = 28.0
@export var beat_swing: float = 38.0
## The buzz's loudness (dB).
@export var buzz_volume_db: float = -10.0

var first_person := false

var _player: PlayerMovement
var _wings: Array[Node3D] = []
var _buzz: Node
var _time := 0.0
var _open := 0.0

static var _buzz_stream: AudioStreamWAV
static var _look: StandardMaterial3D


## Builds them for `player`: on its back (a body), or behind its view.
func setup(player: PlayerMovement, in_first_person: bool) -> void:
	_player = player
	first_person = in_first_person
	for side: float in [-1.0, 1.0]:
		for pair in 2: # fore and hind wings
			var hinge := Node3D.new()
			if first_person:
				hinge.position = Vector3(side * 0.2, -0.12 - pair * 0.04, 0.05)
			else:
				hinge.position = Vector3(side * 0.06, 0.05 - pair * 0.12, 0.0)
			add_child(hinge)
			var wing := MeshInstance3D.new()
			var quad := QuadMesh.new()
			if first_person:
				quad.size = Vector2(0.6 - pair * 0.1, 0.18 - pair * 0.03)
			else:
				quad.size = Vector2(0.75 - pair * 0.15, 0.22 - pair * 0.04)
			wing.mesh = quad
			wing.material_override = _material()
			wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wing.position = Vector3(side * quad.size.x * 0.5, 0.0, 0.0)
			if first_person:
				wing.rotation.x = -PI * 0.5 # lying flat, seen from above
			hinge.add_child(wing)
			hinge.set_meta(&"side", side)
			hinge.set_meta(&"pair", pair)
			_wings.append(hinge)
	if first_person:
		_buzz = AudioStreamPlayer.new()
	else:
		var buzz := AudioStreamPlayer3D.new()
		buzz.unit_size = 6.0
		_buzz = buzz
	_buzz.set("stream", _make_buzz())
	# With the footsteps and the rest of moving (the user's).
	_buzz.set("bus", &"Surface" if AudioServer.get_bus_index(&"Surface") != -1 else &"Master")
	_buzz.set("volume_db", -80.0)
	add_child(_buzz)
	visible = false


func _process(delta: float) -> void:
	if _player == null:
		return
	var flying := _player.flying
	_open = move_toward(_open, 1.0 if flying else 0.0, delta * 8.0)
	visible = _open > 0.01
	if not visible:
		if _buzz.get("playing"):
			_buzz.call("stop")
		return
	_time += delta
	for hinge in _wings:
		var side: float = hinge.get_meta(&"side")
		var pair: int = hinge.get_meta(&"pair")
		if first_person:
			# Resting just past the screen's sides; each beat swings the tips in.
			var wave := sin(_time * TAU * beat_rate + pair * 1.4)
			var sweep := deg_to_rad(FP_REST_DEGREES + FP_BEAT_DEGREES * (0.5 + 0.5 * wave) + pair * 3.0)
			hinge.rotation = Vector3(wave * 0.35, side * sweep, 0.0)
			hinge.scale = Vector3.ONE * maxf(_open, 0.01)
			continue
		var beat := sin(_time * TAU * beat_rate + pair * 1.4) * deg_to_rad(beat_swing) * _open
		# Swept back and out as they open, then beating up and down.
		hinge.rotation = Vector3(0.0, side * deg_to_rad(25.0 + pair * 15.0) * _open, side * (beat + deg_to_rad(10.0)))
		hinge.scale = Vector3.ONE * maxf(_open, 0.01)
	if not _buzz.get("playing"):
		_buzz.call("play")
	_buzz.set("volume_db", buzz_volume_db + linear_to_db(maxf(_open, 0.0001)))
	_buzz.set("pitch_scale", 0.95 + randf() * 0.1)


## Pale, see-through, veined (a checker of fine lines standing in for veins).
static func _material() -> StandardMaterial3D:
	if _look == null:
		_look = StandardMaterial3D.new()
		_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_look.cull_mode = BaseMaterial3D.CULL_DISABLED
		_look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_look.albedo_color = Color(0.82, 0.88, 0.8, 0.32)
		var veins := Image.create(32, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 32:
				var vein := x % 8 == 0 or y % 5 == 0 or (x + y * 2) % 13 == 0
				veins.set_pixel(x, y, Color(0.35, 0.4, 0.3, 0.9) if vein else Color(1, 1, 1, 0.55))
		_look.albedo_texture = ImageTexture.create_from_image(veins)
		_look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return _look


## The buzz (loopable): a fast rasping tone, beating at the wings' rate.
static func _make_buzz() -> AudioStreamWAV:
	if _buzz_stream:
		return _buzz_stream
	var rate := 22050
	var frames := rate # 1 s
	var data := PackedByteArray()
	data.resize(frames * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	for i in frames:
		var t := float(i) / rate
		var tone := fposmod(t * 150.0, 1.0) * 2.0 - 1.0 # a rasp (sawtooth)
		var beat := 0.55 + 0.45 * sin(t * TAU * 28.0)
		var sample := (tone * 0.6 + noise.randf_range(-1.0, 1.0) * 0.25) * beat * 0.5
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	_buzz_stream = AudioStreamWAV.new()
	_buzz_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_buzz_stream.mix_rate = rate
	_buzz_stream.data = data
	_buzz_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_buzz_stream.loop_end = frames
	return _buzz_stream