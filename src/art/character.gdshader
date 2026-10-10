shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Clothing zones come from vertex colour baked in rest pose (see CharacterModel).
instance uniform vec4 skin_color : source_color = vec4(0.62, 0.5, 0.42, 1.0);
instance uniform vec4 top_color : source_color = vec4(0.25, 0.27, 0.24, 1.0);
instance uniform vec4 bottom_color : source_color = vec4(0.2, 0.22, 0.27, 1.0);
instance uniform vec4 boot_color : source_color = vec4(0.12, 0.1, 0.09, 1.0);
instance uniform float sleeves = 1.0;
instance uniform float grime = 0.3;
instance uniform float decay = 0.0;     // zombie skin / torn cloth / stains
instance uniform float hit_flash = 0.0;
instance uniform float seed = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float region = floor(COLOR.r * 4.0 + 0.5);
	vec3 rp = vec3(COLOR.b * 2.0 - 1.0, COLOR.g * 1.85, COLOR.a * 2.0 - 1.0) + vec3(seed);
	float n1 = vnoise(rp * 6.0);
	float n2 = vnoise(rp * 23.0);

	vec3 col;
	float rough = 0.85;
	if (region < 0.5) {
		col = skin_color.rgb;
		rough = 0.62;
	} else if (region < 1.5) {
		col = top_color.rgb;
	} else if (region < 2.5) {
		col = bottom_color.rgb;
		rough = 0.9;
	} else if (region < 3.5) {
		col = boot_color.rgb;
		rough = 0.7;
	} else {
		col = mix(skin_color.rgb, top_color.rgb, sleeves);
	}
	// fabric / skin variation
	col *= mix(0.85, 1.08, n1) * mix(0.94, 1.04, n2);
	// dirt rises from the boots
	float low = smoothstep(0.55, 0.0, COLOR.g);
	col = mix(col, vec3(0.16, 0.13, 0.1), clamp(grime * (low * 0.8 + n1 * 0.3), 0.0, 0.8));

	// decay: torn cloth reveals sickly skin, dark stains
	if (decay > 0.0) {
		float torn = smoothstep(0.62, 0.7, vnoise(rp * 4.0 + 3.1)) * decay;
		if (region > 0.5 && region < 2.5) {
			col = mix(col, skin_color.rgb * 0.85, torn);
		}
		float stain = smoothstep(0.58, 0.75, vnoise(rp * 3.0 + 7.7)) * decay;
		col = mix(col, vec3(0.16, 0.05, 0.04), stain * 0.75);
		if (region < 0.5) {
			// veins / bruising on exposed skin
			col *= 1.0 - smoothstep(0.55, 0.8, n2) * 0.25 * decay;
			// sunken eye shadow on the face side of the head
			float face = smoothstep(0.86, 0.9, COLOR.g) * (1.0 - smoothstep(0.92, 0.95, COLOR.g)) * step(0.52, COLOR.a);
			col *= 1.0 - face * 0.6 * decay;
		}
		rough = mix(rough, 0.55, stain);
	}
	col = mix(col, vec3(1.0, 0.92, 0.85), hit_flash);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	// gentle rim to separate silhouettes from dark backgrounds
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * rim * 0.12;
}
