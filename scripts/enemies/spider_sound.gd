class_name SpiderSound
extends RefCounted

## The spiders' own sounds, made in code (the user's, 2026-10-17: like the
## roaches' buzz, every one its own -- never the same clip stacked on
## itself): a skittering loop of leg-clicks while one crawls, and a quick
## chittering rasp as it leaps. VARIANTS of each, different every one; each
## spider picks one, its own pitch and where in the loop it starts.
## Heard at UNIT_SIZE (the roaches' buzz, brought in 25% too) and not past
## HEAR_DISTANCE. Bigger spiders sound lower (Spider).

const VARIANTS := 6
const RATE := 22050
const UNIT_SIZE := 9.0
const HEAR_DISTANCE := 45.0
const SKITTER_DB := -8.0
const LEAP_DB := -2.0

static var _skitters: Array[AudioStreamWAV] = []
static var _leaps: Array[AudioStreamWAV] = []


static func skitter(index: int) -> AudioStreamWAV:
	if _skitters.is_empty():
		for i in VARIANTS:
			_skitters.append(_make_skitter(1000 + i))
	return _skitters[posmod(index, VARIANTS)]


static func leap(index: int) -> AudioStreamWAV:
	if _leaps.is_empty():
		for i in VARIANTS:
			_leaps.append(_make_leap(2000 + i))
	return _leaps[posmod(index, VARIANTS)]


## A second of legs ticking on concrete: tiny clicks (a sharp tap of filtered
## noise, a few ms), 30-45 a second in uneven little runs, loopable.
static func _make_skitter(seed_value: int) -> AudioStreamWAV:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	var frames := RATE
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var t := 0.0
	var rate_hz := dice.randf_range(30.0, 45.0)
	var tone := dice.randf_range(2200.0, 4200.0)
	while t < 1.0:
		var start := int(t * RATE)
		var length := int(RATE * dice.randf_range(0.002, 0.006))
		var loud := dice.randf_range(0.25, 1.0)
		var phase := dice.randf() * TAU
		var pitch := tone * dice.randf_range(0.8, 1.25)
		for k in length:
			var i := (start + k) % frames
			var decay := exp(-float(k) / (length * 0.35))
			samples[i] += (sin(phase + TAU * pitch * k / RATE) * 0.6 + dice.randf_range(-1.0, 1.0) * 0.5) * decay * loud
		# Uneven: runs of quick ticks, now and then a gap.
		t += (1.0 / rate_hz) * dice.randf_range(0.4, 1.6) + (0.04 if dice.randf() < 0.08 else 0.0)
	return _wav(samples, true)


## A leap: a dry chittering rasp that rises and snaps off (~0.3 s).
static func _make_leap(seed_value: int) -> AudioStreamWAV:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	var seconds := dice.randf_range(0.25, 0.38)
	var frames := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var chitter := dice.randf_range(55.0, 85.0) # clicks a second in the rasp
	var low := 0.0
	for i in frames:
		var u := float(i) / frames
		var envelope := minf(u / 0.08, 1.0) * pow(1.0 - u, 1.6)
		var noise := dice.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.35) # a little softer than white
		var t := float(i) / RATE
		var rasp := 0.5 + 0.5 * signf(sin(TAU * chitter * (1.0 + u * 0.6) * t))
		var hiss := (noise - low) * 0.8 + low * 0.4
		samples[i] = hiss * (0.35 + 0.65 * rasp) * envelope * 0.9
	return _wav(samples, false)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
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
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav