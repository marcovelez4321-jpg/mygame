// The cloud deck (CloudDeck): a layer of murk high over the land that the
// megastructures and the skyline giants vanish into and rise out of
// (Rule 9: "reaching past the clouds"). A huge flat sheet kept over the
// camera, its clouds drifting: lighter and darker billows of the world's
// fog colour, thin in places so you glimpse what's above.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix;

global uniform vec4 world_fog_color;

// How big the billows are (metres), how much of the sky they cover, how
// thick they get, and which way and how fast they drift (m/s).
uniform float billow_size = 900.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.7;
uniform float thickness : hint_range(0.0, 1.0) = 0.9;
uniform vec2 drift = vec2(6.0, 2.5);
// The undersides a touch darker, the tops a touch lighter.
uniform float shade = 0.12;
// Fades out right overhead close by (so it's never a flat lid above you).
uniform float near_fade = 400.0;
// Soft where things pass through it (the user's: the towers were cut off at
// the deck): something just behind the deck shows through, and it thickens
// over soft_depth metres beyond -- so a tower fades up into the clouds
// instead of stopping at a line. And anything solid behind it still shows
// a little (see_through), however deep: the towers looming through the
// cloud, just barely, like the lit windows through the fog.
uniform float soft_depth = 500.0;
uniform float see_through : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (v_world.xz - drift * TIME) / billow_size;
	float billows = value_noise(p) * 0.55 + value_noise(p * 2.3 + 7.1) * 0.3 + value_noise(p * 5.1 - 3.7) * 0.15;
	float cloud = smoothstep(1.0 - coverage, 1.0 - coverage + 0.25, billows);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float alpha = cloud * thickness * smoothstep(near_fade * 0.5, near_fade, dist);
	// What's behind it here: open sky, or something solid -- and how far past
	// the deck that is.
	float depth = texture(depth_texture, SCREEN_UV).r;
	if (depth > 0.0000001) { // (reversed depth: 0 is the far sky)
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float behind = length(view.xyz / view.w) - length(VERTEX);
		alpha *= smoothstep(0.0, soft_depth, behind);
		alpha = min(alpha, 1.0 - see_through);
	}
	// Seen from below, darker; from above, lighter.
	float below = step(v_world.y, CAMERA_POSITION_WORLD.y) * 2.0 - 1.0;
	ALBEDO = world_fog_color.rgb * (1.0 + shade * below + (billows - 0.5) * 0.2);
	ALPHA = alpha;
}
