class_name GrandmasHouse
extends Node3D

## Grandma's house in her yard (the user's, 2026-10-19), built from
## maps/grandmas_house.map (tools/make_grandmas_house.gd; edit the map in
## TrenchBroom, then Build its "Map" node).
## No loading screen: the HL2 way (Valve's areaportals). Everything inside --
## the rooms (func_detail "house_interior"), the locked doors, Grandma, the
## lamp -- is only there while the front door's open or someone's in the
## house; door shut and everyone out, it's all hidden and asleep. The walls,
## roof and windows (opaque) always show, so nothing's missed from outside.
## The rooms keep their collision while hidden (only their look goes).
## Each game decides for itself from where every player is (Rule 1:
## presentation; the doors are each game's own).
## The locked doors (targetname "house_<room>", "Locked.") open when a quest
## or a rare key fires their targetname (MapIO) -- later.

## How often it checks (seconds).
const CHECK_EVERY := 0.15
## The house in its own space, porch and roof included: "someone's in".
@export var bounds := AABB(Vector3(-5.3, -0.5, -6.6), Vector3(10.6, 11.0, 11.2))

var _front_door: MapDoor
## Shown only with the door open or someone in.
var _hidden_parts: Array[Node3D] = []
## Also asleep then (Grandma, the locked doors).
var _sleepers: Array[Node] = []
var _shown := true
var _check_left := 0.0


func _ready() -> void:
	add_to_group(&"grandmas_house") # (FleshTree's roots and the red weed find it)
	var map := get_node_or_null(^"Map")
	if map:
		for node in map.get_children():
			if node is MapDoor:
				# Read straight from the map: its own setup runs a frame later.
				if str((node as MapDoor).func_godot_properties.get("targetname", "")).is_empty():
					_front_door = node
				else:
					_hidden_parts.append(node)
					_sleepers.append(node)
			elif String(node.name).ends_with("house_interior"): # (func_godot: "entity_house_interior")
				_hidden_parts.append(node)
			elif node is Grandma:
				_hidden_parts.append(node)
				_sleepers.append(node)
	var lamp := get_node_or_null(^"Lamp") as Node3D
	if lamp:
		_hidden_parts.append(lamp)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_sit_on_ground()
	_show(_wanted())


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	var want := _wanted()
	if want != _shown:
		_show(want)


## The front door open (or swinging), or a player in the house.
func _wanted() -> bool:
	if _front_door and not _front_door.is_closed():
		return true
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player and bounds.has_point(to_local(player.global_position + Vector3.UP)):
			return true
	return false


func _show(on: bool) -> void:
	_shown = on
	for part in _hidden_parts:
		if is_instance_valid(part):
			part.visible = on
	for node in _sleepers:
		if is_instance_valid(node):
			node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Onto the yard's ground (the terrain under it, not the house itself).
func _sit_on_ground() -> void:
	var skip: Array[RID] = []
	for node in find_children("*", "CollisionObject3D", true, false):
		skip.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 200.0, global_position + Vector3.DOWN * 200.0, 1, skip)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit.position as Vector3).y - 0.05
