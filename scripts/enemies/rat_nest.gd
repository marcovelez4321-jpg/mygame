class_name RatNest
extends Node3D

## A pack of rats with no Rat Bender: they burrow up out of the floor here
## when the level starts, hang around this spot, and swarm any player who
## comes within the swarm's hunt_range. Same rats and swarm brain as his
## horde (RatSwarm, Rat) -- just leaderless.
##
## Rule 1 (co-op): the host spawns the rats; the swarm runs on the host.

@export var rat_count: int = 12

@onready var swarm: RatSwarm = $RatSwarm


func _ready() -> void:
	swarm.home = global_position
	if multiplayer.is_server():
		swarm.spawn_rats.call_deferred(rat_count, global_position)
