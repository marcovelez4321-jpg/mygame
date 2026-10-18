class_name WorldWind
extends RefCounted

## The wind high up, everywhere (the user's, 2026-10-17: universal, the
## procedural Stacks' own): out in the open air, barely there at the cloud
## deck and only getting stronger all the way to the very top (the user's,
## 2026-10-18) -- easing in (strength()), to SPEED by the top, gusting to
## GUST -- a prevailing wind wandering slowly round. None indoors (a
## megastructure's halls and rooms: HallEcho.inside()). PlayerMovement pulls
## you along it while you're in the air.
## Where it starts and tops out come from the level: its CloudDeck's height,
## and the top of its tallest megastructure (FROM / TOP without them).

const FROM := 4000.0
const TOP := 12000.0
const SPEED := 4.0
const GUST := 7.0

static var _scene_id := 0
static var _from := FROM
static var _top := TOP
static var _top_found := false


## 0 at the cloud deck (and below) to 1 at the very top, easing in: barely
## anything low down, the most of it near the top.
static func strength(y: float) -> float:
	_heights()
	var high := clampf(inverse_lerp(_from, _top, y), 0.0, 1.0)
	return high * high


static func at(point: Vector3) -> Vector3:
	var high := strength(point.y)
	if high <= 0.0 or HallEcho.inside(point):
		return Vector3.ZERO
	var t := Time.get_ticks_msec() * 0.001
	var gust := maxf(sin(t * 0.37) * 0.6 + sin(t * 1.13 + 1.7) * 0.4, 0.0) # 0..1, comes and goes
	var way := Vector3.RIGHT.rotated(Vector3.UP, 0.6 + sin(t * 0.05) * 0.4)
	return way * lerpf(SPEED, GUST, gust) * high


## This level's cloud deck and its tallest top (found once a level; the top
## looked for till the megastructures are in).
static func _heights() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene := tree.current_scene if tree else null
	if scene == null:
		return
	if scene.get_instance_id() != _scene_id:
		_scene_id = scene.get_instance_id()
		var deck := scene.find_child("CloudDeck", true, false)
		_from = float(deck.get("height")) if deck and deck.get("height") != null else FROM
		_top = TOP
		_top_found = false
	if _top_found:
		return
	var top := -INF
	for place in HallEcho.places:
		if not is_instance_valid(place):
			continue
		var columns: Variant = place.get("nest_columns")
		if columns is PackedVector3Array:
			for column: Vector3 in columns:
				top = maxf(top, (place as Node3D).global_position.y + column.y)
	if top > _from + 100.0:
		_top = top
		_top_found = true