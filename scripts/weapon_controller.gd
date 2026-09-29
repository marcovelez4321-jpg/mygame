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

signal shot_fired
## Emitted for every resolved ray with where it started and ended, and whether
## it hit something with Health. Presentation only (tracer lines).
signal shot_resolved(from: Vector3, to: Vector3, hit_target: bool)
## Emitted when a ray hit something with Health. Presentation only (hit
## marker); `killed` is true if that hit finished the target off.
signal hit_confirmed(killed: bool)
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
## player's own screen. Presentation only (hud.gd's screen droplets).
signal gory_kill_nearby

## Everything the host needs to judge one shot.
class Shot:
	var origin: Vector3
	var direction: Vector3
	var tick: int          # physics tick it was fired on (for lag compensation)
	var attacker_id: int   # multiplayer peer id of the shooter (host is 1)
	var weapon: WeaponData

## TEMPORARY: until weapons are found in levels and remembered by the campaign,
## the player starts with these test weapons.
## How far past a hit body to check for a wall to splatter blood onto --
## "the wall behind them," not any wall anywhere down the shot's path.
const WALL_SPLATTER_MAX_DISTANCE := 3.0
## How close a shot has to land to the live neck bone to count as an artery
## hit. Generous enough to actually hit reliably at combat ranges/spread,
## tight enough that it still reads as "the neck specifically," not "the
## upper body in general."
const ARTERY_HIT_RADIUS := 0.375 # 0.5 - 25%
## Brief global time_scale dip on an artery kill -- same "hit stop" trick
## player_movement.gd's stomp kill uses, so a clean artery kill feels just as
## impactful. See player_movement.gd's own stomp_hit_stop_scale for the
## co-op caveat (Engine.time_scale is global, fine until networking exists).
const ARTERY_HIT_STOP_SCALE := 0.05
const ARTERY_HIT_STOP_TIME := 0.06
## How close an artery kill has to land to the player to splash blood on
## their own screen (hud.gd's gory_kill_nearby handler).
const CLOSE_KILL_RANGE := 4.0

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

## Debug toggle (pause menu): firing never drains the magazine, so reload is
## effectively never needed. Runtime-only, not saved -- resets to off on
## restart. Not a WeaponData/balance number on purpose: this is a dev/testing
## convenience, not something a level or weapon should ever configure.
var infinite_ammo: bool = false

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

@onready var _body: CollisionObject3D = get_parent() as CollisionObject3D


func _ready() -> void:
	_ammo[WeaponData.AmmoType.BULLETS] = starting_bullets
	_ammo[WeaponData.AmmoType.SHELLS] = starting_shells
	_ammo[WeaponData.AmmoType.ROCKETS] = 0

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
		_current = _owned.find(weapon)
		_cooldown = maxf(_cooldown, weapon.draw_time)
		weapon_switched.emit(weapon, weapon.draw_time)


## Called by AmmoPickup, and internally by pickup_weapon(). `emit_signal`
## lets a weapon pickup's own ammo top-off fold into ONE picked_up signal
## instead of firing two.
func add_ammo(type: WeaponData.AmmoType, amount: int, emit_signal: bool = true) -> void:
	_ammo[type] = _ammo.get(type, 0) + amount
	if emit_signal:
		picked_up.emit(null, type, amount)


## Called once per physics tick by the owner's simulation step.
## select_weapon is an inventory index, or -1 for "no change".
func tick(fire: bool, reload: bool, select_weapon: int, delta: float, origin: Vector3, direction: Vector3, attacker_id: int) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	if select_weapon >= 0 and select_weapon != _current and select_weapon < _owned.size():
		_current = select_weapon
		var new_weapon := _owned[_current]
		# Can't fire until it's up, and any cooldown from the old weapon still
		# counts, so switching never lets you fire faster.
		_cooldown = maxf(_cooldown, new_weapon.draw_time)
		_reload_time_left = 0.0 # switching cancels a reload in progress
		weapon_switched.emit(new_weapon, new_weapon.draw_time)

	var weapon := current_weapon()
	if weapon == null:
		return

	if _reload_time_left > 0.0:
		_reload_time_left = maxf(_reload_time_left - delta, 0.0)
		if _reload_time_left <= 0.0:
			_finish_reload(weapon)
		return

	var loaded: int = _magazine.get(weapon, weapon.magazine_size)
	if reload and _cooldown <= 0.0 and loaded < weapon.magazine_size and _ammo.get(weapon.ammo_type, 0) > 0:
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
	shot_fired.emit()

	var shot := Shot.new()
	shot.origin = origin
	shot.direction = direction
	shot.tick = Engine.get_physics_frames()
	shot.attacker_id = attacker_id
	shot.weapon = weapon
	resolve_shot(shot)


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
		var direction := _spread(shot.direction, shot.weapon.spread_degrees)
		var ray_origin := shot.origin
		var range_left := shot.weapon.max_range
		var exclude: Array[RID] = [_body.get_rid()] # don't shoot ourselves
		var penetrations_left := shot.weapon.max_penetrations

		while true:
			var end := ray_origin + direction * range_left
			var query := PhysicsRayQueryParameters3D.create(ray_origin, end)
			query.exclude = exclude
			# Only physics layer 1: ragdoll corpses live on layer 4, so they
			# never absorb shots meant for what's behind them.
			query.collision_mask = 1
			var result := space.intersect_ray(query)
			if result.is_empty():
				shot_resolved.emit(ray_origin, end, false)
				break

			# Anything with a Health child can be hurt: targets, monsters, players.
			var health := (result.collider as Node).get_node_or_null("Health") as Health
			shot_resolved.emit(ray_origin, result.position, health != null)
			if health == null:
				BloodFX.spawn_bullet_hole(_body.get_tree().current_scene, result.position, result.normal)
				break # world geometry always stops it, penetration or not

			# Artery hit: land a shot near the live skeleton's own neck bone and
			# it's an instant, dramatic kill regardless of remaining health --
			# checked against the actual bone position rather than a separate
			# hitbox, since a live enemy only has one hitbox capsule right now.
			var is_artery := not health.is_dead and _is_artery_hit(result.collider, result.position)
			var damage: float = health.current_health if is_artery else shot.weapon.damage
			health.take_damage(damage, shot.attacker_id, direction, result.position, shot.weapon.impact_force)
			hit_confirmed.emit(health.is_dead)
			_spawn_blood(space, result, direction)
			if is_artery and health.is_dead:
				_spawn_artery_spurt(result.collider)
				_hit_stop(ARTERY_HIT_STOP_SCALE, ARTERY_HIT_STOP_TIME)
			# ANY kill close enough splashes the screen, not just artery ones --
			# see CLOSE_KILL_RANGE's own comment.
			if health.is_dead and _body.global_position.distance_to(result.position) <= CLOSE_KILL_RANGE:
				gory_kill_nearby.emit()

			if penetrations_left <= 0:
				break
			penetrations_left -= 1
			range_left -= ray_origin.distance_to(result.position)
			exclude.append((result.collider as CollisionObject3D).get_rid())
			ray_origin = result.position + direction * 0.01 # past the hit surface, so the next cast doesn't re-hit it


## Blood off the body that got hit, plus a splatter decal on any wall caught
## close behind them -- "a shot punches through and marks the wall behind the
## target," not blood on every wall anywhere down the shot's path. Works
## against any collider (a hand-built StaticBody3D or a func_godot-baked
## TrenchBroom wall alike): both the impact spray and the splatter come from
## a plain raycast hit + BloodFX.spawn_splatter's Decal, neither of which
## cares what kind of CollisionShape3D produced the hit.
func _spawn_blood(space: PhysicsDirectSpaceState3D, hit: Dictionary, direction: Vector3) -> void:
	var world := _body.get_tree().current_scene
	BloodFX.spawn_impact(world, hit.position, hit.normal)

	var behind_query := PhysicsRayQueryParameters3D.create(
			hit.position + direction * 0.05, hit.position + direction * WALL_SPLATTER_MAX_DISTANCE)
	behind_query.exclude = [_body.get_rid(), hit.collider.get_rid()]
	behind_query.collision_mask = 1
	var behind_result := space.intersect_ray(behind_query)
	if not behind_result.is_empty():
		BloodFX.spawn_splatter(world, behind_result.position, behind_result.normal, 0.6)


## Whether `hit_position` landed close to `collider`'s own live neck bone.
## Measured against the actual skeleton rather than a separate hitbox --
## a live enemy only has one hitbox capsule right now, so this reads the
## real, currently-animating bone position instead of needing a second
## collision shape just for this.
func _is_artery_hit(collider: Node, hit_position: Vector3) -> bool:
	var skeleton := collider.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton == null:
		return false
	var neck_idx := skeleton.find_bone("Neck")
	if neck_idx < 0:
		return false
	var neck_pos: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(neck_idx).origin
	return neck_pos.distance_to(hit_position) <= ARTERY_HIT_RADIUS


## Called right after an artery hit kills the target -- by this point
## EnemyRagdoll has already run (Health.died fires synchronously), so the
## neck's PhysicalBone3D already exists and is already simulating. Finds it
## by name and hands it to BloodFX for a sustained, bone-attached spray.
func _spawn_artery_spurt(collider: Node) -> void:
	var neck_bone := collider.find_child("Physical Bone Neck", true, false) as Node3D
	if neck_bone == null:
		return # no physical skeleton on this target (e.g. a test target) -- nothing to attach to
	# This body's OWN bones, so BloodFX can exclude just them -- the spray can
	# still land on a different nearby corpse, just never the one it's coming
	# out of. See BloodFX.spawn_artery_spurt()'s own comment.
	var own_bones := collider.find_children("Physical Bone *", "PhysicalBone3D", true, false)
	var exclude_rids: Array[RID] = []
	for bone in own_bones:
		exclude_rids.append((bone as PhysicalBone3D).get_rid())
	BloodFX.spawn_artery_spurt(neck_bone, 7.0, exclude_rids)


## Same trick as player_movement.gd's _hit_stop(): briefly slows the whole
## game to `scale` for `duration` REAL (unscaled) seconds, then snaps back.
func _hit_stop(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)


## `direction` nudged by a random amount inside a cone of `spread_degrees`.
func _spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var aim := Basis.looking_at(direction, up) # -Z of this basis is `direction`
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0)
	var offset := jitter * tan(deg_to_rad(spread_degrees))
	return (aim * Vector3(offset.x, offset.y, -1.0)).normalized()