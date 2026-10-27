class_name NpcLines
extends Resource

## Everything a quest NPC says, in one file (dialogue/<role>.tres): click it
## in the FileSystem dock and edit it in the Inspector -- no code, like
## Grandma's. Each line by its name (QuestTalk asks for them by name); your
## replies too ("reply_..."). Bracketed replies are things you do.

## The name shown above their lines.
@export var speaker_name: String = ""
## Their lines and your replies, by name.
@export var lines: Dictionary = {}


## A line by name ("..." if it's missing).
func line(key: String) -> String:
	return str(lines.get(key, "..."))
