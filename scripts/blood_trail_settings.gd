class_name BloodTrailSettings
extends Resource

## How the streaks behind blood droplets look, for the artery spurt and the
## headshot bleed (BloodFX.spawn_artery_spurt()). Edit fx/blood_trail.tres in
## the Inspector -- no code. It's read once per run and the trail mesh is built
## once and shared by every spurt (Rule 2), so changes show on the next play.

## Off = plain droplets, no streaks.
@export var enabled: bool = true
## Seconds of path each droplet drags behind it. Streak length is this times
## the droplet's speed (4.5-8.5 m/s), so 0.06 is roughly 0.3-0.5 m.
@export_range(0.01, 1.0, 0.01) var lifetime: float = 0.06
## Thickness of a streak in meters, before each droplet's random size
## (0.3-0.65x) is applied.
@export var radius: float = 0.025
## Sides around the tube. 3 = triangular and chunky (PS1 look); higher = rounder.
@export_range(3, 16) var radial_steps: int = 3
## Segments along a streak. More = smoother when it curves under gravity, but
## more vertices per droplet.
@export_range(1, 16) var sections: int = 4
@export var color: Color = Color(0.35, 0.02, 0.02)
