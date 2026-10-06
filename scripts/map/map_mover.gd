@tool
class_name MapMover
extends AnimatableBody3D

## The moving part shared by every interactive map piece -- doors, buttons
## and levers are all "a group of brushes that travels between a closed pose
## and an open pose", like Quake's own func_door/func_button
## (SUB_CalcMove in Quake 1, Move_Calc in Quake 2's g_func.c). Two kinds of
## motion:
##   SLIDE  - straight along a direction (Quake's "angle" key), by the
##            brushes' own size minus a "lip" -- a door slides until only
##            the lip still shows.
##   ROTATE - swings by some degrees around a hinge (Quake 2's
##            func_door_rotating, Half-Life's func_rot_button).
##
## The node is built by func_godot from the mapper's brushes; its settings
## arrive in func_godot_properties (typed in TrenchBroom's entity panel).
## AnimatableBody3D, so moving it pushes players out of the way.
##
## @tool only so func_godot can hand it its properties when a map is built
## in the editor (Build Map) and they get saved with the level -- nothing
## else runs in the editor.
##
## Rule 1 (co-op): the open/close decisions are gameplay and belong to the
## host; the motion itself is deterministic from those decisions, so a client
## could replay it from "opened at tick N" alone.

enum Motion { SLIDE, ROTATE }
## TrenchBroom "axis" choice -> the line a rotating piece swings around.
enum Axis { VERTICAL, EAST_WEST, NORTH_SOUTH }
## TrenchBroom "hinge" choice -> where on the brushes that line sits.
enum Hinge { ORIGIN, BOTTOM, TOP, WEST_OR_SOUTH, EAST_OR_NORTH }

## Every property the mapper set in TrenchBroom, filled in by func_godot when
## the map is built (and saved with the level when built in the editor).
@export var func_godot_properties: Dictionary = {}

## Seconds it stays open before going back by itself. -1 = stays open.
var wait: float = 3.0
## For find_broken_links() and messages; set by the subclass.
var target: String = ""

var _motion := Motion.SLIDE
var _closed_transform: Transform3D
var _slide_offset := Vector3.ZERO
var _pivot := Vector3.ZERO
var _axis := Vector3.UP
var _open_angle := 0.0
var _travel_time := 1.0
## 0 = closed, 1 = fully open, and where it's heading.
var _amount := 0.0
var _goal := 0.0
var _wait_left := -1.0
var _move_sound: SoundEvent
var _stop_sound: SoundEvent


func _ready() -> void:
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	sync_to_physics = true
	# Deferred: when a map is built while the game runs (Load Test Map),
	# func_godot hands over the properties only after the node is added.
	_setup.call_deferred()


## Subclasses read their properties here and call configure_slide() or
## configure_rotate().
func _setup() -> void:
	_closed_transform = transform


## A short name for messages and warnings, e.g. "lever".
func describe() -> String:
	return "map piece"


func prop(key: String, default: Variant) -> Variant:
	return func_godot_properties.get(key, default)


## Slides along `direction` until only `lip_units` of it still shows, at
## `speed_units` per second (TrenchBroom units, like Quake).
func configure_slide(direction: Vector3, lip_units: float, speed_units: float) -> void:
	_motion = Motion.SLIDE
	var size := local_bounds().size
	var depth := absf(direction.x) * size.x + absf(direction.y) * size.y + absf(direction.z) * size.z
	var distance := maxf(depth - MapIO.units_to_meters(lip_units), 0.0)
	_slide_offset = direction * distance
	_travel_time = distance / maxf(MapIO.units_to_meters(speed_units), 0.01)


## Swings `degrees` around a line set by `axis_choice` through the spot set by
## `hinge_choice`, at `degrees_per_second`. Hinge ORIGIN is this node's own
## origin: the middle of the mapper's origin brush if they drew one (func_
## godot's origin-brush support), otherwise the middle of the brushes.
func configure_rotate(axis_choice: int, hinge_choice: int, degrees: float, degrees_per_second: float) -> void:
	_motion = Motion.ROTATE
	var bounds := local_bounds()
	var center := bounds.get_center()
	var low := bounds.position
	var high := bounds.end
	var hinge_local := Vector3.ZERO
	# The long horizontal side decides which "ends" a hinge can be on:
	# TrenchBroom east-west is Godot Z, north-south is Godot X.
	var runs_east_west := bounds.size.z >= bounds.size.x
	match hinge_choice:
		Hinge.BOTTOM:
			hinge_local = Vector3(center.x, low.y, center.z)
		Hinge.TOP:
			hinge_local = Vector3(center.x, high.y, center.z)
		Hinge.WEST_OR_SOUTH:
			hinge_local = Vector3(center.x, center.y, low.z) if runs_east_west else Vector3(low.x, center.y, center.z)
		Hinge.EAST_OR_NORTH:
			hinge_local = Vector3(center.x, center.y, high.z) if runs_east_west else Vector3(high.x, center.y, center.z)
	_pivot = transform * hinge_local
	match axis_choice:
		Axis.EAST_WEST:
			_axis = Vector3.BACK # Godot +Z = TrenchBroom east
		Axis.NORTH_SOUTH:
			_axis = Vector3.RIGHT # Godot +X = TrenchBroom north
		_:
			_axis = Vector3.UP
	_open_angle = deg_to_rad(degrees)
	_travel_time = absf(degrees) / maxf(degrees_per_second, 1.0)


## The brushes' box in this node's own space, from its built mesh.
func local_bounds() -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for child in get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node and mesh_node.mesh:
			var box := mesh_node.transform * mesh_node.mesh.get_aabb()
			bounds = box if not has_bounds else bounds.merge(box)
			has_bounds = true
	return bounds


func set_sounds(move_sound: SoundEvent, stop_sound: SoundEvent) -> void:
	_move_sound = move_sound
	_stop_sound = stop_sound


func is_open() -> bool:
	return is_equal_approx(_amount, 1.0)


func is_closed() -> bool:
	return is_zero_approx(_amount)


## Heading toward open (1) or closed (0), even if not there yet.
func is_opening() -> bool:
	return _goal > 0.5


func is_moving() -> bool:
	return not is_equal_approx(_amount, _goal)


func open() -> void:
	_move_to(1.0)


func close() -> void:
	_move_to(0.0)


func _move_to(goal: float) -> void:
	_wait_left = -1.0
	if is_equal_approx(goal, _goal):
		return
	_goal = goal
	SoundPlayer.play_3d(_move_sound, global_position, get_tree().current_scene)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if is_moving():
		_amount = move_toward(_amount, _goal, delta / maxf(_travel_time, 0.001))
		_apply_amount()
		if not is_moving():
			_arrived()
	elif _wait_left > 0.0:
		_wait_left -= delta
		if _wait_left <= 0.0:
			if _can_close():
				close()
			else:
				_wait_left = 0.5 # someone's in the way -- try again shortly
	elif not _keep_processing():
		set_physics_process(false)


func _arrived() -> void:
	SoundPlayer.play_3d(_stop_sound, global_position, get_tree().current_scene)
	if is_open() and wait >= 0.0:
		_wait_left = maxf(wait, 0.001)
	_on_arrived(is_open())


## Hook for subclasses: fully open (true) or fully closed (false).
func _on_arrived(_now_open: bool) -> void:
	pass


## Hook for subclasses that need to keep checking things while idle (a door
## that opens when a player walks up).
func _keep_processing() -> bool:
	return false


## Won't swing shut on top of a player -- Quake doors reverse when blocked;
## this simply waits for them to step out first.
func _can_close() -> bool:
	return true


func _apply_amount() -> void:
	var eased := smoothstep(0.0, 1.0, _amount)
	if _motion == Motion.SLIDE:
		transform = Transform3D(_closed_transform.basis, _closed_transform.origin + _slide_offset * eased)
	else:
		var turn := Basis(_axis, _open_angle * eased)
		transform = Transform3D(turn * _closed_transform.basis, _pivot + turn * (_closed_transform.origin - _pivot))


## The pieces' closed-pose box in the parent's space, grown by `margin` --
## for "is a player standing in the doorway / near the door".
func closed_box(margin: float) -> AABB:
	var box := _closed_transform * local_bounds()
	return box.grow(margin)


## Living players whose position is inside `box`.
func players_in(box: AABB) -> Array[PlayerMovement]:
	var found: Array[PlayerMovement] = []
	var parent := get_parent() as Node3D
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null:
			continue
		var local := parent.to_local(player.global_position) if parent else player.global_position
		if box.has_point(local) or box.has_point(local + Vector3.UP * 1.0):
			found.append(player)
	return found
