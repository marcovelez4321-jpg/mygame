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


## Everything it remembers, wiped (the F9 menu's, for testing).
static func forget() -> void:
	_file = ConfigFile.new()
	save()


## Your Steam name, or "" (no Steam: no name).
static func player_name() -> String:
	if Network.steam and Network.steam.available and Engine.has_singleton("Steam"):
		return str(Engine.get_singleton("Steam").call("getPersonaName"))
	return ""
