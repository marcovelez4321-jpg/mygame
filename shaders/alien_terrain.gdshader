// The alien land's ground (docs/WORLD.md): Terrain3D's minimum shader (its
// height, LOD morph and hole handling, unchanged) with our look on top, in
// two biomes through a PS1 lens:
//   REEF: purple and blue -- indigo valleys -> violet -> periwinkle/lavender
//   ridges, steep faces darker and bluer, blotches of teal moss and magenta rust.
//   SEWER (most of the land): the insects' filth -- black sludge valleys ->
//   olive mud -> grimy tan -> nicotine-yellow ridges, steep faces wet black
//   grime, blotches of toxic slime green and rust.
//   Which one: biome_map (BiomeMap, white = reef), sampled smooth, so the
//   two blend across the border. No map = sewer everywhere.
//   PS1: screen-space vertex snapping (the wobble), faceted flat-shaded
//   triangles, colour worked out in blocks (a low-res "texture" with no
//   texture) and cut to 15-bit colour (32 shades a channel, like the PS1).
// Every look setting is a uniform: tune them on the Terrain3D material.
// Base shader: addons/terrain_3d/extras/shaders/minimum.gdshader
// (Copyright 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors, MIT).

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_lambert,specular_disabled,skip_vertex_transform;

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms (set by Terrain3D)
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1/_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1/1024
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

// --- Biomes (TerrainLook sets these from the world's BiomeMap) ---
uniform sampler2D biome_map : hint_default_black, filter_linear, repeat_disable;
// The world area the map covers: x, z, width, depth (metres).
uniform vec4 biome_area = vec4(-2048.0, -2048.0, 4096.0, 4096.0);

// --- Our look ---
group_uniforms height_gradient;
// Heights (metres) the gradient runs between, and its four colours.
uniform float low_height = 0.0;
uniform float high_height = 60.0;
uniform vec3 valley_color : source_color = vec3(0.10, 0.07, 0.28); // deep indigo
uniform vec3 low_color : source_color = vec3(0.30, 0.16, 0.50);    // violet
uniform vec3 high_color : source_color = vec3(0.45, 0.48, 0.85);   // periwinkle
uniform vec3 ridge_color : source_color = vec3(0.70, 0.62, 0.92);  // lavender
group_uniforms slope;
// Steep faces darken toward this blue, starting at slope_start (0 = flat,
// 1 = vertical) and fully by slope_end.
uniform vec3 slope_color : source_color = vec3(0.08, 0.10, 0.30);
uniform float slope_start : hint_range(0.0, 1.0) = 0.25;
uniform float slope_end : hint_range(0.0, 1.0) = 0.6;
group_uniforms blotches;
// Big slow blotches across the land: teal moss and magenta rust. Size in
// metres, and how much of the ground each covers (0..1).
uniform vec3 moss_color : source_color = vec3(0.12, 0.42, 0.50);
uniform vec3 rust_color : source_color = vec3(0.52, 0.14, 0.38);
uniform float blotch_size = 70.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.25;
// Fine speckle so close ground isn't flat colour, and its strength.
uniform float speckle_size = 2.0;
uniform float speckle_amount : hint_range(0.0, 0.5) = 0.12;
group_uniforms sewer;
// The sewer biome's own gradient, slope and blotch colours (the same
// heights, slope range and blotch sizes as the reef's).
uniform vec3 sewer_valley_color : source_color = vec3(0.06, 0.06, 0.035); // black sludge
uniform vec3 sewer_low_color : source_color = vec3(0.19, 0.18, 0.085);   // olive mud
uniform vec3 sewer_high_color : source_color = vec3(0.32, 0.28, 0.16);   // grimy tan
uniform vec3 sewer_ridge_color : source_color = vec3(0.46, 0.40, 0.24);  // nicotine yellow
uniform vec3 sewer_slope_color : source_color = vec3(0.05, 0.05, 0.03);  // wet black grime
uniform vec3 slime_color : source_color = vec3(0.22, 0.34, 0.05);        // toxic green slime
uniform vec3 sewer_rust_color : source_color = vec3(0.34, 0.15, 0.06);
uniform float slime_amount : hint_range(0.0, 1.0) = 0.3;
uniform float sewer_rust_amount : hint_range(0.0, 1.0) = 0.3;
group_uniforms yard;
// Grandma's yard: grass (the user's: TrenchBroom's Grass_01) in the flat
// circle round the middle, fading into the alien ground over yard_soft.
// TerrainLook sets the texture. grass_tile: metres one tile covers.
uniform sampler2D yard_grass : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec2 yard_center = vec2(0.0, 0.0);
uniform float yard_radius = 45.0;
uniform float yard_soft = 10.0;
uniform float grass_tile = 4.0;
uniform bool yard_grass_on = false;
group_uniforms paint;
// Terrain3D's Color brush tints the ground on top of all this (its colour
// map; white = untouched). How strongly it shows.
uniform float paint_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms ps1;
// Screen-space vertex snap (lower = more wobble, as shaders/ps1.gdshader).
uniform float snap_resolution : hint_range(16.0, 320.0) = 160.0;
// The "texel": colour's worked out in blocks this big (metres).
uniform float texel_size = 1.0;
// Shades per colour channel (31 = the PS1's 15-bit colour).
uniform float color_steps = 31.0;
// Faceted triangles (flat shading) instead of smooth ground.
uniform bool flat_terrain_normals = true;
group_uniforms;

// Varyings & Types
varying float v_vertex_xz_dist;
varying vec3 v_vertex;

////////////////////////
// Helpers
////////////////////////

ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise, 0..1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Two octaves: broad shapes with ragged edges.
float blotch_noise(vec2 p) {
	return value_noise(p) * 0.7 + value_noise(p * 2.7 + 17.0) * 0.3;
}

////////////////////////
// Vertex
////////////////////////

void vertex() {
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	vec2 shift = (scale < _vertex_spacing + 1e-6) ?
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	UV = v_vertex.xz * _vertex_density;
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >>2u & 0x1u);

	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z < 0))) {
		v_vertex.x = 0. / 0.;
	} else {
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r, texelFetch(_height_maps, uv_b, 0).r, vertex_lerp);
		v_vertex.y = h;
	}

	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);

	// PS1 wobble: snap to a coarse SCREEN grid after projection (as ps1.gdshader).
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	// Not in the sun's shadow pass (an orthographic projection; the player's
	// camera is perspective): snapped on the sun's grid, shadows came loose
	// from what cast them and smeared across big flat faces.
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		clip.xy = floor(clip.xy / clip.w * snap_resolution) / snap_resolution * clip.w;
	}
	POSITION = clip;
}

////////////////////////
// Fragment
////////////////////////

void fragment() {
	vec2 uv = UV;
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 weight = fract(uv);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y,
		weight.x * weight.y,
		weight.x * invert.y,
		invert.x * invert.y
	);

	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);
	bool bilerp = region_mip < 0.0;

	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);

	vec3 index_normal[4];
	float h[4];
	float u = 0.0;
	float v = 0.0;

	h[3] = texelFetch(_height_maps, index[3], 0).r;
	h[2] = texelFetch(_height_maps, index[2], 0).r;
	h[0] = texelFetch(_height_maps, index[0], 0).r;
	index_normal[3] = normalize(vec3(h[3] - h[2] + u, _vertex_spacing, h[3] - h[0] + v));
	vec3 w_normal = index_normal[3];

	if (bilerp) {
		h[1] = texelFetch(_height_maps, index[1], 0).r;
		float h_4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r;
		float h_5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r;
		float h_6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r;
		float h_7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r;
		index_normal[0] = normalize(vec3(h[0] - h[1] + u, _vertex_spacing, h[0] - h_7 + v));
		index_normal[1] = normalize(vec3(h[1] - h_5 + u, _vertex_spacing, h[1] - h_4 + v));
		index_normal[2] = normalize(vec3(h[2] - h_6 + u, _vertex_spacing, h[2] - h[1] + v));
		w_normal =
			index_normal[0] * weights[0] +
			index_normal[1] * weights[1] +
			index_normal[2] * weights[2] +
			index_normal[3] * weights[3] ;
	}

	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;

	if (flat_terrain_normals) {
		NORMAL = normalize(cross(dFdyCoarse(VERTEX),dFdxCoarse(VERTEX)));
		TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
		BINORMAL = normalize(cross(NORMAL, TANGENT));
	}

	// --- Colour, worked out per block (the PS1 "texel") ---
	vec2 cell = (floor(v_vertex.xz / texel_size) + 0.5) * texel_size;
	float height = clamp((v_vertex.y - low_height) / max(high_height - low_height, 0.001), 0.0, 1.0);
	// Steep faces (w_normal.y: 1 = flat, 0 = vertical), blotch noise: shared.
	float steep = smoothstep(slope_start, slope_end, 1.0 - w_normal.y);
	float moss = blotch_noise(cell / blotch_size);
	float rust = blotch_noise(cell / (blotch_size * 1.3) + 41.0);
	// Reef: height gradient, darker bluer slopes, moss and rust.
	vec3 reef = mix(valley_color, low_color, smoothstep(0.0, 0.35, height));
	reef = mix(reef, high_color, smoothstep(0.35, 0.75, height));
	reef = mix(reef, ridge_color, smoothstep(0.75, 1.0, height));
	reef = mix(reef, slope_color, steep);
	reef = mix(reef, moss_color, smoothstep(1.0 - moss_amount, 1.0 - moss_amount + 0.12, moss) * 0.85);
	reef = mix(reef, rust_color, smoothstep(1.0 - rust_amount, 1.0 - rust_amount + 0.12, rust) * 0.8);
	// Sewer: the same, in filth.
	vec3 sewer = mix(sewer_valley_color, sewer_low_color, smoothstep(0.0, 0.35, height));
	sewer = mix(sewer, sewer_high_color, smoothstep(0.35, 0.75, height));
	sewer = mix(sewer, sewer_ridge_color, smoothstep(0.75, 1.0, height));
	sewer = mix(sewer, sewer_slope_color, steep);
	sewer = mix(sewer, slime_color, smoothstep(1.0 - slime_amount, 1.0 - slime_amount + 0.12, moss) * 0.85);
	sewer = mix(sewer, sewer_rust_color, smoothstep(1.0 - sewer_rust_amount, 1.0 - sewer_rust_amount + 0.12, rust) * 0.8);
	// Which biome here (sampled per block too, so the border's blocky like the rest).
	float reefness = texture(biome_map, (cell - biome_area.xy) / biome_area.zw).r;
	vec3 color = mix(sewer, reef, reefness);
	// Grandma's yard: grass, the true texture (not by block), fading out.
	if (yard_grass_on) {
		float yard = 1.0 - smoothstep(yard_radius, yard_radius + yard_soft, distance(v_vertex.xz, yard_center));
		if (yard > 0.0) {
			color = mix(color, texture(yard_grass, v_vertex.xz / grass_tile).rgb, yard);
		}
	}
	// Hand-painted tint (Terrain3D's Color brush), blended across the four
	// corners round this point like the normals above.
	vec3 tint = texelFetch(_color_maps, index[0], 0).rgb * weights[0]
			+ texelFetch(_color_maps, index[1], 0).rgb * weights[1]
			+ texelFetch(_color_maps, index[2], 0).rgb * weights[2]
			+ texelFetch(_color_maps, index[3], 0).rgb * weights[3];
	color *= mix(vec3(1.0), tint, paint_strength);
	// Fine speckle.
	color *= 1.0 + (value_noise(cell / speckle_size) - 0.5) * 2.0 * speckle_amount;
	// 15-bit colour.
	color = floor(color * color_steps + 0.5) / color_steps;

	ALBEDO = color;
	ROUGHNESS = 1.0;
}
