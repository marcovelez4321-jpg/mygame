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
	# The web past Grandma's (the user's, 2026-10-27: Quests).
	&"bones_voice": {
		open = "The trader up at 400 m. The only one who talks. He says it's real, the thing in the dark -- he wants a skull off its pile to prove it. Forty scrap. He begged me to leave it a gift first: meat and teeth, bound.",
		done = {
			&"": ["Gave him the skull. He held it like it was holy. Forty scrap.",
					"{name} gave him the skull. Forty scrap."],
		},
	},
	&"feed_tree": {
		open = "A cultist at a shrine of roots and skulls. He wants the Tree fed: a big one's raw meat, pressed to the bark. Seven scrap and a revolver.",
		steps = [
			[&"fed_by", "Fed it. The bark opened and took it. The roots moved.",
					"{name} fed it. The roots moved."],
		],
		done = {
			&"": ["He paid. Seven scrap and a revolver. Go with the Tree, he said.",
					"{name} took his pay. Go with the Tree, he said."],
		},
	},
	&"climbers_tags": {
		open = "A dead climber at the foot of the tallest tower. A letter on him: \"Mara, if this finds you: I'm close. I've got a camp up on the tallest one, a kilometre up, everything I own's there. When I reach the top I'll come down and we'll go somewhere quiet. I promise this time.\" Mara rides with the traders.",
		steps = [
			[&"found_by", "Took his tags.", "{name} took his tags."],
		],
		done = {
			&"": ["Gave Mara his tags. She thinks he might still be up there.",
					"{name} gave Mara his tags. She thinks he might still be up there."],
		},
	},
	&"climb_for_him": {
		open = "Mara wants his tags at the top of the tallest tower. So he knows someone came.",
		steps = [
			[&"left_by", "Left his tags on the cairn at the very top.", "{name} left his tags at the very top."],
		],
		done = {
			&"": ["Told Mara. Fifty scrap -- all she had.", "{name} told Mara. Fifty scrap."],
		},
	},
	&"bounty": {
		open = "A stranger at a fire out in the wilds wants a trader dead: the one whose banner's torn across the eye. Anything I've ever wanted, he says.",
		steps = [
			[&"note_by", "A note on him. He was one of the robed ones. The cultist at the shrine won't deal with us now.",
					"{name} found a note on him. He was one of the robed ones."],
		],
		done = {
			&"right": ["The right one. The stranger gave me a jar of black blood. The robed ones leave us be now.",
					"{name} did it. A jar of black blood. The robed ones leave us be now."],
			&"wrong": ["The wrong trader. They laughed at us.", "{name} killed the wrong trader. They laughed at us."],
			&"killed": ["Killed the stranger instead.", "{name} killed the stranger."],
		},
	},
	&"fanatic": {
		open = "A man hauling a bomb up the 1.4 km tower on a sled, piece by piece. He wants its top off. Gas, pipe, wire.",
		done = {
			&"helped": ["Brought him all three. Forty scrap and ten grenades. Then he went up.",
					"{name} brought him the last of it. Then he went up."],
			&"talked_down": ["Talked him down. He sells what he's got left, cheap.", "{name} talked him down."],
			&"kamikaze": ["Pushed him too far. He went off.", "{name} pushed him too far. He went off."],
		},
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
