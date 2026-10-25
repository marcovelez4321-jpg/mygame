class_name QuestJournal
extends RefCounted

## What the journal says (the user's, 2026-10-25): a page a quest, from the
## world's facts (WorldFacts) -- the open note while it's open; done, that
## note crossed out with how it ended written under it. Own notes in co-op
## (the user's): the quests are shared, but each player's journal words it
## its own way -- "I" when it was you, their name when it was someone else.
## Each entry: its open line ({hint}: the giver's hint, as a sentence), its
## done lines by outcome (empty: its only way) as [yours, a teammate's
## ({name})], and the sketch drawn with it (JournalPage).

const ENTRIES := {
	&"cigarettes": {
		open = "Grandma wants her cigarettes. The last pack in the world, she says. {hint}.",
		done = {
			&"": ["She has them now. I felt something change in me.",
					"{name} gave them to her. She has them now. I felt something change in me."],
		},
		sketch = &"cigarettes",
	},
}
## A teammate with no name (no Steam).
const NAMELESS := "Someone"

static var _my_id := ""


## Every page, in order: [{text (BBCode), sketch}].
static func pages() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id: StringName in ENTRIES:
		var state := int(WorldFacts.get_fact(WorldFacts.quest(id), GrandmaQuests.State.NOT_STARTED))
		if state == GrandmaQuests.State.NOT_STARTED:
			continue
		var entry: Dictionary = ENTRIES[id]
		var hint := str(WorldFacts.get_fact(WorldFacts.quest(id, "hint"), ""))
		var open := str(entry.open).replace(" {hint}.", (" %s." % _sentence(hint)) if not hint.is_empty() else "")
		var text := _escape(open)
		if state == GrandmaQuests.State.DONE:
			var done: Dictionary = entry.done
			var outcome := StringName(str(WorldFacts.get_fact(WorldFacts.quest(id, "outcome"), "")))
			var lines: Array = done.get(outcome, done.get(&"", ["", ""]))
			var by := str(WorldFacts.get_fact(WorldFacts.quest(id, "by"), ""))
			var yours := by.is_empty() or by == my_id()
			var who := str(WorldFacts.get_fact(WorldFacts.quest(id, "by_name"), ""))
			var line := str(lines[0] if yours else lines[1]).replace("{name}", who if not who.is_empty() else NAMELESS)
			text = "[s]%s[/s]\n\n%s" % [text, _escape(line)]
		found.append({text = text, sketch = entry.get("sketch", &"")})
	return found


## This PC's own id (StalkerMemory): whose notes these are.
static func my_id() -> String:
	if _my_id.is_empty():
		_my_id = str(StalkerMemory.my_profile().id)
	return _my_id


static func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else text


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
