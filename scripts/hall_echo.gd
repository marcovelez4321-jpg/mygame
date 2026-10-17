class_name HallEcho
extends RefCounted

## A sound heard through the halls the way a radio is (the user's: exactly
## the same -- Radio's three voices on its buses and its mix): clear up
## close, the tinny one further off, and far away a muffled echo rolling
## through the halls, its long reverb fading slowly after. One shot of
## `clip` at `at` (global), mixed for where the camera is as it starts.
static func play(clip: AudioStream, at: Vector3, world: Node, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if clip == null or world == null or not world.is_inside_tree():
		return
	Radio._ensure_buses()
	var camera := world.get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(at) if camera else 0.0
	# Radio._mix_by(), with a radio's own settings.
	var clear_until := 15.0
	var tinny_until := 45.0
	var to_tinny := smoothstep(clear_until * 0.5, clear_until * 2.0, distance)
	var to_echo := smoothstep(clear_until, 80.0, distance)
	var voices := [
		[Radio.CLEAR_BUS, tinny_until, 3.0, 2.0 + linear_to_db(maxf(1.0 - to_tinny, 0.0001))],
		[Radio.VOICE_BUS, tinny_until + 20.0, 5.0, -2.0 + linear_to_db(maxf(to_tinny * (1.0 - smoothstep(tinny_until * 0.7, tinny_until, distance) * 0.7), 0.0001))],
		[Radio.ECHO_BUS, 275.0, 22.0, lerpf(-30.0, 0.0, to_echo)],
	]
	for voice: Array in voices:
		var player := AudioStreamPlayer3D.new()
		player.stream = clip
		player.bus = voice[0]
		player.max_distance = voice[1]
		player.unit_size = voice[2]
		player.volume_db = voice[3] + volume_db
		player.pitch_scale = pitch
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		if voice[0] == Radio.ECHO_BUS:
			player.attenuation_filter_cutoff_hz = 2500.0
			player.attenuation_filter_db = -18.0
		world.add_child(player)
		player.global_position = at
		player.finished.connect(player.queue_free)
		player.play()


## Only the echo: the radio's far, muffled voice with its long reverb, laid
## under a sound that's already played dry (a gunshot inside the Stack, the
## user's) -- some of it even right by you, more further off.
static func tail(clip: AudioStream, at: Vector3, world: Node, pitch: float = 1.0) -> void:
	if clip == null or world == null or not world.is_inside_tree():
		return
	Radio._ensure_buses()
	var camera := world.get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(at) if camera else 0.0
	var player := AudioStreamPlayer3D.new()
	player.stream = clip
	player.bus = Radio.ECHO_BUS
	player.max_distance = 275.0
	player.unit_size = 22.0
	player.volume_db = lerpf(-10.0, -2.0, smoothstep(15.0, 80.0, distance))
	player.pitch_scale = pitch
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.attenuation_filter_cutoff_hz = 2500.0
	player.attenuation_filter_db = -18.0
	world.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()
