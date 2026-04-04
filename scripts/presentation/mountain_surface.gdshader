shader_type spatial;

render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_disabled;

uniform sampler2D light_ramp;
uniform vec4 base_color : source_color = vec4(0.88, 0.89, 0.91, 1.0);
uniform vec4 ridge_color : source_color = vec4(0.98, 0.98, 0.99, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.55, 0.57, 0.61, 1.0);
uniform vec4 talus_color : source_color = vec4(0.71, 0.72, 0.75, 1.0);
uniform vec4 crack_color : source_color = vec4(0.45, 0.47, 0.51, 1.0);
uniform vec3 light_direction = vec3(-0.58, 0.78, -0.22);
uniform float large_noise_scale : hint_range(0.01, 1.0) = 0.10;
uniform float large_noise_strength : hint_range(0.0, 0.2) = 0.04;
uniform float crack_scale : hint_range(0.05, 2.0) = 0.28;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.30;

varying vec3 local_position;
varying vec4 vertex_mask;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - (2.0 * f));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	local_position = VERTEX;
	vertex_mask = COLOR;
}

void fragment() {
	vec3 normal_dir = normalize(NORMAL);
	vec3 light_dir = normalize(light_direction);
	float slope = clamp(1.0 - normal_dir.y, 0.0, 1.0);

	float cap_mask = clamp(vertex_mask.r, 0.0, 1.0);
	float cliff_mask = clamp(vertex_mask.g, 0.0, 1.0);
	float foot_mask = clamp(vertex_mask.b, 0.0, 1.0);
	float ridge_mask = clamp(vertex_mask.a, 0.0, 1.0);
	float ledge_mask = clamp((1.0 - cap_mask) * (1.0 - cliff_mask * 0.55) * (0.35 + ridge_mask * 0.45), 0.0, 1.0);

	float lambert = clamp(dot(normal_dir, light_dir), 0.0, 1.0);
	float shade_bias = (cap_mask * 0.14) - (cliff_mask * 0.18) - (slope * 0.08);
	float stepped = texture(light_ramp, vec2(clamp(lambert + shade_bias, 0.0, 1.0), 0.5)).r;

	float broad_noise = (noise2d(local_position.xz * large_noise_scale) - 0.5) * large_noise_strength * (0.25 + cliff_mask * 0.75 + foot_mask * 0.30);
	float crack_noise = noise2d((local_position.xz * crack_scale) + vec2(17.0, 9.0));
	float crack_mask = smoothstep(0.70, 0.95, crack_noise) * crack_strength * (0.25 + cliff_mask * 0.75);

	vec3 cap_tone = mix(base_color.rgb, ridge_color.rgb, cap_mask * (0.72 + ridge_mask * 0.18));
	vec3 ledge_tone = mix(base_color.rgb, ridge_color.rgb, ledge_mask * 0.18);
	vec3 cliff_tone = mix(base_color.rgb, shadow_color.rgb, 0.52 + slope * 0.18);
	vec3 foot_tone = mix(base_color.rgb, talus_color.rgb, foot_mask * 0.88);
	vec3 color_mix = mix(ledge_tone, cap_tone, cap_mask);
	color_mix = mix(color_mix, foot_tone, foot_mask * 0.78);
	color_mix = mix(color_mix, cliff_tone, clamp(cliff_mask + slope * 0.22, 0.0, 1.0));
	color_mix += vec3(broad_noise);
	color_mix = mix(color_mix, crack_color.rgb, crack_mask);

	float face_shadow = clamp((slope * 0.62) + (cliff_mask * 0.40), 0.0, 1.0);
	vec3 lit = mix(mix(shadow_color.rgb, color_mix, 0.56), color_mix, stepped);
	lit = mix(lit, shadow_color.rgb, face_shadow * (1.0 - stepped) * 0.45);
	lit = mix(lit, ridge_color.rgb, cap_mask * 0.22 + ridge_mask * cap_mask * 0.20);
	lit = mix(lit, talus_color.rgb, foot_mask * 0.14);

	ALBEDO = clamp(lit, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.02;
}
