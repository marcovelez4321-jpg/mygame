extends MapLevel

## Extends MapLevel (rather than Node3D directly) purely to pick up its
## NavigationMesh baking for free, so enemies can pathfind in this hand-built
## test scene too -- test_map has no info_player_start group, so MapLevel's
## own player-placement logic just no-ops (see its own comment) here.
##
## Applies dev-checker materials to the ground and platform at load time.
## Kept out of the .tscn itself (rather than baking a texture resource in by
## hand) because DevChecker.make_material() needs to compute uv1_scale from
## each surface's real size -- if the ground size ever changes, the checker
## tiling stays correct automatically instead of needing to be re-tuned by
## hand in the editor.
##
## Rule 6: dev/checker textures on grey-box test surfaces are standard
## industry practice for exactly the problem we had -- a flat solid color
## gives your eye nothing to track as you move past it, so speed and depth
## become unreadable. The tiled pattern restores that "optical flow" cue.

const GROUND_SIZE := Vector2(60.0, 60.0)
const PLATFORM_SIZE := Vector2(8.0, 8.0)

# Neutral, cool grey checker for the ground -- kept deliberately unremarkable
# so the platform's warm accent color (below) is the thing that visually
# "pops," per the GDC "guide color" principle (Rule 6): reserve a strong
# color for the one surface that matters (the platform you're trying to
# reach), and keep everything else quiet so it doesn't compete for attention.
const GROUND_COLOR_A := Color(0.62, 0.62, 0.66)
const GROUND_COLOR_B := Color(0.46, 0.46, 0.5)

const PLATFORM_COLOR_A := Color(0.95, 0.55, 0.15)
const PLATFORM_COLOR_B := Color(0.75, 0.4, 0.08)

@onready var ground_mesh: MeshInstance3D = $Ground/MeshInstance3D
@onready var platform_mesh: MeshInstance3D = $Platform/MeshInstance3D


func _ready() -> void:
	super._ready()
	ground_mesh.set_surface_override_material(
		0, DevChecker.make_material(GROUND_COLOR_A, GROUND_COLOR_B, GROUND_SIZE)
	)
	platform_mesh.set_surface_override_material(
		0, DevChecker.make_material(PLATFORM_COLOR_A, PLATFORM_COLOR_B, PLATFORM_SIZE)
	)
