class_name InteractHighlight
extends Node

## Outlines things you can pick up or use -- weapons and ammo on the ground,
## keys, buttons, levers, Grandma -- so they stand out. The pause menu's
## Outlines setting (GameSettings.outline_mode) picks when:
##   - When looking at it: only the thing you're looking at.
##   - Always: everything, all the time.
##   - Off.
## A pickup joins GROUP in its _ready(); anything F can use (the player's
## USABLE_GROUP) counts too.
##
## Presentation only (Rule 1, co-op): each player's game outlines what that
## player is looking at; nothing here touches gameplay.

const GROUP := "highlightable"
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

## How far away a pickup can be and still light up when you look at it.
@export var look_range: float = 6.0
## How far off the middle of the screen (degrees) still counts as looking at
## a pickup -- forgiving, so a small grenade on the floor is easy to catch.
@export var look_angle_degrees: float = 7.0

@onready var _player := owner as PlayerMovement

var _material: ShaderMaterial
var _outlined: Array[Node] = []


func _ready() -> void:
	if not owner.is_multiplayer_authority():
		set_process(false)
		return
	_material = ShaderMaterial.new()
	_material.shader = OUTLINE_SHADER


func _process(_delta: float) -> void:
	var wanted: Array[Node] = []
	match GameSettings.outline_mode:
		GameSettings.OutlineMode.ALWAYS:
			wanted.assign(get_tree().get_nodes_in_group(GROUP))
			for usable in get_tree().get_nodes_in_group(PlayerMovement.USABLE_GROUP):
				if usable.call("can_use"):
					wanted.append(usable)
		GameSettings.OutlineMode.LOOKING:
			var target := _looked_at()
			if target:
				wanted.append(target)
	for node in _outlined:
		if is_instance_valid(node) and not wanted.has(node):
			_set_outline(node, false)
	for node in wanted:
		if not _outlined.has(node):
			_set_outline(node, true)
	_outlined = wanted


## What you're looking at: the button/lever/NPC under the crosshair (the same
## one F would use), otherwise the pickup closest to the middle of the
## screen within look_range and look_angle_degrees that no wall hides.
func _looked_at() -> Node:
	if _player.usable_in_view:
		return _player.usable_in_view
	var eye := _player.camera.global_position
	var forward := -_player.camera.global_basis.z
	var min_dot := cos(deg_to_rad(look_angle_degrees))
	var best: Node3D = null
	var best_dot := min_dot
	for node in get_tree().get_nodes_in_group(GROUP):
		var pickup := node as Node3D
		if pickup == null:
			continue
		var to_pickup := pickup.global_position - eye
		var distance := to_pickup.length()
		if distance > look_range or distance < 0.01:
			continue
		var dot := forward.dot(to_pickup / distance)
		if dot > best_dot and _can_see(eye, pickup):
			best = pickup
			best_dot = dot
	return best


func _can_see(eye: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye, target.global_position)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func _set_outline(node: Node, on: bool) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _material if on else null
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = _material if on else null
