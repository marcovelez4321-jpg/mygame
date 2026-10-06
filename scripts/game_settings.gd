extends Node

## Global player settings: resolution, window mode, vsync, audio volumes and
## mouse sensitivity, saved to user://settings.cfg. Autoloaded as
## "GameSettings" so any scene (pause menu, future main menu, etc.) can read
## or change it without needing a node reference passed around.
##
## Rule 1 note: this is pure client-local presentation state, same category
## as camera/HUD -- a server never needs to know or care what resolution a
## player's monitor is running, so this is fine as a plain singleton instead
## of going through PlayerInput/simulation like movement does.

const SETTINGS_PATH := "user://settings.cfg"

enum WindowMode { WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN }
## When pickups and usable things get an outline (InteractHighlight).
enum OutlineMode { LOOKING, ALWAYS, OFF }

## Every audio bus the pause menu's Audio panel shows a slider for, in order:
## Master, then one per audio/sfx folder (default_bus_layout.tres).
const AUDIO_BUSES: Array[String] = ["Master", "Body", "Surface", "Gore", "Props",
		"Weapons", "Enemies", "Player", "Hits", "Ambience"]

var resolution: Vector2i = Vector2i(1280, 720)
var window_mode: WindowMode = WindowMode.WINDOWED
var vsync_enabled: bool = true
## Bus name -> linear volume (1.0 = 100%). Missing = 100%.
var audio_volumes: Dictionary = {}
## Saved mouse sensitivity; 0 = never set, so the player keeps its own default.
var mouse_sensitivity: float = 0.0
## Path of the character FBX the player wears (PlayerModel); "" = first one.
var player_character: String = ""
var outline_mode: OutlineMode = OutlineMode.LOOKING


func _ready() -> void:
	load_settings()
	apply_all()


func get_bus_volume(bus: String) -> float:
	return audio_volumes.get(bus, 1.0)


## Live: applies straight away. Saved when the pause menu closes (see
## pause_menu.gd), not on every slider tick.
func set_bus_volume(bus: String, linear: float) -> void:
	audio_volumes[bus] = linear
	_apply_bus_volume(bus)


## Common resolutions across common aspect ratios, filtered down to ones
## that actually fit the monitor Godot detects -- this is what makes the
## list work sensibly "for any monitor" instead of listing 4K options on a
## 1080p screen. The monitor's own native resolution is always included
## even if it's not one of the presets (e.g. an odd laptop panel size).
func get_common_resolutions() -> Array[Vector2i]:
	var native := DisplayServer.screen_get_size()
	var candidates: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1080),
		Vector2i(2560, 1440),
		Vector2i(3440, 1440),
		Vector2i(3840, 2160),
	]
	var result: Array[Vector2i] = []
	for res in candidates:
		if res.x <= native.x and res.y <= native.y:
			result.append(res)
	if not result.has(native):
		result.append(native)
	return result


func set_resolution(size: Vector2i) -> void:
	resolution = size
	_apply_resolution()
	save_settings()


func set_window_mode(mode: WindowMode) -> void:
	window_mode = mode
	_apply_window_mode()
	save_settings()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_vsync()
	save_settings()


func apply_all() -> void:
	_apply_window_mode()
	_apply_resolution()
	_apply_vsync()
	for bus in AUDIO_BUSES:
		_apply_bus_volume(bus)


func _apply_bus_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(get_bus_volume(bus)))


## Resolution only means anything in windowed mode -- fullscreen/borderless
## always render at the monitor's own native size, same as every AAA game.
func _apply_resolution() -> void:
	if window_mode == WindowMode.WINDOWED and not get_window().is_embedded():
		get_window().size = resolution
		get_window().move_to_center()


func _apply_window_mode() -> void:
	# When testing inside the Godot editor's embedded Game panel, the "window"
	# is really just a texture the editor draws -- it isn't a real OS window,
	# so it can't be resized, moved, or fullscreened independently of the
	# editor, and the engine will warn if we try. This is only ever true
	# while developing in-editor; an exported build (or the editor's
	# separate-window play mode) always gets a real OS window, so skipping
	# these calls here doesn't affect what a real player experiences.
	if get_window().is_embedded():
		return

	match window_mode:
		WindowMode.WINDOWED:
			get_window().mode = Window.MODE_WINDOWED
			get_window().borderless = false
			get_window().size = resolution
			get_window().move_to_center()
		WindowMode.BORDERLESS_FULLSCREEN:
			get_window().mode = Window.MODE_FULLSCREEN
			get_window().borderless = true
		WindowMode.EXCLUSIVE_FULLSCREEN:
			get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN
			get_window().borderless = false


func _apply_vsync() -> void:
	var mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "resolution_x", resolution.x)
	config.set_value("display", "resolution_y", resolution.y)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "vsync", vsync_enabled)
	for bus in audio_volumes:
		config.set_value("audio", bus, audio_volumes[bus])
	if mouse_sensitivity > 0.0:
		config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	if not player_character.is_empty():
		config.set_value("player", "character", player_character)
	config.set_value("display", "outline_mode", outline_mode)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return # no saved file yet -- keep the defaults above
	var res_x: int = config.get_value("display", "resolution_x", resolution.x)
	var res_y: int = config.get_value("display", "resolution_y", resolution.y)
	resolution = Vector2i(res_x, res_y)
	window_mode = config.get_value("display", "window_mode", window_mode) as WindowMode
	vsync_enabled = config.get_value("display", "vsync", vsync_enabled)
	for bus in AUDIO_BUSES:
		if config.has_section_key("audio", bus):
			audio_volumes[bus] = config.get_value("audio", bus)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	player_character = config.get_value("player", "character", player_character)
	outline_mode = config.get_value("display", "outline_mode", outline_mode) as OutlineMode
