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
## Bleeding out (bleed()): health lost per second, seconds left, and who
## caused it (credited with the kill if it finishes them).
var _bleed_rate := 0.0
var _bleed_left := 0.0
var _bleed_attacker := NO_ATTACKER
## Healing over time (regenerate()): health gained per second, seconds left.
var _regen_rate := 0.0
var _regen_left := 0.0


func _ready() -> void:
	current_health = max_health
	set_physics_process(false) # only runs while bleeding or healing over time


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


## A wound that keeps bleeding (a headshot or artery hit): `total` damage
## drained evenly over `duration` seconds. Quiet -- no flinch, no hit flash
## every tick, just health draining -- but it can finish them off. A new
## wound adds what's left of the old one on top. Host only, like all damage.
func bleed(total: float, duration: float, attacker_id: int = NO_ATTACKER) -> void:
	if is_dead or total <= 0.0 or duration <= 0.0:
		return
	var remaining := _bleed_rate * _bleed_left + total
	_bleed_left = maxf(_bleed_left, duration)
	_bleed_rate = remaining / _bleed_left
	_bleed_attacker = attacker_id
	set_physics_process(true)


## Healed right now (pills): up to max_health. Host only, like damage.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)


## Healed `total` over `duration` seconds (a bandage). A new one adds what's
## left of the old one on top, like bleed().
func regenerate(total: float, duration: float) -> void:
	if is_dead or total <= 0.0 or duration <= 0.0:
		return
	var remaining := _regen_rate * _regen_left + total
	_regen_left = maxf(_regen_left, duration)
	_regen_rate = remaining / _regen_left
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if is_dead or (_bleed_left <= 0.0 and _regen_left <= 0.0):
		_bleed_left = 0.0
		_regen_left = 0.0
		set_physics_process(false)
		return
	if _regen_left > 0.0:
		var heal_step := minf(delta, _regen_left)
		_regen_left -= heal_step
		current_health = minf(current_health + _regen_rate * heal_step, max_health)
	if _bleed_left <= 0.0:
		return
	var step := minf(delta, _bleed_left)
	_bleed_left -= step
	current_health = maxf(current_health - _bleed_rate * step, 0.0)
	if current_health <= 0.0:
		is_dead = true
		died.emit(_bleed_attacker, false)


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
