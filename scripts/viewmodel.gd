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

## -- Healing (pills, bandage), Left 4 Dead 2's pills --
## Where the item is brought to, camera space: centred, just under your mouth.
const ITEM_MOUTH_POINT := Vector3(0.0, -0.13, -0.24)
## Share of the use time spent bringing it up; the rest is tipping it out.
const ITEM_RAISE_SHARE := 0.4
## How far it's tipped back toward your mouth (degrees, round the item).
const ITEM_TIP_DEGREES := 40.0
## The little shakes at the top: how many, how much further they tip, and
## how far up each one jerks it (meters).
const ITEM_SHAKES := 2
const ITEM_SHAKE_DEGREES := 14.0
const ITEM_SHAKE_LIFT := 0.015

## How many frames freshly built arms stay hidden while their pose lands.
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

## Use the dedicated first-person arms (FirstPersonArms: Arms/arms_rig.glb,
## bare skin) instead of a character's arms. Their right hand holds every
## gun; the left is the tentacle arm (PlayerGrapple). Off = arms_character.
@export var use_new_arms: bool = true
## One-handed weapons not yet fitted to the new arms start with this
## weapon's arm placement (both arms' position/turn/size and the right arm's
## own nudge), then get seated in the hand by their grip_point.
@export var one_handed_arms_template: WeaponData = preload("res://weapons/starter_gun.tres")

## Show only the arms of the first-person arms model: its mesh is cut down to
## the shoulders, arms and hands (its torso would otherwise swing up into
## view as the gun tilts down). Off = the old way (head and legs shrunk away).
@export var hide_torso: bool = true

## Throws and heals swing the arm round its shoulder joint, not round your
## eye. Round the eye, tipping the arm up for the wind-up carried the
## shoulder and sleeve (which sit just beside and below the camera) forward
## into the bottom of the screen. Off = the old swing round the eye.
@export var throw_from_shoulder: bool = true

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

## The model in your hand: a pivot holding the gun/item model, a child of
## the arms' right hand bone (_hand_attachment), placed so that with the arms
## in their hold pose it sits exactly at the weapon's viewmodel_position /
## rotation / scale (camera space). Half-Life 2's way: the gun is IN the hand,
## so anything that moves the hand carries the gun with it.
var _model: Node3D
## The gun's own model inside _model (without the arms).
var _gun: Node3D
## Every gun/item model made so far, kept (hidden) for the next time it's
## shown, so a switch never loads or builds anything: WeaponData -> _model.
var _gun_models := {}
## Thrown the grenade, waiting for the next one to come into the hand.
var _waiting_for_grenade := false
## The weapon whose model is in your hand right now (it can differ from the
## equipped one for a moment: a quick throw or an T / B heal shows its own).
var _shown_weapon: WeaponData
var _model_rest_position: Vector3
var _model_rest_rotation: Vector3
var _model_rest_transform: Transform3D
## Your character's arms: ONE copy, built the first time it's needed and kept
## for good (like HL2's c_arms) -- a switch just plays the new weapon's hold
## pose on it and moves it to the weapon's arms_position. A child of
## _kick_pivot, so the kick, sway, switch and reload animations all carry the
## hands and the gun together.
var _arms: Node3D
var _arms_skeleton: Skeleton3D
var _arms_animator: AnimationPlayer
## The hold poses played so far (one per hold_animation).
var _arms_library: AnimationLibrary
## The skeleton node's place inside _arms (fixed, measured once).
var _skeleton_in_arms := Transform3D.IDENTITY
var _hand_bone := -1
## Follows the right hand bone; the gun models hang off it.
var _hand_attachment: BoneAttachment3D
## [MeshInstance3D, its original mesh, its original per-surface material
## overrides] for each skinned mesh of the arms, so it can be cut again
## (both arms / right arm only) from the original.
var _arms_meshes: Array = []
## Which cut is on: 1 = both arms, 0 = right arm only, -1 = none yet.
var _arms_keep_left := -1
## The head/legs shrinker, used only when the mesh can't be cut.
var _arms_hider: HideBonesModifier
## F2 > U: holding the healing item up at your mouth, as when it's used.
var _use_pose_shown := false
## Whether the shown weapon wants arms at all (it has a hold_animation).
var _arms_wanted := false
## Arms-only cuts of the arms model's meshes, made once and shared:
## "<mesh id>|<skin id>|<keep left>" -> [ArrayMesh, kept surface indices].
static var _arms_only_meshes := {}
## The arms model's size (PlayerModel.fit_scale_for() of ITS head height).
var _arms_fit_scale := 1.0
var _player_model: PlayerModel
## Flying (PlayerMovement.flying): 0..1 of the way into the lowered pose the
## reload dips to (the user's: hands down while the wings are out).
var _flight_lower := 0.0
## The new arms (use_new_arms), and the grapple their left arm works for.
var _fp_arms: FirstPersonArms
var _grapple: PlayerGrapple
## Dual wielding (WeaponData.dual_wield): the second gun, in the left hand
## (kept per weapon like _gun_models), and whether the last shot was its.
var _left_model: Node3D
var _left_models := {}
var _shot_from_left := false
## The muzzle flashes, right hand and left (made on first shot, reused).
var _flashes: Array[MuzzleFlash] = [null, null]
## F2 then L: the arrows move the flash's key light (it stays lit).
var _tuning_light: bool = false
## Flips across X: turns the right gun's place in its hand into the left's.
const MIRROR_X := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)), Vector3.ZERO)
var _tuning_arms: bool = false
var _switch_tween: Tween
var _kick_tween: Tween
var _tuning: bool = false
var _tuning_muzzle: bool = false
## F2 then G: the arrows move the gun's grip_point and the gun stays seated
## in the hand by it (Shift turns it round the grip, +/- resizes it there).
var _tuning_grip: bool = false
## F2 then J / K: the arrows move just the right / left arm (the gun stays put).
var _tuning_right_arm: bool = false
var _tuning_left_arm: bool = false
## F2 then O, with the backpack open: tune how it's held (BackpackHold).
var _tuning_bag: bool = false
## Bag tuning: which finger [ and ] curl (-1: the whole fist; 0 thumb .. 4 pinky).
var _bag_finger := -1
## Bag tuning, X: the items' container (the pack's own shape) shown.
var _tuning_bag_box := false
## Y: the right hand's own grip for the gun in it (WeaponData.right_grip*),
## and which finger [ and ] curl (-1: the whole hand).
var _tuning_right_grip := false
var _grip_finger := -1
## The open backpack (your own view), and whether it was out last frame.
var _bag_view: BackpackView
var _bag_was_out := false
var _grip_marker: MeshInstance3D
var _tune_label: Label
## A small green marker at the weapon's current muzzle_offset, visible only
## while _tuning_muzzle is on -- live visual feedback without having to fire
## to see where it is.
var _muzzle_marker: MeshInstance3D

## Sits between the switching animation (on this node) and the gun, so sway
## never fights the lower/raise animation or the fire kick.
var _sway_pivot: Node3D
## Between this node and _sway_pivot: shifts the rig so this node's tilt
## turns it round _pivot_point instead of round the eye (see
## _apply_pivot()). Only while _pivot_on.
var _swing_pivot: Node3D
## What the tilt turns round while _pivot_on, in _swing_pivot's space: the
## arms' right shoulder (throws) or the item in your hand (heals).
var _pivot_point := Vector3.ZERO
var _pivot_on := false
## Frames left before freshly built arms are shown (see _ensure_arms()).
var _arms_hidden_frames := 0
## Between _sway_pivot and the arms: the fire kick, which moves the arms and
## the gun in them as one (see _apply_kick()).
var _kick_pivot: Node3D
## The kick right now: how far back (meters) and how far the muzzle's tipped
## up (degrees). Tweened back to 0 after each shot.
var _kick_back := 0.0:
	set(value):
		_kick_back = value
		_apply_kick()
var _kick_pitch := 0.0:
	set(value):
		_kick_pitch = value
		_apply_kick()
## F2 > I: shows the whole viewmodel where it goes when aimed.
var _preview_offset := Vector3.ZERO
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
	_grapple = body.get_node_or_null("PlayerGrapple") as PlayerGrapple
	if _player_model and not use_new_arms:
		_player_model.character_changed.connect(_on_character_changed)
	_swing_pivot = Node3D.new()
	add_child(_swing_pivot)
	_sway_pivot = Node3D.new()
	_swing_pivot.add_child(_sway_pivot)
	_kick_pivot = Node3D.new()
	_sway_pivot.add_child(_kick_pivot)
	set_notify_local_transform(true)
	_weapons.weapon_switched.connect(_on_weapon_switched)
	_weapons.shot_fired.connect(_on_shot_fired)
	_weapons.reload_started.connect(_on_reload_started)
	_weapons.projectile_launched.connect(_on_projectile_launched)
	_weapons.throw_started.connect(_on_throw_started)
	_weapons.quick_throw_started.connect(_on_quick_throw_started)
	_weapons.item_used.connect(_on_item_used)
	_weapons.hand_changed.connect(_on_hand_changed)
	call_deferred("_show_current_weapon")
	if OS.is_debug_build():
		_make_tune_label()


## Your right hand (PlayerHand, through WeaponController.hand_changed): a
## thing in it is shown like a weapon -- a runtime copy of HAND_TEMPLATE's
## hold (the pills', one-handed, right hand) with the thing as its model,
## real size but no bigger than HAND_MAX_SIZE (the user's: 30 cm). Made once
## per look and kept (_hand_looks), so picking things up never rebuilds.
const HAND_TEMPLATE := preload("res://weapons/pills.tres")
const HAND_MAX_SIZE := 0.3
## Where a held kind sits until it has a placement of its own: the RPG round's.
const HAND_DEFAULT := "res://weapons/hand/rockets.tres"
var _hand_weapon: WeaponData
var _hands_empty := false
## Starving (HungerCues sets it, 0..1): the hands shake, TREMBLE_AMOUNT (m).
var tremble := 0.0
var _tremble_time := 0.0
const TREMBLE_AMOUNT := 0.006
static var _hand_looks := {}


func _on_hand_changed(data: Dictionary) -> void:
	if data.get("empty", false):
		# The gun's in the bag, the hand's empty: the arms drop out of view.
		# Only the right arm and the gun go (the user's: the left arm -- the
		# grapple, the bag -- works and shows as ever).
		_hand_weapon = null
		_hands_empty = true
		if is_instance_valid(_model):
			_model.visible = false
		if is_instance_valid(_left_model):
			_left_model.visible = false # (the second Uzi goes too)
		if _fp_arms:
			# Dual wielding off while they're stowed: the left hand mirrors the
			# right in it, and the right's away -- the left (grapple, bag) is its
			# own again (the user's). _pose_arms() sets it back when a gun's out.
			_fp_arms.set_dual(false)
			_fp_arms.set_right_hidden(true)
		return
	_hands_empty = false
	if _fp_arms:
		_fp_arms.set_right_hidden(false)
	if data.is_empty():
		_hand_weapon = null
		var gun := _weapons.current_weapon()
		if gun:
			_on_weapon_switched(gun, maxf(gun.draw_time, 0.2))
		return
	_hand_weapon = _hand_look(data)
	_on_weapon_switched(_hand_weapon, HAND_TEMPLATE.draw_time)


## The weapon a held thing is shown as (made once per look).
func _hand_look(data: Dictionary) -> WeaponData:
	var key := "%d|%s|%s|%s" % [data.get("kind", -1), CarryItem.is_rotten_data(data), data.get("weapon", ""), data.get("mutation", "")]
	if _hand_looks.has(key):
		return _hand_looks[key]
	# Its own placement file per kind (the user's: tune where ammo, pills... sit
	# in the hand with the same keys as a gun -- F2, then F3 saves it there).
	var kind_index: int = data.get("kind", -1)
	var kind_name: String = "pod" if kind_index == CarryItem.POD else (Backpack.Kind.keys()[kind_index + 1] as String).to_lower()
	var path := "res://weapons/hand/%s.tres" % kind_name
	var path_to_load := path
	# None of its own yet: where the RPG round sits (the user's tuned one).
	if not ResourceLoader.exists(path) and ResourceLoader.exists(HAND_DEFAULT):
		path_to_load = HAND_DEFAULT
	var saved := load(path_to_load) as WeaponData if ResourceLoader.exists(path_to_load) else null
	var look := (saved if saved else HAND_TEMPLATE).duplicate() as WeaponData
	look.take_over_path(path)
	look.weapon_name = "Hand: %s" % kind_name
	look.heal_item = -1
	look.one_handed = true
	look.viewmodel_scene = _hand_scene(data)
	_hand_looks[key] = look
	return look


## The thing as a little scene of its own, sized for the hand.
func _hand_scene(data: Dictionary) -> PackedScene:
	var root := Node3D.new()
	var source := CarryItem.model_for(data, _weapons.grenade_weapon())
	# Flattened into plain mesh copies (the user's bug: ammo, grenades and pills
	# -- whole imported scenes -- were lost packing them; the RPG round, a
	# plain mesh, showed).
	var model := Node3D.new()
	root.add_child(model)
	if source:
		var holder := Node3D.new()
		holder.add_child(source)
		for node in holder.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			if part.mesh == null:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = part.mesh
			copy.material_override = part.material_override
			for surface in part.mesh.get_surface_count():
				copy.set_surface_override_material(surface, part.get_active_material(surface))
			var place := Transform3D.IDENTITY
			var walk: Node = part
			while walk and walk != holder:
				place = (walk as Node3D).transform * place
				walk = walk.get_parent()
			copy.transform = place
			model.add_child(copy)
		holder.free()
	var box := BackpackView._bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var size := minf(CarryItem.size_of(data), HAND_MAX_SIZE)
	model.scale *= size / maxf(longest, 0.0001)
	for node in root.find_children("*", "", true, false):
		node.owner = root
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # (no shadow from your hand)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


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
	_switch_tween.tween_callback(_set_shoulder_pivot.bind(true))
	_switch_tween.tween_property(self, "position", THROW_WINDUP_OFFSET, windup) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_WINDUP_TILT, windup)
	_switch_tween.tween_property(self, "position", THROW_SWING_OFFSET, swing).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", THROW_SWING_TILT, swing)
	_switch_tween.tween_callback(_release_held_grenade)
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, THROW_FOLLOW_TIME).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, THROW_FOLLOW_TIME)
	_switch_tween.tween_callback(_set_shoulder_pivot.bind(false)) # out of view now


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
	_switch_tween.tween_callback(_set_shoulder_pivot.bind(true))
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
	_switch_tween.tween_callback(_set_shoulder_pivot.bind(false))
	_switch_tween.tween_callback(_show_weapon.bind(gun_weapon))
	_switch_tween.tween_property(self, "position", Vector3.ZERO, recover_time - follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, recover_time - follow)


## Pills or a bandage used -- Left 4 Dead 2's pills: the hand brings the item
## up to just under your mouth (ITEM_MOUTH_POINT), tips it back and shakes
## it out a couple of times, then drops away out of view. The tips turn round
## the item itself (_set_pivot()), so it tips in place instead of swinging
## round your eye. The heal lands as it starts down (WeaponController times
## it to use_time). Used off a gun (T / B), the gun drops first and comes
## back up after, like Q; used from its own slot, the next one comes up into
## your hand (or, with none left, WeaponController switches you back).
func _on_item_used(item: int, item_weapon: WeaponData, use_time: float, lower_time: float, recover_time: float, equipped: bool) -> void:
	var back_to := _weapons.current_weapon()
	if _switch_tween:
		_switch_tween.kill()
	var raise := use_time * ITEM_RAISE_SHARE
	var step := (use_time - raise) / float(ITEM_SHAKES * 2)
	var follow := recover_time * 0.4
	# Moving the whole viewmodel by this takes the item from where it sits in
	# your hand to your mouth.
	var to_mouth := ITEM_MOUTH_POINT - item_weapon.viewmodel_position
	var shake_up := to_mouth + Vector3(0.0, ITEM_SHAKE_LIFT, 0.0)
	_switch_tween = create_tween()
	if not equipped:
		# Gun down, the item hand in...
		_switch_tween.tween_property(self, "position", LOWERED_OFFSET, lower_time).set_ease(Tween.EASE_IN)
		_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, lower_time)
		_switch_tween.tween_callback(_show_quick_grenade.bind(item_weapon))
	_switch_tween.tween_callback(_set_pivot.bind(item_weapon.viewmodel_position))
	# ...up to your mouth, tipping back as it comes...
	_switch_tween.tween_property(self, "position", to_mouth, raise) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", ITEM_TIP_DEGREES * 0.5, raise) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ...tipped right back and shaken out...
	for i in ITEM_SHAKES:
		_switch_tween.tween_property(self, "rotation_degrees:x", ITEM_TIP_DEGREES + ITEM_SHAKE_DEGREES, step) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_switch_tween.parallel().tween_property(self, "position", shake_up, step).set_ease(Tween.EASE_OUT)
		_switch_tween.tween_property(self, "rotation_degrees:x", ITEM_TIP_DEGREES, step) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_switch_tween.parallel().tween_property(self, "position", to_mouth, step).set_ease(Tween.EASE_IN)
	# ...done (the heal lands now): down out of view, used up...
	_switch_tween.tween_property(self, "position", LOWERED_OFFSET, follow).set_ease(Tween.EASE_IN)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", LOWERED_TILT_DEGREES, follow)
	_switch_tween.tween_callback(_hide_held_gun)
	# ...and back up: the gun, or the next one in hand.
	_switch_tween.tween_callback(_set_pivot.bind(null))
	_switch_tween.tween_callback(func() -> void:
		if not equipped:
			if back_to and _weapons.current_weapon() == back_to:
				_show_weapon(back_to)
		elif _gun:
			_gun.visible = _weapons.heal_count(item) > 0
	)
	_switch_tween.tween_property(self, "position", Vector3.ZERO, recover_time - follow).set_ease(Tween.EASE_OUT)
	_switch_tween.parallel().tween_property(self, "rotation_degrees:x", 0.0, recover_time - follow)


## Throws and heals turn the arm round its shoulder (throw_from_shoulder).
## Switched on and off only where the switch can't be seen: at the start of
## the wind-up (no tilt yet, or the arm is still down out of view) and once
## it has followed through out of view.
func _set_shoulder_pivot(on: bool) -> void:
	if on and throw_from_shoulder:
		_set_pivot(_find_shoulder())
	elif _pivot_on:
		_set_pivot(null)


## Makes this node's tilt turn the viewmodel round `point` (in
## _swing_pivot's space), or round the eye again with null.
func _set_pivot(point: Variant) -> void:
	_pivot_on = point != null
	_pivot_point = point if point != null else Vector3.ZERO
	_apply_pivot()


## Where the arms model's right shoulder joint is (its upper arm bone), in
## _swing_pivot's space. No arms: zero, i.e. round the eye like before.
func _find_shoulder() -> Vector3:
	if not is_instance_valid(_arms):
		return Vector3.ZERO
	var skeletons := _arms.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return Vector3.ZERO
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone("RightUpperArm")
	if bone == -1:
		bone = skeleton.find_bone("RightShoulder")
	if bone == -1:
		bone = skeleton.find_bone("upper_arm.R") # the new arms
	if bone == -1:
		return Vector3.ZERO
	return _swing_pivot.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)


## This node turns round its own origin (the eye). Shifting what's under it
## by B^-1 * P - P (B = its turn, P = _pivot_point) makes the same turn
## happen round P instead: P stays where it is and the rest swings round it.
func _apply_pivot() -> void:
	if _swing_pivot == null:
		return
	if not _pivot_on:
		_swing_pivot.position = Vector3.ZERO
		return
	_swing_pivot.position = transform.basis.inverse() * _pivot_point - _pivot_point


func _notification(what: int) -> void:
	# Every tween step on this node's tilt/position, kept round _pivot_point.
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and _pivot_on:
		_apply_pivot()


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
	if not (_tuning and _use_pose_shown):
		_set_shoulder_pivot(false) # a throw cut off partway
	if _hands_empty:
		return # the gun's in the backpack: nothing to show
	# Something in your right hand (PlayerHand) is what's shown, not the gun.
	var weapon := _hand_weapon if _hand_weapon else _weapons.current_weapon()
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
	# Dual wielding: the guns take turns.
	_shot_from_left = not _shot_from_left and is_instance_valid(_left_model)
	var kick_distance := (weapon.recoil_kick_distance if weapon else 0.06) * RECOIL_VISUAL_SCALE
	var kick_rotation := (weapon.recoil_kick_rotation_degrees if weapon else 4.0) * RECOIL_VISUAL_SCALE
	# Small per-shot randomization so consecutive shots don't look identical.
	kick_distance *= randf_range(1.0 - KICK_JITTER, 1.0 + KICK_JITTER)
	kick_rotation *= randf_range(1.0 - KICK_JITTER, 1.0 + KICK_JITTER)

	if _kick_tween:
		_kick_tween.kill()
	_kick_back = kick_distance
	_kick_pitch = kick_rotation
	_kick_tween = create_tween()
	_kick_tween.set_parallel(true)
	_kick_tween.tween_property(self, "_kick_back", 0.0, KICK_TIME)
	_kick_tween.tween_property(self, "_kick_pitch", 0.0, KICK_ROTATION_TIME).set_ease(Tween.EASE_OUT)
	_spawn_muzzle_flash()


## The kick, as a move of the whole viewmodel (arms and gun together): the
## same move that takes the gun from its rest pose to its rest pose pushed
## back _kick_back and tipped up _kick_pitch round its own middle.
func _apply_kick() -> void:
	if _kick_pivot == null:
		return
	if _kick_back == 0.0 and _kick_pitch == 0.0:
		_kick_pivot.transform = Transform3D.IDENTITY
		return
	var rest := Transform3D(Basis.from_euler(_model_rest_rotation * (PI / 180.0)), _model_rest_position)
	var kicked := Transform3D(Basis.from_euler((_model_rest_rotation + Vector3(_kick_pitch, 0.0, 0.0)) * (PI / 180.0)),
			_model_rest_position + Vector3(0.0, 0.0, _kick_back))
	_kick_pivot.transform = kicked * rest.affine_inverse()


## Where the equipped gun's muzzle is in the world right now (its
## muzzle_offset, following the kick, sway and switch animations) -- where
## ShotTracer starts your visible bullets.
func muzzle_position() -> Vector3:
	var weapon := _weapons.current_weapon()
	if _model == null or weapon == null:
		return global_position
	return _firing_model().global_transform * _firing_muzzle_offset(weapon)


## The muzzle flash (MuzzleFlash: PS1 sprite, side key light + fill light)
## at the firing gun's muzzle_offset, for its muzzle_flash_time. One flash
## per hand, made once and reused.
func _spawn_muzzle_flash() -> void:
	var weapon := _weapons.current_weapon()
	if weapon == null:
		return
	var left := _firing_model() == _left_model
	_flash_for(left).flash(_firing_model(), _firing_muzzle_offset(weapon), _key_light_offset(weapon, left),
			maxf(weapon.muzzle_flash_time, 0.06))


## The key light's place beside the muzzle (camera space), mirrored for the
## left-hand gun so both light their own gun from the outside in.
func _key_light_offset(weapon: WeaponData, left: bool) -> Vector3:
	var offset := weapon.muzzle_light_offset
	return Vector3(-offset.x, offset.y, offset.z) if left else offset


func _flash_for(left: bool) -> MuzzleFlash:
	var index := 1 if left else 0
	if not is_instance_valid(_flashes[index]):
		_flashes[index] = MuzzleFlash.new()
		add_child(_flashes[index])
	return _flashes[index]


## Puts `weapon` in your hand. Nothing is loaded or built after the first
## time: the arms are kept (_ensure_arms()), take the weapon's hold pose
## (_pose_arms()), and the weapon's model is pulled out of _gun_models.
func _show_weapon(weapon: WeaponData) -> void:
	if _kick_tween:
		_kick_tween.kill()
	_kick_back = 0.0
	_kick_pitch = 0.0
	if is_instance_valid(_model):
		_model.visible = false
	_shown_weapon = weapon
	_pose_arms(weapon)

	# _model is a pivot. The weapon's position, rotation and scale are applied to
	# it, and the gun is shifted inside it so the GUN'S CENTRE sits on the pivot.
	# Imported models often have their origin far from the actual mesh, which
	# would make rotating or resizing swing the gun around wildly.
	var model: Node3D = null
	if is_instance_valid(_gun_models.get(weapon)):
		model = _gun_models[weapon]
	if model == null:
		model = Node3D.new()
		_hand_anchor().add_child(model)
		var gun: Node3D
		if weapon.viewmodel_scene:
			gun = weapon.viewmodel_scene.instantiate() as Node3D
			_strip_scene_extras(gun)
		else:
			gun = _make_placeholder(weapon)
		model.add_child(gun)
		_center_on_pivot(gun)
		_gun_models[weapon] = model
	_model = model
	_model.visible = true
	_gun = _model.get_child(0) as Node3D
	_show_left_gun(weapon)
	# A grenade slot with nothing in hand yet: empty hand until one's ready.
	_waiting_for_grenade = weapon.throws_grenade and _weapons.get_magazine_ammo() <= 0
	_gun.visible = not _waiting_for_grenade
	_apply_transform(weapon)
	_sight_center = _find_sight_center(weapon)
	# An empty launcher comes out empty.
	if weapon.fires_projectile:
		_show_loaded_projectile(_weapons.get_magazine_ammo() > 0)
	if _tuning_muzzle:
		_update_muzzle_marker(weapon)


## Puts the model where the weapon's data says it should be. The data is in
## camera space (where the gun sits on screen); the model hangs off the hand
## bone, so it's placed relative to where the hand is in the hold pose.
func _apply_transform(weapon: WeaponData) -> void:
	_model_rest_position = weapon.viewmodel_position
	_model_rest_rotation = weapon.viewmodel_rotation_degrees
	_model_rest_transform = Transform3D(
			_cant_basis(weapon) * Basis.from_euler(_model_rest_rotation * (PI / 180.0)) * Basis.from_scale(Vector3.ONE * weapon.viewmodel_scale),
			_model_rest_position)
	_apply_arms_transform(weapon)
	if _fp_arms and _two_handed(weapon):
		_apply_arm_offsets(weapon) # the support hand follows the gun if it moved
	if is_instance_valid(_model):
		_model.transform = _anchor_in_rig().affine_inverse() * _model_rest_transform
	if is_instance_valid(_left_model):
		# The arms are mirror images, so the left gun sits in the left hand
		# exactly as the right one sits in the right, mirrored.
		_left_model.transform = MIRROR_X * _model.transform * MIRROR_X


## The second gun for a dual-wielded weapon, in the left hand (made once per
## weapon, then kept); any other weapon puts it away.
func _show_left_gun(weapon: WeaponData) -> void:
	if is_instance_valid(_left_model):
		_left_model.visible = false
	_left_model = null
	_shot_from_left = false
	if not weapon.dual_wield or _fp_arms == null:
		return
	var model: Node3D = _left_models.get(weapon)
	if not is_instance_valid(model):
		model = Node3D.new()
		_fp_arms.left_hand_attachment.add_child(model)
		var gun := weapon.viewmodel_scene.instantiate() as Node3D if weapon.viewmodel_scene else _make_placeholder(weapon)
		_strip_scene_extras(gun)
		model.add_child(gun)
		_center_on_pivot(gun)
		_left_models[weapon] = model
	_left_model = model
	_left_model.visible = true


## The gun the last shot came from (the left one every other shot when dual
## wielding), and its muzzle_offset in that gun's own space.
func _firing_model() -> Node3D:
	return _left_model if _shot_from_left and is_instance_valid(_left_model) else _model


func _firing_muzzle_offset(weapon: WeaponData) -> Vector3:
	return MIRROR_X * weapon.muzzle_offset if _firing_model() == _left_model else weapon.muzzle_offset


## The gun tipped on its side for a canted grip (WeaponData.hold_cant_degrees):
## rolled round the view direction, on top of its own rotation. The new
## arms' right forearm turns over to match (FirstPersonArms.set_cant()).
func _cant_basis(weapon: WeaponData) -> Basis:
	if not use_new_arms or is_zero_approx(weapon.hold_cant_degrees):
		return Basis.IDENTITY
	return Basis(Vector3.BACK, deg_to_rad(weapon.hold_cant_degrees))


## What the gun models hang off: the right hand bone, or (no arms) the rig.
func _hand_anchor() -> Node3D:
	return _hand_attachment if is_instance_valid(_hand_attachment) else _kick_pivot


## Where _hand_anchor() is in _kick_pivot's space (= camera space at rest),
## with the arms in their current pose.
func _anchor_in_rig() -> Transform3D:
	if not is_instance_valid(_hand_attachment):
		return Transform3D.IDENTITY
	if _fp_arms:
		return _arms.transform * _fp_arms.bone_in_rig(_hand_bone)
	return _arms.transform * _skeleton_in_arms * _arms_skeleton.get_bone_global_pose(_hand_bone)


## A new character: the arms (and the models hanging off them) are rebuilt.
func _on_character_changed() -> void:
	_free_arms()
	if _shown_weapon:
		_show_weapon(_shown_weapon)


func _free_arms() -> void:
	for model in _gun_models.values():
		if is_instance_valid(model):
			(model as Node3D).queue_free()
	_gun_models.clear()
	_left_models.clear() # they hang off the arms, freed with them
	_left_model = null
	_model = null
	_gun = null
	if is_instance_valid(_arms):
		_arms.queue_free()
	_arms = null
	_fp_arms = null
	_arms_skeleton = null
	_hand_attachment = null
	_arms_hider = null
	_arms_meshes.clear()
	_arms_keep_left = -1


## Your character's arms, built once: a copy of the same character the body
## wears (PlayerModel), cut down to its arms, no shadow (the body already
## casts one), with a BoneAttachment3D on the right hand for the gun to hang
## off. False if there's no character to make them from.
func _ensure_arms() -> bool:
	if is_instance_valid(_arms):
		return true
	if use_new_arms:
		return _ensure_new_arms()
	if _player_model == null:
		return false
	var path := arms_character if not arms_character.is_empty() else _player_model.character_path
	if path.is_empty():
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	_arms = scene.instantiate() as Node3D
	# Hidden for its first frames: a fresh copy is drawn once in its rest
	# T-pose before the hold pose lands -- an arm flashing out sideways
	# across the bottom of the screen. _process shows it.
	_arms.visible = false
	_arms_hidden_frames = ARMS_REVEAL_FRAMES
	_kick_pivot.add_child(_arms)

	_arms_animator = PlayerModel.animator_for(_arms)
	_arms_library = AnimationLibrary.new()
	_arms_animator.add_animation_library(&"fp", _arms_library)

	var skeletons := _arms.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_arms_skeleton = skeletons[0] as Skeleton3D
		_skeleton_in_arms = _arms.global_transform.affine_inverse() * _arms_skeleton.global_transform
		# Sized like the body would size this character, from its own head height.
		var head := _arms_skeleton.find_bone("Head")
		_arms_fit_scale = _player_model.model_scale
		if head != -1:
			var head_in_model := _skeleton_in_arms * _arms_skeleton.get_bone_global_rest(head).origin
			_arms_fit_scale = _player_model.fit_scale_for(head_in_model.y)
		_hand_bone = _arms_skeleton.find_bone("RightHand")
		if _hand_bone != -1:
			_hand_attachment = BoneAttachment3D.new()
			_hand_attachment.bone_name = _arms_skeleton.get_bone_name(_hand_bone)
			_arms_skeleton.add_child(_hand_attachment)
		for node in _arms.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			var overrides: Array[Material] = []
			if mesh_instance.mesh:
				for surface in mesh_instance.mesh.get_surface_count():
					overrides.append(mesh_instance.get_surface_override_material(surface))
			_arms_meshes.append([mesh_instance, mesh_instance.mesh, overrides])
	for node in _arms.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gun models made before there were arms hang off the rig: move them.
	if is_instance_valid(_hand_attachment):
		for model in _gun_models.values():
			if is_instance_valid(model):
				(model as Node3D).reparent(_hand_attachment, false)
	return true


## The new arms (FirstPersonArms), built once. Their right hand bone is what
## the gun models hang off, like the character arms' RightHand.
func _ensure_new_arms() -> bool:
	_fp_arms = FirstPersonArms.new()
	_arms = _fp_arms
	_arms.visible = false
	_arms_hidden_frames = ARMS_REVEAL_FRAMES
	_kick_pivot.add_child(_arms)
	_arms_skeleton = _fp_arms.skeleton
	_hand_bone = _fp_arms.hand_bone
	_hand_attachment = _fp_arms.hand_attachment
	_arms_fit_scale = 1.0
	# The backpack, held out in the left hand when you open it (Tab).
	var body := _weapons.get_parent() as PlayerMovement if _weapons else null
	if body and body.is_multiplayer_authority():
		_bag_view = BackpackView.new()
		_bag_view.name = "Backpack"
		_kick_pivot.add_child(_bag_view)
		_bag_view.setup(body, _fp_arms)
	if _grapple:
		_grapple.arms = _fp_arms
	for model in _gun_models.values():
		if is_instance_valid(model):
			(model as Node3D).reparent(_hand_attachment, false)
	return true


## A weapon shown on the new arms for the first time (not fitted to them
## yet, WeaponData.arms_fitted).
##   One-handed: copies one_handed_arms_template (the Pistol) -- the same arm
##     placement, the gun at the same angle (turned by the two models'
##     model_facing_degrees, so a model facing another way still points the
##     same way) and its grip_point where the Pistol's grip is, in the hand.
##     Its size stays its own.
##   Two-handed and dual guns: the template's arm placement too (so the
##     right arm starts where the one-handed guns hold theirs), the gun seated
##     in that hand by its grip_point, keeping its own angle.
##   Grenades and healing items: the arms as the rig was made (camera bone
##     on your eye), the item seated in the hand by its grip_point.
## F2 tunes it from there (G for the grip); F3 saves it.
func _fit_to_new_arms(weapon: WeaponData) -> void:
	var template := one_handed_arms_template
	if weapon.one_handed and template and template != weapon and template.arms_fitted:
		weapon.arms_position = template.arms_position
		weapon.arms_rotation_degrees = template.arms_rotation_degrees
		weapon.arms_scale = template.arms_scale
		weapon.right_arm_offset = template.right_arm_offset
		weapon.right_arm_rotation_degrees = template.right_arm_rotation_degrees
		# The same held angle: the template's rotation with its model's own
		# facing taken off, then this model's facing put on.
		var held := Basis.from_euler(template.viewmodel_rotation_degrees * (PI / 180.0)) \
				* _facing(template).inverse() * _facing(weapon)
		weapon.viewmodel_rotation_degrees = held.get_euler() * (180.0 / PI)
		# The grip where the template's grip is (in the same hand).
		var template_grip := template.viewmodel_position + _gun_basis(template) * template.grip_point
		weapon.viewmodel_position = template_grip - _gun_basis(weapon) * weapon.grip_point
		_apply_arms_transform(weapon)
		_apply_arm_offsets(weapon)
	elif template and template.arms_fitted and not weapon.throws_grenade and weapon.heal_item < 0:
		# Two-handed (and dual) guns: the right arm starts where the one-handed
		# ones hold theirs, and the gun's seated in that hand by its grip.
		weapon.arms_position = template.arms_position
		weapon.arms_rotation_degrees = template.arms_rotation_degrees
		weapon.arms_scale = template.arms_scale
		weapon.right_arm_offset = template.right_arm_offset
		weapon.right_arm_rotation_degrees = template.right_arm_rotation_degrees
		_apply_arms_transform(weapon)
		_apply_arm_offsets(weapon)
		_seat_in_hand(weapon)
	else:
		weapon.arms_position = Vector3.ZERO
		weapon.arms_rotation_degrees = Vector3.ZERO
		weapon.arms_scale = 1.0
		_apply_arms_transform(weapon)
		_apply_arm_offsets(weapon)
		_seat_in_hand(weapon)
	weapon.arms_fitted = true


func _facing(weapon: WeaponData) -> Basis:
	return Basis.from_euler(weapon.model_facing_degrees * (PI / 180.0))


## The gun model's turn and size in camera space (cant included).
func _gun_basis(weapon: WeaponData) -> Basis:
	return _cant_basis(weapon) * Basis.from_euler(weapon.viewmodel_rotation_degrees * (PI / 180.0)) \
			* Basis.from_scale(Vector3.ONE * weapon.viewmodel_scale)


## Hands the weapon's per-arm nudges (camera space) to the new arms, turned
## into the arms' own space. A barrel-gripping support hand gets the gun's
## grip instead: its support point, the gun's cant, and its support_*
## settings, all in the arms' space -- the arms reach it by IK.
func _apply_arm_offsets(weapon: WeaponData) -> void:
	if _fp_arms == null:
		return
	var to_rig := _arms.transform.basis.inverse()
	var to_cam := _arms.transform.basis
	var right_turn := (to_rig * Basis.from_euler(weapon.right_arm_rotation_degrees * (PI / 180.0)) * to_cam).orthonormalized()
	var left_turn := (to_rig * Basis.from_euler(weapon.left_arm_rotation_degrees * (PI / 180.0)) * to_cam).orthonormalized()
	_fp_arms.set_right_grip(weapon.right_grip, weapon.right_grip_cup, weapon.right_finger_curl, weapon.right_wrist_degrees)
	_fp_arms.set_arm_offsets(to_rig * weapon.right_arm_offset, right_turn, to_rig * weapon.left_arm_offset, left_turn)
	if _two_handed(weapon) and weapon.support_pose == WeaponData.SupportPose.BARREL_GRIP:
		var from_camera := _arms.transform.affine_inverse()
		_fp_arms.set_support_grip(from_camera * _support_point_on_screen(weapon), to_rig * _cant_basis(weapon),
				weapon.support_cup, weapon.support_hand_rotation_degrees, to_rig * weapon.support_elbow_direction,
				weapon.support_elbow_degrees, weapon.support_twist_share, weapon.support_baked_pose)


## A gun held in both hands (the left one supporting it), not a one-handed
## gun, a dual pair, a grenade or a healing item.
func _two_handed(weapon: WeaponData) -> bool:
	return not weapon.one_handed and not weapon.dual_wield and not weapon.hide_left_arm \
			and not weapon.throws_grenade and weapon.heal_item < 0


## Where the support hand grips the gun, in camera space (the gun at rest):
## its support_point, or if that's unset, 35% of the way from the gun's
## middle (its grip) toward its muzzle -- on the barrel or handguard, close
## enough that the arm doesn't have to reach so far out it shows its end.
func _support_point_on_screen(weapon: WeaponData) -> Vector3:
	var point := weapon.support_point
	if point == Vector3.ZERO:
		point = weapon.grip_point.lerp(weapon.muzzle_offset, 0.35)
	return weapon.viewmodel_position + _gun_basis(weapon) * point


## Moves the gun (keeping its rotation and size) so its grip_point sits in
## the middle of the closed right hand.
func _seat_in_hand(weapon: WeaponData) -> void:
	if _fp_arms == null:
		return
	var socket := _arms.transform * _fp_arms.grip_socket_in_rig()
	weapon.viewmodel_position = socket - _gun_basis(weapon) * weapon.grip_point


## Gets the arms ready for `weapon`: its hold pose (the first frame of its
## hold_animation, held still so the hands can't drift off the grip), both
## arms or just the right, and its arms_position/rotation/scale. A weapon
## with no hold_animation is held with no arms showing.
func _pose_arms(weapon: WeaponData) -> void:
	if use_new_arms:
		_arms_wanted = _ensure_arms()
		if _arms_hidden_frames == 0:
			_arms.visible = _arms_wanted
		_fp_arms.set_cant(weapon.hold_cant_degrees)
		_fp_arms.set_dual(weapon.dual_wield)
		# Two-handed guns get the left hand up under them; one-handed guns,
		# grenades and healing items leave it free (the grapple's arm).
		_fp_arms.set_support(_two_handed(weapon), weapon.support_pose == WeaponData.SupportPose.BARREL_GRIP)
		if not weapon.arms_fitted:
			_fit_to_new_arms(weapon)
		else:
			_apply_arms_transform(weapon)
			_apply_arm_offsets(weapon)
		return
	_arms_wanted = weapon.hold_animation != null and _ensure_arms()
	if not is_instance_valid(_arms):
		return
	if _arms_hidden_frames == 0:
		_arms.visible = _arms_wanted
	if weapon.hold_animation:
		var pose_name := StringName("hold_%d" % weapon.hold_animation.get_instance_id())
		if not _arms_library.has_animation(pose_name):
			_arms_library.add_animation(pose_name, weapon.hold_animation)
		_arms_animator.play(StringName("fp/%s" % pose_name))
		_arms_animator.seek(0.0, true)
		_arms_animator.pause()
	if _arms_skeleton:
		_cut_arms(not weapon.hide_left_arm)
		if weapon.arms_position == Vector3.ZERO:
			_auto_place_arms(weapon, _arms_skeleton)
	_apply_arms_transform(weapon)


## Just the arms showing: both, or only the right when not `keep_left`. Only
## does anything when that changes. The mesh is cut (_strip_to_arms()) so
## there's no torso, head or legs left to swing into view however the view
## rig tilts (your full body is a separate model: look down and your legs
## are still there). If it can't be cut, the head and legs are shrunk away.
func _cut_arms(keep_left: bool) -> void:
	var state := 1 if keep_left else 0
	if state == _arms_keep_left:
		return
	_arms_keep_left = state
	if hide_torso and _strip_to_arms(_arms_skeleton, keep_left):
		return
	if is_instance_valid(_arms_hider):
		_arms_hider.queue_free()
	_arms_hider = HideBonesModifier.new()
	var hidden := PackedStringArray(["Head", "LeftUpperLeg", "RightUpperLeg"])
	if not keep_left:
		hidden.append("LeftUpperArm") # one hand only
	_arms_hider.bone_names = hidden
	_arms_skeleton.add_child(_arms_hider)


## Cuts every skinned mesh of the arms model (from its original, kept in
## _arms_meshes) down to the triangles whose corners are all mostly (half
## their skin weight or more) on a shoulder, arm or hand bone -- the right
## one, and the left too when `keep_left`. Anything else in the model
## (unskinned bits: hats, gear) is hidden. The cut meshes are made once per
## model and side and shared (_arms_only_meshes). False if the model has no
## shoulder/arm bones to keep, or no skinned mesh to cut.
func _strip_to_arms(skeleton: Skeleton3D, keep_left: bool) -> bool:
	var keep_bones := {}
	for side in (["Right", "Left"] if keep_left else ["Right"]):
		var root := skeleton.find_bone(side + "Shoulder")
		if root == -1:
			root = skeleton.find_bone(side + "UpperArm")
		if root != -1:
			_add_with_children(skeleton, root, keep_bones)
	if keep_bones.is_empty():
		return false
	var cut_any := false
	for entry in _arms_meshes:
		var mesh_instance := entry[0] as MeshInstance3D
		var original := entry[1] as Mesh
		var original_overrides: Array[Material] = entry[2]
		if original == null or mesh_instance.skin == null:
			mesh_instance.visible = false
			continue
		var key := "%d|%d|%s" % [original.get_instance_id(), mesh_instance.skin.get_instance_id(), keep_left]
		var cut: Array = _arms_only_meshes.get(key, [])
		if cut.is_empty():
			cut = _arms_only_mesh(original, mesh_instance.skin, skeleton, keep_bones)
			_arms_only_meshes[key] = cut
		var mesh: ArrayMesh = cut[0]
		var kept_surfaces: PackedInt32Array = cut[1]
		mesh_instance.mesh = mesh
		# The node's own per-surface materials follow their surfaces.
		for i in kept_surfaces.size():
			mesh_instance.set_surface_override_material(i, original_overrides[kept_surfaces[i]])
		cut_any = true
	return cut_any


func _add_with_children(skeleton: Skeleton3D, bone: int, into: Dictionary) -> void:
	into[bone] = true
	for child in skeleton.get_bone_children(bone):
		_add_with_children(skeleton, child, into)


## [the cut ArrayMesh, the original index of each surface it kept].
func _arms_only_mesh(mesh: Mesh, skin: Skin, skeleton: Skeleton3D, keep_bones: Dictionary) -> Array:
	# Skin bind slots -> skeleton bones (vertex bone indices are bind slots).
	var bind_bones := PackedInt32Array()
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		bind_bones.append(bone)
	var out := ArrayMesh.new()
	var kept_surfaces := PackedInt32Array()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones == null or weights == null or (bones as PackedInt32Array).is_empty():
			continue
		var per_vertex := (bones as PackedInt32Array).size() / vertices.size()
		var keep := PackedByteArray()
		keep.resize(vertices.size())
		for v in vertices.size():
			var on_arms := 0.0
			for k in per_vertex:
				var bind: int = bones[v * per_vertex + k]
				if bind >= 0 and bind < bind_bones.size() and keep_bones.has(bind_bones[bind]):
					on_arms += weights[v * per_vertex + k]
			keep[v] = 1 if on_arms >= 0.5 else 0
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null or (indices as PackedInt32Array).is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var kept := PackedInt32Array()
		for i in range(0, (indices as PackedInt32Array).size() - 2, 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			if keep[a] and keep[b] and keep[c]:
				kept.append(a)
				kept.append(b)
				kept.append(c)
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags: int = int(mesh.surface_get_format(surface)) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(surface))
		kept_surfaces.append(surface)
	return [out, kept_surfaces]


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
	# The posed hand, in the arms model's own space (this includes the FBX's
	# internal scaling).
	var hand_in_model := _skeleton_in_arms * skeleton.get_bone_global_pose(hand).origin
	weapon.arms_position = weapon.viewmodel_position - _arms_basis(weapon) * hand_in_model


## Puts the arms where weapon.arms_position/rotation say, in camera space
## (the arms are a child of _kick_pivot, which is camera space at rest).
func _apply_arms_transform(weapon: WeaponData) -> void:
	if not is_instance_valid(_arms):
		return
	if _fp_arms:
		# The new arms: as made (camera bone on the eye), then the weapon's tweak.
		var tweak := Basis.from_euler(weapon.arms_rotation_degrees * (PI / 180.0)) \
				* Basis.from_scale(Vector3.ONE * weapon.arms_scale)
		_arms.transform = Transform3D(tweak, weapon.arms_position) * _fp_arms.camera_transform()
		return
	_arms.transform = Transform3D(_arms_basis(weapon), weapon.arms_position)


## Some gun packs export the artist's whole scene: a light and a camera ride
## along with the model. In your hand that light would glow on everything
## all the time, so they're taken out (the model's own import can skip them
## too, see the MP5's).
func _strip_scene_extras(gun: Node) -> void:
	for node in gun.find_children("*", "Light3D", true, false) + gun.find_children("*", "Camera3D", true, false):
		node.get_parent().remove_child(node)
		node.queue_free()


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
	# Leaving the flash-light mode (another mode, or F2 off): its light goes out.
	if _tuning_light and key.keycode in [KEY_F2, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_M]:
		_tuning_light = false
		_flash_for(false).stop()
	if key.keycode == KEY_F2:
		_tuning = not _tuning
		_tune_label.visible = _tuning
		_preview_offset = Vector3.ZERO
		_show_use_pose(null)
	elif key.keycode == KEY_U and _tuning:
		_use_pose_shown = not _use_pose_shown
		if not _use_pose_shown:
			_show_use_pose(null)
		_update_label("")
		_update_label("")
	elif key.keycode == KEY_F3 and _tuning and _tuning_bag and is_instance_valid(_bag_view):
		var error := ResourceSaver.save(_bag_view.hold, BackpackView.HOLD_PATH)
		_update_label("SAVED the backpack hold" if error == OK else "Couldn't save the backpack hold (error %d)" % error)
	elif key.keycode == KEY_F3 and _tuning:
		_save_weapon()
	elif key.keycode == KEY_O and is_instance_valid(_bag_view):
		# O on its own (F2 not needed): the backpack hold's tuning.
		_tuning_bag = not _tuning_bag
		_tuning = _tuning or _tuning_bag
		_tune_label.visible = _tuning
		_bag_view.tuning = _tuning_bag
		_bag_finger = -1
		_tuning_bag_box = false
		_bag_view.show_container(false)
		_tuning_grip = false
		_tuning_right_arm = false
		_tuning_left_arm = false
		_tuning_arms = false
		_tuning_muzzle = false
		_tuning_aim = false
		_update_label("open the backpack (Tab) to see it" if _tuning_bag else "")
	elif _tuning_bag and key.keycode == KEY_X:
		_tuning_bag_box = not _tuning_bag_box
		_bag_view.show_container(_tuning_bag_box)
		_update_label("")
	elif _tuning_bag and key.keycode in [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]:
		_bag_finger = int(key.keycode - KEY_1) if key.keycode != KEY_0 else -1
		_update_label("")
	elif key.keycode == KEY_Y and _tuning and _fp_arms and _shown_weapon and not _tuning_bag:
		# Y: the right hand's own grip (turned on for this gun if it wasn't).
		_tuning_right_grip = not _tuning_right_grip
		_grip_finger = -1
		if _tuning_right_grip:
			_tuning_grip = false
			_tuning_right_arm = false
			_tuning_left_arm = false
			_tuning_arms = false
			_tuning_muzzle = false
			_tuning_aim = false
			if not _shown_weapon.right_grip:
				_shown_weapon.right_grip = true
				_apply_arm_offsets(_shown_weapon)
		_update_label("")
	elif _tuning_right_grip and key.keycode in [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]:
		_grip_finger = int(key.keycode - KEY_1) if key.keycode != KEY_0 else -1
		_update_label("")
	elif key.keycode == KEY_B and _tuning and _tuning_left_arm and _fp_arms and _shown_weapon:
		_shown_weapon.support_baked_pose = _fp_arms.bake_support_pose()
		_apply_arm_offsets(_shown_weapon)
		_update_label("BAKED -- F3 to save it into the weapon")
	elif key.keycode == KEY_N and _tuning and _tuning_left_arm and _shown_weapon:
		_shown_weapon.support_baked_pose = {}
		_apply_arm_offsets(_shown_weapon)
		_update_label("UNBAKED -- live IK again")
	elif key.keycode == KEY_I and _tuning:
		_tuning_aim = not _tuning_aim
		_tuning_arms = false
		_tuning_muzzle = false
		_preview_offset = Vector3.ZERO # back to the hip pose when leaving
		var weapon := _shown_weapon
		if weapon and _model:
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
	elif key.keycode == KEY_L and _tuning:
		_tuning_light = not _tuning_light
		_tuning_grip = false
		_tuning_right_arm = false
		_tuning_left_arm = false
		_tuning_arms = false
		_tuning_muzzle = false
		_tuning_aim = false
		if not _tuning_light:
			_flash_for(false).stop()
		_update_label("")
	elif (key.keycode == KEY_J or key.keycode == KEY_K) and _tuning and _fp_arms:
		var right := key.keycode == KEY_J
		var was_on := _tuning_right_arm if right else _tuning_left_arm
		_tuning_right_arm = right and not was_on
		_tuning_left_arm = not right and not was_on
		_tuning_grip = false
		_tuning_arms = false
		_tuning_muzzle = false
		_tuning_aim = false
		_update_label("")
	elif key.keycode == KEY_G and _tuning and _fp_arms:
		_tuning_grip = not _tuning_grip
		_tuning_right_arm = false
		_tuning_left_arm = false
		_tuning_arms = false
		_tuning_muzzle = false
		_tuning_aim = false
		if _shown_weapon:
			_update_muzzle_marker(_shown_weapon)
		_update_label("")
	elif key.keycode == KEY_H and _tuning:
		_tuning_arms = not _tuning_arms
		_tuning_grip = false
		_tuning_right_arm = false
		_tuning_left_arm = false
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
		_sway_pivot.position = aim_offset + _preview_offset
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
	# Flying: the hands eased down into the reload's lowered pose, and back up
	# after (on this layer, so the reload's and the switch's own dips aren't
	# touched).
	var body := _weapons.get_parent() as PlayerMovement if _weapons else null
	var lower := 1.0 if body and body.flying else 0.0
	_flight_lower = move_toward(_flight_lower, lower, delta * (4.0 if lower > _flight_lower else 3.0))
	var dip := smoothstep(0.0, 1.0, _flight_lower)
	# Starving (HungerCues): the hands shake.
	if tremble > 0.0:
		_tremble_time += delta
		_sway_position += Vector2(sin(_tremble_time * 31.0), sin(_tremble_time * 27.0 + 1.3)) * TREMBLE_AMOUNT * tremble

	# Aiming steadies the sway and carries the gun toward your eye.
	var calm := 1.0 - aim_steady
	_sway_pivot.position = Vector3(_sway_position.x, _sway_position.y, 0.0) * calm + aim_offset + _preview_offset + LOWERED_OFFSET * dip
	_sway_pivot.rotation_degrees = Vector3(_sway_tilt.x, _sway_tilt.y, 0.0) * calm + Vector3(LOWERED_TILT_DEGREES * dip, 0.0, 0.0)


func _process(delta: float) -> void:
	if _arms_hidden_frames > 0:
		_arms_hidden_frames -= 1
		if _arms_hidden_frames == 0 and is_instance_valid(_arms):
			_arms.visible = _arms_wanted
	_update_held_grenade()
	_keep_in_step()
	_tick_left_arm(delta)
	if _tuning and _tuning_bag and is_instance_valid(_bag_view):
		# The bag's tuning needs no gun in hand.
		var bag_x := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		var bag_y := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
		var bag_z := float(Input.is_key_pressed(KEY_PAGEDOWN)) - float(Input.is_key_pressed(KEY_PAGEUP))
		_tune_bag(bag_x, bag_y, bag_z, 0.1 if Input.is_key_pressed(KEY_CTRL) else 1.0, delta)
		_update_label("")
		return
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


	if _tuning_right_grip:
		_tune_right_grip(weapon, x, y, z, fine, delta)
		_update_label("")
		return
	if _tuning_muzzle:
		weapon.muzzle_offset += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		_update_muzzle_marker(weapon)
	elif _tuning_light:
		weapon.muzzle_light_offset += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		_flash_for(false).preview(_model, weapon.muzzle_offset, weapon.muzzle_light_offset)
	elif _tuning_left_arm and _two_handed(weapon) and weapon.support_pose == WeaponData.SupportPose.BARREL_GRIP:
		_tune_support(weapon, x, y, z, fine, delta)
	elif _tuning_right_arm or _tuning_left_arm:
		# One arm on its own; the gun keeps its place on screen
		# (_apply_transform() below re-hangs it off the moved hand).
		if Input.is_key_pressed(KEY_SHIFT):
			var turn := Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
			if _tuning_right_arm:
				weapon.right_arm_rotation_degrees += turn
			else:
				weapon.left_arm_rotation_degrees += turn
		else:
			var move := Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
			if _tuning_right_arm:
				weapon.right_arm_offset += move
			else:
				weapon.left_arm_offset += move
		_apply_arm_offsets(weapon)
	elif _tuning_grip:
		# Moved in meters on screen, stored in the gun's own space.
		if Input.is_key_pressed(KEY_SHIFT):
			weapon.viewmodel_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
		else:
			var gun_basis := _cant_basis(weapon) * Basis.from_euler(weapon.viewmodel_rotation_degrees * (PI / 180.0)) \
					* Basis.from_scale(Vector3.ONE * weapon.viewmodel_scale)
			weapon.grip_point -= gun_basis.inverse() * (Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta)
			var grow_gun := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
			weapon.viewmodel_scale = maxf(weapon.viewmodel_scale * (1.0 + grow_gun * TUNE_SCALE_SPEED * fine * delta), 0.0001)
		_seat_in_hand(weapon)
		_update_muzzle_marker(weapon)
	elif _tuning_aim:
		weapon.aim_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
	elif _tuning_arms:
		# H mode: the same keys move/rotate/resize the arms, and the gun stays
		# in the hand and goes with them (its viewmodel_* numbers are worked
		# out again from where the hand takes it).
		var grip := _model.transform
		if Input.is_key_pressed(KEY_SHIFT):
			weapon.arms_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
		else:
			weapon.arms_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
			var grow_arms := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
			weapon.arms_scale = maxf(weapon.arms_scale * (1.0 + grow_arms * TUNE_SCALE_SPEED * fine * delta), 0.0001)
		_apply_arms_transform(weapon)
		var carried := _anchor_in_rig() * grip
		weapon.viewmodel_position = carried.origin
		# The cant is added on top when shown, so it comes off what's stored.
		var upright := _cant_basis(weapon).inverse() * carried.basis.orthonormalized()
		weapon.viewmodel_rotation_degrees = upright.get_euler() * (180.0 / PI)
		weapon.viewmodel_scale = carried.basis.get_scale().x
	elif Input.is_key_pressed(KEY_SHIFT):
		weapon.viewmodel_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	else:
		weapon.viewmodel_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		var grow := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
		weapon.viewmodel_scale = maxf(weapon.viewmodel_scale * (1.0 + grow * TUNE_SCALE_SPEED * fine * delta), 0.0001)

	_apply_transform(weapon)
	# I mode: show the viewmodel where it'll sit when aimed, so you can line
	# up the sights.
	_preview_offset = aim_position_for(weapon) - weapon.viewmodel_position if _tuning_aim else Vector3.ZERO
	# U: a healing item held up at your mouth, as when it's used.
	_show_use_pose(weapon if _use_pose_shown and weapon.heal_item >= 0 else null)
	_update_label("")


## O (with the backpack open; no F2 needed): how it's held (BackpackHold).
##   Arrows / PageUp,Down: move the bag.  Shift: turn it.  +/-: its size.
##   Alt + those: move the hand on the bag.  Alt + Shift: turn the hand.
##   Ctrl + Alt + arrows / PageUp,Down: point the elbow.
##   [ / ]: a looser / tighter fist -- or, after 1-5, just that finger
##   (thumb, index, middle, ring, pinky; 0 back to the whole fist).
##   , / .: the elbow straighter / bent.
##   X: show (or hide) the items' container -- the pack's own shape -- as a
##   yellow wireframe; the keys keep tuning the hold.
##   F3 saves it (scenes/player/backpack_hold.tres).
func _tune_bag(x: float, y: float, z: float, fine: float, delta: float) -> void:
	var hold := _bag_view.hold

	var alt := Input.is_key_pressed(KEY_ALT)
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if alt and Input.is_key_pressed(KEY_CTRL):
		hold.elbow_direction = (hold.elbow_direction.normalized() + Vector3(x, y, -z) * 1.2 * delta).normalized()
	elif alt and shift:
		hold.hand_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	elif alt:
		hold.handle_point += Vector3(x, y, z) * 0.5 * fine * delta
	elif shift:
		hold.bag_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	else:
		hold.bag_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		var grow := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
		hold.bag_scale = maxf(hold.bag_scale * (1.0 + grow * TUNE_SCALE_SPEED * fine * delta), 0.01)
	var fist := float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))
	if _bag_finger < 0:
		hold.fist = clampf(hold.fist + fist * 0.6 * fine * delta, 0.0, 1.0)
	elif fist != 0.0:
		var curls := hold.finger_curl
		curls.resize(5)
		curls[_bag_finger] = clampf(curls[_bag_finger] + fist * 0.6 * fine * delta, -1.0, 1.0)
		hold.finger_curl = curls
	var bend := float(Input.is_key_pressed(KEY_PERIOD)) - float(Input.is_key_pressed(KEY_COMMA))
	hold.elbow_degrees = clampf(hold.elbow_degrees - bend * TUNE_ROTATE_SPEED * fine * delta, 40.0, 170.0)


## Y: the right hand's own grip for the gun in it.
##   [ / ]: a looser / tighter hand -- or, after 1-5, just that finger
##   (thumb, index, middle, ring, pinky; 0 back to the whole hand).
##   Shift + arrows / PageUp,Down: turn the hand at the wrist (the gun turns
##   with it).   F3 saves it onto the gun.
func _tune_right_grip(weapon: WeaponData, x: float, y: float, z: float, fine: float, delta: float) -> void:
	var curl := float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))
	if curl != 0.0:
		if _grip_finger < 0:
			weapon.right_grip_cup = clampf(weapon.right_grip_cup + curl * 0.6 * fine * delta, 0.0, 1.0)
		else:
			var curls := weapon.right_finger_curl
			curls.resize(5)
			curls[_grip_finger] = clampf(curls[_grip_finger] + curl * 0.6 * fine * delta, -1.0, 1.0)
			weapon.right_finger_curl = curls
	if Input.is_key_pressed(KEY_SHIFT):
		weapon.right_wrist_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	if curl != 0.0 or (Input.is_key_pressed(KEY_SHIFT) and (x != 0.0 or y != 0.0 or z != 0.0)):
		_apply_arm_offsets(weapon)


## K on a two-handed gun: the support hand (live IK, then baked).
##   Arrows / PageUp,Down: where the hand grips (the gun's support_point).
##   Shift + those: turn the hand.   Alt + arrows: which way the elbow points.
##   Alt + PageUp/Down: the elbow's bend (90 = an L).
##   [ / ]: less / more cup.   , / .: the forearm's share of the palm's turn.
##   B: bake the pose onto the gun (no IK after; F3 saves it).  N: unbake.
func _tune_support(weapon: WeaponData, x: float, y: float, z: float, fine: float, delta: float) -> void:
	if not weapon.support_baked_pose.is_empty():
		return # baked: N to unbake and tune again
	if weapon.support_point == Vector3.ZERO:
		# Not set yet: start from the worked-out spot it's been using.
		weapon.support_point = weapon.grip_point.lerp(weapon.muzzle_offset, 0.35)
	if Input.is_key_pressed(KEY_ALT):
		var elbow := (weapon.support_elbow_direction.normalized() + Vector3(x, y, 0.0) * fine * delta * 1.5).normalized()
		weapon.support_elbow_direction = elbow
		weapon.support_elbow_degrees = clampf(weapon.support_elbow_degrees - z * TUNE_ROTATE_SPEED * fine * delta, 40.0, 170.0)
	elif Input.is_key_pressed(KEY_SHIFT):
		weapon.support_hand_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	else:
		# Moved in meters on screen, stored in the gun's own space.
		weapon.support_point += _gun_basis(weapon).inverse() * (Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta)
	var cup := float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))
	weapon.support_cup = clampf(weapon.support_cup + cup * 0.6 * fine * delta, 0.0, 1.0)
	var share := float(Input.is_key_pressed(KEY_PERIOD)) - float(Input.is_key_pressed(KEY_COMMA))
	weapon.support_twist_share = clampf(weapon.support_twist_share + share * 0.6 * fine * delta, 0.0, 1.0)
	_apply_arm_offsets(weapon)


## The new arms' left arm follows the grapple: up and reaching while you
## hold E, out while the tentacle's out, down again after. Only with a
## one-handed weapon in hand (a two-handed one needs that hand).
func _tick_left_arm(delta: float) -> void:
	if _fp_arms == null or _grapple == null:
		return
	# The backpack out: it puts the left hand on its handle first. Put away:
	# the arm goes back to what the gun wants.
	if is_instance_valid(_bag_view):
		var out := _bag_view.update(delta)
		if _bag_was_out and not out:
			_bag_view.release_arm()
			if _shown_weapon:
				_apply_arm_offsets(_shown_weapon)
		_bag_was_out = out
	var free_hand := _shown_weapon != null and _shown_weapon.one_handed and _arms.visible
	_fp_arms.tick(delta, _grapple.is_coiling(), _grapple.coil, _grapple.is_out(), free_hand)


## Holds the viewmodel in the healing animation's top pose -- `weapon` (an
## item) at your mouth, tipped back (_on_item_used()) -- or puts it back with
## null. Only for the F2 tool.
func _show_use_pose(weapon: WeaponData) -> void:
	if weapon:
		_set_pivot(weapon.viewmodel_position)
		position = ITEM_MOUTH_POINT - weapon.viewmodel_position
		rotation_degrees.x = ITEM_TIP_DEGREES
	elif _pivot_on or position != Vector3.ZERO:
		if _switch_tween and _switch_tween.is_running():
			return
		_set_pivot(null)
		position = Vector3.ZERO
		rotation_degrees.x = 0.0


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
	# The grip marker (blue): where the hand wraps, F2 > G.
	if not is_instance_valid(_grip_marker):
		_grip_marker = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.012
		ball.height = 0.024
		_grip_marker.mesh = ball
		var blue := StandardMaterial3D.new()
		blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		blue.no_depth_test = true # seen through the closed hand
		blue.albedo_color = Color(0.2, 0.5, 1.0)
		_grip_marker.material_override = blue
	if _grip_marker.get_parent() != _model:
		if _grip_marker.get_parent():
			_grip_marker.get_parent().remove_child(_grip_marker)
		_model.add_child(_grip_marker)
	_grip_marker.position = weapon.grip_point
	_grip_marker.visible = _tuning_grip
	# Fixed size on screen whatever the gun's scale.
	_grip_marker.scale = Vector3.ONE / maxf(weapon.viewmodel_scale, 0.0001)


func _save_weapon() -> void:
	var weapon := _shown_weapon
	if weapon == null or weapon.resource_path.is_empty():
		return
	# Keep the file's uid: other scenes may point at the weapon by it, and a
	# plain save hands the file a new one.
	var uid := ResourceLoader.get_resource_uid(weapon.resource_path)
	# A hand placement (weapons/hand/): saved without the model it was shown
	# with (made fresh each time from the item).
	var hand_scene: PackedScene = null
	if weapon.resource_path.begins_with("res://weapons/hand/"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://weapons/hand"))
		hand_scene = weapon.viewmodel_scene
		weapon.viewmodel_scene = null
	var result := ResourceSaver.save(weapon, weapon.resource_path)
	if hand_scene:
		weapon.viewmodel_scene = hand_scene
	if result == OK and uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(weapon.resource_path, uid)
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
	if _tuning_right_grip and _shown_weapon and _tune_label:
		var gun := _shown_weapon
		var curls := gun.right_finger_curl
		curls.resize(5)
		_tune_label.text = ("TUNING THE RIGHT HAND'S GRIP (%s)\nhand %.2f   fingers: thumb %+.2f  index %+.2f  middle %+.2f  ring %+.2f  pinky %+.2f\n"
				+ "wrist turned (%.1f, %.1f, %.1f)   [ ] now curls: %s\n\n"
				+ "[ ] = curl   1-5 = pick a finger   0 = whole hand\nShift + arrows/PgUp,PgDn = turn the wrist (the gun turns with it)\n"
				+ "Ctrl = finer   F3 = save onto the gun   Y = done\n%s") % [gun.weapon_name, gun.right_grip_cup,
				curls[0], curls[1], curls[2], curls[3], curls[4], gun.right_wrist_degrees.x, gun.right_wrist_degrees.y,
				gun.right_wrist_degrees.z, "whole hand" if _grip_finger < 0 else ["thumb", "index", "middle", "ring", "pinky"][_grip_finger], message]
		return
	if _tuning_bag and is_instance_valid(_bag_view) and _tune_label:
		var hold := _bag_view.hold
		var curls := hold.finger_curl
		curls.resize(5)
		var finger_names := ["thumb", "index", "middle", "ring", "pinky"]
		var sizes := ""
		for kind_name in hold.item_scales:
			sizes += "%s %.2f  " % [String(kind_name).to_lower(), float(hold.item_scales[kind_name])]
		message = ("item sizes: " + sizes + "\n" if not sizes.is_empty() else "") + "Hold Left Alt over an item + scroll = that kind's size\n" + message

		_tune_label.text = ("TUNING THE BACKPACK HOLD (Tab to open it)\nbag at (%.3f, %.3f, %.3f)  turned (%.1f, %.1f, %.1f)  size %.3f\n"
				+ "hand on bag (%.2f, %.2f, %.2f)  turned (%.1f, %.1f, %.1f)\n"
				+ "elbow points (%.2f, %.2f, %.2f)  bend %.0f\n"
				+ "fist %.2f   fingers: thumb %+.2f  index %+.2f  middle %+.2f  ring %+.2f  pinky %+.2f   [ ] now curls: %s\n\n"
				+ "Arrows/PgUp,PgDn = move bag   Shift = turn bag   +/- = size\nAlt = move hand on it   Alt+Shift = turn hand\n"
				+ "Ctrl+Alt = point the elbow   , . = elbow bend\n"
				+ "[ ] = curl   1-5 = pick a finger   0 = whole fist\nX = show the items' container (the pack's shape)   Ctrl = finer   F3 = save   O = done\n%s") % [
				hold.bag_position.x, hold.bag_position.y, hold.bag_position.z,
				hold.bag_rotation_degrees.x, hold.bag_rotation_degrees.y, hold.bag_rotation_degrees.z, hold.bag_scale,
				hold.handle_point.x, hold.handle_point.y, hold.handle_point.z,
				hold.hand_rotation_degrees.x, hold.hand_rotation_degrees.y, hold.hand_rotation_degrees.z,
				hold.elbow_direction.x, hold.elbow_direction.y, hold.elbow_direction.z, hold.elbow_degrees,
				hold.fist, curls[0], curls[1], curls[2], curls[3], curls[4],
				"whole fist" if _bag_finger < 0 else finger_names[_bag_finger], message]
		return
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
	elif _tuning_grip:
		target = "GRIP (blue dot sits in the hand)"
		p = weapon.grip_point
	elif _tuning_light:
		target = "FLASH KEY LIGHT (from the muzzle; stays lit)"
		p = weapon.muzzle_light_offset
	elif _tuning_right_arm:
		target = "RIGHT ARM only (gun stays put)"
		p = weapon.right_arm_offset
		r = weapon.right_arm_rotation_degrees
	elif _tuning_left_arm and _two_handed(weapon) and weapon.support_pose == WeaponData.SupportPose.BARREL_GRIP:
		target = ("SUPPORT HAND (%s)  cup %.2f  elbow bend %.0f  forearm twist %.2f\n"
				+ "arrows/PgUp,PgDn = grip spot   Shift = turn hand   Alt + arrows = elbow direction   Alt + PgUp,PgDn = bend\n"
				+ "[ ] = cup   , . = forearm twist share   B = bake pose   N = unbake") % [
				"BAKED" if not weapon.support_baked_pose.is_empty() else "live IK", weapon.support_cup,
				weapon.support_elbow_degrees, weapon.support_twist_share]
		p = weapon.support_point
		r = weapon.support_hand_rotation_degrees
	elif _tuning_left_arm:
		target = "LEFT ARM only (gun stays put)"
		p = weapon.left_arm_offset
		r = weapon.left_arm_rotation_degrees
	elif _tuning_aim:
		target = "AIMED POSITION"
		p = weapon.aim_position
	_tune_label.text = "TUNING %s: %s\nposition  (%.3f, %.3f, %.3f)\nrotation  (%.1f, %.1f, %.1f)\nscale     %.4f%s\n\nArrows = move   PageUp/PageDown = forward/back\nShift + arrows / PageUp,Down = rotate\n+ / - = resize    Ctrl = 10x finer\nGUN moves the item in your hand.  H = arms (item goes with the hand)\nU = hold a healing item at your mouth (to check it there)\nG = grip (gun stays in the hand)   J / K = right / left arm alone\nM = muzzle   L = flash light   I = aimed position   F3 = save   F2 = off\n%s" \
			% [target, weapon.weapon_name, p.x, p.y, p.z, r.x, r.y, r.z, s,
			"   (AT MOUTH)" if _use_pose_shown else "", message]
