shader_type spatial;
// The Flesh Tree's skin (the user's, 2026-10-28: three skins in patches that
// blend smoothly into each other): the tape worm's skin, and the Eldritch
// pack's M9 and M4, laid on along the tree's own UVs; which shows where is a
// slow noise over the world (so the patches run on across trunk, limbs and
// roots alike), each skin's share softly blended at the edges. Fleshy, not
// shiny: matte, a dark red rim where it turns away from you (as before).
render_mode cull_disabled;

// The tape worm's sheet is worm shapes, not a tile: just a piece of its body
// (worm_rect, in the sheet's 0..1), tiled mirrored so its edges never show,
// worm_aspect times as many repeats down as across (its piece is that long).
uniform sampler2D worm_skin : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 worm_rect = vec4(0.112, 0.148, 0.559, 0.212);
uniform float worm_aspect = 4.0;
uniform sampler2D veined_skin : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D raw_skin : source_color, filter_nearest_mipmap, repeat_enable;
// Metres across a patch, and how soft their edges are (low: sharp).
uniform float patch_metres = 18.0;
uniform float blend = 0.35;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, 0..1.
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float field(vec3 p) {
	return noise(p) * 0.65 + noise(p * 2.13 + 7.7) * 0.35;
}

vec2 mirrored(vec2 uv) {
	return abs(fract(uv * 0.5) * 2.0 - 1.0);
}

void fragment() {
	vec3 p = world_at / patch_metres;
	// Each skin's own field; the strongest shows, blended into the others
	// near where they're level.
	vec3 f = vec3(field(p), field(p + vec3(31.4, 17.2, 5.9)), field(p + vec3(-12.7, 44.1, 23.3)));
	vec3 w = exp((f - max(f.x, max(f.y, f.z))) / max(blend * 0.25, 0.001));
	w /= (w.x + w.y + w.z);
	vec2 worm_uv = worm_rect.xy + mirrored(UV * vec2(1.0, worm_aspect)) * worm_rect.zw;
	vec3 colour = texture(worm_skin, worm_uv).rgb * w.x
			+ texture(veined_skin, UV).rgb * w.y
			+ texture(raw_skin, UV).rgb * w.z;
	ALBEDO = colour * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
	RIM = 0.35;
	RIM_TINT = 0.9;
}
