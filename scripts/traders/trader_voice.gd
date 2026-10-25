class_name TraderVoice
extends AudioStreamPlayer3D

## His babble (the user's, 2026-10-25: no words -- Animal Crossing's way): one
## of the user's own voicelines (CLIP) chopped into syllables, each a sliver
## from somewhere in it at its own pitch -- low, an old man's grumble (PITCH)
## -- RATE a second. How many syllables each babble is: BABBLES (cross ones a
## touch higher and clipped).

const CLIP := "res://audio/events/stalker/stalkersounds/hellonormal1.ogg"
const RATE := 8.0
const PITCH := Vector2(0.6, 0.8)
## A syllable's share of its slot (the rest: the gap between).
const GRAIN := 0.75
## Only from the clip's middle (its ends are breath and silence).
const FROM_SHARE := Vector2(0.12, 0.85)
const BABBLES := {&"greet": 7, &"price": 4, &"sale": 6, &"no": 3, &"help": 12}
const CROSS_PITCH := 1.12

var _left := 0
var _next := 0.0
var _cross := false
var _length := 0.0
var _stop_msec := 0


func _ready() -> void:
	if ResourceLoader.exists(CLIP):
		stream = load(CLIP) as AudioStream
		_length = stream.get_length() if stream else 0.0
	unit_size = 4.0
	max_distance = 35.0
	attenuation_filter_cutoff_hz = 20500.0


func babble(kind: StringName) -> void:
	if stream == null or _length <= 0.0:
		return
	_left = int(BABBLES.get(kind, 4))
	_cross = kind == &"no" or kind == &"help"
	volume_db = 8.0 if kind == &"help" else 0.0 # (calling for help: loud)
	_next = 0.0


func _process(delta: float) -> void:
	if playing and Time.get_ticks_msec() >= _stop_msec:
		stop()
	if _left <= 0:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = 1.0 / RATE
	_left -= 1
	pitch_scale = randf_range(PITCH.x, PITCH.y) * (CROSS_PITCH if _cross else 1.0)
	var grain := GRAIN / RATE
	var from := randf_range(_length * FROM_SHARE.x, maxf(_length * FROM_SHARE.y - grain * pitch_scale, _length * FROM_SHARE.x))
	play(from)
	_stop_msec = Time.get_ticks_msec() + int(grain * 1000.0 * (0.8 if _cross else 1.0))
