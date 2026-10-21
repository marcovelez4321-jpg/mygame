class_name StalkerSound
extends RefCounted

## The Stalker's voice (the user's, 2026-10-17). Placeholders made in code
## until the user's own files, bar the help scream (theirs):
##   RATTLE -- Kayako's dry croak: glottal clicks, uneven, swelling and
##   fading, through a throat's resonance.
##   SHRIEK -- driven off: a tearing, rising screech.
##   HELP -- the user's scream (audio/dragon-studio-scary-scream-*.mp3),
##   heard through the halls' echo (HallEcho) from far off.
## Every machine plays them (Network relays the host's), each a little
## different in pitch.

enum Kind { RATTLE, SHRIEK, HELP }

const HELP := preload("res://audio/dragon-studio-scary-scream-401725.mp3")
const RATE := 22050
const UNIT_SIZE := 8.0

## The user's sounds, a slot for everything it does (StalkerVoices).
const VOICES := "res://audio/events/stalker/stalker_voices.tres"
## The user's: every voice line this much faster, its pitch kept the same
## (HallEcho.sped_bus).
const VOICE_SPEED := 1.25

static var _rattles: Array[AudioStreamWAV] = []
static var _voices: StalkerVoices


## The `slot`'s sound (StalkerVoices) at `at`; an empty slot falls back to
## the old made-up sound where there was one (the grab always has one: the
## user's, every grab heard), else stays silent.
## Where it is decides how it sounds (the user's): in a megastructure, through
## the halls' echo; out in the open, dry and clear close by, muffled like a
## distant call further off, and only very far -- out toward the fog line --
## with the echo rolling under it (_open_air).
static func voice(slot: StringName, at: Vector3, world: Node, volume_db: float = 0.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	if _voices == null and ResourceLoader.exists(VOICES):
		_voices = load(VOICES) as StalkerVoices
	var event: SoundEvent = _voices.event(slot) if _voices else null
	var clip: AudioStream = event.pick_clip() if event else null
	if clip:
		if HallEcho.inside(at):
			HallEcho.play(clip, at, world, event.roll_pitch_scale(), event.roll_volume_db() + volume_db, VOICE_SPEED)
		else:
			_open_air(clip, at, world, event.roll_pitch_scale(), event.roll_volume_db() + volume_db)
		return
	match slot:
		&"croak_behind", &"lunge", &"behind_you", &"watching":
			play(Kind.RATTLE, at, world)
		&"driven_off", &"grab":
			play(Kind.SHRIEK, at, world)
		&"help_scream":
			play(Kind.HELP, at, world)


## Out in the open: the call itself, dry close by and muffled the further
## off it is (a distant call); from ECHO_FROM of the way to the fog line out,
## the echo fading in under it -- only the far ones reverberate.
const ECHO_FROM := 0.6
const FOG_FALLBACK := 242.0


static func _open_air(clip: AudioStream, at: Vector3, world: Node, pitch: float, volume_db: float) -> void:
	Radio._ensure_buses()
	var camera := world.get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(at) if camera else 0.0
	var air: Environment = world.get_viewport().world_3d.environment if world.get_viewport().world_3d else null
	var fog_line := air.fog_depth_end if air and air.fog_enabled and air.fog_depth_end > 0.0 else FOG_FALLBACK
	var call := AudioStreamPlayer3D.new()
	call.stream = clip
	call.bus = HallEcho.sped_bus(StalkerSigns.bus(), VOICE_SPEED) # (its own bus: the silence never mutes it)
	call.unit_size = 14.0
	call.max_distance = fog_line * 1.3
	call.volume_db = volume_db
	call.pitch_scale = pitch * VOICE_SPEED
	# Further off, duller: the highs gone, a call from a long way away.
	call.attenuation_filter_cutoff_hz = 2200.0
	call.attenuation_filter_db = -30.0
	world.add_child(call)
	call.global_position = at
	call.finished.connect(call.queue_free)
	call.play()
	var far := smoothstep(fog_line * ECHO_FROM, fog_line, distance)
	if far <= 0.0:
		return
	var echo := AudioStreamPlayer3D.new()
	echo.stream = clip
	echo.bus = HallEcho.sped_bus(Radio.ECHO_BUS, VOICE_SPEED)
	echo.unit_size = 40.0
	echo.max_distance = fog_line * 1.5
	echo.volume_db = volume_db + lerpf(-24.0, 0.0, far)
	echo.pitch_scale = pitch * VOICE_SPEED
	echo.attenuation_filter_cutoff_hz = 1800.0
	echo.attenuation_filter_db = -18.0
	world.add_child(echo)
	echo.global_position = at
	echo.finished.connect(echo.queue_free)
	echo.play()
static var _shriek: AudioStreamWAV


## `kind` at `at` (global), heard where it is.
static func play(kind: int, at: Vector3, world: Node) -> void:
	if world == null or not world.is_inside_tree():
		return
	match kind:
		Kind.HELP:
			HallEcho.play(HELP, at, world, randf_range(0.95, 1.05), 4.0)
			return
		Kind.SHRIEK:
			_at(_make_shriek(), at, world, 4.0, randf_range(0.9, 1.1))
			HallEcho.tail(_make_shriek(), at, world)
		_:
			_at(rattle(randi()), at, world, 0.0, randf_range(0.85, 1.1))


static func _at(stream: AudioStream, at: Vector3, world: Node, volume_db: float, pitch: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.unit_size = UNIT_SIZE
	player.max_distance = 60.0
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = StalkerSigns.bus()
	world.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


static func rattle(index: int) -> AudioStreamWAV:
	if _rattles.is_empty():
		for i in 4:
			_rattles.append(_make_rattle(3000 + i))
	return _rattles[posmod(index, _rattles.size())]


## ~1.6 s of a throat clicking: pulses 25-45 a second, uneven, each a short
## burst rung through two resonances (~700 Hz and ~2.4 kHz), swelling and
## fading.
static func _make_rattle(seed_value: int) -> AudioStreamWAV:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	var seconds := dice.randf_range(1.3, 1.9)
	var frames := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var t := 0.0
	var low := dice.randf_range(600.0, 850.0)
	var high := dice.randf_range(2100.0, 2700.0)
	while t < seconds - 0.02:
		var u := t / seconds
		var swell := sin(u * PI) * (0.7 + 0.3 * sin(u * 23.0))
		var start := int(t * RATE)
		var length := int(RATE * dice.randf_range(0.006, 0.014))
		var loud := swell * dice.randf_range(0.5, 1.0)
		for k in length:
			var i := start + k
			if i >= frames:
				break
			var decay := exp(-float(k) / (length * 0.3))
			var s := float(k) / RATE
			samples[i] += (sin(TAU * low * s) * 0.7 + sin(TAU * high * s) * 0.35 + dice.randf_range(-1.0, 1.0) * 0.25) * decay * loud
		var rate_hz := lerpf(25.0, 45.0, sin(u * PI * 1.5) * 0.5 + 0.5)
		t += (1.0 / rate_hz) * dice.randf_range(0.6, 1.5) + (0.05 if dice.randf() < 0.06 else 0.0)
	return _wav(samples)


## ~1.2 s: a screech tearing upward (a buzzing saw rising 700 -> 1400 Hz,
## rough with noise and a crackle), cut off.
static func _make_shriek() -> AudioStreamWAV:
	if _shriek:
		return _shriek
	var dice := RandomNumberGenerator.new()
	dice.seed = 4100
	var frames := int(RATE * 1.2)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var phase := 0.0
	for i in frames:
		var u := float(i) / frames
		var pitch := lerpf(700.0, 1400.0, pow(u, 0.6)) * (1.0 + 0.04 * sin(u * 90.0))
		phase += pitch / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var grit := dice.randf_range(-1.0, 1.0)
		var envelope := minf(u / 0.05, 1.0) * (1.0 - smoothstep(0.85, 1.0, u))
		samples[i] = clampf((saw * 0.7 + grit * 0.4) * 1.6, -1.0, 1.0) * envelope
	_shriek = _wav(samples)
	return _shriek


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
