class_name PlayerGrapple
extends Node3D

## The tentacle grapple (right mouse, or E). Only with a one-handed gun out
## (WeaponData.one_handed): the right hand keeps the gun, the left throws the
## tentacle. With anything else out, it switches to the last one-handed gun.
##
## Charge it, then it pulls you (docs/CLIMB_VISION.md):
##   CHARGE: hold right mouse; the ring shows where it'll bite. It only fires
##   once held at least min_charge_share of charge_time (no spamming), and
##   each throw costs fire_cost (half a stamina bar, the user's 2026-10-16);
##   nothing drains while it's out or holding.
##   Let go right as it fills (good_window): a tiny extra boost, and a sound.
##   PULL (the user's: back to the original, Titanfall 2 style -- the straight
##   launch didn't feel natural): once it bites it hauls you toward the spot,
##   building up to pull_speed, no gravity; you can still steer, and you keep
##   your speed when you let go. Press right mouse again in the last moments
##   before you arrive (perfect_window): let go at speed with another tiny
##   boost and a second sound, flying on past.
##   PERCH: arriving (or pressed against something on the way, getting no
##   closer), you stick to the wall there.
##   You stay perched till Space lets go (with a hop). (No rappelling or
##   reeling any more: the user's, 2026-10-16.) One grapple at a time: a new
##   one only once this one's let go.
## TENDRILS (the user's, 2026-10-14; switched off for now -- tendrils_enabled
## -- to come back to): where it bites (on the level, not a
## creature), three tendrils shoot on from the spot -- fanned out ahead the
## way you're flying (or up and onward: tendril_spread) -- each to a surface
## up to tendril_reach on, an M2 marker floating over each. Look right at
## one and right click: you're re-attached there at once (no charge-up), for
## half a stamina bar, 25% faster (up to the speed cap) -- the other markers
## vanish, and the new spot sprouts three more. Unused, they stay till you
## fire a brand-new charged grapple.
## Big enemies (BIG_GROUP: the Harvestman, the worm) pull you to them: kick them
## on arrival and bounce off, or press again during the flight to latch on
## and ride them until you jump. Small enemies are a miss.
##
## References: HL2 and Titanfall 2's grapples (straight at the point, keep
## your momentum), Spider-Man's web-zip, Opposing Force's barnacle grapple
## (an organic one).
##
## Rule 1 (co-op): tick() and apply_pull() run inside the player's simulation
## step from the input packet (PlayerInput.grapple), so the host runs them for
## every player; the kick's damage happens there too. Only _process() draws:
## your own grapple as the tentacle in your chosen style (GrappleTentacle,
## GameSettings.tentacle_style), everyone else's as a plain line. The timing
## sounds are your own (local).

signal fired(power: float)
signal attached(to_enemy: bool)
signal missed
signal kicked(damage: float)
signal released
## The timing rewards: let go right as it filled; let go perfectly mid-flight.
signal charge_timed
signal launch_timed

## Anything in this group (on the node itself or any parent of the part hit)
## is a big enemy you zip to. Small enemies are a miss.
const BIG_GROUP := "grapple_big"

## FETCH: an item flying into your right hand (PlayerHand). CARRY: a prop up
## to MAX_CARRY kg hanging off the tentacle in front of you (left click
## throws it, right click lets go). WHIP: the Tentacle whip mutation's lash.
## TOUCH: just hit the wall the pull brought you to -- a moment to kick off it.
enum Rope { NONE, LASH, PULL, PERCH, RIDE, MISS, FETCH, CARRY, WHIP, TOUCH }
## Where the tendrils look: fanned ahead the way you're flying, or up and on.
enum TendrilSpread { FAN_AHEAD, UP_AND_ONWARD }

@export_group("Charge")
## Seconds of holding for a full-power grapple.
@export var charge_time: float = 1.0
## It only fires once held at least this share of charge_time (the user's:
## half -- no spamming); let go sooner and nothing happens, nothing's spent.
@export_range(0.0, 1.0, 0.05) var min_charge_share: float = 0.5
## Let go within this many seconds of it filling: the charge reward.
@export var good_window: float = 0.15
## How much faster the pull is for it.
@export var charge_boost: float = 1.16

@export_group("Lash")
## Reach at full power, in meters (half at the least charge).
@export var max_range: float = 45.0
## How fast the tentacle flies out, m/s (the pull starts when it bites).
@export var lash_speed: float = 150.0
## How long a miss takes to whip out and snap back.
@export var miss_time: float = 0.25

@export_group("Pull")
## Pull speed at full power, m/s; at the least charge, this share of it.
@export var pull_speed: float = 20.0
@export_range(0.0, 1.0, 0.05) var min_speed_scale: float = 0.6
## How hard it pulls you up to that speed, m/s per second.
@export var pull_accel: float = 70.0
## Slows the pull near the spot so you settle onto it (speed is capped at
## distance x this).
@export var arrive_slowdown: float = 1.0
## The last seconds before arriving in which a press lets go perfectly, and
## how much faster you fly on for it.
@export var perfect_window: float = 0.3
@export var perfect_boost: float = 1.16
## How close to the spot counts as arriving.
@export var arrive_distance: float = 0.5

@export_group("Tendrils")
## Off for now (the user's, 2026-10-14: to come back to).
@export var tendrils_enabled: bool = false
## Which way the three tendrils fan out from the spot (the user's: ahead;
## up and onward as the other choice).
@export var tendril_spread: TendrilSpread = TendrilSpread.FAN_AHEAD
## How far on they reach, and how far apart they fan (degrees each side).
@export var tendril_reach: float = 15.0
@export var tendril_fan_degrees: float = 30.0
## A spot this close to the bite doesn't count (it's the same wall).
@export var tendril_min_distance: float = 2.0
## Re-attaching: stamina bars it costs, how much faster it sends you (up to
## the player's speed cap), and how near the crosshair a marker must be
## (degrees) -- right on it.
@export var reattach_cost: float = 0.5
@export var reattach_boost: float = 0.25
@export var marker_aim_degrees: float = 4.0

@export_group("Hold")
## Stamina bars a throw costs (the user's, 2026-10-16: half a bar; nothing
## drains while it's out or holding any more).
@export var fire_cost: float = 0.5
## How far off the wall you perch.
@export var perch_standoff: float = 1.0
## Upward speed added when you let go with Space.
@export var release_hop: float = 2.5

@export_group("Wall Kick")
## Pulled into a wall, you bounce off it along the natural path (the way
## you'd glance off), never slamming to a stop (the user's, 2026-10-16):
## Space in the last kick_window seconds before you hit (or up to
## kick_grace after touching) kicks off at kick_keep of your speed; in the
## last kick_perfect_window (or the moment you touch) it's kick_perfect_bonus
## stronger still, with the chime. No press: a weak bounce, bounce_keep of it.
@export var wall_reach: float = 1.2
@export var kick_window: float = 0.4
@export var kick_perfect_window: float = 0.1
@export var kick_grace: float = 0.1
@export var kick_keep: float = 1.2
@export var kick_perfect_bonus: float = 1.3
@export var bounce_keep: float = 0.3

@export_group("Big Enemies")
## How close (to the grabbed spot) counts as arriving: kick or latch on.
@export var kick_reach: float = 3.5
## Kick damage per m/s you were going when you hit (15.6 m/s x 4 = 62).
@export var kick_damage_per_speed: float = 4.0
## How hard you bounce back off after a kick, and up.
@export var kick_bounce: float = 13.5
@export var kick_bounce_up: float = 8.0
## How far off the enemy's surface you hang while riding.
@export var ride_standoff: float = 1.0

@export_group("Props")
## A prop (not an item) this heavy or lighter hangs off the tentacle; heavier
## is an anchor (the user's).
const MAX_CARRY := 15.0
## How far in front of your eyes it hangs (the old F prop mover's), how fast
## it can be dragged there, and the throw (the user's: 25 m/s).
@export var carry_distance: float = 2.0
@export var carry_max_speed: float = 90.0
@export var throw_speed: float = 25.0

@export_group("Whip")
## The Tentacle whip mutation (the user's): double-tap right click within
## whip_double_tap; a whip_time lash sweeping whip_reach in front of you,
## whip_damage to everything the tentacle itself touches, one stamina bar.
@export var whip_double_tap: float = 0.3
@export var whip_time: float = 0.4
@export var whip_reach: float = 5.0
@export var whip_damage: float = 50.0
@export var whip_sweep_degrees: float = 120.0

@export_group("Seeded Growth")
## The Seeded Growth mutation (the user's, SeededGrowth): a tap of right
## click (let go within seed_tap_time) bursts five tentacles out of the
## ground where you aim -- as far as the grapple reaches, on anything it
## could grab (the ring's not red). seed_cost bars, seed_cooldown seconds.
@export var seed_tap_time: float = 0.2
@export var seed_cost: float = 1.0
@export var seed_cooldown: float = 4.0

@export_group("Sound")
## The timing rewards' sounds (empty: a generated chime).
@export var charge_timed_sound: AudioStream
@export var launch_timed_sound: AudioStream

@export_group("Look")
## Where your grapple comes from on screen (camera space), until the new arms
## give it a real left hand.
@export var view_origin: Vector3 = Vector3(-0.32, -0.3, -0.45)
## Where other players see it come from (their body space: the left shoulder).
@export var body_origin: Vector3 = Vector3(-0.3, 1.35, 0.0)
## The plain line other players see.
@export var line_color: Color = Color(0.08, 0.02, 0.03)
@export var line_width: float = 0.04

## Testing: the grapple costs and drains no stamina (the pause menu's
## "Infinite Grapples" switch, like Infinite Ammo). Off by default (the
## user's, 2026-10-15: so the drain is felt).
var infinite_charges: bool = false
## 0..1 how coiled the tentacle is right now (the arm animation reads this).
var coil: float = 0.0

var _player: PlayerMovement
var _rope := Rope.NONE
var _held_prev := false
var _coiling := false
var _hold := 0.0
var _power := 0.0
## This pull got the charge reward (and so goes charge_boost faster).
var _charge_bonus := false
var _pull_speed := 0.0
## How long the pull has made no headway against something (perch there).
var _stalled := 0.0
var _last_distance := INF
## What it's stuck to, and where on it (in its own space, so a moving enemy
## or prop carries the spot along).
var _anchor: Node3D
var _anchor_local := Vector3.ZERO
var _normal_local := Vector3.UP
var _to_enemy := false
## The fly-out (LASH/MISS): seconds gone, seconds it takes, and where it ends.
var _lash_time := 0.0
var _lash_total := 0.0
var _lash_end := Vector3.ZERO
var _ride_wanted := false
var _ride_prev := Vector3.ZERO
var _ride_velocity := Vector3.ZERO
var _attacker_id := 0
## This tick's move input (x = strafe, y = back(+)/forward(-)).
var _move := Vector2.ZERO
## The tendrils' spots: {at (world), normal, collider (what it's on)}, and
## where they came from (for drawing them).
var _spots: Array[Dictionary] = []
var _spots_from := Vector3.ZERO
var _spot_marks: Array[Node3D] = []
## Seconds since the last right-click press (the whip's double tap).
var _since_press := 99.0
## Seeded Growth: a tap waiting out the whip's double tap (s; -1 none), where
## it was aimed, the cooldown, and the arm's push out for it.
var _seed_wait := -1.0
var _seed_aim := Vector3.FORWARD
var _seed_cooldown_left := 0.0
var _seed_arm := 0.0
## What the bite is for: an item into your hand, a prop to carry (else
## you're pulled).
var _for_fetch := false
var _for_carry := false
## Your speed as you perched (given back when you let go: momentum kept).
var _perch_kept := Vector3.ZERO
## The whip: seconds into the lash, which way it faces, and what it's hit.
var _whip_time := 0.0
var _whip_aim := Vector3.FORWARD
var _whip_hit: Array = []
## The wall kick: your speed going in (each pull tick), a Space press in
## time (and whether it was perfect), and the bounce worked out on impact.
var _pull_velocity := Vector3.ZERO
var _kick_queued := false
var _kick_perfect := false
var _bounce_dir := Vector3.ZERO
var _bounce_speed := 0.0
var _touch_left := 0.0
## Reused for every sweep of the lash (no allocations per tick).
var _whip_query: PhysicsShapeQueryParameters3D
var _whip_capsule: CapsuleShape3D
var _carry_fire_prev := false

var _line: MeshInstance3D
var _tentacle: GrappleTentacle
## Your own view: the landing ring while you hold the grapple.
var _indicator: GrappleIndicator
var _chime: AudioStreamPlayer
## Co-op, someone else's grapple on a client: where its tip is, from the host
## (INF: not out). Their grapple isn't run here, just drawn.
var _remote_tip := Vector3.INF
## Your first-person arms (set by the Viewmodel): the tentacle coils round
## the left forearm and lashes out of that palm.
var arms: FirstPersonArms


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	charge_timed.connect(_chime_play.bind(true))
	launch_timed.connect(_chime_play.bind(false))


## Called by PlayerMovement every simulation tick, before gravity and the
## move. `held` = right mouse (or E), `jump_pressed` = a fresh Space, `move`
## = this tick's move input. Returns true if Space was used up letting go
## (so it isn't also a wall jump).
func tick(held: bool, jump_pressed: bool, delta: float, origin: Vector3, aim: Vector3, attacker_id: int, move: Vector2 = Vector2.ZERO) -> bool:
	_attacker_id = attacker_id
	_move = move
	var pressed := held and not _held_prev
	_held_prev = held

	var weapons := _player.weapons
	var gun := weapons.current_weapon()
	# Something in your right hand (PlayerHand) leaves the left free too.
	# (Or the gun's in the backpack: both hands are.)
	var hand_free := _player.hand.is_holding() or weapons.gun_stowed or (gun != null and gun.one_handed)
	_since_press += delta
	var double_tap := pressed and _since_press <= whip_double_tap
	if pressed:
		_since_press = 0.0
	_seed_cooldown_left = maxf(_seed_cooldown_left - delta, 0.0)
	_seed_arm = maxf(_seed_arm - delta, 0.0)
	if _seed_wait >= 0.0:
		_seed_wait -= delta
		if _rope == Rope.WHIP or (_coiling and _hold > seed_tap_time):
			_seed_wait = -1.0 # the second tap whipped, or it's a grapple hold now
		elif _seed_wait < 0.0:
			_seed_burst(origin, _seed_aim)

	# Out of the one-handed gun (picked a two-handed one): the left hand's
	# needed on it, so the tentacle lets go.
	if not hand_free and not _coiling and is_attached():
		release()

	if _rope == Rope.LASH or _rope == Rope.MISS:
		_lash_time += delta
		if _lash_time >= _lash_total:
			if _rope == Rope.LASH:
				_land()
			else:
				_rope = Rope.NONE

	if _rope == Rope.WHIP:
		_whip(delta, origin, aim)
		return false

	if is_attached() and not is_instance_valid(_anchor):
		release()
	# The item's in your hand: the tentacle comes back.
	if _rope == Rope.FETCH and _player.hand.fetching() == null:
		_rope = Rope.NONE
		_anchor = null

	# Space on the way into a wall (or just as you touch it): a kick off it.
	if jump_pressed and _rope == Rope.TOUCH:
		_wall_kick(true) # the moment you touch: perfect
		return true
	if jump_pressed and _rope == Rope.PULL and not _to_enemy and _time_to_wall() <= kick_window:
		_kick_queued = true
		_kick_perfect = _time_to_wall() <= kick_perfect_window
		return true
	if jump_pressed and is_pulling():
		_let_go()
		return true

	# The Tentacle whip (a mutation): a quick second press lashes it.
	if double_tap and _player.virus.has(Virus.WHIP) and hand_free and (_rope == Rope.NONE or _coiling) \
			and (infinite_charges or _player.spend_stamina()):
		_start_whip(aim)
		return false

	# A prop on the tentacle: right click again lets it drop.
	if _rope == Rope.CARRY:
		if pressed:
			release()
		else:
			_carry(delta, origin, aim)
	if _rope == Rope.CARRY or _rope == Rope.FETCH:
		return false

	# Right on a tendril's marker: re-attach there, at once.
	if pressed and not _spots.is_empty() and not _coiling and hand_free:
		var pick := _spot_in_sight(origin, aim)
		if pick >= 0 and (infinite_charges or _player.stamina >= reattach_cost):
			if not infinite_charges:
				_player.drain_stamina(reattach_cost)
			_reattach(pick)
			return false

	# Pulled at a big enemy, a press means "ride it" (held till you arrive);
	# at a wall, a press in the last moments means let go at speed.
	if _rope == Rope.LASH or _rope == Rope.PULL:
		if _to_enemy:
			if pressed:
				_ride_wanted = true
			elif not held:
				_ride_wanted = false
		elif pressed and _rope == Rope.PULL and _time_to_arrive() <= perfect_window:
			_perfect_release()
		return false

	if _coiling:
		if not hand_free:
			_coiling = false # switched to a two-handed gun mid-coil
		elif held:
			_hold += delta
		else:
			_coiling = false
			if _hold < seed_tap_time and _player.virus.has(Virus.SEEDED):
				# A tap: Seeded Growth. With the whip too, it waits a beat for a
				# second tap (the user's: that one's the whip).
				if _player.virus.has(Virus.WHIP):
					_seed_wait = whip_double_tap
					_seed_aim = aim
				else:
					_seed_burst(origin, aim)
			elif _hold >= charge_time * min_charge_share:
				_charge_bonus = _hold >= charge_time and _hold <= charge_time + good_window
				_fire(origin, aim)
	elif pressed and _rope == Rope.NONE and not weapons.is_busy() and (infinite_charges or _player.stamina >= fire_cost):
		if hand_free or weapons.switch_to_one_handed():
			_coiling = true
			_hold = 0.0

	coil = clampf(_hold / charge_time, 0.0, 1.0) if _coiling else 0.0
	return false


## Holding it, winding it up.
func is_coiling() -> bool:
	return _coiling


## The tentacle is out (flying, stuck, or snapping back from a miss).
func is_out() -> bool:
	return _rope != Rope.NONE


## The left arm pushed out: the tentacle's out, or Seeded Growth just went.
func arm_out() -> bool:
	return is_out() or _seed_arm > 0.0


## Seeded Growth: where you aim, on what the grapple could grab, within its
## reach -- the ground under a big enemy aimed at -- five tentacles burst.
func _seed_burst(origin: Vector3, aim: Vector3) -> void:
	if _seed_cooldown_left > 0.0:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * max_range * _player.virus.reach_scale())
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return # out of reach (the ring's red)
	var target := hit.collider as Node3D
	var big := _big_enemy(target)
	if target and big == null and _is_small_enemy(target):
		return # (red too)
	var at: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if big != null or (target and target.get_node_or_null(^"Health") != null):
		var down := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 30.0, 1)
		if target is CollisionObject3D:
			down.exclude = [(target as CollisionObject3D).get_rid()]
		var ground := space.intersect_ray(down)
		if ground.is_empty():
			return
		at = ground.position
		normal = ground.normal
	if not infinite_charges and not _player.spend_bars(seed_cost):
		return
	_seed_cooldown_left = seed_cooldown
	_seed_arm = 0.35
	var decides := not Network.is_online() or multiplayer.is_server()
	SeededGrowth.burst(get_tree().current_scene, at, normal, decides, _player)
	if Network.is_online() and multiplayer.is_server():
		for peer in multiplayer.get_peers():
			if peer != _player.get_multiplayer_authority():
				_net_seed.rpc_id(peer, at, normal)


@rpc("any_peer", "call_remote", "reliable")
func _net_seed(at: Vector3, normal: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		SeededGrowth.burst(get_tree().current_scene, at, normal, false, _player)


## Where it's stuck (global), or INF if it isn't pulling you anywhere.
func anchor_point() -> Vector3:
	return _anchor_point() if is_pulling() and is_instance_valid(_anchor) else Vector3.INF


## True while the line is holding you (gravity and ground movement change).
func is_pulling() -> bool:
	return _rope == Rope.PULL or _rope == Rope.PERCH or _rope == Rope.RIDE or _rope == Rope.TOUCH


## Attached to anything: you (pulling, perched, riding), an item flying in,
## or a prop on it.
func is_attached() -> bool:
	return is_pulling() or _rope == Rope.FETCH or _rope == Rope.CARRY


## A prop hanging off it (left click throws: carry_fire()).
func is_carrying() -> bool:
	return _rope == Rope.CARRY


## Left click (held: `fire`) while a prop's on the tentacle: thrown where
## you look at throw_speed, on top of your own speed. True while carrying
## (the click is the throw's, not the gun's).
func carry_fire(fire: bool, aim: Vector3) -> bool:
	var fire_pressed := fire and not _carry_fire_prev
	_carry_fire_prev = fire
	if _rope != Rope.CARRY:
		return false
	if fire_pressed and is_instance_valid(_anchor) and _anchor is RigidBody3D:
		var prop := _anchor as RigidBody3D
		release()
		prop.linear_velocity = aim * throw_speed + _player.velocity
	return true


## True while it moves you entirely itself (perched, riding): no steering in
## the air then. Pulled, you can still steer.
func holds_still() -> bool:
	return _rope == Rope.PERCH or _rope == Rope.RIDE or _rope == Rope.TOUCH


## Perched on (or held against) a wall by it.
func is_perched() -> bool:
	return _rope == Rope.PERCH or _rope == Rope.TOUCH


## No gravity while it pulls or holds you.
func gravity_scale() -> float:
	return 0.0 if holds_still() or _rope == Rope.PULL else 1.0


## Called by PlayerMovement just before move_and_slide().
func apply_pull(delta: float) -> void:
	match _rope:
		Rope.RIDE:
			_ride(delta)
		Rope.PULL:
			_pull(delta)
		Rope.PERCH:
			_perch(delta)
		Rope.TOUCH:
			_touch(delta)


## Lets go without a hop (death, mantling, switching guns, out of stamina).
func release() -> void:
	if is_pulling():
		released.emit()
	if _rope == Rope.FETCH:
		_player.hand.cancel_fetch() # (out of stamina mid-flight: it drops)
	if _rope == Rope.CARRY and is_instance_valid(_anchor) and _anchor is RigidBody3D:
		var prop := _anchor as RigidBody3D
		prop.linear_velocity = prop.linear_velocity.limit_length(6.0) # let go: a toss, not a throw
	_rope = Rope.NONE
	_coiling = false
	_anchor = null
	_ride_wanted = false


func _fire(origin: Vector3, aim: Vector3) -> void:
	if not infinite_charges and not _player.spend_bars(fire_cost):
		_hold = 0.0
		return # out of stamina: nothing to throw it with
	_power = clampf(_hold / charge_time, min_charge_share, 1.0)
	_hold = 0.0
	release()
	_clear_spots() # a brand-new grapple: the old tendrils' spots go
	if _charge_bonus:
		charge_timed.emit()
	var reach := max_range * _power * _player.virus.reach_scale() # (Spinnerets: further)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach)
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	fired.emit(_power)
	var target: Node3D = null
	if not hit.is_empty():
		target = hit.collider as Node3D
	var big := _big_enemy(target)
	if target == null or (big == null and _is_small_enemy(target)):
		_rope = Rope.MISS
		_lash_end = origin + aim * reach if target == null else (hit.position as Vector3)
		_lash_time = 0.0
		_lash_total = miss_time
		missed.emit()
		return
	_anchor = target
	_anchor_local = target.global_transform.affine_inverse() * (hit.position as Vector3)
	_normal_local = (target.global_basis.inverse() * (hit.normal as Vector3)).normalized()
	_to_enemy = big != null
	# An item: into your right hand. A light prop: onto the tentacle. Anything
	# heavier (or fixed): you're pulled to it, as ever (the user's).
	_for_fetch = big == null and PlayerHand.is_item(target)
	_for_carry = big == null and not _for_fetch and target is RigidBody3D \
			and not (target as RigidBody3D).freeze and (target as RigidBody3D).mass <= MAX_CARRY
	_lash_end = hit.position
	_lash_time = 0.0
	_lash_total = origin.distance_to(hit.position) / lash_speed
	_rope = Rope.LASH


## It bit: the pull starts.
func _land() -> void:
	if not is_instance_valid(_anchor):
		_rope = Rope.NONE
		return
	if _for_fetch:
		_rope = Rope.FETCH
		_player.hand.fetch(_anchor)
		attached.emit(false)
		return
	if _for_carry:
		_rope = Rope.CARRY
		attached.emit(false)
		return
	var power_t := inverse_lerp(min_charge_share, 1.0, _power) if min_charge_share < 1.0 else 1.0
	_pull_speed = pull_speed * lerpf(min_speed_scale, 1.0, clampf(power_t, 0.0, 1.0))
	if _charge_bonus:
		_pull_speed *= charge_boost
	_rope = Rope.PULL
	_stalled = 0.0
	_last_distance = INF
	_kick_queued = false # (a fresh pull: no kick carried over)
	_kick_perfect = false
	_pull_velocity = Vector3.ZERO
	attached.emit(_to_enemy)
	if not _to_enemy and tendrils_enabled:
		_sprout(_anchor_point(), (_anchor.global_basis * _normal_local).normalized())


## The pull (the original, Titanfall 2 style): you're hauled toward the spot
## (it follows a moving one), building up to the pull speed and easing off
## as you get there; your own steering adds to it. Arriving -- or pressed
## against something on the way and getting no closer -- you perch; at a big
## enemy, you kick it or latch on.
func _pull(delta: float) -> void:
	var to := _to_spot()
	var distance := to.length()
	if _to_enemy:
		if distance <= kick_reach:
			if _ride_wanted:
				_start_ride()
			else:
				_kick(to / maxf(distance, 0.001))
			return
	else:
		# Into the wall: bounce or kick off it, never a slam (the user's).
		var hit := Vector3.ZERO
		for i in _player.get_slide_collision_count():
			var normal := _player.get_slide_collision(i).get_normal()
			if _pull_velocity.length_squared() > 1.0 and normal.dot(_pull_velocity.normalized()) < -0.5:
				hit = normal
				break
		if hit == Vector3.ZERO and distance <= wall_reach:
			hit = (_anchor.global_basis * _normal_local).normalized()
		if hit != Vector3.ZERO:
			_hit_wall(hit)
			return
	# Up against a ledge or a beam, no closer: perch where you are.
	var blocked := _player.get_slide_collision_count() > 0 and distance > _last_distance - 0.5 * delta
	_stalled = _stalled + delta if blocked else 0.0
	_last_distance = distance
	if _stalled > 0.3 and not _to_enemy:
		_start_perch()
		return
	var direction := to / distance
	# A heavy pack: pulled slower, and building up slower (Backpack.pull_scale()).
	var heavy := _player.backpack.pull_scale()
	# At a big enemy it eases in; into a wall it keeps its speed (you bounce).
	var speed := minf(_pull_speed * heavy, distance * arrive_slowdown) if _to_enemy else _pull_speed * heavy
	var along := _player.velocity.dot(direction)
	if along < speed:
		_player.velocity += direction * minf(pull_accel * heavy * delta, speed - along)
	_pull_velocity = _player.velocity # (what it hits a wall with, next tick)


## Seconds till the pull reaches the wall (INF if not pulled at one).
func _time_to_wall() -> float:
	if _rope != Rope.PULL or _to_enemy or not is_instance_valid(_anchor):
		return INF
	var to := _to_spot()
	var closing := maxf(_player.velocity.dot(to.normalized()), 1.0)
	return maxf(to.length() - wall_reach, 0.0) / closing


## Hit the wall facing `normal`: the path you'd glance off along (your
## speed reflected off it). Kicked already (Space in time): off you go;
## otherwise a moment against it (kick_grace) to kick, then a weak bounce.
func _hit_wall(normal: Vector3) -> void:
	var v := _pull_velocity if _pull_velocity.length_squared() > 1.0 else _player.velocity
	var into := v.dot(normal)
	_bounce_dir = (v - 2.0 * into * normal if into < 0.0 else v + normal * v.length() * 0.3).normalized()
	_bounce_speed = v.length()
	if _kick_queued:
		_wall_kick(_kick_perfect)
		return
	_rope = Rope.TOUCH
	_touch_left = kick_grace
	_player.velocity = Vector3.ZERO


## Off the wall: kick_keep of your speed along the bounce (perfect: kick_
## perfect_bonus more, and the chime); `weak`: just bounce_keep of it.
func _wall_kick(perfect: bool, weak: bool = false) -> void:
	var keep := bounce_keep if weak else kick_keep * (kick_perfect_bonus if perfect else 1.0)
	var direction := _bounce_dir if _bounce_dir != Vector3.ZERO else -_to_spot().normalized()
	var speed := maxf(_bounce_speed, pull_speed * 0.5) * keep
	_kick_queued = false
	_kick_perfect = false
	release()
	_player.velocity = direction * speed
	if perfect and not weak:
		launch_timed.emit() # the grapple's chime

## The three tendrils from a spot it bit (`at`, on a surface facing
## `normal`): fanned ahead the way you're flying (or up and onward), each to
## a level surface up to tendril_reach on; more angles tried if one misses.
func _sprout(at: Vector3, normal: Vector3) -> void:
	_clear_spots()
	_spots_from = at
	var ahead := _player.velocity
	ahead.y = 0.0
	if ahead.length_squared() < 1.0:
		ahead = -_player.global_basis.z
	ahead = ahead.normalized()
	var up := 0.15 if tendril_spread == TendrilSpread.FAN_AHEAD else 0.8
	var from := at + normal * 0.3
	var space := get_world_3d().direct_space_state
	for step: float in [0.0, -1.0, 1.0, -1.6, 1.6, -0.5, 0.5]:
		if _spots.size() >= 3:
			break
		var way := (ahead.rotated(Vector3.UP, deg_to_rad(tendril_fan_degrees) * step) + Vector3.UP * up).normalized()
		var query := PhysicsRayQueryParameters3D.create(from, from + way * tendril_reach)
		query.exclude = [_player.get_rid()]
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.position as Vector3).distance_to(at) < tendril_min_distance:
			continue
		if not LevelGeometry.is_static(hit.collider) or _is_small_enemy(hit.collider) or _big_enemy(hit.collider):
			continue
		var crowded := false
		for spot in _spots:
			if (spot.at as Vector3).distance_to(hit.position) < tendril_min_distance:
				crowded = true
		if not crowded:
			_spots.append({at = hit.position, normal = hit.normal, collider = hit.collider})
	_show_spots()


## The tendril spot your crosshair's right on (within marker_aim_degrees),
## or -1.
func _spot_in_sight(origin: Vector3, aim: Vector3) -> int:
	var best := -1
	var best_angle := deg_to_rad(marker_aim_degrees)
	for i in _spots.size():
		var angle := aim.angle_to((_spots[i].at as Vector3) - origin)
		if angle < best_angle:
			best_angle = angle
			best = i
	return best


## Re-attached to a tendril's spot: at once, faster (reattach_boost, up to
## the speed cap), heading there; the other spots vanish and the new one
## sprouts three more.
func _reattach(index: int) -> void:
	var spot: Dictionary = _spots[index]
	var target := spot.collider as Node3D
	release()
	_clear_spots()
	if not is_instance_valid(target):
		return
	_anchor = target
	_anchor_local = target.global_transform.affine_inverse() * (spot.at as Vector3)
	_normal_local = (target.global_basis.inverse() * (spot.normal as Vector3)).normalized()
	_to_enemy = false
	_charge_bonus = false
	var speed := _player.velocity.length()
	var cap := maxf(speed, _player.speed_cap)
	var faster := minf(maxf(speed, pull_speed) * (1.0 + reattach_boost), cap)
	_player.velocity = _to_spot().normalized() * faster
	_pull_speed = faster
	_rope = Rope.PULL
	_stalled = 0.0
	_last_distance = INF
	_lash_end = spot.at
	attached.emit(false)
	_sprout(spot.at, spot.normal)


func _clear_spots() -> void:
	_spots.clear()
	_show_spots()


## Seconds left till you arrive (INF if not pulled).
func _time_to_arrive() -> float:
	if _rope != Rope.PULL or _pull_speed <= 0.0:
		return INF
	var to := _to_spot()
	var closing := maxf(_player.velocity.dot(to.normalized()), _pull_speed * 0.5)
	return maxf(to.length() - arrive_distance, 0.0) / closing


## Let go at just the right moment in the flight: on past it, faster.
func _perfect_release() -> void:
	release()
	_player.velocity *= perfect_boost
	launch_timed.emit()


## Against the wall a moment (kick_grace) for a Space kick; none, and it's a
## weak bounce off it.
func _touch(delta: float) -> void:
	_player.velocity = Vector3.ZERO
	_touch_left -= delta
	if _touch_left <= 0.0:
		_wall_kick(false, true)


func _start_perch() -> void:
	# Arriving off the pull, your speed's kept for when you let go (the
	# user's: momentum is never cut).
	if _rope == Rope.PULL:
		_perch_kept = _player.velocity
	_rope = Rope.PERCH
	_player.velocity = Vector3.ZERO


## Stuck to the wall at the spot, till you jump off (Space). (Rappelling down
## the line and reeling back up are gone: the user's, 2026-10-16.)
func _perch(delta: float) -> void:
	var normal := (_anchor.global_basis * _normal_local).normalized()
	var spot := _anchor_point() + normal * perch_standoff - Vector3.UP * 0.9
	_player.velocity = ((spot - _player.global_position) / maxf(delta, 0.001)).limit_length(20.0)


## From the chest to the spot it's stuck to.
func _to_spot() -> Vector3:
	return _anchor_point() - (_player.global_position + Vector3.UP * 0.9)


func _let_go() -> void:
	var was_riding := _rope == Rope.RIDE
	var was_perched := _rope == Rope.PERCH
	release()
	if was_riding:
		_player.velocity = _ride_velocity
	elif was_perched and _perch_kept != Vector3.ZERO:
		# Off the wall with the speed you arrived at (on top of any sway).
		_player.velocity += _perch_kept
	_perch_kept = Vector3.ZERO
	_player.velocity.y = maxf(_player.velocity.y, 0.0) + release_hop


## A prop on the tentacle: kept carry_distance in front of your eyes, the
## old F prop mover's way -- its velocity set to close the gap by the next
## tick (no spring lag or swinging), capped; Jolt still collides it.
func _carry(delta: float, origin: Vector3, aim: Vector3) -> void:
	var prop := _anchor as RigidBody3D
	if prop == null:
		release()
		return
	var offset := origin + aim * carry_distance - prop.global_position
	if offset.length() > carry_distance * 5.0:
		release() # stuck behind something
		return
	prop.linear_velocity = (offset / maxf(delta, 0.001)).limit_length(carry_max_speed)
	prop.angular_velocity = Vector3.ZERO


# ---- The Tentacle whip (a mutation) ------------------------------------------------------

## The lash: whip_time long, sweeping whip_sweep_degrees across in front
## of you (right to left) out to whip_reach.
func _start_whip(aim: Vector3) -> void:
	_coiling = false
	_hold = 0.0
	_rope = Rope.WHIP
	_whip_time = 0.0
	_whip_aim = aim
	_whip_hit.clear()


## Each tick of the lash: while it's slung (whip_points()), the whip itself
## is the hitbox: everything it passes through takes whip_damage once.
func _whip(delta: float, origin: Vector3, _aim: Vector3) -> void:
	_whip_time += delta
	var t := clampf(_whip_time / whip_time, 0.0, 1.0)
	if t < WHIP_WINDUP or t > WHIP_THROW_END + 0.05:
		if t >= 1.0:
			_rope = Rope.NONE
		return # drawn back behind you, or gone slack: it hurts only as it's slung
	var points := whip_points(origin, t)
	var space := get_world_3d().direct_space_state
	if _whip_query == null:
		_whip_query = PhysicsShapeQueryParameters3D.new()
		_whip_capsule = CapsuleShape3D.new()
		_whip_capsule.radius = 0.2
		_whip_query.shape = _whip_capsule
		_whip_query.collide_with_areas = false
		_whip_query.exclude = [_player.get_rid()]
	# One capsule laid along each piece of the tentacle.
	for i in range(1, points.size()):
		var from := points[i - 1]
		var along := points[i] - from
		var length := along.length()
		if length < 0.01:
			continue
		_whip_capsule.height = length + _whip_capsule.radius * 2.0
		var up := along / length
		var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
		_whip_query.transform = Transform3D(Basis(side, up, side.cross(up)), from + along * 0.5)
		for hit in space.intersect_shape(_whip_query, 8):
			_whip_strike(hit.collider as Node, points[i])
	if t >= 1.0:
		_rope = Rope.NONE


## The lash, slung the way a real whip is (the user's: less wriggling). Drawn
## back behind you to the right (to WHIP_WINDUP); then the arm sweeps across
## and a loop rolls down the whip from the hand to the tip -- the part past
## the loop still lying back where it was -- till it's all straight out and
## the tip snaps past full length (to WHIP_THROW_END); then it goes slack,
## the tip dropping, and draws back in. The hitbox and what's drawn.
const WHIP_WINDUP := 0.18
const WHIP_THROW_END := 0.7
const WHIP_POINTS := 12


func whip_points(origin: Vector3, t: float) -> PackedVector3Array:
	var flat := Vector3(_whip_aim.x, 0.0, _whip_aim.z).normalized()
	if flat == Vector3.ZERO:
		flat = -_player.global_basis.z
	var half := deg_to_rad(whip_sweep_degrees) * 0.5
	var length := whip_reach
	var back_dir := (flat.rotated(Vector3.UP, -half - 1.2) + Vector3.DOWN * 0.35).normalized()
	var points := PackedVector3Array()
	if t < WHIP_WINDUP:
		var u := t / WHIP_WINDUP
		for i in WHIP_POINTS:
			var s := float(i) / (WHIP_POINTS - 1)
			points.append(origin + back_dir * s * length * lerpf(0.5, 1.0, u) + Vector3.DOWN * s * s * 0.4)
		return points
	if t < WHIP_THROW_END:
		var u := (t - WHIP_WINDUP) / (WHIP_THROW_END - WHIP_WINDUP)
		var unroll := 1.0 - pow(1.0 - minf(u * 1.4, 1.0), 2.0) # the loop rolls out fast
		var direction := flat.rotated(Vector3.UP, lerpf(-half, half, u)) # right to left
		direction.y = _whip_aim.y
		direction = direction.normalized()
		var fold := unroll * length
		var fold_at := origin + direction * fold
		var loop_lift := Vector3.UP * 0.35 * (1.0 - unroll)
		var tip_home := origin + back_dir * length
		var trail := (tip_home - fold_at).normalized()
		var snap := 1.0 + 0.08 * sin(clampf((u - 0.6) / 0.4, 0.0, 1.0) * PI) # the crack
		for i in WHIP_POINTS:
			var s := float(i) / (WHIP_POINTS - 1) * length
			if s <= fold:
				points.append(origin + direction * s * (snap if unroll >= 1.0 else 1.0))
			else:
				points.append(fold_at + loop_lift + trail * (s - fold))
		return points
	var slack := (t - WHIP_THROW_END) / (1.0 - WHIP_THROW_END)
	var end := flat.rotated(Vector3.UP, half)
	end.y = _whip_aim.y
	end = end.normalized()
	for i in WHIP_POINTS:
		var s := float(i) / (WHIP_POINTS - 1)
		points.append(origin + end * s * length * (1.0 - slack * 0.85) + Vector3.DOWN * s * s * 1.2 * slack)
	return points


func _whip_strike(collider: Node, at: Vector3) -> void:
	var node := collider
	while node != null and node.get_node_or_null(^"Health") == null:
		node = node.get_parent()
	if node == null or node.is_in_group("player") or _whip_hit.has(node):
		return # (never a teammate)
	if Network.is_online() and not multiplayer.is_server():
		return # the host's call, like all damage (it runs this tick too)
	_whip_hit.append(node)
	var health := node.get_node(^"Health") as Health
	var direction := (at - _player.global_position).normalized()
	health.take_damage(whip_damage, _attacker_id, direction, at, 6.0)
	Factions.provoke(node, _player)
	_player.weapons.hit_confirmed.emit(health.is_dead, WeaponController.HitKind.NORMAL)


func _kick(direction: Vector3) -> void:
	var speed := _player.velocity.length()
	var damage := kick_damage_per_speed * speed
	var health := _anchor.get_node_or_null("Health") as Health
	if health:
		health.take_damage(damage, _attacker_id, direction, _anchor_point(), 6.0)
		_player.weapons.hit_confirmed.emit(health.is_dead, WeaponController.HitKind.NORMAL)
	Factions.provoke(_anchor, _player)
	kicked.emit(damage)
	release()
	_player.velocity = -direction * kick_bounce + Vector3.UP * kick_bounce_up


func _start_ride() -> void:
	_rope = Rope.RIDE
	_ride_prev = _anchor_point()
	_ride_velocity = Vector3.ZERO


## Hanging off the enemy: you're carried along with the grabbed spot.
func _ride(delta: float) -> void:
	var point := _anchor_point()
	_ride_velocity = (point - _ride_prev) / maxf(delta, 0.001)
	_ride_prev = point
	var normal := (_anchor.global_basis * _normal_local).normalized()
	var spot := point + normal * ride_standoff - Vector3.UP * 0.9
	_player.velocity = ((spot - _player.global_position) / maxf(delta, 0.001)).limit_length(60.0)


func _anchor_point() -> Vector3:
	return _anchor.global_transform * _anchor_local


## The big enemy `node` is part of (it or a parent is in BIG_GROUP), or null.
func _big_enemy(node: Node) -> Node:
	while node != null:
		if node.is_in_group(BIG_GROUP):
			return node
		node = node.get_parent()
	return null


func _is_small_enemy(node: Node) -> bool:
	while node != null:
		if node.is_in_group("enemies"):
			return true
		node = node.get_parent()
	return false


# --- Sound (your own: the timing rewards) ---

func _chime_play(for_charge: bool) -> void:
	if not _player.is_multiplayer_authority():
		return
	if _chime == null:
		_chime = AudioStreamPlayer.new()
		_chime.bus = &"Player" if AudioServer.get_bus_index(&"Player") != -1 else &"Master"
		add_child(_chime)
	var custom := charge_timed_sound if for_charge else launch_timed_sound
	_chime.stream = custom if custom else _make_chime(880.0 if for_charge else 1320.0, 0.14 if for_charge else 0.2)
	_chime.play()


## A short bright chime, rising a fifth (placeholder until the user's sounds).
static func _make_chime(pitch: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for i in frames:
		var t := float(i) / frames
		phase += TAU * pitch * lerpf(1.0, 1.5, minf(t * 3.0, 1.0)) / rate
		var envelope := minf(t * 40.0, 1.0) * pow(1.0 - t, 2.0)
		var sample := (sin(phase) * 0.7 + sin(phase * 2.0) * 0.2) * envelope * 0.6
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


# --- Drawing (per peer, never touches the simulation) ---

## Your own view: while you hold the grapple, the ring (GrappleIndicator) on
## whatever it would grab at the reach this charge gives -- the same ray it
## fires -- filling like a dial; red where it'd give out if there's nothing.
func _update_indicator(delta: float) -> void:
	var camera := _player.camera
	if not _coiling or camera == null or not camera.current:
		if _indicator:
			_indicator.hide_ring()
		return
	if _indicator == null:
		_indicator = GrappleIndicator.new()
		add_child(_indicator)
	var origin := camera.global_position
	var aim := -camera.global_basis.z
	var power := clampf(_hold / charge_time, min_charge_share, 1.0)
	var reach := max_range * power
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach)
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var fill := clampf(_hold / charge_time, 0.0, 1.0)
	if hit.is_empty():
		_indicator.show_at(origin + aim * reach, Vector3.UP, false, fill, origin, delta)
		return
	var target := hit.collider as Node3D
	var grabs := target != null and (_big_enemy(target) != null or not _is_small_enemy(target))
	_indicator.show_at(hit.position, hit.normal, grabs, fill, origin, delta)


## Your own view: each tendril spot's tendril (a dark line from where it
## sprouted) and its M2 marker floating over it (the same size at any
## distance, seen through walls; yellow while your crosshair's right on it).
func _show_spots() -> void:
	for mark in _spot_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_spot_marks.clear()
	if _player == null or not _player.is_multiplayer_authority() or not is_inside_tree():
		return
	for spot in _spots:
		var at: Vector3 = spot.at
		var mark := Node3D.new()
		mark.top_level = true
		add_child(mark)
		var line := MeshInstance3D.new()
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := BoxMesh.new()
		box.size = Vector3(line_width, line_width, 1.0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = line_color
		box.material = material
		line.mesh = box
		mark.add_child(line)
		var length := _spots_from.distance_to(at)
		if length > 0.01:
			var along := (at - _spots_from) / length
			var up := Vector3.UP if absf(along.y) < 0.99 else Vector3.FORWARD
			line.global_transform = Transform3D(Basis.looking_at(along, up) * Basis.from_scale(Vector3(1.0, 1.0, length)), (_spots_from + at) * 0.5)
		var label := Label3D.new()
		label.text = "M2"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 40
		label.outline_size = 10
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		label.render_priority = 10
		mark.add_child(label)
		label.global_position = at + (spot.normal as Vector3) * 0.3 + Vector3.UP * 0.25
		_spot_marks.append(mark)


## The marker your crosshair's right on, yellow; the rest pale.
func _light_spot_in_sight() -> void:
	if _spot_marks.is_empty() or _player.camera == null:
		return
	var camera := _player.camera
	var pick := _spot_in_sight(camera.global_position, -camera.global_basis.z)
	for i in _spot_marks.size():
		var mark := _spot_marks[i]
		if not is_instance_valid(mark) or mark.get_child_count() < 2:
			continue
		(mark.get_child(1) as Label3D).modulate = Color(1.0, 0.85, 0.15) if i == pick else Color(0.95, 0.93, 0.86, 0.85)


## Where the tentacle's tip is right now, or INF while it isn't out (the host
## sends this with each player's update).
func rope_tip() -> Vector3:
	match _rope:
		Rope.LASH:
			return _start_point().lerp(_lash_end, clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0))
		Rope.MISS:
			var t := clampf(_lash_time / maxf(_lash_total, 0.001), 0.0, 1.0)
			return _start_point().lerp(_lash_end, sin(t * PI)) # out and snaps back
		Rope.PULL, Rope.PERCH, Rope.RIDE, Rope.CARRY, Rope.TOUCH:
			if is_instance_valid(_anchor):
				return _anchor_point()
		Rope.FETCH:
			# The item as it flies in (the hand moves it, not its own body).
			if is_instance_valid(_anchor):
				return _anchor_point()
		Rope.WHIP:
			var points := whip_points(_start_point(), clampf(_whip_time / whip_time, 0.0, 1.0))
			return points[points.size() - 1]
	return Vector3.INF


## Co-op: someone else's grapple, drawn from the host's word (INF: not out).
func show_remote(tip: Vector3) -> void:
	_remote_tip = tip


func _process(delta: float) -> void:
	var tip := rope_tip()
	if not tip.is_finite() and _rope == Rope.NONE:
		tip = _remote_tip
	var showing := tip.is_finite()
	if not showing:
		tip = Vector3.ZERO
	var mine := _player.is_multiplayer_authority()
	if mine:
		_ensure_tentacle()
		var normal := (_anchor.global_basis * _normal_local).normalized() if is_instance_valid(_anchor) else Vector3.UP
		# Gripping: its tip splits into the little tendrils over whatever it
		# holds -- a wall, an item flying in, a prop on it (the user's).
		var stuck := is_attached()
		var arm_points: Array[Vector3] = []
		var arm_coil := 0.0
		if is_instance_valid(arms) and arms.raise > 0.01:
			arm_points = arms.left_arm_points()
			arm_coil = arms.coil
		var path := whip_points(_start_point(), clampf(_whip_time / whip_time, 0.0, 1.0)) if _rope == Rope.WHIP else PackedVector3Array()
		_tentacle.show_rope(showing, _start_point(), tip, normal, stuck, arm_points, arm_coil, delta, path)
		_update_indicator(delta)
		_light_spot_in_sight()
		if _line:
			_line.visible = false
	else:
		_ensure_line()
		_line.visible = showing
		if showing:
			var start := _start_point()
			var length := start.distance_to(tip)
			if length > 0.01:
				var along := (tip - start) / length
				var up := Vector3.UP if absf(along.y) < 0.99 else Vector3.FORWARD
				var facing := Basis.looking_at(along, up) * Basis.from_scale(Vector3(1.0, 1.0, length))
				_line.global_transform = Transform3D(facing, (start + tip) * 0.5)


func _start_point() -> Vector3:
	if is_instance_valid(arms) and arms.raise > 0.01:
		var points := arms.left_arm_points()
		return points[2] + points[3] * 0.06 # out of the palm
	if _player.is_multiplayer_authority() and _player.camera.current:
		return _player.camera.global_transform * view_origin
	return _player.global_transform * body_origin


func _ensure_tentacle() -> void:
	if _tentacle == null:
		_tentacle = GrappleTentacle.new()
		add_child(_tentacle)


func _ensure_line() -> void:
	if _line:
		return
	_line = MeshInstance3D.new()
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(line_width, line_width, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = line_color
	box.material = material
	_line.mesh = box
	add_child(_line)
