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
##   Lost them: it hunts them down their trail (HUNT; it used to turn up
##   out of nowhere -- now only back from AWAY, and down their trail then).
## Stunts, the fear meter and the strike come next (stages 2-3).
## Its body (every screen): two-bone IK on each arm and leg, planted hands
## and feet stepping in diagonal pairs -- jerky, broken-jointed (The Grudge)
## -- the spine riding them on a spring, and the head locked on you, tilted
## wrong, now and then snapping to a new tilt.
## Rule 1 (co-op): the host runs it; everyone else sees its puppet
## (NetEntities: its transform carries the surface it's on), and works the
## body out from that.

enum State { STALK, SPOTTED, HIDE, WAIT, FALL, FLEE, AWAY, STUNT, APPROACH, LUNGE, DRAG, HUNT }
## Its stunts (the user's, stage 2) -- each staged to scare, then it's gone.
enum Stunt { BEHIND, CEILING, DOORWAY, WATCH, RATTLE, DRAG, LEAP, HELP }

const MODEL := preload("res://art/characters/Characters_psx/Models/Killers/Character_Monster_03.fbx")
## Speeds (the user's): crawling, scrambling away to hide when it's looked
## at (slow enough to watch it skitter out of view), sprinting (driven off).
## Spotted, it first freezes SPOTTED_FREEZE s, staring, then scrambles.
const CRAWL := 13.0
const SCRAMBLE := 17.0
const SPRINT := 22.0
const SPOTTED_FREEZE := 1.0
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
## Never far behind (the user's: it lost you too easily -- Alien: Isolation's
## "backstage"): unseen, it doesn't crawl all the way. More than LEASH from
## everyone for LEASH_TIME, or not gaining STUCK_GAIN on them in STUCK_TIME
## (hung up on a wall, a ceiling, the land), it turns up again out of sight
## BACKSTAGE_TO from one of them.
## (25% less clingy, the user's: was 90 m, 6 s, 6 s, 35-55 m.)
const LEASH := 112.5
const LEASH_TIME := 7.5
const STUCK_TIME := 7.5
const STUCK_GAIN := 2.0
const BACKSTAGE_TO := Vector2(44.0, 69.0)
var _leash_for := 0.0
var _stuck_for := 0.0
var _stuck_best := INF
## Indoors, how long it's had no way through to them (another floor, a wall).
var _cut_for := 0.0
## Each player's trail: player -> {points, leaps (1: a jump to that crumb),
## length, aired, msec}.
var _trails := {}
## Who it's hunting, the crumb it's making for, and how long it's not seen them.
var _hunted: PlayerMovement
var _crumb := 0
var _unseen_for := 0.0
var _sight_check := 0.0
var _crumb_best := INF
var _crumb_stall := 0.0
var _skip_check := 0.0
var _flee_side := 1.0
## How long it's been heading for its hiding spot (never there by STUCK_TIME:
## it waits where it is -- not hiding for ever, never stalking or staging).
var _hiding_for := 0.0
## Up the walls, like a spider (the user's): it stalks from a PERCH -- a
## spot PERCH_HEIGHT up a wall near where it means to be, or indoors (half
## the time) on the ceiling -- picked again every PERCH_EVERY; and it hides
## up walls and on ceilings as readily as round a corner (higher is better).
const PERCH_HEIGHT := Vector2(2.0, 6.0)
const PERCH_EVERY := 3.0
const PERCH_REACH := 15.0
const PERCH_CHANCE := 0.4
var _perch := Vector3.INF
## Getting away (the user's): it first runs straight off from the players
## for RUN_OFF_TIME, then picks cover further from them than it is. Stuck
## (not moving UNSTICK_MOVE in UNSTICK_EVERY while it means to) on a wall or
## a ceiling, it lets go and drops to the floor, and picks cover on the
## floor; stuck on the floor, other cover.
const RUN_OFF_TIME := 1.5
const UNSTICK_EVERY := 1.5
const UNSTICK_MOVE := 0.6
var _run_off_left := 0.0
var _check_pos := Vector3.ZERO
var _check_left := UNSTICK_EVERY
var _floor_only := false
var _perch_left := 0.0
const WALL_DOT := 0.7
## Twice a person (the user's): everything about its body scales with this.
const SIZE := 2.0
const RIDE := 0.25 * SIZE
const SPAN := 1.6 * SIZE
const GRAVITY := 22.0
const AWAY_DEPTH := -5000.0
## The body (looks): how high the spine rides, the hands' and feet's spots
## round it, how far one strays before it steps, how high and how fast.
const BODY_HEIGHT := 0.6 * SIZE
const STRIDE := 0.5 * SIZE
const STEP_HEIGHT := 0.28 * SIZE
const STEP_TIME := 0.32 * sqrt(SIZE)
const STANDING_HEIGHT := 1.9 * SIZE

## STAGE 2 (the user's): stunts every STUNT_EVERY, and the shared FEAR
## meter (hidden). A reaction within REACT_WINDOW of a stunt fills it (each
## once a stunt you saw): seeing it, panic firing, running off, whipping
## round; going to where it screamed for help, on purpose, fills half. A
## clear glimpse of it outside a stunt counts as seeing it too (see
## GLIMPSE_*). Each rise shows why under the meter. It drains over FEAR_DRAIN_TIME,
## and once it's full it stays full: the strike (stage 3) can come.
const STUNT_EVERY := Vector2(30.0, 60.0)
const REACT_WINDOW := 3.0
## (Doubled, the user's: 15/10/10/5/50 % before.)
## (Halved, the user's 2026-10-17: it filled too fast -- was 0.30, 0.20, 0.20, 0.10, 1.0.)
const FEAR_SEEN := 0.15
const FEAR_FIRE := 0.10
const FEAR_FLEE := 0.10
const FEAR_SPIN := 0.05
const FEAR_HELP := 0.5
const FEAR_DRAIN_TIME := 300.0
## Full, it stays full this long (seconds) if it hasn't had you -- then the
## slow drain again (the user's).
const FEAR_HOLD := 120.0
## (The user's, 2026-10-18: going to the scream on purpose -- within
## INVESTIGATE_REACH of it inside INVESTIGATE_WITHIN of hearing it.)
const INVESTIGATE_REACH := 15.0
const INVESTIGATE_WITHIN := 60.0
## Glimpsed (the user's, 2026-10-18): only when it's clearly in view -- within
## GLIMPSE_CONE of the middle of your view, GLIMPSE_RANGE off (through the
## fog), for GLIMPSE_TIME -- once a sighting; not a hand at the screen's edge.
## (It still hides whenever it's anywhere in your view.) Reactions (running
## off, whipping round, panic fire) count only after a stunt you saw, or one
## right beside you.
const GLIMPSE_CONE := 30.0
const GLIMPSE_RANGE := 60.0
const GLIMPSE_TIME := 0.3
## Looked straight at (degrees off centre): a watching one's cue to go.
const STARED_AT := 12.0
const SPIN_RATE := 4.7 # rad/s: whipping round
## Each stunt (the user's): these words on its player's screen.
const TINGLE := "A tingle goes down your spine."
const FLEE_SPEED := 7.0
const DRAG_SPEED := 5.0
const CORPSE := preload("res://scenes/enemy/enemy.tscn")

## STAGE 3 (the user's): the fear full, it goes for a player caught off guard
## (any one: looking away, reloading or hands busy, alone -- no teammate
## within ALONE_RANGE -- or grappling): closes in unseen behind them, lunges
## (LUNGE), and on reaching them drags them off by a foot (StalkerDrag) at
## DRAG_PULL for DRAG_TIME. Loose (spam clicks, or TEAMMATE_FREES damage from
## someone else): it scrambles off, the fear spent. Not loose in time:
## DRAG_DAMAGE, dropped there in the dark. Either way it runs flat out to cover,
## then waits out its COOLDOWN before staging or striking again.
const LUNGE := 25.0
const LUNGE_FROM := 12.0
const LUNGE_TIME := 2.5
const APPROACH_BEHIND := 8.0
const ALONE_RANGE := 25.0
const DRAG_PULL := 8.0
const DRAG_TIME := 15.0
const DRAG_DAMAGE := 70.0
const TEAMMATE_FREES := 30.0

const THROW_SPEED := 30.0
const THROW_DAMAGE := 50.0

const COOLDOWN := Vector2(120.0, 180.0)

const RUSHED_RANGE := 20.0
const RUSHED_SPEED := 1.25
## (The user's, 2026-10-18: 20 -- get within 20 m of it, looking at it or
## not, and it lunges for the grab; was 10, an instant grab.)
const GRAB_RANGE := 20.0

## HUNTING (the user's, 2026-10-18): it follows your trail. Every player
## leaves one -- a crumb every CRUMB_EVERY metres wherever they touch ground
## or a wall, a jump or grapple across a gap (over LEAP_GAP) kept as a leap --
## the last TRAIL_LENGTH of it. Out of its sight for HUNT_AFTER (any fear),
## it hunts the nearest player down their trail at HUNT_SPEED, crumb to
## crumb along the very way they went, leaping their gaps. Fallen more than
## TRAIL_LENGTH behind (off the far end of their trail: further than
## FELL_OFF from its oldest crumb), it's put back on it at that far end, 600 m
## back, where no one can see it (the user's). Seeing them again, or within
## HUNT_UNTIL, it stalks again (or, at full fear, flanks). Spotted while
## hunting, it bolts and hides like ever, then picks the trail back up. Its
## skitter carries HUNT_HEAR times as far while it hunts.
const HUNT_SPEED := 25.0
const HUNT_AFTER := 3.0
const HUNT_UNTIL := 30.0
const CRUMB_EVERY := 3.0
const TRAIL_LENGTH := 600.0
## Further than this from their trail's far end (with its oldest crumb the
## one it's making for): it's fallen more than TRAIL_LENGTH behind.
const FELL_OFF := 40.0
const LEAP_GAP := 6.0
## Faster than this between crumbs (m/s), they didn't travel it: a respawn,
## a teleport -- the trail starts over.
const TRAIL_BREAK_SPEED := 120.0
const CRUMB_REACH := 3.5
const HUNT_HEAR := 3.0
## FULL FEAR, not being looked at (the user's): it flanks round behind you
## at FLANK_SPEED on a ring FLANK_RING out, then creeps in -- and within
## GRAB_RANGE it lunges. Spotted further off: no stare, it bolts sideways
## out of your view, zigzagging, frantic, then hides.
const FLANK_SPEED := 18.0
const FLANK_RING := 20.0 
var _cooldown_left := 0.0
var _hide_fast := false
var _victim: PlayerMovement
var _drag_way := Vector3.FORWARD
var _freed_by_others := 0.0

var fear := 0.0
var _full_for := 0.0
var _stunt := Stunt.RATTLE
var _stunt_phase := 0
var _stunt_target: PlayerMovement
var _stunt_to := Vector3.ZERO
var _stunt_seen := false
var _stunt_away_for := 0.0
var _stunt_rattle_left := 0.0
var _stunt_left_every := 40.0
var _corpse: Enemy
var _moment_msec := -100000
var _reacted := {}
var _yaws := {}
var _help_spot := Vector3.INF
var _help_time := 0.0
var _clear_for := 0.0
var _unclear_for := 0.0
var _glimpse_counted := false
## The reaction window's stunt was seen (or right beside them).
var _moment_perceived := false
var _fire_hooked := {}
var _hook_left := 0.0
var _skitter: AudioStreamPlayer3D
var _airborne := false

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
## Hitboxes on its bones (the user's: shots hit only sometimes -- one capsule
## down its spine missed the sprawled limbs, and the drawn body trailed the
## real one): a capsule per part, moved onto its bones every physics tick.
## [shape, from bone, to bone (-1: a ball at `from`), radius].
var _hitboxes: Array = []
## Its eyes (the user's): blue, piercing, unmissable -- through the fog and
## the dark (no fog on them): two hot points that stay a few pixels big
## however far off it is. No glow round them. Walls still hide them.
const EYE_COLOR := Color(0.3, 0.62, 1.0)
## How strong the blue glare round each eye is (the user's: half, 2026-10-18).
const EYE_GLOW := 0.5
const EYE_CORE := 0.12 # m (the eye itself, up close)
## The glare: screen-steady (fixed_size: as if this big at 1 m) -- a pinpoint,
## ~6 px (the user's: at 0.045 it was ~20 px an eye, over its whole body far off).
const EYE_GLARE := 0.012

## Where the eyes sit on the head bone (a person's, scaled to its size).
const EYE_FORWARD := 0.09
const EYE_UP := 0.08
const EYE_APART := 0.034
var _eyes: Array[Node3D] = []

## The neck and head bobble as it goes (the user's: the Harvestmen's jiggle
## limbs, JiggleLimb -- Half-Life 2's $jigglebone): each a point on a spring
## pulling back to its own shape, gravity dragging, damped; the body's moves
## swing them and every hand or foot planting gives the head a little kick.
## The head still locks on you, the bobble laid over it.
const JIGGLE_STIFFNESS := 13.0
const JIGGLE_DAMPING := 2.4
const JIGGLE_GRAVITY := 6.0
const STEP_KICK := 1.2
## How much of the springs' swing shows (the user's: half -- it shook too wildly).
const JIGGLE_AMOUNT := 0.5
var _neck_point := Vector3.INF
var _neck_velocity := Vector3.ZERO
var _head_point := Vector3.INF
var _head_velocity := Vector3.ZERO
var _head_wobble := Quaternion.IDENTITY


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
	# Past the fog, never culled for distance: always there for everyone (the user's).
	set_meta(&"net_always", true)
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	# (Its hitboxes follow its bones: _build_hitboxes(), after the body.)
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = 1000000.0
	add_child(_health)
	_health.damaged.connect(_on_damaged)
	for player in get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(player as PhysicsBody3D)
	_build_body()
	_build_hitboxes()
	_last_position = global_position


# ---- Co-op (NetEntities: a script-made one) ------------------------------------------

func net_spawn_args() -> Dictionary:
	return {}


func net_restore(_data: Dictionary) -> void:
	pass


## The fear meter, sent with each update (for the HUD's meter everywhere).
func net_state() -> int:
	return int(round(fear * 1000.0))


func net_apply(value: int) -> void:
	fear = value / 1000.0


# ---- Hitboxes on its bones -------------------------------------------------------------

func _build_hitboxes() -> void:
	var parts := [["Hips", "Neck", 0.28], ["Neck", "Head", 0.12], ["Head", "", 0.17],
			["LeftArm", "LeftForeArm", 0.09], ["LeftForeArm", "LeftHand", 0.08],
			["RightArm", "RightForeArm", 0.09], ["RightForeArm", "RightHand", 0.08],
			["LeftUpLeg", "LeftLeg", 0.11], ["LeftLeg", "LeftFoot", 0.09],
			["RightUpLeg", "RightLeg", 0.11], ["RightLeg", "RightFoot", 0.09]]
	for part: Array in parts:
		var from: int = _bones.get(part[0], -1)
		var to: int = _bones.get(part[1], -1) if part[1] != "" else -1
		if from < 0 or (part[1] != "" and to < 0):
			continue
		var shape := CollisionShape3D.new()
		var radius: float = part[2] * SIZE
		if to < 0:
			var ball := SphereShape3D.new()
			ball.radius = radius
			shape.shape = ball
		else:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			shape.shape = capsule
		add_child(shape)
		_hitboxes.append([shape, from, to, radius])
	if _hitboxes.is_empty():
		# No bones found: one capsule down its length, as before.
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35 * SIZE
		capsule.height = SPAN
		shape.shape = capsule
		shape.rotation.x = PI * 0.5
		shape.position = Vector3.UP * BODY_HEIGHT
		add_child(shape)
	_update_hitboxes()


## Each part's shape onto its bones, where they are this tick.
func _update_hitboxes() -> void:
	if _skeleton == null:
		return
	var skeleton_xf := _skeleton.global_transform
	for box: Array in _hitboxes:
		var shape := box[0] as CollisionShape3D
		var a: Vector3 = skeleton_xf * _skeleton.get_bone_global_pose(box[1]).origin
		if int(box[2]) < 0:
			shape.global_transform = Transform3D(Basis.IDENTITY, a)
			continue
		var b: Vector3 = skeleton_xf * _skeleton.get_bone_global_pose(box[2]).origin
		var along := b - a
		var length := along.length()
		if length < 0.001:
			continue
		var capsule := shape.shape as CapsuleShape3D
		capsule.height = maxf(length + float(box[3]) * 2.0, float(box[3]) * 2.0 + 0.01)
		# A capsule stands along its Y: turned onto the bone.
		var y := along / length
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		shape.global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


# ---- Host: the brain ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_hitboxes()
	if NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	_state_left -= delta
	_record_trails()
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
	if state == State.FALL or _airborne:
		_fall(delta)
	else:
		_crawl(delta)
	_face()
	_unstick(delta)


func _think(delta: float) -> void:
	_fear_tick(delta)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if state == State.APPROACH and is_instance_valid(_victim) and _cut_off_tick(delta, _victim):
		return
	if state == State.APPROACH or state == State.LUNGE or state == State.DRAG:
		_strike_tick(delta)
		return
	# Within GRAB_RANGE (looking at it or not): it lunges for them (not while
	# it's cooling down after a drag).
	var near := _nearest_player()
	if near and _cooldown_left <= 0.0 and state != State.STUNT and near.drag == null and near.global_position.distance_to(global_position) < GRAB_RANGE:
		_lunge_at(near)
		return
	# Rushed at: off flat out to cover.
	if near and state != State.HIDE and state != State.STUNT:
		var to_me := global_position - near.global_position
		var closing := Vector3(near.velocity.x, 0.0, near.velocity.z).dot(_flat(to_me))
		if to_me.length() < RUSHED_RANGE and closing > RUSHED_SPEED:
			_start_hide(true)
	# Seen? Hide (a stunt plays out first).
	_look_check -= delta
	if _look_check <= 0.0:
		_look_check = 0.1
		var seen := _seen()
		if state == State.STUNT:
			_stunt_look(seen)
		elif seen and state != State.HIDE and state != State.SPOTTED:
			state = State.SPOTTED
			# (Full fear: no stare -- it bolts, frantic, the moment it's seen.)
			_state_left = SPOTTED_FREEZE if fear < 1.0 else 0.0
		# The fear: only clearly in view a moment, once a sighting (the user's).
		if state != State.STUNT:
			_clear_for = _clear_for + 0.1 if _clearly_seen() else 0.0
			_unclear_for = _unclear_for + 0.1 if _clear_for == 0.0 else 0.0
			if _unclear_for > 1.0:
				_glimpse_counted = false
			if _clear_for >= GLIMPSE_TIME and not _glimpse_counted:
				_glimpse_counted = true
				_add_fear(FEAR_SEEN, "glimpsed")
	if state == State.STUNT:
		_stunt_tick(delta)
		return
	var nearest := _nearest_player()
	if nearest == null:
		_desired = Vector3.ZERO
		return
	var distance := nearest.global_position.distance_to(global_position)
	# Lost sight of them HUNT_AFTER (any fear): it hunts them down their trail
	# (no more turning up out of nowhere: it runs the way they went).
	_sight_check -= delta
	if _sight_check <= 0.0:
		_sight_check = 0.2
		_unseen_for = 0.0 if _sees(nearest) else _unseen_for + 0.2
	if (state == State.STALK or state == State.WAIT) and _unseen_for >= HUNT_AFTER and distance > HUNT_UNTIL:
		_start_hunt(nearest)
	match state:
		State.HUNT:
			_hunt_tick(delta)
		State.SPOTTED:
			# Dead still a beat, staring back -- then it scrambles off.
			_desired = Vector3.ZERO
			_velocity = Vector3.ZERO
			if _state_left <= 0.0:
				_start_hide(false)
		State.HIDE:
			# Off away from them first -- a bolt, flat out, after its stare (the
			# user's) -- then to cover further off.
			if _run_off_left > 0.0:
				_run_off_left -= delta
				_desired = _flee_dir() * SPRINT
				if _run_off_left <= 0.0:
					_hide_to = _hiding_spot()
				return
			_hiding_for += delta
			if not _hide_to.is_finite() or global_position.distance_to(_hide_to) < 1.5 or _hiding_for > STUCK_TIME:
				_hide_fast = false
				state = State.WAIT
				_state_left = WAIT_TIME
				_desired = Vector3.ZERO
			else:
				_desired = (_hide_to - global_position).normalized() * (SPRINT if _hide_fast else SCRAMBLE)
		State.WAIT:
			_desired = Vector3.ZERO
			if _state_left <= 0.0:
				state = State.STALK
		State.STALK:
			# The fear's full and they're not looking at it: round behind them.
			if fear >= 1.0 and _cooldown_left <= 0.0 and nearest.drag == null and not _seen():
				_victim = nearest
				state = State.APPROACH
				return
			_stunt_left_every -= delta
			if _stunt_left_every <= 0.0 and _cooldown_left <= 0.0:
				_stunt_left_every = randf_range(STUNT_EVERY.x, STUNT_EVERY.y)
				if _start_stunt():
					return
				_stunt_left_every = 2.0 # none fit here: tries again shortly, not a whole wait later
			# Round to a spot STALK_DISTANCE from them, on the side it's on.
			var away := global_position - nearest.global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
			var spot := nearest.global_position + away * STALK_DISTANCE
			if HallEcho.inside(nearest.global_position):
				# Indoors: on their side of the walls (in their room, on their floor).
				var eye := nearest.head.global_position
				var wall := _ray(eye, eye + away * STALK_DISTANCE)
				if not wall.is_empty():
					var floor_hit := _ground_at(eye + away * maxf(eye.distance_to(wall.position) - SPAN, 2.0) + Vector3.DOWN * 5.0)
					if not floor_hit.is_empty() and absf((floor_hit.position as Vector3).y - nearest.global_position.y) < 4.0:
						spot = floor_hit.position
			# Up a wall or on a ceiling near there, rather than on the ground.
			_perch_left -= delta
			if _perch_left <= 0.0 or not _perch.is_finite() or _perch.distance_to(spot) > PERCH_REACH * 2.0:
				_perch_left = PERCH_EVERY
				_perch = _perch_near(spot)
			var to := _perch - global_position
			_desired = to.normalized() * CRAWL * clampf(to.length() / 4.0, 0.0, 1.0) if to.length() > 2.0 else Vector3.ZERO


# ---- Stage 3: the strike, the drag ------------------------------------------------------

## A player caught off guard (any one: looking away from it, reloading or
## hands busy, alone, grappling), or null.
func _exposed_player() -> PlayerMovement:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p == null or p.is_dead() or p.drag != null:
			continue
		if _off_guard(p):
			return p
	return null


func _off_guard(p: PlayerMovement) -> bool:
	var to := (global_position - p.head.global_position).normalized()
	if (-p.head.global_basis.z).dot(to) < cos(deg_to_rad(70.0)):
		return true # looking away from it
	if p.weapons.is_reloading() or p.weapons.is_busy() or p.hand.is_busy() or p.bag_open:
		return true
	if p.grapple.is_out():
		return true
	for node in get_tree().get_nodes_in_group("player"):
		if node != p and (node as Node3D).global_position.distance_to(p.global_position) < ALONE_RANGE:
			return false
	return true # alone


func _strike_tick(delta: float) -> void:
	var p := _victim
	if not is_instance_valid(p) or p.is_dead():
		_let_go(false)
		return
	match state:
		State.APPROACH:
			# Within reach: it lunges, seen or not (the user's).
			if global_position.distance_to(p.global_position) < GRAB_RANGE:
				_lunge_at(p)
				return
			# In unseen behind them; seen further off, it bolts and hides (and tries again).
			if _seen():
				state = State.SPOTTED
				_state_left = SPOTTED_FREEZE
				_moment()
				return
			# Flanking: round them on a ring FLANK_RING out, toward their back
			# (out of their sight), then in from behind.
			var back := -_flat(-p.head.global_basis.z)
			var bearing := _flat(global_position - p.global_position)
			var round_to := bearing.signed_angle_to(back, Vector3.UP)
			var goal := p.global_position + back * APPROACH_BEHIND
			if absf(round_to) > 0.5:
				goal = p.global_position + bearing.rotated(Vector3.UP, clampf(round_to, -1.0, 1.0)) * FLANK_RING
			var to := goal - global_position
			_desired = to.normalized() * FLANK_SPEED if to.length() > 1.0 else Vector3.ZERO
			if global_position.distance_to(p.global_position) < GRAB_RANGE:
				_lunge_at(p)
		State.LUNGE:
			var to := p.global_position - global_position
			_desired = to.normalized() * LUNGE
			if to.length() < 1.8:
				_grab(p)
			elif _state_left <= 0.0:
				_let_go(false) # missed: off into hiding
		State.DRAG:
			_desired = _drag_way * DRAG_PULL
			if _state_left <= 0.0:
				# Not loose in time: badly hurt, left there in the dark; it runs off.
				p.health.hurt_unscaled(DRAG_DAMAGE)
				_let_go(true)


## Lunging for them (and grabbing on reaching them: _strike_tick's LUNGE).
func _lunge_at(p: PlayerMovement) -> void:
	_victim = p
	state = State.LUNGE
	_state_left = LUNGE_TIME
	Network.send_stalker_sound(StalkerSound.Kind.RATTLE, global_position + Vector3.UP * BODY_HEIGHT)


func _grab(p: PlayerMovement) -> void:
	state = State.DRAG
	_state_left = DRAG_TIME
	_freed_by_others = 0.0
	# Off away from the others (toward the dark), dragging them behind.
	var away := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("player"):
		if node != p:
			away += _flat(p.global_position - (node as Node3D).global_position)
	_drag_way = _flat(away) if away.length_squared() > 0.01 else _flat(global_position - p.global_position).rotated(Vector3.UP, randf_range(-0.6, 0.6))
	_drag_way = -_drag_way if _drag_way.dot(_flat(global_position - p.global_position)) < -0.5 else _drag_way
	if p.hand.is_holding():
		p.hand.put_away()
	Network.send_stalker_drag(p.get_multiplayer_authority(), true)
	_moment(true)


## The drag broken: by their clicks (StalkerDrag.tug(), the host's), or a
## teammate's shots.
func drag_broken() -> void:
	if state != State.DRAG or not is_instance_valid(_victim):
		return
	# Thrown off, any which way.
	var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var throw := (way * cos(0.35) + Vector3.UP * sin(0.35)) * THROW_SPEED
	_victim.health.hurt_unscaled(THROW_DAMAGE)
	_let_go(false, throw)


## Lets go of whoever it has (`dragged`: it had them) and runs flat out to
## cover; after a drag, a COOLDOWN before it stages or strikes again (it
## keeps stalking). The fear's spent.
func _let_go(dragged: bool, throw: Vector3 = Vector3.ZERO) -> void:
	if is_instance_valid(_victim):
		Network.send_stalker_drag(_victim.get_multiplayer_authority(), false, throw)
	_victim = null
	fear = 0.0
	if dragged or state == State.DRAG:
		_cooldown_left = randf_range(COOLDOWN.x, COOLDOWN.y)
	_start_hide(true)

# ---- Stage 2: the fear meter ----------------------------------------------------------

func _add_fear(amount: float, why: String) -> void:
	if fear >= 1.0:
		return
	fear = minf(fear + amount, 1.0)
	Network.send_fear_note("+%d%%  %s" % [roundi(amount * 100.0), why]) # (the note under the meter)
	if OS.is_debug_build():
		print("Stalker fear %3.0f%%  (+%2.0f%% %s)" % [fear * 100.0, amount * 100.0, why])


## A stunt's moment: reactions in the next REACT_WINDOW count (each once).
## `perceived`: they saw it (or it was right beside them) -- only then do
## their reactions count (the user's).
func _moment(perceived: bool = false) -> void:
	_moment_msec = Time.get_ticks_msec()
	_moment_perceived = perceived
	_reacted.clear()


func _reacting(kind: String) -> bool:
	if not _moment_perceived or Time.get_ticks_msec() - _moment_msec > int(REACT_WINDOW * 1000.0) or _reacted.has(kind):
		return false
	_reacted[kind] = true
	return true


## Every tick: the meter drains; players whipping round or running off after
## a stunt fill it; a help scream's spot, investigated, fills half.
func _fear_tick(delta: float) -> void:
	_full_for = _full_for + delta if fear >= 1.0 else 0.0
	if fear < 1.0 or _full_for > FEAR_HOLD:
		fear = maxf(fear - delta / FEAR_DRAIN_TIME, 0.0)
	_hook_left -= delta
	if _hook_left <= 0.0:
		_hook_left = 2.0
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as PlayerMovement
			if player and not _fire_hooked.has(player):
				_fire_hooked[player] = true
				player.weapons.shot_fired.connect(_on_player_fired)
	var in_window := Time.get_ticks_msec() - _moment_msec <= int(REACT_WINDOW * 1000.0)
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null:
			continue
		var yaw := player.rotation.y
		var turned := absf(angle_difference(float(_yaws.get(player, yaw)), yaw)) / maxf(delta, 0.001)
		_yaws[player] = yaw
		if not in_window:
			continue
		if turned > SPIN_RATE and _reacting("spin"):
			_add_fear(FEAR_SPIN, "whipped round")
		var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var away := player.global_position - global_position
		away.y = 0.0
		if flat.length() > FLEE_SPEED and flat.normalized().dot(away.normalized()) > 0.5 and _reacting("flee"):
			_add_fear(FEAR_FLEE, "ran off")
	if _help_spot.is_finite():
		# Went to it on purpose: right up to it soon after hearing it (the
		# scream's 70-140 m off: no one's there by chance).
		_help_time += delta
		if _help_time > INVESTIGATE_WITHIN:
			_help_spot = Vector3.INF
		else:
			for node in get_tree().get_nodes_in_group("player"):
				if (node as Node3D).global_position.distance_to(_help_spot) < INVESTIGATE_REACH:
					_help_spot = Vector3.INF
					_add_fear(FEAR_HELP, "went to the scream")
					break


func _on_player_fired() -> void:
	if _reacting("fire"):
		_add_fear(FEAR_FIRE, "panic fired")


# ---- Hunting: following your trail -----------------------------------------------

## Every player's trail: a crumb every CRUMB_EVERY metres where they touch
## ground or a wall; a gap they jumped (over LEAP_GAP) marked as a leap; a
## jump in the trail too fast to have been travelled (a respawn) starts it
## over; the last TRAIL_LENGTH kept.
func _record_trails() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p == null or p.is_dead():
			continue
		var trail: Dictionary = _trails.get(p, {})
		if trail.is_empty():
			trail = {points = PackedVector3Array(), leaps = PackedByteArray(), length = 0.0, aired = false, msec = 0}
			_trails[p] = trail
		if not (p.is_on_floor() or p.is_on_wall() or p.grapple.is_perched()):
			trail.aired = true
			continue
		var at := p.global_position
		var points: PackedVector3Array = trail.points
		var leaps: PackedByteArray = trail.leaps
		var now := Time.get_ticks_msec()
		if not points.is_empty():
			var gap := points[points.size() - 1].distance_to(at)
			if gap < CRUMB_EVERY:
				if gap < CRUMB_EVERY * 0.5:
					trail.aired = false # (a hop on the spot)
				continue
			var seconds := maxf((now - int(trail.msec)) / 1000.0, 0.05)
			if gap / seconds > TRAIL_BREAK_SPEED:
				points.clear()
				leaps.clear()
				trail.length = 0.0
			else:
				trail.length = float(trail.length) + gap
		points.append(at)
		leaps.append(1 if trail.aired and points.size() > 1 and points[points.size() - 2].distance_to(at) > LEAP_GAP else 0)
		trail.aired = false
		trail.msec = now
		while float(trail.length) > TRAIL_LENGTH and points.size() > 2:
			trail.length = float(trail.length) - points[0].distance_to(points[1])
			points.remove_at(0)
			leaps.remove_at(0)
			if p == _hunted:
				_crumb = maxi(_crumb - 1, 0)
		trail.points = points
		trail.leaps = leaps


## Hunting `p`: making for the crumb of theirs nearest it (or, off their trail
## and unseen, turning up on it).
func _start_hunt(p: PlayerMovement) -> void:
	_hunted = p
	state = State.HUNT
	_crumb_best = INF
	_crumb_stall = 0.0
	var points: PackedVector3Array = (_trails.get(p, {}) as Dictionary).get("points", PackedVector3Array())
	var best := INF
	_crumb = maxi(points.size() - 1, 0)
	for i in points.size():
		var d := points[i].distance_squared_to(global_position)
		if d < best:
			best = d
			_crumb = i


## The trail from crumb `from` on to its newest end (metres).
static func _trail_left(points: PackedVector3Array, from: int) -> float:
	var total := 0.0
	for i in range(maxi(from, 0), points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


func _hunt_tick(delta: float) -> void:
	var p := _hunted
	if not is_instance_valid(p) or p.is_dead():
		state = State.STALK
		return
	var points: PackedVector3Array = (_trails.get(p, {}) as Dictionary).get("points", PackedVector3Array())
	var leaps: PackedByteArray = (_trails.get(p, {}) as Dictionary).get("leaps", PackedByteArray())
	# Found them: back to stalking (or flanking).
	if _sees(p) or p.global_position.distance_to(global_position) < HUNT_UNTIL or points.is_empty():
		state = State.STALK
		_unseen_for = 0.0
		return
	_crumb = clampi(_crumb, 0, points.size() - 1)
	# Fallen more than the trail's length behind: back at its far end, unseen.
	_skip_check -= delta
	if _skip_check <= 0.0:
		_skip_check = 0.5
		if _crumb == 0 and global_position.distance_to(points[0]) > FELL_OFF and not _seen():
			_to_trail_end(points)
	var goal := points[_crumb]
	var gap := goal.distance_to(global_position)
	if gap < CRUMB_REACH:
		_arrive(points, leaps)
		return
	# Getting nowhere toward it (hung up): on to the next.
	if gap < _crumb_best - 0.5:
		_crumb_best = gap
		_crumb_stall = 0.0
	else:
		_crumb_stall += delta
		if _crumb_stall > 2.0:
			_arrive(points, leaps)
			return
	_desired = (goal - global_position).normalized() * HUNT_SPEED


## Made the crumb: on to the next -- with a leap, if they jumped it.
func _arrive(points: PackedVector3Array, leaps: PackedByteArray) -> void:
	_crumb_best = INF
	_crumb_stall = 0.0
	if _crumb >= points.size() - 1:
		_desired = (_hunted.global_position - global_position).normalized() * HUNT_SPEED # (their newest: straight at them)
		return
	_crumb += 1
	if _crumb < leaps.size() and leaps[_crumb] == 1:
		_leap_to(points[_crumb])
		_crumb = mini(_crumb + 1, points.size() - 1)


## A leap across a gap they jumped, landing where they landed.
func _leap_to(to: Vector3) -> void:
	var from := global_position
	var flight := clampf(from.distance_to(to) / HUNT_SPEED, 0.5, 3.0)
	_velocity = (to + Vector3.UP * RIDE - from) / flight + Vector3.UP * 0.5 * GRAVITY * flight
	_heading = _velocity.normalized()
	_airborne = true


## Put back on their trail at its far end (TRAIL_LENGTH back), at the first
## crumb from there that no one can see (never past their newest).
func _to_trail_end(points: PackedVector3Array) -> void:
	for j in range(0, points.size() - 1):
		if _visible_from_any(_body_points(points[j], Basis.IDENTITY)):
			continue
		global_position = points[j] + Vector3.UP * RIDE
		_normal = Vector3.UP
		_velocity = Vector3.ZERO
		_crumb = j + 1
		_crumb_best = INF
		return


## Whether it can see `p` (their head, nothing in the way).
func _sees(p: PlayerMovement) -> bool:
	var me := global_position + global_basis.y * BODY_HEIGHT
	return _ray(me, p.head.global_position).is_empty()


## Turned up somewhere on `p`'s trail `how_far` (metres along it) back from
## them, where no one can see it; false if there's no such spot.
func _place_on_trail(p: PlayerMovement, how_far: Vector2) -> bool:
	var points: PackedVector3Array = (_trails.get(p, {}) as Dictionary).get("points", PackedVector3Array())
	if points.size() < 3:
		return false
	var back := 0.0
	for j in range(points.size() - 2, 0, -1):
		back += points[j].distance_to(points[j + 1])
		if back < how_far.x:
			continue
		if back > how_far.y:
			break
		if _visible_from_any(_body_points(points[j], Basis.IDENTITY)):
			continue
		global_position = points[j] + Vector3.UP * RIDE
		_normal = Vector3.UP
		_velocity = Vector3.ZERO
		state = State.WAIT
		_state_left = WAIT_TIME
		return true
	return false


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
	var side := basis.x * 0.5 * SIZE
	return [at + up + forward, at + up - forward, at + up * 0.3 + forward + side, at + up * 0.3 + forward - side,
			at + up * 0.3 - forward + side, at + up * 0.3 - forward - side]


## Whether any player could see any part of it right now: its real body --
## each hitbox on its bones -- as well as the points round where it stands.
func _seen() -> bool:
	var points := _body_points(global_position, global_basis)
	for box: Array in _hitboxes:
		points.append((box[0] as CollisionShape3D).global_position)
	return _visible_from_any(points)


## Clearly in someone's view: near the middle (GLIMPSE_CONE), within
## GLIMPSE_RANGE, nothing in the way.
func _clearly_seen() -> bool:
	var points := _body_points(global_position, global_basis)
	for box: Array in _hitboxes:
		points.append((box[0] as CollisionShape3D).global_position)
	var cone := cos(deg_to_rad(GLIMPSE_CONE))
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
			if distance > GLIMPSE_RANGE or look.dot(to / maxf(distance, 0.001)) < cone:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, 1, [player.get_rid(), get_rid()])).is_empty():
				return true
	return false


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
			# (A point just inside the ground or a wall still counts as seen.)
			if hit.is_empty() or (hit.position as Vector3).distance_to(point) < 0.5 * SIZE:
				return true
	return false


## Into hiding: straight off away from the players first (`fast`: flat out).
func _start_hide(fast: bool) -> void:
	_hide_fast = fast
	_flee_side = 1.0 if randf() < 0.5 else -1.0
	_hide_to = Vector3.INF
	_run_off_left = RUN_OFF_TIME
	_hiding_for = 0.0
	state = State.HIDE


## Not getting anywhere while it means to: clinging to a wall or ceiling, it
## lets go and drops (and hides on the floor after); on the floor, it picks
## other cover.
func _unstick(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = UNSTICK_EVERY
	var moved := global_position.distance_to(_check_pos)
	_check_pos = global_position
	if _desired.length() < 1.0 or state == State.FALL or _airborne or state == State.DRAG:
		return
	if moved >= UNSTICK_MOVE:
		return
	if _normal.y < WALL_DOT:
		# Off the wall (or ceiling): a push out from it, and down.
		_velocity = _normal * 3.0 + Vector3.DOWN
		_airborne = true
		_floor_only = true
	elif state == State.HIDE and _run_off_left <= 0.0:
		_hide_to = _hiding_spot()


## A spot up a wall (PERCH_HEIGHT) within PERCH_REACH of `spot`, or indoors
## half the time on the ceiling over it; `spot` itself if there's neither.
func _perch_near(spot: Vector3) -> Vector3:
	# Not always (the user's: walls mustn't keep it from getting about).
	if randf() > PERCH_CHANCE:
		return spot
	if HallEcho.inside(spot) and randf() < 0.5:
		var ceiling := _ray(spot + Vector3.UP * 1.5, spot + Vector3.UP * 35.0)
		if not ceiling.is_empty() and (ceiling.normal as Vector3).y < -0.7:
			return ceiling.position
	var turn := randf() * TAU
	for i in 8:
		var way := Vector3.FORWARD.rotated(Vector3.UP, turn + TAU * i / 8.0)
		var from := spot + Vector3.UP * 1.5
		var wall := _ray(from, from + way * PERCH_REACH)
		if wall.is_empty() or absf((wall.normal as Vector3).y) > 0.3:
			continue
		var normal := wall.normal as Vector3
		var up_it := (wall.position as Vector3) + Vector3.UP * randf_range(PERCH_HEIGHT.x, PERCH_HEIGHT.y)
		var on := _ray(up_it + normal * 1.5, up_it - normal * 2.0)
		if not on.is_empty():
			return on.position
	return spot


## Somewhere near none of them can see (any of it): round it on its surface,
## the nearest such spot that isn't toward them; straight away from them if
## there's none.
func _hiding_spot() -> Vector3:
	var best := Vector3.INF
	var best_score := INF
	var space := get_world_3d().direct_space_state
	var players := get_tree().get_nodes_in_group("player")
	var walls := not _floor_only # (not straight after dropping off one that held it up)
	_floor_only = false
	# Further from them than it is now (the user's: it gets away first).
	var nearest_now := INF
	for node in players:
		nearest_now = minf(nearest_now, (node as Node3D).global_position.distance_to(global_position))
	var further := func(at: Vector3) -> bool:
		for node in players:
			if (node as Node3D).global_position.distance_to(at) < nearest_now + 5.0:
				return false
		return true
	for ring: float in [6.0, 12.0, 20.0, 30.0]:
		for i in 12:
			var way := _flat_perpendicular(_normal, Vector3.FORWARD.rotated(_normal, TAU * i / 12.0 + randf() * 0.4))
			var spot := global_position + way * ring
			var stick := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + _normal * 3.0, spot - _normal * 6.0, 1, [get_rid()]))
			if stick.is_empty():
				continue
			spot = stick.position
			var frame := Basis(way.cross(_normal), _normal, -way)
			if not further.call(spot) or _visible_from_any(_body_points(spot, frame)):
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
			return best # (cover on the floor first: getting away comes before climbing)
	# None on the floor: up a wall or onto a ceiling round it, like a spider.
	for i in (16 if walls else 0):
		var way := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		var hit := _ray(global_position + _normal * 0.5, global_position + way * 25.0)
		if hit.is_empty():
			continue
		var at := hit.position as Vector3
		var normal := hit.normal as Vector3
		if normal.y > WALL_DOT:
			continue # (floors: the rings above)
		var forward := _flat_perpendicular(normal, at - global_position)
		if not further.call(at) or _visible_from_any(_body_points(at, Basis(forward.cross(normal), normal, -forward))):
			continue
		var score := global_position.distance_to(at) - (at.y - global_position.y) * 0.5 # higher is better
		for node in players:
			var player := node as Node3D
			if player.global_position.distance_to(at) < player.global_position.distance_to(global_position):
				score += 15.0
		if score < best_score:
			best_score = score
			best = at
	if best.is_finite():
		return best
	return global_position + _away_from_players() * 25.0


## Out of sight the fastest way (the user's: frantic, not sitting there in
## view): sideways out of the nearest one's view as much as away from them,
## zigzagging.
func _flee_dir() -> Vector3:
	var viewer := _nearest_player()
	if viewer == null:
		return _away_from_players()
	var look := _flat(-viewer.head.global_basis.z)
	var to_me := _flat(global_position - viewer.global_position)
	var lateral := to_me - look * to_me.dot(look)
	if lateral.length_squared() < 0.01:
		lateral = look.cross(Vector3.UP) * _flee_side
	lateral = lateral.normalized()
	var way := (lateral * 0.8 + to_me * 0.45).normalized().rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.009) * 0.4)
	return _flat_perpendicular(_normal, way)


func _away_from_players() -> Vector3:
	var away := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("player"):
		var from := global_position - (node as Node3D).global_position
		away += from.normalized() / maxf(from.length(), 1.0)
	return _flat_perpendicular(_normal, away if away.length_squared() > 0.0001 else -global_basis.z)


func _on_damaged(amount: float, attacker: int) -> void:
	_health.current_health = _health.max_health # never killed
	if _visual:
		HitFlash.flash(_visual) # (so a hit reads as one: it never bleeds out)
	if state == State.FLEE or state == State.AWAY:
		return
	_hurt += amount
	# Shot off the one it's dragging by someone else.
	if state == State.DRAG and is_instance_valid(_victim) and attacker != _victim.get_multiplayer_authority():
		_freed_by_others += amount
		if _freed_by_others >= TEAMMATE_FREES and _hurt < DRIVE_OFF:
			_let_go(false)
			return
	if _hurt >= DRIVE_OFF:
		if state == State.DRAG or state == State.LUNGE or state == State.APPROACH:
			_let_go(false) # (driven off mid-strike: whoever it had is let go)
		state = State.FLEE
		_state_left = FLEE_TIME
		_airborne = false
		Network.send_stalker_sound(StalkerSound.Kind.SHRIEK, global_position + Vector3.UP * BODY_HEIGHT)
	elif state == State.STALK or state == State.WAIT:
		_start_hide(false)


## Gone for a while (driven off): out of the world entirely.
func _go_away() -> void:
	state = State.AWAY
	_state_left = randf_range(AWAY_TIME.x, AWAY_TIME.y)
	_hurt = 0.0
	_velocity = Vector3.ZERO
	global_position = Vector3(global_position.x, AWAY_DEPTH, global_position.z)


## Back, somewhere out of sight RELOCATE_TO from one of the players (behind
## them, on the ground).
## In a megastructure, the straight crawl to someone can be no way at all --
## they're a floor up, or through a wall it'd only climb about on. Cut off
## that long (STUCK_TIME, nobody watching), it slips round and turns up on
## their floor, out of sight -- the Left 4 Dead director's way (its special
## infected never path across the map: they turn up near you, unseen). True
## if it did.
func _cut_off_tick(delta: float, p: PlayerMovement) -> bool:
	if not (HallEcho.inside(p.global_position) or HallEcho.inside(global_position)):
		_cut_for = 0.0
		return false
	var me := global_position + global_basis.y * BODY_HEIGHT
	var blocked := not _ray(me, p.head.global_position).is_empty()
	_cut_for = _cut_for + delta if blocked else 0.0
	if _cut_for > STUCK_TIME and not _seen():
		_cut_for = 0.0
		_start_hunt(p) # (down their trail: the way they really went)
		return true
	return false


func _turn_up(how_far: Vector2 = RELOCATE_TO) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_state_left = 2.0
		return
	var player := players[randi() % players.size()] as PlayerMovement
	# Back down their trail if it can (it came the way they went).
	if _place_on_trail(player, how_far):
		return
	var space := get_world_3d().direct_space_state
	for attempt in 16:
		var behind := player.head.global_basis.z.rotated(Vector3.UP, randf_range(-1.2, 1.2))
		behind.y = 0.0
		behind = behind.normalized()
		var ground := {}
		if HallEcho.inside(player.global_position):
			# Indoors: behind them in their own room, on their floor -- never
			# dropped onto the roof or another storey (rays from high above
			# land there).
			var eye := player.head.global_position
			var reach := randf_range(how_far.x, how_far.y)
			var wall := _ray(eye, eye + behind * reach)
			if not wall.is_empty():
				reach = eye.distance_to(wall.position) - SPAN
			if reach < LUNGE_FROM:
				continue
			var over := eye + behind * reach
			ground = _ray(over, over + Vector3.DOWN * (eye.y - player.global_position.y + 4.0))
		else:
			# Outdoors: from not far over their head, so not up on a bridge or a
			# tower's roof.
			var spot := player.global_position + behind * randf_range(how_far.x, how_far.y)
			ground = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(spot.x, player.global_position.y + 60.0, spot.z), spot + Vector3.DOWN * 400.0, 1, [get_rid()]))
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


# ---- Stage 2: the stunts ---------------------------------------------------------------

## A stunt for one of the players (one that fits where they are; the leap
## across the towers by preference when they're climbing a megastructure's
## outside). False if none could be staged this time.
func _start_stunt() -> bool:
	var players := get_tree().get_nodes_in_group("player").filter(func(n: Node) -> bool:
		return n is PlayerMovement and not (n as PlayerMovement).is_dead())
	if players.is_empty():
		return false
	_stunt_target = players[randi() % players.size()] as PlayerMovement
	var kinds: Array = [Stunt.BEHIND, Stunt.CEILING, Stunt.DOORWAY, Stunt.WATCH, Stunt.RATTLE, Stunt.DRAG, Stunt.HELP]
	kinds.shuffle()
	if _climbing_outside(_stunt_target) and randf() < 0.5:
		kinds.push_front(Stunt.LEAP)
	for kind: int in kinds:
		if _stage(kind):
			Network.send_message(_stunt_target.get_multiplayer_authority(), TINGLE)
			return true
	return false


## On a megastructure's outside, high up: where the leap's seen from.
func _climbing_outside(player: PlayerMovement) -> bool:
	if HallEcho.inside(player.global_position) or player.global_position.y < 150.0:
		return false
	for place in HallEcho.places:
		if is_instance_valid(place) and Vector2(place.global_position.x - player.global_position.x, place.global_position.z - player.global_position.z).length() < 700.0:
			return true
	return false


func _stage(kind: int) -> bool:
	var p := _stunt_target
	var eye := p.head.global_position
	var look := _flat(-p.head.global_basis.z)
	var side := look.cross(Vector3.UP).normalized()
	_stunt = kind
	_stunt_phase = 0
	_stunt_seen = false
	_stunt_away_for = 0.0
	match kind:
		Stunt.RATTLE:
			# Its croak right behind and above you; nothing there.
			Network.send_stalker_sound(StalkerSound.Kind.RATTLE, p.global_position - look * 3.0 + Vector3.UP * 1.6)
			_moment(true) # (right behind them)
			return true
		Stunt.HELP:
			# A human voice screaming for help, far off; then it follows, unseen.
			for attempt in 8:
				var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				var hit := _ground_at(p.global_position + way * randf_range(70.0, 140.0))
				if hit.is_empty():
					continue
				_help_spot = hit.position
				_help_time = 0.0
				Network.send_stalker_sound(StalkerSound.Kind.HELP, _help_spot + Vector3.UP * 1.5)
				_moment()
				return true
			return false
		Stunt.BEHIND:
			# Right behind you, still, staring -- there when you turn round.
			var hit := _ground_at(p.global_position - look * 3.5)
			if hit.is_empty() or not _place(hit.position, hit.normal, (p.global_position - (hit.position as Vector3)), true):
				return false
			_stunt_left_set(8.0)
			_stunt_rattle_left = 3.0
			return true
		Stunt.CEILING:
			# Across the ceiling (outdoors: a wall or the ground) at the edge
			# of your view, scuttling on out of it.
			var turn := randf_range(0.95, 1.13) * (1.0 if randf() < 0.5 else -1.0)
			var dir := look.rotated(Vector3.UP, turn)
			var start := eye + dir * randf_range(12.0, 20.0)
			var hit := {}
			if HallEcho.inside(p.global_position):
				hit = _ray(start, start + Vector3.UP * 40.0)
				if not hit.is_empty() and (hit.normal as Vector3).y > -0.7:
					hit = {}
			if hit.is_empty():
				hit = _ground_at(start)
			if hit.is_empty() or not _place(hit.position, hit.normal, dir, false):
				return false
			_stunt_to = dir.rotated(Vector3.UP, signf(turn) * 0.8)
			_stunt_left_set(2.4)
			_moment()
			return true
		Stunt.DOORWAY, Stunt.DRAG:
			# Across your way ahead, from cover to cover (a doorway, a gap):
			# skittering past -- or dragging a body after it.
			var middle := _ground_at(eye + look * randf_range(16.0, 26.0))
			if middle.is_empty():
				return false
			var from := _cover_beside(middle.position, -side, p)
			var to := _cover_beside(middle.position, side, p)
			if not from.is_finite() or not to.is_finite():
				return false
			if not _place(from, Vector3.UP, to - from, true):
				return false
			_stunt_to = to
			_stunt_left_set(9.0)
			if kind == Stunt.DRAG:
				_corpse = CORPSE.instantiate() as Enemy
				_corpse.can_mutate = false
				_corpse.set_meta(&"culled", true) # nothing to drop
				get_tree().current_scene.add_child(_corpse)
				_corpse.global_position = from + (from - to).normalized() * 1.4 + Vector3.UP * 0.3
				var health := _corpse.get_node(^"Health") as Health
				health.take_damage(health.current_health + 1.0)
			return true
		Stunt.WATCH:
			# Off to the side in the dark, dead still, head tilted, rattling --
			# gone the moment you look away, or stare straight at it.
			var dir := look.rotated(Vector3.UP, randf_range(0.45, 0.7) * (1.0 if randf() < 0.5 else -1.0))
			var hit := _ground_at(eye + dir * randf_range(20.0, 35.0))
			if hit.is_empty() or not _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), false):
				return false
			_stunt_left_set(15.0)
			_stunt_rattle_left = 1.0
			return true
		Stunt.LEAP:
			# Across the gap between two towers far off, a silhouette.
			for attempt in 10:
				var a_dir := (look.rotated(Vector3.UP, randf_range(-0.5, 0.5)) + Vector3.UP * randf_range(-0.1, 0.15)).normalized()
				var a := _ray(eye, eye + a_dir * 400.0)
				if a.is_empty() or eye.distance_to(a.position) < 120.0 or absf((a.normal as Vector3).y) > 0.4:
					continue
				var b_dir := a_dir.rotated(Vector3.UP, randf_range(0.15, 0.3) * (1.0 if randf() < 0.5 else -1.0))
				var b := _ray(eye, eye + b_dir * 400.0)
				if b.is_empty() or absf((b.normal as Vector3).y) > 0.4:
					continue
				var gap := (a.position as Vector3).distance_to(b.position)
				if gap < 30.0 or gap > 150.0:
					continue
				global_position = (a.position as Vector3) + (a.normal as Vector3) * RIDE
				_normal = a.normal
				var flight := clampf(gap / 25.0, 1.2, 3.0)
				_velocity = ((b.position as Vector3) - (a.position as Vector3)) / flight + Vector3.UP * 0.5 * GRAVITY * flight
				_heading = _velocity.normalized()
				_airborne = true
				state = State.STUNT
				_stunt_left_set(flight + 2.0)
				_moment()
				return true
			return false
	return false


func _stunt_left_set(seconds: float) -> void:
	state = State.STUNT
	_state_left = seconds


## Each tick of the stunt under way.
func _stunt_tick(delta: float) -> void:
	_desired = Vector3.ZERO
	var p := _stunt_target
	if not is_instance_valid(p):
		_end_stunt()
		return
	match _stunt:
		Stunt.BEHIND:
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			_stunt_rattle_left -= delta
			if _stunt_rattle_left <= 0.0 and _stunt_phase == 0:
				_stunt_rattle_left = 999.0
				Network.send_stalker_sound(StalkerSound.Kind.RATTLE, global_position + Vector3.UP * 0.8)
				_moment()
			if _stunt_phase == 1 and _state_left <= 0.0:
				_end_stunt()
		Stunt.CEILING:
			_desired = _flat_perpendicular(_normal, _stunt_to) * SCRAMBLE
		Stunt.DOORWAY, Stunt.DRAG:
			if _stunt_phase == 0 and _stunt == Stunt.DRAG and _state_left > 8.6:
				return # (the body falls limp first)
			var to := _stunt_to - global_position
			if to.length() < 1.5:
				_end_stunt()
				return
			_desired = to.normalized() * (DRAG_SPEED if _stunt == Stunt.DRAG else SCRAMBLE)
			if _stunt == Stunt.DRAG:
				_drag_corpse(delta)
		Stunt.WATCH:
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			_stunt_rattle_left -= delta
			if _stunt_rattle_left <= 0.0:
				_stunt_rattle_left = randf_range(3.0, 5.0)
				Network.send_stalker_sound(StalkerSound.Kind.RATTLE, global_position + Vector3.UP * 0.8)
			# Looked away for a second: it moves on.
			var look := -p.head.global_basis.z
			var to := (global_position - p.head.global_position).normalized()
			_stunt_away_for = _stunt_away_for + delta if look.dot(to) < cos(deg_to_rad(70.0)) else 0.0
			if _stunt_away_for > 1.0:
				_end_stunt()
			if _stunt_phase == 1 and _state_left <= 0.0:
				_end_stunt()
	if _state_left <= 0.0 and _stunt_phase == 0:
		_end_stunt()


## Seen mid-stunt: it counts once (fear), and for the ones that wait to be
## seen -- behind you, watching -- a beat, frozen, staring, then it goes.
func _stunt_look(seen: bool) -> void:
	var p := _stunt_target
	if not is_instance_valid(p):
		return
	var stared := false
	if _stunt == Stunt.WATCH:
		var to := (global_position + Vector3.UP * BODY_HEIGHT - p.head.global_position).normalized()
		stared = (-p.head.global_basis.z).dot(to) > cos(deg_to_rad(STARED_AT))
	var noticed := stared if _stunt == Stunt.WATCH else seen
	if noticed and not _stunt_seen:
		_stunt_seen = true
		_moment(true)
		_add_fear(FEAR_SEEN, "saw it (%s)" % Stunt.keys()[_stunt].to_lower())
		if _stunt == Stunt.BEHIND or _stunt == Stunt.WATCH:
			_stunt_phase = 1
			_state_left = SPOTTED_FREEZE


## The stunt's over: out of sight again, and back to stalking.
func _end_stunt() -> void:
	_airborne = false
	if is_instance_valid(_corpse):
		var ragdoll := _corpse.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
		if ragdoll:
			ragdoll.carry({})
	_corpse = null
	if _stunt == Stunt.LEAP:
		_turn_up() # (far off on another tower: just gone)
		return
	_start_hide(false)


## The body dragged along behind it by a foot (the roaches' hold).
func _drag_corpse(delta: float) -> void:
	if not is_instance_valid(_corpse):
		return
	var ragdoll := _corpse.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
	if ragdoll == null:
		return
	var foot := ragdoll.bone_named("LeftFoot")
	if foot == null:
		return
	var hold := global_position + global_basis.z * 0.9 + Vector3.UP * 0.35
	var pull := ((hold - foot.global_position) * 10.0 - foot.linear_velocity) * ragdoll.total_mass() * delta * 0.6
	ragdoll.carry({foot: pull}, 0.7)


## Somewhere beside `point` (along `way`, 4-10 m out) none of the players
## can see: cover to come out of, or go into.
func _cover_beside(point: Vector3, way: Vector3, _player: PlayerMovement) -> Vector3:
	for k: float in [4.0, 6.0, 8.0, 10.0]:
		var hit := _ground_at(point + way * k)
		if hit.is_empty():
			continue
		if not _visible_from_any(_body_points(hit.position, Basis.IDENTITY)):
			return hit.position
	return Vector3.INF


## Put down at `at` on a surface facing `normal`, facing `toward`. `hidden`:
## only if none of the players can see it there (false: not placed).
func _place(at: Vector3, normal: Vector3, toward: Vector3, hidden: bool) -> bool:
	var up := normal.normalized()
	var forward := _flat_perpendicular(up, toward)
	if hidden and _visible_from_any(_body_points(at, Basis(forward.cross(up), up, -forward))):
		return false
	_normal = up
	_heading = forward
	_velocity = Vector3.ZERO
	global_position = at + up * RIDE
	global_basis = Basis(forward.cross(up), up, -forward).orthonormalized()
	return true


## The ground under `point` -- from just under the ceiling if there's one
## within 6 m (indoors: else the ray starts over it and finds the floor above).
func _ground_at(point: Vector3) -> Dictionary:
	var ceiling := _ray(point, point + Vector3.UP * 6.0)
	var top := (ceiling.position as Vector3) + Vector3.DOWN * 0.2 if not ceiling.is_empty() else point + Vector3.UP * 6.0
	return _ray(top, point + Vector3.DOWN * 40.0)


static func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD

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
		if _airborne:
			_airborne = false # (a stunt's leap, a drop off a wall: it goes on)
			if _floor_only and state == State.HIDE:
				_hide_to = _hiding_spot()
		else:
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
	# Standing height to STANDING_HEIGHT, then laid down chest-first. Measured
	# as the meshes really sit in the model -- every node above them, its
	# import scale too (the first version measured without it: tiny).
	_model.transform = Transform3D.IDENTITY
	var to_model := _model.global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := (to_model * mesh.global_transform) * mesh.get_aabb()
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
		var home := Vector3(root.x + out * (0.35 if arm else 0.25) * SIZE, 0.0, root.z + (-0.3 if arm else 0.25) * SIZE)
		_limbs.append({upper = upper, lower = lower, end = end, group = spec[3], arm = arm, out = out, home = home,
				planted = _visual.global_transform * home, foot = _visual.global_transform * home,
				stepping = false, t = 0.0, from = Vector3.ZERO, to = Vector3.ZERO})
	_build_eyes()


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
	# The look follows the body (smoothly: a puppet's moves in steps) -- or,
	# after a jump across the map (it turned up, a stunt), snaps there.
	if _visual.global_position.distance_to(global_position) > 4.0:
		_visual.global_transform = global_transform
		for limb in _limbs:
			limb.stepping = false
			limb.planted = _visual.global_transform * (limb.home as Vector3)
			limb.foot = limb.planted
	elif NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		_visual.global_transform = _visual.global_transform.interpolate_with(global_transform, 1.0 - exp(-20.0 * delta))
	else:
		_visual.global_transform = global_transform # (the host: exactly where it is -- where shots are judged)
	var hidden := global_position.y < AWAY_DEPTH * 0.5
	_visual.visible = not hidden
	if hidden:
		if _skitter:
			_skitter.queue_free()
			_skitter = null
		return
	var moved := (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if moved.length() < 60.0:
		_smooth_velocity = _smooth_velocity.lerp(moved, 1.0 - exp(-15.0 * delta))
	var camera := get_viewport().get_camera_3d()
	_update_skitter(camera)
	if camera and camera.global_position.distance_to(global_position) > 90.0:
		_update_eyes() # (seen from any way off)
		return # too far to make out its limbs
	_update_limbs(delta)
	_update_spine(delta)
	_reset_pose()
	for limb in _limbs:
		_two_bone(limb)
	_jiggle_neck(delta)
	_aim_head(delta, camera)
	_update_eyes()


## The eyes onto its head as it's posed now.
func _update_eyes() -> void:
	var head: int = _bones.get("Head", -1)
	if head < 0 or _eyes.is_empty():
		return
	var pose := _skeleton.global_transform * _skeleton.get_bone_global_pose(head)
	var up := pose.basis.y.normalized()
	var face := pose.basis.z.normalized()
	var side := up.cross(face).normalized()
	var k := STANDING_HEIGHT / 1.8
	var middle := pose.origin + (up * EYE_UP + face * EYE_FORWARD) * k
	_eyes[0].global_position = middle + side * EYE_APART * k
	_eyes[1].global_position = middle - side * EYE_APART * k



func _build_eyes() -> void:
	var core := _glow_material(Color(0.9, 0.97, 1.0), false)
	var glare := _glow_material(Color(EYE_COLOR, EYE_GLOW), true)
	for i in 2:
		var eye := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * EYE_CORE * SIZE
		eye.mesh = quad
		eye.material_override = core
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(eye)
		# The glare: a few pixels however far off.
		var flare := MeshInstance3D.new()
		var flare_quad := QuadMesh.new()
		flare_quad.size = Vector2.ONE * EYE_GLARE
		flare.mesh = flare_quad
		flare.material_override = glare
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(flare)
		_eyes.append(eye)
	# (No soft glow round them and no light off them: the user's -- just the
	# piercing eyes.)


## A soft round glow (white-hot middle fading out), lit by nothing, no fog on
## it, added over what's behind; `steady`: the same size on screen at any range.
static func _glow_material(color: Color, steady: bool) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = color
	material.disable_fog = true
	material.fixed_size = steady
	material.render_priority = 10
	return material


## Its hands and feet on the floor as it goes: the spiders' skitter, slower
## and heavier (StalkerSound placeholders), louder the faster it moves.
func _update_skitter(camera: Camera3D) -> void:
	var reach := SpiderSound.HEAR_DISTANCE * (HUNT_HEAR if state == State.HUNT else 1.0)
	var near := camera != null and camera.global_position.distance_to(global_position) < reach
	if not near:
		if _skitter:
			_skitter.queue_free()
			_skitter = null
		return
	if _skitter == null:
		_skitter = AudioStreamPlayer3D.new()
		_skitter.stream = SpiderSound.skitter(7)
		_skitter.unit_size = SpiderSound.UNIT_SIZE * 1.4
		_skitter.max_distance = SpiderSound.HEAR_DISTANCE * HUNT_HEAR
		_skitter.pitch_scale = 0.45 # (the user's: lower, heavier)
		_skitter.bus = &"Enemies" if AudioServer.get_bus_index(&"Enemies") != -1 else &"Master"
		_visual.add_child(_skitter)
		_skitter.play(randf())
	var level := clampf(_smooth_velocity.length() / CRAWL, 0.0, 1.0)
	_skitter.volume_db = SpiderSound.SKITTER_DB + 2.0 + (4.0 if state == State.HUNT else 0.0) + linear_to_db(maxf(level, 0.0005))
	_skitter.stream_paused = level < 0.05


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
				# Planted: a jolt up through it to the head.
				var kick := (up * randf_range(0.6, 1.0) + xf.basis.x.normalized() * randf_range(-0.5, 0.5)) * STEP_KICK * SIZE
				_neck_velocity += kick
				_head_velocity += kick * 1.3
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


## The neck on its spring (its end, where the head sits, lags, swings and
## settles), then the head's own spring -- kept as a wobble for _aim_head.
func _jiggle_neck(delta: float) -> void:
	var neck: int = _bones.get("Neck", -1)
	var head: int = _bones.get("Head", -1)
	if neck < 0 or head < 0 or delta <= 0.0:
		return
	delta = minf(delta, 0.05)
	_skeleton.set_bone_pose_rotation(neck, _skeleton.get_bone_rest(neck).basis.get_rotation_quaternion())
	var to_world := _skeleton.global_transform
	var to_skeleton := to_world.affine_inverse()
	var neck_pose := _skeleton.get_bone_global_pose(neck)
	var neck_offset := _skeleton.get_bone_rest(head).origin
	var want := to_world * (neck_pose.origin + neck_pose.basis * neck_offset)
	var joint := to_world * neck_pose.origin
	if not _neck_point.is_finite():
		_neck_point = want
	var spring := _spring(joint, want, _neck_point, _neck_velocity, delta)
	_neck_point = spring[0]
	_neck_velocity = spring[1]
	var was := neck_pose.basis * neck_offset
	var wants := to_skeleton * _neck_point - neck_pose.origin
	if was.length_squared() > 0.0000001 and wants.length_squared() > 0.0000001:
		var turned := Basis(Quaternion.IDENTITY.slerp(Quaternion(was.normalized(), wants.normalized()), JIGGLE_AMOUNT)) * neck_pose.basis
		var parent := _skeleton.get_bone_parent(neck)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_rotation(neck, (parent_basis.inverse() * turned).get_rotation_quaternion())
	# The head's own bobble: how far its spring has swung it off where it'd be.
	var head_pose := _skeleton.get_bone_global_pose(head)
	var head_offset := head_pose.basis.y.normalized() * neck_offset.length() * 0.8
	var head_joint := to_world * head_pose.origin
	var head_want := to_world * (head_pose.origin + head_offset)
	if not _head_point.is_finite():
		_head_point = head_want
	var head_spring := _spring(head_joint, head_want, _head_point, _head_velocity, delta)
	_head_point = head_spring[0]
	_head_velocity = head_spring[1]
	var rest_dir := (head_want - head_joint).normalized()
	var now_dir := (_head_point - head_joint).normalized()
	_head_wobble = Quaternion.IDENTITY.slerp(Quaternion(to_skeleton.basis * rest_dir, to_skeleton.basis * now_dir), JIGGLE_AMOUNT) if rest_dir.dot(now_dir) < 0.9999 else Quaternion.IDENTITY


## One jiggle step (JiggleLimb's): `point` pulled toward `want`, gravity,
## damping, kept its length from `joint`. [point, velocity].
static func _spring(joint: Vector3, want: Vector3, point: Vector3, velocity: Vector3, delta: float) -> Array:
	var length := joint.distance_to(want)
	velocity += (JIGGLE_STIFFNESS * (want - point) - JIGGLE_DAMPING * velocity + Vector3.DOWN * JIGGLE_GRAVITY) * delta
	var moved := point + velocity * delta
	var reach := moved - joint
	moved = joint + (reach.normalized() if reach.length_squared() > 0.000001 else (want - joint).normalized()) * length
	return [moved, (moved - point) / delta]


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
		var turned := Basis(_head_wobble) * Basis(wants, _tilt) * turn * pose.basis
		var parent := _skeleton.get_bone_parent(head)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_rotation(head, (parent_basis.inverse() * turned).get_rotation_quaternion())
