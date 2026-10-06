class_name PhysicsGrabber
extends Node

## Half-Life-style "hold F to pick up and carry" physics interaction.
## Attach as a child of the player body (same pattern as WeaponController --
## it never reads Input directly, the player's simulation step calls tick()
## every physics frame, Rule 1).
##
## Works on RigidBody3D physics props AND on ragdoll PhysicalBone3D corpses
## in one system: "hold F to move any object including the ragdolls" was
## explicit in the request, so the raycast mask deliberately covers both,
## reusing EnemyRagdoll's own RAGDOLL_LAYER/WORLD_MASK constants instead of
## redefining the layer split somewhere else (Rule 6).
##
## REWRITE: this used to nudge the held body toward the hold point with a
## speed-capped IMPULSE each tick (a spring). A spring inherently lags behind
## fast mouse movement -- it takes several ticks to catch up -- and once it
## catches up it overshoots and swings side to side, which is exactly what
## got reported ("lags behind the mouse", "swings left and right"). Every
## tick now sets the held body's linear_velocity DIRECTLY to whatever
## velocity closes the entire remaining gap by the next tick (still capped
## by max_pull_speed, so a huge initial gap or a ragdoll's own joints
## fighting back can't produce an absurd one-step jump), and zeroes
## angular_velocity so nothing keeps spinning/swinging from residual
## momentum. This tracks the hold point immediately with no lag and no
## oscillation, while still being a real physics body -- Jolt still resolves
## collisions against it normally along the way, it just never falls behind.
##
## Rule 1 (co-op): purely a local interaction like the weapon wheel -- each
## player's game grabs and releases its own held body from its own "F is
## held" state. Not yet networked; when it is, this is the seam a server
## would arbitrate ("who's allowed to hold this crate").

## How far in front of the camera a held object is pulled to.
@export var grab_distance: float = 2.0
## How far the initial pickup raycast reaches.
@export var max_grab_range: float = 5.0
## Auto-release if the held body ends up further than this from the hold
## point -- stuck on geometry, or the player backed through a wall. Kept
## well past max_grab_range + grab_distance so a fresh grab from near the
## edge of pickup range is never immediately past this threshold.
@export var release_distance: float = 10.0
## Hard cap on how fast a held body can move in one tick. Since velocity is
## now set directly to whatever closes the gap immediately, this is the only
## real safety limit left -- without it, a huge initial gap (grabbing
## something near max_grab_range) or a ragdoll's own joints fighting back
## could produce an absurd one-step jump.
@export var max_pull_speed: float = 90.0
## Separate, much lower cap applied ONLY at the moment of release. Without
## this, whatever velocity _snap_to_hold_point() last set (up to
## max_pull_speed, needed for the hold itself to track a fast mouse flick
## with no lag) is exactly what the body keeps after letting go of F -- so
## whipping the camera right before releasing launched props and ragdolls
## like a rocket. This turns "let go" back into a toss instead of a throw.
@export var max_throw_speed: float = 6.0

@onready var _body: CollisionObject3D = get_parent() as CollisionObject3D

## RigidBody3D or PhysicalBone3D -- deliberately untyped. They don't share a
## common ancestor that exposes linear_velocity/angular_velocity, so a
## static type here would block one or the other.
var _held
## The held body's visual/collision CENTER, in ITS OWN local space -- see
## _local_center()'s comment for why this is needed at all.
var _held_local_center := Vector3.ZERO


func is_holding() -> bool:
	return _held != null


## Called once per physics tick by the owner's simulation step, same pattern
## as WeaponController.tick().
func tick(grab: bool, delta: float, origin: Vector3, direction: Vector3) -> void:
	if grab and _held == null:
		_try_grab(origin, direction)
	elif not grab and _held != null:
		_release()

	if _held == null:
		return
	if not is_instance_valid(_held):
		_held = null
		return
	_snap_to_hold_point(origin, direction, delta)


func _try_grab(origin: Vector3, direction: Vector3) -> void:
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_grab_range)
	query.exclude = [_body.get_rid()]
	query.collision_mask = EnemyRagdoll.WORLD_MASK # world/props (layer 1) + ragdoll corpses
	var result := space.intersect_ray(query)
	if result.is_empty():
		return
	var collider = result.collider
	if not (collider is RigidBody3D or collider is PhysicalBone3D):
		return # world geometry, a static prop, or something else not meant to be picked up

	_held = collider
	# Only for RigidBody3D props -- a prop's ORIGIN is wherever its mesh's
	# pivot was authored (often the floor-contact point for furniture, like
	# the chair), not its visual center, so pulling the raw origin to the
	# hold point makes it hang by its "feet". A ragdoll bone keeps the old
	# behavior (grab exactly where you're aiming): a capsule's own origin is
	# already centered on it, and "grab the exact point on a limb" is the
	# more natural feel for dragging a body around by a specific arm/leg.
	_held_local_center = _local_center(_held) if _held is RigidBody3D else Vector3.ZERO
	print("PhysicsGrabber: grabbed '%s'" % _held.name) # TEMPORARY diagnostic


func _release(reason: String = "let go") -> void:
	if is_instance_valid(_held):
		# Cap down to max_throw_speed regardless of what the hold itself just
		# had it moving at -- see max_throw_speed's own comment.
		var held_velocity: Vector3 = _held.linear_velocity # untyped _held -> explicit type, := can't infer through Variant
		_held.linear_velocity = held_velocity.limit_length(max_throw_speed)
		print("PhysicsGrabber: released '%s' (%s)" % [_held.name, reason]) # TEMPORARY diagnostic
	_held = null


func _snap_to_hold_point(origin: Vector3, direction: Vector3, delta: float) -> void:
	var target := origin + direction * grab_distance
	# global_transform (not global_position) so the center offset rotates
	# WITH the object -- if it's tumbling, the tracked point has to move
	# with it, not stay at a fixed world offset.
	var global_transform: Transform3D = _held.global_transform # untyped _held -> explicit type, := can't infer through Variant
	var held_position := global_transform * _held_local_center
	var offset := target - held_position
	var distance := offset.length()
	if distance > release_distance:
		_release("too far: %.1fm" % distance)
		return
	# The exact velocity that closes the WHOLE gap by the next tick, not a
	# fraction of it -- this is what makes it a rigid snap instead of a
	# spring. Zeroing angular_velocity too stops it from continuing to spin
	# on whatever rotation it had when grabbed.
	var needed_velocity: Vector3 = offset / delta
	_held.linear_velocity = needed_velocity.limit_length(max_pull_speed)
	_held.angular_velocity = Vector3.ZERO


## The combined bounding box center of all of `body`'s CollisionShape3D
## children, in body's OWN local space. Works for any shape type uniformly
## (Box, Convex hull, Capsule...) by asking each shape for its own debug
## mesh -- every Shape3D can produce one, so this needs no per-shape-type
## special-casing.
func _local_center(body: Node3D) -> Vector3:
	var combined: AABB
	var found := false
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape_aabb: AABB = shape_node.transform * shape_node.shape.get_debug_mesh().get_aabb()
		combined = shape_aabb if not found else combined.merge(shape_aabb)
		found = true
	return combined.get_center() if found else Vector3.ZERO
