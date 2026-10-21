class_name StalkerMemory
extends RefCounted

## The Stalker remembers you between sessions (the user's, 2026-10-21: "a
## living thing inside their PC"): what it's learnt of you -- your habits, your
## ways, where it was shot, how many times it got you, its hunger and tension,
## where you logged off and last camped -- kept in the game's own save folder
## (PATH). Nothing else on the computer is touched; only the clock and the
## Steam name are read. The host's memory runs it (Stalker); every game counts
## its own sessions (the loading cover's silhouette: ShaderWarmup).

const PATH := "user://stalker_memory.cfg"
const SECTION := "stalker"

static var _file: ConfigFile
static var _session_noted := false
static var _hours_away := -1.0


static func file() -> ConfigFile:
	if _file == null:
		_file = ConfigFile.new()
		_file.load(PATH) # (missing the first time: empty)
	return _file


static func get_value(key: String, default: Variant) -> Variant:
	return file().get_value(SECTION, key, default)


static func set_value(key: String, value: Variant) -> void:
	file().set_value(SECTION, key, value)


static func save() -> void:
	file().save(PATH)


## This launch is a session (counted once): and how long since the last one
## ended, in hours (-1: there wasn't one).
static func note_session() -> void:
	if _session_noted:
		return
	_session_noted = true
	var last := float(get_value("last_end", -1.0))
	_hours_away = (Time.get_unix_time_from_system() - last) / 3600.0 if last > 0.0 else -1.0
	set_value("sessions", int(get_value("sessions", 0)) + 1)
	save()


static func sessions() -> int:
	return int(get_value("sessions", 0))


static func hours_away() -> float:
	return _hours_away


## Everything it remembers, wiped (the F9 menu's, for testing) -- this PC's
## record of you too (a new you).
static func forget() -> void:
	_file = ConfigFile.new()
	save()


## A player's record (the user's, 2026-10-21: it knows each of you): who
## (an id made once on their PC; their Steam name, or none) and what it's
## learnt of them -- the times it got them, their habits, the grudge, how long
## they've known it, where they logged off and last camped, what it's seen
## them do, how many sessions.
const DEFAULTS := {id = "", name = "", got = 0, spins = 0, stares = 0, grudge = 0.0, known = 0.0,
		logoff = null, last_camp = null, seen = {}, sessions = 0}
const ME := "me"


## This PC's own record of you -- kept here, on your PC, so it goes with you
## to any game you join (Network.send_my_profile).
static func my_profile() -> Dictionary:
	var me: Dictionary = file().get_value(ME, "profile", {})
	for key: String in DEFAULTS:
		if not me.has(key):
			me[key] = DEFAULTS[key].duplicate(true) if DEFAULTS[key] is Dictionary else DEFAULTS[key]
	if str(me.id).is_empty():
		me.id = "%08x%08x" % [randi(), randi()]
		# What it learnt of you before it knew each of you apart: yours now.
		me.got = int(get_value("got_you", 0))
		me.spins = int(get_value("spins", 0))
		me.stares = int(get_value("stares", 0))
		me.seen = get_value("seen_doing", {})
		var logoff: Variant = get_value("logoff", null)
		me.logoff = logoff if logoff is Vector3 and (logoff as Vector3).is_finite() else null
		var camp: Variant = get_value("last_camp", null)
		me.last_camp = camp if camp is Vector3 and (camp as Vector3).is_finite() else null
		save_my_profile(me)
	me.name = player_name()
	me.sessions = sessions()
	return me


## Your record, back from the game you played in (kept here).
static func save_my_profile(profile: Dictionary) -> void:
	file().set_value(ME, "profile", profile)
	save()


## Your Steam name, or "" (no Steam: no name).
static func player_name() -> String:
	if Network.steam and Network.steam.available and Engine.has_singleton("Steam"):
		return str(Engine.get_singleton("Steam").call("getPersonaName"))
	return ""
