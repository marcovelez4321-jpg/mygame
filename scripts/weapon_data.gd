class_name WeaponData
extends Resource

## All the numbers for one weapon, in one data file. To add a weapon, make a
## new .tres file with these fields; no new code needed.
## Rule 3: balance numbers live here, in one obvious place, so tuning a gun
## never means digging through game logic.

enum AmmoType { BULLETS, SHELLS, ROCKETS, GRENADES }

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
## Seconds after a shot before you can start reloading. 0 = press reload the
## instant after firing. The next SHOT is still limited by fire_interval
## (counted from the last shot, and it keeps counting during the reload).
@export var reload_delay_after_fire: float = 0.0
@export var reload_style: ReloadStyle = ReloadStyle.TILT

@export_group("Recoil")
## How far the viewmodel kicks back on fire (meters), and how far its muzzle
## rises (degrees). Was a fixed constant shared by every weapon; now
## per-weapon so a shotgun can kick dramatically harder than a pistol.
@export var recoil_kick_distance: float = 0.06
@export var recoil_kick_rotation_degrees: float = 4.0

@export_group("View Recoil")
## Your AIM kicks as you hold the trigger, following this per-shot pattern --
## the Counter-Strike / Valorant "spray pattern": the same every time, so it
## can be learned and pulled down against, not random kick. Each entry is one
## shot's kick in degrees: x = sideways (+ = right), y = up. Past the end, the
## last four entries repeat. Empty = no view recoil (only the gun model
## kicks, see Recoil above).
@export var recoil_pattern: Array[Vector2] = []
## Multiplies the whole pattern -- quick way to make it harder or softer.
@export var recoil_scale: float = 1.0
## A little extra random wobble per shot (degrees) on top of the pattern.
@export var recoil_jitter: float = 0.0
## Stop firing this long (seconds) and the next burst starts the pattern
## from shot 1 again -- and the aim starts drifting back down.
@export var recoil_reset_time: float = 0.3
## How fast (degrees per second) the aim drifts back down after you stop
## firing. Only the recoil you didn't pull down yourself comes back.
@export var recoil_recovery_speed: float = 12.0
## Each kick is eased in over this long (seconds) instead of snapping in one
## frame, so it reads as recoil rather than camera jitter.
@export var recoil_kick_time: float = 0.06

@export_group("Aim Down Sights")
## Hold right mouse to raise this gun to your eye. Off = right mouse does
## nothing while holding it.
@export var can_aim: bool = false
## Seconds to raise the gun to your eye (lowering takes the same).
@export var aim_time: float = 0.25
## Where the gun sits when fully raised -- same space as viewmodel_position.
## Tune in-game: F2, then I, arrows to move, F3 to save. With an Aim Sight
## Node set, this is instead a small nudge on top of the automatic line-up
## (normally 0, 0, 0).
@export var aim_position: Vector3 = Vector3(0.0, -0.1, -0.3)
## The name of the sight part in the model (the rifle's "Scope"). Set it and
## aiming lines that part up dead centre in front of your eye by itself --
## it stays lined up however the gun is moved or resized. Empty = use
## aim_position as-is.
@export var aim_sight_node: String = ""
## How much the view zooms in when fully aimed: 1 = none, 2.5 = things look
## 2.5x bigger. Mouse turning slows down to match.
@export var aim_zoom: float = 1.2
## Spread (degrees) when fully aimed. spread_degrees above becomes the
## hip-fire spread; in between it blends.
@export var aim_spread_degrees: float = 0.0
## Walking speed while aimed, as a fraction of normal.
@export var aim_move_speed_scale: float = 0.6
## A full-screen scope image -- a PNG that's see-through where you look
## through it. Set: once the gun is raised the screen blinks, the gun hides
## and this covers the view, like an old Call of Duty sniper. Empty: plain
## iron sights, the gun stays visible.
@export var scope_overlay: Texture2D
@export var aim_in_sound: SoundEvent
@export var aim_out_sound: SoundEvent

@export_group("Projectile (RPG)")
## Fires a rocket (Rocket) instead of hitscan bullets; damage, pellets and
## spread above are then unused -- the explosion settings below apply.
@export var fires_projectile: bool = false
## The node in viewmodel_scene that IS the loaded rocket. It's hidden in the
## launcher when fired, launched as the projectile, and shown again when
## the reload finishes.
@export var projectile_part: String = "Rocket"
## Stage 1, the launch charge: how fast it leaves the tube (m/s) and how much
## it dips (m/s²) before the motor lights.
@export var launch_speed: float = 18.0
@export var launch_gravity: float = 4.0
## Seconds after leaving the tube that the motor ignites (stage 2).
@export var ignite_delay: float = 0.15
## Stage 2, the motor: acceleration (m/s²) up to max_speed (m/s).
@export var thrust: float = 120.0
@export var max_speed: float = 45.0
## Slow roll as it flies, radians per second.
@export var rocket_spin: float = 6.0
## Where the backblast comes out of the rear of the launcher -- same space as
## muzzle_offset (tune with F2 then M for the muzzle; this one by hand).
@export var backblast_offset: Vector3 = Vector3.ZERO
## The explosion settings below are used by grenades too (Thrown group).
## Damage at the centre of the blast (a direct hit always takes all of it),
## falling off to 0 at explosion_radius metres.
@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 5.6
## Push at the centre, m/s -- what launches a rocket jump.
@export var explosion_knockback: float = 14.0
## What a PLAYER takes at the centre of the blast instead of explosion_damage
## (falling off the same way) -- you when rocket jumping, and in co-op your
## friends, so a stray rocket stings but never one-shots anyone.
@export var explosion_player_damage: float = 10.0

@export_group("Thrown (Grenade)")
## Throws a grenade (Grenade) instead of shooting -- one at a time, held in
## your hand. Its blast uses the explosion settings in the Projectile group.
## The model is viewmodel_scene, both in your hand and in flight.
@export var throws_grenade: bool = false
## Seconds from the click to the grenade leaving your hand: the arm winds back
## and swings through first, like Half-Life 2.
@export var throw_release_delay: float = 0.25
## How hard it's thrown, m/s, on top of your own running speed.
@export var throw_speed: float = 16.0
## The throw goes this many degrees above where you aim, so it arcs -- Half-
## Life 2 tilts its grenade throw up by about 10.
@export var throw_lift_degrees: float = 10.0
## Seconds from leaving your hand to exploding (Half-Life 2's frag: 3).
@export var fuse_time: float = 3.0
## Hides your left arm, so one hand holds and throws.
@export var hide_left_arm: bool = false
## Plays each time it flashes -- the warning beep.
@export var fuse_tick_sound: SoundEvent
## Plays when it hits something, if it's moving fast enough.
@export var bounce_sound: SoundEvent

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
