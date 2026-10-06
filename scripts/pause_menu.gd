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
@onready var hit_zones_check: CheckButton = $Dim/MenuPanel/VBox/HitZonesRow/HitZonesCheck
@onready var sensitivity_slider: HSlider = $Dim/MenuPanel/VBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_value_label: Label = $Dim/MenuPanel/VBox/SensitivityRow/SensitivityValueLabel
@onready var resume_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/ResumeButton
@onready var quit_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/QuitButton
@onready var menu_panel: Panel = $Dim/MenuPanel
@onready var audio_button: Button = $Dim/MenuPanel/VBox/AudioButton
@onready var character_option: OptionButton = $Dim/MenuPanel/VBox/CharacterRow/CharacterOption
@onready var test_map_button: Button = $Dim/MenuPanel/VBox/TestMapButton
@onready var hub_button: Button = $Dim/MenuPanel/VBox/HubButton

## On-screen names for GameSettings.AUDIO_BUSES, one slider each.
const AUDIO_BUS_LABELS := {
	"Master": "Master",
	"Body": "Bodies",
	"Surface": "Footsteps & Surfaces",
	"Gore": "Gore",
	"Props": "Props",
	"Weapons": "Weapons",
	"Enemies": "Enemies",
	"Player": "Player",
	"Hits": "Hit Feedback",
	"Ambience": "Ambience",
}
## Slider range in percent; 100 sits in the middle so any category can be
## turned up as well as down.
const AUDIO_MAX_PERCENT := 200.0

var _resolutions: Array[Vector2i] = []
var player: CharacterBody3D
var _audio_panel: Panel
## Character dropdown index -> FBX path (PlayerModel.available_characters()).
var _characters: Array[String] = []
## Bus name -> [HSlider, value Label]
var _audio_rows: Dictionary = {}

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
	hit_zones_check.toggled.connect(_on_hit_zones_toggled)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	resume_button.pressed.connect(close)
	quit_button.pressed.connect(func() -> void:
		GameSettings.save_settings()
		get_tree().quit()
	)
	audio_button.pressed.connect(_show_audio_panel)
	_build_audio_panel()
	_populate_character_options()
	character_option.item_selected.connect(_on_character_selected)

	# Play a TrenchBroom .map from your own computer (see TestMapLoader).
	var test_map_loader := TestMapLoader.new()
	add_child(test_map_loader)
	test_map_button.pressed.connect(test_map_loader.pick)
	test_map_loader.map_ready.connect(_open_test_map)
	hub_button.pressed.connect(_go_to_hub)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	# Only offered when you're somewhere other than the hub already.
	var current := get_tree().current_scene
	hub_button.visible = current != null and current.scene_file_path != MissionData.HUB_SCENE
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_sensitivity_slider()
	if is_instance_valid(player):
		var weapons := player.get_node("WeaponController") as WeaponController
		infinite_ammo_check.button_pressed = weapons.infinite_ammo
		hit_zones_check.button_pressed = weapons.show_hit_zones


## Saves here rather than on every slider tick: dragging a slider fires
## dozens of changes a second, and none of them need to hit the disk.
func close() -> void:
	visible = false
	_show_main_panel()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameSettings.save_settings()


## Pulls the player's current sensitivity into the slider. Called every time
## the menu opens (not just once at _ready) so it always reflects reality.
func _sync_sensitivity_slider() -> void:
	if not is_instance_valid(player):
		player = PlayerMovement.local_player(get_tree())
	if not is_instance_valid(player):
		return
	sensitivity_slider.value = player.mouse_sensitivity * SENSITIVITY_DISPLAY_SCALE
	sensitivity_value_label.text = "%.1f" % sensitivity_slider.value


func _on_sensitivity_changed(value: float) -> void:
	if is_instance_valid(player):
		player.mouse_sensitivity = value / SENSITIVITY_DISPLAY_SCALE
	GameSettings.mouse_sensitivity = value / SENSITIVITY_DISPLAY_SCALE
	sensitivity_value_label.text = "%.1f" % value


## A second panel the same size and spot as the main one, built from
## GameSettings.AUDIO_BUSES: a slider per bus. Built in code so adding a
## sound category later is one line in GameSettings, not hand-made nodes.
func _build_audio_panel() -> void:
	_audio_panel = Panel.new()
	_audio_panel.anchor_left = 0.5
	_audio_panel.anchor_top = 0.5
	_audio_panel.anchor_right = 0.5
	_audio_panel.anchor_bottom = 0.5
	_audio_panel.offset_left = menu_panel.offset_left
	_audio_panel.offset_top = menu_panel.offset_top
	_audio_panel.offset_right = menu_panel.offset_right
	_audio_panel.offset_bottom = menu_panel.offset_bottom
	_audio_panel.visible = false
	dim.add_child(_audio_panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 20.0
	vbox.offset_top = 20.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 10)
	_audio_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Audio"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	for bus in GameSettings.AUDIO_BUSES:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = AUDIO_BUS_LABELS.get(bus, bus)
		label.custom_minimum_size = Vector2(170, 0)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = AUDIO_MAX_PERCENT
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(52, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
		row.add_child(slider)
		row.add_child(value_label)
		vbox.add_child(row)
		_audio_rows[bus] = [slider, value_label]
		slider.value_changed.connect(_on_audio_slider_changed.bind(bus))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_show_main_panel)
	vbox.add_child(back)


func _show_audio_panel() -> void:
	for bus in _audio_rows:
		var slider: HSlider = _audio_rows[bus][0]
		slider.set_value_no_signal(GameSettings.get_bus_volume(bus) * 100.0)
		_update_audio_label(bus, slider.value)
	menu_panel.visible = false
	_audio_panel.visible = true


func _show_main_panel() -> void:
	_audio_panel.visible = false
	menu_panel.visible = true


func _on_audio_slider_changed(percent: float, bus: String) -> void:
	GameSettings.set_bus_volume(bus, percent / 100.0)
	_update_audio_label(bus, percent)


func _update_audio_label(bus: String, percent: float) -> void:
	var value_label: Label = _audio_rows[bus][1]
	value_label.text = "%d%%" % roundi(percent)


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


## "Male - Character_15", "Female - Character_Female_03"... in the same
## sorted order PlayerModel uses, so an index means the same model everywhere.
func _populate_character_options() -> void:
	_characters = PlayerModel.available_characters()
	character_option.clear()
	for path in _characters:
		character_option.add_item("%s - %s" % [path.get_base_dir().get_file(), path.get_file().get_basename()])
	var current := _characters.find(GameSettings.player_character)
	character_option.select(maxi(current, 0))


## Swaps your model live; saved with everything else when the menu closes.
func _on_character_selected(index: int) -> void:
	GameSettings.player_character = _characters[index]
	if not is_instance_valid(player):
		player = PlayerMovement.local_player(get_tree())
	if is_instance_valid(player):
		var model := player.get_node_or_null("PlayerModel") as PlayerModel
		if model:
			model.set_character(_characters[index])


## Back to Grandma's house (MissionData.HUB_SCENE) from a mission -- a
## stand-in until missions have their own return portal at the end.
## Rule 1 (co-op): becomes a host-only "everyone back to the hub".
func _go_to_hub() -> void:
	close()
	get_tree().change_scene_to_file(MissionData.HUB_SCENE)


## Reloads even when already in the test level, so re-picking an edited map
## rebuilds it.
func _open_test_map() -> void:
	close()
	get_tree().change_scene_to_file(TestMapLevel.SCENE_PATH)


func _on_vsync_toggled(enabled: bool) -> void:
	GameSettings.set_vsync(enabled)


func _on_infinite_ammo_toggled(enabled: bool) -> void:
	if not is_instance_valid(player):
		player = PlayerMovement.local_player(get_tree())
	if is_instance_valid(player):
		(player.get_node("WeaponController") as WeaponController).infinite_ammo = enabled


func _on_hit_zones_toggled(enabled: bool) -> void:
	if not is_instance_valid(player):
		player = PlayerMovement.local_player(get_tree())
	if is_instance_valid(player):
		(player.get_node("WeaponController") as WeaponController).show_hit_zones = enabled
