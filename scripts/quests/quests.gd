class_name Quests
extends RefCounted

## The quest web past Grandma's (the user's, 2026-10-27; every detail theirs,
## docs/QUESTS_TRADERS_WALKERS.md). Shared in co-op: one web, the host's --
## world facts (WorldFacts), saved and mirrored; whoever does it, it's done
## for everyone; the journal words it each player's own way (QuestJournal).
## What anyone does goes to the host (Network.ask_quest -> act()); the host
## decides and writes the facts.
##   VOICE -- Bones for the Voice: the trader up the Stack at 400 m (the only
##     one who talks) wants a skull off the Stalker's pile: VOICE_PAY. Leave
##     the offering in its home first and it lets you go (and a gift waits
##     at your next camp); don't, and it's furious at whoever took it.
##   FEED -- Feed the Tree: the cultist at the bone shrine wants a big one's
##     raw meat pressed to the Flesh Tree: FEED_PAY and a revolver; fed, two
##     more roots over the house, twice the red weed. Refused: ambushes.
##   TAGS -- the Climber's Tags: his letter on his body at the tallest tower's
##     foot, his camp at 1 km; his tags back to Mara (with the torn-banner
##     trader). Then CLIMB -- Climb for him: lay them on the tallest tower's
##     summit cairn: CLIMB_PAY.
##   BOUNTY -- the stranger at his fire wants the torn-banner trader dead:
##     the right one, the black blood and the cult's side; the wrong one,
##     failed for good; kill him, his note turns the shrine cultist on you.
##   FANATIC -- on the 1.4 km tower, higher each session: bring his three
##     parts and the top comes off (FANATIC_PAY, FANATIC_GRENADES); talk him
##     down and he sells cheap explosives; threaten him and he blows.

const VOICE := &"bones_voice"
const FEED := &"feed_tree"
const TAGS := &"climbers_tags"
const CLIMB := &"climb_for_him"
const BOUNTY := &"bounty"
const FANATIC := &"fanatic"
const ALL: Array[StringName] = [VOICE, FEED, TAGS, CLIMB, BOUNTY, FANATIC]

## The rewards (the user's).
const VOICE_PAY := 40
const FEED_PAY := 7
const FEED_GUN := "res://weapons/revolver.tres"
const CLIMB_PAY := 50
const FANATIC_PAY := 40
const FANATIC_GRENADES := 10
## Bones for the Voice with no offering left (the user's): furious this long
## at whoever took the skull, from when they leave its home.
const NO_OFFERING_FURY := 600.0
## The Fanatic's climb (the user's): first here, this much higher each session.
const FANATIC_FIRST := 200.0
const FANATIC_STEP := 200.0
const FANATIC_TOP := 1400.0
## His bomb, after he's got all three parts: the top off this long later.
const FANATIC_FUSE := 30.0
## The 400 m trader (TraderDirector's id).
const VOICE_TRADER := "stack_400"
const BOMB_PARTS: Array[int] = [Backpack.Kind.BOMB_GAS, Backpack.Kind.BOMB_PIPE, Backpack.Kind.BOMB_WIRE]

enum State { NOT_STARTED, ACTIVE, DONE }


static func state(id: StringName) -> int:
	return int(WorldFacts.get_fact(WorldFacts.quest(id), State.NOT_STARTED))


static func fact(name: String, default: Variant = null) -> Variant:
	return WorldFacts.get_fact(StringName(name), default)


static func flag(name: String) -> bool:
	return bool(WorldFacts.get_fact(StringName(name), false))


## This world's own dice (the host's, once: kept in the facts), so what's
## "rolled per world" lands the same every session.
static func world_seed() -> int:
	var value: Variant = WorldFacts.get_fact(&"world.seed", 0)
	if int(value) == 0 and (not Network.is_online() or Network.multiplayer.is_server()):
		value = randi_range(1, 1 << 30)
		Network.send_fact(&"world.seed", value)
	return int(value)


static func world_dice(salt: int) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	dice.seed = hash([world_seed(), salt])
	return dice


## The wanderer with the torn banner (the user's: one per world).
static func torn_trader() -> String:
	var value := str(WorldFacts.get_fact(&"world.torn_trader", ""))
	if value.is_empty() and (not Network.is_online() or Network.multiplayer.is_server()):
		value = "wanderer_%d" % world_dice(17).randi_range(0, TraderDirector.WANDERERS - 1)
		Network.send_fact(&"world.torn_trader", value)
	return value


## Fed (Feed the Tree): the roots and the weed grow.
static func tree_fed() -> bool:
	return flag("tree.fed")


## Mara won't speak to you (her trader's dead).
static func mara_hates() -> bool:
	return flag("mara.hates")


## How high the Fanatic is now (m above the Stack's foot).
static func fanatic_height() -> float:
	var sessions := maxi(int(fact("fanatic.sessions", 1)), 1)
	return minf(FANATIC_FIRST + FANATIC_STEP * (sessions - 1), FANATIC_TOP)


## How much of his bomb's been brought (0..1, for the sled's size).
static func fanatic_grown() -> float:
	return clampf((fanatic_height() - FANATIC_FIRST) / (FANATIC_TOP - FANATIC_FIRST), 0.0, 1.0)


## Which of his three parts he has.
static func part_given(kind: int) -> bool:
	return flag("fanatic.part_%d" % kind)


# ---- The host: what someone did -----------------------------------------------------------

## The host: `peer` did `action` for quest `id` (Network.ask_quest).
static func act(tree: SceneTree, peer: int, id: StringName, action: StringName) -> void:
	var player := Network.body_of(peer) if Network.is_online() else PlayerMovement.local_player(tree)
	if player == null:
		return
	match id:
		VOICE:
			if action == &"accept" and state(VOICE) == State.NOT_STARTED:
				Network.send_quest(VOICE, State.ACTIVE, "")
			elif action == &"hand_in" and state(VOICE) == State.ACTIVE and take(player, Backpack.Kind.SKULL, 1):
				grant(player, {kind = Backpack.Kind.SCRAP, amount = VOICE_PAY})
				record(VOICE, "by", player)
				Network.send_quest(VOICE, State.DONE, "")
		FEED:
			if flag("cult.note_read"):
				return # (he won't deal with you)
			if action == &"accept" and state(FEED) == State.NOT_STARTED:
				Network.send_quest(FEED, State.ACTIVE, "")
			elif action == &"refuse" and state(FEED) == State.NOT_STARTED:
				Network.send_fact(&"cult.ambush", true)
				Network.send_fact(WorldFacts.quest(FEED, "refused"), true)
			elif action == &"hand_in" and state(FEED) == State.ACTIVE and tree_fed():
				grant(player, {kind = Backpack.Kind.SCRAP, amount = FEED_PAY})
				var gun := load(FEED_GUN) as WeaponData if ResourceLoader.exists(FEED_GUN) else null
				grant(player, {kind = Backpack.Kind.GUN, weapon = FEED_GUN, amount = gun.magazine_size if gun else 6})
				record(FEED, "by", player)
				Network.send_quest(FEED, State.DONE, "")
		TAGS:
			if action == &"give_tags" and state(TAGS) == State.ACTIVE and not mara_hates() and has(player, Backpack.Kind.TAGS):
				record(TAGS, "by", player)
				Network.send_quest(TAGS, State.DONE, "")
		CLIMB:
			if mara_hates():
				return
			if action == &"accept" and state(TAGS) == State.DONE and state(CLIMB) == State.NOT_STARTED:
				Network.send_quest(CLIMB, State.ACTIVE, "")
			elif action == &"leave_tags" and state(CLIMB) == State.ACTIVE and not flag("climb.tags_left") and take(player, Backpack.Kind.TAGS, 1):
				Network.send_fact(&"climb.tags_left", true)
				record(CLIMB, "left_by", player)
			elif action == &"hand_in" and state(CLIMB) == State.ACTIVE and flag("climb.tags_left"):
				grant(player, {kind = Backpack.Kind.SCRAP, amount = CLIMB_PAY})
				record(CLIMB, "by", player)
				Network.send_quest(CLIMB, State.DONE, "")
		BOUNTY:
			if flag("bounty.dead"):
				return
			if action == &"hinted":
				Network.send_fact(&"bounty.hinted", true)
			elif action == &"accept" and state(BOUNTY) == State.NOT_STARTED:
				Network.send_quest(BOUNTY, State.ACTIVE, "")
			elif action == &"hand_in" and state(BOUNTY) == State.ACTIVE and str(fact("bounty.killed", "")) == "right":
				grant(player, {kind = Backpack.Kind.BLACK_BLOOD, amount = 1})
				Network.send_fact(&"cult.sided", true)
				Network.send_fact(WorldFacts.quest(BOUNTY, "outcome"), "right")
				record(BOUNTY, "by", player)
				Network.send_quest(BOUNTY, State.DONE, "")
		FANATIC:
			_fanatic_act(tree, player, action)


static func _fanatic_act(tree: SceneTree, player: PlayerMovement, action: StringName) -> void:
	if state(FANATIC) == State.DONE:
		return
	match action:
		&"help":
			if state(FANATIC) == State.NOT_STARTED:
				Network.send_quest(FANATIC, State.ACTIVE, "")
		&"hand_in":
			if state(FANATIC) != State.ACTIVE:
				return
			var gave := false
			for kind: int in BOMB_PARTS:
				if not part_given(kind) and take(player, kind, 1):
					Network.send_fact(StringName("fanatic.part_%d" % kind), true)
					record(FANATIC, "part_%d_by" % kind, player)
					gave = true
			if gave and BOMB_PARTS.all(func(kind: int) -> bool: return part_given(kind)):
				grant(player, {kind = Backpack.Kind.SCRAP, amount = FANATIC_PAY})
				grant(player, {kind = Backpack.Kind.GRENADES, amount = FANATIC_GRENADES})
				Network.send_fact(WorldFacts.quest(FANATIC, "outcome"), "helped")
				record(FANATIC, "by", player)
				Network.send_quest(FANATIC, State.DONE, "")
				# Up he goes with it, and the top comes off.
				tree.create_timer(FANATIC_FUSE).timeout.connect(func() -> void:
					Network.send_fact(&"stack.top_gone", true))
		&"talked_down":
			Network.send_fact(WorldFacts.quest(FANATIC, "outcome"), "talked_down")
			Network.send_fact(&"fanatic.shop", true)
			record(FANATIC, "by", player)
			Network.send_quest(FANATIC, State.DONE, "")
		&"threat":
			kamikaze(tree, player)


## The host: he blows himself up (threatened, or hurt): the quest's over.
static func kamikaze(tree: SceneTree, by: PlayerMovement) -> void:
	if flag("fanatic.dead"):
		return
	Network.send_fact(&"fanatic.dead", true)
	Network.send_fact(WorldFacts.quest(FANATIC, "outcome"), "kamikaze")
	if by:
		record(FANATIC, "by", by)
	Network.send_quest(FANATIC, State.DONE, "")
	Network.send_quest_event(&"kamikaze", Vector3.ZERO)


## The host: a trader died (Trader._die): the Bounty, and Mara.
static func trader_killed(trader_id: String) -> void:
	if trader_id == torn_trader():
		Network.send_fact(&"mara.hates", true)
	if state(BOUNTY) != State.ACTIVE or not str(fact("bounty.killed", "")).is_empty():
		return
	if trader_id == torn_trader():
		Network.send_fact(&"bounty.killed", "right")
	else:
		# The wrong one: the cult mocks you, and it's failed for good.
		Network.send_fact(&"bounty.killed", "wrong")
		Network.send_fact(WorldFacts.quest(BOUNTY, "outcome"), "wrong")
		Network.send_quest(BOUNTY, State.DONE, "")


## The host: the bounty man's dead -- his note on his body.
static func bounty_man_killed(at: Vector3, tree: SceneTree) -> void:
	Network.send_fact(&"bounty.dead", true)
	if state(BOUNTY) == State.ACTIVE:
		Network.send_fact(WorldFacts.quest(BOUNTY, "outcome"), "killed")
		Network.send_quest(BOUNTY, State.DONE, "")
	QuestNote.drop(tree, at + Vector3.UP * 0.6, &"cult_note")


## The host: a note picked up (QuestNote).
static func note_read(note: StringName, player: PlayerMovement) -> void:
	match note:
		&"climber_letter":
			if state(TAGS) != State.NOT_STARTED:
				return
			grant(player, {kind = Backpack.Kind.TAGS, amount = 1})
			record(TAGS, "found_by", player)
			Network.send_quest(TAGS, State.ACTIVE, "")
		&"cult_note":
			Network.send_fact(&"cult.note_read", true)
			record(BOUNTY, "note_by", player)


## The host: the Flesh Tree's been fed (FleshTree, F with raw meat).
static func fed(player: PlayerMovement) -> void:
	if state(FEED) != State.ACTIVE or tree_fed():
		return
	Network.send_fact(&"tree.fed", true)
	record(FEED, "fed_by", player)


# ---- Helpers (the host's) -----------------------------------------------------------------

## Whether `player` has one of `kind` (hand or bag).
static func has(player: PlayerMovement, kind: int) -> bool:
	return player.hand.held_kind() == kind or player.backpack.count_of(kind) > 0


## `amount` of `kind` off `player` -- their hand first, then their bag (the
## owner's copy told). False (nothing taken) if they're short.
static func take(player: PlayerMovement, kind: int, amount: int) -> bool:
	if player.hand.held_kind() == kind:
		player.hand.use_up()
		return true
	if player.backpack.count_of(kind) < amount or not player.backpack.take(kind as Backpack.Kind, amount):
		return false
	Network.send_backpack_take(player.get_multiplayer_authority(), kind, amount)
	return true


## `item` to `player`: into their bag (the owner's copy told), or, with no
## room, dropped at their feet.
static func grant(player: PlayerMovement, item: Dictionary) -> void:
	if player.hand.store(item.duplicate()):
		player.hand.tell_owner_stored(item)
		return
	CarryItem.spawn(player.get_tree().current_scene, player.global_position + Vector3.UP * 0.8, item)


## Who did it, for the journal's own notes (their StalkerMemory id and name).
static func record(id: StringName, part: String, player: PlayerMovement) -> void:
	var profile: Dictionary = Network.profiles.get(player.get_multiplayer_authority() if player else 1, {})
	Network.send_fact(WorldFacts.quest(id, part), str(profile.get("id", "")))
	Network.send_fact(WorldFacts.quest(id, part + "_name"), str(profile.get("name", "")))
