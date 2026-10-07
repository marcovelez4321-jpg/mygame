class_name SwarmKing
extends RatBender

## The Swarm King: a Rat Bender who also commands roaches. Everything the
## Rat Bender does (the horde, bodyguards, escort, phase two, heal, summon)
## plus a cloud of roaches that swirls around him -- and every spell drives
## BOTH swarms at once, picked by how far away you are:
##   - far (rush_min_range+): RUSH -- the rats frenzy and every roach dives at
##     you for swarm_rush_time seconds (a Swarm Rush: no taking turns);
##   - mid (volley_min_range to rush_min_range): VOLLEY -- every spitter
##     spits at you in a quick ripple while the rats near you pounce;
##   - closing in (you're within shield_range and coming at him): SHIELD --
##     the roaches pull in tight around him as a living Cloud Shield and the
##     rats crowd in at his feet, for shield_time seconds;
##   - close (leap_range): LEAP -- the rats leap at you in a wave and his
##     roaches dive at you too.
## His summon tops his roaches back up to roach_count along with the rats.
## While he lives his rats and roaches never fight each other or him
## (Factions.allied()); once he's dead they're wild again and go at it.
## Rule 1 (co-op): host only, like the Rat Bender.

enum Spell { NONE, VOLLEY, SHIELD }

@export_group("Roaches")
## Roaches in his cloud; his summon tops them back up to this.
@export var roach_count: int = 18
## VOLLEY range (out to rush_min_range), its cooldown, and the gap between
## one spitter's glob and the next.
@export var volley_min_range: float = 6.0
@export var volley_cooldown: float = 6.0
@export var volley_stagger: float = 0.08
## Rats this close to you pounce during a VOLLEY.
@export var volley_rat_leap_range: float = 4.0
## SHIELD: when you're within shield_range and closing in faster than
## approach_speed (m/s) -- it lasts shield_time seconds, every shield_cooldown.
@export var shield_range: float = 10.0
@export var approach_speed: float = 1.0
@export var shield_time: float = 5.0
@export var shield_cooldown: float = 10.0
## How long every roach keeps diving at you after a RUSH, and after a LEAP.
@export var swarm_rush_time: float = 4.0
@export var close_rush_time: float = 2.0

## His roaches (untyped entries: any may be freed).
var _roaches: Array = []
var _roach_spell := Spell.NONE
var _volley_cooldown_left := 0.0
var _shield_cooldown_left := 0.0
var _shield_left := 0.0
## How fast you're coming at him (m/s, smoothed), for SHIELD.
var _approach := 0.0
var _last_distance := -1.0


func _ready() -> void:
	super._ready()
	_top_up_roaches.call_deferred()


## Alive: his rats and roaches answer to him (Factions.master_of()).
func controls_roaches() -> bool:
	return _state != State.DEAD


## His roaches are holding the Cloud Shield around him.
func is_shielding() -> bool:
	return _shield_left > 0.0 and _state != State.DEAD


func _physics_process(delta: float) -> void:
	_volley_cooldown_left = maxf(_volley_cooldown_left - delta, 0.0)
	_shield_cooldown_left = maxf(_shield_cooldown_left - delta, 0.0)
	_shield_left = maxf(_shield_left - delta, 0.0)
	super._physics_process(delta)


## The Rat Bender's fight, with his two roach spells checked first.
func _think_chase_target() -> void:
	if _target and not _wants_heal():
		var can_see_now := _can_see(_target)
		var distance := _flat_distance_to_position(_target.global_position)
		var delta := get_physics_process_delta_time()
		if _last_distance >= 0.0 and delta > 0.0:
			_approach = lerpf(_approach, (_last_distance - distance) / delta, 0.1)
		_last_distance = distance
		if can_see_now and distance > leap_range and distance <= shield_range \
				and _approach > approach_speed and _shield_cooldown_left <= 0.0:
			_roach_spell = Spell.SHIELD
			_start_cast(Mode.CAST_LEAP)
			return
		if can_see_now and distance >= volley_min_range and distance < rush_min_range \
				and _volley_cooldown_left <= 0.0 and _has_spitters():
			_roach_spell = Spell.VOLLEY
			_start_cast(Mode.CAST_RUSH)
			return
	super._think_chase_target()
	if is_shielding():
		swarm.order = RatSwarm.Order.FOLLOW # the rats crowd in at his feet too


## Every spell drives both swarms.
func _release_spell() -> void:
	var packs: Array[RatSwarm] = [swarm]
	packs.append_array(_packs())
	match _roach_spell:
		Spell.SHIELD:
			_shield_cooldown_left = shield_cooldown
			_shield_left = shield_time
			for pack in packs:
				pack.order = RatSwarm.Order.FOLLOW
		Spell.VOLLEY:
			_volley_cooldown_left = volley_cooldown
			var delay := 0.0
			for roach in _living_roaches():
				if roach.is_spitter:
					get_tree().create_timer(delay).timeout.connect(roach.spit_now.bind(_target))
					delay += volley_stagger
			for pack in packs:
				pack.leap_at(volley_rat_leap_range, volley_stagger)
		_:
			var rush_mode := _mode
			super._release_spell() # the rats: a frenzy (RUSH) or a leap wave (LEAP)
			var rush_time := swarm_rush_time if rush_mode == Mode.CAST_RUSH else close_rush_time
			for roach in _living_roaches():
				roach.swarm_rush(_target, rush_time)
	_roach_spell = Spell.NONE


## A finished summon brings his roaches back up to roach_count too.
func _end_cast() -> void:
	var was_summon := _mode == Mode.SUMMON and _summon_into == swarm
	super._end_cast()
	_roach_spell = Spell.NONE
	if was_summon:
		_top_up_roaches()


func _living_roaches() -> Array[FlyingRoach]:
	var alive: Array[FlyingRoach] = []
	for roach in _roaches:
		if is_instance_valid(roach) and roach.get_state() != FlyingRoach.State.DEAD:
			alive.append(roach)
	_roaches = alive.duplicate()
	return alive


func _has_spitters() -> bool:
	return _living_roaches().any(func(roach: FlyingRoach) -> bool: return roach.is_spitter)


## Hatches roaches around him (each a spitter or not, 50/50) up to roach_count.
func _top_up_roaches() -> void:
	if _state == State.DEAD:
		return
	var world := get_tree().current_scene
	for i in mini(roach_count - _living_roaches().size(), RoachCarry.room_for_roaches(get_tree())):
		var roach := RoachCarry.ROACH_SCENE.instantiate() as FlyingRoach
		roach.kind = FlyingRoach.Kind.SPITTER if randf() < RoachCarry.BRED_SPITTER_CHANCE else FlyingRoach.Kind.NORMAL
		roach.master = self
		world.add_child(roach)
		var out := Vector2.from_angle(randf() * TAU) * randf_range(0.8, 2.0)
		roach.global_position = global_position + Vector3(out.x, 1.6 + randf(), out.y)
		roach.burst_out.call_deferred(Vector3(out.x, 1.0, out.y).normalized())
		_roaches.append(roach)
