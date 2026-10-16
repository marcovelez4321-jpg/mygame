class_name CampBuilder
extends Node

## Placing a camp (the user's, 2026-10-16): with the camp kit in your right
## hand (PlayerHand) a see-through camp (Camp.make_look()) follows your aim --
## green where it fits, red where it doesn't (too steep, too bumpy, something
## in the way). The mouse wheel turns it, left click builds it there, right
## click puts the kit back in the bag. Its tent is one of the two at random,
## picked each time the kit comes out.
## Rule 1 (co-op): the ghost and the clicks are your own view's; the build
## is the host's (_net_build), which checks you still hold the kit.

## How far off you can put it down.
const REACH := 8.0
## The room it needs (its own space: the tent, the bedroll, the fire).
const FOOTPRINT := AABB(Vector3(-1.4, 0.0, -1.8), Vector3(4.4, 2.0, 6.7))
## Steepest ground it goes on, and the most the ground under its corners can
## rise or drop from its middle.
const MAX_SLOPE_DEGREES := 25.0
const MAX_STEP := 0.7
## One click of the mouse wheel turns it this much.
const TURN_STEP := 15.0

var _player: PlayerMovement
var _ghost: Node3D
var _variant := 0
var _turn := 0.0
var _place := Transform3D()
var _valid := false
var _shown_valid := true

static var _green: StandardMaterial3D
static var _red: StandardMaterial3D


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	set_process(_player.is_multiplayer_authority())
	set_process_unhandled_input(_player.is_multiplayer_authority())


## The kit's out to place (your own view).
func is_placing() -> bool:
	var hand := _player.hand
	return _player.is_multiplayer_authority() and not _player.is_dead() and not _player.bag_open \
			and hand != null and hand.is_holding() and int(hand.data.get("kind", -1)) == Backpack.Kind.CAMP_KIT


func _process(_delta: float) -> void:
	if not is_placing():
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		return
	if _ghost == null:
		_variant = randi() % Camp.TENTS.size()
		_turn = 0.0
		_ghost = Camp.make_look(_variant)
		_ghost.top_level = true
		_player.add_child(_ghost)
		_shown_valid = not _valid
	_valid = _find_place()
	_ghost.global_transform = _place
	if _valid != _shown_valid:
		_shown_valid = _valid
		var look := _ghost_material(_valid)
		for node in _ghost.find_children("*", "GeometryInstance3D", true, false):
			var mesh := node as GeometryInstance3D
			mesh.material_override = look
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.is_pressed() or not is_placing() \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	match (event as InputEventMouseButton).button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_turn += TURN_STEP
		MOUSE_BUTTON_WHEEL_DOWN:
			_turn -= TURN_STEP
		MOUSE_BUTTON_LEFT:
			if _valid:
				_ask_build(_place, _variant)
		MOUSE_BUTTON_RIGHT:
			_ask_put_away()
		_:
			return
	get_viewport().set_input_as_handled()


## Where your aim puts it, facing you (its fire your way), turned by the
## wheel; whether it fits there.
func _find_place() -> bool:
	var head := _player.head
	var from := head.global_position
	var forward := -head.global_basis.z
	var space := _player.get_world_3d().direct_space_state
	var hit := _ray(space, from, from + forward * REACH)
	var spot: Vector3 = hit.position if not hit.is_empty() else from + forward * REACH
	var ground := _ray(space, spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 6.0)
	if not ground.is_empty():
		spot = ground.position
	var toward := _player.global_position - spot
	var yaw := atan2(toward.x, toward.z) + deg_to_rad(_turn)
	_place = Transform3D(Basis(Vector3.UP, yaw), spot)
	if ground.is_empty() or (ground.normal as Vector3).angle_to(Vector3.UP) > deg_to_rad(MAX_SLOPE_DEGREES):
		return false
	var low := FOOTPRINT.position
	var high := FOOTPRINT.end
	for corner in [Vector3(low.x, 0, low.z), Vector3(high.x, 0, low.z), Vector3(low.x, 0, high.z), Vector3(high.x, 0, high.z)]:
		var at: Vector3 = _place * corner
		var under := _ray(space, at + Vector3.UP * (MAX_STEP + 1.0), at + Vector3.DOWN * (MAX_STEP + 1.0))
		if under.is_empty() or absf((under.position as Vector3).y - spot.y) > MAX_STEP:
			return false
	# Nothing in the way above the bumps it's allowed.
	var box := BoxShape3D.new()
	box.size = Vector3(FOOTPRINT.size.x, FOOTPRINT.size.y - MAX_STEP, FOOTPRINT.size.z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = _place * Transform3D(Basis.IDENTITY, FOOTPRINT.get_center() + Vector3.UP * MAX_STEP * 0.5)
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, _player.collision_mask, [_player.get_rid()])
	return space.intersect_ray(query)


static func _ghost_material(valid: bool) -> StandardMaterial3D:
	if _green == null:
		_green = StandardMaterial3D.new()
		_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_green.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
		_red = _green.duplicate() as StandardMaterial3D
		_red.albedo_color = Color(1.0, 0.25, 0.2, 0.35)
	return _green if valid else _red


# ---- Building (the host's) ----------------------------------------------------------

func _ask_build(place: Transform3D, variant: int) -> void:
	if not Network.is_online() or multiplayer.is_server():
		_build(place, variant)
	else:
		_net_build.rpc_id(1, place, variant)


@rpc("any_peer", "call_remote", "reliable")
func _net_build(place: Transform3D, variant: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == _player.get_multiplayer_authority():
		_build(place, variant)


func _build(place: Transform3D, variant: int) -> void:
	var hand := _player.hand
	if _player.is_dead() or not hand.is_holding() or int(hand.data.get("kind", -1)) != Backpack.Kind.CAMP_KIT \
			or place.origin.distance_to(_player.global_position) > REACH + 4.0:
		return
	hand.use_up()
	Camp.build(_player.get_tree().current_scene, place, variant)


func _ask_put_away() -> void:
	if not Network.is_online() or multiplayer.is_server():
		_player.hand.put_away()
	else:
		_net_put_away.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _net_put_away() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == _player.get_multiplayer_authority():
		_player.hand.put_away()