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
##
## LAG COMPENSATION (Source's, from Half-Life on): the host keeps where every
## creature was over the last HISTORY_MSEC. A client sees them in the past --
## its ping, plus INTERP_DELAY -- so when the host runs that client's shot it
## first moves every creature back to where the client saw it (rewind_for()),
## casts the shot, and puts them all back (restore()), in the same instant.
## Aim where they are on YOUR screen and it hits. Hitscan only: rockets and
## grenades fly in real time on the host (Source does the same).

## Not enemies, but seen in co-op: anything in this group is replicated too.
const GROUP := "net_entities"
const RELEVANT_RANGE := 320.0
## Bigger things are seen from further (the worm, a megastructure's horde).
const BIG_RANGE := 900.0
const SEND_INTERVAL := 0.05
const INTERP_DELAY_MSEC := 100
const PUPPET_HOLDER := "NetPuppets"
## A spawn of something made in code: this, then its script's path (it's
## made with .new() and handed its net_spawn_args() through net_restore()).
const SCRIPT_PREFIX := "script:"
## How far back the host can rewind (Source's sv_maxunlag is 1 s).
const HISTORY_MSEC := 1000

var _next_id := 1
var _send_left := 0.0
## Host: peer id -> {entity id: true} that peer has been sent.
var _known := {}
## Host: entity id -> node (so a freed one can be told about).
var _tracked := {}
## Client: entity id -> {node, snaps: [[msec, position, rotation]]}.
var _puppets := {}
## Host: creature -> [[msec, global transform], ...] over the last
## HISTORY_MSEC (lag compensation).
var _history := {}


## Everything forgotten (going offline).
func reset() -> void:
	_known.clear()
	_tracked.clear()
	_puppets.clear()
	_history.clear()
	_next_id = 1


## Host: a peer left -- nothing more to send it.
func forget(peer: int) -> void:
	_known.erase(peer)


## Whether `node` is a client's copy of one of the host's creatures.
static func is_puppet(node: Node) -> bool:
	return node.has_meta(&"net_puppet")


func _physics_process(delta: float) -> void:
	if not Net.is_online(self):
		return
	if multiplayer.is_server():
		_host_tick(delta)


func _process(_delta: float) -> void:
	if Net.is_online(self) and not multiplayer.is_server():
		_show_puppets()


# ---- Host -----------------------------------------------------------------------

func _host_tick(delta: float) -> void:
	var creatures := _creatures()
	_record_history(creatures)
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = SEND_INTERVAL
	for creature in creatures:
		_tracked[_id_of(creature)] = creature
	for peer in multiplayer.get_peers():
		var body := Net.body_of(self, peer)
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
				var made_from := creature.scene_file_path
				var settings := _size_settings(creature)
				if made_from.is_empty() and creature.owner == null:
					# Made in code: only if it can say how to make it again
					# (net_spawn_args(): a meat chunk, a pod -- CarryItem).
					if not creature.has_method(&"net_spawn_args") or creature.get_script() == null:
						continue
					made_from = SCRIPT_PREFIX + (creature.get_script() as Script).resource_path
					settings = creature.call(&"net_spawn_args")
				known[id] = true
				_spawn.rpc_id(peer, id, made_from, _path_in_scene(creature), creature.global_transform,
						settings, _health_of(creature))
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


func _creatures() -> Array[Node3D]:
	var creatures: Array[Node3D] = []
	var seen := {}
	for group in ["enemies", GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var creature := node as Node3D
			if creature and creature.is_inside_tree() and not seen.has(creature):
				seen[creature] = true
				creatures.append(creature)
	return creatures


## Host, every physics frame: where each creature is now, kept HISTORY_MSEC.
func _record_history(creatures: Array[Node3D]) -> void:
	var now := Time.get_ticks_msec()
	for creature in creatures:
		if not _history.has(creature):
			_history[creature] = []
		var samples: Array = _history[creature]
		samples.append([now, creature.global_transform])
		while samples.size() > 2 and now - int(samples[0][0]) > HISTORY_MSEC:
			samples.pop_front()
	for creature: Variant in _history.keys():
		if not is_instance_valid(creature):
			_history.erase(creature)


## Host: every living creature within `reach` of `near` moved back to where
## client `peer` saw it when it sent the input that arrived at
## `arrival_msec`: that's its ping (the input's trip here and the creatures'
## news's trip to it) plus how far behind the newest news it shows them
## (INTERP_DELAY). The whole creature moves (its skeleton too, so head and
## artery hits are judged where they were), and its bodies are made static
## for the instant -- in Jolt a moving (kinematic) body only goes where it's
## put at the next physics step, a static one at once. Returns what to give
## restore(). Nothing's moved for the host itself, or offline.
func rewind_for(peer: int, arrival_msec: int, near: Vector3, reach: float) -> Array:
	var moved: Array = []
	if peer == multiplayer.get_unique_id() or not Net.is_online(self):
		return moved
	var now := Time.get_ticks_msec()
	var seen_at := arrival_msec - int(Net.round_trip_msec(self, peer)) - INTERP_DELAY_MSEC
	seen_at = clampi(seen_at, now - HISTORY_MSEC, now)
	for creature: Variant in _history:
		if not is_instance_valid(creature):
			continue
		var node := creature as Node3D
		if node.global_position.distance_to(near) > reach + 10.0:
			continue
		var health := node.get_node_or_null(^"Health") as Health
		if health and health.is_dead:
			continue
		var bodies: Array = []
		var modes: Array = []
		var all := node.find_children("*", "CollisionObject3D", true, false)
		if node is CollisionObject3D:
			all.push_front(node)
		var now_at := node.global_transform
		node.global_transform = _transform_at(_history[creature], seen_at)
		for body: Node in all:
			var rid := (body as CollisionObject3D).get_rid()
			var mode := PhysicsServer3D.body_get_mode(rid)
			if mode == PhysicsServer3D.BODY_MODE_KINEMATIC:
				PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
				bodies.append(body)
				modes.append(mode)
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, (body as Node3D).global_transform)
		moved.append([node, now_at, all, bodies, modes])
	return moved


## Puts every creature rewind_for() moved back where it really is, its
## bodies as they were.
func restore(moved: Array) -> void:
	for entry: Array in moved:
		var node: Variant = entry[0]
		if not is_instance_valid(node):
			continue
		(node as Node3D).global_transform = entry[1]
		for body: Variant in entry[2]:
			if is_instance_valid(body):
				PhysicsServer3D.body_set_state((body as CollisionObject3D).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, (body as Node3D).global_transform)
		var bodies: Array = entry[3]
		var modes: Array = entry[4]
		for i in bodies.size():
			if is_instance_valid(bodies[i]):
				PhysicsServer3D.body_set_mode((bodies[i] as CollisionObject3D).get_rid(), modes[i])


## Where a creature was at `msec`, between the samples either side of it.
static func _transform_at(samples: Array, msec: int) -> Transform3D:
	var a: Array = samples[0]
	for i in samples.size():
		var b: Array = samples[i]
		if int(b[0]) >= msec:
			var span := float(int(b[0]) - int(a[0]))
			var t := clampf(float(msec - int(a[0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
			return (a[1] as Transform3D).interpolate_with(b[1], t)
		a = b
	return a[1]

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
	# One of the big ones (BigOnes): the puppet's made big too.
	if node.has_meta(&"big"):
		settings[&"__big"] = true
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
		if scene_path.begins_with(SCRIPT_PREFIX):
			var script_path := scene_path.trim_prefix(SCRIPT_PREFIX)
			if not ResourceLoader.exists(script_path):
				return
			node = (load(script_path) as GDScript).new() as Node3D
			if node == null:
				return
			node.call(&"net_restore", settings)
		else:
			if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
				return
			node = (load(scene_path) as PackedScene).instantiate() as Node3D
			if node == null:
				return
			for key: StringName in settings:
				if key == &"__big":
					BigOnes.make_puppet_big(node)
				else:
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
