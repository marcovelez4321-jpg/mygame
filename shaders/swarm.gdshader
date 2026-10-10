// A swarm circling a megastructure's top like birds round a cliff
// (StackBuilder): hundreds of dark specks, all moved here on the GPU --
// nothing for the CPU to do. Each instance's custom data is its orbit:
//   r = radius (0..1 of swarm_radius), g = height (-1..1 of swarm_height),
//   b = speed (0..1), a = phase (0..1).
// They weave in and out and bob as they go round. Their own fog, like the
// skyline's, so the swarm shows high above the murk.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

global uniform vec4 world_fog_color;
global uniform float world_fog_begin;
global uniform float world_fog_end;

uniform float swarm_radius = 300.0;
uniform float swarm_height = 120.0;
uniform float speed = 0.06;
uniform vec3 speck_color : source_color = vec3(0.04, 0.035, 0.03);
uniform float height_thinning : hint_range(0.0, 1.0) = 0.0;
uniform float fog_floor = 0.0;
uniform float thin_height = 700.0;
uniform float far_reach = 14000.0;
// Far off, the fog never quite takes it: at most `silhouette` of the way,
// so giants kilometres off stay dim shapes in the murk. And the cloud band
// (cloud_bottom..cloud_top) it vanishes into, coming out above it.
uniform float silhouette : hint_range(0.0, 1.0) = 0.8;
uniform float cloud_bottom = 650.0;
uniform float cloud_top = 1000.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.97;

varying vec3 v_world;

void vertex() {
	float radius = mix(0.35, 1.0, INSTANCE_CUSTOM.r) * swarm_radius;
	float angle = INSTANCE_CUSTOM.a * 6.2831 + TIME * speed * mix(0.6, 1.4, INSTANCE_CUSTOM.b) * 6.2831;
	float weave = sin(TIME * 0.7 + INSTANCE_CUSTOM.a * 40.0) * 0.18 * swarm_radius;
	float bob = sin(TIME * 0.9 + INSTANCE_CUSTOM.a * 23.0) * 0.15 * swarm_height;
	vec3 orbit = vec3(cos(angle) * (radius + weave), INSTANCE_CUSTOM.g * swarm_height + bob, sin(angle) * (radius + weave));
	// Wings: the speck flutters.
	VERTEX.y *= 0.4 + 0.6 * abs(sin(TIME * 18.0 + INSTANCE_CUSTOM.a * 50.0));
	VERTEX += orbit;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = clamp((v_world.y - fog_floor) / max(thin_height, 1.0), 0.0, 1.0);
	float fog_end = mix(world_fog_end, far_reach, up * up * height_thinning);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float fog = pow(clamp((dist - world_fog_begin) / max(fog_end - world_fog_begin, 1.0), 0.0, 1.0), 1.2);
	fog = min(fog, silhouette);
	float band = smoothstep(cloud_bottom - 100.0, cloud_bottom + 60.0, v_world.y) * (1.0 - smoothstep(cloud_top - 60.0, cloud_top + 100.0, v_world.y));
	fog = max(fog, band * cloud_density * smoothstep(world_fog_begin, world_fog_end, dist));
	ALBEDO = mix(speck_color, world_fog_color.rgb, fog);
}
