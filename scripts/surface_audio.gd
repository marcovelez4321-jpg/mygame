class_name SurfaceAudio
extends Resource

## How one material sounds when it hits or scrapes against things: flesh,
## skull, concrete, metal... The same idea as Valve's surface properties
## (surfaceproperties.txt in Source / GMod), including their "base"
## inheritance. One .tres per material in audio/surfaces/. See
## AUDIO_DESIGN.md section 1b.

## Anything left empty here is taken from this material instead -- e.g. limbs
## and skull fall back to plain flesh until their own sounds exist.
@export var base: SurfaceAudio

@export_group("Sounds")
@export var impact_soft: SoundEvent
@export var impact_hard: SoundEvent
@export var scrape_rough: SoundEvent
@export var scrape_smooth: SoundEvent

@export_group("Hard or soft impact")
## How hard this material is to things hitting it (concrete 1, flesh 0.2).
@export_range(0.0, 1.0, 0.05) var hardness: float = 1.0
## This material plays its SOFT impact when the thing it hits has a hardness
## below this. Flesh at 0.5: hitting concrete is hard, hitting a body is soft.
@export_range(0.0, 1.0, 0.05) var hard_threshold: float = 0.5
## Below this impact speed (m/s) it's always the soft impact, whatever it hit.
@export var hard_min_speed: float = 3.0

@export_group("Rough or smooth scrape")
## How rough this material is to things sliding on it (concrete 1, tile 0.2).
@export_range(0.0, 1.0, 0.05) var roughness: float = 1.0
## Sliding on something with roughness below this plays the SMOOTH scrape.
@export_range(0.0, 1.0, 0.05) var rough_threshold: float = 0.5


## Valve's rule (vphysics_sound.h): soft if what we hit is softer than our
## threshold, or the hit was too slow to count as hard.
func impact_sound(hit: SurfaceAudio, speed: float) -> SoundEvent:
	var soft := (hit != null and hit.hardness < hard_threshold) or speed < hard_min_speed
	return _resolve(&"impact_soft" if soft else &"impact_hard")


func scrape_sound(hit: SurfaceAudio) -> SoundEvent:
	var smooth := hit != null and hit.roughness < rough_threshold
	return _resolve(&"scrape_smooth" if smooth else &"scrape_rough")


## The named sound if it has audio, otherwise the base material's.
func _resolve(field: StringName) -> SoundEvent:
	var event := get(field) as SoundEvent
	if (event == null or not event.has_clips()) and base != null:
		return base._resolve(field)
	return event
