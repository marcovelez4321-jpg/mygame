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


## Starts it for `player` (here), dragged by `stalker`.
static func begin(who: PlayerMovement, by: Node3D) -> StalkerDrag:
	var existing: Variant = who.get_meta(&"stalker_drag", null)
	if existing is StalkerDrag and is_instance_valid(existing):
		return existing
	var drag := StalkerDrag.new()
	drag.player = who
	drag.stalker = by
	who.get_tree().current_scene.add_child(drag)
	return drag


## Ends it for `player` (here), if it's on.
static func finish(who: PlayerMovement) -> void:
	var existing: Variant = who.get_meta(&"stalker_drag", null)
	if existing is StalkerDrag and is_instance_valid(existing):
		(existing as StalkerDrag).queue_free()


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
	# On its back, feet toward the Stalker, head trailing away from it.
	var trail := player.global_position - stalker.global_position
	trail.y = 0.0
	trail = trail.normalized() if trail.length_squared() > 0.01 else Vector3.BACK
	var lying := Basis.looking_at(-trail, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	_model.global_transform = Transform3D(lying.scaled(Vector3.ONE * scale_by), player.global_position + Vector3.UP * 0.3)
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_simulator = RagdollBuilder.build(skeletons[0] as Skeleton3D)
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
	# Their own body hidden, out of the way; the gun and arms gone.
	if _body_model:
		_body_model.visible = false
	_saved_layers = Vector2i(player.collision_layer, player.collision_mask)
	player.collision_layer = 0
	player.collision_mask = 0
	_saved_head = player.head.transform
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as Node3D
	if viewmodel:
		viewmodel.visible = false
	player.grapple.release()
	if player.is_multiplayer_authority() or not Network.is_online() or multiplayer.is_server():
		player.weapons.latch_leech(self) # clicks are tugs; its meter shows


func _exit_tree() -> void:
	if not is_instance_valid(player):
		return
	if player.get_meta(&"stalker_drag", null) == self:
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
	# Back on their feet where they were left.
	if _hips:
		player.global_position = _hips.global_position + Vector3.UP * 0.6
	player.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	escape = maxf(escape - ESCAPE_SLIP * delta, 0.0)
	if not is_instance_valid(stalker) or _foot == null:
		return
	# Hauled by the foot toward its hold: just behind it, low.
	var hold := stalker.global_position + stalker.global_basis.z * 0.8 + stalker.global_basis.y * 0.35
	var pull := (hold - _foot.global_position) * PULL - _foot.linear_velocity
	_foot.apply_central_impulse(pull * _foot.mass * delta * 6.0)
	if _shin:
		_shin.apply_central_impulse(pull * _shin.mass * delta * 3.0)


## Your view: the ragdoll's head, a touch in front of the face, looking where
## the face looks -- yours only, and out of your hands.
func _process(_delta: float) -> void:
	if _head == null or not player.is_multiplayer_authority():
		return
	var face := _head.global_basis
	var forward := face.z.normalized() if face.z.length_squared() > 0.0001 else Vector3.UP
	var up := face.y.normalized()
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.UP
	player.head.global_transform = Transform3D(Basis.looking_at(forward, up), _head.global_position + forward * VIEW_AHEAD)


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