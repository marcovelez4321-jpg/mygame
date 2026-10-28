class_name LoadingScreen
extends CanvasLayer

## The loading screen (the user's, 2026-10-27: a classic zombies one -- the
## art full screen, a loading bar in the bottom right, and over the bar what
## it's loading, what it's doing and how far along it is). The game's main
## scene: it loads `target` in the background (ResourceLoader's threaded
## load), puts it in, and stays over it while it settles -- its navigation
## worked out, a few frames for the first shaders -- then fades away.
## `art`: the user's picture to come; a dark placeholder till then.

## What it opens, and what it calls it.
@export_file("*.tscn") var target := "res://scenes/zombies/stacks_demo.tscn"
@export var place_name := "the Stacks"
@export var art: Texture2D
## The bar: its size, how far in from the bottom-right corner, its colours.
@export var bar_size := Vector2(360.0, 6.0)
@export var bar_margin := Vector2(56.0, 56.0)
@export var bar_back := Color(1.0, 1.0, 1.0, 0.15)
@export var bar_fill := Color(0.9, 0.88, 0.84)
@export var text_color := Color(0.85, 0.83, 0.8)
@export var font_size := 16

## Its stages: [what it's doing, the share of the bar it ends at].
const LOADING := 0.7
const BUILDING := 0.8
const ROUTES := 0.92
## The longest it waits on the navigation, and the frames it settles for.
const ROUTES_TIMEOUT := 12.0
const SETTLE_FRAMES := 30
const FADE := 0.5

enum Stage { LOADING, BUILDING, ROUTES, SETTLING, FADING }

var _stage := Stage.LOADING
var _shown := 0.0
var _wanted := 0.0
var _scene: Node
var _waited := 0.0
var _frames := 0
var _root: Control
var _fill: ColorRect
var _label: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	# Not the scene itself (so it stays when the scene changes to `target`,
	# over it while it settles).
	_step_aside.call_deferred()
	if ResourceLoader.load_threaded_request(target) != OK:
		_say("Couldn't load %s" % place_name, 0.0)
		set_process(false)


func _step_aside() -> void:
	if get_tree().current_scene == self:
		get_tree().current_scene = null


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var back := ColorRect.new()
	back.color = Color(0.03, 0.03, 0.035)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)
	if art:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(picture)
	# The bar, bottom right; the words over it, right-aligned to it.
	var bar := ColorRect.new()
	bar.color = bar_back
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.offset_left = -bar_margin.x - bar_size.x
	bar.offset_right = -bar_margin.x
	bar.offset_top = -bar_margin.y - bar_size.y
	bar.offset_bottom = -bar_margin.y
	_root.add_child(bar)
	_fill = ColorRect.new()
	_fill.color = bar_fill
	_fill.size = Vector2(0.0, bar_size.y)
	bar.add_child(_fill)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override(&"font_size", font_size)
	_label.add_theme_color_override(&"font_color", text_color)
	_label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.offset_left = -bar_margin.x - bar_size.x - 200.0
	_label.offset_right = -bar_margin.x
	_label.offset_top = -bar_margin.y - bar_size.y - 10.0 - font_size * 1.6
	_label.offset_bottom = -bar_margin.y - bar_size.y - 10.0
	_root.add_child(_label)


func _process(delta: float) -> void:
	match _stage:
		Stage.LOADING:
			var progress := []
			var status := ResourceLoader.load_threaded_get_status(target, progress)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_say("Building %s" % place_name, LOADING)
				_stage = Stage.BUILDING
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_say("Couldn't load %s" % place_name, _wanted)
				set_process(false)
				return
			else:
				_say("Loading %s" % place_name, LOADING * float(progress[0] if not progress.is_empty() else 0.0))
		Stage.BUILDING:
			# (A frame after the words change, so they show before the stall.)
			_frames += 1
			if _frames == 2:
				# (The scene's own way in: it's the current scene as it starts.)
				get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(target) as PackedScene)
			elif _frames > 2 and get_tree().current_scene != null:
				_scene = get_tree().current_scene
				_say("Finding the ways through %s" % place_name, BUILDING)
				_stage = Stage.ROUTES
				_frames = 0
		Stage.ROUTES:
			_waited += delta
			var world := (_scene as Node3D).get_world_3d() if _scene is Node3D else null
			var routed := world == null or NavigationServer3D.map_get_iteration_id(world.navigation_map) != 0
			_say("Finding the ways through %s" % place_name, lerpf(BUILDING, ROUTES, clampf(_waited / ROUTES_TIMEOUT, 0.0, 0.9)))
			if routed or _waited >= ROUTES_TIMEOUT:
				_say("Settling in", ROUTES)
				_stage = Stage.SETTLING
		Stage.SETTLING:
			_frames += 1
			_say("Settling in", lerpf(ROUTES, 1.0, float(_frames) / SETTLE_FRAMES))
			if _frames >= SETTLE_FRAMES and _shown >= 0.999:
				_stage = Stage.FADING
				print("loaded %s in %.1f s" % [place_name, Time.get_ticks_msec() / 1000.0])
				var fade := create_tween()
				fade.tween_interval(0.15)
				fade.tween_property(_root, ^"modulate:a", 0.0, FADE)
				fade.tween_callback(queue_free)
	# The bar eases to where it's got to (never back).
	_shown = move_toward(_shown, _wanted, delta * 1.5)
	_fill.size.x = bar_size.x * _shown
	_label.text = "%s   %d%%" % [_label.get_meta(&"doing", ""), roundi(_shown * 100.0)]


## What it's doing now, and how far along the bar that's got it.
func _say(doing: String, share: float) -> void:
	_label.set_meta(&"doing", doing)
	_wanted = maxf(_wanted, clampf(share, 0.0, 1.0))
