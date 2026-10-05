class_name WeaponData
extends Resource

## All the numbers for one weapon, in one data file. To add a weapon, make a
## new .tres file with these fields; no new code needed.
## Rule 3: balance numbers live here, in one obvious place, so tuning a gun
## never means digging through game logic.

enum AmmoType { BULLETS, SHELLS, ROCKETS }

@export var weapon_name: String = "Weapon"

@export_group("Combat")
@export var damage: float = 20.0
## Seconds between shots (0.4 = 2.5 shots per second).
@export var fire_interval: float = 0.4
@export var ammo_type: AmmoType = AmmoType.BULLETS
@export var ammo_per_shot: int = 1
## How far the shot reaches, in meters.
@export var max_range: float = 100.0
## Rays fired per shot. A pistol fires 1; a shotgun fires several. Each pellet
## does the full `damage`.
@export var pellets: int = 1
## Random spread, as a cone half-angle in degrees. 0 = perfectly accurate.
@export var spread_degrees: float = 0.0
## How hard each hit shoves what it hits (used for ragdolls and, later, props).
## Per pellet, so a close-range shotgun adds up. Low = the body just goes limp.
@export var impact_force: float = 2.0
## How many living targets a single pellet can punch THROUGH before it stops
## -- 1 means it can pass through one enemy and still go on to hit (and
## damage) a second, but no further. World geometry always stops it outright,
## regardless of this value.
@export var max_penetrations: int = 1
## Close-range damage boost: inside this distance (meters) each pellet's
## damage climbs the closer the target is -- normal at this distance, up to
## close_range_max_multiplier at point blank. 0 = off. Rule 3: this will
## apply between players too once PvP exists.
@export var close_range_distance: float = 0.0
@export var close_range_max_multiplier: float = 1.0

enum ReloadStyle {
	TILT,      ## The shared lower-out-of-view/raise-back-up animation every weapon uses by default.
	PUMP_RACK, ## One-handed pump-shotgun rack: turns upright, shakes, settles. See viewmodel.gd's _play_pump_rack_reload().
}

@export_group("Reload")
## Rounds loaded before a reload is needed. Fire is blocked once this hits 0
## until you reload -- draws from the shared ammo_type pool, same as before,
## reload just gates HOW MUCH of that pool is usable at once.
@export var magazine_size: int = 999
## Seconds a reload takes -- also how long the viewmodel reload animation
## runs (see viewmodel.gd's _on_reload_started()).
@export var reload_time: float = 1.2
@export var reload_style: ReloadStyle = ReloadStyle.TILT

@export_group("Recoil")
## How far the viewmodel kicks back on fire (meters), and how far its muzzle
## rises (degrees). Was a fixed constant shared by every weapon; now
## per-weapon so a shotgun can kick dramatically harder than a pistol.
@export var recoil_kick_distance: float = 0.06
@export var recoil_kick_rotation_degrees: float = 4.0

@export_group("Switching")
## Seconds to bring this weapon up after choosing it. You can't fire during
## it, and any cooldown left from the previous weapon carries over, so
## switching can never be used to fire faster.
@export var draw_time: float = 0.4

@export_group("Presentation")
## Shown on the weapon wheel. If empty, only the name is shown.
@export var icon: Texture2D
## The first-person model. If empty, a coloured block stands in for it.
@export var viewmodel_scene: PackedScene
## Where the gun sits relative to the camera (x = right, y = up, -z = forward).
@export var viewmodel_position: Vector3 = Vector3(0.22, -0.2, -0.45)
@export var viewmodel_rotation_degrees: Vector3 = Vector3.ZERO
@export var viewmodel_scale: float = 1.0
## Where the muzzle flash spawns, relative to the viewmodel's own pivot (same
## space as viewmodel_position). Tune per-weapon in-game: F2 to enter viewmodel
## tuning, M to switch to muzzle tuning (a green marker shows exactly where
## this is), arrows/PageUp/PageDown to move it, F3 to save.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.02, -0.35)
## Seconds the muzzle flash (light + glow quad) stays visible after a shot.
## Kept short by default so a fast-firing weapon's flashes don't overlap into
## one continuous glow; a slower-firing weapon can afford a longer, punchier
## flash since there's no next shot arriving to collide with it.
@export var muzzle_flash_time: float = 0.05
## Colour of the stand-in block used until a real model is assigned.
@export var placeholder_color: Color = Color(0.7, 0.7, 0.7)

@export_group("First-person arms")
## The pose your character's arms hold this gun in: a Mixamo animation
## (art/animations), first frame held still. Empty = no arms, just the gun.
@export var hold_animation: Animation
## Where the arms sit, in camera space (x = right, y = up, -z = forward).
## Left at zero, the arms auto-place with the right hand on the gun; fine-tune
## in-game with F2 then H (hands), and F3 to save.
@export var arms_position: Vector3 = Vector3.ZERO
@export var arms_rotation_degrees: Vector3 = Vector3.ZERO
## Multiplies the arms' size on top of the character's own eye-height scale.
@export var arms_scale: float = 1.0

@export_group("Sound")
## Played (non-positional, see sound_player.gd's play_2d) each time this
## weapon fires. One weapon, one SoundEvent -- no code needed to give a new
## weapon its own gunshot, just fill in its .tres.
@export var fire_sound: SoundEvent
@export var reload_sound: SoundEvent
## Plays when switching TO this weapon (not away from it) -- skipped for the
## very first weapon at spawn, see weapon_sound.gd's _on_weapon_switched().
@export var switch_sound: SoundEvent


## Damage multiplier for a hit `distance` meters away: 1.0 outside
## close_range_distance, rising in a straight line to
## close_range_max_multiplier at point blank.
func close_range_multiplier(distance: float) -> float:
	if close_range_distance <= 0.0 or distance >= close_range_distance:
		return 1.0
	return lerpf(close_range_max_multiplier, 1.0, distance / close_range_distance)
