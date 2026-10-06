class_name Factions
extends RefCounted

## Who fights whom, Half-Life 2 style. Every creature belongs to one side:
##   PLAYER  - players (skipped while hidden_from_enemies is on, the pause
##             menu's "Invisible to Enemies")
##   TWEAKER - the human enemies: melee, rushers, gunners (Enemy)
##   ROACH   - flying roaches, spitters included (FlyingRoach)
##   RAT     - rats and the Rat Bender (Rat, RatBender)
## Every side hates every other side, but not equally -- Source's NPC
## relationships (CBaseCombatCharacter: a relationship type and a PRIORITY
## per class). An NPC picks its enemy the way CAI_BaseNPC::BestEnemy() does:
## the highest priority wins, and only between equals does the nearest win.
## On top of that, whatever hurt it lately jumps up the list (Source NPCs
## turn on their attacker: UpdateEnemyMemory on taking damage) -- so a
## tweaker being bitten by a roach turns and fights it, then goes back to
## you once it stops.
## Rule 1 (co-op): only the host picks targets; players are just one more side.

## Sides are passed around as plain ints (Side values) -- Godot's type check
## treats "Side" here and "Factions.Side" elsewhere as different types.
enum Side { PLAYER, TWEAKER, ROACH, RAT }

const GROUPS := {
	Side.PLAYER: "player",
	Side.TWEAKER: "tweakers",
	Side.ROACH: "roaches",
	Side.RAT: "rats",
}

## How much each side wants to fight each other side (higher = first).
const PRIORITY := {
	Side.TWEAKER: {Side.PLAYER: 3, Side.ROACH: 2, Side.RAT: 1},
	Side.ROACH: {Side.PLAYER: 3, Side.RAT: 2, Side.TWEAKER: 1},
	Side.RAT: {Side.PLAYER: 3, Side.TWEAKER: 2, Side.ROACH: 1},
	Side.PLAYER: {},
}
## Whatever hurt you within REVENGE_TIME seconds counts this much higher.
const REVENGE_BONUS := 2
const REVENGE_TIME := 5.0
## Sticking with the current target: it counts as this much closer than it
## is, so an NPC only switches for something higher priority or clearly
## nearer -- without it, two equally hated targets swapping places as they
## move made NPCs flip between them twice a second (the "vibrating").
const STICKINESS := 0.6


## The target `viewer` (on `side`, at `from`) wants most, within max_range:
## highest priority (plus revenge), nearest among equals -- `current`, its
## target right now, counting as closer (STICKINESS). Null if none.
## `current` is deliberately untyped: callers pass their old target straight
## in, and it may have been freed since (a body eaten, a corpse removed).
## Godot refuses to pass a freed object into a typed Node3D parameter ("argument
## 6 (previously freed) is not a subclass..."), so it's checked here instead.
static func nearest_hostile(tree: SceneTree, side: int, from: Vector3, max_range: float = INF, viewer: Node = null, current = null) -> Node3D:
	if not is_instance_valid(current):
		current = null
	var best: Node3D = null
	var best_priority := -1
	var best_distance := INF
	for other: int in GROUPS:
		if other == side:
			continue
		for node in tree.get_nodes_in_group(GROUPS[other]):
			var target := node as Node3D
			if target == null or not is_alive_target(target):
				continue
			var distance := from.distance_to(target.global_position)
			if distance > max_range:
				continue
			if target == current:
				distance *= STICKINESS
			var priority := priority_of(side, other, viewer, target)
			if priority > best_priority or (priority == best_priority and distance < best_distance):
				best_priority = priority
				best_distance = distance
				best = target
	return best


## How much `side` wants to fight `target` (of side `other`), with revenge.
static func priority_of(side: int, other: int, viewer: Node, target: Node3D) -> int:
	var priority: int = PRIORITY[side].get(other, 0)
	if viewer and viewer.has_meta("provoked_by") and viewer.get_meta("provoked_by") == target \
			and Time.get_ticks_msec() - int(viewer.get_meta("provoked_at", 0)) < REVENGE_TIME * 1000.0:
		priority += REVENGE_BONUS
	return priority


## `attacker` just hurt `victim`: it jumps up the victim's list for a while.
static func provoke(victim: Node, attacker: Node3D) -> void:
	if victim == null or attacker == null:
		return
	victim.set_meta("provoked_by", attacker)
	victim.set_meta("provoked_at", Time.get_ticks_msec())


## Which side `node` is on, or -1.
static func side_of(node: Node) -> int:
	for side: int in GROUPS:
		if node.is_in_group(GROUPS[side]):
			return side
	return -1


## Every living target `side` is hostile to.
static func hostiles(tree: SceneTree, side: int) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for other: int in GROUPS:
		if other == side:
			continue
		for node in tree.get_nodes_in_group(GROUPS[other]):
			var target := node as Node3D
			if target and is_alive_target(target):
				found.append(target)
	return found


## Alive, and (for a player) not invisible to enemies.
static func is_alive_target(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target.get("hidden_from_enemies") == true:
		return false
	var health := target.get_node_or_null("Health") as Health
	return health != null and not health.is_dead


## How tall the target stands, for aiming and reach: a person, a rat, a roach.
static func height_of(target: Node3D) -> float:
	if target.is_in_group(GROUPS[Side.RAT]) and not target is CharacterBody3D:
		return 0.25
	if target.is_in_group(GROUPS[Side.ROACH]):
		return 0.3
	return 1.8


## Where to aim at the target: a person's chest, or the middle of a rat/roach.
static func aim_point(target: Node3D) -> Vector3:
	if target.is_in_group(GROUPS[Side.ROACH]):
		return target.global_position # a roach's origin is its middle already
	return target.global_position + Vector3.UP * height_of(target) * 0.55
