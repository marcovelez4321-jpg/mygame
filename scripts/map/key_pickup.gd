class_name KeyPickup
extends Area3D

## item_key: a spinning key a mapper places in TrenchBroom. Walk through it
## and you carry that key (PlayerMovement.give_key()); a door with the same
## "key" setting then opens for you. Quake 1's silver and gold keys
## (item_key1/item_key2) -- to add a colour, add a name and a colour below
## and a matching choice in fgd/item_key.tres and fgd/func_door*.tres.

const KEY_NAMES: Array[String] = ["silver", "gold"]
const KEY_COLORS: Array[Color] = [Color(0.8, 0.84, 0.9), Color(1.0, 0.78, 0.2)]
const SPIN_SPEED := 2.0 # radians per second
const BOB_HEIGHT := 0.08
const PICKUP_SOUND := preload("res://audio/events/map/key_pickup.tres")

## Index into KEY_NAMES; set from the "key_type" choice in TrenchBroom.
@export var key_type: int = 0

var _model: Node3D
var _time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Deferred: when the map is built while the game runs, func_godot sets
	# key_type only after this node is added.
	_build_model.call_deferred()


func key_name() -> String:
	return KEY_NAMES[clampi(key_type, 0, KEY_NAMES.size() - 1)]


func _process(delta: float) -> void:
	_time += delta
	if _model:
		_model.rotation.y = _time * SPIN_SPEED
		_model.position.y = sin(_time * 2.0) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerMovement
	if player == null or player.has_key(key_name()):
		return
	player.give_key(key_name())
	SoundPlayer.play_3d(PICKUP_SOUND, global_position, get_tree().current_scene)
	MapIO.show_message(get_tree(), "You got the %s key" % key_name())
	queue_free()


## A simple key: a ring (the bow) and a shaft with a tooth, in the key's
## colour and a little glow so it reads in a dark corner.
func _build_model() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = KEY_COLORS[clampi(key_type, 0, KEY_COLORS.size() - 1)]
	material.metallic = 0.8
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.3

	_model = Node3D.new()
	add_child(_model)
	var bow := TorusMesh.new()
	bow.inner_radius = 0.06
	bow.outer_radius = 0.11
	_add_part(bow, Vector3(0.0, 0.15, 0.0), Vector3(PI * 0.5, 0.0, 0.0), material)
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.035, 0.28, 0.035)
	_add_part(shaft, Vector3(0.0, -0.08, 0.0), Vector3.ZERO, material)
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.08, 0.05, 0.035)
	_add_part(tooth, Vector3(0.05, -0.19, 0.0), Vector3.ZERO, material)


func _add_part(mesh: Mesh, position_offset: Vector3, rotation_offset: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position_offset
	part.rotation = rotation_offset
	_model.add_child(part)
