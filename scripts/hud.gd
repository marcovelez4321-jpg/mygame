extends CanvasLayer

## How long the crosshair stays tinted after a hit, in seconds.
const HIT_MARKER_TIME := 0.15
const HIT_COLOR := Color(1.0, 0.25, 0.25, 1.0)
const KILL_COLOR := Color(1.0, 0.9, 0.2, 1.0)

## Red screen flash when the player is hurt: how opaque it starts (0 to 1)
## and how long it takes to fade out.
const DAMAGE_FLASH_ALPHA := 0.4
const DAMAGE_FLASH_TIME := 0.3

## How long a "picked up X" message stays fully visible before fading, and
## how long the fade itself takes.
const PICKUP_HOLD_TIME := 1.2
const PICKUP_FADE_TIME := 0.5

## Screen blood droplets on a close-range kill: a handful of splats scattered
## near the screen edges (like it splashed in from off-frame), punching in
## fast, held briefly, then fading out quickly -- ~2 seconds total. Reuses
## BloodFX's own procedural splat texture as flat 2D sprites instead of a 3D
## decal -- same shape, same generation, just drawn on the HUD.
const SCREEN_BLOOD_COUNT := 5
const SCREEN_BLOOD_SPLAT_IN_TIME := 0.08
const SCREEN_BLOOD_HOLD_TIME := 1.2
const SCREEN_BLOOD_FADE_TIME := 0.7

@onready var speed_label: Label = $SpeedLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var health_label: Label = $HealthLabel
@onready var death_label: Label = $DeathLabel
@onready var crosshair: ColorRect = $Crosshair
@onready var damage_flash: ColorRect = $DamageFlash
@onready var weapon_wheel: Control = $WeaponWheel
@onready var pickup_label: Label = $PickupLabel
## Deadlock-style stamina pips: the width of each Fill rect (0..PIP_WIDTH) is
## how full that charge is. Left-to-right = pip index, matching
## player_movement.gd's stamina_charges count.
@onready var stamina_pips: Array[ColorRect] = [$StaminaBar/Pip0Fill, $StaminaBar/Pip1Fill, $StaminaBar/Pip2Fill]
const PIP_WIDTH := 14.0

var player: CharacterBody3D
var _player_health: Health
var _default_crosshair_color: Color
var _hit_tween: Tween
var _flash_tween: Tween
var _pickup_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	_default_crosshair_color = crosshair.color
	call_deferred("_find_player")


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.weapons.hit_confirmed.connect(_on_hit_confirmed)
	player.weapons.inventory_changed.connect(_refresh_wheel)
	player.weapons.weapon_switched.connect(_on_weapon_switched)
	player.weapons.picked_up.connect(_on_picked_up)
	player.weapons.gory_kill_nearby.connect(_on_gory_kill_nearby)
	# The wheel is local UI: it reports a pick, and the player turns that into
	# part of its input packet.
	weapon_wheel.weapon_chosen.connect(player.request_weapon)
	_refresh_wheel()
	_player_health = player.get_node("Health") as Health
	_player_health.damaged.connect(_on_player_damaged)
	_player_health.died.connect(_on_player_died)


func _process(_delta: float) -> void:
	if not player:
		_find_player()
		return
	var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed_label.text = "Speed: %.1f m/s" % horiz_speed
	var weapon: WeaponData = player.weapons.current_weapon()
	var weapon_name := weapon.weapon_name if weapon else "No weapon"
	var reloading: bool = player.weapons.is_reloading()
	ammo_label.text = "%s  %s / %d%s" % [
		weapon_name,
		"..." if reloading else str(player.weapons.get_magazine_ammo()),
		player.weapons.get_ammo(),
		" (reloading)" if reloading else "",
	]
	health_label.text = "Health: %d" % ceili(_player_health.current_health)
	_update_stamina_bar()


## Each pip is full (PIP_WIDTH) if that charge is available, empty if it
## isn't, and the ONE pip currently regenerating (index == stamina_charges)
## fills in gradually as stamina_recharge_fraction climbs toward 1 -- reads
## the player's stamina fields directly rather than a signal since this is
## a smooth, every-frame fill, not an event.
func _update_stamina_bar() -> void:
	for i in stamina_pips.size():
		var fraction := 0.0
		if i < player.stamina_charges:
			fraction = 1.0
		elif i == player.stamina_charges:
			fraction = player.stamina_recharge_fraction
		stamina_pips[i].size.x = PIP_WIDTH * fraction


func _refresh_wheel() -> void:
	weapon_wheel.set_weapons(player.weapons.get_owned_weapons(), player.weapons.get_current_index())


func _on_weapon_switched(_weapon: WeaponData, _draw_time: float) -> void:
	_refresh_wheel()


## Scatters a handful of blood splats near the screen edges, holds, then
## fades out -- see SCREEN_BLOOD_* consts' own comment.
func _on_gory_kill_nearby() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	for i in SCREEN_BLOOD_COUNT:
		var splat := TextureRect.new()
		splat.texture = BloodFX.get_screen_splat_texture()
		splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var size := randf_range(60.0, 160.0)
		splat.size = Vector2(size, size)
		splat.pivot_offset = Vector2(size, size) * 0.5
		# Confined to the outer edges on BOTH axes -- i.e. one of the four
		# corners -- so nothing ever lands over the crosshair/center of the
		# screen where the actual action is. Like it splashed in from
		# off-frame, not dead center.
		var from_left := randf() < 0.5
		var from_top := randf() < 0.5
		var x_range := viewport_size.x * 0.3
		var y_range := viewport_size.y * 0.3
		splat.position = Vector2(
			randf_range(0.0, x_range) if from_left else randf_range(viewport_size.x - x_range - size, viewport_size.x - size),
			randf_range(0.0, y_range) if from_top else randf_range(viewport_size.y - y_range - size, viewport_size.y - size)
		)
		splat.rotation = randf() * TAU
		splat.modulate = Color(1.0, 1.0, 1.0, 0.0)
		splat.scale = Vector2.ONE * 1.4 # punches IN (shrinks to rest size) as it fades in, reads as a fast splat rather than a plain fade
		add_child(splat)

		var target_alpha := randf_range(0.6, 0.9)
		var tween := splat.create_tween()
		tween.set_parallel(true)
		tween.tween_property(splat, "modulate:a", target_alpha, SCREEN_BLOOD_SPLAT_IN_TIME)
		tween.tween_property(splat, "scale", Vector2.ONE, SCREEN_BLOOD_SPLAT_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_interval(SCREEN_BLOOD_HOLD_TIME)
		tween.chain().tween_property(splat, "modulate:a", 0.0, SCREEN_BLOOD_FADE_TIME)
		tween.chain().tween_callback(splat.queue_free)


## Hit marker: the crosshair flashes red on a hit and yellow on a kill.
func _on_hit_confirmed(killed: bool) -> void:
	if _hit_tween:
		_hit_tween.kill()
	crosshair.color = KILL_COLOR if killed else HIT_COLOR
	_hit_tween = create_tween()
	_hit_tween.tween_property(crosshair, "color", _default_crosshair_color, HIT_MARKER_TIME)


## Quick red flash over the whole screen when the player takes damage.
## Screen-only: it never affects gameplay.
func _on_player_damaged(_amount: float, _attacker_id: int) -> void:
	if _flash_tween:
		_flash_tween.kill()
	damage_flash.color.a = DAMAGE_FLASH_ALPHA
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, DAMAGE_FLASH_TIME)


func _on_player_died(_attacker_id: int) -> void:
	death_label.visible = true


## "Picked up X" / "+N Shells" message: pops in oversized and snaps down to
## normal size (not a plain fade-in) -- that little overshoot-and-settle is
## most of what makes a pickup feel like it LANDED instead of just appearing.
## Holds fully visible for a beat, then fades out.
func _on_picked_up(weapon: WeaponData, ammo_type: WeaponData.AmmoType, ammo_amount: int) -> void:
	if weapon != null:
		pickup_label.text = "Picked up %s" % weapon.weapon_name
	else:
		# WeaponData.AmmoType.keys() returns an untyped Array -- indexing it
		# yields a Variant that := can't statically resolve, even though it's
		# always a String at runtime (same class of bug as physics_grabber.gd's
		# earlier "offset" crash).
		var ammo_name: String = WeaponData.AmmoType.keys()[ammo_type].capitalize()
		pickup_label.text = "+%d %s" % [ammo_amount, ammo_name]

	if _pickup_tween:
		_pickup_tween.kill()
	pickup_label.pivot_offset = pickup_label.size * 0.5
	pickup_label.scale = Vector2(1.3, 1.3)
	pickup_label.modulate.a = 1.0
	_pickup_tween = create_tween()
	_pickup_tween.tween_property(pickup_label, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pickup_tween.tween_interval(PICKUP_HOLD_TIME)
	_pickup_tween.tween_property(pickup_label, "modulate:a", 0.0, PICKUP_FADE_TIME)
