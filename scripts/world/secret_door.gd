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
	echo(MOVING, middle, get_tree().current_scene)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + PI * 0.5, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: echo(STOPPED, middle, get_tree().current_scene))


## A sound heard through the halls the way a radio is (the user's: exactly
## the same -- Radio's three voices on its buses and its mix): clear up
## close, the tinny one further off, and far away a muffled echo rolling
## through the halls, its long reverb fading slowly after.
static func echo(event: SoundEvent, at: Vector3, world: Node) -> void:
	var clip := event.pick_clip() if event else null
	if clip == null or world == null:
		return
	Radio._ensure_buses()
	var camera := world.get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(at) if camera else 0.0
	# Radio._mix_by(), with a radio's own settings.
	var clear_until := 15.0
	var tinny_until := 45.0
	var to_tinny := smoothstep(clear_until * 0.5, clear_until * 2.0, distance)
	var to_echo := smoothstep(clear_until, 80.0, distance)
	var voices := [
		[Radio.CLEAR_BUS, tinny_until, 3.0, 2.0 + linear_to_db(maxf(1.0 - to_tinny, 0.0001))],
		[Radio.VOICE_BUS, tinny_until + 20.0, 5.0, -2.0 + linear_to_db(maxf(to_tinny * (1.0 - smoothstep(tinny_until * 0.7, tinny_until, distance) * 0.7), 0.0001))],
		[Radio.ECHO_BUS, 275.0, 22.0, lerpf(-30.0, 0.0, to_echo)],
	]
	var pitch := event.roll_pitch_scale()
	for voice: Array in voices:
		var player := AudioStreamPlayer3D.new()
		player.stream = clip
		player.bus = voice[0]
		player.max_distance = voice[1]
		player.unit_size = voice[2]
		player.volume_db = voice[3]
		player.pitch_scale = pitch
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		if voice[0] == Radio.ECHO_BUS:
			player.attenuation_filter_cutoff_hz = 2500.0
			player.attenuation_filter_db = -18.0
		world.add_child(player)
		player.global_position = at
		player.finished.connect(player.queue_free)
		player.play()


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