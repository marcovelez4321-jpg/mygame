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
@onready var invisible_check: CheckButton = $Dim/MenuPanel/VBox/InvisibleRow/InvisibleCheck
@onready var sensitivity_slider: HSlider = $Dim/MenuPanel/VBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_value_label: Label = $Dim/MenuPanel/VBox/SensitivityRow/SensitivityValueLabel
@onready var resume_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/ResumeButton
@onready var quit_button: Button = $Dim/MenuPanel/VBox/ButtonsRow/QuitButton
@onready var menu_panel: Panel = $Dim/MenuPanel
@onready var audio_button: Button = $Dim/MenuPanel/VBox/AudioButton
@onready var character_option: OptionButton = $Dim/MenuPanel/VBox/CharacterRow/CharacterOption
@onready var outlines_option: OptionButton = $Dim/MenuPanel/VBox/OutlinesRow/OutlinesOption
@onready var test_map_button: Button = $Dim/MenuPanel/VBox/TestMapButton
@onready var hub_button: Button = $Dim/MenuPanel/VBox/HubButton

## On-screen names for GameSettings.AUDIO_BUSES, one slider each.
const AUDIO_BUS_LABELS := {
	"Master": "Master",
	"Body": "Bodies",
	"Surface": "Footsteps & Movement", # (jumps, lands, dashes, mantles too: the user's)
	"Gore": "Gore",
	"Props": "Props",
	"Weapons": "Weapons",
	"Enemies": "Enemies",
	"Player": "Player",
	"Hits": "Hit Feedback",
	"Ambience": "Ambience",
	"Music": "Music",
}
## Slider range in percent; 100 sits in the middle so any category can be
## turned up as well as down.
const AUDIO_MAX_PERCENT := 200.0

var _resolutions: Array[Vector2i] = []
var player: CharacterBody3D
var _audio_panel: Panel
var _graphics_panel: Panel
## SewerLook value key -> [HSlider, value Label] / ColorPickerButton.
var _look_sliders: Dictionary = {}
var _look_pickers: Dictionary = {}
## Character dropdown index -> FBX path (PlayerModel.available_characters()).
var _characters: Array[String] = []
## Bus name -> [HSlider, value Label]
var _audio_rows: Dictionary = {}
## "Infinite Grapples" (made from a copy of the Infinite Ammo row).
var _infinite_grapples_check: CheckButton
var _coop_panel: Panel

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
	# Debug: no enemy can pick you as a target (they fight each other instead).
	invisible_check.toggled.connect(func(enabled: bool) -> void:
		if is_instance_valid(player):
			player.set("hidden_from_enemies", enabled)
	)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	resume_button.pressed.connect(close)
	quit_button.pressed.connect(func() -> void:
		GameSettings.save_settings()
		get_tree().quit()
	)
	audio_button.pressed.connect(_show_audio_panel)
	_build_audio_panel()
	_build_graphics_panel()
	_build_coop_panel()
	_populate_character_options()
	character_option.item_selected.connect(_on_character_selected)
	_add_tentacle_row()
	_add_infinite_grapples_row()
	# Same order as GameSettings.OutlineMode.
	for label in ["When looking at it", "Always", "Off"]:
		outlines_option.add_item(label)
	outlines_option.select(GameSettings.outline_mode)
	outlines_option.item_selected.connect(func(index: int) -> void:
		GameSettings.outline_mode = index as GameSettings.OutlineMode
	)

	# Play a TrenchBroom .map from your own computer (see TestMapLoader).
	var test_map_loader := TestMapLoader.new()
	add_child(test_map_loader)
	test_map_button.pressed.connect(test_map_loader.pick)
	test_map_loader.map_ready.connect(_open_test_map)
	hub_button.pressed.connect(_go_to_hub)


## "Infinite Grapples" (PlayerGrapple.infinite_charges): a copy of the
## Infinite Ammo row placed just under it.
func _add_infinite_grapples_row() -> void:
	var ammo_row := infinite_ammo_check.get_parent()
	var row := ammo_row.duplicate() as HBoxContainer
	row.name = "InfiniteGrapplesRow"
	for child in row.get_children():
		if child is Label:
			(child as Label).text = "Infinite Grapples"
		elif child is CheckButton:
			_infinite_grapples_check = child as CheckButton
	ammo_row.get_parent().add_child(row)
	ammo_row.get_parent().move_child(row, ammo_row.get_index() + 1)
	_infinite_grapples_check.toggled.connect(func(enabled: bool) -> void:
		if not is_instance_valid(player):
			player = PlayerMovement.local_player(get_tree())
		if is_instance_valid(player) and player.has_node("PlayerGrapple"):
			player.get_node("PlayerGrapple").set("infinite_charges", enabled)
	)


## "Tentacle style" (GameSettings.tentacle_style): a copy of the Outlines row
## placed just under it. Called before the Outlines row gets its items.
func _add_tentacle_row() -> void:
	var outlines_row := outlines_option.get_parent()
	var row := outlines_row.duplicate() as HBoxContainer
	row.name = "TentacleRow"
	(row.get_child(0) as Label).text = "Tentacle style"
	var option := row.get_child(1) as OptionButton
	outlines_row.get_parent().add_child(row)
	outlines_row.get_parent().move_child(row, outlines_row.get_index() + 1)
	# Same order as GameSettings.TentacleStyle.
	for label in ["Black symbiote", "Flesh worm", "Spider horde"]:
		option.add_item(label)
	option.select(GameSettings.tentacle_style)
	option.item_selected.connect(func(index: int) -> void:
		GameSettings.tentacle_style = index as GameSettings.TentacleStyle
	)


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
	# In co-op the game doesn't stop for one player's menu (the others are
	# still playing): only offline does Esc freeze it.
	get_tree().paused = not Network.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_sensitivity_slider()
	if is_instance_valid(player):
		var weapons := player.get_node("WeaponController") as WeaponController
		infinite_ammo_check.button_pressed = weapons.infinite_ammo
		if _infinite_grapples_check and player.has_node("PlayerGrapple"):
			_infinite_grapples_check.set_pressed_no_signal(player.get_node("PlayerGrapple").get("infinite_charges") == true)
		hit_zones_check.button_pressed = weapons.show_hit_zones
		invisible_check.set_pressed_no_signal(player.get("hidden_from_enemies") == true)


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


## A panel the same size and spot as the main one, hidden, with a title --
## returns its VBoxContainer to fill. Audio and Graphics are built this way.
func _make_sub_panel(title_text: String) -> VBoxContainer:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = menu_panel.offset_left
	panel.offset_top = menu_panel.offset_top
	panel.offset_right = menu_panel.offset_right
	panel.offset_bottom = menu_panel.offset_bottom
	panel.visible = false
	dim.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 20.0
	vbox.offset_top = 20.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	return vbox


## Pushes what's below to the bottom (unless something above already fills
## the space) and adds the Back button.
func _finish_sub_panel(vbox: VBoxContainer, push_down: bool = true) -> void:
	if push_down:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_show_main_panel)
	vbox.add_child(back)


## A second panel built from GameSettings.AUDIO_BUSES: a slider per bus.
## Built in code so adding a sound category later is one line in
## GameSettings, not hand-made nodes.
func _build_audio_panel() -> void:
	var vbox := _make_sub_panel("Audio")
	_audio_panel = vbox.get_parent() as Panel

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
	_add_skim_sound_row(vbox)
	_finish_sub_panel(vbox)


## "Skim Sound" (GameSettings.skim_sound): what skimming up a hill sounds
## like. One without its file yet shows greyed out.
func _add_skim_sound_row(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Skim Sound"
	label.custom_minimum_size = Vector2(170, 0)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Same order as GameSettings.SkimSound.
	var names := ["Wet glide", "Chitin skate", "Wing flutter"]
	for i in names.size():
		var has_file := ResourceLoader.exists(PlayerSound.SKIM_FILES[i])
		option.add_item(names[i] if has_file else names[i] + " (no sound yet)")
		option.set_item_disabled(i, not has_file)
	option.select(GameSettings.skim_sound)
	option.item_selected.connect(func(index: int) -> void:
		GameSettings.skim_sound = index as GameSettings.SkimSound
		GameSettings.save_settings()
	)
	row.add_child(label)
	row.add_child(option)
	vbox.add_child(row)


## Everything about how the game looks, in one place: the display settings
## (moved here from the main panel) and the sewer-look switches (SewerLook).
## Opened by a Graphics button added next to Audio.
func _build_graphics_panel() -> void:
	var outer := _make_sub_panel("Graphics")
	_graphics_panel = outer.get_parent() as Panel
	# More than fits: everything below the title scrolls.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	for row in [resolution_option.get_parent(), window_mode_option.get_parent(),
			vsync_check.get_parent(), outlines_option.get_parent()]:
		(row as Node).reparent(vbox, false)
	_add_heading(vbox, "Sewer Look")
	_add_toggle(vbox, "Sickly Color Grade", GameSettings.color_grade, func(on: bool) -> void: GameSettings.color_grade = on)
	_add_toggle(vbox, "Grime & Wet Floors", GameSettings.grime, func(on: bool) -> void: GameSettings.grime = on)
	_add_toggle(vbox, "Ground Fog", GameSettings.ground_fog, func(on: bool) -> void: GameSettings.ground_fog = on)
	_add_toggle(vbox, "PS1 Texture Warp", GameSettings.texture_warp, func(on: bool) -> void: GameSettings.texture_warp = on)
	# The Stalker's fear meter, shown (the user's: to see how it's working).
	_add_toggle(vbox, "Player Fear Meter", GameSettings.show_fear_meter, func(on: bool) -> void: GameSettings.show_fear_meter = on)
	_add_heading(vbox, "Look Values")
	for entry in SewerLook.VALUES:
		_add_look_slider(vbox, entry[0], entry[1], entry[2], entry[3], entry[4])
	for entry in SewerLook.COLORS:
		_add_look_picker(vbox, entry[0], entry[1])
	var reset := Button.new()
	reset.text = "Reset Look Values"
	reset.custom_minimum_size = Vector2(0, 32)
	reset.pressed.connect(func() -> void:
		SewerLook.reset_values()
		_sync_look_widgets()
	)
	vbox.add_child(reset)
	_finish_sub_panel(outer, false)

	var graphics_button := Button.new()
	graphics_button.text = "Graphics"
	graphics_button.custom_minimum_size = audio_button.custom_minimum_size
	audio_button.get_parent().add_child(graphics_button)
	audio_button.get_parent().move_child(graphics_button, audio_button.get_index())
	graphics_button.pressed.connect(_show_graphics_panel)


## A labelled on/off switch: `apply` stores it, then the look updates live.
func _add_toggle(vbox: VBoxContainer, text: String, on: bool, apply: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(160, 0)
	var check := CheckButton.new()
	check.button_pressed = on
	check.toggled.connect(func(pressed: bool) -> void:
		apply.call(pressed)
		SewerLook.apply_settings()
		GameSettings.save_settings()
	)
	row.add_child(label)
	row.add_child(check)
	vbox.add_child(row)


func _add_heading(vbox: VBoxContainer, text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	vbox.add_child(heading)


## A slider for SewerLook value `key`: changes it live, with its number beside it.
func _add_look_slider(vbox: VBoxContainer, key: String, text: String, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	vbox.add_child(row)
	_look_sliders[key] = [slider, value_label]
	slider.value_changed.connect(func(value: float) -> void:
		SewerLook.set_value(key, value)
		value_label.text = _look_number(value, step)
	)


## A colour picker for SewerLook colour `key`.
func _add_look_picker(vbox: VBoxContainer, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(80, 28)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(picker)
	vbox.add_child(row)
	_look_pickers[key] = picker
	picker.color_changed.connect(func(color: Color) -> void: SewerLook.set_value(key, color))


## The widgets show SewerLook's current values (on open, and after a reset).
func _sync_look_widgets() -> void:
	for key: String in _look_sliders:
		var slider: HSlider = _look_sliders[key][0]
		var value: float = SewerLook.get(key)
		slider.set_value_no_signal(value)
		(_look_sliders[key][1] as Label).text = _look_number(value, slider.step)
	for key: String in _look_pickers:
		(_look_pickers[key] as ColorPickerButton).color = SewerLook.get(key)


func _look_number(value: float, step: float) -> String:
	return "%.3f" % value if step < 0.01 else "%.2f" % value


func _show_graphics_panel() -> void:
	_sync_look_widgets()
	menu_panel.visible = false
	_graphics_panel.visible = true


func _show_audio_panel() -> void:
	for bus in _audio_rows:
		var slider: HSlider = _audio_rows[bus][0]
		slider.set_value_no_signal(GameSettings.get_bus_volume(bus) * 100.0)
		_update_audio_label(bus, slider.value)
	menu_panel.visible = false
	_audio_panel.visible = true


func _show_main_panel() -> void:
	_audio_panel.visible = false
	_graphics_panel.visible = false
	_coop_panel.visible = false
	menu_panel.visible = true


## Co-op: host a game, or join one by IP address (Network). To try it alone,
## run two copies: Host in one, Join 127.0.0.1 in the other.
func _build_coop_panel() -> void:
	var vbox := _make_sub_panel("Co-op")
	_coop_panel = vbox.get_parent() as Panel
	var status := Label.new()
	status.text = Network.status
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)
	Network.status_changed.connect(func(text: String) -> void: status.text = text)
	# Steam (SteamCoop, the user's): host with a friends-only lobby and invite
	# friends -- no ports, no addresses. Off (and says why) without GodotSteam
	# or Steam running.
	var steam_row := HBoxContainer.new()
	var steam_host := Button.new()
	steam_host.text = "Host on Steam"
	steam_host.custom_minimum_size = Vector2(0, 36)
	steam_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_host.pressed.connect(func() -> void: Network.steam.host())
	var steam_invite := Button.new()
	steam_invite.text = "Invite friends"
	steam_invite.custom_minimum_size = Vector2(0, 36)
	steam_invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_row.add_child(steam_host)
	steam_row.add_child(steam_invite)
	vbox.add_child(steam_row)
	# Your online friends, one click to invite each (the user's: works without
	# Steam's overlay, which often isn't there when run from the editor).
	var friends_scroll := ScrollContainer.new()
	friends_scroll.custom_minimum_size = Vector2(0, 160)
	friends_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	friends_scroll.visible = false
	var friends_list := VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_scroll.add_child(friends_list)
	vbox.add_child(friends_scroll)
	steam_invite.pressed.connect(func() -> void:
		Network.steam.invite()
		for child in friends_list.get_children():
			child.queue_free()
		var friends: Array[Dictionary] = Network.steam.online_friends()
		if friends.is_empty():
			var none := Label.new()
			none.text = "  (no friends online)"
			friends_list.add_child(none)
		for friend in friends:
			var button := Button.new()
			button.text = "Invite %s" % friend.name
			button.custom_minimum_size = Vector2(0, 30)
			button.pressed.connect(func() -> void:
				var sent: bool = Network.steam.invite_friend(friend.id)
				button.text = ("Invited %s" if sent else "Couldn't invite %s") % friend.name
				button.disabled = sent)
			friends_list.add_child(button)
		friends_scroll.visible = true)
	var steam_note := Label.new()
	steam_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steam_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steam_note.add_theme_font_size_override("font_size", 13)
	vbox.add_child(steam_note)
	var show_steam := func() -> void:
		var ready: bool = Network.steam.available
		steam_host.disabled = not ready
		steam_invite.disabled = not (ready and Network.steam.lobby_id != 0)
		if steam_invite.disabled:
			friends_scroll.visible = false
		steam_note.text = "Steam: accept a friend's invite to join them." if ready else "Steam invites are off: %s" % Network.steam.why_not
	show_steam.call()
	Network.steam.state_changed.connect(func() -> void: show_steam.call())
	Network.status_changed.connect(func(_text: String) -> void: show_steam.call())
	var host := Button.new()
	host.text = "Host (port %d)" % Network.PORT
	host.custom_minimum_size = Vector2(0, 36)
	host.pressed.connect(func() -> void: Network.host())
	vbox.add_child(host)
	var your_address := Label.new()
	your_address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	your_address.add_theme_font_size_override("font_size", 14)
	vbox.add_child(your_address)
	var show_address := func() -> void:
		var addresses := Network.lan_addresses()
		your_address.text = "Your address on this network: %s" % ", ".join(addresses) if not addresses.is_empty() else ""
	show_address.call()
	Network.status_changed.connect(func(_text: String) -> void: show_address.call())
	# Games on the local network: one click to join.
	var lan_title := Label.new()
	lan_title.text = "Games on your network:"
	vbox.add_child(lan_title)
	var lan_list := VBoxContainer.new()
	vbox.add_child(lan_list)
	var none := Label.new()
	none.text = "  (none yet -- the host presses Host)"
	lan_list.add_child(none)
	Network.lan_games_changed.connect(func(games: Array) -> void:
		for child in lan_list.get_children():
			child.queue_free()
		if games.is_empty():
			var empty := Label.new()
			empty.text = "  (none yet -- the host presses Host)"
			lan_list.add_child(empty)
		for game: Dictionary in games:
			var button := Button.new()
			button.text = "Join %s's game (%s, %d in)" % [game.name, game.address, game.players]
			button.custom_minimum_size = Vector2(0, 32)
			button.pressed.connect(func() -> void:
				Network.join(game.address)
				close()
			)
			lan_list.add_child(button)
	)
	var row := HBoxContainer.new()
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host's IP address"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(90, 36)
	join.pressed.connect(func() -> void:
		Network.join(address.text)
		close() # loading the host's world; play when it's in
	)
	row.add_child(address)
	row.add_child(join)
	vbox.add_child(row)
	var leave := Button.new()
	leave.text = "Leave (back to playing alone)"
	leave.custom_minimum_size = Vector2(0, 36)
	leave.pressed.connect(func() -> void: Network.leave())
	vbox.add_child(leave)
	var help := Label.new()
	help.text = ("Same house / same Wi-Fi: the host presses Host, the game shows up above for the other -- click it. "
			+ "If it doesn't, type the host's address (shown on their screen) and Join. "
			+ "The first time, Windows asks to let the game through its firewall: allow it on private networks.\n"
			+ "Playing alone? Run two copies: Host in one, Join 127.0.0.1 in the other.\n"
			+ "Over the internet the host forwards UDP port %d on their router.") % Network.PORT
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 13)
	vbox.add_child(help)
	_finish_sub_panel(vbox)
	var coop_button := Button.new()
	coop_button.text = "Co-op"
	coop_button.custom_minimum_size = audio_button.custom_minimum_size
	audio_button.get_parent().add_child(coop_button)
	audio_button.get_parent().move_child(coop_button, audio_button.get_index())
	coop_button.pressed.connect(func() -> void:
		menu_panel.visible = false
		_coop_panel.visible = true
		Network.start_lan_search()
	)


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
