class_name DeepmawCrawler
extends CharacterBody3D

## A smaller deepmaw that doesn't burrow: it slithers along the floor on the
## DEEPMAW model's own animations ("Glide" to move, sped up with its pace)
## and fights with the model's melee attacks -- "BITE" at anything in front
## of its jaws, "TAIL ATTACK" at anything by its tail -- flinching ("hit
## reaction") when shot and dying with "dead". Half the length of the
## boss's burrowing escorts (Deepmaw). It moves where its pack says
## (DeepmawPack -- the rats' pack behaviour) and guards a barnacle clump.
## Rule 1 (co-op): the host moves it and deals the damage.

enum State { MOVE, ATTACK, DEAD }

@export var model_scene: PackedScene = preload("res://art/DEEPMAW- Retro psx  monster/DEEPMAW.fbx")
@export var body_material: Material
@export var teeth_material: Material

@export_group("Body")
## Head to tail, meters (the model is sized to it).
@export var body_length: float = 2.5
@export var acceleration: float = 20.0
## How fast it turns to face where it's going (higher = quicker).
@export var turn_rate: float = 6.0
## The slither ("Glide") plays this fast at full pace, slower as it slows.
@export var glide_speed: float = 1.4
## How high its spine rides above the floor, as a share of its length (its
## body's radius, about) -- raise it if it sinks into the floor, lower it if
## it floats.
@export var belly_height: float = 0.08

@export_group("Melee")
## A target within bite_range of its jaws, in front of it: BITE. Within
## tail_range of its tail: TAIL ATTACK. The hit lands hit_delay seconds into
## the attack; it can't attack again for attack_cooldown.
@export var bite_damage: float = 14.0
@export var bite_range: float = 1.0
@export var tail_damage: float = 10.0
@export var tail_range: float = 1.2
@export var hit_delay: float = 0.35
@export var attack_cooldown: float = 1.1
@export var knockback: float = 6.0

@export_group("Look")
@export var blood_color: Color = Color(0.55, 0.03, 0.03)
## Dying: the "dead" animation plays out, then it swells (swell_amount
## bigger, throbbing, over swell_time seconds) and bursts in a blood
## explosion -- death_gore big, a splat of swell_splat across the floor.
@export var swell_amount: float = 0.45
@export var swell_time: float = 0.45
@export var death_gore: float = 3.0
@export var swell_splat: float = 3.0
@export var burst_sound: SoundEvent
## Past this far from the camera its animation is paused (it still moves).
@export var animate_distance: float = 45.0
@export var bite_sound: SoundEvent
@export var death_sound: SoundEvent

## Set by DeepmawPack.
var pack: DeepmawPack
var slot := Vector2.RIGHT
var slot_radius := 1.5
var rhythm_seed := 0.0
var speed_scale := 1.0
## What the pack wants it doing (horizontal m/s).
var desired_velocity := Vector3.ZERO

var _state := State.MOVE
var _facing := Vector3.FORWARD
var _attack_left := 0.0
var _attack_length := 1.0
var _cooldown := 0.0
var _hit_done := false
var _attack_kind := ""
var _lod_timer := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _anim_names := {}
var _current_clip := ""
var _gravity := 9.8

@onready var health: Health = $Health


func _ready() -> void:
	add_to_group("enemies")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float
	rhythm_seed = randf() * 1000.0
	speed_scale = randf_range(0.9, 1.1)
	_facing = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D)
	_build_model()
	_fit_hitbox()
	_face_now()


## The model: turned nose to -Z, centred on this body along its length,
## belly on the floor, sized to body_length -- worked out from its bones.
func _build_model() -> void:
	_model = model_scene.instantiate() as Node3D
	add_child(_model)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.get_surface_override_material_count():
			var original := mesh.get_active_material(surface)
			var label := original.resource_name.to_lower() if original else ""
			if original is BaseMaterial3D and (original as BaseMaterial3D).albedo_texture:
				label += (original as BaseMaterial3D).albedo_texture.resource_path.to_lower()
			var teeth := "diente" in label
			if teeth and teeth_material:
				mesh.set_surface_override_material(surface, teeth_material)
			elif not teeth and body_material:
				mesh.set_surface_override_material(surface, body_material)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in _anim.get_animation_list():
			var lower := String(clip).to_lower()
			for key in ["glide", "bite", "tail attack", "hit reaction", "dead"]:
				if lower.ends_with(key):
					_anim_names[key] = clip
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var head_bone := skeleton.find_bone("Bone")
	if head_bone < 0:
		return
	var tail_bone := head_bone
	while not skeleton.get_bone_children(tail_bone).is_empty():
		tail_bone = skeleton.get_bone_children(tail_bone)[0]
	var to_model := _model.global_transform.affine_inverse() * skeleton.global_transform
	var head := to_model * skeleton.get_bone_global_rest(head_bone).origin
	var tail := to_model * skeleton.get_bone_global_rest(tail_bone).origin
	var length := head.distance_to(tail) * 1.15 # plus the jaws past the head bone
	var scale_by := body_length / maxf(length, 0.0001)
	var nose := (head - tail).normalized()
	var side := nose.cross(Vector3.UP).normalized()
	var axes := Basis(side, side.cross(nose), -nose) # the model's own right/up/back
	var turn := axes.inverse()
	var rig := turn.scaled(Vector3.ONE * scale_by)
	var middle := (head + tail) * 0.5
	# Centred on this body along its length, and lifted so its belly is on
	# the floor: its spine (head-to-tail bone line, now through the origin)
	# one body radius up. (Measured from the bones, not the mesh's bounding
	# box: on this skinned FBX the mesh's own box isn't in the same units as
	# where it's drawn -- that put them floating high above their hitboxes.)
	_model.transform = Transform3D(rig, -(rig * middle) + Vector3.UP * body_length * belly_height)
	_play("glide", true)


## A capsule along its body, a little thicker than it, so it's easy to shoot.
func _fit_hitbox() -> void:
	var shape := $CollisionShape3D as CollisionShape3D
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_length * 0.16
	capsule.height = body_length
	shape.shape = capsule
	shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.UP * capsule.radius)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return # the death sequence (_on_died) plays out on its own
	if not multiplayer.is_server():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _state == State.ATTACK:
		_attack_step(delta)
		desired_velocity = Vector3.ZERO
	else:
		_maybe_attack()
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired_velocity, acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if flat.length_squared() > 0.04 and _state != State.ATTACK:
		_facing = _facing.slerp(flat.normalized(), 1.0 - exp(-turn_rate * delta)).normalized()
	elif _state == State.ATTACK and pack and is_instance_valid(pack.target) and _attack_kind == "bite":
		var to := pack.target.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			_facing = _facing.slerp(to.normalized(), 1.0 - exp(-turn_rate * 1.5 * delta)).normalized()
	_face_now()


func _face_now() -> void:
	global_basis = Basis.looking_at(Vector3(_facing.x, 0.0, _facing.z).normalized(), Vector3.UP)


func _process(delta: float) -> void:
	if _anim == null:
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var camera := get_viewport().get_camera_3d()
		_anim.active = camera == null or camera.global_position.distance_to(global_position) < animate_distance
	# The slither keeps pace with how fast it's going.
	if _state == State.MOVE and _current_clip == "glide":
		var pace := Vector2(velocity.x, velocity.z).length() / maxf(pack.crawler_speed if pack else 4.0, 0.1)
		_anim.speed_scale = lerpf(0.3, glide_speed, clampf(pace, 0.0, 1.0))
	else:
		_anim.speed_scale = 1.0


## Its target in reach: a bite at it in front of its jaws, or a swipe of its
## tail at it by its tail.
func _maybe_attack() -> void:
	if _cooldown > 0.0 or pack == null or not is_instance_valid(pack.target):
		return
	var target := pack.target
	var forward := -global_basis.z
	var jaws := global_position + forward * body_length * 0.5
	var tail := global_position - forward * body_length * 0.5
	var at := target.global_position
	if _flat_distance(jaws, at) < bite_range and (at - global_position).dot(forward) > 0.0:
		_start_attack("bite")
	elif _flat_distance(tail, at) < tail_range and _anim_names.has("tail attack"):
		_start_attack("tail attack")


func _start_attack(kind: String) -> void:
	_state = State.ATTACK
	_attack_kind = "bite" if kind == "bite" else "tail"
	_hit_done = false
	var clip_length := 1.0
	if _anim and _anim_names.has(kind):
		clip_length = _anim.get_animation(_anim_names[kind]).length
	_attack_left = clip_length
	_attack_length = clip_length
	_play(kind, false)


func _attack_step(delta: float) -> void:
	_attack_left -= delta
	if not _hit_done and _attack_length - _attack_left >= hit_delay:
		_hit_done = true
		_land_hit()
	if _attack_left <= 0.0:
		_state = State.MOVE
		_cooldown = attack_cooldown
		_play("glide", true)


## The bite or swipe lands -- on its target if it's still in reach.
func _land_hit() -> void:
	if pack == null or not is_instance_valid(pack.target):
		return
	var target := pack.target
	var forward := -global_basis.z
	var bite := _attack_kind == "bite"
	var from := global_position + forward * body_length * (0.5 if bite else -0.5)
	if _flat_distance(from, target.global_position) > (bite_range if bite else tail_range) * 1.3:
		return
	var target_health := target.get_node_or_null("Health") as Health
	if target_health:
		target_health.take_damage(bite_damage if bite else tail_damage, Health.NO_ATTACKER)
	var away := target.global_position - global_position
	away.y = 0.0
	if target.has_method("shove"):
		target.call("shove", away.normalized() * knockback + Vector3.UP * knockback * 0.3)
	if bite:
		BloodFX.spawn_impact(get_tree().current_scene, from + Vector3.UP * 0.4, forward, blood_color, 1.2)
		SoundPlayer.play_3d(bite_sound, from, get_tree().current_scene)


func _on_damaged(_amount: float, _attacker_id: int) -> void:
	if _state == State.DEAD:
		return
	HitFlash.flash(_model)
	if _state == State.MOVE:
		_play("hit reaction", false)
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if _state == State.MOVE:
				_play("glide", true))
	if pack:
		pack.threatened_by(get_meta("provoked_by") if has_meta("provoked_by") else null)


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	if _state == State.DEAD:
		return
	_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if pack:
		pack.forget(self)
	_play("dead", false)
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, global_position + Vector3.UP * 0.4, Vector3.UP, blood_color, 1.2)
	SoundPlayer.play_3d(death_sound, global_position, world)
	# The dying animation, then it swells -- three throbs, each fatter --
	# and bursts.
	var dying := 1.0
	if _anim and _anim_names.has("dead"):
		dying = _anim.get_animation(_anim_names["dead"]).length
	var rest := _model.scale
	var tween := create_tween()
	tween.tween_interval(dying)
	var pulse := swell_time / 6.0
	for i in 3:
		var amount := swell_amount * (i + 1) / 3.0
		tween.tween_property(_model, "scale", rest * (1.0 + amount), pulse).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(_model, "scale", rest * (1.0 + amount * 0.6), pulse).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_model, "scale", rest * (1.0 + swell_amount * 1.15), pulse * 0.7)
	tween.tween_callback(_burst)


## Pop: a blood explosion out of its whole length, a big splat on the floor,
## a wet crunch -- gone.
func _burst() -> void:
	var world := get_tree().current_scene
	var forward := -global_basis.z
	for k in 3:
		var at := global_position + forward * body_length * (float(k) - 1.0) * 0.35 + Vector3.UP * body_length * 0.15
		var out := (Vector3.UP + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))).normalized()
		BloodFX.spawn_impact(world, at, out, blood_color, death_gore)
	BloodFX.spawn_splatter(world, global_position + Vector3.UP * 0.05, Vector3.UP, swell_splat, blood_color)
	SoundPlayer.play_3d(burst_sound, global_position, world)
	queue_free()


func _play(key: String, loop: bool) -> void:
	if _anim == null or not _anim_names.has(key):
		return
	var clip: StringName = _anim_names[key]
	_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(clip, 0.15)
	_current_clip = key


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
