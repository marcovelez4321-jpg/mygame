class_name Health
extends Node

## A reusable "can be hurt" component. Attach it as a child node to anything
## that has health: the player, a monster, a breakable crate. They all share
## this one piece of code, so damage behaves the same for everything.
##
## Rule 1 (multiplayer-ready): the attacker is an int id, not a Node. A Node
## reference can't be sent over the network; an id can. It'll be the shooter's
## multiplayer peer id (the host is always 1). In multiplayer only the host
## should call take_damage(), so clients can't hurt each other by cheating.

signal damaged(amount: float, attacker_id: int)
## is_critical carries through whatever the attacker considered a "clean,
## finishing" blow (e.g. weapon_controller.gd's headshot) -- Health itself
## has no idea what that means for any particular attacker, it just forwards
## the flag so a listener (e.g. enemy.gd's mutation chance) can react to it.
signal died(attacker_id: int, is_critical: bool)

## Attacker id meaning "no one" (fall damage, a trap, the level itself).
const NO_ATTACKER := 0
## Blows landing within this many milliseconds count as one (so all the
## pellets of a single shotgun blast add up into one push).
const HIT_MERGE_MSEC := 100

@export var max_health: float = 100.0

var current_health: float
var is_dead: bool = false

## Where and how hard the most recent blow landed. Only used for cosmetic
## reactions such as a ragdoll being knocked back; it has no effect on damage.
## Co-op: the host will send this along with the death message so both
## players' games react the same way.
var last_hit_impulse: Vector3 = Vector3.ZERO
var last_hit_position: Vector3 = Vector3.ZERO
var _last_hit_msec: int = -1000


func _ready() -> void:
	current_health = max_health


## hit_direction, hit_position and impact_force are optional and only describe
## the blow for cosmetic reactions. A melee hit or a trap can leave them out.
func take_damage(amount: float, attacker_id: int = NO_ATTACKER, hit_direction: Vector3 = Vector3.ZERO,
		hit_position: Vector3 = Vector3.ZERO, impact_force: float = 0.0, is_critical: bool = false) -> void:
	if is_dead or amount <= 0.0:
		return
	_record_hit(hit_direction * impact_force, hit_position)
	current_health = maxf(current_health - amount, 0.0)
	damaged.emit(amount, attacker_id)
	if current_health <= 0.0:
		is_dead = true
		died.emit(attacker_id, is_critical)


func _record_hit(impulse: Vector3, position: Vector3) -> void:
	if impulse == Vector3.ZERO:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_msec <= HIT_MERGE_MSEC:
		last_hit_impulse += impulse
	else:
		last_hit_impulse = impulse
	last_hit_position = position
	_last_hit_msec = now
