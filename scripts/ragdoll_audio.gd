class_name RagdollAudio
extends Node

## Everything a dead body sounds like (Rule 7, AUDIO_DESIGN.md section 3D).
## Attach as a child of the Enemy, next to EnemyRagdoll.
##
## Valve's base: every ragdoll bone is a physics object with a material
## (flesh, or skull for the head), and each of its hits goes through
## PhysicsAudio -- speed gate, per-bone cooldown, speed² volume, soft/hard,
## merged per frame. On top of that, our layers:
##   - the drop: one heavy body-fall the first time the torso lands hard
##   - per-bone variety: limbs, torso and head use different materials
##   - ground layer: the floor's own impact sound under the body's
##   - drag loop: a looping scrape while the torso slides along the floor
##   - bone crunch: an extra crack on only the very hardest hits
##
## Hits are read from each bone's contact reports (switched on at death)
## rather than signals: PhysicalBone3D has no body_entered signal the way
## RigidBody3D does.
## Rule 1 (co-op): presentation only -- every client hears its own bodies.

@export_group("Materials")
@export var torso_surface: SurfaceAudio = preload("res://audio/surfaces/flesh.tres")
@export var limb_surface: SurfaceAudio = preload("res://audio/surfaces/flesh_limb.tres")
@export var head_surface: SurfaceAudio = preload("res://audio/surfaces/skull.tres")
## What level geometry counts as until materials are read from the level's
## textures. A body landing on it plays this as the ground layer.
@export var world_surface: SurfaceAudio = preload("res://audio/surfaces/concrete.tres")

@export_group("Impacts")
## Seconds before the same bone can make another impact sound (Source: 0.05).
@export var bone_cooldown: float = 0.05
## How loud the ground layer is next to the body's own impact (0..1).
@export_range(0.0, 1.0, 0.05) var ground_layer_volume: float = 0.6

@export_group("Drop")
@export var drop_sound: SoundEvent = preload("res://audio/events/body/body_drop_heavy.tres")
## The torso has to land at least this fast (m/s) to count as the drop.
@export var drop_min_speed: float = 3.0

@export_group("Bone crunch")
@export var crunch_sound: SoundEvent = preload("res://audio/events/body/body_bone_crunch.tres")
## Only hits at least this fast (m/s) crunch -- keep it rare.
@export var crunch_min_speed: float = 7.0
@export var crunch_cooldown: float = 0.4

@export_group("Drag")
## Torso sliding speed (m/s) where the drag loop starts, and where it's full
## volume. Volume follows speed squared in between, like Source's scrapes.
@export var drag_min_speed: float = 1.0
@export var drag_full_speed: float = 5.0
## Seconds the drag keeps going after the sliding stops (Source: 0.1).
@export var drag_release_time: float = 0.1

## How many contacts each bone reports per physics step.
const CONTACTS_PER_BONE := 4

@onready var _enemy: Enemy = get_parent() as Enemy

var _active := false
var _bones: Array[PhysicalBone3D] = []
## Per-bone state, keyed by the bone.
var _surface_of: Dictionary = {}
var _last_impact: Dictionary = {}
var _prev_speed: Dictionary = {}
var _is_torso: Dictionary = {}
var _hips: PhysicalBone3D

var _dropped := false
var _last_crunch := -INF
var _drag_player: AudioStreamPlayer3D
var _drag_base_db := 0.0
var _drag_last_time := -INF


func _ready() -> void:
	_enemy.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Enemy.State) -> void:
	if state == Enemy.State.DEAD:
		_start()


func _start() -> void:
	for node in _enemy.find_children("Physical Bone *", "PhysicalBone3D", true, false):
		var bone := node as PhysicalBone3D
		var bone_name := String(bone.bone_name)
		_bones.append(bone)
		_surface_of[bone] = _surface_for(bone_name)
		_is_torso[bone] = bone_name in ["Hips", "Spine", "Chest", "UpperChest"]
		_last_impact[bone] = -INF
		_prev_speed[bone] = bone.linear_velocity.length()
		if bone_name == "Hips":
			_hips = bone
		PhysicsServer3D.body_set_max_contacts_reported(bone.get_rid(), CONTACTS_PER_BONE)
	_active = not _bones.is_empty()


## Valve's $jointsurfaceprop idea: the head gets its own material, limbs
## another, everything else is the torso's flesh.
func _surface_for(bone_name: String) -> SurfaceAudio:
	if bone_name == "Head":
		return head_surface
	for limb in ["Arm", "Leg", "Foot", "Hand", "Shoulder"]:
		if limb in bone_name:
			return limb_surface
	return torso_surface


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var drag_speed := 0.0
	var drag_hit: SurfaceAudio = null

	for bone: PhysicalBone3D in _bones:
		var speed := bone.linear_velocity.length()
		var prev_speed: float = _prev_speed[bone]
		_prev_speed[bone] = speed
		var state := PhysicsServer3D.body_get_direct_state(bone.get_rid())
		if state == null:
			continue

		# Strongest contact this step against anything that isn't this same
		# body -- a limb resting on its own torso isn't an impact.
		var hit_object: Object = null
		var hit_impulse := 0.0
		var hit_position := Vector3.ZERO
		for i in state.get_contact_count():
			var other := state.get_contact_collider_object(i)
			if other == null or _surface_of.has(other):
				continue
			var impulse := state.get_contact_impulse(i).length()
			if hit_object == null or impulse > hit_impulse:
				hit_object = other
				hit_impulse = impulse
				hit_position = state.get_contact_local_position(i)
		if hit_object == null:
			continue
		var hit_surface := _surface_of_object(hit_object)

		if _is_torso[bone]:
			var slide := Vector2(bone.linear_velocity.x, bone.linear_velocity.z).length()
			if slide > drag_speed:
				drag_speed = slide
				drag_hit = hit_surface

		# How hard it hit: the speed change the contact caused (impulse /
		# mass), or how much speed the bone just lost, whichever is bigger.
		# Resting contact barely registers, so it stays under the speed gate.
		var impact_speed := maxf(hit_impulse / bone.mass, prev_speed - speed)
		if impact_speed < PhysicsAudio.MIN_SPEED or now - float(_last_impact[bone]) < bone_cooldown:
			continue
		_last_impact[bone] = now
		_play_impact(bone, hit_object, hit_surface, impact_speed, hit_position, now)

	_update_drag(drag_speed, drag_hit, now)


func _play_impact(bone: PhysicalBone3D, hit_object: Object, hit_surface: SurfaceAudio,
		speed: float, position: Vector3, now: float) -> void:
	var tree := get_tree()
	var surface: SurfaceAudio = _surface_of[bone]
	PhysicsAudio.report_impact(tree, surface, hit_surface, speed, position)

	# Ground layer: the floor gets its own voice -- played as the floor being
	# struck by flesh, so it picks its soft or hard sound the Valve way too.
	# Skipped when it landed on another body: that's already flesh on flesh.
	if hit_object is not PhysicalBone3D:
		PhysicsAudio.report_impact(tree, hit_surface, surface, speed, position, ground_layer_volume)

	var world := tree.current_scene
	if not _dropped and _is_torso[bone] and speed >= drop_min_speed:
		_dropped = true
		SoundPlayer.play_3d(drop_sound, position, world)
	if speed >= crunch_min_speed and now - _last_crunch >= crunch_cooldown:
		_last_crunch = now
		SoundPlayer.play_3d(crunch_sound, position, world)


## Another corpse is flesh; anything carrying a "surface_audio" meta uses
## that; everything else is the level, which is world_surface for now.
func _surface_of_object(object: Object) -> SurfaceAudio:
	if object is PhysicalBone3D:
		return torso_surface
	if object.has_meta(&"surface_audio"):
		return object.get_meta(&"surface_audio") as SurfaceAudio
	return world_surface


## Source-style friction sound: one looping scrape per body that starts when
## the torso slides along something, follows the slide speed (squared, like
## Source's energy² scrape volume) and stops shortly after the slide ends.
func _update_drag(speed: float, hit: SurfaceAudio, now: float) -> void:
	if speed >= drag_min_speed and hit != null:
		_drag_last_time = now
		if _drag_player == null:
			var follow: Node3D = _hips if _hips != null else _bones[0]
			_drag_player = SoundPlayer.play_loop_3d(torso_surface.scrape_sound(hit), follow)
			if _drag_player:
				_drag_base_db = _drag_player.volume_db
		if _drag_player:
			var volume := clampf(pow(speed / drag_full_speed, 2.0), 1.0 / 128.0, 1.0)
			_drag_player.volume_db = _drag_base_db + linear_to_db(volume)
	elif _drag_player and now - _drag_last_time > drag_release_time:
		_drag_player.stop()
		_drag_player.queue_free()
		_drag_player = null
