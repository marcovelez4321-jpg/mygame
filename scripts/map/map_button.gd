@tool
class_name MapButton
extends MapMover

## func_button (pushes in) and func_lever (swings on a hinge). Both are used
## ONLY by walking up and pressing F (PlayerMovement looks for the
## "map_usable" group) -- not by touching or shooting them like Quake's
## buttons. The press-a-key idea is Half-Life's +use; the lever is its
## func_rot_button.
##
## Like Quake's func_button (g_func.c), it fires its target once it has
## finished moving -- the press lands, then the door goes.
##   wait >= 0: springs back after `wait` seconds and can be used again.
##   wait = -1: a button stays pushed in for good; a lever stays pulled, and
##              pulling it again swings it back and fires its target again
##              (so a lever toggles a door open and shut).

const USABLE_GROUP := "map_usable"

const PRESS_SOUND := preload("res://audio/events/map/button_press.tres")
const LEVER_SOUND := preload("res://audio/events/map/lever_pull.tres")

## Shown under the crosshair while you look at it: "[F] Press".
var use_prompt: String = "Press"
var message: String = ""
var _is_lever := false
## Who pressed it, passed on to whatever it fires.
var _activator: Node


func describe() -> String:
	return "lever" if _is_lever else "button"


func _setup() -> void:
	super._setup()
	_is_lever = str(prop("classname", "")) == "func_lever"
	target = str(prop("target", ""))
	message = str(prop("message", ""))
	MapIO.register_target(self, target)
	add_to_group(USABLE_GROUP)
	if _is_lever:
		use_prompt = "Pull"
		wait = float(prop("wait", -1.0))
		set_sounds(LEVER_SOUND, null)
		configure_rotate(int(prop("axis", Axis.EAST_WEST)), int(prop("hinge", Hinge.BOTTOM)),
				float(prop("distance", 60.0)), float(prop("speed", 180.0)))
	else:
		wait = float(prop("wait", 1.0))
		set_sounds(PRESS_SOUND, null)
		configure_slide(MapIO.angle_to_direction(float(prop("angle", 0.0))),
				float(prop("lip", 4.0)), float(prop("speed", 40.0)))


## Whether pressing F right now would do anything -- the HUD only shows
## the prompt when it would.
func can_use() -> bool:
	if is_moving():
		return false
	if is_closed():
		return true
	return _is_lever and wait < 0.0 # a stay-put lever can be pulled back


## Called by PlayerMovement when its player presses F on this.
func use_by(player: Node) -> void:
	if not can_use():
		return
	_activator = player
	if is_closed():
		open()
	else:
		close()


## The press or pull has landed: fire the target. A springing-back piece
## only fires on the way in, not when it returns.
func _on_arrived(now_open: bool) -> void:
	if now_open or (_is_lever and wait < 0.0):
		MapIO.fire_targets(self, target, _activator)
		MapIO.show_message(get_tree(), message)
