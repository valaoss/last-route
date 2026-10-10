shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_burley, specular_disabled;

// Far-tree card: one camera-facing (Y-locked) quad per tree. Instance colour
// alpha picks the atlas cell (0 = fir, 1 = broadleaf); the normal leans toward
// the sky so it lights like the canopy it replaces.
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float near_dist = 80.0;   // closer trees are drawn in 3D: the card collapses to a point

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	if (distance(origin.xz, INV_VIEW_MATRIX[3].xz) < near_dist) {
		scale = vec2(0.0);
	}
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 wp = origin + right * VERTEX.x * scale.x + vec3(0.0, VERTEX.y * scale.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.8, 0.0, 0.0)).xyz + vec3(0.0, 0.0, 0.6));
	UV.x = UV.x * 0.5 + step(0.5, COLOR.a) * 0.5;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
