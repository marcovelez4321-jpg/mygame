class_name RedCreep
extends Node3D

## The red creep (the user's, 2026-10-27; docs/RED_CREEP.md): the red weed
## come alive in the Stacks -- a sentient, mold-like growth whose one goal is
## to spread. It starts as one bush in each area (`areas`), each sending out
## its ropes (RedCreepPatch), and then:
##   SEEDS: anything alive that touches a bush or its ropes picks up its seeds
##   (red barbs on it); they fall off SEED_TIME later wherever it's got to,
##   and a new small bush grows there.
##   NURSERIES: anything it drains to death, and any body its ropes reach,
##   is grown over into a new bush.
##   NOISE AND BLOOD: gunshots, hits and explosions (WeaponController,
##   Explosion) draw its growing tips that way for STIMULUS_TIME, faster.
##   LINKS: a patch sends a runner to any other within LINK_RANGE; joined,
##   they're one network, pulsing as one (the shader's pulse_phase). A cut
##   runner unlinks them.
##   WRAPS: life it reaches is held, drained and covered (RedWrap).
##   FIRE burns it back (Explosion: burn()); a shot's path cuts it (shot_line()).
## At most MAX_PATCHES, PATCH_GAP apart.
## Rule 1 (co-op): the host's; every game makes the same patches and ropes
## from the host's word (_net_*), a late joiner asking for all of it.

const SEED_TIME := Vector2(20.0, 180.0) # (the user's: random 20 s - 3 min)
const MAX_PATCHES := 16
const PATCH_GAP := 6.0
const STIMULUS_RANGE := 25.0
const STIMULUS_TIME := 12.0
const STIMULUS_BOOST := 1.5
const LINK_RANGE := 30.0
const LINK_ROPES := 4
## The bushes: twice the open world's (the user's): an area's 1-4 m, a
## seed's (a small one, the user's) 1-2 m.
const BUSH_SIZE := Vector2(1.0, 4.0)
const SEEDLING_SIZE := Vector2(1.0, 2.0)
const TICK := 0.25
const SEND_EVERY := 0.5
const SEEDS_EVERY := 0.5
const BODIES_EVERY := 1.0
const LINKS_EVERY := 2.0
const TOUCH := 0.6
## Rope pieces remade a frame, across every patch (RedCreepPatch.rebuild).
const MESH_BUDGET := 6
## Far patches look for life to reach this many ticks apart.
const FAR_REACH_TICKS := 4

## Where it starts: one bush in each (a floor found in it, at random).
@export var areas: Array[AABB] = []
## Kept out of (the Flesh Tree's trunk).
@export var keep_out: Array[AABB] = []

var _patches := {} # id -> RedCreepPatch
var _next_id := 1
var _stimuli: Array = [] # [position, until msec]
var _carriers := {} # Node3D -> drop msec
var _wraps := {} # wrap id -> RedWrap
var _next_wrap := 1
## Host: [a id, b id] linked pairs; the runners out: [from id, rope, to id].
var _links: Array = []
var _runners: Array = []
var _phases := {} # patch id -> pulse phase
var _tick_left := TICK
var _send_left := SEND_EVERY
var _seeds_left := SEEDS_EVERY
var _bodies_left := BODIES_EVERY
var _links_left := LINKS_EVERY
var _life: Array[Node3D] = []
var _mesh_queue: Array = [] # [patch, rope]
var _far_tick := 0


func _ready() -> void:
	add_to_group(&"red_creep")
	if _host():
		get_tree().create_timer(1.5).timeout.connect(_plant_areas)
	else:
		_net_ask.rpc_id(1)


func _host() -> bool:
	return not Network.is_online() or multiplayer.is_server()


# ---- Where it starts --------------------------------------------------------------------------

func _plant_areas() -> void:
	var space := get_world_3d().direct_space_state
	for area in areas:
		for attempt in 30:
			var x := randf_range(area.position.x + 2.0, area.end.x - 2.0)
			var z := randf_range(area.position.z + 2.0, area.end.z - 2.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, area.end.y - 0.5, z), Vector3(x, area.position.y - 1.0, z), 1))
			if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
				continue
			var at: Vector3 = hit.position
			if keep_out.any(func(box: AABB) -> bool: return box.has_point(at + Vector3.UP)):
				continue
			if start_patch(at, hit.normal, randf_range(BUSH_SIZE.x, BUSH_SIZE.y)) >= 0:
				break


## Host: a new patch at `at` (on a surface facing `normal`). Its id, or -1:
## too many, or too near another.
func start_patch(at: Vector3, normal: Vector3, size: float) -> int:
	if _patches.size() >= MAX_PATCHES:
		return -1
	for patch: RedCreepPatch in _patches.values():
		if patch.global_position.distance_to(at) < PATCH_GAP:
			return -1
	var id := _next_id
	_next_id += 1
	_phases[id] = randf() * TAU
	_make_patch(id, at, normal, size, _phases[id])
	if Network.is_online():
		_net_patch.rpc(id, at, normal, size, _phases[id])
	return id


func _make_patch(id: int, at: Vector3, normal: Vector3, size: float, phase: float) -> RedCreepPatch:
	var patch := RedCreepPatch.new()
	patch.name = "Patch_%d" % id
	add_child(patch)
	patch.global_position = at
	patch.setup(id, self, normal, size, _host(), phase)
	_patches[id] = patch
	return patch


# ---- The host's growing -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _host():
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK
		_gather_life()
		_forget_stimuli()
		_far_tick = (_far_tick + 1) % FAR_REACH_TICKS
		for patch: RedCreepPatch in _patches.values():
			patch.near = _anyone_near(patch.global_position, RedCreepPatch.NEAR) or patch.drawn()
			if patch.near or _far_tick == 0:
				patch.reach_for(_life)
		_runners_on()
	_seeds_left -= delta
	if _seeds_left <= 0.0:
		_seeds_left = SEEDS_EVERY
		_seeds()
	_bodies_left -= delta
	if _bodies_left <= 0.0:
		_bodies_left = BODIES_EVERY
		_bodies()
	_links_left -= delta
	if _links_left <= 0.0:
		_links_left = LINKS_EVERY
		_send_runners()
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left = SEND_EVERY
		_send_growth()


## Every game: a few rope pieces remade a frame (never all at once: no hitch).
func _process(_delta: float) -> void:
	for k in mini(MESH_BUDGET, _mesh_queue.size()):
		var job: Array = _mesh_queue.pop_front()
		var patch := job[0] as RedCreepPatch
		if is_instance_valid(patch):
			patch.rebuild(job[1])


## A patch's rope wants its pieces remade (once in the queue at a time).
func queue_mesh(patch: RedCreepPatch, rope: int) -> void:
	for job: Array in _mesh_queue:
		if job[0] == patch and job[1] == rope:
			return
	_mesh_queue.append([patch, rope])


## Everything alive now (the last tick's list).
func life() -> Array[Node3D]:
	return _life


func _anyone_near(at: Vector3, reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player and player.global_position.distance_to(at) < reach:
			return true
	return false


## Everything alive it could reach: the players and the creatures.
func _gather_life() -> void:
	_life.clear()
	for group: String in ["player", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body and Factions.is_alive_target(body):
				_life.append(body)


# ---- Noise and blood --------------------------------------------------------------------------

func _stimulus(at: Vector3) -> void:
	_stimuli.append([at, Time.get_ticks_msec() + int(STIMULUS_TIME * 1000.0)])
	if _stimuli.size() > 24:
		_stimuli.pop_front()


func _forget_stimuli() -> void:
	var now := Time.get_ticks_msec()
	_stimuli = _stimuli.filter(func(s: Array) -> bool: return int(s[1]) > now)


## The nearest noise or blood within STIMULUS_RANGE of `at` (INF: none).
func stimulus_near(at: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := STIMULUS_RANGE
	for s: Array in _stimuli:
		var d := (s[0] as Vector3).distance_to(at)
		if d < best_d:
			best_d = d
			best = s[0]
	return best


# ---- Cut and burned (WeaponController, Explosion: the host's) --------------------------------

## A shot from `from` to `to` (`hit`: it hit something -- blood): the noise
## draws it; every rope on its path is cut; a cocoon on it is hit.
func shot_line(from: Vector3, to: Vector3, hit: bool) -> void:
	if not _host():
		return
	_stimulus(from)
	if hit:
		_stimulus(to)
	for patch: RedCreepPatch in _patches.values():
		var cuts := patch.cut_line(from, to)
		if not cuts.is_empty() and Network.is_online():
			_net_cuts.rpc(patch.id, cuts)
	for wrap: RedWrap in _wraps.values():
		if wrap.crossed_by(from, to) and wrap.hit():
			end_wrap(wrap, false)


func burn(at: Vector3, radius: float) -> void:
	if not _host():
		return
	_stimulus(at)
	for wrap: RedWrap in _wraps.values():
		if wrap.global_position.distance_to(at) < radius + 1.0:
			end_wrap(wrap, false)
	for id: int in _patches.keys():
		var patch: RedCreepPatch = _patches[id]
		var result: Variant = patch.burn_at(at, radius)
		if result == null:
			_remove_patch(id)
		elif not (result as Array).is_empty() and Network.is_online():
			_net_cuts.rpc(id, result)


func _remove_patch(id: int) -> void:
	var patch := _patches.get(id) as RedCreepPatch
	if patch == null:
		return
	for wrap: RedWrap in _wraps.values():
		if wrap.patch == patch:
			end_wrap(wrap, false)
	_patches.erase(id)
	_links = _links.filter(func(l: Array) -> bool: return l[0] != id and l[1] != id)
	_runners = _runners.filter(func(r: Array) -> bool: return r[0] != id and r[2] != id)
	_rephase()
	patch.wither_all()
	if Network.is_online():
		_net_gone.rpc(id)


# ---- Seeds ------------------------------------------------------------------------------------

## Anything alive touching a bush or a rope picks seeds up; carried ones fall
## when it's their time, and grow.
func _seeds() -> void:
	var now := Time.get_ticks_msec()
	for target in _life:
		# (The list's from the last tick: something may have been freed since.)
		if not is_instance_valid(target) or _carriers.has(target):
			continue
		var at := target.global_position + Vector3.UP * 0.3
		for patch: RedCreepPatch in _patches.values():
			if patch.global_position.distance_to(at) > RedCreepPatch.RADIUS + RedCreepPatch.CLIMB_MAX:
				continue
			if patch.touches(at, TOUCH):
				_carriers[target] = now + int(randf_range(SEED_TIME.x, SEED_TIME.y) * 1000.0)
				_barbs_on(target)
				break
	for carrier: Variant in _carriers.keys():
		if not is_instance_valid(carrier):
			_carriers.erase(carrier)
			continue
		if int(_carriers[carrier]) > now:
			continue
		_carriers.erase(carrier)
		var body := carrier as Node3D
		var barbs := body.get_node_or_null(^"RedSeeds")
		if barbs:
			barbs.queue_free()
		_grow_from(body.global_position, SEEDLING_SIZE)


## A new bush on the ground under `at` (if there's room for one).
func _grow_from(at: Vector3, size: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 4.0, 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return
	var spot: Vector3 = hit.position
	if keep_out.any(func(box: AABB) -> bool: return box.has_point(spot + Vector3.UP)):
		return
	start_patch(spot, hit.normal, randf_range(size.x, size.y))


## Its seeds stuck on whatever's carrying them: a few red barbs (the host's
## sight of it; cosmetic).
func _barbs_on(target: Node3D) -> void:
	if target.get_node_or_null(^"RedSeeds"):
		return
	var barbs := Node3D.new()
	barbs.name = "RedSeeds"
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.45, 0.02, 0.03)
	look.roughness = 0.3
	for i in 5:
		var barb := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.015
		cone.height = 0.06
		cone.radial_segments = 4
		cone.rings = 1
		barb.mesh = cone
		barb.material_override = look
		barb.position = Vector3(randf_range(-0.2, 0.2), randf_range(0.2, 1.1), randf_range(-0.2, 0.2))
		barb.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		barbs.add_child(barb)
	target.add_child(barbs)


# ---- Nurseries --------------------------------------------------------------------------------

## A body its ropes reach: grown over into a new bush.
func _bodies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or body.has_meta(&"red_nursery"):
			continue
		var health := body.get_node_or_null("Health") as Health
		if health == null or not health.is_dead:
			continue
		var at := body.global_position
		for patch: RedCreepPatch in _patches.values():
			if patch.global_position.distance_to(at) > RedCreepPatch.RADIUS + 3.0:
				continue
			var reached := false
			for tip in patch.tips():
				if tip.distance_to(at) < 1.2:
					reached = true
					break
			if reached:
				body.set_meta(&"red_nursery", true)
				_grow_from(at, SEEDLING_SIZE)
				break


# ---- Links ------------------------------------------------------------------------------------

## Patches within LINK_RANGE of each other, not yet one network: the bigger
## one sends a runner across.
func _send_runners() -> void:
	var ids := _patches.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: int = ids[i]
			var b: int = ids[j]
			var pa: RedCreepPatch = _patches[a]
			var pb: RedCreepPatch = _patches[b]
			if pa.global_position.distance_to(pb.global_position) > LINK_RANGE or _network_of(a) == _network_of(b):
				continue
			if _runners.any(func(r: Array) -> bool: return (r[0] == a and r[2] == b) or (r[0] == b and r[2] == a)):
				continue
			var from := pa if pa._living_ropes() >= pb._living_ropes() else pb
			if from._living_ropes() < LINK_ROPES:
				continue
			var to := pb if from == pa else pa
			_runners.append([from.id, from.send_runner(to), to.id])


## A runner arrived: the two are one network now.
func _runners_on() -> void:
	for runner: Array in _runners.duplicate():
		var from := _patches.get(runner[0]) as RedCreepPatch
		var to := _patches.get(runner[2]) as RedCreepPatch
		if from == null or to == null:
			_runners.erase(runner)
			continue
		if from.runner_arrived(runner[1], to):
			_runners.erase(runner)
			_links.append([runner[0], runner[2], runner[1]])
			_rephase()


## A runner cut: unlinked (or never got there).
func runner_cut(patch: RedCreepPatch, rope: int) -> void:
	_runners = _runners.filter(func(r: Array) -> bool: return not (r[0] == patch.id and r[1] == rope))
	var before := _links.size()
	_links = _links.filter(func(l: Array) -> bool: return not (l[0] == patch.id and l[2] == rope))
	if _links.size() != before:
		_rephase()


func _network_of(id: int) -> int:
	# The lowest id it's joined to (a small flood over the links).
	var seen := {id: true}
	var queue: Array[int] = [id]
	var lowest := id
	while not queue.is_empty():
		var at: int = queue.pop_back()
		lowest = mini(lowest, at)
		for link: Array in _links:
			for k in 2:
				var other: int = link[1 - k]
				if link[k] == at and not seen.has(other):
					seen[other] = true
					queue.append(other)
	return lowest


## Every patch pulses with the rest of its network (its lowest id's phase).
func _rephase() -> void:
	var phases := {}
	for id: int in _patches.keys():
		var root := _network_of(id)
		if not _phases.has(root):
			_phases[root] = randf() * TAU
		phases[id] = _phases[root]
		(_patches[id] as RedCreepPatch).set_pulse(phases[id])
	if Network.is_online():
		_net_phases.rpc(phases)


# ---- Wraps ------------------------------------------------------------------------------------

func is_wrapped(target: Node3D) -> bool:
	for wrap: RedWrap in _wraps.values():
		if wrap.target == target:
			return true
	return false


## Host: a tendril's touched `target`.
func start_wrap(target: Node3D, patch: RedCreepPatch, rope: int) -> void:
	var id := _next_wrap
	_next_wrap += 1
	var size := _size_of(target)
	var now := Time.get_ticks_msec()
	var wrap := _make_wrap(id, target.global_position, size.x, size.y, now)
	wrap.hold(target, patch, rope)
	if Network.is_online():
		_net_wrap.rpc(id, target.global_position, size.x, size.y)


func _make_wrap(id: int, pin: Vector3, tall: float, wide: float, start_msec: int) -> RedWrap:
	var wrap := RedWrap.new()
	wrap.name = "Wrap_%d" % id
	add_child(wrap)
	wrap.setup(self, id, pin, tall, wide, start_msec, _host())
	_wraps[id] = wrap
	return wrap


## Host: a wrap's over -- `died`: what it held is dead (a nursery there).
func end_wrap(wrap: RedWrap, died: bool) -> void:
	if not _wraps.has(wrap.wrap_id):
		return
	_wraps.erase(wrap.wrap_id)
	var pin := wrap.global_position
	var patch := wrap.patch
	var rope := wrap.rope
	wrap.release()
	wrap.queue_free()
	if is_instance_valid(patch):
		patch.wrap_ended(rope)
	if died:
		_grow_from(pin, SEEDLING_SIZE)
	if Network.is_online():
		_net_unwrap.rpc(wrap.wrap_id)


## A wrap's tendril was cut: what it held goes free.
func wrap_cut(target: Variant) -> void:
	for wrap: RedWrap in _wraps.values():
		if wrap.target == target:
			end_wrap(wrap, false)
			return


## How tall and wide something is (its collision capsule or box; a person's
## otherwise).
static func _size_of(target: Node3D) -> Vector2:
	for node in target.get_children():
		var shape := node as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		if shape.shape is CapsuleShape3D:
			var capsule := shape.shape as CapsuleShape3D
			return Vector2(capsule.height, capsule.radius + 0.12)
		if shape.shape is BoxShape3D:
			var box := (shape.shape as BoxShape3D).size
			return Vector2(box.y, maxf(box.x, box.z) * 0.5 + 0.1)
		if shape.shape is SphereShape3D:
			var r := (shape.shape as SphereShape3D).radius
			return Vector2(r * 2.0, r + 0.08)
	return Vector2(1.8, 0.45)


# ---- Co-op ------------------------------------------------------------------------------------

func _send_growth() -> void:
	if not Network.is_online():
		for patch: RedCreepPatch in _patches.values():
			patch.take_growth() # (keeps its count of what's sent)
		return
	for patch: RedCreepPatch in _patches.values():
		var growth := patch.take_growth()
		if not growth.is_empty():
			_net_growth.rpc(patch.id, growth)


@rpc("authority", "call_remote", "reliable")
func _net_patch(id: int, at: Vector3, normal: Vector3, size: float, phase: float) -> void:
	if not _patches.has(id):
		_make_patch(id, at, normal, size, phase)


@rpc("authority", "call_remote", "reliable")
func _net_growth(id: int, growth: Array) -> void:
	var patch := _patches.get(id) as RedCreepPatch
	if patch:
		patch.apply_growth(growth)


@rpc("authority", "call_remote", "reliable")
func _net_cuts(id: int, cuts: Array) -> void:
	var patch := _patches.get(id) as RedCreepPatch
	if patch:
		for c: Array in cuts:
			patch.cut(c[0], c[1])


@rpc("authority", "call_remote", "reliable")
func _net_gone(id: int) -> void:
	var patch := _patches.get(id) as RedCreepPatch
	if patch:
		_patches.erase(id)
		patch.wither_all()


@rpc("authority", "call_remote", "reliable")
func _net_phases(phases: Dictionary) -> void:
	for id: int in phases:
		var patch := _patches.get(id) as RedCreepPatch
		if patch:
			patch.set_pulse(phases[id])


@rpc("authority", "call_remote", "reliable")
func _net_wrap(id: int, pin: Vector3, tall: float, wide: float) -> void:
	if not _wraps.has(id):
		_make_wrap(id, pin, tall, wide, Time.get_ticks_msec())


@rpc("authority", "call_remote", "reliable")
func _net_unwrap(id: int) -> void:
	var wrap := _wraps.get(id) as RedWrap
	if wrap:
		_wraps.erase(id)
		wrap.queue_free()


## A late joiner: everything as it is.
@rpc("any_peer", "call_remote", "reliable")
func _net_ask() -> void:
	if not _host():
		return
	var peer := multiplayer.get_remote_sender_id()
	for id: int in _patches.keys():
		var patch: RedCreepPatch = _patches[id]
		_net_patch.rpc_id(peer, id, patch.global_position, patch.surface_normal, patch.bush_size, float(_phases.get(_network_of(id), 0.0)))
		_net_growth.rpc_id(peer, id, patch.all_growth())
	for id: int in _wraps.keys():
		var wrap: RedWrap = _wraps[id]
		_net_wrap.rpc_id(peer, id, wrap.global_position, wrap.height, wrap.radius)
