class_name Population
extends RefCounted

## Hard caps on how many rats, roaches and spiders can be alive at once, game-wide --
## so a long fight can't pile up hundreds of them and sink the frame rate.
## When something new is about to be born at the cap, the OLDEST living ones
## (by when they spawned: their "born" meta) die on the spot -- a normal death,
## blood and all -- to make room, so births never just silently fail.
## Hand-placed ones count too (born when the level loads, so they go first).
## Rule 1: host only, like every spawn.

const MAX_RATS := 60
const MAX_ROACHES := 60
const MAX_SPIDERS := 60


## Stamps when `creature` was born (Rat/FlyingRoach call this in _ready()).
static func mark_born(creature: Node) -> void:
	creature.set_meta("born", Time.get_ticks_msec())


## Frees up room for `needed` new members of `group` (Factions group name)
## under `cap`, killing the oldest living ones that are `kind` (a script
## class) -- so a Rat Bender in the "rats" group is never culled.
static func make_room(tree: SceneTree, group: String, kind: Script, cap: int, needed: int) -> void:
	var alive: Array[Node] = []
	for node in tree.get_nodes_in_group(group):
		if node.get_script() == kind and Factions.is_alive_target(node as Node3D):
			alive.append(node)
	var excess := alive.size() + needed - cap
	if excess <= 0:
		return
	alive.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("born", 0)) < int(b.get_meta("born", 0)))
	for i in mini(excess, alive.size()):
		var health := alive[i].get_node_or_null("Health") as Health
		if health:
			health.take_damage(health.current_health + 1.0)


static func make_room_for_rats(tree: SceneTree, needed: int) -> void:
	make_room(tree, Factions.GROUPS[Factions.Side.RAT], Rat, MAX_RATS, needed)


static func make_room_for_roaches(tree: SceneTree, needed: int) -> void:
	make_room(tree, Factions.GROUPS[Factions.Side.ROACH], FlyingRoach, MAX_ROACHES, needed)


static func make_room_for_spiders(tree: SceneTree, needed: int) -> void:
	make_room(tree, Factions.GROUPS[Factions.Side.SPIDER], Spider, MAX_SPIDERS, needed)
