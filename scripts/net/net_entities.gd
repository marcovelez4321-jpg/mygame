class_name NetEntities
extends Node

## Co-op: the host's creatures shown on the clients -- a Source-style entity
## list, kept simple (Network owns one).
## HOST: every creature in the "enemies" group (or GROUP, for things that
## aren't enemies but must be seen: barnacles, the worm) gets an id. To each
## client it sends:
##   a SPAWN when one comes within RELEVANT_RANGE of that client's player
##   (its scene, where it is, the few settings that make its size, its health);
##   20 times a second, where every relevant one is and its health, plus
##   whatever extra it reports (net_state(): a barnacle's tongue, the worm's
##   body) -- one small packet;
##   a DESPAWN once it's gone or out of range.
## CLIENT: makes a puppet of each from the same scene (meta "net_puppet":
## its AI only ever thinks on the host anyway; physics bodies are frozen),
## shows it INTERP_DELAY behind the newest news so it glides between updates
## (interpolation), hands its extra state to net_apply(), and passes health
## drops on to its Health -- so flinches and deaths play through the puppet's
## own reactions, exactly as offline.
## Relevance (only what's near you is sent) is what keeps the bandwidth down,
## the way Source's PVS does.

## Not enemies, but seen in co-op: anything in this group is replicated too.
const GROUP := "net_entities"
const RELEVANT_RANGE := 320.0
## Bigger things are seen from further (the worm, a megastructure's horde).
const BIG_RANGE := 900.0
const SEND_INTERVAL := 0.05
const INTERP_DELAY_MSEC := 100
const PUPPET_HOLDER := "NetPuppets"

var _next_id := 1
var _send_left := 0.0
## Host: peer id -> {entity id: true} that peer has been sent.
var _known := {}
## Host: entity id -> node (so a freed one can be told about).
var _tracked := {}
## Client: entity id -> {node, snaps: [[msec, position, rotation]]}.
var _puppets := {}


## Everything forgotten (going offline).
func reset() -> void:
	_known.clear()
	_tracked.clear()
	_puppets.clear()
	_next_id = 1


## Host: a peer left -- nothing more to send it.
func forget(peer: int) -> void:
	_known.erase(peer)


## Whether `node` is a client's copy of one of the host's creatures.
static func is_puppet(node: Node) -> bool:
	return node.has_meta(&"net_puppet")


func _physics_process(delta: float) -> void:
	if not Network.is_online():
		return
	if multiplayer.is_server():
		_host_tick(delta)


func _process(_delta: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		_show_puppets()


# ---- Host -----------------------------------------------------------------------

func _host_tick(delta: float) -> void:
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = SEND_INTERVAL
	var creatures: Array[Node3D] = []
	for group in ["enemies", GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var creature := node as Node3D
			if creature and creature.is_inside_tree() and not creatures.has(creature):
				creatures.append(creature)
	for creature in creatures:
		_tracked[_id_of(creature)] = creature
	for peer in multiplayer.get_peers():
		var body := Network.body_of(peer)
		if body == null:
			continue
		if not _known.has(peer):
			_known[peer] = {}
		var known: Dictionary = _known[peer]
		var seen := {}
		var snaps := []
		for creature in creatures:
			var id: int = creature.get_meta(&"net_id")
			var reach := BIG_RANGE if creature.has_meta(&"net_big") else RELEVANT_RANGE
			if creature.global_position.distance_to(body.global_position) > reach:
				continue
			seen[id] = true
			if not known.has(id):
				if creature.scene_file_path.is_empty() and creature.owner == null:
					continue # made in code, nothing to make it from
				known[id] = true
				_spawn.rpc_id(peer, id, creature.scene_file_path, _path_in_scene(creature), creature.global_transform,
						_size_settings(creature), _health_of(creature))
			var snap := [id, creature.global_position, creature.global_basis.get_rotation_quaternion(), _health_of(creature)[0]]
			if creature.has_method(&"net_state"):
				snap.append(creature.call(&"net_state"))
			snaps.append(snap)
		for id: int in known.keys():
			if not seen.has(id):
				known.erase(id)
				_despawn.rpc_id(peer, id)
		if not snaps.is_empty():
			_snapshot.rpc_id(peer, snaps)
	# Forget the ones that are gone.
	for id: int in _tracked.keys():
		if not is_instance_valid(_tracked[id]):
			_tracked.erase(id)


func _id_of(node: Node) -> int:
	if not node.has_meta(&"net_id"):
		node.set_meta(&"net_id", _next_id)
		_next_id += 1
	return node.get_meta(&"net_id")


## A creature that's part of the scene (placed in the level, or in a streamed
## chunk) is already on the client: found by its path, not made again.
func _path_in_scene(node: Node) -> String:
	if node.owner == null:
		return ""
	return str(get_tree().current_scene.get_path_to(node))


## What makes its size, sent so the puppet's the same size: its rolled size
## (spiders, rats: their range pinned to it) or its size setting (roaches).
static func _size_settings(node: Node) -> Dictionary:
	var settings := {}
	var size: Variant = node.get(&"size")
	if size is float:
		if node.get(&"size_min") is float:
			settings[&"size_min"] = size
			settings[&"size_max"] = size
		else:
			settings[&"size"] = size
	return settings


## [health, max health], or [-1, -1] for one with no Health.
static func _health_of(node: Node) -> Array:
	var health := node.get_node_or_null(^"Health") as Health
	if health == null:
		return [-1.0, -1.0]
	return [health.current_health, health.max_health]


# ---- Client ---------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, scene_path: String, scene_node: String, at: Transform3D, settings: Dictionary, health: Array) -> void:
	var node: Node3D = null
	var scene := get_tree().current_scene
	if scene == null:
		return
	if not scene_node.is_empty():
		node = scene.get_node_or_null(NodePath(scene_node)) as Node3D
	if node == null:
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			return
		node = (load(scene_path) as PackedScene).instantiate() as Node3D
		if node == null:
			return
		for key: StringName in settings:
			node.set(key, settings[key])
		node.set_meta(&"net_puppet", true)
		node.name = "Net_%d" % id
		_holder(scene).add_child(node)
	else:
		node.set_meta(&"net_puppet", true)
	node.global_transform = at
	if node is RigidBody3D:
		# Moved by the host's updates, not by its own physics.
		(node as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		(node as RigidBody3D).freeze = true
	var own_health := node.get_node_or_null(^"Health") as Health
	if own_health and health[0] >= 0.0:
		own_health.max_health = health[1]
		own_health.current_health = health[0]
	_puppets[id] = {node = node, snaps = []}


@rpc("authority", "call_remote", "reliable")
func _despawn(id: int) -> void:
	var puppet: Variant = _puppets.get(id)
	_puppets.erase(id)
	if puppet == null:
		return
	var node: Variant = puppet.node
	if is_instance_valid(node) and (node as Node).name.begins_with("Net_"):
		(node as Node).queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(snaps: Array) -> void:
	var now := Time.get_ticks_msec()
	for snap: Array in snaps:
		var puppet: Variant = _puppets.get(snap[0])
		if puppet == null:
			continue
		if not is_instance_valid(puppet.node):
			_puppets.erase(snap[0])
			continue
		var history: Array = puppet.snaps
		history.append([now, snap[1], snap[2]])
		if history.size() > 10:
			history.pop_front()
		_apply_health(puppet.node, snap[3])
		if snap.size() > 4 and (puppet.node as Node).has_method(&"net_apply"):
			(puppet.node as Node).call(&"net_apply", snap[4])


## The health the host says it has: a drop goes through take_damage (its
## flinch, its death), a rise is just set.
func _apply_health(node: Node, health: float) -> void:
	if health < 0.0:
		return
	var own := node.get_node_or_null(^"Health") as Health
	if own == null or own.is_dead:
		return
	if health < own.current_health - 0.01:
		own.take_damage(own.current_health - health)
	elif health > own.current_health:
		own.current_health = health


## Each puppet where the host had it INTERP_DELAY ago, between the two
## updates either side of that moment.
func _show_puppets() -> void:
	var at := Time.get_ticks_msec() - INTERP_DELAY_MSEC
	for id: int in _puppets.keys():
		var puppet: Dictionary = _puppets[id]
		var node := puppet.node as Node3D
		if not is_instance_valid(node):
			_puppets.erase(id)
			continue
		var history: Array = puppet.snaps
		if history.is_empty():
			continue
		var a: Array = history[0]
		var b: Array = history[0]
		for i in history.size():
			b = history[i]
			if int(b[0]) >= at:
				a = history[maxi(i - 1, 0)]
				break
			a = b
		var span := float(int(b[0]) - int(a[0]))
		var t := clampf(float(at - int(a[0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
		var scale := node.global_basis.get_scale()
		node.global_transform = Transform3D(Basis((a[2] as Quaternion).slerp(b[2], t)).scaled(scale), (a[1] as Vector3).lerp(b[1], t))
		# Its animation reads how fast it's going.
		var moving := ((b[1] as Vector3) - (a[1] as Vector3)) / (span / 1000.0) if span > 0.0 else Vector3.ZERO
		if node is CharacterBody3D:
			(node as CharacterBody3D).velocity = moving
		elif node is RigidBody3D:
			(node as RigidBody3D).linear_velocity = moving


func _holder(scene: Node) -> Node3D:
	var holder := scene.get_node_or_null(PUPPET_HOLDER) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = PUPPET_HOLDER
		scene.add_child(holder)
	return holder
