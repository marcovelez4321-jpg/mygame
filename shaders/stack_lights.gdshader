// A megastructure's lights (StackBuilder): lit windows and red warning
// blinkers, as MultiMesh instances. Pure light (unshaded), seen through the
// murk like the skyline (its own fog, thinning with height), so a window a
// kilometre up glows through fog that hides the ground.
//   INSTANCE_CUSTOM.r = phase (each its own beat), .g = 1 for a blinker
//   (on and off, slowly), 0 for a steady window, .b = flicker (0..1).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

global uniform vec4 world_fog_color;
global uniform float world_fog_begin;
global uniform float world_fog_end;

uniform float blink_speed = 0.5;
uniform float brightness = 5.0;
// The world's fog (height_thinning: see skyline.gdshader), and how much of
// each light shines on through it -- lights hanging in the murk.
uniform float height_thinning : hint_range(0.0, 1.0) = 0.0;
uniform float fog_floor = 0.0;
uniform float thin_height = 700.0;
uniform float far_reach = 14000.0;
uniform float light_pierce : hint_range(0.0, 1.0) = 0.85;
// Far off, the fog never quite takes it: at most `silhouette` of the way,
// so giants kilometres off stay dim shapes in the murk. And the cloud band
// (cloud_bottom..cloud_top) it vanishes into, coming out above it.
uniform float silhouette : hint_range(0.0, 1.0) = 0.8;
uniform float cloud_bottom = 650.0;
uniform float cloud_top = 1000.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.97;

varying vec3 v_world;
varying float v_on;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float blink = step(0.55, sin(TIME * blink_speed * 6.2831 + phase));
	float flicker = 1.0 - INSTANCE_CUSTOM.b * 0.5 * step(0.92, fract(sin(floor(TIME * 12.0) + phase * 17.0) * 43758.5));
	v_on = mix(1.0, blink, INSTANCE_CUSTOM.g) * flicker;
}

void fragment() {
	vec3 light = COLOR.rgb * brightness * v_on;
	float up = clamp((v_world.y - fog_floor) / max(thin_height, 1.0), 0.0, 1.0);
	float fog_end = mix(world_fog_end, far_reach, up * up * height_thinning);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float fog = pow(clamp((dist - world_fog_begin) / max(fog_end - world_fog_begin, 1.0), 0.0, 1.0), 1.2);
	fog = min(fog, silhouette);
	float band = smoothstep(cloud_bottom - 100.0, cloud_bottom + 60.0, v_world.y) * (1.0 - smoothstep(cloud_top - 60.0, cloud_top + 100.0, v_world.y));
	fog = max(fog, band * cloud_density * smoothstep(world_fog_begin, world_fog_end, dist));
	ALBEDO = mix(light, world_fog_color.rgb, fog) + light * fog * light_pierce;
}
