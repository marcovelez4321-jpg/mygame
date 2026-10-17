class_name HeartBoss
extends Node3D

## The heart boss (docs/HEART_BOSS.md), first pass: the real heart hanging in
## its cathedral (the Stack puts it there: StackBuilder.build_scene), chained
## up from every side, beating, dripping blood. While anyone's in the
## cathedral it beats to its song's map (beat_map: a hole opens a beat before
## each snare and blasts a BloodBeam on it; the kicks make it beat) -- or,
## with no map yet, to test_bpm, a beam every beat.
## Values here are first picks (the user: "put the heart in"), all to change.
## Rule 1 (co-op): the host fires the beams (Network.send_blood_beam); its
## beating, chains and drips are looks, every game its own.

const HEART_MODEL := "res://art/heart_boss/realistic-human-heart/source/Heart.fbx"
const CHAIN_MODEL := "res://art/heart_boss/chain/chain.FBX"

## How tall the heart is (m).
@export var size: float = 30.0
## Its map: when its drums land. None: test_bpm, a beam every beat.
@export var beat_map: BeatMap
@export var test_bpm: float = 80.0
## Beams at the players inside (else anywhere off its surface).
@export var aim_at_players: bool = true
## Chains: this many to the walls round it, this many up to the ceiling.
@export var wall_chains: int = 4
@export var ceiling_chains: int = 4
## How long one chain link is (m), and how far a chain sags (share of its length).
@export var link_length: float = 1.6
@export var sag: float = 0.06
## The cathedral (in the Stack's space), set by the Stack's bake.
@export var room := AABB()

## The beat: how much it swells on the lub and the dub.
const LUB := 0.07
const DUB := 0.045
const DUB_AFTER := 0.2
const DRIP_EVERY := 0.6
## Its looks only run with someone this close (m).
const NEAR := 700.0

var _model: Node3D
var _radii := Vector3.ONE
var _chains: Array[Dictionary] = [] # {from (local), to (world), multimesh, links}
var _drips: GPUParticles3D
var _light: OmniLight3D
var _time := 0.0 # into the song (or the test beat)
var _beat_age := 10.0
var _next_beat := 0.0
var _next_beam := 0
var _drip_left := 0.0
var _active := false
var _player: AudioStreamPlayer


func _ready() -> void:
	_build_heart()
	_build_drips()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.15)
	_light.omni_range = size * 4.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	if beat_map and beat_map.song:
		_player = AudioStreamPlayer.new()
		_player.stream = beat_map.song
		add_child(_player)
	_build_chains.call_deferred() # once the cathedral's walls are in the physics


func _process(delta: float) -> void:
	var near := _nearest_distance()
	_set_looks(near < NEAR)
	if near >= NEAR:
		return
	var inside := _anyone_inside()
	if inside and not _active:
		_start()
	elif not inside and _active:
		_stop()
	_beat_age += delta
	if _active:
		_tick(delta)
	# Lub-dub, and the light pulsing with it.
	var lub := exp(-_beat_age * 12.0)
	var dub := exp(-maxf(_beat_age - DUB_AFTER, 0.0) * 12.0) if _beat_age > DUB_AFTER else 0.0
	_model.scale = Vector3.ONE * _base_scale * (1.0 + LUB * lub + DUB * dub)
	_light.light_energy = 1.0 + 6.0 * (lub + dub * 0.6)
	_update_chains(lub + dub * 0.6)
	# Dripping on the floor below.
	_drip_left -= delta
	if _drip_left <= 0.0:
		_drip_left = DRIP_EVERY * randf_range(0.5, 1.5)
		var from := global_position + Vector3(randf_range(-_radii.x, _radii.x) * 0.6, -_radii.y * 0.8, randf_range(-_radii.z, _radii.z) * 0.6)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0, 1))
		if not hit.is_empty():
			BloodFX.spawn_splatter(get_tree().current_scene, hit.position, hit.normal, randf_range(0.8, 2.0))


# ---- The beat ----------------------------------------------------------------------

func _start() -> void:
	_active = true
	_time = 0.0
	_next_beat = 0.0
	_next_beam = 0
	if _player:
		_player.play()


func _stop() -> void:
	_active = false
	if _player:
		_player.stop()


func _tick(delta: float) -> void:
	_time = _song_time() if _player and _player.playing else _time + delta
	if beat_map and beat_map.song:
		# Its map: the kicks beat it; a hole opens a beat before each snare.
		var beat := beat_map.beat()
		if not beat_map.between(BeatMap.Drum.KICK, _time - delta, _time).is_empty():
			_beat_age = 0.0
		for at in beat_map.between(BeatMap.Drum.SNARE, _time - delta + beat, _time + beat):
			_fire(at - _time)
		if not _player.playing:
			_start() # the song's over: round again
		return
	# No map: test_bpm, a beat and a beam every beat.
	var beat := 60.0 / maxf(test_bpm, 1.0)
	if _time >= _next_beat:
		_next_beat += beat
		_beat_age = 0.0
		_fire(beat)


func _song_time() -> float:
	return _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


## A hole opening on it, `warn` seconds before it blasts (the host's call).
func _fire(warn: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	var target := Vector3.INF
	if aim_at_players:
		var inside: Array[Node3D] = []
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as PlayerMovement
			if player and not player.is_dead() and _room_world().has_point(player.global_position + Vector3.UP):
				inside.append(player)
		if not inside.is_empty():
			target = inside[randi() % inside.size()].global_position + Vector3.UP
	var way := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.5), randf_range(-1.0, 1.0)).normalized()
	if target.is_finite():
		way = (target - global_position).normalized().slerp(way, 0.3).normalized()
	var from := global_position + way * _radii * 0.85
	var aim := (target - from).normalized() if target.is_finite() else way
	Network.send_blood_beam(from, aim, maxf(warn, 0.05))


# ---- Who's here -----------------------------------------------------------------

func _room_world() -> AABB:
	var stack := get_parent() as Node3D
	return stack.global_transform * room if stack else room


func _anyone_inside() -> bool:
	var box := _room_world()
	for node in get_tree().get_nodes_in_group("player"):
		if box.has_point((node as Node3D).global_position + Vector3.UP):
			return true
	return false


func _nearest_distance() -> float:
	var best := INF
	for node in get_tree().get_nodes_in_group("player"):
		best = minf(best, (node as Node3D).global_position.distance_to(global_position))
	var camera := get_viewport().get_camera_3d()
	if camera:
		best = minf(best, camera.global_position.distance_to(global_position))
	return best


# ---- Looks -------------------------------------------------------------------------

var _base_scale := 1.0
var _looks_on := true


func _set_looks(on: bool) -> void:
	if on == _looks_on:
		return
	_looks_on = on
	_drips.emitting = on
	for chain in _chains:
		(chain.node as Node3D).visible = on


## The model, sized to `size` tall, centred on this node.
func _build_heart() -> void:
	var packed := load(HEART_MODEL) as PackedScene
	var model: Node3D = packed.instantiate() as Node3D if packed else Node3D.new()
	var box := _bounds(model)
	_base_scale = size / maxf(box.size.y, 0.001)
	# The holder it beats round: the model inside it, its middle on the holder's.
	_model = Node3D.new()
	add_child(_model)
	_model.add_child(model)
	model.position -= box.get_center()
	_model.scale = Vector3.ONE * _base_scale
	_radii = box.size * 0.5 * _base_scale
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var to_root := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk is Node3D:
			to_root = (walk as Node3D).transform * to_root
			if walk == root:
				break
			walk = walk.get_parent()
		var part := to_root * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Blood dripping off its underside the whole time.
func _build_drips() -> void:
	_drips = GPUParticles3D.new()
	_drips.amount = 80
	_drips.lifetime = 4.0
	_drips.local_coords = false
	_drips.draw_pass_1 = BloodFX.droplet_mesh()
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.visibility_aabb = AABB(Vector3(-size, -400.0, -size), Vector3(size * 2.0, 400.0 + size, size * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.25
	process.direction = Vector3.DOWN
	process.spread = 10.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, -14.0, 0.0)
	process.scale_min = 2.0
	process.scale_max = 4.0
	process.color = BloodFX.BLOOD_COLOR
	_drips.process_material = process
	add_child(_drips)
	_drips.position = Vector3.DOWN * _radii.y * 0.7
	_drips.emitting = true


## The chains: out from points on the heart to the walls round it and up to
## the ceiling (wherever a ray from it meets them), links laid along each
## with a sag, every other link turned a quarter.
func _build_chains() -> void:
	var packed := load(CHAIN_MODEL) as PackedScene
	if packed == null:
		return
	var source := packed.instantiate() as Node3D
	var mesh_node := source.find_children("*", "MeshInstance3D", true, false)
	if mesh_node.is_empty():
		source.free()
		return
	var mesh := (mesh_node[0] as MeshInstance3D).mesh
	var material := (mesh_node[0] as MeshInstance3D).get_active_material(0)
	source.free()
	var box := mesh.get_aabb()
	# Its long side runs along the chain; scaled so one is link_length long.
	var long_axis := box.get_longest_axis_index()
	var link_scale := link_length / maxf(box.size[long_axis], 0.001)
	var ways: Array[Vector3] = []
	for i in wall_chains:
		var angle := TAU * (i + 0.5) / maxf(wall_chains, 1)
		ways.append(Vector3(cos(angle), randf_range(-0.05, 0.15), sin(angle)).normalized())
	for i in ceiling_chains:
		var angle := TAU * i / maxf(ceiling_chains, 1)
		ways.append(Vector3(cos(angle) * 0.6, 1.0, sin(angle) * 0.6).normalized())
	var space := get_world_3d().direct_space_state
	for way in ways:
		var from := way * _radii * 0.8
		var start := global_position + from
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + way * 600.0, 1))
		if hit.is_empty():
			continue
		var to: Vector3 = hit.position
		var count := int(start.distance_to(to) / (link_length * 0.8))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = count
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		if material:
			node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.top_level = true
		node.global_transform = Transform3D.IDENTITY
		_chains.append({node = node, from = from, to = to, multimesh = multimesh, links = count,
				axis = long_axis, scale = link_scale, jolt = randf_range(0.6, 1.4)})
	_update_chains(0.0)


## Every link along its chain's sag; a beat jolts them (`pulse` 0..1).
func _update_chains(pulse: float) -> void:
	for chain in _chains:
		var start: Vector3 = global_position + (chain.from as Vector3) * _model.scale.x / _base_scale
		var finish: Vector3 = chain.to
		var links: int = chain.links
		var length := start.distance_to(finish)
		var droop := length * sag * (1.0 - 0.35 * pulse * float(chain.jolt))
		var multimesh: MultiMesh = chain.multimesh
		var previous := start
		for i in links:
			var t := (i + 0.5) / links
			var at := start.lerp(finish, t) + Vector3.DOWN * droop * 4.0 * t * (1.0 - t)
			var next_t := (i + 1.5) / links
			var ahead := start.lerp(finish, next_t) + Vector3.DOWN * droop * 4.0 * next_t * (1.0 - next_t)
			var along := (ahead - previous).normalized()
			previous = at
			var basis := _link_basis(along, int(chain.axis), i % 2 == 1) * Basis.from_scale(Vector3.ONE * float(chain.scale))
			multimesh.set_instance_transform(i, Transform3D(basis, at))


## A link's turn: its long axis (`axis` of the model) along the chain, every
## other one rolled a quarter turn round it.
static func _link_basis(along: Vector3, axis: int, roll: bool) -> Basis:
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := up.cross(along).normalized()
	up = along.cross(side).normalized()
	var basis := Basis(side, up, along)
	match axis:
		0:
			basis = Basis(along, up, along.cross(up))
		1:
			basis = Basis(side, along, side.cross(along))
	if roll:
		basis = Basis(along, PI * 0.5) * basis
	return basis
