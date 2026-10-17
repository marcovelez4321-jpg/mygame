class_name SecretButton
extends StaticBody3D

## A secret door's button (the user's, 2026-10-17; StackBuilder puts it within
## 40 m of its door): a small wall button, a light switch, a call button, a
## valve or a lever -- one of them, at random -- set into a wall. F presses
## it (it sinks in, or the lever throws) and its SecretDoor swings open.
## Rule 1 (co-op): the host opens the door (SecretDoor tells everyone).

const MEGA := "res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/"
## [path, how big it is (its longest side, m)].
const MODELS := [
	[MEGA + "Electronics & Misc/button_12.glb", 0.25],
	[MEGA + "Electronics & Misc/elevator_call_button_1.glb", 0.3],
	[MEGA + "Electronics & Misc/elevator_buttons_1.glb", 0.4],
	[MEGA + "Electronics & Misc/light_switch_1.glb", 0.15],
	[MEGA + "Electronics & Misc/light_switch_1_1.glb", 0.15],
	[MEGA + "Large Props/pipe_valve_holder_large_1.glb", 0.6],
	["res://New assets/PSX_Traps/Assets/Lever.fbx", 0.6],
]

## What pressing it sounds like (the user's to set: the SoundEvent files, or
## files named button_press_01.. / lever_pull_01.. in audio/sfx/map).
const PRESS_SOUND := preload("res://audio/events/map/button_press.tres")
const PULL_SOUND := preload("res://audio/events/map/lever_pull.tres")
## The words at the bottom of your screen when it opens its door (the user's).
const OPENED_TEXT := "Something opened."

@export var door_path: NodePath
@export var model_index := 0

var use_prompt := "Press"
var _pressed := false
var _model: Node3D


func _ready() -> void:
	add_to_group(PlayerMovement.USABLE_GROUP)
	var pick: Array = MODELS[model_index % MODELS.size()]
	var size: float = pick[1]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size, 0.3), maxf(size, 0.3), 0.3)
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, 0.15)
	add_child(shape)
	if (pick[0] as String).ends_with("Lever.fbx"):
		use_prompt = "Pull"
	if ResourceLoader.exists(pick[0]):
		var model := (load(pick[0]) as PackedScene).instantiate() as Node3D
		var holder := Node3D.new()
		holder.add_child(model)
		var bounds := BackpackView._bounds(holder)
		var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var fit := size / maxf(longest, 0.001)
		holder.scale = Vector3.ONE * fit
		# Its back flat on the wall (+Z is out of the wall).
		holder.position = -Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z) * fit
		_model = holder
		add_child(holder)


func can_use() -> bool:
	return not _pressed


func use_by(player: Node) -> void:
	if _pressed:
		return
	_pressed = true
	remove_from_group(PlayerMovement.USABLE_GROUP)
	SoundPlayer.play_3d(PULL_SOUND if use_prompt == "Pull" else PRESS_SOUND, global_position, get_tree().current_scene)
	if player is Node and player.is_multiplayer_authority():
		MapIO.show_message(get_tree(), OPENED_TEXT)
	if _model:
		var tween := create_tween()
		if use_prompt == "Pull":
			tween.tween_property(_model, "rotation:x", -0.9, 0.25)
		else:
			tween.tween_property(_model, "position:z", _model.position.z - 0.04, 0.1)
	if Network.is_online() and not multiplayer.is_server():
		return # the host opens it
	var door := get_node_or_null(door_path) as SecretDoor
	if door:
		door.open()