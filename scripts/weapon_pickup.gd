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
## Whoever just dropped it: ignored until they've stepped off it (or a gun
## swapped out at your feet would be picked straight back up).
var _ignored: Node


func _ready() -> void:
	# A bare pickup (no shape of its own in its scene): shows its gun.
	if weapon and not get_children().any(func(child: Node) -> bool: return child is CollisionShape3D):
		_show_gun(self, weapon)
	add_to_group(InteractHighlight.GROUP) # outlined when you look at it
	_pickup_area.body_entered.connect(_on_body_entered)
	_pickup_area.body_exited.connect(func(body: Node3D) -> void:
		if body == _ignored:
			_ignored = null
	)


func _on_body_entered(body: Node3D) -> void:
	if body == _ignored:
		return
	var weapons := body.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return # not a player (or a player scene missing WeaponController)
	weapons.pickup_weapon(weapon, ammo_amount)
	queue_free()


## `weapon` dropped at `by`'s feet as a pickup: a physics body with the gun's
## own model and a box round it, and a pickup zone that ignores `by` until
## they step off it.
static func drop(weapon: WeaponData, by: Node3D) -> WeaponPickup:
	if weapon == null or by == null or not by.is_inside_tree():
		return null
	var pickup := WeaponPickup.new()
	pickup.weapon = weapon
	pickup.ammo_amount = 0
	pickup.mass = 3.0
	_show_gun(pickup, weapon)
	var area := Area3D.new()
	area.name = "PickupArea"
	var zone := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	zone.shape = sphere
	area.add_child(zone)
	pickup.add_child(area)
	pickup._ignored = by
	var level := by.get_tree().current_scene
	(level if level else by.get_tree().root).add_child(pickup)
	pickup.global_position = by.global_position + Vector3.UP * 0.6 - by.global_basis.z * 0.5
	return pickup

## The gun on the ground, at about its real length (WeaponData.
## backpack_length, or LONG_GUN for one without; a model's own units are no
## guide -- the sawed-off's is 5 long), facing forward, with a box round it.
const LONG_GUN := 0.9


static func _show_gun(body: Node3D, gun: WeaponData) -> void:
	var size := Vector3(0.6, 0.18, 0.2)
	if gun.viewmodel_scene:
		var model := gun.viewmodel_scene.instantiate() as Node3D
		if model:
			var holder := Node3D.new()
			holder.name = "Model"
			holder.add_child(model)
			model.basis = Basis.from_euler(gun.model_facing_degrees * (PI / 180.0))
			var box := BackpackView._bounds(holder)
			var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
			var fit := (gun.backpack_length if gun.backpack_length > 0.0 else LONG_GUN) / maxf(longest, 0.0001)
			holder.scale = Vector3.ONE * fit
			holder.position = -box.get_center() * fit
			size = (box.size * fit).max(Vector3.ONE * 0.04)
			body.add_child(holder)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = size
	shape.shape = collider
	body.add_child(shape)
