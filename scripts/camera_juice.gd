class_name CameraJuice
extends Camera3D

## Presentation-only camera feel, layered directly onto the player's real
## Camera3D: shake and FOV kicks that read as speed/impact. Safe to hang
## anything off of -- aiming and shot math both read from Head's transform
## (see player_movement.gd's weapons.tick() call), never from this camera, so
## nothing here can ever throw off where a shot actually goes.
##
## Rule 1 (co-op): purely cosmetic, generated locally from each client's own
## events (their own dash, their own landing, their own confirmed hit) and
## never sent over the network -- exactly like the existing shot tracers.

@export var shake_decay: float = 90.0 ## degrees/second a shake settles at
@export var fov_decay: float = 90.0   ## degrees/second an FOV kick settles at

## Magnification: 1 = normal, 2.5 = everything looks 2.5x bigger. Set by
## AimDownSights while you aim.
var zoom: float = 1.0

var _base_fov: float
var _shake_strength: float = 0.0
var _fov_offset: float = 0.0


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


func _process(delta: float) -> void:
	if _shake_strength > 0.01:
		rotation = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0) * 0.3, # less roll than pitch/yaw -- roll reads as "off" fast
		) * deg_to_rad(_shake_strength)
		_shake_strength = maxf(_shake_strength - shake_decay * delta, 0.0)
	elif rotation != Vector3.ZERO:
		rotation = Vector3.ZERO

	# Zooming narrows the view: 2x zoom = half as wide (measured as the
	# tangent of the half-angle, so it's a true 2x, not just half the degrees).
	var base_fov := _base_fov
	if zoom > 1.0:
		base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov) * 0.5) / zoom))
	if _fov_offset > 0.01:
		fov = base_fov + _fov_offset
		_fov_offset = maxf(_fov_offset - fov_decay * delta, 0.0)
	elif fov != base_fov:
		fov = base_fov
