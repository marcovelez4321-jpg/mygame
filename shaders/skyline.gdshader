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
global uniform float world_fog_begin;
global uniform float world_fog_end;

uniform sampler2D albedo_texture : source_color, filter_nearest, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.3);
uniform float glow_strength = 4.0;
group_uniforms fog;
// The world's fog (its colour and distances, kept in step by BiomeAtmosphere).
// height_thinning: 0 = exactly the world's fog; up to 1 = it thins with
// height (from fog_floor over thin_height), solid only at far_reach up high.
uniform float height_thinning : hint_range(0.0, 1.0) = 0.0;
uniform float fog_floor = 0.0;
uniform float thin_height = 600.0;
uniform float far_reach = 9000.0;
uniform float fog_curve = 1.2;
// How much of its glow (lights, bulbs) shines on through the fog.
uniform float light_pierce : hint_range(0.0, 1.0) = 0.8;
// Far off, the fog never quite takes it: at most `silhouette` of the way,
// so giants kilometres off stay dim shapes in the murk. And the cloud band
// (cloud_bottom..cloud_top) it vanishes into, coming out above it.
uniform float silhouette : hint_range(0.0, 1.0) = 0.8;
uniform float cloud_bottom = 650.0;
uniform float cloud_top = 1000.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.97;
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
	// The murk (the world's fog, unless height_thinning).
	float up = clamp((v_world.y - fog_floor) / max(thin_height, 1.0), 0.0, 1.0);
	float fog_end = mix(world_fog_end, far_reach, up * up * height_thinning);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float fog = pow(clamp((dist - world_fog_begin) / max(fog_end - world_fog_begin, 1.0), 0.0, 1.0), fog_curve);
	fog = min(fog, silhouette);
	float band = smoothstep(cloud_bottom - 100.0, cloud_bottom + 60.0, v_world.y) * (1.0 - smoothstep(cloud_top - 60.0, cloud_top + 100.0, v_world.y));
	fog = max(fog, band * cloud_density * smoothstep(world_fog_begin, world_fog_end, dist));
	// Fog by hand: the lit colour fades out, the fog's own colour fades in
	// as light of its own (so it isn't shaded like the surface); its glow
	// shines on through.
	ALBEDO *= 1.0 - fog;
	EMISSION = mix(glow, world_fog_color.rgb, fog) + glow * fog * light_pierce;
}
