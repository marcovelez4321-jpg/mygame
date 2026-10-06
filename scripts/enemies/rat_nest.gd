class_name RatNest
extends Node3D

## A pack of rats with no Rat Bender: they burrow up out of the floor here
## when the level starts and roam around this spot. Once any rat notices a
## player they all creep over, then swarm them (RatSwarm's "Without a
## Bender" settings). Same rats and swarm brain as his horde -- just
## leaderless. Big enough packs drag bodies off to eat them.
##
## Rule 1 (co-op): the host spawns the rats; the swarm runs on the host.

@export var rat_count: int = 12
## Big bodyguard rats mixed into the pack -- they move with it like any other
## rat, just bigger, tougher and biting harder.
@export var bodyguard_count: int = 2
@export var bodyguard_scale: float = 2.0
@export var bodyguard_health: float = 4.0
@export var bodyguard_damage: float = 2.0

@onready var swarm: RatSwarm = $RatSwarm


func _ready() -> void:
	swarm.home = global_position
	if multiplayer.is_server():
		swarm.spawn_rats.call_deferred(rat_count, global_position)
		swarm.spawn_rats.call_deferred(bodyguard_count, global_position, -1.0, -1.0,
				bodyguard_scale, bodyguard_health, bodyguard_damage)
