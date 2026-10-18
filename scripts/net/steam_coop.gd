class_name SteamCoop
extends Node

## Co-op through Steam (the user's: invites), on top of Network's game flow.
## Needs the GodotSteam extension and its SteamMultiplayerPeer installed, and
## Steam running (docs/STEAM.md). Without them this stays off and co-op is by
## IP / LAN as ever -- every Steam call goes through Engine.get_singleton()
## and ClassDB, so the game compiles and runs without the extension.
##   HOST (Host on Steam): a friends-only Steam lobby, and the game hosted
##   over Steam's own relays (SteamMultiplayerPeer: no ports, no addresses).
##   Invite friends opens Steam's invite list; friends can also right-click
##   you in Steam and Join Game.
##   JOIN: accepting an invite -- in the game, from the friends list, or by
##   launching the game from it (+connect_lobby <id>) -- joins the lobby and
##   connects to its owner over Steam.
## After the connection everything is Network's usual: the host's scene, the
## bodies, play.

signal state_changed

## Steam's app: Spacewar (Valve's free test app, 480) until the game has its
## own App ID from Steamworks -- then this, and steam_appid.txt.
const APP_ID := 480
const LOBBY_FRIENDS_ONLY := 1 # Steam's k_ELobbyTypeFriendsOnly
const RESULT_OK := 1 # k_EResultOK
const ENTER_OK := 1 # k_EChatRoomEnterResponseSuccess
const VIRTUAL_PORT := 0
## The lobby holds the host and Network.MAX_CLIENTS others.
const MAX_MEMBERS := 4

## Steam's up and SteamMultiplayerPeer's there: Steam co-op can be used.
var available := false
## Why not, if it isn't (shown in the Co-op panel).
var why_not := "starting up"
## The lobby we're in (0: none), and whether we made it.
var lobby_id := 0
var hosting := false
var _steam: Object
var _network: Node
var _pending_join := 0


func _ready() -> void:
	_network = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start()
	state_changed.emit() # (the Co-op panel may have asked before this was up)


func _start() -> void:
	if not Engine.has_singleton("Steam"):
		why_not = "GodotSteam isn't installed (see docs/STEAM.md)"
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		why_not = "GodotSteam's SteamMultiplayerPeer isn't installed (see docs/STEAM.md)"
		return
	_steam = Engine.get_singleton("Steam")
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	if not _init_steam():
		return
	available = true
	why_not = ""
	for pair: Array in [["lobby_created", _on_lobby_created], ["lobby_joined", _on_lobby_joined],
			["join_requested", _on_join_requested], ["join_game_requested", _on_join_game_requested]]:
		if _steam.has_signal(pair[0]):
			_steam.connect(pair[0], pair[1])
	# Launched from an invite: Steam passes the lobby on the command line.
	var args := OS.get_cmdline_args()
	var at := args.find("+connect_lobby")
	if at >= 0 and at + 1 < args.size():
		_pending_join = args[at + 1].to_int()


func _init_steam() -> bool:
	if _steam.has_method("steamInitEx"):
		# (Our app ID, and our own run_callbacks in _process. If the project's
		# Steam settings already started it, this just says so.)
		var result: Variant = _steam.call("steamInitEx", APP_ID, false)
		var status: int = int((result as Dictionary).get("status", -1)) if result is Dictionary else int(result)
		if status != 0:
			why_not = "Steam didn't start (%s) -- is Steam running?" % (result as Dictionary).get("verbal", status) if result is Dictionary else "Steam didn't start -- is Steam running?"
			return false
		return true
	if _steam.has_method("steamInit"):
		var result: Variant = _steam.call("steamInit")
		if result is Dictionary and int((result as Dictionary).get("status", 0)) != 1:
			why_not = "Steam didn't start -- is Steam running?"
			return false
		return true
	why_not = "GodotSteam's Steam has no steamInit"
	return false


func _process(_delta: float) -> void:
	if not available:
		return
	_steam.call("run_callbacks")
	if _pending_join != 0 and get_tree().current_scene != null:
		var lobby := _pending_join
		_pending_join = 0
		join_lobby(lobby)


# ---- Hosting --------------------------------------------------------------------

## Host on Steam: a friends-only lobby, then the game over Steam.
func host() -> void:
	if not available:
		return
	_network.call(&"_close")
	leave_lobby()
	hosting = true
	_network.call(&"_set_status", "Making a Steam lobby...")
	_steam.call("createLobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)


func _on_lobby_created(result: int, id: int) -> void:
	if result != RESULT_OK:
		hosting = false
		_network.call(&"_set_status", "Steam couldn't make a lobby (result %d)" % result)
		return
	lobby_id = id
	_steam.call("setLobbyJoinable", id, true)
	_steam.call("setLobbyData", id, "name", str(_steam.call("getPersonaName")))
	_steam.call("setLobbyData", id, "game", "2V2")
	if _steam.has_method("setRichPresence"):
		_steam.call("setRichPresence", "connect", "+connect_lobby %d" % id)
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	var error: int = peer.call("create_host", VIRTUAL_PORT)
	if error != OK:
		hosting = false
		leave_lobby()
		_network.call(&"_set_status", "Couldn't host over Steam (error %d)" % error)
		return
	_network.call(&"use_steam_peer", peer, true)
	state_changed.emit()


## Steam's invite list, for the lobby we're hosting (or in).
func invite() -> void:
	if available and lobby_id != 0:
		_steam.call("activateGameOverlayInviteDialog", lobby_id)


# ---- Joining --------------------------------------------------------------------

## An invite accepted in the game (or the friends list's Join Game).
func _on_join_requested(lobby: int, _friend: int) -> void:
	join_lobby(lobby)


## Join Game on a friend through their rich presence ("+connect_lobby <id>").
func _on_join_game_requested(_friend: int, connect: String) -> void:
	var parts := connect.split(" ", false)
	var at := parts.find("+connect_lobby")
	if at >= 0 and at + 1 < parts.size():
		join_lobby(parts[at + 1].to_int())


func join_lobby(id: int) -> void:
	if not available or id == 0:
		return
	_network.call(&"_close")
	leave_lobby()
	hosting = false
	_network.call(&"_set_status", "Joining through Steam...")
	_steam.call("joinLobby", id)


func _on_lobby_joined(lobby: int, _permissions: int, _locked: int, response: int) -> void:
	if response != ENTER_OK:
		_network.call(&"_set_status", "Couldn't join that Steam lobby (response %d)" % response)
		return
	lobby_id = lobby
	var owner: int = _steam.call("getLobbyOwner", lobby)
	if owner == int(_steam.call("getSteamID")):
		return # (our own lobby: we're its host already)
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	var error: int = peer.call("create_client", owner, VIRTUAL_PORT)
	if error != OK:
		leave_lobby()
		_network.call(&"_set_status", "Couldn't connect over Steam (error %d)" % error)
		return
	_network.call(&"use_steam_peer", peer, false)
	state_changed.emit()


func leave_lobby() -> void:
	if available and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
		if _steam.has_method("clearRichPresence"):
			_steam.call("clearRichPresence")
	lobby_id = 0
	hosting = false
	state_changed.emit()
