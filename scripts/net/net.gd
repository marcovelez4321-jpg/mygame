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
	var peer := node.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or node.multiplayer.is_server():
		return 0.0
	var host := peer.get_peer(1)
	if host == null:
		return 0.0
	return host.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0