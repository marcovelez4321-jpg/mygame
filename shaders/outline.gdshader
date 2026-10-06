shader_type spatial;

// The highlight outline on things you can pick up or use (InteractHighlight).
// The "inverted hull" trick used by lots of toon-style games: the mesh is
// drawn a second time, pushed out along its normals, with only its BACK
// faces showing, in one flat colour -- so all you see of it is a rim poking
// out around the real mesh's edges.

render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
// Thickness as a fraction of the distance to the camera, so the line looks
// the same width close up or far away (and on a tiny grenade or a big door).
uniform float width = 0.004;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float distance_to_camera = length(CAMERA_POSITION_WORLD - world_position);
	world_position += world_normal * width * distance_to_camera;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
