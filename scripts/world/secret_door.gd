class_name SecretDoor
extends AnimatableBody3D

## A secret door in the Stack (the user's, 2026-10-17; StackBuilder places
## them). Person-size, it swings in on its hinge (this node: +X across the
## doorway, +Z toward the side you stand on).
##   KEY: a visible locked door (one of the Mega Pack's loose doors, at
##   random). F with a key in your backpack: the key's used up and it opens;
##   without one it rattles, locked. Keys open any key door (universal), never
##   a button door.
##   BUTTON: looks like the wall round it (the builder's panel: the wall's
##   own concrete, lined up with it) -- nothing to use. Its SecretButton,
##   somewhere within 40 m, opens it.
## Rule 1 (co-op): the host opens it (a key, a button) and tells everyone;
## open is open for everyone. A late joiner asks the host which are open.

enum Lock { KEY, BUTTON }

const DOOR_MODELS := [
	"door_1_loose", "door_2_loose", "door_3_loose", "door_4_loose", "door_mp_1_loose", "door_mp_6_loose",
]
const MODEL_DIR := "res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Modular Structures/"
const OPEN_TIME := 1.3
const LOCKED := preload("res://audio/events/map/door_locked.tres")
const MOVING := preload("res://audio/events/map/door_move.tres")
const STOPPED := preload("res://audio/events/map/door_stop.tres")

@export var lock: Lock = Lock.KEY
@export var size := Vector2(2.0, 3.0)
@export var thick := 0.5
@export var model_index := 0

var is_open := false
var use_prompt := "Unlock"

static var _doors: Array[SecretDoor] = []


func _ready() -> void:
	sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, thick)
	shape.shape = box
	shape.position = Vector3(size.x * 0.5, size.y * 0.5, -thick * 0.5)
	add_child(shape)
	if lock == Lock.KEY:
		_build_leaf()
		add_to_group(PlayerMovement.USABLE_GROUP)
	_doors.append(self)
	if Network.is_online() and not multiplayer.is_server():
		(func() -> void: _net_ask.rpc_id(1)).call_deferred()


func _exit_tree() -> void:
	_doors.erase(self)


func can_use() -> bool:
	return lock == Lock.KEY and not is_open


## F on a key door: a key out of your backpack opens it (the host's call).
func use_by(player: Node) -> void:
	var body := player as PlayerMovement
	if body == null or is_open or lock != Lock.KEY:
		return
	if Network.is_online() and not multiplayer.is_server():
		if body.backpack.keys <= 0 and body.is_multiplayer_authority():
			_rattle(body)
		return
	if body.backpack.keys <= 0:
		_rattle(body)
		return
	body.backpack.use_key()
	open()


func _rattle(body: PlayerMovement) -> void:
	SoundPlayer.play_3d(LOCKED, global_position + global_basis * Vector3(size.x * 0.5, 1.2, 0.0), get_tree().current_scene)
	if body.is_multiplayer_authority():
		MapIO.show_message(get_tree(), "Locked. It needs a key.")


## Opens it (the host's; a key, its button): everyone sees it swing.
func open() -> void:
	if is_open:
		return
	if Network.is_online() and multiplayer.is_server():
		_net_open.rpc()
	_swing()


func _swing() -> void:
	if is_open:
		return
	is_open = true
	remove_from_group(PlayerMovement.USABLE_GROUP)
	var middle := global_position + global_basis * Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	SoundPlayer.play_3d(MOVING, middle, get_tree().current_scene)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + PI * 0.5, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: SoundPlayer.play_3d(STOPPED, middle, get_tree().current_scene))


@rpc("any_peer", "call_remote", "reliable")
func _net_open() -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_swing()


@rpc("any_peer", "call_remote", "reliable")
func _net_ask() -> void:
	if multiplayer.is_server() and is_open:
		_net_open.rpc_id(multiplayer.get_remote_sender_id())


## The key door's leaf: one of the loose doors, fitted to the doorway.
func _build_leaf() -> void:
	var path: String = MODEL_DIR + DOOR_MODELS[model_index % DOOR_MODELS.size()] + ".glb"
	var model: Node3D = null
	if ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate() as Node3D
	if model == null:
		var plain := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x, size.y, 0.12)
		plain.mesh = mesh
		plain.position = Vector3(size.x * 0.5, size.y * 0.5, -0.06)
		add_child(plain)
		return
	var holder := Node3D.new()
	holder.add_child(model)
	var box := BackpackView._bounds(holder)
	# Its thin side along Z (into the doorway).
	if box.size.x < box.size.z:
		model.rotation.y = PI * 0.5
		box = BackpackView._bounds(holder)
	var fit := Vector3(size.x / maxf(box.size.x, 0.01), size.y / maxf(box.size.y, 0.01), 0.12 / maxf(box.size.z, 0.01))
	holder.scale = fit
	holder.position = Vector3(size.x * 0.5, 0.0, -0.06) - Vector3(box.get_center().x, box.position.y, box.get_center().z) * fit
	add_child(holder)