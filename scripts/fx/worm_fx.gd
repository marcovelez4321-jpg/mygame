class_name WormFX
extends Node3D

## The extra show for a burrowing worm (BurrowWorm, Deepmaw), kept cheap:
##   - churned dirt (shaders/worm_dirt.gdshader) -- a lumpy mound heaving
##     along the floor over it while it tunnels near the surface (or ploughs
##     through it), with a bow wave of dirt at the front, and a furrow of
##     loose ridges left behind it that settles flat and goes after
##     FURROW_LIFE seconds (Tremors/Dune). The mound and the whole furrow are
##     one MultiMesh: one draw call. Clods tumbling off the mound's sides and
##     a low dust haze stream off it as it goes (two small emitters);
##   - slow, lingering dust clouds and a fling of rubble when it breaks the
##     surface (two dust emitters used in turn, one rubble emitter);
##   - a low rumble loop from its head while it's underground, louder the
##     closer it is (3D falloff does the "closer" part).
## On the open world's terrain (the user's: everything follows the land),
## the dirt's every vertex sits on the real ground under it -- the shader
## reads Terrain3D's own height maps (link_terrain() copies them over) -- so
## the mound, its bow wave and the furrow hug hills, dips and slopes; the
## landing ring and the dust bursts sit on the ground and tilt with it
## (ground(): Terrain3D's height and normal there, no raycast). On a level's
## floor (no terrain) they stay flat, as before.
## Optimisation: every mesh, material and particle setup is made once and
## shared by every worm (static); a worm's emitters are only created the
## first time it breaks the surface; nothing casts shadows; no raycasts.
## Visual only -- every peer runs its own from the worm's position.

const DUST_COLOR := Color(0.36, 0.3, 0.24, 0.55)
const RUBBLE_COLOR := Color(0.17, 0.12, 0.08)
const DIRT_SHADER := preload("res://shaders/worm_dirt.gdshader")
## Loose, dark, freshly turned soil (one of the level dirt textures).
const DIRT_TEXTURE := preload("res://trenchbroom/textures/Dirt_03-256x256.png")
## The furrow: how many patches it can have down at once, how long each
## lasts (it settles flat over the second half), and how far apart they're
## laid as a share of the worm's thickness.
const FURROW_COUNT := 40
const FURROW_LIFE := 7.0
const FURROW_SPACING := 1.2
const RUMBLE_PATH := "res://audio/sfx/worm_rumble.wav"
const SPIT_COLOR := Color(0.72, 0.68, 0.42)
const BLOOD_COLOR := Color(0.55, 0.03, 0.03)
const DIRT_COLOR := Color(0.13, 0.09, 0.06)
## Tremors (ceiling dust, props jittering) at most this often, and how far
## up a ceiling can be / how far out props feel it.
const TREMOR_INTERVAL := 0.4
const CEILING_REACH := 14.0
const PROP_REACH := 3.5
## Jaws: a drip of drool this often while it's out; dirt shed off its body
## this often while it's in the air.
const DROOL_INTERVAL := 0.2
const SHED_INTERVAL := 0.12

## How big this worm's effects are (1 = the boss).
var size := 1.0
## Set by the worm; null = the placeholder rumble (RUMBLE_PATH).
var rumble_stream: AudioStream
var rumble_volume_db := 0.0
var rumble_range := 30.0

static var _dirt_mesh: PlaneMesh
static var _dirt_material: ShaderMaterial
static var _clod_mesh: BoxMesh
static var _clod_process: ParticleProcessMaterial
static var _haze_process: ParticleProcessMaterial
static var _dust_process: ParticleProcessMaterial
static var _dust_mesh: QuadMesh
static var _rubble_process: ParticleProcessMaterial
static var _rubble_mesh: BoxMesh
static var _fall_process: ParticleProcessMaterial
static var _ring_mesh: TorusMesh
static var _ring_material: StandardMaterial3D

## Terrain3D's private uniforms the dirt shader reads the ground from.
const TERRAIN_UNIFORMS: Array[StringName] = [&"_vertex_density", &"_region_size", &"_region_texel_size",
		&"_region_map_size", &"_region_map", &"_height_maps"]
## The terrain whose height maps the dirt has (its instance id), and the
## one found in this scene (weak: scenes change).
static var _linked_terrain := 0
static var _terrain: WeakRef
static var _terrain_looked_msec := -100000
## Instance 0 = the mound, 1..FURROW_COUNT = the furrow's patches.
var _dirt: MultiMeshInstance3D
## Each furrow patch: when it was laid (seconds, -1 = gone), where (its full
## size), and how high its ridges started.
var _furrow_born := PackedFloat32Array()
var _furrow_place: Array[Transform3D] = []
var _furrow_height := PackedFloat32Array()
var _furrow_next := 0
var _last_stamp := Vector3.ZERO
var _stamped := false
var _clods: GPUParticles3D
var _haze: GPUParticles3D
## Which way the mound faces (its travel; kept while it's standing still).
var _facing := Basis.IDENTITY
var _dust: Array[GPUParticles3D] = []
var _next_dust := 0
var _rubble: GPUParticles3D
var _rumble: AudioStreamPlayer3D
var _ring: MeshInstance3D
var _ring_tween: Tween
var _fall: GPUParticles3D
var _tremor_left := 0.0
## Under the open world's terrain this frame (follow()).
var _on_terrain := false
var _drool_left := 0.0
var _shed_left := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_make_shared()
	_dirt = MultiMeshInstance3D.new()
	_dirt.material_override = _dirt_material
	_dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _dirt_mesh
	multimesh.instance_count = 1 + FURROW_COUNT
	_dirt.multimesh = multimesh
	# The patches are all over the place: never cull it by a stale box.
	_dirt.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	add_child(_dirt)
	for i in multimesh.instance_count:
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_furrow_born.resize(FURROW_COUNT)
	_furrow_born.fill(-1.0)
	_furrow_height.resize(FURROW_COUNT)
	_furrow_place.resize(FURROW_COUNT)
	_clods = _make_stream(_clod_process, _clod_mesh, 18, 0.7)
	_haze = _make_stream(_haze_process, _dust_mesh, 6, 1.6)
	_rumble = AudioStreamPlayer3D.new()
	var stream := rumble_stream
	if stream == null and ResourceLoader.exists(RUMBLE_PATH):
		stream = load(RUMBLE_PATH) as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_rumble.stream = stream
	_rumble.volume_db = rumble_volume_db
	_rumble.max_distance = rumble_range * size
	_rumble.unit_size = 6.0 * size
	_rumble.bus = "Enemies" if AudioServer.get_bus_index("Enemies") != -1 else "Master"
	add_child(_rumble)


## A still one (ShaderWarmup): a patch of its dirt at `at`, its clods, haze,
## landing ring, dust and rubble going -- no rumble.
static func warm_up(world: Node, at: Vector3) -> WormFX:
	var fx := WormFX.new()
	world.add_child(fx)
	fx.shockwave(at, 3.0)
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	fx._dirt.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 2.0), at))
	fx._clods.global_position = at
	fx._haze.global_position = at
	fx._clods.emitting = true
	fx._haze.emitting = true
	return fx


## Every frame from the worm: the dirt mound over its head while it's
## tunnelling shallow enough (bigger the shallower) or ploughing through the
## floor line (`underground` covers that too: the worm says so), with clods
## and dust streaming off it; the furrow laid behind it and settling; and the
## rumble while it's under.
## `on_terrain`: it's under the open world's terrain (not a level's floor), so
## the dirt follows the ground's shape.
func follow(head: Vector3, velocity: Vector3, ground_y: float, max_depth: float, radius: float, underground: bool,
		on_terrain: bool = false) -> void:
	var depth := ground_y - head.y
	var active := underground and depth > -radius * 0.5 and depth < max_depth
	_on_terrain = on_terrain and link_terrain(self)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.01:
		_facing = Basis.looking_at(flat.normalized(), Vector3.UP)
	var floor_point := Vector3(head.x, ground_y, head.z)
	var multimesh := _dirt.multimesh
	if active:
		var near := clampf(1.0 - depth / max_depth, 0.0, 1.0)
		# Coming up through the floor line (ploughing) the worm itself shows:
		# the mound sinks back around it instead of burying its head.
		var emerge := clampf((depth + radius * 0.5) / radius, 0.0, 1.0)
		var width := radius * 2.6 * (0.6 + 0.4 * near)
		var mound := Transform3D(_facing * Basis.from_scale(Vector3(width, 1.0, width * 1.5)), floor_point)
		multimesh.set_instance_transform(0, mound)
		multimesh.set_instance_custom_data(0, Color(radius * 1.1 * near * emerge, 0.37, 1.0, 2.0 if _on_terrain else 0.0))
		if _on_terrain:
			floor_point = ground(self, floor_point.x, floor_point.z, floor_point.y)[0]
		var stream := Transform3D(_facing.scaled(Vector3.ONE * size), floor_point + Vector3.UP * 0.1)
		_clods.global_transform = stream
		_haze.global_transform = stream
		_lay_furrow(floor_point, radius, near)
	else:
		multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ZERO), floor_point))
		_stamped = false
	_clods.emitting = active
	_haze.emitting = active
	_settle_furrow()
	if _rumble.stream:
		_rumble.global_position = head
		if underground and not _rumble.playing:
			_rumble.play()
		elif not underground and _rumble.playing:
			_rumble.stop()


## A furrow patch behind the mound every FURROW_SPACING of its thickness it
## travels: two loose ridges either side of a dark trough, as wide as the
## mound and overlapping the last, oldest patch reused (FURROW_COUNT).
func _lay_furrow(floor_point: Vector3, radius: float, near: float) -> void:
	var spacing := radius * FURROW_SPACING
	if _stamped and floor_point.distance_to(_last_stamp) < spacing:
		return
	_stamped = true
	_last_stamp = floor_point
	var back := _facing.z.normalized() # +Z is behind (it faces -Z)
	var width := radius * 2.8
	var place := Transform3D(_facing * Basis.from_scale(Vector3(width, 1.0, spacing * 1.9)), floor_point + back * radius * 1.4)
	var i := _furrow_next
	_furrow_next = (_furrow_next + 1) % FURROW_COUNT
	_furrow_born[i] = Time.get_ticks_msec() * 0.001
	_furrow_place[i] = place
	_furrow_height[i] = radius * 0.4 * (0.5 + 0.5 * near)
	_dirt.multimesh.set_instance_custom_data(i + 1, Color(_furrow_height[i], randf() * 10.0, 0.0, 3.0 if _on_terrain else 1.0))


## Every patch settles: its ridges sink flat over the second half of
## FURROW_LIFE and it narrows away at the very end.
func _settle_furrow() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var multimesh := _dirt.multimesh
	for i in FURROW_COUNT:
		var born := _furrow_born[i]
		if born < 0.0:
			continue
		var t := (now - born) / FURROW_LIFE
		if t >= 1.0:
			_furrow_born[i] = -1.0
			multimesh.set_instance_transform(i + 1, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		var settle := 1.0 - smoothstep(0.5, 1.0, t)
		var narrow := 1.0 - smoothstep(0.85, 1.0, t)
		var place := _furrow_place[i]
		multimesh.set_instance_transform(i + 1, Transform3D(place.basis * Basis.from_scale(Vector3(narrow, 1.0, 1.0)), place.origin))
		var custom := multimesh.get_instance_custom_data(i + 1)
		custom.r = _furrow_height[i] * settle
		multimesh.set_instance_custom_data(i + 1, custom)


## Dead (or gone): the rumble stops, the mound and its streams of clods and
## dust go (the furrow settles as it would).
func silence() -> void:
	_rumble.stop()
	_dirt.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_clods.emitting = false
	_haze.emitting = false


## The rumble swelling (dB on top of its normal volume) -- the wind-up.
func rumble_boost(db: float) -> void:
	if _rumble:
		_rumble.volume_db = rumble_volume_db + db


## Bursting out: a column of dirt blasting up out of the hole -- a big dust
## cloud and rubble at once, then three bursts climbing the column -- for a
## worm `radius` thick.
func eruption(at: Vector3, radius: float) -> void:
	burst(at, Vector3.UP)
	burst(at + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)) * radius, Vector3.UP)
	var world := get_tree().current_scene
	for i in 3:
		var height := (i + 1) * radius * 1.5
		var delay := 0.06 * (i + 1)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(world):
				BloodFX.spawn_impact(world, at + Vector3.UP * height, Vector3.UP, DIRT_COLOR, 3.0 - i * 0.5))


## Breaking the surface at `at`: a slow cloud of dust and a fling of rubble.
func burst(at: Vector3, normal: Vector3) -> void:
	if _dust.is_empty():
		for i in 2:
			_dust.append(_make_emitter(_dust_process, _dust_mesh, 10, 2.8))
		_rubble = _make_emitter(_rubble_process, _rubble_mesh, 14, 1.6)
	var dust := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	for emitter: GPUParticles3D in [dust, _rubble]:
		emitter.global_transform = Transform3D(_up_basis(normal).scaled(Vector3.ONE * size), at)
		emitter.restart()


## A landing: a ring of dust tearing outward to `radius` and fading, with a
## dust cloud and rubble.
func shockwave(at: Vector3, radius: float) -> void:
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.mesh = _ring_mesh
		_ring.material_override = _ring_material
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	if _ring_tween:
		_ring_tween.kill()
	_ring.visible = true
	# Lying on the ground there, tilted with it (on the terrain).
	var normal := Vector3.UP
	if _on_terrain:
		var spot: Array = ground(self, at.x, at.z, at.y)
		at = spot[0]
		normal = spot[1]
	_ring.global_transform = Transform3D(_up_basis(normal) * Basis.from_scale(Vector3(0.5, 1.0, 0.5)), at + normal * 0.25)
	_ring.transparency = 0.0
	_ring_tween = create_tween()
	_ring_tween.tween_property(_ring, "scale", Vector3(radius, 1.5, radius), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ring_tween.parallel().tween_property(_ring, "transparency", 1.0, 0.45).set_ease(Tween.EASE_IN)
	_ring_tween.tween_callback(func() -> void: _ring.visible = false)
	burst(at, normal)


## Passing under the floor at `surface` (the floor point above it): every
## TREMOR_INTERVAL, dust and pebbles shake loose from a ceiling or overhang
## above (one ray up), and loose props on the floor nearby jitter (host:
## one small sphere query -- they're physics).
func tremor(surface: Vector3, delta: float) -> void:
	_tremor_left -= delta
	if _tremor_left > 0.0:
		return
	_tremor_left = TREMOR_INTERVAL * randf_range(0.8, 1.2)
	var space := get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(surface + Vector3.UP * 2.2, surface + Vector3.UP * CEILING_REACH)
	up.collision_mask = 1
	var hit := space.intersect_ray(up)
	if not hit.is_empty() and hit.collider is StaticBody3D and (hit.normal as Vector3).y < -0.5:
		if _fall == null:
			_fall = _make_emitter(_fall_process, _rubble_mesh, 10, 1.2)
			_fall.explosiveness = 0.6
		_fall.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), (hit.position as Vector3) - Vector3.UP * 0.1)
		_fall.restart()
		BloodFX.spawn_impact(get_tree().current_scene, (hit.position as Vector3) - Vector3.UP * 0.15, Vector3.DOWN, Color(DUST_COLOR, 1.0), 0.5)
	if not multiplayer.is_server():
		return
	var sphere := SphereShape3D.new()
	sphere.radius = PROP_REACH * size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, surface + Vector3.UP * 0.5)
	query.collision_mask = 1
	for result in space.intersect_shape(query, 12):
		var prop := result.collider as RigidBody3D
		if prop == null or prop.has_method("stun") or prop.freeze:
			continue # creatures (rats, roaches) aren't props
		var kick := Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.6), randf_range(-0.6, 0.6))
		prop.apply_central_impulse(kick * prop.mass)


## A quick zoom-out punch on the camera of anyone within `within` of `at`
## (stronger closer). Static: any worm (or anything) can call it.
static func punch(tree: SceneTree, at: Vector3, amount: float, within: float) -> void:
	for node in tree.get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < within and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).kick_fov(amount * (1.0 - distance / within))


## Out of the ground: thick drool pouring off its lower lip (`jaws`, the
## worm works out where that is) -- a heavy drip from somewhere along the lip
## every DROOL_INTERVAL or so, and now and then a big glob that strings down
## below it, so it reads from across the room.
func drool(jaws: Vector3, delta: float) -> void:
	_drool_left -= delta
	if _drool_left > 0.0:
		return
	_drool_left = DROOL_INTERVAL * randf_range(0.6, 1.4)
	var world := get_tree().current_scene
	var along_lip := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.35 * size
	BloodFX.spawn_impact(world, jaws + along_lip, Vector3.DOWN, SPIT_COLOR, (0.6 * size + 0.3) * 2.0)
	if randf() < 0.35:
		# A big glob stringing off, with a drip trailing under it.
		BloodFX.spawn_impact(world, jaws + along_lip * 0.5, Vector3.DOWN, SPIT_COLOR, (0.9 * size + 0.4) * 2.0)
		BloodFX.spawn_impact(world, jaws + along_lip * 0.5 + Vector3.DOWN * 0.5 * size, Vector3.DOWN, SPIT_COLOR, (0.5 * size + 0.2) * 2.0)


## A bite: gore and spit spraying out of its jaws along `forward`.
func bite_spray(jaws: Vector3, forward: Vector3, with_spit: bool = true) -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, jaws, forward, BLOOD_COLOR, 1.5 * size + 0.5)
	if with_spit:
		BloodFX.spawn_impact(world, jaws, (forward + Vector3.UP * 0.5).normalized(), SPIT_COLOR, 1.0 * size + 0.3)


## Flying out of the ground: clods of dirt shedding off its body (one of
## `points`, picked at random, each time).
func shed(points: PackedVector3Array, ground_y: float, delta: float) -> void:
	_shed_left -= delta
	if _shed_left > 0.0 or points.is_empty():
		return
	_shed_left = SHED_INTERVAL
	var at := points[randi() % points.size()]
	if at.y > ground_y + 0.3:
		BloodFX.spawn_impact(get_tree().current_scene, at, Vector3.DOWN, DIRT_COLOR, 0.5 * size + 0.25)


func _make_emitter(process: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.process_material = process
	emitter.draw_pass_1 = mesh
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.9
	emitter.emitting = false
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 12, 16))
	add_child(emitter)
	return emitter


## An emitter that streams steadily while `emitting` (the mound's clods and
## dust), particles left behind in the world.
func _make_stream(process: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float) -> GPUParticles3D:
	var emitter := _make_emitter(process, mesh, amount, lifetime)
	emitter.one_shot = false
	emitter.explosiveness = 0.0
	emitter.randomness = 0.5
	return emitter


## The open world's ground at (x, z): [the point on it, which way it faces],
## from Terrain3D's own data (no raycast); [(x, fallback_y, z), up] where
## there's no terrain (a level, a hole, off its edge).
static func ground(node: Node, x: float, z: float, fallback_y: float) -> Array:
	var terrain := _find_terrain(node)
	if terrain:
		var data: Object = terrain.call(&"get_data")
		if data:
			var probe := Vector3(x, 0.0, z)
			var height: float = data.call(&"get_height", probe)
			if not is_nan(height) and is_finite(height):
				var normal: Vector3 = data.call(&"get_normal", probe)
				if not normal.is_finite() or normal.length_squared() < 0.01:
					normal = Vector3.UP
				return [Vector3(x, height, z), normal.normalized()]
	return [Vector3(x, fallback_y, z), Vector3.UP]


## Gives the dirt material the terrain's height maps (once per terrain).
## False if this scene has no terrain.
static func link_terrain(node: Node) -> bool:
	var terrain := _find_terrain(node)
	if terrain == null:
		return false
	if _linked_terrain == terrain.get_instance_id():
		return true
	var material: Object = terrain.call(&"get_material")
	if material == null or _dirt_material == null:
		return false
	var source: RID = material.call(&"get_material_rid")
	for uniform in TERRAIN_UNIFORMS:
		RenderingServer.material_set_param(_dirt_material.get_rid(), uniform, RenderingServer.material_get_param(source, uniform))
	_linked_terrain = terrain.get_instance_id()
	return true


## The scene's Terrain3D, or null (looked for at most once a second).
static func _find_terrain(node: Node) -> Node:
	if _terrain and is_instance_valid(_terrain.get_ref()):
		return _terrain.get_ref() as Node
	if Time.get_ticks_msec() - _terrain_looked_msec < 1000 or not node.is_inside_tree():
		return null
	_terrain_looked_msec = Time.get_ticks_msec()
	var scene := node.get_tree().current_scene
	var found := scene.find_children("*", "Terrain3D", true, false) if scene else []
	if found.is_empty():
		return null
	_terrain = weakref(found[0])
	_linked_terrain = 0
	return found[0]


static func _up_basis(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up))


## The shared resources, made once for every worm.
static func _make_shared() -> void:
	if _dirt_mesh != null:
		return
	# Churned dirt: a 1 x 1 plane, finely enough cut for the shader to shape
	# lumps into (16 x 16 squares; still PS1-chunky up close).
	_dirt_mesh = PlaneMesh.new()
	_dirt_mesh.size = Vector2.ONE
	_dirt_mesh.subdivide_width = 15
	_dirt_mesh.subdivide_depth = 15
	_dirt_material = ShaderMaterial.new()
	_dirt_material.shader = DIRT_SHADER
	_dirt_material.set_shader_parameter("dirt_texture", DIRT_TEXTURE)
	# Clods tumbling off the mound's sides: dirt-textured chunks thrown up
	# and outward (radial), falling back into the floor.
	var clod_material := StandardMaterial3D.new()
	clod_material.albedo_texture = DIRT_TEXTURE
	clod_material.albedo_color = Color(0.8, 0.75, 0.7)
	clod_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	clod_material.roughness = 1.0
	_clod_mesh = BoxMesh.new()
	_clod_mesh.size = Vector3(0.14, 0.1, 0.12)
	_clod_mesh.material = clod_material
	_clod_process = ParticleProcessMaterial.new()
	_clod_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_clod_process.emission_box_extents = Vector3(0.9, 0.05, 1.2)
	_clod_process.direction = Vector3.UP
	_clod_process.spread = 35.0
	_clod_process.initial_velocity_min = 2.0
	_clod_process.initial_velocity_max = 4.0
	_clod_process.radial_velocity_min = 1.0
	_clod_process.radial_velocity_max = 2.5
	_clod_process.gravity = Vector3(0.0, -16.0, 0.0)
	_clod_process.angular_velocity_min = -360.0
	_clod_process.angular_velocity_max = 360.0
	_clod_process.scale_min = 0.5
	_clod_process.scale_max = 1.4
	# A low haze of dust hanging over it.
	_haze_process = ParticleProcessMaterial.new()
	_haze_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_haze_process.emission_box_extents = Vector3(0.9, 0.1, 1.2)
	_haze_process.direction = Vector3.UP
	_haze_process.spread = 60.0
	_haze_process.initial_velocity_min = 0.3
	_haze_process.initial_velocity_max = 1.0
	_haze_process.gravity = Vector3(0.0, 0.2, 0.0)
	_haze_process.damping_min = 0.5
	_haze_process.damping_max = 1.0
	_haze_process.scale_min = 1.0
	_haze_process.scale_max = 2.0
	# Dust: soft round puffs that billow up slowly, swell and fade.
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 32
	puff.height = 32
	var puff_gradient := Gradient.new()
	puff_gradient.set_color(0, Color(1, 1, 1, 1))
	puff_gradient.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = puff_gradient
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_material.vertex_color_use_as_albedo = true
	dust_material.albedo_texture = puff
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2.ONE
	_dust_mesh.material = dust_material
	_dust_process = ParticleProcessMaterial.new()
	_dust_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_dust_process.emission_sphere_radius = 0.8
	_dust_process.direction = Vector3.UP
	_dust_process.spread = 70.0
	_dust_process.initial_velocity_min = 1.0
	_dust_process.initial_velocity_max = 3.0
	_dust_process.gravity = Vector3(0.0, 0.3, 0.0)
	_dust_process.damping_min = 1.0
	_dust_process.damping_max = 2.0
	_dust_process.scale_min = 1.5
	_dust_process.scale_max = 3.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	_dust_process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, DUST_COLOR)
	fade.set_color(1, Color(DUST_COLOR, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	_dust_process.color_ramp = fade_texture
	_haze_process.scale_curve = grow_texture
	var haze_fade := Gradient.new()
	haze_fade.set_color(0, Color(DUST_COLOR, 0.35))
	haze_fade.set_color(1, Color(DUST_COLOR, 0.0))
	var haze_fade_texture := GradientTexture1D.new()
	haze_fade_texture.gradient = haze_fade
	_haze_process.color_ramp = haze_fade_texture
	# Rubble: chunks of floor flung up, tumbling, falling back (and into the
	# floor, which hides them -- no collision needed).
	var rubble_material := StandardMaterial3D.new()
	rubble_material.albedo_color = RUBBLE_COLOR
	rubble_material.roughness = 1.0
	_rubble_mesh = BoxMesh.new()
	_rubble_mesh.size = Vector3(0.18, 0.12, 0.15)
	_rubble_mesh.material = rubble_material
	_rubble_process = ParticleProcessMaterial.new()
	_rubble_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_rubble_process.emission_sphere_radius = 0.6
	_rubble_process.direction = Vector3.UP
	_rubble_process.spread = 45.0
	_rubble_process.initial_velocity_min = 5.0
	_rubble_process.initial_velocity_max = 10.0
	_rubble_process.gravity = Vector3(0.0, -18.0, 0.0)
	_rubble_process.angular_velocity_min = -360.0
	_rubble_process.angular_velocity_max = 360.0
	_rubble_process.scale_min = 0.6
	_rubble_process.scale_max = 1.8
	# Ceiling dust: pebbles shaken loose, dropping.
	_fall_process = ParticleProcessMaterial.new()
	_fall_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_fall_process.emission_box_extents = Vector3(1.2, 0.05, 1.2)
	_fall_process.direction = Vector3.DOWN
	_fall_process.spread = 10.0
	_fall_process.initial_velocity_min = 0.0
	_fall_process.initial_velocity_max = 0.5
	_fall_process.gravity = Vector3(0.0, -12.0, 0.0)
	_fall_process.angular_velocity_min = -180.0
	_fall_process.angular_velocity_max = 180.0
	_fall_process.scale_min = 0.3
	_fall_process.scale_max = 0.8
	# Shockwave ring: a thin, low torus of dust, scaled out and faded per use.
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.82
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(DUST_COLOR, 0.7)
