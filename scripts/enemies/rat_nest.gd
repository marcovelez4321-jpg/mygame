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

## A pack with no Bender comes this many times bigger than its counts above
## (rats and bodyguards alike): with no leader to rally them, they make up
## for it in numbers.
const LEADERLESS_SCALE := 2

@onready var swarm: RatSwarm = $RatSwarm


func _ready() -> void:
	swarm.home = global_position
	var rats := rat_count * LEADERLESS_SCALE
	var guards := bodyguard_count * LEADERLESS_SCALE
	# Room to breed back up to its full size, at least.
	swarm.feed_limit = maxi(swarm.feed_limit, rats + guards)
	if multiplayer.is_server():
		swarm.spawn_rats.call_deferred(rats, global_position)
		swarm.spawn_rats.call_deferred(guards, global_position, -1.0, -1.0,
				bodyguard_scale, bodyguard_health, bodyguard_damage)
