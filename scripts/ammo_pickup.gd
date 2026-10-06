class_name AmmoPickup
extends RigidBody3D

## A loose pile of ammo in the level -- a REAL physics object (falls, sits on
## the ground, reacts to being shot or kicked, can be grabbed with F), not a
## floating trigger. Walk close enough and it's added to the shared ammo
## pool for that type (every weapon using BULLETS, say, draws from the same
## pool), then it removes itself.
##
## Same structure as WeaponPickup: this node is the physical body, the child
## PickupArea (Area3D) is the separate non-physical zone that detects the
## player and actually triggers the pickup. See WeaponPickup's own comment
## for why those two jobs are kept as separate shapes.

@export var ammo_type: WeaponData.AmmoType = WeaponData.AmmoType.BULLETS
@export var amount: int = 20

@onready var _pickup_area: Area3D = $PickupArea


func _ready() -> void:
	add_to_group(InteractHighlight.GROUP) # outlined when you look at it
	_pickup_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var weapons := body.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return
	weapons.add_ammo(ammo_type, amount)
	queue_free()
