class_name Consumed
extends RigidBody3D

## THE CONSUMED (the user's, 2026-10-25/26; docs/QUESTS_TRADERS_WALKERS.md): a
## human fully consumed by the virus, grown a roach's wings (theirs, scaled
## up) -- a random body from the human set, flying flat face-down (the
## user's: like Spider-Man), its arms and legs dangling limp
## with real physics (its limbs a ragdoll, almost dead), its head up and aimed
## dead at you with the Stalker's eyes (ConsumedLook). It never stops: it
## rushes at SPEED and flings itself into you with no regard for itself --
## HIT damage and a SHOVE that throws you (off a ledge, up there) -- bounces
## off, tumbles TUMBLE_TIME, and comes again. Its wings buzz, it groans as it
## dives, a thud as it hits.
## CIRCLING (round the Ossuary's spires): it loops round `circle_at` till
## someone's within NOTICE of it, then it's on them.
## Killed: limp, all of it a ragdoll; MEAT_CHANCE it leaves a meat chunk.
## Rule 1 (co-op): the host's (NetEntities, made with .new(): its look comes
## with net_spawn_args); every game dangles its own limbs and aims its own
## head (presentation).

## (The user's: 22, then half, 2026-10-26.)
const SPEED := 11.0
## Turning at most this many degrees a second toward you (the user's: like
## the heart's blood orbs, then twice theirs).
const TURN_RATE := HeartOrb.TURN_RATE * 2.0
## Flying, it keeps this far off the ground under it (its limbs hang clear),
## lifting this fast (m/s per metre short).
const CLEARANCE := 1.4
const LIFT := 8.0
## Its bones kept out of the ground this long after it dies (and while it
## tumbles); a bone looked at only if it moved this far in a step.
const GUARD_TIME := 5.0
const GUARD_MOVE := 0.05
const ACCEL := 45.0
const HIT := 15.0
const SHOVE := 12.0
const TUMBLE_TIME := 2.0
const HEALTH := 40.0
const MEAT_CHANCE := 1.0 / 3.0
const MEAT_WEIGHT := 2.0
const NOTICE := 120.0
const LOSE := 400.0
const CIRCLE_RADIUS := Vector2(60.0, 120.0)
const CIRCLE_SPEED := 7.0 # (halved with its speed)
const HEIGHT := 1.8
const MODEL_DIRS := ["res://art/characters/Characters_psx/Models/Male/", "res://art/characters/Characters_psx/Models/Female/"]
const ROACH := "res://scenes/enemy/roach_model.tscn"
const BUZZ := "res://audio/events/enemy/roach_buzz.tres"
const WING_SCALE := 3.375
const LIMBS: Array[StringName] = [&"LeftUpperArm", &"LeftLowerArm", &"RightUpperArm", &"RightLowerArm",
		&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
const CORPSE_TIME := 60.0
## Its hanging limbs (the user's: hanging low, still swinging, never wildly):
## their swing damped this much, gravity this many times on them, their
## drag through the air.
const LIMB_SWING_DAMP := 8.0
const LIMB_GRAVITY := 2.0
const LIMB_DRAG := 0.5
## The wings' roots, at its shoulder blades (its own space: lying face-down,
## head at -Z), WINGS_APART either side; WOUND_FLAPS torn flaps of skin
## round each.
const WINGS_AT := Vector3(0.0, 0.13, -0.42)
const WINGS_APART := 0.1
const WOUND_FLAPS := 6
## Optimizing: its limbs' real physics only this near your camera (beyond,
## ConsumedHang hangs them for nothing); its head aimed only this near; its
## look gone past SEEN_TO; checked every LOD_EVERY; a target looked for
## every PICK_EVERY.
const LIMB_PHYSICS_NEAR := 60.0
const GAZE_NEAR := 150.0
const SEEN_TO := 400.0
const LOD_EVERY := 0.5
const PICK_EVERY := 0.5

## Its look (an index into the human set) and, circling, round where.
var look := 0
var circle_at := Vector3.INF

var _health: Health
var _model: Node3D
var _skeleton: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
var _gaze: ConsumedLook
var _hang: ConsumedHang
var _limbs_live := false
var _lod_left := 0.0
var _pick_left := 0.0
var _wings: Array[Node3D] = []
## The wings and their wounds (going with its chest once it's dead).
var _back_parts: Array[Node3D] = []
var _buzz: AudioStreamPlayer3D
var _target: PlayerMovement
var _tumble_left := 0.0
var _dead := false
var _flap := 0.0
var _circle_angle := 0.0
var _circle_radius := 90.0
var _hit_cooldown := 0.0
## Which way it's flying at them (ZERO: from how it's moving, next).
var _heading := Vector3.ZERO
var _guard_left := 0.0
## Where each simulated bone was last step (_guard_bones).
var _bones_were := {}

static var _models: Array[String] = []


## The human set's models (every male and female character).
static func models() -> Array[String]:
	if _models.is_empty():
		for dir_path: String in MODEL_DIRS:
			var dir := DirAccess.open(dir_path)
			if dir == null:
				continue
			for file in dir.get_files():
				var bare := file.trim_suffix(".import").trim_suffix(".remap")
				if bare.ends_with(".fbx") and not _models.has(dir_path + bare):
					_models.append(dir_path + bare)
		_models.sort()
	return _models


# ---- Co-op (NetEntities) --------------------------------------------------------------

func net_spawn_args() -> Dictionary:
	return {look = look}


func net_restore(args: Dictionary) -> void:
	look = int(args.get("look", 0))


func _init() -> void:
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = HEALTH
	add_child(_health)


func _ready() -> void:
	add_to_group("enemies")
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true # (fast and thin: never through the terrain in a step)
	angular_damp = 4.0
	linear_damp = 0.2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75 # (head to feet: none of it out past it as it rolls)
	shape.shape = capsule
	shape.rotation.x = PI * 0.5 # (lying along it, as it flies)
	add_child(shape)
	_build_body()
	if not NetEntities.is_puppet(self) and not (Network.is_online() and not multiplayer.is_server()):
		_health.died.connect(func(_attacker: int, _critical: bool) -> void: _die(true))
		body_entered.connect(_on_hit)
		_circle_angle = randf() * TAU
		_circle_radius = randf_range(CIRCLE_RADIUS.x, CIRCLE_RADIUS.y)
	else:
		_health.died.connect(func(_attacker: int, _critical: bool) -> void: _die(false))
	_start_buzz.call_deferred()


## Its body: the human (sized), its limbs left to hang (a ragdoll of just
## them), its head aimed (ConsumedLook), the Stalker's eyes, the wings.
func _build_body() -> void:
	var list := models()
	if list.is_empty():
		return
	var scene := load(list[look % list.size()]) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	var bounds := BackpackView._bounds(_model)
	var fit_scale := HEIGHT / maxf(bounds.size.y, 0.01)
	# Flying flat (the user's: like Spider-Man): lying face-down along its way
	# (-Z), head first, its middle on its own; its limbs hang from it.
	_model.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * fit_scale), Vector3.BACK * HEIGHT * 0.5)
	# Grey and veined by the virus; not drawn past SEEN_TO.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _veins()
		(node as MeshInstance3D).visibility_range_end = SEEN_TO
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_skeleton = skeletons[0] as Skeleton3D
	_ragdoll = RagdollBuilder.build(_skeleton)
	for node in _ragdoll.get_children():
		var bone := node as PhysicalBone3D
		if bone:
			bone.collision_layer = 0
			# They drag over the ground and walls (never through them); nothing
			# hits them, and never their own body.
			bone.collision_mask = 1
			bone.add_collision_exception_with(self)
			bone.can_sleep = false
			bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
			bone.angular_damp = LIMB_SWING_DAMP
			bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
			bone.linear_damp = LIMB_DRAG
			bone.gravity_scale = LIMB_GRAVITY
	# (Its limbs' physics start once it's near your camera: _limbs.)
	_hang = ConsumedHang.new()
	_skeleton.add_child(_hang)
	_gaze = ConsumedLook.new()
	_skeleton.add_child(_gaze)
	# The Stalker's eyes, on its head.
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	_skeleton.add_child(head)
	var fit := maxf(_skeleton.global_transform.basis.get_scale().x, 0.0001)
	var eyes := Node3D.new()
	eyes.scale = Vector3.ONE / fit
	head.add_child(eyes)
	_shared_meshes()
	var core := Stalker._glow_material(Color(0.9, 0.97, 1.0), false)
	var glare := Stalker._glow_material(Color(Stalker.EYE_COLOR, Stalker.EYE_GLOW), true)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = _eye_core
		eye.material_override = core
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.visibility_range_end = SEEN_TO
		eye.position = Vector3(side * Stalker.EYE_APART, Stalker.EYE_UP, Stalker.EYE_FORWARD)
		eyes.add_child(eye)
		var flare := MeshInstance3D.new()
		flare.mesh = _eye_glare
		flare.material_override = glare
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.visibility_range_end = SEEN_TO
		eye.add_child(flare)
	# The roach's wings, scaled up, burst out through split skin at its
	# shoulder blades (the user's): flat along the lying body, as on the
	# roach, each root sunk in a raw, bloody wound, torn skin curling back
	# round it (on the body itself: its chest never moves).
	if ResourceLoader.exists(ROACH):
		var roach := (load(ROACH) as PackedScene).instantiate()
		var dice := RandomNumberGenerator.new()
		dice.seed = look
		for pivot_name in ["WingPivotL", "WingPivotR"]:
			var pivot := roach.get_node_or_null(NodePath(pivot_name)) as Node3D
			if pivot == null:
				continue
			roach.remove_child(pivot)
			for part in [pivot] + pivot.find_children("*", "", true, false):
				(part as Node).owner = null # (its own now: not the roach scene's)
			var root := WINGS_AT + Vector3.RIGHT * WINGS_APART * (-1.0 if pivot_name.ends_with("L") else 1.0)
			var holder := Node3D.new()
			holder.scale = Vector3.ONE * WING_SCALE
			holder.position = root
			add_child(holder)
			_back_parts.append(holder)
			holder.add_child(pivot)
			pivot.position = Vector3.ZERO
			for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(mesh as MeshInstance3D).visibility_range_end = SEEN_TO
			_wings.append(pivot)
			_wound(root, dice)
		roach.free()


static var _eye_core: QuadMesh
static var _eye_glare: QuadMesh
static var _raw_mesh: SphereMesh
static var _flap_mesh: BoxMesh
static var _skin_material: StandardMaterial3D


## Its meshes, one of each for all of them.
static func _shared_meshes() -> void:
	if _eye_core:
		return
	_eye_core = QuadMesh.new()
	_eye_core.size = Vector2.ONE * Stalker.EYE_CORE
	_eye_glare = QuadMesh.new()
	_eye_glare.size = Vector2.ONE * Stalker.EYE_GLARE
	_raw_mesh = SphereMesh.new()
	_raw_mesh.radius = 0.09
	_raw_mesh.height = 0.07
	_raw_mesh.radial_segments = 8
	_raw_mesh.rings = 3
	_flap_mesh = BoxMesh.new()
	_flap_mesh.size = Vector3(0.06, 0.008, 0.045)


## Its torn skin (the wounds' flaps).
static func _torn_skin() -> StandardMaterial3D:
	if _skin_material == null:
		_skin_material = StandardMaterial3D.new()
		_skin_material.albedo_color = Color(0.5, 0.44, 0.42)
		_skin_material.roughness = 0.9
		_skin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _skin_material


## A wing's root at `at`: the skin split open, raw and bloody (the nests'
## wet flesh), WOUND_FLAPS torn flaps curling back up from its edge.
func _wound(at: Vector3, dice: RandomNumberGenerator) -> void:
	var raw := MeshInstance3D.new()
	raw.mesh = _raw_mesh
	raw.material_override = ConsumedNest.flesh()
	raw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raw.visibility_range_end = SEEN_TO
	raw.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.6)), at + Vector3.DOWN * 0.02)
	add_child(raw)
	_back_parts.append(raw)
	for i in WOUND_FLAPS:
		var angle := TAU * (float(i) + dice.randf_range(-0.3, 0.3)) / WOUND_FLAPS
		var out := Vector3(cos(angle) * 0.085, 0.0, sin(angle) * 0.13)
		var flap := MeshInstance3D.new()
		flap.mesh = _flap_mesh
		flap.material_override = _torn_skin()
		flap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flap.visibility_range_end = SEEN_TO
		# Pointing out from the wound, curled up and back off it.
		var curl := Basis(Vector3.UP, -angle) * Basis(Vector3.BACK, dice.randf_range(0.4, 0.9))
		flap.transform = Transform3D(curl * Basis.from_scale(Vector3.ONE * dice.randf_range(0.8, 1.3)), at + out + Vector3.UP * 0.005)
		add_child(flap)
		_back_parts.append(flap)


static var _vein_material: StandardMaterial3D


static func _veins() -> StandardMaterial3D:
	if _vein_material == null:
		_vein_material = StandardMaterial3D.new()
		_vein_material.albedo_color = Color(0.35, 0.38, 0.4, 0.55)
		_vein_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_vein_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return _vein_material


func _start_buzz() -> void:
	if not is_inside_tree() or not ResourceLoader.exists(BUZZ):
		return
	_buzz = SoundPlayer.play_loop_3d(load(BUZZ) as SoundEvent, self)
	if _buzz:
		_buzz.pitch_scale = 0.6


func _process(delta: float) -> void:
	if _dead:
		return
	# The wings: a blur.
	_flap += delta * 30.0
	for i in _wings.size():
		_wings[i].rotation.z = sin(_flap) * 0.9 * (1.0 if i == 0 else -1.0)
	# Near your camera: its limbs' real physics, its head aimed; farther,
	# neither (each game's own).
	var camera := get_viewport().get_camera_3d()
	_lod_left -= delta
	if _lod_left <= 0.0 and camera:
		_lod_left = LOD_EVERY
		var gap := camera.global_position.distance_to(global_position)
		_limbs(gap < LIMB_PHYSICS_NEAR)
		if _gaze:
			_gaze.active = gap < GAZE_NEAR
	# Its head aimed dead at you (your own game: at you).
	if _gaze and _gaze.active and camera:
		_gaze.target = camera.global_position
	if _buzz:
		_buzz.pitch_scale = lerpf(0.5, 0.8, clampf(linear_velocity.length() / SPEED, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	# Tumbling, or falling dead (every game's own): its bones kept out of the
	# ground.
	if _tumble_left > 0.0 or _guard_left > 0.0:
		_guard_left = maxf(_guard_left - delta, 0.0)
		_guard_bones()
	if _dead or NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	if _tumble_left > 0.0:
		_tumble_left -= delta
		if _tumble_left <= 0.0:
			gravity_scale = 0.0
		return
	_keep_off_ground()
	if is_instance_valid(_target) and (_target.is_dead() or _target.global_position.distance_to(global_position) > LOSE):
		_target = null
	if not is_instance_valid(_target):
		_target = null
		_pick_left -= delta
		if _pick_left <= 0.0:
			_pick_left = PICK_EVERY
			_target = _pick_target()
	if _target == null:
		_circle(delta)
		return
	# Rushing at them, flat out -- flinging itself. Like the heart's blood
	# orbs (the user's): along its heading, turning at most TURN_RATE a second
	# toward them -- juke it late and it overshoots, swinging wide to come
	# round again.
	var aim := _target.head.global_position + Vector3.DOWN * 0.4
	var to := aim - global_position
	if _heading == Vector3.ZERO:
		# Level, the way it's going (never up: off the ground after a tumble
		# it's lifting, and it'd shoot off into the sky).
		var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if flat.length_squared() < 1.0:
			flat = Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
		_heading = flat.normalized() if flat.length_squared() > 0.0001 else to.normalized()
	var want := to.normalized()
	var off := _heading.angle_to(want)
	if off > 0.0001:
		var axis := _heading.cross(want)
		if axis.length_squared() < 0.000001:
			axis = _heading.cross(Vector3.UP if absf(_heading.y) < 0.9 else Vector3.RIGHT) # (dead behind it: either way round)
		_heading = _heading.rotated(axis.normalized(), minf(off, deg_to_rad(TURN_RATE) * delta)).normalized()
	linear_velocity = linear_velocity.move_toward(_heading * SPEED, ACCEL * delta)
	angular_velocity = Vector3.ZERO
	_upright(_heading)
	if to.length() < 1.3:
		_strike(_target)


## Its simulated bones, tumbling or falling dead: any that went through the
## ground or a wall in a step (fast and thin, too much for the physics to
## catch) put back on its near side, no longer moving into it.
func _guard_bones() -> void:
	if _ragdoll == null:
		return
	var space := get_world_3d().direct_space_state
	for node in _ragdoll.get_children():
		var bone := node as PhysicalBone3D
		if bone == null or not bone.is_simulating_physics():
			continue
		var now := bone.global_position
		var was: Vector3 = _bones_were.get(bone, now)
		_bones_were[bone] = now
		if was.distance_squared_to(now) < GUARD_MOVE * GUARD_MOVE:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(was, now, 1, [get_rid()]))
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		bone.global_position = (hit.position as Vector3) + normal * 0.05
		bone.linear_velocity -= normal * minf(bone.linear_velocity.dot(normal), 0.0)
		_bones_were[bone] = bone.global_position


## Flying, it keeps CLEARANCE off the ground under it (its hanging limbs
## clear of it): lifting, and its heading pulled out of any dive.
func _keep_off_ground() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * CLEARANCE, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider is PlayerMovement:
		return # (over you: diving on you, not lifting off)
	var short := CLEARANCE - global_position.distance_to(hit.position as Vector3)
	linear_velocity.y = maxf(linear_velocity.y, short * LIFT)
	if _heading.y < 0.0:
		_heading = Vector3(_heading.x, _heading.y * (1.0 - short / CLEARANCE), _heading.z).normalized()


## Its limbs' real physics on (near) or off (ConsumedHang hangs them).
func _limbs(live: bool) -> void:
	if live == _limbs_live or _ragdoll == null:
		return
	_limbs_live = live
	if live:
		_ragdoll.physical_bones_start_simulation(LIMBS)
	else:
		_ragdoll.physical_bones_stop_simulation()
	if _hang:
		_hang.active = not live


## The nearest player it'll go for: within NOTICE while circling, else any.
func _pick_target() -> PlayerMovement:
	var best: PlayerMovement = null
	var best_distance := NOTICE if circle_at.is_finite() else LOSE
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var gap := player.global_position.distance_to(global_position)
		if gap < best_distance:
			best_distance = gap
			best = player
	if best:
		WalkerSound.play("groan", global_position, get_tree().current_scene, 80.0, 0.0, 8.0)
	return best


## Looping round where it nests (the Ossuary's spires), waiting.
func _circle(delta: float) -> void:
	_heading = Vector3.ZERO
	if not circle_at.is_finite():
		linear_velocity = linear_velocity.move_toward(Vector3.ZERO, ACCEL * delta)
		return
	_circle_angle += CIRCLE_SPEED / _circle_radius * delta
	var want := circle_at + Vector3(cos(_circle_angle), sin(_circle_angle * 0.7) * 0.15, sin(_circle_angle)) * _circle_radius
	var to := want - global_position
	linear_velocity = linear_velocity.move_toward(to.limit_length(CIRCLE_SPEED * 2.0), ACCEL * delta)
	angular_velocity = Vector3.ZERO
	_upright(linear_velocity)


func _upright(toward: Vector3) -> void:
	var flat := Vector3(toward.x, 0.0, toward.z)
	if flat.length_squared() < 0.01:
		return
	var want := Basis.looking_at(flat.normalized(), Vector3.UP)
	global_basis = global_basis.slerp(want, 0.15).orthonormalized()


func _on_hit(body: Node) -> void:
	if body is PlayerMovement:
		_strike(body as PlayerMovement)


## Into them: HIT and a SHOVE, a thud -- and off it bounces, tumbling.
func _strike(player: PlayerMovement) -> void:
	if _hit_cooldown > 0.0 or _dead or _tumble_left > 0.0:
		return
	_hit_cooldown = TUMBLE_TIME
	var dir := (player.global_position - global_position)
	dir.y = maxf(dir.y, 0.0)
	dir = dir.normalized() if dir.length_squared() > 0.01 else -global_basis.z
	player.health.take_damage(HIT)
	player.shove(dir * SHOVE + Vector3.UP * SHOVE * 0.35)
	WalkerSound.play("thud", global_position, get_tree().current_scene, 40.0, 0.0, 6.0)
	linear_velocity = -dir * 8.0 + Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	gravity_scale = 1.0
	_tumble_left = TUMBLE_TIME
	_heading = Vector3.ZERO # (coming round again from wherever it's thrown)


## Dead: limp, all of it a ragdoll, falling like a sack; the host's: now
## and then a meat chunk. Gone after CORPSE_TIME.
func _die(host: bool) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	# Only the ragdoll falls now: its body's left out of the way (else the
	# two fight, and the bones are pushed into the ground).
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	set_deferred(&"freeze", true) # (deferred: it may die mid-physics)
	_guard_left = GUARD_TIME
	if _buzz:
		_buzz.stop()
	if _gaze:
		_gaze.queue_free()
	if _hang:
		_hang.queue_free()
	if _ragdoll:
		_ragdoll.physical_bones_start_simulation()
		for node in _ragdoll.get_children():
			var bone := node as PhysicalBone3D
			if bone:
				bone.collision_layer = 1 << 3
				bone.collision_mask = 1
				# Limp now: a sack, falling free.
				bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_COMBINE
				bone.angular_damp = 0.0
				bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_COMBINE
				bone.linear_damp = 0.0
				bone.gravity_scale = 1.0
	if host and randf() < MEAT_CHANCE:
		CarryItem.spawn_meat(get_tree().current_scene, global_position, MEAT_WEIGHT, false)
	get_tree().create_timer(CORPSE_TIME).timeout.connect(queue_free)
	_wings_to_chest()


## Dead: its wings and their wounds go with its falling chest (not the body
## they were on).
func _wings_to_chest() -> void:
	if _skeleton == null or _back_parts.is_empty():
		return
	var chest := BoneAttachment3D.new()
	chest.bone_name = "UpperChest" if _skeleton.find_bone("UpperChest") >= 0 else "Chest"
	_skeleton.add_child(chest)
	await get_tree().process_frame
	if not is_instance_valid(chest):
		return
	for part in _back_parts:
		if is_instance_valid(part):
			part.reparent(chest, true)
