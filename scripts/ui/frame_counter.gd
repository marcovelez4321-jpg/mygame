extends CanvasLayer

## A small frame counter in the top right corner, over everything (an
## autoload, so it's in every scene): frames a second and the worst frame's
## time (ms) over the last half second -- the worst one shows hitches that
## an average hides (a chunk streaming in, a horde spawning).

## How often it updates (seconds).
const INTERVAL := 0.5

var _label: Label
var _left := 0.0
var _worst := 0.0


func _ready() -> void:
	layer = 128 # over the HUD, the menus and the PS1 dither
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.7))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_label)


func _process(delta: float) -> void:
	_worst = maxf(_worst, delta)
	_left -= delta
	if _left > 0.0:
		return
	_left = INTERVAL
	_label.text = "%d fps  %.1f ms" % [Engine.get_frames_per_second(), _worst * 1000.0]
	_worst = 0.0
