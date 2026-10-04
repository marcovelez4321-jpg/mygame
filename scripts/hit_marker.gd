@tool
class_name HitMarker
extends Control

## The hit marker: four lines around the crosshair that flash on every
## confirmed hit -- white for a normal hit, red for a headshot or artery hit,
## so you know at a glance you landed the shot that matters. A kill pops it a
## little bigger. Presentation only (Rule 1): driven by WeaponController's
## hit_confirmed on each player's own HUD.
##
## Everything about how it looks is an export on HUD > HitMarker. Tick
## preview_in_editor to see it in the 2D view while you tune it.

@export_group("Colors")
@export var normal_color: Color = Color(1.0, 1.0, 1.0)
## Headshots and artery hits.
@export var critical_color: Color = Color(1.0, 0.1, 0.1)

@export_group("Shape")
## Pixels from the middle of the marker to where each line starts.
@export var gap: float = 4.0
@export var length: float = 10.0
@export var thickness: float = 2.0
## 0 = lines point up/down/left/right (Quake 2 style). 45 = diagonal X
## (modern shooter style). Anything in between works too.
@export_range(0.0, 90.0, 1.0) var angle_degrees: float = 0.0
## Moves the whole marker away from the center of the screen, in pixels.
@export var offset: Vector2 = Vector2.ZERO

@export_group("Timing")
## Seconds at full brightness before fading.
@export var hold_time: float = 0.05
@export var fade_time: float = 0.15
## Size multiplier when the hit was a kill.
@export var kill_scale: float = 1.4

@export_group("Editor")
@export var preview_in_editor: bool = false
@export var preview_critical: bool = false

var _alpha: float = 0.0:
	set(value):
		_alpha = value
		queue_redraw()
var _critical: bool = false
var _scale: float = 1.0
var _tween: Tween


## Flashes the marker. `critical` = headshot or artery hit.
func show_hit(critical: bool, killed: bool) -> void:
	_critical = critical
	_scale = kill_scale if killed else 1.0
	if _tween:
		_tween.kill()
	_alpha = 1.0
	_tween = create_tween()
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "_alpha", 0.0, fade_time)


func _process(_delta: float) -> void:
	# Editor only: redraw every frame so Inspector tweaks show up immediately.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	var alpha := _alpha
	var critical := _critical
	var size_scale := _scale
	if Engine.is_editor_hint():
		if not preview_in_editor:
			return
		alpha = 1.0
		critical = preview_critical
		size_scale = 1.0
	if alpha <= 0.0:
		return

	var color := critical_color if critical else normal_color
	color.a *= alpha
	for i in 4:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_degrees + 90.0 * i))
		var from := offset + dir * gap * size_scale
		var to := offset + dir * (gap + length) * size_scale
		draw_line(from, to, color, thickness) # no antialiasing: crisp pixels for the PS1 look
