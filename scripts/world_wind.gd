class_name WorldWind
extends RefCounted

## The wind high up, everywhere (the user's, 2026-10-17: universal, the
## procedural Stacks' own): out in the open air from FROM metres up, building
## to SPEED by TOP, gusting to GUST -- a prevailing wind wandering slowly
## round. None indoors (a megastructure's halls and rooms: HallEcho.inside()).
## PlayerMovement pulls you along it while you're in the air.

const FROM := 4000.0
const TOP := 12000.0
const SPEED := 4.0
const GUST := 7.0


static func at(point: Vector3) -> Vector3:
	if point.y < FROM or HallEcho.inside(point):
		return Vector3.ZERO
	var high := clampf(inverse_lerp(FROM, TOP, point.y), 0.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	var gust := maxf(sin(t * 0.37) * 0.6 + sin(t * 1.13 + 1.7) * 0.4, 0.0) # 0..1, comes and goes
	var way := Vector3.RIGHT.rotated(Vector3.UP, 0.6 + sin(t * 0.05) * 0.4)
	return way * lerpf(SPEED, GUST, gust) * high