class_name Barnacle
extends StaticBody3D

## A fleshy roach-birthing growth stuck to a floor or wall (the PSX Creatures
## kit's barnacle model), grown in little fungal clumps by BarnacleCluster.
## Every spit_interval_min..max (10-20) seconds it throbs and swells -- three pulses,
## each bigger than the last -- then spits roaches out of its mouth (a random
## normal or spitter each, RoachCarry.hatch()). Bigger barnacles spit more:
## the smallest (size_min) 1 roach, the biggest (size_max) 3, in between 2.
## Shoot it dead and it bursts in a red blood explosion with a splat, and
## everything it had in it -- a full spit's worth -- spills out at once.
##
## Its own "up" is the way its mouth faces (out of the floor or wall it's on).
## Nothing hunts it (it's in no Factions group); it's yours to clear.
## A nest is a roach nest or a spider nest (brood, rolled per clump by
## BarnacleCluster): a spider nest is paler and spits spiders instead, into
## its clump's SpiderPack so they swarm together.
## Rule 1 (co-op): the host runs the timers and spawns the roaches.

## It's started to throb toward a spit (its clump's look-only barnacles
## swell along with it: BarnacleCluster).
signal swelling

enum Brood { ROACHES, SPIDERS }

## What it spits out.
@export var brood: Brood = Brood.ROACHES
## A spider nest's skin is tinted this colour, so you can tell them apart.
@export var spider_nest_tint: Color = Color(0.72, 0.76, 0.9)
## How hard spiders are flung out of its mouth, m/s.
@export var spider_launch_speed: float = 3.5

@export_group("Size")
## How big this one is (1 = the model's own size). BarnacleCluster rolls it.
@export var size: float = 1.0
## The size range spit counts are spread over: size_min spits 1, size_max 3.
@export var size_min: float = 0.6
@export var size_max: float = 1.6
## If the imported model comes in the wrong size (the FBX is authored in
## centimetres), fix its look here -- the hitbox and mouth go by `size` only.
## A size-1 barnacle should be about 0.7 m across and 0.56 m tall.
@export var model_scale: float = 1.0
## Health for a size-1 barnacle; scales with size.
@export var health_per_size: float = 60.0
## Every barnacle this much bigger than its rolled size (look, hitbox and
## health; not how many it spits).
@export var scale_boost: float = 1.4

@export_group("Spitting")
## Seconds between spits, rolled fresh each time.
@export var spit_interval_min: float = 10.0
@export var spit_interval_max: float = 20.0
## How long the throb-and-swell before a spit takes, and how much bigger it
## gets at the last (biggest) pulse (0.3 = 30% taller).
@export var swell_time: float = 1.2
@export var swell_amount: float = 0.3
## It only breeds with a player within wake_range (HL2's spawners: nothing
## spawns for nobody to see), and keeps at most max_brood of its own alive at
## once -- so a big nest is a threat, not an endless flood (and the open
## world's many nests don't fill the game's creature caps from miles off).
@export var wake_range: float = 40.0
@export var max_brood: int = 4
## Too close (the user's: 4 m): it throbs and spits at once, whatever its
## timer says -- then not again for burst_cooldown. The throb is its warning.
## (Its spitting over time, below, goes on as before.)
@export var burst_range: float = 4.0
@export var burst_cooldown: float = 6.0

@export_group("Look")
@export var blood_color: Color = Color(0.6, 0.03, 0.03)
## Size of the blood explosion and the splat left on the surface when it dies.
@export var death_gore: float = 3.0
@export var splat_size: float = 1.6
## Laid over every mesh of the model (the kit's texture).
@export var skin_material: Material
@export var spit_sound: SoundEvent
@export var death_sound: SoundEvent

## Roaches (or spiders) it spits each time (and spills when it dies): 1 to 3
## by size.
var roaches_per_spit := 1
## A spider nest's pack (set by BarnacleCluster; made here if not).
var spider_pack: SpiderPack
## What it's spat that's still about (weak refs).
var _brood: Array[WeakRef] = []
var _wake_check := 0.0
var _awake := false
var _spit_left := 0.0
var _swelling := false
var _close := false
var _burst_left := 0.0
var _dead := false

@onready var health: Health = $Health
@onready var _model: Node3D = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mouth: Marker3D = $Mouth


func _ready() -> void:
	add_to_group("barnacles")
	var spit_share := clampf(inverse_lerp(size_min, size_max, size), 0.0, 1.0)
	size *= scale_boost
	_model.scale = Vector3.ONE * size * model_scale
	_mouth.position *= size
	# Its own copy of the shape, sized to it (scaling a physics body itself
	# is unreliable; sizing its shape isn't).
	var cylinder := (_shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
	cylinder.radius *= size
	cylinder.height *= size
	_shape.shape = cylinder
	_shape.position *= size
	roaches_per_spit = 1 + roundi(spit_share * 2.0)
	health.max_health = health_per_size * size
	health.current_health = health.max_health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if skin_material:
		var skin := skin_material
		if brood == Brood.SPIDERS and skin is StandardMaterial3D:
			skin = skin.duplicate() as StandardMaterial3D
			(skin as StandardMaterial3D).albedo_color = spider_nest_tint
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = skin
	_spit_left = randf_range(spit_interval_min, spit_interval_max)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead or _swelling:
		return
	_wake_check -= delta
	_burst_left -= delta
	if _wake_check <= 0.0:
		# (Spread out over the frames; checked faster while someone's near.)
		_wake_check = (0.2 if _awake else 0.5) + randf() * 0.1
		var nearest := _nearest_player()
		_awake = nearest < wake_range
		_close = nearest < burst_range
	if not _awake:
		return
	# Someone right up against it: it bursts (more than its usual brood allowed).
	if _close and _burst_left <= 0.0 and _alive_brood() < max_brood * 2:
		_burst_left = burst_cooldown
		_swell()
		return
	_spit_left -= delta
	if _spit_left <= 0.0:
		if _alive_brood() >= max_brood:
			_spit_left = randf_range(spit_interval_min, spit_interval_max) * 0.5 # full: try again later
			return
		_swell()


## How far the nearest player is.
func _nearest_player() -> float:
	var nearest := INF
	for node in get_tree().get_nodes_in_group("player"):
		nearest = minf(nearest, (node as Node3D).global_position.distance_to(global_position))
	return nearest


## Its brood still alive (and forgets the rest).
func _alive_brood() -> int:
	var alive: Array[WeakRef] = []
	for ref in _brood:
		var creature := ref.get_ref() as Node3D
		if creature != null and Factions.is_alive_target(creature):
			alive.append(ref)
	_brood = alive
	return _brood.size()


## Throbs three times, each pulse bigger than the last (taller than it is
## wide, like something pushing up inside it), then spits.
func _swell() -> void:
	_swelling = true
	swelling.emit()
	var rest := Vector3.ONE * size * model_scale
	var pulse := swell_time / 6.0
	var tween := create_tween()
	for i in 3:
		var amount := swell_amount * (i + 1) / 3.0
		tween.tween_property(_model, "scale", rest * Vector3(1.0 + amount * 0.6, 1.0 + amount, 1.0 + amount * 0.6), pulse) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(_model, "scale", rest, pulse).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_spit)


## Out they come: roaches_per_spit roaches, popped out of its mouth.
func _spit() -> void:
	_swelling = false
	_spit_left = randf_range(spit_interval_min, spit_interval_max)
	if _dead:
		return
	var world := get_tree().current_scene
	var up := global_basis.y.normalized()
	BloodFX.spawn_impact(world, _mouth.global_position, up, blood_color, 1.0 * size)
	SoundPlayer.play_3d(spit_sound, _mouth.global_position, world)
	_release(roaches_per_spit)
	# A quick squash as they leave it.
	var tween := create_tween()
	var rest := Vector3.ONE * size * model_scale
	tween.tween_property(_model, "scale", rest * Vector3(1.15, 0.8, 1.15), 0.08)
	tween.tween_property(_model, "scale", rest, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Pops `count` roaches (or spiders) out of its mouth, fanned out around the
## way it faces (at the game's cap the oldest die to make room: Population).
func _release(count: int) -> void:
	var world := get_tree().current_scene
	var up := global_basis.y.normalized()
	if brood == Brood.SPIDERS:
		if not is_instance_valid(spider_pack):
			spider_pack = SpiderPack.new()
			spider_pack.start_count = 0
			spider_pack.position = global_position # the level's root sits at the origin
			world.add_child(spider_pack)
		for spider in spider_pack.spawn_spiders(count, _mouth.global_position + up * 0.2, up * spider_launch_speed):
			_brood.append(weakref(spider))
		return
	for i in count:
		var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.45
		var direction := (up + spread).normalized()
		_brood.append(weakref(RoachCarry.hatch(world, _mouth.global_position + direction * 0.2, direction)))


func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if not _dead:
		HitFlash.flash(self)


## Shot dead: a red blood explosion and a splat, a splatter on whatever it
## grew on, and everything it had in it spills out at once.
func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	if _dead:
		return
	_dead = true
	var world := get_tree().current_scene
	var up := global_basis.y.normalized()
	var center := global_position + up * 0.3 * size
	BloodFX.spawn_impact(world, center, up, blood_color, death_gore * size)
	for i in 3:
		var out := (up + Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.0), randf_range(-1.0, 1.0))).normalized()
		BloodFX.spawn_impact(world, center, out, blood_color, death_gore * 0.6 * size)
	BloodFX.spawn_splatter(world, global_position, up, splat_size * size, blood_color)
	SoundPlayer.play_3d(death_sound, center, world)
	if multiplayer.is_server():
		_release(roaches_per_spit)
	queue_free()
