class_name WindowSpawner
extends Node

## The demo's horde before the rounds exist (the user's, 2026-10-27:
## infected through the windows): every EVERY seconds, while fewer than
## MAX_ALIVE of its own are about, one of the infected turns up outside a
## boarded window (Barricade) within REACH of a player and comes in through
## it. Rule 1 (co-op): the host's.

const EVERY := 4.0
const MAX_ALIVE := 10
const REACH := 45.0
## Every kind of tweaker (the user's, 2026-10-27; the director's roaming
## gangs have them too: DemoHorde).
const SCENES := ["res://scenes/enemy/enemy.tscn", "res://scenes/enemy/enemy.tscn", "res://scenes/enemy/enemy_rusher.tscn",
		"res://scenes/enemy/enemy_gunner.tscn", "res://scenes/enemy/mutant_enemy.tscn"]
const GROUP := &"window_infected"

var _left := 3.0
## The Alpha Stalker (the user's: the full AI, hunting from round 1): brought
## in once, ALPHA_AFTER in (the user's, 2026-10-27: 3 s, as it was).
const ALPHA_AFTER := 3.0
var _alpha_left := ALPHA_AFTER


func _physics_process(delta: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if _alpha_left > 0.0:
		_alpha_left -= delta
		if _alpha_left <= 0.0:
			Stalker.ensure(get_tree())
	_left -= delta
	if _left > 0.0:
		return
	_left = EVERY
	if get_tree().get_nodes_in_group(GROUP).size() >= MAX_ALIVE:
		return
	var near: Array[Barricade] = []
	for node in get_tree().get_nodes_in_group(&"barricades"):
		var window := node as Barricade
		if window and _anyone_within(window.global_position, REACH):
			near.append(window)
	if near.is_empty():
		return
	var window: Barricade = near.pick_random()
	var path: String = SCENES.pick_random()
	if not ResourceLoader.exists(path):
		return
	var one := (load(path) as PackedScene).instantiate() as Enemy
	one.can_mutate = false
	one.window = window
	one.add_to_group(GROUP)
	get_tree().current_scene.add_child(one)
	one.global_position = window.spawn_point()
	window.claim(one)


func _anyone_within(at: Vector3, reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(at) < reach:
			return true
	return false
