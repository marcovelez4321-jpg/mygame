class_name JournalView
extends CanvasLayer

## The journal held up open in front of you (the user's, 2026-10-25):
## double-click the notebook in the backpack, close the bag, and it's up --
## half the screen, lower middle, two pages (JournalPage) side by side in its
## cover, square to your eyes. Drawn over everything, above the PS1 look's
## dither (PS1Dither's layer: the user's -- readable, not crushed), the pages
## rendered at twice their size and shown smoothly. Left click turns forward
## a page spread, right click back (the grapple's off meanwhile); only F puts
## it away (PlayerHand), and picking anything up does. You move as normal
## while reading. Your own view only.

## Its share of the screen's width (the user's: half), how far up from the
## bottom its lower edge sits (share of the screen's height), and the most of
## the screen's height it may take.
const SCREEN_SHARE := 0.5
const BOTTOM_GAP := 0.04
const MOST_HEIGHT := 0.88
const COVER := Color(0.16, 0.15, 0.14)
const COVER_EDGE := 10.0
const SPINE := 6.0
## Above the PS1 dither (its CanvasLayer is 5).
const LAYER := 7
## The pages rendered at this many times their size (sharp when big).
const SHARPNESS := 2

var _player: PlayerMovement
var _root: Control
var _cover: Panel
var _viewports: Array[SubViewport] = []
var _pages: Array[JournalPage] = []
var _shown: Array[TextureRect] = []
var _spread := 0
var _dirty := true
var _page_count := 0


func setup(player: PlayerMovement, _camera: Camera3D) -> void:
	_player = player
	layer = LAYER
	visible = false
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_cover = Panel.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COVER
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 10
	_cover.add_theme_stylebox_override("panel", style)
	_root.add_child(_cover)
	for i in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(JournalPage.SIZE) * SHARPNESS
		viewport.size_2d_override = Vector2i(JournalPage.SIZE)
		viewport.size_2d_override_stretch = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var page := JournalPage.new()
		viewport.add_child(page)
		_viewports.append(viewport)
		_pages.append(page)
		var shown := TextureRect.new()
		shown.texture = viewport.get_texture()
		shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shown.stretch_mode = TextureRect.STRETCH_SCALE
		shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cover.add_child(shown)
		_shown.append(shown)
	Network.fact_changed.connect(func(_name: StringName, _value: Variant) -> void: _dirty = true)


func _process(_delta: float) -> void:
	var reading := _player != null and _player.is_multiplayer_authority() and not _player.is_dead() \
			and not _player.bag_open and _player.hand.reading()
	if reading != visible:
		visible = reading
		_dirty = true
	if not reading:
		return
	_place()
	if _dirty:
		_refresh()


func _input(event: InputEvent) -> void:
	if not visible or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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


## Half the screen's width, its lower edge just off the bottom, centred.
func _place() -> void:
	var screen := _root.get_viewport_rect().size
	var page := Vector2(screen.x * SCREEN_SHARE * 0.5, 0.0)
	page.y = page.x * JournalPage.SIZE.y / JournalPage.SIZE.x
	if page.y > screen.y * MOST_HEIGHT:
		page *= screen.y * MOST_HEIGHT / page.y
	var book := Vector2(page.x * 2.0 + SPINE + COVER_EDGE * 2.0, page.y + COVER_EDGE * 2.0)
	_cover.size = book
	_cover.position = Vector2((screen.x - book.x) * 0.5, screen.y * (1.0 - BOTTOM_GAP) - book.y)
	for i in 2:
		_shown[i].size = page
		_shown[i].position = Vector2(COVER_EDGE + i * (page.x + SPINE), COVER_EDGE)
