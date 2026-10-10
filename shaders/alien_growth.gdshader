// The alien land's growths (GrowthMeshes, scattered by GrowthScatter): coral,
// kelp, grass, fans, sponges... through the same PS1 lens as the ground.
//   Vertex colour = the growth's colour (times the instance's tint), its
//   alpha = how much that part sways (roots still, tips swaying).
//   UV2.x = how much it glows; glow_day by day, glow_night after dark.
//   Each instance sways out of step with the next (INSTANCE_CUSTOM.r) and
//   glows a little more or less (INSTANCE_CUSTOM.g).
//   Breathing (the black vines): CUSTOM0.xyz = each vertex's outward
//   direction from its vine's middle, UV.x = the vine's thickness there; the
//   whole growth swells out along those and shrinks back, in and out.
//   PS1: screen-space vertex snap, per-vertex light, 15-bit colour. The snap
//   grid gets finer with distance: a thin branch far off is narrower than
//   one grid cell, and a coarse grid made its corners jump cell to cell as
//   you moved -- the far-off flicker. Close up it wobbles as before.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, vertex_lighting;

// How far the tips sway (metres) and how fast.
uniform float sway_amount = 0.15;
uniform float sway_speed = 0.9;
// The glow: its colour, how strong by day and by night, and how dark it is
// now (0 = day, 1 = night; GrowthScatter sets it -- the day/night cycle will).
uniform vec3 glow_color : source_color = vec3(0.45, 0.9, 1.0);
uniform float glow_day = 0.25;
uniform float glow_night = 2.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
// Breathing: how far it swells (times its own thickness; 0 = it doesn't)
// and breaths a second.
uniform float breathe_amount = 0.0;
uniform float breathe_speed = 0.35;
// PS1 look.
uniform float snap_resolution : hint_range(16.0, 320.0) = 160.0;
// Up to this far (metres) the grid's snap_resolution; further, finer in step
// with distance (twice as far = twice as fine).
uniform float snap_fine_distance = 20.0;
uniform float color_steps = 31.0;

varying float v_glow;

void vertex() {
	float sway = COLOR.a;
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * sway_speed + phase + world.x * 0.05 + world.z * 0.04;
	// Gusts: a slow swell on top of the sway.
	float gust = 0.7 + 0.3 * sin(TIME * 0.31 + world.x * 0.01);
	VERTEX.x += sin(t) * sway_amount * sway * gust;
	VERTEX.z += cos(t * 0.83) * sway_amount * 0.6 * sway * gust;
	if (breathe_amount > 0.0) {
		// In and out, slow in the lungs: a smooth swell, each growth on its own beat.
		float breath = 0.5 - 0.5 * cos((TIME * breathe_speed + INSTANCE_CUSTOM.r) * 6.2831);
		VERTEX += CUSTOM0.xyz * UV.x * breathe_amount * breath;
	}
	v_glow = UV2.x * (0.6 + INSTANCE_CUSTOM.g * 0.8);
	// PS1 wobble: snap to a screen grid after projection, finer far away.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float grid = snap_resolution * max(1.0, -view.z / snap_fine_distance);
	vec4 clip = PROJECTION_MATRIX * view;
	clip.xy = floor(clip.xy / clip.w * grid) / grid * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 color = floor(COLOR.rgb * color_steps + 0.5) / color_steps;
	ALBEDO = color;
	ROUGHNESS = 1.0;
	EMISSION = glow_color * color * v_glow * mix(glow_day, glow_night, night);
}
