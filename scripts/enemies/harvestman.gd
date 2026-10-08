class_name Harvestman
extends Node3D

## A ten-meter sewer stilt-walker: a sack of flesh carried on three needle
## legs, creeping about on its tiptoes. Half-Life 2's Strider is the model
## for how it fights (tall, real stepping legs, a leg stabbed down like a
## spear, crouching to slam and to get under things, rockets and weak spots
## to bring it down); a harvestman (daddy-longlegs) for how it moves.
##
## Its look is a model scene (model_scene, made by HarvestmanBuilder -- open
## it to change it): the sack (HarvestmanCore), a spider face with glowing
## eyes and a searchlight, civilian limbs dangling on jiggle bones, and three
## legs -- the enemy spider's back leg stretched to ~11 m, or (leech legs)
## chains of tape-worm segments drawn along the IK here.
##
## Legs: real inverse kinematics (FABRIK, like the spiders), each foot found
## on the floor with one ray when it steps. It steps one leg at a time, round
## and round, lifting each foot high and setting it down straight and soft,
## like it's trying not to be heard; the body rides the legs on a slow spring,
## sinking as a foot lifts and leaning onto the planted ones, and the sack
## swings a beat behind it. Clumsy: now and then a foot slips on the slime
## and the whole thing lurches. Anything small under a foot gets squashed.
##
## Senses: it sees out of its eyes (a cone of sight_range the searchlight
## sweeps -- break line of sight to hide; the invisibility setting works) and
## feels anyone right under it. Patrolling, it wanders, stops to listen with
## its light sweeping round; spotting you, it wails (a horn) and its drone
## rises. Lost, it searches where you were.
##
## Attacks (one at a time, attack_cooldown between):
##   - Skewer: a leg rears up over its body, trembles, and stabs down where
##     you'll be (the spitter roach's lead). Kills small creatures outright.
##   - Slam: under it, it rises, then drops its sack onto the floor -- a
##     shockwave -- and stays down, exposed (sack damage x exposed_multiplier)
##     for slam_exposed seconds before it climbs back up.
##   - Sewage hose: from range, a feeding tube out of its face sprays a sweep
##     of filth across you (the roach's spit, brown) leaving burning puddles.
##   - Brood drop: its sack splits and roaches pour out.
##   - Feeding (not an attack): with nobody about, it walks to a corpse,
##     crouches, drags it up into its face on a tube and eats it (heals).
##
## Weak spots: the sack (sack_multiplier) and the three knees
## (knee_multiplier) -- a hit there gushes blood like an artery shot. A knee
## that takes knee_health breaks: that leg goes limp and drags. Two broken
## and it collapses, crawling on what it has left. The legs' shafts take
## leg_multiplier. Dead: the legs give one by one, it comes down, and the
## sack bursts.
##
## Rule 1 (co-op): the host thinks, moves it and deals all damage; the legs,
## body motion, limbs and effects are looks every peer works out from where
## it is (its position/heading still need syncing, like every creature).

enum State { PATROL, LISTEN, HUNT, SEARCH, ATTACK, FEED, COLLAPSED, DEAD }
enum Attack { NONE, SKEWER, SLAM, HOSE, BROOD }

const LEECH_SEGMENT_MESH := "res://art/worm_boss/worm_segment_mesh.res"
const LEECH_TEXTURE := "res://art/props/PSX Creatures/Textures/tape_worm.png"
const DRONE_STREAM := "res://audio/sfx/worm_rumble.wav"
const ROACH_SCENE := "res://scenes/enemy/roach.tscn"
const SEWAGE_COLOR := Color(0.3, 0.32, 0.1)
const GUSH_SOUND := preload("res://audio/events/artery_spurt.tres")
## The leech legs: segments drawn per leg, and how the leg's length splits
## between its three parts (hip-knee, knee-ankle, ankle-foot).
const LEECH_SEGMENTS := 12
const LEECH_SPLIT := [0.34, 0.38, 0.28]
## The baked worm segment's length along Z (BurrowWorm: 0.8625 x 1.8).
const SEGMENT_MESH_LENGTH := 1.55

@export var model_scene: PackedScene

@export_group("Model")
## On spawn, whatever the core looks like (edit it however you like in the
## model scene): the whole body is shifted so the core's middle is the body's
## middle (where it rides and gets hit), its hitbox sized to it...
@export var center_core: bool = true
## ...and every leg's hip put back on the core's surface, at the angle round
## the body its Leg node has.
@export var fit_legs_to_core: bool = true
## The civilian limbs dangling off it, and the leech legs' barnacle knees.
## Off = left out (still in the model scene, for later).
@export var show_limbs: bool = false
@export var show_knees: bool = false

@export_group("Searchlight")
@export var light_color: Color = Color(1.0, 0.1, 0.06)
@export var light_energy: float = 9.0
@export var light_range: float = 45.0
@export var light_angle: float = 22.0
## The beam you can see in the air, down to wherever it lands (0 = none).
@export_range(0.0, 0.5, 0.01) var beam_strength: float = 0.09

@export_group("Stance")
## Height of the middle of its sack above the floor, standing / crouched
## (to get under things, to feed).
@export var stand_height: float = 8.0
@export var crouch_height: float = 3.2
## How far out from under its body its feet stand.
@export var foot_radius: float = 6.0
## Leech legs: how long each is laid out straight (spider legs are as long
## as the model's).
@export var leg_length: float = 11.0
## The sack's size for its hitbox (m).
@export var sack_radius: float = 1.8

@export_group("Walking")
@export var walk_speed: float = 1.8
@export var hunt_speed: float = 3.2
## How fast it turns (radians a second).
@export var turn_speed: float = 0.9
## A foot steps once it's this far from where it should stand...
@export var stride: float = 2.4
## ...taking this long, lifting this high (tiptoeing).
@export var step_time: float = 0.9
@export var step_lift: float = 2.2
## Chance a foot slips on landing (the whole body lurches).
@export_range(0.0, 1.0, 0.05) var slip_chance: float = 0.1
## How much the body sways and lags (higher = wobblier).
@export var body_sway: float = 0.35
## Creatures under a landing foot take this.
@export var squash_damage: float = 40.0

@export_group("Senses")
@export var sight_range: float = 40.0
@export var sight_cone_degrees: float = 70.0
## Anyone this close is felt, seen or not.
@export var feel_range: float = 9.0
## Gives up hunting after not seeing them this long, and searches.
@export var lose_time: float = 6.0
@export var search_time: float = 8.0
@export var listen_time: float = 3.5
@export var patrol_radius: float = 22.0

@export_group("Attacks")
@export var attack_cooldown: float = 2.0
@export var skewer_range: float = 9.0
@export var skewer_damage: float = 70.0
@export var skewer_windup: float = 0.9
@export var slam_range: float = 4.5
@export var slam_damage: float = 35.0
@export var slam_radius: float = 7.0
@export var slam_exposed: float = 3.0
@export var hose_range_min: float = 8.0
@export var hose_range_max: float = 24.0
@export var hose_time: float = 1.8
@export var hose_globs: int = 14
@export var hose_damage: float = 6.0
@export var hose_sweep: float = 3.5
@export var hose_speed: float = 14.0
@export var puddle_damage: float = 5.0
@export var puddle_time: float = 6.0
@export var brood_cooldown: float = 22.0
@export var brood_count: int = 3

@export_group("Feeding")
@export var feed_range: float = 22.0
@export var feed_heal: float = 200.0
@export var feed_time: float = 4.0
@export var feed_pull: float = 30.0

@export_group("Damage")
@export var sack_multiplier: float = 2.0
@export var exposed_multiplier: float = 3.0
@export var knee_multiplier: float = 1.5
@export var knee_health: float = 220.0
@export var leg_multiplier: float = 0.5
## How long a weak-spot hit gushes (s).
@export var gush_time: float = 1.5
## Gone this long after it dies.
@export var corpse_time: float = 60.0

@export_group("Sound")
@export var horn_sound: SoundEvent
@export var step_sound: SoundEvent
@export var hurt_sound: SoundEvent
@export var death_sound: SoundEvent
## Its drone: pitch while wandering / hunting, and how loud.
@export var drone_pitch: float = 1.7
@export var drone_hunt_pitch: float = 2.1
@export var drone_volume_db: float = -6.0
## Close-up horror: within this, the camera sways and the drone warps down.
@export var horror_range: float = 8.0

var target: Node3D

@onready var health: Health = $Health


## One leg: its hip node, its bones (spider legs), its joints this frame,
## and its foot.
class HLeg:
	var node: Node3D
	var angle := 0.0
	var skeleton: Skeleton3D
	var bones := PackedInt32Array()
	var rest_local: Array[Transform3D] = []
	var child_offset: Array[Vector3] = []
	var body_rest := Transform3D.IDENTITY
	var lengths := PackedFloat32Array()
	var joints := PackedVector3Array()
	var knee := 2
	var planted := Vector3.ZERO
	var step_from := Vector3.ZERO
	var step_to := Vector3.ZERO
	var foot := Vector3.ZERO
	var stepping := false
	var step_t := 0.0
	var step_duration := 1.0
	var slip_left := 0.0
	var slip_dir := Vector3.ZERO
	## An attack driving the foot instead of the walk.
	var driven := false
	var drive_to := Vector3.ZERO
	var broken := false
	var knee_hp := 0.0
	var knee_body: AnimatableBody3D
	var shafts: Array[AnimatableBody3D] = []
	var lump: Node3D


var _state := State.PATROL
var _state_time := 0.0
var _attack := Attack.NONE
var _attack_time := 0.0
var _attack_leg: HLeg
var _attack_point := Vector3.ZERO
var _attack_fired := 0
var _attack_guess := Vector2.ONE
var _cooldown := 1.0
var _brood_left := 8.0
var _exposed := 0.0
var _goal := Vector3.ZERO
var _home := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _since_seen := INF
var _think_left := 0.0
var _feed_corpse: Node3D
var _feed_ragdoll: EnemyRagdoll
var _dead_step := 0.0
var _burst := false

# ---- Looks ----
var _model: Node3D
var _body: Node3D
var _core: Node3D
var _face: Node3D
var _mouth: Node3D
var _light: SpotLight3D
var _legs: Array[HLeg] = []
var _leech_mm: MultiMeshInstance3D
var _tube_mm: MultiMeshInstance3D
var _tube_end := Vector3.ZERO
var _tube_on := false
var _yaw := 0.0
var _speed := 0.0
var _height := 8.0
var _height_target := 8.0
var _height_vel := 0.0
var _sway := Vector3.ZERO
var _sway_vel := Vector3.ZERO
var _sack_lag := Vector2.ZERO
var _sack_lag_vel := Vector2.ZERO
var _last_body := Vector3.ZERO
var _body_velocity := Vector3.ZERO
var _eye_dir := Vector3.FORWARD
var _next_leg := 0
var _time := 0.0
var _drone: AudioStreamPlayer3D
var _horror_left := 0.0
var _sack_body: AnimatableBody3D
var _beam: MeshInstance3D
var _beam_left := 0.0
var _beam_length := 10.0
var _gush_cooldowns := {}
var _bodies: Array[AnimatableBody3D] = []


func _ready() -> void:
	_home = global_position
	_goal = global_position
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_height = stand_height
	_height_target = stand_height
	health.died.connect(_on_died)
	health.damaged.connect(_on_hurt)
	if model_scene:
		_model = model_scene.instantiate() as Node3D
		add_child(_model)
		_body = _model.get_node_or_null("Body") as Node3D
	if _body == null:
		push_warning("Harvestman: no model (model_scene with a Body node).")
		return
	_core = _body.get_node_or_null("Core") as Node3D
	_face = _body.get_node_or_null("Face") as Node3D
	_mouth = _body.get_node_or_null("Face/Mouth") as Node3D
	_light = _body.get_node_or_null("Face/Searchlight") as SpotLight3D
	var legs := _body.get_node_or_null("Legs")
	if not show_limbs:
		var limbs := _body.get_node_or_null("Limbs")
		if limbs:
			limbs.free()
	if not show_knees and legs:
		for leg_node in legs.get_children():
			var knee := leg_node.get_node_or_null("Knee")
			if knee:
				knee.free()
	_fit_to_core(legs)
	_setup_light()
	if legs:
		for child in legs.get_children():
			if child is Node3D:
				var leg := _make_leg(child as Node3D)
				if leg:
					_legs.append(leg)
	if _legs.any(func(leg: HLeg) -> bool: return leg.skeleton == null):
		_leech_mm = _segments_mesh(LEECH_SEGMENTS * _legs.size())
	_tube_mm = _segments_mesh(8)
	var sack := SphereShape3D.new()
	sack.radius = sack_radius
	_sack_body = _hitbox(sack, "sack", null)
	for leg in _legs:
		var knee := SphereShape3D.new()
		knee.radius = 0.7
		leg.knee_body = _hitbox(knee, "knee", leg)
		for i in leg.lengths.size():
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.3
			capsule.height = maxf(leg.lengths[i], 0.7)
			leg.shafts.append(_hitbox(capsule, "leg", leg))
		leg.knee_hp = knee_health
	_drone = AudioStreamPlayer3D.new()
	if ResourceLoader.exists(DRONE_STREAM):
		var stream := load(DRONE_STREAM) as AudioStream
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		_drone.stream = stream
	_drone.pitch_scale = drone_pitch
	_drone.volume_db = drone_volume_db
	_drone.unit_size = 10.0
	_drone.max_distance = 70.0
	_drone.bus = "Enemies" if AudioServer.get_bus_index("Enemies") != -1 else "Master"
	add_child(_drone)
	_place_body(0.0)
	_plant_all.call_deferred()
	if _drone.stream:
		_drone.play.call_deferred()


# ---- Building the live parts --------------------------------------------------

## Whatever the core turned out like: the body's parts all shifted so the
## core's middle is the body's middle (center_core; the sack's hitbox then
## sits on it, sized to it), and each leg's hip moved onto the core's
## surface at its own angle round the body (fit_legs_to_core).
func _fit_to_core(legs: Node) -> void:
	if _core == null or not (center_core or fit_legs_to_core):
		return
	var points := HarvestmanBuilder.surface_points(_core, _body)
	if points.is_empty():
		return
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	var middle := box.get_center()
	if center_core:
		for child in _body.get_children():
			if child is Node3D:
				(child as Node3D).position -= middle
		for i in points.size():
			points[i] -= middle
		sack_radius = maxf(minf(box.size.x, box.size.z) * 0.5, 0.8)
	if fit_legs_to_core and legs:
		for node in legs.get_children():
			var leg := node as Node3D
			if leg == null:
				continue
			var angle := atan2(leg.position.x, -leg.position.z)
			var out := Vector3(sin(angle), 0.45, -cos(angle)).normalized()
			leg.position = HarvestmanBuilder.surface_at(points, out, sack_radius) - out * 0.2


## The searchlight: red, long, and a faint beam you can see in the air down
## to wherever it lands (_aim_beam()).
func _setup_light() -> void:
	if _light == null:
		return
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.spot_range = light_range
	_light.spot_angle = light_angle
	_light.shadow_enabled = false
	if beam_strength <= 0.0:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = tan(deg_to_rad(light_angle))
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(light_color, beam_strength)
	_beam = MeshInstance3D.new()
	_beam.mesh = cone
	_beam.material_override = material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light.add_child(_beam)


## The beam reaches from the eyes to where the light lands (one ray, a few
## times a second).
func _aim_beam(delta: float) -> void:
	if _beam == null or _light == null:
		return
	_beam_left -= delta
	if _beam_left <= 0.0:
		_beam_left = 0.1
		var from := _light.global_position
		var to := from - _light.global_basis.z * light_range
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var hit := _static_hit(get_world_3d().direct_space_state, query)
		_beam_length = from.distance_to(hit.position) if not hit.is_empty() else light_range * 0.6
	# The cone's axis is its Y: lay it along the light (-Z), tip at the eyes.
	_beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(_beam_length, _beam_length, _beam_length)), Vector3(0.0, 0.0, -_beam_length * 0.5))
	_beam.visible = _state != State.DEAD

func _make_leg(node: Node3D) -> HLeg:
	var leg := HLeg.new()
	leg.node = node
	leg.angle = atan2(node.position.x, -node.position.z)
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		leg.skeleton = skeleton
		skeleton.reset_bone_poses() # the IK works from the rest pose
		var body_bone := skeleton.find_bone("body")
		leg.body_rest = skeleton.get_bone_global_rest(body_bone) if body_bone >= 0 else Transform3D.IDENTITY
		var prefix: String = HarvestmanBuilder.SPIDER_LEG
		for part in ["A", "B", "C", "D"]:
			var bone := skeleton.find_bone(prefix + part)
			if bone < 0:
				return null
			leg.bones.append(bone)
			leg.rest_local.append(skeleton.get_bone_rest(bone))
		for i in 3:
			leg.child_offset.append(skeleton.get_bone_rest(leg.bones[i + 1]).origin)
		var tip := skeleton.find_bone(prefix + "D_end")
		leg.child_offset.append(skeleton.get_bone_rest(tip).origin if tip >= 0 else leg.child_offset[2])
		# Segment lengths in meters, from the rest pose where the model puts it.
		var chain := leg.body_rest
		var points := PackedVector3Array()
		for i in 4:
			chain = chain * leg.rest_local[i]
			points.append(skeleton.global_transform * chain.origin)
		points.append(skeleton.global_transform * (chain * leg.child_offset[3]))
		for i in 4:
			leg.lengths.append(points[i].distance_to(points[i + 1]))
		leg.knee = 2
	else:
		for share in LEECH_SPLIT:
			leg.lengths.append(leg_length * share)
		leg.knee = 1
		leg.lump = node.get_node_or_null("Knee") as Node3D
	leg.joints.resize(leg.lengths.size() + 1)
	return leg


## A MultiMesh of `count` tape-worm segments (the leech legs, the tube).
func _segments_mesh(count: int) -> MultiMeshInstance3D:
	var mesh: Mesh = load(LEECH_SEGMENT_MESH) if ResourceLoader.exists(LEECH_SEGMENT_MESH) else null
	if mesh == null:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = SEGMENT_MESH_LENGTH
		mesh = cylinder
	var instance := MultiMeshInstance3D.new()
	instance.top_level = true
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(LEECH_TEXTURE)
	material.roughness = 0.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	instance.material_override = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	instance.multimesh = multimesh
	instance.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	add_child(instance)
	instance.global_transform = Transform3D.IDENTITY
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	return instance


## A shootable part: a body with its own Health that passes the damage on
## (_on_part_hurt).
func _hitbox(shape: Shape3D, part: String, leg: HLeg) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.top_level = true
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var proxy := Health.new()
	proxy.name = "Health"
	proxy.max_health = 1000000.0
	body.add_child(proxy)
	proxy.damaged.connect(_on_part_hurt.bind(body, part, leg))
	add_child(body)
	_bodies.append(body)
	return body


# ---- Thinking (host) ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _body == null:
		return
	_state_time += delta
	if _state == State.DEAD:
		_die_step(delta)
		return
	if not multiplayer.is_server():
		return
	_cooldown -= delta
	_brood_left -= delta
	_exposed = maxf(_exposed - delta, 0.0)
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = 0.25
		_look()
		_ignore_players()
	match _state:
		State.PATROL:
			_walk_to(_goal, walk_speed, delta)
			if _flat_distance(_goal) < 2.5:
				_set_state(State.LISTEN)
			elif _state_time > 25.0:
				_pick_patrol_goal()
		State.LISTEN:
			_walk_to(global_position, 0.0, delta)
			if _state_time > listen_time:
				if not _try_feed():
					_pick_patrol_goal()
					_set_state(State.PATROL)
		State.SEARCH:
			_walk_to(_last_seen, walk_speed, delta)
			if _state_time > search_time:
				_pick_patrol_goal()
				_set_state(State.PATROL)
		State.HUNT, State.COLLAPSED:
			_hunt(delta)
		State.ATTACK:
			_walk_to(global_position, 0.0, delta)
			_attack_step(delta)
		State.FEED:
			_feed_step(delta)


func _set_state(state: State) -> void:
	_state = state
	_state_time = 0.0


func _pick_patrol_goal() -> void:
	var offset := Vector2.from_angle(randf() * TAU) * randf_range(patrol_radius * 0.3, patrol_radius)
	_goal = _home + Vector3(offset.x, 0.0, offset.y)
	_state_time = 0.0


## Every quarter second: can it see (or feel) a player?
func _look() -> void:
	var eyes := _face.global_position if _face else _body.global_position
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var aim := Factions.aim_point(player)
		var distance := eyes.distance_to(aim)
		var felt := _flat_distance(player.global_position) < feel_range
		if distance > sight_range and not felt:
			continue
		if not felt and rad_to_deg(_eye_dir.angle_to(aim - eyes)) > sight_cone_degrees * 0.5:
			continue
		if not felt and not _clear_line(eyes, aim):
			continue
		if distance < best_distance:
			best_distance = distance
			best = player
	if best:
		var was_hunting := _state == State.HUNT or _state == State.ATTACK or _state == State.COLLAPSED
		target = best
		_last_seen = best.global_position
		_since_seen = 0.0
		if not was_hunting:
			_spotted()
		return
	_since_seen += 0.25
	if (_state == State.HUNT) and _since_seen > lose_time:
		target = null
		_set_state(State.SEARCH)


func _spotted() -> void:
	if _state == State.FEED:
		_end_feed()
	if _state != State.COLLAPSED:
		_set_state(State.HUNT)
	SoundPlayer.play_3d(horn_sound, _body.global_position, get_tree().current_scene)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for body in _bodies:
		exclude.append(body.get_rid())
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or not (hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D)


## Hunting: close in (or crawl, collapsed) and pick an attack when ready.
func _hunt(delta: float) -> void:
	if not is_instance_valid(target) or not Factions.is_alive_target(target):
		target = null
		if _state == State.HUNT:
			_set_state(State.SEARCH)
		_walk_to(global_position, 0.0, delta)
		return
	var distance := _flat_distance(target.global_position)
	var collapsed := _state == State.COLLAPSED
	var speed := hunt_speed * (0.3 if collapsed else 1.0)
	if distance > skewer_range * 0.7:
		_walk_to(target.global_position, speed, delta)
	else:
		_walk_to(global_position, 0.0, delta)
		_face_toward(target.global_position, delta)
	if _cooldown > 0.0:
		return
	var leg := _ready_leg()
	if collapsed:
		if leg and distance < skewer_range:
			_start_attack(Attack.SKEWER, leg)
		return
	if _brood_left <= 0.0 and distance < 24.0 and randf() < 0.3:
		_start_attack(Attack.BROOD, null)
	elif distance < slam_range:
		_start_attack(Attack.SLAM, null)
	elif distance < skewer_range and leg:
		_start_attack(Attack.SKEWER, leg)
	elif distance > hose_range_min and distance < hose_range_max and randf() < 0.5:
		_start_attack(Attack.HOSE, null)


## A working leg nearest the target, to stab with.
func _ready_leg() -> HLeg:
	var best: HLeg = null
	var best_distance := INF
	for leg in _legs:
		if leg.broken or leg.stepping:
			continue
		var distance := leg.foot.distance_to(target.global_position) if is_instance_valid(target) else 0.0
		if distance < best_distance:
			best_distance = distance
			best = leg
	return best


func _walk_to(point: Vector3, speed: float, delta: float) -> void:
	var to := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	var want := speed if to.length() > 1.0 else 0.0
	_speed = move_toward(_speed, want, delta * 1.5)
	if to.length_squared() > 1.0:
		_face_toward(point, delta)
	if _speed <= 0.0:
		return
	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw)) * -1.0
	# Something tall in the way (a wall the body won't clear): veer off it.
	var ahead := global_position + Vector3.UP * 3.0
	if not _clear_line(ahead, ahead + forward * 5.0):
		_yaw += turn_speed * delta * 1.5
		forward = Vector3(sin(_yaw), 0.0, cos(_yaw)) * -1.0
	global_position += forward * _speed * delta
	_update_ground()


func _face_toward(point: Vector3, delta: float) -> void:
	var to := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to.length_squared() < 0.01:
		return
	var want := atan2(-to.x, -to.z)
	_yaw = rotate_toward(_yaw, want, turn_speed * delta)


## Stands on the floor under it; crouches under anything overhead.
func _update_ground() -> void:
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 10.0)
	down.collision_mask = 1
	var hit := _static_hit(space, down)
	if not hit.is_empty():
		global_position.y = (hit.position as Vector3).y


func _static_hit(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var exclude: Array[RID] = []
	for body in _bodies:
		exclude.append(body.get_rid())
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D):
			return hit
		exclude.append(hit.rid)
	return {}


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


## Players walk through its legs (shots still hit them) -- including ones
## that join later.
func _ignore_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PhysicsBody3D
		if player == null:
			continue
		for body in _bodies:
			body.add_collision_exception_with(player)


# ---- Attacks (host) -----------------------------------------------------------

func _start_attack(attack: Attack, leg: HLeg) -> void:
	_attack = attack
	_attack_leg = leg
	_attack_time = 0.0
	_attack_fired = 0
	_attack_guess = WormLeap.roll_guess()
	_set_state(State.ATTACK)
	if leg:
		leg.driven = true
		leg.stepping = false


func _end_attack() -> void:
	if _attack_leg:
		_attack_leg.driven = false
		_attack_leg.planted = _attack_leg.foot
	_attack_leg = null
	_attack = Attack.NONE
	_tube_on = false
	_cooldown = attack_cooldown
	if _state == State.ATTACK:
		_set_state(State.COLLAPSED if _broken_legs() >= 2 else State.HUNT)


func _attack_step(delta: float) -> void:
	_attack_time += delta
	match _attack:
		Attack.SKEWER:
			_skewer_step()
		Attack.SLAM:
			_slam_step()
		Attack.HOSE:
			_hose_step()
		Attack.BROOD:
			_brood_step()
		_:
			_end_attack()


## Skewer: the leg rears up over the body and trembles (the tell), stabs
## down where it guesses you'll be, sticks there a moment, pulls free.
func _skewer_step() -> void:
	var leg := _attack_leg
	if leg == null or leg.broken or not is_instance_valid(target):
		_end_attack()
		return
	var body := _body.global_position
	var toward := Vector3(target.global_position.x - body.x, 0.0, target.global_position.z - body.z).normalized()
	var strike := 0.15
	if _attack_time < skewer_windup:
		var tremble := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.15
		leg.drive_to = body + toward * 3.0 + Vector3.UP * 2.5 + tremble
		_attack_point = WormLeap.landing(body, target, skewer_windup - _attack_time + strike, _attack_guess)
		_attack_point.y = target.global_position.y
	elif _attack_time < skewer_windup + strike:
		var t := (_attack_time - skewer_windup) / strike
		leg.drive_to = leg.drive_to.lerp(_attack_point, t * t)
	elif _attack_fired == 0:
		_attack_fired = 1
		leg.drive_to = _attack_point - Vector3.UP * 0.3
		_impale(_attack_point)
	elif _attack_time > skewer_windup + strike + 0.5:
		_end_attack()


func _impale(at: Vector3) -> void:
	var world := get_tree().current_scene
	BloodFX.spawn_impact(world, at, Vector3.UP, Color(0.15, 0.11, 0.08), 2.5)
	_shake_near(at, 3.0, 18.0)
	var hurt_any := false
	for body in _bodies_near(at + Vector3.UP * 0.8, 1.4):
		var body_health := body.get_node_or_null("Health") as Health
		if body_health == null or body_health.is_dead:
			continue
		var damage := skewer_damage if body is PlayerMovement else body_health.current_health + 1.0
		body_health.take_damage(damage, Health.NO_ATTACKER, Vector3.DOWN, at, 1.0)
		hurt_any = true
		if body.has_method("shove"):
			body.call("shove", (body.global_position - at).normalized() * 6.0 + Vector3.UP * 3.0)
	if hurt_any:
		BloodFX.spawn_impact(world, at + Vector3.UP * 0.6, Vector3.UP, BloodFX.BLOOD_COLOR, 3.0)
	Explosion.launch_ragdolls(self, at + Vector3.UP, 2.0, 6.0)


## Slam: up (the tell), then the sack dropped onto the floor -- a shockwave
## -- and it stays down, exposed, before it climbs back up.
func _slam_step() -> void:
	var rise := 0.6
	var drop := 0.25
	var down_height := sack_radius + 0.3
	if _attack_time < rise:
		_height_target = stand_height + 1.2
	elif _attack_time < rise + drop:
		_height_target = down_height
		_height = lerpf(_height, down_height, 0.35)
	elif _attack_fired == 0:
		_attack_fired = 1
		_height = down_height
		_slam_impact()
		_exposed = slam_exposed
	elif _attack_time > rise + drop + slam_exposed:
		_height_target = stand_height
		_end_attack()


func _slam_impact() -> void:
	var center := global_position
	var world := get_tree().current_scene
	for i in 6:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 6.0)
		BloodFX.spawn_impact(world, center + out * sack_radius, (out + Vector3.UP).normalized(), Color(0.15, 0.11, 0.08), 2.5)
	_shake_near(center, 7.0, 25.0)
	WormFX.punch(get_tree(), center, 6.0, 25.0)
	SoundPlayer.play_3d(death_sound, center, world)
	for body in _bodies_near(center + Vector3.UP, slam_radius):
		var away := body.global_position - center
		away.y = 0.0
		var falloff := clampf(1.0 - away.length() / slam_radius, 0.2, 1.0)
		var push := away.normalized() * 10.0 * falloff + Vector3.UP * 5.0 * falloff
		var body_health := body.get_node_or_null("Health") as Health
		if body_health and not body_health.is_dead:
			body_health.take_damage((slam_damage if body is PlayerMovement else 80.0) * falloff, Health.NO_ATTACKER, push.normalized(), center, 1.0)
		if body.has_method("shove"):
			body.call("shove", push)
		elif body is RigidBody3D:
			(body as RigidBody3D).apply_central_impulse(push * (body as RigidBody3D).mass)
	Explosion.launch_ragdolls(self, center + Vector3.UP, slam_radius, 12.0)


## Hose: a tube out of its face sprays a sweep of filth across you -- the
## spitter roach's spit (brown), each glob led like the roach leads -- and
## every glob leaves a burning puddle where it lands.
func _hose_step() -> void:
	if not is_instance_valid(target) or _mouth == null:
		_end_attack()
		return
	_tube_on = true
	var mouth := _mouth.global_position
	_tube_end = mouth + (Factions.aim_point(target) - mouth).normalized() * 3.5
	var due := mini(hose_globs, int(_attack_time / maxf(hose_time, 0.01) * hose_globs))
	while _attack_fired < due:
		var sweep := lerpf(-1.0, 1.0, float(_attack_fired) / maxf(hose_globs - 1, 1))
		var line := Vector3(target.global_position.x - mouth.x, 0.0, target.global_position.z - mouth.z).normalized()
		var across := line.cross(Vector3.UP)
		var landing := Factions.aim_point(target)
		var flight := 0.6
		for _pass in 3:
			flight = clampf(Vector2(landing.x - mouth.x, landing.z - mouth.z).length() / hose_speed, 0.5, 1.6)
			landing = WormLeap.landing(mouth, target, flight, _attack_guess)
		landing += across * sweep * hose_sweep
		var exclude: Array[RID] = []
		for body in _bodies:
			exclude.append(body.get_rid())
		var velocity := AcidSpit.lob_velocity(mouth, landing, flight, 12.0)
		var world := get_tree().current_scene
		AcidSpit.launch(world, mouth, velocity, 12.0, hose_damage, SEWAGE_COLOR, exclude)
		var floor_point := Vector3(landing.x, target.global_position.y, landing.z)
		get_tree().create_timer(flight).timeout.connect(SewagePuddle.spill.bind(world, floor_point, 1.3, puddle_damage, puddle_time))
		_attack_fired += 1
	if _attack_time > hose_time + 0.3:
		_end_attack()


## Brood drop: the sack swells, splits with a gush, and roaches pour out.
func _brood_step() -> void:
	if _attack_time < 0.6:
		return
	if _attack_fired == 0:
		_attack_fired = 1
		_brood_left = brood_cooldown
		var bottom := _body.global_position + Vector3.DOWN * sack_radius
		var world := get_tree().current_scene
		BloodFX.spawn_impact(world, bottom, Vector3.DOWN, BloodFX.BLOOD_COLOR, 4.0)
		SoundPlayer.play_3d(death_sound, bottom, world)
		var roach_scene := load(ROACH_SCENE) as PackedScene
		for i in brood_count:
			var roach := roach_scene.instantiate() as Node3D
			world.add_child(roach)
			var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			roach.global_position = bottom + out * 0.5
			if roach is RigidBody3D:
				(roach as RigidBody3D).linear_velocity = out * 4.0 + Vector3.DOWN * 2.0
	if _attack_time > 1.4:
		_end_attack()


## Every non-static body within `radius` of `at`, but none of its own parts.
func _bodies_near(at: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for body in _bodies:
		exclude.append(body.get_rid())
	query.exclude = exclude
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := result.collider as Node3D
		if body == null or found.has(body) or (body is StaticBody3D and not body is AnimatableBody3D):
			continue
		found.append(body)
	return found


# ---- Feeding (host) -----------------------------------------------------------

## Looks for a body to eat nearby; true if it's going for one.
func _try_feed() -> bool:
	if health.current_health >= health.max_health and randf() < 0.6:
		return false
	var best: Node3D = null
	var best_distance := feed_range
	for node in get_tree().get_nodes_in_group(RatSwarm.CORPSE_GROUP):
		var corpse := node as Node3D
		if corpse == null or corpse.has_meta("dragged"):
			continue
		var ragdoll := corpse.get_node_or_null("EnemyRagdoll") as EnemyRagdoll
		if ragdoll == null:
			continue
		var distance := _flat_distance(ragdoll.body_position())
		if distance < best_distance:
			best_distance = distance
			best = corpse
	if best == null:
		return false
	_feed_corpse = best
	_feed_ragdoll = best.get_node("EnemyRagdoll") as EnemyRagdoll
	best.set_meta("dragged", true)
	_set_state(State.FEED)
	return true


func _feed_step(delta: float) -> void:
	if not is_instance_valid(_feed_corpse) or not is_instance_valid(_feed_ragdoll):
		_end_feed()
		_set_state(State.PATROL)
		return
	var body_at := _feed_ragdoll.body_position()
	if _flat_distance(body_at) > 2.5 and _state_time < 15.0:
		_walk_to(body_at, walk_speed, delta)
		return
	_walk_to(global_position, 0.0, delta)
	_height_target = crouch_height + 0.8
	if _mouth == null:
		_end_feed()
		return
	_tube_on = true
	var mouth := _mouth.global_position
	_tube_end = body_at
	var head := _feed_ragdoll.bone_named("Head")
	if head == null:
		head = _feed_ragdoll.bone_named("Hips")
	if head:
		var pull := (mouth - head.global_position).normalized() * feed_pull * head.mass * delta
		_feed_ragdoll.carry({head: pull}, 0.25)
	if body_at.distance_to(mouth) < 2.2 or _state_time > feed_time + 6.0:
		var world := get_tree().current_scene
		BloodFX.spawn_impact(world, mouth, Vector3.DOWN, BloodFX.BLOOD_COLOR, 3.0)
		SoundPlayer.play_3d(death_sound, mouth, world)
		_feed_corpse.queue_free()
		health.heal(feed_heal)
		_feed_corpse = null
		_end_feed()
		_set_state(State.PATROL)


func _end_feed() -> void:
	if is_instance_valid(_feed_ragdoll):
		_feed_ragdoll.carry({})
	if is_instance_valid(_feed_corpse):
		_feed_corpse.remove_meta("dragged")
	_feed_ragdoll = null
	_feed_corpse = null
	_tube_on = false
	_height_target = stand_height


# ---- Being hurt ---------------------------------------------------------------

## A part was hit: the worm-style proxy hands the damage on, times the
## part's multiplier; the sack and knees are weak spots (an artery gush),
## and a knee can break.
func _on_part_hurt(amount: float, attacker_id: int, body: AnimatableBody3D, part: String, leg: HLeg) -> void:
	var proxy := body.get_node("Health") as Health
	proxy.current_health = proxy.max_health
	if _state == State.DEAD:
		return
	var multiplier := leg_multiplier
	var weak := false
	match part:
		"sack":
			multiplier = sack_multiplier * (exposed_multiplier if _exposed > 0.0 else 1.0)
			weak = true
		"knee":
			multiplier = knee_multiplier
			weak = true
	var at := proxy.last_hit_position if proxy.last_hit_position != Vector3.ZERO else body.global_position
	HitFlash.flash(_body)
	if weak:
		_gush(body, at)
	else:
		BloodFX.spawn_impact(get_tree().current_scene, at, Vector3.UP, BloodFX.BLOOD_COLOR, 0.8)
	health.take_damage(amount * multiplier, attacker_id, Vector3.ZERO, at)
	if part == "knee" and leg and not leg.broken:
		leg.knee_hp -= amount
		if leg.knee_hp <= 0.0:
			_break_leg(leg)


func _on_hurt(_amount: float, _attacker_id: int) -> void:
	if not multiplayer.is_server() or _state == State.DEAD:
		return
	SoundPlayer.play_3d(hurt_sound, _body.global_position, get_tree().current_scene, 0.6)
	if target == null:
		# Shot by someone it hadn't seen: it turns on the nearest player.
		var nearest: Node3D = null
		var best := INF
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as Node3D
			if player and Factions.is_alive_target(player) and _flat_distance(player.global_position) < best:
				best = _flat_distance(player.global_position)
				nearest = player
		if nearest:
			target = nearest
			_last_seen = nearest.global_position
			_since_seen = 0.0
			if _state != State.ATTACK and _state != State.COLLAPSED:
				_spotted()


## A weak spot hit: blood gushing out of where it was hit, like an artery
## shot, for gush_time (each part at most every 0.4 s).
func _gush(body: AnimatableBody3D, at: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_gush_cooldowns.get(body, -10000)) < 400:
		return
	_gush_cooldowns[body] = now
	var wound := Node3D.new()
	body.add_child(wound)
	var out := (at - body.global_position)
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.UP
	var side := out.cross(Vector3.FORWARD if absf(out.z) < 0.9 else Vector3.RIGHT).normalized()
	wound.global_transform = Transform3D(Basis(side, out, side.cross(out)), at)
	BloodFX.spawn_artery_spurt(wound, gush_time)
	SoundPlayer.play_3d(GUSH_SOUND, at, get_tree().current_scene, 0.8)
	get_tree().create_timer(gush_time + 3.0).timeout.connect(wound.queue_free)


func _break_leg(leg: HLeg) -> void:
	leg.broken = true
	leg.driven = false
	leg.stepping = false
	if leg.knee_body:
		leg.knee_body.collision_layer = 0
		_gush(leg.knee_body, leg.knee_body.global_position + Vector3.UP * 0.5)
	SoundPlayer.play_3d(hurt_sound, leg.joints[leg.knee], get_tree().current_scene)
	_shake_near(leg.joints[leg.knee], 3.0, 20.0)
	if _broken_legs() >= 2 and _state != State.DEAD:
		if _state == State.ATTACK:
			_end_attack()
		_set_state(State.COLLAPSED)


func _broken_legs() -> int:
	var count := 0
	for leg in _legs:
		if leg.broken:
			count += 1
	return count


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	if _state == State.ATTACK:
		_end_attack()
	if _state == State.FEED:
		_end_feed()
	_set_state(State.DEAD)
	_dead_step = 0.0
	_drone.stop()
	for body in _bodies:
		body.collision_layer = 0


## Dying: the legs give one at a time, it comes down, the sack bursts; the
## remains lie there corpse_time.
func _die_step(delta: float) -> void:
	_dead_step -= delta
	if _dead_step <= 0.0:
		_dead_step = 0.4
		for leg in _legs:
			if not leg.broken:
				leg.broken = true
				SoundPlayer.play_3d(hurt_sound, leg.joints[leg.knee], get_tree().current_scene)
				break
	_height_target = sack_radius * 0.6
	if not _burst and _height < sack_radius * 1.1:
		_burst = true
		var at := _body.global_position
		var world := get_tree().current_scene
		for i in 5:
			var out := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
			BloodFX.spawn_impact(world, at + out * sack_radius * 0.6, out, BloodFX.BLOOD_COLOR, 4.0)
		for i in 4:
			var spot := global_position + Vector3(randf_range(-1, 1), 0.02, randf_range(-1, 1)) * sack_radius * 1.6
			BloodFX.spawn_splatter(world, spot, Vector3.UP, sack_radius * 1.8, BloodFX.BLOOD_COLOR)
		SoundPlayer.play_3d(death_sound, at, world)
		_shake_near(at, 5.0, 25.0)
		if _core:
			_core.scale = Vector3(1.15, 0.55, 1.15) # burst and slumped
			_core.set_process(false)
	if _state_time > corpse_time:
		queue_free()


# ---- Looks (every peer) -------------------------------------------------------

func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	delta = minf(delta, 0.05)
	_place_body(delta)
	_update_eyes(delta)
	_update_legs(delta)
	for leg in _legs:
		_solve_leg(leg)
	_draw_leech_legs()
	_draw_tube()
	_place_hitboxes()
	_update_sound(delta)


## The body rides its legs on a slow, heavy spring: up at its height, sinking
## as a foot lifts, leaning onto the planted feet and lagging after its own
## movement; the sack swings a beat behind that.
func _place_body(delta: float) -> void:
	var stepping := 0
	var broken := 0
	var lean := Vector3.ZERO
	for leg in _legs:
		if leg.stepping or leg.driven:
			stepping += 1
		if leg.broken:
			broken += 1
			lean += Vector3(sin(leg.angle), 0.0, -cos(leg.angle))
	var target_height := _height_target
	if _state == State.COLLAPSED:
		target_height = minf(target_height, sack_radius + 1.0)
	elif broken > 0 and _state != State.DEAD:
		target_height -= 1.5 * broken
	target_height -= stepping * 0.35
	if delta > 0.0:
		_height_vel += (6.0 * (target_height - _height) - 3.0 * _height_vel) * delta
		_height += _height_vel * delta
	var facing := Basis(Vector3.UP, _yaw)
	var noise := Vector3(sin(_time * 0.7) * 0.5 + sin(_time * 1.9) * 0.2, 0.0, cos(_time * 0.6) * 0.5) * body_sway
	var want := facing * (lean * -0.8) + noise
	if delta > 0.0:
		_sway_vel += (4.0 * (want - _sway) - 2.5 * _sway_vel) * delta
		_sway += _sway_vel * delta
	var at := global_position + Vector3.UP * _height + _sway
	if delta > 0.0:
		var velocity := (at - _last_body) / delta
		var accel := (velocity - _body_velocity) / delta
		_body_velocity = velocity
		var lag_target := Vector2(clampf(accel.z * 0.05, -0.4, 0.4), clampf(-accel.x * 0.05, -0.4, 0.4)) * body_sway * 3.0
		_sack_lag_vel += (8.0 * (lag_target - _sack_lag) - 2.0 * _sack_lag_vel) * delta
		_sack_lag += _sack_lag_vel * delta
	_last_body = at
	var tilt := Basis(Vector3.RIGHT, _sway.z * 0.06) * Basis(Vector3.BACK, -_sway.x * 0.06)
	_body.global_transform = Transform3D(facing * tilt, at)
	if _core:
		_core.rotation = Vector3(_sack_lag.x, 0.0, _sack_lag.y)


## Where its eyes (and searchlight) look: at you when hunting; sweeping
## round, down and ahead, otherwise.
func _update_eyes(delta: float) -> void:
	var facing := Basis(Vector3.UP, _yaw)
	var want: Vector3
	if is_instance_valid(target) and (_state == State.HUNT or _state == State.ATTACK or _state == State.COLLAPSED):
		var eyes := _face.global_position if _face else _body.global_position
		want = (Factions.aim_point(target) - eyes).normalized()
	else:
		var sweep := sin(_time * (0.9 if _state == State.LISTEN else 0.4)) * deg_to_rad(65.0)
		want = facing * (Basis(Vector3.UP, sweep) * Basis(Vector3.RIGHT, deg_to_rad(-25.0)) * Vector3.FORWARD)
	_eye_dir = _eye_dir.slerp(want, 1.0 - exp(-3.0 * delta)).normalized()
	if _face and _eye_dir.length_squared() > 0.01:
		_face.global_basis = Basis.looking_at(_eye_dir, Vector3.UP if absf(_eye_dir.y) < 0.98 else Vector3.FORWARD)
	if _light:
		_light.visible = _state != State.DEAD
	_aim_beam(delta)


## Feet: one leg steps at a time, round and round, each lifting high and
## coming straight down soft; an attack drives its leg's foot; a broken leg
## drags; dying, they splay.
func _update_legs(delta: float) -> void:
	var ground := Transform3D(Basis(Vector3.UP, _yaw), global_position)
	var lead := Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * _speed * step_time
	var any_stepping := false
	for leg in _legs:
		if leg.stepping:
			any_stepping = true
	for i in _legs.size():
		var leg := _legs[i]
		var home := ground * (Vector3(sin(leg.angle), 0.0, -cos(leg.angle)) * foot_radius)
		if leg.driven:
			leg.foot = leg.foot.lerp(leg.drive_to, 1.0 - exp(-14.0 * delta))
			continue
		if leg.broken:
			# Limp: the foot slides along the floor toward under the hip.
			var under := ground * (Vector3(sin(leg.angle), 0.0, -cos(leg.angle)) * foot_radius * (0.5 if _state != State.DEAD else 1.3))
			leg.planted = leg.planted.move_toward(Vector3(under.x, leg.planted.y, under.z), delta * 1.5)
			leg.foot = leg.planted
			continue
		if leg.stepping:
			leg.step_t += delta / leg.step_duration
			if leg.step_t >= 1.0:
				leg.stepping = false
				leg.planted = leg.step_to
				leg.foot = leg.planted
				_landed(leg)
			else:
				var t := leg.step_t
				var across := smoothstep(0.0, 0.75, t)
				var lift := sin(minf(t / 0.75, 1.0) * PI * 0.5) if t < 0.75 else 1.0 - smoothstep(0.75, 1.0, t)
				leg.foot = leg.step_from.lerp(leg.step_to, across) + Vector3.UP * step_lift * lift
			continue
		if leg.slip_left > 0.0:
			leg.slip_left -= delta
			leg.planted += leg.slip_dir * delta * 3.0
		leg.foot = leg.planted
		var off := Vector2(leg.planted.x - home.x - lead.x, leg.planted.z - home.z - lead.z).length()
		if off > stride * 3.0:
			leg.planted = _foot_spot(home + lead)
			leg.foot = leg.planted
		elif off > stride and not any_stepping and (i == _next_leg or off > stride * 1.8):
			leg.stepping = true
			any_stepping = true
			leg.step_t = 0.0
			leg.step_duration = step_time * randf_range(0.9, 1.15)
			leg.step_from = leg.planted
			leg.step_to = _foot_spot(home + lead)
			_next_leg = (i + 1) % _legs.size()


## A foot comes down: a quiet wet tap, anything small under it squashed,
## and now and then it slips and the body lurches.
func _landed(leg: HLeg) -> void:
	SoundPlayer.play_3d(step_sound, leg.foot, get_tree().current_scene, 0.6)
	if randf() < slip_chance:
		leg.slip_left = 0.25
		leg.slip_dir = Vector3(leg.foot.x - global_position.x, 0.0, leg.foot.z - global_position.z).normalized()
		_sway_vel += -leg.slip_dir * 2.5
		_height_vel -= 2.0
		BloodFX.spawn_impact(get_tree().current_scene, leg.foot, Vector3.UP, SEWAGE_COLOR, 0.8)
	if multiplayer.is_server() and squash_damage > 0.0:
		for body in _bodies_near(leg.foot + Vector3.UP * 0.4, 0.9):
			if body is PlayerMovement:
				continue
			var body_health := body.get_node_or_null("Health") as Health
			if body_health and not body_health.is_dead:
				body_health.take_damage(squash_damage, Health.NO_ATTACKER, Vector3.DOWN, leg.foot, 1.0)


func _plant_all() -> void:
	var ground := Transform3D(Basis(Vector3.UP, _yaw), global_position)
	for leg in _legs:
		leg.planted = _foot_spot(ground * (Vector3(sin(leg.angle), 0.0, -cos(leg.angle)) * foot_radius))
		leg.foot = leg.planted


## The floor under a spot (one ray), or the spot.
func _foot_spot(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point + Vector3.DOWN * 6.0)
	query.collision_mask = 1
	var hit := _static_hit(get_world_3d().direct_space_state, query)
	return hit.position if not hit.is_empty() else point


## The leg's joints reaching from its hip to its foot: an arch up and out to
## start from (so the knee always bends up, harvestman-high), then FABRIK.
## Spider legs: each bone turned onto its new direction.
func _solve_leg(leg: HLeg) -> void:
	var hip := leg.node.global_position
	if leg.skeleton:
		hip = leg.skeleton.global_transform * (leg.body_rest * leg.rest_local[0]).origin
	var foot := leg.foot
	var count := leg.lengths.size()
	var total := 0.0
	for length in leg.lengths:
		total += length
	var out := Vector3(foot.x - hip.x, 0.0, foot.z - hip.z)
	out = out.normalized() if out.length_squared() > 0.01 else Vector3(sin(leg.angle), 0.0, -cos(leg.angle))
	var bend := (Vector3.UP + out * 0.35).normalized()
	var joints := leg.joints
	joints[0] = hip
	var run := 0.0
	for i in count:
		run += leg.lengths[i]
		var f := run / total
		joints[i + 1] = hip.lerp(foot, f) + bend * sin(f * PI) * total * 0.5
	if hip.distance_to(foot) >= total:
		var straight := (foot - hip).normalized()
		for i in count:
			joints[i + 1] = joints[i] + straight * leg.lengths[i]
	else:
		for iteration in 6:
			joints[count] = foot
			for i in range(count - 1, -1, -1):
				joints[i] = joints[i + 1] + (joints[i] - joints[i + 1]).normalized() * leg.lengths[i]
			joints[0] = hip
			for i in count:
				joints[i + 1] = joints[i] + (joints[i + 1] - joints[i]).normalized() * leg.lengths[i]
	leg.joints = joints
	if leg.skeleton == null:
		return
	var to_skeleton := leg.skeleton.global_transform.affine_inverse()
	var parent := leg.body_rest
	for i in leg.bones.size():
		var current := parent * leg.rest_local[i]
		var was := current.basis * leg.child_offset[i]
		var wants := to_skeleton * joints[i + 1] - current.origin
		if was.length_squared() < 0.0000001 or wants.length_squared() < 0.0000001:
			parent = current
			continue
		var turned := Basis(Quaternion(was.normalized(), wants.normalized())) * current.basis
		leg.skeleton.set_bone_pose_rotation(leg.bones[i], (parent.basis.inverse() * turned).get_rotation_quaternion())
		parent = Transform3D(turned, current.origin)


## Leech legs: tape-worm segments laid along each leg's joints, thick at the
## hip, thin at the foot; the barnacle knee on the knee.
func _draw_leech_legs() -> void:
	if _leech_mm == null:
		return
	var multimesh := _leech_mm.multimesh
	var index := 0
	for leg in _legs:
		if leg.skeleton:
			continue
		if leg.lump:
			leg.lump.global_position = leg.joints[leg.knee]
		_lay_segments(multimesh, index, LEECH_SEGMENTS, leg.joints, 0.42, 0.12)
		index += LEECH_SEGMENTS


## The feeding tube / hose: a thin tape-worm tube from its mouth to the end,
## sagging a little; tucked away when not in use.
func _draw_tube() -> void:
	if _tube_mm == null or _mouth == null:
		return
	if not _tube_on:
		if _tube_mm.visible:
			_tube_mm.visible = false
		return
	_tube_mm.visible = true
	var start := _mouth.global_position
	var middle := start.lerp(_tube_end, 0.5) + Vector3.DOWN * 0.6
	_lay_segments(_tube_mm.multimesh, 0, 8, PackedVector3Array([start, middle, _tube_end]), 0.16, 0.1)


## `count` segments evenly along the path through `points`, from instance
## `first` on, tapering from `thick` to `thin`.
func _lay_segments(multimesh: MultiMesh, first: int, count: int, points: PackedVector3Array, thick: float, thin: float) -> void:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	if total < 0.01:
		return
	var piece := total / count
	for k in count:
		var a := _along(points, piece * k)
		var b := _along(points, piece * (k + 1))
		var dir := b - a
		if dir.length_squared() < 0.000001:
			continue
		var radius := lerpf(thick, thin, float(k) / count)
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD)
		basis = basis * Basis(Vector3.BACK, k * 0.3) * Basis.from_scale(Vector3(radius, radius, piece * 1.35 / SEGMENT_MESH_LENGTH))
		multimesh.set_instance_transform(first + k, Transform3D(basis, (a + b) * 0.5))


## The point `distance` along the path through `points`.
func _along(points: PackedVector3Array, distance: float) -> Vector3:
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if distance <= length or i == points.size() - 2:
			return points[i].lerp(points[i + 1], clampf(distance / maxf(length, 0.0001), 0.0, 1.0))
		distance -= length
	return points[-1]


func _place_hitboxes() -> void:
	if _sack_body:
		_sack_body.global_transform = Transform3D(Basis.IDENTITY, _body.global_position)
	for leg in _legs:
		if leg.knee_body:
			leg.knee_body.global_transform = Transform3D(Basis.IDENTITY, leg.joints[leg.knee])
		for i in leg.shafts.size():
			var a := leg.joints[i]
			var b := leg.joints[i + 1]
			var up := (b - a).normalized()
			if up.length_squared() < 0.01:
				continue
			var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
			leg.shafts[i].global_transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)


## The drone: always there, rising and quickening when it hunts; close up,
## it warps down and the camera sways (close-up horror, local player only).
func _update_sound(delta: float) -> void:
	if _drone == null or _state == State.DEAD:
		return
	var hunting := _state == State.HUNT or _state == State.ATTACK or _state == State.COLLAPSED
	var pitch := drone_hunt_pitch if hunting else drone_pitch
	var player := PlayerMovement.local_player(get_tree())
	if player:
		var distance := _flat_distance(player.global_position)
		if distance < horror_range:
			var closeness := 1.0 - distance / horror_range
			pitch = lerpf(pitch, 1.1, closeness * 0.7)
			_horror_left -= delta
			if _horror_left <= 0.0:
				_horror_left = 0.4
				if player.get("camera") is CameraJuice:
					(player.get("camera") as CameraJuice).shake(0.6 * closeness)
	_drone.pitch_scale = lerpf(_drone.pitch_scale, pitch, 1.0 - exp(-2.0 * delta))
	_drone.volume_db = lerpf(_drone.volume_db, drone_volume_db + (4.0 if hunting else 0.0), 1.0 - exp(-2.0 * delta))
	_drone.global_position = _body.global_position


func _shake_near(at: Vector3, strength: float, within: float) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		var distance := player.global_position.distance_to(at)
		if distance < within and player.get("camera") is CameraJuice:
			(player.get("camera") as CameraJuice).shake(strength * (1.0 - distance / within))
