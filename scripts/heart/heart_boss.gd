class_name HeartBoss
extends Node3D

## The heart boss (docs/HEART_BOSS.md), first pass: the real heart hanging in
## its cathedral (the Stack puts it there: StackBuilder.build_scene), chained
## up from every side, beating, dripping blood. While anyone's in the
## cathedral it plays its song's map (beat_map): on every snare its holes
## glow open and a beat later the volley blasts (BloodBeam); on every kick it
## beats and the whole cathedral shakes (HeartQuake). With no map yet:
## test_bpm, kick and snare taking turns.
## Values here are first picks (the user: "put the heart in"), all to change.
## Rule 1 (co-op): the host fires the beams (Network.send_blood_beam); its
## beating, chains and drips are looks, every game its own.

const HEART_MODEL := "res://art/heart_boss/realistic-human-heart/source/Heart.fbx"
const CHAIN_MODEL := "res://art/heart_boss/chain/chain.FBX"

## How tall the heart is (m).
@export var size: float = 40.0
## Its map: when its drums land. None: test_bpm, a beam every beat.
@export var beat_map: BeatMap
@export var test_bpm: float = 80.0
## Each snare's volley: one beam mainly at a player inside (the user's), and
## this many more off random spots on it, every way.
@export var aim_at_players: bool = true
@export var random_beams: int = 5
## And one at where they're heading (the user's), led the way the flying
## roaches lead their spit (FlyingRoach._spit_at) with the same values: their
## sideways speed fully (x PREDICTION), toward/away only PREDICTION_TOWARD of
## it, a random GUESS share of that lead each time plus up to GUESS_SIDEWAYS m
## across their way, AIM_PAST beyond them, SCATTER of a miss -- carried on
## for the time till it blasts (the glow).
@export var predicting_beam: bool = true
const PREDICTION := 0.8
const PREDICTION_TOWARD := 0.3
const GUESS := Vector2(0.4, 1.3)
const GUESS_SIDEWAYS := 1.2
const AIM_PAST := 0.4
const SCATTER := 0.25
## Chains: this many to the walls round it, this many up to the ceiling.
@export var wall_chains: int = 6
@export var ceiling_chains: int = 6
## How long one chain link is (m), and how far a chain sags (share of its length).
@export var link_length: float = 1.6
@export var sag: float = 0.06
## The cathedral (in the Stack's space), set by the Stack's bake.
@export var room := AABB()

## The beat (the user's): one big thump a kick -- swelling THUMP in a snap,
## easing back fast (THUMP_FALL a second) so quick kicks each land their own;
## its glow pulsing GLOW bright with it.
const THUMP := 0.2
const THUMP_RISE := 60.0
const THUMP_FALL := 9.0
const GLOW := 12.0
const DRIP_EVERY := 0.6
## A kick (the user's): the cathedral's walls, columns and mezzanines judder
## (their meshes only -- the floor you stand on doesn't move) this far, for
## about this long; its lamps flicker and dim, then come back.
const JUDDER := 0.45
const JUDDER_TIME := 0.45
const JUDDER_RATE := 38.0
const FLICKER_TIME := 0.35
const ROOM_MESHES := ["Cathedral_plain", "Tower_5_concrete"]
## Its structures shift about (the user's), so there's no hiding behind the
## same wall: every SHIFT_EVERY kicks each one (a mezzanine with its ramps, a
## column, the pyramid, the slab, the stairs) heads for a new spot within
## SHIFT_RANGE m of where it was built, at 1 m a beat; never into the open
## middle (ARENA) or out of the room. The host picks; everyone moves them.
const SHIFT_EVERY := 10
const SHIFT_RANGE := 25.0
const ARENA := 80.0
## Kept this far clear of the heart (its bounds swollen by a full thump), the
## user's: never clipping into it -- where it'd end up, and the way there.
const HEART_CLEARANCE := 6.0
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
var _room_meshes: Array[Node3D] = []
var _room_rests: Array[Vector3] = []
var _lamps: Array[Light3D] = []
var _lamp_energy: Array[float] = []
var _quake_age := 10.0
var _pieces: Array[AnimatableBody3D] = []
var _piece_home: Array[Vector3] = []
var _piece_to: Array[Vector3] = []
var _piece_extent: Array[AABB] = [] # each piece's own shape, round its origin
var _kicks := 0
var _active := false
var _player: AudioStreamPlayer
## The map it's playing (yours if you've picked one: PlayerMovement.heart_song).
var _map: BeatMap
## The song's snares up to here have had their holes opened.
var _snares_to := -1.0


func _ready() -> void:
	add_to_group(&"heart_boss")
	_build_heart()
	_build_drips()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.15)
	_light.omni_range = size * 4.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_build_chains.call_deferred() # once the cathedral's walls are in the physics
	_find_room.call_deferred()


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
	_shake_room(delta)
	# One thump, and the light pulsing with it.
	var thump := (1.0 - exp(-_beat_age * THUMP_RISE)) * exp(-_beat_age * THUMP_FALL)
	_model.scale = Vector3.ONE * _base_scale * (1.0 + THUMP * thump)
	_light.light_energy = 1.0 + GLOW * thump
	_update_chains(thump)
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
	_map = _chosen_map()
	_snares_to = -1.0
	_player.stream = _map.song if _map else null
	if _player.stream:
		_player.play()


func _stop() -> void:
	_active = false
	_player.stop()


## Your pick (the heart_song in your player's inspector), else its own.
func _chosen_map() -> BeatMap:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and player.is_multiplayer_authority() and player.heart_song and player.heart_song.song:
			return player.heart_song
	return beat_map if beat_map and beat_map.song else null


func _tick(delta: float) -> void:
	_time = _song_time() if _player.playing else _time + delta
	if _map:
		# Its map: every kick, the quake; every snare, the volley blasts ON it
		# (the user's) -- its holes glowing open the beat before.
		var beat := _map.beat()
		if not _map.between(BeatMap.Drum.KICK, _time - delta, _time).is_empty():
			_kick()
		var ahead := _time + beat
		for at in _map.between(BeatMap.Drum.SNARE, _snares_to, ahead):
			_fire(at - _time)
		_snares_to = maxf(_snares_to, ahead)
		if not _player.playing:
			_start() # the song's over: round again
		return
	# No map: test_bpm, kick and snare taking turns.
	var beat := 60.0 / maxf(test_bpm, 1.0)
	if _time >= _next_beat:
		_next_beat += beat
		if _next_beam % 2 == 0:
			_kick()
			_fire(beat) # (the snare's volley: glowing now, blasting on the next beat)
		_next_beam += 1


## A kick: it beats, and (the host's call) the cathedral quakes.
func _kick() -> void:
	_beat_age = 0.0
	if Network.is_online() and not multiplayer.is_server():
		return
	var inside: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		if _room_world().has_point((node as Node3D).global_position + Vector3.UP):
			inside.append(node as Node3D)
	Network.send_heart_kick(HeartQuake.pick_chunks(_room_world(), inside, global_position))
	_kicks += 1
	if _kicks % SHIFT_EVERY == 0 and not _pieces.is_empty():
		Network.send_heart_shift(_pick_shift())


## New spots for its structures: each within SHIFT_RANGE of where it was
## built (level: heights stay), in the room, out of the open middle.
func _pick_shift() -> PackedVector3Array:
	var room := _room_world()
	var heart := AABB(global_position - _radii * (1.0 + THUMP), _radii * 2.0 * (1.0 + THUMP)).grow(HEART_CLEARANCE)
	var spots := PackedVector3Array()
	for i in _pieces.size():
		var home := _piece_home[i]
		var now := _pieces[i].global_position if is_instance_valid(_pieces[i]) else home
		var chosen := now # (none clear: it stays)
		for attempt in 12:
			var flat := Vector2.from_angle(randf() * TAU) * SHIFT_RANGE * sqrt(randf())
			var to := home + Vector3(flat.x, 0.0, flat.y)
			to.x = clampf(to.x, room.position.x + 8.0, room.end.x - 8.0)
			to.z = clampf(to.z, room.position.z + 8.0, room.end.z - 8.0)
			var from_middle := Vector2(to.x - global_position.x, to.z - global_position.z)
			var home_middle := Vector2(home.x - global_position.x, home.z - global_position.z)
			# (Not into the arena -- unless it was built nearer than that.)
			var least := minf(ARENA, home_middle.length())
			if from_middle.length() < least:
				from_middle = from_middle.normalized() * least if from_middle.length_squared() > 0.01 else home_middle
				to = Vector3(global_position.x + from_middle.x, to.y, global_position.z + from_middle.y)
			if _clear_of(heart, i, now, to):
				chosen = to
				break
		spots.append(chosen)
	return spots


## Whether piece i, sliding from `from` to `to`, stays out of `heart` the
## whole way (checked every couple of metres along it).
func _clear_of(heart: AABB, i: int, from: Vector3, to: Vector3) -> bool:
	var extent := _piece_extent[i]
	var steps := maxi(1, ceili(from.distance_to(to) / 2.0))
	for k in steps + 1:
		var at := from.lerp(to, float(k) / steps)
		if AABB(at + extent.position, extent.size).intersects(heart):
			return false
	return true


## Network.send_heart_shift, on every game: where they head now.
func shift(spots: PackedVector3Array) -> void:
	for i in mini(spots.size(), _piece_to.size()):
		_piece_to[i] = spots[i]


## Sliding them on toward their spots, 1 m a beat.
func _physics_process(delta: float) -> void:
	if _pieces.is_empty():
		return
	var beat := _map.beat() if _map else 60.0 / maxf(test_bpm, 1.0)
	var step := delta / maxf(beat, 0.05)
	for i in _pieces.size():
		var piece := _pieces[i]
		if is_instance_valid(piece) and not piece.global_position.is_equal_approx(_piece_to[i]):
			piece.global_position = piece.global_position.move_toward(_piece_to[i], step)


## Network.send_heart_kick, on every game.
func quake(spots: PackedVector3Array, decides: bool) -> void:
	_quake_age = 0.0
	HeartQuake.hit(self, _room_world(), spots, decides)


## The cathedral's own meshes (to judder) and its lamps (to flicker).
func _find_room() -> void:
	var stack := get_parent()
	if stack == null:
		return
	for name: String in ROOM_MESHES:
		var mesh := stack.find_child(name, true, false) as Node3D
		if mesh:
			_room_meshes.append(mesh)
			_room_rests.append(mesh.position)
	var pieces := stack.find_child("CathedralPieces", true, false)
	if pieces:
		for node in pieces.get_children():
			if node is AnimatableBody3D:
				_pieces.append(node)
				_piece_home.append((node as Node3D).global_position)
				_piece_to.append((node as Node3D).global_position)
				var extent := AABB()
				var first := true
				for shape_node in node.get_children():
					var shape := shape_node as CollisionShape3D
					if shape and shape.shape is BoxShape3D:
						var size := (shape.shape as BoxShape3D).size
						var part := shape.transform * AABB(-size * 0.5, size)
						extent = part if first else extent.merge(part)
						first = false
				_piece_extent.append(extent)
	var box := _room_world()
	for light in stack.find_children("*", "Light3D", true, false):
		if not is_ancestor_of(light) and box.has_point((light as Node3D).global_position):
			_lamps.append(light as Light3D)
			_lamp_energy.append((light as Light3D).light_energy)


## The kick's judder and flicker, easing off.
func _shake_room(delta: float) -> void:
	_quake_age += delta
	var left := clampf(1.0 - _quake_age / JUDDER_TIME, 0.0, 1.0)
	for i in _room_meshes.size():
		if not is_instance_valid(_room_meshes[i]):
			continue
		var offset := Vector3.ZERO
		if left > 0.0:
			var t := _quake_age * JUDDER_RATE
			offset = Vector3(sin(t * 1.3 + i), sin(t * 0.9 + 2.0 * i) * 0.5, cos(t * 1.1 + i)) * JUDDER * left * left
		_room_meshes[i].position = _room_rests[i] + offset
	var flicker := _quake_age < FLICKER_TIME
	for i in _lamps.size():
		if is_instance_valid(_lamps[i]):
			_lamps[i].light_energy = _lamp_energy[i] * (randf_range(0.05, 0.5) if flicker else 1.0)


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
			var chosen := inside[randi() % inside.size()] as PlayerMovement
			target = chosen.global_position + Vector3.UP
			if predicting_beam:
				# Where they'll be by the blast (the roaches' lead).
				var lead := _predict(chosen, global_position, warn)
				var lead_way := (lead - global_position).normalized()
				var lead_from := global_position + lead_way * _radii * 0.85
				Network.send_blood_beam(lead_from, (lead - lead_from).normalized(), maxf(warn, 0.05))
	var way := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.5), randf_range(-1.0, 1.0)).normalized()
	if target.is_finite():
		way = (target - global_position).normalized().slerp(way, 0.3).normalized()
	var from := global_position + way * _radii * 0.85
	var aim := (target - from).normalized() if target.is_finite() else way
	Network.send_blood_beam(from, aim, maxf(warn, 0.05))
	# The rest: out of random spots on it, straight out from them, any way.
	for i in random_beams:
		var out := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		Network.send_blood_beam(global_position + out * _radii * 0.85, out, maxf(warn, 0.05))


## Where `target` will be in `time` seconds, as the roaches guess it.
func _predict(target: PlayerMovement, from_point: Vector3, time: float) -> Vector3:
	var aim := Factions.aim_point(target)
	var to_target := Vector3(aim.x - from_point.x, 0.0, aim.z - from_point.z)
	var line := to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD
	var ground := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var toward_away := line * ground.dot(line)
	var sideways := ground - toward_away
	var lead := (sideways + toward_away * PREDICTION_TOWARD) * PREDICTION * randf_range(GUESS.x, GUESS.y)
	var sideways_guess := Vector3.ZERO
	if ground.length_squared() > 1.0:
		sideways_guess = ground.normalized().cross(Vector3.UP) * randf_range(-GUESS_SIDEWAYS, GUESS_SIDEWAYS)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * SCATTER
	return aim + line * AIM_PAST + sideways_guess + lead * time + scatter


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
