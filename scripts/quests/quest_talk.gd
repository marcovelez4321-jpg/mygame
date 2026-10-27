class_name QuestTalk
extends RefCounted

## The quest NPCs' conversations (the user's lines, dialogue/<role>.tres --
## NpcLines; every one theirs): a Fallout-style DialogueBox on the talker's
## own game; what they choose goes to the host (Network.ask_quest), whose
## quest web it is (Quests).

const FILES := {
	&"voice": "res://dialogue/voice_trader.tres",
	&"shrine": "res://dialogue/shrine_cultist.tres",
	&"bounty": "res://dialogue/bounty_man.tres",
	&"mara": "res://dialogue/mara.tres",
	&"fanatic": "res://dialogue/fanatic.tres",
}
static var _talking := false


static func lines(role: StringName) -> NpcLines:
	var path: String = FILES.get(role, "")
	return load(path) as NpcLines if path != "" and ResourceLoader.exists(path) else NpcLines.new()


## Whether `role` has anything to say to `player` now ("[F] Talk" shows).
static func can_talk(role: StringName, player: PlayerMovement) -> bool:
	if _talking or player == null:
		return false
	match role:
		&"voice":
			return Quests.state(Quests.VOICE) != Quests.State.DONE
		&"shrine":
			return Quests.state(Quests.FEED) != Quests.State.DONE
		&"bounty":
			return Quests.state(Quests.BOUNTY) != Quests.State.DONE or str(Quests.fact("bounty.killed", "")) == "wrong"
		&"mara":
			if Quests.mara_hates():
				return true
			if Quests.state(Quests.TAGS) == Quests.State.ACTIVE:
				return _has(player, Backpack.Kind.TAGS)
			return Quests.state(Quests.TAGS) == Quests.State.DONE and Quests.state(Quests.CLIMB) != Quests.State.DONE
		&"fanatic":
			return Quests.state(Quests.FANATIC) != Quests.State.DONE
	return false


## A talk with `role` (`who`: the NPC, or the trader), on `player`'s own game.
static func talk(role: StringName, player: PlayerMovement) -> void:
	if _talking or player == null or not player.is_multiplayer_authority():
		return
	_talking = true
	var box := DialogueBox.open(player.get_tree())
	var said := lines(role)
	match role:
		&"voice":
			await _voice(box, said, player)
		&"shrine":
			await _shrine(box, said, player)
		&"bounty":
			await _bounty(box, said, player)
		&"mara":
			await _mara(box, said, player)
		&"fanatic":
			await _fanatic(box, said, player)
	box.close()
	_talking = false


static func _say(box: DialogueBox, said: NpcLines, key: String, replies: Array[String]) -> int:
	return await box.ask(said.speaker_name, said.line(key), replies)


## Bones for the Voice (the 400 m trader).
static func _voice(box: DialogueBox, said: NpcLines, player: PlayerMovement) -> void:
	var leave := said.line("reply_leave")
	match Quests.state(Quests.VOICE):
		Quests.State.NOT_STARTED:
			var pick := await box.ask(said.speaker_name, said.line("offer") + "\n\n" + said.line("offering_hint"),
					[said.line("reply_accept"), said.line("reply_decline")])
			if pick == 0:
				Network.ask_quest(Quests.VOICE, &"accept")
		Quests.State.ACTIVE:
			if _has(player, Backpack.Kind.SKULL):
				if await _say(box, said, "reminder", [said.line("reply_hand_in"), leave]) == 0:
					Network.ask_quest(Quests.VOICE, &"hand_in")
					await _say(box, said, "hand_in", [leave])
			else:
				await _say(box, said, "reminder", [leave])


## Feed the Tree (the shrine cultist).
static func _shrine(box: DialogueBox, said: NpcLines, player: PlayerMovement) -> void:
	var leave := said.line("reply_leave")
	if Quests.flag("cult.note_read"):
		await _say(box, said, "refused", [leave])
		return
	match Quests.state(Quests.FEED):
		Quests.State.NOT_STARTED:
			var pick := await _say(box, said, "offer", [said.line("reply_accept"), said.line("reply_decline")])
			if pick == 0:
				Network.ask_quest(Quests.FEED, &"accept")
			else:
				Network.ask_quest(Quests.FEED, &"refuse")
				await _say(box, said, "refused", [leave])
		Quests.State.ACTIVE:
			if Quests.tree_fed():
				if await _say(box, said, "reminder", [said.line("reply_hand_in"), leave]) == 0:
					Network.ask_quest(Quests.FEED, &"hand_in")
					await _say(box, said, "done", [leave])
			else:
				await _say(box, said, "reminder", [leave])


## The Bounty (the stranger at his fire).
static func _bounty(box: DialogueBox, said: NpcLines, player: PlayerMovement) -> void:
	var leave := said.line("reply_leave")
	if str(Quests.fact("bounty.killed", "")) == "wrong":
		await _say(box, said, "wrong_one", [leave])
		return
	# Fed the Tree: he trusts you (the user's), once.
	if Quests.tree_fed() and not Quests.flag("bounty.hinted"):
		await _say(box, said, "ritual_hint", ["..."])
		Network.ask_quest(Quests.BOUNTY, &"hinted")
	match Quests.state(Quests.BOUNTY):
		Quests.State.NOT_STARTED:
			var pick := await _say(box, said, "offer", [said.line("reply_accept"), said.line("reply_decline")])
			if pick == 0:
				Network.ask_quest(Quests.BOUNTY, &"accept")
			else:
				await _say(box, said, "refused", [leave])
		Quests.State.ACTIVE:
			if str(Quests.fact("bounty.killed", "")) == "right":
				if await _say(box, said, "reminder", [said.line("reply_hand_in"), leave]) == 0:
					Network.ask_quest(Quests.BOUNTY, &"hand_in")
					await _say(box, said, "right_one", [leave])
			else:
				await _say(box, said, "reminder", [leave])


## The Climber's Tags, then Climb for him (Mara).
static func _mara(box: DialogueBox, said: NpcLines, player: PlayerMovement) -> void:
	var leave := said.line("reply_leave")
	if Quests.mara_hates():
		await _say(box, said, "hates", [leave])
		return
	if Quests.state(Quests.TAGS) == Quests.State.ACTIVE:
		if await box.ask(said.speaker_name, "...", [said.line("reply_tags"), leave]) != 0:
			return
		Network.ask_quest(Quests.TAGS, &"give_tags")
		await _say(box, said, "tags", ["..."])
	elif Quests.state(Quests.CLIMB) == Quests.State.ACTIVE:
		if Quests.flag("climb.tags_left"):
			if await _say(box, said, "reminder", [said.line("reply_hand_in"), leave]) == 0:
				Network.ask_quest(Quests.CLIMB, &"hand_in")
				await _say(box, said, "done", [leave])
		else:
			await _say(box, said, "reminder", [leave])
		return
	if await _say(box, said, "offer", [said.line("reply_accept"), said.line("reply_decline")]) == 0:
		Network.ask_quest(Quests.CLIMB, &"accept")


## The Fanatic.
static func _fanatic(box: DialogueBox, said: NpcLines, player: PlayerMovement) -> void:
	var leave := said.line("reply_leave")
	var why := said.line("reply_why")
	var threat := said.line("reply_threat")
	var pick := -1
	if Quests.state(Quests.FANATIC) == Quests.State.ACTIVE:
		var has_part := Quests.BOMB_PARTS.any(func(kind: int) -> bool: return not Quests.part_given(kind) and _has(player, kind))
		if has_part:
			pick = await _say(box, said, "parts_left", [said.line("reply_hand_in"), why, threat, leave])
			if pick == 0:
				var after := Quests.BOMB_PARTS.all(func(kind: int) -> bool: return Quests.part_given(kind) or _has(player, kind))
				Network.ask_quest(Quests.FANATIC, &"hand_in")
				await _say(box, said, "all_parts" if after else "parts_left", [leave])
				return
			pick -= 1 # (why, threat, leave as below)
		else:
			pick = await _say(box, said, "parts_left", [why, threat, leave])
	else:
		pick = await _say(box, said, "greeting", [said.line("reply_help"), why, threat])
		if pick == 0:
			if await _say(box, said, "help", [said.line("reply_accept"), said.line("reply_decline")]) == 0:
				Network.ask_quest(Quests.FANATIC, &"help")
			return
		pick -= 1
	match pick:
		0: # Why the top?
			var answer := await _say(box, said, "why", [said.line("reply_see"), threat])
			if answer == 0:
				Network.ask_quest(Quests.FANATIC, &"talked_down")
				await _say(box, said, "talked_down", [leave])
			else:
				await _kamikaze(box, said)
		1: # Put it down or I put you down.
			await _kamikaze(box, said)


static func _kamikaze(box: DialogueBox, said: NpcLines) -> void:
	Network.ask_quest(Quests.FANATIC, &"threat")
	await _say(box, said, "kamikaze", ["..."])


## Whether `player` has `kind` (hand or bag) -- their own game's copy.
static func _has(player: PlayerMovement, kind: int) -> bool:
	return player.hand.held_kind() == kind or player.backpack.count_of(kind) > 0
