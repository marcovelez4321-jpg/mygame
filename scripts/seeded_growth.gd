class_name SeededGrowth
extends Node3D

## Seeded Growth (a mutation, the user's, 2026-10-17): tap right click and
## five big black symbiote tentacles burst out of the ground where you aim,
## spread over a 4 m circle. They thrust out fast and straight (a squid's
## strike), then lash for ALIVE_TIME -- bends running from base to tip, the
## tips curling, an octopus arm's way -- and suck back into the ground.
##   Bursting out: BURST_DAMAGE to what's on them. Small things (rats,
##   roaches, spiders, people) are either flung (ENEMY_LAUNCH, along the
##   tentacle) or grabbed, 50/50: the tentacle wraps round it (WRAP_TIME)
##   and slowly reels it under (REEL_TIME) -- gone, no drops. Big ones (the
##   big ones, Harvestmen, bosses) are flung where they can be, and hurt.
##   Standing on one as it bursts, you're launched along it (PLAYER_LAUNCH).
##   While they're out: TICK_DAMAGE a second to everything in the circle.
## Cheap: one mesh for all five, rebuilt only while it's alive (~2.5 s);
## one sphere query at the burst and one every TICK_EVERY.
## Rule 1 (co-op): the host's decides (hurts, grabs, flings); everyone else's
## is the look. The same seed (from where it is) shapes them the same.

const COUNT := 5
const SPREAD := 2.0 # (a 4 m circle)
const HEIGHT := 4.0
const THICKNESS := 0.35
const EMERGE_TIME := 0.14
const ALIVE_TIME := 2.0
const SINK_TIME := 0.35
const BURST_DAMAGE := 40.0
const TICK_DAMAGE := 10.0 # a second
const TICK_EVERY := 0.25
const ENEMY_LAUNCH := 18.0
const PLAYER_LAUNCH := 20.0
const PLAYER_REACH := 1.5
## How far round each tentacle the burst catches things.
const HIT_REACH := 1.6
const WRAP_TIME := 0.6
const REEL_TIME := 3.0
const POINTS := 16
const SIDES := 6
const TIP_RADIUS := 0.03

class Tendril:
	var base := Vector3.ZERO
	var up := Vector3.UP
	var side := Vector3.RIGHT
	var front := Vector3.FORWARD
	var phase := 0.0
	var pace := 1.0
	var curl := 1.0
	var catch: Node3D
	var catch_time := -1.0
	var catch_from := Vector3.ZERO
	var catch_depth := 1.5
	var done := false

var authority := false
var attacker_id := 1
var caster: PlayerMovement

var _tendrils: Array[Tendril] = []
var _time := 0.0
var _burst_done := false
var _tick_left := TICK_EVERY
var _hurt_by_burst := {}
var _immediate: ImmediateMesh
var _query: PhysicsShapeQueryParameters3D

static var _material: Material


## Five tentacles at `center` on a surface facing `normal`. `decides`: this
## one hurts and grabs (offline, or the host's).
static func burst(world: Node, center: Vector3, normal: Vector3, decides: bool, by: PlayerMovement) -> SeededGrowth:
	var growth := SeededGrowth.new()
	growth.authority = decides
	growth.caster = by
	growth.attacker_id = by.get_multiplayer_authority() if by else 1
	world.add_child(growth)
	growth._place(center, normal)
	return growth


func _place(center: Vector3, normal: Vector3) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(center.round()))
	var side := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
	var front := side.cross(normal).normalized()
	var space := get_world_3d().direct_space_state
	for i in COUNT:
		var t := Tendril.new()
		# Spread round the circle (a golden-angle ring), each a little off.
		var angle := i * 2.39996 + rng.randf_range(-0.3, 0.3)
		var out := (side * cos(angle) + front * sin(angle))
		var at := center + out * SPREAD * sqrt((i + 0.5) / COUNT)
		var query := PhysicsRayQueryParameters3D.create(at + normal * 1.5, at - normal * 2.5, 1)
		var hit := space.intersect_ray(query)
		t.base = hit.position if not hit.is_empty() else at
		t.up = (normal + out * 0.35).normalized()
		t.side = t.up.cross(out).normalized() if out.length_squared() > 0.01 else side
		t.front = t.side.cross(t.up).normalized()
		t.phase = rng.randf() * TAU
		t.pace = rng.randf_range(0.8, 1.25)
		t.curl = rng.randf_range(0.7, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		_tendrils.append(t)
		# The ground bursts open: dark spray, a stain.
		BloodFX.spawn_impact(get_tree().current_scene, t.base, normal, Color(0.03, 0.03, 0.035), 2.2)
		BloodFX.spawn_splatter(get_tree().current_scene, t.base + normal * 0.05, normal, 1.6, Color(0.05, 0.05, 0.06))
	_immediate = ImmediateMesh.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _immediate
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)


func _process(delta: float) -> void:
	_time += delta
	if authority:
		_decide(delta)
	for t in _tendrils:
		if not t.done and t.catch_time < 0.0 and _time >= ALIVE_TIME + SINK_TIME:
			t.done = true
	_draw()
	var all_done := true
	for t in _tendrils:
		if not t.done:
			all_done = false
	if all_done or _time > ALIVE_TIME + SINK_TIME + WRAP_TIME + REEL_TIME + 1.0:
		_release_catches()
		queue_free()


# ---- What it does (the host's) ---------------------------------------------------------

func _decide(delta: float) -> void:
	if not _burst_done and _time >= EMERGE_TIME * 0.5:
		_burst_done = true
		_burst_hits()
	for t in _tendrils:
		if t.catch_time >= 0.0:
			_reel(t)
	if _time < ALIVE_TIME:
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left += TICK_EVERY
			_tick_hurt()


func _burst_hits() -> void:
	for t in _tendrils:
		for body in _bodies_near(t.base, HIT_REACH):
			if body is PlayerMovement:
				if body.global_position.distance_to(t.base) <= PLAYER_REACH:
					(body as PlayerMovement).shove(t.up * PLAYER_LAUNCH)
				continue
			if _hurt_by_burst.has(body) or _is_caught(body):
				continue
			_hurt_by_burst[body] = true
			if _is_small(body) and t.catch == null and randf() < 0.5:
				_grab(t, body)
				continue
			_hurt(body, BURST_DAMAGE, t.up)
			_fling(body, t.up * ENEMY_LAUNCH)


func _tick_hurt() -> void:
	var centre := Vector3.ZERO
	for t in _tendrils:
		centre += t.base
	centre /= _tendrils.size()
	for body in _bodies_near(centre, SPREAD + HIT_REACH * 0.5):
		if body is PlayerMovement or _is_caught(body):
			continue
		_hurt(body, TICK_DAMAGE * TICK_EVERY, Vector3.UP)


## Everything with Health within `reach` of `at` (one sphere query).
func _bodies_near(at: Vector3, reach: float) -> Array[Node3D]:
	if _query == null:
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = SphereShape3D.new()
		_query.collide_with_areas = false
		_query.collision_mask = 1
	(_query.shape as SphereShape3D).radius = reach
	_query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.5)
	var found: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 32):
		var node := hit.collider as Node
		while node != null and node.get_node_or_null(^"Health") == null:
			node = node.get_parent()
		var body := node as Node3D
		if body and not found.has(body):
			var health := body.get_node(^"Health") as Health
			if not health.is_dead:
				found.append(body)
	return found


func _is_small(body: Node3D) -> bool:
	if body.has_meta(&"big"):
		return false
	return body is Rat or body is FlyingRoach or body is Spider or (body is Enemy and not (body is RatBender))


func _is_caught(body: Node3D) -> bool:
	for t in _tendrils:
		if t.catch == body:
			return true
	return false


func _hurt(body: Node3D, amount: float, direction: Vector3) -> void:
	var health := body.get_node_or_null(^"Health") as Health
	if health == null or health.is_dead:
		return
	health.take_damage(amount, attacker_id, direction, body.global_position, 4.0)
	Factions.provoke(body, caster)
	if caster:
		caster.weapons.hit_confirmed.emit(health.is_dead, WeaponController.HitKind.NORMAL)


## Thrown: the way it's pushed (shove), or a body's own velocity.
func _fling(body: Node3D, velocity: Vector3) -> void:
	if body.has_method("shove"):
		body.call("shove", velocity)
	elif body is RigidBody3D:
		(body as RigidBody3D).linear_velocity = velocity


## Caught: still, out of the physics, the tentacle's to move from now on.
func _grab(t: Tendril, body: Node3D) -> void:
	t.catch = body
	t.catch_time = 0.0
	t.catch_from = body.global_position
	t.catch_depth = 1.2 + (2.0 if body is Enemy else 0.6)
	body.set_meta(&"culled", true) # dragged under: no drops, no meat
	body.process_mode = Node.PROCESS_MODE_DISABLED
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = true
	if body is CollisionObject3D:
		(body as CollisionObject3D).collision_layer = 0
		(body as CollisionObject3D).collision_mask = 0


## Wrapped, then slowly pulled down into the ground; once under, gone.
func _reel(t: Tendril) -> void:
	t.catch_time += get_process_delta_time()
	if not is_instance_valid(t.catch):
		t.catch_time = -1.0
		t.done = true
		return
	var reel := clampf((t.catch_time - WRAP_TIME) / REEL_TIME, 0.0, 1.0)
	var lift := t.catch_from + t.up * 0.4 * sin(minf(t.catch_time / WRAP_TIME, 1.0) * PI * 0.5) * (1.0 - reel)
	var under := t.base - t.up * t.catch_depth
	t.catch.global_position = lift.lerp(under, reel * reel * (3.0 - 2.0 * reel))
	if reel >= 1.0:
		var body := t.catch
		t.catch = null
		t.catch_time = -1.0
		t.done = true
		if caster:
			caster.weapons.hit_confirmed.emit(true, WeaponController.HitKind.NORMAL)
		if body.has_method("_remove"):
			body.call("_remove") # (out of its swarm or pack too)
		else:
			body.queue_free()


func _release_catches() -> void:
	for t in _tendrils:
		if is_instance_valid(t.catch):
			t.catch.queue_free()
			t.catch = null


# ---- The look ------------------------------------------------------------------------------

func _draw() -> void:
	_immediate.clear_surfaces()
	var shapes: Array[PackedVector3Array] = []
	for t in _tendrils:
		if t.done and t.catch_time < 0.0:
			continue
		var points := _caught_shape(t) if is_instance_valid(t.catch) else _lash_shape(t)
		if points.size() >= 2:
			shapes.append(points)
	if shapes.is_empty():
		return # (nothing out: an empty surface is an error)
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _look())
	for points in shapes:
		_tube(points)
	_immediate.surface_end()


## How far out of the ground it is (0..1): a fast thrust with a little
## overshoot, out for ALIVE_TIME, then sucked back in.
func _out() -> float:
	if _time < EMERGE_TIME:
		var u := _time / EMERGE_TIME
		return 1.0 + 0.12 * sin(u * PI) - pow(1.0 - u, 3.0) # out past full, then back
	if _time < ALIVE_TIME:
		return 1.0
	var u := clampf((_time - ALIVE_TIME) / SINK_TIME, 0.0, 1.0)
	return 1.0 - u * u


## Lashing free: a flexible arm built segment by segment from the ground,
## each bent a little more -- bends travelling base to tip on two axes, the
## outer third curling, the whole thing thrashing harder once it's out.
func _lash_shape(t: Tendril) -> PackedVector3Array:
	var out := _out()
	var points := PackedVector3Array()
	if out <= 0.01:
		return points
	var length := HEIGHT * maxf(out, 0.0)
	var step := length / (POINTS - 1)
	var settle := smoothstep(EMERGE_TIME * 0.6, EMERGE_TIME * 2.5, _time) # straight as it strikes out
	var time := _time * t.pace
	var at := t.base - t.up * 0.25 # (out of a hole, not off the surface)
	var direction := t.up
	points.append(at)
	for i in range(1, POINTS):
		var s := float(i) / (POINTS - 1)
		var wave_a := sin(s * 5.0 - time * 7.0 + t.phase)
		var wave_b := sin(s * 3.5 - time * 4.3 + t.phase * 1.7)
		var bend_a := (0.55 * wave_a + 0.25 * sin(time * 2.1 + t.phase)) * settle
		var bend_b := 0.35 * wave_b * settle
		var tip_curl := smoothstep(0.6, 1.0, s) * 1.6 * t.curl * (0.6 + 0.4 * sin(time * 3.0 + t.phase))
		direction = direction.rotated(t.side, (bend_a + tip_curl * settle) * step / HEIGHT * 3.0)
		direction = direction.rotated(t.front, bend_b * step / HEIGHT * 3.0).normalized()
		at += direction * step
		points.append(at)
	return points


## Holding something: up out of the ground to it, then wound round it
## (more turns as it wraps), following it down as it's reeled under.
func _caught_shape(t: Tendril) -> PackedVector3Array:
	var points := PackedVector3Array()
	var body := t.catch.global_position + Vector3.UP * (0.9 if t.catch is Enemy else 0.25)
	var wrap := clampf(t.catch_time / WRAP_TIME, 0.0, 1.0)
	var start := t.base - t.up * 0.25
	var reach := 9
	for i in reach:
		var s := float(i) / (reach - 1)
		var sway := t.side * sin(s * PI) * 0.4
		points.append(start.lerp(body, s) + sway)
	var radius := 0.45 if t.catch is Enemy else 0.25
	var height := 1.2 if t.catch is Enemy else 0.35
	var turns := 2.5 * wrap
	var coil := 10
	for i in range(1, coil + 1):
		var u := float(i) / coil
		var angle := u * turns * TAU + t.phase
		var ring := (t.side * cos(angle) + t.front * sin(angle)) * radius * (1.0 - u * 0.25)
		points.append(body + ring + Vector3.UP * (u - 0.5) * height * wrap)
	return points


## A tube round `points`, thick at the base, thin at the tip.
func _tube(points: PackedVector3Array) -> void:
	var count := points.size()
	var reference := Vector3.UP
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in count:
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var n := tangent.cross(reference)
		if n.length_squared() < 0.001:
			n = tangent.cross(Vector3.RIGHT)
		n = n.normalized()
		reference = n.cross(tangent)
		var b := tangent.cross(n)
		var s := float(i) / (count - 1)
		var radius := lerpf(THICKNESS * 0.5, TIP_RADIUS, pow(s, 0.8)) * (1.0 + 0.08 * sin(s * 12.0 - _time * 6.0))
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in SIDES + 1:
			var angle := TAU * k / SIDES
			var around := n * cos(angle) + b * sin(angle)
			ring.append(points[i] + around * radius)
			ring_normals.append(around)
		rings.append(ring)
		normals.append(ring_normals)
	for i in count - 1:
		var v0 := 4.0 * i / (count - 1)
		var v1 := 4.0 * (i + 1) / (count - 1)
		for k in SIDES:
			var u0 := float(k) / SIDES
			var u1 := float(k + 1) / SIDES
			_vertex(rings[i][k], normals[i][k], Vector2(u0, v0))
			_vertex(rings[i + 1][k], normals[i + 1][k], Vector2(u0, v1))
			_vertex(rings[i + 1][k + 1], normals[i + 1][k + 1], Vector2(u1, v1))
			_vertex(rings[i][k], normals[i][k], Vector2(u0, v0))
			_vertex(rings[i + 1][k + 1], normals[i + 1][k + 1], Vector2(u1, v1))
			_vertex(rings[i][k + 1], normals[i][k + 1], Vector2(u1, v0))


func _vertex(point: Vector3, normal: Vector3, uv: Vector2) -> void:
	_immediate.surface_set_normal(normal)
	_immediate.surface_set_uv(uv)
	_immediate.surface_add_vertex(point)


## The black symbiote's look (the grapple's own: GrappleTentacle), shared.
static func _look() -> Material:
	if _material == null:
		_material = PS1Look.material(GrappleTentacle.symbiote_texture(), Color.WHITE, true)
	return _material