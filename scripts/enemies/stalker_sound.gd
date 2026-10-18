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

static var _rattles: Array[AudioStreamWAV] = []
static var _voices: StalkerVoices


## The `slot`'s sound (StalkerVoices) at `at`, through the halls' echo; an
## empty slot falls back to the old made-up sound where there was one, else
## stays silent.
static func voice(slot: StringName, at: Vector3, world: Node, volume_db: float = 0.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	if _voices == null and ResourceLoader.exists(VOICES):
		_voices = load(VOICES) as StalkerVoices
	var event: SoundEvent = _voices.event(slot) if _voices else null
	var clip: AudioStream = event.pick_clip() if event else null
	if clip:
		HallEcho.play(clip, at, world, event.roll_pitch_scale(), event.roll_volume_db() + volume_db)
		return
	match slot:
		&"croak_behind", &"lunge", &"behind_you", &"watching":
			play(Kind.RATTLE, at, world)
		&"driven_off":
			play(Kind.SHRIEK, at, world)
		&"help_scream":
			play(Kind.HELP, at, world)
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
	player.bus = &"Enemies" if AudioServer.get_bus_index(&"Enemies") != -1 else &"Master"
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