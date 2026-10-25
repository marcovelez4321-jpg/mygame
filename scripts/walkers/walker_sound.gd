class_name WalkerSound
extends RefCounted

## The walking megastructures' sounds (the user's, 2026-10-25): bones
## creaking, footfall booms, a bell, a choir. Each a slot: drop files named
## <slot>_<number> (footfall_01.wav, creak_02.ogg, bell_01.wav, choir_01.ogg)
## into audio/sfx/walkers and one's picked at random each time; until then a
## placeholder made in code (the user's: code-made placeholders).

const FOLDER := "res://audio/sfx/walkers/"
const RATE := 22050

static var _files := {}
static var _made := {}


## A sound for `slot`: one of the user's files, or the placeholder.
static func pick(slot: String) -> AudioStream:
	if not _files.has(slot):
		var found: Array[AudioStream] = []
		var dir := DirAccess.open(FOLDER)
		if dir:
			for file in dir.get_files():
				var bare := file.trim_suffix(".import").trim_suffix(".remap")
				if bare.begins_with(slot + "_") and (bare.ends_with(".wav") or bare.ends_with(".ogg") or bare.ends_with(".mp3")):
					var stream := load(FOLDER + bare) as AudioStream
					if stream and not found.has(stream):
						found.append(stream)
		_files[slot] = found
	var files: Array = _files[slot]
	if not files.is_empty():
		return files[randi() % files.size()]
	return placeholder(slot)


static func placeholder(slot: String) -> AudioStream:
	if _made.has(slot):
		return _made[slot]
	var samples := PackedFloat32Array()
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(slot)
	match slot:
		"footfall":
			# A deep boom: a falling low tone, a crunch on top.
			var frames := int(RATE * 3.0)
			samples.resize(frames)
			for i in frames:
				var s := float(i) / RATE
				var tone := sin(TAU * (34.0 - 10.0 * s) * s) * exp(-s * 1.4)
				var crunch := dice.randf_range(-1.0, 1.0) * exp(-s * 6.0) * 0.6
				samples[i] = tone + crunch
		"creak":
			# Bone groaning: slow, rough, rising.
			var frames := int(RATE * 1.6)
			samples.resize(frames)
			var phase := 0.0
			var low := 0.0
			for i in frames:
				var s := float(i) / RATE
				phase += TAU * (70.0 + 50.0 * s + 8.0 * sin(s * 23.0)) / RATE
				low = lerpf(low, dice.randf_range(-1.0, 1.0), 0.05)
				var body := signf(sin(phase)) * 0.4 + low * 0.8
				samples[i] = body * sin(PI * s / 1.6)
		"bell":
			# A big cracked bell: inharmonic partials ringing out.
			var frames := int(RATE * 7.0)
			samples.resize(frames)
			for i in frames:
				var s := float(i) / RATE
				var ring := 0.0
				for p: Array in [[110.0, 1.0, 0.5], [131.0, 0.6, 0.7], [220.0, 0.5, 0.9], [299.0, 0.35, 1.3], [411.0, 0.25, 1.8]]:
					ring += sin(TAU * p[0] * s) * p[1] * exp(-s * p[2])
				samples[i] = ring
		"choir":
			# A faint choir: a held chord of soft "aah"s, wavering (it loops).
			var frames := int(RATE * 4.0)
			samples.resize(frames)
			for i in frames:
				var s := float(i) / RATE
				var voices := 0.0
				for f: float in [196.0, 246.9, 293.7, 392.0]:
					var wobble := 1.0 + 0.004 * sin(TAU * 5.0 * s + f)
					voices += sin(TAU * f * wobble * s) + 0.3 * sin(TAU * f * 2.0 * wobble * s)
				samples[i] = voices * (0.85 + 0.15 * sin(TAU * s / 4.0))
		_:
			samples.resize(int(RATE * 0.1))
	var wav := StalkerSound._wav(samples)
	if slot == "choir":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	_made[slot] = wav
	return wav


## A one-shot at `at`, heard out to `reach` m.
static func play(slot: String, at: Vector3, world: Node, reach: float, volume_db: float = 0.0, unit_size: float = 40.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = pick(slot)
	player.max_distance = reach
	player.unit_size = unit_size
	player.volume_db = volume_db
	player.attenuation_filter_cutoff_hz = 20500.0
	world.add_child(player)
	player.global_position = at
	player.play()
	player.finished.connect(player.queue_free)
