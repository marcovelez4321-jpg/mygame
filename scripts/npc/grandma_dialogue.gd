class_name GrandmaDialogue
extends Resource

## Everything Grandma says and every reply you can pick, in one file:
## dialogue/grandma.tres. Click it in the FileSystem dock and edit it all
## in the Inspector -- no code. Every Grandma in every level reads this same
## file. Lines with several entries (greetings, goodbyes) pick one at random
## each time. (Her missions and portals are gone -- the user's, 2026-10-19;
## she gives quests now: GrandmaQuests.)

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
## Once you've smoked her cigarettes (LastPack; the user's): her greeting,
## every time.
@export_multiline var smoked_greeting: String = "You smell like my cigarettes."
## Asking about work (shown while she has a quest you haven't taken).
@export var reply_need_anything: String = "Need anything, Grandma?"
@export var reply_just_saying_hi: String = "Just saying hi."

@export_group("Quest: the cigarettes")
## Asking you for them (the user's).
@export_multiline var cigarettes_offer: String = "Come sit with Grandma. I need my cigarettes, sweetheart... there's one pack left, up in the towers. I can smell it."
## Where it is, under her ask and her reminder: {where} becomes which tower
## and how high (e.g. "the second-tallest tower, about halfway up").
@export_multiline var cigarettes_hint: String = "It's in {where}."
@export var reply_accept: String = "I'll find them."
@export var reply_decline: String = "Not right now."
## While you're looking (the user's).
@export var reply_ask_about: String = "About those cigarettes..."
@export_multiline var cigarettes_reminder: String = "Still no cigarettes? Grandma's patient. Grandma's always patient."
## Handing them in (the user's).
@export var reply_hand_in: String = "I found your cigarettes."
@export_multiline var cigarettes_done: String = "There's my good baby. Let Grandma give you something... special."

@export_group("Goodbye")
## What she says after "Just saying hi."
@export_multiline var goodbye_lines: Array[String] = [
	"Alright, baby. Love you.",
	"Mm-hm. Don't be a stranger.",
]
## Leaving the conversation.
@export var reply_leave: String = "[Leave]"
