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
## The key model (PSX Mega Pack key_mp_4). It's tinted the key's colour so
## silver and gold stay easy to tell apart.
@export var model_scene: PackedScene = preload("res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Items & Weapons/key_mp_4.glb")
## The model is a real-sized 9 cm key; this makes it big enough to spot.
@export var model_scale: float = 3.0

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


## The key model, stood upright (it's modelled lying flat), scaled up,
## centred on the spin point and tinted the key's colour with a slight glow
## so it reads in a dark corner.
func _build_model() -> void:
	if model_scene == null:
		return
	_model = Node3D.new() # spins and bobs (see _process)
	add_child(_model)
	var key := model_scene.instantiate() as Node3D
	key.rotation.z = PI * 0.5
	key.scale = Vector3.ONE * model_scale
	_model.add_child(key)

	var meshes := key.find_children("*", "MeshInstance3D", true, false)
	if key is MeshInstance3D:
		meshes.append(key)
	var bounds := AABB()
	var has_bounds := false
	var color := KEY_COLORS[clampi(key_type, 0, KEY_COLORS.size() - 1)]
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var box := _model.global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
		_tint(mesh_node, color)
	if has_bounds:
		key.position -= bounds.get_center()


## Multiplies the model's own texture by the key colour (a copy of each
## material, so tinting one key never recolours another).
func _tint(mesh_node: MeshInstance3D, color: Color) -> void:
	for i in mesh_node.get_surface_override_material_count():
		var original := mesh_node.get_active_material(i) as StandardMaterial3D
		if original == null:
			continue
		var tinted := original.duplicate() as StandardMaterial3D
		tinted.albedo_color = color
		tinted.emission_enabled = true
		tinted.emission = color
		tinted.emission_energy_multiplier = 0.25
		mesh_node.set_surface_override_material(i, tinted)
