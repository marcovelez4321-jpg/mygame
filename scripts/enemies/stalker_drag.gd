class_name StalkerDrag
extends Node3D

## Taken by the Stalker (the user's, 2026-10-17; stage 3), on every machine:
## the player goes limp -- a ragdoll of their own character, on their back --
## and the Stalker drags it off by one foot. Their camera rides the
## ragdoll's head (just in front of the face), out of their control: every
## bump and swing of the drag is felt. Their own body is hidden meanwhile;
## the player is carried where the ragdoll's hips are.
## Getting loose: spam click -- each click a tug (ESCAPE_CLICKS of them,
## slipping back ESCAPE_SLIP a second), the Harvestman grab's meter; or a
## teammate shooting it (Stalker). The host decides (Stalker.drag_broken()).
## Rule 1 (co-op): the host starts and ends it (Network.send_stalker_drag);
## each machine pulls its own copy after its own Stalker.

const ESCAPE_CLICKS := 20.0
const ESCAPE_SLIP := 0.15
## How hard the foot is hauled toward the Stalker's hold.
const PULL := 10.0
const RAGDOLL_LAYER := 1 << 3
const VIEW_AHEAD := 0.14
## Smooth both ways (the user's: never immersion-breaking): the ragdoll
## starts in the very pose the body was in and is toppled by the pull; the
## view eases into its head over INTO_TIME and follows it a touch smoothed
## (VIEW_FOLLOW); let go, the view eases back up to your eyes over OUT_TIME
## (getting up), facing the way you lay, and your gun comes back up drawn.
const INTO_TIME := 0.35
const OUT_TIME := 0.5
const VIEW_FOLLOW := 18.0

var player: PlayerMovement
var stalker: Node3D
var escape := 0.0

var _model: Node3D
var _simulator: PhysicalBoneSimulator3D
var _bones: Array[PhysicalBone3D] = []
var _foot: PhysicalBone3D
var _shin: PhysicalBone3D
var _hips: PhysicalBone3D
var _head: PhysicalBone3D
var _body_model: Node3D
var _saved_layers := Vector2i.ZERO
var _saved_head := Transform3D.IDENTITY
var _start_view := Transform3D.IDENTITY
var _view := Transform3D.IDENTITY
var _time := 0.0
var _releasing := false
var _release_time := 0.0
var _release_from := Transform3D.IDENTITY
## Died while taken (PlayerDeath took over): its ragdoll is the body now.
var _dead := false


## Starts it for `player` (here), dragged by `stalker`.
static func begin(who: PlayerMovement, by: Node3D) -> StalkerDrag:
	var existing: Variant = (who.get_meta(&"stalker_drag") if who.has_meta(&"stalker_drag") else null)
	if existing is StalkerDrag and is_instance_valid(existing):
		return existing
	var drag := StalkerDrag.new()
	drag.player = who
	drag.stalker = by
	who.get_tree().current_scene.add_child(drag)
	return drag


## Ends it for `player` (here), if it's on: they get up (release()).
static func finish(who: PlayerMovement, throw: Vector3 = Vector3.ZERO) -> void:
	var existing: Variant = (who.get_meta(&"stalker_drag") if who.has_meta(&"stalker_drag") else null)
	if existing is StalkerDrag and is_instance_valid(existing):
		(existing as StalkerDrag).release(throw)


func _ready() -> void:
	player.set_meta(&"stalker_drag", self)
	player.drag = self
	_body_model = player.get_node_or_null(^"PlayerModel") as Node3D
	var path: String = _body_model.get("character_path") if _body_model else ""
	var scale_by: float = _body_model.get("model_scale") if _body_model else 1.0
	if path != "" and ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate() as Node3D
	if _model == null:
		return
	add_child(_model)
	for node in _model.find_children("*", "AnimationPlayer", true, false):
		(node as AnimationPlayer).stop()
	var trail := player.global_position - stalker.global_position
	trail.y = 0.0
	trail = trail.normalized() if trail.length_squared() > 0.01 else Vector3.BACK
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	# Exactly where and how the body stood (no pop): its place, its pose.
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
		_model.global_transform = Transform3D(Basis.looking_at(-trail, Vector3.UP).scaled(Vector3.ONE * scale_by), player.global_position)
	_simulator = RagdollBuilder.build(skeleton)
	for node in _simulator.get_children():
		var bone := node as PhysicalBone3D
		if bone == null:
			continue
		bone.collision_layer = RAGDOLL_LAYER
		bone.collision_mask = 1 | RAGDOLL_LAYER
		_bones.append(bone)
		var named := String(bone.bone_name)
		if named == "LeftFoot":
			_foot = bone
		elif named == "LeftLowerLeg":
			_shin = bone
		elif named == "Hips":
			_hips = bone
		elif named == "Head":
			_head = bone
	_simulator.physical_bones_start_simulation()
	for bone in _bones:
		bone.can_sleep = false
	if _foot == null:
		_foot = _shin
	# Toppled backward as the foot's yanked out from under them.
	for bone in _bones:
		var named := String(bone.bone_name)
		if named in ["Chest", "UpperChest", "Head", "Neck", "Spine"]:
			bone.apply_central_impulse((trail * 2.5 + Vector3.DOWN * 1.0) * bone.mass)
		elif named in ["LeftFoot", "LeftLowerLeg", "RightFoot", "RightLowerLeg"]:
			bone.apply_central_impulse((-trail * 3.0 + Vector3.UP * 1.5) * bone.mass)
	# Their own body hidden, out of the way; the gun and arms gone.
	if _body_model:
		_body_model.visible = false
	_saved_layers = Vector2i(player.collision_layer, player.collision_mask)
	player.collision_layer = 0
	player.collision_mask = 0
	_saved_head = player.head.transform
	_start_view = player.head.global_transform
	_view = _start_view
	# The gun drops out of view a beat after the grab; a jolt as it hits.
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as Node3D
	if viewmodel:
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			if is_instance_valid(viewmodel) and not _releasing:
				viewmodel.visible = false)
	if player.is_multiplayer_authority() and player.camera:
		player.camera.shake(3.5)
		player.camera.kick_fov(8.0)
	player.grapple.release()
	if player.is_multiplayer_authority() or not Network.is_online() or multiplayer.is_server():
		player.weapons.latch_leech(self) # clicks are tugs; its meter shows


## Let go: back on their feet where they lie, facing the way they lay; the
## view eases up from the ragdoll's head to their eyes over OUT_TIME, then
## it's all theirs again.
## `throw` (the user's: broke out of its grip): flung that way at once,
## yours to control again straight away (the view still eases up).
func release(throw: Vector3 = Vector3.ZERO) -> void:
	if _releasing or _dead:
		return
	_releasing = true
	_release_time = 0.0
	_release_from = _view
	player.weapons.unlatch_leech(self)
	if _hips:
		var facing := _flat(_release_from.basis * Vector3.FORWARD)
		player.global_position = _hips.global_position + Vector3.UP * 0.6
		player.rotation.y = atan2(-facing.x, -facing.z)
	player.velocity = Vector3.ZERO
	player.set("_pitch", 0.0)
	if throw != Vector3.ZERO:
		player.drag = null
		player.collision_layer = _saved_layers.x
		player.collision_mask = _saved_layers.y
		player.shove(throw)


## Died while taken (PlayerDeath): the ragdoll stays as the body, no more
## pulling or riding its head -- the view and the end are PlayerDeath's (it
## frees this when you wake). The ragdoll's hips: PlayerDeath's to look at.
func die() -> PhysicalBone3D:
	_dead = true
	player.weapons.unlatch_leech(self)
	return _hips


## The head as it sat before the grab (PlayerDeath's: your eyes on waking).
func saved_head() -> Transform3D:
	return _saved_head


static func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD


func _exit_tree() -> void:
	if not is_instance_valid(player):
		return
	if (player.get_meta(&"stalker_drag") if player.has_meta(&"stalker_drag") else null) == self:
		player.remove_meta(&"stalker_drag")
	player.drag = null
	player.weapons.unlatch_leech(self)
	if _body_model:
		_body_model.visible = true
	player.collision_layer = _saved_layers.x
	player.collision_mask = _saved_layers.y
	player.head.transform = _saved_head
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as Node3D
	if viewmodel:
		viewmodel.visible = true
	# The gun comes back up, drawn.
	var gun := player.weapons.current_weapon()
	if gun and not player.weapons.gun_stowed:
		player.weapons.weapon_switched.emit(gun, maxf(gun.draw_time, 0.3))


func _physics_process(delta: float) -> void:
	escape = maxf(escape - ESCAPE_SLIP * delta, 0.0)
	if _releasing or _dead or not is_instance_valid(stalker) or _foot == null:
		return
	# Hauled by the foot toward its hold: just behind it, low.
	var hold := stalker.global_position + stalker.global_basis.z * 0.8 + stalker.global_basis.y * 0.35
	var pull := (hold - _foot.global_position) * PULL - _foot.linear_velocity
	_foot.apply_central_impulse(pull * _foot.mass * delta * 6.0)
	if _shin:
		_shin.apply_central_impulse(pull * _shin.mass * delta * 3.0)


## Your view: the ragdoll's head, a touch in front of the face, looking where
## the face looks -- yours only, and out of your hands.
func _process(delta: float) -> void:
	_time += delta
	if _dead:
		return
	if _releasing:
		_release_time += delta
		if player.is_multiplayer_authority():
			# Up from where the ragdoll's head was to your own eyes.
			var eyes := player.global_transform * _saved_head
			var t := smoothstep(0.0, 1.0, clampf(_release_time / OUT_TIME, 0.0, 1.0))
			player.head.global_transform = _release_from.interpolate_with(eyes, t)
		if _release_time >= OUT_TIME:
			queue_free()
		return
	if _head == null or not player.is_multiplayer_authority():
		return
	var face := _head.global_basis
	var forward := face.z.normalized() if face.z.length_squared() > 0.0001 else Vector3.UP
	var up := face.y.normalized()
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.UP
	var target := Transform3D(Basis.looking_at(forward, up), _head.global_position + forward * VIEW_AHEAD)
	# Followed a touch smoothed (the violence comes through, not the jitter),
	# eased into from where you were looking.
	_view = _view.interpolate_with(target, 1.0 - exp(-VIEW_FOLLOW * delta))
	var into := smoothstep(0.0, 1.0, clampf(_time / INTO_TIME, 0.0, 1.0))
	player.head.global_transform = _start_view.interpolate_with(_view, into)


## Where the player is now (the ragdoll's hips).
func hips_position() -> Vector3:
	return _hips.global_position if _hips else player.global_position


# The grab's meter (WeaponController's leech hooks: clicks tug, the HUD shows it).
func tug() -> void:
	escape = minf(escape + 1.0 / ESCAPE_CLICKS, 1.0)
	if escape >= 1.0 and (not Network.is_online() or multiplayer.is_server()) and is_instance_valid(stalker):
		stalker.call(&"drag_broken")


func progress() -> float:
	return escape


func meter_text() -> String:
	return "IT'S GOT YOU! SPAM CLICK TO BREAK FREE!"
