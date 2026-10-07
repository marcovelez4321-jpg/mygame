class_name WeaponController
extends Node

## Handles the player's weapons: which ones they own, which is equipped,
## switching, cooldown, ammo, and the hitscan shot. Attach as a child of the
## player body. It never reads Input; the player's simulation step tells it
## what happened this tick (Rule 1).
##
## Co-op design (Rule 1): firing is split in two on purpose.
##   tick()          - "pull the trigger": switching, cooldown, ammo, builds a Shot.
##   resolve_shot()  - "did it hit?": the rays + damage.
## Offline, tick() calls resolve_shot() directly. In co-op, the client will
## send its Shot to the host and only the host runs resolve_shot(), so the
## host decides what was hit (and its random pellet spread). That is also
## where lag compensation goes: the host rewinds targets to shot.tick.

## Where on the body a hit landed. ARTERY is the neck (instant kill + spurt),
## HEADSHOT multiplies damage; see _hit_kind() for how they're told apart.
enum HitKind { NORMAL, HEADSHOT, ARTERY }

signal shot_fired
## A projectile weapon (the RPG) just launched this rocket. Presentation hook:
## the viewmodel hands it the rocket that was sitting in the launcher.
signal projectile_launched(rocket: Rocket)
## A grenade throw began: the arm winds up, and the grenade leaves the hand
## `release_delay` seconds from now (grenade_thrown).
signal throw_started(release_delay: float)
signal grenade_thrown(grenade: Grenade)
## Q: a quick grenade throw with the gun still equipped -- lower the gun for
## lower_time, throw `grenade_weapon` (leaves the hand release_delay after
## that), then bring the gun back up over recover_time.
signal quick_throw_started(grenade_weapon: WeaponData, lower_time: float, release_delay: float, recover_time: float)
## Emitted for every resolved ray with where it started and ended, and whether
## it hit something with Health. Presentation only (tracer lines).
signal shot_resolved(from: Vector3, to: Vector3, hit_target: bool)
## Emitted when a ray hit something with Health. Presentation only (hit
## marker, camera kick, hit sounds); `killed` is true if that hit finished the
## target off, `kind` says whether it was a headshot or artery hit.
signal hit_confirmed(killed: bool, kind: HitKind)
## The equipped weapon changed. draw_time is 0 for the very first weapon.
signal weapon_switched(weapon: WeaponData, draw_time: float)
## The list of owned weapons changed.
signal inventory_changed
## A weapon or ammo pickup was collected. Presentation only (HUD message).
## `weapon` is null for an ammo-only pickup.
signal picked_up(weapon: WeaponData, ammo_type: WeaponData.AmmoType, ammo_amount: int)
## A reload just started on the current weapon, lasting `duration` seconds.
## Presentation only -- the viewmodel plays its tilt-down/tilt-up animation
## on this (see viewmodel.gd's _on_reload_started()).
signal reload_started(duration: float)
## Any kill (artery or otherwise) landed close enough to splash blood on the
## player's own screen, in whatever colour that target bleeds (red, or a
## roach's green goo). Presentation only (hud.gd's screen droplets).
signal gory_kill_nearby(blood_color: Color)
## An artery (neck) hit landed -- a kill too unless artery_instant_kill is off.
## Presentation only (weapon_sound.gd's artery sounds) -- fires alongside
## hit_confirmed, not instead of it. Carries the neck bone itself (not just a
## position) so a listener can attach a SOUND to it the same way
## _spawn_artery_spurt() below attaches the blood particles -- it keeps
## following the spurt as the ragdoll falls and settles, instead of playing
## from one fixed point in empty air.
signal artery_kill(bone: Node3D)
## A leech (Leech) latched on (true) or the last one came off (false). While
## one's on, the gun won't fire: each fresh click tugs at it instead.
signal leech_latched(on: bool)
## H (pills) / B (bandage) pressed with one to use: the gun goes down, the
## item comes up in one hand (Viewmodel), and the heal lands at the end.
signal item_used(item: int, model: PackedScene, use_time: float, lower_time: float, recover_time: float)
## Carried pills or bandages changed (picked up or used), for the HUD.
signal items_changed

enum Item { PILLS, BANDAGE }

## Everything the host needs to judge one shot.
class Shot:
	var origin: Vector3
	var direction: Vector3
	var tick: int          # physics tick it was fired on (for lag compensation)
	var attacker_id: int   # multiplayer peer id of the shooter (host is 1)
	var weapon: WeaponData
	var spread_degrees: float # hip-fire spread, tightened by aiming

## TEMPORARY: until weapons are found in levels and remembered by the campaign,
## the player starts with these test weapons.
## How far past a hit body to check for a wall to splatter blood onto --
## "the wall behind them," not any wall anywhere down the shot's path.
const WALL_SPLATTER_MAX_DISTANCE := 3.0
## Brief global time_scale dip on an artery kill -- same "hit stop" trick
## player_movement.gd's stomp kill uses, so a clean artery kill feels just as
## impactful. See player_movement.gd's own stomp_hit_stop_scale for the
## co-op caveat (Engine.time_scale is global, fine until networking exists).
const ARTERY_HIT_STOP_SCALE := 0.05
const ARTERY_HIT_STOP_TIME := 0.06
## How close an artery kill has to land to the player to splash blood on
## their own screen (hud.gd's gory_kill_nearby handler).
const CLOSE_KILL_RANGE := 4.0
## Roughly how far the surface of the skull is from the middle of the head,
## in meters -- where a headshot wound gets placed (see _spawn_headshot_bleed()).
const HEAD_WOUND_RADIUS := 0.1
## Seconds an artery wound keeps spurting.
const ARTERY_BLEED_TIME := 7.0

const TEST_WEAPON_PATHS := [
	"res://weapons/starter_gun.tres",
	"res://weapons/shotgun.tres",
	"res://weapons/machine_gun.tres",
]

## Weapons the player starts with. If empty, the test weapons above are used.
@export var starting_weapons: Array[WeaponData] = []
## Test ammo until pickups exist.
@export var starting_bullets: int = 50
@export var starting_shells: int = 16

@export_group("Hit Zones")
## Damage per hit = the weapon's own damage (set per weapon in weapons/*.tres)
## times the multiplier for where it landed. Rule 3: these apply to every
## weapon and every target, players included once PvP exists -- tune with that
## in mind.
## Plain body hits.
@export var body_damage_multiplier: float = 1.0
## How close (meters) a shot has to land to the center of the head to count
## as a headshot.
@export var headshot_radius: float = 0.18
@export var headshot_damage_multiplier: float = 2.0
## How close (meters) a shot has to land to the neck bone to count as an
## artery hit (blood spurt). 0.2625 = the old 0.375 shrunk 30%. Keep it small
## and skill-rewarding, especially while it's an instant kill.
@export var artery_hit_radius: float = 0.2625
## On: an artery hit kills outright, whatever health is left. Off: it does the
## weapon's damage times artery_damage_multiplier instead.
@export var artery_instant_kill: bool = true
@export var artery_damage_multiplier: float = 3.0
## Seconds a headshot wound keeps pouring blood (the artery pours for 7).
@export var headshot_bleed_time: float = 4.0
## A headshot or artery wound that doesn't kill keeps bleeding: this much
## damage in total, drained over its bleed time, on top of the hit itself.
@export var bleed_damage: float = 10.0

@export_group("Physics Push")
## How much harder than a weapon's impact_force shots shove physics props
## (chairs, crates, pickups). A body with its own shot_push_multiplier (the
## roach) uses that instead.
@export var prop_push_multiplier: float = 2.0

@export_group("Healing Items (H, B)")
## Pills (H): pop them and pills_heal comes back the moment the bottle's gone
## past the top of the screen (Left 4 Dead 2's pills -- an instant top-up
## after a quick animation). Bandages (B): wrap one on and bandage_heal comes
## back over bandage_heal_time seconds.
@export var pills_heal: float = 50.0
@export var pills_use_time: float = 0.9
@export var max_pills: int = 2
@export var bandage_heal: float = 40.0
@export var bandage_heal_time: float = 8.0
@export var bandage_use_time: float = 1.4
@export var max_bandages: int = 3
## The one-handed models (the PSX Mega Pack's), and the gun's drop/return.
@export var pills_model: PackedScene = preload("res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Items & Weapons/pills_bottle_2.glb")
@export var bandage_model: PackedScene = preload("res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/Items & Weapons/bandage_mp_1.glb")
@export var item_lower_time: float = 0.15
@export var item_recover_time: float = 0.35

@export_group("Quick Grenade (Q)")
## Q throws a grenade without switching to it: the gun drops out of view
## (this long), the throw plays, then the gun comes back up (this long).
## You can't shoot until it's back.
@export var quick_throw_lower_time: float = 0.15
@export var quick_throw_recover_time: float = 0.45

## Debug toggle (pause menu): firing never drains the magazine, so reload is
## effectively never needed. Runtime-only, not saved -- resets to off on
## restart. Not a WeaponData/balance number on purpose: this is a dev/testing
## convenience, not something a level or weapon should ever configure.
var infinite_ammo: bool = false
## Debug toggle (pause menu): draws every living enemy's headshot zone
## (yellow) and artery zone (red) as see-through spheres. Placed by the same
## _head_center()/_bone_position() calls _hit_kind() uses, at the same radii,
## so what you see is exactly what counts. Runtime-only, like infinite_ammo.
var show_hit_zones: bool = false:
	set(value):
		show_hit_zones = value
		if not value:
			_clear_hit_zone_debug()

const HIT_ZONE_DEBUG_NAME := "HitZoneDebug"
const HEADSHOT_ZONE_COLOR := Color(1.0, 0.85, 0.1, 0.35)
const ARTERY_ZONE_COLOR := Color(1.0, 0.1, 0.1, 0.45)

var _headshot_zone_mesh: SphereMesh
var _artery_zone_mesh: SphereMesh

var _owned: Array[WeaponData] = []
var _current: int = 0
var _ammo: Dictionary = {}
var _cooldown: float = 0.0
## Rounds currently loaded, per weapon (WeaponData -> int). Looked up with
## .get(weapon, weapon.magazine_size) everywhere -- a weapon not yet in this
## dict just reads as "starts full", so nothing needs to pre-populate it in
## _ready()/pickup_weapon().
var _magazine: Dictionary = {}
var _reload_time_left: float = 0.0
## Seconds until a reload can start: the weapon's reload_delay_after_fire
## after a shot, or its draw_time after switching to it. Separate from
## _cooldown (the wait until the next SHOT), so reloading never has to sit
## out the whole fire_interval.
var _reload_blocked_left: float = 0.0
## View recoil (WeaponData's spray pattern): which shot of the current burst
## is next, how long since the last shot, and kick (degrees: x = right,
## y = up) not yet handed to the player -- PlayerMovement takes it with
## take_recoil() inside its own simulation step.
var _spray_index: int = 0
var _time_since_shot: float = 999.0
var _pending_recoil := Vector2.ZERO
## How far the gun is raised to your eye: 0 = at the hip, 1 = fully aimed
## (WeaponData's Aim Down Sights). Part of the simulation, not just the look,
## because it decides each shot's spread -- in co-op the host needs it too.
var _aim := 0.0
## Seconds until a thrown grenade leaves the hand; below 0 = not throwing.
var _throw_left := -1.0
## The grenade weapon being thrown (the equipped one, or a Q quick throw's).
var _throw_weapon: WeaponData
var _quick_throw_held_prev := false
var _fire_held_prev := false
## Healing items carried, and the one being used (-1 = none) with the time
## left until its heal lands.
var pills := 0
var bandages := 0
var _item_using := -1
var _item_left := 0.0
var _pills_held_prev := false
var _bandage_held_prev := false
## Leeches stuck on this player (untyped: any may be freed).
var _leeches: Array = []
## The weapon held before this one -- where you go back to when you run out
## of grenades.
var _previous: int = 0

@onready var _body: CollisionObject3D = get_parent() as CollisionObject3D


func _ready() -> void:
	_ammo[WeaponData.AmmoType.BULLETS] = starting_bullets
	_ammo[WeaponData.AmmoType.SHELLS] = starting_shells
	_ammo[WeaponData.AmmoType.ROCKETS] = 0
	_ammo[WeaponData.AmmoType.GRENADES] = 0

	_owned.assign(starting_weapons)
	if _owned.is_empty():
		for path in TEST_WEAPON_PATHS:
			var loaded := load(path) as WeaponData
			if loaded:
				_owned.append(loaded)

	inventory_changed.emit()
	if current_weapon():
		weapon_switched.emit(current_weapon(), 0.0)


func current_weapon() -> WeaponData:
	if _owned.is_empty():
		return null
	return _owned[_current]


func get_owned_weapons() -> Array[WeaponData]:
	return _owned


func get_current_index() -> int:
	return _current


## Reserve ammo in the shared pool for the equipped weapon's ammo_type --
## NOT what's currently loaded, see get_magazine_ammo() for that.
func get_ammo() -> int:
	var weapon := current_weapon()
	if weapon == null:
		return 0
	return _ammo[weapon.ammo_type]


## Rounds currently loaded in the equipped weapon.
func get_magazine_ammo() -> int:
	var weapon := current_weapon()
	if weapon == null:
		return 0
	return _magazine.get(weapon, weapon.magazine_size)


func is_reloading() -> bool:
	return _reload_time_left > 0.0


## 0 = gun at the hip, 1 = fully aimed down the sights.
func aim_amount() -> float:
	return _aim


## The grenade weapon you own (null if none) -- what Q throws.
func grenade_weapon() -> WeaponData:
	for weapon in _owned:
		if weapon.throws_grenade:
			return weapon
	return null


## Every grenade you have: the one in hand plus the spares.
func grenade_count() -> int:
	var grenade := grenade_weapon()
	if grenade == null:
		return 0
	return _magazine.get(grenade, grenade.magazine_size) + _ammo.get(grenade.ammo_type, 0)


## Called by WeaponPickup when the player walks over one. "Found in levels,
## kept permanently" (original design): once owned, a weapon stays owned for
## the rest of the level/campaign, so picking up a duplicate just tops off
## its ammo instead of doing nothing.
func pickup_weapon(weapon: WeaponData, ammo_amount: int) -> void:
	if weapon == null:
		return
	var already_owned := _owned.has(weapon)
	if not already_owned:
		_owned.append(weapon)
		inventory_changed.emit()
	add_ammo(weapon.ammo_type, ammo_amount, false)
	picked_up.emit(weapon if not already_owned else null, weapon.ammo_type, ammo_amount)
	# A brand new weapon auto-equips (you want to see/use what you just
	# found); a duplicate you already have just adds ammo without yanking
	# whatever you currently have out of your hands.
	if not already_owned:
		_select(_owned.find(weapon))


## Called by AmmoPickup, and internally by pickup_weapon(). `emit_signal`
## lets a weapon pickup's own ammo top-off fold into ONE picked_up signal
## instead of firing two.
## Takes up to `amount` pills or bandages (ItemPickup), as many as there's
## room for; returns how many it took.
func add_item(item: int, amount: int) -> int:
	var room := (max_pills - pills) if item == Item.PILLS else (max_bandages - bandages)
	var taken := clampi(amount, 0, room)
	if taken <= 0:
		return 0
	if item == Item.PILLS:
		pills += taken
	else:
		bandages += taken
	items_changed.emit()
	return taken


## Called every physics tick next to tick(): H pops pills, B wraps a bandage
## (if you have one, aren't busy throwing, and no leech is on you), and the
## heal lands when the item's animation is done. Rule 1: built from the
## player's input like tick(), so the host can run it.
func tick_items(use_pills: bool, use_bandage: bool, delta: float) -> void:
	var pills_pressed := use_pills and not _pills_held_prev
	var bandage_pressed := use_bandage and not _bandage_held_prev
	_pills_held_prev = use_pills
	_bandage_held_prev = use_bandage
	if _item_using >= 0:
		_item_left -= delta
		if _item_left <= 0.0:
			_finish_item()
		return
	if has_leech() or _throw_left >= 0.0:
		return
	if pills_pressed and pills > 0:
		_start_item(Item.PILLS, pills_model, pills_use_time)
	elif bandage_pressed and bandages > 0:
		_start_item(Item.BANDAGE, bandage_model, bandage_use_time)


func _start_item(item: int, model: PackedScene, use_time: float) -> void:
	_item_using = item
	_item_left = item_lower_time + use_time
	_reload_time_left = 0.0 # a reload in progress is dropped
	_aim = 0.0
	item_used.emit(item, model, use_time, item_lower_time, item_recover_time)


## The animation's done: the item's used up and the heal lands.
func _finish_item() -> void:
	var health := _body.get_node_or_null("Health") as Health
	if _item_using == Item.PILLS:
		pills -= 1
		if health:
			health.heal(pills_heal)
	else:
		bandages -= 1
		if health:
			health.regenerate(bandage_heal, bandage_heal_time)
	_item_using = -1
	_cooldown = maxf(_cooldown, item_recover_time) # the gun's still coming back up
	items_changed.emit()


## A leech got you (Leech._latch()).
func latch_leech(leech: Node) -> void:
	if _leeches.has(leech):
		return
	_leeches.append(leech)
	if _leeches.size() == 1:
		leech_latched.emit(true)


## A leech came off (ripped off, or it died).
func unlatch_leech(leech: Node) -> void:
	_leeches.erase(leech)
	if not has_leech():
		leech_latched.emit(false)


## How full the rip-it-off meter of the leech on you is (0..1), for the HUD.
func leech_progress() -> float:
	return float(_leeches[0].call("progress")) if has_leech() else 0.0


func has_leech() -> bool:
	if _leeches.is_empty():
		return false
	_leeches = _leeches.filter(func(leech) -> bool: return is_instance_valid(leech))
	return not _leeches.is_empty()


func add_ammo(type: WeaponData.AmmoType, amount: int, emit_signal: bool = true) -> void:
	_ammo[type] = _ammo.get(type, 0) + amount
	if emit_signal:
		picked_up.emit(null, type, amount)


## Called once per physics tick by the owner's simulation step.
## select_weapon is an inventory index, or -1 for "no change". aim = right
## mouse held, quick_throw = Q held.
func tick(fire: bool, reload: bool, aim: bool, quick_throw: bool, select_weapon: int, delta: float, origin: Vector3, direction: Vector3, attacker_id: int) -> void:
	var fire_pressed := fire and not _fire_held_prev
	_fire_held_prev = fire
	if has_leech():
		# A leech on your face: no shooting, switching or throwing -- every
		# fresh click is a tug at it (Leech.tug()).
		if fire_pressed:
			_leeches[0].call("tug")
		return
	if _item_using >= 0:
		return # both hands busy with pills or a bandage (tick_items())
	_cooldown = maxf(_cooldown - delta, 0.0)
	_reload_blocked_left = maxf(_reload_blocked_left - delta, 0.0)
	_time_since_shot += delta

	if select_weapon >= 0 and select_weapon < _owned.size():
		_select(select_weapon)

	var weapon := current_weapon()
	if weapon == null:
		return

	# An arm mid-throw: nothing else happens until the grenade's gone.
	if _throw_left >= 0.0:
		_throw_left -= delta
		if _throw_left < 0.0:
			_release_grenade(_throw_weapon, origin, direction, attacker_id)
		return

	var quick_pressed := quick_throw and not _quick_throw_held_prev
	_quick_throw_held_prev = quick_throw
	if quick_pressed:
		if weapon.throws_grenade:
			fire = true # holding grenades already: Q is just a throw
		else:
			_start_quick_throw()
			return

	# Raise toward your eye while aiming, lower otherwise. Reloading lowers it.
	var aiming := aim and weapon.can_aim and _reload_time_left <= 0.0
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta / maxf(weapon.aim_time, 0.01))

	if weapon.throws_grenade:
		_tick_throw(weapon, fire)
		return

	if _reload_time_left > 0.0:
		_reload_time_left = maxf(_reload_time_left - delta, 0.0)
		if _reload_time_left <= 0.0:
			_finish_reload(weapon)
		return

	var loaded: int = _magazine.get(weapon, weapon.magazine_size)
	# Gated by _reload_blocked_left, not the fire cooldown: you can reload
	# right after a shot (WeaponData.reload_delay_after_fire). The shot
	# cooldown keeps ticking during the reload, so this never fires faster.
	if reload and _reload_blocked_left <= 0.0 and loaded < weapon.magazine_size and _ammo.get(weapon.ammo_type, 0) > 0:
		_reload_time_left = weapon.reload_time
		reload_started.emit(weapon.reload_time)
		return

	if not fire or _cooldown > 0.0:
		return
	if not infinite_ammo and loaded < weapon.ammo_per_shot:
		return # empty -- no auto-reload, you have to press reload yourself

	if not infinite_ammo:
		_magazine[weapon] = loaded - weapon.ammo_per_shot
	_cooldown = weapon.fire_interval
	_reload_blocked_left = weapon.reload_delay_after_fire
	_add_recoil(weapon)
	shot_fired.emit()

	var shot := Shot.new()
	shot.origin = origin
	shot.direction = direction
	shot.tick = Engine.get_physics_frames()
	shot.attacker_id = attacker_id
	shot.weapon = weapon
	shot.spread_degrees = lerpf(weapon.spread_degrees, weapon.aim_spread_degrees, _aim)
	if weapon.fires_projectile:
		_launch_rocket(shot)
	else:
		resolve_shot(shot)


## Switches to the weapon at inventory `index`.
func _select(index: int) -> void:
	if index == _current:
		return
	# Switching away mid-throw keeps the grenade (back with the spares).
	if _throw_left >= 0.0:
		_throw_left = -1.0
		_ammo[_throw_weapon.ammo_type] = _ammo.get(_throw_weapon.ammo_type, 0) + 1
	_previous = _current
	_current = index
	var new_weapon := _owned[_current]
	# Can't fire until it's up, and any cooldown from the old weapon still
	# counts, so switching never lets you fire faster.
	_cooldown = maxf(_cooldown, new_weapon.draw_time)
	_reload_blocked_left = maxf(_reload_blocked_left, new_weapon.draw_time)
	_reload_time_left = 0.0 # switching cancels a reload in progress
	_aim = 0.0 # the new gun comes up at the hip
	weapon_switched.emit(new_weapon, new_weapon.draw_time)


## Grenades, Half-Life 2 style: click and the arm winds up and throws, the
## grenade leaving the hand throw_release_delay later. The next one comes
## into your hand once fire_interval has passed; out of grenades, you switch
## back to the weapon you had before.
func _tick_throw(weapon: WeaponData, fire: bool) -> void:
	var loaded: int = _magazine.get(weapon, weapon.magazine_size)
	if loaded <= 0:
		if _cooldown > 0.0:
			return
		if _ammo.get(weapon.ammo_type, 0) > 0:
			_magazine[weapon] = 1
			_ammo[weapon.ammo_type] -= 1
		elif _owned.size() > 1:
			_select(_previous if _previous != _current and _previous < _owned.size() else 0)
		return
	if not fire or _cooldown > 0.0:
		return
	if not infinite_ammo:
		_magazine[weapon] = loaded - 1
	_cooldown = weapon.fire_interval
	_throw_weapon = weapon
	_throw_left = weapon.throw_release_delay
	throw_started.emit(weapon.throw_release_delay)


## Q with a gun out: throw a grenade without switching to it -- a spare
## first, then the one "in hand" in the grenade slot. The gun is down for the
## whole thing, so it can't fire until quick_throw_recover_time after release.
func _start_quick_throw() -> void:
	var grenade := grenade_weapon()
	if grenade == null or grenade_count() <= 0:
		return
	if not infinite_ammo:
		if _ammo.get(grenade.ammo_type, 0) > 0:
			_ammo[grenade.ammo_type] -= 1
		else:
			_magazine[grenade] = _magazine.get(grenade, grenade.magazine_size) - 1
	_reload_time_left = 0.0 # a reload in progress is dropped
	_aim = 0.0
	_throw_weapon = grenade
	_throw_left = quick_throw_lower_time + grenade.throw_release_delay
	_cooldown = maxf(_cooldown, _throw_left + quick_throw_recover_time)
	quick_throw_started.emit(grenade, quick_throw_lower_time, grenade.throw_release_delay, quick_throw_recover_time)


## The grenade leaves the hand: thrown along the aim tilted up a little, plus
## the thrower's own speed (Half-Life 2's ThrowGrenade adds the player's
## velocity the same way). Rule 1 (co-op): like a shot, this is built only
## from the aim and the body's velocity, so the host can throw the same one.
func _release_grenade(weapon: WeaponData, origin: Vector3, direction: Vector3, attacker_id: int) -> void:
	var right := direction.cross(Vector3.UP).normalized()
	var throw_direction := direction
	if right != Vector3.ZERO:
		throw_direction = direction.rotated(right, deg_to_rad(weapon.throw_lift_degrees))
	# Out of the right hand, a little in front of the eye -- pulled back if
	# that would put it inside a wall.
	var start := origin + right * 0.15 + Vector3.DOWN * 0.1 + direction * 0.4
	var query := PhysicsRayQueryParameters3D.create(origin, start)
	query.exclude = [_body.get_rid()]
	var wall := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		start = wall.position - direction * 0.1
	var body_velocity: Vector3 = _body.get("velocity") if _body.get("velocity") is Vector3 else Vector3.ZERO
	var grenade := Grenade.throw(_body.get_tree().current_scene, start, throw_direction * weapon.throw_speed + body_velocity,
			weapon, attacker_id, _body as PhysicsBody3D, self)
	grenade_thrown.emit(grenade)


## A projectile weapon's shot: a Rocket from the eye along the aim (so it
## flies where the crosshair points); the viewmodel then hands it the rocket
## from the launcher so it's SEEN leaving the tube (projectile_launched).
## Rule 1 (co-op): the host launches it from the same Shot it would resolve.
func _launch_rocket(shot: Shot) -> void:
	var rocket := Rocket.launch(_body.get_tree().current_scene, shot.origin, shot.direction, shot.weapon,
			shot.attacker_id, _body as Node3D, self)
	projectile_launched.emit(rocket)


## Hit markers for everything an explosion this player caused hurt (not
## counting themselves) -- same feedback as a bullet hit.
func report_explosion_hits(hits: Array[Explosion.Hit]) -> void:
	for hit in hits:
		hit_confirmed.emit(hit.killed, HitKind.NORMAL)


## This shot's kick from the weapon's spray pattern. A pause longer than
## recoil_reset_time starts the pattern over; past its end the last four
## entries cycle. The jitter's random generator is seeded from the shot's
## number in the burst and the physics tick, so in co-op the host and the
## shooter roll the same wobble (Rule 1).
func _add_recoil(weapon: WeaponData) -> void:
	if _time_since_shot > weapon.recoil_reset_time:
		_spray_index = 0
	_time_since_shot = 0.0
	var pattern := weapon.recoil_pattern
	if pattern.is_empty():
		return
	var index := _spray_index
	if index >= pattern.size():
		var tail := mini(4, pattern.size())
		index = pattern.size() - tail + (index - pattern.size()) % tail
	var kick := pattern[index] * weapon.recoil_scale
	if weapon.recoil_jitter > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(_spray_index, Engine.get_physics_frames()))
		kick += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * weapon.recoil_jitter
	_pending_recoil += kick
	_spray_index += 1


## Hands over the view kick waiting since the last call (degrees: x = right,
## y = up) -- PlayerMovement turns it into actual aim movement.
func take_recoil() -> Vector2:
	var kick := _pending_recoil
	_pending_recoil = Vector2.ZERO
	return kick


## Seconds since the last shot -- the player's aim starts drifting back once
## this passes the weapon's recoil_reset_time.
func time_since_shot() -> float:
	return _time_since_shot


## Moves ammo from the shared reserve pool into the magazine, capped at
## magazine_size and by however much reserve is actually available (a
## partial reload if the pool doesn't have enough to fill it completely).
func _finish_reload(weapon: WeaponData) -> void:
	var loaded: int = _magazine.get(weapon, weapon.magazine_size)
	var need := weapon.magazine_size - loaded
	var available: int = _ammo.get(weapon.ammo_type, 0)
	var take := mini(need, available)
	_magazine[weapon] = loaded + take
	_ammo[weapon.ammo_type] = available - take


## Casts the rays and applies damage. In co-op only the host runs this.
## Each pellet can punch through up to weapon.max_penetrations living targets
## -- it keeps casting past a hit enemy (excluding whoever it already hit) up
## to that many times, damaging each one it passes through, and always stops
## outright the moment it hits plain world geometry. shot_resolved/
## hit_confirmed fire once per thing actually hit along the way, so a
## penetrating shot draws a continuous tracer through both bodies and flashes
## the hit marker for each one.
func resolve_shot(shot: Shot) -> void:
	var space := _body.get_world_3d().direct_space_state
	for pellet in shot.weapon.pellets:
		var direction := _spread(shot.direction, shot.spread_degrees)
		var ray_origin := shot.origin
		var range_left := shot.weapon.max_range
		var exclude: Array[RID] = [_body.get_rid()] # don't shoot ourselves
		var penetrations_left := shot.weapon.max_penetrations

		while true:
			var end := ray_origin + direction * range_left
			var query := PhysicsRayQueryParameters3D.create(ray_origin, end)
			query.exclude = exclude
			# World geometry (layer 1) AND the ragdoll layer, so a downed
			# corpse can still be shot -- see the PhysicalBone3D branch
			# below. Cosmetic only (no Health there to damage, no kill to
			# land twice), but a double-tap on a body still spraying blood
			# reads better than a shot silently passing through it.
			query.collision_mask = EnemyRagdoll.WORLD_MASK
			var result := space.intersect_ray(query)
			if result.is_empty():
				shot_resolved.emit(ray_origin, end, false)
				break

			if result.collider is PhysicalBone3D:
				shot_resolved.emit(ray_origin, result.position, true)
				_spawn_blood(space, result, direction)
				_hit_mutating_corpse(result.collider, shot, ray_origin, direction, result.position)
				if penetrations_left <= 0:
					break
				penetrations_left -= 1
				range_left -= ray_origin.distance_to(result.position)
				exclude.append((result.collider as CollisionObject3D).get_rid())
				ray_origin = result.position + direction * 0.01
				continue

			# Anything with a Health child can be hurt: targets, monsters, players.
			var health := (result.collider as Node).get_node_or_null("Health") as Health
			shot_resolved.emit(ray_origin, result.position, health != null)
			_push_physics_body(result.collider, direction, result.position, shot.weapon.impact_force)
			if health == null:
				BloodFX.spawn_bullet_hole(_body.get_tree().current_scene, result.position, result.normal)
				break # world geometry always stops it, penetration or not

			var kind: HitKind = _hit_kind(result.collider, ray_origin, direction) if not health.is_dead else HitKind.NORMAL
			var damage := _damage_for(shot.weapon, kind, health.current_health, shot.origin.distance_to(result.position), result.collider)
			# is_critical = a headshot kill, the one clean finish that rules out
			# a mutation. Artery and body kills can still mutate (see enemy.gd's
			# Mutation group).
			health.take_damage(damage, shot.attacker_id, direction, result.position, shot.weapon.impact_force, kind == HitKind.HEADSHOT)
			Factions.provoke(result.collider, _body as Node3D) # it turns on whoever shot it
			if not health.is_dead and (kind == HitKind.HEADSHOT or kind == HitKind.ARTERY):
				health.bleed(bleed_damage, headshot_bleed_time if kind == HitKind.HEADSHOT else ARTERY_BLEED_TIME, shot.attacker_id)
			hit_confirmed.emit(health.is_dead, kind)
			_play_hit_effects(space, result, direction, kind, health.is_dead)

			if penetrations_left <= 0:
				break
			penetrations_left -= 1
			range_left -= ray_origin.distance_to(result.position)
			exclude.append((result.collider as CollisionObject3D).get_rid())
			ray_origin = result.position + direction * 0.01 # past the hit surface, so the next cast doesn't re-hit it


## The weapon's own damage times the multiplier for where it landed (the Hit
## Zones exports), or everything the target has left (`remaining`) for an
## instant-kill artery. `distance` (from the shooter to the hit) feeds the
## weapon's close-range boost -- see WeaponData.close_range_multiplier(). An
## instant artery kill ignores it; it already takes everything.
## A target with its own weak_spot_multiplier (the Rat Bender) can't be
## one-shot: a headshot or artery hit just does that many times the damage.
func _damage_for(weapon: WeaponData, kind: HitKind, remaining: float, distance: float, target: Object = null) -> float:
	var close := weapon.close_range_multiplier(distance)
	var weak_spot: Variant = target.get("weak_spot_multiplier") if target else null
	if weak_spot is float and kind != HitKind.NORMAL:
		return weapon.damage * weak_spot * close
	match kind:
		HitKind.HEADSHOT:
			return weapon.damage * headshot_damage_multiplier * close
		HitKind.ARTERY:
			return remaining if artery_instant_kill else weapon.damage * artery_damage_multiplier * close
	return weapon.damage * body_damage_multiplier * close


## The double tap: a corpse twitching toward a mutation (enemy.gd's
## will_mutate) has a fresh pool of mutation_health, and emptying it stops
## the transformation for good. Damage works exactly like on a live enemy --
## the head and artery zones are read from the ragdoll's own bones -- and the
## hit marker / kill confirm fire the same way, so finishing it off reads as a
## kill. An ordinary corpse ignores all this and just bleeds.
## Runs only where resolve_shot() runs -- the host, in co-op (Rule 1).
func _hit_mutating_corpse(bone: Node, shot: Shot, ray_origin: Vector3, direction: Vector3, hit_position: Vector3) -> void:
	var enemy := _owning_enemy(bone)
	if enemy == null or not enemy.will_mutate:
		return
	var kind := _hit_kind(enemy, ray_origin, direction)
	var damage := _damage_for(shot.weapon, kind, enemy.mutation_health_left, shot.origin.distance_to(hit_position))
	var stopped := enemy.damage_mutation(damage)
	hit_confirmed.emit(stopped, kind)


## A target can bleed its own colour (the roach's green goo) by having a
## blood_color property; everything else bleeds red.
func _blood_color_of(target: Object) -> Color:
	var custom: Variant = target.get("blood_color")
	return custom if custom is Color else BloodFX.BLOOD_COLOR


## Shots shove physics objects -- a flying roach, a crate, a barrel -- the
## Half-Life "everything movable reacts" rule from RULES.md. Pushed at the
## spot it was hit, so an off-centre shot spins it. Props get
## prop_push_multiplier; a body can set its own with a shot_push_multiplier
## property instead (the roach does). Host-only like the rest of
## resolve_shot(); the body's movement then syncs like any host physics.
func _push_physics_body(collider: Object, direction: Vector3, hit_position: Vector3, force: float) -> void:
	var body := collider as RigidBody3D
	if body == null or body.freeze:
		return
	var own_multiplier: Variant = body.get("shot_push_multiplier")
	force *= own_multiplier if own_multiplier is float else prop_push_multiplier
	body.apply_impulse(direction * force, hit_position - body.global_position)


## The Enemy a ragdoll bone belongs to (bones sit a few levels down, under its
## model's skeleton), or null.
func _owning_enemy(node: Node) -> Enemy:
	while node != null and not node is Enemy:
		node = node.get_parent()
	return node as Enemy


## Every cosmetic effect of one confirmed hit, in one place -- nothing here
## touches health or gameplay. Rule 1 (co-op): resolve_shot() only runs on the
## host, so this is the hook for the other player: the host will send the hit
## (target, position, normal, direction, kind, killed) and each client calls
## this same function to bleed its own copy of the enemy locally.
func _play_hit_effects(space: PhysicsDirectSpaceState3D, hit: Dictionary, direction: Vector3, kind: HitKind, killed: bool) -> void:
	# Things with health that don't bleed (bleeds = false, e.g. an explosive
	# barrel) just take a bullet hole.
	if hit.collider.get("bleeds") == false:
		BloodFX.spawn_bullet_hole(_body.get_tree().current_scene, hit.position, hit.normal)
		return
	_spawn_blood(space, hit, direction)
	if kind == HitKind.HEADSHOT:
		_spawn_headshot_bleed(hit.collider, hit.position)
	# The spurt follows the neck whether the hit killed or not (it only can't
	# kill when artery_instant_kill is off); the hit stop is for kills only.
	if kind == HitKind.ARTERY:
		_spawn_artery_spurt(hit.collider)
		if killed:
			_hit_stop(ARTERY_HIT_STOP_SCALE, ARTERY_HIT_STOP_TIME)
	# ANY kill close enough splashes the screen, not just artery ones --
	# see CLOSE_KILL_RANGE's own comment.
	if killed and _body.global_position.distance_to(hit.position) <= CLOSE_KILL_RANGE:
		gory_kill_nearby.emit(_blood_color_of(hit.collider))


## Blood off the body that got hit, plus a splatter decal on any wall caught
## close behind them -- "a shot punches through and marks the wall behind the
## target," not blood on every wall anywhere down the shot's path. Works
## against any collider (a hand-built StaticBody3D or a func_godot-baked
## TrenchBroom wall alike): both the impact spray and the splatter come from
## a plain raycast hit + BloodFX.spawn_splatter's Decal, neither of which
## cares what kind of CollisionShape3D produced the hit.
func _spawn_blood(space: PhysicsDirectSpaceState3D, hit: Dictionary, direction: Vector3) -> void:
	var world := _body.get_tree().current_scene
	var blood_color := _blood_color_of(hit.collider)
	BloodFX.spawn_impact(world, hit.position, hit.normal, blood_color)

	var behind_query := PhysicsRayQueryParameters3D.create(
			hit.position + direction * 0.05, hit.position + direction * WALL_SPLATTER_MAX_DISTANCE)
	behind_query.exclude = [_body.get_rid(), hit.collider.get_rid()]
	behind_query.collision_mask = 1
	var behind_result := space.intersect_ray(behind_query)
	if not behind_result.is_empty():
		BloodFX.spawn_splatter(world, behind_result.position, behind_result.normal, 0.6, blood_color)


## Artery, headshot, or a plain body hit. Measured against the live,
## currently-animating skeleton rather than separate hitboxes -- a live enemy
## only has one capsule, so this reads where the neck and head actually are
## this frame.
##
## The test is whether the bullet's PATH passes through a zone, not where it
## touched the capsule: the capsule is far wider than a head (0.4 m radius), so
## a shot dead-centre on the face touches it ~0.3 m in front of the skull --
## outside the head zone -- and used to count as a body shot. Same two-step
## idea as Source's hitboxes: the collision hull says "you hit this enemy",
## then the trace is checked against the small per-bone zones inside it.
##
## The two zones overlap around the jaw; whichever centre the path passes
## closer to wins, so the neck doesn't swallow shots to the face.
## Runs only where resolve_shot() runs -- the host, in co-op (Rule 1).
func _hit_kind(collider: Node, ray_origin: Vector3, direction: Vector3) -> HitKind:
	var skeleton := collider.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton == null:
		return HitKind.NORMAL

	var artery_distance := INF
	var neck := skeleton.find_bone("Neck")
	if neck >= 0:
		artery_distance = _ray_distance(ray_origin, direction, _bone_position(skeleton, neck))

	var head_distance := INF
	var head := skeleton.find_bone("Head")
	if head >= 0:
		head_distance = _ray_distance(ray_origin, direction, _head_center(skeleton, head))

	var in_artery := artery_distance <= artery_hit_radius
	var in_head := head_distance <= headshot_radius
	if in_artery and (not in_head or artery_distance <= head_distance):
		return HitKind.ARTERY
	if in_head:
		return HitKind.HEADSHOT
	return HitKind.NORMAL


## How close a shot travelling from ray_origin along (normalized) direction
## passes to `point` -- never measured behind where the shot started.
func _ray_distance(ray_origin: Vector3, direction: Vector3, point: Vector3) -> float:
	var along := maxf((point - ray_origin).dot(direction), 0.0)
	return (ray_origin + direction * along).distance_to(point)


func _bone_position(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## The Head bone sits at the base of the skull; the middle of the head is
## halfway to its child bone (the top of the head, HeadTop_End on these rigs).
func _head_center(skeleton: Skeleton3D, head: int) -> Vector3:
	var base := _bone_position(skeleton, head)
	var children := skeleton.get_bone_children(head)
	if children.is_empty():
		return base
	return base.lerp(_bone_position(skeleton, children[0]), 0.5)


func _process(_delta: float) -> void:
	if show_hit_zones:
		_update_hit_zone_debug()


## One pair of spheres per living enemy, moved onto its live head and neck
## every frame. They're parented to the enemy (top_level, so they sit in world
## space) and get freed with it. A dead enemy hides its pair -- the zones only
## matter on something you can still shoot.
func _update_hit_zone_debug() -> void:
	_sync_zone_meshes()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var markers := _get_zone_markers(enemy)
		var skeleton := enemy.find_child("*Skeleton*", true, false) as Skeleton3D
		markers.visible = skeleton != null and not enemy.health.is_dead
		if not markers.visible:
			continue
		var head := skeleton.find_bone("Head")
		var neck := skeleton.find_bone("Neck")
		var head_marker := markers.get_child(0) as MeshInstance3D
		var neck_marker := markers.get_child(1) as MeshInstance3D
		head_marker.visible = head >= 0
		neck_marker.visible = neck >= 0
		if head >= 0:
			head_marker.global_position = _head_center(skeleton, head)
		if neck >= 0:
			neck_marker.global_position = _bone_position(skeleton, neck)


## Builds the two shared sphere meshes once, then keeps their size matched to
## headshot_radius/artery_hit_radius, so tuning those in the Inspector while
## playing resizes the spheres too.
func _sync_zone_meshes() -> void:
	if _headshot_zone_mesh == null:
		_headshot_zone_mesh = _make_zone_mesh(HEADSHOT_ZONE_COLOR)
		_artery_zone_mesh = _make_zone_mesh(ARTERY_ZONE_COLOR)
	# Only on change: setting a SphereMesh's size rebuilds it.
	if not is_equal_approx(_headshot_zone_mesh.radius, headshot_radius):
		_headshot_zone_mesh.radius = headshot_radius
		_headshot_zone_mesh.height = headshot_radius * 2.0
	if not is_equal_approx(_artery_zone_mesh.radius, artery_hit_radius):
		_artery_zone_mesh.radius = artery_hit_radius
		_artery_zone_mesh.height = artery_hit_radius * 2.0


## See-through and drawn on top of everything (no_depth_test) -- both zones
## sit inside the head and neck, so they'd be hidden by the model otherwise.
func _make_zone_mesh(color: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = color
	mesh.material = mat
	return mesh


func _get_zone_markers(enemy: Node3D) -> Node3D:
	var markers := enemy.get_node_or_null(HIT_ZONE_DEBUG_NAME) as Node3D
	if markers:
		return markers
	markers = Node3D.new()
	markers.name = HIT_ZONE_DEBUG_NAME
	markers.top_level = true
	for mesh in [_headshot_zone_mesh, _artery_zone_mesh]:
		var marker := MeshInstance3D.new()
		marker.mesh = mesh
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		markers.add_child(marker)
	enemy.add_child(markers)
	return markers


func _clear_hit_zone_debug() -> void:
	if not is_inside_tree():
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var markers := enemy.get_node_or_null(HIT_ZONE_DEBUG_NAME)
		if markers:
			markers.queue_free()


## Called right after an artery hit kills the target -- by this point
## EnemyRagdoll has already run (Health.died fires synchronously), so the
## neck's PhysicalBone3D already exists and is already simulating. Finds it
## by name and hands it to BloodFX for a sustained, bone-attached spray.
func _spawn_artery_spurt(collider: Node) -> void:
	var neck_bone := collider.find_child("Physical Bone Neck", true, false) as Node3D
	if neck_bone == null:
		return # no physical skeleton on this target (e.g. a test target) -- nothing to attach to
	if _already_bleeding(neck_bone, ARTERY_BLEED_TIME):
		return
	BloodFX.spawn_artery_stream(neck_bone, ARTERY_BLEED_TIME, _own_body_rids(collider))
	artery_kill.emit(neck_bone)


## A headshot wound that pours like the artery, from the spot on the skull
## that was hit, attached to the head's physical bone so it follows the head
## -- animating while the enemy is alive, ragdolling once it's dead. The shot
## hits the enemy's single body capsule, which sits further out than the
## actual skull, so the wound is pulled in to HEAD_WOUND_RADIUS from the head's
## middle, and the spray points straight out through it.
func _spawn_headshot_bleed(collider: Node, hit_position: Vector3) -> void:
	var head_bone := collider.find_child("Physical Bone Head", true, false) as Node3D
	if head_bone == null or _already_bleeding(head_bone, headshot_bleed_time):
		return
	var outward := hit_position - head_bone.global_position
	if outward.length_squared() < 0.0001:
		outward = -head_bone.global_transform.basis.z
	var wound := head_bone.global_position + outward.limit_length(HEAD_WOUND_RADIUS)
	var to_local := head_bone.global_transform.affine_inverse()
	BloodFX.spawn_artery_spurt(head_bone, headshot_bleed_time, _own_body_rids(collider),
			to_local * wound, (to_local.basis * outward).normalized())


## One wound per bone at a time: a shotgun blast is up to 8 pellets, and 8
## overlapping spurts on one head cost 8x the particles and landing traces for
## no visible difference (Rule 2). Returns true if `bone` is still bleeding;
## otherwise marks it as bleeding for `duration` and returns false.
func _already_bleeding(bone: Node, duration: float) -> bool:
	var now := Time.get_ticks_msec()
	if now < int(bone.get_meta(&"bleeding_until_msec", 0)):
		return true
	bone.set_meta(&"bleeding_until_msec", now + int(duration * 1000.0))
	return false


## This body's own collision RIDs (its capsule and every ragdoll bone), so a
## spurt's landing check can splat another nearby corpse or the floor, but
## never the body the blood is coming out of.
func _own_body_rids(collider: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if collider is CollisionObject3D:
		rids.append((collider as CollisionObject3D).get_rid())
	for bone in collider.find_children("Physical Bone *", "PhysicalBone3D", true, false):
		rids.append((bone as PhysicalBone3D).get_rid())
	return rids


## Same trick as player_movement.gd's _hit_stop(): briefly slows the whole
## game to `scale` for `duration` REAL (unscaled) seconds, then snaps back.
func _hit_stop(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	# Engine's own setter, not a lambda: the lambda would belong to this node,
	# and a level restart mid-hit-stop would free it before the timer fires.
	get_tree().create_timer(duration, true, false, true).timeout.connect(Engine.set_time_scale.bind(1.0))


## `direction` nudged by a random amount inside a cone of `spread_degrees`.
func _spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var aim := Basis.looking_at(direction, up) # -Z of this basis is `direction`
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0)
	var offset := jitter * tan(deg_to_rad(spread_degrees))
	return (aim * Vector3(offset.x, offset.y, -1.0)).normalized()
