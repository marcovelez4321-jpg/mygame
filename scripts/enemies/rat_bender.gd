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

@export_group("Patrol")
@export var patrol_speed: float = 1.6
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
@export var summon_cancel_damage: float = 40.0

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
@export var heal_cancel_damage: float = 40.0
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
		_start_cast(Mode.SUMMON)
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
	if _wants_heal():
		_start_cast(Mode.HEAL)
		return
	if can_see_now and distance <= leap_range and _leap_cooldown_left <= 0.0:
		_start_cast(Mode.CAST_LEAP)
		return
	if can_see_now and distance >= rush_min_range and _rush_cooldown_left <= 0.0:
		_start_cast(Mode.CAST_RUSH)
		return
	if swarm.count() < rat_cap and _summon_cooldown_left <= 0.0 and distance > leap_range:
		_start_cast(Mode.SUMMON)
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
		_summon_goal = mini(summon_batch, rat_cap - swarm.count())
		_summoned = 0
	_anim_name = "" # the same spell twice in a row still replays from the start
	_play(key, false, speed)
	_cast_length = _anim.get_animation(LIBRARY + "/" + key).length / speed if _anim and _anim.has_animation(LIBRARY + "/" + key) else 1.5
	_flash_material.albedo_color = heal_flash_color if mode == Mode.HEAL else cast_flash_color
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
			swarm.spawn_rats(due - _summoned, global_position, 0.15)
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
		_summon_cooldown_left = summon_cooldown
	_mode = Mode.CHASE if _target else Mode.PATROL


func _release_spell() -> void:
	match _mode:
		Mode.CAST_RUSH:
			_rush_cooldown_left = rush_cooldown
			swarm.frenzy()
		Mode.CAST_LEAP:
			_leap_cooldown_left = leap_cooldown
			swarm.leap_wave(leap_wave_range, leap_wave_stagger)


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
	if swarm.get_parent() == self:
		swarm.bender = null
		swarm.reparent.call_deferred(get_tree().current_scene)
	super._on_died(attacker_id, is_critical)


# ---- Look -------------------------------------------------------------------

## The cast tell: flashes speeding up, each one a throb, and a swell that
## grows until the spell goes off -- orange for attacks, green for a heal.
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
