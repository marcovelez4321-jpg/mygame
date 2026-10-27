shader_type spatial;
render_mode cull_disabled;

// The red creep (RedCreep): the red weed's glossy blood-red vines (red_weed.gdshader),
// grown into ropes that braid over the floors -- alive. They squirm (more
// the freer a vertex is), and every patch joined into one network pulses
// together: a slow swell and a dark-red glow running along them.
// COLOR.r = how free a vertex is to move (0 laid on a surface, 1 a tip
// reaching through the air), COLOR.g = its shade, COLOR.b = how far along
// its rope (m, /32) for the pulse to run along.

uniform vec4 albedo : source_color = vec4(0.42, 0.02, 0.03, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.0, 0.01, 1.0);
uniform vec4 glow : source_color = vec4(0.5, 0.0, 0.02, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.28;
uniform float specular : hint_range(0.0, 1.0) = 0.7;
uniform float rim : hint_range(0.0, 1.0) = 0.25;
// The squirm: how far (m) a free vertex sways, how fast; a laid rope's own
// little crawl.
uniform float sway = 0.1;
uniform float sway_speed = 0.9;
uniform float crawl = 0.015;
// The network's pulse: its phase (shared by every patch it joins), speed,
// how much it swells (m) and glows.
uniform float pulse_phase = 0.0;
uniform float pulse_speed = 1.6;
uniform float swell = 0.012;
uniform float pulse_glow = 0.6;

varying float v_pulse;

void vertex() {
	float free = COLOR.r;
	float along = COLOR.b * 32.0;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * sway_speed;
	vec3 offset = vec3(
			sin(t + world.y * 1.7 + world.z * 0.9),
			sin(t * 0.7 + world.x * 1.1) * 0.4,
			cos(t * 0.8 + world.x * 1.3 + world.y)) * sway * free;
	offset += NORMAL * sin(t * 2.3 + along * 3.0) * crawl;
	// The pulse running along it, away from where it grew from.
	v_pulse = pow(max(sin(TIME * pulse_speed + pulse_phase - along * 0.7), 0.0), 4.0);
	offset += NORMAL * v_pulse * swell;
	VERTEX += offset;
}

void fragment() {
	ALBEDO = mix(deep.rgb, albedo.rgb, COLOR.g);
	EMISSION = glow.rgb * v_pulse * pulse_glow;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	RIM = rim;
	RIM_TINT = 0.8;
}
