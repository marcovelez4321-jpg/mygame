class_name StalkerVoices
extends Resource

## Every sound the Stalker makes, one slot per thing it does or decides (the
## user's, 2026-10-18: their screeches, "help me", "follow me" -- to mess
## with you). Each slot is a SoundEvent: drag clips into its `clips` in the
## Inspector, or just drop files named <slot>_<number> (hurt_01.wav,
## lure_02.ogg ...) into audio/sfx/stalker -- each play picks one at random.
## An empty slot stays silent (bar the few with the old made-up sounds to
## fall back on: the croak, the shriek, the help scream).
## Kept sparse (Stalker.VOICE_GAP and each slot's own pacing): it never
## spams.

@export_group("Hurt")
## Shot (now and then, not every bullet).
@export var hurt: SoundEvent
## Hurt too much: it flees.
@export var driven_off: SoundEvent
## Gone (it leaves for a while after fleeing).
@export var leaves: SoundEvent

@export_group("Attacking")
## Lunging for you.
@export var lunge: SoundEvent
## It's got you.
@export var grab: SoundEvent
## While it drags you (every few seconds).
@export var dragging: SoundEvent
## You broke free (it throws you).
@export var thrown_off: SoundEvent
## Done dragging: it drops you, hurt, and runs.
@export var dropped: SoundEvent

@export_group("Stalking and hunting")
## Starts stalking you (sometimes).
@export var starts_stalking: SoundEvent
## Picks up your trail.
@export var starts_hunting: SoundEvent
## Running your trail (now and then).
@export var hunting: SoundEvent
## Starts flanking round behind you (full fear).
@export var flanking: SoundEvent
## Turns up again (back from away, back on your trail).
@export var turns_up: SoundEvent
## The fear meter's just filled.
@export var fear_full: SoundEvent

@export_group("Seen and hiding")
## You've seen it.
@export var spotted: SoundEvent
## It bolts for cover.
@export var runs_away: SoundEvent
## Settled in hiding (sometimes).
@export var hiding: SoundEvent

@export_group("Stunts")
## The croak right behind you, nothing there.
@export var croak_behind: SoundEvent
## The far-off scream for help.
@export var help_scream: SoundEvent
## "Help me" / "follow me": out of sight nearby, right behind you, or far off.
@export var lure: SoundEvent
## Standing right behind you when you turn round.
@export var behind_you: SoundEvent
## Watching from the dark, off to the side.
@export var watching: SoundEvent
## Scuttling across the ceiling at the edge of your view.
@export var ceiling_scuttle: SoundEvent
## Skittering across your way ahead.
@export var doorway_dash: SoundEvent
## Dragging a body across your way.
@export var corpse_drag: SoundEvent
## Leaping between towers, far off.
@export var leap: SoundEvent


## The slot called `slot` (null if there's none).
func event(slot: StringName) -> SoundEvent:
	return get(slot) as SoundEvent