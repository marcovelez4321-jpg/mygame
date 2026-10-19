class_name Grandma
extends StaticBody3D

## Grandma. Walk up and press F to talk ("[F] Talk"): she switches to her
## talking animation and a Fallout-style DialogueBox opens. A quest giver
## (the user's, 2026-10-19: no more missions or portals) -- GrandmaQuests:
## she asks for the last pack of cigarettes in the world (somewhere inside
## the Stack; she hints which tower and how high), reminds you while you
## look, and takes it off you when you bring it.
##
## Uses the shared Mixamo setup like every other character, so any
## Mixamo animation imported with art/animations/mixamo_bonemap.tres works
## on her: drop the .res files into the animation slots below.
##
## Rule 1 (co-op): the conversation is local to whoever's talking; taking the
## quest and handing the pack in go to the host (Network.ask_quest), whose
## quest it is, everyone's (the user's: shared).
## Everything she says and every reply you can pick. Click
## dialogue/grandma.tres to edit it all in the Inspector.
@export var dialogue: GrandmaDialogue = preload("res://dialogue/grandma.tres")

@export_group("Model")
@export var model_scene: PackedScene = preload("res://art/characters/Characters_psx/Models/Female/Character_31_Female.fbx")
## The Characters PSX models import big; enemies use the same 0.45.
@export var model_scale: float = 0.45

@export_group("Animations")
## Her idle (e.g. Mixamo "Sitting Idle", once the hub has a chair for her).
## The standing player idle until then.
@export var idle_animation: Animation = preload("res://art/animations/IdlePlayer.res")
## Talking to you (Mixamo "Sitting Talking"). Empty = her idle, a bit faster.
@export var talk_animation: Animation

## Shown under the crosshair: "[F] Talk".
var use_prompt: String = "Talk"

var _animator: AnimationPlayer
var _talking := false


func _ready() -> void:
	add_to_group(PlayerMovement.USABLE_GROUP)
	_build_model()


## PlayerMovement asks before showing "[F] Talk".
func can_use() -> bool:
	return not _talking


## F pressed on her.
func use_by(_player: Node) -> void:
	if _talking:
		return
	_talk()


func _talk() -> void:
	_talking = true
	_play(talk_animation if talk_animation else idle_animation, 1.0 if talk_animation else 1.3)
	var lines := dialogue
	var box := DialogueBox.open(get_tree())
	var quest := GrandmaQuests.CIGARETTES
	var state := GrandmaQuests.state(quest)
	var player := PlayerMovement.local_player(get_tree())
	var has_pack := player != null and player.backpack != null and player.backpack.cigarettes > 0
	# What you can say: the quest first (hand it in, ask about it, or ask if
	# she needs anything), then hello, then leave.
	var options: Array[String] = []
	var actions: Array[StringName] = []
	if state != GrandmaQuests.State.DONE:
		if has_pack:
			options.append(lines.reply_hand_in)
			actions.append(&"hand_in")
		elif state == GrandmaQuests.State.ACTIVE:
			options.append(lines.reply_ask_about)
			actions.append(&"reminder")
		else:
			options.append(lines.reply_need_anything)
			actions.append(&"offer")
	options.append(lines.reply_just_saying_hi)
	actions.append(&"hi")
	options.append(lines.reply_leave)
	actions.append(&"leave")
	var pick := await box.ask(lines.speaker_name, _random_line(lines.greetings), options)
	var action: StringName = actions[pick] if pick >= 0 and pick < actions.size() else &"leave"
	match action:
		&"offer":
			var answer := await box.ask(lines.speaker_name, _with_hint(lines.cigarettes_offer), [lines.reply_accept, lines.reply_decline])
			if answer == 0:
				Network.ask_quest(quest, &"accept")
		&"reminder":
			await box.ask(lines.speaker_name, _with_hint(lines.cigarettes_reminder), [lines.reply_leave])
		&"hand_in":
			Network.ask_quest(quest, &"hand_in")
			await box.ask(lines.speaker_name, lines.cigarettes_done, [lines.reply_leave])
		&"hi":
			await box.ask(lines.speaker_name, _random_line(lines.goodbye_lines), [lines.reply_leave])
	box.close()
	_play(idle_animation, 1.0)
	_talking = false


## Her line, then where the pack is (GrandmaQuests' hint), if she knows.
func _with_hint(line: String) -> String:
	var where := GrandmaQuests.hint(GrandmaQuests.CIGARETTES)
	if where.is_empty():
		return line
	return line + "\n\n" + dialogue.cigarettes_hint.replace("{where}", where)

## One line at random from a list ("..." if the list was left empty).
func _random_line(options: Array[String]) -> String:
	return options.pick_random() if not options.is_empty() else "..."


func _build_model() -> void:
	if model_scene == null:
		return
	var model := model_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = PI # Mixamo characters face +Z; she faces her -Z
	add_child(model)
	_animator = PlayerModel.animator_for(model)
	_play(idle_animation, 1.0)


func _play(animation: Animation, speed: float) -> void:
	if _animator == null or animation == null:
		return
	if not _animator.has_animation_library(&"grandma"):
		_animator.add_animation_library(&"grandma", AnimationLibrary.new())
	var library := _animator.get_animation_library(&"grandma")
	var clip_name := StringName(animation.resource_path.get_file().get_basename())
	if not library.has_animation(clip_name):
		library.add_animation(clip_name, animation)
	animation.loop_mode = Animation.LOOP_LINEAR # (idle and talking loop)
	_animator.play(StringName("grandma/" + clip_name), 0.25, speed)
