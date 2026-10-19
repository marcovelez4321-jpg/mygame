shader_type spatial;
render_mode cull_disabled;

// The red weed (RedWeed): glossy blood-red vines, alive. Their tendrils
// writhe slowly, each bush to its own beat, and curl toward any player
// standing close. COLOR.r = how free a vertex is to move (0 rooted, 1 a
// tendril's tip), COLOR.g = its shade (darker deep in the tangle).
// INSTANCE_CUSTOM.x = each bush's own phase.

uniform vec4 albedo : source_color = vec4(0.42, 0.02, 0.03, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.0, 0.01, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.28;
uniform float specular : hint_range(0.0, 1.0) = 0.7;
uniform float rim : hint_range(0.0, 1.0) = 0.25;
// The writhe: how far (m) a tip sways, how fast.
uniform float sway = 0.12;
uniform float sway_speed = 0.8;
// Reaching for you: from how far (m), and how far (m) a tip curls toward you.
uniform float reach_range = 5.0;
uniform float curl = 0.7;
// Every player's position (RedWeed sets them each frame).
uniform vec3 players[4];
uniform int player_count = 0;

void vertex() {
	float free = COLOR.r;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float t = TIME * sway_speed;
	vec3 offset = vec3(
			sin(t + phase + world.y * 1.7 + world.z * 0.9),
			sin(t * 0.7 + phase * 1.3 + world.x * 1.1) * 0.4,
			cos(t * 0.8 + phase * 0.7 + world.x * 1.3 + world.y)) * sway * free;
	for (int i = 0; i < player_count; i++) {
		vec3 to = players[i] + vec3(0.0, 0.9, 0.0) - world;
		float d = length(to);
		float near = 1.0 - smoothstep(reach_range * 0.3, reach_range, d);
		offset += to / max(d, 0.001) * min(d * 0.5, curl) * near * free * free;
	}
	// Back into the bush's own space (it's turned and scaled evenly).
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * offset / dot(m[0], m[0]);
}

void fragment() {
	ALBEDO = mix(deep.rgb, albedo.rgb, COLOR.g);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	RIM = rim;
	RIM_TINT = 0.8;
}
