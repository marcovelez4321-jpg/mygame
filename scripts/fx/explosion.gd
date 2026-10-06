class_name Explosion
extends RefCounted

## One explosion everything uses -- rockets now, explosive barrels later.
##
## Gameplay (host only, Rule 1):
##   - Radius damage that falls off in a straight line from full at the
##     centre to nothing at the edge, and is blocked by walls (Quake's
##     T_RadiusDamage idea, with a line-of-sight check like Source's).
##   - Knockback on everything in range: players get shoved (rocket jumping
##     comes from this), physics props and roaches get launched (roaches
##     also get their engine stalled).
##   - Players -- you, and in co-op your friends -- take player_damage
##     instead of the full damage, so rocket jumping costs a little health
##     and a stray rocket never one-shots a teammate.
## Presentation (every client, from one "explosion here" event):
##   - An old-school Quake-style explosion: a bright billboard fireball that
##     swells and burns out, chunks of fire, a dark smoke puff that rises, a
##     flash of light, screen shake and the boom.
##   - Ragdolls (corpses, and bodies this blast just killed) get launched.
##     They're presentation, not networked, so each player's game throws its own.

## Who was hurt, so the shooter's hit markers can light up.
class Hit:
	var health: Health
	var killed: bool

const BOOM_SOUND := preload("res://audio/events/explosion.tres")
const FIREBALL_COLOR := Color(1.0, 0.6, 0.15)
const SMOKE_COLOR := Color(0.18, 0.16, 0.14, 0.75)
## Screen shake for the local player at the centre, fading out to nothing at
## this many radii away.
const SHAKE_STRENGTH := 6.0
const SHAKE_REACH := 4.0
## Every explosion throws OBJECTS (props, roaches, corpses, ragdolls) this
## many times harder than its knockback. Players aren't multiplied, so rocket
## jumps stay controllable -- their push is the knockback itself.
const OBJECT_PUSH_MULTIPLIER := 3.0
## How much upward lift objects get, as a fraction of their push, so they go
## flying instead of skidding along the floor.
const OBJECT_LIFT := 0.6
## Ragdolls fly at this fraction of a prop's launch speed: a full 3x push
## sends a body at ~40 m/s, straight out of the map.
const RAGDOLL_LAUNCH_SCALE := 0.4

## Settings for one kind of explosion -- a weapon or a barrel fills these.
class Settings:
	var damage := 100.0
	var radius := 5.6
	## Push in m/s at the centre (falls off like the damage).
	var knockback := 14.0
	## What a PLAYER takes at the centre instead of `damage` (falls off the
	## same way) -- the shooter and, in co-op, everyone else.
	var player_damage := 10.0
	## Multiplayer id of whoever caused it (Health.NO_ATTACKER for a barrel).
	var attacker_id := Health.NO_ATTACKER
	## The attacker's own body, so they don't get hit markers on themselves.
	## May be null.
	var attacker_body: Node3D
	## What a projectile struck directly -- takes the full damage and push,
	## not the distance falloff. May be null.
	var direct_hit: Node3D


## Blows up at `center`. Returns who was hurt (not counting the attacker).
static func explode(world: Node3D, center: Vector3, settings: Settings) -> Array[Hit]:
	var hits := _apply_damage_and_push(world, center, settings)
	play_effects(world, center, settings.radius, settings.knockback)
	return hits


## Everything within the radius, damaged and pushed by how close it is and
## whether a wall is in the way.
static func _apply_damage_and_push(world: Node3D, center: Vector3, settings: Settings) -> Array[Hit]:
	var hits: Array[Hit] = []
	var space := world.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = settings.radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 1 # world, players, enemies, props (ragdolls: _launch_ragdolls)
	var seen := {}
	for result in space.intersect_shape(query, 128):
		var body := result.collider as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		var aim_point := _aim_point(body)
		var distance := center.distance_to(aim_point)
		var direct := body == settings.direct_hit
		if not direct and (distance > settings.radius or not _in_line_of_sight(space, center, aim_point, body)):
			continue
		var falloff := 1.0 if direct else 1.0 - distance / settings.radius
		var push_direction := (aim_point - center).normalized() if distance > 0.01 else Vector3.UP
		_hurt(body, settings, falloff, push_direction, center, hits)
		_push(body, push_direction, settings.knockback * falloff)
	return hits


static func _hurt(body: Node3D, settings: Settings, falloff: float, direction: Vector3, center: Vector3, hits: Array[Hit]) -> void:
	var health := body.get_node_or_null("Health") as Health
	if health == null or health.is_dead:
		return
	var damage := (settings.player_damage if body is PlayerMovement else settings.damage) * falloff
	# No throw force here: a body this kills is launched by _launch_ragdolls,
	# all of it at once.
	health.take_damage(damage, settings.attacker_id, direction, center)
	if body != settings.attacker_body:
		var hit := Hit.new()
		hit.health = health
		hit.killed = health.is_dead
		hits.append(hit)


## Players are shoved (applied inside their own movement step, so rocket
## jumps predict cleanly in co-op); physics props and roaches are launched.
## `speed` is m/s, already fallen off with distance.
static func _push(body: Node3D, direction: Vector3, speed: float) -> void:
	if speed < 0.01:
		return
	if body.has_method("shove"):
		# A little extra lift, so a blast at your feet throws you up rather
		# than sliding you along the floor -- the rocket jump.
		body.call("shove", direction * speed + Vector3.UP * speed * 0.3)
	elif body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.apply_central_impulse(_object_launch(direction, speed) * rigid.mass)
		if rigid.has_method("stun"):
			rigid.call("stun") # roaches: blast stalls their wings


## The velocity an object is thrown with: away from the blast but never down
## into the floor (a rocket hitting a crate from above would just pin it),
## lifted so it goes flying, and OBJECT_PUSH_MULTIPLIER times the knockback.
static func _object_launch(direction: Vector3, speed: float) -> Vector3:
	var away := Vector3(direction.x, maxf(direction.y, 0.0), direction.z)
	return (away + Vector3.UP * OBJECT_LIFT).normalized() * speed * OBJECT_PUSH_MULTIPLIER


## Where to measure distance and line of sight to: a character's chest
## (their origin is at the feet), anything else's own centre.
static func _aim_point(body: Node3D) -> Vector3:
	if body is CharacterBody3D:
		return body.global_position + Vector3.UP * 0.9
	return body.global_position


## Blocked if world geometry (a StaticBody3D -- walls, floors, map brushes)
## is between the blast and the target. Other bodies don't shield.
static func _in_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	if target is CollisionObject3D:
		query.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or not hit.collider is StaticBody3D


## The look and sound. Public so a client in co-op can play it from the
## host's "explosion at X" message without redoing the damage.
static func play_effects(world: Node3D, center: Vector3, radius: float, knockback: float) -> void:
	var scene := world.get_tree().current_scene
	var root := Node3D.new()
	scene.add_child(root)
	root.global_position = center
	_add_fireball(root, radius)
	_add_fire_chunks(root, radius)
	_add_smoke(root, radius)
	_add_flash(root, radius)
	SoundPlayer.play_3d(BOOM_SOUND, center, scene)
	_shake_local_player(world, center, radius)
	_launch_ragdolls(root, center, radius, knockback)
	world.get_tree().create_timer(2.5).timeout.connect(root.queue_free)


## Throws every ragdoll in range as ONE piece: every bone of a body gets the
## same velocity, so its joints have nothing to fight. (Pushing bones one at
## a time barely moves a ragdoll -- the joints pull each bone straight back
## toward its neighbours.) Waits one physics step first, so bodies this blast
## just killed have switched to ragdoll and can be found.
static func _launch_ragdolls(root: Node3D, center: Vector3, radius: float, knockback: float) -> void:
	await root.get_tree().physics_frame
	if not is_instance_valid(root):
		return
	var space := root.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = EnemyRagdoll.RAGDOLL_LAYER
	# Each body's bone nearest the blast decides how hard the body is thrown.
	var nearest := {} # the body's PhysicalBoneSimulator3D -> its nearest bone
	for result in space.intersect_shape(query, 128):
		var bone := result.collider as PhysicalBone3D
		if bone == null:
			continue
		var body := bone.get_parent()
		if not nearest.has(body) or center.distance_to(bone.global_position) < center.distance_to(nearest[body].global_position):
			nearest[body] = bone
	for body: Node in nearest:
		var bone: PhysicalBone3D = nearest[body]
		var distance := center.distance_to(bone.global_position)
		if distance > radius or not _in_line_of_sight(space, center, bone.global_position, bone):
			continue
		var bones := body.get_children().filter(func(child: Node) -> bool: return child is PhysicalBone3D)
		var middle := Vector3.ZERO
		for each: PhysicalBone3D in bones:
			middle += each.global_position
		middle /= bones.size()
		var direction := (middle - center).normalized() if middle.distance_to(center) > 0.01 else Vector3.UP
		var velocity := _object_launch(direction, knockback * (1.0 - distance / radius)) * RAGDOLL_LAUNCH_SCALE
		for each: PhysicalBone3D in bones:
			each.apply_central_impulse(velocity * each.mass)


## The Quake look: a flat, bright billboard that swells fast and burns out.
static func _add_fireball(root: Node3D, radius: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = _fireball_texture()
	material.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 0.9
	var ball := MeshInstance3D.new()
	ball.mesh = quad
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3
	root.add_child(ball)
	var tween := ball.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.3, 0.05, 0.0), 0.45).set_delay(0.08)


static func _add_fire_chunks(root: Node3D, radius: float) -> void:
	var chunks := GPUParticles3D.new()
	chunks.amount = 24
	chunks.lifetime = 0.6
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.draw_pass_1 = BloodFX.droplet_mesh()
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = radius * 1.5
	material.initial_velocity_max = radius * 3.0
	material.gravity = Vector3(0.0, -9.8, 0.0)
	material.scale_min = 1.5
	material.scale_max = 3.0
	material.color = FIREBALL_COLOR
	chunks.process_material = material
	root.add_child(chunks)
	chunks.emitting = true


## Dark puffs that bloom out, rise and fade -- what's left after the flash.
static func _add_smoke(root: Node3D, radius: float) -> void:
	var smoke := GPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 1.8
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	var puff_material := StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.vertex_color_use_as_albedo = true
	puff_material.albedo_texture = _puff_texture()
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * radius * 0.35
	puff.material = puff_material
	smoke.draw_pass_1 = puff
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 70.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = radius * 0.6
	material.gravity = Vector3(0.0, 1.2, 0.0) # hot smoke rises
	material.damping_min = 1.5
	material.damping_max = 2.5
	material.scale_min = 0.8
	material.scale_max = 1.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	material.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, SMOKE_COLOR)
	fade.set_color(1, Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	smoke.process_material = material
	root.add_child(smoke)
	smoke.emitting = true


static func _add_flash(root: Node3D, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = FIREBALL_COLOR
	light.light_energy = 8.0
	light.omni_range = radius * 3.0
	root.add_child(light)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.35)


## Shakes the local player's camera, harder the closer they are.
static func _shake_local_player(world: Node3D, center: Vector3, radius: float) -> void:
	var player := PlayerMovement.local_player(world.get_tree())
	if player == null:
		return
	var closeness := 1.0 - clampf(player.global_position.distance_to(center) / (radius * SHAKE_REACH), 0.0, 1.0)
	if closeness > 0.0:
		player.camera.shake(SHAKE_STRENGTH * closeness)


static var _fireball_tex: ImageTexture
static var _puff_tex: ImageTexture


## A soft round blob, hot white in the middle to orange at the edge, made
## once in code (no image file to lose).
static func _fireball_texture() -> ImageTexture:
	if _fireball_tex == null:
		_fireball_tex = _radial_texture(64, Color(1.0, 0.95, 0.75), Color(1.0, 0.45, 0.05))
	return _fireball_tex


static func _puff_texture() -> ImageTexture:
	if _puff_tex == null:
		_puff_tex = _radial_texture(32, Color.WHITE, Color.WHITE)
	return _puff_tex


static func _radial_texture(size: int, inner: Color, outer: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var t := clampf(Vector2(x, y).distance_to(center) / (size * 0.5), 0.0, 1.0)
			var color := inner.lerp(outer, t)
			color.a = clampf(1.0 - t, 0.0, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
