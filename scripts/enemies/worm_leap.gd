class_name WormLeap
extends RefCounted

## Aiming a burrowing worm's leap (BurrowWorm, Deepmaw): it comes up out of
## the ground a set distance away from its prey and arcs down onto where it
## guesses they'll be -- the spitter roach's lead (FlyingRoach._spit_at()),
## with the same values:
##   - the prey's ground speed is split into sideways (led by PREDICTION) and
##     toward/away from the worm (only PREDICTION_TOWARD of that -- people
##     running at it usually stop or swerve), carried forward for the time
##     until it comes down;
##   - each leap rolls its own guess (roll_guess()): a random share of that
##     lead (GUESS_MIN..GUESS_MAX) and a random step of up to GUESS_SIDEWAYS
##     across their direction of travel, so it doesn't always land the same
##     way -- changing direction still dodges it;
##   - it aims AIM_PAST beyond them along its line, so a near miss carries
##     into them instead of dropping short.

const PREDICTION := 0.8
const PREDICTION_TOWARD := 0.3
const AIM_PAST := 0.4
const GUESS_MIN := 0.4
const GUESS_MAX := 1.3
const GUESS_SIDEWAYS := 1.2


## One leap's guess: x = share of the lead, y = sideways step (meters).
static func roll_guess() -> Vector2:
	return Vector2(randf_range(GUESS_MIN, GUESS_MAX), randf_range(-GUESS_SIDEWAYS, GUESS_SIDEWAYS))


## Seconds in the air for a leap peaking `height` above the floor and coming
## down to `land_height` above it, under `gravity`.
static func air_time(height: float, gravity: float, land_height: float) -> float:
	var up := sqrt(2.0 * gravity * maxf(height, 0.1))
	var down := sqrt(maxf(up * up - 2.0 * gravity * clampf(land_height, 0.0, height), 0.0))
	return (up + down) / gravity


## Where to come down, `time` seconds from now, from `from`: the prey's
## middle plus the roach's lead and this leap's guess.
static func landing(from: Vector3, prey: Node3D, time: float, guess: Vector2) -> Vector3:
	var aim := Factions.aim_point(prey)
	var to_prey := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var line := to_prey.normalized() if to_prey.length_squared() > 0.0001 else Vector3.FORWARD
	var lead := Vector3.ZERO
	var sideways := Vector3.ZERO
	var body := prey as CharacterBody3D
	if body:
		var ground := Vector3(body.velocity.x, 0.0, body.velocity.z)
		var toward_away := line * ground.dot(line)
		lead = ((ground - toward_away) + toward_away * PREDICTION_TOWARD) * PREDICTION * guess.x
		if ground.length_squared() > 1.0:
			sideways = ground.normalized().cross(Vector3.UP) * guess.y
	return aim + line * AIM_PAST + sideways + lead * time


## Mid-air re-aim: seconds until it comes down to `land_height` above
## `ground_y`, from `from` moving at `velocity`.
static func time_left(from: Vector3, velocity: Vector3, ground_y: float, land_height: float, gravity: float) -> float:
	var drop := from.y - (ground_y + land_height)
	return maxf((velocity.y + sqrt(maxf(velocity.y * velocity.y + 2.0 * gravity * drop, 0.0))) / gravity, 0.15)


## The sideways velocity (y = 0) to steer toward mid-air: the roach's guess
## at where `prey` will be when it comes down, re-made with the time it has
## left, divided by that time.
static func steer_toward(from: Vector3, velocity: Vector3, prey: Node3D, guess: Vector2, ground_y: float, gravity: float) -> Vector3:
	var left := time_left(from, velocity, ground_y, 1.0, gravity)
	var landing_at := landing(from, prey, left, guess)
	return Vector3(landing_at.x - from.x, 0.0, landing_at.z - from.z) / left
