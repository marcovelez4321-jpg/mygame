class_name PlayerSound
extends Node

## Wires the player's existing signals to sound -- attach as a sibling of
## WeaponController on the player body. Every event here already exists
## (jumped/dashed/wall_jumped on PlayerMovement, damaged/died on Health,
## gory_kill_nearby on WeaponController); this file adds nothing to
## simulation, it only listens (Rule 1) -- exactly like camera_juice.gd
## already does for the same events. Co-op ready: every sound goes through
## SoundPlayer.play_for_owner(), so the local player hears their own sounds
## in their ears and a remote player's come from where that player stands.
## The screen-splash sting is local-only feedback, so it only plays for you.
##
## To give the player footsteps/jump/land/etc a voice: assign the SoundEvent
## exports below in the Inspector.

@export_group("Movement")
@export var jump_sound: SoundEvent
@export var land_sound: SoundEvent
@export var footstep_sound: SoundEvent
## Distance (meters) between footsteps -- naturally speeds up/slows down with
## actual move speed since it's distance-based, not a fixed timer.
@export var footstep_distance: float = 1.8
@export var dash_sound: SoundEvent
@export var wall_jump_sound: SoundEvent
@export var mantle_sound: SoundEvent

@export_group("Combat")
@export var damage_sound: SoundEvent
@export var death_sound: SoundEvent
## A kill close enough to splash blood on your own screen (see
## weapon_controller.gd's gory_kill_nearby/CLOSE_KILL_RANGE) -- a beefier
## "that one was messy" sting, separate from the plain hit marker.
@export var gory_kill_sound: SoundEvent

@onready var _player: PlayerMovement = get_parent() as PlayerMovement
@onready var _health: Health = _player.get_node("Health") as Health
@onready var _weapons: WeaponController = _player.get_node("WeaponController") as WeaponController

var _distance_since_step: float = 0.0
var _last_position: Vector3
var _was_on_floor: bool = true


func _ready() -> void:
	_last_position = _player.global_position
	_player.jumped.connect(_on_jumped)
	_player.dashed.connect(_on_dashed)
	_player.wall_jumped.connect(_on_wall_jumped)
	_player.mantled.connect(_on_mantled)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_weapons.gory_kill_nearby.connect(_on_gory_kill_nearby)


func _physics_process(_delta: float) -> void:
	var on_floor := _player.is_on_floor()
	if on_floor and not _was_on_floor:
		SoundPlayer.play_for_owner(land_sound, _player)
	_was_on_floor = on_floor

	if on_floor:
		_distance_since_step += _player.global_position.distance_to(_last_position)
		if _distance_since_step >= footstep_distance:
			_distance_since_step = 0.0
			SoundPlayer.play_for_owner(footstep_sound, _player)
	_last_position = _player.global_position


func _on_jumped() -> void:
	SoundPlayer.play_for_owner(jump_sound, _player)


func _on_dashed() -> void:
	SoundPlayer.play_for_owner(dash_sound, _player)


func _on_wall_jumped() -> void:
	SoundPlayer.play_for_owner(wall_jump_sound, _player)


func _on_mantled() -> void:
	SoundPlayer.play_for_owner(mantle_sound, _player)


func _on_damaged(_amount: float, _attacker_id: int) -> void:
	SoundPlayer.play_for_owner(damage_sound, _player)


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	SoundPlayer.play_for_owner(death_sound, _player)


func _on_gory_kill_nearby() -> void:
	if _player.is_multiplayer_authority():
		SoundPlayer.play_2d(gory_kill_sound)
