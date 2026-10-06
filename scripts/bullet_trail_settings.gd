class_name BulletTrailSettings
extends Resource

## How a bullet looks in flight: a small bright slug dragging a streak, for
## every gun -- the player's (ShotTracer) and the gunner's (EnemyWeapon).
## Edit fx/bullet_trail.tres in the Inspector -- no code. Read once per run,
## like the blood trail settings, so changes show on the next play.

## Off = no visible bullets at all.
@export var enabled: bool = true
## How fast the visible bullet flies, in m/s. Cosmetic only: damage is still
## instant (hitscan), so keep it fast or the bullet visibly arrives after the
## hit already counted.
@export var speed: float = 150.0
## Seconds of path the streak drags behind the bullet. Streak length = speed
## times this, so 0.02 at 150 m/s is a 3 m streak.
@export_range(0.005, 0.5, 0.005) var trail_lifetime: float = 0.02
## Thickness of the streak in meters.
@export var radius: float = 0.012
## Sides around the streak. 3 = triangular and chunky (PS1 look).
@export_range(3, 16) var radial_steps: int = 3
@export var player_color: Color = Color(1.0, 0.85, 0.45)
## A different colour from yours, so incoming fire reads at a glance.
@export var enemy_color: Color = Color(1.0, 0.35, 0.2)
