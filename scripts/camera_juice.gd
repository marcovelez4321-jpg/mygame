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
## and sways and the view widens -- all from speed_floor up to speed_top,
## with a light rattle near the top. (No speed lines
## or wind rush: the user took them out.)
##
## Rule 1 (co-op): purely cosmetic, generated locally from each client's own
## events (their own dash, their own landing, their own confirmed hit) and
## never sent over the network -- exactly like the existing shot tracers.

@export var shake_decay: float = 90.0 ## degrees/second a shake settles at
@export var fov_decay: float = 90.0   ## degrees/second an FOV kick settles at

@export_group("Speed")
## Speed (horizontal m/s) where the effects start, lightly, and where they're
## full (the user's: 32 to 40, past the bhop cap -- grapple kicks, launches).
@export var speed_floor: float = 32.0
@export var speed_top: float = 40.0
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
## turning (degrees/second, + = left). Only your own camera gets this.
func set_motion(speed: float, sideways: float, turning: float) -> void:
	_speed = clampf(inverse_lerp(speed_floor, speed_top, speed), 0.0, 1.0)
	var lean := 0.6 + 0.4 * _speed
	_roll_target = clampf((-sideways * strafe_roll + turning / 100.0 * turn_roll) * lean, -max_roll, max_roll)


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
