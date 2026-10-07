class_name Barnacle
extends StaticBody3D

## A fleshy roach-birthing growth stuck to a floor or wall (the PSX Creatures
## kit's barnacle model), grown in little fungal clumps by BarnacleCluster.
## Every spit_interval_min..max seconds it throbs and swells -- three pulses,
## each bigger than the last -- then spits roaches out of its mouth (a random
## normal or spitter each, RoachCarry.hatch()). Bigger barnacles spit more:
## the smallest (size_min) 1 roach, the biggest (size_max) 3, in between 2.
## Shoot it dead and it bursts in a red blood explosion with a splat, and
## everything it had in it -- a full spit's worth -- spills out at once.
##
## Its own "up" is the way its mouth faces (out of the floor or wall it's on).
## Nothing hunts it (it's in no Factions group); it's yours to clear.
## Rule 1 (co-op): the host runs the timers and spawns the roaches.

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

@export_group("Spitting")
## Seconds between spits, rolled fresh each time.
@export var spit_interval_min: float = 5.0
@export var spit_interval_max: float = 10.0
## How long the throb-and-swell before a spit takes, and how much bigger it
## gets at the last (biggest) pulse (0.3 = 30% taller).
@export var swell_time: float = 1.2
@export var swell_amount: float = 0.3
## Roaches already alive at which it holds off spitting (keeps a level full
## of barnacles from flooding the game -- and the frame rate).
@export var roach_cap: int = 50

@export_group("Look")
@export var blood_color: Color = Color(0.6, 0.03, 0.03)
## Size of the blood explosion and the splat left on the surface when it dies.
@export var death_gore: float = 3.0
@export var splat_size: float = 1.6
## Laid over every mesh of the model (the kit's texture).
@export var skin_material: Material
@export var spit_sound: SoundEvent
@export var death_sound: SoundEvent

## Roaches it spits each time (and spills when it dies): 1 to 3 by size.
var roaches_per_spit := 1
var _spit_left := 0.0
var _swelling := false
var _dead := false

@onready var health: Health = $Health
@onready var _model: Node3D = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mouth: Marker3D = $Mouth


func _ready() -> void:
	add_to_group("barnacles")
	_model.scale = Vector3.ONE * size * model_scale
	_mouth.position *= size
	# Its own copy of the shape, sized to it (scaling a physics body itself
	# is unreliable; sizing its shape isn't).
	var cylinder := (_shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
	cylinder.radius *= size
	cylinder.height *= size
	_shape.shape = cylinder
	_shape.position *= size
	var t := clampf(inverse_lerp(size_min, size_max, size), 0.0, 1.0)
	roaches_per_spit = 1 + roundi(t * 2.0)
	health.max_health = health_per_size * size
	health.current_health = health.max_health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if skin_material:
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = skin_material
	BloodFX.warm_splat_texture(blood_color)
	_spit_left = randf_range(spit_interval_min, spit_interval_max)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead or _swelling:
		return
	_spit_left -= delta
	if _spit_left <= 0.0:
		_swell()


## Throbs three times, each pulse bigger than the last (taller than it is
## wide, like something pushing up inside it), then spits.
func _swell() -> void:
	_swelling = true
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


## Pops `count` roaches out of its mouth, fanned out around the way it faces --
## fewer if the level is already at roach_cap.
func _release(count: int) -> void:
	var world := get_tree().current_scene
	var up := global_basis.y.normalized()
	var alive := get_tree().get_nodes_in_group(Factions.GROUPS[Factions.Side.ROACH]).size()
	for i in mini(count, maxi(roach_cap - alive, 0)):
		var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.45
		var direction := (up + spread).normalized()
		RoachCarry.hatch(world, _mouth.global_position + direction * 0.2, direction)


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
