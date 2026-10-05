class_name PlayerModel
extends Node3D

## The character the player wears: any Male/Female character FBX, picked in
## the pause menu and saved (GameSettings.player_character). They all share
## the Mixamo skeleton through art/animations/mixamo_bonemap.tres, so one set
## of animations drives every one of them.
##
## For the LOCAL player the head and arms are hidden (HideBonesModifier):
## looking down shows your torso and legs, without the inside of your own
## skull or a second pair of arms next to the gun. A remote co-op player's
## model shows everything.
## Rule 1 (co-op): cosmetic only. A remote player's model is set by
## set_character() from their chosen path, sent over the network -- never
## from this client's own saved choice.

const CHARACTER_FOLDERS: Array[String] = [
	"res://art/characters/Characters_psx/Models/Male",
	"res://art/characters/Characters_psx/Models/Female",
]
## The player's own idle and run (from IdlePlayer.fbx / RunningPlayer.fbx),
## separate from the enemies' Idle/Run so the two can be changed apart.
const IDLE_ANIMATION := "res://art/animations/IdlePlayer.res"
const RUN_ANIMATION := "res://art/animations/RunningPlayer.res"

## Bones hidden from your own first-person view, with everything below them.
@export var hidden_bones_local: PackedStringArray = ["Head", "LeftUpperArm", "RightUpperArm"]
## The model is scaled so its Head bone (the base of the skull) sits this far
## below the camera -- so every character, tall or short, sees from its eyes.
@export var head_bone_below_eyes: float = 0.1
## Pushes the body back behind the camera, so looking down doesn't put the
## camera inside your own chest.
@export var body_back_offset: float = 0.15
## Horizontal speed (m/s) at which the run animation plays at normal speed;
## faster or slower movement speeds it up or down to match.
@export var run_animation_speed: float = 6.0

## Fired after the model is (re)built, so the first-person arms can rebuild
## with the same character.
signal character_changed

var character_path: String = ""
## The size the model was scaled to so its head meets the camera -- the
## first-person arms use the same scale so they match the body.
var model_scale: float = 1.0

var _model: Node3D
var _animation_player: AnimationPlayer

@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _head: Node3D = _player.get_node("Head") as Node3D


## Every character a player can pick, sorted so the list -- and in co-op, a
## path sent between players -- is the same on every machine.
static func available_characters() -> Array[String]:
	var result: Array[String] = []
	for folder in CHARACTER_FOLDERS:
		for file in ResourceLoader.list_directory(folder):
			if file.get_extension().to_lower() == "fbx":
				result.append(folder.path_join(file))
	result.sort()
	return result


func _ready() -> void:
	if not _player.is_multiplayer_authority():
		return # a remote player's character arrives through set_character()
	var characters := available_characters()
	var path := GameSettings.player_character
	if not characters.has(path):
		path = characters[0] if not characters.is_empty() else ""
	set_character(path)


func set_character(path: String) -> void:
	if path == character_path and _model != null:
		return
	if _model != null:
		remove_child(_model)
		_model.queue_free()
		_model = null
		_animation_player = null
	character_path = path
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	var skeleton := _find_skeleton()
	if skeleton == null:
		push_warning("PlayerModel: %s has no skeleton -- was it imported with mixamo_bonemap.tres?" % path)
		return
	_fit_to_player(skeleton)
	_setup_animation()
	if _player.is_multiplayer_authority():
		var hider := HideBonesModifier.new()
		hider.bone_names = hidden_bones_local
		skeleton.add_child(hider)
	character_changed.emit()


func _find_skeleton() -> Skeleton3D:
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] as Skeleton3D if not skeletons.is_empty() else null


## Faces the model forward (Mixamo characters face +Z, the player looks down
## -Z), scales it so its head lands at the camera, and nudges it back.
## Measured from the skeleton's rest pose, so it works for any character.
func _fit_to_player(skeleton: Skeleton3D) -> void:
	_model.rotation = Vector3(0.0, PI, 0.0)
	var head := skeleton.find_bone("Head")
	if head == -1:
		return
	var head_height := (skeleton.global_transform * skeleton.get_bone_global_rest(head).origin).y - global_position.y
	if head_height > 0.01:
		model_scale = (_head.position.y - head_bone_below_eyes) / head_height
		_model.scale = Vector3.ONE * model_scale
	_model.position = Vector3(0.0, 0.0, body_back_offset)


## The model's AnimationPlayer -- or a new one, since a character FBX with no
## animations of its own is imported without one. The Mixamo clips address
## the skeleton as %GeneralSkeleton (named by the bone map), so they find it
## from the model's root either way.
static func animator_for(model: Node3D) -> AnimationPlayer:
	var animator := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animator == null:
		animator = AnimationPlayer.new()
		model.add_child(animator)
	return animator


func _setup_animation() -> void:
	_animation_player = animator_for(_model)
	if not _animation_player.has_animation_library(&"moves"):
		var library := AnimationLibrary.new()
		library.add_animation(&"Idle", load(IDLE_ANIMATION) as Animation)
		library.add_animation(&"Run", load(RUN_ANIMATION) as Animation)
		_animation_player.add_animation_library(&"moves", library)
	for animation_name in [&"moves/Idle", &"moves/Run"]:
		_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(&"moves/Idle")


## Idle when standing, run when moving -- sped up or slowed to the player's
## real speed so feet don't slide. Reads only velocity, so in co-op it works
## the same for a remote player from their replicated movement.
func _process(_delta: float) -> void:
	if _animation_player == null:
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed > 0.5 and _player.is_on_floor():
		_play(&"moves/Run", clampf(speed / run_animation_speed, 0.5, 2.0))
	else:
		_play(&"moves/Idle", 1.0)


func _play(animation_name: StringName, speed_scale: float) -> void:
	if _animation_player.current_animation != animation_name:
		_animation_player.play(animation_name, 0.2)
	_animation_player.speed_scale = speed_scale
