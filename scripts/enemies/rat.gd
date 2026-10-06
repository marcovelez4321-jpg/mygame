class_name Rat
extends RigidBody3D

## One rat of a Rat Bender's horde (RatSwarm). A real physics object --
## shots and blasts shove it around -- that runs wherever its swarm says
## (desired_velocity), bites players it gets to, and every so often leaps out
## of the horde at a player's face.
##
## Deaths:
##   - Shot: pops into a little pool of blood and is gone.
##   - Killed by an explosion: splats on the spot, a big red splatter on the
##     floor where it stood.
##   - Caught by a blast but survives (stun()): flies, and splats against
##     whatever it hits next, leaving a red spot.
##
## Rule 1 (co-op): only the host moves and bites. The swarm is the brain;
## this script just follows orders and reacts to physics.

enum State { EMERGE, RUN, LEAP, THROWN, DEAD }

const ANIM_RUN := "Run"
const ANIM_IDLE := "Idle"
const ANIM_ATTACK := "Attack"
## Rats further than this from the camera animate at a lower rate
## (FAR_ANIMATION_RATE times a second) -- they're small and nobody can tell.
const FAR_ANIMATION_DISTANCE := 12.0
const FAR_ANIMATION_RATE := 12.0

@export_group("Movement")
## Plays the running animation this much faster (1.5 = 1.5x speed).
@export var run_animation_speed: float = 1.5
## How fast it reaches the swarm's chosen velocity, m/s².
@export var acceleration: float = 30.0
## Hops this hard (m/s) when it's trying to move but stuck on a step or lip.
@export var hop_speed: float = 3.5

@export_group("Bite")
@export var bite_damage: float = 5.0
@export var bite_interval: float = 0.8
## How close to a player's feet it has to be to bite, meters.
@export var bite_reach: float = 0.8

@export_group("Leap")
## Swarming a player, a rat this far from them (meters) may leap: it
## launches at their chest, nose first, bites on the way in and bounces off.
@export var leap_range_min: float = 1.2
@export var leap_range_max: float = 3.5
## Chance per second each rat in range takes the leap, and its rest after.
@export var leap_chance: float = 0.35
@export var leap_cooldown: float = 2.5
@export var leap_damage: float = 10.0
## Flight time to the target (s) -- shorter = flatter, faster leap.
@export var leap_time: float = 0.35
## How far it tips nose-down/up in the air, degrees.
@export var leap_tilt: float = 35.0

@export_group("Variety")
## Every rat rolls its own size in this range. Bigger rats have more health
## (by size²), weigh more (size³) and run a little slower; little ones are
## quick and pop from one hit.
@export var size_min: float = 0.85
@export var size_max: float = 1.2
## On top of that, each rat's own speed is this much faster or slower (0.1
## = up to 10% either way).
@export var speed_variation: float = 0.1

@export_group("Burrowing")
## Summoned rats burrow up out of the floor: a dirt hole and a spray of dirt,
## then the rat squirms up from emerge_depth below over emerge_time seconds,
## shaking side to side (wiggle, radians) less and less as it surfaces.
@export var emerge_time: float = 0.7
@export var emerge_depth: float = 0.3
@export var wiggle: float = 0.5
@export var hole_size: float = 0.45
@export var dirt_color: Color = Color(0.13, 0.09, 0.06)

@export_group("Death")
@export var blood_color: Color = Color(0.55, 0.02, 0.02)
## Size (m) of the pool a shot rat leaves, and of the spot a launched rat
## splats into.
@export var pool_size: float = 0.7
@export var splat_size: float = 0.9
## How big its blood bursts are, compared with a normal hit's: while it eats
## (gore), and when it dies -- shot, blasted or splatted (death_gore).
@export var gore: float = 2.5
@export var death_gore: float = 0.85

## Set by RatSwarm.
var swarm: RatSwarm
## Where in the pack it likes to be: a direction (unit) and how far out.
var slot := Vector2.RIGHT
var slot_radius := 1.5
## What the swarm wants it doing this tick (horizontal m/s).
var desired_velocity := Vector3.ZERO
## Nibbling a corpse -- plays the attack clip in place, flicking blood.
var eating := false
## One of the rats hauling a corpse away (RatSwarm's corpse dragging).
var dragging := false
## This rat's own size, pace and rhythm (rolled once, in _roll_variety()).
## The swarm reads speed_scale and rhythm_seed for its steering.
var size := 1.0
var speed_scale := 1.0
var rhythm_seed := 0.0
## Set by RatSwarm before it's added: wait this long, then burrow up out of
## the floor. Below 0 = just appear (not summoned).
var emerge_delay := -1.0

var _state := State.RUN
var _bite_cooldown := 0.0
var _stuck_time := 0.0
var _thrown_time := 0.0
var _pop_pending := false
var _leap_cooldown := 0.0
var _leap_bit := false
var _anim: AnimationPlayer
var _anim_name := ""
var _anim_time := 0.0
var _anim_step := 0.0
var _lod_timer := 0.0
var _emerge_time := 0.0
var _dug := false
var _gore_timer := 0.0

@onready var health: Health = $Health
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	lock_rotation = true # upright; the Visual turns to face where it runs
	_roll_variety()
	health.died.connect(_on_died)
	body_entered.connect(_on_body_entered)
	# Players and its own Bender walk straight through the horde instead of
	# tripping over 30 little physics bodies.
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D)
	if swarm and is_instance_valid(swarm.bender):
		add_collision_exception_with(swarm.bender as PhysicsBody3D)
	BloodFX.warm_splat_texture(blood_color)
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		# Advanced by hand in _process, so far-away rats can animate less often.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anim.seek(randf() * 0.5, true) # out of step with each other
	_lod_timer = randf() * 0.5
	if emerge_delay >= 0.0:
		_start_burrow()


## Waits under the floor, frozen in place, until its turn to dig up.
func _start_burrow() -> void:
	_state = State.EMERGE
	_emerge_time = -emerge_delay
	BloodFX.warm_splat_texture(dirt_color) # no hitch on the first hole
	freeze = true
	_visual.position.y = -emerge_depth * size
	_visual.rotation.y = randf() * TAU
	_visual.visible = false
	_play(ANIM_RUN, true) # scrabbling its way up


## Out of the ground: a normal rat from here on.
func _surface() -> void:
	freeze = false
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3(0.0, _visual.rotation.y, 0.0)
	_visual.visible = true
	_state = State.RUN


## No two rats alike. Rule 1 (co-op): rolled on the host; the size and seed
## travel with the spawn so every screen sees the same rat.
## On top of that, its swarm can make every rat bigger and tougher (the
## Bender's bodyguards: RatSwarm.rat_scale / rat_health_multiplier).
func _roll_variety() -> void:
	var variety := randf_range(size_min, size_max)
	size = variety * (swarm.rat_scale if swarm else 1.0)
	speed_scale = randf_range(1.0 - speed_variation, 1.0 + speed_variation) / sqrt(variety)
	rhythm_seed = randf() * 1000.0
	# On the model, not Visual: Visual is the part that turns to face where
	# it runs, and a turning node has to stay unscaled.
	($Visual/Model as Node3D).scale *= size
	var shape := $CollisionShape3D as CollisionShape3D
	var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size *= size
	shape.shape = box
	shape.position *= size
	mass *= size * size * size
	health.max_health *= variety * variety * (swarm.rat_health_multiplier if swarm else 1.0)
	health.current_health = health.max_health
	bite_reach *= size
	var damage_multiplier := swarm.rat_damage_multiplier if swarm else 1.0
	bite_damage *= damage_multiplier
	leap_damage *= damage_multiplier


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _pop_pending:
		_pop_pending = false
		if _state == State.THROWN:
			_splat_here() # killed by the blast that hit it: no flight, just splat
		else:
			_pop()
		return
	match _state:
		State.RUN:
			_run(delta)
			_maybe_leap(delta)
		State.LEAP:
			_fly_leap(delta)
		State.THROWN:
			_thrown_time += delta
		State.EMERGE:
			_emerge_time += delta
			if _emerge_time >= emerge_time:
				_surface()


func _run(delta: float) -> void:
	_bite_cooldown = maxf(_bite_cooldown - delta, 0.0)
	var velocity := linear_velocity
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired_velocity, acceleration * delta)
	linear_velocity = Vector3(flat.x, velocity.y, flat.z)
	if desired_velocity.length_squared() > 0.25:
		_face(desired_velocity, delta)
		# Wants to move but isn't getting anywhere: a step or a lip -- hop it.
		_stuck_time = _stuck_time + delta if flat.length() < 0.4 else 0.0
		if _stuck_time > 0.25 and _on_ground():
			_stuck_time = 0.0
			linear_velocity.y = hop_speed
	_try_bite()


func _try_bite() -> void:
	if _bite_cooldown > 0.0 or swarm == null:
		return
	var target := swarm.target
	if target == null or not is_instance_valid(target):
		return
	var offset := target.global_position - global_position
	if absf(offset.y) > 1.2 or Vector2(offset.x, offset.z).length() > bite_reach:
		return
	# A Bender spell whips them into a frenzy: they bite faster.
	_bite_cooldown = bite_interval / swarm.bite_rate()
	_bite(target, bite_damage)


func _bite(target: Node3D, damage: float) -> void:
	var target_health := target.get_node_or_null("Health") as Health
	if target_health:
		target_health.take_damage(damage, Health.NO_ATTACKER)
	_play(ANIM_ATTACK, false)
	if swarm:
		swarm.rat_bit(global_position)


## Swarming a player and close enough: now and then, leap.
func _maybe_leap(delta: float) -> void:
	_leap_cooldown = maxf(_leap_cooldown - delta, 0.0)
	if _leap_cooldown > 0.0 or swarm == null or swarm.order != RatSwarm.Order.HUNT:
		return
	var target := swarm.target
	if target == null or not is_instance_valid(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if distance >= leap_range_min and distance <= leap_range_max and randf() < leap_chance * delta:
		leap(target)


## Launch at the target's chest on a ballistic arc that gets there in
## leap_time -- velocity = gap / time, plus what gravity will take off.
func leap(target: Node3D) -> void:
	if _state != State.RUN or not _on_ground():
		return
	var chest := target.global_position + Vector3.UP * 1.0
	var gap := chest - global_position
	var gravity := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float * gravity_scale
	linear_velocity = gap / leap_time + Vector3.UP * 0.5 * gravity * leap_time
	_face(gap, 1.0)
	_state = State.LEAP
	_leap_bit = false
	_leap_cooldown = leap_cooldown
	_set_contacts(true)
	_play(ANIM_ATTACK, false)


## In the air: nose follows the arc; bites once if it reaches the target,
## then bounces off them; lands and goes back to running.
func _fly_leap(_delta: float) -> void:
	var tilt := clampf(-linear_velocity.y * 6.0, -leap_tilt, leap_tilt)
	_visual.rotation.x = deg_to_rad(tilt)
	if not _leap_bit and swarm and is_instance_valid(swarm.target):
		var offset := swarm.target.global_position + Vector3.UP * 0.9 - global_position
		if offset.length() < bite_reach:
			_leap_bit = true
			_bite(swarm.target, leap_damage)
			linear_velocity = Vector3(-linear_velocity.x * 0.3, 2.0, -linear_velocity.z * 0.3)
	if linear_velocity.y <= 0.0 and _on_ground():
		_visual.rotation.x = 0.0
		_set_contacts(false)
		_state = State.RUN

## Explosion.push() calls this when a blast launches it: it flies, and splats
## on the next thing it hits.
func stun() -> void:
	if _state == State.THROWN:
		return
	if _state == State.EMERGE:
		_surface() # blown out of its hole
	_state = State.THROWN
	_thrown_time = 0.0
	_set_contacts(true)
	remove_from_group("enemies")


func _on_body_entered(_body: Node) -> void:
	# A few hundredths of a second of grace, or the floor it was launched off
	# would splat it on the spot.
	if _state == State.THROWN and _thrown_time > 0.08:
		_splat()


## Shot (or hurt any other way): decided next physics tick, once we know
## whether a blast did it (Explosion hurts first, then pushes -- stun()).
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	_pop_pending = true


## Shot dead: a burst of blood and a little pool where it stood.
func _pop() -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, global_position + Vector3.UP * 0.1, Vector3.UP, blood_color, death_gore * size)
	var floor_hit := _ray(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 0.6)
	if not floor_hit.is_empty():
		BloodFX.spawn_splatter(world, floor_hit.position, floor_hit.normal, pool_size, blood_color)
	_remove()


## Killed by a blast: splatted where it stood -- a big red splatter on the
## floor, a burst of blood, gone.
func _splat_here() -> void:
	var world := get_tree().current_scene
	var floor_hit := _ray(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 1.0)
	var at: Vector3 = floor_hit.position if not floor_hit.is_empty() else global_position
	var normal: Vector3 = floor_hit.normal if not floor_hit.is_empty() else Vector3.UP
	BloodFX.spawn_splatter(world, at, normal, splat_size * size, blood_color)
	BloodFX.spawn_impact(world, at + normal * 0.1, normal, blood_color, death_gore * 1.2 * size)
	_remove()


## Launched and hit something: a red spot on whatever it hit.
func _splat() -> void:
	var world := get_tree().current_scene
	var heading := linear_velocity.normalized() if linear_velocity.length() > 0.5 else Vector3.DOWN
	var hit := _ray(global_position - heading * 0.2, global_position + heading * 0.8)
	if hit.is_empty():
		hit = _ray(global_position, global_position + Vector3.DOWN * 0.8)
	if not hit.is_empty():
		BloodFX.spawn_splatter(world, hit.position, hit.normal, splat_size * size, blood_color)
		BloodFX.spawn_impact(world, hit.position, hit.normal, blood_color, death_gore * 1.2 * size)
	_remove()


func _remove() -> void:
	_state = State.DEAD
	if swarm:
		swarm.forget(self)
	queue_free()


func _set_contacts(on: bool) -> void:
	contact_monitor = on
	max_contacts_reported = 2 if on else 0


func _on_ground() -> bool:
	return not _ray(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.15).is_empty()


func _face(direction: Vector3, delta: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(flat.normalized(), Vector3.UP)
	_visual.basis = _visual.basis.slerp(target_basis, clampf(12.0 * delta, 0.0, 1.0)).orthonormalized()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query)


# ---- Look -------------------------------------------------------------------

func _process(delta: float) -> void:
	if _state == State.EMERGE:
		_show_emerging()
	if eating:
		_eat_gore(delta)
	if _anim == null:
		return
	# A one-off bite plays out; otherwise run, stand, or chew (eating loops).
	var biting := _anim_name == ANIM_ATTACK and _anim.is_playing() \
			and _anim.get_animation(ANIM_ATTACK).loop_mode == Animation.LOOP_NONE
	if _state == State.RUN and not biting:
		var moving := Vector2(linear_velocity.x, linear_velocity.z).length() > 0.6
		_play(ANIM_ATTACK if eating else (ANIM_RUN if moving else ANIM_IDLE), true)
	# Far away: animate in bigger, less frequent steps.
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var camera := get_viewport().get_camera_3d()
		var far := camera != null and camera.global_position.distance_to(global_position) > FAR_ANIMATION_DISTANCE
		_anim_step = 1.0 / FAR_ANIMATION_RATE if far else 0.0
	_anim_time += delta
	if _anim_time >= _anim_step:
		_anim.advance(_anim_time)
		_anim_time = 0.0


## Eating a body: every so often a little spray of blood from its mouth, and
## now and then a spot of it on the floor.
func _eat_gore(delta: float) -> void:
	_gore_timer -= delta
	if _gore_timer > 0.0:
		return
	_gore_timer = randf_range(0.35, 0.8)
	var world := get_tree().current_scene
	var forward := -_visual.global_basis.z
	var mouth := global_position + forward * 0.18 * size + Vector3.UP * 0.08 * size
	BloodFX.spawn_impact(world, mouth, (Vector3.UP + forward * 0.5).normalized(), blood_color, gore * 0.65)
	if randf() < 0.3:
		BloodFX.spawn_splatter(world, global_position + forward * 0.2 * size, Vector3.UP, pool_size * 0.6, blood_color)
	if swarm:
		swarm.fed_on(self) # enough mouthfuls and the pack breeds


## Squirming up out of the floor: rises fast then eases, nose up, shaking
## side to side less and less as it gets clear.
func _show_emerging() -> void:
	if _emerge_time < 0.0:
		return
	if not _dug:
		_dug = true
		_visual.visible = true
		_dig_fx()
	var t := clampf(_emerge_time / maxf(emerge_time, 0.01), 0.0, 1.0)
	var rise := 1.0 - (1.0 - t) * (1.0 - t)
	_visual.position.y = -emerge_depth * size * (1.0 - rise)
	var shake := 1.0 - t
	_visual.rotation.z = sin(_emerge_time * 28.0 + rhythm_seed) * wiggle * shake
	_visual.rotation.x = -0.6 * shake # nose up out of the hole


## A dark hole in the floor and a little spray of dirt.
func _dig_fx() -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_splatter(world, global_position + Vector3.UP * 0.01, Vector3.UP, hole_size * size, dirt_color)
	var dirt := GPUParticles3D.new()
	dirt.amount = 10
	dirt.lifetime = 0.6
	dirt.one_shot = true
	dirt.explosiveness = 0.9
	dirt.draw_pass_1 = BloodFX.droplet_mesh()
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 35.0
	material.initial_velocity_min = 1.5
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0.0, -9.8, 0.0)
	material.scale_min = 0.6
	material.scale_max = 1.2
	material.color = dirt_color.lightened(0.15)
	dirt.process_material = material
	world.add_child(dirt)
	dirt.global_position = global_position + Vector3.UP * 0.05
	dirt.emitting = true
	dirt.finished.connect(dirt.queue_free)


func _play(animation_name: String, loop: bool) -> void:
	if _anim == null or not _anim.has_animation(animation_name):
		return
	var loop_mode := Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var animation := _anim.get_animation(animation_name)
	if animation_name == _anim_name and _anim.is_playing() and animation.loop_mode == loop_mode:
		return
	_anim_name = animation_name
	animation.loop_mode = loop_mode
	_anim.play(animation_name, 0.1, run_animation_speed if animation_name == ANIM_RUN else 1.0)
	if not loop:
		_anim.seek(0.0, true) # a bite always starts from the top
