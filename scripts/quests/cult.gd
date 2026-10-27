class_name Cult
extends RefCounted

## The cult (the user's, 2026-10-27; docs/QUESTS_TRADERS_WALKERS.md): hooded
## humans in dirty oxblood robes -- the same humans as the rest (melee,
## gunners, rushers), their own side (Factions.Side.CULT). They attack on
## sight unless the group's sided with them (the Bounty: Cult.sided()).
##   CAMPS: CAMPS of them out in the wilds, rolled per world (Quests.world_dice),
##   each a smaller flesh-root altar (QuestProps.altar) and a fire, CAMP_PEOPLE
##   cultists round it (CultCamp).
##   AMBUSHES: refuse the shrine cultist (Feed the Tree) and now and then --
##   about every AMBUSH_EVERY -- AMBUSH_PEOPLE of them close in on you from out
##   of sight (QuestWorld).
## Rule 1 (co-op): the host's; the cultists are Enemies (NetEntities), their
## robes put on in every game (Enemy.cult).

const ROBE := Color(0.3, 0.06, 0.06)
const ROBE_DARK := Color(0.12, 0.03, 0.03)
const SCENES := ["res://scenes/enemy/enemy.tscn", "res://scenes/enemy/enemy_gunner.tscn", "res://scenes/enemy/enemy_rusher.tscn"]
const CAMPS := 3
const CAMP_PEOPLE := Vector2i(4, 6)
const CAMP_REACH := Vector2(700.0, 2600.0)
const AMBUSH_EVERY := Vector2(1500.0, 2100.0) # (the user's: about every half hour)
const AMBUSH_PEOPLE := Vector2i(4, 6)
const AMBUSH_FROM := Vector2(60.0, 90.0)
const SIGHT := 120.0


## The group's sided with them (the Bounty done the right way): they leave you be.
static func sided() -> bool:
	return bool(WorldFacts.get_fact(&"cult.sided", false))


## They're after you (the shrine cultist refused you, or you refused him).
static func hunting() -> bool:
	return bool(WorldFacts.get_fact(&"cult.ambush", false)) and not sided()


## The host: one of them, at `at` -- a random one of the humans, robed.
static func cultist(scene: Node, at: Vector3) -> Enemy:
	var path: String = SCENES.pick_random()
	if not ResourceLoader.exists(path):
		return null
	var one := (load(path) as PackedScene).instantiate() as Enemy
	one.cult = true
	one.can_mutate = false
	one.sight_range = SIGHT
	scene.add_child(one)
	one.global_position = at
	return one


## Its robe and hood (every game): a long robe hung from its chest, a deep
## pointed hood over its head, its face a shadow.
static func robe_up(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.has_node(^"CultRobe"):
		return
	var fit := maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	var chest := BoneAttachment3D.new()
	chest.name = "CultRobe"
	chest.bone_name = "Chest" if skeleton.find_bone("Chest") >= 0 else "Spine"
	skeleton.add_child(chest)
	var robe := MeshInstance3D.new()
	var cloth := CylinderMesh.new()
	cloth.top_radius = 0.2
	cloth.bottom_radius = 0.38
	cloth.height = 1.35
	cloth.radial_segments = 10
	cloth.rings = 2
	cloth.cap_bottom = false
	robe.mesh = cloth
	robe.material_override = robe_material()
	robe.scale = Vector3.ONE / fit
	robe.position = Vector3(0.0, -0.5, 0.0) / fit
	chest.add_child(robe)
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	skeleton.add_child(head)
	var hood := Node3D.new()
	hood.scale = Vector3.ONE / fit
	head.add_child(hood)
	var cowl := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.17
	cone.height = 0.42
	cone.radial_segments = 10
	cone.rings = 2
	cone.cap_bottom = false
	cowl.mesh = cone
	cowl.material_override = robe_material()
	cowl.position = Vector3(0.0, 0.12, 0.03)
	cowl.rotation.x = -0.25
	hood.add_child(cowl)
	var shadow := MeshInstance3D.new()
	var face := SphereMesh.new()
	face.radius = 0.11
	face.height = 0.2
	shadow.mesh = face
	shadow.material_override = QuestProps.material(Color(0.02, 0.01, 0.01))
	shadow.position = Vector3(0.0, 0.05, 0.05)
	hood.add_child(shadow)


static var _robe: StandardMaterial3D


static func robe_material() -> StandardMaterial3D:
	if _robe == null:
		_robe = StandardMaterial3D.new()
		_robe.albedo_color = ROBE
		_robe.roughness = 1.0
		_robe.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _robe


## The host: AMBUSH_PEOPLE of them closing in on `player` from out of sight.
static func ambush(player: PlayerMovement) -> void:
	var scene := player.get_tree().current_scene
	var look := -player.head.global_basis.z
	var count := randi_range(AMBUSH_PEOPLE.x, AMBUSH_PEOPLE.y)
	var made := 0
	for attempt in count * 6:
		if made >= count:
			break
		var out := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
		if out.dot(look) > 0.0:
			continue # (behind you, out of sight)
		var at := player.global_position + out * randf_range(AMBUSH_FROM.x, AMBUSH_FROM.y)
		var ground := QuestWorld.ground_at(player.get_tree(), at)
		if not ground.is_finite():
			continue
		var one := cultist(scene, ground + Vector3.UP * 0.2)
		if one:
			one.hunt(player)
			made += 1
