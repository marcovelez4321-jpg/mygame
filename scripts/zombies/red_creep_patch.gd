class_name RedCreepPatch
extends Node3D

## One patch of the red creep (RedCreep; docs/RED_CREEP.md): a bush of the
## red weed (RedWeed's, twice its size -- the user's) and the ropes it sends
## out. Each rope is braided red vine laid over whatever it crawls on, its tip
## creeping on like a worm at GROW_SPEED: along floors, up walls, over lips
## and down off ledges (dangling when there's nothing to hold), feeling its way
## (a wander), drawn to life within SENSE, to noise and blood (RedCreep's
## stimuli: faster too), and back in when it nears its edge -- a patch stops
## at RADIUS from its bush (the user's: about 15 m across; only seeds take it
## further), and CLIMB_MAX up. Now and then a rope forks (BRANCH_CHANCE).
## Life within REACH of a rope: a tendril lifts off it, reaching through the
## air for it, and on touching it the creep wraps it (RedWrap). A runner
## (RedCreep's links) crawls on past the edge to another patch.
## Cut (a shot's path through it) or burned: the rope's lost past there,
## withering away, and the stump grows on again after REGROW_PAUSE.
## Rule 1 (co-op): the host grows it; every game is sent the points
## (RedCreep) and draws the same ropes.

enum Kind { CRAWL, TENDRIL, RUNNER }
enum State { GROWING, RESTING, PAUSED, WRAPPING, DEAD }

const GROW_SPEED := 1.0 / 3.0 # (the user's: steady, about 1 m every 3 s)
const REACH_SPEED := 1.6
const STEP := 0.35
const RADIUS := 7.5
const CLIMB_MAX := 12.0
const MAX_ROPES := 10
const START_ROPES := 4
const BRANCH_CHANCE := 0.05
const SENSE := 10.0
const REACH := 4.0
## A tendril gives up on what's moved this far from where it rose.
const REACH_LOST := 6.5
const TOUCH := 0.7
const DANGLE_MAX := 10
const REGROW_PAUSE := 5.0
const CUT_RADIUS := 0.3
const WITHER_TIME := 1.6
## The braid: two strands round the rope's line, this far apart, turning
## once every TWIST metres; each strand's thickness.
const BRAID := 0.045
const TWIST := 0.7
const STRAND := 0.04
const SIDES := 4
const SEEN_RANGE := 90.0
const MESH_BUDGET := 4

var id := 0
var director: RedCreep
var surface_normal := Vector3.UP
var bush_size := 2.0
var host := true
## [rope dict] (indices never reused: a dead rope stays, empty).
var ropes: Array[Dictionary] = []
## Who each tendril's reaching for: target -> rope index.
var _reaching := {}
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _bush: MeshInstance3D
var _dirty: Array[int] = []


func setup(patch_id: int, the_director: RedCreep, normal: Vector3, size: float, is_host: bool, pulse_phase: float) -> void:
	id = patch_id
	director = the_director
	surface_normal = normal
	bush_size = size
	host = is_host
	_rng.seed = hash(patch_id * 7919 + int(global_position.x * 13.0) + int(global_position.z * 7.0))
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/red_creep.gdshader")
	set_pulse(pulse_phase)
	_bush = MeshInstance3D.new()
	_bush.mesh = RedWeed._bush_mesh(_rng)
	_bush.material_override = _material
	_bush.visibility_range_end = SEEN_RANGE
	add_child(_bush)
	_bush.global_basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * bush_size)
	if host:
		for i in START_ROPES:
			var way := _tangent(Vector3.FORWARD.rotated(surface_normal, TAU * (float(i) + _rng.randf() * 0.6) / START_ROPES), surface_normal)
			_new_rope(Kind.CRAWL, global_position + surface_normal * 0.05, surface_normal, way)


func set_pulse(phase: float) -> void:
	_material.set_shader_parameter(&"pulse_phase", phase)


## How big the bush is (a seed's touch: within it).
func bush_reach() -> float:
	return bush_size * 0.9


# ---- Growing (the host's) ---------------------------------------------------------------------

func grow(delta: float, life: Array[Node3D]) -> void:
	for index in ropes.size():
		var rope := ropes[index]
		match rope.state:
			State.PAUSED:
				rope.pause -= delta
				if rope.pause <= 0.0:
					rope.state = State.GROWING
			State.GROWING:
				if rope.kind == Kind.TENDRIL:
					_reach_on(index, delta)
					continue
				var boost := 1.0
				var lure := director.stimulus_near(rope.pts[rope.pts.size() - 1])
				if lure.is_finite():
					boost = RedCreep.STIMULUS_BOOST
				rope.carry += GROW_SPEED * boost * delta
				while rope.carry >= STEP and rope.state == State.GROWING:
					rope.carry -= STEP
					if not _advance(index, life, lure):
						rope.state = State.RESTING
	_reach_for(life)


func _new_rope(kind: Kind, at: Vector3, normal: Vector3, heading: Vector3, parent := Vector2i(-1, -1)) -> int:
	ropes.append({kind = kind, state = State.GROWING, pts = PackedVector3Array([at]), nrm = PackedVector3Array([normal]),
			heading = heading, carry = 0.0, wander = 0.0, dangle = 0, pause = 0.0, parent = parent,
			target = null, shade = _rng.randf_range(0.5, 1.0), sent = 0, mesh = null})
	_mark(ropes.size() - 1)
	return ropes.size() - 1


## One STEP on along whatever it's on. False: it can't (or mustn't) go on.
func _advance(index: int, life: Array[Node3D], lure: Vector3) -> bool:
	var rope := ropes[index]
	var p: Vector3 = rope.pts[rope.pts.size() - 1]
	var n: Vector3 = rope.nrm[rope.nrm.size() - 1]
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	if rope.kind == Kind.CRAWL and (flat > RADIUS or p.y - global_position.y > CLIMB_MAX):
		return false
	# Feeling its way: a slow wander, then drawn to what it wants.
	rope.wander = clampf(rope.wander + _rng.randf_range(-0.35, 0.35), -0.8, 0.8)
	var heading: Vector3 = (rope.heading as Vector3).rotated(n, rope.wander * 0.3)
	var want := Vector3.INF
	var pull := 0.0
	if rope.kind == Kind.RUNNER and is_instance_valid(rope.target) and rope.target is RedCreepPatch:
		want = (rope.target as Node3D).global_position
		pull = 1.5
	else:
		var near := _nearest_life(p, life, SENSE)
		if near:
			want = near.global_position
			pull = 1.2
		elif lure.is_finite():
			want = lure
			pull = 1.0
	if rope.kind == Kind.CRAWL and flat > RADIUS * 0.75:
		var back := (global_position - p)
		heading += _tangent(back, n) * (flat - RADIUS * 0.75) / (RADIUS * 0.25) * 1.5
	if want.is_finite():
		heading += _tangent(want - p, n) * pull
	heading = _tangent(heading, n)
	if FireSource.near_point(p + heading * STEP, 1.2):
		heading = heading.rotated(n, PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0))
	var next := _crawl(p, n, heading, rope)
	if next.is_empty():
		return false
	_append(rope, next[0], next[1])
	rope.heading = next[2]
	_mark(index)
	# Forking now and then (a crawl's, once it's out a way).
	if rope.kind == Kind.CRAWL and rope.pts.size() > 8 and _living_ropes() < MAX_ROPES and _rng.randf() < BRANCH_CHANCE:
		var fork := (next[2] as Vector3).rotated(next[1], deg_to_rad(50.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
		_new_rope(Kind.CRAWL, next[0], next[1], fork, Vector2i(index, rope.pts.size() - 1))
	return true


## The next point on from `p` (on a surface facing `n`), heading `h`:
## [point, its surface's normal, the heading on from it], or [] if it can't.
##   A surface across its way (a wall ahead): onto it, heading up it.
##   Else the surface carries on under it.
##   Else it's at an edge: round it onto the face beyond (over a lip, down
##   off a ledge).
##   Else it dangles, straight down, till something's under it.
func _crawl(p: Vector3, n: Vector3, h: Vector3, rope: Dictionary) -> Array:
	var space := get_world_3d().direct_space_state
	var lift := p + n * 0.12
	var ahead := _ray(space, lift, lift + h * STEP * 1.3)
	if not ahead.is_empty():
		var m: Vector3 = ahead.normal
		var on: Vector3 = (ahead.position as Vector3) + m * 0.05
		if absf(m.dot(n)) < 0.7:
			rope.dangle = 0
			return [on, m, _tangent(n, m)]
		return [on, m, _tangent(h, m)]
	var c := p + h * STEP
	var under := _ray(space, c + n * 0.4, c - n * 0.6)
	if not under.is_empty():
		rope.dangle = 0
		var m: Vector3 = under.normal
		return [(under.position as Vector3) + m * 0.05, m, _tangent(h, m)]
	var round_it := _ray(space, c - n * 0.35, c - n * 0.35 - h * STEP * 1.5)
	if not round_it.is_empty():
		rope.dangle = 0
		var m: Vector3 = round_it.normal
		return [(round_it.position as Vector3) + m * 0.05, m, _tangent(-n, m)]
	if rope.dangle >= DANGLE_MAX:
		return []
	rope.dangle += 1
	var down := p + Vector3.DOWN * STEP
	var hang := Vector3(-h.x, 0.0, -h.z).normalized() if Vector2(h.x, h.z).length() > 0.1 else Vector3.BACK
	return [down, hang, Vector3.DOWN]


## Life within REACH of a rope (not already reached for, not already
## wrapped): a tendril rises off the nearest point toward it.
func _reach_for(life: Array[Node3D]) -> void:
	for gone: Variant in _reaching.keys():
		if not is_instance_valid(gone):
			_reaching.erase(gone)
	for target in life:
		if not is_instance_valid(target) or _reaching.has(target) or director.is_wrapped(target):
			continue
		var to := target.global_position
		if Vector2(to.x - global_position.x, to.z - global_position.z).length() > RADIUS + REACH + 2.0:
			continue
		var best := Vector3.INF
		var best_d := REACH
		var best_rope := -1
		var best_i := 0
		for r in ropes.size():
			var rope := ropes[r]
			if rope.state == State.DEAD or rope.kind == Kind.TENDRIL:
				continue
			var pts: PackedVector3Array = rope.pts
			for i in range(0, pts.size(), 2):
				var d := pts[i].distance_to(to)
				if d < best_d:
					best_d = d
					best = pts[i]
					best_rope = r
					best_i = i
		if best_rope < 0:
			continue
		var up: Vector3 = ropes[best_rope].nrm[best_i]
		var tendril := _new_rope(Kind.TENDRIL, best, up, (_chest(target) - best).normalized(), Vector2i(best_rope, best_i))
		ropes[tendril].target = target
		_reaching[target] = tendril


## A tendril reaching on through the air for its target; touching it, the
## wrap (RedCreep.start_wrap); lost (gone, dead, moved off), it withers.
func _reach_on(index: int, delta: float) -> void:
	var rope := ropes[index]
	var target := rope.target as Node3D
	var root: Vector3 = rope.pts[0]
	if not is_instance_valid(target) or not Factions.is_alive_target(target) or target.global_position.distance_to(root) > REACH_LOST:
		_drop_tendril(index)
		return
	var tip: Vector3 = rope.pts[rope.pts.size() - 1]
	var chest := _chest(target)
	if tip.distance_to(chest) < TOUCH:
		rope.state = State.WRAPPING
		director.start_wrap(target, self, index)
		return
	rope.carry += REACH_SPEED * delta
	while rope.carry >= STEP * 0.6:
		rope.carry -= STEP * 0.6
		var way := (chest - tip).normalized()
		# A worm's reach: curling as it comes.
		var side := way.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		tip += (way + side.normalized() * sin(rope.pts.size() * 0.9) * 0.35).normalized() * STEP * 0.6
		_append(rope, tip, side.normalized().cross(way).normalized())
		_mark(index)
		if tip.distance_to(chest) < TOUCH:
			break


## (Packed arrays are copied out of a dictionary: put back.)
static func _append(rope: Dictionary, point: Vector3, normal: Vector3) -> void:
	var pts: PackedVector3Array = rope.pts
	var nrm: PackedVector3Array = rope.nrm
	pts.append(point)
	nrm.append(normal)
	rope.pts = pts
	rope.nrm = nrm


func _drop_tendril(index: int) -> void:
	var rope := ropes[index]
	_reaching.erase(rope.target)
	cut(index, 0)


## Its wrap's over (cut free, burned, or what it held died): the tendril goes.
func wrap_ended(index: int) -> void:
	if index < ropes.size() and ropes[index].kind == Kind.TENDRIL and ropes[index].state != State.DEAD:
		_drop_tendril(index)


func _chest(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * 1.1


func _nearest_life(at: Vector3, life: Array[Node3D], reach: float) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	for target in life:
		if not is_instance_valid(target):
			continue
		var d := target.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = target
	return best


func _living_ropes() -> int:
	var count := 0
	for rope in ropes:
		if rope.state != State.DEAD and rope.kind == Kind.CRAWL:
			count += 1
	return count


## A runner out to `other` (RedCreep's links): from the bush.
func send_runner(other: RedCreepPatch) -> int:
	var way := _tangent(other.global_position - global_position, surface_normal)
	var index := _new_rope(Kind.RUNNER, global_position + surface_normal * 0.05, surface_normal, way)
	ropes[index].target = other
	return index


## A runner's tip has reached `other`'s ground.
func runner_arrived(index: int, other: RedCreepPatch) -> bool:
	var rope := ropes[index]
	if rope.state == State.DEAD:
		return false
	var tip: Vector3 = rope.pts[rope.pts.size() - 1]
	return tip.distance_to(other.global_position) < 2.5 or other.touches(tip, 1.0)


## Whether `at` is on it: in the bush, or by a rope.
func touches(at: Vector3, reach: float) -> bool:
	if at.distance_to(global_position) < bush_reach() + reach * 0.5:
		return true
	for rope in ropes:
		if rope.state == State.DEAD or rope.kind == Kind.TENDRIL:
			continue
		var pts: PackedVector3Array = rope.pts
		for i in range(0, pts.size(), 2):
			if pts[i].distance_to(at) < reach:
				return true
	return false


## The tips of its ropes (corpses they reach turn into nurseries).
func tips() -> PackedVector3Array:
	var out := PackedVector3Array()
	for rope in ropes:
		if rope.state != State.DEAD and rope.kind != Kind.TENDRIL and not (rope.pts as PackedVector3Array).is_empty():
			out.append(rope.pts[rope.pts.size() - 1])
	return out


# ---- Cut and burned --------------------------------------------------------------------------

## A shot's path from `a` to `b`: every rope it passes through cut there.
## [[rope, point index], ...] (for the other games).
func cut_line(a: Vector3, b: Vector3) -> Array:
	var cuts: Array = []
	var middle := (a + b) * 0.5
	if middle.distance_to(global_position) - a.distance_to(b) * 0.5 > RADIUS + CLIMB_MAX:
		return cuts
	for r in ropes.size():
		var rope := ropes[r]
		if rope.state == State.DEAD:
			continue
		var pts: PackedVector3Array = rope.pts
		for i in pts.size() - 1:
			var near := Geometry3D.get_closest_points_between_segments(a, b, pts[i], pts[i + 1])
			if near[0].distance_to(near[1]) < CUT_RADIUS:
				cuts.append([r, i + 1])
				break
	for c: Array in cuts:
		cut(c[0], c[1])
	return cuts


## Fire at `at` (radius): every rope burned back from where it's caught;
## the bush caught, the whole patch. [[rope, index], ...], or null: the patch.
func burn_at(at: Vector3, radius: float) -> Variant:
	if at.distance_to(global_position) < radius + bush_reach():
		return null
	var cuts: Array = []
	for r in ropes.size():
		var rope := ropes[r]
		if rope.state == State.DEAD:
			continue
		var pts: PackedVector3Array = rope.pts
		for i in pts.size():
			if pts[i].distance_to(at) < radius:
				cuts.append([r, i])
				break
	for c: Array in cuts:
		cut(c[0], c[1])
	return cuts


## Rope `index` lost from point `from` on: that piece withers away; any rope
## forked off it, and any tendril off it, go too. A stump grows on again.
func cut(index: int, from: int) -> void:
	if index >= ropes.size():
		return
	var rope := ropes[index]
	if rope.state == State.DEAD:
		return
	var pts: PackedVector3Array = rope.pts
	from = clampi(from, 0, pts.size())
	if from < pts.size():
		_wither(pts.slice(maxi(from - 1, 0)), rope.shade)
	if rope.kind == Kind.TENDRIL and rope.target != null:
		# (it may be gone already: erasing and asking about it are safe)
		_reaching.erase(rope.target)
		if host:
			director.wrap_cut(rope.target)
	if from < 2:
		rope.state = State.DEAD
		rope.pts = PackedVector3Array()
		rope.nrm = PackedVector3Array()
	else:
		rope.pts = pts.slice(0, from)
		rope.nrm = (rope.nrm as PackedVector3Array).slice(0, from)
		if rope.kind != Kind.TENDRIL:
			rope.state = State.PAUSED
			rope.pause = REGROW_PAUSE
			rope.dangle = 0
		else:
			rope.state = State.DEAD
	rope.sent = mini(rope.sent, (rope.pts as PackedVector3Array).size())
	_mark(index)
	if host and rope.kind == Kind.RUNNER:
		director.runner_cut(self, index)
	for r in ropes.size():
		var other := ropes[r]
		var parent: Vector2i = other.parent
		if r != index and other.state != State.DEAD and parent.x == index and parent.y >= from:
			cut(r, 0)


## The whole patch withering away (burned at its bush).
func wither_all() -> void:
	for r in ropes.size():
		cut(r, 0)
	if _bush:
		var tween := create_tween()
		tween.tween_property(_bush, ^"scale", Vector3.ONE * 0.05, WITHER_TIME)
	get_tree().create_timer(WITHER_TIME + 0.1).timeout.connect(queue_free)


func _wither(pts: PackedVector3Array, shade: float) -> void:
	if pts.size() < 2:
		return
	var piece := MeshInstance3D.new()
	piece.mesh = _rope_mesh(pts, PackedVector3Array(), shade, Kind.CRAWL)
	piece.material_override = _material
	add_child(piece)
	piece.global_transform = Transform3D.IDENTITY
	var middle := Vector3.ZERO
	for p in pts:
		middle += p
	middle /= pts.size()
	# Shrivelling into itself, then gone.
	var tween := piece.create_tween()
	tween.tween_method(func(t: float) -> void:
		piece.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (1.0 - t)), middle * t), 0.0, 0.95, WITHER_TIME)
	tween.tween_callback(piece.queue_free)


# ---- The other games: told what grew ------------------------------------------------------------

## What's grown since last asked: [[rope, from index, points, normals, kind, parent], ...].
func take_growth() -> Array:
	var out: Array = []
	for r in ropes.size():
		var rope := ropes[r]
		var pts: PackedVector3Array = rope.pts
		if pts.size() > rope.sent:
			out.append([r, rope.sent, pts.slice(rope.sent), (rope.nrm as PackedVector3Array).slice(rope.sent), rope.kind, rope.parent])
			rope.sent = pts.size()
	return out


## Everything (a late joiner): from the start.
func all_growth() -> Array:
	var out: Array = []
	for r in ropes.size():
		var rope := ropes[r]
		out.append([r, 0, rope.pts, rope.nrm, rope.kind, rope.parent])
	return out


## A client: what the host's grown.
func apply_growth(growth: Array) -> void:
	for g: Array in growth:
		var r: int = g[0]
		while ropes.size() <= r:
			ropes.append({kind = Kind.CRAWL, state = State.GROWING, pts = PackedVector3Array(), nrm = PackedVector3Array(),
					heading = Vector3.FORWARD, carry = 0.0, wander = 0.0, dangle = 0, pause = 0.0, parent = Vector2i(-1, -1),
					target = null, shade = _rng.randf_range(0.5, 1.0), sent = 0, mesh = null})
		var rope := ropes[r]
		rope.kind = g[4]
		rope.parent = g[5]
		var from: int = g[1]
		var pts: PackedVector3Array = (rope.pts as PackedVector3Array).slice(0, from)
		var nrm: PackedVector3Array = (rope.nrm as PackedVector3Array).slice(0, from)
		pts.append_array(g[2])
		nrm.append_array(g[3])
		rope.pts = pts
		rope.nrm = nrm
		rope.state = State.GROWING if not pts.is_empty() else State.DEAD
		_mark(r)


# ---- Drawing ----------------------------------------------------------------------------------

func _mark(index: int) -> void:
	if not _dirty.has(index):
		_dirty.append(index)


func _process(_delta: float) -> void:
	# A few ropes remade a frame (only those that changed).
	for k in mini(MESH_BUDGET, _dirty.size()):
		var index: int = _dirty.pop_front()
		var rope := ropes[index]
		var pts: PackedVector3Array = rope.pts
		if pts.size() < 2:
			if rope.mesh and is_instance_valid(rope.mesh):
				(rope.mesh as Node).queue_free()
			rope.mesh = null
			continue
		if rope.mesh == null or not is_instance_valid(rope.mesh):
			var shown := MeshInstance3D.new()
			shown.material_override = _material
			shown.visibility_range_end = SEEN_RANGE
			shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(shown)
			shown.global_transform = Transform3D.IDENTITY
			rope.mesh = shown
		(rope.mesh as MeshInstance3D).mesh = _rope_mesh(pts, rope.nrm, rope.shade, rope.kind)


## A rope: two strands braided round its line (lying on the surfaces it
## crawls over), thinning to its tip. World space.
static func _rope_mesh(pts: PackedVector3Array, nrm: PackedVector3Array, shade: float, kind: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := pts.size()
	var total := 0.0
	var alongs := PackedFloat32Array([0.0])
	for i in range(1, count):
		total += pts[i].distance_to(pts[i - 1])
		alongs.append(total)
	for strand in 2:
		var centres := PackedVector3Array()
		var radii := PackedFloat32Array()
		var frees := PackedFloat32Array()
		for i in count:
			var forward := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var up: Vector3 = nrm[i] if i < nrm.size() else Vector3.UP
			var side := forward.cross(up)
			if side.length_squared() < 0.0001:
				side = forward.cross(Vector3.RIGHT)
			side = side.normalized()
			up = side.cross(forward).normalized()
			var turn := alongs[i] / TWIST * TAU + PI * strand
			var left := total - alongs[i]
			var thin := clampf(left / 1.5, 0.35, 1.0)
			centres.append(pts[i] + up * (STRAND + BRAID * 0.6 * cos(turn)) + side * BRAID * sin(turn) * thin)
			radii.append(STRAND * thin)
			var free := 0.08 + 0.5 * (1.0 - clampf(left, 0.0, 1.0))
			if kind == Kind.TENDRIL:
				free = lerpf(0.3, 1.0, alongs[i] / maxf(total, 0.01))
			frees.append(free)
		_strand(tool, centres, radii, frees, alongs, shade)
	return tool.commit()


static func _strand(tool: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, free: PackedFloat32Array,
		alongs: PackedFloat32Array, shade: float) -> void:
	var count := points.size()
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in count:
		var forward := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := forward.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(forward).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for s in SIDES:
			var a := TAU * s / SIDES
			var out := side * cos(a) + up * sin(a)
			ring.append(points[i] + out * radii[i])
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	for i in count - 1:
		var ca := Color(free[i], shade, fmod(alongs[i], 32.0) / 32.0)
		var cb := Color(free[i + 1], shade, fmod(alongs[i + 1], 32.0) / 32.0)
		for s in SIDES:
			var n := (s + 1) % SIDES
			for corner: Array in [[i, s, ca], [i, n, ca], [i + 1, n, cb], [i, s, ca], [i + 1, n, cb], [i + 1, s, cb]]:
				tool.set_color(corner[2])
				tool.set_normal(normals[corner[0]][corner[1]])
				tool.add_vertex(rings[corner[0]][corner[1]])


static func _tangent(v: Vector3, n: Vector3) -> Vector3:
	var flat := v - n * v.dot(n)
	if flat.length_squared() < 0.0001:
		flat = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	return flat.normalized()


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
