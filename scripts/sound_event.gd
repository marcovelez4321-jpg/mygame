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

@export_group("Variation")
## Randomized per play, in decibels, added to the base volume below.
@export var volume_db: float = 0.0
@export var volume_db_variance: float = 0.0
## Randomized per play, as a multiplier on playback speed (1.0 = normal
## pitch). Something like +-0.1 is a believable amount of natural variation
## for a footstep or gunshot without it sounding pitch-shifted/cartoonish.
@export var pitch_scale: float = 1.0
@export var pitch_variance: float = 0.0

@export_group("Routing")
## Which audio bus this plays on. Falls back to "Master" at playback time if
## a bus with this name doesn't exist yet (see sound_player.gd's
## _resolve_bus()) -- so this is safe to leave as "SFX" now and have it
## silently do nothing extra until an SFX bus actually exists in the
## project's Audio panel (Project Settings -> Audio Bus Layout), at which
## point every SoundEvent already routes there for free.
@export var bus: String = "SFX"


## A random clip from the list, or null if none are assigned yet (a stub
## event nobody has dragged audio files into).
func pick_clip() -> AudioStream:
	if clips.is_empty():
		return null
	return clips[randi() % clips.size()]


func roll_volume_db() -> float:
	return volume_db + randf_range(-volume_db_variance, volume_db_variance)


func roll_pitch_scale() -> float:
	return pitch_scale + randf_range(-pitch_variance, pitch_variance)
