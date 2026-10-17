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
enum Kind { NONE = -1, GUN, BULLETS, SHELLS, ROCKETS, GRENADES, PILLS, BANDAGE, SCRAP, SILK, CAMP_KIT,
		MEAT, ROTTEN_MEAT, COOKED_MEAT, GLUED_MEAT, GLUED_COOKED, KEY }

const MAX_STACKS := 12
## Camp kits: only one on you at a time (the user's).
const MAX_CAMP_KITS := 1
## Weight (kg) of one of each kind; a gun weighs its own (WeaponData.carry_weight).
const WEIGHTS := {
	Kind.BULLETS: 0.012, Kind.SHELLS: 0.04, Kind.ROCKETS: 2.0, Kind.GRENADES: 0.4,
	Kind.PILLS: 0.05, Kind.BANDAGE: 0.08, Kind.SCRAP: 0.6, Kind.SILK: 0.15, Kind.CAMP_KIT: 3.0, Kind.KEY: 0.02,
}

## Up to free_weight (kg) the pack costs nothing ("overweight" past it: the
## weight shows over the open bag); from there to heavy_at ("too heavy": the
## number goes red) it drags on you more and more, worst at heavy_at (the
## user's: all of these):
@export var free_weight: float = 6.0
@export var heavy_at: float = 22.0
## Stamina refills this much as fast at the worst...
@export_range(0.1, 1.0, 0.05) var slowest_refill: float = 0.45
## ... you walk and run this much as fast...
@export_range(0.1, 1.0, 0.05) var slowest_move: float = 0.8
## ... you jump (and wall jump) this much as high...
@export_range(0.1, 1.0, 0.05) var lowest_jump: float = 0.85
## ... the grapple pulls you this much as fast (and builds up as slowly)...
@export_range(0.1, 1.0, 0.05) var slowest_pull: float = 0.8
## ... and holding on drains stamina this many times as fast.
@export_range(1.0, 3.0, 0.05) var heaviest_drain: float = 1.5

## The climb's materials and camp kits (the rest is the WeaponController's).
var scrap := 0
var silk := 0
var camp_kits := 0
## Keys for the Stack's key doors (SecretDoor): any key, any key door; used up.
var keys := 0
## Meat chunks (CarryItem.to_data(): their weight, boss or not, when they
## rot, cooked or not). They go on rotting in here (the user's).
var meat: Array[Dictionary] = []
## True while the camp kit's been brought out to place (the camp builder
## takes it from there).
var placing_camp := false

var _player: PlayerMovement
## How heavy it is worked out at most this often (it counts the whole pack).
const WEIGH_EVERY_MSEC := 500
var _weight := 0.0
var _weighed_msec := -100000


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	camp_kits = 1 # the user's: you start with one, to make your first camp
	changed.connect(_send_meat)


## The meat in here goes on aging (rotting) -- the host's, in
## CarryItem.AGE_EVERY steps (the user's: every couple of minutes).
var _age_left := CarryItem.AGE_EVERY


func _physics_process(delta: float) -> void:
	if meat.is_empty() or (Network.is_online() and not multiplayer.is_server()):
		return
	_age_left -= delta
	if _age_left > 0.0:
		return
	_age_left += CarryItem.AGE_EVERY
	var turned := false
	for chunk in meat:
		turned = CarryItem.grow_old(chunk, CarryItem.AGE_EVERY) or turned
	if turned:
		changed.emit() # one went off: it moves to the rotten stack


## Co-op: the host tells the owner what meat's in their pack (it's made and
## eaten on the host).
func _send_meat() -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority():
		_net_meat.rpc_id(_player.get_multiplayer_authority(), meat)


@rpc("any_peer", "call_remote", "reliable")
func _net_meat(new_meat: Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	meat.assign(new_meat)
	changed.emit()


## Every stack in the pack: [{kind, count, weapon}] -- weapon only for GUN.
func stacks() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var weapons := _player.weapons
	# A gun's in the bag unless it's in your hands (stowed with F, or put
	# away for something in your right hand: both can be in here).
	var held := weapons.gun_in_hand()
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
			[Kind.SILK, silk], [Kind.CAMP_KIT, camp_kits], [Kind.KEY, keys]]:
		if pair[1] > 0:
			found.append({kind = pair[0], count = pair[1], weapon = null})
	var meats := {}
	# Enough for a camp kit and none on you: it shows, ready to craft (the
	# user's: double-click it).
	if camp_kits == 0 and scrap >= KIT_SCRAP and silk >= KIT_SILK:
		found.append({kind = Kind.CAMP_KIT, count = 0, weapon = null, craftable = true})
	for chunk in meat:
		var meat_kind := _meat_kind(chunk)
		meats[meat_kind] = int(meats.get(meat_kind, 0)) + 1
	for meat_kind: int in meats:
		found.append({kind = meat_kind, count = meats[meat_kind], weapon = null})
	# Glued meat: with none glued yet and the makings there, it shows ready
	# to craft, like the camp kit (the user's: double-click it).
	for glued_kind: Kind in [Kind.GLUED_MEAT, Kind.GLUED_COOKED]:
		if not meats.has(glued_kind) and can_glue(glued_kind):
			found.append({kind = glued_kind, count = 0, weapon = null, craftable = true})
	return found


## Which stack a chunk's in: fresh, rotten (by now) or cooked.
static func _meat_kind(chunk: Dictionary) -> Kind:
	var glued: bool = chunk.get("glued", false)
	if chunk.kind == Kind.COOKED_MEAT:
		return Kind.GLUED_COOKED if glued else Kind.COOKED_MEAT
	if CarryItem.is_rotten_data(chunk):
		return Kind.ROTTEN_MEAT
	return Kind.GLUED_MEAT if glued else Kind.MEAT


## Glued meat's recipe (the user's): two fresh chunks (raw with raw, cooked
## with cooked; never rotten, never already glued) and a silk.
const GLUE_CHUNKS := 2
const GLUE_SILK := 1


## Whether there's the makings of a glued chunk of `glued_kind`.
func can_glue(glued_kind: Kind) -> bool:
	return silk >= GLUE_SILK and _glue_picks(glued_kind).size() >= GLUE_CHUNKS


## The chunks that would go in (the freshest first).
func _glue_picks(glued_kind: Kind) -> Array[int]:
	var plain := Kind.COOKED_MEAT if glued_kind == Kind.GLUED_COOKED else Kind.MEAT
	var picks: Array[int] = []
	for i in meat.size():
		if _meat_kind(meat[i]) == plain:
			picks.append(i)
	picks.sort_custom(func(a: int, b: int) -> bool: return float(meat[a].age) < float(meat[b].age))
	return picks


## Two chunks stuck together with silk (CarryItem: glued): their weight
## together, a boss's if either was, as old as the older. False if short.
func craft_glued(glued_kind: Kind) -> bool:
	if not can_glue(glued_kind):
		return false
	var picks := _glue_picks(glued_kind).slice(0, GLUE_CHUNKS)
	var glued := (meat[picks[0]] as Dictionary).duplicate()
	glued.glued = true
	for i in picks.slice(1):
		var other: Dictionary = meat[i]
		glued.meat_weight = float(glued.meat_weight) + float(other.meat_weight)
		glued.boss = bool(glued.boss) or bool(other.get("boss", false))
		glued.age = maxf(float(glued.age), float(other.age))
		glued.cooked_for = minf(float(glued.get("cooked_for", 0.0)), float(other.get("cooked_for", 0.0)))
	picks.sort()
	picks.reverse()
	for i in picks:
		meat.remove_at(i)
	silk -= GLUE_SILK
	meat.append(glued)
	changed.emit()
	return true


## A meat chunk (CarryItem.to_data()) in, if there's room.
func add_meat(chunk: Dictionary) -> bool:
	var meat_kind := _meat_kind(chunk)
	if not has_room_for(meat_kind):
		return false
	meat.append(chunk)
	changed.emit()
	return true


## A chunk of `meat_kind` out (the freshest fresh one, the most rotten
## rotten one), or {} if there's none.
func take_meat(meat_kind: Kind) -> Dictionary:
	var best := -1
	for i in meat.size():
		if _meat_kind(meat[i]) != meat_kind:
			continue
		if best < 0 or (meat_kind == Kind.MEAT and meat[i].age < meat[best].age) \
				or (meat_kind == Kind.ROTTEN_MEAT and meat[i].age > meat[best].age):
			best = i
	if best < 0:
		return {}
	var chunk := meat[best]
	meat.remove_at(best)
	if meat_kind == Kind.ROTTEN_MEAT:
		chunk.kind = Kind.MEAT # (a rotten chunk is meat that's old: CarryItem)
	changed.emit()
	return chunk


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
		Kind.KEY:
			keys += amount
		_:
			return 0
	changed.emit()
	return amount


## A camp kit's recipe (the user's).
const KIT_SCRAP := 4
const KIT_SILK := 2


## Crafts a camp kit from KIT_SCRAP scrap and KIT_SILK silk; false if short
## (or one's already on you).
func craft_camp_kit() -> bool:
	if camp_kits >= MAX_CAMP_KITS or scrap < KIT_SCRAP or silk < KIT_SILK:
		return false
	scrap -= KIT_SCRAP
	silk -= KIT_SILK
	camp_kits += 1
	changed.emit()
	return true


## Everything you carry -- the pack and your weapons -- taken off you (dying
## near a camp: DeathPack). The host tells the owner's copy too.
func take_all() -> Dictionary:
	var gear := _player.weapons.take_all()
	gear.scrap = scrap
	gear.silk = silk
	gear.camp_kits = camp_kits
	gear.keys = keys
	gear.meat = meat.duplicate(true)
	scrap = 0
	silk = 0
	camp_kits = 0
	keys = 0
	meat.clear()
	placing_camp = false
	changed.emit()
	_tell_owner(gear, false)
	return gear


## take_all()'s gear back (the DeathPack picked up).
func give_all(gear: Dictionary) -> void:
	_player.weapons.give_all(gear, not Network.is_online() or multiplayer.is_server())
	scrap += int(gear.get("scrap", 0))
	silk += int(gear.get("silk", 0))
	camp_kits = mini(camp_kits + int(gear.get("camp_kits", 0)), MAX_CAMP_KITS)
	keys += int(gear.get("keys", 0))
	for chunk: Dictionary in gear.get("meat", []):
		meat.append(chunk)
	changed.emit()
	_tell_owner(gear, true)


func _tell_owner(gear: Dictionary, back: bool) -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority():
		_net_gear.rpc_id(_player.get_multiplayer_authority(), gear, back)


@rpc("any_peer", "call_remote", "reliable")
func _net_gear(gear: Dictionary, back: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if back:
		give_all(gear)
	else:
		take_all()


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
		Kind.KEY:
			if keys < amount:
				return false
			keys -= amount
		_:
			return false
	changed.emit()
	return true


## A key door opened (SecretDoor): one key used up.
func use_key() -> bool:
	return take(Kind.KEY, 1)


## How heavy the pack is, in kg.
func weight() -> float:
	var total := 0.0
	for stack in stacks():
		if stack.kind == Kind.GUN:
			total += (stack.weapon as WeaponData).carry_weight if stack.weapon else 3.5
		elif stack.kind not in [Kind.MEAT, Kind.ROTTEN_MEAT, Kind.COOKED_MEAT, Kind.GLUED_MEAT, Kind.GLUED_COOKED]:
			total += float(WEIGHTS.get(stack.kind, 0.0)) * stack.count
	for chunk in meat:
		total += float(chunk.meat_weight)
	return total


## The pack's weight as of the last weighing (twice a second).
func current_weight() -> float:
	var now := Time.get_ticks_msec()
	if now - _weighed_msec >= WEIGH_EVERY_MSEC:
		_weighed_msec = now
		_weight = weight()
	return _weight


## How far into overweight it is: 0 up to free_weight, 1 at heavy_at and past.
func heaviness() -> float:
	return clampf(inverse_lerp(free_weight, heavy_at, current_weight()), 0.0, 1.0)


func is_overweight() -> bool:
	return current_weight() > free_weight


func is_too_heavy() -> bool:
	return current_weight() >= heavy_at


## What the weight does (1 = nothing): stamina refill, walking and running,
## jump height, the grapple's pull, and its stamina drain while holding on.
func refill_scale() -> float:
	return lerpf(1.0, slowest_refill, heaviness())


func move_scale() -> float:
	return lerpf(1.0, slowest_move, heaviness())


## For a jump's speed: the height goes with its square.
func jump_scale() -> float:
	return sqrt(lerpf(1.0, lowest_jump, heaviness()))


func pull_scale() -> float:
	return lerpf(1.0, slowest_pull, heaviness())


func drain_scale() -> float:
	return lerpf(1.0, heaviest_drain, heaviness())


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
