// Speed lines (CameraJuice): faint streaks rushing out toward the screen's
// edges, more of them and brighter the faster you're going (`amount` 0..1).
// The middle stays clear so you can always see where you're headed.
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect;
	float r = length(uv);
	float turn = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float lines = 160.0;
	float id = floor(turn * lines);
	float seed = hash(id);
	// Each line its own streak, flying outward on its own beat.
	float t = fract(TIME * (0.9 + seed * 1.4) + seed * 7.0);
	float head = mix(0.3, 1.1, t);
	float len = 0.1 + 0.2 * seed;
	float streak = smoothstep(head - len, head, r) * (1.0 - smoothstep(head, head + 0.01, r));
	float thin = 1.0 - smoothstep(0.0, 0.5, abs(fract(turn * lines) - 0.5) * 2.0);
	float edge = smoothstep(0.3, 0.7, r);
	float shown = step(1.0 - amount * 0.85, seed); // more lines the faster
	COLOR = vec4(vec3(1.0), streak * thin * edge * shown * amount * 0.4);
}