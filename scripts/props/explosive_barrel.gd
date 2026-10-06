class_name ExplosiveBarrel
extends RigidBody3D

## A red barrel that blows up when it's shot or caught in a blast -- the same
## explosion as the RPG (Explosion), so barrels set each other off in chains.
## A real physics prop until then: shots and blasts shove it around.
##
## Rule 1 (co-op): its Health only takes damage on the host (like everything
## else), so only the host decides when it explodes. Each client will play
## the look from the host's "explosion here" message (Explosion.play_effects).

## Doesn't bleed when shot -- WeaponController leaves a bullet hole instead.
var bleeds := false

@export_group("Explosion")
## Same numbers as the RPG's rocket by default (weapons/rpg.tres).
@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 5.6
@export var explosion_knockback: float = 14.0
## What a player takes at the centre instead of explosion_damage.
@export var explosion_player_damage: float = 10.0
## Once it's dead it waits a random moment in this range (seconds) before
## going off -- a short fuse, so a row of barrels goes off one-two-three
## instead of all in the same frame.
@export var fuse_min: float = 0.05
@export var fuse_max: float = 0.25

## Middle of the barrel, where it blows up from (its origin is at the bottom).
const CENTER_HEIGHT := 0.55

var _exploded := false


func _ready() -> void:
	($Health as Health).died.connect(_on_died)


func _on_died(attacker_id: int, _is_critical: bool) -> void:
	get_tree().create_timer(randf_range(fuse_min, fuse_max)).timeout.connect(_explode.bind(attacker_id))


func _explode(attacker_id: int) -> void:
	if _exploded:
		return
	_exploded = true
	var settings := Explosion.Settings.new()
	settings.damage = explosion_damage
	settings.radius = explosion_radius
	settings.knockback = explosion_knockback
	settings.player_damage = explosion_player_damage
	# Whoever set it off gets the credit for what it kills.
	settings.attacker_id = attacker_id
	# Out of the way first, so the blast doesn't count the barrel itself.
	collision_layer = 0
	visible = false
	Explosion.explode(self, global_position + global_basis.y * CENTER_HEIGHT, settings)
	queue_free()
