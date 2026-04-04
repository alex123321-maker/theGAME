shader_type spatial;

render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_disabled;

uniform sampler2D light_ramp;
uniform sampler2D detail_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_roughness_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.88, 0.89, 0.91, 1.0);
uniform vec4 ridge_color : source_color = vec4(0.98, 0.98, 0.99, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.55, 0.57, 0.61, 1.0);
uniform vec4 talus_color : source_color = vec4(0.71, 0.72, 0.75, 1.0);
uniform vec4 crack_color : source_color = vec4(0.45, 0.47, 0.51, 1.0);
uniform vec3 light_direction = vec3(-0.58, 0.78, -0.22);
uniform float triplanar_blend_sharpness : hint_range(1.0, 12.0) = 6.0;
uniform float detail_uv_scale : hint_range(0.02, 1.5) = 0.045;
uniform float detail_albedo_strength : hint_range(0.0, 1.0) = 0.06;
uniform float detail_cavity_strength : hint_range(0.0, 1.0) = 0.03;
uniform float detail_micro_shadow_strength : hint_range(0.0, 1.0) = 0.02;
uniform float detail_roughness_strength : hint_range(0.0, 1.0) = 0.08;
uniform float large_noise_scale : hint_range(0.01, 1.0) = 0.10;
uniform float large_noise_strength : hint_range(0.0, 0.2) = 0.02;
uniform float crack_scale : hint_range(0.05, 2.0) = 0.28;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.16;

varying vec3 local_position;
varying vec3 world_position;
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

vec3 triplanar_weights(vec3 n) {
	vec3 blend = pow(abs(n), vec3(triplanar_blend_sharpness));
	return blend / max(blend.x + blend.y + blend.z, 0.0001);
}

vec3 triplanar_color(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = triplanar_weights(n);
	vec2 uv_x = p.zy * detail_uv_scale;
	vec2 uv_y = p.xz * detail_uv_scale;
	vec2 uv_z = p.xy * detail_uv_scale;
	vec3 sx = texture(tex, uv_x).rgb;
	vec3 sy = texture(tex, uv_y).rgb;
	vec3 sz = texture(tex, uv_z).rgb;
	return (sx * w.x) + (sy * w.y) + (sz * w.z);
}

float triplanar_gray(sampler2D tex, vec3 p, vec3 n, float scale_mul) {
	vec3 w = triplanar_weights(n);
	vec2 uv_x = p.zy * detail_uv_scale * scale_mul;
	vec2 uv_y = p.xz * detail_uv_scale * scale_mul;
	vec2 uv_z = p.xy * detail_uv_scale * scale_mul;
	float sx = dot(texture(tex, uv_x).rgb, vec3(0.3333));
	float sy = dot(texture(tex, uv_y).rgb, vec3(0.3333));
	float sz = dot(texture(tex, uv_z).rgb, vec3(0.3333));
	return (sx * w.x) + (sy * w.y) + (sz * w.z);
}

void vertex() {
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_mask = COLOR;
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 light_dir = normalize(light_direction);

	// 1. Изолируем верхние грани (плато) от вертикальных скал по данным меша, а не по сглаженной нормали
	float cap_mask = clamp(vertex_mask.r, 0.0, 1.0);
	float cliff_data = clamp(vertex_mask.g, 0.0, 1.0);
	float is_top = smoothstep(0.55, 0.85, cap_mask) * (1.0 - smoothstep(0.25, 0.55, cliff_data));

	// 2. Глубина (Fake Ambient Occlusion) - у подножия горы темнее, макушки светлее
	float height_ao = smoothstep(-1.0, 8.0, local_position.y);

	// 3. Органичный шум-фактура (Painted Clay / Stylized Rock)
	vec2 noise_uv = world_position.xz * 0.8 + local_position.y * vec2(0.4, 0.7);
	float n = noise2d(noise_uv * large_noise_scale);
	float texture_breakup = (n - 0.5) * (0.12 + large_noise_strength);

	// 4. Раскраска Плато (Сверху - крышка горы)
	vec3 plateau_color = mix(base_color.rgb, ridge_color.rgb, clamp(vertex_mask.r + 0.2, 0.0, 1.0));
	plateau_color += texture_breakup * 0.5;

	// 5. Раскраска Скал (Сбоку) - уберем мелкие полоски (они выглядят как глитч)
	vec3 rock_color = talus_color.rgb * 0.95; // Более мягкий цвет скал (серый скалистый)
	rock_color += texture_breakup * 0.4;

	// Смешиваем верх и бока
	vec3 albedo = mix(rock_color, plateau_color, is_top);
	float cliff_weight = 1.0 - is_top;

	// 6. Трипланарная детализация без швов (цвет + roughness + микрорельеф)
	vec3 detail_color = triplanar_color(detail_albedo_tex, world_position, world_normal);
	float detail_gray = dot(detail_color, vec3(0.3333));
	detail_color = mix(vec3(detail_gray), detail_color, 0.35);
	detail_color = mix(vec3(0.58), detail_color, 0.42);
	float detail_luma = dot(detail_color, vec3(0.299, 0.587, 0.114));
	float detail_rough = triplanar_gray(detail_roughness_tex, world_position, world_normal, 1.0);
	float detail_normal = triplanar_gray(detail_normal_tex, world_position + vec3(13.7, 5.3, 17.1), world_normal, 1.15);

	float detail_cap_mask = smoothstep(0.35, 0.85, is_top);
	float detail_mix = detail_albedo_strength * detail_cap_mask;
	vec3 detail_tint = mix(vec3(1.0), detail_color, detail_mix);
	vec3 textured_albedo = albedo * detail_tint;

	float cavity = pow(clamp(1.0 - detail_luma, 0.0, 1.0), 1.35) * detail_cavity_strength * detail_cap_mask;
	float micro_shadow = abs(detail_normal - 0.5) * 2.0 * detail_micro_shadow_strength * detail_cap_mask;
	float crack_noise = noise2d((world_position.xz * crack_scale) + vec2(17.0, 9.0));
	float crack_mask = smoothstep(0.72, 0.96, crack_noise + (cavity * 0.35)) * crack_strength * (0.25 + cliff_weight * 0.75);
	textured_albedo = mix(textured_albedo, textured_albedo * crack_color.rgb, crack_mask * 0.38);

	// 7. Освещение (диорамное, но более материальное)
	float NdotL = dot(world_normal, light_dir);
	float ramp_light = texture(light_ramp, vec2(clamp((NdotL * 0.5) + 0.5, 0.0, 1.0), 0.5)).r;
	float soft_light = smoothstep(-0.08, 0.18, NdotL);
	float light_mask = mix(soft_light, ramp_light, 0.55);
	float cliff_light_dampen = mix(1.0, 0.90, cliff_weight);
	light_mask *= cliff_light_dampen;

	// Свет и тень: сохраняем цвет поверхности даже в глубокой тени
	vec3 shadow_tint = textured_albedo * shadow_color.rgb * (1.0 + cliff_weight * 0.04);
	vec3 lit_color = mix(shadow_tint, textured_albedo, light_mask);

	// Запекаем AO (низ горы уходит в тень), но не убиваем читаемость
	lit_color = mix(shadow_tint * 0.86, lit_color, height_ao * 0.84 + 0.16);

	// Локальные микротени от детализации
	float detail_occlusion = clamp(cavity + (micro_shadow * (0.30 + cliff_weight * 0.30)), 0.0, 0.28);
	lit_color *= 1.0 - detail_occlusion;

	// 8. Подсветка граней (Edge Wear & Bounce Light)
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fresnel = 1.0 - clamp(dot(view_dir, world_normal), 0.0, 1.0);
	
	// Подсветка ребер плато на свету
	float edge_wear = smoothstep(0.6, 0.9, fresnel) * is_top * light_mask;
	lit_color += ridge_color.rgb * edge_wear * 0.22;
	
	// Легкая «пыль» по верхам для диорамности
	float top_dust = is_top * smoothstep(0.58, 1.0, detail_luma);
	lit_color += ridge_color.rgb * (top_dust * 0.015);
	
	// Легкий "Bounce Light" для теневой стороны скал, чтобы они не сливались в плоское черное пятно
	float bounce_light = smoothstep(0.0, 1.0, -NdotL) * smoothstep(0.5, 0.8, fresnel);
	lit_color += shadow_color.rgb * bounce_light * 0.20 * (1.0 - is_top);

	ALBEDO = clamp(lit_color, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.80 + (detail_rough * detail_roughness_strength) + (cavity * 0.12), 0.70, 1.0);
	SPECULAR = 0.0;
}
