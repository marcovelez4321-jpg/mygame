class_name JournalView
extends Node3D

## The journal held up open in front of you (the user's, 2026-10-25): double-
## click the notebook in the backpack, close the bag, and it's up -- two
## pages (JournalPage) side by side in its cover, in the world's own PS1
## look, held where and as JournalSettings says (quests/journal_settings.tres,
## the user's to set: half the screen's width, lower middle, tipped back).
## TUNED IN GAME (the user's), like the backpack's hold: while reading, J --
## arrows move it, PageUp/PageDown nearer/further, +/- size, Alt + arrows
## tip it back/turn it, Alt + PageUp/PageDown lean it, , . the pages' angle,
## Ctrl finer, F3 saves it to the settings file, J again: done.
## Left click turns forward a page spread, right click back (the grapple's
## off meanwhile); only F puts it away, and picking anything up does
## (PlayerHand). You move as normal while reading. Your own view only: held
## in your hands (the viewmodel's sway: it sways, bobs and comes up with
## them), drawn over the world so it never sinks into a wall.

const SETTINGS := "res://quests/journal_settings.tres"
const COVER := Color(0.16, 0.15, 0.14)
## Tuning speeds: screen shares, metres, degrees and size, a second.
const TUNE_MOVE := 0.25
const TUNE_NEAR := 0.15
const TUNE_TURN := 45.0
const TUNE_SIZE := 0.3
## Its size (screen_share) is the share of the screen's width it takes held
## this far off; nearer or further from there, bigger or smaller.
const SIZE_AT := 0.4

var settings: JournalSettings
var _tuning := false
var _tune_label: Label
var _tune_note := ""

var _player: PlayerMovement
var _camera: Camera3D
var _viewports: Array[SubViewport] = []
var _pages: Array[JournalPage] = []
var _quads: Array[MeshInstance3D] = []
var _cover: MeshInstance3D
var _spread := 0
var _dirty := true
var _page_count := 0


func setup(player: PlayerMovement, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	visible = false
	settings = load(SETTINGS) as JournalSettings if ResourceLoader.exists(SETTINGS) else JournalSettings.new()
	var layer := CanvasLayer.new()
	layer.layer = 20
	_tune_label = Label.new()
	_tune_label.position = Vector2(16.0, 130.0)
	_tune_label.add_theme_font_size_override("font_size", 18)
	_tune_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tune_label.add_theme_constant_override("outline_size", 6)
	_tune_label.visible = false
	layer.add_child(_tune_label)
	add_child(layer)
	for i in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(JournalPage.SIZE)
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var page := JournalPage.new()
		viewport.add_child(page)
		_viewports.append(viewport)
		_pages.append(page)
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		quad.material_override = _over_world(viewport.get_texture(), Color.WHITE, 21)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		_quads.append(quad)
	_cover = MeshInstance3D.new()
	_cover.mesh = BoxMesh.new()
	_cover.material_override = _over_world(null, COVER, 20)
	_cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cover)
	Network.fact_changed.connect(func(_name: StringName, _value: Variant) -> void: _dirty = true)


static func _over_world(texture: Texture2D, color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # (readable)
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = priority
	return material


func _process(_delta: float) -> void:
	var reading := _player != null and _player.is_multiplayer_authority() and not _player.is_dead() \
			and not _player.bag_open and _player.hand.reading()
	if reading != visible:
		visible = reading
		_dirty = true
	if not reading:
		_tuning = false
		_tune_label.visible = false
		return
	if _tuning:
		_tune(_delta)
	_place()
	if _dirty:
		_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_J:
			_tuning = not _tuning
			_tune_note = ""
			_tune_label.visible = _tuning
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_F3 and _tuning:
			var error := ResourceSaver.save(settings, SETTINGS)
			_tune_note = "SAVED to " + SETTINGS if error == OK else "Couldn't save (error %d)" % error
			get_viewport().set_input_as_handled()
			return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		_turn(1)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		_turn(-1)


func _turn(by: int) -> void:
	var last := maxi((_page_count - 1) / 2, 0)
	var to := clampi(_spread + by, 0, last)
	if to != _spread:
		_spread = to
		_dirty = true


func _refresh() -> void:
	_dirty = false
	var entries := QuestJournal.pages()
	_page_count = entries.size()
	_spread = clampi(_spread, 0, maxi((_page_count - 1) / 2, 0))
	for i in 2:
		var number := _spread * 2 + i
		_pages[i].show_entry(entries[number] if number < entries.size() else {}, number)
		_viewports[i].render_target_update_mode = SubViewport.UPDATE_ONCE


## Tuning, each frame: the held keys move, turn and size it.
func _tune(delta: float) -> void:
	var s := settings
	var x := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	var y := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
	var z := float(Input.is_key_pressed(KEY_PAGEDOWN)) - float(Input.is_key_pressed(KEY_PAGEUP))
	var fine := 0.1 if Input.is_key_pressed(KEY_CTRL) else 1.0
	var step := delta * fine
	if Input.is_key_pressed(KEY_ALT): # (not Shift: that's your dash)
		s.tilt_degrees = clampf(s.tilt_degrees + y * TUNE_TURN * step, -90.0, 90.0)
		s.turn_degrees = clampf(s.turn_degrees - x * TUNE_TURN * step, -90.0, 90.0)
		s.roll_degrees = clampf(s.roll_degrees + z * TUNE_TURN * step, -90.0, 90.0)
	else:
		s.sideways = clampf(s.sideways + x * TUNE_MOVE * step, -1.0, 1.0)
		s.drop = clampf(s.drop - y * TUNE_MOVE * step, -1.0, 1.0)
		s.distance = clampf(s.distance + z * TUNE_NEAR * step, 0.1, 2.0)
	var grow := float(Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD)) - float(Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT))
	s.screen_share = clampf(s.screen_share + grow * TUNE_SIZE * step, 0.1, 1.5)
	var open := float(Input.is_key_pressed(KEY_PERIOD)) - float(Input.is_key_pressed(KEY_COMMA))
	s.page_angle_degrees = clampf(s.page_angle_degrees + open * TUNE_TURN * step, 0.0, 45.0)
	_tune_label.text = ("TUNING THE JOURNAL (J: done)\n"
			+ "size %.3f of the screen   %.3f m away   %.3f down   %.3f right\n"
			+ "tipped back %.1f   turned %.1f   leaned %.1f   pages %.1f\n\n"
			+ "Arrows = move   PgUp/PgDn = nearer/further   +/- = size\n"
			+ "Alt + arrows = tip back / turn   Alt + PgUp/PgDn = lean   , . = pages' angle\n"
			+ "Ctrl = finer   F3 = save\n%s") % [s.screen_share, s.distance, s.drop, s.sideways,
			s.tilt_degrees, s.turn_degrees, s.roll_degrees, s.page_angle_degrees, _tune_note]


## Sized to its share of the screen's width at its distance, where and as
## the settings say.
func _place() -> void:
	var s := settings
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x / maxf(screen.y, 1.0)
	var half_height := s.distance * tan(deg_to_rad(_camera.fov) * 0.5)
	var half_width := half_height * aspect
	# Its real size: its share of the screen's width as if held SIZE_AT away
	# -- so nearer looks bigger, further smaller.
	var page_width := SIZE_AT * tan(deg_to_rad(_camera.fov) * 0.5) * aspect * 2.0 * s.screen_share * 0.5
	var page_height := page_width * JournalPage.SIZE.y / JournalPage.SIZE.x
	var turn := Basis.from_euler(Vector3(deg_to_rad(s.tilt_degrees), deg_to_rad(s.turn_degrees), deg_to_rad(s.roll_degrees)))
	transform = Transform3D(turn, Vector3(half_width * 2.0 * s.sideways, -half_height * 2.0 * s.drop, -s.distance))
	var page_angle := deg_to_rad(s.page_angle_degrees)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		(_quads[i].mesh as QuadMesh).size = Vector2(page_width, page_height)
		_quads[i].transform = Transform3D(Basis(Vector3.UP, -side * page_angle),
				Vector3(side * page_width * 0.5 * cos(page_angle), 0.0, page_width * 0.5 * sin(page_angle)))
	(_cover.mesh as BoxMesh).size = Vector3(page_width * 2.08, page_height * 1.04, 0.004)
	_cover.position = Vector3(0.0, 0.0, -0.003)
