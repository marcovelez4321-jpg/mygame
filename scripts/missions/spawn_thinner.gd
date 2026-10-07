class_name SpawnThinner
extends Node

## Cuts a level's creatures down to keep_share of what the map places, so a
## mission built on a copy of another map can focus on its boss (the worm
## boss mission keeps 30%). Applies to the level's own top-level children:
##   - placed creatures (tweakers -- melee, rushers, gunners --, roaches,
##     rats, spiders, deepmaws): of each kind (same scene), an evenly spread
##     keep_share of them stay, the rest are removed (props, test targets and
##     pickups are left alone);
##   - rat nests and spider packs: their rat / bodyguard / spider counts are
##     scaled by keep_share.
## Exempt: barnacle nests (BarnacleCluster, BarnacleScatter), the bosses
## (BurrowWorm, RatBender/SwarmKing), players and Grandma.
##
## Place it as the LAST child of the level: it works in _enter_tree(), after
## every level node has entered the tree but before any of them is ready --
## so nests and packs spawn the reduced numbers and removed enemies never run.
## Rule 1 (co-op): it picks by node order, not at random, so every player's
## game removes the same ones.

@export_range(0.0, 1.0, 0.05) var keep_share: float = 0.3


func _enter_tree() -> void:
	var level := get_parent()
	if level == null:
		return
	var kinds := {} # scene path -> [nodes]
	for child in level.get_children():
		if child == self or _exempt(child):
			continue
		if child is RatNest:
			var nest := child as RatNest
			nest.rat_count = roundi(nest.rat_count * keep_share)
			nest.bodyguard_count = roundi(nest.bodyguard_count * keep_share)
		elif child is SpiderPack:
			var pack := child as SpiderPack
			pack.start_count = roundi(pack.start_count * keep_share)
		elif child is Enemy or child is FlyingRoach or child is Rat or child is Spider or child is Deepmaw:
			var kind := child.scene_file_path if not child.scene_file_path.is_empty() else str(child.get_script())
			if not kinds.has(kind):
				kinds[kind] = []
			(kinds[kind] as Array).append(child)
	for kind in kinds:
		var nodes: Array = kinds[kind]
		var kept := roundi(nodes.size() * keep_share)
		for i in nodes.size():
			# Evenly spread: keep `kept` of them, one each time the running
			# count ticks over.
			var keep := floori(float((i + 1) * kept) / nodes.size()) > floori(float(i * kept) / nodes.size())
			if not keep:
				(nodes[i] as Node).queue_free()


func _exempt(node: Node) -> bool:
	return node is BarnacleCluster or node is BarnacleScatter or node is BurrowWorm \
			or node is RatBender or node.is_in_group("player") or node.name.begins_with("Grandma") \
			or node.name == "Player"
