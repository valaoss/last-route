shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Shared world surface: one look for every static mesh regardless of its source.
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness_base = 0.9;
uniform float metallic_base = 0.0;
uniform float grime_amount = 0.5;
uniform float streak_amount = 0.4;
uniform float cracks = 0.0;
uniform float puddles = 0.0;
uniform float moss_top = 0.0;
uniform float tex_scale = 0.23;
uniform vec4 grime_color : source_color = vec4(0.16, 0.14, 0.11, 1.0);
uniform vec4 moss_color : source_color = vec4(0.27, 0.31, 0.19, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;

// merged meshes (MeshMerger) carry each source's surface params per vertex
uniform bool vertex_params = false;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 vp_col;   // linear base colour, per-object hash
varying vec4 vp_a;     // roughness, metallic, grime, streaks
varying vec4 vp_b;     // cracks, puddles, moss_top

float tri(vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.yz * s).r * w.x
		+ texture(noise_tex, p.xz * s).r * w.y
		+ texture(noise_tex, p.xy * s).r * w.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (vertex_params) {
		vp_col = CUSTOM0;
		vp_a = CUSTOM1;
		vp_b = CUSTOM2;
	}
}

void fragment() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = vertex_params ? vp_col.a : fract(sin(dot(origin.xz + origin.yy, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 bc = vertex_params ? vp_col.rgb : base_color.rgb;
	float rough_k = vertex_params ? vp_a.x : roughness_base;
	float metal_k = vertex_params ? vp_a.y : metallic_base;
	float grime_k = vertex_params ? vp_a.z : grime_amount;
	float streak_k = vertex_params ? vp_a.w : streak_amount;
	float cracks_k = vertex_params ? vp_b.x : cracks;
	float puddles_k = vertex_params ? vp_b.y : puddles;
	float moss_k = vertex_params ? vp_b.z : moss_top;
	float n1 = tri(wpos, wnorm, tex_scale);
	float n2 = tri(wpos, wnorm, tex_scale * 4.3);
	float n3 = tri(wpos + vec3(17.0), wnorm, tex_scale * 0.31);

	vec3 col = bc * (0.94 + 0.12 * h);
	col *= mix(0.8, 1.12, n1);
	col *= mix(0.9, 1.06, n2);

	// grime pools near the ground and in broad blotches
	float low = smoothstep(1.4, 0.0, wpos.y);
	float g = clamp(grime_k * (low * 0.7 + smoothstep(0.45, 0.8, n3) * 0.6), 0.0, 1.0);
	col = mix(col, grime_color.rgb * (0.8 + 0.4 * n2), g * 0.75);

	// rain streaks on vertical faces
	float vertical = 1.0 - abs(wnorm.y);
	float streak = texture(noise_tex, vec2((wpos.x + wpos.z) * 1.7, wpos.y * 0.09)).r;
	col *= 1.0 - smoothstep(0.55, 0.85, streak) * streak_k * vertical * 0.45;

	// moss / dust settles on upward faces
	float up = smoothstep(0.6, 0.95, wnorm.y);
	col = mix(col, moss_color.rgb * (0.7 + 0.5 * n2), up * moss_k * smoothstep(0.4, 0.7, n1));

	// cracks_k: contour lines of the broad noise
	float crack = (1.0 - smoothstep(0.0, 0.006, abs(n3 - 0.5))) * smoothstep(0.45, 0.65, n2) * cracks_k * up;
	col *= 1.0 - crack * 0.65;

	float rough = clamp(rough_k + (n2 - 0.5) * 0.15, 0.05, 1.0);
	// puddles_k: dark, glossy low spots on flat ground
	float wet = smoothstep(0.3, 0.16, n3) * puddles_k * up;
	col *= 1.0 - wet * 0.3;
	rough = mix(rough, 0.3, wet);
	SPECULAR = 0.4 * (1.0 - wet * 0.4);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal_k;
}
