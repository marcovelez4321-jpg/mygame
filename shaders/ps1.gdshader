shader_type spatial;
// vertex_lighting: PS1 lit per-VERTEX (Gouraud shading), not per-pixel --
// flatter, more faceted look on curved surfaces, and cheaper (which is
// exactly why the real hardware did it that way). Confirmed real Godot 4
// render_mode keyword, matches the standard community PS1-shader approach.
render_mode vertex_lighting, diffuse_lambert, specular_schlick_ggx;

// No film grain, no screen-space distortion -- deliberately just these two
// PS1-authentic techniques (both real hardware limitations turned into a
// look, not a camera-lens gimmick):
//   1. Vertex snapping (below): PS1's GPU used fixed-point math, so
//      transformed vertices snapped to a coarse SCREEN-SPACE grid --
//      that's the classic wobble/jitter, worst on rotation and distant
//      geometry. Snapping in world space would look like reduced mesh
//      precision instead; this has to happen post-projection, in clip
//      space, to be the right effect.
//   2. Per-vertex lighting (render_mode above).
// Low-res pixelated rendering (the third requested effect) is a project
// display/stretch setting, not a shader -- see project.godot.

// Lower = more visible wobble/jitter. The real PS1 output at 320x240; since
// the project now renders at that same resolution before upscaling, a
// moderate grid here reads as authentic without being illegible on a modern
// display.
uniform float snap_resolution : hint_range(16.0, 320.0) = 160.0;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Snap in normalized device coordinates (after the divide-by-w), then
	// multiply back by w -- this is what makes it a genuine on-SCREEN grid
	// snap rather than a world-space one.
	clip_position.xy = floor(clip_position.xy / clip_position.w * snap_resolution) / snap_resolution * clip_position.w;
	POSITION = clip_position;
}

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	ALBEDO = tex_color.rgb * albedo_color.rgb;
	ALPHA = tex_color.a * albedo_color.a;
}
