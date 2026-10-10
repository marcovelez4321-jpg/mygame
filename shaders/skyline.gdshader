// A plain lit material for the skyline giants and megastructure shells
// (SkylineLayer, Megastructure): their texture and colour (or their vertex
// colours), lit by the sun, and the world's own fog like everything else.
//   UV2.x = glow (lights, bulbs).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, vertex_lighting;

uniform sampler2D albedo_texture : source_color, filter_nearest, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.3);
uniform float glow_strength = 4.0;

varying float v_glow;

void vertex() {
	v_glow = UV2.x;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	if (use_vertex_color) {
		base.rgb *= COLOR.rgb;
	}
	ALBEDO = base.rgb;
	ROUGHNESS = 1.0;
	EMISSION = glow_color * base.rgb * v_glow * glow_strength;
}