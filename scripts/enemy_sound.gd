class_name EnemySound
extends Node

## Wires an Enemy's existing signals to sound -- attach as a sibling of
## EnemyAnimator. Every event here already exists (state_changed,
## attack_started); this file adds nothing to the enemy's own logic, it just
## listens, exactly like EnemyAnimator does for animation and HitFlash does
## for the hit-white-flash. Rule 1: pure presentation, each client's own copy
## of this enemy reacts to the SAME host-driven state changes independently,
## so sound needs nothing sent over the network.
##
## To give an enemy a voice: assign the SoundEvent exports below in the
## Inspector. Leave one empty and that sound just doesn't play -- no code
## required either way.

@export_group("Sounds")
## Loops for as long as the enemy is alive -- its constant "I'm here"
## presence (breathing, growling, a mechanical hum). Stops the instant it dies.
@export var idle_sound: SoundEvent
@export var hurt_sound: SoundEvent
@export var death_sound: SoundEvent
## Plays on attack_started -- the wind-up, not when the hit lands (see
## enemy.gd's own comment on that signal). Covers both a melee swing and a
## gunner's shot, since both fire the same signal; give a gunner variant's
## own EnemySound node a distinct SoundEvent in its scene if you want the
## gunshot to sound different from a melee swing.
@export var attack_sound: SoundEvent
## A gunner's gunshot -- plays on every shot it fires (enemy.gd's shot_fired),
## once per bullet in a burst. Unused by melee enemies.
@export var shot_sound: SoundEvent
## One-shot per footstep, spaced out by distance travelled (not a timer), so
## it naturally speeds up/slows down with the enemy's own move_speed instead
## of needing separate tuning.
@export var footstep_sound: SoundEvent
@export var footstep_distance: float = 1.4

@onready var _enemy: Enemy = get_parent() as Enemy

var _idle_player: AudioStreamPlayer3D
var _distance_since_step: float = 0.0
var _last_position: Vector3


func _ready() -> void:
	_last_position = _enemy.global_position
	_enemy.state_changed.connect(_on_state_changed)
	_enemy.attack_started.connect(_on_attack_started)
	_enemy.shot_fired.connect(_on_shot_fired)
	_start_idle_loop()


func _physics_process(_delta: float) -> void:
	if _enemy.get_state() == Enemy.State.DEAD:
		return
	var moved := _enemy.global_position.distance_to(_last_position)
	_last_position = _enemy.global_position
	if not _enemy.is_on_floor():
		return # airborne (a lunge mid-burst, or falling) doesn't leave footsteps
	_distance_since_step += moved
	if _distance_since_step >= footstep_distance:
		_distance_since_step = 0.0
		SoundPlayer.play_3d(footstep_sound, _enemy.global_position, _enemy.get_tree().current_scene)


func _on_state_changed(state: Enemy.State) -> void:
	if state == Enemy.State.PAIN:
		SoundPlayer.play_3d(hurt_sound, _enemy.global_position, _enemy.get_tree().current_scene)
	elif state == Enemy.State.DEAD:
		SoundPlayer.play_3d(death_sound, _enemy.global_position, _enemy.get_tree().current_scene)
		_stop_idle_loop()


func _on_attack_started() -> void:
	SoundPlayer.play_3d(attack_sound, _enemy.global_position, _enemy.get_tree().current_scene)


func _on_shot_fired(_end_point: Vector3) -> void:
	SoundPlayer.play_3d(shot_sound, _enemy.global_position, _enemy.get_tree().current_scene)


func _start_idle_loop() -> void:
	_idle_player = SoundPlayer.play_loop_3d(idle_sound, _enemy)


func _stop_idle_loop() -> void:
	if is_instance_valid(_idle_player):
		_idle_player.stop()
		_idle_player.queue_free()
		_idle_player = null
