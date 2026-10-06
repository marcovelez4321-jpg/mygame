class_name Rocket
extends Node3D

## An RPG rocket in flight, flying like a real RPG-7 but shortened for a
## game: a small charge pushes it out of the tube fairly slowly (a puff of
## smoke, a slight dip), then a moment later the rocket motor lights -- a
## flame at the tail, a thick smoke trail, and it accelerates hard to full
## speed. "Pop... WHOOSH." It spins slowly as it flies, like the real thing.
## On impact it blows up (Explosion).
##
## Where it really is vs. where it's drawn: the rocket's TRUE flight starts
## at the shooter's eye along the aim, so it goes exactly where the
## crosshair points (and the host can compute it from the shot alone). The
## shooter sees it leave the launcher instead: its model starts where the
## rocket sat in the tube and slides onto the true path over the first
## moments of flight -- the usual way shooters (TF2, Overwatch) make a
## projectile come out of the gun without it missing the crosshair.
##
## Rule 1 (co-op): flight is pure maths from (start, direction, fire time),
## so the host only sends "rocket fired"; it alone decides the explosion.

const MAX_LIFETIME := 8.0
## How long the drawn rocket takes to slide from the tube onto its true path.
const VISUAL_CATCH_UP_TIME := 0.25
const MOTOR_SOUND := preload("res://audio/events/weapons/rocket_motor.tres")
const FLAME_COLOR := Color(1.0, 0.65, 0.2)

var _weapon: WeaponData
var _direction := Vector3.FORWARD
var _velocity := Vector3.ZERO
var _age := 0.0
var _ignited := false
var _done := false
var _exclude: Array[RID] = []
var _attacker_id := Health.NO_ATTACKER
var _attacker_body: Node3D
var _weapons: WeaponController

var _visual: Node3D
var _visual_offset_start := Vector3.ZERO
## The handed-over launcher rocket, turning from the tube's angle
## (_visual_turn_start) to straight along the flight (_visual_turn_end).
var _visual_part: Node3D
var _visual_scale := Vector3.ONE
var _visual_turn_start := Quaternion.IDENTITY
var _visual_turn_end := Quaternion.IDENTITY
var _spin := 0.0
var _flame: Node3D
var _trail: GPUParticles3D
var _motor: AudioStreamPlayer3D


## Fires a rocket from `origin` along `direction`. `weapons` is the shooter's
## WeaponController (for hit markers); `shooter` is their body (can't hit
## itself directly, takes self damage from the blast).
static func launch(world: Node, origin: Vector3, direction: Vector3, weapon: WeaponData,
		attacker_id: int, shooter: Node3D, weapons: WeaponController) -> Rocket:
	var rocket := Rocket.new()
	rocket._weapon = weapon
	rocket._direction = direction.normalized()
	rocket._velocity = rocket._direction * weapon.launch_speed
	rocket._attacker_id = attacker_id
	rocket._attacker_body = shooter
	rocket._weapons = weapons
	if shooter is CollisionObject3D:
		rocket._exclude = [(shooter as CollisionObject3D).get_rid()]
	world.add_child(rocket)
	rocket.global_position = origin
	return rocket


## The shooter's viewmodel hands over the rocket that was sitting in the
## tube: the drawn rocket becomes a copy of it, starting exactly where it
## was, then slides onto the true flight path. `rest_basis` is how it would
## sit with the gun at rest (no sway or fire kick) -- the copy turns from
## the tube's angle to that one, so it ends up pointing along the flight.
func take_launcher_visual(launcher_rocket: Node3D, rest_basis: Basis) -> void:
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	var copy := launcher_rocket.duplicate() as Node3D
	copy.visible = true
	_visual.add_child(copy)
	copy.global_transform = launcher_rocket.global_transform
	# How far the tube is from the true path, in this rocket's own space: the
	# copy goes on the spin axis, and the whole visual starts out offset by
	# that much, shrinking to nothing (_process).
	_visual_offset_start = copy.position
	copy.position = Vector3.ZERO
	_visual.position = _visual_offset_start
	_visual_part = copy
	_visual_scale = copy.basis.get_scale()
	_visual_turn_start = copy.basis.orthonormalized().get_rotation_quaternion()
	_visual_turn_end = (global_basis.inverse() * rest_basis).orthonormalized().get_rotation_quaternion()


func _ready() -> void:
	# Deferred: the shooter's viewmodel hands over the real launcher rocket
	# right after launch(); only build a stand-in if nobody did (co-op).
	_ensure_visual.call_deferred()
	_build_flame_and_trail()
	_puff(global_position, 8)
	_point_along(_direction)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= MAX_LIFETIME:
		_explode(global_position)
		return
	_update_velocity(delta)
	var next := global_position + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next)
	query.exclude = _exclude
	query.collision_mask = 1 # world, enemies, players, props; corpses don't stop it
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		# Pulled back a touch off the surface so the blast's line-of-sight
		# check doesn't start inside the wall.
		_explode(hit.position + hit.normal * 0.1, hit.collider as Node3D)
		return
	global_position = next
	_point_along(_velocity)


func _process(delta: float) -> void:
	if _done or _visual == null:
		return
	# Slide the drawn rocket from the tube onto the true path.
	var t := smoothstep(0.0, 1.0, clampf(_age / VISUAL_CATCH_UP_TIME, 0.0, 1.0))
	_visual.position = _visual_offset_start * (1.0 - t)
	if _visual_part:
		_visual_part.basis = Basis(_visual_turn_start.slerp(_visual_turn_end, t)) * Basis.from_scale(_visual_scale)
	_spin += _weapon.rocket_spin * delta
	_visual.rotation.z = _spin


## Stage 1: the launch charge -- launch_speed with a little gravity, so it
## dips. Stage 2 after ignite_delay: the motor -- gravity gone, thrust
## accelerates it along the aim up to max_speed.
func _update_velocity(delta: float) -> void:
	if not _ignited:
		_velocity += Vector3.DOWN * _weapon.launch_gravity * delta
		if _age >= _weapon.ignite_delay:
			_ignite()
		return
	var speed := minf(_velocity.length() + _weapon.thrust * delta, _weapon.max_speed)
	# The motor steers it back along the aim, so the launch dip doesn't
	# throw the shot off the crosshair.
	_velocity = _velocity.normalized().slerp(_direction, minf(6.0 * delta, 1.0)) * speed


func _ignite() -> void:
	_ignited = true
	_flame.visible = true
	_trail.emitting = true
	_puff(global_position, 6)
	_motor = SoundPlayer.play_loop_3d(MOTOR_SOUND, self)


## `direct_hit` is whatever the rocket struck itself -- it takes the full
## damage, like Quake's direct rocket hits, not the falloff from the blast.
func _explode(at: Vector3, direct_hit: Node3D = null) -> void:
	_done = true
	global_position = at
	var settings := Explosion.Settings.new()
	settings.direct_hit = direct_hit
	settings.damage = _weapon.explosion_damage
	settings.radius = _weapon.explosion_radius
	settings.knockback = _weapon.explosion_knockback
	settings.player_damage = _weapon.explosion_player_damage
	settings.attacker_id = _attacker_id
	settings.attacker_body = _attacker_body
	var hits := Explosion.explode(self, at, settings)
	if is_instance_valid(_weapons):
		_weapons.report_explosion_hits(hits)
	if is_instance_valid(_motor):
		_motor.stop()
		_motor.queue_free()
	if _visual:
		_visual.visible = false
	_flame.visible = false
	_trail.emitting = false
	# Let the smoke trail finish fading before removing everything.
	get_tree().create_timer(_trail.lifetime + 0.1).timeout.connect(queue_free)


func _point_along(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(direction.normalized().y) < 0.98 else Vector3.RIGHT
	look_at(global_position + direction, up)


## For a rocket nobody handed a launcher visual (another player's, in co-op):
## the same rocket part pulled out of the weapon's own model, at the size
## it is on the gun.
func _ensure_visual() -> void:
	if _visual != null or _done:
		return
	_visual = Node3D.new()
	add_child(_visual)
	if _weapon.viewmodel_scene == null:
		return
	var model := _weapon.viewmodel_scene.instantiate() as Node3D
	var part := model.find_child(_weapon.projectile_part, true, false) as Node3D
	if part:
		# The part's size and turn inside the model, all the way up to the root.
		var part_basis := part.transform.basis
		var parent := part.get_parent() as Node3D
		while parent:
			part_basis = parent.transform.basis * part_basis
			parent = parent.get_parent() as Node3D
		part.get_parent().remove_child(part)
		_visual.add_child(part)
		part.transform = Transform3D(Basis.from_scale(Vector3.ONE * _weapon.viewmodel_scale) * part_basis, Vector3.ZERO)
	model.queue_free()


## A flame at the tail (behind the rocket: +Z, since it flies along -Z) and
## a smoke trail left hanging in the air -- both off until ignition.
func _build_flame_and_trail() -> void:
	_flame = Node3D.new()
	_flame.position = Vector3(0.0, 0.0, 0.35)
	add_child(_flame)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = FLAME_COLOR
	glow.emission_enabled = true
	glow.emission = FLAME_COLOR
	glow.emission_energy_multiplier = 3.0
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.35
	cone.radial_segments = 6
	var flame_mesh := MeshInstance3D.new()
	flame_mesh.mesh = cone
	flame_mesh.material_override = glow
	flame_mesh.rotation.x = -PI * 0.5 # point the cone backward, out of the tail
	flame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.add_child(flame_mesh)
	var light := OmniLight3D.new()
	light.light_color = FLAME_COLOR
	light.light_energy = 2.0
	light.omni_range = 4.0
	_flame.add_child(light)
	_flame.visible = false

	_trail = GPUParticles3D.new()
	_trail.amount = 60
	_trail.lifetime = 1.2
	_trail.local_coords = false
	_trail.emitting = false
	_trail.position = Vector3(0.0, 0.0, 0.4)
	_trail.draw_pass_1 = _smoke_quad(0.35)
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.BACK
	material.spread = 12.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.gravity = Vector3(0.0, 0.4, 0.0)
	material.damping_min = 1.0
	material.damping_max = 2.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	material.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.82, 0.78, 0.7))
	fade.set_color(1, Color(0.6, 0.58, 0.55, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	_trail.process_material = material
	add_child(_trail)


## A quick burst of smoke left in the air -- the launch charge at the tube,
## and again as the motor lights.
func _puff(at: Vector3, amount: int) -> void:
	var puff := GPUParticles3D.new()
	puff.amount = amount
	puff.lifetime = 0.9
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.draw_pass_1 = _smoke_quad(0.4)
	var material := ParticleProcessMaterial.new()
	material.spread = 180.0
	material.initial_velocity_min = 0.3
	material.initial_velocity_max = 1.2
	material.gravity = Vector3(0.0, 0.5, 0.0)
	material.damping_min = 2.0
	material.damping_max = 3.0
	material.color = Color(0.8, 0.78, 0.75, 0.6)
	puff.process_material = material
	get_tree().current_scene.add_child(puff)
	puff.global_position = at
	puff.emitting = true
	puff.finished.connect(puff.queue_free)


static var _smoke_material: StandardMaterial3D


static func _smoke_quad(size: float) -> QuadMesh:
	if _smoke_material == null:
		_smoke_material = StandardMaterial3D.new()
		_smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_material.vertex_color_use_as_albedo = true
		_smoke_material.albedo_texture = Explosion._puff_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _smoke_material
	return quad
