class_name AimDownSights
extends Node

## What aiming down the sights LOOKS like (hold right mouse): the gun raises
## to your eye, the view zooms in, and a gun with a scope_overlay blinks to
## its scope image with the gun hidden -- the old Call of Duty sniper scope.
##
## Presentation only (Rule 1, co-op): how far the gun is raised comes from
## WeaponController.aim_amount(), which is part of the simulation (it decides
## each shot's spread). This node just draws it for the local player.
##
## Which guns can aim is WeaponData's "Can Aim" tick box. To take aiming
## out of the game, untick it on every weapon; to remove just the visuals,
## delete this node from player.tscn -- nothing else depends on it.

## How far raised (0..1) the gun has to be before the scope image takes over.
const SCOPE_IN_AT := 0.85
## How long the black blink lasts when the scope goes on or off.
const BLINK_TIME := 0.12

@onready var _player := owner as PlayerMovement
@onready var _viewmodel := owner.get_node("Head/Camera3D/Viewmodel") as Viewmodel

var _scoped := false
var _previous_aim := 0.0
var _raising := false
var _layer: CanvasLayer
var _scope_image: TextureRect
var _left_bar: ColorRect
var _right_bar: ColorRect
var _blink: ColorRect


func _ready() -> void:
	if not owner.is_multiplayer_authority():
		set_process(false)
		return
	_build_overlay()


func _process(_delta: float) -> void:
	var weapon := _player.weapons.current_weapon()
	var aim := _player.weapons.aim_amount()
	if weapon == null or not weapon.can_aim:
		aim = 0.0
	var eased := smoothstep(0.0, 1.0, aim)

	# The gun travels from its hip position to its aimed position.
	if weapon:
		_viewmodel.aim_offset = (_viewmodel.aim_position_for(weapon) - weapon.viewmodel_position) * eased
	else:
		_viewmodel.aim_offset = Vector3.ZERO
	_viewmodel.aim_steady = eased

	var scoped := weapon != null and weapon.scope_overlay != null and aim >= SCOPE_IN_AT
	if scoped != _scoped:
		_set_scoped(scoped, weapon)
	if weapon == null or aim <= 0.0:
		_player.camera.zoom = 1.0
	elif weapon.scope_overlay:
		# A scope zooms all at once, hidden by the blink.
		_player.camera.zoom = weapon.aim_zoom if scoped else 1.0
	else:
		_player.camera.zoom = lerpf(1.0, weapon.aim_zoom, eased)
	if _scoped:
		_fit_scope_to_screen()

	# Raise/lower sounds play when the gun starts moving each way.
	if aim != _previous_aim:
		var raising := aim > _previous_aim
		if raising != _raising and weapon:
			SoundPlayer.play_2d(weapon.aim_in_sound if raising else weapon.aim_out_sound)
		_raising = raising
	_previous_aim = aim


func _set_scoped(scoped: bool, weapon: WeaponData) -> void:
	_scoped = scoped
	_viewmodel.set_gun_hidden(scoped)
	if scoped:
		_scope_image.texture = weapon.scope_overlay
	_scope_image.visible = scoped
	_left_bar.visible = scoped
	_right_bar.visible = scoped
	# A quick blink to black and back hides the swap.
	_blink.color.a = 1.0
	_layer.visible = true
	var tween := create_tween()
	tween.tween_property(_blink, "color:a", 0.0, BLINK_TIME)
	tween.tween_callback(func() -> void: _layer.visible = _scoped)


## The scope image keeps its shape, filling the screen's height; black bars
## fill whatever's left at the sides on a wide screen.
func _fit_scope_to_screen() -> void:
	var screen := _scope_image.get_viewport_rect().size
	var texture := _scope_image.texture
	if texture == null or texture.get_height() == 0:
		return
	var image_width := screen.y * texture.get_width() / float(texture.get_height())
	var side := maxf((screen.x - image_width) * 0.5, 0.0)
	_left_bar.position = Vector2.ZERO
	_left_bar.size = Vector2(side + 1.0, screen.y)
	_right_bar.position = Vector2(screen.x - side - 1.0, 0.0)
	_right_bar.size = Vector2(side + 1.0, screen.y)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 0 # under the HUD, so ammo and hit markers show over the scope
	_layer.visible = false
	add_child(_layer)

	_scope_image = TextureRect.new()
	_scope_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scope_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_scope_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_scope_image)

	_left_bar = _black_rect()
	_right_bar = _black_rect()
	_blink = _black_rect()
	_blink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blink.color.a = 0.0


func _black_rect() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(rect)
	return rect
