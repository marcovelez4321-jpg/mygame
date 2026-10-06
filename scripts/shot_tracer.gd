extends Node

## Draws the player's bullets: one visible bullet with a streak per ray,
## flying from the gun's muzzle to wherever it landed (BulletFX, tuned in
## fx/bullet_trail.tres). Presentation only -- it never affects gameplay.

@export var enabled: bool = true

@onready var _weapons: WeaponController = get_parent().get_node("WeaponController")
## Shots start at the Head node's position (player_movement.gd passes it in).
@onready var _head: Node3D = get_parent().get_node("Head")
@onready var _viewmodel: Viewmodel = get_parent().get_node_or_null("Head/Camera3D/Viewmodel") as Viewmodel


func _ready() -> void:
	_weapons.shot_resolved.connect(_on_shot_resolved)


func _on_shot_resolved(from: Vector3, to: Vector3, _hit_target: bool) -> void:
	if not enabled:
		return
	# The real ray starts at your eye, where a bullet would just be a dot on
	# your own screen -- so a shot's first stretch is drawn from the gun's
	# muzzle instead. A later stretch (a pellet punching through one body into
	# the next) starts where it came out, which isn't at the eye.
	var start := from
	if _viewmodel and from.distance_to(_head.global_position) < 0.1:
		start = _viewmodel.muzzle_position()
	BulletFX.spawn(get_tree().current_scene, start, to)
