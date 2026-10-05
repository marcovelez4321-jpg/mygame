class_name PlayerMovement
extends CharacterBody3D

## Quake 3 strafe-jumping movement. Locked to a single style (no more
## CPMA/Hybrid presets) so every constant here is a real, final competitive
## number a networked build has to reproduce exactly on the server -- not a
## design option to keep re-deriving later.

## Presentation-only events for sound (player_sound.gd) -- fired at the exact
## points the existing camera shake/kick calls already mark as "this
## happened" (see _simulate_movement()'s jump branch, _start_dash(),
## _wall_jump()). Nothing in simulation reads these back; they exist purely
## so a listener can react, the same reason weapon_controller.gd has
## shot_fired/hit_confirmed.
signal jumped
signal dashed
signal wall_jumped
signal mantled

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.0025

@export_group("General Movement")
@export var gravity: float = 20.0
@export var jump_velocity: float = 6.5
@export var ground_max_speed: float = 7.0
@export var ground_accel: float = 14.0
@export var ground_friction: float = 6.0
@export var stop_speed: float = 1.5
## If true, holding jump keeps bhopping automatically on every landing.
## If false, you must tap jump right as you land, like vanilla Quake.
@export var auto_bhop: bool = true

@export_group("Air Movement (Quake 3 PM_AirAccelerate)")
## How much speed you gain per strafe cycle in the air.
@export var air_accel: float = 10.0
## Ceiling on the wishspeed used while airborne (recreates Quake's classic
## 30-unit air-speed cap, converted to meters). Lower = tighter curves.
@export var air_cap_speed: float = 3.0

@export_group("Stairs")
## Tallest ledge you walk up automatically, without jumping. Quake uses 18
## units (~0.56 m); we use 0.5 m (16 map units, about 1 ft 8 in). Build
## stairs with each step at or below this height.
@export var step_height: float = 0.5

@export_group("Death")
## Seconds between dying and the level restarting.
@export var respawn_delay: float = 2.0

@export_group("Stamina")
## Deadlock-style: a small number of discrete charges (shown as pips in the
## HUD, see hud.gd/hud.tscn's StaminaBar) rather than a continuous meter --
## dash and wall jump each spend exactly one.
@export var max_stamina_charges: int = 3
## Seconds for ONE spent charge to fully refill.
@export var stamina_recharge_time: float = 2.0
## Pause after spending a charge before that pip starts refilling again --
## without this, tapping dash repeatedly at the exact regen rate would never
## actually run you out.
@export var stamina_recharge_delay: float = 0.5

@export_group("Dash")
@export var dash_speed: float = 16.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.6
## A little extra vertical pop if you're looking upward when you dash --
## scales with how far up you're looking (0 at the horizon, full strength
## looking straight up), so aiming up turns the dash into a small assisted
## hop instead of a second jump. Kept deliberately small.
@export var dash_up_boost: float = 5.0

@export_group("Wall Jump")
## How far BEHIND the player counts as "against a wall" for a wall jump --
## checked specifically behind you (the opposite of your look direction), not
## any nearby wall in any direction. That's deliberate: it's a position check
## ("is there a wall at my back?"), not "am I actively colliding with one
## this exact tick" -- so you don't have to be strafing INTO a wall to
## trigger this, you just have to have your back to one and jump.
@export var wall_check_distance: float = 0.7
## How far off "dead behind you" a wall can be and still count, in degrees
## each way -- 0 would mean only a wall exactly behind you works; higher
## forgives you not facing directly away from it. See _find_wall_behind().
@export_range(0.0, 90.0, 5.0) var wall_behind_angle: float = 50.0
## How many raycasts sweep across wall_behind_angle looking for a wall. Odd
## numbers include a straight-behind ray; more rays = finer coverage, still
## cheap since this only runs on a fresh jump press, not every tick.
@export var wall_behind_ray_count: int = 5
## Push straight away from the wall's own surface -- guarantees you actually
## clear it, blended with wall_jump_look_speed below rather than used alone.
@export var wall_jump_push: float = 3.0
## How much of the kick follows wherever you're actually AIMING, not just
## straight off the wall's surface -- this is the part that makes it read as
## leaping/kicking off toward your look direction instead of climbing.
@export var wall_jump_look_speed: float = 5.0
@export var wall_jump_up_velocity: float = 11.0
## Same hit-stop trick as stomp_hit_stop_scale/stomp_hit_stop_time (see that
## export's comment for the co-op caveat), but much lighter -- a wall jump
## happens constantly during normal traversal, not just on a rare kill, so
## this needs to read as a snappy little "oomph" and be gone before it's
## noticed as slowdown, not a dramatic freeze-frame.
@export_range(0.0, 1.0, 0.05) var wall_jump_hit_stop_scale: float = 0.3
@export var wall_jump_hit_stop_time: float = 0.04

@export_group("Mantle")
## Turns mantling on/off entirely.
@export var mantle_enabled: bool = true
## How far ahead (meters) the wall-detection probe reaches -- short on
## purpose, this is "is there a ledge basically right in front of my face",
## not a long-range grapple.
@export var mantle_forward_distance: float = 1.0
## Ledge height range (meters), measured from the player's feet, that counts
## as mantleable. Below mantle_min_height, _try_step_up() already carries you
## up silently with no space press needed -- keep this at or above
## step_height so there's no dead zone between the two systems. Above
## mantle_max_height it's just out of reach.
@export var mantle_min_height: float = 0.6
@export var mantle_max_height: float = 2.1
## How wide a fan of rays sweeps the wall-detection probe, in degrees each
## way, and how many rays make up that fan -- same "don't require pixel-
## perfect aim" technique _find_wall_behind() already uses for the wall-jump
## check. Without this, the probe was a SINGLE ray along the camera's exact
## look direction (pitch included), so missing the ledge by even a couple
## degrees -- or just looking slightly up/down at it, which is normal when
## approaching one -- made detection miss entirely. That's what "inconsistent"
## was: not a bug in the climb itself, a too-narrow, too-strict probe.
@export_range(0.0, 45.0, 5.0) var mantle_probe_angle: float = 30.0
@export var mantle_probe_ray_count: int = 5
## How long, after a valid ledge was LAST seen, a space press still grabs it --
## this is the "timing" in mantle: you get a short window, not an infinite
## hold. Ledge detection runs every tick (see _simulate_movement()) whether or
## not space is pressed, refreshing this timer back to full each time a valid
## ledge is in view; a space TAP only succeeds while it's still counting down.
## Long enough that a natural glance-then-jump doesn't whiff, short enough
## that mashing space nowhere near a ledge never grabs one.
@export var mantle_grace_time: float = 0.25
## How long the pull-up itself takes once triggered.
@export var mantle_duration: float = 0.35
## Rule 3 (competitive balance): a mantle is a MOVEMENT tool, not free
## verticality -- it reaches ledges you could otherwise only get to with a
## jump/dash/wall-jump combo, it doesn't let you skip needing one. Revisit
## mantle_max_height if playtesting shows it trivializing a height an
## opponent has to actually work for.
@export var mantle_cooldown: float = 0.4

@export_group("Enemy Stomp")
## Hitting an enemy while airborne at at least this total speed (m/s, the
## full 3D velocity, not just horizontal) counts as a stomp instead of just
## bumping into them. Deliberately NOT limited to landing on top of them --
## any approach angle counts, like skipping a stone off water. Speed is what
## matters here, not the angle you came in at.
@export var stomp_min_speed: float = 6.0
## Horizontal speed after the stomp = speed at the moment of impact * this.
@export var stomp_speed_boost: float = 1.4
## The big pop straight toward wherever you're looking, like a rocket jump
## off their skull.
@export var stomp_jump_velocity: float = 11.0
## Push fed into the enemy's ragdoll (the same last_hit_impulse a gunshot
## leaves), so the kill reads as "stomped", not "died where it stood".
@export var stomp_impact_force: float = 10.0
## Brief global time_scale dip right on a stomp kill -- deliberately only
## here, not on every kill, so it reads as "that one's special" instead of
## diluting into a generic hit-feel every enemy death gets. Not co-op safe as
## written (Engine.time_scale is global, not per-client) -- fine for now
## since there's no networking yet; revisit when co-op lands.
@export_range(0.0, 1.0, 0.05) var stomp_hit_stop_scale: float = 0.05
## Real seconds (not scaled) the dip lasts before resuming at normal speed.
@export var stomp_hit_stop_time: float = 0.06

## One tick's worth of player intent, packaged up so simulation code never
## has to touch Input directly. Rule 1 (multiplayer-ready): this is the seam
## a networked build plugs into later -- a client fills this from its own
## keyboard/mouse for its own body and sends it to the server, and reads it
## back off the network for every other body. `_simulate_movement()` below
## never changes either way.
class PlayerInput:
	var wishdir: Vector2 = Vector2.ZERO   # x = strafe (+right), y = forward(-)/back(+)
	var look_delta: Vector2 = Vector2.ZERO # mouse motion this tick, already scaled by sensitivity
	var want_jump: bool = false
	var want_dash: bool = false
	var fire: bool = false
	var reload: bool = false
	var grab: bool = false
	var select_weapon: int = -1 # inventory index chosen on the weapon wheel, -1 = no change

## Result of _find_mantle_ledge(): whether a valid ledge was found, and where
## its landing spot is. A plain bool return can't also carry a position
## cleanly, and Vector3.ZERO is a real, reachable world position (unlike
## _find_wall_behind()'s use of it for a normal, which is never zero-length
## when valid) -- so this is its own tiny result type instead, same idea as
## PlayerInput itself.
class MantleTarget:
	var found: bool = false
	var position: Vector3 = Vector3.ZERO

@onready var head: Node3D = $Head
@onready var camera: CameraJuice = $Head/Camera3D
@onready var weapons: WeaponController = $WeaponController
@onready var grabber: PhysicsGrabber = $PhysicsGrabber
@onready var health: Health = $Health

## How far ahead we look when deciding whether a ledge is a walkable step.
const STEP_PROBE_DISTANCE := 0.1
## Extra downward reach when looking for the top of a step, so float error
## can't make us miss it.
const STEP_DOWN_MARGIN := 0.05
## Ignore "steps" smaller than this (meters); it's just collision noise.
const MIN_STEP_RISE := 0.02

var _pitch: float = 0.0
var _jump_held_prev: bool = false
var _dash_held_prev: bool = false
var _pending_look_delta: Vector2 = Vector2.ZERO
## Weapon picked on the wheel since the last tick. The wheel is local UI; this
## hand-off is what turns the pick into part of the input packet.
var _pending_weapon_select: int = -1
var _is_dead: bool = false

## How many stamina charges are currently available (0..max_stamina_charges).
## Public so hud.gd can read it straight off the player for the pip display.
var stamina_charges: int = 0
## 0..1 fill progress of the NEXT charge that's currently regenerating (the
## HUD reads this for the one pip that's mid-refill). Public for the same
## reason as stamina_charges.
var stamina_recharge_fraction: float = 0.0
var _stamina_regen_timer: float = 0.0

var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO

## One wall jump, then nothing more until you touch the ground or dash --
## otherwise you could just alternate walls forever and never actually fall.
## Reset to false wherever landing and dashing already happen (see
## is_on_floor() branch below and _start_dash()), set true in _wall_jump().
var _wall_jumped_since_reset := false

## Seconds left in an in-progress mantle; <= 0 means not mantling. The actual
## climb is driven by a Tween (see _start_mantle()) animating global_position
## directly; this timer just gates "skip normal movement" in
## _simulate_movement() for the same span, so the two can't drift apart.
var _mantle_time_left: float = 0.0
var _mantle_cooldown_left: float = 0.0
## Landing spot from the most recent successful _find_mantle_ledge() scan,
## and how much of mantle_grace_time is left to still use it -- see that
## export's comment. Position is only meaningful while the timer is > 0.
var _last_mantle_ledge_position: Vector3 = Vector3.ZERO
var _mantle_grace_left: float = 0.0

# Reused every tick instead of allocating new ones (Rule 2: no per-frame
# allocations in the physics loop).
var _step_params := PhysicsTestMotionParameters3D.new()
var _step_result := PhysicsTestMotionResult3D.new()


## The player THIS game client controls. In co-op the "player" group holds
## everyone, so anything that means "me" (pause menu settings, ambience
## around the listener) asks this instead of grabbing the first player.
## Offline it's simply the only player.
static func local_player(tree: SceneTree) -> PlayerMovement:
	for node in tree.get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			return node as PlayerMovement
	return null


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Saved sensitivity from the pause menu, if the player has ever set one.
	if GameSettings.mouse_sensitivity > 0.0:
		mouse_sensitivity = GameSettings.mouse_sensitivity
	health.died.connect(_on_died)
	stamina_charges = max_stamina_charges
	# Camera juice is purely cosmetic feedback (Rule 1) -- driven off the same
	# signals the HUD's own hit marker uses, so gunplay reads as impactful
	# without touching the actual aim/shot math at all.
	weapons.shot_fired.connect(_on_shot_fired)
	weapons.hit_confirmed.connect(_on_hit_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse capture/recapture is owned entirely by PauseMenu -- this stays
	# local presentation only, buffering raw look motion for the next
	# physics tick, so all rotation still happens inside the deterministic
	# simulation step.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pending_look_delta += event.relative


## Called by the weapon wheel (HUD) when the player picks a weapon.
func request_weapon(index: int) -> void:
	_pending_weapon_select = index


func _physics_process(delta: float) -> void:
	if _is_dead:
		_pending_look_delta = Vector2.ZERO # mouse movement is ignored while dead
		return
	var input := _gather_input()
	_simulate_movement(input, delta)


## Freeze the player and restart the level after a short delay.
## Rule 1: reloading the whole scene only makes sense offline. In co-op this
## becomes "respawn at a spawn point" (and the level keeps running for the
## other player), so it's kept in this one small function.
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	_is_dead = true
	velocity = Vector3.ZERO
	get_tree().create_timer(respawn_delay).timeout.connect(_restart_level)


func _restart_level() -> void:
	get_tree().reload_current_scene()


## The ONLY function allowed to touch Input/keyboard/mouse state. Everything
## downstream works from the PlayerInput it returns.
func _gather_input() -> PlayerInput:
	var input := PlayerInput.new()

	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	input.wishdir = move.normalized()

	input.want_jump = Input.is_physical_key_pressed(KEY_SPACE)
	input.want_dash = Input.is_physical_key_pressed(KEY_SHIFT)
	# Only count clicks while the mouse is captured, so clicking menu buttons
	# never fires the gun.
	input.fire = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	input.reload = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_physical_key_pressed(KEY_R)
	input.grab = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_physical_key_pressed(KEY_F)

	input.select_weapon = _pending_weapon_select
	_pending_weapon_select = -1

	input.look_delta = _pending_look_delta * mouse_sensitivity
	_pending_look_delta = Vector2.ZERO

	return input


## Pure simulation step: current state + one tick of input -> new state.
## Deliberately has no idea whether `input` came from a keyboard or a
## network packet -- that's what makes this reusable once there's a server.
func _simulate_movement(input: PlayerInput, delta: float) -> void:
	rotate_y(-input.look_delta.x)
	_pitch = clamp(_pitch - input.look_delta.y, deg_to_rad(-89.0), deg_to_rad(89.0))
	head.rotation.x = _pitch

	_mantle_cooldown_left = maxf(_mantle_cooldown_left - delta, 0.0)

	# Already mid-mantle: run the scripted pull-up and skip everything else
	# below (gravity, ground/air movement, wall jump) until it finishes --
	# see _update_mantle()'s own comment for why this is a direct position
	# move rather than velocity + move_and_slide like the rest of this file.
	if _mantle_time_left > 0.0:
		_update_mantle(delta)
		_finish_tick(input, delta)
		return

	# Scan for a mantleable ledge every tick -- not just when space is
	# pressed -- so mantle_grace_left tracks "how recently was a valid ledge
	# actually in view" independent of when you happen to hit the key. Cheap
	# (a handful of raycasts, same cost class as _find_wall_behind() already
	# runs on every wall-jump attempt), and skipped entirely on cooldown.
	if mantle_enabled and _mantle_cooldown_left <= 0.0:
		var ledge := _find_mantle_ledge()
		if ledge.found:
			_last_mantle_ledge_position = ledge.position
			_mantle_grace_left = mantle_grace_time
		else:
			_mantle_grace_left = maxf(_mantle_grace_left - delta, 0.0)
	else:
		_mantle_grace_left = 0.0

	var fresh_jump: bool = input.want_jump and not _jump_held_prev

	# Mantle needs a TIMED tap, not a hold -- a fresh press (this tick's
	# want_jump wasn't already true last tick) while the grace window is
	# still open. Holding space through the window only gets you ONE
	# mantle at the moment you first pressed, same as it only gets you one
	# jump; you don't get to just hold the key and let the game decide when
	# to grab. Checked BEFORE the normal jump/wall-jump handling below, so a
	# successful mantle consumes the tap instead of also triggering a jump
	# this same tick.
	if fresh_jump and mantle_enabled and _mantle_cooldown_left <= 0.0 and _mantle_grace_left > 0.0:
		_start_mantle(_last_mantle_ledge_position)
		_finish_tick(input, delta)
		return

	_update_stamina(delta)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)

	var wishdir := Vector3.ZERO
	if input.wishdir != Vector2.ZERO:
		wishdir = (transform.basis * Vector3(input.wishdir.x, 0.0, input.wishdir.y)).normalized()

	var fresh_dash: bool = input.want_dash and not _dash_held_prev
	if fresh_dash and _dash_cooldown_left <= 0.0 and _spend_stamina():
		_start_dash(wishdir)

	var was_airborne := not is_on_floor()

	if is_on_floor():
		_wall_jumped_since_reset = false # touching ground resets the wall-jump limiter
		_ground_move(wishdir, delta)
		var do_jump: bool = input.want_jump if auto_bhop else (input.want_jump and not _jump_held_prev)
		if do_jump:
			velocity.y = jump_velocity
			jumped.emit()
		_try_step_up(delta)
	else:
		velocity.y -= gravity * delta
		_air_move(wishdir, delta)

		# Wall jump: airborne only (it's an air-movement tool, not a way to
		# cancel a step-up), and a fresh press so holding jump against a wall
		# doesn't refire it every tick. _find_wall_behind() is a position
		# check (is there a wall behind me?), not "am I actively colliding
		# with one this exact tick" -- so you don't have to be strafing INTO
		# the wall for this to trigger, and since the wall's specifically
		# BEHIND you, the leap is naturally away from it instead of fighting
		# whatever direction you're holding. Only one per ground touch/dash
		# (_wall_jumped_since_reset) -- otherwise you could just ping-pong
		# between two walls forever and never actually fall.
		# fresh_jump was already computed above (before the mantle check), and
		# _jump_held_prev doesn't change until _finish_tick() at the end of
		# this same tick, so it's still valid to reuse here.
		if fresh_jump and not _wall_jumped_since_reset:
			var wall_normal := _find_wall_behind()
			if wall_normal != Vector3.ZERO and _spend_stamina():
				_wall_jump(wall_normal)

	if _dash_time_left > 0.0:
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed

	# Captured right before move_and_slide() changes anything, so the stomp
	# check below judges the speed that actually went INTO the hit, not
	# whatever's left after the collision itself slowed it down.
	var pre_slide_speed := velocity.length()

	move_and_slide()

	if was_airborne:
		_check_enemy_stomp(pre_slide_speed)

	_finish_tick(input, delta)


## Shared tail end of a tick: remembers this tick's held-button state for
## next tick's "fresh press" checks, then hands off to weapons/grabber. Every
## exit point of _simulate_movement() (normal movement, and the two early
## mantle returns above) goes through this so none of them can forget a step
## the others do.
func _finish_tick(input: PlayerInput, delta: float) -> void:
	_jump_held_prev = input.want_jump
	_dash_held_prev = input.want_dash

	# Aim comes from the player's own state (head position and facing), not
	# from the camera, so a server can rebuild the same shot (Rule 1).
	# multiplayer.get_unique_id() is 1 offline, which matches the host's id.
	weapons.tick(input.fire, input.reload, input.select_weapon, delta, head.global_position, -head.global_transform.basis.z, multiplayer.get_unique_id())
	grabber.tick(input.grab, delta, head.global_position, -head.global_transform.basis.z)


func _update_stamina(delta: float) -> void:
	if _stamina_regen_timer > 0.0:
		_stamina_regen_timer = maxf(_stamina_regen_timer - delta, 0.0)
		return
	if stamina_charges >= max_stamina_charges:
		return
	stamina_recharge_fraction += delta / stamina_recharge_time
	if stamina_recharge_fraction >= 1.0:
		stamina_recharge_fraction = 0.0
		stamina_charges += 1


## Spends one charge if any are available. Both dash and wall jump go through
## this instead of checking stamina_charges themselves, so "can I afford
## this" and "pay for it" can never drift apart.
func _spend_stamina() -> bool:
	if stamina_charges <= 0:
		return false
	stamina_charges -= 1
	stamina_recharge_fraction = 0.0
	_stamina_regen_timer = stamina_recharge_delay
	return true


## A short, direct burst of speed toward wishdir (or straight ahead if no
## movement keys are held) -- horizontal only, so it can't be used to cancel
## a fall the way a wall jump or the normal jump would.
func _start_dash(wishdir: Vector3) -> void:
	_dash_dir = wishdir if wishdir != Vector3.ZERO else -transform.basis.z
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	_wall_jumped_since_reset = false # dashing also refreshes the wall-jump limiter

	# How far up you're looking, from the ACTUAL look direction (not a raw
	# pitch angle -- same reasoning as look_dir elsewhere in this file), so
	# 0 at the horizon and 1.0 dead straight up. Only added, never
	# subtracted, so looking down doesn't turn a dash into extra fall speed.
	var look_up: float = (-head.global_transform.basis.z).y
	if look_up > 0.0:
		velocity.y += look_up * dash_up_boost

	camera.shake(2.0)
	camera.kick_fov(12.0)
	dashed.emit()


## Kicks off the wall found at our back, toward wherever we're actually
## LOOKING -- not just straight off its surface. Blends two pieces: the
## wall's own normal (wall_jump_push) so you're guaranteed to actually clear
## it even facing almost along its length, and your current look direction
## (wall_jump_look_speed, usually the bigger of the two) so the leap follows
## your aim, like kicking off a wall toward a target instead of just bouncing
## off it. In practice these two usually point close to the same way, since
## `wall_normal` came from a wall specifically BEHIND you (see
## _find_wall_behind()) -- which is exactly why the leap reads as clean and
## intentional instead of a random bounce. Sets velocity directly rather than
## adding to it, so your aim decides where you go.
func _wall_jump(wall_normal: Vector3) -> void:
	var look_dir := -head.global_transform.basis.z
	look_dir.y = 0.0
	look_dir = look_dir.normalized() if look_dir.length_squared() > 0.0001 else wall_normal
	var launch := wall_normal * wall_jump_push + look_dir * wall_jump_look_speed
	velocity.x = launch.x
	velocity.z = launch.z
	velocity.y = wall_jump_up_velocity
	_wall_jumped_since_reset = true
	camera.shake(3.0)
	camera.kick_fov(6.0)
	_hit_stop(wall_jump_hit_stop_scale, wall_jump_hit_stop_time)
	wall_jumped.emit()


## Is there a wall at our BACK? A position check, not "am I actively
## colliding with one this exact tick" -- that's what used to make wall jump
## only trigger while actively strafing into a wall (is_on_wall() only
## reflects an actual collision from the last move_and_slide()). The body's
## own -Z is always the look direction (rotate_y() in _simulate_movement()
## turns the whole CharacterBody3D, not just Head -- only pitch lives on
## Head), so +Z is straight behind us.
##
## Sweeps a fan of rays across wall_behind_angle instead of a single ray
## dead behind you -- checked center-out (straight behind first, then +/- one
## step at a time) so a wall exactly at your back is still preferred over one
## off to the side when both happen to be in range, but you're not forced to
## face dead-on away from it.
func _find_wall_behind() -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.9 # roughly chest height
	var backward := transform.basis.z # Godot forward is -Z, so +Z is "behind"

	var half_count: int = maxi((wall_behind_ray_count - 1) / 2, 1)
	var offsets: Array[int] = [0]
	for step in range(1, half_count + 1):
		offsets.append(-step)
		offsets.append(step)

	for offset in offsets:
		var t: float = float(offset) / float(half_count)
		var dir := backward.rotated(Vector3.UP, deg_to_rad(wall_behind_angle) * t)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * wall_check_distance)
		query.exclude = [get_rid()]
		query.collision_mask = 1
		var result := space.intersect_ray(query)
		if not result.is_empty():
			return result.normal
	return Vector3.ZERO


## Looks for a ledge worth pulling yourself up onto: a roughly vertical wall
## in front of you, with a flat surface within mantle range just above it.
## Runs every tick (see _simulate_movement()), so like _find_wall_behind() it
## reuses no cached state and just allocates fresh query objects -- still
## just a handful of raycasts, not a hot enough path to matter.
##
## Two-ray probe, the standard mantle technique: a forward ray finds the
## wall, then a downward ray from above it finds where the wall stops being
## a wall (its top surface).
func _find_mantle_ledge() -> MantleTarget:
	var result := MantleTarget.new()
	var space := get_world_3d().direct_space_state

	# Flat (yaw-only) forward, not the camera's full pitch-included look
	# direction -- so glancing slightly up or down at a ledge, which is
	# normal when approaching one, doesn't tilt the wall probe off-target.
	# Cast from chest height on the BODY (same point _find_wall_behind()
	# uses) rather than the head, for the same reason.
	var flat_look := Vector3(-head.global_transform.basis.z.x, 0.0, -head.global_transform.basis.z.z).normalized()
	var from := global_position + Vector3.UP * 0.9 # roughly chest height

	# Sweep a fan of rays across mantle_probe_angle, same center-out pattern
	# as _find_wall_behind(), instead of a single ray dead ahead -- this is
	# the forgiveness fix: you no longer have to aim pixel-perfectly at the
	# ledge, just roughly at it.
	var half_count: int = maxi((mantle_probe_ray_count - 1) / 2, 1)
	var offsets: Array[int] = [0]
	for step in range(1, half_count + 1):
		offsets.append(-step)
		offsets.append(step)

	var wall_hit: Dictionary = {}
	for offset in offsets:
		var t: float = float(offset) / float(half_count)
		var dir := flat_look.rotated(Vector3.UP, deg_to_rad(mantle_probe_angle) * t)
		var wall_query := PhysicsRayQueryParameters3D.create(from, from + dir * mantle_forward_distance)
		wall_query.exclude = [get_rid()]
		wall_query.collision_mask = 1
		var hit := space.intersect_ray(wall_query)
		if not hit.is_empty():
			# Reject floor/steep-slope and ceiling hits -- a mantleable ledge
			# is a roughly VERTICAL wall, not a ramp.
			if absf((hit.normal as Vector3).y) <= 0.3:
				wall_hit = hit
				break
	if wall_hit.is_empty():
		return result

	# From above and just past the wall, straight down, to find its top --
	# the second half of the two-ray probe.
	var probe_xz: Vector3 = (wall_hit.position as Vector3) + flat_look * 0.2
	var probe_top := Vector3(probe_xz.x, global_position.y + mantle_max_height, probe_xz.z)
	var probe_bottom := Vector3(probe_xz.x, global_position.y + mantle_min_height, probe_xz.z)
	var top_query := PhysicsRayQueryParameters3D.create(probe_top, probe_bottom)
	top_query.exclude = [get_rid()]
	top_query.collision_mask = 1
	var top_hit := space.intersect_ray(top_query)
	if top_hit.is_empty():
		return result # nothing to stand on within mantle range -- too tall, or open air past the wall
	if (top_hit.normal as Vector3).y < 0.7:
		return result # not flat enough to land on

	var landing: Vector3 = top_hit.position
	landing.y += 0.05 # small clearance so the capsule doesn't spawn embedded in the surface

	# Clearance check: does the player's own shape actually fit there? Same
	# body_test_motion technique _try_step_up() uses -- catches a ledge too
	# shallow or a low ceiling that would otherwise mantle you INTO geometry.
	var landing_transform := global_transform
	landing_transform.origin = landing
	_step_params.from = landing_transform
	_step_params.motion = Vector3.UP * 0.01
	if PhysicsServer3D.body_test_motion(get_rid(), _step_params, _step_result):
		return result

	result.found = true
	result.position = landing
	return result


## Kicks off the scripted pull-up: a Tween animates global_position straight
## to the ledge over mantle_duration, eased out (fast start, soft landing) so
## it reads as a climb, not a teleport-slide -- the same Tween-driven
## animate-a-property approach viewmodel.gd already uses for its switch/
## reload animations and hud.gd uses for its fades, rather than hand-rolled
## per-tick lerp math (Rule 2: reuse what the codebase already reaches for).
## Tied to the physics step (TWEEN_PROCESS_PHYSICS) since that's what drives
## every other movement in this file, and a direct position move rather than
## velocity + move_and_slide because the target is a specific point that has
## to be reached exactly, not a direction to accelerate toward and slide
## against -- the same reasoning _try_step_up() uses for its own direct
## position nudge, just sustained over the Tween's span instead of one tick.
## Untested at time of writing (no Godot executable available in this
## environment -- same caveat _try_step_up() shipped with).
func _start_mantle(target: Vector3) -> void:
	_mantle_time_left = mantle_duration
	velocity = Vector3.ZERO
	mantled.emit()

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "global_position", target, mantle_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Just the gating timer -- see its own comment. The Tween started in
## _start_mantle() is independently animating global_position over this same
## span and always lands exactly on target, so there's nothing left to do
## here but start the cooldown once it's run out.
func _update_mantle(delta: float) -> void:
	_mantle_time_left = maxf(_mantle_time_left - delta, 0.0)
	if _mantle_time_left <= 0.0:
		_mantle_cooldown_left = mantle_cooldown


## Mario-stomp/skip-off-an-enemy, Quake-movement style: hit an enemy while
## airborne and moving fast enough, from ANY angle -- not just landing on top
## of them, a glancing side hit while flying past counts too, like skipping a
## stone off water -- and instead of just bumping into them you kill them and
## launch off them: speed boost plus a big jump straight toward wherever
## you're looking. Reads the same move_and_slide() collision list
## _find_wall_normal() uses, so it only fires on an actual hit, not just
## standing near one.
func _check_enemy_stomp(speed: float) -> void:
	if speed < stomp_min_speed:
		return

	for i in get_slide_collision_count():
		var enemy := get_slide_collision(i).get_collider() as Enemy
		if enemy == null or enemy.get_state() == Enemy.State.DEAD:
			continue
		_stomp(enemy, speed)
		return # one stomp per landing


## Kills the enemy (host-only, the same authority rule enemy.gd's own AI
## thinking uses) and launches the player regardless -- each client always
## simulates its own movement locally (Rule 1), so the boost/jump has to
## apply even on a client who isn't authoritative over the enemy's death.
func _stomp(enemy: Enemy, impact_speed: float) -> void:
	if multiplayer.is_server():
		var enemy_health := enemy.get_node_or_null("Health") as Health
		if enemy_health:
			var hit_dir := Vector3(velocity.x, -1.0, velocity.z).normalized()
			enemy_health.take_damage(enemy_health.current_health, multiplayer.get_unique_id(),
					hit_dir, enemy.global_position, stomp_impact_force)

	# A stomp kill goes straight through Health.take_damage() rather than
	# WeaponController.resolve_shot(), so it never got the impact spray a
	# gunshot kill does -- add it here so stomping isn't the one kill method
	# with no blood at all. Always close range by definition (you're
	# standing on them), so the screen splatter always fires too, no
	# distance check needed the way weapon_controller.gd's does.
	BloodFX.spawn_impact(get_tree().current_scene, enemy.global_position, Vector3.UP)
	weapons.gory_kill_nearby.emit()

	var look_dir := -head.global_transform.basis.z
	look_dir.y = 0.0
	look_dir = look_dir.normalized() if look_dir.length_squared() > 0.0001 else -transform.basis.z
	var boosted_speed: float = impact_speed * stomp_speed_boost
	velocity.x = look_dir.x * boosted_speed
	velocity.z = look_dir.z * boosted_speed
	velocity.y = stomp_jump_velocity
	camera.shake(8.0)
	camera.kick_fov(20.0)
	_hit_stop(stomp_hit_stop_scale, stomp_hit_stop_time)


## Slows the whole game down to `scale` for `duration` REAL (unscaled)
## seconds, then snaps back to normal speed -- a "hit stop", the classic
## trick of briefly holding on the moment of a big impact instead of letting
## it blur past at normal speed. ignore_time_scale=true on the timer is what
## makes `duration` mean real seconds even while time_scale itself is down.
func _hit_stop(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	# Engine's own setter, not a lambda: the lambda would belong to this node,
	# and a level restart mid-hit-stop would free it before the timer fires.
	get_tree().create_timer(duration, true, false, true).timeout.connect(Engine.set_time_scale.bind(1.0))


func _on_shot_fired() -> void:
	camera.shake(1.5)
	camera.kick_fov(4.0)


func _on_hit_confirmed(killed: bool, _kind: WeaponController.HitKind) -> void:
	camera.shake(3.0 if killed else 1.5)
	camera.kick_fov(8.0 if killed else 3.0)


## Auto step-up, the same idea as Quake's PM_StepSlideMove and Doom's
## 24-unit step rule. move_and_slide() treats the vertical face of a stair as
## a wall, so without this you'd have to jump every step. Runs inside the
## simulation step, so a server and client would get the same answer
## (Rule 1). It only lifts us straight up onto the step; move_and_slide()
## then carries us forward as usual, so speed is kept.
##
## Steps: (1) are we blocked? (2) try to go up step_height, (3) is the way
## clear forward from up there? (4) go down to find the step's top surface.
func _try_step_up(delta: float) -> void:
	if velocity.y > 0.0:
		return # jumping: never snap the player onto a ledge mid-jump
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.0001:
		return
	var direction := horizontal.normalized()
	var walkable_normal_y := cos(floor_max_angle)

	# 1. Blocked? Nothing in the way means no step needed.
	_step_params.from = global_transform
	_step_params.motion = horizontal * delta
	if not PhysicsServer3D.body_test_motion(get_rid(), _step_params, _step_result):
		return
	# A gentle slope isn't a step; move_and_slide() already walks up those.
	if _step_result.get_collision_normal().y >= walkable_normal_y:
		return

	# 2. Go up (the physics engine stops us early if there's a ceiling).
	_step_params.motion = Vector3.UP * step_height
	PhysicsServer3D.body_test_motion(get_rid(), _step_params, _step_result)
	var raised := global_transform.translated(_step_result.get_travel())

	# 3. From up there, is the way forward clear? If not, the wall is taller
	# than a step and we do nothing.
	var forward := direction * maxf((horizontal * delta).length(), STEP_PROBE_DISTANCE)
	_step_params.from = raised
	_step_params.motion = forward
	if PhysicsServer3D.body_test_motion(get_rid(), _step_params, _step_result):
		return

	# 4. Come back down to find the top of the step. No floor within reach
	# means it's a gap, not a step.
	var raised_by := raised.origin.y - global_position.y
	_step_params.from = raised.translated(forward)
	_step_params.motion = Vector3.DOWN * (raised_by + STEP_DOWN_MARGIN)
	if not PhysicsServer3D.body_test_motion(get_rid(), _step_params, _step_result):
		return
	if _step_result.get_collision_normal().y < walkable_normal_y:
		return

	var rise := raised_by - _step_result.get_travel().length()
	if rise > MIN_STEP_RISE:
		global_position.y += rise


func _ground_move(wishdir: Vector3, delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.0001:
		var control: float = speed if speed > stop_speed else stop_speed
		var drop: float = control * ground_friction * delta
		var new_speed: float = max(speed - drop, 0.0)
		var scale: float = new_speed / speed
		velocity.x *= scale
		velocity.z *= scale

	_accelerate(wishdir, ground_max_speed, ground_accel, delta)


func _accelerate(wishdir: Vector3, wishspeed: float, accel: float, delta: float) -> void:
	if wishdir == Vector3.ZERO:
		return
	var currentspeed := velocity.dot(wishdir)
	var addspeed := wishspeed - currentspeed
	if addspeed <= 0.0:
		return
	var accelspeed: float = min(accel * wishspeed * delta, addspeed)
	velocity += accelspeed * wishdir


## Faithful-ish PM_AirAccelerate: accel scales with the true wishspeed, but
## the speed you can reach in one pass is capped, which is what produces the
## classic slow-building Quake 3 strafe curve.
func _air_move(wishdir: Vector3, delta: float) -> void:
	if wishdir == Vector3.ZERO:
		return
	var wishspeed := ground_max_speed
	var capped_speed: float = min(wishspeed, air_cap_speed)
	var currentspeed := velocity.dot(wishdir)
	var addspeed := capped_speed - currentspeed
	if addspeed <= 0.0:
		return
	var accelspeed: float = min(air_accel * wishspeed * delta, addspeed)
	velocity += accelspeed * wishdir
