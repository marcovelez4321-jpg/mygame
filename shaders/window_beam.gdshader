// The light falling out of a lit apartment window (StackBuilder): a soft
// warm shaft of it in the air, brightest at the window, fading as it
// spreads out (UV.y: 0 at the window, 1 at its end). Added light, no
// surface: you see through it.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 light_color : source_color = vec3(1.0, 0.62, 0.28);
uniform float strength = 0.35;
// Added light shows through fog undimmed, so it fades by hand: full up to
// dim_start metres, down to `faint` of itself by dim_end.
uniform float dim_start = 25.0;
uniform float dim_end = 180.0;
uniform float faint = 0.08;

varying float v_dim;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dim = mix(1.0, faint, smoothstep(dim_start, dim_end, length(world - CAMERA_POSITION_WORLD)));
}

void fragment() {
	float fade = pow(1.0 - UV.y, 2.0);
	// A slow flicker, as if something moves in the room.
	float flicker = 0.9 + 0.1 * sin(TIME * 1.7);
	ALBEDO = light_color * strength * fade * flicker * v_dim;
}