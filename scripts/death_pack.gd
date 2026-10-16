class_name DeathPack
extends RigidBody3D

## Your gear where you died (the user's, 2026-10-16): die with a camp to wake
## at and everything you carried -- guns, ammo, pills, the pack's materials,
## kit and meat -- is left here in a backpack (Backpack.take_all()). Walk into
## it or grapple it and it's all yours again. Only its owner's.
## Rule 1 (co-op): the host's; seen through NetEntities.

const SIZE := 0.7
const PICKUP_RADIUS := 1.2

var gear: Dictionary = {}
var owner_id := 1


## Everything `player` carries, dropped where they fell (the host's).
static func drop(player: PlayerMovement) -> DeathPack:
	var pack := DeathPack.new()
	pack.owner_id = player.get_multiplayer_authority()
	pack.gear = player.backpack.take_all()
	player.get_tree().current_scene.add_child(pack)
	pack.global_position = player.global_position + Vector3.UP * 0.5
	return pack


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	mass = 6.0
	can_sleep = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = BackpackView.pack_mesh()
	if mesh.mesh == null:
		mesh.mesh = BoxMesh.new()
	else:
		mesh.material_override = BackpackView.pack_material()
	var box := mesh.get_aabb()
	var fit := SIZE / maxf(box.get_longest_axis_size(), 0.0001)
	mesh.scale = Vector3.ONE * fit
	mesh.position = -box.get_center() * fit
	mesh.visibility_range_end = 200.0
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = box.size * fit
	shape.shape = body_box
	add_child(shape)
	if NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.monitorable = false
	var zone_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	zone_shape.shape = sphere
	zone.add_child(zone_shape)
	add_child(zone)
	zone.body_entered.connect(func(body: Node3D) -> void:
		if body is PlayerMovement:
			claim(body as PlayerMovement))


## Its gear back to its owner (walked into, or grappled: PlayerHand.fetch()).
func claim(player: PlayerMovement) -> bool:
	if gear.is_empty() or player.is_dead() or player.get_multiplayer_authority() != owner_id:
		return false
	player.backpack.give_all(gear)
	gear = {}
	if player.is_multiplayer_authority():
		MapIO.show_pickup(get_tree(), "+ Your gear")
	queue_free()
	return true