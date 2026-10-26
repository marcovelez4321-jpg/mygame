class_name Consumed
extends RigidBody3D

## THE CONSUMED (the user's, 2026-10-25/26; docs/QUESTS_TRADERS_WALKERS.md): a
## human fully consumed by the virus, grown a roach's wings (theirs, scaled
## up) -- a random body from the human set, its arms and legs dangling limp
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

const SPEED := 22.0
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
const CIRCLE_SPEED := 14.0
const HEIGHT := 1.8
const MODEL_DIRS := ["res://art/characters/Characters_psx/Models/Male/", "res://art/characters/Characters_psx/Models/Female/"]
const ROACH := "res://scenes/enemy/roach_model.tscn"
const BUZZ := "res://audio/events/enemy/roach_buzz.tres"
const WING_SCALE := 6.0
const LIMBS: Array[StringName] = [&"LeftUpperArm", &"LeftLowerArm", &"RightUpperArm", &"RightLowerArm",
		&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
const CORPSE_TIME := 60.0

## Its look (an index into the human set) and, circling, round where.
var look := 0
var circle_at := Vector3.INF

var _health: Health
var _model: Node3D
var _skeleton: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
var _gaze: ConsumedLook
var _wings: Array[Node3D] = []
var _buzz: AudioStreamPlayer3D
var _target: PlayerMovement
var _tumble_left := 0.0
var _dead := false
var _flap := 0.0
var _circle_angle := 0.0
var _circle_radius := 90.0
var _hit_cooldown := 0.0

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
	angular_damp = 4.0
	linear_damp = 0.2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	shape.shape = capsule
	shape.position = Vector3.UP * 0.2
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
	_model.position = Vector3.DOWN * HEIGHT * 0.5
	var bounds := BackpackView._bounds(_model)
	_model.scale = Vector3.ONE * HEIGHT / maxf(bounds.size.y, 0.01)
	_model.rotation.y = PI
	# Grey and veined by the virus.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _veins()
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_skeleton = skeletons[0] as Skeleton3D
	_ragdoll = RagdollBuilder.build(_skeleton)
	for node in _ragdoll.get_children():
		var bone := node as PhysicalBone3D
		if bone:
			bone.collision_layer = 0
			bone.collision_mask = 0 # (they hang and swing; nothing to snag on)
			bone.can_sleep = false
	_ragdoll.physical_bones_start_simulation(LIMBS)
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
	var core := Stalker._glow_material(Color(0.9, 0.97, 1.0), false)
	var glare := Stalker._glow_material(Color(Stalker.EYE_COLOR, Stalker.EYE_GLOW), true)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * Stalker.EYE_CORE
		eye.mesh = quad
		eye.material_override = core
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(side * Stalker.EYE_APART, Stalker.EYE_UP, Stalker.EYE_FORWARD)
		eyes.add_child(eye)
		var flare := MeshInstance3D.new()
		var flare_quad := QuadMesh.new()
		flare_quad.size = Vector2.ONE * Stalker.EYE_GLARE
		flare.mesh = flare_quad
		flare.material_override = glare
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(flare)
	# The roach's wings, scaled up, off its back.
	var back := BoneAttachment3D.new()
	back.bone_name = "UpperChest" if _skeleton.find_bone("UpperChest") >= 0 else "Chest"
	_skeleton.add_child(back)
	if ResourceLoader.exists(ROACH):
		var roach := (load(ROACH) as PackedScene).instantiate()
		for pivot_name in ["WingPivotL", "WingPivotR"]:
			var pivot := roach.get_node_or_null(NodePath(pivot_name)) as Node3D
			if pivot == null:
				continue
			roach.remove_child(pivot)
			var holder := Node3D.new()
			holder.scale = Vector3.ONE * WING_SCALE / fit
			holder.position = Vector3(0.0, 0.05, -0.15) / fit
			back.add_child(holder)
			holder.add_child(pivot)
			pivot.position = Vector3(0.04 * (-1.0 if pivot_name.ends_with("L") else 1.0), 0.0, 0.0)
			_wings.append(pivot)
		roach.free()


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
	# Its head aimed dead at you (your own game: at you).
	var me := PlayerMovement.local_player(get_tree())
	if _gaze and me:
		_gaze.target = me.head.global_position
	if _buzz:
		_buzz.pitch_scale = lerpf(0.5, 0.8, clampf(linear_velocity.length() / SPEED, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if _dead or NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	if _tumble_left > 0.0:
		_tumble_left -= delta
		if _tumble_left <= 0.0:
			gravity_scale = 0.0
		return
	if not is_instance_valid(_target) or _target.is_dead() or _target.global_position.distance_to(global_position) > LOSE:
		_target = _pick_target()
	if _target == null:
		_circle(delta)
		return
	# Rushing at them, flat out -- flinging itself.
	var aim := _target.head.global_position + Vector3.DOWN * 0.4
	var to := aim - global_position
	linear_velocity = linear_velocity.move_toward(to.normalized() * SPEED, ACCEL * delta)
	angular_velocity = Vector3.ZERO
	_upright(to)
	if to.length() < 1.3:
		_strike(_target)


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


## Dead: limp, all of it a ragdoll, falling like a sack; the host's: now
## and then a meat chunk. Gone after CORPSE_TIME.
func _die(host: bool) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	gravity_scale = 1.0
	if _buzz:
		_buzz.stop()
	if _gaze:
		_gaze.queue_free()
	if _ragdoll:
		_ragdoll.physical_bones_start_simulation()
		for node in _ragdoll.get_children():
			var bone := node as PhysicalBone3D
			if bone:
				bone.collision_layer = 1 << 3
				bone.collision_mask = 1
	if host and randf() < MEAT_CHANCE:
		CarryItem.spawn_meat(get_tree().current_scene, global_position, MEAT_WEIGHT, false)
	get_tree().create_timer(CORPSE_TIME).timeout.connect(queue_free)
