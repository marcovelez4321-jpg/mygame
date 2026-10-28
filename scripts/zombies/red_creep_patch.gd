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
## SMOOTH (the user's, 2026-10-27: no growth spurts -- like an arm reaching):
## a rope's points are worked out a step ahead of its tip, and the tip slides
## out along them continuously (`shown`; the shader draws it only that far,
## tapering to a point). CHEAP: a rope is drawn in pieces of CHUNK points;
## only its newest piece is ever remade (RedCreep queues them, a few a
## frame); far from everyone and out of sight (FAR), it grows in coarse
## FAR_STEP steps with nothing drawn, and is drawn again as you come near.
## Rule 1 (co-op): the host grows it; every game is sent the points
## (RedCreep) and slides the same tips out along them.

enum Kind { CRAWL, TENDRIL, RUNNER }
enum State { GROWING, RESTING, PAUSED, WRAPPING, DEAD }

const GROW_SPEED := 1.0 / 3.0 # (the user's: steady, about 1 m every 3 s)
const REACH_SPEED := 1.6
const STEP := 0.35
const LOOKAHEAD := STEP * 1.5
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
const CHUNK := 12
const SEEN_RANGE := 90.0
## Full growing within NEAR of a player (or on the host's screen); past it,
## FAR_STEP steps at a time.
const NEAR := 45.0
const FAR_STEP := 2.0
const SHOWN_ALL := 1000000.0

var id := 0
var director: RedCreep
var surface_normal := Vector3.UP
var bush_size := 2.0
var host := true
## [rope dict] (indices never reused: a dead rope stays, empty).
var ropes: Array[Dictionary] = []
## Close enough to someone (or on screen) to grow in full (the host's).
var near := true
## Who each tendril's reaching for: target -> rope index.
var _reaching := {}
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _bush: MeshInstance3D
var _notifier: VisibleOnScreenNotifier3D
var _on_screen := false
var _far_left := 0.0
## Ropes whose pieces need remaking once it's in sight again.
var _stale := {}


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
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-RADIUS - 2.0, -3.0, -RADIUS - 2.0), Vector3(RADIUS * 2.0 + 4.0, CLIMB_MAX + 5.0, RADIUS * 2.0 + 4.0))
	add_child(_notifier)
	_notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		_refresh_stale())
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	if host:
		for i in START_ROPES:
			var way := _tangent(Vector3.FORWARD.rotated(surface_normal, TAU * (float(i) + _rng.randf() * 0.6) / START_ROPES), surface_normal)
			_new_rope(Kind.CRAWL, global_position + surface_normal * 0.05, surface_normal, way)


func set_pulse(phase: float) -> void:
	_material.set_shader_parameter(&"pulse_phase", phase)


## How big the bush is (a seed's touch: within it).
func bush_reach() -> float:
	return bush_size * 0.9


## Whether it's drawn now: in sight of this game's camera, or close.
func drawn() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var d := camera.global_position.distance_to(global_position)
	return d < SEEN_RANGE + RADIUS and (_on_screen or d < RADIUS + 15.0)


# ---- Every frame: tips sliding out, and (the host) growing ----------------------------------

func _process(delta: float) -> void:
	if host:
		if near:
			_grow(delta)
		else:
			_far_left += delta
			if _far_left >= FAR_STEP:
				_grow(_far_left)
				_far_left = 0.0
	else:
		_follow(delta)
	if drawn():
		_show_tips()


## The host: every rope's tip on along its way, and its next points worked
## out as the tip nears the end of them.
func _grow(delta: float) -> void:
	var life := director.life()
	for index in ropes.size():
		var rope := ropes[index]
		match rope.state:
			State.PAUSED:
				rope.pause -= delta
				if rope.pause <= 0.0:
					rope.state = State.GROWING
					rope.stuck = false
			State.GROWING:
				if rope.kind == Kind.TENDRIL:
					_reach_on(index, delta)
					continue
				var length := _length(rope)
				rope.shown = minf(rope.shown + GROW_SPEED * rope.boost * delta, length)
				var tries := 0
				while not rope.stuck and _length(rope) - rope.shown < LOOKAHEAD and tries < 8:
					tries += 1
					if not _advance(index, life):
						rope.stuck = true
				if rope.stuck and rope.shown >= _length(rope) - 0.01:
					rope.state = State.RESTING


## A client: tips slide out along what the host's sent, at the same pace
## (quicker if they've fallen behind).
func _follow(delta: float) -> void:
	for rope in ropes:
		if rope.state == State.DEAD:
			continue
		var length := _length(rope)
		var speed := REACH_SPEED if rope.kind == Kind.TENDRIL else GROW_SPEED
		if length - rope.shown > 2.0:
			speed *= 3.0
		rope.shown = minf(rope.shown + speed * delta, length)


## Each rope's newest pieces drawn only as far as its tip.
func _show_tips() -> void:
	for rope in ropes:
		var chunks: Array = rope.chunks
		for k in range(chunks.size() - 1, -1, -1):
			var piece := chunks[k] as MeshInstance3D
			if not is_instance_valid(piece):
				continue
			var ends: float = piece.get_meta(&"ends", 0.0)
			if ends <= rope.shown and piece.get_meta(&"all", false):
				break
			var all: bool = ends <= rope.shown
			piece.set_instance_shader_parameter(&"grow_to", SHOWN_ALL if all else rope.shown)
			piece.set_meta(&"all", all)


func _new_rope(kind: Kind, at: Vector3, normal: Vector3, heading: Vector3, parent := Vector2i(-1, -1)) -> int:
	ropes.append(_blank_rope(kind, parent))
	var rope := ropes[ropes.size() - 1]
	rope.pts = PackedVector3Array([at])
	rope.nrm = PackedVector3Array([normal])
	rope.alg = PackedFloat32Array([0.0])
	rope.heading = heading
	return ropes.size() - 1


func _blank_rope(kind: int, parent: Vector2i) -> Dictionary:
	return {kind = kind, state = State.GROWING, pts = PackedVector3Array(), nrm = PackedVector3Array(), alg = PackedFloat32Array(),
			shown = 0.0, stuck = false, boost = 1.0, heading = Vector3.FORWARD, wander = 0.0, dangle = 0, pause = 0.0,
			parent = parent, target = null, shade = _rng.randf_range(0.5, 1.0), sent = 0, chunks = [], dirty_from = -1}


static func _length(rope: Dictionary) -> float:
	var alg: PackedFloat32Array = rope.alg
	return alg[alg.size() - 1] if not alg.is_empty() else 0.0


## Where the tip is now (`shown` along it).
static func tip_of(rope: Dictionary) -> Vector3:
	var pts: PackedVector3Array = rope.pts
	var alg: PackedFloat32Array = rope.alg
	if pts.is_empty():
		return Vector3.INF
	var shown: float = rope.shown
	for i in range(1, pts.size()):
		if alg[i] >= shown:
			var span := maxf(alg[i] - alg[i - 1], 0.0001)
			return pts[i - 1].lerp(pts[i], (shown - alg[i - 1]) / span)
	return pts[pts.size() - 1]


## One STEP more of its way worked out. False: it can't (or mustn't) go on.
func _advance(index: int, life: Array[Node3D]) -> bool:
	var rope := ropes[index]
	var p: Vector3 = rope.pts[rope.pts.size() - 1]
	var n: Vector3 = rope.nrm[rope.nrm.size() - 1]
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	if rope.kind == Kind.CRAWL and (flat > RADIUS or p.y - global_position.y > CLIMB_MAX):
		return false
	var lure := director.stimulus_near(p)
	rope.boost = RedCreep.STIMULUS_BOOST if lure.is_finite() else 1.0
	# Feeling its way: a slow wander, then drawn to what it wants.
	rope.wander = clampf(rope.wander + _rng.randf_range(-0.35, 0.35), -0.8, 0.8)
	var heading: Vector3 = (rope.heading as Vector3).rotated(n, rope.wander * 0.3)
	var want := Vector3.INF
	var pull := 0.0
	if rope.kind == Kind.RUNNER and is_instance_valid(rope.target) and rope.target is RedCreepPatch:
		want = (rope.target as Node3D).global_position
		pull = 1.5
	else:
		var close := _nearest_life(p, life, SENSE)
		if close:
			want = close.global_position
			pull = 1.2
		elif lure.is_finite():
			want = lure
			pull = 1.0
	if rope.kind == Kind.CRAWL and flat > RADIUS * 0.75:
		heading += _tangent(global_position - p, n) * (flat - RADIUS * 0.75) / (RADIUS * 0.25) * 1.5
	if want.is_finite():
		heading += _tangent(want - p, n) * pull
	heading = _tangent(heading, n)
	if FireSource.near_point(p + heading * STEP, 1.2):
		heading = heading.rotated(n, PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0))
	var next := _crawl(p, n, heading, rope)
	if next.is_empty():
		return false
	_append(index, next[0], next[1])
	rope.heading = next[2]
	# Forking now and then (a crawl's, once it's out a way).
	if rope.kind == Kind.CRAWL and rope.pts.size() > 8 and _living_ropes() < MAX_ROPES and _rng.randf() < BRANCH_CHANCE:
		var fork := (next[2] as Vector3).rotated(next[1], deg_to_rad(50.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
		_new_rope(Kind.CRAWL, next[0], next[1], fork, Vector2i(index, rope.pts.size() - 1))
	return true


## (Packed arrays come out of a dictionary as copies: put back.)
func _append(index: int, point: Vector3, normal: Vector3) -> void:
	var rope := ropes[index]
	var pts: PackedVector3Array = rope.pts
	var nrm: PackedVector3Array = rope.nrm
	var alg: PackedFloat32Array = rope.alg
	alg.append((alg[alg.size() - 1] if not alg.is_empty() else 0.0) + (pts[pts.size() - 1].distance_to(point) if not pts.is_empty() else 0.0))
	pts.append(point)
	nrm.append(normal)
	rope.pts = pts
	rope.nrm = nrm
	rope.alg = alg
	_mark(index, pts.size() - 2)


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


# ---- Reaching for life (the host's) ----------------------------------------------------------

## Life within REACH of a rope (not already reached for, not already
## wrapped): a tendril rises off the nearest point toward it.
func reach_for(life: Array[Node3D]) -> void:
	for gone: Variant in _reaching.keys():
		if not is_instance_valid(gone):
			_reaching.erase(gone)
	for target in life:
		if not is_instance_valid(target) or _reaching.has(target) or director.is_wrapped(target):
			continue
		var to := target.global_position
		if Vector2(to.x - global_position.x, to.z - global_position.z).length() > RADIUS + REACH + 2.0:
			continue
		var best_d := REACH
		var best_rope := -1
		var best_i := 0
		for r in ropes.size():
			var rope := ropes[r]
			if rope.state == State.DEAD or rope.kind == Kind.TENDRIL:
				continue
			var pts: PackedVector3Array = rope.pts
			var alg: PackedFloat32Array = rope.alg
			for i in range(0, pts.size(), 2):
				if alg[i] > rope.shown:
					break # (not grown that far yet)
				var d := pts[i].distance_to(to)
				if d < best_d:
					best_d = d
					best_rope = r
					best_i = i
		if best_rope < 0:
			continue
		var from: Vector3 = ropes[best_rope].pts[best_i]
		var up: Vector3 = ropes[best_rope].nrm[best_i]
		var tendril := _new_rope(Kind.TENDRIL, from, up, (_chest(target) - from).normalized(), Vector2i(best_rope, best_i))
		ropes[tendril].target = target
		_reaching[target] = tendril


## A tendril reaching on through the air for its target, its tip sliding
## smoothly out (`shown`), its way worked out ahead; touching it, the wrap
## (RedCreep.start_wrap); lost (gone, dead, moved off), it withers.
func _reach_on(index: int, delta: float) -> void:
	var rope := ropes[index]
	var target := rope.target as Node3D
	var root: Vector3 = rope.pts[0]
	if not is_instance_valid(target) or not Factions.is_alive_target(target) or target.global_position.distance_to(root) > REACH_LOST:
		_drop_tendril(index)
		return
	var chest := _chest(target)
	rope.shown = minf(rope.shown + REACH_SPEED * delta, _length(rope))
	var tries := 0
	while _length(rope) - rope.shown < LOOKAHEAD and tries < 8:
		tries += 1
		var tip: Vector3 = rope.pts[rope.pts.size() - 1]
		if tip.distance_to(chest) < TOUCH * 0.5:
			break
		var way := (chest - tip).normalized()
		# A worm's reach: curling as it comes.
		var side := way.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var step := minf(STEP * 0.6, tip.distance_to(chest))
		_append(index, tip + (way + side * sin(rope.pts.size() * 0.9) * 0.35).normalized() * step, side.cross(way).normalized())
	if tip_of(rope).distance_to(chest) < TOUCH:
		rope.state = State.WRAPPING
		rope.shown = _length(rope)
		director.start_wrap(target, self, index)


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
	var tip := tip_of(rope)
	return tip.distance_to(other.global_position) < 2.5 or other.touches(tip, 1.0)


## Whether `at` is on it: in the bush, or by a rope (as far as it's grown).
func touches(at: Vector3, reach: float) -> bool:
	if at.distance_to(global_position) < bush_reach() + reach * 0.5:
		return true
	for rope in ropes:
		if rope.state == State.DEAD or rope.kind == Kind.TENDRIL:
			continue
		var pts: PackedVector3Array = rope.pts
		var alg: PackedFloat32Array = rope.alg
		for i in range(0, pts.size(), 2):
			if alg[i] > rope.shown:
				break
			if pts[i].distance_to(at) < reach:
				return true
	return false


## Where its ropes' tips are now (corpses they reach turn into nurseries).
func tips() -> PackedVector3Array:
	var out := PackedVector3Array()
	for rope in ropes:
		if rope.state != State.DEAD and rope.kind != Kind.TENDRIL and not (rope.pts as PackedVector3Array).is_empty():
			out.append(tip_of(rope))
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
		var alg: PackedFloat32Array = rope.alg
		for i in pts.size() - 1:
			if alg[i] > rope.shown:
				break
			var near_points := Geometry3D.get_closest_points_between_segments(a, b, pts[i], pts[i + 1])
			if near_points[0].distance_to(near_points[1]) < CUT_RADIUS:
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
	if from < pts.size() and drawn():
		var lost := pts.slice(maxi(from - 1, 0))
		var alg: PackedFloat32Array = rope.alg
		var shown_lost := 0
		while shown_lost < lost.size() and alg[maxi(from - 1, 0) + shown_lost] <= rope.shown:
			shown_lost += 1
		_wither(lost.slice(0, shown_lost), rope.shade)
	if rope.kind == Kind.TENDRIL and rope.target != null:
		# (it may be gone already: erasing and asking about it are safe)
		_reaching.erase(rope.target)
		if host:
			director.wrap_cut(rope.target)
	if from < 2:
		rope.state = State.DEAD
		rope.pts = PackedVector3Array()
		rope.nrm = PackedVector3Array()
		rope.alg = PackedFloat32Array()
		rope.shown = 0.0
	else:
		rope.pts = pts.slice(0, from)
		rope.nrm = (rope.nrm as PackedVector3Array).slice(0, from)
		rope.alg = (rope.alg as PackedFloat32Array).slice(0, from)
		rope.shown = minf(rope.shown, _length(rope))
		rope.stuck = false
		if rope.kind != Kind.TENDRIL:
			rope.state = State.PAUSED
			rope.pause = REGROW_PAUSE
			rope.dangle = 0
		else:
			rope.state = State.DEAD
	rope.sent = mini(rope.sent, (rope.pts as PackedVector3Array).size())
	_mark(index, from - 1)
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
	var alg := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		alg.append(alg[i - 1] + pts[i].distance_to(pts[i - 1]))
	var piece := MeshInstance3D.new()
	piece.mesh = _piece_mesh(pts, PackedVector3Array(), alg, alg[alg.size() - 1], shade, Kind.CRAWL)
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

## What's been worked out since last asked: [[rope, from index, points,
## normals, kind, parent], ...].
func take_growth() -> Array:
	var out: Array = []
	for r in ropes.size():
		var rope := ropes[r]
		var pts: PackedVector3Array = rope.pts
		if pts.size() > rope.sent:
			out.append([r, rope.sent, pts.slice(rope.sent), (rope.nrm as PackedVector3Array).slice(rope.sent), rope.kind, rope.parent])
			rope.sent = pts.size()
	return out


## Everything (a late joiner): from the start, its tips where they are.
func all_growth() -> Array:
	var out: Array = []
	for r in ropes.size():
		var rope := ropes[r]
		out.append([r, 0, rope.pts, rope.nrm, rope.kind, rope.parent, rope.shown])
	return out


## A client: what the host's worked out.
func apply_growth(growth: Array) -> void:
	for g: Array in growth:
		var r: int = g[0]
		while ropes.size() <= r:
			ropes.append(_blank_rope(Kind.CRAWL, Vector2i(-1, -1)))
		var rope := ropes[r]
		rope.kind = g[4]
		rope.parent = g[5]
		var from: int = g[1]
		var pts: PackedVector3Array = (rope.pts as PackedVector3Array).slice(0, from)
		var nrm: PackedVector3Array = (rope.nrm as PackedVector3Array).slice(0, from)
		pts.append_array(g[2])
		nrm.append_array(g[3])
		var alg := PackedFloat32Array()
		for i in pts.size():
			alg.append(0.0 if i == 0 else alg[i - 1] + pts[i].distance_to(pts[i - 1]))
		rope.pts = pts
		rope.nrm = nrm
		rope.alg = alg
		if g.size() > 6:
			rope.shown = g[6]
		rope.shown = minf(rope.shown, _length(rope))
		rope.state = State.GROWING if not pts.is_empty() else State.DEAD
		_mark(r, from - 1)


# ---- Drawing: a rope in pieces, only its newest remade ------------------------------------------

## Rope `index` has changed from point `from` on: its pieces from there are
## remade (now if it's drawn, else once it is).
func _mark(index: int, from: int) -> void:
	var rope := ropes[index]
	var chunk := maxi(from, 0) / CHUNK
	rope.dirty_from = chunk if rope.dirty_from < 0 else mini(rope.dirty_from, chunk)
	if drawn():
		director.queue_mesh(self, index)
	else:
		_stale[index] = true


## Back in sight: everything that changed meanwhile, queued.
func _refresh_stale() -> void:
	for index: int in _stale.keys():
		director.queue_mesh(self, index)
	_stale.clear()


## RedCreep, a few a frame: rope `index`'s changed pieces remade.
func rebuild(index: int) -> void:
	if index >= ropes.size():
		return
	var rope := ropes[index]
	var from: int = rope.dirty_from
	if from < 0:
		return
	rope.dirty_from = -1
	var pts: PackedVector3Array = rope.pts
	var nrm: PackedVector3Array = rope.nrm
	var alg: PackedFloat32Array = rope.alg
	var chunks: Array = rope.chunks
	var wanted := 0 if pts.size() < 2 else ceili(float(pts.size() - 1) / CHUNK)
	while chunks.size() > wanted:
		var extra = chunks.pop_back()
		if is_instance_valid(extra):
			(extra as Node).queue_free()
	var total := _length(rope)
	for k in range(from, wanted):
		var a := k * CHUNK
		var b := mini(a + CHUNK, pts.size() - 1)
		var piece: MeshInstance3D
		if k < chunks.size() and is_instance_valid(chunks[k]):
			piece = chunks[k]
		else:
			piece = MeshInstance3D.new()
			piece.material_override = _material
			piece.visibility_range_end = SEEN_RANGE
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(piece)
			piece.global_transform = Transform3D.IDENTITY
			if k < chunks.size():
				chunks[k] = piece
			else:
				chunks.append(piece)
		piece.mesh = _piece_mesh(pts.slice(a, b + 1), nrm.slice(a, b + 1), alg.slice(a, b + 1), total, rope.shade, rope.kind)
		piece.set_meta(&"ends", alg[b])
		piece.set_meta(&"all", false)
		piece.set_instance_shader_parameter(&"grow_to", rope.shown)
	rope.chunks = chunks


## A piece of rope: two strands braided round its line (lying on the
## surfaces it crawls over), thinning to its tip. World space.
static func _piece_mesh(pts: PackedVector3Array, nrm: PackedVector3Array, alg: PackedFloat32Array, total: float, shade: float, kind: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var count := pts.size()
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
			var turn := alg[i] / TWIST * TAU + PI * strand
			centres.append(pts[i] + up * (STRAND + BRAID * 0.6 * cos(turn)) + side * BRAID * sin(turn))
			radii.append(STRAND)
			var free := 0.08
			if kind == Kind.TENDRIL:
				free = lerpf(0.3, 1.0, alg[i] / maxf(total, 0.01))
			frees.append(free)
		_strand(tool, centres, radii, frees, alg, shade)
	return tool.commit()


## One strand: a tube through `points`, CUSTOM0 its line and how far along
## (the shader's tip), COLOR its freedom and shade. The caller sets the
## tool's custom format (CUSTOM_RGBA_FLOAT on 0).
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
		var ca := Color(free[i], shade, 0.0)
		var cb := Color(free[i + 1], shade, 0.0)
		var la := Color(points[i].x, points[i].y, points[i].z, alongs[i])
		var lb := Color(points[i + 1].x, points[i + 1].y, points[i + 1].z, alongs[i + 1])
		for s in SIDES:
			var n := (s + 1) % SIDES
			for corner: Array in [[i, s, ca, la], [i, n, ca, la], [i + 1, n, cb, lb], [i, s, ca, la], [i + 1, n, cb, lb], [i + 1, s, cb, lb]]:
				tool.set_color(corner[2])
				tool.set_custom(0, corner[3])
				tool.set_normal(normals[corner[0]][corner[1]])
				tool.add_vertex(rings[corner[0]][corner[1]])


static func _tangent(v: Vector3, n: Vector3) -> Vector3:
	var flat := v - n * v.dot(n)
	if flat.length_squared() < 0.0001:
		flat = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	return flat.normalized()


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
