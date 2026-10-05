class_name SoundEvent
extends Resource

## One "thing that can happen" mapped to sound: a gunshot, a footstep, an
## enemy's dying scream. Assigning or changing what an action sounds like is
## just editing this resource in the Inspector -- dragging audio files into
## `clips` -- no code, exactly like WeaponData lets you re-skin a weapon's
## numbers without touching weapon_controller.gd.
##
## A LIST of clips, not one: play() (see sound_player.gd) picks a random
## entry each time, so the same action doesn't sound identical on every
## repeat -- a machine gun firing the exact same .wav every 0.1s reads as a
## broken record, not a real gun.

@export var clips: Array[AudioStream] = []

@export_group("Folder")
## Drop-in alternative to filling `clips` by hand: every file in this folder
## named <clip_prefix>_<number> (impact_soft_01.wav, impact_soft_02.wav, ...)
## joins the pool, on top of anything in `clips`. Dropping a new variation
## into the folder is enough -- no editing this resource.
@export_dir var clip_folder: String = ""
@export var clip_prefix: String = ""
## Used when this event has no audio of its own yet -- e.g. the rusher's
## death scream falls back to the base enemy's until it gets its own.
@export var fallback: SoundEvent

@export_group("Variation")
## Randomized per play, in decibels, added to the base volume below.
@export var volume_db: float = 0.0
@export var volume_db_variance: float = 0.0
## Randomized per play, as a multiplier on playback speed (1.0 = normal
## pitch). Something like +-0.1 is a believable amount of natural variation
## for a footstep or gunshot without it sounding pitch-shifted/cartoonish.
@export var pitch_scale: float = 1.0
@export var pitch_variance: float = 0.0

@export_group("Distance")
## How far a 3D sound carries (Godot's AudioStreamPlayer3D.unit_size, like
## Valve's soundlevel). Inside this many meters it plays at full volume;
## beyond it, it fades -- halving this halves how far away it's heard.
## 10 is Godot's default.
@export var unit_size: float = 10.0

@export_group("Routing")
## Which audio bus this plays on. "SFX" (default_bus_layout.tres) is the
## PS1 bus -- LoFi bit reduction then a 9 kHz low-pass -- so every sound
## shares one console character (Rule 7). Falls back to "Master" if the
## named bus doesn't exist (see sound_player.gd's _resolve_bus()).
@export var bus: String = "SFX"

## `clips` plus whatever clip_folder holds. Built once, on first use, so the
## folder is only ever scanned one time per run.
var _pool: Array[AudioStream] = []
var _pool_built := false


## A random clip from the pool, or null if there's nothing yet (a stub event
## nobody has added audio to).
func pick_clip() -> AudioStream:
	_build_pool()
	if _pool.is_empty():
		return fallback.pick_clip() if fallback != null else null
	return _pool[randi() % _pool.size()]


func has_clips() -> bool:
	_build_pool()
	return not _pool.is_empty() or (fallback != null and fallback.has_clips())


## ResourceLoader.list_directory, not DirAccess: in an exported game the
## folder holds .import/.remap files instead of the original .wavs, and this
## returns the original names either way.
func _build_pool() -> void:
	if _pool_built:
		return
	_pool_built = true
	# Skip empty slots -- an Inspector "+" with no file dragged in leaves a
	# null that would otherwise silently swallow a share of the plays.
	for clip in clips:
		if clip != null:
			_pool.append(clip)
	if clip_folder.is_empty() or clip_prefix.is_empty():
		return
	var pattern := RegEx.create_from_string("^%s_\\d+\\.(wav|ogg|mp3)$" % clip_prefix)
	for file in ResourceLoader.list_directory(clip_folder):
		if pattern.search(file):
			var stream := load(clip_folder.path_join(file)) as AudioStream
			if stream:
				_pool.append(stream)


func roll_volume_db() -> float:
	return volume_db + randf_range(-volume_db_variance, volume_db_variance)


func roll_pitch_scale() -> float:
	return pitch_scale + randf_range(-pitch_variance, pitch_variance)
