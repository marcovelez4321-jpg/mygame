class_name LastPack
extends RefCounted

## THE LAST PACK (the user's, 2026-10-25; docs/QUESTS_TRADERS_WALKERS.md):
## Grandma's cigarettes, as a quest of the web. Its steps are world facts
## (WorldFacts: quest.cigarettes.stage), so they last between sessions:
##   LYING -- in the Stack, in a shaft of light, out in the open (StackSecrets:
##     a bait CarryItem, never taken by hand or grapple). Come within
##     Stalker.PACK_RANGE and the Stalker scrambles past you from behind and
##     snatches it, off out of sight with it (Stalker._pack_snatch_tick).
##   IN_LAIR -- on its biggest bone pile in its lair (StalkerLair); it's home
##     whenever you come, only watching -- until you take them: then a chase
##     out of the depths (Stalker.CHASE_TIME).
##   RECOVERED -- someone has them. Quit with them and it has them back at
##     home next time (LastPack.new_session()).
## Then: smoke them (PlayerHand: three pods ripen -- a free mutation; Grandma
## knows, and her next quest pays nothing), sell them to a trader (traders:
## to come), or give them to Grandma (GrandmaQuests).

const QUEST := GrandmaQuests.CIGARETTES
const LYING := ""
const IN_LAIR := "lair"
const RECOVERED := "recovered"
const SMOKED := "smoked"


static func stage() -> String:
	var value: Variant = WorldFacts.get_fact(WorldFacts.quest(QUEST, "stage"), LYING)
	return str(value) if value != null else LYING


## Smoked (Grandma knows: GrandmaQuests.pays()).
static func smoked() -> bool:
	return str(WorldFacts.get_fact(WorldFacts.quest(QUEST, "outcome"), "")) == SMOKED


## The host: it got them home (a step: `from` is who it took them from).
static func taken_home(from: PlayerMovement) -> void:
	Network.send_fact(WorldFacts.quest(QUEST, "stage"), IN_LAIR)
	_record("snatched_by", from)


## The host: `by` took them back out of its lair.
static func recovered(by: PlayerMovement) -> void:
	Network.send_fact(WorldFacts.quest(QUEST, "stage"), RECOVERED)
	_record("recovered_by", by)


## The host: `by` smoked them -- the quest's done that way.
static func smoke(by: PlayerMovement) -> void:
	Network.send_fact(WorldFacts.quest(QUEST, "outcome"), SMOKED)
	Network.send_fact(&"grandma.next_unpaid", true) # (Grandma knows: GrandmaQuests.pays())
	_record("by", by)
	Network.send_quest(QUEST, GrandmaQuests.State.DONE, GrandmaQuests.hint(QUEST))


## The host, as a level starts: nobody carries anything over from last time,
## so taken back out but not handed in or smoked, they're home again.
static func new_session() -> void:
	if stage() == RECOVERED and GrandmaQuests.state(QUEST) != GrandmaQuests.State.DONE:
		Network.send_fact(WorldFacts.quest(QUEST, "stage"), IN_LAIR)
		Network.send_fact(WorldFacts.quest(QUEST, "recovered_by"), "")
		Network.send_fact(WorldFacts.quest(QUEST, "recovered_by_name"), "")


## The player with the pack on them (bag or hand), or null.
static func carrier(tree: SceneTree) -> PlayerMovement:
	for node in tree.get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		if (player.backpack and player.backpack.cigarettes > 0) \
				or (player.hand and player.hand.is_holding() and int(player.hand.data.get("kind", -1)) == Backpack.Kind.CIGARETTES):
			return player
	return null


## Who did it, for the journal's own notes (their StalkerMemory id and name).
static func _record(part: String, player: PlayerMovement) -> void:
	var profile: Dictionary = Network.profiles.get(player.get_multiplayer_authority() if player else 1, {})
	Network.send_fact(WorldFacts.quest(QUEST, part), str(profile.get("id", "")))
	Network.send_fact(WorldFacts.quest(QUEST, part + "_name"), str(profile.get("name", "")))
