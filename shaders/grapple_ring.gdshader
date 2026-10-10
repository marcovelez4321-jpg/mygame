// The grapple's landing ring (GrappleIndicator): a thin glowing ring lying
// on the surface the grapple would grab, filling round like a dial as you
// charge it (`fill` 0..1, clockwise from the top), the rest of it faint.
// Red where it would give out with nothing to grab.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.92, 0.85, 1.0, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 0.0;
// The ring's band (0..1 of its radius) and the unfilled part's strength.
uniform float inner = 0.8;
uniform float empty_alpha = 0.25;
// A flash as it fills completely.
uniform float flash = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = smoothstep(inner - 0.04, inner, r) * (1.0 - smoothstep(0.96, 1.0, r));
	// Round from the top, clockwise.
	float around = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float filled = step(around, fill);
	// Notches every eighth, so the dial reads as one.
	float notch = 1.0 - 0.5 * step(0.985, fract(around * 8.0));
	float alpha = band * mix(empty_alpha, 1.0, filled) * notch;
	ALBEDO = color.rgb * (1.0 + flash * 2.0);
	ALPHA = clamp(alpha * color.a, 0.0, 1.0);
}
