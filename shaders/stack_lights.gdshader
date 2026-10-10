// A megastructure's lights (StackBuilder): lit windows and red warning
// blinkers, as MultiMesh instances. Pure light (unshaded), seen through the
// murk like the skyline (its own fog, thinning with height), so a window a
// kilometre up glows through fog that hides the ground.
//   INSTANCE_CUSTOM.r = phase (each its own beat), .g = 1 for a blinker
//   (on and off, slowly), 0 for a steady window, .b = flicker (0..1).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

global uniform vec4 world_fog_color;

uniform float blink_speed = 0.5;
uniform float brightness = 2.5;
uniform float fog_floor = 0.0;
uniform float thin_height = 700.0;
uniform float near_reach = 300.0;
uniform float far_reach = 14000.0;

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
	float reach = mix(near_reach, far_reach, up * up);
	float fog = clamp(length(v_world - CAMERA_POSITION_WORLD) / reach, 0.0, 1.0);
	ALBEDO = mix(light, world_fog_color.rgb, fog * fog);
}
