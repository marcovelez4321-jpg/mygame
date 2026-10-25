class_name Traders
extends RefCounted

## What every trader shares (the user's, 2026-10-25): who's hurt one (world
## facts, per player, never fading -- WorldFacts), which traders refuse whom,
## a trader's own discounts, and the safe ground round each one (creatures
## keep SAFE_RANGE off him -- it's why he's lived this long).
## Facts:
##   trader.robbed.<player id>             true: every trader charges ROBBED_PRICE times
##   trader.<trader id>.refuses.<player id>  true: that one won't trade with them
##   trader.<trader id>.discount.<player id> 0..1 off (the Bounty, the Feather: to come)

const ROBBED_PRICE := 2.0
const REFUSE_SHARE := 0.5
const SAFE_RANGE := 25.0

## Every trader standing right now (each game's own list: puppets too).
static var _all: Array[Node3D] = []


static func register(trader: Node3D) -> void:
	if not _all.has(trader):
		_all.append(trader)


static func unregister(trader: Node3D) -> void:
	_all.erase(trader)


## Within SAFE_RANGE of a trader: creatures leave you be there, and keep off.
static func safe(at: Vector3) -> bool:
	for trader in _all:
		if is_instance_valid(trader) and trader.global_position.distance_squared_to(at) < SAFE_RANGE * SAFE_RANGE:
			return true
	return false


## The trader nearest `at` within SAFE_RANGE, or null.
static func guarding(at: Vector3) -> Node3D:
	for trader in _all:
		if is_instance_valid(trader) and trader.global_position.distance_squared_to(at) < SAFE_RANGE * SAFE_RANGE:
			return trader
	return null


## A player's id for the facts (their StalkerMemory id).
static func id_of(player: PlayerMovement) -> String:
	var profile: Dictionary = Network.profiles.get(player.get_multiplayer_authority() if player else 1, {})
	return str(profile.get("id", "nobody"))


static func robbed_by(player: PlayerMovement) -> bool:
	return bool(WorldFacts.get_fact(StringName("trader.robbed.%s" % id_of(player)), false))


static func refuses(trader_id: String, player: PlayerMovement) -> bool:
	return bool(WorldFacts.get_fact(StringName("trader.%s.refuses.%s" % [trader_id, id_of(player)]), false))


static func discount(trader_id: String, player: PlayerMovement) -> float:
	var value: Variant = WorldFacts.get_fact(StringName("trader.%s.discount.%s" % [trader_id, id_of(player)]), 0.0)
	return clampf(float(value) if value != null else 0.0, 0.0, 1.0)
