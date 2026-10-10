shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

// Grass cards lit like the ground under them (normal forced up) with gentle wind.
uniform sampler2D blades : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.42, 0.48, 0.3, 1.0);
uniform vec4 tip_tint : source_color = vec4(0.6, 0.6, 0.4, 1.0);
uniform float wind = 0.06;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.55, 0.0, 1.0);
	float sway = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) + 0.5 * sin(TIME * 2.9 + wp.z * 0.6);
	VERTEX.x += sway * wind * h * h;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec4 t = texture(blades, UV);
	float h = 1.0 - UV.y;
	ALBEDO = mix(tint.rgb, tip_tint.rgb, h) * COLOR.rgb * (0.55 + 0.6 * t.g);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25, 0.28, 0.12) * h;
}
