shader_type spatial;
// Churned dirt for the burrowing worms (WormFX): the mound heaving along the
// floor over a worm tunnelling just under it, and the furrow it leaves behind.
// One subdivided plane mesh, drawn by a MultiMesh -- every copy shaped here:
//   INSTANCE_CUSTOM.x = height (meters) of this copy
//   INSTANCE_CUSTOM.y = a random seed (so no two patches lump the same)
//   INSTANCE_CUSTOM.z = churn: 1 = turning over (the moving mound), 0 = settled
//   INSTANCE_CUSTOM.w = shape: 0 = mound (a dome with a steep bow wave at the
//                       front), 1 = furrow (two loose ridges either side of a
//                       dark trough)
// The lumps come from noise in WORLD space, so as the mound moves the ground
// seems to heave up and fall back as it passes, instead of a bump sliding
// over it. The dirt texture is mapped in world space too (it stays put on the
// ground). Copies are cut to an organic, clumpy outline with alpha scissor
// (no transparency sorting); outside it the plane sinks under the floor.
// PS1 look like ps1.gdshader: per-vertex lighting and screen-space vertex
// snapping.
render_mode vertex_lighting, diffuse_lambert, cull_disabled;

uniform sampler2D dirt_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(0.85, 0.8, 0.75, 1.0);
// World meters per texture repeat.
uniform float texture_size = 1.6;
// Lump size (meters across) and how much they raise/lower the dirt (share
// of its height), and how fast the moving mound churns.
uniform float lump_size = 0.45;
uniform float lump_amount = 0.45;
uniform float churn_speed = 0.9;
uniform float snap_resolution : hint_range(16.0, 320.0) = 160.0;

varying vec3 world_pos;
varying float shade;
varying float cover;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Two octaves, -1..1.
float lumps(vec2 world_xz, float seed, float churn, float time) {
	vec2 drift = vec2(0.3, -0.5) * time * churn_speed * churn;
	vec2 p = world_xz / lump_size + vec2(seed * 17.0) + drift;
	return (noise(p) * 0.65 + noise(p * 2.3 + 5.1) * 0.35) * 2.0 - 1.0;
}

// The shape, 0..1, at plane point p (-1..1 across x, along y; -y = forward).
float dome(vec2 p) {
	// The peak sits a little forward, the front steeper than the back: a bow
	// wave of dirt being pushed ahead.
	float along = p.y + 0.2;
	along *= along < 0.0 ? 1.35 : 0.8;
	float r2 = p.x * p.x + along * along;
	return pow(clamp(1.0 - r2, 0.0, 1.0), 1.4);
}

float furrow_ridges(vec2 p) {
	float off = (abs(p.x) - 0.55) / 0.22;
	float ridge = exp(-off * off);
	float ends = 1.0 - smoothstep(0.55, 1.0, abs(p.y));
	return ridge * ends;
}

float furrow_cover(vec2 p) {
	return (1.0 - smoothstep(0.75, 0.95, abs(p.x))) * (1.0 - smoothstep(0.7, 1.0, abs(p.y)));
}

// Height (meters) at plane point `local` (the mesh's own x/z, -0.5..0.5).
float height_at(vec2 local, mat4 model, vec4 custom, float time) {
	vec2 p = local * 2.0;
	vec2 world_xz = (model * vec4(local.x, 0.0, local.y, 1.0)).xz;
	float shape = mix(dome(p), furrow_ridges(p), custom.w);
	float lump = lumps(world_xz, custom.y, custom.z, time);
	return shape * custom.x * (1.0 + lump_amount * lump);
}

void vertex() {
	vec4 custom = INSTANCE_CUSTOM;
	vec2 local = VERTEX.xz;
	vec2 p = local * 2.0;
	float h = height_at(local, MODEL_MATRIX, custom, TIME);
	// Coverage: where the dirt is at all (a clumpy edge from the lumps).
	float rim = lumps((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * 2.0, custom.y + 3.0, 0.0, 0.0) * 0.12;
	float mound_cover = dome(p) - 0.04 + rim;
	float trail_cover = furrow_cover(p) - 0.04 + rim;
	cover = mix(mound_cover, trail_cover, custom.w);
	// Outside it: under the floor, out of sight.
	VERTEX.y = cover > 0.0 ? max(h, 0.0) + 0.02 : -0.05;
	// Normals from the slope (the mesh's own space: the copy's stretch is
	// taken care of by the normal matrix).
	float e = 0.03;
	float hx = height_at(local + vec2(e, 0.0), MODEL_MATRIX, custom, TIME) - height_at(local - vec2(e, 0.0), MODEL_MATRIX, custom, TIME);
	float hz = height_at(local + vec2(0.0, e), MODEL_MATRIX, custom, TIME) - height_at(local - vec2(0.0, e), MODEL_MATRIX, custom, TIME);
	NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Darker in the dips and down the middle of a furrow (loose, damp dirt
	// turned up from below), lighter on the crests.
	float crest = clamp(h / max(custom.x, 0.001), 0.0, 1.0);
	float trough = custom.w * (1.0 - smoothstep(0.15, 0.45, abs(p.x)));
	shade = mix(0.55, 1.05, crest) * (1.0 - 0.35 * trough);

	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	clip_position.xy = floor(clip_position.xy / clip_position.w * snap_resolution) / snap_resolution * clip_position.w;
	POSITION = clip_position;
}

void fragment() {
	vec3 dirt = texture(dirt_texture, world_pos.xz / texture_size).rgb;
	ALBEDO = dirt * tint.rgb * shade;
	ROUGHNESS = 1.0;
	ALPHA = cover > 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
