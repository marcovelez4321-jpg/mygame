class_name WorldFacts
extends RefCounted

## What's happened in the world (the user's, 2026-10-25: the quest web's
## backbone -- docs/QUESTS_TRADERS_WALKERS.md): named facts the quests write
## (what you did, how, what you killed or spared) and read (their lines,
## rewards, outcomes), and the world shows (WorldChange). The host's, kept in
## its save folder like the Stalker's memory (the user's: they survive
## quitting) and mirrored to every game (Network.facts; late joiners get them
## all as they load in). Shared in co-op (the user's): one web for the group.
## Names, by convention:
##   quest.<id>          its state (GrandmaQuests.State: 0 not started, 1 open, 2 done)
##   quest.<id>.hint     the giver's hint ("the tallest tower, high up")
##   quest.<id>.outcome  how it ended (empty for its only way; e.g. "smoked")
##   quest.<id>.by       who ended it: their StalkerMemory id
##   quest.<id>.by_name  and their name ("" with no Steam)

const PATH := "user://world_facts.cfg"
const SECTION := "facts"


static func get_fact(name: StringName, default: Variant = null) -> Variant:
	return Network.facts.get(name, default)


static func is_set(name: StringName) -> bool:
	return Network.facts.has(name)


## The host: `name` is `value` now -- here, saved, and on every game.
static func set_fact(name: StringName, value: Variant) -> void:
	Network.send_fact(name, value)


## A quest's own fact's name: quest.<id>, or quest.<id>.<part>.
static func quest(id: StringName, part: String = "") -> StringName:
	return StringName("quest.%s" % id if part.is_empty() else "quest.%s.%s" % [id, part])


## What the host's save folder remembers (empty the first time).
static func load_saved() -> Dictionary:
	var file := ConfigFile.new()
	var found := {}
	if file.load(PATH) != OK or not file.has_section(SECTION):
		return found
	for key in file.get_section_keys(SECTION):
		found[StringName(key)] = file.get_value(SECTION, key)
	return found


static func save(facts: Dictionary) -> void:
	var file := ConfigFile.new()
	for name: StringName in facts:
		file.set_value(SECTION, String(name), facts[name])
	file.save(PATH)
