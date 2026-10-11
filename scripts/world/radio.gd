class_name Radio
extends RigidBody3D

## An old radio left playing in a window room (the user's: one of the
## entertainment pack's four radios, a physics prop you pick up and throw
## with F, music from a folder the user fills). Horror-movie sound: far off,
## the song reaches you only as a muffled echo rolling through the halls;
## closer, the echo thins and the radio's own thin, crackly AM voice comes
## through, clear at the radio itself. It keeps playing wherever it's thrown.
##
## Two voices play the same song in step:
##   the radio's VOICE (bus RadioVoice: band-limited and a little lo-fi --
##   an old speaker), heard out to voice_reach;
##   the hall's ECHO (bus RadioEcho: muffled, delayed, a huge reverb), heard
##   out to echo_reach, fading as you come close (echo_near_db..echo_far_db).
## Both feed the Music bus: its own volume slider, apart from Ambience.
## A radio only plays while you're within echo_reach (+ a margin); when you
## come back it picks the song up where it "would be" by now, like a
## broadcast that never stopped -- so a building full of them costs nothing
## where nobody is.
## Rule 1 (co-op): sound is local, but the song and where it's up to are
## seeded from the radio's place, so both players hear the same thing.

## The songs: every audio file in this folder (the user drops them in).
const MUSIC_FOLDER := "res://audio/music/radio"
const MODEL_SCENE := "res://art/Entertainment/Models/Entertainment.fbx"
## The pack's radios (Entertainment.fbx), any of which it can be.
const MODELS: Array[String] = ["Radio", "Radio_01", "Radio_02", "Radio_03"]
const VOICE_BUS := &"RadioVoice"
const ECHO_BUS := &"RadioEcho"
const CHECK_EVERY := 0.5

## Which of MODELS it is (-1: picked from its place).
@export var model_index: int = -1
@export var voice_volume_db: float = 0.0
@export var voice_reach: float = 45.0
@export var echo_reach: float = 220.0
## The echo's loudness right at the radio and from far off: it's what
## carries the song through the halls, and it thins as you come close.
@export var echo_near_db: float = -14.0
@export var echo_far_db: float = 2.0
## Where the echo's at its fullest (m away).
@export var echo_full_at: float = 70.0

static var _models: Node3D
static var _songs: Array[AudioStream] = []
static var _songs_loaded := false

var _voice: AudioStreamPlayer3D
var _echo: AudioStreamPlayer3D
var _song: AudioStream
var _offset := 0.0
var _check_left := 0.0


func _ready() -> void:
	mass = 4.0
	can_sleep = true
	var seed_from := hash(Vector3i(global_position.round()))
	if model_index < 0:
		model_index = absi(seed_from) % MODELS.size()
	_build_model(MODELS[model_index % MODELS.size()])
	_ensure_buses()
	var songs := _load_songs()
	if songs.is_empty():
		return # no music yet: just a radio
	_song = songs[absi(seed_from / 7) % songs.size()]
	_offset = float(absi(seed_from) % 10007)
	_voice = _player(VOICE_BUS, voice_reach, 3.0, voice_volume_db)
	_echo = _player(ECHO_BUS, echo_reach, 22.0, echo_far_db)
	_echo.attenuation_filter_cutoff_hz = 2500.0 # further still: more muffled
	_echo.attenuation_filter_db = -18.0
	_check_left = randf() * CHECK_EVERY


func _player(bus: StringName, reach: float, unit: float, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _song
	player.bus = bus
	player.max_distance = reach
	player.unit_size = unit
	player.volume_db = volume
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.finished.connect(_play_from_start.bind(player))
	add_child(player)
	return player


func _process(delta: float) -> void:
	if _song == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	# The echo thins as you come close: the radio's own voice takes over.
	var far := smoothstep(4.0, echo_full_at, distance)
	_echo.volume_db = lerpf(echo_near_db, echo_far_db, far)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	if distance < echo_reach and not _echo.playing:
		var at := _broadcast_time()
		_voice.play(at)
		_echo.play(at)
	elif distance > echo_reach + 30.0 and _echo.playing:
		_voice.stop()
		_echo.stop()


## Where the song is up to: as if it's been playing since the game began.
func _broadcast_time() -> float:
	var length := _song.get_length()
	if length <= 0.0:
		return 0.0
	return fmod(Time.get_ticks_msec() / 1000.0 + _offset, length)


func _play_from_start(player: AudioStreamPlayer3D) -> void:
	player.play(0.0)


## One of the pack's radios: its mesh (materials and all), centred on this
## body, a box round it to collide with, and the PS1 look like everything else.
func _build_model(model_name: String) -> void:
	if _models == null:
		_models = (load(MODEL_SCENE) as PackedScene).instantiate() as Node3D
	var source := _models.find_child(model_name, true, false) as MeshInstance3D
	if source == null:
		return
	var placed := _place_of(source)
	var box := source.get_aabb()
	var look := MeshInstance3D.new()
	look.name = "Model"
	look.mesh = source.mesh
	for surface in source.get_surface_override_material_count():
		look.set_surface_override_material(surface, source.get_surface_override_material(surface))
	look.transform = Transform3D(placed.basis, -(placed.basis * box.get_center()))
	add_child(look)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = (placed.basis * box.size).abs()
	shape.shape = collider
	add_child(shape)
	PS1Look.apply(look)


static func _place_of(node: Node3D) -> Transform3D:
	var place := node.transform
	var parent := node.get_parent() as Node3D
	while parent:
		place = parent.transform * place
		parent = parent.get_parent() as Node3D
	return place


## Every audio file in MUSIC_FOLDER (in an exported game the folder lists
## their .import files, so those count as the songs too).
static func _load_songs() -> Array[AudioStream]:
	if _songs_loaded:
		return _songs
	_songs_loaded = true
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(MUSIC_FOLDER):
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in ["ogg", "mp3", "wav"] and not names.has(name):
			names.append(name)
	names.sort()
	for name in names:
		var stream := load(MUSIC_FOLDER.path_join(name)) as AudioStream
		if stream:
			_songs.append(stream)
	return _songs


## The two radio buses, made once: the VOICE an old speaker (no lows, no
## highs, a little lo-fi grit); the ECHO the halls (muffled, two long
## delays, a vast reverb, all wet). Both feed Music, so its volume slider
## sets theirs (not Ambience's: the user's).
static func _ensure_buses() -> void:
	if AudioServer.get_bus_index(VOICE_BUS) == -1:
		var voice := _add_bus(VOICE_BUS)
		var low_cut := AudioEffectHighPassFilter.new()
		low_cut.cutoff_hz = 380.0
		var high_cut := AudioEffectLowPassFilter.new()
		high_cut.cutoff_hz = 3600.0
		var grit := AudioEffectDistortion.new()
		grit.mode = AudioEffectDistortion.MODE_LOFI
		grit.drive = 0.22
		grit.post_gain = -2.0
		for effect: AudioEffect in [low_cut, high_cut, grit]:
			AudioServer.add_bus_effect(voice, effect)
	if AudioServer.get_bus_index(ECHO_BUS) == -1:
		var echo := _add_bus(ECHO_BUS)
		var low_cut := AudioEffectHighPassFilter.new()
		low_cut.cutoff_hz = 180.0
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 1800.0
		var delay := AudioEffectDelay.new()
		delay.dry = 0.6
		delay.tap1_delay_ms = 340.0
		delay.tap1_level_db = -7.0
		delay.tap2_delay_ms = 610.0
		delay.tap2_level_db = -11.0
		delay.feedback_active = true
		delay.feedback_delay_ms = 820.0
		delay.feedback_level_db = -14.0
		var hall := AudioEffectReverb.new()
		hall.room_size = 1.0
		hall.damping = 0.35
		hall.spread = 1.0
		hall.predelay_msec = 90.0
		hall.predelay_feedback = 0.5
		hall.wet = 0.9
		hall.dry = 0.15
		for effect: AudioEffect in [low_cut, muffle, delay, hall]:
			AudioServer.add_bus_effect(echo, effect)


static func _add_bus(bus_name: StringName) -> int:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	var send := &"Music" if AudioServer.get_bus_index(&"Music") != -1 else &"Master"
	AudioServer.set_bus_send(index, send)
	return index
