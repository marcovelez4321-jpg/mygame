class_name CameraJuice
extends Camera3D

## Presentation-only camera feel, layered directly onto the player's real
## Camera3D: shake and FOV kicks that read as speed/impact. Safe to hang
## anything off of -- aiming and shot math both read from Head's transform
## (see player_movement.gd's weapons.tick() call), never from this camera, so
## nothing here can ever throw off where a shot actually goes.
##
## Speed (the user's: Vholume-style juice as momentum builds, set_motion()
## from your own body every frame): the camera rolls into strafes and turns
## and sways, the view widens, speed lines rush past the screen's edges, and
## wind roars louder and higher -- all from a run (speed_floor) up to the
## speed cap (speed_top), with a light rattle near the top.
##
## Rule 1 (co-op): purely cosmetic, generated locally from each client's own
## events (their own dash, their own landing, their own confirmed hit) and
## never sent over the network -- exactly like the existing shot tracers.

@export var shake_decay: float = 90.0 ## degrees/second a shake settles at
@export var fov_decay: float = 90.0   ## degrees/second an FOV kick settles at

@export_group("Speed")
## Speed (horizontal m/s) where the effects start, and where they're full.
@export var speed_floor: float = 7.0
@export var speed_top: float = 28.0
## Degrees the view widens at full speed.
@export var speed_fov: float = 12.0
## Camera roll: into a strafe (degrees, full sideways speed), into a turn
## (degrees per 100 degrees/second of turning), at most, and how quickly it
## follows (per second).
@export var strafe_roll: float = 2.5
@export var turn_roll: float = 1.2
@export var max_roll: float = 7.0
@export var roll_follow: float = 8.0
## A gentle sway as you go (degrees of pitch at full speed).
@export var speed_sway: float = 0.6
## From this share of full speed, a light rattle (degrees at the top).
@export_range(0.0, 1.0, 0.05) var rattle_from: float = 0.8
@export var rattle: float = 0.5
## The wind's loudness at full speed (dB), and its pitch at no / full speed.
@export var wind_volume_db: float = -4.0
@export var wind_pitch_low: float = 0.8
@export var wind_pitch_high: float = 1.35

## Magnification: 1 = normal, 2.5 = everything looks 2.5x bigger. Set by
## AimDownSights while you aim.
var zoom: float = 1.0

var _base_fov: float
var _shake_strength: float = 0.0
var _fov_offset: float = 0.0
## Speed (set_motion): 0..1 of the way from speed_floor to speed_top, the
## roll it's leaning toward and the roll it has, and the sway's clock.
var _speed := 0.0
var _roll_target := 0.0
var _roll := 0.0
var _sway_time := 0.0
var _lines: ShaderMaterial
var _wind: AudioStreamPlayer

static var _wind_stream: AudioStreamWAV


func _ready() -> void:
	_base_fov = fov


## A punchy camera shake; `strength` is roughly the max degrees of tilt.
## Takes the max against whatever's already fading out instead of resetting
## it, so a fast chain of hits keeps building instead of restarting at zero
## on every single one.
func shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)


## A quick zoom-out punch (`amount` in degrees added on top of the base FOV)
## that eases back to normal -- reads as speed/impact with no motion blur or
## screen distortion.
func kick_fov(amount: float) -> void:
	_fov_offset = maxf(_fov_offset, amount)


## Your own body, every frame: how fast you're going (horizontal m/s), how
## much of it is sideways (-1 left .. 1 right, of a run), and how fast you're
## turning (degrees/second, + = left). Only your own camera gets this, so
## only it makes the speed lines and the wind.
func set_motion(speed: float, sideways: float, turning: float) -> void:
	_speed = clampf(inverse_lerp(speed_floor, speed_top, speed), 0.0, 1.0)
	var lean := 0.6 + 0.4 * _speed
	_roll_target = clampf((-sideways * strafe_roll + turning / 100.0 * turn_roll) * lean, -max_roll, max_roll)
	if _lines == null:
		_make_speed_lines()
		_make_wind()


func _process(delta: float) -> void:
	# Leaning into strafes and turns, and a sway as you go.
	_roll = lerpf(_roll, _roll_target, 1.0 - exp(-roll_follow * delta))
	_sway_time += delta * (2.0 + 4.0 * _speed)
	var lean := Vector3(sin(_sway_time) * speed_sway * _speed, 0.0, _roll)
	if _speed > rattle_from:
		shake(rattle * inverse_lerp(rattle_from, 1.0, _speed))
	var turn := lean
	if _shake_strength > 0.01:
		turn += Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0) * 0.3, # less roll than pitch/yaw -- roll reads as "off" fast
		) * _shake_strength
		_shake_strength = maxf(_shake_strength - shake_decay * delta, 0.0)
	rotation = turn * (PI / 180.0)

	# Zooming narrows the view: 2x zoom = half as wide (measured as the
	# tangent of the half-angle, so it's a true 2x, not just half the degrees).
	var base_fov := _base_fov
	if zoom > 1.0:
		base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov) * 0.5) / zoom))
	else:
		base_fov += speed_fov * _speed # faster: wider
	fov = base_fov + _fov_offset
	_fov_offset = maxf(_fov_offset - fov_decay * delta, 0.0)

	if _lines:
		_lines.set_shader_parameter("amount", _speed)
		var size := get_viewport().get_visible_rect().size
		_lines.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	if _wind:
		var loud := _speed * _speed # creeps in, then roars
		_wind.volume_db = linear_to_db(maxf(loud, 0.0001)) + wind_volume_db
		_wind.pitch_scale = lerpf(wind_pitch_low, wind_pitch_high, _speed)


## The speed lines: a full-screen layer over the 3D, under the HUD.
func _make_speed_lines() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines = ShaderMaterial.new()
	_lines.shader = preload("res://shaders/speed_lines.gdshader")
	rect.material = _lines
	layer.add_child(rect)


## The wind rushing past: a loop of rushing air, made once.
func _make_wind() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.stream = _rush()
	_wind.bus = &"Player" if AudioServer.get_bus_index(&"Player") != -1 else &"Master"
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()


## Rushing air (loopable): noise, softened and fluttering a little, both
## ears' worth of hiss and roar.
static func _rush(seconds: float = 4.0) -> AudioStreamWAV:
	if _wind_stream:
		return _wind_stream
	var rate := 22050
	var frames := int(seconds * rate)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var noise := RandomNumberGenerator.new()
	noise.seed = 11
	var low := 0.0
	var mid := 0.0
	for i in frames:
		var t := float(i) / rate
		var flutter := 0.75 + 0.15 * sin(t * TAU * 0.5) + 0.1 * sin(t * TAU * 7.3)
		var white := noise.randf_range(-1.0, 1.0)
		low += (white - low) * 0.02 # the roar
		mid += (white - mid) * 0.25 # the hiss
		samples[i] = (low * 3.0 + (mid - low) * 0.5) * flutter
	# Looped: the last second faded into the first.
	var fade := rate
	var looped := samples.slice(0, frames - fade)
	for i in fade:
		var k := float(i) / fade
		looped[i] = samples[i] * k + samples[frames - fade + i] * (1.0 - k)
	var peak := 0.0001
	for s in looped:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(looped.size() * 2)
	for i in looped.size():
		data.encode_s16(i * 2, int(clampf(looped[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	_wind_stream = AudioStreamWAV.new()
	_wind_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_wind_stream.mix_rate = rate
	_wind_stream.data = data
	_wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_wind_stream.loop_end = looped.size()
	return _wind_stream