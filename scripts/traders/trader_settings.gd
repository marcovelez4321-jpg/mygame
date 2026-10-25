class_name TraderSettings
extends Resource

## The traders' look, in one file: traders/trader_settings.tres. Click it in
## the FileSystem dock and swap the model in the Inspector (the user's: which
## old man -- any human from art/characters/Characters_psx/Models).

## The old man's model (a character imported with the shared bone map).
@export var model: PackedScene = preload("res://art/characters/Characters_psx/Models/Male/Character_01.fbx")
## How bent he is from pulling (the user's: a heavy stoop).
@export_range(0.0, 70.0, 1.0) var stoop_degrees: float = 35.0
## His height (m), standing straight, before the stoop.
@export var height: float = 1.75
