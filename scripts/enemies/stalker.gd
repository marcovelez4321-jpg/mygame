class_name Stalker
extends AnimatableBody3D

## The Stalker (the user's, 2026-10-17; docs/CLIMB_VISION.md): one of a kind,
## a human gone wrong (the PSX pack's Character_Monster_03) crawling on all
## fours -- on floors, walls and ceilings, stuck to them the spider's way (a
## ray ahead climbs it onto what's in front, a ray down keeps it on, a ray
## back under an edge wraps it round the corner; nothing there: it falls).
## STAGE 1 (this file): the crawler, its body, and the rules that hold it:
##   It always knows roughly where you are (Alien: Isolation) and stalks at
##   STALK_DISTANCE -- out of sight.
##   LOOKED AT, IT HIDES: the moment any player could see any of it, it
##   freezes (SPOTTED_FREEZE), staring, then scrambles (SCRAMBLE: slow enough
##   to watch it skitter off) to a spot none of them can see, and waits there.
##   DRIVEN OFF, NEVER KILLED: DRIVE_OFF damage and it flees and is gone,
##   back AWAY_TIME later.
##   Everyone far off (RELOCATE_FAR): it turns up again out of sight, nearer.
## Stunts, the fear meter and the strike come next (stages 2-3).
## Its body (every screen): two-bone IK on each arm and leg, planted hands
## and feet stepping in diagonal pairs -- jerky, broken-jointed (The Grudge)
## -- the spine riding them on a spring, and the head locked on you, tilted
## wrong, now and then snapping to a new tilt.
## Rule 1 (co-op): the host runs it; everyone else sees its puppet
## (NetEntities: its transform carries the surface it's on), and works the
## body out from that.

enum State { STALK, SPOTTED, HIDE, WAIT, FALL, FLEE, AWAY }

const MODEL := preload("res://art/characters/Characters_psx/Models/Killers/Character_Monster_03.fbx")
## Speeds (the user's): crawling, scrambling away to hide when it's looked
## at (slow enough to watch it skitter out of view), sprinting (driven off).
## Spotted, it first freezes SPOTTED_FREEZE s, staring, then scrambles.
const CRAWL := 9.0
const SCRAMBLE := 13.0
const SPRINT := 18.0
const SPOTTED_FREEZE := 0.8
const ACCELERATION := 30.0
const STALK_DISTANCE := 30.0
## Looked at within this cone (degrees off where a player looks) with a clear
## line to any of it: seen.
const VIEW_CONE := 55.0
const SEEN_RANGE := 160.0
## Hidden this long after hiding, it stalks again.
const WAIT_TIME := 1.5
## Driven off (the user's): this much damage, then gone for AWAY_TIME s.
const DRIVE_OFF := 200.0
const AWAY_TIME := Vector2(300.0, 480.0)
const FLEE_TIME := 4.0
## Everyone further than this for RELOCATE_AFTER s: it turns up again,
## hidden, RELOCATE_TO from one of them.
const RELOCATE_FAR := 280.0
const RELOCATE_AFTER := 5.0
const RELOCATE_TO := Vector2(55.0, 85.0)
const WALL_DOT := 0.7
const RIDE := 0.25
const SPAN := 1.6
const GRAVITY := 22.0
const AWAY_DEPTH := -5000.0
## The body (looks): how high the spine rides, the hands' and feet's spots
## round it, how far one strays before it steps, how high and how fast.
const BODY_HEIGHT := 0.6
const STRIDE := 0.5
const STEP_HEIGHT := 0.28
const STEP_TIME := 0.32
const STANDING_HEIGHT := 1.9

var state := State.STALK
var _normal := Vector3.UP
var _velocity := Vector3.ZERO
var _heading := Vector3.FORWARD
var _desired := Vector3.ZERO
var _hide_to := Vector3.INF
var _state_left := 0.0
var _hurt := 0.0
var _far_for := 0.0
var _look_check := 0.0
var _health: Health

# Looks.
var _visual: Node3D
var _pivot: Node3D
var _model: Node3D
var _skeleton: Skeleton3D
var _bones := {}
var _limbs: Array[Dictionary] = []
var _last_position := Vector3.ZERO
var _smooth_velocity := Vector3.ZERO
var _time := 0.0
var _tilt := 0.0
var _tilt_target := 0.0
var _tilt_left := 0.0
var _body_y := 0.0
var _body_pitch := 0.0
var _body_roll := 0.0


## The one Stalker (the host's): made once, near the players but hidden.
static func ensure(tree: SceneTree) -> void:
	if not tree.get_nodes_in_group("stalker").is_empty():
		return
	var stalker := Stalker.new()
	stalker.name = "Stalker"
	tree.current_scene.add_child(stalker)
	stalker.global_position = Vector3(0.0, AWAY_DEPTH, 0.0)
	stalker.state = State.AWAY
	stalker._state_left = 0.5 # turns up straight away, somewhere out of sight


func _ready() -> void:
	add_to_group("stalker")
	add_to_group(NetEntities.GROUP)
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = SPAN
	shape.shape = capsule
	shape.rotation.x = PI * 0.5 # lying along its length
	shape.position = Vector3.UP * BODY_HEIGHT
	add_child(shape)
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = 1000000.0
	add_child(_health)
	_health.damaged.connect(_on_damaged)
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D)
	_build_body()
	_last_position = global_position


# ---- Co-op (NetEntities: a script-made one) ------------------------------------------

func net_spawn_args() -> Dictionary:
	return {}


func net_restore(_data: Dictionary) -> void:
	pass


# ---- Host: the brain ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	_state_left -= delta
	match state:
		State.AWAY:
			if _state_left <= 0.0:
				_turn_up()
			return
		State.FLEE:
			_desired = _away_from_players() * SPRINT
			if _state_left <= 0.0:
				_go_away()
				return
		_:
			_think(delta)
	if state == State.FALL:
		_fall(delta)
	else:
		_crawl(delta)
	_face()


func _think(delta: float) -> void:
	# Seen? Hide, at once (a stunt aside, later).
	_look_check -= delta
	if _look_check <= 0.0:
		_look_check = 0.1
		if _seen() and state != State.HIDE and state != State.SPOTTED:
			state = State.SPOTTED
			_state_left = SPOTTED_FREEZE
	var nearest := _nearest_player()
	if nearest == null:
		_desired = Vector3.ZERO
		return
	var distance := nearest.global_position.distance_to(global_position)
	# Everyone's far off: turn up again somewhere nearer, unseen.
	_far_for = _far_for + delta if distance > RELOCATE_FAR else 0.0
	if _far_for > RELOCATE_AFTER:
		_far_for = 0.0
		_turn_up()
		return
	match state:
		State.SPOTTED:
			# Dead still a beat, staring back -- then it scrambles off.
			_desired = Vector3.ZERO
			_velocity = Vector3.ZERO
			if _state_left <= 0.0:
				_hide_to = _hiding_spot()
				state = State.HIDE
		State.HIDE:
			if not _hide_to.is_finite() or global_position.distance_to(_hide_to) < 1.5:
				state = State.WAIT
				_state_left = WAIT_TIME
				_desired = Vector3.ZERO
			else:
				_desired = (_hide_to - global_position).normalized() * SCRAMBLE
		State.WAIT:
			_desired = Vector3.ZERO
			if _state_left <= 0.0:
				state = State.STALK
		State.STALK:
			# Round to a spot STALK_DISTANCE from them, on the side it's on.
			var away := global_position - nearest.global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
			var spot := nearest.global_position + away * STALK_DISTANCE
			var to := spot - global_position
			_desired = to.normalized() * CRAWL * clampf(to.length() / 4.0, 0.0, 1.0) if to.length() > 2.0 else Vector3.ZERO


func _nearest_player() -> PlayerMovement:
	var best: PlayerMovement = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var distance := player.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## Points over its body: head, hips, the hands and feet's spots.
func _body_points(at: Vector3, basis: Basis) -> Array[Vector3]:
	var up := basis.y * BODY_HEIGHT
	var forward := -basis.z * SPAN * 0.5
	var side := basis.x * 0.5
	return [at + up + forward, at + up - forward, at + up * 0.3 + forward + side, at + up * 0.3 + forward - side,
			at + up * 0.3 - forward + side, at + up * 0.3 - forward - side]


## Whether any player could see any part of it right now.
func _seen() -> bool:
	return _visible_from_any(_body_points(global_position, global_basis))


func _visible_from_any(points: Array[Vector3]) -> bool:
	var cone := cos(deg_to_rad(VIEW_CONE))
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead():
			continue
		var eye := player.head.global_position
		var look := -player.head.global_basis.z
		for point in points:
			var to := point - eye
			var distance := to.length()
			if distance > SEEN_RANGE or look.dot(to / maxf(distance, 0.001)) < cone:
				continue
			var query := PhysicsRayQueryParameters3D.create(eye, point, 1, [player.get_rid(), get_rid()])
			var hit := space.intersect_ray(query)
			if hit.is_empty() or (hit.position as Vector3).distance_to(point) < 0.3:
				return true
	return false


## Somewhere near none of them can see (any of it): round it on its surface,
## the nearest such spot that isn't toward them; straight away from them if
## there's none.
func _hiding_spot() -> Vector3:
	var best := Vector3.INF
	var best_score := INF
	var space := get_world_3d().direct_space_state
	var players := get_tree().get_nodes_in_group("player")
	for ring: float in [6.0, 12.0, 20.0, 30.0]:
		for i in 12:
			var way := _flat_perpendicular(_normal, Vector3.FORWARD.rotated(_normal, TAU * i / 12.0 + randf() * 0.4))
			var spot := global_position + way * ring
			var stick := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + _normal * 3.0, spot - _normal * 6.0, 1, [get_rid()]))
			if stick.is_empty():
				continue
			spot = stick.position
			var frame := Basis(way.cross(_normal), _normal, -way)
			if _visible_from_any(_body_points(spot, frame)):
				continue
			var score := ring
			for node in players:
				var player := node as Node3D
				if player.global_position.distance_to(spot) < player.global_position.distance_to(global_position):
					score += 15.0 # (not toward them)
			if score < best_score:
				best_score = score
				best = spot
		if best.is_finite():
			return best
	return global_position + _away_from_players() * 25.0


func _away_from_players() -> Vector3:
	var away := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("player"):
		var from := global_position - (node as Node3D).global_position
		away += from.normalized() / maxf(from.length(), 1.0)
	return _flat_perpendicular(_normal, away if away.length_squared() > 0.0001 else -global_basis.z)


func _on_damaged(amount: float, _attacker: int) -> void:
	_health.current_health = _health.max_health # never killed
	if state == State.FLEE or state == State.AWAY:
		return
	_hurt += amount
	if _hurt >= DRIVE_OFF:
		state = State.FLEE
		_state_left = FLEE_TIME
	elif state == State.STALK or state == State.WAIT:
		_hide_to = _hiding_spot()
		state = State.HIDE


## Gone for a while (driven off): out of the world entirely.
func _go_away() -> void:
	state = State.AWAY
	_state_left = randf_range(AWAY_TIME.x, AWAY_TIME.y)
	_hurt = 0.0
	_velocity = Vector3.ZERO
	global_position = Vector3(global_position.x, AWAY_DEPTH, global_position.z)


## Back, somewhere out of sight RELOCATE_TO from one of the players (behind
## them, on the ground).
func _turn_up() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_state_left = 2.0
		return
	var player := players[randi() % players.size()] as PlayerMovement
	var space := get_world_3d().direct_space_state
	for attempt in 16:
		var behind := player.head.global_basis.z.rotated(Vector3.UP, randf_range(-1.2, 1.2))
		behind.y = 0.0
		var spot := player.global_position + behind.normalized() * randf_range(RELOCATE_TO.x, RELOCATE_TO.y)
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 300.0, spot + Vector3.DOWN * 400.0, 1, [get_rid()]))
		if ground.is_empty():
			continue
		var at: Vector3 = ground.position
		_normal = ground.normal
		if _visible_from_any(_body_points(at, Basis.IDENTITY)):
			continue
		global_position = at + _normal * RIDE
		_velocity = Vector3.ZERO
		state = State.WAIT
		_state_left = WAIT_TIME
		return
	_state_left = 2.0 # nowhere hidden yet: try again shortly


# ---- Host: crawling (the spider's way) -----------------------------------------------

func _crawl(delta: float) -> void:
	var up := _normal
	var wanted := _desired - up * _desired.dot(up)
	var into := -_desired.dot(up)
	if into > 0.0 and absf(up.y) < WALL_DOT:
		wanted += _flat_perpendicular(up, Vector3.UP) * into # on a wall, through it: up and over
	_velocity = (_velocity - up * _velocity.dot(up)).move_toward(wanted, ACCELERATION * delta)
	var step := _velocity * delta
	var step_length := step.length()
	var direction := step / step_length if step_length > 0.0001 else _heading
	if step_length > 0.0001:
		_heading = direction
		var ahead := _ray(global_position, global_position + direction * (step_length + RIDE * 1.3))
		if not ahead.is_empty() and (ahead.normal as Vector3).dot(up) < WALL_DOT:
			_set_surface(ahead.normal, up * _velocity.length()) # a wall in front: onto it
			global_position = (ahead.position as Vector3) + _normal * RIDE
			return
		global_position += step
	var down := _ray(global_position + up * RIDE * 0.5, global_position - up * (RIDE + 0.6 * SPAN))
	if not down.is_empty():
		_set_surface(down.normal, _velocity)
		global_position = (down.position as Vector3) + _normal * RIDE
		return
	var under := global_position - up * (RIDE + 0.25 * SPAN)
	var back := _ray(under, under - direction * (step_length + RIDE * 2.0 + 0.1))
	if not back.is_empty() and (back.normal as Vector3).dot(up) < WALL_DOT:
		_set_surface(back.normal, -up * _velocity.length()) # round the edge
		global_position = (back.position as Vector3) + _normal * RIDE
		return
	state = State.FALL


func _fall(delta: float) -> void:
	_velocity += Vector3.DOWN * GRAVITY * delta
	var step := _velocity * delta
	var hit := _ray(global_position, global_position + step * 1.2)
	if not hit.is_empty():
		_set_surface(hit.normal, _velocity)
		global_position = (hit.position as Vector3) + _normal * RIDE
		state = State.STALK
		return
	global_position += step
	if global_position.y < -400.0:
		_turn_up()


func _set_surface(normal: Vector3, velocity: Vector3) -> void:
	_normal = normal.normalized()
	var along := velocity - _normal * velocity.dot(_normal)
	_velocity = along.normalized() * velocity.length() if along.length_squared() > 0.0001 else Vector3.ZERO
	_heading = _flat_perpendicular(_normal, _heading)


## Its body turned to its surface, facing where it's going -- carried to
## everyone in its transform.
func _face() -> void:
	var forward := _flat_perpendicular(_normal, _heading)
	var target := Basis(forward.cross(_normal), _normal, -forward).orthonormalized()
	global_basis = global_basis.orthonormalized().slerp(target, 0.25).orthonormalized()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var exclude: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var collider = hit.collider
		if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D or collider is PhysicalBone3D:
			exclude.append(hit.rid)
			continue
		return hit
	return {}


static func _flat_perpendicular(normal: Vector3, direction: Vector3) -> Vector3:
	var flat := direction - normal * direction.dot(normal)
	if flat.length_squared() < 0.0001:
		flat = normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD)
	return flat.normalized()


# ---- Looks (every screen) ----------------------------------------------------------

## The model laid flat on all fours (a Mixamo rig stands up +Y facing +Z:
## turned chest-down, head forward to -Z), sized to a person, its spine at
## BODY_HEIGHT; the limbs' bones found by name, each hand's and foot's spot.
func _build_body() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.top_level = true
	add_child(_visual)
	_visual.global_transform = global_transform
	_pivot = Node3D.new()
	_visual.add_child(_pivot)
	_model = MODEL.instantiate() as Node3D
	_pivot.add_child(_model)
	for node in _model.find_children("*", "AnimationPlayer", true, false):
		(node as AnimationPlayer).stop()
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Stalker: no skeleton in the model.")
		return
	_skeleton = skeletons[0] as Skeleton3D
	for key: String in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
			"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		_bones[key] = _find_bone(key)
	# Standing height to a person's, then laid down chest-first.
	var bounds := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var fit := STANDING_HEIGHT / maxf(bounds.size.y, 0.01)
	_model.basis = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * fit)
	_model.position = Vector3.ZERO
	# Its spine (hips to neck) level at BODY_HEIGHT, centred.
	var hips := _bone_in_visual(_bones.Hips)
	var neck := _bone_in_visual(_bones.Neck)
	var middle := (hips + neck) * 0.5
	_model.position = Vector3(-middle.x, BODY_HEIGHT - middle.y, -middle.z)
	# The hands' and feet's spots, round the shoulders and hips, on the ground.
	var limbs := [["LeftArm", "LeftForeArm", "LeftHand", 0, true], ["RightArm", "RightForeArm", "RightHand", 1, true],
			["LeftUpLeg", "LeftLeg", "LeftFoot", 1, false], ["RightUpLeg", "RightLeg", "RightFoot", 0, false]]
	for spec: Array in limbs:
		var upper: int = _bones[spec[0]]
		var lower: int = _bones[spec[1]]
		var end: int = _bones[spec[2]]
		if upper < 0 or lower < 0 or end < 0:
			continue
		var root := _bone_in_visual(upper)
		var arm: bool = spec[4]
		var out := signf(root.x) if absf(root.x) > 0.01 else (-1.0 if (spec[0] as String).begins_with("Left") else 1.0)
		var home := Vector3(root.x + out * (0.35 if arm else 0.25), 0.0, root.z + (-0.3 if arm else 0.25))
		_limbs.append({upper = upper, lower = lower, end = end, group = spec[3], arm = arm, out = out, home = home,
				planted = _visual.global_transform * home, foot = _visual.global_transform * home,
				stepping = false, t = 0.0, from = Vector3.ZERO, to = Vector3.ZERO})


func _find_bone(key: String) -> int:
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if bone_name == key or bone_name.ends_with(":" + key) or bone_name.ends_with("_" + key):
			return i
	return -1


## A bone's rest position in the Visual's space.
func _bone_in_visual(bone: int) -> Vector3:
	if bone < 0:
		return Vector3.ZERO
	var world := _skeleton.global_transform * _skeleton.get_bone_global_rest(bone).origin
	return _visual.global_transform.affine_inverse() * world


func _process(delta: float) -> void:
	if _skeleton == null:
		return
	_time += delta
	# The look follows the body (smoothly: a puppet's moves in steps).
	_visual.global_transform = _visual.global_transform.interpolate_with(global_transform, 1.0 - exp(-14.0 * delta))
	var hidden := global_position.y < AWAY_DEPTH * 0.5
	_visual.visible = not hidden
	if hidden:
		return
	var moved := (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if moved.length() < 60.0:
		_smooth_velocity = _smooth_velocity.lerp(moved, 1.0 - exp(-15.0 * delta))
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(global_position) > 90.0:
		return # too far to make out its limbs
	_update_limbs(delta)
	_update_spine(delta)
	_reset_pose()
	for limb in _limbs:
		_two_bone(limb)
	_aim_head(delta, camera)


## Hands and feet: planted till the body's carried them too far, then a step
## -- one diagonal pair at a time, in jerks (The Grudge: broken joints).
func _update_limbs(delta: float) -> void:
	var xf := _visual.global_transform
	var up := xf.basis.y.normalized()
	var lead := _smooth_velocity * 0.12
	var busy := [false, false]
	for limb in _limbs:
		if limb.stepping:
			busy[limb.group] = true
	for limb in _limbs:
		var want: Vector3 = xf * limb.home + lead
		if limb.stepping:
			limb.t += delta / STEP_TIME
			if limb.t >= 1.0:
				limb.stepping = false
				limb.planted = limb.to
				limb.foot = limb.planted
			else:
				# In jerks: three snatches, each with a catch at its end.
				var t: float = limb.t
				var piece := floorf(t * 3.0)
				var within := clampf((t * 3.0 - piece) / 0.6, 0.0, 1.0)
				var jerked := (piece + within * within * (3.0 - 2.0 * within)) / 3.0
				limb.foot = (limb.from as Vector3).lerp(limb.to, jerked) + up * sin(jerked * PI) * STEP_HEIGHT
			continue
		var off := (limb.planted as Vector3).distance_to(want)
		if off > STRIDE * 3.0:
			limb.planted = _ground_under(want, up)
			limb.foot = limb.planted
		elif off > STRIDE and not busy[1 - int(limb.group)]:
			limb.stepping = true
			busy[limb.group] = true
			limb.t = 0.0
			limb.from = limb.planted
			limb.to = _ground_under(want + lead, up)


func _ground_under(point: Vector3, up: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + up * 0.8, point - up * 1.2, 1, [get_rid()]))
	return hit.position if not hit.is_empty() else point


## The spine settles to the hands' and feet's heights and tilt, on a spring.
func _update_spine(delta: float) -> void:
	if _limbs.size() < 4:
		return
	var to_local := _visual.global_transform.affine_inverse()
	var front := 0.0
	var back := 0.0
	var left := 0.0
	var right := 0.0
	for limb in _limbs:
		var y := (to_local * (limb.foot as Vector3)).y
		if limb.arm:
			front += y * 0.5
		else:
			back += y * 0.5
		if limb.out < 0.0:
			left += y * 0.5
		else:
			right += y * 0.5
	var follow := 1.0 - exp(-8.0 * delta)
	_body_y = lerpf(_body_y, (front + back) * 0.5, follow)
	_body_pitch = lerpf(_body_pitch, atan2(front - back, SPAN * 0.7), follow)
	_body_roll = lerpf(_body_roll, atan2(right - left, 0.8), follow)
	_pivot.position = Vector3(0.0, _body_y + sin(_time * 1.7) * 0.015, 0.0)
	_pivot.basis = Basis.from_euler(Vector3(_body_pitch, 0.0, -_body_roll))


func _reset_pose() -> void:
	for limb in _limbs:
		for bone: int in [limb.upper, limb.lower]:
			_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())


## One arm or leg: the upper bone turned so the elbow/knee lands where the
## two lengths meet (bent up and out, spider-wise), then the lower one so its
## end lands on the hand's or foot's spot.
func _two_bone(limb: Dictionary) -> void:
	var to_skeleton := _skeleton.global_transform.affine_inverse()
	var target: Vector3 = to_skeleton * (limb.foot as Vector3)
	var a := _skeleton.get_bone_global_pose(limb.upper).origin
	var b := _skeleton.get_bone_global_pose(limb.lower).origin
	var c := _skeleton.get_bone_global_pose(limb.end).origin
	var len1 := a.distance_to(b)
	var len2 := b.distance_to(c)
	if len1 < 0.0001 or len2 < 0.0001:
		return
	var reach := clampf(a.distance_to(target), 0.05, (len1 + len2) * 0.999)
	var dir := (target - a).normalized()
	# The bend: up (off the surface) and out to its side, a little back for a
	# knee, forward for an elbow.
	var up_sk := (to_skeleton.basis * _visual.global_basis.y).normalized()
	var side_sk := (to_skeleton.basis * _visual.global_basis.x).normalized() * float(limb.out)
	var fwd_sk := (to_skeleton.basis * -_visual.global_basis.z).normalized()
	var pole := up_sk * 1.0 + side_sk * 0.8 + fwd_sk * (-0.3 if limb.arm else 0.3)
	pole = (pole - dir * pole.dot(dir))
	if pole.length_squared() < 0.0001:
		pole = up_sk
	pole = pole.normalized()
	var cos_a := clampf((len1 * len1 + reach * reach - len2 * len2) / (2.0 * len1 * reach), -1.0, 1.0)
	var elbow := a + dir * len1 * cos_a + pole * len1 * sqrt(1.0 - cos_a * cos_a)
	_turn_bone(limb.upper, b - a, elbow - a)
	var b2 := _skeleton.get_bone_global_pose(limb.lower).origin
	var c2 := _skeleton.get_bone_global_pose(limb.end).origin
	_turn_bone(limb.lower, c2 - b2, (a + dir * reach) - b2)


## A bone rotated (in skeleton space) so `was` points along `wants`.
func _turn_bone(bone: int, was: Vector3, wants: Vector3) -> void:
	if was.length_squared() < 0.000001 or wants.length_squared() < 0.000001:
		return
	var global := _skeleton.get_bone_global_pose(bone)
	var turned := Basis(Quaternion(was.normalized(), wants.normalized())) * global.basis
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())


## The head locked on the nearest player (yours, on your screen), tilted
## wrong, now and then snapping to a new tilt (The Grudge).
func _aim_head(delta: float, camera: Camera3D) -> void:
	var head: int = _bones.get("Head", -1)
	if head < 0 or camera == null:
		return
	_tilt_left -= delta
	if _tilt_left <= 0.0:
		_tilt_left = randf_range(2.0, 5.0)
		_tilt_target = randf_range(0.4, 1.1) * (1.0 if randf() < 0.5 else -1.0)
	_tilt = move_toward(_tilt, _tilt_target, delta * 12.0) # a snap, not a turn
	_skeleton.set_bone_pose_rotation(head, _skeleton.get_bone_rest(head).basis.get_rotation_quaternion())
	var to_skeleton := _skeleton.global_transform.affine_inverse()
	var pose := _skeleton.get_bone_global_pose(head)
	var face := pose.basis.z.normalized()
	var wants := ((to_skeleton * camera.global_position) - pose.origin).normalized()
	var angle := face.angle_to(wants)
	if angle > 0.001:
		var axis := face.cross(wants).normalized()
		var turn := Basis(axis, minf(angle, deg_to_rad(80.0)))
		var turned := Basis(wants, _tilt) * turn * pose.basis
		var parent := _skeleton.get_bone_parent(head)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_rotation(head, (parent_basis.inverse() * turned).get_rotation_quaternion())