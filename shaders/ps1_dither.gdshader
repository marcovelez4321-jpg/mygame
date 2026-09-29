shader_type canvas_item;

/// Full-screen ordered (Bayer) dithering -- a real PS1-era technique
/// (breaking up color banding with a fixed dot pattern instead of smooth
/// gradients), distinct from film grain/noise: the pattern is fixed per
/// pixel position, not randomized per frame, so it reads as a deliberate
/// retro dither, not screen noise or distortion.
///
/// Verified against the real Godot 4.7 docs before writing this: canvas_item
/// shaders read the already-rendered screen via a sampler2D uniform hinted
/// hint_screen_texture, sampled at SCREEN_UV.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
/// Fewer levels = chunkier, more visible dithering (more PS1-authentic);
/// more levels = subtler.
uniform float color_levels : hint_range(2.0, 32.0) = 10.0;

const mat4 BAYER = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

void fragment() {
	vec3 color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	ivec2 pixel = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = BAYER[pixel.x][pixel.y] - 0.5;
	color += threshold / color_levels;
	color = floor(color * color_levels + 0.5) / color_levels;
	COLOR = vec4(color, 1.0);
}
