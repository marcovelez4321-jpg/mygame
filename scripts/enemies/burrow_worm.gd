class_name BurrowWorm
extends Node3D

## A giant worm that swims through the ground and walls, Terraria-style
## (the Eater of Worlds / Devourer): no terrain is dug -- it just passes
## through everything, and the floor and walls hide whatever's underground.
##
## Movement is the Terraria worm's: only the head thinks. Inside the ground
## (or a wall) it has full control -- it accelerates toward where it wants
## to be, a limited acceleration, so it overshoots and comes round in big
## arcs. Out in the open air it has (almost) no control: gravity takes it,
## so a lunge at you erupts out of the floor, arcs over and dives back in.
## Far from you it tunnels under the floor toward you (lurk_depth down),
## shaking the camera and kicking up a trail of dirt you can follow; within
## breach_range it comes straight up at you.
##
## The body is follow-the-leader: each segment keeps segment_spacing behind
## the one in front, so the whole worm traces the head's path. Every segment
## can be shot (each has its own hitbox and Health, all feeding the worm's
## one Health); touching any of it hurts, the head bites hardest.
##
## Look: the PSX Creatures kit's tape_worm, which is flat -- so each segment
## is slices_per_segment copies of it fanned round the body's axis (60 degrees
## apart for 3), each a little longer than a segment so they overlap like
## scales, and every segment twisted a little more than the last so the
## ridges spiral down the body. Reads as a round, ribbed, fleshy tube from
## any angle. The head's maw is the kit's barnacle, mouth forward.
## Rule 1 (co-op): the host moves it and deals the damage.

const TAPE_WORM := preload("res://art/props/PSX Creatures/Models/FBX/tape_worm.fbx")
const MAW := preload("res://art/props/PSX Creatures/Models/FBX/barnacle.fbx")

@export_group("Body")
@export var segment_count: int = 20
## Distance between segment centres, meters.
@export var segment_spacing: float = 0.8625
## Body thickness (radius, meters) at the head, tapering to tail_radius.
@export var head_radius: float = 0.8625
@export var tail_radius: float = 0.345
## Tape worm slices fanned round each segment (3 = 60 degrees apart).
@export var slices_per_segment: int = 3
## Each slice's length as a multiple of segment_spacing (above 1 they
## overlap), and how thick a slice is as a share of the segment's radius.
@export var slice_overlap: float = 1.8
@export var slice_thickness: float = 0.45
## Each segment is turned this many more degrees round the body than the
## one in front, so the ridges spiral.
@export var twist_per_segment: float = 17.0
@export var skin_material: Material
@export var maw_material: Material
## Size of the barnacle maw across, as a multiple of the head's diameter.
@export var maw_size: float = 1.15

@export_group("Movement")
## Tunnelling speed under the floor (15% up on the first version's 11).
@export var max_speed: float = 12.65
## How fast it can change velocity inside the ground (m/s²): lower = wider,
## lazier arcs and more overshoot.
@export var acceleration: float = 16.1
## Out of the ground: gravity (it has no control in the air).
@export var air_gravity: float = 16.0
## Tunnelling this far under the floor...
@export var lurk_depth: float = 3.0
## ...never deeper than this.
@export var max_depth: float = 10.0
## Players further than this are ignored: it wanders, breaching now and then.
@export var notice_range: float = 45.0
@export var wander_radius: float = 25.0
## Chance a wander goal is up in the air (so it breaches just to show off).
@export_range(0.0, 1.0, 0.05) var wander_breach_chance: float = 0.3

@export_group("The Leap")
## Its attack, over and over: it tunnels to a spot leap_distance away from
## where it means to come down, sinks to dive_depth while the ground there
## shakes and cracks and the rumble swells (windup_time -- your warning),
## then erupts in a column of dirt with a roar and arcs leap_height high
## down onto where it guesses you'll be -- the spitter roach's lead
## (WormLeap) -- the whole body pouring out after it; landing sends out a
## shockwave; it dives back in, swings round underground (dive_time) and
## goes again.
@export var leap_height: float = 12.6
## How far from its landing spot it erupts.
@export var leap_distance: float = 7.0
## In the air it keeps re-guessing and eases its sideways drift toward the
## new guess, at most this many m/s² -- a smooth correction, the arc stays
## an arc (0 = committed once it leaves the ground).
@export var air_steer: float = 5.0
## The re-aim eases in over this long after it leaves the ground (so the
## turn into the new heading is gradual, never a snap).
@export var steer_ramp: float = 0.6
@export var dive_depth: float = 7.0
@export var windup_time: float = 1.1
@export var rise_speed: float = 22.0
@export var dive_time: float = 1.4
## Every so often a smaller skimming hop instead (a quick breach and back in).
@export_range(0.0, 1.0, 0.05) var hop_chance: float = 0.25
@export var hop_height: float = 4.9

@export_group("Shockwave")
## Landing from a leap: everything within shockwave_radius -- players,
## enemies, creatures, loose bodies -- except its own escorts is thrown back
## (shockwave_force out, shockwave_lift up, less further out) and takes
## shockwave_damage (less further out).
@export var shockwave_radius: float = 9.0
@export var shockwave_force: float = 14.0
@export var shockwave_lift: float = 6.0
@export var shockwave_damage: float = 10.0

@export_group("Spider Brood")
## At the top of a big leap it lingers in the air for a moment (apex_hang
## seconds, gravity down to apex_gravity of normal; the arc carries on, just
## stretched at the top), a swelling rolls down
## its body (brood_bulge fatter), and brood_count spiders burst out of it
## one after another as the swelling passes -- each from its own segment,
## flung out sideways and up at brood_speed in a spray of blood -- then it
## falls and lands. They join one spider pack of its own (Population caps
## them like any spider). Skimming hops don't do it; brood_chance per leap.
@export var brood_count: int = 30
@export_range(0.0, 1.0, 0.05) var brood_chance: float = 1.0
@export var brood_speed: float = 7.0
@export var brood_bulge: float = 0.7
@export var apex_hang: float = 0.6
@export_range(0.0, 1.0, 0.05) var apex_gravity: float = 0.15

@export_group("Escorts")
## Deepmaws that swim along under it and come up at anyone near it
## (Deepmaw.guard_node = this worm). Host only, spawned with it.
@export var escort_scene: PackedScene = preload("res://scenes/enemy/deepmaw.tscn")
@export var escort_count: int = 3

@export_group("Attack")
## The head's bite and any other segment's touch, and how often each can
## hurt the same player.
@export var bite_damage: float = 20.0
@export var contact_damage: float = 6.0
@export var contact_interval: float = 0.7
## How hard a hit throws you (m/s), plus half that upward.
@export var knockback: float = 9.0
## One explosion catching several segments only counts the worst-hit one
## fully, plus this share of the rest (so a rocket isn't x6).
@export_range(0.0, 1.0, 0.05) var multi_hit_share: float = 0.35

@export_group("Look")
@export var dirt_color: Color = Color(0.13, 0.09, 0.06)
@export var blood_color: Color = Color(0.55, 0.03, 0.03)
## Dirt kicked up above it as it tunnels (every trail_interval s), and the
## camera rumble while it's this close underneath you.
@export var trail_interval: float = 0.18
@export var rumble_range: float = 10.0
@export var rumble: float = 0.6
## Camera shake when it bursts out of or dives into a surface near you, and
## how big the eruption under you is.
@export var breach_shake: float = 4.0
@export var eruption_shake: float = 9.0
@export var shake_range: float = 20.0
## Breaching effects (sound, dirt, hole) at most this often -- the head
## grazing the floor line mustn't fire them every frame.
@export var breach_fx_cooldown: float = 0.6
@export var breach_sound: SoundEvent
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent
## Its roar as it erupts.
@export var roar_sound: SoundEvent
## The rumble swells by up to this many dB through the wind-up.
@export var windup_rumble_boost: float = 10.0
## The low rumble from under the floor while it's down there (empty = the
## generated placeholder, audio/sfx/worm_rumble.wav). Louder up close.
@export var rumble_stream: AudioStream
@export var rumble_volume_db: float = 2.0
## Peristalsis: swallowing bulges rolling down the body -- how much fatter a
## segment gets, how fast they travel (waves a second), and how many
## segments apart they are.
@export var bulge_amount: float = 0.28
@export var bulge_speed: float = 0.8
@export var bulge_spacing: float = 9.0

var target: Node3D
var _fx: WormFX
var _time := 0.0
## The brood burst at the top of a leap: seconds of it left (below 0 = not
## bursting), whether this leap gets one, and which segments still have a
## spider in them.
var _brood_left := -1.0
var _brood_this_leap := false
var _brood_segments: Array[int] = []
var _brood_pack: SpiderPack

## The attack cycle (The Leap).
enum Phase { WANDER, TUNNEL, WINDUP, RISE, AIR, DIVE }
var _phase := Phase.WANDER
var _phase_left := 0.0
## Where it'll erupt (on the floor) and the velocity it leaves the ground with.
var _leap_from := Vector3.ZERO
## Where it means to come down, and this leap's guess at your path (WormLeap).
var _leap_to := Vector3.ZERO
var _guess := Vector2.ONE
var _air_left := 0.0 # seconds since it left the ground (re-aim ramp)
var _leap_height := 0.0
var _breach_fx_left := 0.0

var _segments: Array[AnimatableBody3D] = []
var _visuals: Array[Node3D] = []
var _pos := PackedVector3Array()
var _radii := PackedFloat32Array()
var _below := PackedByteArray() # each segment under the floor plane last tick
var _vel := Vector3.ZERO
var _ground_y := 0.0
var _home := Vector3.ZERO
var _inside := true
var _wander_to := Vector3.ZERO
var _wander_left := 0.0
var _retarget := 0.0
var _trail_left := 0.0
var _hit_cooldowns := {} # player -> seconds
var _dead := false
var _death_step := 0.0
var _death_index := 0
## This physics frame's damage per segment (multi_hit_share).
var _hit_frame := -1
var _frame_hits := {}
var _frame_applied := 0.0

## The tape worm measured once: [lay basis, centre, size along x/y/z after
## laying (x = width, y = thickness, z = length)].
static var _slice_fit: Array = []

@onready var health: Health = $Health


func _ready() -> void:
	_home = global_position
	var floor_hit := _static_ray(global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 50.0)
	_ground_y = (floor_hit.position as Vector3).y if not floor_hit.is_empty() else global_position.y
	health.died.connect(_on_died)
	_fx = WormFX.new()
	_fx.size = 1.0
	_fx.rumble_stream = rumble_stream
	_fx.rumble_volume_db = rumble_volume_db
	add_child(_fx)
	var start := Vector3(_home.x, _ground_y - lurk_depth, _home.z)
	var back := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_vel = -back * max_speed * 0.5
	for i in segment_count:
		var t := float(i) / maxf(segment_count - 1, 1)
		var radius := lerpf(head_radius, tail_radius, t * t)
		_radii.append(radius)
		_pos.append(start + back * segment_spacing * i)
		_below.append(1)
		_build_segment(i, radius)
	_pick_wander()
	_place_segments()
	_ignore_players()
	if multiplayer.is_server():
		_spawn_escorts.call_deferred()


func _spawn_escorts() -> void:
	if escort_scene == null:
		return
	var world := get_tree().current_scene
	for i in escort_count:
		var escort := escort_scene.instantiate() as Node3D
		var around := Vector2.from_angle(TAU * i / maxf(escort_count, 1)) * 4.0
		escort.position = Vector3(_home.x + around.x, _ground_y, _home.z + around.y) # the level's root sits at the origin
		escort.set("guard_node", self)
		world.add_child(escort)


## The floor right under its head (what its escorts guard).
func ground_position() -> Vector3:
	return Vector3(_pos[0].x, _ground_y, _pos[0].z)


# ---- Building the body ------------------------------------------------------

func _build_segment(index: int, radius: float) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.top_level = true
	body.collision_layer = 1
	body.collision_mask = 0
	body.name = "Segment%d" % index
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.9
	shape.shape = sphere
	body.add_child(shape)
	# Its own Health so shots find it; everything it takes goes to the worm's.
	var segment_health := Health.new()
	segment_health.name = "Health"
	segment_health.max_health = 1000000.0
	body.add_child(segment_health)
	segment_health.damaged.connect(_on_segment_damaged.bind(index))
	add_child(body) # in the tree before measuring the maw (global transforms)
	var visual := Node3D.new()
	body.add_child(visual)
	_add_slices(visual, radius, index)
	if index == 0:
		_add_maw(visual, radius)
	_segments.append(body)
	_visuals.append(visual)


## The tape worm laid along the body (length on Z, flat side up) -- worked out
## from its own bounds, the same as the leech does it.
func _measure_slice() -> Array:
	if not _slice_fit.is_empty():
		return _slice_fit
	var probe := TAPE_WORM.instantiate() as Node3D
	add_child(probe)
	var bounds := _bounds_of(probe)
	probe.queue_free()
	var size := bounds.size
	var thin := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
	var long := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	if thin == long:
		long = (thin + 1) % 3
	var mid := 3 - thin - long
	var columns := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	columns[thin] = Vector3.UP
	columns[long] = Vector3.BACK
	columns[mid] = Vector3.RIGHT
	var lay := Basis(columns[0], columns[1], columns[2])
	if lay.determinant() < 0.0:
		columns[mid] = Vector3.LEFT
		lay = Basis(columns[0], columns[1], columns[2])
	_slice_fit = [lay, bounds.get_center(), Vector3(size[mid], size[thin], size[long])]
	return _slice_fit


## slices_per_segment tape worms fanned round the body's axis, each stretched
## to the segment's length (overlapping the next) and width.
func _add_slices(visual: Node3D, radius: float, index: int) -> void:
	var fit := _measure_slice()
	var lay: Basis = fit[0]
	var center: Vector3 = fit[1]
	var size: Vector3 = fit[2]
	var stretch := Basis.from_scale(Vector3(
			radius * 2.0 / maxf(size.x, 0.0001),
			radius * slice_thickness / maxf(size.y, 0.0001),
			segment_spacing * slice_overlap / maxf(size.z, 0.0001)))
	var twist := deg_to_rad(twist_per_segment) * index
	for k in slices_per_segment:
		var spin := Basis(Vector3.BACK, twist + PI * k / maxf(slices_per_segment, 1))
		var slice := TAPE_WORM.instantiate() as Node3D
		visual.add_child(slice)
		var basis := spin * stretch * lay
		slice.transform = Transform3D(basis, -(basis * center))
		_skin(slice, skin_material)
		# 60 slices in the shadow pass cost frames: only the head's maw
		# casts a shadow (the dirt and the eruption sell it anyway).
		for mesh in slice.find_children("*", "GeometryInstance3D", true, false):
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if slice is GeometryInstance3D:
			(slice as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The barnacle's maw on the head, its mouth facing forward (-Z).
func _add_maw(visual: Node3D, radius: float) -> void:
	var maw := MAW.instantiate() as Node3D
	visual.add_child(maw)
	var bounds := _bounds_of(maw)
	var across := maxf(maxf(bounds.size.x, bounds.size.z), 0.0001)
	var face := Basis(Vector3.RIGHT, -PI * 0.5) # its up (the mouth) to forward
	maw.transform = Transform3D(face.scaled(Vector3.ONE * radius * 2.0 * maw_size / across),
			Vector3(0.0, 0.0, -segment_spacing * 0.35))
	_skin(maw, maw_material)


func _skin(model: Node3D, material: Material) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node in meshes:
		if material:
			(node as MeshInstance3D).material_override = material


func _bounds_of(model: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var to_model := model.global_transform.affine_inverse()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node in meshes:
		var mesh := node as MeshInstance3D
		var box := to_model * mesh.global_transform * mesh.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	return bounds


# ---- Moving (host) ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		_die_step(delta)
		return
	if not multiplayer.is_server():
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		target = _nearest_player()
		_ignore_players()
	_breach_fx_left = maxf(_breach_fx_left - delta, 0.0)
	var head := _pos[0]
	var was_inside := _inside
	_inside = _in_ground(head)
	_update_phase(head, delta)
	if _phase == Phase.AIR:
		# No control up there: the arc is set -- except it hangs at the top
		# while the brood bursts out of it.
		var hanging := _brood_left > 0.0
		_vel.y -= air_gravity * (apex_gravity if hanging else 1.0) * delta
		_reaim(head, delta)
		_update_brood(delta)
	elif _phase == Phase.RISE:
		_vel = _vel.move_toward((_leap_from - head).normalized() * rise_speed, rise_speed * 4.0 * delta)
	elif _inside:
		# In the ground: full control, but only so much acceleration -- it
		# overshoots and comes round in arcs.
		_vel = _vel.move_toward((_goal(head, delta) - head).normalized() * max_speed, acceleration * delta)
	else:
		_vel.y -= air_gravity * delta # breached while wandering: falls back in
	if head.y < _ground_y - max_depth:
		_vel.y = maxf(_vel.y, 2.0)
	if _phase != Phase.AIR:
		_vel = _vel.limit_length(maxf(max_speed, rise_speed) * 1.2)
	var new_head := head + _vel * delta
	if was_inside != _inside:
		_on_crossed(head, new_head, _inside)
	_pos[0] = new_head
	# Follow the leader.
	for i in range(1, _pos.size()):
		var away := _pos[i] - _pos[i - 1]
		if away.length_squared() < 0.000001:
			away = -_vel.normalized() if _vel.length_squared() > 0.0001 else Vector3.BACK
		_pos[i] = _pos[i - 1] + away.normalized() * segment_spacing
	_crossings()
	_trail(delta)
	_contact(delta)
	_time += delta
	_place_segments()
	_fx.follow(_pos[0], _vel, _ground_y, lurk_depth + 2.0, _radii[0], _pos[0].y < _ground_y)
	_jaw_fx(delta)


func _place_segments() -> void:
	for i in _segments.size():
		var forward := (_pos[i - 1] - _pos[i]) if i > 0 else _vel
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var up := Vector3.UP if absf(forward.normalized().y) < 0.98 else Vector3.BACK
		_segments[i].global_transform = Transform3D(Basis.looking_at(forward.normalized(), up), _pos[i])
		# Peristalsis: a bulge rolling down the body (fatter across, not longer).
		var wave := sin(_time * bulge_speed * TAU - float(i) * TAU / maxf(bulge_spacing, 1.0))
		var swell := 1.0 + bulge_amount * pow(maxf(wave, 0.0), 6.0) + _brood_swell(i)
		_visuals[i].scale = Vector3(swell, swell, 1.0)


## The attack cycle (see The Leap): hunting, it tunnels to the spot under
## its prey, winds up deep under it, rises, erupts and arcs over, dives back
## in and comes round again. With no prey, it wanders.
func _update_phase(head: Vector3, delta: float) -> void:
	_phase_left -= delta
	var hunting := target != null and is_instance_valid(target)
	if not hunting and _phase != Phase.AIR and _phase != Phase.RISE:
		_phase = Phase.WANDER
	match _phase:
		Phase.WANDER:
			if hunting:
				_phase = Phase.TUNNEL
				_guess = WormLeap.roll_guess()
		Phase.TUNNEL:
			_plan_leap()
			var under := Vector3(_leap_from.x, head.y, _leap_from.z)
			if head.distance_to(under) < 2.5 and head.y < _ground_y - 0.5:
				_phase = Phase.WINDUP
				_phase_left = windup_time
		Phase.WINDUP:
			_plan_leap()
			_telegraph(delta)
			if _phase_left <= 0.0:
				_phase = Phase.RISE
		Phase.RISE:
			_plan_leap() # keeps tracking them on the way up
			if not _inside:
				_erupt(head)
			elif head.y > _ground_y + 1.0:
				_erupt(head) # came up inside something (a platform): go anyway
		Phase.AIR:
			if _inside and _vel.y < 0.0:
				_phase = Phase.DIVE
				_phase_left = dive_time
				_shockwave(head)
		Phase.DIVE:
			if _phase_left <= 0.0:
				_phase = Phase.TUNNEL
				_guess = WormLeap.roll_guess()
	_fx.rumble_boost(windup_rumble_boost * (1.0 - clampf(_phase_left / maxf(windup_time, 0.01), 0.0, 1.0)) if _phase == Phase.WINDUP else 0.0)


## Where to come up: leap_distance short of where it'll come down (its
## guess at where you'll be by then -- WormLeap), along the way it's coming.
func _plan_leap() -> void:
	if not is_instance_valid(target):
		return
	var head := _pos[0]
	var until_out := windup_time + 0.4
	if _phase == Phase.WINDUP:
		until_out = _phase_left + 0.3
	elif _phase == Phase.RISE:
		until_out = 0.2
	var flight := WormLeap.air_time(leap_height, air_gravity, 1.0)
	_leap_to = WormLeap.landing(head, target, until_out + flight, _guess)
	var approach := Vector3(_leap_to.x - head.x, 0.0, _leap_to.z - head.z)
	if approach.length_squared() < 0.25:
		approach = Vector3(_vel.x, 0.0, _vel.z)
	approach = approach.normalized() if approach.length_squared() > 0.0001 else Vector3.FORWARD
	_leap_from = Vector3(_leap_to.x, _ground_y, _leap_to.z) - approach * leap_distance


## Breaking the surface: up at sqrt(2 g h), across at whatever brings it
## down on its guess at where you'll be when it lands -- and the ground
## explodes: a column of dirt and rubble, a roar, the camera hit.
func _erupt(head: Vector3) -> void:
	_phase = Phase.AIR
	var height := hop_height if randf() < hop_chance else leap_height
	_brood_this_leap = height >= leap_height and randf() < brood_chance and brood_count > 0
	_brood_left = -1.0
	var rise := sqrt(2.0 * air_gravity * maxf(height, 0.5))
	var across := Vector3.ZERO
	if is_instance_valid(target):
		var flight := WormLeap.air_time(height, air_gravity, 1.0)
		_leap_to = WormLeap.landing(head, target, flight, _guess)
		across = Vector3(_leap_to.x - head.x, 0.0, _leap_to.z - head.z) / flight
	_vel = Vector3(across.x, rise, across.z)
	_air_left = 0.0
	var surface := Vector3(head.x, _ground_y, head.z)
	_shake_near(head, eruption_shake, shake_range)
	WormFX.punch(get_tree(), head, 9.0, shake_range)
	_fx.fade_cracks()
	_fx.rumble_boost(0.0)
	_fx.eruption(surface, _radii[0])
	SoundPlayer.play_3d(roar_sound, surface, get_tree().current_scene)


## The extras: tremors (ceiling dust, props jittering) while it's under the
## floor near the surface, drool from its jaws while it's out, and dirt
## shedding off its body while it flies.
func _jaw_fx(delta: float) -> void:
	var head := _pos[0]
	var depth := _ground_y - head.y
	if depth > 0.0 and depth < lurk_depth + 3.0:
		_fx.tremor(Vector3(head.x, _ground_y, head.z), delta)
	elif depth <= 0.0:
		var forward := _vel.normalized() if _vel.length_squared() > 0.01 else Vector3.FORWARD
		_fx.drool(head + forward * _radii[0], delta)
		if _phase == Phase.AIR:
			_fx.shed(_pos, _ground_y, delta)


## Smooth re-aim in the air (air_steer): the same guess at your path,
## brought up to date, and the sideways drift eased toward it.
func _reaim(head: Vector3, delta: float) -> void:
	if air_steer <= 0.0 or not is_instance_valid(target):
		return
	_air_left += delta
	var ramp := clampf(_air_left / maxf(steer_ramp, 0.01), 0.0, 1.0)
	ramp = ramp * ramp * (3.0 - 2.0 * ramp)
	var want := WormLeap.steer_toward(head, _vel, target, _guess, _ground_y, air_gravity)
	var flat := Vector3(_vel.x, 0.0, _vel.z).move_toward(want, air_steer * ramp * delta)
	_vel.x = flat.x
	_vel.z = flat.z


## The brood burst: at the top of the arc (rising stops) it starts; the
## swelling rolls from just behind the head to the tail over apex_hang
## seconds and each brood segment bursts as the swelling reaches it.
func _update_brood(delta: float) -> void:
	if not _brood_this_leap:
		return
	if _brood_left < 0.0:
		if _vel.y > 0.0:
			return # still rising
		_brood_left = apex_hang
		_brood_segments.clear()
		# Spread down the body from just behind the head; with more spiders
		# than segments, several burst from each.
		for k in brood_count:
			_brood_segments.append(2 + int(float(k) / maxf(brood_count, 1) * (_segments.size() - 2)))
		_shake_near(_pos[0], breach_shake, shake_range)
		return
	_brood_left -= delta
	var front := _brood_front()
	while not _brood_segments.is_empty() and float(_brood_segments[0]) <= front:
		_burst_spider(_brood_segments.pop_front())
	if _brood_left <= 0.0:
		for index in _brood_segments:
			_burst_spider(index)
		_brood_segments.clear()
		_brood_this_leap = false
		_brood_left = -1.0


## Where along the body (segment index) the brood swelling is now.
func _brood_front() -> float:
	var t := 1.0 - clampf(_brood_left / maxf(apex_hang, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, float(_segments.size()), eased)


## How much fatter segment i is from the brood swelling rolling past.
func _brood_swell(i: int) -> float:
	if _brood_left <= 0.0:
		return 0.0
	var off := (float(i) - _brood_front()) / 1.5
	return brood_bulge * exp(-off * off)


## One spider tears out of segment `index`: flung out sideways (a random way
## round the body) and up, in a burst of blood.
func _burst_spider(index: int) -> void:
	if index < 0 or index >= _pos.size():
		return
	var at := _pos[index]
	var along := (_pos[index - 1] - at).normalized() if index > 0 else _vel.normalized()
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var out := side.normalized().rotated(along, randf_range(-PI, PI) * 0.6)
	if out.y < 0.0:
		out = -out
	out = (out + Vector3.UP * 0.4).normalized()
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, at + out * _radii[index], out, blood_color, 2.0)
	SoundPlayer.play_3d(breach_sound, at, world, 0.6)
	if not is_instance_valid(_brood_pack):
		_brood_pack = SpiderPack.new()
		_brood_pack.start_count = 0
		_brood_pack.free_when_empty = false # more come with every leap
		_brood_pack.position = Vector3(at.x, _ground_y, at.z) # the level's root sits at the origin
		world.add_child(_brood_pack)
	_brood_pack.spawn_spiders(1, at + out * (_radii[index] + 0.2), out * brood_speed)


## Landing: a ring of dust tears outward and throws back everything near --
## players, enemies, creatures, loose bodies -- except its own escorts.
func _shockwave(at: Vector3) -> void:
	var center := Vector3(at.x, _ground_y, at.z)
	_fx.shockwave(center, shockwave_radius)
	_shake_near(center, eruption_shake, shake_range)
	WormFX.punch(get_tree(), center, 5.0, shake_range)
	SoundPlayer.play_3d(breach_sound, center, get_tree().current_scene)
	if not multiplayer.is_server():
		return
	var sphere := SphereShape3D.new()
	sphere.radius = shockwave_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * 1.0)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for segment in _segments:
		exclude.append(segment.get_rid())
	query.exclude = exclude
	var seen := {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var body := result.collider as Node3D
		if body == null or seen.has(body) or (body is StaticBody3D and not body is AnimatableBody3D):
			continue
		seen[body] = true
		var owner_node := body.get_parent()
		if owner_node is Deepmaw and (owner_node as Deepmaw).guard_node == self:
			continue # its own escort
		if body is Spider and is_instance_valid(_brood_pack) and (body as Spider).pack == _brood_pack:
			continue # its own brood
		var away := body.global_position - center
		away.y = 0.0
		var distance := away.length()
		var falloff := clampf(1.0 - distance / shockwave_radius, 0.0, 1.0)
		if falloff <= 0.0:
			continue
		var out := away / distance if distance > 0.01 else Vector3.FORWARD
		var push := out * shockwave_force * falloff + Vector3.UP * shockwave_lift * falloff
		var body_health := body.get_node_or_null("Health") as Health
		if body_health and shockwave_damage > 0.0:
			body_health.take_damage(shockwave_damage * falloff, Health.NO_ATTACKER)
		if body.has_method("shove"):
			body.call("shove", push)
		elif body is RigidBody3D:
			(body as RigidBody3D).apply_central_impulse(push * (body as RigidBody3D).mass)
			if body.has_method("stun"):
				body.call("stun")
		elif body is PhysicalBone3D:
			(body as PhysicalBone3D).apply_central_impulse(push * (body as PhysicalBone3D).mass)


## Winding up under its prey: the ground shakes harder and harder and cracks
## open where it's about to come out.
func _telegraph(delta: float) -> void:
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = 0.15
	var t := 1.0 - clampf(_phase_left / maxf(windup_time, 0.01), 0.0, 1.0)
	var spot := Vector3(_leap_from.x, _ground_y + 0.05, _leap_from.z)
	var jitter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * head_radius
	BloodFX.spawn_impact(get_tree().current_scene, spot + jitter, Vector3.UP, dirt_color, 0.75 + t)
	_fx.show_cracks(Vector3(_leap_from.x, _ground_y, _leap_from.z), 0.25 + 0.75 * t)
	_shake_near(spot, rumble * (1.0 + t * 2.0), rumble_range)


## Where the head is going while it has control: hunting, the tunnel under
## its prey (or, winding up, straight down under the eruption spot; diving,
## on down and round); with nobody about, wandering.
func _goal(head: Vector3, delta: float) -> Vector3:
	match _phase:
		Phase.TUNNEL:
			return Vector3(_leap_from.x, _ground_y - lurk_depth, _leap_from.z)
		Phase.WINDUP:
			return Vector3(_leap_from.x, _ground_y - dive_depth, _leap_from.z)
		Phase.DIVE:
			var on := Vector3(_vel.x, 0.0, _vel.z).normalized() * 6.0
			return Vector3(head.x + on.x, _ground_y - lurk_depth - 1.0, head.z + on.z)
	_wander_left -= delta
	if _wander_left <= 0.0 or head.distance_to(_wander_to) < 2.0:
		_pick_wander()
	return _wander_to


func _pick_wander() -> void:
	_wander_left = randf_range(4.0, 9.0)
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(wander_radius * 0.3, wander_radius)
	var height := _ground_y + 3.0 if randf() < wander_breach_chance else _ground_y - lurk_depth
	_wander_to = Vector3(_home.x + offset.x, height, _home.z + offset.y)


## Players walk through it (contact damage does the hurting) -- including
## ones who join after it spawned.
func _ignore_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PhysicsBody3D
		if player == null:
			continue
		for segment in _segments:
			segment.add_collision_exception_with(player)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := notice_range
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var distance := player.global_position.distance_to(_pos[0])
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## In the ground: under the floor it lives in, or inside level geometry (a
## wall, a pillar, a platform).
func _in_ground(point: Vector3) -> bool:
	if point.y < _ground_y - 0.05:
		return true
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	for result in get_world_3d().direct_space_state.intersect_point(query, 8):
		var collider = result.collider
		if collider is StaticBody3D and not collider is AnimatableBody3D:
			return true
	return false


# ---- Effects ----------------------------------------------------------------

## Bursting out of (or diving into) a surface: a spray of dirt and a dark
## hole where it went through, a crunch, and the camera shakes nearby.
## Crossed a surface: the full effects, at most every breach_fx_cooldown --
## the head grazing the floor line would otherwise fire them every frame
## (that was the flood of digging noises).
func _on_crossed(from: Vector3, to: Vector3, entering: bool) -> void:
	if _breach_fx_left > 0.0:
		return
	_breach_fx_left = breach_fx_cooldown
	_breach_fx(from, to, entering)


func _breach_fx(from: Vector3, to: Vector3, entering: bool) -> void:
	var world := get_tree().current_scene
	var hit := _static_ray(from, to + (to - from).normalized() * 0.5) if entering \
			else _static_ray(to, from - (to - from).normalized() * 0.5)
	var at := Vector3(to.x, _ground_y, to.z)
	var normal := Vector3.UP
	if not hit.is_empty():
		at = hit.position
		normal = hit.normal
	var size := _radii[0]
	_fx.burst(at, normal)
	BloodFX.spawn_splatter(world, at + normal * 0.01, normal, size * 3.0, dirt_color)
	BloodFX.spawn_impact(world, at, normal, dirt_color.lightened(0.15), 3.0)
	BloodFX.spawn_impact(world, at, (normal + Vector3(randf() - 0.5, 0.0, randf() - 0.5)).normalized(), dirt_color, 2.0)
	SoundPlayer.play_3d(breach_sound, at, world)
	_shake_near(at, breach_shake, shake_range)


func _shake_near(at: Vector3, strength: float, within: float) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < within and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).shake(strength * (1.0 - distance / within))


## Body segments crossing the floor (out or back in): a smaller puff of dirt
## where each goes through, so the whole length visibly pours out and back.
func _crossings() -> void:
	var world := get_tree().current_scene
	for i in range(1, _pos.size()):
		var below := 1 if _pos[i].y < _ground_y else 0
		if below != _below[i] and i % 4 == 0:
			BloodFX.spawn_impact(world, Vector3(_pos[i].x, _ground_y + 0.05, _pos[i].z), Vector3.UP, dirt_color, 1.0)
		_below[i] = below


## Tunnelling under the floor: dirt kicked up above its head, and the ground
## rumbling under anyone it's passing beneath.
func _trail(delta: float) -> void:
	var head := _pos[0]
	if _phase != Phase.TUNNEL or head.y >= _ground_y or head.y < _ground_y - lurk_depth - 1.5:
		return
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = trail_interval
	var surface := Vector3(head.x, _ground_y + 0.05, head.z)
	BloodFX.spawn_impact(get_tree().current_scene, surface, Vector3.UP, dirt_color, 0.75)
	_shake_near(surface, rumble, rumble_range)


# ---- Hurting and being hurt -------------------------------------------------

## Any part of it touching a player hurts (the head bites), each player at
## most every contact_interval, and throws them.
func _contact(delta: float) -> void:
	for player in _hit_cooldowns.keys():
		_hit_cooldowns[player] = float(_hit_cooldowns[player]) - delta
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player) or float(_hit_cooldowns.get(player, 0.0)) > 0.0:
			continue
		var middle := Factions.aim_point(player)
		var touching := -1
		for i in _pos.size():
			if _pos[i].y < _ground_y - _radii[i]:
				continue # underground
			if _pos[i].distance_to(middle) < _radii[i] + 0.7:
				touching = i
				break
		if touching < 0:
			continue
		_hit_cooldowns[player] = contact_interval
		var player_health := player.get_node_or_null("Health") as Health
		if player_health:
			player_health.take_damage(bite_damage if touching == 0 else contact_damage, Health.NO_ATTACKER)
		var away := (middle - _pos[touching])
		away.y = 0.0
		var throw := (away.normalized() if away.length_squared() > 0.001 else _vel.normalized()) * knockback + Vector3.UP * knockback * 0.5
		if player.has_method("shove"):
			player.call("shove", throw)
		if touching == 0:
			SoundPlayer.play_3d(bite_sound, _pos[0], get_tree().current_scene)
			_fx.bite_spray(_pos[0], (middle - _pos[0]).normalized())


## A segment was hit: it bleeds and flashes, and the worm takes the damage --
## all of one hit, but only multi_hit_share of the rest when one blast catches
## several segments in the same physics frame.
func _on_segment_damaged(amount: float, attacker_id: int, index: int) -> void:
	if _dead or index >= _segments.size():
		return
	var segment_health := _segments[index].get_node("Health") as Health
	segment_health.current_health = segment_health.max_health
	HitFlash.flash(_visuals[index])
	BloodFX.spawn_impact(get_tree().current_scene, _pos[index], Vector3.UP, blood_color, 1.0)
	var frame := Engine.get_physics_frames()
	if frame != _hit_frame:
		_hit_frame = frame
		_frame_hits.clear()
		_frame_applied = 0.0
	_frame_hits[index] = float(_frame_hits.get(index, 0.0)) + amount
	var most := 0.0
	var total := 0.0
	for value in _frame_hits.values():
		most = maxf(most, value)
		total += value
	var owed := most + (total - most) * multi_hit_share
	if owed > _frame_applied:
		health.take_damage(owed - _frame_applied, attacker_id)
		_frame_applied = owed


## Dead: it comes apart from the head down, a burst of blood per segment.
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	_dead = true
	_fx.silence()
	_death_step = 0.0
	_death_index = 0
	SoundPlayer.play_3d(death_sound, _pos[0], get_tree().current_scene)


func _die_step(delta: float) -> void:
	_death_step -= delta
	if _death_step > 0.0:
		return
	_death_step = 0.06
	if _death_index >= _segments.size():
		queue_free()
		return
	var at := _pos[_death_index]
	var world := get_tree().current_scene
	if at.y > _ground_y - _radii[_death_index]:
		BloodFX.spawn_impact(world, at, Vector3.UP, blood_color, 2.0 * _radii[_death_index] / maxf(head_radius, 0.01) + 0.5)
		var floor_hit := _static_ray(at, at + Vector3.DOWN * 6.0)
		if not floor_hit.is_empty():
			BloodFX.spawn_splatter(world, floor_hit.position, floor_hit.normal, _radii[_death_index] * 2.5, blood_color)
	_segments[_death_index].visible = false
	_segments[_death_index].collision_layer = 0
	_death_index += 1


## Level geometry only.
func _static_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for segment in _segments:
		exclude.append(segment.get_rid())
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D):
			return hit
		exclude.append(hit.rid)
	return {}
