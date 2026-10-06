class_name RoachVisual
extends Node3D

## How a FlyingRoach looks and sounds -- presentation only (Rule 1): it reads
## the roach's facing, speed and state and never changes them, so in co-op
## each player's game animates and plays its own copy from the synced roach.
##
## Until there's a real model (set model_scene), it builds a placeholder
## low-poly roach out of simple shapes, wings and all.

@export_group("Model")
## The real roach model, when you have one. Empty = the placeholder. If it
## has an AnimationPlayer, its first animation loops (a wing-flap cycle).
@export var model_scene: PackedScene
## The spitter's own model, if it gets one. Empty = model_scene (or the
## spitter placeholder: yellower, with a swollen abdomen).
@export var spitter_model_scene: PackedScene
## Size of the model (real or placeholder). Keep the roach's collision
## sphere (roach.tscn, radius 0.22 x this) in step if you change it a lot.
@export var model_scale: float = 1.15
## Placeholder only: wing flaps per second.
@export var wing_beats_per_second: float = 22.0
## Spitter: how far (m) it rears back during the wind-up and lunges forward
## when the glob leaves -- the spit's visible kick.
@export var spit_rear_back: float = 0.12
@export var spit_jolt: float = 0.22

@export_group("Sound")
@export var buzz_sound: SoundEvent = preload("res://audio/events/enemy/roach_buzz.tres")
@export var dive_sound: SoundEvent = preload("res://audio/events/enemy/roach_dive.tres")
@export var bite_sound: SoundEvent = preload("res://audio/events/enemy/roach_bite.tres")
@export var death_sound: SoundEvent = preload("res://audio/events/enemy/roach_death.tres")
@export var spit_sound: SoundEvent = preload("res://audio/events/enemy/roach_spit.tres")
## A dead roach hitting the ground.
@export var splat_sound: SoundEvent = preload("res://audio/events/enemy/roach_splat.tres")
## The buzz rises in pitch as it gets close, like the manhack's engine
## (pitch 100 -> 160 within 512 units, about 13 m, in npc_manhack.cpp).
@export var buzz_pitch_far: float = 1.0
@export var buzz_pitch_near: float = 1.6
@export var buzz_pitch_range: float = 13.0

@onready var _roach: FlyingRoach = get_parent() as FlyingRoach

var _model: Node3D
var _wings: Array[Node3D] = []
var _buzz: AudioStreamPlayer3D
var _time := randf() * 10.0
var _tumble_axis := Vector3.RIGHT
var _spit_tween: Tween
var _splatted := false


func _ready() -> void:
	# The model waits for kind_decided: a roach only knows whether it's a
	# spitter a frame after spawning.
	_roach.kind_decided.connect(_build_model)
	_roach.state_changed.connect(_on_state_changed)
	_roach.bit_player.connect(_on_bit_player)
	_roach.spat.connect(_on_spat)
	_roach.splatted.connect(_on_splatted)
	# Deferred: the buzz player is added as a child of the roach, and the
	# roach is still busy setting up its own children during this _ready --
	# Godot refuses the add then, and the buzz never started.
	_start_buzz.call_deferred()


func _build_model(spitter: bool) -> void:
	var scene := spitter_model_scene if spitter and spitter_model_scene else model_scene
	if scene == null:
		_build_placeholder(spitter)
		return
	_model = scene.instantiate() as Node3D
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)
	var animator := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animator and not animator.get_animation_list().is_empty():
		var clip := animator.get_animation_list()[0]
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		animator.play(clip)


func _start_buzz() -> void:
	if _roach.get_state() != FlyingRoach.State.DEAD:
		_buzz = SoundPlayer.play_loop_3d(buzz_sound, _roach)


func _process(delta: float) -> void:
	_time += delta
	var state := _roach.get_state()
	if _splatted:
		pass # flat on the floor, done moving
	elif state == FlyingRoach.State.STUNNED or state == FlyingRoach.State.DEAD:
		rotate(_tumble_axis, (6.0 if state == FlyingRoach.State.DEAD else 9.0) * delta)
	elif _roach.facing.length_squared() > 0.01:
		var up := Vector3.UP if absf(_roach.facing.normalized().y) < 0.98 else Vector3.BACK
		global_basis = Basis.looking_at(_roach.facing, up)

	var flapping := state != FlyingRoach.State.DEAD
	for i in _wings.size():
		var flap := sin(_time * TAU * wing_beats_per_second) * 0.7 if flapping else -0.2
		_wings[i].rotation.z = flap if i == 0 else -flap
	_update_buzz_pitch()


func _update_buzz_pitch() -> void:
	if not is_instance_valid(_buzz):
		return
	var listener := PlayerMovement.local_player(get_tree())
	var closeness := 0.0
	if listener:
		closeness = 1.0 - clampf(listener.global_position.distance_to(global_position) / buzz_pitch_range, 0.0, 1.0)
	# A little extra pitch with speed, so a dive screams.
	var speed_boost := clampf(_roach.linear_velocity.length() / 13.0, 0.0, 1.0) * 0.15
	_buzz.pitch_scale = lerpf(buzz_pitch_far, buzz_pitch_near, closeness) + speed_boost


func _on_state_changed(state: FlyingRoach.State) -> void:
	match state:
		FlyingRoach.State.DIVE:
			SoundPlayer.play_3d(dive_sound, global_position, get_tree().current_scene)
		FlyingRoach.State.SPIT:
			# Rears back over the wind-up -- the tell that a glob is coming.
			_tween_model_z(spit_rear_back, _roach.spit_windup, Tween.EASE_OUT)
		FlyingRoach.State.STUNNED:
			_tumble_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		FlyingRoach.State.DEAD:
			_tumble_axis = Vector3(randf_range(-1.0, 1.0), 0.3, randf_range(-1.0, 1.0)).normalized()
			SoundPlayer.play_3d(death_sound, global_position, get_tree().current_scene)
			if is_instance_valid(_buzz):
				_buzz.stop()
				_buzz.queue_free()


func _on_bit_player() -> void:
	SoundPlayer.play_3d(bite_sound, global_position, get_tree().current_scene)


## Hit the ground dead: stops tumbling, lies flat facing a random way, and
## squashes -- flattened and spread out -- with a splat.
func _on_splatted() -> void:
	_splatted = true
	SoundPlayer.play_3d(splat_sound, global_position, get_tree().current_scene)
	global_basis = Basis(Vector3.UP, randf() * TAU)
	if _model == null:
		return
	var squashed := Vector3(model_scale * 1.3, model_scale * 0.3, model_scale * 1.15)
	create_tween().tween_property(_model, "scale", squashed, 0.08).set_ease(Tween.EASE_OUT)


## The glob's out: snaps forward (the model faces -Z), then settles back.
func _on_spat() -> void:
	SoundPlayer.play_3d(spit_sound, global_position, get_tree().current_scene)
	if _model == null:
		return
	if _spit_tween:
		_spit_tween.kill()
	_spit_tween = create_tween()
	_spit_tween.tween_property(_model, "position:z", -spit_jolt, 0.05).set_ease(Tween.EASE_OUT)
	_spit_tween.tween_property(_model, "position:z", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tween_model_z(z: float, duration: float, easing: Tween.EaseType) -> void:
	if _model == null:
		return
	if _spit_tween:
		_spit_tween.kill()
	_spit_tween = create_tween()
	_spit_tween.tween_property(_model, "position:z", z, duration).set_ease(easing)


## A fist-sized-and-then-some roach, facing -Z: a long, flattened brown
## shell, a dark head, two antennae and two clear wings that flap. The
## spitter is yellow-green with a swollen, faintly glowing acid sac at the
## back, so you can pick it out of a swarm.
func _build_placeholder(spitter: bool) -> void:
	_model = Node3D.new()
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)
	var shell_color := Color(0.42, 0.45, 0.1) if spitter else Color(0.32, 0.17, 0.07)
	var shell := _material(shell_color, 0.45)
	if spitter:
		var sac := _material(_roach.spit_color, 0.3)
		sac.emission_enabled = true
		sac.emission = _roach.spit_color
		sac.emission_energy_multiplier = 0.4
		var abdomen := SphereMesh.new()
		abdomen.radius = 0.1
		abdomen.height = 0.2
		abdomen.radial_segments = 8
		abdomen.rings = 4
		_part(_model, abdomen, sac, Vector3(0.0, 0.02, 0.2), Vector3.ZERO, Vector3(1.1, 0.8, 1.3))
	var dark := _material(Color(0.12, 0.07, 0.03), 0.6)
	var wing := _material(Color(0.75, 0.68, 0.5, 0.45), 0.2)
	wing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body := SphereMesh.new()
	body.radius = 0.12
	body.height = 0.24
	body.radial_segments = 8
	body.rings = 4
	_part(_model, body, shell, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.5, 1.7))
	var head := SphereMesh.new()
	head.radius = 0.06
	head.height = 0.12
	head.radial_segments = 6
	head.rings = 3
	_part(_model, head, dark, Vector3(0.0, 0.0, -0.22), Vector3.ZERO, Vector3.ONE)
	var antenna := BoxMesh.new()
	antenna.size = Vector3(0.008, 0.008, 0.28)
	_part(_model, antenna, dark, Vector3(-0.03, 0.03, -0.38), Vector3(0.35, -0.3, 0.0), Vector3.ONE)
	_part(_model, antenna, dark, Vector3(0.03, 0.03, -0.38), Vector3(0.35, 0.3, 0.0), Vector3.ONE)

	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.22, 0.004, 0.3)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.05, 0.0)
		_model.add_child(pivot)
		_part(pivot, wing_mesh, wing, Vector3(0.11 * side, 0.0, 0.03), Vector3.ZERO, Vector3.ONE)
		_wings.append(pivot)


func _part(parent: Node3D, mesh: Mesh, material: Material, offset: Vector3, angles: Vector3, size: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = offset
	part.rotation = angles
	part.scale = size
	parent.add_child(part)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
