class_name QuestTests
extends RefCounted

## F9's quest buttons (the user's, 2026-10-27: for testing the quest web --
## StalkerTestMenu shows them; the host's). Take them out before release.

const BUTTONS := [
	["q_start_all", "Quests: start them all"],
	["q_skull", "Give me: skull + offering"],
	["q_meat", "Give me: raw meat"],
	["q_parts", "Give me: the bomb parts"],
	["q_tags", "Give me: his tags"],
	["q_go_shrine", "Go to: shrine cultist"],
	["q_go_bounty", "Go to: the stranger"],
	["q_go_mara", "Go to: Mara"],
	["q_go_fanatic", "Go to: the Fanatic"],
	["q_go_climber", "Go to: the climber's body"],
	["q_go_camp", "Go to: his 1 km camp"],
	["q_go_cairn", "Go to: the summit cairn"],
	["q_go_lair", "Go to: the Stalker's lair"],
	["q_go_cult", "Go to: a cult camp"],
	["q_ambush", "Cult ambush on me"],
	["q_kamikaze", "Fanatic: go off"],
	["q_collapse", "Blow the 1.4 km top off"],
]


static func run(event: StringName, player: PlayerMovement) -> String:
	var tree := player.get_tree()
	match event:
		&"q_start_all":
			for id: StringName in [Quests.VOICE, Quests.FEED, Quests.BOUNTY, Quests.FANATIC]:
				if Quests.state(id) == Quests.State.NOT_STARTED:
					Network.send_quest(id, Quests.State.ACTIVE, "")
			Quests.note_read(&"climber_letter", player)
			return "Started: Bones, Feed, Climber's Tags (tags given), Bounty, Fanatic"
		&"q_skull":
			Quests.grant(player, {kind = Backpack.Kind.SKULL, amount = 1})
			Quests.grant(player, {kind = Backpack.Kind.OFFERING, amount = 1})
			return "A skull and an offering in your bag"
		&"q_meat":
			CarryItem.spawn_meat(tree.current_scene, player.global_position - player.head.global_basis.z * 1.5 + Vector3.UP, 2.0, false)
			return "Raw meat in front of you"
		&"q_parts":
			for kind: int in Quests.BOMB_PARTS:
				Quests.grant(player, {kind = kind, amount = 1})
			return "Gas, pipe and wire in your bag"
		&"q_tags":
			Quests.grant(player, {kind = Backpack.Kind.TAGS, amount = 1})
			return "His tags in your bag"
		&"q_ambush":
			Cult.ambush(player)
			return "Cultists closing in from behind you"
		&"q_kamikaze":
			if _npc(tree, &"fanatic") == null:
				return "No Fanatic here (gone, or not placed)"
			Quests.kamikaze(tree, player)
			return "He's going off"
		&"q_collapse":
			Network.send_fact(&"stack.top_gone", true)
			return "The 1.4 km tower's top is gone (back: Forget the world, then reload)"
	if String(event).begins_with("q_go_"):
		var place := _where(tree, StringName(String(event).trim_prefix("q_go_")))
		if not place.is_finite():
			return "Not placed here (or gone)"
		player.global_position = place
		player.velocity = Vector3.ZERO
		return "There"
	return ""


## Where to stand for `what` (INF: not here).
static func _where(tree: SceneTree, what: StringName) -> Vector3:
	match what:
		&"shrine", &"bounty", &"mara", &"fanatic":
			var npc := _npc(tree, what)
			if npc:
				# Beside them (the Fanatic's sled is on his right).
				return npc.global_transform * Vector3(-1.5, 0.5, -1.5)
		&"climber", &"cairn":
			for node in tree.get_nodes_in_group(&"quest_decor"):
				var decor := node as QuestDecor
				if decor and decor.kind == (QuestDecor.CLIMBER_BODY if what == &"climber" else QuestDecor.CAIRN):
					return decor.global_position + Vector3(2.0, 1.0, 0.0)
		&"camp":
			var world := tree.get_first_node_in_group(QuestWorld.GROUP) as QuestWorld
			if world and is_instance_valid(world.climber_camp):
				return world.climber_camp.global_transform * Vector3(-1.2, 1.0, 2.6)
		&"lair":
			var lair := tree.get_first_node_in_group(StalkerLair.GROUP) as Node3D
			if lair:
				return lair.global_position + Vector3(0.0, 1.5, 0.0)
		&"cult":
			var camp := tree.get_first_node_in_group(&"cult_camps") as Node3D
			if camp:
				return camp.global_position + Vector3(0.0, 1.0, 30.0)
	return Vector3.INF


static func _npc(tree: SceneTree, role: StringName) -> QuestNpc:
	for node in tree.get_nodes_in_group(&"quest_npcs"):
		var npc := node as QuestNpc
		if npc and npc.role == role:
			return npc
	return null
