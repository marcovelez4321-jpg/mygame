// A cobweb (StackBuilder's _cobweb_nodes): pale strands from a decal
// texture whose strands are faint (10-25% alpha), strengthened and cut
// cleanly (alpha scissor: no sorting, cheap), with a little glint where the
// light catches them. Completely still: no vertex work at all (the user's).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D web_texture : source_color, filter_linear_mipmap;
uniform vec3 web_color : source_color = vec3(0.86, 0.86, 0.83);
// How much the strands' alpha is strengthened, and where it's cut.
uniform float alpha_boost = 4.0;
uniform float cutoff = 0.4;

void fragment() {
	float a = texture(web_texture, UV).a * alpha_boost;
	ALBEDO = web_color;
	ROUGHNESS = 0.3;
	SPECULAR = 0.8;
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = cutoff;
}