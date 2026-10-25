class_name QuestJournal
extends RefCounted

## What the journal says (the user's, 2026-10-25): a page a quest, from the
## world's facts (WorldFacts) -- the open note while it's open, each step
## under it as it happens; done, all of that crossed out with how it ended
## written under it. Own notes in co-op (the user's): the quests are shared,
## but each player's journal words it its own way -- "I" when it was you,
## their name when it was someone else.
## Each entry: its open line ({hint}: the giver's hint, as a sentence); its
## steps, each shown once its fact (quest.<id>.<step>: who did it) is set,
## as [yours, a teammate's ({name})]; its done lines by outcome (empty: the
## plain way) the same; and the sketch drawn with it (JournalPage).

const ENTRIES := {
	&"cigarettes": {
		open = "Grandma wants her cigarettes. The last pack in the world, she says. {hint}.",
		steps = [
			[&"snatched_by", "It took them. Right out from in front of me. It went down -- the depths, under the Stack, where the water is.",
					"It took them from {name}. Right out from in front of them. The depths, under the Stack."],
			[&"recovered_by", "Got them. I didn't look back.",
					"{name} got them back."],
		],
		done = {
			&"": ["She has them now. I felt something change in me.",
					"{name} gave them to her. She has them now. I felt something change in me."],
			&"smoked": ["Smoked them. Grandma won't look at me.",
					"{name} smoked them. Grandma won't look at us."],
			&"sold": ["Sold them for scrap. Fifty. Grandma doesn't know.",
					"{name} sold them for scrap."],
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
		var hint := _fact(WorldFacts.quest(id, "hint"))
		var notes := _escape(str(entry.open).replace(" {hint}.", (" %s." % _sentence(hint)) if not hint.is_empty() else ""))
		for step: Array in entry.get("steps", []):
			var line := _whose(id, String(step[0]), step[1], step[2])
			if not line.is_empty():
				notes += "\n\n" + _escape(line)
		var text := notes
		if state == GrandmaQuests.State.DONE:
			var done: Dictionary = entry.done
			var outcome := StringName(_fact(WorldFacts.quest(id, "outcome")))
			var lines: Array = done.get(outcome, done.get(&"", ["", ""]))
			var by := _fact(WorldFacts.quest(id, "by"))
			var line := str(lines[0] if by.is_empty() or by == my_id() else lines[1]).replace("{name}", _name(WorldFacts.quest(id, "by_name")))
			text = "[s]%s[/s]\n\n%s" % [notes.replace("\n\n", "[/s]\n\n[s]"), _escape(line)]
		found.append({text = text, sketch = entry.get("sketch", &"")})
	return found


## A step's line: yours, or a teammate's with their name -- or "" while its
## fact (who did it) isn't set.
static func _whose(id: StringName, part: String, yours: String, theirs: String) -> String:
	var by := _fact(WorldFacts.quest(id, part))
	if by.is_empty():
		return ""
	return yours if by == my_id() else theirs.replace("{name}", _name(WorldFacts.quest(id, part + "_name")))


static func _name(fact: StringName) -> String:
	var who := _fact(fact)
	return who if not who.is_empty() else NAMELESS


static func _fact(name: StringName) -> String:
	var value: Variant = WorldFacts.get_fact(name, "")
	return str(value) if value != null else ""


## This PC's own id (StalkerMemory): whose notes these are.
static func my_id() -> String:
	if _my_id.is_empty():
		_my_id = str(StalkerMemory.my_profile().id)
	return _my_id


static func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else text


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
