extends Node

## Co-op (RULES.md Rule 1; co-op step 1): hosting and joining by IP, and
## who's in the game. The Half-Life 2 / Source model:
##   The HOST's game is the real one. Every player's body is simulated on the
##   host from that player's input packets (PlayerMovement), so the host
##   decides where everyone is, what every shot hit and who got hurt.
##   Each CLIENT also simulates its own body straight away (prediction), so
##   moving never waits on the network; the host keeps sending back where it
##   really is, and the client folds in any difference (reconciliation).
##   Everyone else's body is shown slightly in the past, gliding between the
##   host's updates (interpolation).
##   Enemies are the host's; NetEntities shows them on the clients.
## Offline none of this runs: multiplayer.is_server() is true, there's one
## player, and the game plays exactly as it did before.
##
## On a LAN (same house, same Wi-Fi): while hosting, the game announces itself
## on the local network once a second (a UDP broadcast on LAN_PORT); the
## Co-op panel listens and lists the games it hears, so joining is one click
## -- no addresses to type. (Windows asks to let the game through its
## firewall the first time: allow it on private networks.)
##
## Joining: the client connects, the host tells it which scene it's in, the
## client loads it fresh (so nothing it made while offline is left over) and
## says it's ready, with its character. The host then makes its body
## (Player_<id>, owned by that client) on every machine, and sends the
## newcomer everyone who's already there.

signal status_changed(text: String)
## The games heard on the local network changed: [{address, name, players}].
signal lan_games_changed(games: Array)

const PORT := 7777
const MAX_CLIENTS := 3
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## How far from the player they appear next to a newcomer spawns (metres).
const SPAWN_SPREAD := 3.0
## LAN discovery: the port the announcements go out on, what they start with
## (so nothing else's broadcasts are mistaken for a game), how often they go
## out, and how long a game stays listed after its last one.
const LAN_PORT := 7778
const LAN_TAG := "MYGAME_COOP"
const LAN_EVERY := 1.0
const LAN_FORGET_MSEC := 4000

var status := "Offline"
var entities: NetEntities
## Steam co-op (invites; on when GodotSteam's installed and Steam's running).
var steam: SteamCoop
## Round trips (ms) to each peer, measured here by ping (Steam's peer has no
## ENet statistics): peer id -> msec. Net.half_ping / round_trip_msec use it.
var round_trips := {}
var _ping_left := 0.0
const PING_EVERY := 1.0
## Host: peer id -> the character it picked (its body's look on every machine).
var _characters := {}
## LAN: the host's announcer, the listener, and what it's heard
## (address -> {address, name, players, heard: msec}).
var _announcer: PacketPeerUDP
var _announce_left := 0.0
var _listener: PacketPeerUDP
var _lan_games := {}


func _init() -> void:
	# Made here, not in _ready: the pause menu (an earlier autoload) builds its
	# Co-op panel before this is ready, and asks after it.
	steam = SteamCoop.new()
	steam.name = "SteamCoop"
	add_child(steam)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the pause menu's buttons call it
	entities = NetEntities.new()
	entities.name = "NetEntities"
	add_child(entities)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


## Connected to someone (hosting with a peer, or joined). Offline: false.
func is_online() -> bool:
	return Net.is_online(self)


func host(port: int = PORT) -> void:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_set_status("Couldn't host on port %d (error %d) -- is another copy already hosting?" % [port, error])
		return
	multiplayer.multiplayer_peer = peer
	_characters = {1: GameSettings.player_character}
	_start_announcing()
	_set_status("Hosting on port %d -- waiting for someone to join" % port)


## This machine's addresses on the local network (what a buddy in the same
## house types to join, if the list doesn't show the game).
func lan_addresses() -> PackedStringArray:
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_172_private(address):
			found.append(address)
	return found


static func _is_172_private(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var second := address.get_slice(".", 1).to_int()
	return second >= 16 and second <= 31


## Starts (or keeps) listening for games on the local network.
func start_lan_search() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(LAN_PORT) != OK:
		_listener = null # another copy on this PC is already listening: fine, it's for testing
		return


func stop_lan_search() -> void:
	if _listener:
		_listener.close()
		_listener = null
	_lan_games.clear()
	lan_games_changed.emit([])


func _start_announcing() -> void:
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_announcer.set_dest_address("255.255.255.255", LAN_PORT)
	_announce_left = 0.0


func _process(delta: float) -> void:
	# Ping everyone now and then (the round trips, for any kind of peer).
	if is_online() and not (multiplayer.multiplayer_peer is ENetMultiplayerPeer):
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_EVERY
			_net_ping.rpc(Time.get_ticks_msec())
	if _announcer and multiplayer.is_server():
		_announce_left -= delta
		if _announce_left <= 0.0:
			_announce_left = LAN_EVERY
			var who := OS.get_environment("USERNAME")
			if who.is_empty():
				who = "Someone"
			var text := "%s|%s|%d|%d" % [LAN_TAG, who, PORT, multiplayer.get_peers().size() + 1]
			_announcer.put_packet(text.to_utf8_buffer())
	if _listener:
		_listen()


func _listen() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var text := _listener.get_packet().get_string_from_utf8()
		var address := _listener.get_packet_ip()
		var parts := text.split("|")
		if parts.size() < 4 or parts[0] != LAN_TAG:
			continue
		if _announcer and lan_addresses().has(address):
			continue # our own game
		changed = changed or not _lan_games.has(address)
		_lan_games[address] = {address = address, name = parts[1], players = parts[3].to_int(), heard = Time.get_ticks_msec()}
	for address: String in _lan_games.keys():
		if Time.get_ticks_msec() - int(_lan_games[address].heard) > LAN_FORGET_MSEC:
			_lan_games.erase(address)
			changed = true
	if changed:
		lan_games_changed.emit(_lan_games.values())


func join(address: String, port: int = PORT) -> void:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		_set_status("Couldn't start joining %s (error %d)" % [address, error])
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Joining %s..." % address)


## Steam's connection is up (SteamCoop): hosting, or joining a lobby's owner.
## From here it's the same as hosting / joining by address.
func use_steam_peer(peer: MultiplayerPeer, hosting: bool) -> void:
	multiplayer.multiplayer_peer = peer
	if hosting:
		_characters = {1: GameSettings.player_character}
		_set_status("Hosting on Steam -- press Invite friends")
	else:
		_set_status("Joining through Steam...")


## Back to playing alone. A host keeps its world (minus the others' bodies);
## a client's world was the host's, so it starts its scene fresh.
func leave() -> void:
	var was_client := is_online() and not multiplayer.is_server()
	_close()
	steam.leave_lobby()
	_set_status("Offline")
	if was_client:
		get_tree().reload_current_scene()
	else:
		for body in _remote_bodies():
			body.queue_free()


## The body owned by peer `id` (the host's is the scene's own Player), or null.
func body_of(id: int) -> PlayerMovement:
	return Net.body_of(self, id) as PlayerMovement


## Host: where a dead player comes back -- beside someone still alive, or
## where they first came in.
func respawn_point(body: PlayerMovement) -> Vector3:
	for node in get_tree().get_nodes_in_group("player"):
		var other := node as PlayerMovement
		if other != body and not other.is_dead():
			return other.global_position + _beside()
	return body.spawn_position


## Host: an explosion's look, to everyone but whoever set it off (their own
## game already showed it).
func send_explosion(center: Vector3, radius: float, knockback: float, attacker_id: int) -> void:
	for peer in multiplayer.get_peers():
		if peer != attacker_id:
			_explosion.rpc_id(peer, center, radius, knockback)


## Host: one of the Stalker's sounds (StalkerSound), here and on every machine.
func send_stalker_sound(kind: int, at: Vector3) -> void:
	StalkerSound.play(kind, at, get_tree().current_scene)
	if is_online():
		_stalker_sound.rpc(kind, at)


## Host: one of the heart's blood beams (BloodBeam), on every machine -- only
## the host's deals hits. `exclude`: what it passes through here (the heart).
func send_blood_beam(from: Vector3, direction: Vector3, warn: float, exclude: Array[RID] = []) -> void:
	BloodBeam.fire(get_tree().current_scene, from, direction, warn, true, exclude)
	if is_online():
		_net_blood_beam.rpc(from, direction, warn)


@rpc("authority", "call_remote", "reliable")
func _net_blood_beam(from: Vector3, direction: Vector3, warn: float) -> void:
	# Late by the trip here: its warning's that much shorter, so it fires with the host's.
	BloodBeam.fire(get_tree().current_scene, from, direction, maxf(warn - half_ping(), 0.0), false)


## Host: the heart's kick (HeartQuake) -- the shake, dust and chunks
## (breaking off at `spots`) on every machine; only the host's launches.
func send_heart_kick(spots: PackedVector3Array) -> void:
	_heart_kick(spots, true)
	if is_online():
		_net_heart_kick.rpc(spots)


@rpc("authority", "call_remote", "reliable")
func _net_heart_kick(spots: PackedVector3Array) -> void:
	_heart_kick(spots, false)


func _heart_kick(spots: PackedVector3Array, decides: bool) -> void:
	var heart := get_tree().get_first_node_in_group(&"heart_boss") as Node3D
	if heart:
		heart.call(&"quake", spots, decides)


## Host: the heart's cathedral rearranging (HeartBoss.shift): where each of
## its structures heads now, on every machine.
func send_heart_shift(spots: PackedVector3Array) -> void:
	_heart_shift(spots)
	if is_online():
		_net_heart_shift.rpc(spots)


@rpc("authority", "call_remote", "reliable")
func _net_heart_shift(spots: PackedVector3Array) -> void:
	_heart_shift(spots)


func _heart_shift(spots: PackedVector3Array) -> void:
	var heart := get_tree().get_first_node_in_group(&"heart_boss") as Node3D
	if heart:
		heart.call(&"shift", spots)


## Host: something happening to the heart (HeartBoss.event: hit, stun,
## recover, die), on every machine.
func send_heart_event(kind: StringName) -> void:
	_heart_event(kind)
	if is_online():
		_net_heart_event.rpc(kind)


@rpc("authority", "call_remote", "reliable")
func _net_heart_event(kind: StringName) -> void:
	_heart_event(kind)


func _heart_event(kind: StringName) -> void:
	var heart := get_tree().get_first_node_in_group(&"heart_boss") as Node3D
	if heart:
		heart.call(&"event", kind)


## Host: words on one player's screen (the bottom-middle message), wherever
## they are.
func send_message(peer_id: int, text: String) -> void:
	if not is_online() or peer_id == multiplayer.get_unique_id():
		MapIO.show_message(get_tree(), text)
	elif is_online():
		_net_message.rpc_id(peer_id, text)


@rpc("authority", "call_remote", "reliable")
func _net_message(text: String) -> void:
	MapIO.show_message(get_tree(), text)


## Host: a player taken by the Stalker (or let go), here and everywhere.
## `throw`: let go with a fling (broke out of its grip), else zero.
func send_stalker_drag(peer_id: int, on: bool, throw: Vector3 = Vector3.ZERO) -> void:
	_stalker_drag(peer_id, on, throw)
	if is_online():
		_net_stalker_drag.rpc(peer_id, on, throw)


@rpc("authority", "call_remote", "reliable")
func _net_stalker_drag(peer_id: int, on: bool, throw: Vector3) -> void:
	_stalker_drag(peer_id, on, throw)


func _stalker_drag(peer_id: int, on: bool, throw: Vector3 = Vector3.ZERO) -> void:
	var stalker := get_tree().get_first_node_in_group("stalker") as Node3D
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and player.get_multiplayer_authority() == peer_id:
			if on and stalker:
				StalkerDrag.begin(player, stalker)
			elif not on:
				StalkerDrag.finish(player, throw)


@rpc("authority", "call_remote", "reliable")
func _stalker_sound(kind: int, at: Vector3) -> void:
	StalkerSound.play(kind, at, get_tree().current_scene)


@rpc("authority", "call_remote", "unreliable")
func _explosion(center: Vector3, radius: float, knockback: float) -> void:
	var scene := get_tree().current_scene as Node3D
	if scene:
		Explosion.play_effects(scene, center, radius, knockback)


## Client: half the round trip to the host, in seconds (0 on the host or offline).
func half_ping() -> float:
	return Net.half_ping(self)


@rpc("any_peer", "call_remote", "unreliable")
func _net_ping(sent: int) -> void:
	_net_pong.rpc_id(multiplayer.get_remote_sender_id(), sent)


@rpc("any_peer", "call_remote", "unreliable")
func _net_pong(sent: int) -> void:
	round_trips[multiplayer.get_remote_sender_id()] = Time.get_ticks_msec() - sent


func _close() -> void:
	if _announcer:
		_announcer.close()
		_announcer = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_characters.clear()
	round_trips.clear()
	entities.reset()


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


func _beside() -> Vector3:
	var around := Vector2.from_angle(randf() * TAU) * SPAWN_SPREAD
	return Vector3(around.x, 0.5, around.y)


func _remote_bodies() -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group("player"):
		if node.name.begins_with("Player_"):
			found.append(node)
	return found


# ---- Host -----------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_set_status("Player %d connected -- loading in" % id)
	_go_to_scene.rpc_id(id, get_tree().current_scene.scene_file_path)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_characters.erase(id)
	entities.forget(id)
	_remove_body(id)
	_remove_body.rpc(id)
	if multiplayer.get_peers().is_empty():
		_set_status("Hosting on Steam -- press Invite friends" if steam.hosting else "Hosting on port %d -- waiting for someone to join" % PORT)
	else:
		_set_status("Player %d left" % id)


## A client has loaded the host's scene: its body, everywhere, and everyone
## already here, to it.
@rpc("any_peer", "call_remote", "reliable")
func _ready_to_play(character: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_characters[id] = character
	var host_body := body_of(1)
	if host_body:
		_set_character.rpc_id(id, 1, str(_characters.get(1, "")))
	for other: int in _characters:
		var body := body_of(other)
		if other != 1 and other != id and body:
			_spawn_body.rpc_id(id, other, body.global_position, str(_characters[other]))
	var at := (host_body.global_position if host_body else Vector3.ZERO) + _beside()
	_spawn_body(id, at, character)
	_spawn_body.rpc(id, at, character)
	var count := multiplayer.get_peers().size() + 1
	_set_status("Hosting -- %d players in" % count)


# ---- Client ---------------------------------------------------------------------

func _on_connected() -> void:
	_set_status("Connected -- waiting for the host")


func _on_connection_failed() -> void:
	_close()
	steam.leave_lobby()
	_set_status("Couldn't reach the host (wrong address, or nobody hosting?)")


func _on_server_gone() -> void:
	_close()
	steam.leave_lobby()
	_set_status("The host left")
	get_tree().reload_current_scene()


## The host's scene, loaded fresh; then ready to play.
@rpc("authority", "call_remote", "reliable")
func _go_to_scene(path: String) -> void:
	_set_status("Connected -- loading the host's world")
	get_tree().change_scene_to_file(path)
	# The new scene goes in at the end of this frame; give its nodes a frame
	# to be ready before the host starts sending bodies into it.
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_to_play.rpc_id(1, GameSettings.player_character)
	_set_status("Playing on the host's game")


# ---- Everyone -------------------------------------------------------------------

## A player's body: Player_<id>, owned by that peer (it's the one that sends
## its input); on that peer's own machine it's the one you play.
@rpc("authority", "call_remote", "reliable")
func _spawn_body(id: int, at: Vector3, character: String) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.has_node(NodePath("Player_%d" % id)):
		return
	var body := PLAYER_SCENE.instantiate() as PlayerMovement
	body.name = "Player_%d" % id
	body.set_multiplayer_authority(id)
	body.position = at
	scene.add_child(body)
	if id != multiplayer.get_unique_id():
		_set_character(id, character)


@rpc("authority", "call_remote", "reliable")
func _set_character(id: int, character: String) -> void:
	var body := body_of(id)
	if body == null or character.is_empty():
		return
	var model := body.get_node_or_null(^"PlayerModel") as PlayerModel
	if model:
		model.set_character(character)


@rpc("authority", "call_remote", "reliable")
func _remove_body(id: int) -> void:
	var scene := get_tree().current_scene
	var body := scene.get_node_or_null(NodePath("Player_%d" % id)) if scene else null
	if body:
		body.queue_free()
