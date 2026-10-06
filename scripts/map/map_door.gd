@tool
class_name MapDoor
extends MapMover

## func_door (slides) and func_door_rotating (swings on a hinge), the Quake 2
## way (g_func.c):
##   - No targetname: opens by itself when a player walks up (Quake spawns an
##     invisible "touch field" around the door for this), closes after wait.
##   - With a targetname: only a button or lever (anything whose target
##     names it) opens it. Walking up just shows its message, if it has one.
##   - key: locked until the player carries that key (Quake 1's silver/gold
##     key doors). The key isn't used up, so one key can open several doors.

## How far from the closed door a player has to be for it to open by itself
## -- Quake 1's touch field reaches 60 units past the door (doors.qc).
const TOUCH_RANGE_UNITS := 60.0
## Seconds between repeats of "You need the gold key" while you stand there.
const MESSAGE_COOLDOWN := 2.0
## wait's default in TrenchBroom: 3 seconds for a door that opens by itself,
## stays open for one a button or lever opens -- so a lever-and-door pair
## works without the mapper touching wait.
const WAIT_AUTO := -2.0

const MOVE_SOUND := preload("res://audio/events/map/door_move.tres")
const STOP_SOUND := preload("res://audio/events/map/door_stop.tres")
const LOCKED_SOUND := preload("res://audio/events/map/door_locked.tres")

var targetname: String = ""
## "" = not locked, otherwise the key's name (KeyPickup.KEY_NAMES).
var key_name: String = ""
var message: String = ""
var _unlocked := false
var _message_cooldown := 0.0


func describe() -> String:
	return "rotating door" if _is_rotating() else "door"


func _setup() -> void:
	super._setup()
	targetname = str(prop("targetname", ""))
	message = str(prop("message", ""))
	var key_index := int(prop("key", 0))
	key_name = KeyPickup.KEY_NAMES[key_index - 1] if key_index > 0 and key_index <= KeyPickup.KEY_NAMES.size() else ""
	wait = float(prop("wait", WAIT_AUTO))
	if is_equal_approx(wait, WAIT_AUTO):
		wait = -1.0 if not targetname.is_empty() else 3.0
	MapIO.register_targetname(self, targetname)
	set_sounds(MOVE_SOUND, STOP_SOUND)

	if _is_rotating():
		configure_rotate(int(prop("axis", Axis.VERTICAL)), int(prop("hinge", Hinge.ORIGIN)),
				float(prop("distance", 90.0)), float(prop("speed", 100.0)))
	else:
		configure_slide(MapIO.angle_to_direction(float(prop("angle", -1.0))),
				float(prop("lip", 8.0)), float(prop("speed", 100.0)))
	# Watches for players walking up -- both to open, and to show a locked
	# door's or a remote-opened door's message.
	set_physics_process(true)


func _is_rotating() -> bool:
	return str(prop("classname", "")) == "func_door_rotating"


## Fired by a button or lever. A door that stays open (wait -1) toggles, so
## pulling a lever back closes it again; otherwise it just opens.
func use(_activator: Node) -> void:
	if is_opening() and wait < 0.0:
		close()
	else:
		open()


func _keep_processing() -> bool:
	return true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_message_cooldown = maxf(_message_cooldown - delta, 0.0)
	if is_opening():
		return
	var nearby := players_in(closed_box(MapIO.units_to_meters(TOUCH_RANGE_UNITS)))
	if nearby.is_empty():
		return
	if not targetname.is_empty():
		_say(message) # opened from somewhere else -- the message can hint where
		return
	if not key_name.is_empty() and not _unlocked:
		for player in nearby:
			if player.has_key(key_name):
				_unlocked = true
				break
		if not _unlocked:
			if _message_cooldown <= 0.0:
				SoundPlayer.play_3d(LOCKED_SOUND, global_position, get_tree().current_scene)
			_say(message if not message.is_empty() else "You need the %s key" % key_name)
			return
	open()


## Doesn't close on someone standing in the doorway.
func _can_close() -> bool:
	return players_in(closed_box(0.3)).is_empty()


func _say(text: String) -> void:
	if text.is_empty() or _message_cooldown > 0.0:
		return
	_message_cooldown = MESSAGE_COOLDOWN
	MapIO.show_message(get_tree(), text)
