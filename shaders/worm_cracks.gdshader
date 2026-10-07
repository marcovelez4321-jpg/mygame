shader_type spatial;
// Ground cracking open where a worm is about to burst out: jagged cracks
// spreading out from the middle to `grow` (0..1 of the quad's radius), with a
// dark pit in the middle and a faint hot glow pulsing in the cracks.
// Procedural (no texture), unshaded, one quad. `grow` is per instance, so
// every crack shares this one material.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform float grow : hint_range(0.0, 1.0) = 0.0;
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 crack_color : source_color = vec4(0.04, 0.025, 0.02, 1.0);
uniform vec4 glow_color : source_color = vec4(0.55, 0.14, 0.05, 1.0);
uniform float crack_count = 9.0;
uniform float crack_width = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = (atan(p.y, p.x) + PI) / TAU * crack_count;
	// Each crack wanders a little as it goes out.
	float wander = (hash(vec2(floor(a), floor(r * 7.0))) - 0.5) * 0.35 * r;
	float x = a + wander;
	float across = min(fract(x), 1.0 - fract(x)) * TAU / crack_count * r;
	float crack = 1.0 - smoothstep(0.0, crack_width * (1.2 - r), across);
	float pit = 1.0 - smoothstep(0.12, 0.3, r / max(grow, 0.001));
	float reach = 1.0 - smoothstep(grow * 0.85, grow, r);
	float mask = max(crack * reach, pit * step(0.05, grow));
	float pulse = 0.5 + 0.5 * sin(TIME * 14.0);
	ALBEDO = mix(crack_color.rgb, glow_color.rgb, crack * reach * pulse * grow * 0.7);
	ALPHA = mask * fade * smoothstep(1.0, 0.9, r);
}
