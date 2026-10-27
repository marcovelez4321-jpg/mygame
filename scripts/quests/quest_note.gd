class_name QuestNote
extends Area3D

## A note to find (the user's: it floats and spins like the keys): the dead
## climber's letter to Mara, the cult's note on the bounty man. Walk into it
## and it's read -- into the journal (QuestJournal), its quest moved on
## (Quests.note_read).
## Rule 1 (co-op): the host's (NetEntities); the host decides who read it.

const SPIN_SPEED := 2.0
const HOVER := 1.0
const BOB := 0.12
const PAPER := Color(0.86, 0.8, 0.66)

var note: StringName = &""

var _paper: Node3D
var _time := 0.0
var _read := false


## The host: one dropped at `at`.
static func drop(tree: SceneTree, at: Vector3, which: StringName) -> QuestNote:
	var made := QuestNote.new()
	made.note = which
	tree.current_scene.add_child(made)
	made.global_position = at
	return made


func net_spawn_args() -> Dictionary:
	return {note = note}


func net_restore(args: Dictionary) -> void:
	note = StringName(args.get("note", ""))


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	collision_layer = 0
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	_paper = Node3D.new()
	add_child(_paper)
	var sheet := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.21, 0.29) * CarryItem.ITEM_SIZE
	sheet.mesh = quad
	var look := StandardMaterial3D.new()
	look.albedo_color = PAPER
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.emission_enabled = true
	look.emission = PAPER
	look.emission_energy_multiplier = 0.25
	sheet.material_override = look
	_paper.add_child(sheet)
	var light := CarryItem.light_shaft(HOVER + 1.0)
	if light:
		add_child(light)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_time += delta
	_paper.rotation.y = _time * SPIN_SPEED
	_paper.position.y = HOVER * 0.5 + sin(_time * 2.2) * BOB


func _on_body(body: Node3D) -> void:
	if _read or not body is PlayerMovement or NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	var player := body as PlayerMovement
	if player.is_dead():
		return
	_read = true
	Quests.note_read(note, player)
	player.hand.picked_up()
	queue_free()
