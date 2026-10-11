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
## Joining: the client connects, the host tells it which scene it's in, the
## client loads it fresh (so nothing it made while offline is left over) and
## says it's ready, with its character. The host then makes its body
## (Player_<id>, owned by that client) on every machine, and sends the
## newcomer everyone who's already there.

signal status_changed(text: String)

const PORT := 7777
const MAX_CLIENTS := 3
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## How far from the player they appear next to a newcomer spawns (metres).
const SPAWN_SPREAD := 3.0

var status := "Offline"
var entities: NetEntities
## Host: peer id -> the character it picked (its body's look on every machine).
var _characters := {}


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
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host(port: int = PORT) -> void:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_set_status("Couldn't host on port %d (error %d) -- is another copy already hosting?" % [port, error])
		return
	multiplayer.multiplayer_peer = peer
	_characters = {1: GameSettings.player_character}
	_set_status("Hosting on port %d -- waiting for someone to join" % port)


func join(address: String, port: int = PORT) -> void:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		_set_status("Couldn't start joining %s (error %d)" % [address, error])
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Joining %s..." % address)


## Back to playing alone. A host keeps its world (minus the others' bodies);
## a client's world was the host's, so it starts its scene fresh.
func leave() -> void:
	var was_client := is_online() and not multiplayer.is_server()
	_close()
	_set_status("Offline")
	if was_client:
		get_tree().reload_current_scene()
	else:
		for body in _remote_bodies():
			body.queue_free()


## The body owned by peer `id` (the host's is the scene's own Player), or null.
func body_of(id: int) -> PlayerMovement:
	for node in get_tree().get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == id:
			return node as PlayerMovement
	return null


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


@rpc("authority", "call_remote", "unreliable")
func _explosion(center: Vector3, radius: float, knockback: float) -> void:
	var scene := get_tree().current_scene as Node3D
	if scene:
		Explosion.play_effects(scene, center, radius, knockback)


## Client: half the round trip to the host, in seconds -- how stale the
## host's news is when it gets here (0 on the host or offline).
func half_ping() -> float:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or multiplayer.is_server():
		return 0.0
	var host := peer.get_peer(1)
	if host == null:
		return 0.0
	return host.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0


func _close() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_characters.clear()
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
		_set_status("Hosting on port %d -- waiting for someone to join" % PORT)
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
	_set_status("Couldn't reach the host (wrong address, or nobody hosting?)")


func _on_server_gone() -> void:
	_close()
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
