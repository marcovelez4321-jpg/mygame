class_name GrandmaQuests
extends RefCounted

## Grandma's quests (the user's, 2026-10-19: she's a quest giver now, like
## Fallout's -- no more missions or portals). One so far:
##   CIGARETTES: the last pack of cigarettes in the world, lying somewhere
##   inside the Stack (StackSecrets puts it: any hall floor or window room,
##   any tower, any height). Grandma hints at which tower and how high. Bring
##   it to her: CIGARETTES_POINTS virus points for everyone.
## Shared in co-op (the user's): one quest for everyone, the host's -- world
## facts (WorldFacts: quest.<id>, its hint, who ended it), mirrored to every
## game and kept in the host's save folder (the user's, 2026-10-25: they
## survive quitting); whoever hands the pack in, everyone gets the points.

enum State { NOT_STARTED, ACTIVE, DONE }

const CIGARETTES := &"cigarettes"
## The reward (the user's): a whole mutation's worth.
const CIGARETTES_POINTS := 14


static func state(id: StringName) -> int:
	return int(WorldFacts.get_fact(WorldFacts.quest(id), State.NOT_STARTED))


static func hint(id: StringName) -> String:
	return str(WorldFacts.get_fact(WorldFacts.quest(id, "hint"), ""))


## The host: what a player (`peer`) did at Grandma's -- "accept" a quest or
## "hand_in" what it wanted.
static func act(tree: SceneTree, peer: int, id: StringName, action: StringName) -> void:
	if id != CIGARETTES:
		return
	match action:
		&"accept":
			if state(id) == State.NOT_STARTED:
				Network.send_quest(id, State.ACTIVE, hint(id))
		&"hand_in":
			if state(id) == State.DONE:
				return
			var body := Network.body_of(peer) if Network.is_online() else PlayerMovement.local_player(tree)
			if body == null or not body.backpack.take(Backpack.Kind.CIGARETTES, 1):
				return
			Network.send_backpack_take(peer, Backpack.Kind.CIGARETTES, 1)
			for node in tree.get_nodes_in_group("player"):
				var player := node as PlayerMovement
				if player and player.virus:
					player.virus.gain_points(CIGARETTES_POINTS)
			# Who did it (the journal's own notes: "I", or their name).
			var profile: Dictionary = Network.profiles.get(peer, {})
			Network.send_fact(WorldFacts.quest(id, "by"), str(profile.get("id", "")))
			Network.send_fact(WorldFacts.quest(id, "by_name"), str(profile.get("name", "")))
			Network.send_quest(id, State.DONE, hint(id)) # (the hint kept: the journal's crossed-out note)


## Where in the Stack something is, the way Grandma would say it: which
## tower (by height) and how far up it. `stack`: the Megastructure; `at`: in
## its own space.
static func where_in(stack: Megastructure, at: Vector3) -> String:
	var columns := stack.nest_columns
	if columns.is_empty():
		return "somewhere up in those towers"
	var nearest := 0
	for i in columns.size():
		var here := Vector2(columns[i].x - at.x, columns[i].z - at.z).length()
		var best := Vector2(columns[nearest].x - at.x, columns[nearest].z - at.z).length()
		if here < best:
			nearest = i
	var rank := 0
	for column in columns:
		if column.y > columns[nearest].y:
			rank += 1
	var tower := ["the tallest tower", "the second-tallest tower", "the third-tallest tower",
			"the fourth-tallest tower", "the fifth-tallest tower"]
	var which: String = tower[rank] if rank < tower.size() else "one of the little towers"
	var share := clampf(at.y / maxf(columns[nearest].y, 1.0), 0.0, 1.0)
	var how_high := "near the bottom"
	if share > 0.85:
		how_high = "near the very top"
	elif share > 0.6:
		how_high = "high up"
	elif share > 0.4:
		how_high = "about halfway up"
	elif share > 0.15:
		how_high = "low down"
	return "%s, %s" % [which, how_high]
