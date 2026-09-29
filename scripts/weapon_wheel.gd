extends Control

## Radial weapon wheel. Hold middle mouse to open it; while it's open, mouse
## movement moves a cursor around the wheel instead of turning the camera.
## Let go over a slice to pick that weapon.
##
## Local presentation only (Rule 1, co-op): the wheel just reports which
## inventory slot you picked. The choice then travels as part of the input
## packet (PlayerInput.select_weapon), so the host decides what's equipped.

signal weapon_chosen(index: int)

const RADIUS := 170.0
## The cursor must leave this small centre circle to count as picking a slice,
## so a quick tap of middle mouse doesn't change weapons by accident.
const DEAD_ZONE := 40.0
const SEGMENTS := 24 # smoothness of each slice's curved edge
const COLOR_BACK := Color(0.0, 0.0, 0.0, 0.55)
const COLOR_SELECTED := Color(1.0, 0.8, 0.2, 0.5)
const COLOR_LINE := Color(1.0, 1.0, 1.0, 0.25)

var _weapons: Array[WeaponData] = []
var _equipped: int = 0
var _is_open: bool = false
var _cursor: Vector2 = Vector2.ZERO # offset from the centre of the wheel


func _ready() -> void:
	visible = false


## Called by the HUD whenever the player's weapons change.
func set_weapons(weapons: Array[WeaponData], equipped_index: int) -> void:
	_weapons = weapons
	_equipped = equipped_index
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _weapons.is_empty():
				_open_wheel()
		elif _is_open:
			_close_wheel()
	elif event is InputEventMouseMotion and _is_open:
		_cursor = (_cursor + event.relative).limit_length(RADIUS)
		queue_redraw()
		# Stop the player's camera from also receiving this movement.
		get_viewport().set_input_as_handled()


func _open_wheel() -> void:
	_is_open = true
	_cursor = Vector2.ZERO
	visible = true
	queue_redraw()


func _close_wheel() -> void:
	var index := _selected_index()
	_is_open = false
	visible = false
	if index >= 0 and index != _equipped:
		weapon_chosen.emit(index)


## Which slice the cursor is over, or -1 if it's still in the centre.
func _selected_index() -> int:
	if _cursor.length() < DEAD_ZONE or _weapons.is_empty():
		return -1
	# Slice 0 sits at the top and they run clockwise. Vector2.angle() is 0 at
	# "right", so shift by a quarter turn to make 0 mean "up".
	var angle := fposmod(_cursor.angle() + PI / 2.0, TAU)
	var slice := TAU / _weapons.size()
	return int(round(angle / slice)) % _weapons.size()


func _draw() -> void:
	if not _is_open or _weapons.is_empty():
		return
	var center := size / 2.0
	var count := _weapons.size()
	var slice := TAU / count
	var selected := _selected_index()

	draw_circle(center, RADIUS, COLOR_BACK)
	for i in count:
		var middle := i * slice - PI / 2.0
		if i == selected:
			_draw_slice(center, middle - slice / 2.0, middle + slice / 2.0, COLOR_SELECTED)
		var edge := Vector2.from_angle(middle - slice / 2.0)
		draw_line(center + edge * DEAD_ZONE, center + edge * RADIUS, COLOR_LINE, 2.0)
		_draw_label(_weapons[i], center + Vector2.from_angle(middle) * RADIUS * 0.65, i == _equipped)

	draw_arc(center, RADIUS, 0.0, TAU, 64, COLOR_LINE, 2.0)
	draw_arc(center, DEAD_ZONE, 0.0, TAU, 32, COLOR_LINE, 2.0)
	draw_circle(center + _cursor, 6.0, Color.WHITE)


func _draw_slice(center: Vector2, from_angle: float, to_angle: float, color: Color) -> void:
	var points := PackedVector2Array([center])
	for step in SEGMENTS + 1:
		var angle := lerpf(from_angle, to_angle, float(step) / SEGMENTS)
		points.append(center + Vector2.from_angle(angle) * RADIUS)
	draw_colored_polygon(points, color)


## The weapon's icon (if it has one) and name. The equipped weapon is brighter
## and has a ring around it.
func _draw_label(weapon: WeaponData, position: Vector2, equipped: bool) -> void:
	var tint := Color.WHITE if equipped else Color(1.0, 1.0, 1.0, 0.65)
	if weapon.icon:
		draw_texture_rect(weapon.icon, Rect2(position - Vector2(32.0, 44.0), Vector2(64.0, 64.0)), false, tint)
	if equipped:
		draw_arc(position + Vector2(0.0, 8.0), 50.0, 0.0, TAU, 32, tint, 2.0)
	draw_string(ThemeDB.fallback_font, position + Vector2(-70.0, 34.0), weapon.weapon_name,
			HORIZONTAL_ALIGNMENT_CENTER, 140.0, 18, tint)