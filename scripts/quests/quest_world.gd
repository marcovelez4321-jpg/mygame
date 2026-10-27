class_name QuestWorld
extends Node

## Where the quest web's people and things are (the user's, 2026-10-27;
## Quests). The host places them as the level starts -- rolled per world
## (Quests.world_dice: the same every session) where the user said "per
## world" -- and keeps the quests moving:
##   the shrine cultist at the flesh-root altar (SHRINE_REACH out in the
##   wilds), the cult's camps (Cult.CAMPS), the bounty man at his fire
##   (BOUNTY_REACH), Mara beside the torn-banner trader, the Fanatic on the
##   1.4 km tower (higher each session), the climber at the tallest tower's
##   foot (his letter on him) and his cold camp at CLIMBER_CAMP up it, the
##   summit cairn on its top; the skull on the Stalker's pile and the
##   Fanatic's parts about the Stack while their quests want them.
##   Each tick (CHECK_EVERY): an offering dropped in its home taken, a skull
##   carried out of it with none left (its fury), the climber's camp found,
##   the cult's ambushes; a camp made with a gift due (the gun by the bed).
## Every game: the Fanatic going off (Network quest events), the tower's top
## coming off (stack.top_gone: StackCollapse), the Tree fed (its roots, the
## weed).

const GROUP := &"quest_world"
const CHECK_EVERY := 1.0
const SHRINE_REACH := Vector2(600.0, 1500.0) # (the user's)
const BOUNTY_REACH := Vector2(800.0, 2200.0)
const CLIMBER_CAMP := 1000.0 # (the user's: 1 km)
const TALLEST := 0 # (StackBuilder.TOWERS: the main tower)
const FANATIC_TOWER := 4 # (StackBuilder.TOWERS: the 1.4 km tower)
const LAIR_IN := 60.0
const LAIR_OUT := 90.0
## The rare guns the Stalker's gift can be (the user's), with their ammo.
const GIFT_GUNS := [["res://weapons/shotgun.tres", Backpack.Kind.SHELLS, 16],
		["res://weapons/sniper.tres", Backpack.Kind.BULLETS, 30],
		["res://weapons/pkm.tres", Backpack.Kind.BULLETS, 120],
		["res://weapons/rpg.tres", Backpack.Kind.ROCKETS, 3]]
## The climber's camp's light gun (the user's: rolled per world).
const LIGHT_GUNS := ["res://weapons/starter_gun.tres", "res://weapons/revolver.tres", "res://weapons/uzi.tres"]

var _check_left := 2.0
var _ambush_left := 0.0
var _skull_inside := {}
var _climber_camp_at := Vector3.INF
var _mara_placed := false
var _skull_placed := false
var _parts_placed := false


static func ensure(tree: SceneTree) -> void:
	if tree.current_scene == null or not tree.get_nodes_in_group(GROUP).is_empty():
		return
	var world := QuestWorld.new()
	world.name = "QuestWorld"
	tree.current_scene.add_child(world)


func _ready() -> void:
	add_to_group(GROUP)
	Network.fact_changed.connect(_on_fact)
	Network.quest_event.connect(_on_event)
	tree_node_added_hook()
	_ambush_left = randf_range(Cult.AMBUSH_EVERY.x, Cult.AMBUSH_EVERY.y)
	if WorldFacts.get_fact(&"stack.top_gone", false):
		StackCollapse.apply.call_deferred(get_tree(), false)
	if _decides():
		_place.call_deferred()


func _decides() -> bool:
	return not Network.is_online() or multiplayer.is_server()


func tree_node_added_hook() -> void:
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Camp and _decides():
			_camp_made.call_deferred(node))


# ---- Placing (the host's, once a level) ------------------------------------------------

func _place() -> void:
	var scene := get_tree().current_scene
	var house := scene.get_node_or_null(^"GrandmasHouse") as Node3D
	var stack := scene.get_node_or_null(^"TheStack") as Megastructure
	Quests.world_seed()
	Quests.torn_trader()
	# A new session: the Fanatic's higher (the user's).
	if Quests.state(Quests.FANATIC) != Quests.State.DONE:
		Network.send_fact(&"fanatic.sessions", int(WorldFacts.get_fact(&"fanatic.sessions", 0)) + 1)
	if house:
		var home := house.global_position
		# The shrine cultist at his altar.
		var dice := Quests.world_dice(101)
		var at := ground_at(get_tree(), home + Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU) * dice.randf_range(SHRINE_REACH.x, SHRINE_REACH.y))
		if at.is_finite():
			_npc(&"shrine", at, home)
		# The cult's camps, spread round.
		dice = Quests.world_dice(102)
		var start := dice.randf() * TAU
		for i in Cult.CAMPS:
			var turn := start + TAU * i / Cult.CAMPS + dice.randf_range(-0.4, 0.4)
			var spot := ground_at(get_tree(), home + Vector3.FORWARD.rotated(Vector3.UP, turn) * dice.randf_range(Cult.CAMP_REACH.x, Cult.CAMP_REACH.y))
			if spot.is_finite():
				var camp := CultCamp.new()
				camp.camp_seed = hash([Quests.world_seed(), i])
				scene.add_child(camp)
				camp.global_position = spot
		# The bounty man at his fire (or, dead, his note where he fell).
		dice = Quests.world_dice(103)
		var fire := ground_at(get_tree(), home + Vector3.FORWARD.rotated(Vector3.UP, dice.randf() * TAU) * dice.randf_range(BOUNTY_REACH.x, BOUNTY_REACH.y))
		if fire.is_finite():
			if not Quests.flag("bounty.dead"):
				_npc(&"bounty", fire, home)
			elif not Quests.flag("cult.note_read"):
				QuestNote.drop(get_tree(), fire + Vector3.UP * 0.6, &"cult_note")
	if stack:
		_place_on_stack(stack)


func _place_on_stack(stack: Megastructure) -> void:
	var scene := get_tree().current_scene
	var columns := stack.nest_columns
	if columns.size() <= FANATIC_TOWER:
		return
	var tallest := columns[TALLEST]
	var half := float(StackBuilder.TOWERS[TALLEST][2]) * 0.5
	# The climber where he fell: at the tallest tower's foot, on the house's side.
	var house := scene.get_node_or_null(^"GrandmasHouse") as Node3D
	var toward := stack.to_local(house.global_position) if house else Vector3.FORWARD * 1000.0
	toward = Vector3(toward.x, 0.0, toward.z).normalized()
	var foot := ground_at(get_tree(), stack.to_global(Vector3(tallest.x, 0.0, tallest.z) + toward * (half + 6.0)))
	if foot.is_finite():
		var body := QuestDecor.new()
		body.kind = QuestDecor.CLIMBER_BODY
		scene.add_child(body)
		body.global_position = foot
		if Quests.state(Quests.TAGS) == Quests.State.NOT_STARTED:
			QuestNote.drop(get_tree(), foot + Vector3.UP * 0.4, &"climber_letter")
	# His camp, a kilometre up it (once found, his things are yours to take).
	if not Quests.flag("climber.camp_found"):
		var spot := tower_spot(stack, TALLEST, CLIMBER_CAMP, Quests.world_dice(104))
		if spot.is_finite():
			_climber_camp_at = spot
			var camp := Camp.build(scene, Transform3D(Basis(Vector3.UP, Quests.world_dice(105).randf() * TAU), spot), 0, true)
			_climber_loot(camp)
	# The summit cairn.
	var top := stack.to_global(Vector3(tallest.x, tallest.y + 80.0, tallest.z))
	var hit := stack.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 300.0, 1))
	if not hit.is_empty():
		var cairn := QuestDecor.new()
		cairn.kind = QuestDecor.CAIRN
		scene.add_child(cairn)
		cairn.global_position = hit.position
	# The Fanatic (unless he's gone: up with his bomb, or blown).
	var outcome := str(WorldFacts.get_fact(WorldFacts.quest(Quests.FANATIC, "outcome"), ""))
	if outcome in ["", "talked_down"] and not Quests.flag("fanatic.dead"):
		var height := Quests.fanatic_height() if outcome == "" else float(WorldFacts.get_fact(&"fanatic.stopped_at", Quests.fanatic_height()))
		Network.send_fact(&"fanatic.stopped_at", height)
		var dice := RandomNumberGenerator.new()
		dice.randomize()
		var spot := tower_spot(stack, FANATIC_TOWER, height, dice)
		if spot.is_finite():
			_npc(&"fanatic", spot, stack.to_global(Vector3(columns[FANATIC_TOWER].x, spot.y, columns[FANATIC_TOWER].z)))


## His camp's things (the user's): a light gun rolled per world, its ammo,
## pills, bandages and a camp kit, by his cold fire and bedroll.
func _climber_loot(camp: Camp) -> void:
	var dice := Quests.world_dice(106)
	var gun_path: String = LIGHT_GUNS[dice.randi() % LIGHT_GUNS.size()]
	var gun := load(gun_path) as WeaponData if ResourceLoader.exists(gun_path) else null
	var things := [{kind = Backpack.Kind.GUN, weapon = gun_path, amount = gun.magazine_size if gun else 6},
			{kind = Backpack.Kind.BULLETS, amount = 30}, {kind = Backpack.Kind.PILLS, amount = 2},
			{kind = Backpack.Kind.BANDAGE, amount = 2}, {kind = Backpack.Kind.CAMP_KIT, amount = 1}]
	for i in things.size():
		var at := camp.global_transform * (Camp.BED_AT + Vector3(-0.6 + i * 0.4, 0.5, -0.8))
		CarryItem.spawn(get_tree().current_scene, at, things[i])


func _npc(role: StringName, at: Vector3, facing: Vector3) -> QuestNpc:
	var npc := QuestNpc.new()
	npc.role = role
	get_tree().current_scene.add_child(npc)
	npc.global_position = at
	var look := Vector3(facing.x - at.x, 0.0, facing.z - at.z)
	if look.length_squared() > 0.01:
		npc.global_basis = Basis.looking_at(look.normalized(), Vector3.UP)
	return npc


## A spot up tower `index` near `height` (m above the Stack's foot): open
## ground on it (rays down within its footprint), else a room near there.
## INF if there's none.
static func tower_spot(stack: Megastructure, index: int, height: float, dice: RandomNumberGenerator) -> Vector3:
	var column := stack.nest_columns[index]
	var reach := float(StackBuilder.TOWERS[index][2]) * 0.75
	var space := stack.get_world_3d().direct_space_state
	var found: Array[Vector3] = []
	for i in 300:
		var local := Vector3(column.x + dice.randf_range(-reach, reach), height + 40.0, column.z + dice.randf_range(-reach, reach))
		var from := stack.to_global(local)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 120.0, 1))
		if hit.is_empty() or (hit.normal as Vector3).y < 0.9:
			continue
		if absf(stack.to_local(hit.position).y - height) < 70.0:
			found.append(hit.position)
	if found.is_empty():
		for room in stack.room_boxes:
			if absf(room.get_center().y - height) < 100.0 and Vector2(room.get_center().x - column.x, room.get_center().z - column.z).length() < reach * 1.5:
				found.append(stack.to_global(Megastructure._on_room_floor(dice, room)))
	if found.is_empty():
		return Vector3.INF
	return found[dice.randi() % found.size()]


# ---- Each tick (the host's) --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _decides():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	_mara()
	_lair()
	_fanatic_parts()
	if _climber_camp_at.is_finite() and anyone_within(get_tree(), _climber_camp_at, 8.0):
		Network.send_fact(&"climber.camp_found", true)
		_climber_camp_at = Vector3.INF
	if Cult.hunting():
		_ambush_left -= CHECK_EVERY
		if _ambush_left <= 0.0:
			_ambush_left = randf_range(Cult.AMBUSH_EVERY.x, Cult.AMBUSH_EVERY.y)
			var players := get_tree().get_nodes_in_group("player").filter(func(node: Node) -> bool:
				return node is PlayerMovement and not (node as PlayerMovement).is_dead())
			if not players.is_empty():
				Cult.ambush(players.pick_random() as PlayerMovement)


## Mara beside the torn-banner trader once he's out (or by his wreck).
func _mara() -> void:
	if _mara_placed:
		return
	var id := Quests.torn_trader()
	for node in Traders._all:
		if is_instance_valid(node) and str(node.get(&"trader_id")) == id:
			_mara_placed = true
			_npc(&"mara", (node as Node3D).global_transform * QuestNpc.BESIDE, (node as Node3D).global_position)
			return
	var wreck: Variant = WorldFacts.get_fact(StringName("trader.%s.wreck" % id), null)
	if wreck is Vector3:
		_mara_placed = true
		_npc(&"mara", (wreck as Vector3) + Vector3(3.0, 0.0, 0.0), wreck)


## The Stalker's home: the skull on its pile while Bones for the Voice wants
## one; an offering dropped there taken; a skull carried out with none left.
func _lair() -> void:
	var lair := get_tree().get_first_node_in_group(StalkerLair.GROUP) as StalkerLair
	if lair == null:
		return
	var home := lair.global_position
	if not _skull_placed and Quests.state(Quests.VOICE) == Quests.State.ACTIVE and not _anyone_has(Backpack.Kind.SKULL):
		_skull_placed = true
		CarryItem.spawn(get_tree().current_scene, lair.trophy_spot() + Vector3(1.2, 0.0, 0.0), {kind = Backpack.Kind.SKULL, amount = 1})
	# An offering left (dropped: G) in its home.
	for node in get_tree().get_nodes_in_group(&"carry_items"):
		var item := node as CarryItem
		if item and item.kind == Backpack.Kind.OFFERING and item.global_position.distance_to(home) < LAIR_IN and not item.has_meta(&"fetched"):
			Network.send_fact(&"stalker.offering", true)
			Network.send_fact(&"stalker.gift_due", true)
			var left := QuestDecor.new()
			left.kind = QuestDecor.OFFERING
			get_tree().current_scene.add_child(left)
			left.global_position = item.global_position
			item.queue_free()
	# A skull carried out of its home with no offering left: its fury.
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var peer := player.get_multiplayer_authority()
		var gap := player.global_position.distance_to(home)
		if not Quests.has(player, Backpack.Kind.SKULL):
			_skull_inside.erase(peer)
			continue
		if gap < LAIR_IN:
			_skull_inside[peer] = true
		elif gap > LAIR_OUT and _skull_inside.get(peer, false):
			_skull_inside.erase(peer)
			if not Quests.flag("stalker.offering") and not Quests.flag("voice.fury"):
				Network.send_fact(&"voice.fury", true)
				var stalker := get_tree().get_first_node_in_group(&"stalker")
				if stalker and stalker.has_method(&"enrage"):
					stalker.call(&"enrage", peer, Quests.NO_OFFERING_FURY)


## The Fanatic's three parts about the Stack while he wants them.
func _fanatic_parts() -> void:
	if _parts_placed or Quests.state(Quests.FANATIC) != Quests.State.ACTIVE:
		return
	var stack := get_tree().current_scene.get_node_or_null(^"TheStack") as Megastructure
	if stack == null or stack.room_boxes.is_empty():
		return
	_parts_placed = true
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	for kind: int in Quests.BOMB_PARTS:
		if Quests.part_given(kind) or _anyone_has(kind):
			continue
		var room: AABB = stack.room_boxes[dice.randi() % stack.room_boxes.size()]
		CarryItem.spawn(get_tree().current_scene, stack.to_global(Megastructure._on_room_floor(dice, room)) + Vector3.UP * 0.5, {kind = kind, amount = 1})


## A camp made (the host's): with a gift due (an offering left), the gun's
## by its bed (the user's: instead of the usual signs).
func _camp_made(node: Node) -> void:
	var camp := node as Camp
	if camp == null or not is_instance_valid(camp) or camp.abandoned or not Quests.flag("stalker.gift_due"):
		return
	Network.send_fact(&"stalker.gift_due", false)
	var pick: Array = GIFT_GUNS.pick_random()
	var gun := load(str(pick[0])) as WeaponData if ResourceLoader.exists(str(pick[0])) else null
	CarryItem.spawn(get_tree().current_scene, camp.global_transform * (Camp.BED_AT + Vector3(0.9, 0.5, 0.0)),
			{kind = Backpack.Kind.GUN, weapon = pick[0], amount = gun.magazine_size if gun else 6})
	CarryItem.spawn(get_tree().current_scene, camp.global_transform * (Camp.BED_AT + Vector3(0.9, 0.5, 0.6)),
			{kind = pick[1], amount = pick[2]})


func _anyone_has(kind: int) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and Quests.has(player, kind):
			return true
	for node in get_tree().get_nodes_in_group(&"carry_items"):
		if node is CarryItem and (node as CarryItem).kind == kind:
			return true
	return false


# ---- Every game --------------------------------------------------------------------------

func _on_fact(name: StringName, value: Variant) -> void:
	match name:
		&"stack.top_gone":
			if value:
				StackCollapse.apply(get_tree(), true)
		&"tree.fed":
			if value:
				FleshTree.refresh()
				for weed in get_tree().get_nodes_in_group(&"red_weed"):
					weed.call(&"regrow")


func _on_event(event: StringName, _at: Vector3) -> void:
	if event == &"kamikaze":
		for node in get_tree().get_nodes_in_group(&"quest_npcs"):
			var npc := node as QuestNpc
			if npc and npc.role == &"fanatic":
				npc.go_off()


# ---- Helpers ----------------------------------------------------------------------------

## The ground under `at`: the terrain's height, else a ray down; INF if none.
static func ground_at(tree: SceneTree, at: Vector3) -> Vector3:
	var terrain := tree.current_scene.get_node_or_null(^"Terrain3D") if tree.current_scene else null
	if terrain:
		var data: Object = terrain.get(&"data")
		if data and data.has_method(&"get_height"):
			var height: float = data.call(&"get_height", at)
			if not is_nan(height):
				return Vector3(at.x, height, at.z)
	var world := tree.current_scene as Node3D
	if world == null:
		return Vector3.INF
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 500.0, at + Vector3.DOWN * 500.0, 1))
	return hit.position if not hit.is_empty() else Vector3.INF


static func anyone_within(tree: SceneTree, at: Vector3, reach: float) -> bool:
	for node in tree.get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(at) < reach:
			return true
	return false
