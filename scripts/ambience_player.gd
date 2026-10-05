class_name AmbiencePlayer
extends Node

## A level's background atmosphere (Rule 7), the way Valve's soundscapes do
## it: an optional quiet looping bed, plus random one-shots every so often
## from somewhere around the player -- distant creaks, wind, far-off noises.
## Kept deliberately subtle: felt more than heard. MapLevel adds one to every
## level. Rule 1 (co-op): cosmetic and local, each client rolls its own.

@export var oneshot_sound: SoundEvent = preload("res://audio/events/ambience/ambience_oneshot.tres")
@export var bed_sound: SoundEvent = preload("res://audio/events/ambience/ambience_bed.tres")
## Seconds between one-shots, picked at random in this range.
@export var min_interval: float = 8.0
@export var max_interval: float = 25.0
## How far from the player (m) a one-shot plays, picked at random: far
## enough to read as "somewhere out there", with a direction you can hear.
@export var min_distance: float = 8.0
@export var max_distance: float = 18.0

var _timer: Timer


func _ready() -> void:
	SoundPlayer.play_loop_2d(bed_sound, self)
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_play_oneshot)
	_timer.start(randf_range(min_interval, max_interval))


func _play_oneshot() -> void:
	_timer.start(randf_range(min_interval, max_interval))
	var player := PlayerMovement.local_player(get_tree())
	if player == null:
		SoundPlayer.play_2d(oneshot_sound)
		return
	var angle := randf() * TAU
	var position := player.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(min_distance, max_distance) \
			+ Vector3.UP * randf_range(0.5, 4.0)
	SoundPlayer.play_3d(oneshot_sound, position, get_tree().current_scene)
