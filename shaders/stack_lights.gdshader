// A megastructure's lights (StackBuilder): lit windows and red warning
// blinkers, as MultiMesh instances. Pure light (unshaded), in the world's
// own fog like everything else.
//   INSTANCE_CUSTOM.r = phase (each its own beat), .g = 1 for a blinker
//   (on and off, slowly), 0 for a steady window, .b = flicker (0..1).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float blink_speed = 0.5;
uniform float brightness = 5.0;
// Through the fog only somewhat: from dim_start metres they dim, down to
// `faint` of their brightness by dim_end (the fog does the rest).
uniform float dim_start = 30.0;
uniform float dim_end = 220.0;
uniform float faint = 0.12;

varying float v_on;
varying float v_dim;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float blink = step(0.55, sin(TIME * blink_speed * 6.2831 + phase));
	float flicker = 1.0 - INSTANCE_CUSTOM.b * 0.5 * step(0.92, fract(sin(floor(TIME * 12.0) + phase * 17.0) * 43758.5));
	v_on = mix(1.0, blink, INSTANCE_CUSTOM.g) * flicker;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dim = mix(1.0, faint, smoothstep(dim_start, dim_end, length(world - CAMERA_POSITION_WORLD)));
}

void fragment() {
	ALBEDO = COLOR.rgb * brightness * v_on * v_dim;
}