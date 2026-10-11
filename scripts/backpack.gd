class_name Backpack
extends Node

## The backpack on your back (the user's: everything as diegetic as possible
## -- docs/CLIMB_VISION.md). It holds everything but the gun in your hands:
## the one other gun you may carry, the ammo, pills, bandages, grenades, and
## the climb's materials (scrap, silk) and camp kits.
##   12 STACKS: one stack a kind of thing (6 silk is one stack); a new kind
##   only fits while there's a free stack.
##   WEIGHT: every item weighs something; the heavier the pack, the slower
##   your stamina refills (refill_scale()).
##   USE: an item clicked in the open backpack (BackpackView) is used: pills
##   taken, a bandage wrapped, the spare gun swapped into your hands, a camp
##   kit brought out to place. Materials only sit there: they're for crafting.
## The guns, ammo, pills, bandages and grenades are still counted by the
## WeaponController (they drive the shooting and the healing); the backpack
## is what you see of them, plus the materials it keeps itself.
## Rule 1 (co-op): a click becomes part of the input packet
## (PlayerInput.use_item), so the host runs use() for every player; tick()
## runs inside the player's simulation step.

signal changed

## What a stack is.
enum Kind { NONE = -1, GUN, BULLETS, SHELLS, ROCKETS, GRENADES, PILLS, BANDAGE, SCRAP, SILK, CAMP_KIT }

const MAX_STACKS := 12
## Camp kits: only one on you at a time (the user's).
const MAX_CAMP_KITS := 1
## Weight (kg) of one of each kind; a gun's own weight is GUN_WEIGHT.
const WEIGHTS := {
	Kind.BULLETS: 0.012, Kind.SHELLS: 0.04, Kind.ROCKETS: 2.0, Kind.GRENADES: 0.4,
	Kind.PILLS: 0.05, Kind.BANDAGE: 0.08, Kind.SCRAP: 0.6, Kind.SILK: 0.15, Kind.CAMP_KIT: 3.0,
}
const GUN_WEIGHT := 3.5

## Up to this weight (kg) the pack costs nothing; from there to heavy_at the
## stamina refill slows down to slowest_refill of its normal speed.
@export var free_weight: float = 6.0
@export var heavy_at: float = 22.0
@export_range(0.1, 1.0, 0.05) var slowest_refill: float = 0.45

## The climb's materials and camp kits (the rest is the WeaponController's).
var scrap := 0
var silk := 0
var camp_kits := 0
## True while the camp kit's been brought out to place (the camp builder
## takes it from there).
var placing_camp := false

var _player: PlayerMovement
## refill_scale() worked out at most this often (it counts the whole pack).
const REFILL_EVERY_MSEC := 500
var _refill := 1.0
var _refill_msec := -100000


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	camp_kits = 1 # the user's: you start with one, to make your first camp


## Every stack in the pack: [{kind, count, weapon}] -- weapon only for GUN.
func stacks() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var weapons := _player.weapons
	var held := weapons.current_weapon()
	for weapon in weapons.get_owned_weapons():
		if weapons.is_gun(weapon) and weapon != held:
			found.append({kind = Kind.GUN, count = 1, weapon = weapon})
	for pair: Array in [[Kind.BULLETS, WeaponData.AmmoType.BULLETS], [Kind.SHELLS, WeaponData.AmmoType.SHELLS],
			[Kind.ROCKETS, WeaponData.AmmoType.ROCKETS]]:
		var count := weapons.ammo_of(pair[1])
		if count > 0:
			found.append({kind = pair[0], count = count, weapon = null})
	var grenades := weapons.grenade_count()
	if grenades > 0:
		found.append({kind = Kind.GRENADES, count = grenades, weapon = null})
	for pair: Array in [[Kind.PILLS, weapons.pills], [Kind.BANDAGE, weapons.bandages], [Kind.SCRAP, scrap],
			[Kind.SILK, silk], [Kind.CAMP_KIT, camp_kits]]:
		if pair[1] > 0:
			found.append({kind = pair[0], count = pair[1], weapon = null})
	return found


## Whether something of `kind` fits: its stack's already there, or there's a
## free one (and a camp kit only while you've none).
func has_room_for(kind: Kind) -> bool:
	if kind == Kind.CAMP_KIT and camp_kits >= MAX_CAMP_KITS:
		return false
	var all := stacks()
	for stack in all:
		if stack.kind == kind and kind != Kind.GUN:
			return true
	return all.size() < MAX_STACKS


## Adds materials or camp kits; returns how many it took.
func add(kind: Kind, amount: int) -> int:
	if amount <= 0 or not has_room_for(kind):
		return 0
	match kind:
		Kind.SCRAP:
			scrap += amount
		Kind.SILK:
			silk += amount
		Kind.CAMP_KIT:
			amount = mini(amount, MAX_CAMP_KITS - camp_kits)
			camp_kits += amount
		_:
			return 0
	changed.emit()
	return amount


## Takes materials away (crafting); false (and nothing taken) if short.
func take(kind: Kind, amount: int) -> bool:
	match kind:
		Kind.SCRAP:
			if scrap < amount:
				return false
			scrap -= amount
		Kind.SILK:
			if silk < amount:
				return false
			silk -= amount
		Kind.CAMP_KIT:
			if camp_kits < amount:
				return false
			camp_kits -= amount
		_:
			return false
	changed.emit()
	return true


## How heavy the pack is, in kg.
func weight() -> float:
	var total := 0.0
	for stack in stacks():
		total += GUN_WEIGHT if stack.kind == Kind.GUN else float(WEIGHTS.get(stack.kind, 0.0)) * stack.count
	return total


## How fast stamina refills for this weight (1 = normal; recounted twice a
## second, not every tick).
func refill_scale() -> float:
	var now := Time.get_ticks_msec()
	if now - _refill_msec >= REFILL_EVERY_MSEC:
		_refill_msec = now
		var heavy := clampf(inverse_lerp(free_weight, heavy_at, weight()), 0.0, 1.0)
		_refill = lerpf(1.0, slowest_refill, heavy)
	return _refill


## Uses a stack (a click in the open backpack, from the input packet).
func use(kind: Kind) -> void:
	var weapons := _player.weapons
	match kind:
		Kind.PILLS:
			weapons.use_item(WeaponController.Item.PILLS)
		Kind.BANDAGE:
			weapons.use_item(WeaponController.Item.BANDAGE)
		Kind.GUN:
			weapons.swap_to_spare_gun()
		Kind.GRENADES:
			weapons.equip_grenades()
		Kind.CAMP_KIT:
			if camp_kits > 0:
				placing_camp = true
				changed.emit()
		_:
			pass # materials, ammo: nothing to do with them by hand
