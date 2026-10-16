class_name GameFont
extends Resource

## The game's one font (the user's: change every bit of text from one place).
## Open res://ui/game_font.tres in the inspector and pick a font (and, if you
## like, a size): the HUD, menus, prompts and the 3D labels all use it, from
## the next time the game starts (GameSettings applies it). Empty = Godot's
## own default font.

@export var font: Font
## The default text size (0 = leave each label's own).
@export var size: int = 0

const PATH := "res://ui/game_font.tres"


## Makes it every text's font: the project theme's default (every Control)
## and Godot's fallback (anything else, Label3D included).
static func apply() -> void:
	if not ResourceLoader.exists(PATH):
		return
	var setting := load(PATH) as GameFont
	if setting == null or setting.font == null:
		return
	ThemeDB.fallback_font = setting.font
	var theme := ThemeDB.get_project_theme()
	if theme:
		theme.default_font = setting.font
	if setting.size > 0:
		ThemeDB.fallback_font_size = setting.size
		if theme:
			theme.default_font_size = setting.size