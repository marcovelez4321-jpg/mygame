class_name Net
extends RefCounted

## Co-op checks any script can make without the Network autoload (which
## isn't there in tools and bakes: an autoload only exists while the game
## runs). Each asks the node's own multiplayer.

## Connected to someone (hosting with a peer, or joined). Offline: false.
static func is_online(node: Node) -> bool:
	var peer := node.multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## A client's half round trip to the host, in seconds: how stale the host's
## news is when it arrives (0 on the host or offline).
static func half_ping(node: Node) -> float:
	if node.multiplayer.is_server():
		return 0.0
	var peer := node.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return _measured(node, 1) / 2000.0 # (Steam: Network's own pings)
	var host := peer.get_peer(1)
	if host == null:
		return 0.0
	return host.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0


## Host: the round trip to client `peer`, in milliseconds (0 if unknown).
static func round_trip_msec(node: Node, peer: int) -> float:
	var enet := node.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return _measured(node, peer) # (Steam: Network's own pings)
	var connection := enet.get_peer(peer)
	if connection == null:
		return 0.0
	return connection.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## The round trip to `peer` Network measured by pinging (ms; 0 if none yet).
static func _measured(node: Node, peer: int) -> float:
	var network := node.get_node_or_null(^"/root/Network")
	if network == null:
		return 0.0
	var trips: Variant = network.get("round_trips")
	return float((trips as Dictionary).get(peer, 0.0)) if trips is Dictionary else 0.0


## The body owned by peer `id` (the host's is the scene's own Player), or null.
## (A plain Node3D: naming PlayerMovement here would tie Net to the player's
## script, which needs the game's autoloads -- and Net must load in bakes.)
static func body_of(node: Node, id: int) -> Node3D:
	for player in node.get_tree().get_nodes_in_group("player"):
		if player.get_multiplayer_authority() == id:
			return player as Node3D
	return null
