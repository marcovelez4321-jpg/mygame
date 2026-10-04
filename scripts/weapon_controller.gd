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
## player's own screen. Presentation only (hud.gd's screen droplets).
signal gory_kill_nearby
## An artery (neck) hit landed -- a kill too unless artery_instant_kill is off.
## Presentation only (weapon_sound.gd's artery sounds) -- fires alongside
## hit_confirmed, not instead of it. Carries the neck bone itself (not just a
## position) so a listener can attach a SOUND to it the same way
## _spawn_artery_spurt() below attaches the blood particles -- it keeps
## following the spurt as the ragdoll falls and settles, instead of playing
## from one fixed point in empty air.
signal artery_kill(bone: Node3D)

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

			var kind: HitKind = _hit_kind(result.collider, result.position) if not health.is_dead else HitKind.NORMAL
			var damage := _damage_for(shot.weapon, kind, health)
			health.take_damage(damage, shot.attacker_id, direction, result.position, shot.weapon.impact_force)
			hit_confirmed.emit(health.is_dead, kind)
			_play_hit_effects(space, result, direction, kind, health.is_dead)

			if penetrations_left <= 0:
				break
			penetrations_left -= 1
			range_left -= ray_origin.distance_to(result.position)
			exclude.append((result.collider as CollisionObject3D).get_rid())
			ray_origin = result.position + direction * 0.01 # past the hit surface, so the next cast doesn't re-hit it


## The weapon's own damage times the multiplier for where it landed (the Hit
## Zones exports), or everything the target has left for an instant-kill artery.
func _damage_for(weapon: WeaponData, kind: HitKind, health: Health) -> float:
	match kind:
		HitKind.HEADSHOT:
			return weapon.damage * headshot_damage_multiplier
		HitKind.ARTERY:
			return health.current_health if artery_instant_kill else weapon.damage * artery_damage_multiplier
	return weapon.damage * body_damage_multiplier


## Every cosmetic effect of one confirmed hit, in one place -- nothing here
## touches health or gameplay. Rule 1 (co-op): resolve_shot() only runs on the
## host, so this is the hook for the other player: the host will send the hit
## (target, position, normal, direction, kind, killed) and each client calls
## this same function to bleed its own copy of the enemy locally.
func _play_hit_effects(space: PhysicsDirectSpaceState3D, hit: Dictionary, direction: Vector3, kind: HitKind, killed: bool) -> void:
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
		gory_kill_nearby.emit()


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


## Artery, headshot, or a plain body hit. Measured against the live,
## currently-animating skeleton rather than separate hitboxes -- a live enemy
## only has one capsule, so this reads where the neck and head actually are
## this frame. The two zones overlap around the jaw; whichever spot the shot
## landed closer to wins, so the neck doesn't swallow shots to the face.
## Runs only where resolve_shot() runs -- the host, in co-op (Rule 1).
func _hit_kind(collider: Node, hit_position: Vector3) -> HitKind:
	var skeleton := collider.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton == null:
		return HitKind.NORMAL

	var artery_distance := INF
	var neck := skeleton.find_bone("Neck")
	if neck >= 0:
		artery_distance = _bone_position(skeleton, neck).distance_to(hit_position)

	var head_distance := INF
	var head := skeleton.find_bone("Head")
	if head >= 0:
		head_distance = _head_center(skeleton, head).distance_to(hit_position)

	var in_artery := artery_distance <= artery_hit_radius
	var in_head := head_distance <= headshot_radius
	if in_artery and (not in_head or artery_distance <= head_distance):
		return HitKind.ARTERY
	if in_head:
		return HitKind.HEADSHOT
	return HitKind.NORMAL


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
	BloodFX.spawn_artery_spurt(neck_bone, ARTERY_BLEED_TIME, _own_body_rids(collider))
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