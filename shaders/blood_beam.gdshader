shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The heart's blood beam (BloodBeam): one layer of it -- the white-hot core,
// the red glow round it, or the faint haze outside that. Brightest where you
// look straight through it, soft at its edges (the Avatar State's beams), the
// blood streaming along it from the hole to what it hits.

uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 1.0;
// How fast the edges fall away (higher: a thinner-looking, harder beam).
uniform float edge_power = 2.0;
// The streaming blood: metres a second along it, the size of its clots, and
// how much of the layer it breaks up (0: smooth light).
uniform float flow_speed = 40.0;
uniform float flow_scale = 0.12;
uniform float flow_amount = 0.5;
// The beam's length in metres (the mesh's own), and 0..1 of it showing.
uniform float beam_length = 100.0;
uniform float fade = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, edge_power);
	// UV.y runs from the far end (0) to the hole (1): the blood moves toward 0.
	float along = UV.y * beam_length;
	float clots = value_noise(vec2(UV.x * 10.0, (along + TIME * flow_speed) * flow_scale));
	float streaks = value_noise(vec2(UV.x * 26.0, (along + TIME * flow_speed * 1.3) * flow_scale * 2.5));
	float flow = mix(1.0, clamp((clots * 0.7 + streaks * 0.5) * 1.5, 0.0, 1.6), flow_amount);
	float ends = smoothstep(0.0, 0.015, UV.y) * smoothstep(1.0, 0.985, UV.y);
	ALBEDO = color.rgb * intensity * flow;
	ALPHA = clamp(body * ends * fade * color.a, 0.0, 1.0);
}
