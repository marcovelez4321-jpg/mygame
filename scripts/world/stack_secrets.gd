class_name StackSecrets
extends Node

## What the Stack's secrets hold, rolled anew each play (the user's,
## 2026-10-17; the places are StackBuilder's, on the Megastructure):
##   LOOT ROOMS behind the secret doors, each: 1-2 boxes of ammo, pills half
##   the time, 1-3 scrap, 0-2 silk, a gun 15% of the time, a key 3%.
##   KEYS: HALL_KEYS lying on hall floors, CLIMBER_KEYS on dead climbers
##   (a person who settled where they fell, with an abandoned camp beside
##   them CLIMBER_CAMP of the time), and one in WINDOW_ROOM_KEY of the
##   window rooms.
## Everything's made only once a player first comes within SPAWN_REACH of
## it (nothing far off costs anything) and stays till taken.
## Rule 1 (co-op): the host's; what it makes are normal items (CarryItem,
## seen through NetEntities).

const HALL_KEYS := 28 # the user's: doubled (was 14)
const CLIMBER_KEYS := 4
const WINDOW_ROOM_KEY := 0.08
const CLIMBER_CAMP := 0.3
const SPAWN_REACH := 150.0
const CHECK_EVERY := 1.0
## Loot (the user's: modest).
const AMMO_BOXES := Vector2i(1, 2)
const BULLET_BOX := 30
const SHELL_BOX := 8
const PILL_CHANCE := 0.5
const SCRAP := Vector2i(1, 3)
const SILK := Vector2i(0, 2)
const GUN_CHANCE := 0.15
const KEY_CHANCE := 0.03
const GUNS := ["res://weapons/starter_gun.tres", "res://weapons/shotgun.tres", "res://weapons/machine_gun.tres"]
const CLIMBER := preload("res://scenes/enemy/enemy.tscn")

## Each place to fill: {at (local), what: "loot"/"key"/"climber", box (loot)}.
var _sites: Array[Dictionary] = []
var _stack: Megastructure
var _check_left := 0.0


func _ready() -> void:
	_stack = get_parent() as Megastructure
	if _stack == null or (Network.is_online() and not multiplayer.is_server()):
		set_process(false)
		return
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	for room in _stack.secret_rooms:
		_sites.append({at = room.get_center(), what = "loot", box = room})
	var spots := Array(_stack.secret_keys)
	_shuffle(spots, dice)
	for i in mini(HALL_KEYS, spots.size()):
		_sites.append({at = spots[i], what = "key"})
	var climbers := Array(_stack.secret_climbers)
	_shuffle(climbers, dice)
	for i in mini(CLIMBER_KEYS, climbers.size()):
		_sites.append({at = climbers[i], what = "climber"})
	for room in _stack.room_boxes:
		if dice.randf() < WINDOW_ROOM_KEY:
			_sites.append({at = Megastructure._on_room_floor(dice, room), what = "key"})


static func _shuffle(list: Array, dice: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := dice.randi_range(0, i)
		var keep: Variant = list[i]
		list[i] = list[j]
		list[j] = keep


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or _sites.is_empty():
		return
	_check_left = CHECK_EVERY
	var players := get_tree().get_nodes_in_group("player")
	var reach_sq := SPAWN_REACH * SPAWN_REACH
	for i in range(_sites.size() - 1, -1, -1):
		var site: Dictionary = _sites[i]
		var at := _stack.to_global(site.at)
		for node in players:
			if (node as Node3D).global_position.distance_squared_to(at) < reach_sq:
				_fill(site)
				_sites.remove_at(i)
				break


func _fill(site: Dictionary) -> void:
	match site.what:
		"loot":
			_loot(site.box)
		"key":
			_item(_stack.to_global(site.at) + Vector3.UP * 0.5, {kind = Backpack.Kind.KEY, amount = 1})
		"climber":
			_climber(_stack.to_global(site.at))


func _loot(box: AABB) -> void:
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	var drop := func(data: Dictionary) -> void:
		var local := Megastructure._on_room_floor(dice, box) + Vector3.UP * 0.6
		_item(_stack.to_global(local), data)
	for i in dice.randi_range(AMMO_BOXES.x, AMMO_BOXES.y):
		var shells := dice.randf() < 0.4
		drop.call({kind = Backpack.Kind.SHELLS if shells else Backpack.Kind.BULLETS, amount = SHELL_BOX if shells else BULLET_BOX})
	if dice.randf() < PILL_CHANCE:
		drop.call({kind = Backpack.Kind.PILLS, amount = 1})
	var scrap := dice.randi_range(SCRAP.x, SCRAP.y)
	if scrap > 0:
		drop.call({kind = Backpack.Kind.SCRAP, amount = scrap})
	var silk := dice.randi_range(SILK.x, SILK.y)
	if silk > 0:
		drop.call({kind = Backpack.Kind.SILK, amount = silk})
	if dice.randf() < GUN_CHANCE:
		var gun: String = GUNS[dice.randi() % GUNS.size()]
		var weapon := load(gun) as WeaponData
		drop.call({kind = Backpack.Kind.GUN, amount = weapon.magazine_size if weapon else 6, weapon = gun})
	if dice.randf() < KEY_CHANCE:
		drop.call({kind = Backpack.Kind.KEY, amount = 1})


func _item(at: Vector3, data: Dictionary) -> void:
	CarryItem.spawn(get_tree().current_scene, at, data)


## A climber who didn't make it: a person let fall where they died (their
## own ragdoll, which settles and sleeps), a key on them, and now and then
## the camp they never got to leave.
func _climber(at: Vector3) -> void:
	var body := CLIMBER.instantiate() as Enemy
	body.can_mutate = false
	body.corpse_time = 1.0e9 # stays (and isn't counted with the fights' bodies)
	body.set_meta(&"climber", true)
	body.set_meta(&"culled", true) # nothing to drop
	get_tree().current_scene.add_child(body)
	body.global_position = at + Vector3.UP * 0.2
	body.rotation.y = randf() * TAU
	var health := body.get_node(^"Health") as Health
	health.take_damage(health.current_health + 1.0)
	_item(at + Vector3.UP * 1.2, {kind = Backpack.Kind.KEY, amount = 1})
	if randf() < CLIMBER_CAMP:
		var turn := randf() * TAU
		var camp_at := at + Vector3(cos(turn), 0.0, sin(turn)) * 5.0
		var camp := Camp.build(get_tree().current_scene, Transform3D(Basis(Vector3.UP, turn + PI), camp_at), randi() % Camp.TENTS.size(), true)
		camp.name = "AbandonedCamp"