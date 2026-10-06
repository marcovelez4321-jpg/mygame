class_name DialogueBox
extends CanvasLayer

## A Fallout-style conversation box: who's talking and what they say on top,
## your numbered replies underneath. Click a reply or press its number;
## Escape backs out. Reusable by any NPC -- Grandma is the first.
##
##   var box := DialogueBox.open(get_tree())
##   var pick := await box.ask("Grandma", "There's my baby.", ["Let's do a mission.", "Just saying hi."])
##   # pick = 0, 1, ... or -1 if they pressed Escape
##   box.close()
##
## While it's open your character can't move, look or shoot, and the mouse
## is free (PlayerMovement.controls_locked).
## Rule 1 (co-op): purely local UI. What you pick is what gets sent to the
## host (e.g. "start mission X"), never the menu itself.

## Answered with the reply's index, or -1 for Escape.
signal answered(index: int)

const GROUP := "dialogue_box"
const MAX_REPLIES := 9

var _speaker_label: Label
var _line_label: Label
var _replies: VBoxContainer
var _reply_count := 0


## The scene's dialogue box, made on first use.
static func open(tree: SceneTree) -> DialogueBox:
	var box := tree.get_first_node_in_group(GROUP) as DialogueBox
	if box == null:
		box = DialogueBox.new()
		tree.current_scene.add_child(box)
	box.visible = true
	box._lock_player(true)
	return box


## Shows a line and its replies, then waits for the player to pick one.
func ask(speaker: String, line: String, replies: Array[String]) -> int:
	_speaker_label.text = speaker
	_line_label.text = line
	for child in _replies.get_children():
		child.queue_free()
	_reply_count = mini(replies.size(), MAX_REPLIES)
	for i in _reply_count:
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, replies[i]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.6, 0.2))
		button.pressed.connect(_pick.bind(i))
		_replies.add_child(button)
	var index: int = await answered
	return index


func close() -> void:
	visible = false
	_lock_player(false)


func _ready() -> void:
	add_to_group(GROUP)
	layer = 15 # above the HUD, below the pause menu
	visible = false

	var panel := PanelContainer.new()
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -260.0
	panel.offset_bottom = -30.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.04, 0.88)
	style.border_color = Color(0.95, 0.75, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	column.add_child(_speaker_label)
	_line_label = Label.new()
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.add_theme_font_size_override("font_size", 22)
	column.add_child(_line_label)
	column.add_child(HSeparator.new())
	_replies = VBoxContainer.new()
	column.add_child(_replies)


## Number keys pick a reply; Escape backs out. _input (not
## _unhandled_input) so Escape closes this before the pause menu sees it.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		answered.emit(-1)
		return
	var number := key.keycode - KEY_1
	if number >= 0 and number < _reply_count:
		get_viewport().set_input_as_handled()
		_pick(number)


func _pick(index: int) -> void:
	answered.emit(index)


## Frees the mouse and stops your character while talking, and gives both
## back when done.
func _lock_player(locked: bool) -> void:
	var player := PlayerMovement.local_player(get_tree())
	if player:
		player.controls_locked = locked
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if locked else Input.MOUSE_MODE_CAPTURED
