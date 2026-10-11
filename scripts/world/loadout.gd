class_name Loadout
extends Node

## Hands the player(s) a full loadout as a scene starts (the open-world
## test: every weapon, grenades, plenty of ammo, full heals) -- through the
## same calls pickups use (WeaponController.pickup_weapon / add_ammo /
## add_item), so nothing about it is special-cased. Then back to the first
## weapon in hand.

@export var weapons: Array[WeaponData] = [
	preload("res://weapons/starter_gun.tres"),
	preload("res://weapons/revolver.tres"),
	preload("res://weapons/uzi.tres"),
	preload("res://weapons/uzi.tres"), # the second: dual Uzis
	preload("res://weapons/ppsh.tres"),
	preload("res://weapons/shotgun.tres"),
	preload("res://weapons/machine_gun.tres"),
	preload("res://weapons/pkm.tres"),
	preload("res://weapons/sniper.tres"),
	preload("res://weapons/rpg.tres"),
	preload("res://weapons/grenade.tres"),
]
## Ammo on top: bullets, shells, rockets, grenades.
@export var bullets: int = 900
@export var shells: int = 120
@export var rockets: int = 24
@export var grenades: int = 12


func _ready() -> void:
	_give.call_deferred()
	# Co-op: a body made later (someone joining) gets its loadout too.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is PlayerMovement:
			_give_later.call_deferred(node)
	)


func _give() -> void:
	await get_tree().process_frame # the players' own setup first
	for node in get_tree().get_nodes_in_group("player"):
		_give_to(node)


func _give_later(node: Node) -> void:
	await get_tree().process_frame
	if is_instance_valid(node):
		_give_to(node)


func _give_to(node: Node) -> void:
	var controller := node.get_node_or_null(^"WeaponController") as WeaponController
	if controller == null:
		return
	if controller.has_meta(&"loadout_given"):
		return
	controller.set_meta(&"loadout_given", true)
	for weapon in weapons:
		controller.pickup_weapon(weapon, 0)
	controller.add_ammo(WeaponData.AmmoType.BULLETS, bullets)
	controller.add_ammo(WeaponData.AmmoType.SHELLS, shells)
	controller.add_ammo(WeaponData.AmmoType.ROCKETS, rockets)
	controller.add_ammo(WeaponData.AmmoType.GRENADES, grenades)
	controller.add_item(WeaponController.Item.PILLS, controller.max_pills)
	controller.add_item(WeaponController.Item.BANDAGE, controller.max_bandages)
	controller.call("_select", 0) # the first weapon back in hand
