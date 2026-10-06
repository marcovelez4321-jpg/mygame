class_name RatBender
extends Enemy

## The Rat Bender: a caster who never fights alone. A horde of rats (RatSwarm)
## swarms around his feet and does the biting; he does the spells.
##
##   PATROL - nobody around: wanders (orc walk) around where he started; his
##            rats follow at his feet and stop to eat any corpse nearby.
##   CHASE  - runs at you while the horde swarms you from every side, rats
##            darting in to bite and leaping at you. His spells:
##     - you're far: RUSH (Magic Attack 01) -- whips the horde into a frenzy:
##       faster, biting more, wearing off over a few seconds;
##     - you're close: LEAP (Magic Area Attack 02) -- a frenzy, plus a wave of
##       rats leaping at you one after another;
##     - short on rats: SUMMON (Spell Casting) -- new rats appear around him,
##       back up to the cap.
##   BODYGUARDS - a few big, tough rats that fight as part of the horde but
##            are loyal: they never chase more than guard_leash from him,
##            and only leave him to eat a corpse that's really close. Lost
##            ones burrow back up with his next summon.
##   ESCORT - his whole horde has run off ahead of him: he summons a fresh
##            swarm half its size at his feet that sticks close (escort_leash).
##   PHASE TWO - beaten down to half health, he summons his ENTOURAGE: a
##            whole second horde (past the cap), a bit tougher, that sticks
##            closer to him than the first. Once per fight; cut the summon
##            short and only the rats already up stay.
##   HEAL - hurt and left alone a moment, he stands and channels a heal
##          (Spell Casting, slowed), flashing green faster and faster. Health
##          trickles in the whole time, so knocking him out of it early (enough
##          damage mid-heal) still leaves him with what he got so far.
##
## Every spell has a wind-up you can read from across the room: he flashes
## orange, faster and faster, throbbing and swelling until it goes off --
## the same tell as a grenade's fuse.
##
## Built on Enemy, so pathfinding, health, hit zones, ragdoll and death all
## come along; it just swaps in its own brain (_physics_process).
## Rule 1 (co-op): only the host thinks; spells are short named events
## (cast started / went off) that clients can play from.

enum Mode { PATROL, CHASE, CAST_RUSH, CAST_LEAP, SUMMON, HEAL }

@export_group("Toughness")
## A headshot or artery hit on him does this many times a weapon's damage --
## never the instant kill they are on other enemies. A boss stays a fight.
@export var weak_spot_multiplier: float = 2.0

@export_group("Patrol")
@export var patrol_speed: float = 1.84
## Wanders anywhere within this many meters of where he started.
@export var patrol_radius: float = 10.0
@export var patrol_wait_min: float = 1.0
@export var patrol_wait_max: float = 3.0

@export_group("Spells")
## RUSH when you're at least this far away, at most every rush_cooldown s.
@export var rush_min_range: float = 7.0
@export var rush_cooldown: float = 6.0
## LEAP when you're this close, at most every leap_cooldown s.
@export var leap_range: float = 5.0
@export var leap_cooldown: float = 5.0
## The LEAP wave: rats this close to you jump, this many seconds apart.
@export var leap_wave_range: float = 6.0
@export var leap_wave_stagger: float = 0.05
## How far into a cast animation (0..1) the spell actually goes off.
@export_range(0.1, 1.0, 0.05) var cast_release: float = 0.55
## Plays the casting animations (rush, leap, summon) this much faster --
## the spell goes off and ends sooner to match.
@export var cast_speed: float = 1.2
## The wind-up tell: orange flashes from flash_rate_start to flash_rate_end
## a second, throbbing, swelling up to cast_swell bigger.
@export var cast_flash_color: Color = Color(1.0, 0.5, 0.05, 0.8)
@export var flash_rate_start: float = 2.0
@export var flash_rate_end: float = 12.0
@export var cast_swell: float = 0.15

@export_group("Rats")
@export var rat_cap: int = 90
## Rats per SUMMON cast, and the least time between casts.
@export var summon_batch: int = 25
@export var summon_cooldown: float = 8.0
## SUMMON is channeled like the heal: the animation plays this slowly, and
## the rats burrow up a few at a time all the way through it -- cut it short
## and the ones already up stay. Hit him for summon_cancel_damage to cut it.
@export var summon_animation_speed: float = 0.6
@export var summon_cancel_damage: float = 80.0
## The blinking tell while summoning.
@export var summon_flash_color: Color = Color(1.0, 0.08, 0.05, 0.8)

@export_group("Escort")
## His horde counts as "run off ahead" when no rat is within this many meters
## of him and the pack is out in front of him. Then he summons an escort
## half the horde's size (ignoring rat_cap) -- topped up to that, never past
## it, at most every escort_cooldown seconds.
@export var escort_lead_distance: float = 10.0
@export var escort_cooldown: float = 15.0
## The escort never chases more than this many meters from him.
@export var escort_leash: float = 6.0

@export_group("Phase Two")
## At this share of his health (0.5 = half) he summons the entourage: a full
## second horde of rat_cap rats, on top of the first.
@export_range(0.0, 1.0, 0.05) var phase_two_health: float = 0.5
## Entourage rats have this many times a normal rat's health (1.2 = 20%
## more), and never chase more than entourage_leash meters from him.
@export var entourage_health_multiplier: float = 1.2
@export var entourage_leash: float = 10.0

@export_group("Bodyguards")
@export var guard_count: int = 4
## Bodyguards are this much bigger, with this many times the health, and
## bite this many times harder, than a normal rat.
@export var guard_rat_scale: float = 2.0
@export var guard_health_multiplier: float = 4.0
@export var guard_damage_multiplier: float = 2.0
## They fight with the horde but never chase more than this from him...
@export var guard_leash: float = 6.0
## ...and only leave him to eat a corpse within this many meters of him.
@export var guard_eat_range: float = 3.0

@export_group("Healing")
## Starts a heal once below this share of his health (0.75 = 75%) and not
## hurt for heal_delay seconds; at most every heal_cooldown seconds.
@export_range(0.0, 1.0, 0.05) var heal_below: float = 0.75
@export var heal_delay: float = 4.0
@export var heal_cooldown: float = 10.0
## Health per second while channeling -- all the way through, so a heal cut
## short still counts for what it got.
@export var heal_per_second: float = 20.0
## The heal animation's speed (0.5 = half speed -- a long, punishable cast).
@export var heal_animation_speed: float = 0.5
## Hit him for this much in total during a heal and it's cancelled.
@export var heal_cancel_damage: float = 80.0
@export var heal_flash_color: Color = Color(0.2, 1.0, 0.3, 0.8)

@export_group("Animations")
@export_file("*.res") var patrol_animation: String = "res://art/animations/OrcWalk.res"
@export_file("*.res") var run_animation: String = "res://art/animations/Run.res"
@export_file("*.res") var idle_animation: String = "res://art/animations/Idle.res"
@export_file("*.res") var rush_animation: String = "res://art/animations/MagicAttack01.res"
@export_file("*.res") var leap_animation: String = "res://art/animations/MagicAreaAttack02.res"
@export_file("*.res") var summon_animation: String = "res://art/animations/SpellCasting.res"
@export_file("*.res") var heal_animation: String = "res://art/animations/SpellCasting.res"

@export_group("Sound")
@export var cast_sound: SoundEvent
@export var summon_sound: SoundEvent
@export var heal_sound: SoundEvent

const LIBRARY := "bender"

var _mode := Mode.PATROL
var _home := Vector3.ZERO
var _patrol_point := Vector3.ZERO
var _patrol_wait := 0.0
var _rush_cooldown_left := 0.0
var _leap_cooldown_left := 2.0
var _summon_cooldown_left := 0.0
var _heal_cooldown_left := 0.0
## Damage taken during the current heal or summon (they can be cut short).
var _channel_damage := 0.0
## Rats this summon will bring, and how many are up so far.
var _summon_goal := 0
var _summoned := 0
## Which swarm this summon fills: the horde, or the entourage.
var _summon_into: RatSwarm
## Summoned whenever the horde runs off ahead of him.
var _escort: RatSwarm
var _escort_cooldown_left := 0.0
## His second horde, summoned once at phase two.
var _entourage: RatSwarm
var _phase_two := false
## His few big, loyal bodyguard rats.
var _guards: RatSwarm
var _since_hurt := 999.0
var _cast_time := 0.0
var _cast_length := 1.0
var _cast_released := false
var _flash_phase := 0.0
var _flash_lit := false
var _flash_material: StandardMaterial3D
var _model: Node3D
var _model_scale := Vector3.ONE
var _meshes: Array[MeshInstance3D] = []
var _anim: AnimationPlayer
var _anim_name := ""

@onready var swarm: RatSwarm = $RatSwarm


func _ready() -> void:
	super._ready()
	_home = global_position
	_patrol_point = _home
	swarm.bender = self
	_model = get_node_or_null("Model") as Node3D
	if _model:
		_model_scale = _model.scale
		for node in _model.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(node as MeshInstance3D)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = cast_flash_color
	_setup_animations()
	_play("patrol")
	if multiplayer.is_server():
		swarm.spawn_rats.call_deferred(rat_cap, global_position)
		_make_guards.call_deferred()


func _setup_animations() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("RatBender: no AnimationPlayer in the model.")
		return
	var library := AnimationLibrary.new()
	var paths := {"patrol": patrol_animation, "run": run_animation, "idle": idle_animation,
			"rush": rush_animation, "leap": leap_animation, "summon": summon_animation, "heal": heal_animation}
	for key: String in paths:
		var animation := load(paths[key]) as Animation if ResourceLoader.exists(paths[key]) else null
		if animation:
			library.add_animation(key, animation)
		else:
			push_warning("RatBender: animation '%s' not found -- has Godot imported it yet?" % paths[key])
	_anim.add_animation_library(LIBRARY, library)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _state == State.DEAD:
		return
	_rush_cooldown_left = maxf(_rush_cooldown_left - delta, 0.0)
	_leap_cooldown_left = maxf(_leap_cooldown_left - delta, 0.0)
	_summon_cooldown_left = maxf(_summon_cooldown_left - delta, 0.0)
	_heal_cooldown_left = maxf(_heal_cooldown_left - delta, 0.0)
	_escort_cooldown_left = maxf(_escort_cooldown_left - delta, 0.0)
	_since_hurt += delta
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_update_memory(_find_nearest_player())
	swarm.target = _target

	match _mode:
		Mode.PATROL:
			_think_patrol(delta)
		Mode.CHASE:
			_think_chase_target()
		Mode.CAST_RUSH, Mode.CAST_LEAP, Mode.SUMMON, Mode.HEAL:
			_think_cast(delta)

	# The entourage and bodyguards do whatever the horde is doing (their
	# leashes keep them closer to him).
	for pack in _packs():
		pack.target = _target
		pack.order = swarm.order

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


func _think_patrol(delta: float) -> void:
	if _target and _can_see(_target):
		_mode = Mode.CHASE
		return
	if _wants_heal():
		_start_cast(Mode.HEAL)
		return
	if swarm.count() < rat_cap and _summon_cooldown_left <= 0.0:
		_begin_summon(swarm, mini(summon_batch, rat_cap - swarm.count()))
		return
	swarm.order = RatSwarm.Order.FOLLOW
	if _flat_distance_to_position(_patrol_point) < 1.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("idle")
		_patrol_wait -= delta
		if _patrol_wait <= 0.0:
			_patrol_wait = randf_range(patrol_wait_min, patrol_wait_max)
			_patrol_point = _random_patrol_point()
		return
	var direction := _nav_direction_to(_patrol_point)
	_face_position(global_position + direction)
	velocity.x = direction.x * patrol_speed
	velocity.z = direction.z * patrol_speed
	_play("patrol")


## Somewhere walkable near home.
func _random_patrol_point() -> Vector3:
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(2.0, patrol_radius)
	var point := _home + Vector3(offset.x, 0.0, offset.y)
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	return point


func _think_chase_target() -> void:
	if _target == null:
		_mode = Mode.PATROL
		return
	var can_see_now := _can_see(_target)
	var aim := _target.global_position if can_see_now else _last_seen_position
	var distance := _flat_distance_to_position(aim)
	if not _phase_two and health.current_health <= health.max_health * phase_two_health:
		_phase_two = true
		_begin_summon(_entourage_swarm(), rat_cap)
		return
	if _wants_heal():
		_start_cast(Mode.HEAL)
		return
	if can_see_now and distance <= leap_range and _leap_cooldown_left <= 0.0:
		_start_cast(Mode.CAST_LEAP)
		return
	if can_see_now and distance >= rush_min_range and _rush_cooldown_left <= 0.0:
		_start_cast(Mode.CAST_RUSH)
		return
	if _horde_ran_ahead():
		_begin_summon(_escort_swarm(), _escort_shortfall())
		return

	if swarm.count() < rat_cap and _summon_cooldown_left <= 0.0 and distance > leap_range:
		_begin_summon(swarm, mini(summon_batch, rat_cap - swarm.count()))
		return
	swarm.order = RatSwarm.Order.HUNT # the horde goes for you
	var direction := _nav_direction_to(aim)
	_face_position(aim)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	_play("run")


func _start_cast(mode: Mode) -> void:
	_mode = mode
	_cast_time = 0.0
	_cast_released = false
	_flash_phase = 0.0
	var key: String = {Mode.CAST_RUSH: "rush", Mode.CAST_LEAP: "leap", Mode.SUMMON: "summon", Mode.HEAL: "heal"}[mode]
	var speed := cast_speed
	if mode == Mode.HEAL:
		speed = heal_animation_speed
	elif mode == Mode.SUMMON:
		speed = summon_animation_speed
		_summoned = 0
	_anim_name = "" # the same spell twice in a row still replays from the start
	_play(key, false, speed)
	_cast_length = _anim.get_animation(LIBRARY + "/" + key).length / speed if _anim and _anim.has_animation(LIBRARY + "/" + key) else 1.5
	_flash_material.albedo_color = cast_flash_color
	if mode == Mode.HEAL:
		_flash_material.albedo_color = heal_flash_color
	elif mode == Mode.SUMMON:
		_flash_material.albedo_color = summon_flash_color
	_channel_damage = 0.0
	var sound := cast_sound
	if mode == Mode.SUMMON:
		sound = summon_sound
	elif mode == Mode.HEAL:
		sound = heal_sound
	SoundPlayer.play_3d(sound, global_position, get_tree().current_scene)


func _think_cast(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _target:
		_face_position(_target.global_position)
	_cast_time += delta
	if _mode == Mode.HEAL:
		health.current_health = minf(health.current_health + heal_per_second * delta, health.max_health)
	elif _mode == Mode.SUMMON:
		# Rats come up evenly over the whole cast, the last at its very end.
		var due := ceili(_summon_goal * clampf(_cast_time / _cast_length, 0.0, 1.0))
		if due > _summoned:
			_summon_into.spawn_rats(due - _summoned, global_position, 0.15)
			_summoned = due
	elif not _cast_released and _cast_time >= _cast_length * cast_release:
		_cast_released = true
		_release_spell()
	if _cast_time >= _cast_length:
		_end_cast()


## Back to fighting (or wandering). A heal or summon goes on cooldown however
## it ended -- finished or cut short.
func _end_cast() -> void:
	if _mode == Mode.HEAL:
		_heal_cooldown_left = heal_cooldown
	elif _mode == Mode.SUMMON:
		if _summon_into == swarm:
			_summon_cooldown_left = summon_cooldown
			_top_up_guards()
		elif _summon_into == _escort:
			_escort_cooldown_left = escort_cooldown
	_mode = Mode.CHASE if _target else Mode.PATROL


## A summon that brings `amount` rats up into `into` over the cast.
func _begin_summon(into: RatSwarm, amount: int) -> void:
	_summon_into = into
	_summon_goal = amount
	_start_cast(Mode.SUMMON)


## No rat anywhere near him, and the pack is out in front of him.
func _horde_ran_ahead() -> bool:
	if _escort_cooldown_left > 0.0 or swarm.count() < 2 or _escort_shortfall() <= 0:
		return false
	if swarm.nearest_rat_distance(global_position) <= escort_lead_distance:
		return false
	var forward := -global_basis.z
	return forward.dot(swarm.center() - global_position) > 0.0


## How many rats short of half the horde's size the escort is.
func _escort_shortfall() -> int:
	var have := _escort.count() if _escort else 0
	return swarm.count() / 2 - have


## The escort: normal rats with the horde's settings, on a short leash.
func _escort_swarm() -> RatSwarm:
	if _escort == null:
		_escort = swarm.duplicate() as RatSwarm
		_escort.name = "Escort"
		_escort.leash_distance = escort_leash
		add_child(_escort)
		_escort.bender = self
	return _escort


## The entourage: a second horde with the first's settings, a bit tougher,
## kept closer to him. Made at phase two.
func _entourage_swarm() -> RatSwarm:
	if _entourage == null:
		_entourage = swarm.duplicate() as RatSwarm
		_entourage.name = "Entourage"
		_entourage.rat_health_multiplier = entourage_health_multiplier
		_entourage.leash_distance = entourage_leash
		add_child(_entourage)
		_entourage.bender = self
	return _entourage


## Every pack he has besides the horde.
func _packs() -> Array[RatSwarm]:
	var packs: Array[RatSwarm] = []
	for pack in [_escort, _entourage, _guards]:
		if pack and is_instance_valid(pack):
			packs.append(pack)
	return packs


## His spells drive every pack he has.
func _release_spell() -> void:
	var all: Array[RatSwarm] = [swarm]
	all.append_array(_packs())
	match _mode:
		Mode.CAST_RUSH:
			_rush_cooldown_left = rush_cooldown
			for pack in all:
				pack.frenzy()
		Mode.CAST_LEAP:
			_leap_cooldown_left = leap_cooldown
			for pack in all:
				pack.leap_wave(leap_wave_range, leap_wave_stagger)


## Hurt enough, left alone long enough, and not healed too recently.
func _wants_heal() -> bool:
	return _heal_cooldown_left <= 0.0 and _since_hurt >= heal_delay \
			and health.current_health < health.max_health * heal_below


## A boss doesn't flinch at every bullet: it just flashes, wakes up and
## starts its healing timer over. (Replaces Enemy's stagger.)
func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state == State.DEAD:
		return
	HitFlash.flash(self)
	_since_hurt = 0.0
	_update_memory(_find_nearest_player())
	if _mode == Mode.HEAL or _mode == Mode.SUMMON:
		_channel_damage += _amount
		if _channel_damage >= (heal_cancel_damage if _mode == Mode.HEAL else summon_cancel_damage):
			_end_cast() # knocked out of it -- keeps what he got so far
			return
	if _mode == Mode.PATROL and _target:
		_mode = Mode.CHASE


func _on_died(attacker_id: int, is_critical: bool) -> void:
	_end_cast_look()
	# The horde lives on without him: keep it in the world after his body goes.
	for pack: RatSwarm in [swarm, _escort, _entourage, _guards]:
		if pack and pack.get_parent() == self:
			pack.bender = null
			pack.reparent.call_deferred(get_tree().current_scene)
	super._on_died(attacker_id, is_critical)


# ---- Bodyguards -------------------------------------------------------------

## His bodyguard swarm: a copy of the horde's settings with big, tough rats
## on a short leash.
func _make_guards() -> void:
	_guards = swarm.duplicate() as RatSwarm
	_guards.name = "Bodyguards"
	_guards.rat_scale = guard_rat_scale
	_guards.rat_health_multiplier = guard_health_multiplier
	_guards.rat_damage_multiplier = guard_damage_multiplier
	_guards.separation_distance *= guard_rat_scale
	_guards.eat_range = guard_eat_range
	_guards.leash_distance = guard_leash
	add_child(_guards)
	_guards.bender = self
	_guards.spawn_rats(guard_count, global_position)


## Back up to guard_count after losses -- they burrow up with his summon.
func _top_up_guards() -> void:
	if _guards and _guards.count() < guard_count:
		_guards.spawn_rats(guard_count - _guards.count(), global_position)


# ---- Look -------------------------------------------------------------------

## The cast tell: flashes speeding up, each one a throb, and a swell that
## grows until the spell goes off -- orange for attacks, red for a summon,
## green for a heal.
## A heal or summon is channeled, so it builds over the whole animation.
func _process(delta: float) -> void:
	var channeling := _mode == Mode.HEAL or _mode == Mode.SUMMON
	var casting := _state != State.DEAD and (_mode == Mode.CAST_RUSH or _mode == Mode.CAST_LEAP or channeling) and not _cast_released
	if not casting:
		_end_cast_look()
		return
	var build_up := _cast_length if channeling else _cast_length * cast_release
	var progress := clampf(_cast_time / maxf(build_up, 0.01), 0.0, 1.0)
	_flash_phase += delta * lerpf(flash_rate_start, flash_rate_end, progress * progress)
	_set_flash(fmod(_flash_phase, 1.0) < 0.4)
	var pulse := 0.5 + 0.5 * cos(_flash_phase * TAU)
	if _model:
		_model.scale = _model_scale * (1.0 + cast_swell * progress * progress + cast_swell * 0.5 * progress * pulse)


func _end_cast_look() -> void:
	_set_flash(false)
	if _model:
		_model.scale = _model_scale


func _set_flash(lit: bool) -> void:
	if lit == _flash_lit:
		return
	_flash_lit = lit
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material if lit else null


func _play(key: String, loop: bool = true, speed: float = 1.0) -> void:
	if _anim == null or key == _anim_name:
		return
	var animation_name := LIBRARY + "/" + key
	if not _anim.has_animation(animation_name):
		return
	_anim_name = key
	_anim.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(animation_name, 0.2, speed)
