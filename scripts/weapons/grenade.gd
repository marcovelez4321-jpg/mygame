class_name Grenade
extends RigidBody3D

## A thrown frag grenade: a real physics object that arcs, bounces and rolls,
## then blows up (Explosion) when its fuse runs out -- Half-Life 2's frag.
## While the fuse burns it flashes white (like an enemy taking a hit,
## HitFlash) and throbs, flashing faster and swelling bigger the closer it is
## to going off, so you can read the timer from across the room.
##
## Rule 1 (co-op): the throw is pure data (where, which way, how fast), so
## the host throws the same grenade and alone decides the explosion. The
## flashing and swelling are just the look.

## Flashes per second right after the throw, and right before the bang.
const BLINK_RATE_START := 2.0
const BLINK_RATE_END := 12.0
## How much of each blink is lit (0..1).
const BLINK_LIT := 0.4
## How much bigger it swells by the end (0.35 = 35% bigger), and how much it
## throbs with each blink on top of that.
const SWELL := 0.35
const THROB := 0.15
## Ball shape it bounces on, in meters.
const RADIUS := 0.06
## Below this speed (m/s) a bump makes no sound.
const BOUNCE_SOUND_SPEED := 2.0

var _weapon: WeaponData
var _weapons: WeaponController
var _attacker_id := Health.NO_ATTACKER
var _attacker_body: Node3D
var _fuse_left := 3.0
var _blink_phase := 0.0
var _lit := false
var _visual: Node3D
var _meshes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D


## Throws a grenade from `at` with `velocity`. `weapons` is the thrower's
## WeaponController (for hit markers).
static func throw(world: Node, at: Vector3, velocity: Vector3, weapon: WeaponData,
		attacker_id: int, thrower: PhysicsBody3D, weapons: WeaponController) -> Grenade:
	var grenade := Grenade.new()
	grenade._weapon = weapon
	grenade._weapons = weapons
	grenade._attacker_id = attacker_id
	grenade._attacker_body = thrower
	grenade._fuse_left = weapon.fuse_time
	world.add_child(grenade)
	grenade.global_position = at
	grenade.linear_velocity = velocity
	grenade.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))
	if thrower:
		grenade.add_collision_exception_with(thrower) # don't bounce off your own hand
	return grenade


func _ready() -> void:
	mass = 0.4
	# Small and fast: check the whole path each step so it can't skip
	# through a thin wall.
	continuous_cd = true
	# Bounces off the world, players, enemies and props, but nothing else
	# bumps into it -- you can't trip over your own grenade.
	collision_layer = 0
	collision_mask = 1
	angular_damp = 1.5
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.35
	bounce.friction = 0.7
	physics_material_override = bounce
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	if _weapon.viewmodel_scene:
		_visual.add_child(_weapon.viewmodel_scene.instantiate())
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _physics_process(delta: float) -> void:
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()


## Flash and throb: blinks speed up from BLINK_RATE_START to BLINK_RATE_END
## (squared, so most of the speed-up is near the end), each blink a throb,
## and the whole grenade swells as the fuse runs out.
func _process(delta: float) -> void:
	var progress := clampf(1.0 - _fuse_left / maxf(_weapon.fuse_time, 0.01), 0.0, 1.0)
	_blink_phase += delta * lerpf(BLINK_RATE_START, BLINK_RATE_END, progress * progress)
	var lit := fmod(_blink_phase, 1.0) < BLINK_LIT
	if lit != _lit:
		_lit = lit
		for mesh in _meshes:
			mesh.material_overlay = _flash_material if lit else null
		if lit:
			SoundPlayer.play_3d(_weapon.fuse_tick_sound, global_position, get_parent())
	var pulse := 0.5 + 0.5 * cos(_blink_phase * TAU) # peaks as each blink lights
	_visual.scale = Vector3.ONE * (1.0 + SWELL * progress * progress + THROB * progress * pulse)


func _on_body_entered(_body: Node) -> void:
	if linear_velocity.length() >= BOUNCE_SOUND_SPEED:
		SoundPlayer.play_3d(_weapon.bounce_sound, global_position, get_parent())


func _explode() -> void:
	set_physics_process(false)
	var settings := Explosion.Settings.new()
	settings.damage = _weapon.explosion_damage
	settings.radius = _weapon.explosion_radius
	settings.knockback = _weapon.explosion_knockback
	settings.player_damage = _weapon.explosion_player_damage
	settings.attacker_id = _attacker_id
	settings.attacker_body = _attacker_body if is_instance_valid(_attacker_body) else null
	var hits := Explosion.explode(self, global_position + Vector3.UP * 0.1, settings)
	if is_instance_valid(_weapons):
		_weapons.report_explosion_hits(hits)
	queue_free()
