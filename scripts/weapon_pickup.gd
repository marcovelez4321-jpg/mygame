class_name WeaponPickup
extends RigidBody3D

## A weapon lying in the level -- a REAL physics object (falls under
## gravity, sits on the ground, reacts to being shot, can be shoved or
## grabbed with F like any other prop), not a floating trigger. Walk close
## enough and it's added to your permanent inventory -- "found in levels,
## kept permanently" from the original design, not a Doom-style temporary
## spawn.
##
## Structure: this node itself is the physical body (collision + mesh,
## exactly like physics_prop.tscn); a child PickupArea (Area3D) is the
## SEPARATE, non-physical detection zone that actually triggers the pickup.
## They're deliberately different things -- the physical shape is how it
## collides with the world and gets kicked around, the pickup zone is how it
## knows a player got close, and mixing those two jobs into one shape would
## make the physical collision also have to double as a "walk through me to
## grab me" trigger, which isn't what either one wants to be tuned like.

@export var weapon: WeaponData
## Ammo handed over along with the weapon itself, so finding a shotgun
## doesn't leave you holding an empty one.
@export var ammo_amount: int = 12

@onready var _pickup_area: Area3D = $PickupArea


func _ready() -> void:
	add_to_group(InteractHighlight.GROUP) # outlined when you look at it
	_pickup_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var weapons := body.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return # not a player (or a player scene missing WeaponController)
	weapons.pickup_weapon(weapon, ammo_amount)
	queue_free()
