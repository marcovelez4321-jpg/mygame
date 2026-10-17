class_name LampHum
extends AudioStreamPlayer3D

## A lamp post's electrical hum (the user's file: audio/sfx/map/lighthum.wav),
## heard only close by. Plays only while the camera's within HEAR (checked
## twice a second), so a tower full of lamps costs nothing.

const HUM := preload("res://audio/sfx/map/lighthum.wav")
const HEAR := 16.0

var _check_left := 0.0


func _ready() -> void:
	if HUM is AudioStreamWAV:
		var wav := HUM as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	stream = HUM
	unit_size = 2.0
	max_distance = HEAR
	volume_db = -4.0
	pitch_scale = randf_range(0.95, 1.05)
	bus = &"Props" if AudioServer.get_bus_index(&"Props") != -1 else &"Master"
	_check_left = randf() * 0.5


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.5
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(global_position) < HEAR + 2.0
	if near and not playing:
		play(randf() * maxf(HUM.get_length() - 0.1, 0.0))
	elif not near and playing:
		stop()