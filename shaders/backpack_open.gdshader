// The backpack held open (BackpackView): the pack's own texture, its top
// cut away down to clip_height (its own space) as it unzips, and its
// insides -- the faces turned away from you -- darker, so the opening reads
// as a hollow you're looking into. PS1 look: per-vertex light.
shader_type spatial;
render_mode cull_disabled, vertex_lighting;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float clip_height = 1000.0;
// How dark the inside is.
uniform float inside_shade = 0.38;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	if (local_y > clip_height) {
		discard;
	}
	vec3 color = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	ALBEDO = FRONT_FACING ? color : color * inside_shade;
	ROUGHNESS = 1.0;
}