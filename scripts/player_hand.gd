class_name PlayerHand
extends Node

## Your right hand (the user's, 2026-10-15): grapple an item (PlayerGrapple)
## and it flies in at FETCH_SPEED; the gun goes away while it's there.
##   Left click uses it: raw meat feeds off the virus, cooked meat is eaten,
##   a pod gives its mutation, pills are taken, a gun is equipped, ammo is
##   loaded, grenades readied, a camp kit brought out to place. Scrap and silk
##   just sit in your hand.
##   G drops it at your feet (a CarryItem); F puts it in the backpack.
##   Double-clicking something in the backpack brings it into your hand.
## Held over a fire, meat cooks (CarryItem's rules).
## Rule 1 (co-op): tick() runs in the player's simulation step from the input
## packet; what changes the world (spawning, freeing, eating) only on the
## host, which tells the owner what's in their hand (_net_hand).

## How fast an item flies in (the user's).
const FETCH_SPEED := 20.0
## Where the hand holds things, in your head's space (for cooking over a
## fire, and where a fetched item flies to).
const HOLD_POINT := Vector3(0.25, -0.3, -0.5)
## The heaviest thing a hand takes (the user's; heavier things are props on
## the tentacle, or anchors).
const MAX_WEIGHT := 15.0
## Prompts to the left of it (the user's wording for meat).
const PROMPTS := {
	Backpack.Kind.MEAT: "left click to feed off the virus",
	Backpack.Kind.COOKED_MEAT: "left click to eat",
	Backpack.Kind.PILLS: "left click to take the pills",
	Backpack.Kind.BANDAGE: "left click to wrap the bandage",
	Backpack.Kind.GUN: "left click to equip",
	Backpack.Kind.BULLETS: "left click to load",
	Backpack.Kind.SHELLS: "left click to load",
	Backpack.Kind.ROCKETS: "left click to load",
	Backpack.Kind.GRENADES: "left click to ready",
	Backpack.Kind.CAMP_KIT: "left click to place the camp",
	Backpack.Kind.KEY: "a key: F at a locked door (it's used up)",
	Backpack.Kind.CIGARETTES: "the last pack of cigarettes: for Grandma\nleft click to smoke them",
	# The quests' things (Quests): what they're for.
	Backpack.Kind.SKULL: "a skull off its pile: proof, for the trader at 400 m",
	Backpack.Kind.OFFERING: "an offering: meat and teeth, bound\nG in its home to leave it",
	Backpack.Kind.TAGS: "his tags: for Mara",
	Backpack.Kind.BLACK_BLOOD: "a jar of black blood: for the ritual",
	Backpack.Kind.BOMB_GAS: "gas: for the Fanatic's bomb",
	Backpack.Kind.BOMB_PIPE: "a pipe: for the Fanatic's bomb",
	Backpack.Kind.BOMB_WIRE: "wire: for the Fanatic's bomb",
}
## Smoking the last pack (the user's, 2026-10-25: LastPack): quick and quiet
## -- one drag, a puff of smoke -- standing still SMOKE_TIME; then three pods
## ripen on the Flesh Tree (a mutation's worth of points: a free one).
const SMOKE_TIME := 6.0

## What's in it (CarryItem.to_data()); {} = nothing.
var data: Dictionary = {}
## Flying in right now (a world body), or null.
var incoming: Node3D

var _player: PlayerMovement
var _fire_prev := false
var _drop_prev := false
var _cook_left := 0.0
var _age_left := CarryItem.AGE_EVERY


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	_player.health.died.connect(func(_a: int, _c: bool) -> void:
		cancel_fetch()
		if is_holding():
			_drop()
	)


## Smoking the last pack: you stand still (PlayerMovement), nothing else.
func smoking() -> bool:
	return is_holding() and float(data.get("smoke_left", 0.0)) > 0.0


## The drag's smoke, out of your face.
func _puff() -> void:
	var smoke := Viewmodel.backblast_smoke(-_player.head.global_basis.z + Vector3.UP * 0.3)
	_player.get_tree().current_scene.add_child(smoke)
	smoke.global_position = _player.head.global_position - _player.head.global_basis.z * 0.35
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)


## Done: the pack's gone, the quest's done that way, the pods ripen.
func _finish_smoking() -> void:
	_empty()
	LastPack.smoke(_player)
	_player.virus.gain_points(Virus.POINTS_TO_MUTATE)


## The journal's in your hand: you're reading it (JournalView).
func reading() -> bool:
	return is_holding() and int(data.get("kind", -1)) == Backpack.Kind.JOURNAL


func is_holding() -> bool:
	return not data.is_empty()


## Something on its way in, or in hand.
func is_busy() -> bool:
	return is_holding() or is_instance_valid(incoming)


## Whether `body` goes in a hand (an item, not a prop): a CarryItem, a gun,
## ammo or pills lying about.
static func is_item(body: Node) -> bool:
	return (body is CarryItem and not (body as CarryItem).bait) or body is WeaponPickup or body is AmmoPickup or body is ItemPickup or body is DeathPack


## The grapple bit an item: it flies in. Whatever's in your hand already goes
## in the backpack (or, with no room, drops) -- the user's.
func fetch(body: Node3D) -> void:
	if not _decides() or not is_instance_valid(body):
		return
	if body is DeathPack:
		(body as DeathPack).claim(_player) # your gear: straight back into the pack
		picked_up()
		return
	if is_holding() and not _stow():
		_drop()
	cancel_fetch()
	incoming = body
	body.set_meta(&"fetched", true) # (not walked into on its way: it's coming to the hand)
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.set_meta(&"fetch_layers", [rigid.collision_layer, rigid.collision_mask])
		rigid.freeze = true
		rigid.collision_layer = 0
		rigid.collision_mask = 0
	if body is CarryItem and body.has_meta(&"on_tree"):
		FleshTree.pod_taken(body as CarryItem)


## Still flying in (the grapple's tip follows it).
func fetching() -> Node3D:
	return incoming if is_instance_valid(incoming) else null


## Every simulation tick (PlayerMovement._finish_tick()): the item flying in,
## a fresh left click (use), G (drop), F (stow, from _tick_use()).
func tick(fire: bool, drop: bool, stow: bool, delta: float) -> void:
	var fire_pressed := fire and not _fire_prev
	var drop_pressed := drop and not _drop_prev
	_fire_prev = fire
	_drop_prev = drop
	_fly_in(delta)
	# Smoking (both the host and its owner count it down; the host ends it).
	if smoking():
		var was := float(data.smoke_left)
		data.smoke_left = was - delta
		if was > SMOKE_TIME * 0.5 and float(data.smoke_left) <= SMOKE_TIME * 0.5:
			_puff()
		if float(data.smoke_left) <= 0.0 and _decides():
			_finish_smoking()
		return
	# Reading: only F puts the journal away (the user's) -- G does nothing.
	if reading() and drop_pressed:
		return
	if drop_pressed and not is_holding() and not is_busy():
		# Nothing in the hand: G drops the gun in your hands (the user's).
		_player.weapons.drop_gun(_decides())
		return
	if not is_holding() or not _decides():
		return
	_cook(delta)
	if drop_pressed:
		_drop()
	elif stow:
		if not _stow() and _player.is_multiplayer_authority():
			MapIO.show_message(_player.get_tree(), "No room in the backpack")
	elif fire_pressed:
		_use()


## What left click does with it (the HUD shows it to its left).
func prompt() -> String:
	if not is_holding():
		return ""
	var kind: int = data.kind
	if kind == Backpack.Kind.JOURNAL:
		return "left click: next page\nright click: back\nF: put it away"
	if smoking():
		return ""
	if kind == CarryItem.POD:
		var mutation: Array = Virus.MUTATIONS.get(data.mutation, ["?", ""])
		return "%s\n%s\nleft click to mutate" % [mutation[0], mutation[1]]
	if data.get("glued", false):
		return "Glued meat\n" + PROMPTS.get(kind, "")
	return PROMPTS.get(kind, "")


## A gun double-clicked in the backpack comes as GUN_CODE + its index in
## your weapons (both guns can be in there: which one matters).
const GUN_CODE := 1000


## Double-clicked in the backpack: one of `code` (a Backpack.Kind, or a gun:
## GUN_CODE + its index) into your hand. A gun goes into your hands, as a gun.
func take_from_backpack(code: int) -> void:
	if not _decides():
		return
	var weapons := _player.weapons
	var backpack := _player.backpack
	if code >= GUN_CODE:
		if is_holding() and not _stow():
			_drop()
		weapons.equip_gun(code - GUN_CODE)
		return
	var kind := code as Backpack.Kind
	if kind == Backpack.Kind.GUN:
		return
	var taken := {}
	match kind:
		Backpack.Kind.PILLS:
			if weapons.take_item(WeaponController.Item.PILLS):
				taken = {kind = kind, amount = 1}
		Backpack.Kind.BANDAGE:
			if weapons.take_item(WeaponController.Item.BANDAGE):
				taken = {kind = kind, amount = 1}
		Backpack.Kind.GRENADES:
			if weapons.take_grenade():
				taken = {kind = kind, amount = 1}
		Backpack.Kind.BULLETS, Backpack.Kind.SHELLS, Backpack.Kind.ROCKETS:
			var rounds := weapons.take_ammo(_ammo_type(kind))
			if rounds > 0:
				taken = {kind = kind, amount = rounds}
		Backpack.Kind.JOURNAL:
			taken = {kind = kind, amount = 1}
		Backpack.Kind.SCRAP, Backpack.Kind.SILK, Backpack.Kind.CAMP_KIT, Backpack.Kind.KEY, Backpack.Kind.CIGARETTES:
			if kind == Backpack.Kind.CAMP_KIT and backpack.camp_kits == 0:
				backpack.craft_camp_kit() # crafted from scrap and silk (the user's)
			if backpack.take(kind, 1):
				taken = {kind = kind, amount = 1}
		Backpack.Kind.SKULL, Backpack.Kind.OFFERING, Backpack.Kind.TAGS, Backpack.Kind.BLACK_BLOOD, \
				Backpack.Kind.BOMB_GAS, Backpack.Kind.BOMB_PIPE, Backpack.Kind.BOMB_WIRE:
			if backpack.take(kind, 1):
				taken = {kind = kind, amount = 1}
		Backpack.Kind.MEAT, Backpack.Kind.ROTTEN_MEAT, Backpack.Kind.COOKED_MEAT:
			taken = backpack.take_meat(kind)
		Backpack.Kind.GLUED_MEAT, Backpack.Kind.GLUED_COOKED:
			taken = backpack.take_meat(kind)
			if taken.is_empty() and backpack.craft_glued(kind):
				taken = backpack.take_meat(kind) # crafted (two chunks and a silk: the user's)
	if taken.is_empty():
		return
	if is_holding() and not _stow():
		_drop()
	_hold(taken)


# ---- Inside ------------------------------------------------------------------------

func _hold(new_data: Dictionary) -> void:
	data = new_data
	_player.weapons.set_hand(data)
	_send()


func _empty() -> void:
	data = {}
	_player.weapons.set_hand({})
	_send()


func _hand_point() -> Vector3:
	return _player.head.global_transform * HOLD_POINT


## The item flying in at FETCH_SPEED; there, it's in your hand.
func _fly_in(delta: float) -> void:
	if not is_instance_valid(incoming):
		incoming = null
		return
	var to := _hand_point() - incoming.global_position
	var step := FETCH_SPEED * delta
	if to.length() > step:
		incoming.global_position += to.normalized() * step
		return
	if not _decides():
		return
	var arrived := _data_of(incoming)
	incoming.queue_free()
	incoming = null
	if not arrived.is_empty():
		_hold(arrived)


func cancel_fetch() -> void:
	if not is_instance_valid(incoming):
		incoming = null
		return
	if incoming is RigidBody3D and incoming.has_meta(&"fetch_layers"):
		var rigid := incoming as RigidBody3D
		var layers: Array = rigid.get_meta(&"fetch_layers")
		rigid.collision_layer = layers[0]
		rigid.collision_mask = layers[1]
		rigid.freeze = false
	if incoming.has_meta(&"fetched"):
		incoming.remove_meta(&"fetched")
	incoming = null


## What a world body is, as hand data.
static func _data_of(body: Node) -> Dictionary:
	if body is CarryItem:
		return (body as CarryItem).to_data()
	if body is WeaponPickup:
		var gun := body as WeaponPickup
		return {kind = Backpack.Kind.GUN, amount = gun.ammo_amount, weapon = gun.weapon.resource_path if gun.weapon else ""}
	if body is AmmoPickup:
		var ammo := body as AmmoPickup
		return {kind = _ammo_kind(ammo.ammo_type), amount = ammo.amount}
	if body is ItemPickup:
		var item := body as ItemPickup
		return {kind = Backpack.Kind.PILLS if item.item == WeaponController.Item.PILLS else Backpack.Kind.BANDAGE, amount = item.amount}
	return {}


## Meat in your hand goes on aging (in CarryItem.AGE_EVERY steps), and held
## over (or right by) a fire it cooks (looked for every CarryItem.COOK_EVERY).
func _cook(delta: float) -> void:
	if data.kind != Backpack.Kind.MEAT:
		return
	_cook_left -= delta
	_age_left -= delta
	var changed := false
	if _cook_left <= 0.0:
		_cook_left += CarryItem.COOK_EVERY
		changed = CarryItem.cook(data, CarryItem.COOK_EVERY, _hand_point())
	if _age_left <= 0.0:
		_age_left += CarryItem.AGE_EVERY
		changed = CarryItem.grow_old(data, CarryItem.AGE_EVERY) or changed
	if changed:
		_hold(data) # it rotted or cooked: the new look shows


## Left click.
func _use() -> void:
	if not is_holding():
		return
	var weapons := _player.weapons
	var kind: int = data.kind
	var amount: int = data.get("amount", 1)
	match kind:
		Backpack.Kind.MEAT:
			var held := data
			_empty()
			_player.virus.eat_raw(CarryItem.is_rotten_data(held), held.get("boss", false), held.get("glued", false))
		Backpack.Kind.COOKED_MEAT:
			var glued: bool = data.get("glued", false)
			_empty()
			_player.virus.eat_cooked(glued)
		CarryItem.POD:
			var mutation: StringName = data.mutation
			_empty()
			_player.virus.take_mutation(mutation)
		Backpack.Kind.PILLS, Backpack.Kind.BANDAGE:
			var item := WeaponController.Item.PILLS if kind == Backpack.Kind.PILLS else WeaponController.Item.BANDAGE
			_empty()
			weapons.add_item(item, amount)
			weapons.use_item(item)
		Backpack.Kind.GUN:
			var gun := _gun_of(data)
			_empty()
			weapons.pickup_weapon(gun, amount)
		Backpack.Kind.BULLETS, Backpack.Kind.SHELLS, Backpack.Kind.ROCKETS:
			_empty()
			weapons.add_ammo(_ammo_type(kind), amount)
		Backpack.Kind.GRENADES:
			_empty()
			_stow_grenade(amount)
			weapons.equip_grenades()
		Backpack.Kind.CAMP_KIT:
			pass # placed by its ghost (CampBuilder takes the clicks)
		Backpack.Kind.CIGARETTES:
			data.smoke_left = SMOKE_TIME # (smoking them: tick() counts it down)
			_hold(data)


## Something into the backpack (or, a gun, your weapons): F stowing what's in
## your hand, or walking over a thing lying about (CarryItem). False if it
## doesn't fit (a pod never does). A partly taken stack keeps what's left.
func store(item: Dictionary) -> bool:
	var weapons := _player.weapons
	var backpack := _player.backpack
	var kind: int = item.kind
	var amount: int = item.get("amount", 1)
	match kind:
		Backpack.Kind.MEAT, Backpack.Kind.COOKED_MEAT:
			if not backpack.add_meat(item):
				return false
		Backpack.Kind.PILLS, Backpack.Kind.BANDAGE:
			var heal := WeaponController.Item.PILLS if kind == Backpack.Kind.PILLS else WeaponController.Item.BANDAGE
			var taken := weapons.add_item(heal, amount)
			if taken < amount:
				item.amount = amount - taken
				return false
		Backpack.Kind.GUN:
			var gun := _gun_of(item)
			if gun == null or (not weapons.get_owned_weapons().has(gun) and weapons.is_gun(gun) and weapons.gun_count() >= WeaponController.MAX_GUNS):
				return false
			weapons.pickup_weapon(gun, amount)
		Backpack.Kind.BULLETS, Backpack.Kind.SHELLS, Backpack.Kind.ROCKETS:
			weapons.add_ammo(_ammo_type(kind), amount, false)
		Backpack.Kind.GRENADES:
			if not _stow_grenade(amount):
				return false
		Backpack.Kind.SCRAP, Backpack.Kind.SILK, Backpack.Kind.CAMP_KIT, Backpack.Kind.KEY, Backpack.Kind.CIGARETTES, Backpack.Kind.JOURNAL, \
				Backpack.Kind.SKULL, Backpack.Kind.OFFERING, Backpack.Kind.TAGS, Backpack.Kind.BLACK_BLOOD, \
				Backpack.Kind.BOMB_GAS, Backpack.Kind.BOMB_PIPE, Backpack.Kind.BOMB_WIRE:
			if backpack.add(kind as Backpack.Kind, amount) < amount:
				return false
		_:
			return false # a pod: it won't go in the bag
	return true


## F: what's in your hand into the backpack.
func _stow() -> bool:
	if not store(data):
		return false
	_empty()
	return true


func _stow_grenade(amount: int) -> bool:
	var grenade := _player.weapons.grenade_weapon()
	if grenade == null:
		return false
	_player.weapons.add_ammo(grenade.ammo_type, amount, false)
	return true


## The host: `item` into the hand (bought from a trader: Trader) -- whatever
## was there goes in the bag first.
func give(item: Dictionary) -> void:
	if not _decides():
		return
	put_back()
	_hold(item)


## The host: what's in the hand back in the bag -- the owner's own copy too
## -- or, with no room, dropped at their feet.
func put_back() -> void:
	if not is_holding() or not _decides():
		return
	var held := data.duplicate(true)
	if _stow():
		tell_owner_stored(held)
	else:
		_drop()


## Something picked up (walked into, grabbed): reading, the journal goes
## away (the user's).
func picked_up() -> void:
	if reading():
		put_back()


## The camp kit built (CampBuilder): gone from the hand.
func use_up() -> void:
	_empty()


## The host: what kind is in the hand (-1: nothing).
func held_kind() -> int:
	return int(data.get("kind", -1)) if is_holding() else -1


## Back in the bag (right click while placing a camp); dropped if no room.
func put_away() -> void:
	if is_holding() and not _stow():
		_drop()


## G: at your feet, a CarryItem (not picked straight back up: you're
## ignored till you step off it).
func _drop() -> void:
	if reading():
		return # (the journal's never dropped -- only put away with F: the user's)
	var at := _player.global_position + Vector3.UP * 0.6 - _player.global_basis.z * 0.5
	var dropped := CarryItem.spawn(_player, at, data)
	dropped.ignore = _player
	_empty()


## Co-op: the host stored something the owner walked into; their own copy of
## the inventory gets it too (meat comes with the backpack's own sync).
func tell_owner_stored(item: Dictionary) -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority() \
			and int(item.get("kind", -1)) not in [Backpack.Kind.MEAT, Backpack.Kind.COOKED_MEAT]:
		_net_store.rpc_id(_player.get_multiplayer_authority(), item)


@rpc("any_peer", "call_remote", "reliable")
func _net_store(item: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		store(item)


static func _gun_of(item: Dictionary) -> WeaponData:
	var path: String = item.get("weapon", "")
	return load(path) as WeaponData if path != "" and ResourceLoader.exists(path) else null


static func _ammo_type(kind: int) -> WeaponData.AmmoType:
	match kind:
		Backpack.Kind.SHELLS:
			return WeaponData.AmmoType.SHELLS
		Backpack.Kind.ROCKETS:
			return WeaponData.AmmoType.ROCKETS
	return WeaponData.AmmoType.BULLETS


static func _ammo_kind(type: WeaponData.AmmoType) -> int:
	match type:
		WeaponData.AmmoType.SHELLS:
			return Backpack.Kind.SHELLS
		WeaponData.AmmoType.ROCKETS:
			return Backpack.Kind.ROCKETS
		WeaponData.AmmoType.GRENADES:
			return Backpack.Kind.GRENADES
	return Backpack.Kind.BULLETS


# ---- Co-op ---------------------------------------------------------------------------

func _decides() -> bool:
	return not Network.is_online() or multiplayer.is_server()


func _send() -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority():
		_net_hand.rpc_id(_player.get_multiplayer_authority(), data)


@rpc("any_peer", "call_remote", "reliable")
func _net_hand(new_data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	data = new_data
	_player.weapons.set_hand(data)
