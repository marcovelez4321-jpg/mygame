class_name JournalSettings
extends Resource

## Where the journal's held and how it's angled (the user's: theirs to set),
## in one file: quests/journal_settings.tres. Click it in the FileSystem dock
## and change it in the Inspector; the game reads it as it starts. The
## defaults are the first version's.

## How far in front of your eye it's held (m).
@export var distance: float = 0.4
## Its size: its share of the screen's width when held 0.4 m off (nearer
## looks bigger, further smaller).
@export_range(0.1, 1.5, 0.01) var screen_share: float = 0.5
## How far below the screen's middle its middle sits (share of the screen's
## height; negative: above).
@export_range(-1.0, 1.0, 0.01) var drop: float = 0.2
## How far right of the screen's middle (share of the screen's width;
## negative: left).
@export_range(-1.0, 1.0, 0.01) var sideways: float = 0.0
## Tipped back toward you (degrees).
@export_range(-90.0, 90.0, 0.5) var tilt_degrees: float = 14.0
## Turned left/right (degrees) and leaned (degrees).
@export_range(-90.0, 90.0, 0.5) var turn_degrees: float = 0.0
@export_range(-90.0, 90.0, 0.5) var roll_degrees: float = 0.0
## Each page tipped up from the spine (degrees), like an open book.
@export_range(0.0, 45.0, 0.5) var page_angle_degrees: float = 6.0
