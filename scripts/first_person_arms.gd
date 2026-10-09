class_name FirstPersonArms
extends Node3D

## The first-person arms (Arms/arms_rig.glb: bare arms, no gloves), HL2's
## c_arms way: one rig whose "camera" bone sits on your eye, so the arms are
## always framed the same and every gun is fitted to the same hands.
##   Right arm: holds the gun, in the rig's finger_gun_idle pose (index finger
##     along the frame, the rest wrapped round the grip), held still.
##   Left arm: the tentacle arm (PlayerGrapple). Out of view until you press
##     E; then it rises from below and reaches out like it's pushing something
##     (the rig's push_L at full reach) while the symbiote coils up it, and it
##     stays out pointing at the grapple until it lets go.
## Poses are read straight from the rig's animations (no AnimationPlayer
## running) and written to the bones each frame. Presentation only (Rule 1).

const RIGHT_ROOT := "shoulder.R"
const LEFT_ROOT := "shoulder.L"

## The right arm's pose (where the arm and wrist go) ...
@export var hold_animation: StringName = &"finger_gun_idle"
## ... and the fingers': a hand closed round a handle (the knife grip), so
## the middle, ring and little fingers and the thumb wrap the gun's grip.
@export var grip_animation: StringName = &"knife_idle"
## The index finger, on the trigger: 0 = straight out (the finger-gun pose),
## 1 = curled all the way round like the others.
@export_range(0.0, 1.0, 0.05) var trigger_curl: float = 0.55
## Keep the right wrist straight (the hand in line with the forearm, as in
## the rig's rest pose) instead of the hold pose's bent wrist.
@export var straight_wrist: bool = true
@export var reach_animation: StringName = &"push_L"
## Two-handed guns: the left hand comes up in this one pose (the rig's grab_L
## at support_time of the way through: reaching forward under the gun).
@export var support_animation: StringName = &"grab_L"
@export_range(0.0, 1.0, 0.05) var support_time: float = 0.5
## How far below its pose the left arm hides (meters), and how fast it comes
## up / goes back down (per second, 0..1).
@export var hide_drop: float = 0.55
@export var raise_speed: float = 4.0
@export var lower_speed: float = 3.0
## How far the arm has reached out by the end of the coil (0..1); on release
## it shoves out the rest of the way at push_speed.
@export var coil_reach: float = 0.65
@export var push_speed: float = 9.0
## How much of the coil a full hold winds (the rest snaps on at release), and
## how fast that last bit snaps on (per second, 0..1).
@export_range(0.0, 1.0, 0.05) var coil_before_release: float = 0.8
@export var release_coil_speed: float = 6.0
## How fast the coil unwinds back up the arm after the grapple lets go.
@export var uncoil_speed: float = 2.5

var skeleton: Skeleton3D
var hand_attachment: BoneAttachment3D
var hand_bone := -1

## 0 = hidden, 1 = up. How far it's reaching out (0..1). How much of the
## symbiote is coiled round it (0..1; GrappleTentacle draws it).
var raise := 0.0
var reach := 0.0
var coil := 0.0

var _camera_bone := -1
var _cant := 0.0
var _dual := false
## A two-handed gun out: the left hand's up in the support pose.
var _support := false
var _support_pose := {}
## The left arm's pose while dual wielding (the right grip, mirrored).
var _left_hold := {}
## Follows the left hand bone: the second gun hangs off it when dual wielding.
var left_hand_attachment: BoneAttachment3D
## The skeleton node's place in this node's space (the model's own nodes).
var _skeleton_in_self := Transform3D.IDENTITY
var _right_bones := PackedInt32Array()
var _left_bones := PackedInt32Array()
var _left_root := -1
## Local pose per bone: [position, rotation, scale], for each named pose.
var _hold := {}
var _rest := {}
var _reach := {}
## What's on the bones right now (local), for working out where things are.
var _current := {}
var _forearm_l := -1
var _hand_l := -1
var _palm_l := -1
var _finger_l := -1


func _ready() -> void:
	var model := (load("res://Arms/arms_rig.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.stop()
	player.active = false
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	PS1Look.apply(model) # same skin texture, through the PS1 shader

	_skeleton_in_self = global_transform.affine_inverse() * skeleton.global_transform
	_camera_bone = skeleton.find_bone("camera")
	hand_bone = skeleton.find_bone("hand.R")
	_left_root = skeleton.find_bone(LEFT_ROOT)
	_forearm_l = skeleton.find_bone("forearm.L")
	_hand_l = skeleton.find_bone("hand.L")
	_palm_l = skeleton.find_bone("palm.02.L")
	_finger_l = skeleton.find_bone("f_middle.01.L")
	_collect(skeleton.find_bone(RIGHT_ROOT), _right_bones)
	_collect(_left_root, _left_bones)

	_rest = _sample(null, 0.0)
	_hold = _sample(player.get_animation(hold_animation), 0.0)
	_close_hand(_sample(player.get_animation(grip_animation), 0.0))
	if straight_wrist:
		_hold[hand_bone] = _rest[hand_bone]
	var reach_anim := player.get_animation(reach_animation)
	_reach = _sample(reach_anim, _furthest_reach(reach_anim))
	var support_anim := player.get_animation(support_animation)
	_support_pose = _sample(support_anim, support_anim.length * support_time)
	_current = _rest.duplicate()
	for bone in _right_bones:
		_current[bone] = _hold[bone]

	hand_attachment = BoneAttachment3D.new()
	hand_attachment.bone_name = "hand.R"
	skeleton.add_child(hand_attachment)
	left_hand_attachment = BoneAttachment3D.new()
	left_hand_attachment.bone_name = "hand.L"
	skeleton.add_child(left_hand_attachment)
	_write()


## Where the rig goes in camera space: turned to face -Z (it faces +Z) with
## its camera bone on the eye.
func camera_transform() -> Transform3D:
	var turn := Basis(Vector3.UP, PI)
	var eye := (_skeleton_in_self * skeleton.get_bone_global_rest(_camera_bone)).origin
	return Transform3D(turn, -(turn * eye))


## A bone's place in this node's space with the pose on it now (worked out
## here, so it's never a frame stale).
func bone_in_rig(bone: int) -> Transform3D:
	return _skeleton_in_self * _bone_in_skeleton(bone)


## Dual wielding (WeaponData.dual_wield): the left arm takes the right arm's
## grip, mirrored, and holds a second gun (on left_hand_attachment) instead
## of doing the grapple.
func set_dual(on: bool) -> void:
	if on == _dual:
		return
	_dual = on
	if on:
		_left_hold = _mirrored_right()
	else:
		raise = 0.0 # put away with the guns (mid-switch, out of view)
		reach = 0.0
	tick(0.0, false, 0.0, false, false)


## Two-handed guns: the left hand comes up in the support pose (one pose for
## every such gun, not fitted to each).
func set_support(on: bool) -> void:
	if on == _support:
		return
	_support = on
	if not on:
		raise = 0.0
		reach = 0.0
	tick(0.0, false, 0.0, false, false)


## Turns the right forearm over by `degrees` round its own length (90 = the
## hand rolled so a gun in it lies on its side, top to the left), for a
## canted grip (WeaponData.hold_cant_degrees). The wrist stays where it is.
func set_cant(degrees: float) -> void:
	if is_equal_approx(degrees, _cant):
		return
	_cant = degrees
	for bone in _right_bones:
		_current[bone] = _hold[bone]
	if not is_zero_approx(degrees):
		var forearm := skeleton.find_bone("forearm.R")
		var elbow := _bone_in_skeleton(forearm)
		var along := (_bone_in_skeleton(hand_bone).origin - elbow.origin).normalized()
		# Seen from behind the hand, positive turns it anticlockwise (the
		# arm points away from you, so that's negative round `along`).
		var turned := Basis(Quaternion(along, -deg_to_rad(degrees))) * elbow.basis
		var parent := skeleton.get_bone_parent(forearm)
		var parent_basis := _bone_in_skeleton(parent).basis if parent != -1 else Basis.IDENTITY
		var pose: Array = _current[forearm]
		_current[forearm] = [pose[0], (parent_basis.inverse() * turned).get_rotation_quaternion(), pose[2]]
	if _dual:
		_left_hold = _mirrored_right()
	_write()


## Gives the hold pose the grip pose's fingers: every bone below the right
## hand from `grip`, except the index finger, which goes trigger_curl of the
## way from the hold pose's (straight) to the grip's (curled).
func _close_hand(grip: Dictionary) -> void:
	var fingers := PackedInt32Array()
	for child in skeleton.get_bone_children(hand_bone):
		_collect(child, fingers)
	for bone in fingers:
		if not skeleton.get_bone_name(bone).begins_with("f_index"):
			_hold[bone] = grip[bone]
			continue
		var straight: Array = _hold[bone]
		var curled: Array = grip[bone]
		_hold[bone] = [(straight[0] as Vector3).lerp(curled[0], trigger_curl),
				(straight[1] as Quaternion).slerp(curled[1], trigger_curl),
				(straight[2] as Vector3).lerp(curled[2], trigger_curl)]


## The right arm's pose as it is now, mirrored onto the left arm (the rig is
## symmetric across its X = 0): each left bone's place is its right twin's,
## flipped across X, and its local pose is worked out from that.
func _mirrored_right() -> Dictionary:
	var mirror := Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO)
	var places := {}
	var result := {}
	for bone in _left_bones: # parents before children
		var twin := skeleton.find_bone(skeleton.get_bone_name(bone).replace(".L", ".R"))
		var place := mirror * _bone_in_skeleton(twin) * mirror
		places[bone] = place
		var parent := skeleton.get_bone_parent(bone)
		var parent_place: Transform3D = places[parent] if places.has(parent) else _bone_in_skeleton(parent)
		var local := parent_place.affine_inverse() * place
		result[bone] = [local.origin, local.basis.get_rotation_quaternion(), local.basis.get_scale()]
	return result


func _bone_in_skeleton(bone: int) -> Transform3D:
	var result := _local(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent != -1:
		result = _local(parent) * result
		parent = skeleton.get_bone_parent(parent)
	return result


## Left arm points (global) for the coil: elbow, wrist, middle of the palm,
## and which way the fingers point.
func left_arm_points() -> Array[Vector3]:
	var to_world := global_transform
	var elbow := to_world * bone_in_rig(_forearm_l).origin
	var wrist := to_world * bone_in_rig(_hand_l).origin
	var palm := to_world * bone_in_rig(_palm_l).origin
	var finger := to_world * bone_in_rig(_finger_l).origin
	return [elbow, wrist, palm, (finger - palm).normalized()]


## The middle of the closed right hand (between the palm and the curled
## middle finger), in this node's space: where a gun's grip_point goes.
func grip_socket_in_rig() -> Vector3:
	var palm := bone_in_rig(skeleton.find_bone("palm.02.R")).origin
	var knuckle := bone_in_rig(skeleton.find_bone("f_middle.02.R")).origin
	var tip := bone_in_rig(skeleton.find_bone("f_middle.03.R")).origin
	return (palm + knuckle + tip) / 3.0


## Called every frame by the Viewmodel with the grapple's state.
func tick(delta: float, coiling: bool, coil_amount: float, rope_out: bool, left_allowed: bool) -> void:
	if _dual or _support:
		raise = 1.0
		reach = 0.0
		coil = 0.0
		var pose: Dictionary = _left_hold if _dual else _support_pose
		for bone in _left_bones:
			_current[bone] = pose[bone]
		_write()
		return
	var wanted := left_allowed and (coiling or rope_out)
	raise = move_toward(raise, 1.0 if wanted else 0.0, (raise_speed if wanted else lower_speed) * delta)
	var reach_to := 0.0
	if coiling:
		reach_to = coil_amount * coil_reach
	elif rope_out:
		reach_to = 1.0
	reach = move_toward(reach, reach_to, (push_speed if rope_out else 1.5) * delta)
	# The hold winds it most of the way up the arm; letting go finishes the
	# last turns in a snap, so it's fully coiled right as it lashes.
	if coiling:
		coil = coil_amount * coil_before_release
	elif rope_out:
		coil = move_toward(coil, 1.0, release_coil_speed * delta)
	else:
		coil = move_toward(coil, 0.0, uncoil_speed * delta)
	if not left_allowed:
		coil = 0.0
	var smooth_raise := smoothstep(0.0, 1.0, raise)
	var smooth_reach := smoothstep(0.0, 1.0, reach)
	for bone in _left_bones:
		var a: Array = _rest[bone]
		var b: Array = _reach[bone]
		_current[bone] = [(a[0] as Vector3).lerp(b[0], smooth_reach),
				(a[1] as Quaternion).slerp(b[1], smooth_reach),
				(a[2] as Vector3).lerp(b[2], smooth_reach)]
	# Dropped down out of view, and squashed to nothing once it's all the way
	# down (so no elbow pokes in at the bottom of the screen).
	var root_pose: Array = _current[_left_root]
	var parent := skeleton.get_bone_parent(_left_root)
	var parent_basis := bone_in_rig(parent).basis if parent != -1 else Basis.IDENTITY
	var drop := parent_basis.inverse() * Vector3(0.0, -hide_drop * (1.0 - smooth_raise), 0.0)
	var shown := raise > 0.01
	_current[_left_root] = [(root_pose[0] as Vector3) + drop, root_pose[1],
			(root_pose[2] as Vector3) if shown else Vector3.ONE * 0.001]
	_write()


func _write() -> void:
	for bone in _current:
		var pose: Array = _current[bone]
		skeleton.set_bone_pose_position(bone, pose[0])
		skeleton.set_bone_pose_rotation(bone, pose[1])
		skeleton.set_bone_pose_scale(bone, pose[2])


func _local(bone: int) -> Transform3D:
	var pose: Array = _current.get(bone, _rest[bone])
	return Transform3D(Basis(pose[1] as Quaternion) * Basis.from_scale(pose[2]), pose[0])


func _collect(bone: int, into: PackedInt32Array) -> void:
	if bone == -1:
		return
	into.append(bone)
	for child in skeleton.get_bone_children(bone):
		_collect(child, into)


## Every bone's local pose at time `t` of `anim` (rest where it has no track).
func _sample(anim: Animation, t: float) -> Dictionary:
	var poses := {}
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		poses[bone] = [rest.origin, rest.basis.get_rotation_quaternion(), rest.basis.get_scale()]
	if anim == null:
		return poses
	for track in anim.get_track_count():
		var bone := skeleton.find_bone(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone == -1:
			continue
		var pose: Array = poses[bone]
		match anim.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pose[0] = anim.position_track_interpolate(track, t)
			Animation.TYPE_ROTATION_3D:
				pose[1] = anim.rotation_track_interpolate(track, t)
			Animation.TYPE_SCALE_3D:
				pose[2] = anim.scale_track_interpolate(track, t)
	return poses


## The moment in `anim` when the left hand is furthest forward (the push).
func _furthest_reach(anim: Animation) -> float:
	var best := 0.0
	var best_z := -INF
	for i in 31:
		var t := anim.length * i / 30.0
		_current = _sample(anim, t)
		var z := bone_in_rig(_hand_l).origin.z # the rig faces +Z
		if z > best_z:
			best_z = z
			best = t
	return best
