class_name StalkerTestMenu
extends CanvasLayer

## F9: a list of every Stalker event, one click to make it happen on you now
## (the user's, 2026-10-21: for testing and tuning -- in every build, so it's
## there with friends too; take it out before release). The host's (it runs
## the Stalker); a client's says so. The HUD makes one.

## Events past its stunts (Stalker.test_event).
const EXTRA := [["silence", "Wrong silence"], ["breathing", "Breathing (it waits close)"]]

var _panel: PanelContainer
var _result: Label
var _was_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 24)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Stalker events (F9 to close)"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for stunt: String in Stalker.Stunt.keys():
		_add_button(grid, StringName(stunt.to_lower()), stunt.capitalize())
	for extra: Array in EXTRA:
		_add_button(grid, StringName(extra[0]), extra[1])
	_result = Label.new()
	_result.text = ""
	box.add_child(_result)


func _add_button(parent: Node, event: StringName, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_trigger.bind(event))
	parent.add_child(button)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F9:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_was_mouse = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_result.text = "Host only: the host runs the Stalker." if Network.is_online() and not multiplayer.is_server() else ""
		else:
			Input.mouse_mode = _was_mouse
		get_viewport().set_input_as_handled()


func _trigger(event: StringName) -> void:
	if Network.is_online() and not multiplayer.is_server():
		_result.text = "Host only: the host runs the Stalker."
		return
	var tree := get_tree()
	Stalker.ensure(tree)
	var stalker := tree.get_first_node_in_group(&"stalker")
	var player := PlayerMovement.local_player(tree)
	if stalker == null or player == null:
		_result.text = "No Stalker or player here."
		return
	_result.text = str(stalker.call(&"test_event", event, player))
