class_name DemoSound
extends Node

## The procedural Stack's sound (the user's, 2026-10-27: all of it, the
## inside ambience and the outside ambience too) -- the open world Stack's own
## soundscape (MegastructureSound) laid over the demo's rooms, and an outside
## layer it doesn't have down at ground level:
##   INSIDE (any of its rooms, `rooms`): the hollow loop; now and then a
##   far-off noise echoing through the halls (HallEcho); the wind howling only
##   at the windows nearest you (`openings`).
##   APPROACHING (outside, near it): its low drone.
##   OUTSIDE: the open air's wind, stronger the higher you are, only under
##   open sky (OPEN_SKY up clear); far-off one-shots out in the dusk
##   (OUT_EVERY, OUT_RANGE off, positional, no echo).
##   THE LAMPS: a faint electric hum right by each one (LAMP_REACH).
## The tools bake fills `rooms` and `openings` (tools/stacks_demo_bake.gd).
## Local to each game (sound only).

const WIND := "res://audio/sfx/ambience/stack_wind.res"
const DRONE := "res://audio/sfx/ambience/stack_drone.res"
const HUM := "res://audio/sfx/map/lighthum.wav"
const ONESHOTS := preload("res://audio/events/ambience/ambience_oneshot.tres")
## Its middle (the drone's), how far round it the drone reaches, how high.
const CENTRE := Vector3(0.0, 0.0, 48.0)
const DRONE_REACH := 160.0
const DRONE_HEIGHT := 100.0
## The outside wind: its loudness at the ground and from WIND_FULL_AT up.
const OUT_WIND_DB := -14.0
const OUT_WIND_LOW := 0.45
const WIND_FULL_AT := 40.0
const OPEN_SKY := 40.0
const OUT_EVERY := Vector2(15.0, 40.0)
const OUT_RANGE := Vector2(40.0, 120.0)
const LAMP_REACH := 7.0
const LAMP_DB := -16.0
## The open world Stack (decoration here): its drone kept to its own foot,
## so it isn't humming through the demo's rooms 330 m off.
const STACK_DRONE_REACH := 250.0
const SILENT := -60.0

@export var rooms: Array[AABB] = []
@export var openings := PackedVector3Array()

var _wind: AudioStreamPlayer
var _out_left := 10.0
var _sky_left := 0.0
var _open := 0.0
var _outside := 0.0


func _ready() -> void:
	var sound := MegastructureSound.new()
	sound.name = "StackSound"
	sound.wind_stream = load(WIND) if ResourceLoader.exists(WIND) else null
	sound.drone_stream = load(DRONE) if ResourceLoader.exists(DRONE) else null
	sound.drone_volume_db = -14.0 # (the open world Stack's: felt more than heard)
	sound.openings = openings
	sound.inside = AABB(Vector3(0.0, -9999.0, 0.0), Vector3.ZERO) # (its rooms are the inside)
	sound.inside_zones = rooms
	sound.base_centre = CENTRE
	sound.drone_reach = DRONE_REACH
	sound.drone_height = DRONE_HEIGHT
	add_child(sound)
	_wind = AudioStreamPlayer.new()
	_wind.stream = sound.wind_stream
	_wind.volume_db = SILENT
	_wind.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") != -1 else &"Master"
	add_child(_wind)
	if _wind.stream:
		_wind.play(randf() * maxf(_wind.stream.get_length() - 0.1, 0.0))
	_settle.call_deferred()


## After the scene's in: the lamps' hum, the decoration Stack's drone kept home.
func _settle() -> void:
	var scene := get_tree().current_scene
	var stack := scene.get_node_or_null(^"TheStack")
	if stack:
		for node in stack.find_children("*", "MegastructureSound", true, false):
			var other := node as MegastructureSound
			other.drone_reach = minf(other.drone_reach, STACK_DRONE_REACH)
	var things := scene.get_node_or_null(^"Things")
	var hum := load(HUM) as AudioStream if ResourceLoader.exists(HUM) else null
	if things == null or hum == null:
		return
	if hum is AudioStreamWAV:
		var wav := hum as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	for node in things.get_children():
		if not String(node.name).begins_with("lamp"):
			continue
		var buzz := AudioStreamPlayer3D.new()
		buzz.stream = hum
		buzz.volume_db = LAMP_DB
		buzz.unit_size = 1.5
		buzz.max_distance = LAMP_REACH
		buzz.position = Vector3.UP * 2.5 if String(node.name).begins_with("lamp_post") else Vector3.ZERO
		node.add_child(buzz)
		buzz.play(randf() * maxf(hum.get_length() - 0.1, 0.0))


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	var inside := _in_a_room(at)
	_outside = move_toward(_outside, 0.0 if inside else 1.0, delta / 2.5)
	_sky_left -= delta
	if _sky_left <= 0.0:
		_sky_left = 0.5
		var space := camera.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + Vector3.UP * OPEN_SKY, 1))
		_open = 1.0 if hit.is_empty() else 0.0
	var height := lerpf(OUT_WIND_LOW, 1.0, clampf(at.y / WIND_FULL_AT, 0.0, 1.0))
	var amount := _outside * height * (0.35 + 0.65 * _open)
	var want := linear_to_db(maxf(amount, 0.0001)) + OUT_WIND_DB
	_wind.volume_db = move_toward(_wind.volume_db, maxf(want, SILENT), 30.0 * delta)
	if _outside > 0.5:
		_out_left -= delta
		if _out_left <= 0.0:
			_out_left = randf_range(OUT_EVERY.x, OUT_EVERY.y)
			_far_noise(at)


func _in_a_room(at: Vector3) -> bool:
	for room in rooms:
		if room.has_point(at):
			return true
	return false


## Something far off out in the dusk: one of the ambience one-shots, placed.
func _far_noise(from: Vector3) -> void:
	var clip := ONESHOTS.pick_clip()
	if clip == null:
		return
	var noise := AudioStreamPlayer3D.new()
	noise.stream = clip
	noise.volume_db = ONESHOTS.volume_db + 6.0
	noise.pitch_scale = ONESHOTS.roll_pitch_scale()
	noise.unit_size = 40.0
	noise.max_distance = OUT_RANGE.y * 2.0
	noise.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") != -1 else &"Master"
	add_child(noise)
	var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	way.y = randf_range(0.0, 0.4)
	noise.global_position = from + way.normalized() * randf_range(OUT_RANGE.x, OUT_RANGE.y)
	noise.finished.connect(noise.queue_free)
	noise.play()
