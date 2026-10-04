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
const MUZZLE_FLASH_TIME := 0.05

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

## Dev tool speeds while a key is held.
const TUNE_MOVE_SPEED := 0.3     # meters per second
const TUNE_ROTATE_SPEED := 45.0  # degrees per second
const TUNE_SCALE_SPEED := 0.6    # fraction of current size per second

@export var weapons_path: NodePath

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
var _model_rest_position: Vector3
var _model_rest_rotation: Vector3
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


func _ready() -> void:
	_sway_pivot = Node3D.new()
	add_child(_sway_pivot)
	_weapons.weapon_switched.connect(_on_weapon_switched)
	_weapons.shot_fired.connect(_on_shot_fired)
	_weapons.reload_started.connect(_on_reload_started)
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
	var kick_distance := weapon.recoil_kick_distance if weapon else 0.06
	var kick_rotation := weapon.recoil_kick_rotation_degrees if weapon else 4.0
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


## A brief additive glow + a real light flash right at the equipped weapon's
## OWN muzzle_offset (per-weapon, tunable in-game -- see muzzle_offset's own
## comment in weapon_data.gd). Removes itself after MUZZLE_FLASH_TIME.
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
	var timer := get_tree().create_timer(MUZZLE_FLASH_TIME)
	timer.timeout.connect(light.queue_free)
	timer.timeout.connect(glow.queue_free)


func _show_weapon(weapon: WeaponData) -> void:
	if _kick_tween:
		_kick_tween.kill()
	if _model:
		_model.queue_free()

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
	_center_on_pivot(gun)
	_apply_transform(weapon)
	if _tuning_muzzle:
		_update_muzzle_marker(weapon)


## Puts the model where the weapon's data says it should be.
func _apply_transform(weapon: WeaponData) -> void:
	_model_rest_position = weapon.viewmodel_position
	_model_rest_rotation = weapon.viewmodel_rotation_degrees
	_model.position = _model_rest_position
	_model.rotation_degrees = _model_rest_rotation
	_model.scale = Vector3.ONE * weapon.viewmodel_scale


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
	elif key.keycode == KEY_M and _tuning:
		_tuning_muzzle = not _tuning_muzzle
		var weapon := _weapons.current_weapon()
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
		_sway_pivot.position = Vector3.ZERO
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
	_sway_pivot.position = Vector3(_sway_position.x, _sway_position.y, 0.0)
	_sway_pivot.rotation_degrees = Vector3(_sway_tilt.x, _sway_tilt.y, 0.0)


func _process(delta: float) -> void:
	if not _tuning or _model == null:
		return
	var weapon := _weapons.current_weapon()
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
	elif Input.is_key_pressed(KEY_SHIFT):
		weapon.viewmodel_rotation_degrees += Vector3(y, -x, z) * TUNE_ROTATE_SPEED * fine * delta
	else:
		weapon.viewmodel_position += Vector3(x, y, z) * TUNE_MOVE_SPEED * fine * delta
		var grow := float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))
		weapon.viewmodel_scale = maxf(weapon.viewmodel_scale * (1.0 + grow * TUNE_SCALE_SPEED * fine * delta), 0.0001)

	_apply_transform(weapon)
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
	var weapon := _weapons.current_weapon()
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
	var weapon := _weapons.current_weapon()
	if weapon == null:
		return
	var p := weapon.viewmodel_position
	var r := weapon.viewmodel_rotation_degrees
	_tune_label.text = "TUNING: %s\nposition  (%.3f, %.3f, %.3f)\nrotation  (%.1f, %.1f, %.1f)\nscale     %.4f\n\nArrows = move   PageUp/PageDown = forward/back\nShift + arrows / PageUp,Down = rotate\n+ / - = resize    Ctrl = 10x finer    F3 = save    F2 = off\n%s" \
			% [weapon.weapon_name, p.x, p.y, p.z, r.x, r.y, r.z, weapon.viewmodel_scale, message]