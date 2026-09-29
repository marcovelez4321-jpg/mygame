extends CanvasLayer

## Escape-triggered pause overlay: display settings (resolution, window
## mode, vsync) plus sensitivity, resume, and quit. Autoloaded, so it exists
## in every scene without needing to be added to each map by hand.
##
## Air acceleration used to be a live slider here too. It's gone now that
## movement is locked to a single committed style (Rule 3): a competitive
## physics constant can't be a per-client dial once multiplayer exists, or
## whoever cranks theirs highest just wins. It's a plain @export on
## player_movement.gd now -- a design number I set, not a player setting.

@onready var dim: ColorRect = $Dim
@onready var resolution_option: OptionButton = $Dim/MenuPanel/VBox/ResolutionRow/ResolutionOption
@onready var window_mode_option: OptionButton = $Dim/MenuPanel/VBox/WindowModeRow/WindowModeOption
@onready var vsync_check: CheckButton = $Dim/MenuPanel/VBox/VSyncRow/VSyncCheck
@onready var infinite_ammo_check: CheckButton = $Dim/MenuPanel/VBox/InfiniteAmmoRow/InfiniteAmmoCheck
@onready var sensitivity_slider: HSlider = $Dim/MenuPanel/VBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_value_label: Label = $Dim/MenuPanel/VBox/SensitivityRow/SensitivityValueLabel
@onready var resume_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/ResumeButton
@onready var quit_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/QuitButton

var _resolutions: Array[Vector2i] = []
var player: CharacterBody3D

## Sensitivity is stored on the player as raw radians-per-pixel (a tiny
## number like 0.0025), which makes for an awkward slider. We show/store the
## slider in "x1000" units instead purely so the number on screen is
## friendlier -- same underlying value, just scaled for display.
const SENSITIVITY_DISPLAY_SCALE := 1000.0


func _ready() -> void:
	# Buttons here need to keep working even while the game tree is paused,
	# since pausing the tree is exactly what opening this menu does.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_populate_resolution_options()
	_populate_window_mode_options()
	vsync_check.button_pressed = GameSettings.vsync_enabled

	resolution_option.item_selected.connect(_on_resolution_selected)
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	vsync_check.toggled.connect(_on_vsync_toggled)
	infinite_ammo_check.toggled.connect(_on_infinite_ammo_toggled)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	resume_button.pressed.connect(close)
	quit_button.pressed.connect(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_sensitivity_slider()
	if player:
		infinite_ammo_check.button_pressed = player.get_node("WeaponController").infinite_ammo


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Pulls the player's current sensitivity into the slider. Called every time
## the menu opens (not just once at _ready) so it always reflects reality.
func _sync_sensitivity_slider() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	sensitivity_slider.value = player.mouse_sensitivity * SENSITIVITY_DISPLAY_SCALE
	sensitivity_value_label.text = "%.1f" % sensitivity_slider.value


func _on_sensitivity_changed(value: float) -> void:
	if player:
		player.mouse_sensitivity = value / SENSITIVITY_DISPLAY_SCALE
	sensitivity_value_label.text = "%.1f" % value


func _populate_resolution_options() -> void:
	_resolutions = GameSettings.get_common_resolutions()
	resolution_option.clear()
	for i in _resolutions.size():
		var res: Vector2i = _resolutions[i]
		resolution_option.add_item("%dx%d" % [res.x, res.y])
		if res == GameSettings.resolution:
			resolution_option.select(i)


func _populate_window_mode_options() -> void:
	window_mode_option.clear()
	window_mode_option.add_item("Windowed")
	window_mode_option.add_item("Borderless Fullscreen")
	window_mode_option.add_item("Exclusive Fullscreen")
	window_mode_option.select(GameSettings.window_mode)
	resolution_option.disabled = GameSettings.window_mode != GameSettings.WindowMode.WINDOWED


func _on_resolution_selected(index: int) -> void:
	GameSettings.set_resolution(_resolutions[index])


func _on_window_mode_selected(index: int) -> void:
	GameSettings.set_window_mode(index as GameSettings.WindowMode)
	# Resolution only does anything in windowed mode -- grey it out
	# otherwise so it's visually clear it has no effect right now.
	resolution_option.disabled = index != GameSettings.WindowMode.WINDOWED


func _on_vsync_toggled(enabled: bool) -> void:
	GameSettings.set_vsync(enabled)


func _on_infinite_ammo_toggled(enabled: bool) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if player:
		(player.get_node("WeaponController") as WeaponController).infinite_ammo = enabled
