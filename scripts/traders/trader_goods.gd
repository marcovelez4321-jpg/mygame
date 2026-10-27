class_name TraderGoods
extends RefCounted

## What the traders sell, for scrap (the user's, 2026-10-25;
## docs/QUESTS_TRADERS_WALKERS.md): any of these can turn up, STOCK of them on
## a cart at a time, rarer the pricier (a good's odds go as 1 / its price),
## re-rolled each new meeting. Each good: its name (the prompt), what it is
## as hand data, its price in scrap, and where it's shown on the cart (hooks:
## guns and grenades; shelves: ammo, food, camp kits; the eaves: small things).
## A stock is a seed: every game rolls the same goods from it (co-op: one
## shared cart -- Trader).
## Prices for you: twice as much once you've hurt a trader (Traders.ROBBED,
## the user's: never fading), less with a trader's own discount.

const STOCK := 6 # (the user's: half the 12 it was)
const GOODS := [
	{name = "Pistol", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/starter_gun.tres"}, price = 8, show = &"hook"},
	{name = "Revolver", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/revolver.tres"}, price = 8, show = &"hook"},
	{name = "MP5", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/uzi.tres"}, price = 8, show = &"hook"},
	{name = "Submachine Gun", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/machine_gun.tres"}, price = 15, show = &"hook"},
	{name = "PPSh", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/ppsh.tres"}, price = 15, show = &"hook"},
	{name = "Dual MP5s", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/dual_uzis.tres"}, price = 15, show = &"hook"},
	{name = "Shotgun", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/shotgun.tres"}, price = 25, show = &"hook"},
	{name = "Sniper Rifle", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/sniper.tres"}, price = 25, show = &"hook"},
	{name = "PKM", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/pkm.tres"}, price = 25, show = &"hook"},
	{name = "RPG", data = {kind = Backpack.Kind.GUN, weapon = "res://weapons/rpg.tres"}, price = 40, show = &"hook"},
	{name = "Bullets (30)", data = {kind = Backpack.Kind.BULLETS, amount = 30}, price = 1, show = &"shelf"},
	{name = "Shells (8)", data = {kind = Backpack.Kind.SHELLS, amount = 8}, price = 2, show = &"shelf"},
	{name = "Rocket", data = {kind = Backpack.Kind.ROCKETS, amount = 1}, price = 4, show = &"shelf"},
	{name = "Frag grenade", data = {kind = Backpack.Kind.GRENADES, amount = 1}, price = 3, show = &"hook"},
	{name = "Pills", data = {kind = Backpack.Kind.PILLS, amount = 1}, price = 3, show = &"eave"},
	{name = "Bandage", data = {kind = Backpack.Kind.BANDAGE, amount = 1}, price = 2, show = &"eave"},
	{name = "Cooked meat", data = {kind = Backpack.Kind.COOKED_MEAT, amount = 1, meat_weight = 1.0, age = 0.0, cooked_for = CarryItem.COOK_TIME}, price = 2, show = &"shelf"},
	{name = "Camp kit", data = {kind = Backpack.Kind.CAMP_KIT, amount = 1}, price = 6, show = &"shelf"},
	# The offering (the user's: a bound bundle of meat and teeth, rare -- Bones for the Voice).
	{name = "Offering", data = {kind = Backpack.Kind.OFFERING, amount = 1}, price = 10, show = &"eave"},
]


## The STOCK goods (indices into GOODS) a seed gives: rarer the pricier; a
## gun at most once on a cart.
static func roll(seed: int) -> Array[int]:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed
	var total := 0.0
	for good: Dictionary in GOODS:
		total += 1.0 / float(good.price)
	var picked: Array[int] = []
	var tries := 0
	while picked.size() < STOCK and tries < 200:
		tries += 1
		var roll_at := dice.randf() * total
		var index := 0
		for i in GOODS.size():
			roll_at -= 1.0 / float(GOODS[i].price)
			if roll_at <= 0.0:
				index = i
				break
		if (GOODS[index].data as Dictionary).kind == Backpack.Kind.GUN and picked.has(index):
			continue
		picked.append(index)
	return picked


## Hand data for one of `index` (a gun comes with a full magazine).
static func data_of(index: int) -> Dictionary:
	var data: Dictionary = (GOODS[index].data as Dictionary).duplicate(true)
	if data.kind == Backpack.Kind.GUN:
		var gun := load(str(data.weapon)) as WeaponData
		data.amount = gun.magazine_size if gun else 6
	return data


## What `index` costs `player` at the trader `trader_id`.
static func price(index: int, trader_id: String, player: PlayerMovement) -> int:
	var cost := float(GOODS[index].price)
	if Traders.robbed_by(player):
		cost *= Traders.ROBBED_PRICE
	cost *= 1.0 - Traders.discount(trader_id, player)
	return maxi(ceili(cost - 0.001), 1)
