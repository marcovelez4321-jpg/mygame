class_name GrandmaDialogue
extends Resource

## Everything Grandma says and every reply you can pick, in one file:
## dialogue/grandma.tres. Click it in the FileSystem dock and edit it all
## in the Inspector -- no code. Every Grandma in every level reads this same
## file. Lines with several entries (greetings, goodbyes) pick one at random
## each time.

## The name shown above her lines.
@export var speaker_name: String = "Grandma"

@export_group("Greeting")
## What she says when you walk up and press F.
@export_multiline var greetings: Array[String] = [
	"There's my baby. You eating enough?",
	"Oh, it's you. Wipe your feet.",
	"You look skinny. Come here.",
	"Did you call your mother? Don't lie to me.",
]
## Your replies to her greeting.
@export var reply_mission: String = "Let's do a mission."
@export var reply_just_saying_hi: String = "Just saying hi."

@export_group("Missions")
## Her answer when you ask for a mission; the mission list appears under it.
@export_multiline var mission_prompt: String = "Bet."
## The last option in the mission list, to back out.
@export var reply_never_mind: String = "Never mind."
## If there are no missions in res://missions at all.
@export_multiline var no_missions_line: String = "Nothing for you right now, baby. Go get some sun."

@export_group("Goodbye")
## What she says after "Just saying hi."
@export_multiline var goodbye_lines: Array[String] = [
	"Alright, baby. Love you.",
	"Mm-hm. Don't be a stranger.",
]
## The only reply after a goodbye; closes the conversation.
@export var reply_leave: String = "[Leave]"
