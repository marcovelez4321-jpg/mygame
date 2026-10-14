class_name Fall

## How everything falls (the user's, 2026-10-14): one gravity for the player
## and every creature, and a stronger pull on the way down than on the way
## up -- asymmetric gravity, as Mario, Celeste and most games with good jumps
## do it -- so nothing floats at the top or drifts down like it's on the moon
## (the spiders and rats fell at real-world 9.8, half everyone else's).
## Jumps keep their height (the way up is unchanged); drops are quicker.

## Gravity (m/s^2) for everything that moves itself.
const GRAVITY := 20.0
## On the way down, gravity's this many times as strong.
const MULTIPLIER := 1.7


## The pull this tick for something going up or down at `vertical` m/s.
static func pull(vertical: float) -> float:
	return GRAVITY * (MULTIPLIER if vertical < 0.0 else 1.0)