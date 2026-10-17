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

## Skimming up a hill (PlayerMovement.skim_speed): a loop while it lasts,
## louder and higher the faster you go, faded in and out, on the footsteps'
## bus at their level (the user's). Which one is the player's pick
## (GameSettings.skim_sound, Settings > Audio); in GameSettings.SkimSound's
## order -- empty: no file yet.
const SKIM_FILES := [
	"res://audio/universfield-worm-movement-277577.mp3", # Wet glide (the user's file)
	"", # Chitin skate
	"", # Wing flutter
]
const SKIM_FADE_IN := 0.08
const SKIM_FADE_OUT := 0.3
## A skim lasts at least this long (touches flicker on and off a hill).
const SKIM_HOLD := 0.15

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
var _skim_player: Node
var _skim_loaded := -1
var _skim_level := 0.0
var _skim_hold := 0.0


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
	# Skimming up a hill isn't landing (PlayerMovement.on_ground()), and
	# landings closer together than LAND_SOUND_GAP_MSEC play once.
	_update_skim(_delta)
	var on_floor := _player.on_ground()
	if on_floor and not _was_on_floor and Time.get_ticks_msec() - _land_sound_msec >= LAND_SOUND_GAP_MSEC:
		_land_sound_msec = Time.get_ticks_msec()
		SoundPlayer.play_for_owner(land_sound, _player)
	_was_on_floor = on_floor

	if on_floor:
		_distance_since_step += _player.global_position.distance_to(_last_position)
		if _distance_since_step >= footstep_distance:
			_distance_since_step = 0.0
			SoundPlayer.play_for_owner(footstep_sound, _player)
	_last_position = _player.global_position


## The skim loop: held on while you skim, faded out after.
func _update_skim(delta: float) -> void:
	var velocity := _player.velocity
	if _player.is_on_floor() and velocity.y > _player.skim_speed:
		_skim_hold = SKIM_HOLD
	else:
		_skim_hold = maxf(_skim_hold - delta, 0.0)
	var wanted := 1.0 if _skim_hold > 0.0 else 0.0
	_skim_level = move_toward(_skim_level, wanted, delta / (SKIM_FADE_IN if wanted > _skim_level else SKIM_FADE_OUT))
	if _skim_level <= 0.0:
		if _skim_player and _skim_player.get("playing"):
			_skim_player.call("stop")
		return
	if not _skim_ready():
		return
	var speed := clampf(velocity.length() / maxf(_player.speed_cap, 0.1), 0.0, 1.0)
	_skim_player.set("volume_db", linear_to_db(_skim_level * lerpf(0.6, 1.0, speed)))
	_skim_player.set("pitch_scale", lerpf(0.9, 1.2, speed))
	if not _skim_player.get("playing"):
		# From somewhere new in it each time, so it never starts the same.
		var stream: AudioStream = _skim_player.get("stream")
		_skim_player.call("play", randf() * maxf(stream.get_length() - 1.0, 0.0))


## The loop's player, with the picked sound loaded (false: no file for it).
func _skim_ready() -> bool:
	var pick: int = GameSettings.skim_sound
	if pick == _skim_loaded and _skim_player:
		return true
	var path: String = SKIM_FILES[pick] if pick < SKIM_FILES.size() else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var stream := load(path) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)
	if _skim_player == null:
		# Your own in your ears; someone else's from where they are.
		_skim_player = AudioStreamPlayer.new() if _player.is_multiplayer_authority() else AudioStreamPlayer3D.new()
		_skim_player.set("bus", "Surface")
		_player.add_child(_skim_player)
	_skim_player.call("stop")
	_skim_player.set("stream", stream)
	_skim_loaded = pick
	return true


## Jumps closer together than this play one sound (the user's: bhopping up a
## hill spammed it).
const JUMP_SOUND_GAP_MSEC := 400 # the user's (was 600)
## Landings closer together than this play one sound.
const LAND_SOUND_GAP_MSEC := 600
var _jump_sound_msec := -100000
var _land_sound_msec := -100000


func _on_jumped() -> void:
	var now := Time.get_ticks_msec()
	if now - _jump_sound_msec < JUMP_SOUND_GAP_MSEC:
		return
	_jump_sound_msec = now
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


func _on_gory_kill_nearby(_blood_color: Color) -> void:
	if _player.is_multiplayer_authority():
		SoundPlayer.play_2d(gory_kill_sound)
