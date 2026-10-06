class_name Grandma
extends StaticBody3D

## Grandma. Walk up and press F to talk ("[F] Talk"): she
## switches to her talking animation and a Fallout-style DialogueBox opens.
## "Let's do a mission." -> "Bet." -> pick from the mission list (every
## MissionData in res://missions) -> she does her summoning gesture and a
## MissionPortal opens beside her. Walk into it to go.
##
## Uses the shared Mixamo setup like every other character, so any
## Mixamo animation imported with art/animations/mixamo_bonemap.tres works
## on her: drop the .res files into the animation slots below.
##
## Rule 1 (co-op): the conversation is local to whoever's talking; picking
## a mission is what goes to the host, which opens the portal for both
## players. Her talking/idle animation follows one synced on/off state.

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
## The gesture as she opens the portal (e.g. Mixamo "Sitting Clap"). Empty
## = keeps talking.
@export var summon_animation: Animation
## Seconds from her gesture starting to the portal appearing.
@export var summon_delay: float = 0.8

@export_group("Portal")
## Where the portal opens, relative to her (x = her right, -z = in front
## of her). Rotate her and it follows.
@export var portal_offset: Vector3 = Vector3(1.8, 0.0, -0.6)
## A real portal model, when you have one. Empty = the placeholder ring.
@export var portal_model: PackedScene

## Shown under the crosshair: "[F] Talk".
var use_prompt: String = "Talk"

var _animator: AnimationPlayer
var _talking := false
var _portal: MissionPortal


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
	var pick := await box.ask(lines.speaker_name, _random_line(lines.greetings),
			[lines.reply_mission, lines.reply_just_saying_hi])
	if pick == 0:
		var missions := MissionData.all()
		if missions.is_empty():
			await box.ask(lines.speaker_name, lines.no_missions_line, [lines.reply_leave])
			box.close()
		else:
			var choices: Array[String] = []
			for mission in missions:
				choices.append("%s -- %s" % [mission.title, mission.description] if mission.description else mission.title)
			choices.append(lines.reply_never_mind)
			var chosen := await box.ask(lines.speaker_name, lines.mission_prompt, choices)
			box.close()
			if chosen >= 0 and chosen < missions.size():
				await _summon(missions[chosen])
	elif pick == 1:
		await box.ask(lines.speaker_name, _random_line(lines.goodbye_lines), [lines.reply_leave])
		box.close()
	else:
		box.close()
	_play(idle_animation, 1.0)
	_talking = false


## One line at random from a list ("..." if the list was left empty).
func _random_line(options: Array[String]) -> String:
	return options.pick_random() if not options.is_empty() else "..."


## Her gesture, then the portal pops open beside her, facing the player.
func _summon(mission: MissionData) -> void:
	if summon_animation:
		_play(summon_animation, 1.0)
	await get_tree().create_timer(summon_delay).timeout
	if is_instance_valid(_portal):
		_portal.queue_free() # one portal at a time
	var spot := global_transform * portal_offset
	var player := PlayerMovement.local_player(get_tree())
	var facing := player.global_position if player else spot + global_transform.basis.z
	_portal = MissionPortal.open_portal(get_tree().current_scene, mission, spot, facing, portal_model)


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
	# Idle and talking loop; the summon gesture plays once.
	animation.loop_mode = Animation.LOOP_NONE if animation == summon_animation else Animation.LOOP_LINEAR
	_animator.play(StringName("grandma/" + clip_name), 0.25, speed)
