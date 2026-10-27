class_name DemoDressing
extends Node

## What the Stacks demo is dressed with that has to happen as it starts (the
## user's, 2026-10-27: the open world's details on the procedural Stack): the
## dead climbers by their cold camps -- people let fall where they died, their
## own ragdolls settling (StackSecrets' way). The rest (barrels, crates, camps,
## supplies, wires, washing) is in the scene already (tools/stacks_demo_bake.gd).
## Rule 1 (co-op): the host's (the bodies are enemies: NetEntities).

const BODY := "res://scenes/enemy/enemy.tscn"

## Where each dead climber lies.
@export var climbers := PackedVector3Array()


func _ready() -> void:
	# Every game: the clouds and the skyline giants fade into the demo's own
	# fog colour (what BiomeAtmosphere sets in the open world).
	var world := get_tree().current_scene.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		RenderingServer.global_shader_parameter_set(&"world_fog_color", world.environment.fog_light_color)
	if Network.is_online() and not multiplayer.is_server():
		return
	_lay_out.call_deferred()


func _lay_out() -> void:
	if not ResourceLoader.exists(BODY):
		return
	var scene := load(BODY) as PackedScene
	for at in climbers:
		var body := scene.instantiate() as Enemy
		body.can_mutate = false
		body.corpse_time = 1.0e9 # stays (and isn't counted with the fights' bodies)
		body.set_meta(&"climber", true)
		body.set_meta(&"culled", true) # nothing to drop
		get_tree().current_scene.add_child(body)
		body.global_position = at + Vector3.UP * 0.2
		body.rotation.y = randf() * TAU
		var health := body.get_node(^"Health") as Health
		health.take_damage(health.current_health + 1.0)
