shader_type spatial;
// Wet, living flesh for the worms (BurrowWorm, Deepmaw). Kept PS1-cheap:
// lit per vertex like ps1.gdshader (vertex_lighting), no extra textures.
//   - Wet: low roughness and a strong specular, plus a pale rim where the
//     body curves away from you -- the slime sheen.
//   - Veins: the darkest parts of the skin texture (its grooves and folds)
//     glow a faint blood red, pulsing in waves along the body.
render_mode vertex_lighting, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.75;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec4 vein_color : source_color = vec4(0.55, 0.05, 0.03, 1.0);
uniform float vein_strength : hint_range(0.0, 2.0) = 0.6;
// How dark (luminance) a texel has to be to count as a groove.
uniform float groove_low : hint_range(0.0, 1.0) = 0.03;
uniform float groove_high : hint_range(0.0, 1.0) = 0.16;
uniform float pulse_speed = 2.5;
uniform float pulse_scale = 10.0;

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * tint;
	ALBEDO = tex.rgb;
	ROUGHNESS = mix(0.85, 0.15, wetness);
	SPECULAR = 0.5 + wetness * 0.45;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float groove = 1.0 - smoothstep(groove_low, groove_high, lum);
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed - (UV.x + UV.y) * pulse_scale);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vein_color.rgb * groove * pulse * vein_strength + vec3(0.8, 0.72, 0.68) * rim * rim_strength * wetness;
}
