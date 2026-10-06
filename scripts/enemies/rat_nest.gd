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

@onready var swarm: RatSwarm = $RatSwarm


func _ready() -> void:
	swarm.home = global_position
	if multiplayer.is_server():
		swarm.spawn_rats.call_deferred(rat_count, global_position)
