class_name Viewmodel
extends Node3D

## The gun you see in first person. Attach under the player's camera.
## Presentation only (Rule 1, co-op): it just reacts to announcements from the
## WeaponController ("weapon switched", "shot fired") and never changes
## gameplay. Other players will eventually see a separate weapon model on your
## character's hands.
##
## Until a weapon has a real model (WeaponData.viewmodel_scene), a coloured
## block stands in for it.
##
## DEV TOOL (debug builds only, so it's absent from an exported game): press
## F2 while playing to nudge the equipped gun into place with the keyboard,
## then F3 to save the result into that weapon's .tres file.

## How far the gun dips, and how far it tilts, while switching.
const LOWERED_OFFSET := Vector3(0.0, -0.4, 0.0)
const LOWERED_TILT_DEGREES := -35.0
## How long the fire-recoil kick takes to recover. Magnitude itself
## (distance, rotation) is per-weapon now -- see WeaponData's
## recoil_kick_distance/recoil_kick_rotation_degrees.
const KICK_TIME := 0.1
## Muzzle rises on the kick too, easing back over a slightly longer beat than
## the position kick -- opposite sign from LOWERED_TILT_DEGREES (that one
## tips the barrel DOWN for the lower/raise animation; recoil tips it UP).
const KICK_ROTATION_TIME := 0.15
## Small per-shot randomization on the recoil kick (as a fraction of its own
## magnitude) so consecutive shots never look perfectly identical.
const KICK_JITTER := 0.25
## Flat multiplier on every weapon's recoil_kick_distance/_rotation_degrees --
## makes the visual kick read as more violent across the board without
## having to hand-retune each weapon's own .tres numbers individually.
const RECOIL_VISUAL_SCALE := 2.5


## -- Pump-rack reload (WeaponData.ReloadStyle.PUMP_RACK) --
## Turns the gun upright (muzzle pointing at the ceiling), racks it with a
## few quick, randomized up/down pumps, then settles back to normal -- a
## one-handed pump-shotgun feel, instead of the shared tilt-down-out-of-view
## reload every other weapon uses. Positive rotation_degrees.x = muzzle UP,
## same convention _on_shot_fired()'s recoil kick already uses -- 90 here
## means the barrel ends up pointing straight up, not tipped sideways.
const PUMP_UPRIGHT_PITCH_DEGREES := 90.0
## Negative -- pulls the gun DOWN while racking, not up. Positive Y here was
## raising it too high in the viewport.
const PUMP_UPRIGHT_LIFT := -0.15
## Negative Z is away from the camera (matches viewmodel_position's own
## convention, e.g. the shotgun's own -Z rest position) -- pushes the gun
## further from the player's face while racking, it was reading as too close.
const PUMP_UPRIGHT_PUSH_BACK := -0.12
## One heavy pump instead of several small ones -- bigger drop/wobble to
## carry the same "juice" in a single hit rather than spread thin over
## multiple cycles.
const PUMP_CYCLES := 1
const PUMP_SHAKE_MIN := 0.12
const PUMP_SHAKE_MAX := 0.18
const PUMP_ROTATION_WOBBLE := 22.0

## -- Grenade throw (WeaponData.throws_grenade), Half-Life 2 style --
## The arm draws back over the shoulder (up, back, tipped up), whips forward
## and down through the release, then drops out of view until the next
## grenade comes up. Positive rotation = tipped up, like the recoil kick.
const THROW_WINDUP_OFFSET := Vector3(0.06, 0.1, 0.18)
const THROW_WINDUP_TILT := 40.0
const THROW_SWING_OFFSET := Vector3(-0.08, -0.12, -0.3)
const THROW_SWING_TILT := -45.0
## Share of the release delay spent winding up; the rest is the swing.
const THROW_WINDUP_SHARE := 0.6
const THROW_FOLLOW_TIME := 0.2
const THROW_RAISE_TIME := 0.3
## Frames a newly made arms model stays hidden (see _attach_arms()).
const ARMS_REVEAL_FRAMES := 2

## How far in front of your eye the middle of a scope sits when aimed
## (WeaponData.aim_sight_node), in meters.
const AIM_EYE_DISTANCE := 0.25

## Dev tool speeds while a key is held.
const TUNE_MOVE_SPEED := 0.3     # meters per second
const TUNE_ROTATE_SPEED := 45.0  # degrees per second
const TUNE_SCALE_SPEED := 0.6    # fraction of current size per second

@export var weapons_path: NodePath

## The character whose arms you see in first person, whoever you're playing
## as -- every gun's hand placement is tuned to its arms, so switching your
## character never knocks the hands off the grips. Empty = your own
## character's arms.
@export_file("*.fbx") var arms_character: String = "res://art/characters/Characters_psx/Models/Male/Character_18_Police.fbx"

## Hide everything of the first-person arms model but the arms themselves
## (its torso would otherwise swing up into view as the gun tilts down).
@export var hide_torso: bool = true

@export_group("Sway")
## The gun lags behind when you turn and swings back. Cosmetic only.
@export var sway_enabled: bool = true
## How far the gun shifts (meters) per radian/second of turning.
@export var sway_position_amount: float = 0.012
## How far the gun tilts (degrees) per radian/second of turning.
@export var sway_rotation_amount: float = 1.5
## Sway never exceeds these, however hard you flick the mouse.
@export var sway_max_offset: float = 0.06
@export var sway_max_tilt_degrees: float = 8.0
## How quickly the gun catches up (higher = snappier, lower = floatier).
@export var sway_smoothing: float = 12.0

@onready var _weapons: WeaponController = get_node(weapons_path)

var _model: Node3D
## The gun's own model inside _model (without the arms).
var _gun: Node3D
## Thrown the grenade, waiting for the next one to come into the hand.
var _waiting_for_grenade := false
## The weapon whose model is in your hand right now (it can differ from the
## equipped one for a moment: a quick throw or an T / B heal shows its own).
var _shown_weapon: WeaponData
var _model_rest_position: Vector3
var _model_rest_rotation: Vector3
var _model_rest_transform: Transform3D
## Your character's arms holding the gun -- a child of _model, so the kick,
## sway, switch and reload animations all carry the hands with the gun.
## Placed in camera space (WeaponData.arms_position) and converted into
## _model's space in _apply_arms_transform().
var _arms: Node3D
## The arms model's size (PlayerModel.fit_scale_for() of ITS head height).
var _arms_fit_scale := 1.0
var _player_model: PlayerModel
var _tuning_arms: bool = false
var _switch_tween: Tween
var _kick_tween: Tween
var _tuning: bool = false
var _tuning_muzzle: bool = false
var _tune_label: Label
## A small green marker at the weapon's current muzzle_offset, visible only
## while _tuning_muzzle is on -- live visual feedback without having to fire
## to see where it is.
var _muzzle_marker: MeshInstance3D

## Sits between the switching animation (on this node) and the gun, so sway
## never fights the lower/raise animation or the fire kick.
var _sway_pivot: Node3D
var _sway_position: Vector2 = Vector2.ZERO
var _sway_tilt: Vector2 = Vector2.ZERO # degrees: x = pitch, y = yaw
var _previous_look: Vector2 = Vector2.ZERO # pitch, yaw in radians
var _has_previous_look: bool = false

## Set by AimDownSights while you aim: how far the gun has moved toward your
## eye (camera space), and how much its sway calms down (0 = none, 1 = still).
var aim_offset := Vector3.ZERO
var aim_steady := 0.0
## F2 then I: the arrows move the gun's aimed position (WeaponData.aim_position).
var _tuning_aim: bool = false
## The middle of the weapon's aim_sight_node (the scope), in _model's own
## space -- found once per weapon, see aim_position_for().
var _sight_center: Variant = null


func _ready() -> void:
	# Rule 1 (co-op): first-person arms and gun are only ever for the player
	# you control. A remote player's copy of this node stays hidden and idle;
	# what you see of them is their third-person body.
	var body := _weapons.get_parent()
	if not body.is_multiplayer_authority():
		visible = false
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_key_input(false)
		return
	_player_model = body.get_node_or_null("PlayerModel") as PlayerModel
	if _player_model:
		_player_model.character_changed.connect(_on_character_changed)
	_sway_pivot = Node3D.new()
	add_child(_sway_pivot)
	_weapons.weapon_switched.connect(_on_weapon_switched)
	_weapons.shot_fired.connect(_on_shot_fired)
	_weapons.reload_started.connect(_on_reload_started)
	_weapons.projectile_launched.connect(_on_projectile_launched)
	_weapons.throw_started.connect(_on_throw_started)
	_weapons.quick_throw_started.connect(_on_quick_throw_started)
	_weapons.item_used.connect(_on_item_used)
	call_deferred("_show_current_weapon")
	if OS.is_debug_build():
		_make_tune_label()


## Covers the case where the controller announced its first weapon before we
## were listening.
func _show_current_weapon() -> void:
	var weapon := _weapons.current_weapon()
	if weapon and _model == null:
		_show_weapon(weapon)


func _on_weapon_switched(weapon: WeaponData, draw_time: float) -> void:
	# Not waiting on the next grenade any more: you've put the grenades away
	# (otherwise _update_held_grenade() would cut this switch off halfway and
	# leave the grenade showing with the new gun equipped).
	_waiting_for_grenade = false
	if draw_time <= 0.0:
		_show_weapon(weapon) # the very first weapon just appears
		return
	if _switch_tween:
		_switch_tween.kill()
	var lower_time := draw_time * 0.4
	var raise_time := draw_time * 0.6
	_switch_tween = create_tween()
	# Lower the old gun...
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, lower_time).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, lower_time)
	# ...swap it while it's out of sight...
	_switch_tween.tween_callback(_show_weapon.bind(weapon))
	# ...and bring the new one up.
	_switch_tween.tween_property(self, "position", Vector3.ZERO, raise_time).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, raise_time)


## Dispatches to whichever reload animation this weapon uses -- most weapons
## get the shared tilt-down/tilt-up (_play_tilt_reload, the original ask, so
## adding a new weapon needs no new animation work), but a weapon can opt
## into a distinct one (WeaponData.ReloadStyle.PUMP_RACK) via reload_style.
func _on_reload_started(duration: float) -> void:
	var weapon := _weapons.current_weapon()
	if weapon and weapon.reload_style == WeaponData.ReloadStyle.PUMP_RACK:
		_play_pump_rack_reload(duration)
	else:
		_play_tilt_reload(duration)
	# A launcher gets its new rocket while it's lowered out of sight, so it
	# comes back up loaded.
	if weapon and weapon.fires_projectile:
		get_tree().create_timer(duration * 0.4).timeout.connect(_show_loaded_projectile.bind(true))


## The RPG fired: the rocket that was sitting in the launcher is handed to
## the real rocket (so it's seen leaving the tube) and hidden here, and the
## backblast blows out of the rear.
func _on_projectile_launched(rocket: Rocket) -> void:
	var weapon := _weapons.current_weapon()
	var part := _loaded_projectile()
	if part and is_instance_valid(rocket):
		# How the rocket would sit with the gun at rest -- no sway, no fire
		# kick -- so the rocket can straighten out onto its flight path
		# instead of flying on at whatever angle the gun was swinging.
		var part_in_model := _model.global_basis.inverse() * part.global_basis
		rocket.take_launcher_visual(part, global_basis * _model_rest_transform.basis * part_in_model)
	_show_loaded_projectile(false)
	# Still loaded (a bigger magazine, or Infinite Ammo): the next rocket
	# slides into view just before it can fire again.
	if weapon and _weapons.get_magazine_ammo() > 0:
		get_tree().create_timer(weapon.fire_interval * 0.8).timeout.connect(_show_loaded_projectile.bind(true))
	if weapon and _model:
		_spawn_backblast(_model.global_transform * weapon.backblast_offset,
				_model.global_transform.basis * Vector3.BACK)


## The grenade throw: wind up, swing through (the grenade leaves the hand at
## the end of the swing, exactly when WeaponController releases it), follow
## through out of view. _process brings the arm back up with the next one.
func _on_throw_started(release_delay: float) -> void:
	if _switch_tween:
		_switch_tween.kill()
	var windup := release_delay * THROW_WINDUP_SHARE
	var swing := release_delay - windup
	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "position", THROW_WINDUP_OFFSET, windup) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_WINDUP_TILT, windup)
	_switch_tween.tween_property(self, "position", THROW_SWING_OFFSET, swing).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_SWING_TILT, swing)
	_switch_tween.tween_callback(_release_held_grenade)
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, THROW_FOLLOW_TIME).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, THROW_FOLLOW_TIME)


## Q: the gun drops out of view, the grenade hand comes up and throws (same
## wind-up and swing as the grenade slot), then the gun comes back up. Times
## match WeaponController's, so the grenade leaves the hand on the swing.
func _on_quick_throw_started(grenade: WeaponData, lower_time: float, release_delay: float, recover_time: float) -> void:
	var gun_weapon := _weapons.current_weapon()
	if _switch_tween:
		_switch_tween.kill()
	var windup := release_delay * THROW_WINDUP_SHARE
	var swing := release_delay - windup
	var follow := recover_time * 0.4
	_switch_tween = create_tween()
	# Gun down...
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, lower_time).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, lower_time)
	# ...grenade hand in, straight up into the wind-up, and swing...
	_switch_tween.tween_callback(_show_quick_grenade.bind(grenade))
	_switch_tween.tween_property(self, "position", THROW_WINDUP_OFFSET, windup) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_WINDUP_TILT, windup)
	_switch_tween.tween_property(self, "position", THROW_SWING_OFFSET, swing).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_SWING_TILT, swing)
	# ...let go, follow through out of view...
	_switch_tween.tween_callback(_hide_held_gun)
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, follow)
	# ...and the gun comes back up.
	_switch_tween.tween_callback(_show_weapon.bind(gun_weapon))
	_switch_tween.tween_property(self, "position", Vector3.ZERO, recover_time - follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, recover_time - follow)


## Pills or a bandage used: exactly the grenade throw -- the same wind-up,
## swing and follow-through as the grenade slot and Q -- with the item in
## the hand instead of a grenade; it's used up as it leaves the hand (the
## heal lands then: WeaponController times it to the swing). Used off a gun
## (T / B), the gun drops first and comes back up after, like Q; used from
## its own slot, the next one comes up into your hand like the next grenade
## (or, with none left, WeaponController switches you back).
func _on_item_used(item: int, item_weapon: WeaponData, use_time: float, lower_time: float, recover_time: float, equipped: bool) -> void:
	var back_to := _weapons.current_weapon()
	if _switch_tween:
		_switch_tween.kill()
	var windup := use_time * THROW_WINDUP_SHARE
	var swing := use_time - windup
	var follow := recover_time * 0.4
	_switch_tween = create_tween()
	if not equipped:
		# Gun down, the item hand in...
		_switch_tween.tween_property(self, "position", LOWERED_OFFSET, lower_time).set_ease(Tween.EASE_IN)
		_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, lower_time)
		_switch_tween.tween_callback(_show_quick_grenade.bind(item_weapon))
	# ...wind up and swing (the grenade throw)...
	_switch_tween.tween_property(self, "position", THROW_WINDUP_OFFSET, windup) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_WINDUP_TILT, windup)
	_switch_tween.tween_property(self, "position", THROW_SWING_OFFSET, swing).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_SWING_TILT, swing)
	# ...it's used up as it leaves the hand, follow through out of view...
	_switch_tween.tween_callback(_hide_held_gun)
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, follow)
	# ...and back up: the gun, or the next one in hand.
	_switch_tween.tween_callback(func() -> void:
		if not equipped:
			if back_to and _weapons.current_weapon() == back_to:
				_show_weapon(back_to)
		elif _gun:
			_gun.visible = _weapons.heal_count(item) > 0
	)
	_switch_tween.tween_property(self, "position", Vector3.ZERO, recover_time - follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, recover_time - follow)


func _hide_held_gun() -> void:
	if _gun:
		_gun.visible = false


func _show_quick_grenade(grenade: WeaponData) -> void:
	_show_weapon(grenade)
	_waiting_for_grenade = false
	if _gun:
		_gun.visible = true


func _release_held_grenade() -> void:
	if _gun:
		_gun.visible = false
	_waiting_for_grenade = true


## The next grenade is in the hand: show it and bring the arm back up.
func _update_held_grenade() -> void:
	if not _waiting_for_grenade or _weapons.get_magazine_ammo() <= 0:
		return
	var weapon := _weapons.current_weapon()
	if weapon == null or not weapon.throws_grenade or _shown_weapon != weapon:
		_waiting_for_grenade = false # switched away: not ours to raise
		return
	if _switch_tween and _switch_tween.is_running():
		return # the throw's follow-through (or a switch) is still playing
	_waiting_for_grenade = false
	if _gun:
		_gun.visible = true
	if _switch_tween:
		_switch_tween.kill()
	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "position", Vector3.ZERO, THROW_RAISE_TIME).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, THROW_RAISE_TIME)


## Safety net: whenever nothing's animating, the model in your hand is the
## weapon you have equipped -- so an interrupted animation can never leave
## you holding one thing (a grenade) while firing another (the pistol).
func _keep_in_step() -> void:
	if _switch_tween and _switch_tween.is_running():
		return
	var weapon := _weapons.current_weapon()
	if weapon and weapon != _shown_weapon:
		_show_weapon(weapon)
		position = Vector3.ZERO
		rotation_degrees.x = 0.0


## Where the gun goes when fully aimed. With an aim_sight_node: wherever
## puts the middle of that part (the scope) straight ahead of your eye,
## AIM_EYE_DISTANCE away, plus the weapon's aim_position as a nudge.
## Otherwise just aim_position.
func aim_position_for(weapon: WeaponData) -> Vector3:
	if weapon.aim_sight_node.is_empty() or _sight_center == null:
		return weapon.aim_position
	var sight_offset: Vector3 = _model_rest_transform.basis * (_sight_center as Vector3)
	return -sight_offset + Vector3(0.0, 0.0, -AIM_EYE_DISTANCE) + weapon.aim_position


## The middle of the named sight part's mesh, in _model's space (null if the
## model has no such part).
func _find_sight_center(weapon: WeaponData) -> Variant:
	if weapon.aim_sight_node.is_empty() or _gun == null:
		return null
	var sight := _gun.find_child(weapon.aim_sight_node, true, false) as MeshInstance3D
	if sight == null:
		push_warning("Viewmodel: %s has no part named '%s' to aim through." % [weapon.weapon_name, weapon.aim_sight_node])
		return null
	var to_model := _model.global_transform.affine_inverse() * sight.global_transform
	return to_model * sight.get_aabb().get_center()


## Hides the gun and arms (a scope image is covering the view) or shows them.
func set_gun_hidden(hidden: bool) -> void:
	if _sway_pivot:
		_sway_pivot.visible = not hidden


## The launcher's loaded rocket in the current gun model, or null.
func _loaded_projectile() -> Node3D:
	var weapon := _weapons.current_weapon()
	if weapon == null or not weapon.fires_projectile or _model == null:
		return null
	return _model.find_child(weapon.projectile_part, true, false) as Node3D


func _show_loaded_projectile(loaded: bool) -> void:
	var part := _loaded_projectile()
	if part:
		part.visible = loaded


## Smoke and a flash thrown out of the back of the launcher -- the RPG's
## signature. Left in the world (not on the gun), so it hangs behind you.
func _spawn_backblast(at: Vector3, backward: Vector3) -> void:
	var world := get_tree().current_scene
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 4.0
	light.omni_range = 3.0
	world.add_child(light)
	light.global_position = at
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(light.queue_free)

	var smoke := GPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 1.0
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.local_coords = false
	smoke.draw_pass_1 = Rocket._smoke_quad(0.5)
	var material := ParticleProcessMaterial.new()
	material.direction = backward
	material.spread = 25.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 7.0
	material.damping_min = 4.0
	material.damping_max = 6.0
	material.gravity = Vector3(0.0, 0.4, 0.0)
	material.color = Color(0.8, 0.76, 0.7, 0.7)
	smoke.process_material = material
	world.add_child(smoke)
	smoke.global_position = at
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)


## The same tilt-down/tilt-up shape _on_weapon_switched() uses, minus the
## model swap in the middle.
func _play_tilt_reload(duration: float) -> void:
	if _switch_tween:
		_switch_tween.kill()
	var down_time := duration * 0.4
	var up_time := duration * 0.6
	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, down_time).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, down_time)
	_switch_tween.tween_property(self, "position", Vector3.ZERO, up_time).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, up_time)


## One-handed pump-shotgun rack: rolls the gun upright (instead of dipping it
## out of view), racks it with a few quick up/down pumps -- each one
## randomized a little in depth/speed/wobble so it never repeats identically
## (a perfectly smooth sine-wave shake would read as too clean for a raw
## one-handed rack) -- then settles back to the normal ready pose.
func _play_pump_rack_reload(duration: float) -> void:
	if _switch_tween:
		_switch_tween.kill()

	var upright_time := duration * 0.4
	var rack_time := duration * 0.4
	var settle_time := duration * 0.2

	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "rotation_degrees:x", PUMP_UPRIGHT_PITCH_DEGREES, upright_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "position:y", PUMP_UPRIGHT_LIFT, upright_time)
	_switch_tween.parallel().tween_property(self, "position:z", PUMP_UPRIGHT_PUSH_BACK, upright_time)

	# Wobble oscillates AROUND the upright pitch, not back toward 0 -- the
	# gun stays pointed up through the whole rack, it just shakes there.
	var cycle_time := rack_time / float(PUMP_CYCLES)
	for i in PUMP_CYCLES:
		var down_time := cycle_time * randf_range(0.35, 0.5)
		var up_time := cycle_time - down_time
		var drop := randf_range(PUMP_SHAKE_MIN, PUMP_SHAKE_MAX)
		var wobble := randf_range(-PUMP_ROTATION_WOBBLE, PUMP_ROTATION_WOBBLE)
		_switch_tween.tween_property(self, "position:y", PUMP_UPRIGHT_LIFT - drop, down_time).set_ease(Tween.EASE_IN)
		_switch_tween.parallel().tween_property(self, "rotation_degrees:x", PUMP_UPRIGHT_PITCH_DEGREES + wobble, down_time)
		_switch_tween.tween_property(self, "position:y", PUMP_UPRIGHT_LIFT, up_time).set_ease(Tween.EASE_OUT)
		_switch_tween.parallel().tween_property(self, "rotation_degrees:x", PUMP_UPRIGHT_PITCH_DEGREES, up_time)

	_switch_tween.tween_property(self, "position", Vector3.ZERO, settle_time).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, settle_time)


func _on_shot_fired() -> void:
	if _model == null:
		return
	var weapon := _weapons.current_weapon()
	var kick_distance := (weapon.recoil_kick_distance if weapon else 0.06) * RECOIL_VISUAL_SCALE
	var kick_rotation := (weapon.recoil_kick_rotation_degrees if weapon else 4.0) * RECOIL_VISUAL_SCALE
	# Small per-shot randomization so consecutive shots don't look identical.
	kick_distance *= randf_range(1.0 - KICK_JITTER, 1.0 + KICK_JITTER)
	kick_rotation *= randf_range(1.0 - KICK_JITTER, 1.0 + KICK_JITTER)

	if _kick_tween:
		_kick_tween.kill()
	_model.position = _model_rest_position + Vector3(0.0, 0.0, kick_distance)
	_model.rotation_degrees.x = _model_rest_rotation.x + kick_rotation
	_kick_tween = create_tween()
	_kick_tween.set_parallel(true)
	_kick_tween.tween_property(_model, "position", _model_rest_position, KICK_TIME)
	_kick_tween.tween_property(_model, "rotation_degrees:x", _model_rest_rotation.x, KICK_ROTATION_TIME) \
			.set_ease(Tween.EASE_OUT)
	_spawn_muzzle_flash()


## Where the equipped gun's muzzle is in the world right now (its
## muzzle_offset, following the kick, sway and switch animations) -- where
## ShotTracer starts your visible bullets.
func muzzle_position() -> Vector3:
	var weapon := _weapons.current_weapon()
	if _model == null or weapon == null:
		return global_position
	return _model.global_transform * weapon.muzzle_offset


## A brief additive glow + a real light flash right at the equipped weapon's
## OWN muzzle_offset (per-weapon, tunable in-game -- see muzzle_offset's own
## comment in weapon_data.gd). Removes itself after the weapon's own
## muzzle_flash_time.
func _spawn_muzzle_flash() -> void:
	var weapon := _weapons.current_weapon()
	if weapon == null:
		return
	var offset := weapon.muzzle_offset

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 6.0
	light.omni_range = 3.0
	_model.add_child(light)
	light.position = offset

	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	glow.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.9, 0.6, 1.0)
	glow.material_override = mat
	_model.add_child(glow)
	glow.position = offset

	# Connected straight to the nodes' own queue_free, not a lambda: if the gun
	# is swapped (or the level restarts) before this fires, freed nodes drop
	# their connections automatically, while a lambda would still fire with
	# freed captures ("Lambda capture at index 0 was freed").
	var timer := get_tree().create_timer(weapon.muzzle_flash_time)
	timer.timeout.connect(light.queue_free)
	timer.timeout.connect(glow.queue_free)


func _show_weapon(weapon: WeaponData) -> void:
	if _kick_tween:
		_kick_tween.kill()
	if _model:
		_model.queue_free() # takes the old arms with it
	_arms = null

	# _model is a pivot. The weapon's position, rotation and scale are applied to
	# it, and the gun is shifted inside it so the GUN'S CENTRE sits on the pivot.
	# Imported models often have their origin far from the actual mesh, which
	# would make rotating or resizing swing the gun around wildly.
	_model = Node3D.new()
	_sway_pivot.add_child(_model)
	var gun: Node3D
	if weapon.viewmodel_scene:
		gun = weapon.viewmodel_scene.instantiate() as Node3D
	else:
		gun = _make_placeholder(weapon)
	_model.add_child(gun)
	_gun = gun
	_shown_weapon = weapon
	# A grenade slot with nothing in hand yet: empty hand until one's ready.
	_waiting_for_grenade = weapon.throws_grenade and _weapons.get_magazine_ammo() <= 0
	gun.visible = not _waiting_for_grenade
	_center_on_pivot(gun)
	_apply_transform(weapon)
	_sight_center = _find_sight_center(weapon)
	_attach_arms(weapon)
	# An empty launcher comes out empty.
	if weapon.fires_projectile:
		_show_loaded_projectile(_weapons.get_magazine_ammo() > 0)
	if _tuning_muzzle:
		_update_muzzle_marker(weapon)


## Puts the model where the weapon's data says it should be.
func _apply_transform(weapon: WeaponData) -> void:
	_model_rest_position = weapon.viewmodel_position
	_model_rest_rotation = weapon.viewmodel_rotation_degrees
	_model.position = _model_rest_position
	_model.rotation_degrees = _model_rest_rotation
	_model.scale = Vector3.ONE * weapon.viewmodel_scale
	_model_rest_transform = _model.transform
	_apply_arms_transform(weapon)


func _on_character_changed() -> void:
	var weapon := _weapons.current_weapon()
	if weapon and _model:
		_attach_arms(weapon)


## Your character's arms in the weapon's hold pose, holding the gun. A fresh
## copy of the same character the body wears (PlayerModel), with its head and
## legs hidden and no shadow -- the body already casts one.
func _attach_arms(weapon: WeaponData) -> void:
	if is_instance_valid(_arms):
		_arms.queue_free()
	_arms = null
	if weapon.hold_animation == null or _player_model == null:
		return
	var path := arms_character if not arms_character.is_empty() else _player_model.character_path
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_arms = scene.instantiate() as Node3D
	_model.add_child(_arms)

	# Hold the pose's first frame still, so the hands can't drift off the grip.
	var animator := PlayerModel.animator_for(_arms)
	var library := AnimationLibrary.new()
	library.add_animation(&"hold", weapon.hold_animation)
	animator.add_animation_library(&"fp", library)
	animator.play(&"fp/hold")
	animator.seek(0.0, true)
	animator.pause()

	var skeletons := _arms.find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = null
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
	if skeleton:
		var hider := HideBonesModifier.new()
		var hidden := PackedStringArray(["Head", "LeftUpperLeg", "RightUpperLeg"])
		var kept := PackedStringArray()
		if hide_torso and skeleton.find_bone("RightShoulder") != -1:
			# Just the arms: the whole body goes, the shoulders (and the arms
			# hanging off them) are put back. Otherwise the torso swings up
			# into view whenever the gun tilts down (switching, throwing).
			hidden = PackedStringArray(["Hips"])
			kept.append("RightShoulder")
			if not weapon.hide_left_arm:
				kept.append("LeftShoulder")
		elif weapon.hide_left_arm:
			hidden.append("LeftUpperArm") # one hand only
		hider.bone_names = hidden
		hider.keep_bones = kept
		if not kept.is_empty():
			for chest in ["UpperChest", "Chest"]:
				if skeleton.find_bone(chest) != -1:
					hider.collapse_in_place = PackedStringArray([chest])
					break
		skeleton.add_child(hider)
		# Sized like the body would size this character, from its own head height.
		var head := skeleton.find_bone("Head")
		_arms_fit_scale = _player_model.model_scale
		if head != -1:
			var head_in_model := _arms.global_transform.affine_inverse() \
					* (skeleton.global_transform * skeleton.get_bone_global_rest(head).origin)
			_arms_fit_scale = _player_model.fit_scale_for(head_in_model.y)
		if weapon.arms_position == Vector3.ZERO:
			_auto_place_arms(weapon, skeleton)
	for node in _arms.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_arms_transform(weapon)
	# A fresh arms model is drawn whole (torso and all) until its
	# HideBonesModifier has run once -- that was the torso flashing up at the
	# bottom of the screen on every swap (throws, heals, switches). Kept
	# hidden until the hiding has happened.
	_arms.visible = false
	_reveal_arms(_arms)


func _reveal_arms(arms: Node3D) -> void:
	for i in ARMS_REVEAL_FRAMES:
		await get_tree().process_frame
	if is_instance_valid(arms):
		arms.visible = true


## The arms' facing and size in camera space: turned to face forward (Mixamo
## characters face +Z, the camera looks down -Z), the weapon's own tweak on
## top, scaled to match the body (PlayerModel.model_scale).
func _arms_basis(weapon: WeaponData) -> Basis:
	var size := _arms_fit_scale * weapon.arms_scale
	return Basis.from_euler(weapon.arms_rotation_degrees * (PI / 180.0)) \
			* Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * size)


## First-time placement for a weapon that hasn't been tuned yet: puts the
## posed right hand right on the gun. Stored on the weapon, so F3 saves it.
func _auto_place_arms(weapon: WeaponData, skeleton: Skeleton3D) -> void:
	var hand := skeleton.find_bone("RightHand")
	if hand == -1:
		return
	# The posed hand, in the arms model's own space (it was just added at the
	# identity transform, so this includes the FBX's internal scaling).
	var hand_in_model := _arms.global_transform.affine_inverse() \
			* (skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin)
	weapon.arms_position = weapon.viewmodel_position - _arms_basis(weapon) * hand_in_model


## Puts the arms where weapon.arms_position/rotation say in CAMERA space,
## converted into _model's space (the arms are its child). Measured against
## _model's REST transform, so the kick and sway then move gun and arms as one.
func _apply_arms_transform(weapon: WeaponData) -> void:
	if not is_instance_valid(_arms):
		return
	var desired := Transform3D(_arms_basis(weapon), weapon.arms_position)
	_arms.transform = _model_rest_transform.affine_inverse() * desired


## Shifts gun so the centre of its visible meshes sits at its parent's origin.
func _center_on_pivot(gun: Node3D) -> void:
	var bounds := AABB()
	var has_bounds := false
	var meshes := gun.find_children("*", "MeshInstance3D", true, false)
	if gun is MeshInstance3D:
		meshes.append(gun)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		# The mesh's bounding box, measured in the gun's own coordinates.
		var box := gun.global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	if has_bounds:
		gun.position = -(gun.basis * bounds.get_center())


func _make_placeholder(weapon: WeaponData) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.1, 0.4)
	block.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = weapon.placeholder_color
	block.material_override = material
	return block


# ---- Dev tool: live tuning -------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F2:
		_tuning = not _tuning
		_tune_label.visible = _tuning
		_update_label("")
	elif key.keycode == KEY_F3 and _tuning:
		_save_weapon()
	elif key.keycode == KEY_I and _tuning:
		_tuning_aim = not _tuning_aim
		_tuning_arms = false
		_tuning_muzzle = false
		var weapon := _shown_weapon
		if weapon and _model:
			_apply_transform(weapon) # back to the hip pose when leaving
			_update_muzzle_marker(weapon)
		_update_label("")
	elif key.keycode == KEY_M and _tuning:
		_tuning_muzzle = not _tuning_muzzle
		_tuning_arms = false
		_tuning_aim = false
		var weapon := _shown_weapon
		if weapon:
			_update_muzzle_marker(weapon)
		_update_label("")
	elif key.keycode == KEY_H and _tuning:
		_tuning_arms = not _tuning_arms
		_tuning_muzzle = false
		_tuning_aim = false
		var weapon := _shown_weapon
		if weapon:
			_update_muzzle_marker(weapon)
		_update_label("")


func _physics_process(delta: float) -> void:
	_update_sway(delta)


## Gun sway: the gun lags behind the way you turn, then settles back. It's driven
## by how fast the camera itself is turning, so it needs no mouse input of its
## own. It runs on the physics tick because that's when the camera turns, so
## the turn speed comes out steady instead of spiking between frames.
func _update_sway(delta: float) -> void:
	if not sway_enabled or delta <= 0.0:
		_sway_pivot.position = aim_offset
		_sway_pivot.rotation = Vector3.ZERO
		return
	var camera := get_parent() as Node3D
	var euler := camera.global_transform.basis.get_euler()
	var look := Vector2(euler.x, euler.y) # pitch, yaw in radians
	var turn_speed := Vector2.ZERO # radians per second
	if _has_previous_look:
		turn_speed = Vector2(angle_difference(_previous_look.x, look.x), angle_difference(_previous_look.y, look.y)) / delta
	_previous_look = look
	_has_previous_look = true

	# Turning right: the gun lags to the left. Looking up: the gun dips down.
	var target_position := Vector2(turn_speed.y, -turn_speed.x) * sway_position_amount
	var target_tilt := Vector2(-turn_speed.x, -turn_speed.y) * sway_rotation_amount
	target_position = target_position.limit_length(sway_max_offset)
	target_tilt = target_tilt.limit_length(sway_max_tilt_degrees)

	# Frame-rate independent smoothing toward the target.
	var blend := 1.0 - exp(-sway_smoothing * delta)
	_sway_position = _sway_position.lerp(target_position, blend)
	_sway_tilt = _sway_tilt.lerp(target_tilt, blend)
	# Aiming steadies the sway and carries the gun toward your eye.
	var calm := 1.0 - aim_steady
	_sway_pivot.position = Vector3(_sway_position.x, _sway_position.y, 0.0) * calm + aim_offset
	_sway_pivot.rotation_degrees = Vector3(_sway_tilt.x, _sway_tilt.y, 0.0) * calm


func _process(delta: float) -> void:
	_update_held_grenade()
	_keep_in_step()
	if not _tuning or _model == null:
		return
	if _switch_tween and _switch_tween.is_running():
		return # mid-switch: the model in hand isn't settled yet
	var weapon := _shown_weapon
	if weapon == null:
		return

	# Arrow keys move the gun (left/right, up/down); PageUp pushes it forward
	# and PageDown pulls it back. Hold Shift to rotate instead. +/- resizes it.
	# M switches these same keys to moving the muzzle flash point instead.
	var x := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	var y := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
	var z := float(Input.is_key_pressed(KEY_PAGEDOWN)) - float(Input.is_key_pressed(KEY_PAGEUP))
	var fine := 0.1 if Input.is_key_pressed(KEY_CTRL) else 1.0

	if _tuning_muzzle:
		weapon.muzzle_offset += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		_update_muzzle_marker(weapon)
	elif _tuning_aim:
		weapon.aim_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
	elif _tuning_arms:
		# H mode: the same keys move/rotate/resize the arms instead of the gun.
		if Input.is_key_pressed(KEY_SHIFT):
			weapon.arms_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
		else:
			weapon.arms_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
			var grow_arms := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
			weapon.arms_scale = maxf(weapon.arms_scale * (1.0 + grow_arms * TUNE_SCALE_SPEED * fine * delta), 0.0001)
	elif Input.is_key_pressed(KEY_SHIFT):
		weapon.viewmodel_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	else:
		weapon.viewmodel_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		var grow := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
		weapon.viewmodel_scale = maxf(weapon.viewmodel_scale * (1.0 + grow * TUNE_SCALE_SPEED * fine * delta), 0.0001)

	_apply_transform(weapon)
	if _tuning_aim:
		# Show the gun where it'll sit when aimed, so you can line up the sights.
		_model.position = aim_position_for(weapon)
	_update_label("")


## Creates (if needed) and repositions the green muzzle marker at the
## weapon's current muzzle_offset, as a child of _model so it moves/rotates
## exactly with the gun. Only actually visible while _tuning_muzzle is on.
func _update_muzzle_marker(weapon: WeaponData) -> void:
	if _model == null:
		return
	if not is_instance_valid(_muzzle_marker):
		_muzzle_marker = MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.015
		mesh.height = 0.03
		_muzzle_marker.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 1.0, 0.2)
		_muzzle_marker.material_override = mat
	if _muzzle_marker.get_parent() != _model:
		if _muzzle_marker.get_parent():
			_muzzle_marker.get_parent().remove_child(_muzzle_marker)
		_model.add_child(_muzzle_marker)
	_muzzle_marker.position = weapon.muzzle_offset
	_muzzle_marker.visible = _tuning_muzzle


func _save_weapon() -> void:
	var weapon := _shown_weapon
	if weapon == null or weapon.resource_path.is_empty():
		return
	var result := ResourceSaver.save(weapon, weapon.resource_path)
	_update_label("Saved to %s" % weapon.resource_path if result == OK else "SAVE FAILED (error %d)" % result)


func _make_tune_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_tune_label = Label.new()
	_tune_label.position = Vector2(16.0, 130.0)
	_tune_label.add_theme_font_size_override("font_size", 18)
	_tune_label.visible = false
	layer.add_child(_tune_label)
	add_child(layer)


func _update_label(message: String) -> void:
	var weapon := _shown_weapon
	if weapon == null:
		return
	var target := "GUN"
	var p := weapon.viewmodel_position
	var r := weapon.viewmodel_rotation_degrees
	var s := weapon.viewmodel_scale
	if _tuning_arms:
		target = "ARMS"
		p = weapon.arms_position
		r = weapon.arms_rotation_degrees
		s = weapon.arms_scale
	elif _tuning_muzzle:
		target = "MUZZLE"
		p = weapon.muzzle_offset
	elif _tuning_aim:
		target = "AIMED POSITION"
		p = weapon.aim_position
	_tune_label.text = "TUNING %s: %s\nposition  (%.3f, %.3f, %.3f)\nrotation  (%.1f, %.1f, %.1f)\nscale     %.4f\n\nArrows = move   PageUp/PageDown = forward/back\nShift + arrows / PageUp,Down = rotate\n+ / - = resize    Ctrl = 10x finer\nH = arms   M = muzzle   I = aimed position   F3 = save   F2 = off\n%s" \
			% [target, weapon.weapon_name, p.x, p.y, p.z, r.x, r.y, r.z, s, message]
