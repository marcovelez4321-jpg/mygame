class_name DevChecker
extends RefCounted

## Generates a small 2x2 checkerboard texture -- the classic "dev texture"
## every engine's default grey-box material is (industry standard, not
## specific to us). Tiled across a big flat surface via a material's
## uv1_scale, it gives your eye something to track as you move past it
## (optical flow), which is what actually lets you *feel* speed and depth --
## a flat solid color gives your eye nothing to measure motion against.
##
## Runs once per material at load time, not per-frame, so the O(4) cost here
## is irrelevant (Rule 2: this is complexity that's earning its keep, not a
## premature optimization).
static func make_texture(color_a: Color, color_b: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.set_pixel(0, 0, color_a)
	image.set_pixel(1, 0, color_b)
	image.set_pixel(0, 1, color_b)
	image.set_pixel(1, 1, color_a)
	var texture := ImageTexture.create_from_image(image)
	return texture


## Builds a ready-to-use checker material with crisp (non-blurred) tiling.
## `square_size` is the size in meters you want each checker square to read
## as -- pick something close to the player's own scale (our capsule is
## ~0.8m wide) so speed across it stays easy to judge at a glance.
static func make_material(color_a: Color, color_b: Color, surface_size: Vector2, square_size: float = 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = make_texture(color_a, color_b)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(surface_size.x / square_size, surface_size.y / square_size, 1.0)
	return material
