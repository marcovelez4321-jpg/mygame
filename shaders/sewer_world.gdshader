shader_type spatial;
// The level's walls and floors (SewerLook swaps their StandardMaterial3Ds for
// this at load). Two switchable effects, both driven by global uniforms so
// the pause menu's Graphics toggles change every surface at once:
//
//   1. Texture warping (sewer_affine, 0..1): the PS1 drew textures with
//      AFFINE mapping -- interpolated straight across the screen, no
//      perspective correction -- so they swim and bend as you move. The
//      trick: carry UV*w and w as varyings; the GPU's perspective-correct
//      interpolation of both, divided per pixel, cancels back out to plain
//      screen-space (affine) interpolation. Big flat faces warp the most,
//      which is why SewerLook splits the big primitive meshes up first --
//      the PS1 games subdivided their floors for the same reason.
//
//   2. Grime (sewer_grime, 0..1): dark green-brown filth that runs down
//      walls in vertical streaks (noise stretched tall) and blotches the
//      floors, with wet patches on anything facing up -- darker and glossy,
//      so they catch the light like standing water. World-space, so nothing
//      needs unwrapping or painting, and it tiles across every map.
//
// Per-pixel lighting (not the vertex lighting of ps1.gdshader): it keeps the
// map's lighting as it was on big brush faces.

render_mode diffuse_lambert, specular_schlick_ggx;

global uniform float sewer_affine;
global uniform float sewer_grime;
global uniform sampler2D sewer_grime_noise : filter_linear_mipmap, repeat_enable;
// The grime's look -- globals too, so the Graphics menu's sliders (SewerLook)
// change every surface live. Coverage = how much of the surface it shows up
// on (0 = none, 1 = most of it); the others how strong it is there.
global uniform vec4 sewer_grime_color;
global uniform float sewer_wall_streaks;
global uniform float sewer_wall_coverage;
global uniform float sewer_floor_blotches;
global uniform float sewer_puddles;
global uniform float sewer_puddle_coverage;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

varying vec3 affine_uvw;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	affine_uvw = vec3(UV * clip.w, clip.w);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = mix(UV, affine_uvw.xy / affine_uvw.z, sewer_affine);
	vec4 texel = has_texture ? texture(albedo_texture, uv) : vec4(1.0);
	vec3 albedo = texel.rgb * albedo_color.rgb;
	float rough = roughness;

	if (sewer_grime > 0.0) {
		vec3 n = normalize(world_normal);
		float up = clamp(n.y, 0.0, 1.0);
		float wall = 1.0 - abs(n.y);
		// Walls: noise stretched tall into streaks running down.
		vec2 wall_uv = vec2((world_pos.x + world_pos.z) * 0.35, world_pos.y * 0.04);
		float wall_start = mix(0.8, 0.35, sewer_wall_coverage);
		float streak = smoothstep(wall_start, wall_start + 0.25, texture(sewer_grime_noise, wall_uv).r);
		// Floors: broad blotches, and the wettest of them puddles.
		float spot = texture(sewer_grime_noise, world_pos.xz * 0.06).r;
		float blotch = smoothstep(0.38, 0.75, spot);
		float grime = mix(blotch * sewer_floor_blotches, streak * sewer_wall_streaks, wall) * sewer_grime;
		albedo = mix(albedo, albedo * sewer_grime_color.rgb * 2.0, grime);
		float puddle_start = mix(0.85, 0.45, sewer_puddle_coverage);
		float wet = smoothstep(puddle_start, puddle_start + 0.12, spot) * up * sewer_puddles * sewer_grime;
		albedo *= 1.0 - wet * 0.45;
		rough = mix(rough, 0.06, wet);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic;
}
