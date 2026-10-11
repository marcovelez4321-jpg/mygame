class_name Radio
extends RigidBody3D

## An old radio left playing in a window room (the user's: one of the
## entertainment pack's four radios, a physics prop you pick up and throw
## with F, music from a folder the user fills). Horror-movie sound: far off,
## the song reaches you only as a muffled echo rolling through the halls;
## nearer, the radio's own thin, crackly AM voice comes through; right by it,
## the song is clear -- and the closer you get, the less it echoes. It keeps
## playing wherever it's thrown.
##
## Three voices play the song in step, mixed by how far you are (_mix_by):
##   CLEAR (bus RadioClear: only the lowest rumble cut) -- up close;
##   TINNY (bus RadioVoice: band-limited, a little lo-fi -- an old speaker)
##   -- the middle distance;
##   ECHO (bus RadioEcho: muffled, delayed, a huge reverb) -- far off, and
##   almost gone right by the radio.
## Never two songs at once (the user's): only the nearest radio in earshot
## plays (the one in charge changes only when another's clearly nearer, so
## it doesn't flicker between two); the old one fades out as the new one
## fades in.
## Cheap: a radio that isn't the one playing has its players stopped; the
## one playing picks its song up where it "would be" by now, like a
## broadcast that never stopped.
## Rule 1 (co-op): sound is local, but the song and where it's up to are
## seeded from the radio's place, so both players hear the same thing.

## The songs: every audio file in this folder (the user drops them in).
const MUSIC_FOLDER := "res://audio/music/radio"
const MODEL_SCENE := "res://art/Entertainment/Models/Entertainment.fbx"
## The pack's radios (Entertainment.fbx), any of which it can be.
const MODELS: Array[String] = ["Radio", "Radio_01", "Radio_02", "Radio_03"]
const CLEAR_BUS := &"RadioClear"
const VOICE_BUS := &"RadioVoice"
const ECHO_BUS := &"RadioEcho"
## How often it's worked out which radio plays, and how much nearer another
## has to be to take over (a share of the distance).
const CHOOSE_EVERY_MSEC := 400
const TAKE_OVER_MARGIN := 0.8
## How fast one fades in or out when the radio in charge changes (per second).
const HANDOVER_SPEED := 0.8

## Which of MODELS it is (-1: picked from its place).
@export var model_index: int = -1
## How far it can be heard at all (the echo's reach).
@export var echo_reach: float = 220.0
## Loudness of each voice at its best (dB).
@export var clear_volume_db: float = 2.0
@export var voice_volume_db: float = -2.0
@export var echo_volume_db: float = 0.0
## The crossfade: clear inside clear_until (m), tinny out to tinny_until,
## echo fullest from echo_full_at; the echo right at the radio (dB).
@export var clear_until: float = 6.0
@export var tinny_until: float = 45.0
@export var echo_full_at: float = 80.0
@export var echo_near_db: float = -30.0

static var _models: Node3D
static var _songs: Array[AudioStream] = []
static var _songs_loaded := false
static var _all: Array[Radio] = []
## The one radio playing, and when that was last worked out.
static var _playing: Radio
static var _chosen_msec := -100000

var _clear: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _echo: AudioStreamPlayer3D
var _song: AudioStream
var _offset := 0.0
## 0..1: how much of it you hear (the handover fade).
var _fade := 0.0


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
	_clear = _player(CLEAR_BUS, tinny_until, 3.0)
	_voice = _player(VOICE_BUS, tinny_until + 20.0, 5.0)
	_echo = _player(ECHO_BUS, echo_reach, 22.0)
	_echo.attenuation_filter_cutoff_hz = 2500.0 # further still: more muffled
	_echo.attenuation_filter_db = -18.0
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)
	if _playing == self:
		_playing = null


func _player(bus: StringName, reach: float, unit: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _song
	player.bus = bus
	player.max_distance = reach
	player.unit_size = unit
	player.volume_db = -80.0
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
	_choose(camera.global_position)
	var mine := _playing == self
	_fade = move_toward(_fade, 1.0 if mine else 0.0, HANDOVER_SPEED * delta)
	if _fade <= 0.0:
		if _echo.playing:
			_clear.stop()
			_voice.stop()
			_echo.stop()
		return
	if not _echo.playing:
		var at := _broadcast_time()
		for player in [_clear, _voice, _echo]:
			(player as AudioStreamPlayer3D).play(at)
	_mix_by(camera.global_position.distance_to(global_position))


## The three voices for being `distance` away: clear up close, the tinny
## radio further, the echo furthest -- and hardly any echo right by it.
func _mix_by(distance: float) -> void:
	var to_tinny := smoothstep(clear_until * 0.5, clear_until * 2.0, distance)
	var to_echo := smoothstep(clear_until, echo_full_at, distance)
	var fade := linear_to_db(maxf(_fade, 0.0001))
	_clear.volume_db = clear_volume_db + linear_to_db(maxf(1.0 - to_tinny, 0.0001)) + fade
	_voice.volume_db = voice_volume_db + linear_to_db(maxf(to_tinny * (1.0 - smoothstep(tinny_until * 0.7, tinny_until, distance) * 0.7), 0.0001)) + fade
	_echo.volume_db = lerpf(echo_near_db, echo_volume_db, to_echo) + fade


## Which radio plays: the nearest one in earshot. Worked out once in a while
## for all of them (whichever radio asks first); another takes over only
## when it's clearly nearer, or the one playing is out of earshot.
static func _choose(listener: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - _chosen_msec < CHOOSE_EVERY_MSEC:
		return
	_chosen_msec = now
	var best: Radio = null
	var best_distance := INF
	for radio in _all:
		if not is_instance_valid(radio) or radio._song == null:
			continue
		var distance := listener.distance_to(radio.global_position)
		if distance < radio.echo_reach and distance < best_distance:
			best = radio
			best_distance = distance
	if best == null:
		_playing = null
		return
	if is_instance_valid(_playing) and _playing != best:
		var current := listener.distance_to(_playing.global_position)
		if current < _playing.echo_reach and best_distance > current * TAKE_OVER_MARGIN:
			return # not clearly nearer: the one playing keeps going
	_playing = best


## Where the song is up to: as if it's been playing since the game began.
func _broadcast_time() -> float:
	var length := _song.get_length()
	if length <= 0.0:
		return 0.0
	return fmod(Time.get_ticks_msec() / 1000.0 + _offset, length)


func _play_from_start(player: AudioStreamPlayer3D) -> void:
	if _fade > 0.0:
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


## The radio buses, made once: CLEAR the song itself (just the lowest rumble
## cut); VOICE an old speaker (no lows, no highs, a little lo-fi grit); ECHO
## the halls (muffled, two long delays, a vast reverb, all wet). All feed
## Music, so its volume slider sets theirs (not Ambience's: the user's).
static func _ensure_buses() -> void:
	if AudioServer.get_bus_index(CLEAR_BUS) == -1:
		var clear := _add_bus(CLEAR_BUS)
		var rumble_cut := AudioEffectHighPassFilter.new()
		rumble_cut.cutoff_hz = 90.0
		AudioServer.add_bus_effect(clear, rumble_cut)
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
