class_name PlayerDeath
extends Node3D

## Dying (the user's, 2026-10-17), no words on the screen: the body goes
## limp -- a ragdoll of your own character, every bone carrying on at the
## speed you were going, so you fall the way you'd really fall -- and your
## view leaves your head, pulling back ZOOM m over FADE seconds to look down
## at your body while the screen slowly goes black. Black, you're back (at
## your camp if you had one, else the level restarts), waking up: on your
## back, the view rising to your eyes over WAKE seconds (the way you get up
## after the Stalker throws you), the black lifting.
## Rule 1 (co-op): every machine's copy of the body dies (Health.died fires
## on each) and drops its own ragdoll; only your own screen pulls back,
## fades and wakes.

const FADE := 5.0
## Held black this long before you're back.
const HOLD := 0.4
const ZOOM := 15.0
const WAKE := 1.0
## The black lifting as you wake.
const UNFADE := 0.8
const RAGDOLL_LAYER := 1 << 3
const OVERLAY_LAYER := 90

## Set as the level restarts after a death: wake up in the new one.
static var wake_after_reload := false

var player: PlayerMovement
var momentum := Vector3.ZERO
var _model: Node3D
var _bones: Array[PhysicalBone3D] = []
var _hips: PhysicalBone3D
var _body_model: Node3D
var _saved_head := Transform3D.IDENTITY
var _from_view := Transform3D.IDENTITY
var _back := Vector3.BACK
var _time := 0.0
var _black: ColorRect
## Died while the Stalker had you: its ragdoll is the body (freed on waking).
var _drag: StalkerDrag


## Dead: the ragdoll here, and (your own body) the pull-back and fade.
static func begin(who: PlayerMovement, carrying: Vector3) -> PlayerDeath:
	var existing: Variant = who.get_meta(&"player_death", null)
	if existing is PlayerDeath and is_instance_valid(existing):
		return existing
	var death := PlayerDeath.new()
	death.player = who
	death.momentum = carrying
	who.get_tree().current_scene.add_child(death)
	return death


## Alive again (PlayerMovement.respawn): the body's gone, you wake up.
static func wake(who: PlayerMovement) -> void:
	var existing: Variant = who.get_meta(&"player_death", null)
	if existing is PlayerDeath and is_instance_valid(existing):
		(existing as PlayerDeath).queue_free()
	if who.is_multiplayer_authority():
		var waking := Waking.new()
		waking.player = who
		# Your eyes where they belong (the dead view's still on the head).
		waking.eyes = (existing as PlayerDeath)._saved_head if existing is PlayerDeath and is_instance_valid(existing) else who.head.transform
		who.add_child(waking)


func _ready() -> void:
	player.set_meta(&"player_death", self)
	_body_model = player.get_node_or_null(^"PlayerModel") as Node3D
	var path: String = _body_model.get("character_path") if _body_model else ""
	if path != "" and ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate() as Node3D
	var flat := Vector3(momentum.x, 0.0, momentum.z)
	var facing := -player.global_basis.z
	_back = -(flat.normalized() if flat.length() > 1.0 else Vector3(facing.x, 0.0, facing.z).normalized())
	var drag: Variant = player.get_meta(&"stalker_drag", null)
	if drag is StalkerDrag and is_instance_valid(drag):
		# Died in the Stalker's grip: no second body -- the dragged one goes
		# limp where it lies, and the view pulls back from where it was.
		_drag = drag
		_hips = _drag.die()
		if _model:
			_model.free()
			_model = null
	if _model:
		add_child(_model)
		for node in _model.find_children("*", "AnimationPlayer", true, false):
			(node as AnimationPlayer).stop()
		_ragdoll()
	if _body_model:
		_body_model.visible = false
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as Node3D
	if viewmodel:
		viewmodel.visible = false
	_saved_head = _drag.saved_head() if _drag else player.head.transform
	_from_view = player.head.global_transform
	if player.is_multiplayer_authority():
		var layer := CanvasLayer.new()
		layer.layer = OVERLAY_LAYER
		add_child(layer)
		_black = ColorRect.new()
		_black.color = Color(0.0, 0.0, 0.0, 0.0)
		_black.set_anchors_preset(Control.PRESET_FULL_RECT)
		_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_black)


## The body exactly as it stood (its place, its pose), gone limp, every bone
## carrying on at the speed you were going -- and tipped a touch the way you
## were heading, so even standing still you fall.
func _ragdoll() -> void:
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var source_model: Variant = _body_model.get("_model") if _body_model else null
	if source_model is Node3D:
		_model.global_transform = (source_model as Node3D).global_transform
		var source_skeletons := (source_model as Node3D).find_children("*", "Skeleton3D", true, false)
		if not source_skeletons.is_empty():
			var source := source_skeletons[0] as Skeleton3D
			for i in mini(skeleton.get_bone_count(), source.get_bone_count()):
				skeleton.set_bone_pose_position(i, source.get_bone_pose_position(i))
				skeleton.set_bone_pose_rotation(i, source.get_bone_pose_rotation(i))
	else:
		var scale_by: float = _body_model.get("model_scale") if _body_model else 1.0
		_model.global_transform = Transform3D(Basis.looking_at(_back, Vector3.UP).scaled(Vector3.ONE * scale_by), player.global_position)
	var simulator := RagdollBuilder.build(skeleton)
	for node in simulator.get_children():
		var bone := node as PhysicalBone3D
		if bone == null:
			continue
		bone.collision_layer = RAGDOLL_LAYER
		bone.collision_mask = 1 | RAGDOLL_LAYER
		bone.add_collision_exception_with(player)
		_bones.append(bone)
		if String(bone.bone_name) == "Hips":
			_hips = bone
	simulator.physical_bones_start_simulation()
	for bone in _bones:
		bone.can_sleep = false
		bone.linear_velocity = momentum
		if String(bone.bone_name) in ["Chest", "UpperChest", "Head", "Neck", "Spine"]:
			bone.apply_central_impulse(-_back * 1.5 * bone.mass)


func _process(delta: float) -> void:
	_time += delta
	if _black == null or not is_instance_valid(player):
		return
	var t := clampf(_time / FADE, 0.0, 1.0)
	# Slowly to black, most of it at the end.
	_black.color.a = pow(t, 1.6)
	# Out of your head and back from the body, looking down at it.
	var body := _hips.global_position if _hips else player.global_position
	var way := (_back * 0.7 + Vector3.UP * 0.9).normalized()
	var reach := ZOOM * smoothstep(0.0, 1.0, t)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(body, body + way * reach, 1))
	if not hit.is_empty():
		reach = maxf(body.distance_to(hit.position) - 0.5, 0.0)
	var eye := body + way * reach
	var look := (body - eye).normalized() if reach > 0.1 else -way
	var target := Transform3D(Basis.looking_at(look, Vector3.UP if absf(look.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD), eye)
	player.head.global_transform = _from_view.interpolate_with(target, smoothstep(0.0, 0.35, t))


func _exit_tree() -> void:
	if not is_instance_valid(player):
		return
	if player.get_meta(&"player_death", null) == self:
		player.remove_meta(&"player_death")
	if is_instance_valid(_drag):
		_drag.queue_free()
	if _body_model:
		_body_model.visible = true
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as Node3D
	if viewmodel:
		viewmodel.visible = true
	player.head.transform = _saved_head


## Waking up: on your back where you're back, the view rising to your eyes
## over WAKE, the black lifting over UNFADE; your hands off till you're up.
class Waking extends Node:
	var player: PlayerMovement
	var eyes := Transform3D.IDENTITY
	var _time := 0.0
	var _eyes := Transform3D.IDENTITY
	var _lying := Transform3D.IDENTITY
	var _black: ColorRect

	func _ready() -> void:
		_eyes = eyes
		var facing := -player.global_basis.z
		facing = Vector3(facing.x, 0.0, facing.z).normalized()
		# Flat on your back: looking up (and a little ahead), tipped to one side.
		var up_ahead := (Vector3.UP + facing * 0.35).normalized()
		var lying_basis := Basis.looking_at(up_ahead, -facing).rotated(up_ahead, 0.35)
		_lying = Transform3D(lying_basis, player.global_position + Vector3.UP * 0.25)
		player.controls_locked = true
		var layer := CanvasLayer.new()
		layer.layer = OVERLAY_LAYER
		add_child(layer)
		_black = ColorRect.new()
		_black.color = Color.BLACK
		_black.set_anchors_preset(Control.PRESET_FULL_RECT)
		_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_black)
		player.head.global_transform = _lying

	func _process(delta: float) -> void:
		_time += delta
		_black.color.a = 1.0 - clampf(_time / UNFADE, 0.0, 1.0)
		var t := smoothstep(0.0, 1.0, clampf(_time / WAKE, 0.0, 1.0))
		player.head.global_transform = _lying.interpolate_with(player.global_transform * _eyes, t)
		if _time >= maxf(WAKE, UNFADE):
			player.head.transform = _eyes
			player.controls_locked = false
			queue_free()
