class_name TestMapLevel
extends MapLevel

## A level that builds its .map file while the game is RUNNING, instead of
## with the Build Map button in the editor -- so a mapper can play their own
## TrenchBroom map in the published web build with no Godot at all. Opened by
## TestMapLoader (pause menu -> Load Test Map, or dropping a .map file onto
## the game window), which first copies the chosen file to MAP_PATH.
##
## Everything after the build is the normal MapLevel setup: the player moves
## to the map's info_player_start and enemies get a navigation mesh baked
## from the freshly built geometry.

const SCENE_PATH := "res://scenes/test_map_level.tscn"
## The game's own storage. In a browser this is the browser's local storage
## for this site -- the map never leaves the mapper's computer.
const MAP_PATH := "user://test_map.map"

@onready var _map: FuncGodotMap = $FuncGodotMap


func _ready() -> void:
	_build_map()
	super._ready()


func _build_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		_show_message("No test map loaded yet -- press Esc, then Load Test Map.")
		return
	# A copy that doesn't try to save the materials it generates: an exported
	# game's own files are read-only, so saving would just print errors.
	var settings := _map.map_settings.duplicate() as FuncGodotMapSettings
	settings.save_generated_materials = false
	_map.map_settings = settings
	_map.global_map_file = MAP_PATH
	_map.build()
	if _map.get_child_count() == 0:
		_show_message("Couldn't build that map -- is it a 2v-2 TrenchBroom map?")


## A mapper testing their map sees broken target names right away, in the
## top-left, instead of a lever that silently does nothing.
func _show_map_problems(problems: PackedStringArray) -> void:
	_show_message("Map problems:\n" + "\n".join(problems))


func _show_message(text: String) -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.position = Vector2(24.0, 24.0)
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)
	add_child(layer)
