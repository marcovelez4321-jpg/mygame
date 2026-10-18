class_name Bedroll
extends StaticBody3D

## A camp's bedroll (Camp): F to sleep (the user's: heals SLEEP_HEAL, uses
## SLEEP_HUNGER of the hunger meter; the screen fades out and back). While you
## sleep the Stalker comes on down your trail (Stalker.slept, the user's).

const SLEEP_HEAL := 50.0
const SLEEP_HUNGER := 0.25
const FADE := 1.2

var use_prompt := "Sleep"


func _ready() -> void:
	add_to_group(PlayerMovement.USABLE_GROUP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.3, Camp.BED_LENGTH)
	shape.shape = box
	shape.position = Vector3.UP * 0.15
	add_child(shape)


func can_use() -> bool:
	return true


func use_by(player: Node) -> void:
	var body := player as PlayerMovement
	if body == null or body.is_dead():
		return
	if not Network.is_online() or body.multiplayer.is_server():
		body.health.heal(SLEEP_HEAL)
		body.virus.hunger = maxf(body.virus.hunger - SLEEP_HUNGER, 0.0)
		var stalker := body.get_tree().get_first_node_in_group(&"stalker")
		if stalker:
			stalker.call(&"slept", body)
	if body.is_multiplayer_authority():
		_fade(body)


## The screen fades to black and back (your own).
func _fade(body: PlayerMovement) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	body.add_child(layer)
	var tween := layer.create_tween()
	tween.tween_property(black, "color:a", 1.0, FADE)
	tween.tween_interval(0.6)
	tween.tween_property(black, "color:a", 0.0, FADE)
	tween.tween_callback(layer.queue_free)