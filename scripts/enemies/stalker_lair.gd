class_name StalkerLair
extends Node3D

## The Stalker's lair (the user's, 2026-10-21): in the Stack's flooded depths,
## on top of one of the half-sunk blocks in the drowned hall -- its nest: heaps
## of bones and remains, torn climbers' clothes, blood, the backpacks of the
## climbers it took, and their things to find (LOOT: ammo, pills, scrap, silk,
## now and then a key). It comes home when it's driven off to heal, and now and
## then it's simply there when you come -- still, watching, ready (Stalker:
## State.HOME).
## Every game builds the same nest (the same block, found the same way from
## the Stack's shape; the same seed); the loot is the host's (CarryItems).

const GROUP := "stalker_lair"
## The depths, in the Stack's own space (StackBuilder's).
const DEPTHS_FLOOR := -293.0
const WATER_LEVEL := -290.0
const BLOCK_GRID := 60.0
const LOOT_REACH := 150.0
const SEED := 4321
const AMMO_BOXES := 2
const KEY_CHANCE := 0.5

var _loot_left := true


## Where it is (global): the top of a half-sunk block in the drowned hall
## (the one furthest from the shaft), or INF if there's no Stack here.
static func find_spot(tree: SceneTree) -> Vector3:
	var stack := tree.current_scene.get_node_or_null(^"TheStack") as Node3D if tree.current_scene else null
	if stack == null:
		return Vector3.INF
	var space := stack.get_world_3d().direct_space_state
	var cells: Array[Vector2i] = []
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if gx != 0 or gz != 0:
				cells.append(Vector2i(gx, gz))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() > b.length_squared() or (a.length_squared() == b.length_squared() and (a.x * 10 + a.y) < (b.x * 10 + b.y)))
	for cell in cells:
		var top := stack.to_global(Vector3(cell.x * BLOCK_GRID, DEPTHS_FLOOR + 34.0, cell.y * BLOCK_GRID))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 40.0, 1))
		if hit.is_empty():
			continue
		var local := stack.to_local(hit.position)
		if local.y > WATER_LEVEL + 8.0 and local.y < DEPTHS_FLOOR + 32.0:
			return hit.position
	return Vector3.INF


func _ready() -> void:
	add_to_group(GROUP)
	var dice := RandomNumberGenerator.new()
	dice.seed = SEED
	var world := get_tree().current_scene
	# Bones: heaps of them, and the dark stains they lie in.
	for i in 7:
		var at := global_position + Vector3(dice.randf_range(-6.0, 6.0), 0.0, dice.randf_range(-6.0, 6.0))
		var pile := StalkerSigns.bone_pile(dice)
		add_child(pile)
		pile.global_position = at
		BloodFX.spawn_splatter(world, at + Vector3.UP * 0.3, Vector3.UP, dice.randf_range(1.0, 2.0), Color(0.18, 0.02, 0.02))
	# Torn climbers' clothes.
	for i in 9:
		var cloth := MeshInstance3D.new()
		var piece := BoxMesh.new()
		piece.size = Vector3(dice.randf_range(0.3, 0.8), 0.015, dice.randf_range(0.2, 0.6))
		cloth.mesh = piece
		var look := StandardMaterial3D.new()
		look.albedo_color = StalkerSigns.CLOTH_COLOR.lerp(BloodFX.BLOOD_COLOR, dice.randf_range(0.0, 0.5))
		look.roughness = 1.0
		cloth.material_override = look
		add_child(cloth)
		cloth.position = Vector3(dice.randf_range(-7.0, 7.0), 0.02, dice.randf_range(-7.0, 7.0))
		cloth.rotation.y = dice.randf() * TAU
	# The packs of the climbers it took.
	var pack := BackpackView.pack_mesh()
	for i in 3:
		if pack == null:
			break
		var bag := MeshInstance3D.new()
		bag.mesh = pack
		bag.material_override = BackpackView.pack_material()
		var fit := 0.8 / maxf(pack.get_aabb().get_longest_axis_size(), 0.01)
		add_child(bag)
		bag.scale = Vector3.ONE * fit
		bag.position = Vector3(dice.randf_range(-6.0, 6.0), -pack.get_aabb().position.y * fit, dice.randf_range(-6.0, 6.0))
		bag.rotation = Vector3(dice.randf_range(-0.3, 0.3), dice.randf() * TAU, PI * 0.5 if i == 0 else 0.0)


## The host: its loot, made the first time a player comes near (nothing far
## off costs anything).
func _process(_delta: float) -> void:
	if not _loot_left or (Network.is_online() and not multiplayer.is_server()):
		set_process(false)
		return
	for node in get_tree().get_nodes_in_group("player"):
		if (node as Node3D).global_position.distance_to(global_position) < LOOT_REACH:
			_loot_left = false
			_loot()
			return


func _loot() -> void:
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	var drop := func(data: Dictionary) -> void:
		CarryItem.spawn(get_tree().current_scene, global_position + Vector3(dice.randf_range(-5.0, 5.0), 0.8, dice.randf_range(-5.0, 5.0)), data)
	for i in AMMO_BOXES:
		var shells := dice.randf() < 0.4
		drop.call({kind = Backpack.Kind.SHELLS if shells else Backpack.Kind.BULLETS, amount = StackSecrets.SHELL_BOX if shells else StackSecrets.BULLET_BOX})
	drop.call({kind = Backpack.Kind.PILLS, amount = 1})
	drop.call({kind = Backpack.Kind.SCRAP, amount = dice.randi_range(2, 3)})
	drop.call({kind = Backpack.Kind.SILK, amount = dice.randi_range(1, 2)})
	if dice.randf() < KEY_CHANCE:
		drop.call({kind = Backpack.Kind.KEY, amount = 1})
	set_process(false)
