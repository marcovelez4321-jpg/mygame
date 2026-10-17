class_name Drops
extends RefCounted

## What creatures drop when they die (the user's, 2026-10-16: for crafting a
## camp kit): people SCRAP_CHANCE of a scrap, spiders SILK_CHANCE of a silk
## -- a CarryItem where they died (walk into it or grapple it). The host's.

const SCRAP_CHANCE := 1.0
const SILK_CHANCE := 0.5


## When `body` dies, `chance` of one `kind` (Backpack.Kind) where it fell.
static func on_death(body: Node3D, kind: int, chance: float) -> void:
	var health := body.get_node_or_null(^"Health") as Health
	if health == null:
		return
	health.died.connect(func(attacker: int, _critical: bool) -> void:
		if body.has_meta(&"culled") or NetEntities.is_puppet(body) or (Network.is_online() and not body.multiplayer.is_server()):
			return
		if attacker == Health.NO_ATTACKER:
			return # only a player's kill drops anything (the user's)
		if randf() >= chance:
			return
		var world := body.get_tree().current_scene
		var at := body.global_position + Vector3.UP * 0.6
		var item := CarryItem.spawn(world, at, {kind = kind, amount = 1})
		item.linear_velocity = Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-1.5, 1.5))
		item.expire_unclaimed()
	, CONNECT_ONE_SHOT)