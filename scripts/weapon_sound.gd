class_name WeaponSound
extends Node

## Wires WeaponController's existing signals to sound -- attach as a CHILD of
## WeaponController on the player body. Per-weapon sounds (fire, reload,
## switch) live on WeaponData itself (see weapon_data.gd's Sound group), the
## same place its damage/recoil/viewmodel already live, so a new weapon needs
## no new sound code -- just fill in its .tres. The sounds below aren't
## per-weapon, so they stay here instead.
##
## Rule 1: presentation only. Your own shots/hits play non-positional
## (play_2d -- see sound_player.gd's own comment on why). Once other players
## exist, THEIR shots should play positional (play_3d at their muzzle)
## instead -- flagged here for that future hookup, not built yet since
## there's no networking to receive another player's shot event from.

@export_group("Sounds")
@export var hit_marker_sound: SoundEvent
@export var kill_confirm_sound: SoundEvent
## Plays on top of the hit/kill sound when the shot was a headshot.
@export var headshot_sound: SoundEvent
## The instant, dramatic neck-shot kill sting (see weapon_controller.gd's
## artery_hit_radius/_spawn_artery_spurt) -- distinct from a normal kill so it
## reads as the special case it is. Non-positional, like the rest of this
## file's sounds (see the class comment on why).
@export var artery_kill_sound: SoundEvent
## A SUSTAINED, POSITIONAL sound at the wound itself -- wet spurting/gurgling
## -- parented directly onto the neck bone (see _on_artery_kill()) so it
## keeps coming from the right spot as the ragdoll falls and settles, exactly
## like BloodFX's own particle spray does. Separate from artery_kill_sound
## above: that one is an instant confirm sting, this one is ambience that
## lingers at the corpse.
@export var artery_spurt_sound: SoundEvent
## How long the spurt sound plays before stopping -- matches
## weapon_controller.gd's own blood-spurt duration (7s) by default, but kept
## as its own number here rather than read from there: presentation owns its
## own timing, the same separation camera_juice.gd's decay constants keep
## from the systems that trigger them.
@export var artery_spurt_duration: float = 7.0
@export var pickup_sound: SoundEvent

@onready var _weapons: WeaponController = get_parent() as WeaponController


func _ready() -> void:
	_weapons.shot_fired.connect(_on_shot_fired)
	_weapons.reload_started.connect(_on_reload_started)
	_weapons.weapon_switched.connect(_on_weapon_switched)
	_weapons.hit_confirmed.connect(_on_hit_confirmed)
	_weapons.artery_kill.connect(_on_artery_kill)
	_weapons.picked_up.connect(_on_picked_up)


func _on_shot_fired() -> void:
	var weapon := _weapons.current_weapon()
	if weapon:
		SoundPlayer.play_2d(weapon.fire_sound)


func _on_reload_started(_duration: float) -> void:
	var weapon := _weapons.current_weapon()
	if weapon:
		SoundPlayer.play_2d(weapon.reload_sound)


func _on_weapon_switched(weapon: WeaponData, draw_time: float) -> void:
	# draw_time is 0 for the very first weapon at spawn -- no switch sound
	# for just appearing.
	if weapon and draw_time > 0.0:
		SoundPlayer.play_2d(weapon.switch_sound)


func _on_hit_confirmed(killed: bool, kind: WeaponController.HitKind) -> void:
	SoundPlayer.play_2d(kill_confirm_sound if killed else hit_marker_sound)
	if kind == WeaponController.HitKind.HEADSHOT:
		SoundPlayer.play_2d(headshot_sound)


func _on_artery_kill(bone: Node3D) -> void:
	SoundPlayer.play_2d(artery_kill_sound)

	var spurt_player := SoundPlayer.play_loop_3d(artery_spurt_sound, bone)
	if spurt_player == null:
		return # stub event, no audio assigned yet
	# Straight to the player's own methods, not a lambda: if the corpse is
	# removed first, the sound player is freed with it and these connections
	# vanish instead of firing into a freed node. stop() doesn't emit
	# `finished`, so the loop doesn't restart itself before queue_free().
	var timer := get_tree().create_timer(artery_spurt_duration)
	timer.timeout.connect(spurt_player.stop)
	timer.timeout.connect(spurt_player.queue_free)


func _on_picked_up(_weapon: WeaponData, _ammo_type: WeaponData.AmmoType, _ammo_amount: int) -> void:
	SoundPlayer.play_2d(pickup_sound)
