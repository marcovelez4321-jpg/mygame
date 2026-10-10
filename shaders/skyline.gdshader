// The skyline (SkylineLayer): megastructures and growths kilometres tall and
// kilometres off, rising out of the murk. The world's fog would wipe them
// out past ~240 m, so they're drawn with fog_disabled and their own fog:
// thick at the ground and thinning with height, so their feet drown in it
// while their upper reaches loom dark against the sky. Lit by the sun like
// everything else, no snapping (they're far: it would only shimmer).
//   Colour: albedo_texture x albedo_color, times the vertex colour if
//   use_vertex_color (generated placeholders); UV2.x = glow (lights, bulbs).
//   The fog colour is the world's (global world_fog_color, set by
//   BiomeAtmosphere as it blends), so they sit in the same murk.
shader_type spatial;
render_mode fog_disabled, cull_disabled, diffuse_lambert, specular_disabled, vertex_lighting;

global uniform vec4 world_fog_color;

uniform sampler2D albedo_texture : source_color, filter_nearest, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.3);
uniform float glow_strength = 2.0;
group_uniforms fog;
// How far you can see through the murk (metres until it's solid): at
// fog_floor and below, and from fog_floor + thin_height up.
uniform float fog_floor = 0.0;
uniform float thin_height = 600.0;
uniform float near_reach = 260.0;
uniform float far_reach = 9000.0;
// Fade shape (1 = linear; more = stays clear longer then closes fast).
uniform float fog_curve = 1.4;
// The fog never quite lets go of anything this far off (0..1).
uniform float fog_minimum = 0.15;
group_uniforms;

varying vec3 v_world;
varying float v_glow;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_glow = UV2.x;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	if (use_vertex_color) {
		base.rgb *= COLOR.rgb;
	}
	ALBEDO = base.rgb;
	ROUGHNESS = 1.0;
	vec3 glow = glow_color * base.rgb * v_glow * glow_strength;
	// The murk: as thick as the world's down low, thinning with height.
	float up = clamp((v_world.y - fog_floor) / max(thin_height, 1.0), 0.0, 1.0);
	float reach = mix(near_reach, far_reach, up * up);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float fog = clamp(pow(clamp(dist / reach, 0.0, 1.0), fog_curve) + fog_minimum * smoothstep(500.0, 3000.0, dist), 0.0, 1.0);
	// Fog by hand: the lit colour fades out, the fog's own colour fades in
	// as light of its own (so it isn't shaded like the surface).
	ALBEDO *= 1.0 - fog;
	EMISSION = mix(glow, world_fog_color.rgb, fog);
}
