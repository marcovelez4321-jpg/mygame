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

enum State { STALK, SPOTTED, HIDE, WAIT, FALL, FLEE, AWAY, STUNT, APPROACH, LUNGE, DRAG, HUNT, EAT, HOME }
## Its stunts (the user's, stage 2) -- each staged to scare, then it's gone.
enum Stunt { BEHIND, CEILING, DOORWAY, WATCH, RATTLE, DRAG, LEAP, HELP, LURE, ANGEL, KNOCK, WINDOW, PACER, PATH, CROSS, GRAPPLE, SNATCH, FIGHT_WATCH, FALLEN, AMONG }

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
var _voice_msec := -100000
var _hurt_voice_msec := -100000
var _hunt_voice_left := 0.0
var _drag_voice_left := 0.0
var _was_full := false
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

## STAGE 2 (the user's): stunts when THE DIRECTOR allows (below), and the shared FEAR
## meter (hidden). A reaction within REACT_WINDOW of a stunt fills it (each
## once a stunt you saw): seeing it, panic firing, running off, whipping
## round; going to where it screamed for help, on purpose, fills half. A
## clear glimpse of it outside a stunt counts as seeing it too (see
## GLIMPSE_*). Each rise shows why under the meter. It drains over FEAR_DRAIN_TIME,
## and once it's full it stays full: the strike (stage 3) can come.
## THE DIRECTOR (the user's, 2026-10-21: no timer -- Left 4 Dead's AI
## Director, Alien: Isolation's menace): how much it may show itself now.
##   BUILD -- TENSION rises (TENSION_TIME at its base pace; faster in a fight,
##   moving fast, with raw meat on someone (it smells it), the fear up); small
##   SIGNS of it keep coming -- never more than SIGN_GAP apart (rolled; the
##   user's: liberal for now, narrowed later), sooner as tension rises: its
##   distant sounds, its breathing close by, its tracks across your way, a
##   kill on your route.
##   PEAK -- tension full and BIG_GAP since the last big moment: a big one (a
##   stunt you see; a strike counts too).
##   RELAX -- RELAX_TIME of nothing after a big moment.
## What it does within that is the situation's (the stunts' pick) -- and next,
## its brain's (drives, moods).
enum Phase { BUILD, PEAK, RELAX }
const SIGN_GAP := Vector2(240.0, 1200.0)
const BIG_GAP := 600.0
const RELAX_TIME := 60.0
const TENSION_TIME := 600.0
## ITS BRAIN (the user's, 2026-10-21): drives and moods choosing which stunt
## fits -- the director says when, the situation what can happen, the brain
## what it wants. It never tires (the user's: no sleep).
##   HUNGER -- rises over HUNGER_TIME; eating (meat, a body, a snatch) fills
##   it by MEAL. HUNGRY (over HUNGRY): food stunts first (the snatch, eating
##   the fallen), stalks closer, tension builds faster.
##   CURIOSITY -- spikes when they do something it hasn't seen them do (a
##   camp, the grapple, into the Stack, sleeping), move fast, stay still a
##   while (QUIET_AFTER), or fight; fades over CURIOUS_FADE. CURIOUS (over
##   CURIOUS): what caught its eye decides -- speed: the pacer, crossing,
##   your path; quiet: watching, behind you, the angel; a fight: watching
##   it, the fake charge; something new: watching, your path, the angel.
##   HURT (the user's: wounded, then furious) -- shot for HURT_MOOD or more:
##   WOUNDED for WOUNDED_TIME (keeps far off, limps, no big moments), then
##   FURIOUS for FURIOUS_TIME (closer, bolder stunts first, tension faster).
enum Mood { CALM, HUNGRY, CURIOUS, WOUNDED, FURIOUS }
const HUNGER_TIME := 1200.0
const HUNGRY := 0.6
const MEAL := 0.7
const CURIOUS := 0.5
const CURIOUS_FADE := 400.0
const QUIET_AFTER := 10.0
const NEW_THING := 0.5
const HURT_MOOD := 25.0
const WOUNDED_TIME := 90.0
const FURIOUS_TIME := 180.0
const WOUNDED_BIT := 1 << 15
var hunger := 0.3
var curiosity := 0.0
var _curious_about := &"new"
var _wounded_left := 0.0
var _furious_left := 0.0
var wounded := false
## What each player's been seen doing (for "something new").
var _seen_doing := {}
var _still_for := {}

## ITS MEMORY (the user's, 2026-10-21: all four):
##   WHERE IT WAS SHOT -- it steers clear of those spots (SHOT_AVOID) for
##   SHOT_MEMORY.
##   CAMPS AND ROUTES -- the land's cut into ROUTE_CELL squares and it counts
##   the ones you go through; on a well-trodden one (TRODDEN) it waits in your
##   path there first, and its tracks and kills turn up along your ways. Back
##   at a camp you've used after being away (CAMP_AWAY), now and then its
##   tracks are round it (it was there while you were gone).
##   HABITS -- you whip round at its sounds (SPIN_HABIT times): it baits you
##   (a sound behind you, then it's where you were looking); you stare it
##   down (STARE_HABIT times): it stops showing itself in front of you.
##   GRUDGES -- in co-op, whoever hurt it most (over GRUDGE_MIN) it goes after
##   more: its stunts (GRUDGE_PICK of the time) and strikes; fades GRUDGE_FADE.
const SHOT_MEMORY := 600.0
const SHOT_AVOID := 15.0
const ROUTE_CELL := 40.0
const TRODDEN := 3
const CAMP_AWAY := 150.0
const CAMP_SIGNS := 0.5
const SPIN_HABIT := 2
const STARE_HABIT := 3
const GRUDGE_MIN := 50.0
const GRUDGE_PICK := 0.6
const GRUDGE_FADE := 900.0
var _shot_spots: Array = [] # [where, msec]
var _route_cells := {}
var _last_cell := {}
var _away_from_camp := {}
var _sound_msec := -100000
var _spins := 0
var _stares := 0
var _grudge := {}
var _bait_look := Vector3.ZERO
## ITS LAIR (the user's: the flooded depths -- StalkerLair, every game's own).
## HOME: driven off, it goes home to heal (if nobody's near the lair); and
## whenever someone comes within LAIR_NOTICE of it, LAIR_CHANCE it's simply
## there (the user's) -- upright, still, watching, ready. Within LAIR_DEFEND
## of it, it rises in warning (LAIR_WARN) and attacks. A visit ends HOME_VISIT
## on, or once they're past LAIR_LEAVE.
const LAIR_NOTICE := 120.0
const LAIR_LEAVE := 150.0
const LAIR_CHANCE := 0.35
const LAIR_DEFEND := 30.0
const LAIR_WARN := 1.5
const HOME_VISIT := 180.0
var _lair_at := Vector3.INF
var _near_lair := {}
var _home_warn := -1.0
var _home_healing := false

## FIRE (the user's: it hates it -- wendigo lore): it keeps FIRE_AVOID from
## anything burning (barrels, campfires: FireSource), places nothing there, and
## won't strike at anyone by one; closer than FIRE_BURN it's hurt (FIRE_DPS,
## like damage: it can drive it off). STARVING (hunger full) it crosses the
## fire anyway (the user's: a sign things are bad).
const FIRE_AVOID := 15.0
const FIRE_BURN := 3.0
const FIRE_DPS := 80.0
var _burn_left := 0.0

## The stunts that are only a sound (and their signs): small, not big.
const SOUND_STUNTS := [Stunt.RATTLE, Stunt.LURE, Stunt.HELP]
var phase := Phase.BUILD
var tension := 0.0
var _since_big := 0.0
var _sign_left := 600.0
var _relax_left := 0.0
var _big_retry := 0.0
var _last_pick := ""
## The wrong silence (StalkerSigns): the world goes quiet round the stunt's
## player this long before it's staged; back SILENCE_AFTER after it's done
## (a sound-only one: SOUND_STUNT_HOLD after it).
const SILENCE_LEAD := 4.0
const SILENCE_AFTER := 1.5
const SOUND_STUNT_HOLD := 6.0
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
## (No more words on the screen with a stunt -- the user's, 2026-10-21: the
## silence and the sounds say it.)
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
## Slept (a bedroll, the user's): it gains this share of the trail between it
## and you at once.
const SLEEP_PROGRESS := 0.4
## ... and one sleep in CAMP_VISIT_CHANCE it came to your camp while you slept
## (the user's, 2026-10-21: 1 in 4): its tracks round your bedroll and your
## fire out (StalkerSigns.camp_visit).
const CAMP_VISIT_CHANCE := 0.25
## Its voices (the user's sounds: StalkerVoices, a slot for everything it does
## or decides) -- sparse: none within VOICE_GAP of the last (bar the urgent
## ones: hurt, lunge, grab, driven off, thrown off), the ambient ones only by
## chance (VOICE_CHANCE), the repeating ones well spaced (HUNT_VOICE_EVERY,
## DRAG_VOICE_EVERY).
const VOICE_GAP := 6.0
const VOICE_CHANCE := 0.4
const HURT_VOICE_GAP := 1.5
const HUNT_VOICE_EVERY := Vector2(12.0, 20.0)
const DRAG_VOICE_EVERY := Vector2(4.0, 7.0) 
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

## A stunt about to be staged once the silence has fallen (its player, and
## how long yet), and whose game is silent (0: no one's), till when.
var _pending_target: PlayerMovement
var _pending_left := -1.0
var _silenced_peer := 0
var _silence_off_in := -1.0
## The test menu's pick (StalkerTestMenu): this stunt, whatever's due (-1: none).
var _forced_kind := -1
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

## The wendigo (the user's, 2026-10-21): the human body stretched wrong --
## arms ARM_STRETCH, fingers FINGER_STRETCH, legs LEG_STRETCH (its joints
## moved apart: the skin stretches, the limbs don't fatten), the waist
## WAIST_THIN; frostbitten grey-blue skin (SKIN_TINT), the hands and feet
## darkest (FROSTBITE), a little glossy; small broken antlers out of its
## skull (ANTLER_COLOR).
const ARM_STRETCH := 1.4
const FINGER_STRETCH := 1.5
const LEG_STRETCH := 1.15
const WAIST_THIN := 0.8
const SKIN_TINT := Color(0.66, 0.74, 0.82)
const FROSTBITE := Color(0.3, 0.29, 0.38)
const SKIN_ROUGHNESS := 0.42
const ANTLER_COLOR := Color(0.78, 0.74, 0.64)

## UPRIGHT (the user's, 2026-10-21): the wendigo standing at its full height
## -- right behind you, the leap's stare across the gap, the angel stunt --
## every game standing its body up (net_state carries it, and whether its
## head's turned away from you: the slow, jerky movers never look at you).
var upright := false
var head_averted := false
var _upright_blend := 0.0
## How high its spine's middle stands over its feet (measured at the start).
var _stand_mid := 2.0
const UPRIGHT_BIT := 1 << 11
const AVERT_BIT := 1 << 12
const RISE_SPEED := 1.6 # (blend a second: it unfolds up over ~0.6 s)
## The stunts that wait for you (the user's: twice as long).
const BEHIND_HOLD := 16.0
const WATCH_HOLD := 30.0
## The leap: landed across the gap, it stands and stares this long, then goes.
const LEAP_STARE := 2.5
## The movers (ceiling, doorway, corpse drag), one of two at random each time
## (the user's): STOP AND LOOK -- halfway across it stops dead MOVER_STOP_TIME
## and looks at you, then goes on at MOVER_SLOW; or SLOW AND WRONG -- across
## in jerky snatches at MOVER_CRAWL, never looking at you.
const MOVER_STOP_TIME := 1.2
const MOVER_SLOW := 0.45
const MOVER_CRAWL := 0.3
var _mover_style := 0
var _mover_time := 0.0
var _mover_stopped := false
var _mover_stop_left := 0.0
var _mover_length := 1.0
## The angel (the user's: a weeping angel): standing dead still ANGEL_FROM
## off; each time you look away and back it's ANGEL_STEP closer; within
## ANGEL_CLOSEST it's gone. ANGEL_HOLD at most.
const ANGEL_FROM := 40.0
const ANGEL_STEP := 5.0
const ANGEL_CLOSEST := 8.0
const ANGEL_HOLD := 90.0
var _angel_seen := false
## At Grandma's (the user's: in the rotation while its player's in the house):
## KNOCK -- three slow knocks at the front door; opened within KNOCK_WAIT,
## it's out at the fog's edge (KNOCK_OFF), upright, walking away
## (WALK_AWAY), gone after KNOCK_SHOWN or once they step out. WINDOW -- its
## antlered shadow against a window's pane, lit from outside (StalkerSigns),
## WINDOW_HOLD at most.
const KNOCK_WAIT := 40.0
const KNOCK_OFF := 45.0
const KNOCK_SHOWN := 12.0
const WALK_AWAY := 1.4
const WINDOW_HOLD := 15.0
var _house: GrandmasHouse
var _window_at := Vector3.INF

## OUT IN THE OPEN, MOVING FAST (the user's, 2026-10-21: FAST_SPEED and up --
## bhopping, building speed): these come first then. Gone in sight never
## means vanishing: it scrambles off out of sight (the user's).
##   PACER -- alongside you PACER_OFF out, keeping pace however fast; watched
##   PACER_WATCHED (or after PACER_TIME) it peels off into the murk.
##   PATH -- standing upright where you're heading (PATH_AHEAD s on), hidden
##   till you see it; within PATH_FLEE it scrambles off, fast.
##   CROSS -- one long bound across your way ahead (CROSS_FLIGHT s, a
##   silhouette), from out of your view; it lands and scrambles off.
##   GRAPPLE -- you're flying on the grapple: from out of sight it races to
##   where you're headed and crouches there; as you get within GRAPPLE_FLEE,
##   it scrambles off.
const FAST_SPEED := 18.0
const PACER_OFF := 40.0
const PACER_TIME := 10.0
const PACER_WATCHED := 2.0
const PACER_TOP := 32.0
const PATH_AHEAD := Vector2(2.0, 4.0)
const PATH_FLEE := 24.0 # (past GRAB_RANGE: it runs, it doesn't lunge)
const PATH_HOLD := 12.0
const CROSS_FLIGHT := 1.3
const GRAPPLE_FLEE := 6.0
const GRAPPLE_HOLD := 6.0
var _pacer_side := 1.0
var _watched_for := 0.0
## Each player's last shot (msec): fighting (the fight stunts).
var _last_shot := {}
## FIGHTING (the user's, 2026-10-21: no silence for these; on the normal
## clock): a shot within FIGHT_SHOT and a live enemy within FIGHT_RANGE --
## these come first then.
##   SNATCH -- one of the things they're fighting (anything) yanked off into
##   the dark: it rushes in from out of sight, its arm reaches, grips it by
##   the head, and drags it away (SNATCH_DRAG), a human screaming.
##   FIGHT_WATCH -- upright at the edge of the fight, watching; the fight's
##   over (FIGHT_OVER) or they look straight at it: it scrambles off.
##   FALLEN -- as the fight ends (no one alive within FALLEN_CLEAR, shots
##   within FALLEN_AFTER), crouched over one of the bodies at the edge,
##   eating; seen, it looks up at them FALLEN_STARE, then drags it off by
##   the head.
##   AMONG -- one of the shapes charging them is it, upright: a fake charge
##   (AMONG_CHARGE, never closer than AMONG_STOP), then it veers off and
##   scrambles out of sight.
const FIGHT_SHOT := 8.0
const FIGHT_RANGE := 45.0
const SNATCH_DRAG := 6.0
const SNATCH_REACH := 3.0
const FIGHT_OVER := 5.0
const FIGHT_WATCH_HOLD := 60.0
const FALLEN_CLEAR := 25.0
const FALLEN_AFTER := 25.0
const FALLEN_STARE := 1.2
const FALLEN_HOLD := 45.0
const AMONG_CHARGE := 1.8
const AMONG_STOP := 24.0
## After a stunt, it gets away: no grab for this long (it's leaving).
const AFTER_STUNT_GRACE := 4.0
var _victim_thing: Node3D
var _fight_quiet := 0.0
var _no_grab_left := 0.0

## HOLDING (the user's, 2026-10-21: hand-accurate, immersive): its right arm
## really reaches (IK) for what it takes, and what it's got it holds in that
## hand -- a body by the HEAD (the ragdoll's head pulled to the hand, the rest
## dragging loose behind it) or a small thing whole. Ragdolls are each game's
## own, so every game holds its own copy: the host names the body by where it
## is (Network.send_stalker_sign "reach" / "hold" / "let_go"), and net_state
## says it's still reaching / holding. GRIP: where the hand holds it, in its
## own space (by its hip, the body trailing), times SIZE.
const HOLD_BIT := 1 << 13
const REACH_BIT := 1 << 14
const REACH_TIME := 0.3
const GRIP := Vector3(0.5, 0.3, 0.35)
const HOLD_PULL := 10.0
var holding := false
var reaching := false
var _held: Node3D
var _reach: Node3D
var _reach_t := 0.0
## Clients: a body named before its puppet's here -- looked for a moment.
var _sign_pending := {}
var _grip_limb := -1

## HUNGER (the user's, 2026-10-21: it draws it, and hunts): raw meat on a
## player and it stalks them MEAT_CLOSER as far back (and stunts come twice as
## often: _meat_carrier); rotten meat on one and it hunts them straight down
## their trail. Meat or a body left lying within FOOD_RANGE, nobody seeing
## it: it goes to it and eats (EAT_TIME, chewing every CHEW_EVERY), leaving
## only bones (StalkerSigns).
const MEAT_CLOSER := 0.5
const FOOD_RANGE := 80.0
const FOOD_LOOK_EVERY := 2.0
const EAT_TIME := 7.0
const CHEW_EVERY := 0.9
var _food: Node3D
var _food_look_left := 0.0
var _chew_left := 0.0
var _eating_for := 0.0

## Its breathing (the user's, 2026-10-21): within BREATH_RANGE of you and out
## of your sight, slow and wet from where it is, louder the closer -- each
## game for its own camera.
const BREATH_RANGE := 15.0
const BREATH_DB := 2.0
var _breath: AudioStreamPlayer3D
var _breath_level := 0.0

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
	_find_lair.call_deferred()


## Its lair: found from the Stack's shape (every game the same), built here.
func _find_lair() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_lair_at = StalkerLair.find_spot(get_tree())
	if not _lair_at.is_finite() or get_tree().get_first_node_in_group(StalkerLair.GROUP):
		return
	var lair := StalkerLair.new()
	lair.name = "StalkerLair"
	get_tree().current_scene.add_child(lair)
	lair.global_position = _lair_at


# ---- Co-op (NetEntities: a script-made one) ------------------------------------------

func net_spawn_args() -> Dictionary:
	return {}


func net_restore(_data: Dictionary) -> void:
	pass


## The fear meter, sent with each update (for the HUD's meter everywhere).
func net_state() -> int:
	return int(round(fear * 1000.0)) | (UPRIGHT_BIT if upright else 0) | (AVERT_BIT if head_averted else 0) \
			| (HOLD_BIT if holding else 0) | (REACH_BIT if reaching else 0) | (WOUNDED_BIT if wounded else 0)


func net_apply(value: int) -> void:
	fear = (value & 2047) / 1000.0
	upright = value & UPRIGHT_BIT != 0
	head_averted = value & AVERT_BIT != 0
	holding = value & HOLD_BIT != 0
	wounded = value & WOUNDED_BIT != 0
	reaching = value & REACH_BIT != 0
	if not holding and _held:
		_release_held()
	if not reaching:
		_reach = null


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
	_hold_tick(delta)
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
	_silence_tick(delta)
	_brain_tick(delta)
	_director_tick(delta)
	if state != State.STUNT and state != State.HOME and (upright or head_averted):
		upright = false # (a stunt cut short: back down on all fours)
		head_averted = false
	if state == State.APPROACH and is_instance_valid(_victim) and _cut_off_tick(delta, _victim):
		return
	if state == State.APPROACH or state == State.LUNGE or state == State.DRAG:
		_strike_tick(delta)
		return
	# Within GRAB_RANGE (looking at it or not): it lunges for them (not while
	# it's cooling down after a drag).
	var near := _nearest_player()
	_no_grab_left = maxf(_no_grab_left - delta, 0.0)
	if near and _cooldown_left <= 0.0 and _no_grab_left <= 0.0 and state != State.STUNT and state != State.HOME and near.drag == null and near.global_position.distance_to(global_position) < GRAB_RANGE:
		_lunge_at(near)
		return
	# Rushed at: off flat out to cover.
	if near and state != State.HIDE and state != State.STUNT and state != State.HOME:
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
		elif seen and state != State.HIDE and state != State.SPOTTED and state != State.HOME:
			state = State.SPOTTED
			_say(&"spotted", false, 0.6)
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
				_presence() # (seen: a sign of it, for the director)
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
	# Rotten meat on someone: it hunts them straight down their trail.
	if state == State.STALK or state == State.WAIT:
		var rotten := _meat_carrier(true)
		if rotten and rotten.global_position.distance_to(global_position) > HUNT_UNTIL:
			_start_hunt(rotten)
	# Food lying about, nobody seeing it: it goes to eat (not while a stunt's
	# coming, nor at full fear).
	if (state == State.STALK or state == State.WAIT) and fear < 1.0 and _pending_left < 0.0:
		_food_look_left -= delta
		if _food_look_left <= 0.0:
			_food_look_left = FOOD_LOOK_EVERY
			var food := _food_near()
			if food:
				_food = food
				_eating_for = 0.0
				_chew_left = 0.0
				state = State.EAT
	match state:
		State.HUNT:
			_hunt_tick(delta)
		State.EAT:
			_eat_tick(delta)
		State.HOME:
			_home_tick(delta)
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
				_say(&"hiding", false, VOICE_CHANCE * 0.5)
			else:
				_desired = (_hide_to - global_position).normalized() * (SPRINT if _hide_fast else SCRAMBLE)
		State.WAIT:
			_desired = Vector3.ZERO
			if _state_left <= 0.0:
				state = State.STALK
				_say(&"starts_stalking", false, VOICE_CHANCE)
		State.STALK:
			# The fear's full and they're not looking at it: round behind them.
			var prey := _grudge_target() if _grudge_target() else nearest
			if fear >= 1.0 and _cooldown_left <= 0.0 and prey.drag == null and not _seen() and _big_allowed() \
					and (hunger >= 1.0 or not _fire_near(prey.global_position, FIRE_AVOID)):
				_victim = prey
				state = State.APPROACH
				_say(&"flanking", false, VOICE_CHANCE)
				return

			# Round to a spot STALK_DISTANCE from them, on the side it's on.
			var away := global_position - nearest.global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
			var spot := nearest.global_position + away * STALK_DISTANCE * (MEAT_CLOSER if _carries_raw(nearest) else 1.0) * _mood_distance()
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
			_drag_voice_left -= delta
			if _drag_voice_left <= 0.0:
				_drag_voice_left = randf_range(DRAG_VOICE_EVERY.x, DRAG_VOICE_EVERY.y)
				_say(&"dragging", true)
			if _state_left <= 0.0:
				# Not loose in time: badly hurt, left there in the dark; it runs off.
				p.health.hurt_unscaled(DRAG_DAMAGE)
				_say(&"dropped", true)
				_let_go(true)


## Lunging for them (and grabbing on reaching them: _strike_tick's LUNGE).
func _lunge_at(p: PlayerMovement) -> void:
	_big_moment() # (a strike: a big moment)
	_victim = p
	state = State.LUNGE
	_state_left = LUNGE_TIME
	_say(&"lunge", true)


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
	_drag_voice_left = randf_range(DRAG_VOICE_EVERY.x, DRAG_VOICE_EVERY.y)
	_say(&"grab", true)
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
	_say(&"thrown_off", true)
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
	if fear >= 1.0 and not _was_full:
		_say(&"fear_full")
	_was_full = fear >= 1.0
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
				player.weapons.shot_fired.connect(func() -> void: _last_shot[player] = Time.get_ticks_msec())
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
			if Time.get_ticks_msec() - _sound_msec < int(REACT_WINDOW * 1000.0):
				_spins += 1 # (spun round at its sound: a habit it learns)
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
	_say(&"starts_hunting", false, VOICE_CHANCE)
	_hunt_voice_left = randf_range(HUNT_VOICE_EVERY.x, HUNT_VOICE_EVERY.y)
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
	_hunt_voice_left -= delta
	if _hunt_voice_left <= 0.0:
		_hunt_voice_left = randf_range(HUNT_VOICE_EVERY.x, HUNT_VOICE_EVERY.y)
		_say(&"hunting")
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


## You slept (Bedroll, the host's): while you did, it came on -- at once,
## SLEEP_PROGRESS of the way down your trail from where it was to you, onto
## a crumb no one can see it on (never past your newest). Not mid-strike,
## mid-stunt, fleeing, gone or in someone's view (it never vanishes in sight).
func slept(p: PlayerMovement, bed: Node3D = null) -> void:
	_noticed(p, &"sleep")
	if bed and randf() < CAMP_VISIT_CHANCE:
		camp_visit(bed)
	_slept_on_trail(p)


## It came while they slept: its signs round `bed` (every game).
func camp_visit(bed: Node3D) -> void:
	Network.send_stalker_sign(0, &"camp_visit", bed.global_position, bed.global_basis.z)


func _slept_on_trail(p: PlayerMovement) -> void:
	if state in [State.DRAG, State.LUNGE, State.FLEE, State.AWAY, State.STUNT] or _seen():
		return
	var points: PackedVector3Array = (_trails.get(p, {}) as Dictionary).get("points", PackedVector3Array())
	if points.size() < 3:
		return
	if state != State.HUNT or _hunted != p:
		_start_hunt(p)
	var keep := _trail_left(points, _crumb) * (1.0 - SLEEP_PROGRESS)
	var left := _trail_left(points, _crumb)
	for j in range(_crumb + 1, points.size() - 1):
		left -= points[j - 1].distance_to(points[j])
		if left > keep or _visible_from_any(_body_points(points[j], Basis.IDENTITY)):
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
		_say(&"turns_up", false, VOICE_CHANCE)
		return true
	return false


## A voice (StalkerVoices `slot`) from it (or `at`). `urgent`: past the
## VOICE_GAP; `chance`: only that often (ambient ones). The host's: everyone hears.
func _say(slot: StringName, urgent: bool = false, chance: float = 1.0, at: Vector3 = Vector3.INF, volume_db: float = 0.0) -> void:
	var now := Time.get_ticks_msec()
	if not urgent and now - _voice_msec < int(VOICE_GAP * 1000.0):
		return
	if randf() > chance:
		return
	_voice_msec = now
	Network.send_stalker_voice(slot, at if at.is_finite() else global_position + Vector3.UP * BODY_HEIGHT, volume_db)


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
	_say(&"runs_away", false, VOICE_CHANCE)
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
	if attacker != Health.NO_ATTACKER:
		_grudge[attacker] = float(_grudge.get(attacker, 0.0)) + amount
		var fresh := true
		for spot: Array in _shot_spots:
			if (spot[0] as Vector3).distance_to(global_position) < 5.0:
				spot[1] = Time.get_ticks_msec()
				fresh = false
		if fresh:
			_shot_spots.append([global_position, Time.get_ticks_msec()])
	if amount >= HURT_MOOD or _hurt >= HURT_MOOD:
		_wounded_left = WOUNDED_TIME
		_furious_left = 0.0
	if _hurt < DRIVE_OFF and Time.get_ticks_msec() - _hurt_voice_msec > int(HURT_VOICE_GAP * 1000.0):
		_hurt_voice_msec = Time.get_ticks_msec()
		_say(&"hurt", true)
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
		_say(&"driven_off", true)
	elif state == State.STALK or state == State.WAIT:
		_start_hide(false)


## Gone for a while (driven off): out of the world entirely.
func _go_away() -> void:
	_say(&"leaves", true)
	state = State.AWAY
	_state_left = randf_range(AWAY_TIME.x, AWAY_TIME.y)
	_hurt = 0.0
	_velocity = Vector3.ZERO
	global_position = Vector3(global_position.x, AWAY_DEPTH, global_position.z)
	# Home to heal, if nobody's by its lair.
	if _lair_at.is_finite() and not _anyone_within(_lair_at, LAIR_LEAVE):
		_go_home(_state_left, true)


## Home in its lair: upright, still, watching. `healing`: driven off (gone the
## AWAY time); else a visit.
func _go_home(time: float, healing: bool) -> void:
	_place(_lair_at, Vector3.UP, Vector3.FORWARD, false)
	state = State.HOME
	_state_left = time
	_home_healing = healing
	_home_warn = -1.0
	upright = true


func _anyone_within(at: Vector3, reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p and not p.is_dead() and p.global_position.distance_to(at) < reach:
			return true
	return false


## At home: facing whoever's nearest; one within LAIR_DEFEND: it rises in
## warning, then attacks. Its time up (or a visit, everyone gone): back out.
func _home_tick(delta: float) -> void:
	_velocity = Vector3.ZERO
	_desired = Vector3.ZERO
	upright = true
	var near := _nearest_player()
	if near:
		_heading = _flat(near.global_position - global_position)
	if near and near.global_position.distance_to(global_position) < LAIR_DEFEND and near.drag == null:
		if _home_warn < 0.0:
			_home_warn = LAIR_WARN
			_say(&"spotted", true)
			_moment(true)
		_home_warn -= delta
		if _home_warn <= 0.0:
			upright = false
			_lunge_at(near) # (it defends its home)
		return
	if _state_left <= 0.0 or (not _home_healing and not _anyone_within(global_position, LAIR_LEAVE)):
		upright = false
		_turn_up()


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
	_stunt_target = _pending_target if is_instance_valid(_pending_target) and not _pending_target.is_dead() else players[randi() % players.size()] as PlayerMovement
	_pending_target = null
	# (Its sounds -- the rattle, the lure, the help scream -- are small signs
	# now: the director's, not a big moment's.)
	var kinds: Array = [Stunt.BEHIND, Stunt.CEILING, Stunt.DOORWAY, Stunt.WATCH, Stunt.DRAG]
	kinds.shuffle()
	if _climbing_outside(_stunt_target) and randf() < 0.5:
		kinds.push_front(Stunt.LEAP)
	if _fast(_stunt_target):
		var fast: Array = [Stunt.PACER, Stunt.PATH, Stunt.CROSS]
		fast.shuffle()
		fast.append_array(kinds)
		kinds = fast
	if _stunt_target.grapple.anchor_point().is_finite():
		kinds.push_front(Stunt.GRAPPLE)
	if _fighting(_stunt_target):
		var fight: Array = [Stunt.SNATCH, Stunt.FIGHT_WATCH, Stunt.AMONG]
		fight.shuffle()
		fight.append_array(kinds)
		kinds = fight
	if _fight_ending(_stunt_target):
		kinds.push_front(Stunt.FALLEN)
	# At Grandma's: the knock and the window join in (first, shuffled with
	# the rest -- they only fit there).
	var house := get_tree().get_first_node_in_group(&"grandmas_house") as GrandmasHouse
	if house and house.has_inside(_stunt_target.global_position):
		kinds.insert(randi() % (kinds.size() + 1), Stunt.KNOCK)
		kinds.insert(randi() % (kinds.size() + 1), Stunt.WINDOW)
	if _stares >= STARE_HABIT:
		# Stared down too often: nothing in front of them now -- behind, the sides.
		for front: int in [Stunt.WATCH, Stunt.PATH, Stunt.ANGEL, Stunt.FIGHT_WATCH]:
			if kinds.has(front):
				kinds.erase(front)
				kinds.append(front)
	if _trodden(_stunt_target.global_position) and not kinds.has(Stunt.PATH) and _stares < STARE_HABIT:
		kinds.push_front(Stunt.PATH) # (their usual way: it waits along it)
	var wanted := _mood_stunts()
	for i in range(wanted.size() - 1, -1, -1):
		if kinds.has(wanted[i]):
			kinds.erase(wanted[i])
			kinds.push_front(wanted[i])
	if _forced_kind >= 0:
		kinds = [_forced_kind]
	for kind: int in kinds:
		if _stage(kind):
			_last_pick = Stunt.keys()[kind]
			if state != State.STUNT:
				_silence_off_in = SOUND_STUNT_HOLD # (a sound only: the quiet lifts after it)
			if kind in SOUND_STUNTS:
				_presence()
			else:
				_big_moment()
			match kind:
				Stunt.CEILING:
					_say(&"ceiling_scuttle")
				Stunt.DOORWAY:
					_say(&"doorway_dash")
				Stunt.DRAG:
					_say(&"corpse_drag")
				Stunt.LEAP:
					_say(&"leap")
			return true
	return false


## The test menu (F9, StalkerTestMenu; the user's): `event` on `player` now,
## whatever its clocks say -- a stunt by name (Stunt), "silence", "breathing"
## (it waits hidden close behind them). What happened, for the menu. The host's.
func test_event(event: StringName, player: PlayerMovement) -> String:
	if player == null or player.is_dead():
		return "No player"
	if state in [State.APPROACH, State.LUNGE, State.DRAG]:
		return "It's in the middle of a strike"
	if state == State.AWAY or global_position.y < AWAY_DEPTH * 0.5:
		_turn_up()
	if state == State.STUNT:
		_end_stunt()
	_pending_left = -1.0
	var peer := player.get_multiplayer_authority()
	match event:
		&"sign":
			return "Small sign" if _small_sign() else "No small sign fit here"
		&"tracks", &"kill":
			return "Sign: %s" % event if _small_sign(event) else "Didn't fit here"
		&"home":
			if not _lair_at.is_finite():
				return "No lair (no Stack here)"
			_go_home(HOME_VISIT, false)
			return "Home in its lair (the flooded depths), watching"
		&"peak":
			_since_big = BIG_GAP
			tension = 1.0
			phase = Phase.PEAK
			_big_retry = 0.0
			return "Big moment allowed now (the director picks)"
		&"silence":
			_silence(peer)
			_silence_off_in = 10.0
			return "Wrong silence (10 s)"
		&"eat":
			var food := _food_near()
			if food == null:
				return "No meat or body lying unseen within %d m" % int(FOOD_RANGE)
			_food = food
			_eating_for = 0.0
			_chew_left = 0.0
			state = State.EAT
			return "Going to eat (listen for it)"
		&"camp":
			var bed: Node3D = null
			for camp in get_tree().get_nodes_in_group(Camp.GROUP):
				for child in camp.get_children():
					if child is Bedroll and (bed == null or (child as Node3D).global_position.distance_to(player.global_position) < bed.global_position.distance_to(player.global_position)):
						bed = child
			if bed == null:
				return "No camp: build one first"
			camp_visit(bed)
			return "Camp visit at the nearest camp (go and look)"
		&"breathing":
			var behind := player.global_position + player.head.global_basis.z * 9.0
			var hit := _ground_at(behind)
			if hit.is_empty():
				return "No ground behind you"
			_place(hit.position, hit.normal, player.global_position - (hit.position as Vector3), false)
			state = State.WAIT
			_state_left = 20.0
			return "Waiting 9 m behind you (listen)"
	var kind := Stunt.keys().find(String(event).to_upper())
	if kind < 0:
		return "Unknown: %s" % event
	state = State.STALK
	_cooldown_left = 0.0
	_forced_kind = kind
	_pending_target = player
	_pending_left = SILENCE_LEAD
	_silence(peer)
	return "%s in %d s" % [Stunt.keys()[kind].capitalize(), int(SILENCE_LEAD)]


## The director, each tick (the host's): the phase, the tension, a small
## sign when one's due, a big moment when it's allowed.
func _director_tick(delta: float) -> void:
	_since_big += delta
	if phase == Phase.RELAX:
		_relax_left -= delta
		if _relax_left <= 0.0:
			phase = Phase.BUILD
			_roll_sign()
		return
	var pace := (1.0 + fear) * _mood_pace()
	if _meat_carrier(false):
		pace *= 2.0 # (it smells it)
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and _fighting(player):
			pace *= 1.4
			break
	for node in get_tree().get_nodes_in_group("player"):
		if _fast(node as PlayerMovement):
			pace *= 1.25
			break
	tension = minf(tension + delta / TENSION_TIME * pace, 1.0)
	phase = Phase.PEAK if _big_allowed() else Phase.BUILD
	var free := (state == State.STALK or state == State.WAIT or state == State.HUNT) and _cooldown_left <= 0.0 and _pending_left < 0.0
	if phase == Phase.PEAK and free:
		_big_retry -= delta
		if _big_retry <= 0.0:
			_big_retry = 5.0
			if state != State.STALK:
				state = State.STALK
			_prepare_stunt()
		return
	_sign_left -= delta * (1.0 + tension * 1.5) # (sooner as tension rises)
	if _sign_left <= 0.0 and free:
		if _small_sign():
			_presence()
		else:
			_sign_left = 10.0


## A big moment may come now: not relaxing, BIG_GAP since the last, tension
## full -- and not wounded.
func _big_allowed() -> bool:
	return phase != Phase.RELAX and _since_big >= BIG_GAP and tension >= 1.0 and mood() != Mood.WOUNDED


## Its drives, each tick (the host's): hunger rising, curiosity at what the
## players do (and fading), the hurt moods running out; its memory; fire.
func _brain_tick(delta: float) -> void:
	_memory_tick(delta)
	_fire_tick(delta)
	hunger = minf(hunger + delta / HUNGER_TIME, 1.0)
	curiosity = maxf(curiosity - delta / CURIOUS_FADE, 0.0)
	if _wounded_left > 0.0:
		_wounded_left -= delta
		if _wounded_left <= 0.0:
			_furious_left = FURIOUS_TIME # (healed: now it's angry)
	else:
		_furious_left = maxf(_furious_left - delta, 0.0)
	wounded = _wounded_left > 0.0
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p == null or p.is_dead():
			continue
		# Something it hasn't seen them do.
		if p.grapple.is_out():
			_noticed(p, &"grapple")
		if HallEcho.inside(p.global_position):
			_noticed(p, &"inside")
		for camp in get_tree().get_nodes_in_group(Camp.GROUP):
			if (camp as Node3D).global_position.distance_to(p.global_position) < 6.0:
				_noticed(p, &"camp")
		# Fast, still, fighting: it wants to see.
		var speed := Vector2(p.velocity.x, p.velocity.z).length()
		_still_for[p] = float(_still_for.get(p, 0.0)) + delta if speed < 0.5 else 0.0
		if _fast(p):
			_curious(delta * 0.03, &"speed")
		elif float(_still_for[p]) > QUIET_AFTER:
			_curious(delta * 0.04, &"quiet")
		if _fighting(p):
			_curious(delta * 0.04, &"fight")


## Its memory, each tick: old shot spots forgotten, the routes counted, the
## camps watched, grudges fading.
func _memory_tick(delta: float) -> void:
	_lair_tick()
	var now := Time.get_ticks_msec()
	_shot_spots = _shot_spots.filter(func(spot: Array) -> bool: return now - int(spot[1]) < int(SHOT_MEMORY * 1000.0))
	for peer: int in _grudge.keys():
		_grudge[peer] = float(_grudge[peer]) * exp(-delta / GRUDGE_FADE)
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p == null or p.is_dead():
			continue
		var cell := Vector2i(floori(p.global_position.x / ROUTE_CELL), floori(p.global_position.z / ROUTE_CELL))
		if _last_cell.get(p, Vector2i(999999, 999999)) != cell:
			_last_cell[p] = cell
			_route_cells[cell] = int(_route_cells.get(cell, 0)) + 1
		# Back at a camp they've used, after being away: its tracks round it, now and then.
		var nearest_camp: Node3D = null
		for camp in get_tree().get_nodes_in_group(Camp.GROUP):
			if nearest_camp == null or (camp as Node3D).global_position.distance_to(p.global_position) < nearest_camp.global_position.distance_to(p.global_position):
				nearest_camp = camp
		if nearest_camp:
			var gap := nearest_camp.global_position.distance_to(p.global_position)
			if gap > CAMP_AWAY:
				_away_from_camp[p] = true
			elif gap < 40.0 and _away_from_camp.get(p, false):
				_away_from_camp[p] = false
				if randf() < CAMP_SIGNS:
					var bed: Node3D = null
					for child in nearest_camp.get_children():
						if child is Bedroll:
							bed = child
					if bed:
						Network.send_stalker_sign(0, &"tracks", bed.global_position, Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU))
						_presence()


## Someone coming up on its lair (within LAIR_NOTICE, once an approach):
## LAIR_CHANCE it's there.
func _lair_tick() -> void:
	if not _lair_at.is_finite():
		return
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p == null or p.is_dead():
			continue
		var gap := p.global_position.distance_to(_lair_at)
		if gap > LAIR_LEAVE:
			_near_lair[p] = false
		elif gap < LAIR_NOTICE and not _near_lair.get(p, false):
			_near_lair[p] = true
			if (state == State.STALK or state == State.WAIT or state == State.HUNT) and randf() < LAIR_CHANCE:
				_go_home(HOME_VISIT, false)


## Well-trodden: a square of the land they've come through TRODDEN times.
func _trodden(at: Vector3) -> bool:
	return int(_route_cells.get(Vector2i(floori(at.x / ROUTE_CELL), floori(at.z / ROUTE_CELL)), 0)) >= TRODDEN


## The player it holds a grudge against (over GRUDGE_MIN), or null.
func _grudge_target() -> PlayerMovement:
	var best: PlayerMovement = null
	var most := GRUDGE_MIN
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerMovement
		if p and not p.is_dead() and float(_grudge.get(p.get_multiplayer_authority(), 0.0)) > most:
			most = float(_grudge[p.get_multiplayer_authority()])
			best = p
	return best


## Fire, each tick: closer than FIRE_BURN to one, it burns (like damage).
func _fire_tick(delta: float) -> void:
	_burn_left -= delta
	if _burn_left > 0.0 or global_position.y < AWAY_DEPTH * 0.5:
		return
	_burn_left = 0.25
	if _fire_near(global_position, FIRE_BURN):
		_health.take_damage(FIRE_DPS * 0.25)


## Whether there's a fire burning within `reach` of `at`.
static func _fire_near(at: Vector3, reach: float) -> bool:
	for fire in FireSource._fires:
		if is_instance_valid(fire) and fire.is_inside_tree() and fire.global_position.distance_to(at) < reach:
			return true
	return false


## Keeps clear of fire (unless starving) and of where it was shot: a push
## away from them, for its crawl.
func _avoid_push(at: Vector3) -> Vector3:
	var push := Vector3.ZERO
	if hunger < 1.0:
		for fire in FireSource._fires:
			if is_instance_valid(fire) and fire.is_inside_tree():
				var away := at - fire.global_position
				away.y = 0.0
				var d := away.length()
				if d < FIRE_AVOID and d > 0.01:
					push += away / d * (1.0 - d / FIRE_AVOID)
	for spot: Array in _shot_spots:
		var away: Vector3 = at - (spot[0] as Vector3)
		away.y = 0.0
		var d := away.length()
		if d < SHOT_AVOID and d > 0.01:
			push += away / d * (1.0 - d / SHOT_AVOID)
	return push * SPRINT


func _noticed(p: PlayerMovement, what: StringName) -> void:
	var key := "%d:%s" % [p.get_instance_id(), what]
	if _seen_doing.has(key):
		return
	_seen_doing[key] = true
	_curious(NEW_THING, &"new")


func _curious(amount: float, about: StringName) -> void:
	curiosity = minf(curiosity + amount, 1.0)
	_curious_about = about


## What it feels most now.
func mood() -> Mood:
	if _wounded_left > 0.0:
		return Mood.WOUNDED
	if _furious_left > 0.0:
		return Mood.FURIOUS
	if hunger >= HUNGRY and hunger >= curiosity:
		return Mood.HUNGRY
	if curiosity >= CURIOUS:
		return Mood.CURIOUS
	return Mood.CALM


## How fast tension builds, by mood.
func _mood_pace() -> float:
	match mood():
		Mood.HUNGRY:
			return 1.3
		Mood.CURIOUS:
			return 1.2
		Mood.FURIOUS:
			return 1.5
	return 1.0


## How far back it stalks, by mood (times STALK_DISTANCE).
func _mood_distance() -> float:
	match mood():
		Mood.HUNGRY:
			return 0.75
		Mood.WOUNDED:
			return 1.8
		Mood.FURIOUS:
			return 0.6
	return 1.0


## The stunts its mood wants (first, where they fit).
func _mood_stunts() -> Array:
	match mood():
		Mood.HUNGRY:
			return [Stunt.SNATCH, Stunt.FALLEN]
		Mood.FURIOUS:
			return [Stunt.AMONG, Stunt.BEHIND, Stunt.SNATCH, Stunt.PATH, Stunt.CROSS]
		Mood.CURIOUS:
			match _curious_about:
				&"speed":
					return [Stunt.PACER, Stunt.CROSS, Stunt.PATH]
				&"quiet":
					return [Stunt.WATCH, Stunt.BEHIND, Stunt.ANGEL]
				&"fight":
					return [Stunt.FIGHT_WATCH, Stunt.AMONG]
				_:
					return [Stunt.WATCH, Stunt.PATH, Stunt.ANGEL]
	return []


## It ate (meat, a body, a snatch): hunger filled.
func _fed() -> void:
	hunger = maxf(hunger - MEAL, 0.0)


## A big moment came (a stunt you see, a strike): tension spent, the quiet.
func _big_moment() -> void:
	_since_big = 0.0
	tension = 0.0
	phase = Phase.RELAX
	_relax_left = RELAX_TIME
	_presence()


## A sign of it (or a glimpse): the next sign's gap starts over.
func _presence() -> void:
	_roll_sign()


func _roll_sign() -> void:
	_sign_left = randf_range(SIGN_GAP.x, SIGN_GAP.y)


## A small sign, on one of them: its distant sounds, its breathing close by,
## its tracks across their way, a kill on their route. False: none fit.
func _small_sign(only: StringName = &"") -> bool:
	var players := get_tree().get_nodes_in_group("player").filter(func(n: Node) -> bool:
		return n is PlayerMovement and not (n as PlayerMovement).is_dead())
	if players.is_empty():
		return false
	var p := players[randi() % players.size()] as PlayerMovement
	var kinds: Array = [&"rattle", &"lure", &"help", &"tracks", &"kill", &"breathe"] if only == &"" else [only]
	kinds.shuffle()
	var going := _flat(p.velocity) if Vector2(p.velocity.x, p.velocity.z).length() > 2.0 else _flat(-p.head.global_basis.z)
	for kind: StringName in kinds:
		match kind:
			&"rattle", &"lure", &"help":
				_stunt_target = p
				_sound_msec = Time.get_ticks_msec()
				var stunt: int = {&"rattle": Stunt.RATTLE, &"lure": Stunt.LURE, &"help": Stunt.HELP}[kind]
				if _stage(stunt):
					_last_pick = "sign: " + String(kind)
					return true
			&"tracks":
				var hit := _ground_at(p.global_position + going * randf_range(18.0, 30.0) + Vector3.UP * 4.0)
				if not hit.is_empty():
					Network.send_stalker_sign(0, &"tracks", hit.position, going.cross(Vector3.UP))
					_last_pick = "sign: tracks"
					return true
			&"kill":
				var hit := _ground_at(p.global_position + going * randf_range(25.0, 45.0) + going.cross(Vector3.UP) * randf_range(-6.0, 6.0) + Vector3.UP * 4.0)
				if not hit.is_empty() and not _visible_to(p, [(hit.position as Vector3) + Vector3.UP * 0.3]):
					Network.send_stalker_sign(0, &"kill", hit.position)
					_last_pick = "sign: kill"
					return true
			&"breathe":
				var hit := _ground_at(p.global_position - going * randf_range(9.0, 12.0) + Vector3.UP * 3.0)
				if not hit.is_empty() and _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), true):
					state = State.WAIT
					_state_left = 15.0
					_last_pick = "sign: breathe"
					return true
	return false


## Its brain, for the F9 menu: the director, its fear, what it's doing.
func debug_text() -> String:
	var grudge := _grudge_target()
	return "Phase %s   tension %d%%\nBig moment allowed in %ds (gap %ds)   next sign in %ds\nMood %s   hunger %d%%   curiosity %d%% (%s)   wounded %ds   furious %ds\nMemory: %d shot spots, %d squares walked, spins %d/%d, stares %d/%d, grudge: %s\nFear %d%%   state %s   last: %s" % [
			Phase.keys()[phase], roundi(tension * 100.0), maxi(int(BIG_GAP - _since_big), 0), int(BIG_GAP),
			int(_sign_left), Mood.keys()[mood()], roundi(hunger * 100.0), roundi(curiosity * 100.0), _curious_about,
			int(_wounded_left), int(_furious_left), _shot_spots.size(), _route_cells.size(), _spins, SPIN_HABIT, _stares, STARE_HABIT,
			("peer %d" % grudge.get_multiplayer_authority()) if grudge else "none",
			roundi(fear * 100.0), State.keys()[state], _last_pick]


## A stunt's due: its player picked, and the world goes quiet round them
## first (SILENCE_LEAD); _silence_tick stages it then.
func _prepare_stunt() -> void:
	var players := get_tree().get_nodes_in_group("player").filter(func(n: Node) -> bool:
		return n is PlayerMovement and not (n as PlayerMovement).is_dead())
	if players.is_empty():
		return
	_pending_target = players[randi() % players.size()] as PlayerMovement
	var grudge := _grudge_target()
	if grudge and randf() < GRUDGE_PICK:
		_pending_target = grudge # (the one who hurt it most)
	if _fighting(_pending_target) or _fight_ending(_pending_target):
		_pending_left = 0.0 # (in a fight: no silence -- the user's)
		return
	_pending_left = SILENCE_LEAD
	_silence(_pending_target.get_multiplayer_authority())


## The silence's clock: the pending stunt staged once it's fallen (none fit:
## it lifts, and another's tried soon), and lifted once a stunt's done.
func _silence_tick(delta: float) -> void:
	if _pending_left >= 0.0:
		_pending_left -= delta
		if (_forced_kind < 0 or _forced_kind == Stunt.GRAPPLE) and is_instance_valid(_pending_target) and _pending_target.grapple.anchor_point().is_finite():
			_pending_left = -0.001 # (on the grapple now: it goes for where they're headed)
		if _pending_left < 0.0:
			var forced := _forced_kind >= 0
			var target := _pending_target
			if (forced or (state == State.STALK and _cooldown_left <= 0.0)) and _start_stunt():
				pass
			else:
				if forced and is_instance_valid(target):
					Network.send_message(target.get_multiplayer_authority(), "(test) %s didn't fit here" % Stunt.keys()[_forced_kind].capitalize())
				_pending_target = null
				_unsilence()
				_big_retry = 5.0 # (none fit here: tried again shortly)
			_forced_kind = -1
	if _silence_off_in >= 0.0:
		_silence_off_in -= delta
		if _silence_off_in < 0.0:
			_unsilence()


func _silence(peer: int) -> void:
	if _silenced_peer != 0 and _silenced_peer != peer:
		_unsilence()
	_silenced_peer = peer
	_silence_off_in = -1.0
	Network.send_stalker_sign(peer, &"silence_on")


func _unsilence() -> void:
	if _silenced_peer != 0:
		Network.send_stalker_sign(_silenced_peer, &"silence_off")
	_silenced_peer = 0
	_silence_off_in = -1.0


## Whether `p` has raw (unrotten) meat in their pack (it smells it).
func _carries_raw(p: PlayerMovement) -> bool:
	if p == null or p.backpack == null:
		return false
	for chunk: Dictionary in p.backpack.meat:
		if int(chunk.get("kind", Backpack.Kind.MEAT)) == Backpack.Kind.MEAT and not CarryItem.is_rotten_data(chunk):
			return true
	return false


## The nearest meat or body lying within FOOD_RANGE that nobody can see.
func _food_near() -> Node3D:
	var best: Node3D = null
	var best_distance := FOOD_RANGE
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(InteractHighlight.GROUP):
		var item := node as CarryItem
		if item and item.kind == Backpack.Kind.MEAT and not item.freeze and not item.has_meta(&"fetched") and item.is_inside_tree():
			candidates.append([item, item.global_position])
	for node in get_tree().get_nodes_in_group(RatSwarm.CORPSE_GROUP):
		var body := node as Node3D
		if body == null or body == _corpse or body.has_meta(&"climber") or body.has_meta(&"dragged"):
			continue
		var ragdoll := body.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
		candidates.append([body, ragdoll.body_position() if ragdoll else body.global_position])
	for pair: Array in candidates:
		var at: Vector3 = pair[1]
		var distance := at.distance_to(global_position)
		if distance < best_distance and not _visible_from_any([at + Vector3.UP * 0.5]):
			best_distance = distance
			best = pair[0]
	return best


## Eating: to the food, then down over it, chewing, a while; then only bones.
func _eat_tick(delta: float) -> void:
	if not is_instance_valid(_food):
		state = State.STALK
		return
	var ragdoll := _food.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
	var at := ragdoll.body_position() if ragdoll else _food.global_position
	var to := at - global_position
	if to.length() > 2.5 * SIZE * 0.5:
		_desired = to.normalized() * CRAWL
		return
	_desired = Vector3.ZERO
	_velocity = Vector3.ZERO
	_heading = _flat(to)
	_eating_for += delta
	_chew_left -= delta
	if _chew_left <= 0.0:
		_chew_left = CHEW_EVERY * randf_range(0.7, 1.3)
		_say(&"chewing", true, 1.0, at + Vector3.UP * 0.4, -2.0)
	if _eating_for >= EAT_TIME:
		_fed()
		Network.send_stalker_sign(0, &"bones", at)
		if _food.has_method(&"_remove"):
			_food.call(&"_remove")
		else:
			_food.queue_free()
		_food = null
		state = State.STALK


## In a fight: shot within FIGHT_SHOT, a live enemy within FIGHT_RANGE.
func _fighting(p: PlayerMovement) -> bool:
	if p == null or Time.get_ticks_msec() - int(_last_shot.get(p, -1000000)) > int(FIGHT_SHOT * 1000.0):
		return false
	return not _live_enemies_near(p.global_position, FIGHT_RANGE).is_empty()


## A fight just over: shots within FALLEN_AFTER, no one alive within
## FALLEN_CLEAR, a body within FIGHT_RANGE.
func _fight_ending(p: PlayerMovement) -> bool:
	if p == null or Time.get_ticks_msec() - int(_last_shot.get(p, -1000000)) > int(FALLEN_AFTER * 1000.0):
		return false
	return _live_enemies_near(p.global_position, FALLEN_CLEAR).is_empty() and _corpse_for(p) != null


## The live enemies within `reach` of `at` (no bosses: too big to take).
func _live_enemies_near(at: Vector3, reach: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or body == self or body.global_position.distance_to(at) > reach:
			continue
		var health := body.get_node_or_null(^"Health") as Health
		if health == null or health.is_dead or health.max_health > 500.0:
			continue
		found.append(body)
	return found


## A body at the fight's edge they can't see now (for FALLEN), or null.
func _corpse_for(p: PlayerMovement) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"corpses"):
		var body := node as Node3D
		if body == null or body == _corpse or body.has_meta(&"climber") or body.has_meta(&"dragged"):
			continue
		var ragdoll := body.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
		var at := ragdoll.body_position() if ragdoll else body.global_position
		if at.distance_to(p.global_position) < FIGHT_RANGE and not _visible_to(p, [at + Vector3.UP * 0.5]):
			return body
	return null


## Moving fast (FAST_SPEED and up, flat).
func _fast(p: PlayerMovement) -> bool:
	return p != null and Vector2(p.velocity.x, p.velocity.z).length() >= FAST_SPEED


## A player carrying meat: raw (`rotten` false), or rotten -- or null.
func _meat_carrier(rotten: bool) -> PlayerMovement:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player == null or player.is_dead() or player.backpack == null:
			continue
		for chunk: Dictionary in player.backpack.meat:
			if int(chunk.get("kind", Backpack.Kind.MEAT)) != Backpack.Kind.MEAT:
				continue
			if CarryItem.is_rotten_data(chunk) == rotten:
				return player
	return null


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
		Stunt.LURE:
			# "Help me" / "follow me" (the user's voices), from one of three
			# places, any: out of sight nearby, right behind them, or far off
			# through the echo. A sound only; once a stunt, so it's sparse.
			var at := Vector3.INF
			var volume := 0.0
			match randi() % 3:
				0:
					for attempt in 8:
						var hit := _ground_at(p.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(15.0, 30.0))
						if not hit.is_empty() and not _visible_from_any(_body_points(hit.position, Basis.IDENTITY)):
							at = (hit.position as Vector3) + Vector3.UP * 1.5
							break
				1:
					at = p.global_position - look * 2.5 + Vector3.UP * 1.6
					volume = -6.0 # (a whisper)
				_:
					at = p.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(70.0, 120.0) + Vector3.UP * 3.0
			if not at.is_finite():
				return false
			_say(&"lure", true, 1.0, at, volume)
			_moment(at.distance_to(p.global_position) < 5.0) # (right behind them: they'd notice)
			return true
		Stunt.RATTLE:
			# Its croak right behind and above you; nothing there.
			_say(&"croak_behind", true, 1.0, p.global_position - look * 3.0 + Vector3.UP * 1.6)
			_moment(true) # (right behind them)
			return true
		Stunt.HELP:
			# A human voice screaming for help, far off; then it follows, unseen.
			# Where it came from: torn clothes, a blood trail off into the dark,
			# its long scratches in the ground (the user's) -- nobody.
			for attempt in 8:
				var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				var hit := _ground_at(p.global_position + way * randf_range(70.0, 140.0))
				if hit.is_empty():
					continue
				_help_spot = hit.position
				_help_time = 0.0
				_say(&"help_scream", true, 1.0, _help_spot + Vector3.UP * 1.5)
				Network.send_stalker_sign(0, &"help_signs", _help_spot, way)
				_moment()
				return true
			return false
		Stunt.BEHIND:
			if _spins >= SPIN_HABIT:
				# They whip round at its sounds (it's learnt): a croak behind them,
				# and when they turn, it's where they were looking.
				_bait_look = look
				_say(&"croak_behind", true, 1.0, p.global_position - look * 3.0 + Vector3.UP * 1.6)
				_sound_msec = Time.get_ticks_msec()
				_stunt_phase = 10
				_stunt_left_set(3.0)
				return true
			# Right behind you, still, staring -- there when you turn round.
			var hit := _ground_at(p.global_position - look * 3.5)
			if hit.is_empty() or not _place(hit.position, hit.normal, (p.global_position - (hit.position as Vector3)), true):
				return false
			# Standing, too tall, dead still, its head over at 90 degrees (the user's);
			# noticed: it looks at you a beat, then scrambles off.
			upright = true
			_stunt_left_set(BEHIND_HOLD)
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
			_mover_start(2.4)
			_stunt_left_set(7.0)
			_moment()
			return true
		Stunt.DOORWAY, Stunt.DRAG:
			# Across your way ahead, from cover to cover (a doorway, a gap):
			# skittering past -- or dragging a body after it.
			# Across where they're going (moving fast: where they'll be), from
			# cover to cover -- or out on the open land (the user's), from out of
			# their view on one side to out of it on the other.
			var ahead := Vector3(p.velocity.x, 0.0, p.velocity.z) * 1.5
			var middle := _ground_at(eye + look * randf_range(16.0, 26.0) + ahead)
			if middle.is_empty():
				return false
			var from := _cover_beside(middle.position, -side, p)
			var to := _cover_beside(middle.position, side, p)
			if not from.is_finite():
				from = _out_of_view_beside(middle.position, -side)
			if not to.is_finite():
				to = _out_of_view_beside(middle.position, side)
			if not from.is_finite() or not to.is_finite():
				return false
			if not _place(from, Vector3.UP, to - from, true):
				return false
			_stunt_to = to
			_mover_start(from.distance_to(to))
			_stunt_left_set(30.0)
			if kind == Stunt.DRAG:
				_corpse = CORPSE.instantiate() as Enemy
				_corpse.can_mutate = false
				_corpse.set_meta(&"culled", true) # nothing to drop
				get_tree().current_scene.add_child(_corpse)
				_corpse.global_position = from + (from - to).normalized() * 1.4 + Vector3.UP * 0.3
				var health := _corpse.get_node(^"Health") as Health
				health.take_damage(health.current_health + 1.0)
				hold.call_deferred(_corpse) # (by the head, in its hand -- once it's a ragdoll)
			return true
		Stunt.WATCH:
			# Off to the side in the dark, dead still, head tilted, rattling --
			# gone the moment you look away, or stare straight at it.
			var dir := look.rotated(Vector3.UP, randf_range(0.45, 0.7) * (1.0 if randf() < 0.5 else -1.0))
			var hit := _ground_at(eye + dir * randf_range(20.0, 35.0))
			if hit.is_empty() or not _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), false):
				return false
			_stunt_left_set(WATCH_HOLD)
			_stunt_rattle_left = 1.0
			return true
		Stunt.SNATCH:
			# One of the things they're fighting -- one off at the edge, not right
			# in front of them -- and somewhere near it they can't see.
			var victims := _live_enemies_near(p.global_position, FIGHT_RANGE)
			victims.sort_custom(func(a: Node3D, b: Node3D) -> bool:
				return look.dot(_flat(a.global_position - eye)) < look.dot(_flat(b.global_position - eye)))
			for victim in victims:
				for attempt in 6:
					var away := _flat(victim.global_position - p.global_position).rotated(Vector3.UP, randf_range(-1.2, 1.2))
					var hit := _ground_at(victim.global_position + away * randf_range(6.0, 12.0) + Vector3.UP * 4.0)
					if hit.is_empty() or not _place(hit.position, hit.normal, victim.global_position - (hit.position as Vector3), true):
						continue
					_victim_thing = victim
					_stunt_left_set(SNATCH_DRAG + 6.0)
					return true
			return false
		Stunt.FIGHT_WATCH:
			for attempt in 10:
				var way := look.rotated(Vector3.UP, randf_range(1.0, 1.5) * (1.0 if randf() < 0.5 else -1.0))
				var hit := _ground_at(p.global_position + way * randf_range(25.0, 35.0) + Vector3.UP * 5.0)
				if hit.is_empty() or not _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), true):
					continue
				upright = true
				_fight_quiet = 0.0
				_stunt_left_set(FIGHT_WATCH_HOLD)
				return true
			return false
		Stunt.FALLEN:
			var body := _corpse_for(p)
			if body == null:
				return false
			var ragdoll := body.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
			var at := ragdoll.body_position() if ragdoll else body.global_position
			var far_side := _flat(at - p.global_position)
			var hit := _ground_at(at + far_side * 1.6 + Vector3.UP * 3.0)
			if hit.is_empty() or not _place(hit.position, hit.normal, at - (hit.position as Vector3), true):
				return false
			_victim_thing = body
			head_averted = true # (head down over it, eating)
			_stunt_rattle_left = 0.0
			_stunt_left_set(FALLEN_HOLD)
			return true
		Stunt.AMONG:
			var chargers := _live_enemies_near(p.global_position, 40.0)
			for charger in chargers:
				var gap := charger.global_position.distance_to(p.global_position)
				if gap < AMONG_STOP + 6.0:
					continue
				# From just past the edge of their view beside it: it joins the charge.
				var behind := _flat(charger.global_position - p.global_position)
				var from := _out_of_view_beside(charger.global_position, behind.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0))
				if not from.is_finite():
					continue
				_place(from, Vector3.UP, p.global_position - from, false)
				upright = true
				_stunt_left_set(AMONG_CHARGE)
				return true
			return false
		Stunt.PACER:
			var going := _flat(p.velocity)
			_pacer_side = 1.0 if randf() < 0.5 else -1.0
			var beside := going.cross(Vector3.UP) * _pacer_side
			var hit := _ground_at(p.global_position + beside * PACER_OFF + going * 6.0 + Vector3.UP * 6.0)
			if hit.is_empty() or not _place(hit.position, hit.normal, going, true):
				return false
			_watched_for = 0.0
			_stunt_left_set(PACER_TIME)
			return true
		Stunt.PATH:
			var going := _flat(p.velocity)
			var speed := Vector2(p.velocity.x, p.velocity.z).length()
			if speed < FAST_SPEED:
				speed = FAST_SPEED # (walking their usual way: it waits further along it)
			for seconds: float in [PATH_AHEAD.y, PATH_AHEAD.x, (PATH_AHEAD.x + PATH_AHEAD.y) * 0.5]:
				for off: float in [0.0, 8.0, -8.0, 15.0, -15.0]:
					var spot := p.global_position + going * speed * seconds + going.cross(Vector3.UP) * off
					var hit := _ground_at(spot + Vector3.UP * 6.0)
					if hit.is_empty() or absf((hit.position as Vector3).y - p.global_position.y) > 25.0:
						continue
					if _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), true):
						upright = true
						_stunt_left_set(PATH_HOLD)
						return true
			return false
		Stunt.CROSS:
			var going := _flat(p.velocity)
			var speed := Vector2(p.velocity.x, p.velocity.z).length()
			var middle := _ground_at(p.global_position + going * maxf(speed * 2.0, 30.0) + Vector3.UP * 6.0)
			if middle.is_empty():
				return false
			var across := going.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			var from := _out_of_view_beside(middle.position, -across)
			if not from.is_finite():
				return false
			var to_hit := _ground_at((middle.position as Vector3) + across * from.distance_to(middle.position) + Vector3.UP * 6.0)
			if to_hit.is_empty():
				return false
			_place(from, Vector3.UP, across, false)
			_velocity = ((to_hit.position as Vector3) - from) / CROSS_FLIGHT + Vector3.UP * 0.5 * GRAVITY * CROSS_FLIGHT
			_heading = _flat(_velocity)
			_airborne = true
			_stunt_left_set(CROSS_FLIGHT + 0.4)
			_moment()
			return true
		Stunt.GRAPPLE:
			var anchor := p.grapple.anchor_point()
			if not anchor.is_finite():
				return false
			# From somewhere near it they can't see, it races there.
			for attempt in 10:
				var way := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				var hit := _ground_at(anchor + way * randf_range(6.0, 14.0) + Vector3.UP * 4.0)
				if hit.is_empty() or not _place(hit.position, hit.normal, anchor - (hit.position as Vector3), true):
					continue
				_stunt_to = anchor
				_stunt_left_set(GRAPPLE_HOLD)
				return true
			return false
		Stunt.KNOCK:
			_house = get_tree().get_first_node_in_group(&"grandmas_house") as GrandmasHouse
			if _house == null or not _house.has_inside(p.global_position) or _house.front_door() == null:
				return false
			var door := _house.front_door()
			var out := -_house.global_basis.z
			_say(&"knock", true, 1.0, door.global_position + out * 0.5 + Vector3.UP * 0.5)
			_stunt_left_set(KNOCK_WAIT)
			_moment(true)
			return true
		Stunt.WINDOW:
			_house = get_tree().get_first_node_in_group(&"grandmas_house") as GrandmasHouse
			if _house == null or not _house.has_inside(p.global_position):
				return false
			# A window they're facing, in reach, nothing between.
			var best: Array = []
			var best_dot := 0.2
			for window: Array in _house.windows():
				var to: Vector3 = (window[0] as Vector3) - eye
				var facing := look.dot(_flat(to))
				if to.length() < 30.0 and facing > best_dot:
					best_dot = facing
					best = window
			if best.is_empty():
				return false
			_window_at = best[0]
			Network.send_stalker_sign(0, &"window", best[0], best[1])
			_stunt_left_set(WINDOW_HOLD)
			return true
		Stunt.ANGEL:
			# Standing dead still ANGEL_FROM off, somewhere they'll see it when
			# they turn: closer every time they look away.
			for attempt in 12:
				var way := look.rotated(Vector3.UP, randf_range(0.9, PI) * (1.0 if randf() < 0.5 else -1.0))
				var hit := _ground_at(p.global_position + way * ANGEL_FROM * randf_range(0.85, 1.1) + Vector3.UP * 3.0)
				if hit.is_empty() or absf(((hit.position as Vector3) - p.global_position).y) > 8.0:
					continue
				if not _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), true):
					continue
				upright = true
				_angel_seen = false
				_stunt_left_set(ANGEL_HOLD)
				return true
			return false
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
				_stunt_left_set(flight + LEAP_STARE)
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
			if _stunt_phase == 10:
				# The bait: once they've turned (or a beat), it's where they were looking.
				var now_look := _flat(-p.head.global_basis.z)
				if now_look.dot(_bait_look) < -0.2 or _state_left <= 0.0:
					var hit := _ground_at(p.global_position + _bait_look * 3.5)
					if hit.is_empty() or not _place(hit.position, hit.normal, p.global_position - (hit.position as Vector3), true):
						_end_stunt()
						return
					upright = true
					_stunt_phase = 0
					_state_left = BEHIND_HOLD
					_stunt_rattle_left = 3.0
				return
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			_stunt_rattle_left -= delta
			if _stunt_rattle_left <= 0.0 and _stunt_phase == 0:
				_stunt_rattle_left = 999.0
				_say(&"behind_you", true, 1.0, global_position + Vector3.UP * 0.8)
				_moment()
			if _stunt_phase == 1 and _state_left <= 0.0:
				_end_stunt()
		Stunt.CEILING:
			_desired = _flat_perpendicular(_normal, _stunt_to) * SCRAMBLE * _mover_pace(delta, _mover_time / 2.4)
		Stunt.DOORWAY, Stunt.DRAG:
			if _stunt_phase == 0 and _stunt == Stunt.DRAG and _state_left > 29.6:
				return # (the body falls limp first)
			var to := _stunt_to - global_position
			if to.length() < 1.5:
				_end_stunt()
				return
			var pace := _mover_pace(delta, 1.0 - to.length() / maxf(_mover_length, 0.1))
			_desired = to.normalized() * (DRAG_SPEED if _stunt == Stunt.DRAG else SCRAMBLE) * pace

		Stunt.WATCH:
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			_stunt_rattle_left -= delta
			if _stunt_rattle_left <= 0.0:
				_stunt_rattle_left = randf_range(5.0, 8.0)
				_say(&"watching", false, 1.0, global_position + Vector3.UP * 0.8)
			# Looked away for a second: it moves on.
			var look := -p.head.global_basis.z
			var to := (global_position - p.head.global_position).normalized()
			_stunt_away_for = _stunt_away_for + delta if look.dot(to) < cos(deg_to_rad(70.0)) else 0.0
			if _stunt_away_for > 1.0:
				_end_stunt()
			if _stunt_phase == 1 and _state_left <= 0.0:
				_end_stunt()
		Stunt.LEAP:
			if not _airborne:
				# Landed across the gap: up on its hind legs, staring back at you.
				upright = true
				_velocity = Vector3.ZERO
				_heading = _flat(p.global_position - global_position)
		Stunt.ANGEL:
			_angel_tick(p)
			if state != State.STUNT:
				return
		Stunt.KNOCK:
			_knock_tick(p)
			if state != State.STUNT:
				return
		Stunt.SNATCH:
			_snatch_tick(p, delta)
			if state != State.STUNT:
				return
		Stunt.FIGHT_WATCH:
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			_fight_quiet = 0.0 if _fighting(p) else _fight_quiet + delta
			var to := (global_position + Vector3.UP * SIZE - p.head.global_position).normalized()
			var stared := (-p.head.global_basis.z).dot(to) > cos(deg_to_rad(STARED_AT)) and _visible_to(p, _standing_points(global_position))
			if stared or _fight_quiet >= FIGHT_OVER:
				if stared:
					_stares += 1
				_end_stunt()
				return
		Stunt.FALLEN:
			_fallen_tick(p, delta)
			if state != State.STUNT:
				return
		Stunt.AMONG:
			# Charging them with the rest -- never into its own grab range.
			var gap := p.global_position.distance_to(global_position)
			_desired = _flat(p.global_position - global_position) * SPRINT if gap > AMONG_STOP else Vector3.ZERO
			if gap <= AMONG_STOP or _state_left <= 0.0:
				_end_stunt() # (veers off, scrambling out of sight)
				return
		Stunt.PACER:
			if _stunt_phase == 0:
				# Alongside them PACER_OFF out, keeping pace (however fast).
				var going := _flat(p.velocity)
				var spot := p.global_position + going.cross(Vector3.UP) * _pacer_side * PACER_OFF
				var keep := Vector3(p.velocity.x, 0.0, p.velocity.z) + (spot - global_position) * 0.8
				_desired = keep.limit_length(PACER_TOP)
				_watched_for = _watched_for + delta if _visible_to(p, _body_points(global_position, global_basis)) else 0.0
				if _watched_for >= PACER_WATCHED or _state_left <= 0.0:
					_stunt_phase = 1 # (peels off)
					_state_left = 4.0
			else:
				_desired = _flat(global_position - p.global_position) * SPRINT
				if not _seen() or _state_left <= 0.0:
					_end_stunt()
					return
		Stunt.PATH:
			_velocity = Vector3.ZERO
			_heading = _flat(p.global_position - global_position)
			if p.global_position.distance_to(global_position) < PATH_FLEE:
				_end_stunt() # (scrambles off, fast)
				return
		Stunt.CROSS:
			if not _airborne:
				_end_stunt() # (landed: off out of sight)
				return
		Stunt.GRAPPLE:
			var to := _stunt_to - global_position
			_desired = to.normalized() * SPRINT * 1.3 if to.length() > 1.5 else Vector3.ZERO
			if to.length() <= 1.5:
				_velocity = Vector3.ZERO
				_heading = _flat(p.global_position - global_position)
			if p.global_position.distance_to(global_position) < GRAPPLE_FLEE or not p.grapple.is_pulling():
				_end_stunt()
				return
		Stunt.WINDOW:
			# Seen (looked at, from inside): it counts, once.
			if not _stunt_seen and _window_at.is_finite():
				var to := (_window_at - p.head.global_position).normalized()
				if (-p.head.global_basis.z).dot(to) > cos(deg_to_rad(25.0)):
					_stunt_seen = true
					_moment(true)
					_add_fear(FEAR_SEEN, "saw it (window)")
	if _state_left <= 0.0 and _stunt_phase == 0:
		_end_stunt()


## The angel: dead still while they look at it; each time they've looked
## away (after seeing it), ANGEL_STEP closer, where they can't see it move;
## the next step would bring it within ANGEL_CLOSEST: gone.
func _angel_tick(p: PlayerMovement) -> void:
	_velocity = Vector3.ZERO
	_heading = _flat(p.global_position - global_position)
	var points := _standing_points(global_position)
	for box: Array in _hitboxes:
		points.append((box[0] as CollisionShape3D).global_position)
	if _visible_to(p, points):
		_angel_seen = true
		return
	if not _angel_seen:
		return
	_angel_seen = false
	var toward := _flat(p.global_position - global_position)
	var flat_gap := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	if flat_gap - ANGEL_STEP <= ANGEL_CLOSEST:
		_end_stunt() # (gone)
		return
	var hit := _ground_at(global_position + toward * ANGEL_STEP + Vector3.UP * 3.0)
	if hit.is_empty() or _visible_to(p, _standing_points(hit.position)):
		return
	_place(hit.position, hit.normal, toward, false)


## The snatch: rushing in at it; its arm reaching (SNATCH_REACH off); the
## grab -- dead, taken by the head (a human screams) -- and dragged off into
## the dark, flat out, away from them.
func _snatch_tick(p: PlayerMovement, delta: float) -> void:
	if not is_instance_valid(_victim_thing):
		_end_stunt()
		return
	match _stunt_phase:
		0:
			var at := _head_of(_victim_thing)
			var to := at - global_position
			_desired = to.normalized() * LUNGE
			if to.length() < SNATCH_REACH * SIZE * 0.5 + 1.0:
				_stunt_phase = 1
				_state_left = REACH_TIME
				reach_for(_victim_thing)
			elif _state_left <= SNATCH_DRAG:
				_end_stunt() # (never got to it)
		1:
			_desired = Vector3.ZERO
			_velocity = Vector3.ZERO
			if _state_left <= 0.0:
				# Got it.
				_victim_thing.set_meta(&"culled", true) # (taken: nothing dropped)
				var health := _victim_thing.get_node_or_null(^"Health") as Health
				var human := _victim_thing is Enemy
				if health and not health.is_dead:
					health.take_damage(health.current_health + 1.0)
				hold.call_deferred(_victim_thing)
				_fed()
				if human:
					_say(&"help_scream", true, 1.0, _head_of(_victim_thing))
				_moment(true)
				_stunt_phase = 2
				_state_left = SNATCH_DRAG
		2:
			_desired = (_flat(global_position - p.global_position) + _flat(_heading) * 0.3).normalized() * DRAG_SPEED * 2.2
			if _state_left <= 0.0 or (_state_left < SNATCH_DRAG - 2.0 and not _seen()):
				_end_stunt()


## Eating the fallen: head down over it, chewing; seen, it looks up at them a
## beat, then drags it off by the head, away into the dark.
func _fallen_tick(p: PlayerMovement, delta: float) -> void:
	if not is_instance_valid(_victim_thing):
		_end_stunt()
		return
	match _stunt_phase:
		0:
			_velocity = Vector3.ZERO
			_stunt_rattle_left -= delta
			if _stunt_rattle_left <= 0.0:
				_stunt_rattle_left = CHEW_EVERY * randf_range(0.7, 1.3)
				_say(&"chewing", true, 1.0, _head_of(_victim_thing), -2.0)
			if _visible_to(p, _body_points(global_position, global_basis)):
				head_averted = false # (looks up at them)
				_stunt_phase = 1
				_state_left = FALLEN_STARE
				_moment(true)
		1:
			_velocity = Vector3.ZERO
			if _state_left <= 0.0:
				hold(_victim_thing)
				_stunt_phase = 2
				_state_left = SNATCH_DRAG
		2:
			_desired = _flat(global_position - p.global_position) * DRAG_SPEED * 1.6
			if _state_left <= 0.0 or (_state_left < SNATCH_DRAG - 2.0 and not _seen()):
				_end_stunt()


## The knock: waiting for the door; opened, out at the fog's edge, upright,
## walking away from the house; they step out, or it's been KNOCK_SHOWN: gone.
func _knock_tick(p: PlayerMovement) -> void:
	if _house == null or not is_instance_valid(_house):
		_end_stunt()
		return
	var out := -_house.global_basis.z
	if _stunt_phase == 0:
		var door := _house.front_door()
		if door and not door.is_closed():
			var hit := _ground_at(door.global_position + out * KNOCK_OFF + out.cross(Vector3.UP) * randf_range(-8.0, 8.0) + Vector3.UP * 4.0)
			if hit.is_empty():
				_end_stunt()
				return
			_place(hit.position, hit.normal, out, false)
			upright = true
			head_averted = true # (walking away: not looking back)
			_stunt_phase = 1
			_state_left = KNOCK_SHOWN
			_moment(true)
		return
	_desired = out * WALK_AWAY
	if not _house.has_inside(p.global_position) and p.global_position.distance_to(_house.global_position) > 12.0 * GrandmasHouse.SIZE:
		_end_stunt() # (they came out after it: gone)
	elif _state_left <= 0.0:
		_end_stunt()


## Points up a standing body at `at` (its feet) -- what a player would see of it.
func _standing_points(at: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for h: float in [0.5, 1.5, 2.5, 3.4]:
		points.append(at + Vector3.UP * h * SIZE * 0.5)
	return points


## Whether player `p` could see any of `points` right now.
func _visible_to(p: PlayerMovement, points: Array[Vector3]) -> bool:
	var cone := cos(deg_to_rad(VIEW_CONE))
	var space := get_world_3d().direct_space_state
	var eye := p.head.global_position
	var look := -p.head.global_basis.z
	for point in points:
		var to := point - eye
		var distance := to.length()
		if distance > SEEN_RANGE or look.dot(to / maxf(distance, 0.001)) < cone:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, 1, [p.get_rid(), get_rid()]))
		if hit.is_empty() or (hit.position as Vector3).distance_to(point) < 0.5 * SIZE:
			return true
	return false


## A mover's start (ceiling, doorway, corpse drag): one of the two ways at
## random (the user's); `length` its way across (m), or its time (ceiling).
func _mover_start(length: float) -> void:
	_mover_style = randi() % 2
	_mover_time = 0.0
	_mover_stopped = false
	_mover_stop_left = 0.0
	_mover_length = length
	head_averted = _mover_style == 1


## How fast a mover goes now (share of its speed), `progress` 0..1 across.
func _mover_pace(delta: float, progress: float) -> float:
	_mover_time += delta
	if _mover_style == 0:
		if not _mover_stopped and progress >= 0.5:
			_mover_stopped = true
			_mover_stop_left = MOVER_STOP_TIME
		if _mover_stop_left > 0.0:
			_mover_stop_left -= delta
			_velocity = Vector3.ZERO
			return 0.0 # (stopped dead, looking at you)
		return MOVER_SLOW if _mover_stopped else 1.0
	# Slow and wrong: in snatches, a catch between each.
	var pulse := maxf(sin(_mover_time * 6.0), 0.0)
	return MOVER_CRAWL * pulse * pulse * 2.4


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
		if _stunt == Stunt.WATCH:
			_stares += 1 # (stared it down)
		if (_stunt == Stunt.BEHIND and _stunt_phase == 0) or _stunt == Stunt.WATCH:
			_stunt_phase = 1
			_state_left = SPOTTED_FREEZE # (a beat looking back at you, then off)


## The stunt's over: out of sight again, and back to stalking.
func _end_stunt() -> void:
	_airborne = false
	_silence_off_in = SILENCE_AFTER # (the world's sounds come back)
	_no_grab_left = AFTER_STUNT_GRACE
	upright = false
	head_averted = false
	if holding or reaching:
		let_go()
	_corpse = null
	# A small thing taken whole (no ragdoll): eaten, gone.
	if _stunt == Stunt.SNATCH and is_instance_valid(_victim_thing) and _victim_thing.get_node_or_null(^"EnemyRagdoll") == null \
			and _victim_thing.has_meta(&"culled"):
		_victim_thing.queue_free()
	_victim_thing = null
	if _stunt == Stunt.WINDOW:
		Network.send_stalker_sign(0, &"window_off", _window_at)
		_window_at = Vector3.INF
	if _stunt == Stunt.LEAP or _stunt == Stunt.ANGEL or _stunt == Stunt.KNOCK:
		if _seen():
			_start_hide(true) # (in sight: it scrambles off -- never just gone, the user's)
		else:
			_turn_up() # (gone: far off on another tower, from where it stood, off into the fog)
		return
	if _stunt == Stunt.PACER and not _seen():
		_turn_up() # (lost in the murk)
		return
	if _stunt in [Stunt.SNATCH, Stunt.FALLEN] and not _seen():
		_turn_up() # (off into the dark with it)
		return
	if _stunt in [Stunt.PATH, Stunt.CROSS, Stunt.GRAPPLE, Stunt.PACER, Stunt.FIGHT_WATCH, Stunt.AMONG, Stunt.SNATCH, Stunt.FALLEN]:
		_start_hide(true) # (seen: it scrambles off, flat out -- never just gone)
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


## Out on open land: a spot beside `point` along `way`, far enough out that
## it's past the edge of everyone's view (or lost in the fog) -- or INF.
func _out_of_view_beside(point: Vector3, way: Vector3) -> Vector3:
	for k: float in [8.0, 12.0, 18.0, 26.0, 34.0, 44.0]:
		var hit := _ground_at(point + way * k + Vector3.UP * 4.0)
		if hit.is_empty():
			continue
		if not _visible_from_any(_body_points(hit.position, Basis.IDENTITY)):
			return hit.position
	return Vector3.INF


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
	if hunger < 1.0 and _fire_near(at, FIRE_AVOID):
		return false # (never by a fire: it hates it -- unless it's starving)
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
	var steer := _desired
	if state in [State.STALK, State.HUNT, State.HIDE, State.WAIT, State.EAT]:
		steer += _avoid_push(global_position)
	var wanted := steer - up * steer.dot(up)
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
	# Stretched (the wendigo), then measured standing: how high its spine's
	# middle stands over its feet (upright, _update_spine).
	_stretch_body()
	_model.basis = Basis.from_scale(Vector3.ONE * fit)
	_model.position = Vector3.ZERO
	var stand_middle := (_bone_posed_in_visual(_bones.Hips) + _bone_posed_in_visual(_bones.Neck)) * 0.5
	var sole := minf(_bone_posed_in_visual(_bones.LeftFoot).y, _bone_posed_in_visual(_bones.RightFoot).y) - 0.06 * SIZE
	_stand_mid = stand_middle.y - sole
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
				stepping = false, t = 0.0, from = Vector3.ZERO, to = Vector3.ZERO, length = _limb_length(upper, lower, end)})
		if spec[0] == "RightArm":
			_grip_limb = _limbs.size() - 1
	_frostbite_skin()
	_build_antlers()
	_build_eyes()


## Its joints moved apart (each bone's offset from its parent, longer): the
## arms, hands' fingers and legs stretched; the waist squeezed thin (the
## chest set back to its own width).
func _stretch_body() -> void:
	for pair: Array in [["LeftForeArm", ARM_STRETCH], ["LeftHand", ARM_STRETCH], ["RightForeArm", ARM_STRETCH],
			["RightHand", ARM_STRETCH], ["LeftLeg", LEG_STRETCH], ["LeftFoot", LEG_STRETCH],
			["RightLeg", LEG_STRETCH], ["RightFoot", LEG_STRETCH]]:
		_lengthen(_bones.get(pair[0], -1), pair[1])
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if "Hand" in bone_name and ("Thumb" in bone_name or "Index" in bone_name or "Middle" in bone_name \
				or "Ring" in bone_name or "Pinky" in bone_name):
			_lengthen(i, FINGER_STRETCH)
	var spine := _find_bone("Spine")
	var chest := _find_bone("Spine2")
	if spine >= 0 and chest >= 0:
		_skeleton.set_bone_pose_scale(spine, Vector3(WAIST_THIN, 1.0, WAIST_THIN))
		_skeleton.set_bone_pose_scale(chest, Vector3(1.0 / WAIST_THIN, 1.0, 1.0 / WAIST_THIN))


func _lengthen(bone: int, by: float) -> void:
	if bone >= 0:
		_skeleton.set_bone_pose_position(bone, _skeleton.get_bone_rest(bone).origin * by)


## Its skin: grey-blue and dead, a little glossy; frostbite darkening the
## hands and feet (and a little up the forearms and shins) -- each vertex
## shaded by how much those bones carry it.
func _frostbite_skin() -> void:
	var darkness := {}
	for key: String in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var bone: int = _bones.get(key, -1)
		if bone < 0:
			continue
		darkness[bone] = 1.0
		for i in _skeleton.get_bone_count():
			var parent := _skeleton.get_bone_parent(i)
			while parent >= 0:
				if parent == bone:
					darkness[i] = 1.0
					break
				parent = _skeleton.get_bone_parent(parent)
	for key: String in ["LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg"]:
		if _bones.get(key, -1) >= 0:
			darkness[_bones[key]] = 0.35
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var shown := node as MeshInstance3D
		var mesh := shown.mesh as ArrayMesh
		if mesh == null:
			continue
		var skin := shown.skin
		var made := ArrayMesh.new()
		# (Its shape keys first: an ArrayMesh takes them only before surfaces.)
		made.blend_shape_mode = mesh.blend_shape_mode
		for i in mesh.get_blend_shape_count():
			made.add_blend_shape(mesh.get_blend_shape_name(i))
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors := PackedColorArray()
			colors.resize(vertices.size())
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var per := bones.size() / maxi(vertices.size(), 1)
			if weights.size() != bones.size():
				per = 0 # (no weights to go by: left as it is)
			for v in vertices.size():
				var dark := 0.0
				for k in per:
					var bind := bones[v * per + k]
					var bone := bind
					if skin and bind < skin.get_bind_count():
						bone = skin.get_bind_bone(bind)
						if bone < 0:
							bone = _skeleton.find_bone(skin.get_bind_name(bind))
					dark += float(darkness.get(bone, 0.0)) * weights[v * per + k]
				colors[v] = Color.WHITE.lerp(FROSTBITE, clampf(dark, 0.0, 1.0))
			arrays[Mesh.ARRAY_COLOR] = colors
			var shapes: Array = mesh.surface_get_blend_shape_arrays(surface) if mesh.get_blend_shape_count() > 0 else []
			made.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays, shapes, {},
					mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			var original := shown.get_active_material(surface) as BaseMaterial3D
			var look := (original.duplicate() as StandardMaterial3D) if original is StandardMaterial3D else StandardMaterial3D.new()
			look.albedo_color = SKIN_TINT
			look.vertex_color_use_as_albedo = true
			look.roughness = SKIN_ROUGHNESS
			look.metallic_specular = 0.7
			made.surface_set_material(surface, look)
		shown.mesh = made
		for surface in made.get_surface_count():
			shown.set_surface_override_material(surface, null)


## Small broken antlers out of the top of its skull (the user's): short
## stubby beams, one with a tine, the other snapped off half-grown -- bone,
## on its head (they follow every snap and tilt of it).
func _build_antlers() -> void:
	var head: int = _bones.get("Head", -1)
	if head < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = _skeleton.get_bone_name(head)
	_skeleton.add_child(attach)
	var antlers := MeshInstance3D.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := STANDING_HEIGHT / 1.8 # (a person's head, scaled up to its)
	for side: float in [-1.0, 1.0]:
		var base := Vector3(side * 0.055, 0.15, 0.015) * k
		var out := Vector3(side * 0.6, 1.0, -0.35).normalized()
		var broken := side < 0.0 # (its left one snapped half-grown)
		var length := (0.09 if broken else 0.17) * k
		var beam := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 6:
			var u := i / 5.0
			var bend := Vector3(side * 0.25, -0.15, -0.3) * u * u
			beam.append(base + (out + bend).normalized() * length * u)
			radii.append(lerpf(0.024, 0.016 if broken else 0.007, u) * k)
		_antler_tube(tool, beam, radii, not broken)
		if not broken:
			# One short tine forward off it.
			var from := beam[2]
			var tine := PackedVector3Array([from, from + Vector3(side * 0.1, 0.5, 0.6).normalized() * 0.05 * k])
			_antler_tube(tool, tine, PackedFloat32Array([0.011 * k, 0.004 * k]), true)
	tool.generate_normals()
	antlers.mesh = tool.commit()
	var bone_look := StandardMaterial3D.new()
	bone_look.albedo_color = ANTLER_COLOR
	bone_look.roughness = 0.85
	bone_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	antlers.material_override = bone_look
	attach.add_child(antlers)
	# (Its size in metres: undo the model's own scale above the bone.)
	antlers.scale = Vector3.ONE / maxf(_skeleton.global_transform.basis.get_scale().x, 0.0001)


## A tube along `points` (`radii`), 5 sides; `point_end`: closed in a point
## (a snapped one stays open-ended, ragged).
static func _antler_tube(tool: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, point_end: bool) -> void:
	var sides := 5
	var rings: Array[PackedVector3Array] = []
	for i in points.size():
		var forward := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := forward.cross(Vector3.FORWARD if absf(forward.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(forward)
		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides + (0.4 if i == points.size() - 1 and not point_end else 0.0)
			var jag := 1.0 + (0.35 * sin(a * 3.0) if i == points.size() - 1 and not point_end else 0.0)
			ring.append(points[i] + (side * cos(a) + up * sin(a)) * radii[i] * jag)
		rings.append(ring)
	for i in points.size() - 1:
		for s in sides:
			var n := (s + 1) % sides
			for corner: Vector3 in [rings[i][s], rings[i + 1][s], rings[i + 1][n], rings[i][s], rings[i + 1][n], rings[i][n]]:
				tool.add_vertex(corner)
	if point_end:
		var last := rings[rings.size() - 1]
		var tip := points[points.size() - 1] + (points[points.size() - 1] - points[points.size() - 2]).normalized() * radii[radii.size() - 1] * 2.0
		for s in sides:
			for corner: Vector3 in [last[s], tip, last[(s + 1) % sides]]:
				tool.add_vertex(corner)


func _find_bone(key: String) -> int:
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if bone_name == key or bone_name.ends_with(":" + key) or bone_name.ends_with("_" + key):
			return i
	return -1


## A bone where it's posed now, in the Visual's space.
func _bone_posed_in_visual(bone: int) -> Vector3:
	if bone < 0:
		return Vector3.ZERO
	var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	return _visual.global_transform.affine_inverse() * world


## An arm's or leg's reach as posed (stretched), in metres.
func _limb_length(upper: int, lower: int, end: int) -> float:
	var a := _skeleton.get_bone_global_pose(upper).origin
	var b := _skeleton.get_bone_global_pose(lower).origin
	var c := _skeleton.get_bone_global_pose(end).origin
	return (a.distance_to(b) + b.distance_to(c)) * _skeleton.global_transform.basis.get_scale().x


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
		if _breath:
			_breath.queue_free()
			_breath = null
			_breath_level = 0.0
		return
	var moved := (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if moved.length() < 60.0:
		_smooth_velocity = _smooth_velocity.lerp(moved, 1.0 - exp(-15.0 * delta))
	var camera := get_viewport().get_camera_3d()
	_update_skitter(camera)
	_update_breath(camera, delta)
	if camera and camera.global_position.distance_to(global_position) > 90.0:
		_update_eyes() # (seen from any way off)
		return # too far to make out its limbs
	_upright_blend = move_toward(_upright_blend, 1.0 if upright else 0.0, delta * RISE_SPEED)
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
		_skitter.bus = StalkerSigns.bus()
		_visual.add_child(_skitter)
		_skitter.play(randf())
	var level := clampf(_smooth_velocity.length() / CRAWL, 0.0, 1.0)
	_skitter.volume_db = SpiderSound.SKITTER_DB + 2.0 + (4.0 if state == State.HUNT else 0.0) + linear_to_db(maxf(level, 0.0005))
	_skitter.stream_paused = level < 0.05


## Its breathing on your screen's camera: close and unseen, fading in; in
## sight, or off away, fading out.
func _update_breath(camera: Camera3D, delta: float) -> void:
	var want := 0.0
	if camera:
		var at := global_position + global_basis.y * BODY_HEIGHT
		var distance := camera.global_position.distance_to(at)
		if distance < BREATH_RANGE:
			var in_view := camera.is_position_in_frustum(at) and _ray(camera.global_position, at).is_empty()
			if not in_view:
				want = 1.0 - smoothstep(BREATH_RANGE * 0.5, BREATH_RANGE, distance) * 0.7
	_breath_level = move_toward(_breath_level, want, delta * 0.6)
	if _breath_level <= 0.001:
		if _breath:
			_breath.queue_free()
			_breath = null
		return
	if _breath == null:
		_breath = AudioStreamPlayer3D.new()
		_breath.stream = StalkerSound.breathing()
		_breath.bus = StalkerSigns.bus()
		_breath.unit_size = 3.0
		_breath.max_distance = BREATH_RANGE * 1.3
		_breath.attenuation_filter_cutoff_hz = 20500.0
		_breath.finished.connect(func() -> void: # (a user's clip that doesn't loop: again)
			if is_instance_valid(_breath):
				_breath.play())
		_visual.add_child(_breath)
		_breath.position = Vector3.UP * BODY_HEIGHT
		_breath.play(randf() * 2.0)
	_breath.volume_db = BREATH_DB + linear_to_db(maxf(_breath_level, 0.0005))


## The host: its arm reaching for `body` (its head) -- every game.
func reach_for(body: Node3D) -> void:
	reaching = true
	Network.send_stalker_sign(0, &"reach", _head_of(body))


## The host: `body` in its hand now, by the head -- every game.
func hold(body: Node3D) -> void:
	reaching = false
	holding = true
	Network.send_stalker_sign(0, &"hold", _head_of(body))


## The host: lets go of what it holds (or stops reaching) -- every game.
func let_go() -> void:
	holding = false
	reaching = false
	Network.send_stalker_sign(0, &"let_go")


## A hold sign here (StalkerSigns): the body nearest `at` -- a body or a live
## thing -- reached for, held, or let go of.
func sign_hold(kind: StringName, at: Vector3) -> void:
	match kind:
		&"let_go":
			_sign_pending.clear()
			_release_held()
			_reach = null
		_:
			var body := _body_near(at)
			if body == null:
				_sign_pending = {kind = kind, at = at, left = 1.5} # (its puppet's not here yet)
				return
			_sign_pending.clear()
			if kind == &"reach":
				_reach = body
				_reach_t = 0.0
			else:
				_reach = null
				_held = body
				if body.get_node_or_null(^"EnemyRagdoll") == null:
					_carry_whole(body)


## The body (a corpse or a live thing) nearest `at`, within reach of it.
func _body_near(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := 4.0
	for group: StringName in [&"corpses", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null:
				continue
			var distance := _head_of(body).distance_to(at)
			if distance < best_distance:
				best_distance = distance
				best = body
	return best


## Where a body's head is: its ragdoll's head, its skeleton's, or above it.
func _head_of(body: Node3D) -> Vector3:
	if not is_instance_valid(body):
		return global_position
	var ragdoll := body.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
	if ragdoll:
		var head := ragdoll.bone_named("Head")
		if head and head.is_inside_tree() and (body.get_node_or_null(^"Health") as Health) and (body.get_node(^"Health") as Health).is_dead:
			return head.global_position
	for node in body.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).ends_with("Head"):
				return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
	return body.global_position + Vector3.UP * 0.8


## Its gripping hand, where it is now.
func _hand_point() -> Vector3:
	if _grip_limb < 0 or _skeleton == null:
		return global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_limbs[_grip_limb].end).origin


## Every game, each tick: the held body's head pulled to the hand (the rest
## of the ragdoll dragging after it), or a small thing carried in it whole;
## a body named before its puppet came looked for again.
func _hold_tick(delta: float) -> void:
	if not _sign_pending.is_empty():
		_sign_pending.left = float(_sign_pending.left) - delta
		if float(_sign_pending.left) <= 0.0:
			_sign_pending.clear()
		else:
			var pending: Dictionary = _sign_pending.duplicate()
			sign_hold(pending.kind, pending.at)
	if not is_instance_valid(_held):
		_held = null
		return
	var hand := _hand_point()
	var ragdoll := _held.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
	if ragdoll:
		var head := ragdoll.bone_named("Head")
		if head == null:
			head = ragdoll.bone_named("Neck")
		if head == null:
			return # (not a ragdoll yet: next tick)
		var pull := ((hand - head.global_position) * HOLD_PULL - head.linear_velocity) * ragdoll.total_mass() * delta * 0.6
		ragdoll.carry({head: pull}, 0.75)
	else:
		_held.global_position = hand + Vector3.DOWN * 0.2


## A small thing carried whole (no ragdoll: a rat, a roach): out of the
## physics, still, its own self switched off -- in the hand from now on.
func _carry_whole(body: Node3D) -> void:
	body.set_meta(&"culled", true) # (taken: no drops)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = true
	if body is CollisionObject3D:
		(body as CollisionObject3D).collision_layer = 0
		(body as CollisionObject3D).collision_mask = 0


## Lets go of the held body: a ragdoll falls free (full weight again).
func _release_held() -> void:
	if is_instance_valid(_held):
		var ragdoll := _held.get_node_or_null(^"EnemyRagdoll") as EnemyRagdoll
		if ragdoll:
			ragdoll.carry({})
	_held = null


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
	var standing := _upright_blend > 0.5
	for index in _limbs.size():
		var limb := _limbs[index]
		if index == _grip_limb and (is_instance_valid(_held) or is_instance_valid(_reach)):
			# Its gripping hand: reaching out for it, or holding it by its hip.
			var target: Vector3
			if is_instance_valid(_held):
				target = xf * Vector3(GRIP.x * float(limb.out), GRIP.y, GRIP.z) * SIZE if not standing \
						else _skeleton.global_transform * _skeleton.get_bone_global_pose(limb.upper).origin + Vector3.DOWN * float(limb.length) * 0.9
			else:
				_reach_t += delta
				target = (limb.planted as Vector3).lerp(_head_of(_reach), smoothstep(0.0, 1.0, _reach_t / REACH_TIME))
			limb.stepping = false
			limb.foot = target
			continue
		if standing and limb.arm:
			# Standing: its long arms hanging at its sides, nearly to its knees.
			var shoulder := _skeleton.global_transform * _skeleton.get_bone_global_pose(limb.upper).origin
			limb.stepping = false
			limb.foot = shoulder + Vector3.DOWN * float(limb.length) * 0.97 + xf.basis.x.normalized() * float(limb.out) * 0.1 * SIZE
			limb.planted = limb.foot
			continue
		var home: Vector3 = limb.home
		if standing:
			home = Vector3(home.x * 0.55, 0.0, 0.0) # (feet under it)
		var want: Vector3 = xf * home + lead
		if limb.stepping:
			limb.t += delta / (STEP_TIME * (1.9 if wounded and not limb.arm and float(limb.out) > 0.0 else 1.0))
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
	var crawl_basis := Basis.from_euler(Vector3(_body_pitch, 0.0, -_body_roll))
	var crawl_at := Vector3(0.0, _body_y + sin(_time * 1.7) * 0.015, 0.0)
	# Upright: stood up on its hind legs, the spine straight up, swaying a little.
	var stand_basis := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.FORWARD, sin(_time * 0.6) * 0.03)
	var stand_at := Vector3(0.0, _stand_mid, -BODY_HEIGHT)
	var b := smoothstep(0.0, 1.0, _upright_blend)
	_pivot.basis = Basis(crawl_basis.get_rotation_quaternion().slerp(stand_basis.get_rotation_quaternion(), b))
	_pivot.position = crawl_at.lerp(stand_at, b)


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
	if _upright_blend > 0.5:
		pole = fwd_sk * (-1.0 if limb.arm else 1.0) + side_sk * 0.3 # (standing: knees forward, elbows back)
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
	if upright:
		_tilt_target = signf(_tilt_target if _tilt_target != 0.0 else 1.0) * PI * 0.5 # (standing: the head over at 90 degrees)
	_tilt = move_toward(_tilt, _tilt_target, delta * 12.0) # a snap, not a turn
	_skeleton.set_bone_pose_rotation(head, _skeleton.get_bone_rest(head).basis.get_rotation_quaternion())
	var to_skeleton := _skeleton.global_transform.affine_inverse()
	var pose := _skeleton.get_bone_global_pose(head)
	var face := pose.basis.z.normalized()
	var look_at := camera.global_position
	if head_averted:
		look_at = _visual.global_transform * Vector3(0.0, BODY_HEIGHT, -6.0) # (never at you: where it's going)
	var wants := ((to_skeleton * look_at) - pose.origin).normalized()
	var angle := face.angle_to(wants)
	if angle > 0.001:
		var axis := face.cross(wants).normalized()
		var turn := Basis(axis, minf(angle, deg_to_rad(80.0)))
		var turned := Basis(_head_wobble) * Basis(wants, _tilt) * turn * pose.basis
		var parent := _skeleton.get_bone_parent(head)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_rotation(head, (parent_basis.inverse() * turned).get_rotation_quaternion())
