class_name MegastructureSound
extends Node3D

## A megastructure's soundscape (HL2-style: a few voices placed where they
## matter, not hundreds of emitters), like a real building (the user's):
##   WIND IN THE OPEN SKY: only OUTSIDE it (in none of its inside_zones) and
##   up near the clouds -- fading in from sky_wind_below under the cloud
##   deck, full just over it. Inside, none at all.
##   WIND AT THE OPENINGS: the windows and openings to the outside howl, and
##   only right by them (opening_reach). A few positional voices
##   (opening_voices) are kept on the openings nearest you, so inside, the
##   wind you hear comes from the windows and holes and nowhere else.
##   THE DRONE: a low drone you feel more than hear, full inside, fading in
##   as you near the base (within drone_reach of it, below drone_height).
## Local to each player's game (look and sound only).

@export var wind_stream: AudioStream
@export var drone_stream: AudioStream
## Openings to the outside (local space): where the wind howls through.
@export var openings := PackedVector3Array()
## Inside: within this box (local space) -- the drone's. The rooms and halls
## (local space): in any of them is inside, for the wind.
@export var inside := AABB()
@export var inside_zones: Array[AABB] = []
## The base's middle (local) and how far round it the drone reaches, and up to
## what height above the base.
@export var base_centre := Vector3.ZERO
@export var drone_reach: float = 500.0
@export var drone_height: float = 300.0
## The open-sky wind: from this far under the cloud deck (world height,
## found from the scene's CloudDeck; cloud_height if there's none) to just
## over it.
@export var sky_wind_below: float = 300.0
@export var sky_wind_above: float = 60.0
@export var cloud_height: float = 1300.0
@export var opening_voices: int = 3
## How close to a window or opening you hear its wind (m).
@export var opening_reach: float = 18.0
@export var wind_volume_db: float = -12.0
@export var drone_volume_db: float = 2.0

const SILENT := -60.0

var _high_wind: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer3D] = []
var _check_left := 0.0


func _ready() -> void:
	_high_wind = _loop(AudioStreamPlayer.new(), wind_stream) as AudioStreamPlayer
	_drone = _loop(AudioStreamPlayer.new(), drone_stream) as AudioStreamPlayer
	for i in opening_voices:
		var voice := _loop(AudioStreamPlayer3D.new(), wind_stream) as AudioStreamPlayer3D
		voice.unit_size = 2.5
		voice.max_distance = opening_reach
		voice.volume_db = wind_volume_db + 2.0
		_voices.append(voice)
	var scene := get_tree().current_scene
	var deck := scene.find_child("CloudDeck", true, false) if scene else null
	if deck and deck.get("height") is float:
		cloud_height = deck.get("height")


func _loop(player: Node, stream: AudioStream) -> Node:
	player.set("stream", stream)
	player.set("volume_db", SILENT)
	add_child(player)
	if stream:
		# Each voice starts at its own place in the loop, so they never phase.
		player.call("play", randf() * maxf(stream.get_length() - 0.1, 0.0))
	return player


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := to_local(camera.global_position)
	var is_inside := inside.has_point(at)
	# The open-sky wind: outside, up by the clouds -- none in a room or hall.
	var sky := smoothstep(cloud_height - sky_wind_below, cloud_height + sky_wind_above, camera.global_position.y)
	if _in_a_room(at):
		sky = 0.0
	_fade(_high_wind, wind_volume_db, sky, delta)
	# The drone: full inside, rising as you near the base.
	var flat := Vector2(at.x - base_centre.x, at.z - base_centre.z).length()
	var near := smoothstep(drone_reach, drone_reach * 0.3, flat) * smoothstep(drone_height, drone_height * 0.5, at.y - base_centre.y)
	_fade(_drone, drone_volume_db, 1.0 if is_inside else near, delta)
	# The openings' voices onto the nearest few openings (a few times a second).
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.25
	var nearest := _nearest_openings(at)
	for i in _voices.size():
		if i < nearest.size():
			_voices[i].position = nearest[i]
			_voices[i].volume_db = wind_volume_db + 2.0
		else:
			_voices[i].volume_db = SILENT


## In one of its rooms or halls (or, with none given, its inside box).
func _in_a_room(at: Vector3) -> bool:
	if inside_zones.is_empty():
		return inside.has_point(at)
	for zone in inside_zones:
		if zone.has_point(at):
			return true
	return false


## Eases a player's volume toward `amount` (0..1) of `full_db`.
func _fade(player: AudioStreamPlayer, full_db: float, amount: float, delta: float) -> void:
	var want := linear_to_db(maxf(amount, 0.0001)) + full_db
	player.volume_db = move_toward(player.volume_db, maxf(want, SILENT), 30.0 * delta)


## The few openings nearest `at` within reach (local space), nearest first.
func _nearest_openings(at: Vector3) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var distances: Array[float] = []
	for point in openings:
		var distance := point.distance_to(at)
		if distance > opening_reach:
			continue
		var slot := distances.bsearch(distance)
		distances.insert(slot, distance)
		found.insert(slot, point)
		if found.size() > opening_voices:
			found.resize(opening_voices)
			distances.resize(opening_voices)
	return found
