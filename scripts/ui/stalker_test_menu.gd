class_name StalkerTestMenu
extends CanvasLayer

## F9: a list of every Stalker event, one click to make it happen on you now
## (the user's, 2026-10-21: for testing and tuning -- in every build, so it's
## there with friends too; take it out before release). The host's (it runs
## the Stalker); a client's says so. The HUD makes one.

## Events past its stunts (Stalker.test_event).
const EXTRA := [["silence", "Wrong silence"], ["breathing", "Breathing (it waits close)"], ["camp", "Camp visit"], ["eat", "Eat (nearest meat or body)"],
		["sign", "Small sign (random)"], ["tracks", "Sign: tracks across"], ["kill", "Sign: a kill ahead"], ["peak", "Big moment now"], ["home", "Home in its lair"],
		["comeback", "Comeback (session start)"], ["forget", "Forget me (wipe its memory)"],
		["forget_world", "Forget the world (quest facts)"], ["ossuary_here", "Ossuary: walk past me"], ["ossuary_rest", "Ossuary: rest now"],
		["consumed_here", "A Consumed, at me"], ["bells_wake", "Wake the Bell-wraiths"]]

var _panel: PanelContainer
var _result: Label
## Its brain right now (the director, its fear, what it's doing).
var _brain: Label
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
	_brain = Label.new()
	_brain.add_theme_font_size_override("font_size", 13)
	box.add_child(_brain)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for stunt: String in Stalker.Stunt.keys():
		_add_button(grid, StringName(stunt.to_lower()), stunt.capitalize())
	for extra: Array in EXTRA:
		_add_button(grid, StringName(extra[0]), extra[1])
	# The quest web's (QuestTests).
	for test: Array in QuestTests.BUTTONS:
		_add_button(grid, StringName(test[0]), test[1])
	_result = Label.new()
	_result.text = ""
	box.add_child(_result)


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var stalker := get_tree().get_first_node_in_group(&"stalker")
	_brain.text = str(stalker.call(&"debug_text")) if stalker and (not Network.is_online() or multiplayer.is_server()) else "(no Stalker here yet)"


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
	if String(event).begins_with("q_"):
		var me := PlayerMovement.local_player(tree)
		_result.text = QuestTests.run(event, me) if me else "No player here."
		return
	if event == &"consumed_here":
		var me := PlayerMovement.local_player(tree)
		var one := Consumed.new()
		one.look = randi()
		one.set_meta(&"free", true)
		tree.current_scene.add_child(one)
		one.global_position = me.global_position - me.head.global_basis.z * 30.0 + Vector3.UP * 6.0
		_result.text = "A Consumed, 30 m in front of you"
		return
	if event == &"bells_wake":
		var count := tree.get_nodes_in_group(&"bell_wraiths").size()
		for node in tree.get_nodes_in_group(&"bell_wraiths"):
			(node as BellWraith).wake()
		_result.text = "%d Bell-wraiths awake (10 s)" % count
		return
	if String(event).begins_with("ossuary_"):
		Ossuary.ensure(tree)
		var walker := tree.get_first_node_in_group(&"ossuary") as Ossuary
		var me := PlayerMovement.local_player(tree)
		_result.text = walker.test(StringName(String(event).trim_prefix("ossuary_")), me) if walker and me else "No Ossuary here (no terrain?)"
		return
	Stalker.ensure(tree)
	var stalker := tree.get_first_node_in_group(&"stalker")
	var player := PlayerMovement.local_player(tree)
	if stalker == null or player == null:
		_result.text = "No Stalker or player here."
		return
	_result.text = str(stalker.call(&"test_event", event, player))
