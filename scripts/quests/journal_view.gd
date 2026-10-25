class_name JournalView
extends Node3D

## The journal held up open in front of you (the user's, 2026-10-25): double-
## click the notebook in the backpack, close the bag, and it's up -- held
## close (SCREEN_SHARE of the screen's width), lower middle, two pages
## (JournalPage) side by side in its cover, in the world's own PS1 look.
## Left click turns forward a page spread, right click back (the grapple's
## off meanwhile); only F puts it away, and picking anything up does
## (PlayerHand). You move as normal while reading. Your own view only: on
## your camera, drawn over the world so it never sinks into a wall.

## How far in front of your eye it's held (m), and its share of the screen's
## width (the user's: half, then brought closer -- 65%).
const DISTANCE := 0.4
const SCREEN_SHARE := 0.65
## Its middle this far below the screen's (share of the screen's height),
## and tipped back toward you (degrees); each page tipped up from the spine.
const DROP := 0.1 # (held bigger: raised so its foot stays on screen)
const TILT := 14.0
const PAGE_ANGLE := 6.0
const COVER := Color(0.16, 0.15, 0.14)

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


## Sized to half the screen's width at DISTANCE, lower middle, tipped to you.
func _place() -> void:
	var screen := get_viewport().get_visible_rect().size
	var half_height := DISTANCE * tan(deg_to_rad(_camera.fov) * 0.5)
	var half_width := half_height * screen.x / maxf(screen.y, 1.0)
	var page_width := half_width * 2.0 * SCREEN_SHARE * 0.5
	var page_height := page_width * JournalPage.SIZE.y / JournalPage.SIZE.x
	transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(TILT)), Vector3(0.0, -half_height * 2.0 * DROP, -DISTANCE))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		(_quads[i].mesh as QuadMesh).size = Vector2(page_width, page_height)
		_quads[i].transform = Transform3D(Basis(Vector3.UP, -side * deg_to_rad(PAGE_ANGLE)),
				Vector3(side * page_width * 0.5 * cos(deg_to_rad(PAGE_ANGLE)), 0.0, page_width * 0.5 * sin(deg_to_rad(PAGE_ANGLE))))
	(_cover.mesh as BoxMesh).size = Vector3(page_width * 2.08, page_height * 1.04, 0.004)
	_cover.position = Vector3(0.0, 0.0, -0.003)
