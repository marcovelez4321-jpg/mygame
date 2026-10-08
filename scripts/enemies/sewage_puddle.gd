class_name SewagePuddle
extends Node3D

## A puddle of filth left by a Harvestman's sewage hose: a dark splat on the
## floor that burns any player standing in it (`damage` every `tick` seconds
## within `radius`) for `lifetime` seconds, bubbling now and then, then gone.
## Rule 1 (co-op): only the host deals the damage; every peer shows the splat.

const COLOR := Color(0.24, 0.27, 0.08)

var radius := 1.3
var damage := 5.0
var tick := 0.5
var lifetime := 6.0
var _tick_left := 0.0
var _age := 0.0


static func spill(world: Node, at: Vector3, puddle_radius: float, tick_damage: float, seconds: float) -> void:
	var puddle := SewagePuddle.new()
	puddle.radius = puddle_radius
	puddle.damage = tick_damage
	puddle.lifetime = seconds
	world.add_child(puddle)
	puddle.global_position = at
	BloodFX.spawn_splatter(world, at + Vector3.UP * 0.02, Vector3.UP, puddle_radius * 2.4, COLOR)
	BloodFX.spawn_impact(world, at, Vector3.UP, COLOR, 1.2)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick
	if randf() < 0.5:
		BloodFX.spawn_impact(get_tree().current_scene, global_position + Vector3(randf_range(-1, 1), 0.05, randf_range(-1, 1)) * radius * 0.6, Vector3.UP, COLOR, 0.4)
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
		if flat <= radius and absf(player.global_position.y - global_position.y) < 1.0:
			var health := player.get_node_or_null("Health") as Health
			if health:
				health.take_damage(damage, Health.NO_ATTACKER)
