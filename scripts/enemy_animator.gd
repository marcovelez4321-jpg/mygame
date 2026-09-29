class_name EnemyAnimator
extends Node

## Plays the right animation for whatever state the enemy is in. Attach as a
## child of the Enemy. Presentation only: it listens to the enemy's
## state_changed signal and never changes gameplay (Rule 1: in co-op each
## player's game runs its own copy from the shared state).
##
## Each state has a LIST of clips. Each enemy picks one from each list when
## it spawns, so a crowd doesn't all move identically. The pick is seeded
## from the enemy's unique node path, so in co-op both players' games choose
## the same variant for the same enemy with nothing sent over the network.
##
## Death: the death clip plays once and the body holds its last pose.

@export_group("Shared animation library")
## One file holding every clip (idle, walk, attack, hurt, ...). It's added to
## whatever model this enemy uses when it spawns, so swapping in a different
## character needs no animation setup at all, as long as that character was
## imported with the same Bone Map and Skeleton Name (GeneralSkeleton).
@export var animation_library: AnimationLibrary
## The prefix the clips get, so a clip called "walk" is played as "moves/walk".
@export var library_name: String = "moves"

@export_group("Animation names")
## Exact names shown in the AnimationPlayer's animation list. Add as many as
## you like per state; names that don't exist are ignored. To test before
## loading real clips, use "mixamo_com", the clip baked into the character.
@export var idle_animations: Array[String] = ["moves/idle"]
@export var walk_animations: Array[String] = ["moves/walk"]
@export var attack_animations: Array[String] = ["moves/attack"]
@export var hurt_animations: Array[String] = ["moves/hurt"]
## Leave this empty while the ragdoll handles death (EnemyRagdoll).
@export var die_animations: Array[String] = []

@export_group("Variety")
## false: each enemy keeps the variant it picked at spawn.
## true: picks a fresh random variant every time the state starts.
@export var reroll_each_time: bool = false

@export_group("Timing")
## Seconds spent smoothly blending from one animation into the next.
@export var blend_time: float = 0.15
## Playback speed of the hurt clip (1.0 = normal). If the flinch looks cut
## short, don't slow the clip: raise pain_time on the Enemy to about the
## clip's length instead.
@export var hurt_speed: float = 1.0

@onready var _enemy: Enemy = get_parent() as Enemy

## Decides which variant this enemy picks. 0 = choose randomly at spawn.
var variation_seed: int = 0

var _player: AnimationPlayer
var _rng := RandomNumberGenerator.new()
## The variant this enemy picked for each state: State -> animation name.
var _chosen: Dictionary = {}


func _ready() -> void:
	# The AnimationPlayer lives inside the imported model. find_child searches
	# the whole subtree, including nodes that came from the .fbx file.
	_player = _enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		push_warning("EnemyAnimator: no AnimationPlayer found under the enemy.")
		return

	# Attach the shared clips to this model's AnimationPlayer. The check lets
	# you still load the library by hand in a scene without it being added twice.
	if animation_library and not _player.has_animation_library(library_name):
		_player.add_animation_library(library_name, animation_library)

	# A fresh random seed for every enemy that spawns. Co-op hook: the host
	# will pick this number and send it with the spawn message; the other
	# player's copy sets variation_seed before this runs, so both games
	# choose identical variants without syncing animations.
	if variation_seed == 0:
		variation_seed = randi()
	_rng.seed = variation_seed
	for state in Enemy.State.values():
		_chosen[state] = _pick(_animations_for(state))

	_enemy.state_changed.connect(_on_state_changed)
	_enemy.attack_started.connect(_on_attack_started)
	_player.animation_finished.connect(_on_animation_finished)
	_on_state_changed(Enemy.State.IDLE)


func _on_state_changed(state: Enemy.State) -> void:
	# In attack range the enemy stands ready; the swing clip plays when a
	# swing actually begins (attack_started), once per swing.
	if state == Enemy.State.ATTACK:
		_play(Enemy.State.IDLE)
	else:
		_play(state)


func _on_attack_started() -> void:
	_play(Enemy.State.ATTACK)


## The swing clip is done: back to standing ready until the next swing.
func _on_animation_finished(_animation_name: StringName) -> void:
	if _enemy.get_state() == Enemy.State.ATTACK:
		_play(Enemy.State.IDLE)


func _play(state: Enemy.State) -> void:
	if reroll_each_time:
		_chosen[state] = _pick(_animations_for(state))
	var animation_name: String = _chosen.get(state, "")
	if animation_name.is_empty():
		return
	# Idle, walk/run, and the lunge burst (which reuses the walk/run clip --
	# see _animations_for()) repeat; attack, hurt and die play once.
	var repeats := state == Enemy.State.IDLE or state == Enemy.State.CHASE or state == Enemy.State.LUNGE
	_player.get_animation(animation_name).loop_mode = \
			Animation.LOOP_LINEAR if repeats else Animation.LOOP_NONE
	var speed := hurt_speed if state == Enemy.State.PAIN else 1.0
	_player.play(animation_name, blend_time, speed)


## Random clip from the list, ignoring names that don't exist. Empty string
## (and a warning) if none of them do.
func _pick(names: Array[String]) -> String:
	if names.is_empty():
		return "" # nothing listed on purpose (e.g. death is a ragdoll)
	var valid: Array[String] = []
	for animation_name in names:
		if _player.has_animation(animation_name):
			valid.append(animation_name)
		else:
			push_warning("EnemyAnimator: '%s' not found, skipping it." % animation_name)
	if valid.is_empty():
		push_warning("EnemyAnimator: none of these animations exist: %s" % [names])
		return ""
	return valid[_rng.randi() % valid.size()]


func _animations_for(state: Enemy.State) -> Array[String]:
	match state:
		Enemy.State.CHASE, Enemy.State.LUNGE:
			# LUNGE (the rusher's dash-in burst) has no clips of its own --
			# it's still fundamentally "moving fast toward the target", so it
			# reuses the same walk/run clips CHASE does. Without this case it
			# silently fell through to idle_animations below, which is
			# exactly the "slides at you really fast in an idle pose" bug --
			# the CharacterBody3D was actually moving at lunge_speed the
			# whole time, only the animation was wrong.
			return walk_animations
		Enemy.State.ATTACK:
			return attack_animations
		Enemy.State.PAIN:
			return hurt_animations
		Enemy.State.DEAD:
			return die_animations
	return idle_animations
