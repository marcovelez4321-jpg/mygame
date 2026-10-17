class_name Virus
extends Node

## The eldritch virus in you (the user's, 2026-10-15 -- docs/CLIMB_VISION.md
## "Feeding off the virus"). Everything in this world carries it, you too.
##   POINTS: eating raw meat feeds it (fresh +2, rotten +1, a boss chunk +3);
##   at POINTS_TO_MUTATE the Flesh Tree ripens three pods (FleshTree), and
##   eating one gives you its mutation (spending the points).
##   MUTATIONS: what they do is asked from here (has(), the *_scale()s).
##   HUNGER: one meter for food and water, full to empty in HUNGER_TIME;
##   empty, you lose STARVE_DAMAGE every STARVE_EVERY seconds.
##   DEATH: the newest mutation withers, the points are lost, and the tree
##   shrinks back a step.
## Rule 1 (co-op): the host's game decides (eating happens in the simulation
## step, PlayerHand); it tells the body's owner (_net_sync). Kept across the
## level reloading on death offline (static _kept), like a run's progress.

signal changed
## You ate raw meat or a pod (the trip flash, TripFlash; its words only for meat).
signal fed_raw(with_text: bool)

const WINGS := &"wings"
const CHITIN := &"chitin"
const ROACH_GUT := &"roach_gut"
const RAT_LUNGS := &"rat_lungs"
const MANTIS := &"mantis_legs"
const SPINNERETS := &"spinnerets"
const TENDRILS := &"tendrils"
const WHIP := &"whip"
const SEEDED := &"seeded_growth"

## The pool (the user's): name, and what it does (shown on a pod's highlight).
## (Tendrils is out of it -- the user's, 2026-10-17: it didn't work well;
## its code stays, switched off.)
const MUTATIONS := {
	WINGS: ["Insect Wings", "Shift in the air flies (it replaces the dash)"],
	CHITIN: ["Chitin Skin", "35% less damage from attacks and falls"],
	ROACH_GUT: ["Roach Gut", "Raw meat hurts 20 (not 35), rotten 50 (not 90)"],
	RAT_LUNGS: ["Rat Lungs", "Stamina refills 50% faster"],
	MANTIS: ["Mantis Legs", "Jump 50% higher, half fall damage"],
	SPINNERETS: ["Spinnerets", "The grapple reaches 25% further"],
	WHIP: ["Tentacle Whip", "Double-tap right click: lash the tentacle (50, 5 m, 1 bar)"],
	SEEDED: ["Seeded Growth", "Tap right click: five tentacles burst from the ground where you aim (40, then 10/s for 2 s; 1 bar, 4 s)"],
}

const POINTS_TO_MUTATE := 14
const FRESH_POINTS := 2
const ROTTEN_POINTS := 1
const BOSS_POINTS := 3
## Eating raw: damage, fresh and rotten (Roach gut: less).
const RAW_DAMAGE := 35.0
const ROTTEN_DAMAGE := 90.0
const GUT_RAW_DAMAGE := 20.0
const GUT_ROTTEN_DAMAGE := 50.0
## Hunger filled (0..1): raw fresh, rotten, cooked.
const RAW_FOOD := 0.25
const ROTTEN_FOOD := 0.15
const COOKED_FOOD := 0.45
## Cooked meat heals this (the user's); raw never does.
const COOKED_HEAL := 35.0
## Glued meat (CarryItem.glued, the user's): this much more food, and
## healing cooked, than one chunk; raw, a virus point more.
const GLUED_BONUS := 1.2
const GLUED_POINTS := 1

const HUNGER_TIME := 1200.0
const STARVE_DAMAGE := 1.0
const STARVE_EVERY := 2.0
## How often the host tells the owner the hunger (a tiny unreliable packet;
## it drains smoothly between on their side too).
const SYNC_EVERY := 2.0

var points := 0
## In the order taken (the newest withers on death).
var mutations: Array[StringName] = []
## 0..1: full .. starving.
var hunger := 1.0

var _player: PlayerMovement
var _starve_left := STARVE_EVERY
var _sync_left := 0.0
## Peer id -> {points, mutations}: kept while the level reloads.
static var _kept := {}


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	var kept: Dictionary = _kept.get(_player.get_multiplayer_authority(), {})
	if not kept.is_empty():
		points = kept.points
		mutations.assign(kept.mutations)
	mutations.assign(mutations.filter(func(m: StringName) -> bool: return MUTATIONS.has(m))) # (none out of the pool)
	_player.health.died.connect(_on_died)
	_player.respawned.connect(func() -> void: hunger = 1.0)
	_apply()


func has(mutation: StringName) -> bool:
	return mutations.has(mutation)


## What you'd still be offered (the pool minus what you have).
func missing() -> Array[StringName]:
	var left: Array[StringName] = []
	for mutation: StringName in MUTATIONS:
		if not has(mutation):
			left.append(mutation)
	return left


func _physics_process(delta: float) -> void:
	if _player.is_dead():
		return
	# Drained everywhere (smooth on the owner's screen); the host's number wins
	# (_net_hunger) and only the host starves you.
	hunger = maxf(hunger - delta / HUNGER_TIME, 0.0)
	if not _decides():
		return
	if hunger <= 0.0:
		_starve_left -= delta
		if _starve_left <= 0.0:
			_starve_left += STARVE_EVERY
			_player.health.take_damage(STARVE_DAMAGE)
	else:
		_starve_left = STARVE_EVERY
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_EVERY
		_send_hunger()


## Raw meat eaten (PlayerHand): it hurts (it can kill you), feeds you, and
## feeds the virus.
func eat_raw(rotten: bool, boss: bool, glued: bool = false) -> void:
	if not _decides():
		return
	var gut := has(ROACH_GUT)
	var damage := (GUT_ROTTEN_DAMAGE if gut else ROTTEN_DAMAGE) if rotten else (GUT_RAW_DAMAGE if gut else RAW_DAMAGE)
	hunger = minf(hunger + (ROTTEN_FOOD if rotten else RAW_FOOD) * (GLUED_BONUS if glued else 1.0), 1.0)
	points += (BOSS_POINTS if boss else (ROTTEN_POINTS if rotten else FRESH_POINTS)) + (GLUED_POINTS if glued else 0)
	_announce_trip(true)
	# Meat's damage isn't an attack: Chitin doesn't help (the user's).
	_player.health.hurt_unscaled(damage)
	_changed()
	if points >= POINTS_TO_MUTATE:
		FleshTree.ripen_for(_player)


## Cooked meat eaten: food, and it heals (glued: more of both).
func eat_cooked(glued: bool = false) -> void:
	if not _decides():
		return
	var bonus := GLUED_BONUS if glued else 1.0
	hunger = minf(hunger + COOKED_FOOD * bonus, 1.0)
	_player.health.heal(COOKED_HEAL * bonus)
	_changed()


## A pod eaten (PlayerHand): its mutation, for the points.
func take_mutation(mutation: StringName) -> void:
	if not _decides() or has(mutation) or not MUTATIONS.has(mutation):
		return
	mutations.append(mutation)
	points = maxi(points - POINTS_TO_MUTATE, 0)
	# Taking one heals you to full and fills you up (the user's).
	_player.health.heal(_player.health.max_health)
	hunger = 1.0
	FleshTree.grow(1)
	FleshTree.mutation_eaten() # the other pods shrivel now
	_announce_trip(false)
	_changed()
	if points >= POINTS_TO_MUTATE:
		FleshTree.ripen_for(_player)


## Died: the newest mutation withers, the points go, the tree shrinks back.
func _on_died(_attacker: int, _critical: bool) -> void:
	if not _decides():
		return
	if not mutations.is_empty():
		mutations.pop_back()
		FleshTree.grow(-1)
	points = 0
	_changed()


# ---- What the mutations do ------------------------------------------------------

## For a jump's speed: +50% height (Mantis legs) is sqrt(1.5) the speed.
func jump_scale() -> float:
	return sqrt(1.5) if has(MANTIS) else 1.0


## Fall damage's share (Mantis legs: half; Chitin's 35% comes off in Health).
func fall_damage_scale() -> float:
	return 0.5 if has(MANTIS) else 1.0


## How fast stamina refills (Rat lungs: 50% faster).
func refill_scale() -> float:
	return 1.5 if has(RAT_LUNGS) else 1.0


## How far the grapple reaches (Spinnerets: 25% further).
func reach_scale() -> float:
	return 1.25 if has(SPINNERETS) else 1.0


## Puts the mutations to work where they live in other nodes.
func _apply() -> void:
	if _player == null:
		return
	_player.health.damage_scale = 0.65 if has(CHITIN) else 1.0
	_player.grapple.tendrils_enabled = false # (Tendrils: out of the pool)


## The trip flash, on the screen of whoever owns this body.
func _announce_trip(with_text: bool) -> void:
	if Network.is_online() and not _player.is_multiplayer_authority():
		_trip.rpc_id(_player.get_multiplayer_authority(), with_text)
	else:
		fed_raw.emit(with_text)


# ---- Keeping it -------------------------------------------------------------------

func _decides() -> bool:
	return not Network.is_online() or multiplayer.is_server()


func _changed() -> void:
	_kept[_player.get_multiplayer_authority()] = {points = points, mutations = mutations.duplicate()}
	_apply()
	changed.emit()
	_send()


func _send() -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority():
		_net_sync.rpc_id(_player.get_multiplayer_authority(), points, mutations, hunger)


@rpc("any_peer", "call_remote", "reliable")
func _net_sync(new_points: int, new_mutations: Array, new_hunger: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	points = new_points
	mutations.assign(new_mutations)
	hunger = new_hunger
	_kept[_player.get_multiplayer_authority()] = {points = points, mutations = mutations.duplicate()}
	_apply()
	changed.emit()


func _send_hunger() -> void:
	if Network.is_online() and multiplayer.is_server() and not _player.is_multiplayer_authority():
		_net_hunger.rpc_id(_player.get_multiplayer_authority(), hunger)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_hunger(new_hunger: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		hunger = new_hunger


@rpc("any_peer", "call_remote", "reliable")
func _trip(with_text: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		fed_raw.emit(with_text)
